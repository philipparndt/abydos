import AppKit
import CryptoKit
import QuickLookUI
import GoSTL
import AbydosKit
import SwiftUI

/// Hosts the open files: a tab strip on top, the active file's text below, and a
/// status line showing position and language.
///
/// Each tab owns its own `CodeView` and scroll view rather than sharing one and
/// swapping documents. Caret, selection, scroll offset and collapsed folds then
/// survive tab switches for free, which is the behaviour you actually want and
/// is far harder to get right by saving and restoring state by hand.
final class EditorViewController: NSViewController {

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// Raised while an outer open reports the jump itself, with the line it
	/// asked for rather than the one the file happened to open at.
	var isReportingSuppressed = 0
	/// The repository moved under every open file at once. Debounced, so a
	/// checkout touching a hundred files is one sweep over the open tabs —
	/// the only files anybody can see — rather than a diff per event.
	var marksRefresh: DispatchWorkItem?

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// What the selected launch configuration has to say, when the file has
	/// nothing.
	///
	/// Second, not first: the strip sits above the code, and a sentence about the
	/// file somebody is reading outranks one about a configuration they have not
	/// pressed yet. Both at once is the case this ordering settles — a Java file
	/// with no server, in a project whose launch cannot be debugged either, is
	/// one problem with one cause, and the file's version of it is the one that
	/// names the language.
	var launchNotice: LanguageService.ServerNotice?

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// Asked for the whole window, by a double-click on a tab that is already
	/// permanent. The window owns the panes, so it owns the answer.
	var onMaximize: (() -> Void)?
	/// Told where the editor went, and where it stood before.
	var onNavigated: ((NavigationHistory.Place?, NavigationHistory.Place) -> Void)?
	/// Stage or unstage the lines selected in a diff tab.
	var onApplyDiffSelection: ((GitChange, String, Set<Int>) -> Void)?
	var onDiscardDiffSelection: ((GitChange, String, Set<Int>) -> Void)?
	/// Nil where stashing a hunk is not possible — an old git — so the menu
	/// item is absent rather than failing when pressed.
	var onStashDiffSelection: ((GitChange, String, Set<Int>) -> Void)?

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// Where a decrypted buffer goes when a switch closes its tab, and where
	/// it comes back from. Set by the window, which holds the park.
	var parkDecrypted: ((URL, DecryptedBuffer) -> Void)?
	var takeParkedDecrypted: ((URL) -> DecryptedBuffer?)?
	/// *Blame* on a tab: the window opens the file pinned and turns the
	/// column on, the same path the tree's row takes.
	var onBlameRequested: ((URL) -> Void)?
	/// The bar should ask for a passphrase: the field's placeholder, gpg's
	/// sentence for its tooltip, and what to do with the answer — nil when
	/// the field was dismissed.
	var onPassphraseNeeded: ((String, String, @escaping (String?) -> Void) -> Void)?
	/// The driver's way of answering the field, set by the area while asking.
	var passphraseAnswerForTesting: ((String?) -> Void)?
	var passphraseAskForTesting: String?
	/// The prose of the completion that was last taken, for as long as its stops
	/// are being stepped through.
	///
	/// Kept because it is the only thing that knows what the parameters are for
	/// a server with no signature help. openscad-lsp advertises none, and the
	/// 1530 characters it sends with `cube` are where "a single value, or a
	/// three-value array" is written down.
	var takenDocumentation: String?
	/// Asked for the children of a container, by the reference the adapter gave.
	///
	/// Set by whoever holds the debug session. Nil while nothing is stopped, in
	/// which case there is nothing to open and no hint to open it from.
	var onVariableChildren: ((Int) async -> [Variable])?
	/// The one that is open, so a second click replaces it rather than stacking,
	/// and so that resuming can take it away.
	var openValuePopup: VariableTreePopup?

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// A blame entry was clicked, with the file it is in; the window opens
	/// the log page at that commit.
	var onRevealCommit: ((GitBlame.Line, URL) -> Void)?

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	var previewRefreshWork: DispatchWorkItem?
	var project: Project?

	/// One open file.
	///
	/// A tab is not necessarily text: a binary or oversized file gets a notice
	/// tab, which can swap itself for a hex dump in place. Modelling that as tab
	/// content rather than an alert is what keeps the app free of blocking
	/// dialogs.
	@MainActor
	final class Tab {
		let url: URL
		/// nil for anything not opened as text.
		var document: TextDocument?
		var codeView: CodeView?
		/// Which change-marks read is current, so a diff that arrives after
		/// the tab moved on — a newer save, a close — is dropped rather than
		/// applied. `anchoringWork`'s shape.
		var changedLinesGeneration = 0
		/// The view installed in the content area.
		var contentView: NSView
		/// Provisional tabs are replaced by the next preview open instead of
		/// accumulating. Exactly one may exist at a time.
		var isPreview: Bool

		/// The root the language server answering about this file is filed under.
		///
		/// **A property of the file, not of the scope pill.** Worked out once,
		/// when the file is opened, and carried — because every later question
		/// has to reach the same server the `didOpen` went to. A file opened
		/// under one root and asked about under another reaches a server that
		/// has never heard of it, which answers nothing and is indistinguishable
		/// from the fault this exists to fix.
		///
		/// Nil until the document has a language, since which markers to climb
		/// for is a fact about the language.
		var serverRoot: URL?

		/// What find is doing in this tab.
		///
		/// **On the tab because the offsets are.** `searchMatches` and
		/// `currentMatchIndex` lived on the controller, which holds every tab —
		/// so switching tabs with the bar open left one file's UTF-16 offsets
		/// pointed at another file's view, and `setSearchMatches` then set a
		/// caret from a range that document never produced.
		///
		/// It is also what the rest of this class already does, and says it
		/// does: each tab owns its own `CodeView`, so caret, selection, scroll
		/// offset and folds survive a switch because they were never shared.
		/// Find was the exception.
		var find = FindState()

		/// Whether find is showing in this tab, what is being looked for, and
		/// what was found.
		///
		/// One `FindBar` view still serves the whole group — this is what it
		/// shows, not another bar.
		struct FindState {
			var isShowing = false
			var query = ""
			var options = SearchOptions()
			/// What the matches should become, and whether the bar is asking.
			/// Kept here so a tab comes back to the bar it was left with, the
			/// way its query already does.
			var replacement = ""
			var isReplacing = false
			/// UTF-16 offsets into *this* tab's document, and nowhere else.
			var matches: [SearchMatch] = []
			var current: Int?
		}

		/// A page is not a file: the launch configurations, and whatever else
		/// the app puts in a tab of its own. It is named by this rather than by
		/// its URL, which exists only so a tab can be told apart.
		var pageTitle: String?
		/// What it is marked with in the tab bar.
		var pageSymbol: String?
		/// The line under a page's name: what a compare page counts.
		var pageSubtitle: String?

		/// A diff tab shows a comparison rather than the file, so it is a
		/// separate tab from the file itself and says so in its subtitle.
		var isDiff = false
		/// Which commit this diff is of, when it came from the history.
		var diffCommit: String?

		/// The source view, kept so the preview can be swapped in beside or over
		/// it and swapped back.
		var sourceView: NSView?
		/// How this tab is currently showing a file that has both forms.
		var previewMode: PreviewMode = .source
		/// Whether this file is a go3mf recipe — a `.yaml` the 3D viewer can build
		/// and show — which its name cannot say.
		///
		/// **Decided once, when the tab opens, and kept.** The tab bar asks what
		/// modes a file has on every refresh, and a refresh follows a keystroke; a
		/// question that reads the file could not live there. So the one bounded read
		/// happens where the file is being opened anyway, and everything afterwards
		/// asks the tab.
		///
		/// The cost of keeping it: a `.yaml` that *becomes* a recipe while it is open
		/// is still text until it is reopened. That is the right way round — the
		/// alternative re-reads a file on every redraw to catch an edit somebody
		/// makes once — and closing and reopening the tab settles it.
		var looksLikeRecipe = false
		/// A file SOPS encrypted, looked at once when the tab was opened.
		var isSopsFile = false
		/// The buffer holds the plaintext `sops` gave back. From then on it is
		/// never auto-saved, never sent to a language server, never reloaded
		/// from disk, and ⌘S encrypts it rather than writing it.
		var isDecrypted = false
		/// The plaintext exactly as `sops` gave it back, set by the decrypt
		/// and read by the save — the one comparison that can tell an
		/// unchanged buffer from an edited one, which `isDirty` cannot: undo
		/// marks a buffer dirty on the way back to the decrypt's own text,
		/// and `sops --encrypt` is randomised, so encrypting that buffer
		/// would give the file a new version of the same text. Text and not a
		/// digest because the rope and the undo tree already hold the whole
		/// of it, and a hash would cost a save-time computation to save
		/// kilobytes. Cleared by the lock, like everything else about a
		/// decrypted buffer.
		var decryptedBaseline: String?
		/// A plaintext file the project's `.sops.yaml` has a creation rule for,
		/// looked at once when the tab was opened — which is what turns the
		/// chip into an offer to encrypt rather than nothing at all.
		var sopsOffer = false
		/// What git can see of a file whose values are covered: nothing for one
		/// git ignores, and for the other two a sentence somebody can act on.
		/// Asked when the tab opens and again when the file is reloaded or the
		/// project's git state is refreshed — the two acts that change it.
		var exposure = SecretExposure.State.fine
		/// The Cadova model this file is a source of, when it is one — which its
		/// name cannot say either, and for a harder reason than a recipe's: what
		/// makes a `.swift` a model is the *package manifest*, two or three
		/// directories above it.
		///
		/// **Decided once, when the tab opens, and kept**, for the reason above.
		/// It carries the answer as well as the fact — which product to run and
		/// where that target's sources are is exactly what the pane needs, and
		/// working it out a second time would mean reading the manifest again.
		///
		/// The cost of keeping it is `looksLikeRecipe`'s, one size larger: a
		/// package that *gains* a Cadova dependency while a file of it is open
		/// stays text until the tab is reopened.
		var cadova: CadovaModel?
		/// The two things about this file that its name could not say.
		var previewFacts: PreviewFacts {
			PreviewFacts(
				looksLikeRecipe: looksLikeRecipe, isCadovaModel: cadova != nil,
				isSopsEncrypted: isSopsFile
			)
		}
		/// Where this tab's divider is, when it is split, as a fraction of the
		/// pane. Asked of the split view itself rather than kept in step with it:
		/// a divider is dragged, and nothing tells us when.
		var dividerFraction: Double? {
			(contentView as? PreviewSplitView)?.currentFraction.map { Double($0) }
		}
		var isMarkdown: Bool { document?.languageId == "markdown" }
		var isShowingMarkdownPreview: Bool { previewMode != .source && isMarkdown }

		init(url: URL, document: TextDocument?, codeView: CodeView?, contentView: NSView, isPreview: Bool) {
			self.url = url
			self.document = document
			self.codeView = codeView
			self.contentView = contentView
			self.isPreview = isPreview
		}

		/// Where the file came from when it is an entry inside an archive,
		/// opened from the cache: the tab says so and never writes.
		var archiveOrigin: ArchiveOrigin?
		/// The file as bytes, when the tab is a hex editor; its controller
		/// owns the view and every task behind it. A tab has one of
		/// `document` and `hex`, never both.
		var hex: HexEditorController?

		var isDirty: Bool {
			if let hex { return hex.isDirty }
			return document?.isDirty ?? false
		}
	}

	var tabs: [Tab] = []
	var activeIndex: Int?

	var findBar: FindBar!
	var findBarHeight: NSLayoutConstraint!

	var serverBanner: LanguageServerBanner!
	var serverBannerHeight: NSLayoutConstraint!
	/// Languages whose banner was waved away for now. Not written down: "not
	/// now" means this window, this session — the answer to being asked again
	/// tomorrow is the Ignore button, which is written down.
	var dismissedSuggestions: Set<String> = []
	/// Matches in the active document, and the one currently selected.
	var findDebounce: DispatchWorkItem?
	var languageSyncWork: DispatchWorkItem?
	/// The list of completions, shared by every tab in this group: only one can
	/// be typing at a time.
	let completions = CompletionPopup()
	var completionWork: DispatchWorkItem?
	/// What the parameter under the caret takes, said above the line. Shared by
	/// every tab for the same reason the list is.
	let parameterHint = ParameterHintStrip()
	var signatureWork: DispatchWorkItem?
	/// How much of the word the visible list was built for, so committing one
	/// replaces exactly what was typed.
	var completionPrefixLength = 0
	/// The list of states this file has been in.
	let historyPopup = HistoryPopup()

	var tabBar: EditorTabBar!
	var tabBarTopConstraint: NSLayoutConstraint!
	var tabBarHeightConstraint: NSLayoutConstraint!
	var contentArea: NSView!
	/// Position and language of this group's active tab.
	///
	/// The window shows one status bar for the whole editor area, not one per
	/// pane, so a group reports its state and the area controller displays
	/// whichever group is active.
	internal(set) var statusLine = 1
	internal(set) var statusColumn = 1
	internal(set) var statusLanguage: String?
	/// The server answering for the active tab, or nil when there is none to
	/// name.
	///
	/// **Held rather than asked for.** The status bar is redrawn every time the
	/// caret moves, and this is worked out only when the server's state changes
	/// — the same moments the strip above the file is refreshed from, which
	/// includes `.ideaiLanguageServersChanged`. Reading it from `draw` would put
	/// the project's choices on the path of the arrow keys, which is the fault
	/// 0443 built a card's own struct to avoid and 0458 had to make
	/// `Backlog.item(number:)` cheap for.
	internal(set) var statusServer: LanguageServerFooter?
	var onStatusChanged: ((EditorViewController) -> Void)?
	var placeholder: NSTextField!
	/// The one thing an empty window can offer to do.
	var scratchButton: NSButton!

	/// Notifies the window when the active file changes, so the tree can follow.
	var onActiveFileChanged: ((URL?) -> Void)?

	/// Called when the breakpoint gutter is clicked, with a 1-based line.
	var onToggleBreakpoint: ((URL, Int) -> Void)?
	/// Right-clicked a breakpoint: edit what it does. 1-based line.
	var onEditBreakpoint: ((URL, Int) -> Void)?
	/// Clicked a marker, or chose enable/disable from its menu. 1-based line.
	var onSetBreakpointEnabled: ((URL, Int, Bool) -> Void)?
	/// Dragged a marker out of the gutter, or chose Delete. 1-based line.
	var onDeleteBreakpoint: ((URL, Int) -> Void)?
	/// Chose to disable — or enable — every breakpoint but this one.
	var onSetOtherBreakpointsEnabled: ((URL, Int, Bool) -> Void)?
	/// Lines were added or taken out of a file, so anything anchored to them
	/// has to move. First line 0-based.
	var onLinesChanged: ((URL, Int, Int, Int) -> Void)?
	/// A file was re-read after something else wrote it. No edits were reported
	/// for it — the text is simply different now — so whatever was anchored to
	/// the old text has to find itself again.
	var onFileReloaded: ((URL) -> Void)?
	/// Asked for everywhere a symbol is used, at a zero-based position.
	var onFindUsages: ((URL, Int, Int) -> Void)?
	var onRename: ((URL, Int, Int) -> Void)?
	/// Watch what is selected, while something is being debugged.
	var onWatch: ((String) -> Void)?
	/// Asked to put an agent on a problem: the file, the line, and what the
	/// language server said about it.
	var onFixWithAI: ((URL, Int, LSPDiagnostic) -> Void)?
	/// Copy a link to a place in this tab's file. The window answers it: a
	/// reference needs the project root, a permalink needs git.
	var onCopyLink: ((URL, CodeView.LinkForm, Int, Int?) -> Void)?
	/// Which lines have a breakpoint that does more than stop, per file.
	private var conditionalBreakpoints: [String: Set<Int>] = [:]

	func setConditionalBreakpoints(_ lines: [String: Set<Int>]) {
		conditionalBreakpoints = lines
		for tab in tabs { applyConditionalBreakpoints(to: tab) }
	}

	func applyConditionalBreakpoints(to tab: Tab) {
		let path = FilePath.canonical(tab.url)
		// The gutter counts from zero and everything else from one.
		let lines = Set((conditionalBreakpoints[path] ?? []).map { $0 - 1 })
		tab.codeView?.setConditionalBreakpoints(lines)
	}
	/// The gutter's play button was clicked, with a 1-based line.
	var onRunLine: ((URL, Int) -> Void)?

	/// Identifies this group when a tab is dragged between panes.
	let groupID = UUID()

	/// Told when files are dropped on this group.
	///
	/// Handed up rather than opened here: a file needs the panel making room and
	/// the tree told, and a folder is a project — none of which is a group's
	/// business. `MainWindowController` already does all three for a file opened
	/// from a terminal.
	var onFilesDropped: (([URL]) -> Void)?

	/// Asked to move a dragged tab here, in the given zone.
	var onTabDropped: ((_ payload: EditorTabDrag.Payload, _ zone: EditorTabDrag.Zone, _ target: EditorViewController) -> Void)?
	/// A tab dropped on this group's strip, to land at the given slot.
	var onTabDroppedOnTabBar: ((_ payload: EditorTabDrag.Payload, _ index: Int, _ target: EditorViewController) -> Void)?
	/// Fired when this group has no tabs left, so the area can collapse it.
	var onBecameEmpty: ((EditorViewController) -> Void)?
	/// A tab was dragged clear of every window; the index and where it landed.
	var onTearOffTab: ((EditorViewController, Int, NSPoint) -> Void)?
	/// Fired when this group takes focus, so the area knows which is active.
	var onActivated: ((EditorViewController) -> Void)?
	/// Fired whenever the set of open tabs changes.
	var onTabsChanged: (() -> Void)?

	var isEmpty: Bool { tabs.isEmpty }
	var tabCount: Int { tabs.count }
	var activeTabIndex: Int? { activeIndex }
	var activeTabURL: URL? { activeTab?.url }

	/// The editor a driven run is allowed to put keystrokes into.
	///
	/// Every verb below that *changes* a file asks for the view this way rather
	/// than reaching for `activeTab?.codeView`, and this is why: on the evening
	/// of item 0522 a typing verb landed in a tab the window had restored from
	/// somebody's own session and left `C-ircle(diameter: diameter)` in a source
	/// file nobody was editing, which then failed to compile for everybody.
	///
	/// A driven run does not restore a session any more, so in practice there is
	/// nothing in front that the run did not open. This is the check that says
	/// so out loud instead of relying on it: a file the run did not name is
	/// refused, on standard error, by name — and a refusal that prints is a
	/// finding, where a keystroke that lands in the wrong file is a mystery
	/// three items were filed about.
	///
	/// Nothing here restricts a person. `mayType(into:)` is true for every run
	/// that was not given a launch verb at all.
	func codeViewToDrive(_ verb: String) -> CodeView? {
		guard let tab = activeTab, let codeView = tab.codeView else { return nil }
		guard LaunchOptions.parse().mayType(into: tab.url) else {
			let refusal = "\(verb): refused — this run was not given \(tab.url.path),"
				+ " so it does not type into it\n"
			FileHandle.standardError.write(Data(refusal.utf8))
			return nil
		}
		return codeView
	}

	/// Which of source, preview or a split the file in front is being shown in.
	var currentPreviewMode: PreviewMode { activeTab?.previewMode ?? .source }
	/// Which modes the file in front can be shown in, from the tab rather than from
	/// the name — a `.yaml` has a rendered form only when it is a go3mf recipe, and
	/// the tab is what knows.
	var activeTabPreviewModes: [PreviewMode] { activeTab.map { availableModes(for: $0) } ?? [] }
	var activeDocument: TextDocument? { activeTab?.document }
	/// The view the caret is in, for a gesture that has to be drawn where the
	/// text is rather than reported about.
	var activeCodeView: CodeView? { activeTab?.codeView }

	/// The open document for a file, if this group is the one holding it.
	func document(for url: URL) -> TextDocument? {
		let path = FilePath.canonical(url)
		return tabs.first { FilePath.canonical($0.url) == path }?.document
	}

	/// Puts new text into an open file, through the rope, and writes it.
	///
	/// The open half of applying a workspace edit. Written as well as changed,
	/// because a rename that left forty buffers dirty and the files as they were
	/// would be a refactoring nobody's compiler has heard of — and because the
	/// language server has to be told, or its next answer is about the file as
	/// it was.
	@discardableResult
	func applyRenamedText(_ text: String, to url: URL) -> Bool {
		let path = FilePath.canonical(url)
		guard let tab = tabs.first(where: { FilePath.canonical($0.url) == path }),
		      let document = tab.document
		else { return false }

		// Through the view when there is one, so the caret and the folds are put
		// back; through the document when the tab has never been shown.
		if let codeView = tab.codeView {
			guard codeView.replaceAllText(with: text) else { return false }
		} else {
			let length = document.rope.utf16Offset(fromByte: document.rope.byteCount)
			document.replace(utf16Range: 0..<length, with: text, caretBefore: 0)
		}
		try? document.save()
		refreshTabBar()

		guard let languageId = document.languageId, let root = serverRoot(for: tab) else { return true }
		LanguageService.shared.changed(
			url: tab.url, languageId: languageId, text: text, project: root
		)
		LanguageService.shared.saved(
			url: tab.url, languageId: languageId, text: text, project: root
		)
		return true
	}

	/// Closes the tab on a file a workspace edit has moved or taken away.
	///
	/// A tab whose file is no longer at that path is a tab that will write it
	/// back there on the next auto-save, which would undo half of what was just
	/// done. Closing it is the honest answer and it is what the caller then
	/// reopens under the new name.
	@discardableResult
	func closeTab(showing url: URL) -> Bool {
		let path = FilePath.canonical(url)
		guard let index = tabs.firstIndex(where: { FilePath.canonical($0.url) == path }) else {
			return false
		}
		// `removeTab` rather than `closeTab`: the file has already moved, so
		// there is nothing to offer to save and a prompt about discarding it
		// would be a question about a file that is not there.
		removeTab(at: index)
		return true
	}

	/// Breakpoints to draw, per absolute file path, with verification state.
	var breakpointsByFile: [String: [Int: CodeView.BreakpointMark]] = [:]
	var runnableLinesByFile: [String: Set<Int>] = [:]
	/// Where execution is currently stopped.
	var executionLocation: (file: String, line: Int)?
	/// The values of the frame execution is stopped in, and the file they
	/// belong to. Nil while nothing is stopped, which is when nothing is drawn.
	var inlineValues: InlineValueSet?
}
