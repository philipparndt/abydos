import AppKit
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
	private var project: Project?

	/// One open file.
	///
	/// A tab is not necessarily text: a binary or oversized file gets a notice
	/// tab, which can swap itself for a hex dump in place. Modelling that as tab
	/// content rather than an alert is what keeps the app free of blocking
	/// dialogs.
	final class Tab {
		let url: URL
		/// nil for anything not opened as text.
		var document: TextDocument?
		var codeView: CodeView?
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
			PreviewFacts(looksLikeRecipe: looksLikeRecipe, isCadovaModel: cadova != nil)
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

		var isDirty: Bool { document?.isDirty ?? false }
	}

	private var tabs: [Tab] = []
	private var activeIndex: Int?

	private var findBar: FindBar!
	private var findBarHeight: NSLayoutConstraint!

	private var serverBanner: LanguageServerBanner!
	private var serverBannerHeight: NSLayoutConstraint!
	/// Languages whose banner was waved away for now. Not written down: "not
	/// now" means this window, this session — the answer to being asked again
	/// tomorrow is the Ignore button, which is written down.
	private var dismissedSuggestions: Set<String> = []
	/// Matches in the active document, and the one currently selected.
	private var findDebounce: DispatchWorkItem?
	private var languageSyncWork: DispatchWorkItem?
	/// The list of completions, shared by every tab in this group: only one can
	/// be typing at a time.
	private let completions = CompletionPopup()
	private var completionWork: DispatchWorkItem?
	/// What the parameter under the caret takes, said above the line. Shared by
	/// every tab for the same reason the list is.
	private let parameterHint = ParameterHintStrip()
	private var signatureWork: DispatchWorkItem?
	/// How much of the word the visible list was built for, so committing one
	/// replaces exactly what was typed.
	private var completionPrefixLength = 0
	/// The list of states this file has been in.
	private let historyPopup = HistoryPopup()

	private var tabBar: EditorTabBar!
	private var tabBarTopConstraint: NSLayoutConstraint!
	private var tabBarHeightConstraint: NSLayoutConstraint!
	private var contentArea: NSView!
	/// Position and language of this group's active tab.
	///
	/// The window shows one status bar for the whole editor area, not one per
	/// pane, so a group reports its state and the area controller displays
	/// whichever group is active.
	private(set) var statusLine = 1
	private(set) var statusColumn = 1
	private(set) var statusLanguage: String?
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
	private(set) var statusServer: LanguageServerFooter?
	var onStatusChanged: ((EditorViewController) -> Void)?
	private var placeholder: NSTextField!
	/// The one thing an empty window can offer to do.
	private var scratchButton: NSButton!

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

	private func applyConditionalBreakpoints(to tab: Tab) {
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
	private var breakpointsByFile: [String: [Int: CodeView.BreakpointMark]] = [:]
	private var runnableLinesByFile: [String: Set<Int>] = [:]
	/// Where execution is currently stopped.
	private var executionLocation: (file: String, line: Int)?
	/// The values of the frame execution is stopped in, and the file they
	/// belong to. Nil while nothing is stopped, which is when nothing is drawn.
	private var inlineValues: InlineValueSet?

	// MARK: - View

	override func loadView() {
		let container = EditorDropView(color: Theme.current.editorBackground)

		tabBar = EditorTabBar()
		tabBar.onSelect = { [weak self] index in self?.activate(index: index, focusEditor: true) }
		tabBar.onClose = { [weak self] index in self?.closeTab(at: index) }
		tabBar.onCloseOthers = { [weak self] index in self?.closeTabs(keeping: index) }
		tabBar.onCloseLeft = { [weak self] index in self?.closeTabs(before: index) }
		tabBar.onCloseRight = { [weak self] index in self?.closeTabs(after: index) }
		tabBar.onCloseAll = { [weak self] in self?.closeAllTabs() }
		tabBar.onCopyPath = { [weak self] index in
			guard let url = self?.tabs[safe: index]?.url else { return }
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(url.path, forType: .string)
		}
		tabBar.onRevealInFinder = { [weak self] index in
			guard let url = self?.tabs[safe: index]?.url else { return }
			NSWorkspace.shared.activateFileViewerSelecting([url])
		}
		tabBar.onPromote = { [weak self] index in self?.promoteToPermanent(index: index) }
		tabBar.onMaximize = { [weak self] in self?.onMaximize?() }
		tabBar.onNewScratch = { [weak self] in self?.newScratch() }
		tabBar.onNewGlobalScratch = { [weak self] in self?.newScratch(global: true) }
		tabBar.groupID = groupID
		tabBar.onTearOff = { [weak self] index, screenPoint in
			guard let self else { return }
			onTearOffTab?(self, index, screenPoint)
		}
		tabBar.onPreviewModeChange = { [weak self] mode in
			self?.setPreviewMode(mode)
		}
		tabBar.onTabDropped = { [weak self] payload, index in
			guard let self else { return }
			self.onTabDroppedOnTabBar?(payload, index, self)
		}
		tabBar.urlForIndex = { [weak self] index in
			guard let self, self.tabs.indices.contains(index) else { return nil }
			return self.tabs[index].url
		}

		contentArea = NSView()

		findBar = FindBar()
		findBar.isHidden = true
		findBar.onQueryChanged = { [weak self] query, options in
			self?.scheduleFind(query: query, options: options)
		}
		findBar.onNext = { [weak self] in self?.stepMatch(by: 1) }
		findBar.onPrevious = { [weak self] in self?.stepMatch(by: -1) }
		findBar.onClose = { [weak self] in self?.closeFind() }
		findBar.onReplace = { [weak self] delta in self?.replaceCurrent(steppingBy: delta) }
		findBar.onReplaceAll = { [weak self] in self?.replaceAll() }
		// Kept on the tab as it is typed, so switching away and back brings it
		// with the query rather than losing it.
		findBar.onReplacementChanged = { [weak self] text in
			self?.activeTab?.find.replacement = text
		}

		serverBanner = LanguageServerBanner()
		serverBanner.isHidden = true
		serverBanner.onDetails = { [weak self] in self?.showServerManual() }
		serverBanner.onIgnore = { [weak self] in self?.ignoreServerSuggestion() }
		serverBanner.onDismiss = { [weak self] in self?.dismissServerSuggestion() }
		serverBanner.onOffer = { [weak self] in self?.takeServerOffer() }

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(diagnosticsChanged(_:)),
			name: .ideaiDiagnosticsChanged,
			object: nil
		)
		// The project's servers changed which machine they are on, so every file
		// open here has to be opened again at the one that answers for it now —
		// the same thing a subproject scope change does, for the same reason.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(languageServersMoved(_:)),
			name: .ideaiLanguageServersMoved,
			object: nil
		)
		// A server that starts, or is found to be missing, changes what the
		// banner should say — including making it go away.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(languageServersChanged),
			name: .ideaiLanguageServersChanged,
			object: nil
		)

		placeholder = NSTextField(labelWithString: "Select a file to open")
		placeholder.font = Theme.current.uiFont(13)
		placeholder.textColor = Theme.current.gitIgnored
		placeholder.alignment = .center

		// The other route to a scratch is double-clicking the tab strip, and an
		// empty window has no tab strip to double-click. Offered here so the
		// window is never a dead end.
		scratchButton = NSButton(title: "New Scratch File", target: self, action: #selector(newScratchFromPlaceholder))
		scratchButton.isBordered = false
		scratchButton.bezelStyle = .inline
		styleScratchButton()

		for subview in [tabBar, findBar, serverBanner, contentArea, placeholder, scratchButton] as [NSView] {
			container.addSubview(subview)
			subview.translatesAutoresizingMaskIntoConstraints = false
		}

		// Set from the window's actual titlebar height rather than hardcoded; the
		// titlebar is taller with a toolbar than without, and guessing clips the
		// tab bar.
		tabBarTopConstraint = tabBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 40)
		tabBarHeightConstraint = tabBar.heightAnchor.constraint(equalToConstant: EditorTabBar.height)
		// Collapsed to zero rather than hidden, so the editor reclaims the space.
		findBarHeight = findBar.heightAnchor.constraint(equalToConstant: 0)
		serverBannerHeight = serverBanner.heightAnchor.constraint(equalToConstant: 0)

		NSLayoutConstraint.activate([
			tabBarTopConstraint,
			tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			tabBarHeightConstraint,

			findBar.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
			findBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			findBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			findBarHeight,

			// Under the find bar, above the file: it is about the file, and it
			// must not push the thing somebody is searching around while they
			// search it.
			serverBanner.topAnchor.constraint(equalTo: findBar.bottomAnchor),
			serverBanner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			serverBanner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			serverBannerHeight,

			contentArea.topAnchor.constraint(equalTo: serverBanner.bottomAnchor),
			contentArea.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			contentArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			contentArea.bottomAnchor.constraint(equalTo: container.bottomAnchor),

			placeholder.centerXAnchor.constraint(equalTo: container.centerXAnchor),
			placeholder.centerYAnchor.constraint(equalTo: container.centerYAnchor),

			scratchButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
			scratchButton.topAnchor.constraint(equalTo: placeholder.bottomAnchor, constant: 10),
		])

		view = container
		// The whole group is a drop target, so a tab can be dropped over the text
		// as well as over the strip.
		container.registerForDraggedTypes([EditorTabDrag.pasteboardType])
		container.owner = self
		updateChrome()
	}

	// MARK: - Moving tabs between groups

	/// Removes a tab without tearing it down, so it can be re-homed intact.
	func detachTab(at index: Int) -> Tab? {
		guard tabs.indices.contains(index) else { return nil }
		let tab = tabs.remove(at: index)
		tab.contentView.removeFromSuperview()

		if tabs.isEmpty {
			activeIndex = nil
			contentArea.subviews.forEach { $0.removeFromSuperview() }
			updateChrome()
			refreshTabBar()
			onBecameEmpty?(self)
		} else {
			activeIndex = nil
			activate(index: min(index, tabs.count - 1), focusEditor: false)
		}
		return tab
	}

	/// Takes ownership of a tab detached from another group.
	func adopt(_ tab: Tab, at index: Int? = nil, focus: Bool = true) {
		// Its callbacks still point at the old group, so they are re-bound.
		rebindCallbacks(for: tab)
		let slot = max(0, min(index ?? tabs.count, tabs.count))
		tabs.insert(tab, at: slot)
		activeIndex = nil
		activate(index: slot, focusEditor: focus)
		applyDebugState(to: tab)
	}

	private func rebindCallbacks(for tab: Tab) {
		tab.codeView?.onCaretMoved = { [weak self, weak tab] line, column in
			guard let self, let tab, self.activeTab === tab else { return }
			self.setStatus(line: line, column: column)
		}
		tab.codeView?.onDirtyChanged = { [weak self, weak tab] _ in
			tab?.isPreview = false
			self?.refreshTabBar()
		}
		tab.codeView?.onSetBreakpointEnabled = { [weak self, weak tab] line, enabled in
			guard let tab else { return }
			self?.onSetBreakpointEnabled?(tab.url, line + 1, enabled)
		}
		tab.codeView?.onDeleteBreakpoint = { [weak self, weak tab] line in
			guard let tab else { return }
			self?.onDeleteBreakpoint?(tab.url, line + 1)
		}
		tab.codeView?.onLinesChanged = { [weak self, weak tab] first, removed, inserted in
			guard let tab else { return }
			self?.onLinesChanged?(tab.url, first, removed, inserted)
		}
		tab.codeView?.onTextReplaced = { [weak self, weak tab] range, inserted in
			guard let tab else { return }
			self?.textReplaced(in: tab, replacing: range, insertedLength: inserted)
		}
		tab.codeView?.onSetOtherBreakpointsEnabled = { [weak self, weak tab] line, enabled in
			guard let tab else { return }
			self?.onSetOtherBreakpointsEnabled?(tab.url, line + 1, enabled)
		}
		tab.codeView?.onToggleBreakpoint = { [weak self, weak tab] line in
			guard let tab else { return }
			self?.onToggleBreakpoint?(tab.url, line + 1)
		}
		tab.codeView?.onRunLine = { [weak self, weak tab] line in
			guard let tab else { return }
			self?.onRunLine?(tab.url, line)
		}
		tab.document?.onAutoSaved = { [weak self] in
			self?.refreshTabBar()
		}
	}

	/// Index of a tab by identity, for a drag that started here.
	func indexOfTab(withPath path: String) -> Int? {
		tabs.firstIndex { $0.url.path == path }
	}

	/// Shows a unified diff for a path, reusing the tab if it is already open.
	///
	/// A tab of its own rather than an overlay on the file: the diff and the
	/// file are different things to look at, and staging usually means moving
	/// between several of them.
	/// Selects a hunk in the visible diff, so the harness can capture the
	/// selection styling without a click.
	func selectDiffHunkForTesting(_ hunk: Int) {
		guard let tab = activeTab, tab.isDiff else { return }
		((tab.contentView as? NSScrollView)?.documentView as? DiffView)?.selectHunk(hunk)
	}

	/// Stage or unstage the lines selected in a diff tab.
	var onApplyDiffSelection: ((GitChange, String, Set<Int>) -> Void)?
	var onDiscardDiffSelection: ((GitChange, String, Set<Int>) -> Void)?
	/// Nil where stashing a hunk is not possible — an old git — so the menu
	/// item is absent rather than failing when pressed.
	var onStashDiffSelection: ((GitChange, String, Set<Int>) -> Void)?

	func openDiff(for change: GitChange, root: URL, text: String) {
		let url = root.appendingPathComponent(change.path)

		if let index = tabs.firstIndex(where: { $0.isDiff && $0.url.path == url.path }) {
			let existing = (tabs[index].contentView as? NSScrollView)?.documentView as? DiffView
			existing?.setDiff(text, staged: change.isStaged, url: url)
			existing?.onApplySelection = { [weak self] selected in
				self?.onApplyDiffSelection?(change, text, selected)
			}
			existing?.onDiscardSelection = { [weak self] selected in
				self?.onDiscardDiffSelection?(change, text, selected)
			}
			existing?.onStashSelection = onStashDiffSelection == nil ? nil : { [weak self] selected in
				self?.onStashDiffSelection?(change, text, selected)
			}
			activeIndex = nil
			activate(index: index, focusEditor: false)
			return
		}

		let view = DiffView()
		view.setDiff(text, staged: change.isStaged, url: url)
		view.onApplySelection = { [weak self] selected in
			self?.onApplyDiffSelection?(change, text, selected)
		}
		view.onDiscardSelection = { [weak self] selected in
			self?.onDiscardDiffSelection?(change, text, selected)
		}
		view.onStashSelection = onStashDiffSelection == nil ? nil : { [weak self] selected in
			self?.onStashDiffSelection?(change, text, selected)
		}

		let scrollView = NSScrollView()
		scrollView.documentView = view
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		view.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
			view.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
		])

		let tab = Tab(url: url, document: nil, codeView: nil, contentView: scrollView, isPreview: true)
		tab.isDiff = true

		// Replaces the outgoing provisional tab, so clicking down a list of
		// changed files does not leave a tab behind for every one.
		if let existing = tabs.firstIndex(where: { $0.isPreview }) {
			tabs[existing].contentView.removeFromSuperview()
			tabs.remove(at: existing)
		}

		tabs.append(tab)
		activeIndex = nil
		activate(index: tabs.count - 1, focusEditor: false)
	}

	/// Shows what one commit did to one file.
	///
	/// Read-only, unlike a working-copy diff: there is nothing to stage in a
	/// commit that has already happened, and the subtitle says which commit it
	/// is rather than "diff".
	func openCommitDiff(commit: GitCommit, file: GitCommitFile, root: URL, text: String) {
		let url = root.appendingPathComponent(file.path)

		if let index = tabs.firstIndex(where: { $0.diffCommit == commit.shortHash && $0.url.path == url.path }) {
			activeIndex = nil
			activate(index: index, focusEditor: false)
			return
		}

		let view = DiffView()
		view.setDiff(text, staged: true, url: url)
		view.isReadOnly = true

		let scrollView = NSScrollView()
		scrollView.documentView = view
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		view.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
			view.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
		])

		let tab = Tab(url: url, document: nil, codeView: nil, contentView: scrollView, isPreview: true)
		tab.isDiff = true
		tab.diffCommit = commit.shortHash

		// Clicking down a list of files leaves one tab behind, not twenty.
		if let existing = tabs.firstIndex(where: { $0.isPreview }) {
			tabs[existing].contentView.removeFromSuperview()
			tabs.remove(at: existing)
		}

		tabs.append(tab)
		activeIndex = nil
		activate(index: tabs.count - 1, focusEditor: false)
	}

	/// Moves a tab within this group, for a reorder drop.
	func moveTab(from source: Int, to destination: Int) {
		guard tabs.indices.contains(source) else { return }
		let tab = tabs.remove(at: source)
		let target = max(0, min(destination, tabs.count))
		tabs.insert(tab, at: target)
		activeIndex = nil
		activate(index: target, focusEditor: false)
	}

	/// Applies a hand-picked language to the active tab and repaints it.
	func setActiveLanguage(_ languageId: String?) {
		guard let tab = activeTab, let document = tab.document else { return }
		document.setLanguage(languageId)
		statusLanguage = document.displayLanguageName
		onStatusChanged?(self)
		// And which server answers, since that is the language's question one
		// layer down: saying a file is Rust is saying rust-analyzer is what would
		// answer about it, and the chip beside the language must not go on naming
		// the server for the language it used to be.
		refreshServerState()
		// The document fires onSyntaxUpdated, which refreshes folds and repaints.
	}

	private func setStatus(line: Int, column: Int) {
		guard line != statusLine || column != statusColumn else { return }
		statusLine = line
		statusColumn = column
		onStatusChanged?(self)
	}

	/// Quiet enough to ignore, and the only coloured thing on an empty page —
	/// which is what makes it findable without shouting.
	private func styleScratchButton() {
		scratchButton.attributedTitle = NSAttributedString(
			string: "New Scratch File",
			attributes: [
				.font: Theme.current.uiFont(13),
				.foregroundColor: Theme.current.gitModified,
			]
		)
	}

	@objc private func newScratchFromPlaceholder() {
		newScratch()
	}

	/// Presses the empty page's button, rather than calling what it calls.
	func clickScratchPlaceholderForTesting() -> Bool {
		guard !scratchButton.isHidden else { return false }
		scratchButton.performClick(nil)
		return true
	}

	private func updateChrome() {
		let hasTabs = !tabs.isEmpty
		placeholder.isHidden = hasTabs
		scratchButton.isHidden = hasTabs
		tabBar.isHidden = !hasTabs
		contentArea.isHidden = !hasTabs
		if !hasTabs { hideServerBanner() }
		onStatusChanged?(self)
	}

	// MARK: - The missing-server banner

	@objc private func languageServersChanged() {
		refreshServerState()
		// A server that has only just finished the handshake is the usual case
		// here: the first keystrokes in a file are typed before it is up, and a
		// trigger set read at that point is empty for the life of the tab.
		for tab in tabs { refreshCompletionTriggers(for: tab) }
		// And a list that said "still preparing" now has something to ask for.
		// This notification is posted the moment preparing stops — 0501's chip
		// is drawn from the same one — so nothing here polls or waits.
		reaskIfWaitingOnAServer()
		// **The end of preparation repaints what is already on screen.** A
		// server's last act before it is ready may be to withdraw the false
		// diagnostic, or to send nothing at all — so a view that waited for the
		// next one would hold a dimmed error after the server was ready, which
		// is worse than the state being fixed. The same notification carries it,
		// and `setDiagnostics` returns early unless something really changed.
		for tab in tabs { applyDiagnostics(to: tab) }
	}

	/// What the strip above the file and the chip beside the caret should both
	/// say about this file's server.
	///
	/// One refresh, because they are one question asked at two lengths: the strip
	/// is the sentence with the button and the chip is the name with the mark.
	/// Called from the places a server's state can have changed under a file —
	/// activating a tab, a scope moving, choosing a language by hand, and
	/// `.ideaiLanguageServersChanged`, which every start, stop, refusal and
	/// reconsideration already posts.
	private func refreshServerState() {
		refreshServerBanner()
		refreshServerFooter()
	}

	/// A project's servers moved between this machine and its devcontainer.
	///
	/// Only for the project this group is showing: a window on another project
	/// has nothing to re-send, and re-opening its files at servers that never
	/// stopped would be a `didOpen` for a document they already hold.
	@objc private func languageServersMoved(_ note: Notification) {
		guard let moved = note.object as? URL, project != nil else { return }
		// **Any root this group's files are filed under**, not the scope. With a
		// root per file, one group can hold files belonging to several — a Swift
		// package and a Go module side by side — and a server moving under any
		// of them is one this group has documents at.
		let path = moved.standardizedFileURL.path
		let mine = tabs.contains { tab in
			serverRoot(for: tab)?.standardizedFileURL.path == path
		}
		guard mine else { return }
		rescope()
	}

	/// The root this tab's file is filed under, worked out once and kept.
	///
	/// The single answer every call site in this file uses. `LanguageService.root`
	/// decides it; this remembers it, because it is a directory walk and the
	/// questions asking it include one per keystroke.
	private func serverRoot(for tab: Tab) -> URL? {
		guard let project else { return nil }
		if let known = tab.serverRoot { return known }
		guard let languageId = tab.document?.languageId else { return nil }
		let root = LanguageService.shared.root(
			for: tab.url, languageId: languageId, project: project.root
		)
		tab.serverRoot = root
		return root
	}

	/// The same for a file being opened, before there is a tab to ask.
	private func serverRoot(for url: URL, languageId: String) -> URL? {
		guard let project else { return nil }
		return LanguageService.shared.root(for: url, languageId: languageId, project: project.root)
	}

	/// The tabs, in strip order, with the one in front marked.
	var tabNamesForTesting: String {
		tabs.map { ($0 === activeTab ? "*" : "") + $0.url.lastPathComponent }
			.joined(separator: ", ")
	}

	/// What find is doing in every tab, for a driver.
	///
	/// The gesture nothing could drive: find in one file, switch tab, step. The
	/// fault was read out of the code — one file's UTF-16 offsets handed to
	/// another file's view — and a claim read rather than seen is a claim worth
	/// checking.
	var findReportForTesting: String {
		var lines: [String] = []
		lines.append("bar showing=\(!findBar.isHidden) replacing=\(findBar.isReplacing)"
			+ " \(findBar.statusReportForTesting)")
		for (index, tab) in tabs.enumerated() {
			let mark = tab === activeTab ? "*" : " "
			let length = tab.document?.rope.utf16Count ?? 0
			lines.append("\(mark) \(index) \(tab.url.lastPathComponent)"
				+ " showing=\(tab.find.isShowing) query=\u{201C}\(tab.find.query)\u{201D}"
				+ " matches=\(tab.find.matches.count) current=\(tab.find.current.map(String.init) ?? "none")"
				+ " at=[\(tab.find.matches.prefix(8).map { "\($0.utf16Range.lowerBound)..<\($0.utf16Range.upperBound)" }.joined(separator: ","))]"
				+ " caret=\(tab.codeView?.caretOffset ?? -1) of \(length)")
		}
		return lines.joined(separator: "\n")
	}

	/// Which root the file in front is filed under, beside the scope, for a
	/// driver.
	///
	/// The two used to be the same thing by construction, which is the fault.
	/// Printed together so a run can show they are not — and that the file's
	/// answer is the one that follows the file.
	var serverRootReportForTesting: String {
		guard let project else { return "no project" }
		guard let tab = activeTab else { return "no tab" }
		let language = tab.document?.languageId ?? "none"
		let root = serverRoot(for: tab)?.lastPathComponent ?? "none"
		return "file=\(tab.url.lastPathComponent) language=\(language)"
			+ " root=\(root) scope=\(project.scopeRoot.lastPathComponent)"
			+ " project=\(project.root.lastPathComponent)"
	}

	/// Whether this file's language has anything to say about its server, and
	/// says it.
	///
	/// Asked on every activation rather than once per file: installing the
	/// server is the whole point of the bar, and somebody who has just done it
	/// should see it go away by clicking back onto their code rather than by
	/// restarting the app.
	///
	/// Asked of `LanguageService` rather than of `LanguageServers`, which is
	/// 0432's second fault: the second knows only whether the server is on this
	/// machine, and for a project worked on in a devcontainer the answer to that
	/// is "no" for ever — including while the container's own copy is answering.
	/// The first knows whether anything is running, coming, or neither, so the
	/// strip goes away when the server lands however late that is.
	private func refreshServerBanner() {
		if let notice = fileServerNotice() ?? launchNotice {
			serverBanner.show(notice)
			serverBanner.isHidden = false
			serverBannerHeight.constant = LanguageServerBanner.height
			return
		}
		hideServerBanner()
	}

	/// What the file in front of somebody has to say about its own server.
	private func fileServerNotice() -> LanguageService.ServerNotice? {
		guard project != nil,
		      let tab = activeTab,
		      !tab.isDiff,
		      let languageId = tab.document?.languageId,
		      !dismissedSuggestions.contains(languageId),
		      let root = serverRoot(for: tab)
		else { return nil }

		return LanguageService.shared.notice(
			forLanguage: languageId,
			project: root,
			ignoring: Set(Settings.shared.ignoredLanguageServers)
		)
	}

	/// What the selected launch configuration has to say, when the file has
	/// nothing.
	///
	/// Second, not first: the strip sits above the code, and a sentence about the
	/// file somebody is reading outranks one about a configuration they have not
	/// pressed yet. Both at once is the case this ordering settles — a Java file
	/// with no server, in a project whose launch cannot be debugged either, is
	/// one problem with one cause, and the file's version of it is the one that
	/// names the language.
	private var launchNotice: LanguageService.ServerNotice?

	/// Set by the window when the selected configuration changes.
	///
	/// Held here rather than recomputed, because deciding it needs the run
	/// picker's selection and this controller knows nothing about that.
	func setLaunchNotice(_ notice: LanguageService.ServerNotice?) {
		guard notice != launchNotice else { return }
		if let notice, dismissedSuggestions.contains(notice.languageId) { return }
		launchNotice = notice
		refreshServerBanner()
	}

	/// Works out what the footer's chip says and pushes it, if it has changed.
	///
	/// A diff tab is left out for the reason the strip leaves it out: the file
	/// beside it is a revision nobody's server has been told about, and naming a
	/// server over it would claim it is being checked.
	///
	/// The push is skipped when the answer is the same, which it is for the whole
	/// of a session in which nothing starts or stops. `.ideaiLanguageServersChanged`
	/// is posted by every window's servers, not only this one's, so without the
	/// comparison a project opening in another window would repaint every status
	/// bar in the app.
	private func refreshServerFooter() {
		var footer: LanguageServerFooter?
		if let tab = activeTab, !tab.isDiff, let languageId = tab.document?.languageId,
		   let root = serverRoot(for: tab) {
			// Keyed by the file's own root, so it names the server answering
			// about the file in front rather than the one the pill points at.
			footer = LanguageService.shared.footer(forLanguage: languageId, project: root)
		}
		guard footer != statusServer else { return }
		statusServer = footer
		onStatusChanged?(self)
	}

	private func hideServerBanner() {
		guard serverBanner != nil, !serverBanner.isHidden else { return }
		serverBanner.isHidden = true
		serverBannerHeight.constant = 0
	}

	private func showServerManual() {
		guard let notice = serverBanner.notice, let manual = notice.manual else { return }
		DetailDialog(
			title: "The \(notice.languageName) language server",
			detail: manual,
			isError: false
		).show(over: view.window)
	}

	private func ignoreServerSuggestion() {
		guard let notice = serverBanner.notice, notice.isIgnorable else { return }
		Settings.shared.ignoreLanguageServer(for: notice.languageId)
		hideServerBanner()
		// Every group in every window, not only this one: the answer was about
		// the language, and being asked again in the split beside it would read
		// as the button having done nothing.
		NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
	}

	private func dismissServerSuggestion() {
		guard let notice = serverBanner.notice else { return }
		dismissedSuggestions.insert(notice.languageId)
		hideServerBanner()
	}

	/// Takes the strip up on what it offered.
	///
	/// The scope rather than the project root, because that is the folder the
	/// notice was asked about and a subproject with a devcontainer of its own is
	/// the case 0432 exists for — agreeing here must agree to the container the
	/// sentence named.
	private func takeServerOffer() {
		guard let project, let offer = serverBanner.notice?.offer else { return }
		switch offer {
		case .useDevContainer:
			// For the server the banner is about, which is the one answering
			// about the file in front.
			LanguageService.shared.useDevContainer(
				for: activeTab.flatMap { serverRoot(for: $0) } ?? project.root
			)
		}
	}

	// MARK: - Testing

	/// What the bar is saying, or that it is not there.
	var serverBannerReportForTesting: String {
		guard !serverBanner.isHidden else { return "no banner" }
		let offer = serverBanner.offerForTesting
		return "\(serverBanner.sizesForTesting) — \(serverBanner.textForTesting)"
			+ (offer.isEmpty ? "" : " [\(offer)]")
	}

	func pressServerBannerForTesting(_ button: String) {
		switch button {
		case "details": serverBanner.pressDetailsForTesting()
		case "ignore": serverBanner.pressIgnoreForTesting()
		case "offer": serverBanner.pressOfferForTesting()
		default: serverBanner.pressDismissForTesting()
		}
	}

	/// Distance from the top of the window to the first row of content.
	func setTopInset(_ inset: CGFloat) {
		tabBarTopConstraint.constant = inset
		// The drop preview is drawn over this whole view, which begins behind
		// the titlebar; without the same inset its top edge is covered by it.
		(view as? EditorDropView)?.topInset = inset
	}

	// MARK: - Project

	func setProject(_ project: Project) {
		self.project = project
	}

	// MARK: - Scratch files

	/// Somewhere to put something that is not part of the project.
	///
	/// A real file, so it highlights, folds and searches like anything else —
	/// but one kept outside the repository, where it cannot end up in a commit.
	/// A global one belongs to no project: notes about a language or a way of
	/// doing something, which outlive whichever checkout they were written in.
	func newScratch(global: Bool = false) {
		let files: ScratchFiles
		if global {
			files = .global()
		} else {
			guard let root = project?.root else { return }
			files = ScratchFiles(projectRoot: root)
		}

		do {
			let url = try files.create()
			open(fileURL: url, focusEditor: true)
			NotificationCenter.default.post(name: .ideaiScratchesChanged, object: nil)
		} catch {
			presentScratchFailure(error)
		}
	}

	/// Reopens the scratches this project was left with.
	///
	/// The ones that were open, not every one it has: after a few weeks those
	/// are different numbers, and a window full of old notes is not a restored
	/// workspace. Anything not reopened is still in the Scratches pane — this
	/// decides which tabs come back, never which notes exist.
	func restoreScratches() {
		guard let project else { return }

		// No record yet — the first launch after this was added, or a project
		// only ever opened before it. What it has is the best guess at what it
		// had open. Asked under `sessionRoot`, which is what recorded them.
		let remembered = OpenScratches().existing(forProject: project.sessionRoot)
			?? ScratchFiles(projectRoot: project.root).all()

		for url in remembered where !tabs.contains(where: { $0.url == url }) {
			open(fileURL: url, focusEditor: false)
		}
	}

	/// The scratches open in this group, in tab order.
	var openScratchURLs: [URL] {
		tabs.map(\.url).filter { ScratchFiles.isScratch($0) }
	}

	/// Throws away a scratch that was closed with nothing in it.
	///
	/// Without this every stray double-click would come back at the next open,
	/// for ever. One with something in it is kept: nobody else has that text.
	private func discardIfEmptyScratch(_ tab: Tab) {
		// Not asked which project it belongs to: closing everything to swap
		// projects happens once the window has already taken the new one, and
		// the tabs going away are still the old one's.
		guard ScratchFiles.isScratch(tab.url) else { return }

		// Empty on disk and empty in the editor. Both, because a document that
		// still holds text the disk does not is exactly the case where throwing
		// the file away would lose something — whether the write failed or the
		// text was never written at all. A scratch is the only copy of what is
		// in it, so anything short of certainly-nothing is kept.
		if let document = tab.document, !document.isEmptyText { return }
		let size = (try? tab.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
		guard size == 0 else { return }

		// To the Trash even though it is empty: nothing here is certain enough
		// to be worth an unrecoverable delete.
		_ = try? ScratchFiles.moveToTrash(tab.url)
		NotificationCenter.default.post(name: .ideaiScratchesChanged, object: nil)
	}

	/// Writes an open scratch out before something else moves it.
	///
	/// A rename that left unsaved text behind would either lose it or write it
	/// back to the name the file no longer has.
	func saveIfOpen(_ url: URL) {
		guard let tab = tabs.first(where: { $0.url == url }), tab.isDirty else { return }
		try? tab.document?.save()
	}

	/// The scope moved, so every open file is announced again.
	///
	/// A file opened while the whole checkout was in view went to the server for
	/// the checkout; working on the subproject it belongs to gives it a
	/// different server, and one that has never heard of it answers nothing
	/// about it. `LanguageService.opened` is what closes it at the old one and
	/// opens it at the new, and does nothing at all when they are the same.
	func rescope() {
		guard project != nil else { return }
		for tab in tabs {
			guard !tab.isDiff, let document = tab.document, let languageId = document.languageId
			else { continue }
			// Re-worked out rather than reused: a rescope is exactly when a
			// file may have changed which root owns it.
			tab.serverRoot = nil
			guard let root = serverRoot(for: tab) else { continue }
			LanguageService.shared.opened(
				url: tab.url, languageId: languageId, text: text(of: document),
				project: root
			)
		}
		refreshServerState()
	}

	/// A scratch was renamed, moved, or thrown away: follow it.
	func scratchMoved(from: URL, to destination: URL?) {
		guard let index = tabs.firstIndex(where: { $0.url == from }) else { return }
		let wasActive = activeIndex == index
		removeTab(at: index)
		if let destination { open(fileURL: destination, focusEditor: wasActive) }
	}

	private func presentScratchFailure(_ error: Error) {
		Toast.post("Could not create a scratch file", detail: error.localizedDescription)
	}

	// MARK: - Opening

	/// Opens a file.
	///
	/// - `preview`: a single click in the tree opens provisionally, reusing the
	///   one preview slot. A double-click (or editing) makes it permanent.
	/// - Already-open files are activated rather than reopened, which is what
	///   makes clicking a file in the tree select its existing tab.
	/// The tab already showing a file, whatever spelling of its path is asked.
	///
	/// **Two names for one file is the ordinary case, not the exotic one.** A
	/// project reached through a symlink has two: the one somebody typed and the
	/// one the file system answers with. `/tmp` is itself a symlink to
	/// `/private/tmp` on every Mac, so a project under it has two spellings
	/// before anybody has done anything unusual.
	///
	/// That is not hypothetical here. `abydos <file>` in a pane resolves its
	/// argument with `pwd -P`, because a shell's idea of where it is has to be
	/// made absolute before it can be sent anywhere — and the app is holding the
	/// unresolved name. Compared as URLs, those are different files, so the
	/// command opened a second tab onto the file already on screen.
	///
	/// Compared here rather than by canonicalising the tab's URL, because the
	/// URL a tab holds is what is *shown* — in the tab, the title and the
	/// breadcrumbs — and rewriting somebody's `~/dev/thing` into
	/// `/private/var/…` to win an argument about identity would be a poor trade.
	/// The tab keeps the name it was opened under; only the question "is this
	/// already open" is asked in the file system's terms.
	///
	/// `FilePath.canonical` is the same answer breakpoints needed, for the same
	/// reason: one keyed `/tmp/x` never matched the `/private/tmp/x` the
	/// debugger reported, and so was set and never hit.
	private func indexOfTab(showing fileURL: URL) -> Int? {
		if let exact = tabs.firstIndex(where: { $0.url == fileURL }) { return exact }
		let wanted = FilePath.canonical(fileURL)
		return tabs.firstIndex { FilePath.canonical($0.url) == wanted }
	}

	/// - Parameters:
	///   - preview: a provisional tab, the italic one a single click opens.
	///   - mode: how to show it, when a session remembered. Nil is not `.source`
	///     but "whatever this kind of file opens as" — see `FilePreview`.
	///   - dividerFraction: where the divider was, for a mode that has one.
	func open(
		fileURL: URL,
		focusEditor: Bool = false,
		preview: Bool = false,
		mode: PreviewMode? = nil,
		dividerFraction: Double? = nil
	) {
		let departure = currentPlace
		defer {
			DispatchQueue.main.async { [weak self] in
				guard let self, let arrival = self.currentPlace else { return }
				self.reportNavigation(from: departure, to: arrival)
			}
		}

		if let existing = indexOfTab(showing: fileURL) {
			// Committing to a file that is currently provisional pins it.
			if !preview { tabs[existing].isPreview = false }
			activate(index: existing, focusEditor: focusEditor)
			return
		}

		guard let tab = makeTab(
			for: fileURL, preview: preview, mode: mode, dividerFraction: dividerFraction
		) else { return }

		if preview, let previewIndex = tabs.firstIndex(where: { $0.isPreview }) {
			// Replace the provisional tab in place, so it does not jump position.
			//
			// The file it held is told to the server as closed, which replacement
			// did not do: the slot is recycled rather than removed, so nothing went
			// through `removeTab`, and walking a usage list through forty files
			// left forty documents open at a server that had been told about every
			// one of them and about the end of none.
			announceClosed(tabs[previewIndex])
			teardown(tabs[previewIndex])
			tabs[previewIndex] = tab
			activate(index: previewIndex, focusEditor: focusEditor)
		} else {
			let insertAt = activeIndex.map { $0 + 1 } ?? tabs.count
			tabs.insert(tab, at: min(insertAt, tabs.count))
			activate(index: min(insertAt, tabs.count - 1), focusEditor: focusEditor)
		}
	}

	private func makeTab(
		for fileURL: URL,
		preview: Bool,
		mode: PreviewMode? = nil,
		dividerFraction: Double? = nil
	) -> Tab? {
		// Rendering a huge or binary blob as text helps nobody, but refusing to
		// open it is not the answer either — the tab explains itself and offers
		// the hex viewer instead.
		// A mesh has no source worth reading, so it opens rendered. Checked
		// before the size and binary tests, both of which an STL fails on its
		// way to being useful.
		if FilePreview.defaultMode(for: fileURL) == .preview, FilePreview.hasPreview(fileURL) {
			// A picture opens as the picture; a mesh opens rendered. Both skip
			// the size and binary tests below, which each of them fails on the
			// way to being useful.
			switch FilePreview.kind(for: fileURL) {
			case .image:
				// Unless it is a drawing with text behind it, which goes the
				// ordinary way and comes back rendered at the end.
				if !FilePreview.hasReadableSource(fileURL) {
					return makeImageTab(for: fileURL, preview: preview)
				}
			case .model:
				return makeModelTab(for: fileURL, preview: preview)
			case .pdf:
				// A PDF is a picture's case exactly: nothing to edit, no source to
				// read, and it fails the binary test below on its way to being
				// useful.
				return makePdfTab(for: fileURL, preview: preview)
			default:
				// A `.drawio` opens rendered and has no source half, and it is
				// still a document this app owns: it goes the ordinary way and
				// gets a `TextDocument` like every other file, which is what
				// makes ⌘S, the edited dot and the close prompt work. The
				// branch above used to assume "rendered and not a picture"
				// meant "mesh", and sent every `.drawio` to the 3D viewer.
				break
			}
		}

		// The binary test first, and it costs nothing to ask it there: it reads
		// eight thousand bytes whatever the file's size, so the old order —
		// size, then kind — was not buying anything with it. `FileNotice.reason`
		// holds which of the two answers wins, where a test can pin it.
		let byteSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
		if let reason = FileNotice.reason(
			isBinary: FileInspector.isProbablyBinary(url: fileURL),
			isTooLargeForText: byteSize > 64 * 1024 * 1024
		) {
			return makeNoticeTab(for: fileURL, reason: reason, preview: preview)
		}

		let document: TextDocument
		do {
			document = try TextDocument(url: fileURL)
		} catch {
			return makeNoticeTab(for: fileURL, reason: error.localizedDescription, preview: preview)
		}

		let codeView = CodeView()
		let scrollView = NSScrollView()
		scrollView.documentView = codeView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		// Not forced to .overlay: that ignores "Show scroll bars: Always" in
		// System Settings, so someone who asked for permanent scrollers never
		// got them and had no way to tell there was anything to scroll to.
		scrollView.scrollerStyle = NSScroller.preferredScrollerStyle
		scrollView.contentView.postsBoundsChangedNotifications = true
		// Soft wrap is measured against the viewport, so the layout has to be
		// rebuilt when the viewport changes size — a window resize, a split, a
		// divider drag. Bounds changes alone are scrolls, not resizes.
		scrollView.contentView.postsFrameChangedNotifications = true

		NotificationCenter.default.addObserver(
			forName: NSView.frameDidChangeNotification,
			object: scrollView.contentView,
			queue: .main
		) { [weak codeView] _ in
			codeView?.viewportChanged()
		}

		// The gutter is drawn relative to the clip view, so a horizontal scroll
		// has to repaint even though the document content did not change.
		NotificationCenter.default.addObserver(
			forName: NSView.boundsDidChangeNotification,
			object: scrollView.contentView,
			queue: .main
		) { [weak codeView] _ in
			codeView?.viewportChanged()
			codeView?.needsDisplay = true
		}

		let tab = Tab(url: fileURL, document: document, codeView: codeView, contentView: scrollView, isPreview: preview)
		// The one place a file is looked at from *outside its name* to decide what
		// previews it has. Costs nothing unless the name is a `.yaml`, and then the
		// head of it; nothing unless the name is a `.swift`, and then a walk up to
		// `Package.swift` and a read of it. Once per tab — see `Tab.looksLikeRecipe`
		// and `Tab.cadova` for why neither is asked again.
		tab.looksLikeRecipe = Go3mfRecipe.looksLikeRecipe(fileURL)
		tab.cadova = CadovaModel.find(for: fileURL, stoppingAt: project?.root)

		// Clicking a name in the blame column says what that commit was.
		codeView.onShowBlameDetail = { entry in
			let when = DateFormatter.localizedString(
				from: entry.date, dateStyle: .medium, timeStyle: .short
			)
			Toast.post(
				entry.summary.isEmpty ? entry.shortCommit : entry.summary,
				detail: "\(entry.shortCommit) · \(entry.author) · \(when)",
				kind: .information
			)
		}

		codeView.onCaretMoved = { [weak self] line, column in
			guard let self, self.activeTab === tab else { return }
			self.setStatus(line: line, column: column)
		}
		codeView.onDirtyChanged = { [weak self] _ in
			// Editing a provisional tab is a commitment to it, the same rule
			// VS Code and IDEA use.
			tab.isPreview = false
			self?.refreshTabBar()
			self?.scheduleLanguageSync(for: tab)
		}
		// Auto save clears the dirty marker without any further user action.
		document.onAutoSaved = { [weak self] in
			self?.refreshTabBar()
			guard let self, let languageId = document.languageId,
			      let root = self.serverRoot(for: fileURL, languageId: languageId) else { return }
			// The other half of what repeats. An auto-save follows every typing
			// pause, so this built the whole file as a `String` on the main
			// thread as often as the sync above did.
			self.withText(of: document) { text in
				LanguageService.shared.saved(
					url: fileURL, languageId: languageId, text: text, project: root
				)
			}
		}

		// A value beside the code, opened. The fetching belongs to whoever holds
		// the session — this side knows where the hint was and nothing else.
		codeView.onOpenInlineValue = { [weak self] hint, rect in
			guard let self else { return }
			self.openInlineValue(hint, at: rect, over: codeView)
		}

		codeView.onToggleBreakpoint = { [weak self] line in
			// The gutter works in 0-based lines; everything outside is 1-based.
			self?.onToggleBreakpoint?(fileURL, line + 1)
		}
		codeView.onEditBreakpoint = { [weak self] line in
			self?.onEditBreakpoint?(fileURL, line + 1)
		}
		codeView.onSetBreakpointEnabled = { [weak self] line, enabled in
			self?.onSetBreakpointEnabled?(fileURL, line + 1, enabled)
		}
		codeView.onDeleteBreakpoint = { [weak self] line in
			self?.onDeleteBreakpoint?(fileURL, line + 1)
		}
		codeView.onSetOtherBreakpointsEnabled = { [weak self] line, enabled in
			self?.onSetOtherBreakpointsEnabled?(fileURL, line + 1, enabled)
		}
		codeView.onLinesChanged = { [weak self] first, removed, inserted in
			self?.onLinesChanged?(fileURL, first, removed, inserted)
		}
		codeView.onTextReplaced = { [weak self, weak tab] range, inserted in
			guard let tab else { return }
			self?.textReplaced(in: tab, replacing: range, insertedLength: inserted)
		}
		codeView.onRunLine = { [weak self] line in
			// Already 1-based: the gutter converts before reporting a run.
			self?.onRunLine?(fileURL, line)
		}
		codeView.onGoToDefinition = { [weak self] line, character in
			self?.goToDefinition(from: tab, line: line, character: character)
		}
		codeView.onFindUsages = { [weak self] line, character in
			self?.onFindUsages?(tab.url, line, character)
		}
		codeView.onRename = { [weak self] line, character in
			self?.onRename?(tab.url, line, character)
		}
		codeView.onWatch = { [weak self] expression in
			self?.onWatch?(expression)
		}
		codeView.onFixWithAI = { [weak self] line, diagnostic in
			self?.onFixWithAI?(tab.url, line, diagnostic)
		}
		codeView.onCopyLink = { [weak self] form, line, endLine in
			self?.onCopyLink?(tab.url, form, line, endLine)
		}
		codeView.onRequestCompletions = { [weak self] prefix, wasTriggered, _ in
			self?.scheduleCompletions(for: tab, prefix: prefix, wasTriggered: wasTriggered)
		}
		codeView.onRequestCompletionsNow = { [weak self] prefix in
			self?.completeNow(in: tab, prefix: prefix)
		}
		codeView.onDismissCompletions = { [weak self] in
			self?.completionWork?.cancel()
			self?.completions.hide()
		}
		codeView.onSnippetStopChanged = { [weak self, weak tab] name in
			guard let self, let tab else { return }
			self.hintForSnippetStop(name, in: tab)
		}
		codeView.onRequestSignatureHelp = { [weak self, weak tab] in
			guard let self, let tab else { return }
			self.askForSignatureHelp(in: tab)
		}
		codeView.completionKeyHandler = { [weak self] selector in
			self?.handleCompletionKey(selector) ?? false
		}
		codeView.load(document: document)
		codeView.setWordWrap(Settings.shared.wordWrap)
		applyDebugState(to: tab)
		applyConditionalBreakpoints(to: tab)
		tab.sourceView = scrollView

		// The server is told about the file as it is opened, and answers about
		// it from then on.
		if let languageId = document.languageId,
		   let root = serverRoot(for: fileURL, languageId: languageId) {
			// Worked out once, here, and carried by the tab: every later
			// question must reach the server this `didOpen` went to.
			tab.serverRoot = root
			LanguageService.shared.opened(
				url: fileURL, languageId: languageId, text: text(of: document), project: root
			)
			codeView.setDiagnostics(
				LanguageService.shared.diagnostics(for: fileURL),
				fromPreparingServer: LanguageService.shared.isPreparing(
					languageId: languageId, project: root
				)
			)
			refreshCompletionTriggers(for: tab)
		}

		// A file whose rendered form is the point of it does not open as text:
		// an SVG in a documentation folder is a picture first and its path data
		// second, and a PlantUML file is a diagram somebody is checking against
		// the lines that describe it, so it opens with both.
		//
		// Unless a session says otherwise, in which case that is what it opens
		// as. Decided here rather than by putting the tab right afterwards, so a
		// `.scad` coming back as its source does not build a model view first and
		// throw it away — a restore opens every tab the project had at once.
		let opening = FilePreview.restoredMode(mode, for: fileURL, facts: tab.previewFacts)
		if opening != .source, FilePreview.hasPreview(fileURL, facts: tab.previewFacts) {
			tab.previewMode = opening
			tab.contentView = makeContentView(for: tab, mode: opening, dividerFraction: dividerFraction)
		}
		return tab
	}

	// MARK: - Language servers

	/// Whole text of a document, which is what full synchronisation sends.
	///
	/// Still on the caller's thread, and the caller is usually the main one.
	/// That is fine for the two callers that open a file, which happen once
	/// each; the two that repeat go through `withText(of:)` below.
	private func text(of document: TextDocument) -> String {
		document.rope.string(in: 0..<document.rope.byteCount)
	}

	/// Where a file's text is decoded for a language server.
	///
	/// Serial, so two of these cannot cross. A `didChange` carries a version
	/// number and a whole file, and the older of two arriving last would leave
	/// the server describing text that nobody has. A serial queue delivers the
	/// builds in the order they were asked for, and each hands back to the main
	/// queue as it finishes, so the order survives both hops.
	private static let languageTextQueue = DispatchQueue(
		label: "abydos.languagetext", qos: .userInitiated
	)

	/// Builds a document's whole text away from the main queue and sends it from
	/// the main queue once it is built.
	///
	/// 0437 left this on the main thread and called it a trade wanting a
	/// measurement, on the grounds that the rope is edited on the main thread
	/// and reading it anywhere else is a race. That is true of the *document* —
	/// the main thread reassigns `TextDocument.rope` on every keystroke — and it
	/// is not true of a `Rope`, which is persistent and `Sendable`: taking the
	/// value is a reference bump, and nothing can change it afterwards. It is
	/// the same free snapshot `TextDocument.symbols` already hands to the
	/// parser's queue, three hundred lines above where the doubt was written.
	///
	/// So there is no trade and nothing to measure. Decoding a megabyte of UTF-8
	/// into a `String` is the whole cost, it happens every 0.4 s of typing and on
	/// every auto-save, and it is now on a queue the keyboard does not share.
	///
	/// Through `WeakRelay` rather than two nested `async` calls, and 0465 is why:
	/// written the obvious way the inner `[weak self]` bought nothing, because the
	/// outer closure had to hold `self` strongly to build it. The editor was kept
	/// alive for the length of every decode in flight, which is exactly the gap
	/// the guard below was written for.
	private func withText(
		of document: TextDocument, send: @escaping (String) -> Void
	) {
		let snapshot = document.rope
		WeakRelay.build(on: EditorViewController.languageTextQueue, for: self) {
			snapshot.string(in: 0..<snapshot.byteCount)
		} then: { editor, text in
			// Closed while its text was being decoded. There is no gap to
			// close today, because the send follows the build immediately;
			// there is one now, and a `didChange` for a file the editor no
			// longer holds is one the server cannot make sense of.
			guard editor.tabs.contains(where: { $0.document === document }) else { return }
			StallWatch.mark("language sync") { send(text) }
		}
	}

	/// Tells the server what changed, once the typing pauses.
	///
	/// Debounced because a keystroke is not worth a round trip: a server asked
	/// to reparse on every character spends its time on text nobody has
	/// finished writing, and the diagnostics that come back are about a
	/// half-typed line.
	private func scheduleLanguageSync(for tab: Tab) {
		languageSyncWork?.cancel()
		let work = DispatchWorkItem { [weak self, weak tab] in
			guard let self, let tab, let document = tab.document,
			      let languageId = document.languageId
			else { return }
			// Nothing is waiting to be sent once this has run, which is what
			// `showCompletions` reads to decide whether it has to send it first.
			self.languageSyncWork = nil
			let url = tab.url
			guard let root = self.serverRoot(for: tab) else { return }
			withText(of: document) { text in
				LanguageService.shared.changed(
					url: url, languageId: languageId, text: text, project: root
				)
			}
		}
		languageSyncWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
	}

	/// Sends what is waiting, now, and does not come back until it has gone.
	///
	/// **A question about text the server has not been told about is answered
	/// about different text.** The sync is debounced at 0.4 s and a completion
	/// at 0.15 s, so every list was asked for against a document one or two
	/// keystrokes stale. With a word prefix that mostly went unnoticed — the
	/// server answered about the same identifier a moment earlier and the
	/// answer looked right. Driven against a Swift package it was unmissable:
	/// `Corner.` typed at the end of a file asked about a position past the end
	/// of the file the server held, and sourcekit-lsp answered with a *global*
	/// list — `LazyMapCollection`, `LazyFilterSequence` — where the four cases
	/// of the enum were what had been asked for.
	///
	/// The decode still happens off the main thread; what is new is waiting for
	/// it. That costs one decode per list rather than one per 0.4 s of typing,
	/// which is the price of the answer being about the right text.
	private func syncTextNow(for tab: Tab) async {
		guard languageSyncWork != nil else { return }
		languageSyncWork?.cancel()
		languageSyncWork = nil

		guard let document = tab.document, let languageId = document.languageId,
		      let root = serverRoot(for: tab)
		else { return }
		let url = tab.url
		let snapshot = document.rope

		let text = await withCheckedContinuation { continuation in
			EditorViewController.languageTextQueue.async {
				continuation.resume(returning: snapshot.string(in: 0..<snapshot.byteCount))
			}
		}
		// Ordering is the whole point and it is the wire that provides it: this
		// notification and the request that follows go down the same pipe, so
		// the server has read the change before it reads the question.
		LanguageService.shared.changed(url: url, languageId: languageId, text: text, project: root)
	}

	// MARK: - History

	/// Shows every state the file has been in, including the ones undo cannot
	/// reach because something else was typed after them.
	func toggleFileHistory() {
		guard let tab = activeTab, let document = tab.document, let codeView = tab.codeView else { return }
		historyPopup.onTravel = { [weak self] state in
			guard let restored = document.travel(to: state) else { return }
			codeView.setCaretForTesting(restored)
			codeView.reloadAfterHistoryTravel()
			self?.refreshTabBar()
		}
		historyPopup.toggle(history: document.history, over: codeView)
	}

	func focusForTesting() {
		guard let codeView = activeTab?.codeView else { return }
		view.window?.makeFirstResponder(codeView)
	}

	/// Presses return, through the same command a key press produces.
	func simulateReturn() {
		guard let codeView = activeTab?.codeView else { return }
		view.window?.makeFirstResponder(codeView)
		codeView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
	}

	/// Tab, which steps to the next snippet stop while a session is live and
	/// indents the rest of the time.
	func simulateTab() {
		guard let codeView = activeTab?.codeView else { return }
		view.window?.makeFirstResponder(codeView)
		codeView.doCommand(by: #selector(NSResponder.insertTab(_:)))
	}

	/// Escape, which is how somebody says they have finished with the stops.
	func simulateEscape() {
		guard let codeView = activeTab?.codeView else { return }
		view.window?.makeFirstResponder(codeView)
		codeView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
	}

	/// Takes a completion the way the list does, then works the keys, saying
	/// where the caret and the selection are after each one.
	///
	/// The spec is a server's own `insertText` and then what to do to it, `|`
	/// between: `tab`, `backtab`, `esc`, `home` and `end` are those keys, and
	/// anything else is typed a character at a time. So
	///
	///     cube(size = ${1:size}, center = false);$0|10|tab
	///
	/// is what openscad-lsp answers `cube` with, `10` typed over the stop it
	/// selects, and Tab to the end of the line.
	///
	/// Through `applyCompletion` and `doCommand` — the same two doors a chosen
	/// completion and a key press come through — because what is worth watching
	/// is whether Tab reaches the stops, and a driver that called the stepping
	/// method directly would prove nothing about that.
	func exerciseSnippetForTesting(_ spec: String) {
		guard let codeView = codeViewToDrive("--snippet") else {
			print("SNIPPET: no editor")
			return
		}
		view.window?.makeFirstResponder(codeView)

		let steps = spec.components(separatedBy: "|")
		codeView.applyCompletion(Snippet.expand(steps[0]), replacingPrefixOfLength: 0)
		print("SNIPPET inserted: \(codeView.caretReportForTesting)")

		for step in steps.dropFirst() {
			switch step {
			case "tab":     codeView.doCommand(by: #selector(NSResponder.insertTab(_:)))
			case "backtab": codeView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
			case "esc":     codeView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
			case "home":    codeView.doCommand(by: #selector(NSResponder.moveToBeginningOfLine(_:)))
			case "end":     codeView.doCommand(by: #selector(NSResponder.moveToEndOfLine(_:)))
			default:        simulateTyping(step)
			}
			print("SNIPPET \(step): \(codeView.caretReportForTesting)")
		}

		for line in textTailLinesForTesting(3) where !line.isEmpty {
			print("SNIPPET line: |\(line.replacingOccurrences(of: "\t", with: "→"))|")
		}
		fflush(stdout)
	}

	/// The last few lines of the file, for looking at what typing produced.
	func textTailLinesForTesting(_ count: Int) -> [String] {
		guard let document = activeTab?.document else { return [] }
		let text = document.rope.string(in: 0..<document.rope.byteCount)
		let lines: [String] = text.components(separatedBy: "\n")
		return Array(lines.suffix(count))
	}

	/// One line of the file, for watching a key that deletes.
	///
	/// The caret report says nothing about ⌃K: a forward delete leaves the
	/// caret where it was, so the only difference between the key working and
	/// the key doing nothing is in the text. `textTailForTesting` answers the
	/// same question for the *end* of a file, and a driver pressing a deleting
	/// key in the middle of one has to name the line.
	func lineTextForTesting(_ line: Int) -> String {
		guard let document = activeTab?.document else { return "no file" }
		guard line >= 0, line < document.rope.lineCount else { return "no line \(line)" }
		return document.rope.lineText(line)
	}

	func goToDefinitionForTesting(line: Int, character: Int) {
		guard let tab = activeTab else { return }
		goToDefinition(from: tab, line: line, character: character)
	}

	func hoverWithCommandForTesting(line: Int, character: Int) {
		activeTab?.codeView?.hoverWithCommandForTesting(line: line, character: character)
	}

	func undoForTesting() {
		codeViewToDrive("--undo-tree")?.undo(nil)
	}

	/// The last line or two of the file, for checking what a jump produced.
	var textTailForTesting: String {
		guard let document = activeTab?.document else { return "no file" }
		let text = document.rope.string(in: 0..<document.rope.byteCount)
		return text.split(separator: "\n").suffix(2).joined(separator: " / ")
	}

	var fileHistoryReportForTesting: String {
		guard let document = activeTab?.document else { return "no file" }
		let history = document.history
		return "\(history.count) states, at \(history.current), "
			+ "\(history.futures.count) way(s) forward"
	}

	func showFileHistoryForTesting() {
		toggleFileHistory()
	}

	var historySummariesForTesting: [String] { historyPopup.summariesForTesting }

	func travelToHistoryRowForTesting(_ index: Int) {
		historyPopup.travelToRowForTesting(index)
	}

	// MARK: - Completion

	/// Asks for completions a moment after typing stops.
	///
	/// Debounced, and never on the first character of a word: a list offered
	/// after one letter is mostly noise, and asking a language server on every
	/// keystroke is asking it to answer about text nobody has finished writing.
	///
	/// **A trigger character skips the two-letter rule and nothing else.** The
	/// caret after a `.` is in no word, so waiting for a second letter means
	/// waiting for something that will never come — but the debounce still
	/// applies, so `.centerX` typed at speed is one request for where the
	/// typing stopped rather than seven.
	private func scheduleCompletions(for tab: Tab, prefix: String, wasTriggered: Bool = false) {
		completionWork?.cancel()
		guard wasTriggered || prefix.count >= 2 else {
			completions.hide()
			return
		}

		let work = DispatchWorkItem { [weak self, weak tab] in
			guard let self, let tab else { return }
			Task { @MainActor in await self.showCompletions(for: tab, prefix: prefix) }
		}
		completionWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
	}

	/// Answers ⌃Space: a list now, and a reason when there cannot be one.
	///
	/// Not `scheduleCompletions`, and not because of the prefix rule alone. That
	/// waits 150 ms so a list does not chase somebody's typing, which is right
	/// for typing and wrong for a keystroke whose whole meaning is *now*.
	private func completeNow(in tab: Tab, prefix: String) {
		completionWork?.cancel()
		completionWork = nil

		// **Said before the question, not after it.** Asking a server is an
		// await, and until it answers nothing is on screen — measured against
		// sourcekit-lsp at 1.0 s and 6.0 s after ⌃Space on an empty line: an
		// empty popup, then twenty items. That first second is exactly the
		// moment somebody wonders whether the key did anything, and if the
		// reason it is slow is that the server is still starting, that is the
		// answer they need and it is already known here.
		if let codeView = tab.codeView, let languageId = tab.document?.languageId,
		   let root = serverRoot(for: tab), let point = codeView.caretScreenPoint() {
			if let obstacle = LanguageService.shared.notReadySentence(
				languageId: languageId, project: root
			) {
				completions.show(
					notice: obstacle,
					below: point,
					lineHeight: codeView.lineHeightForTesting,
					parent: view.window
				)
			} else {
				// A server with nothing wrong with it can still be slow:
				// sourcekit-lsp, warm and finished preparing, took over a second
				// to answer an empty line. Said after a moment rather than at
				// once — a notice that flashed and was replaced on every fast
				// answer would be worse than the silence it replaces — and only
				// if nothing else has appeared by then.
				let deadline = DispatchTime.now() + 0.15
				DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self, weak tab] in
					guard let self, let tab, self.activeTab === tab,
					      !self.completions.isVisible,
					      let point = tab.codeView?.caretScreenPoint()
					else { return }
					self.completions.show(
						notice: "Asking the \(languageId) server…",
						below: point,
						lineHeight: codeView.lineHeightForTesting,
						parent: self.view.window
					)
				}
			}
		}

		Task { @MainActor in await self.showCompletions(for: tab, prefix: prefix, wasAsked: true) }
	}

	/// Asks again for a list that was told to wait.
	///
	/// Only where the popup is showing the sentence: every other list on screen
	/// is already an answer, and re-asking for one on every server notification
	/// would be a request per start, stop and reconsideration in the window.
	private func reaskIfWaitingOnAServer() {
		guard completions.isWaitingOnAServer, let tab = activeTab, let codeView = tab.codeView
		else { return }
		let prefix = codeView.currentWordPrefix()
		Task { @MainActor in await self.showCompletions(for: tab, prefix: prefix) }
	}

	/// Tells a tab's view what its server wants to be woken by.
	///
	/// Asked again when a server finishes starting, because the first keystrokes
	/// in a file are usually typed before it has finished the handshake — and a
	/// trigger set read once, too early, is empty for the life of the tab.
	private func refreshCompletionTriggers(for tab: Tab) {
		guard let codeView = tab.codeView, let languageId = tab.document?.languageId,
		      let root = serverRoot(for: tab)
		else { return }
		let completion = LanguageService.shared.completionTriggers(languageId: languageId, project: root)
		codeView.completionTriggerCharacters = Set(completion.compactMap { $0.first })
		let signature = LanguageService.shared.signatureTriggers(languageId: languageId, project: root)
		codeView.signatureTriggerCharacters = Set(signature.compactMap { $0.first })
	}

	// MARK: - What is being filled in

	/// The prose of the completion that was last taken, for as long as its stops
	/// are being stepped through.
	///
	/// Kept because it is the only thing that knows what the parameters are for
	/// a server with no signature help. openscad-lsp advertises none, and the
	/// 1530 characters it sends with `cube` are where "a single value, or a
	/// three-value array" is written down.
	private var takenDocumentation: String?

	/// Says what the stop now being filled in takes, or takes the strip away.
	private func hintForSnippetStop(_ name: String?, in tab: Tab) {
		guard let name, let codeView = tab.codeView else {
			parameterHint.hide()
			takenDocumentation = nil
			return
		}

		// Where the server has signature help, that is the better answer — it
		// knows the whole call rather than one paragraph — and asking is worth
		// a round trip because the stop has only just been arrived at.
		if let languageId = tab.document?.languageId, let root = serverRoot(for: tab),
		   LanguageService.shared.offersSignatureHelp(languageId: languageId, project: root) {
			askForSignatureHelp(in: tab)
			return
		}

		// **Exact, or nothing.** A near match would put a neighbouring
		// parameter's type under the caret, and a wrong answer here is worse
		// than none because it will be believed.
		guard let prose = takenDocumentation,
		      let description = ServerDocumentation.description(ofParameter: name, in: prose),
		      let point = codeView.caretScreenPoint()
		else {
			parameterHint.hide()
			return
		}

		let text = "\(name) — \(description)"
		let name16 = name.utf16.count
		parameterHint.show(text, emphasising: 0..<name16, above: point, parent: view.window)
	}

	/// Asks the server what call the caret is in, and says so above the line.
	///
	/// **Debounced like the completion list, and for a stronger reason.** The
	/// characters this fires on are `(`, `[`, `,` and `:` — sourcekit-lsp's own
	/// retrigger set — so an argument list typed at speed would otherwise be one
	/// request per comma. One request for where the typing stopped instead.
	///
	/// What one costs, measured against sourcekit-lsp on a warm file: 104 ms for
	/// the first and 1 ms for the five after it. So the debounce is not there to
	/// protect the server — it is cheap once it has answered about a file — but
	/// to stop a request going out for a call nobody has finished typing, whose
	/// answer would arrive and be replaced.
	///
	/// Nothing is sent at all to a server that did not claim the capability;
	/// openscad-lsp is never asked, which is what keeps a `.scad` from waiting
	/// on a reply that never comes.
	private func askForSignatureHelp(in tab: Tab) {
		signatureWork?.cancel()
		let work = DispatchWorkItem { [weak self, weak tab] in
			guard let self, let tab else { return }
			Task { @MainActor in await self.showSignatureHelp(for: tab) }
		}
		signatureWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
	}

	@MainActor
	private func showSignatureHelp(for tab: Tab) async {
		guard activeTab === tab, let codeView = tab.codeView, let document = tab.document,
		      let languageId = document.languageId
		else { return }

		// The same reason as the completion list: a call the server has not been
		// told about is a call it answers about the version before it.
		await syncTextNow(for: tab)
		guard activeTab === tab else { return }

		let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: codeView.caretOffset))
		let lineStart = document.rope.utf16Offset(fromByte: document.rope.byteOffset(ofLine: line))
		let character = codeView.caretOffset - lineStart

		guard let root = serverRoot(for: tab) else { return }
		let help = await LanguageService.shared.signatureHelp(
			url: tab.url,
			position: LSPPosition(line: line, character: character),
			languageId: languageId,
			project: root
		)

		guard activeTab === tab, let active = help?.active, let point = codeView.caretScreenPoint()
		else {
			parameterHint.hide()
			return
		}
		parameterHint.show(
			active.signature.label,
			emphasising: active.parameter?.range,
			above: point,
			parent: view.window
		)
	}

	@MainActor
	private func showCompletions(for tab: Tab, prefix: String, wasAsked: Bool = false) async {
		guard activeTab === tab, let codeView = tab.codeView, let document = tab.document else { return }

		// The prefix may have moved on while this was being asked for.
		guard codeView.currentWordPrefix() == prefix else { return }

		var items: [CompletionItem] = []
		if let project, let languageId = document.languageId {
			// Before the question, so it is asked about the text on screen.
			await syncTextNow(for: tab)
			guard activeTab === tab, codeView.currentWordPrefix() == prefix else { return }

			let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: codeView.caretOffset))
			let lineStart = document.rope.utf16Offset(fromByte: document.rope.byteOffset(ofLine: line))
			let character = codeView.caretOffset - lineStart

			let fromServer = await LanguageService.shared.completions(
				url: tab.url,
				position: LSPPosition(line: line, character: character),
				languageId: languageId,
				project: serverRoot(for: tab) ?? project.root
			)
			// A server answers about types and scope; the words in the file
			// cannot, so anything it says is worth more than anything they do.
			//
			// Matched on `matchText` — the server's own `filterText` where it
			// sent one — rather than on the label. Neither server driven here
			// labels an item with its name: openscad-lsp's `cube` is labelled
			// `cube(size, center=false)`, which starts with the word by luck,
			// and sourcekit-lsp labels a function with its whole signature, so
			// the label filter threw away most of a Swift answer.
			let typed = prefix.lowercased()
			items = fromServer
				.filter { $0.matchText.lowercased().hasPrefix(typed) }
				.prefix(20)
				.map(CompletionItem.init)
		}

		// **A server that has not finished starting has not said no.** It is the
		// words in the file that used to be shown here, and they look like an
		// answer: measured against a Cadova package, sourcekit-lsp answered
		// nothing at 1, 11, 32 and 62 seconds after the file was opened, and the
		// enum cases somebody was waiting for at 123, once it had built 651
		// files. Four empty answers and a right one, indistinguishable from
		// "this language has nothing to offer" for the whole two minutes.
		if items.isEmpty, let languageId = document.languageId,
		   let root = serverRoot(for: tab),
		   let obstacle = LanguageService.shared.notReadySentence(
			   languageId: languageId, project: root
		   ) {
			guard let point = codeView.caretScreenPoint() else { return }
			completions.show(
				notice: obstacle,
				below: point,
				lineHeight: codeView.lineHeightForTesting,
				parent: view.window
			)
			return
		}

		if items.isEmpty {
			let text = document.rope.string(in: 0..<document.rope.byteCount)
			items = WordCompletions
				.candidates(matching: prefix, in: text, near: codeView.caretOffset)
				.map { CompletionItem(label: $0, isFromServer: false) }
		}

		guard !items.isEmpty, codeView.currentWordPrefix() == prefix else {
			// A question asked on purpose is answered, including when the answer
			// is nothing. Typing that finds nothing simply takes the list away,
			// because there was no question — but ⌃Space over a blank line and
			// then silence is indistinguishable from a key that does not work.
			if wasAsked, let point = codeView.caretScreenPoint() {
				completions.show(
					notice: "No completions here",
					below: point,
					lineHeight: codeView.lineHeightForTesting,
					parent: view.window
				)
			} else {
				completions.hide()
			}
			return
		}

		completionPrefixLength = prefix.utf16.count
		completions.onCommit = { [weak codeView, weak self] item in
			guard let self else { return }
			// Kept for the life of the session the insertion is about to start:
			// for a server with no signature help this is the only thing that
			// knows what the stops mean.
			self.takenDocumentation = item.documentationSource
			// A snippet is not text to paste: `union() $0` means "put the caret
			// between the braces", and inserted as written it is a syntax
			// error somebody has to go back and delete. Where it has more than
			// one place for the caret to go, the view steps through them on Tab.
			let snippet = item.isSnippet
				? Snippet.expand(item.insertText)
				: Snippet(text: item.insertText, caret: item.insertText.utf16.count)
			codeView?.applyCompletion(snippet, replacingPrefixOfLength: self.completionPrefixLength)
		}
		guard let point = codeView.caretScreenPoint() else { return }
		completions.show(
			items: items,
			below: point,
			lineHeight: codeView.lineHeightForTesting,
			parent: view.window
		)
	}

	/// The keys the list takes before the document sees them.
	private func handleCompletionKey(_ selector: Selector) -> Bool {
		guard completions.isVisible else { return false }
		switch selector {
		case #selector(NSResponder.moveUp(_:)):     return completions.moveSelection(by: -1)
		case #selector(NSResponder.moveDown(_:)):   return completions.moveSelection(by: 1)
		case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
			return completions.commitSelection()
		case #selector(NSResponder.cancelOperation(_:)):
			completions.hide()
			return true
		default:
			// Arrow keys sideways, or anything else, simply put it away: the
			// caret has left the word the list was built for.
			if selector == #selector(NSResponder.moveLeft(_:))
				|| selector == #selector(NSResponder.moveRight(_:)) {
				completions.hide()
			}
			return false
		}
	}

	/// Follows a ⌘-click to wherever the symbol is defined.
	private func goToDefinition(from tab: Tab, line: Int, character: Int) {
		guard let project, let languageId = tab.document?.languageId else { return }
		Task { @MainActor in
			let locations = await LanguageService.shared.definition(
				url: tab.url,
				position: LSPPosition(line: line, character: character),
				languageId: languageId,
				project: serverRoot(for: tab) ?? project.root
			)
			guard let first = locations.first, let url = first.url else { return }
			open(fileURL: url, atLine: first.range.start.line + 1)
		}
	}

	/// Applies whatever a server last said about the files that are open.
	@objc private func diagnosticsChanged(_ notification: Notification) {
		guard let url = notification.object as? URL else { return }
		for tab in tabs where tab.url.absoluteString == url.absoluteString {
			applyDiagnostics(to: tab)
		}
	}

	/// What a server said about this tab's file, and how sure it was.
	///
	/// **Whether the server is preparing is asked here, on the path the
	/// diagnostics already take**, rather than being carried with them: it is a
	/// fact about the server at the moment of drawing, and it changes without
	/// any diagnostic arriving to say so.
	private func applyDiagnostics(to tab: Tab) {
		guard let codeView = tab.codeView else { return }
		let preparing = isServerPreparing(for: tab)
		codeView.setDiagnostics(
			LanguageService.shared.diagnostics(for: tab.url), fromPreparingServer: preparing
		)
	}

	/// Whether the server that answers for this tab's file has said it is not
	/// ready.
	///
	/// By project and language, which is what `isPreparing` is keyed by and what
	/// a tab knows about its own file — so a window holding a preparing Swift
	/// server and a settled Go one behaves correctly by construction rather than
	/// by a special case.
	private func isServerPreparing(for tab: Tab) -> Bool {
		guard let languageId = tab.document?.languageId,
		      let root = serverRoot(for: tab) ?? project?.root
		else { return false }
		return LanguageService.shared.isPreparing(languageId: languageId, project: root)
	}

	// MARK: - Debugging

	/// Sets the breakpoints to draw, keyed by absolute path.
	func setBreakpoints(_ breakpoints: [String: [Int: CodeView.BreakpointMark]]) {
		breakpointsByFile = breakpoints
		for tab in tabs { applyDebugState(to: tab) }
	}

	/// Lines with a play button, keyed by absolute file path.
	func setRunnableLines(_ lines: [String: Set<Int>]) {
		runnableLinesByFile = lines
		for tab in tabs { applyDebugState(to: tab) }
	}

	/// The variables of the frame execution is stopped in, to be drawn beside
	/// the code that names them.
	///
	/// The same route the marker, the breakpoints and the runnable lines take:
	/// one function pushes per-file debug state into every tab, so a second way
	/// in would be a second place for a tab to be missed.
	func setInlineValues(_ values: InlineValueSet?) {
		// A tree of values from a program that is running again is worse than no
		// tree: the values leaving is exactly the moment it goes.
		if values == nil { dismissOpenValue() }
		inlineValues = values
		for tab in tabs { applyDebugState(to: tab) }
	}

	/// Marks where execution stopped, clearing it elsewhere.
	func setExecutionLocation(file: String?, line: Int?) {
		if let file, let line {
			executionLocation = (file, line)
		} else {
			executionLocation = nil
		}
		for tab in tabs { applyDebugState(to: tab) }
	}

	private func applyDebugState(to tab: Tab) {
		guard let codeView = tab.codeView else { return }
		let path = FilePath.canonical(tab.url)

		// Breakpoints are stored the way a debug adapter numbers lines, from 1;
		// the view draws rows, which start at 0. The execution line below has
		// always converted — breakpoints did not, so every marker was drawn one
		// line below the line it was set on.
		let stored = breakpointsByFile[path] ?? [:]
		var marks: [Int: CodeView.BreakpointMark] = [:]
		for (line, mark) in stored { marks[line - 1] = mark }
		codeView.setBreakpoints(marks)
		// Keyed by the resolved path: /tmp is a symlink to /private/tmp, and a
		// project reached through any symlinked directory would otherwise match
		// nothing and silently show no play buttons.
		codeView.setRunnableLines(runnableLinesByFile[path] ?? [])

		// The marker belongs only in the file execution actually stopped in.
		if let location = executionLocation, location.file == path {
			codeView.setExecutionLine(location.line - 1)
		} else {
			codeView.setExecutionLine(nil)
		}

		// And so do the values: a variable is in scope in the frame it belongs
		// to, so every other file gets none. Canonicalised here for the same
		// reason the breakpoints are — /tmp is a symlink to /private/tmp, and a
		// frame reached through a symlinked directory would match nothing.
		if let values = inlineValues, FilePath.canonical(URL(fileURLWithPath: values.file)) == path {
			codeView.setInlineValues(values.values)
		} else {
			codeView.setInlineValues(nil)
		}
	}

	/// Draws every row of the file in front, which is what scrolling it does.
	func scrollStoppedFileForTesting() {
		guard let codeView = activeTab?.codeView else { return }
		codeView.drawEveryRowForTesting()
	}

	/// Opens the first value on the stopped line that has something under it.
	///
	/// Every tab rather than the one in front, for the same reason the values
	/// report reads them all: stopping moves the keyboard about, and "the active
	/// tab" is not a thing worth making a driven check depend on.
	func openFirstInlineValueForTesting() -> String? {
		for tab in tabs {
			guard let codeView = tab.codeView,
			      let found = codeView.firstOpenableInlineValueForTesting()
			else { continue }
			openInlineValue(found.hint, at: found.rect, over: codeView)
			return found.hint.text
		}
		return nil
	}

	func openValueReportForTesting() -> String {
		guard let popup = openValuePopup else { return "nothing is open" }
		return "\(popup.placementForTesting)\n\(popup.reportForTesting)"
	}

	/// Sends selectors at the editor the way a key binding would, and says what
	/// was named — for `--unhandled-motions`.
	///
	/// **Not a key press, and the reason is the finding.** The four motions this
	/// editor still does not handle are all `select…` and none of them has a
	/// default binding on this system, so there is no key that reaches them —
	/// which is exactly why nobody noticed they were missing. What can be driven
	/// is the path a binding would take: `doCommand(by:)`, the same function the
	/// key would arrive at.
	func exerciseUnhandledMotionsForTesting() -> String {
		guard let codeView = activeTab?.codeView else { return "no file in front" }
		for name in ["selectWord:", "selectParagraph:", "noop:", "complete:", "selectWord:"] {
			codeView.doCommand(by: Selector(name))
		}
		return UnhandledMotions.reportForTesting
	}

	/// Walks what is open with the arrow keys, and says where it ended up.
	func walkOpenValueForTesting(_ keys: [String]) -> String {
		openValuePopup?.walkForTesting(keys) ?? "nothing is open"
	}

	/// The same, but reported after whatever the walk asked for has arrived.
	func walkOpenValueThenSettleForTesting(_ keys: [String], then say: @escaping (String) -> Void) {
		guard let popup = openValuePopup else { return say("nothing is open") }
		popup.walkThenSettleForTesting(keys, then: say)
	}

	/// What colour the opened value draws its selected row in.
	func openValueSelectionColourForTesting() -> String {
		openValuePopup?.selectionColourForTesting ?? "nothing is open"
	}

	/// What the opened value's menu offers, and what it copies.
	func openValueMenuForTesting() -> String {
		guard let popup = openValuePopup else { return "nothing is open" }
		return "menu: \(popup.menuTitlesForTesting)\n"
			+ "  name -> \(popup.copyForTesting("name"))\n"
			+ "  value -> \(popup.copyForTesting("value"))\n"
			+ "  both -> \(popup.copyForTesting("both"))\n"
			+ "  tree -> \(popup.copyForTesting("tree"))"
	}

	/// Opens a field inside what is open, for the claim about lazy children.
	func expandInsideOpenValueForTesting() -> String {
		openValuePopup?.expandFirstChildForTesting() ?? "nothing is open"
	}

	/// What a click on the value named would do, without doing it — for the
	/// claim that a piece of text is not a door.
	func inlineValueClickForTesting(named name: String) -> String {
		for tab in tabs {
			guard let codeView = tab.codeView,
			      let answer = codeView.clickAnswerForTesting(named: name)
			else { continue }
			return answer
		}
		return "no value called \(name) is on screen"
	}

	/// Asked for the children of a container, by the reference the adapter gave.
	///
	/// Set by whoever holds the debug session. Nil while nothing is stopped, in
	/// which case there is nothing to open and no hint to open it from.
	var onVariableChildren: ((Int) async -> [Variable])?

	/// Opens a value beside the code into a tree of its own.
	private func openInlineValue(_ hint: InlineValueHint, at rect: NSRect, over view: NSView) {
		guard let onVariableChildren else { return }
		openValuePopup?.dismiss()
		// **The variable, not the hint.** A hint carries the value cut to what
		// fits at the end of a line — ellipsis and all — which is right on the
		// line and wrong everywhere else: copying one out of this window handed
		// back `…` in the middle of a struct. The frame's own answer is what the
		// window is opened on, and the adapter's children carry their full
		// values already.
		let root = inlineValues?.values[hint.name] ?? Variable(
			name: hint.name,
			value: hint.value,
			type: nil,
			variablesReference: hint.variablesReference
		)
		let popup = VariableTreePopup(root: root, children: onVariableChildren)
		openValuePopup = popup
		popup.show(over: view, at: rect)
	}

	/// The one that is open, so a second click replaces it rather than stacking,
	/// and so that resuming can take it away.
	private var openValuePopup: VariableTreePopup?

	/// Closes what is open, which the end of a stop does.
	func dismissOpenValue() {
		openValuePopup?.dismiss()
		openValuePopup = nil
	}

	/// What a server said about each open file, and how loudly it is drawn.
	///
	/// Every tab rather than the one in front: a Cadova model opens with a
	/// preview beside it, and "the file in front" is then whichever half the
	/// driver last touched — which is not a thing worth making a report depend
	/// on.
	func diagnosticReportForTesting() -> String {
		let coded = tabs.filter { $0.codeView != nil }
		guard !coded.isEmpty else { return "no code view is open" }
		return coded.map { tab in
			"\(tab.url.lastPathComponent):\n\(tab.codeView?.diagnosticReportForTesting ?? "")"
		}.joined(separator: "\n")
	}

	/// What each open file has beside its code, for `--debug-inspect`.
	///
	/// **Every tab, not the one in front**, because the claim has two halves:
	/// the frame's file shows its variables, and every other file shows none. A
	/// report of the front tab alone can only ever say the first.
	func inlineValueReportForTesting() -> String {
		guard !tabs.isEmpty else { return "no file is open" }
		return tabs.map { tab in
			let name = tab.url.lastPathComponent
			guard let codeView = tab.codeView else { return "\(name): not a code view" }
			return "\(name):\n\(codeView.inlineValueReportForTesting())"
		}.joined(separator: "\n")
	}

	/// A short selection, suitable for seeding a search field.
	func selectedTextForSearch() -> String? {
		guard let text = activeTab?.codeView?.selectedText() ?? pdfPreview?.selectedText,
		      !text.isEmpty, !text.contains("\n")
		else {
			return nil
		}
		return text
	}

	// MARK: - Find in file

	/// The PDF the tab in front is showing, when it is showing one.
	///
	/// A PDF tab is the document and nothing else — there is no split to look
	/// inside, unlike a diagram — so this is the whole search.
	private var pdfPreview: PdfFileView? { activeTab?.contentView as? PdfFileView }

	/// Opens the find bar, seeded with the selection when there is one.
	/// Whether the find bar is up, for a driven run asking who got ⌘F.
	var findBarIsShowingForTesting: Bool { !findBar.isHidden }

	func showFind() {
		guard let tab = activeTab, tab.codeView != nil || pdfPreview != nil else { return }
		tab.find.isShowing = true
		// The tab's mode, which ⌘F reports rather than changes: somebody who
		// pressed it to re-read their query has not asked for the replacement
		// they typed to go away.
		findBar.setReplacing(tab.find.isReplacing)
		showFindBar(true)

		if let selected = selectedTextForSearch() {
			findBar.setQuery(selected)
		}
		findBar.focusField()
		runFind(query: findBar.query, options: findBar.options)
	}

	/// Opens the bar in replace mode, or switches an open one to it.
	///
	/// Only where there is something to edit. A PDF is searched through PDFKit
	/// and has no text to change, so ⌘R leaves its bar alone rather than putting
	/// up two buttons that cannot fire.
	func showReplace() {
		guard let tab = activeTab, tab.codeView != nil, tab.document != nil else { return }

		// A bar already up keeps what it was searching for: ⌘R is a switch, and
		// re-seeding from the selection would take away the query somebody is
		// part-way through replacing.
		let wasShowing = tab.find.isShowing
		tab.find.isShowing = true
		tab.find.isReplacing = true
		findBar.setReplacing(true)
		showFindBar(true)

		// **Only when the bar was closed.** A search that is already showing has
		// its answer in hand, and running it again is not free of consequence:
		// `runFind` starts from the caret and `setSearchMatches` leaves the caret
		// at the end of whichever match it made current — so asking twice walks
		// the current match forward one. Driving this caught it: ⌘R over a bar
		// showing `1 of 4` replaced the *third* match.
		if !wasShowing {
			if let selected = selectedTextForSearch() { findBar.setQuery(selected) }
			runFind(query: findBar.query, options: findBar.options)
		}
		findBar.focusReplaceField()
	}

	/// Replaces the match the bar calls current, and shows the one after it.
	///
	/// The step is only about *showing*: the edit itself takes this match out of
	/// the list and leaves the next one current, through the same
	/// `onTextReplaced` every other edit goes through. Showing it is the part
	/// that matters — pressing Replace again edits whatever is current, and
	/// something off the bottom of the pane is not something to edit unseen.
	private func replaceCurrent(steppingBy delta: Int) {
		guard let tab = activeTab, let document = tab.document, let codeView = tab.codeView else { return }
		guard findBar.isPatternValid, findBar.isTemplateValid else { return }
		guard let current = tab.find.current, tab.find.matches.indices.contains(current) else { return }

		let match = tab.find.matches[current]
		// Asked of the text as it is now. A match found before an edit is a range
		// and not a promise, and `replacement` answers nil rather than replacing
		// something else that happens to be there.
		guard let text = TextSearch.replacement(
			forMatchAt: match.utf16Range,
			in: document.rope.string,
			query: tab.find.query,
			options: tab.find.options,
			template: findBar.replacement
		) else { return }

		codeView.replace(utf16Range: match.utf16Range, with: text)
		stepMatch(by: delta > 0 ? 0 : -1)
	}

	/// Replaces every match, as one edit.
	///
	/// One `document.replace` over the span from the first match to the last, so
	/// the undo history gets one entry and the parser one edit — not one of each
	/// per match. What lies between the matches and did not match is carried
	/// through untouched.
	private func replaceAll() {
		guard let tab = activeTab, let document = tab.document, let codeView = tab.codeView else { return }
		guard findBar.isPatternValid, findBar.isTemplateValid else { return }
		guard let edit = TextSearch.replaceAll(
			in: document.rope.string,
			query: tab.find.query,
			options: tab.find.options,
			template: findBar.replacement
		) else { return }

		codeView.replace(utf16Range: edit.utf16Range, with: edit.text)
	}

	/// Drives a replace the way the buttons do, and says what it did.
	///
	/// Every step is the one a person takes — the bar is opened, the query and
	/// the replacement are typed into it, and the button's own verb is called —
	/// so what this proves is the path and not a private shortcut through it.
	/// Selects the first place a string appears and says what lit up because of
	/// it, once the scan has settled.
	func selectTextForTesting(_ text: String) -> Bool {
		guard let codeView = activeTab?.codeView else { return false }
		return codeView.selectTextForTesting(text)
	}

	var occurrenceReportForTesting: String {
		activeTab?.codeView?.occurrenceReportForTesting ?? "no code view"
	}

	func replaceForTesting(query: String, replacement: String, all: Bool, regex: Bool) -> String {
		// The same refusal `--type` is held to, and for the same reason: this
		// verb edits whatever is in front, `--open` is a request rather than a
		// guarantee, and a run that rewrote a stranger's file would be the third
		// incident of that shape rather than the first.
		guard codeViewToDrive("--replace") != nil else { return "refused" }
		showReplace()
		findBar.setReplacement(replacement)
		// Only a query this run has not already typed, and for the same reason
		// `showReplace` will not re-run one: asking again moves the match the
		// buttons are about.
		if findBar.query != query || regex != findBar.options.isRegex {
			// The switches as this run named them, rather than as the last run
			// left them: a driven run says what it wants and inherits nothing.
			findBar.setQueryWithoutSearching(query, options: SearchOptions(isRegex: regex))
			// The bar debounces; a run nobody is watching cannot wait for it.
			runFind(query: findBar.query, options: findBar.options)
		}

		let before = activeTab?.find.matches.count ?? 0
		if all { replaceAll() } else { replaceCurrent(steppingBy: 1) }
		return "all=\(all) matched=\(before)\n\(findReportForTesting)"
	}

	func setFindQuery(_ query: String) {
		showFind()
		findBar.setQuery(query)
	}

	func closeFind() {
		// This tab's, and only this tab's. Closing find in one file used to
		// close it in every file in the group, because there was one flag for
		// all of them.
		if let tab = activeTab {
			tab.find = Tab.FindState()
			tab.codeView?.clearSearchMatches()
		}
		showFindBar(false)
		findBar.setReplacing(false)
		findBar.setReplacement("")
		pdfPreview?.clearFind()
		focusActiveEditor()
	}

	/// The one bar, shown or hidden. Which tab it is *about* is the tab's.
	private func showFindBar(_ showing: Bool) {
		findBar.isHidden = !showing
		findBarHeight.constant = showing ? findBar.wantedHeight : 0
	}

	/// Puts the arriving tab's find state into the bar.
	///
	/// Called from `activate(index:)` and from nowhere else. Touches nothing
	/// about responders: where the keyboard goes after a tab switch is settled
	/// there, twice, with the measurements in the comments.
	private func restoreFind(for tab: Tab) {
		// The mode before the height, which is worked out from it.
		findBar.setReplacing(tab.find.isReplacing)
		findBar.setReplacement(tab.find.replacement)
		showFindBar(tab.find.isShowing)
		guard tab.find.isShowing else {
			// **Emptied, not just hidden.** Driving this caught the bar still
			// holding `widget` and `1 of 199` after the tab that searched for it
			// was closed — invisible, because the bar was hidden, and waiting to
			// be shown over a file it knows nothing about. A hidden control
			// holding another tab's answer is the same class of fault as the
			// matches were.
			findBar.setQueryWithoutSearching("", options: SearchOptions())
			findBar.setReplacing(false)
			findBar.setReplacement("")
			findBar.setStatus(matchCount: 0, currentIndex: nil)
			return
		}
		findBar.setQueryWithoutSearching(tab.find.query, options: tab.find.options)
		// The matches belong to this tab's document, so they can be handed to
		// this tab's view — which is the whole point of their living here.
		tab.codeView?.setSearchMatches(tab.find.matches, current: tab.find.current)
		findBar.setStatus(matchCount: tab.find.matches.count, currentIndex: tab.find.current)
	}

	var isFindVisible: Bool { activeTab?.find.isShowing ?? false }

	/// Debounced so a search does not run on every keystroke of a long query.
	private func scheduleFind(query: String, options: SearchOptions, movingCaret: Bool = true) {
		findDebounce?.cancel()
		let work = DispatchWorkItem { [weak self] in
			self?.runFind(query: query, options: options, movingCaret: movingCaret)
		}
		findDebounce = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
	}

	/// - Parameter movingCaret: whether the current match should be selected and
	///   scrolled to. True for a search somebody asked for by typing a query;
	///   false for the one an edit triggers, where the caret is where they are
	///   typing and taking it to the nearest match would make the file
	///   impossible to type in with find open.
	private func runFind(query: String, options: SearchOptions, movingCaret: Bool = true) {
		// A PDF has no rope to search, so PDFKit searches it and the bar is told
		// the same two numbers it is told for a source file. Whole-word and regex
		// are not offered by `PDFDocument.findString`, so those switches do
		// nothing here — the bar keeps showing them because they still apply to
		// the next file, and a search that quietly ignored them would find more
		// than it said rather than less.
		// Remembered whatever kind of tab this is, so coming back to it shows
		// what was being looked for.
		activeTab?.find.query = query
		activeTab?.find.options = options

		// **A pattern that will not compile is not searched for.** It used to
		// be: the search ran, got nothing out of a regex that never compiled,
		// and the bar reported `No results` — an answer to a question nobody
		// asked. Not searching also keeps the last valid query's matches on
		// screen, rather than clearing them on the keystroke that was only half
		// of a bracket.
		guard TextSearch.isValid(query: query, options: options) else {
			findBar.setStatus(matchCount: 0, currentIndex: nil)
			return
		}

		if let pdf = pdfPreview {
			// A PDF has its matches inside PDFKit rather than as offsets, so the
			// tab keeps the question and `PdfFileView` keeps the answer.
			let count = pdf.find(query, caseSensitive: options.caseSensitive)
			findBar.setStatus(matchCount: count, currentIndex: pdf.currentMatchIndex)
			return
		}

		guard let tab = activeTab, let document = tab.document, let codeView = tab.codeView else { return }

		guard !query.isEmpty else {
			tab.find.matches = []
			tab.find.current = nil
			codeView.clearSearchMatches()
			findBar.setStatus(matchCount: 0, currentIndex: nil)
			return
		}

		let matches = TextSearch.matches(in: document.rope, query: query, options: options)
		// Start from the match nearest the caret rather than the top of the file.
		let caret = codeView.caretOffset
		let nearestToCaret = matches.firstIndex { $0.utf16Range.lowerBound >= caret }
			?? (matches.isEmpty ? nil : 0)

		// **A search an edit asked for keeps the match the edit left current.**
		// The caret rule alone moves on one every time: an edit — a replacement
		// above all — leaves the caret at the end of what it put in, and the
		// first match at or after that is the *next* one. Driving it showed the
		// wobble plainly: Replace lit `1 of 3`, and a tenth of a second later the
		// same three matches were `2 of 3` with nothing having happened.
		let current: Int?
		if movingCaret {
			current = nearestToCaret
		} else {
			let wanted = tab.find.current.flatMap {
				tab.find.matches.indices.contains($0) ? tab.find.matches[$0].utf16Range : nil
			}
			current = wanted.flatMap { range in matches.firstIndex { $0.utf16Range == range } }
				?? nearestToCaret
		}
		tab.find.matches = matches
		tab.find.current = current

		if movingCaret {
			codeView.setSearchMatches(matches, current: current)
		} else {
			codeView.updateSearchMatches(matches, current: current)
		}
		findBar.setStatus(matchCount: matches.count, currentIndex: current)
	}

	/// The text moved under a tab's matches.
	///
	/// **Nothing used to ask.** `runFind` was called from the find field, from a
	/// tab coming to the front and from ⌘G, and from no edit anywhere — so the
	/// matches were offsets into the text as it had been when the search ran. A
	/// file searched for a path and then edited to take that path off eight of
	/// its ten lines drew eight bands of the old length at the old offsets, over
	/// words holding nothing of the sort. They are not only drawn, either: the
	/// current one sets a caret.
	///
	/// Two halves, and each is wrong alone. The matches are moved now, so nothing
	/// false is ever on screen; the search is asked again on the debounce it
	/// already runs on, because an edit can make a match as easily as destroy
	/// one and only searching knows.
	private func textReplaced(in tab: Tab, replacing range: Range<Int>, insertedLength: Int) {
		// A file nobody is searching pays nothing for this.
		guard tab.find.isShowing else { return }

		let adjusted = MatchesAfterEdit.adjusted(
			tab.find.matches,
			current: tab.find.current,
			replacing: range,
			insertedLength: insertedLength
		)
		tab.find.matches = adjusted.matches
		tab.find.current = adjusted.current

		// The bar and the bands are the active tab's. A background tab keeps its
		// adjusted matches and is drawn from them when it comes forward.
		guard tab === activeTab else { return }
		tab.codeView?.updateSearchMatches(adjusted.matches, current: adjusted.current)
		findBar.setStatus(matchCount: adjusted.matches.count, currentIndex: adjusted.current)
		scheduleFind(query: tab.find.query, options: tab.find.options, movingCaret: false)
	}

	private func stepMatch(by delta: Int) {
		if let pdf = pdfPreview {
			pdf.stepMatch(by: delta)
			findBar.setStatus(matchCount: pdf.matchCount, currentIndex: pdf.currentMatchIndex)
			return
		}

		// **This tab's matches.** They used to be the group's, so stepping after
		// a tab switch handed one file's offsets to another file's view — and
		// `setSearchMatches` sets a caret from them, against a document that
		// never produced that range.
		guard let tab = activeTab else { return }
		let matches = tab.find.matches
		guard !matches.isEmpty else { return }
		let current = tab.find.current ?? -1
		// Wraps, which is what every find bar does at the ends.
		let next = ((current + delta) % matches.count + matches.count) % matches.count
		tab.find.current = next
		tab.codeView?.setSearchMatches(matches, current: next)
		findBar.setStatus(matchCount: matches.count, currentIndex: next)
	}

	func findNext() { stepMatch(by: 1) }
	func findPrevious() { stepMatch(by: -1) }

	/// ⌘G with the keyboard in the text rather than in the find field.
	///
	/// Every verb that opens the find bar leaves the keyboard in it, so a capture
	/// taken after one can only ever show an *unfocused* selection over the
	/// current match. The other state is real and is reached by the ordinary
	/// gesture — the bar is open, the keyboard is back in the code, ⌘G steps on —
	/// and 0536 had to be looked at in both, because the selection that lands on
	/// the current match is a different colour in each.
	func findNextFromEditor(_ times: Int) {
		focusActiveEditor()
		for _ in 0..<max(1, times) { findNext() }
	}

	/// Opens a file and jumps to a line — the target of review findings and
	/// search results.
	///
	/// `focusEditor` and `preview` are what tell "take me to this one" from "show
	/// me this one": a checklist being walked with ↓ asks for the provisional tab
	/// and leaves the keyboard in the list, so 263 usages cost one tab rather than
	/// 263, and the next ↓ still reaches the next row. Both keep the defaults the
	/// call has always had, so a click and a review finding are unchanged.
	///
	/// The column is where a search match starts on its line and the length is how
	/// wide it is, and they are here because a line is not a place: a match two
	/// hundred characters along a long line is off the side of the pane, and a
	/// forty-character one starting a column inside the edge is mostly off it. The
	/// editor can know neither from the line alone. Column one and length nothing
	/// are the start of the line, which is what a review finding and a `file:150`
	/// mean.
	///
	/// The reveal happens **now**, not on the next turn of the main loop. It used
	/// to be a `DispatchQueue.main.async`, whose comment had the diagnosis right —
	/// a freshly opened document has not laid out, so scrolling would measure
	/// against a zero-height view — and answered it with a bet: one turn is not
	/// "layout has finished", it is one turn. Where the sizing took two, or was
	/// itself scheduled, the reveal ran against a pane that was still wrong and
	/// scrolled somewhere that was not the line. `CodeView.reveal` now forces the
	/// layout pass it depends on and, where there is still nothing to measure,
	/// waits for the pane to be given a size rather than for time to pass — so
	/// this is a plain call, on the tab this call opened, and `abydos deep.txt:150
	/// main.go` cannot reveal line 150 on the wrong file because there is no
	/// interval in which the active tab can change.
	func open(
		fileURL: URL,
		atLine line: Int,
		column: Int = 1,
		length: Int = 0,
		focusEditor: Bool = true,
		preview: Bool = false
	) {
		let departure = currentPlace
		isReportingSuppressed += 1
		open(fileURL: fileURL, focusEditor: focusEditor, preview: preview)
		isReportingSuppressed -= 1
		reportNavigation(
			from: departure,
			to: (fileURL, line)
		)
		activeTab?.codeView?.reveal(line: line, column: column, length: length)
	}

	/// Puts the caret on a 1-based line of the file being edited.
	///
	/// Nothing happens when no file is open: `:` in the palette is a question
	/// about a document, and there is no document to ask it of.
	/// ⌃Space: offer completions at the caret, whatever is being typed.
	func completeAtCaret() {
		guard let tab = activeTab, let codeView = tab.codeView else { return }
		codeView.requestCompletionsNow()
	}

	func goTo(line: Int) {
		activeTab?.codeView?.reveal(line: line)
		activeTab?.codeView?.window?.makeFirstResponder(activeTab?.codeView)
	}

	// MARK: - Markdown preview

	/// Swaps the active markdown tab between source and rendered preview.
	/// Cycles a markdown tab between source and preview, for the menu command.
	func toggleMarkdownPreview() {
		guard let tab = activeTab, tab.isMarkdown else { return }
		setPreviewMode(tab.previewMode == .source ? .preview : .source)
	}

	/// Shows a file's source, its rendered form, or both.
	func setPreviewMode(_ mode: PreviewMode) {
		guard let tab = activeTab, let index = activeIndex else { return }
		guard availableModes(for: tab).contains(mode) else { return }
		guard mode != tab.previewMode else { return }

		tab.previewMode = mode
		tab.contentView = makeContentView(for: tab, mode: mode)

		activeIndex = nil
		activate(index: index, focusEditor: mode == .source)
	}

	/// Which modes a tab's file can be shown in.
	///
	/// Asked of the *tab* rather than of the URL, because one file's answer is not in
	/// its name: a `.yaml` has a rendered form when it is a go3mf recipe, and the tab
	/// is where that was decided, once, when it opened.
	func availableModes(for tab: Tab) -> [PreviewMode] {
		FilePreview.availableModes(for: tab.url, facts: tab.previewFacts)
	}

	/// The view for a tab in a given mode, with the divider a session remembered
	/// or down the middle.
	private func makeContentView(
		for tab: Tab, mode: PreviewMode, dividerFraction: Double? = nil
	) -> NSView {
		let source = tab.sourceView
		guard mode != .source else { return source ?? tab.contentView }

		let preview = makePreview(for: tab)
		guard mode.isSplit, let source else { return preview }

		// Source first: reading order, and the thing being edited stays where
		// it was whichever way the pane is divided.
		let split = PreviewSplitView()
		split.isVertical = mode.splitsSideBySide
		split.dividerStyle = .thin
		split.addArrangedSubview(source)
		split.addArrangedSubview(preview)

		// The split has no size yet — it is not in a window — so the fraction is
		// left with it and spent at its first real layout. This used to be a
		// half-and-half computed a runloop turn later, which found a size only
		// because the tab happened to be the one in front; the split built for a
		// tab behind it measured zero, gave up, and lived on whatever
		// `adjustSubviews` had left.
		//
		// Half for a model too, which 0483 tried to change and measured its way
		// back from. A mesh looks like it wants the larger half — it is being
		// turned around, where a line of OpenSCAD is narrow — and at 0.4 the file
		// that asked for this feature was clipped while the viewport around the
		// part had margins to spare. A 3D view zooms to fit, so it degrades
		// gracefully with less width; text stops at a hard edge. And the longest
		// line of the median `.scad` in the owner's own 493 of them is 93 columns,
		// which no fraction of a 970 pt pane fits — so the divider is not the
		// lever, and half is the answer for the same reason it is everywhere else.
		split.wantedFraction = dividerFraction.map { CGFloat($0) } ?? 0.5
		return split
	}

	/// The rendered form of a file, whichever kind it has.
	private func makePreview(for tab: Tab) -> NSView {
		switch FilePreview.kind(for: tab.url, facts: tab.previewFacts) {
		case .model:
			// A provisional tab waits before rendering; one somebody committed to
			// does not. `makeModelView` says why the wait exists at all.
			//
			// A go3mf recipe arrives here too, as the `.yaml` it is: GoSTL runs
			// `go3mf build` on it into a temporary directory of its own, watches the
			// recipe, and rebuilds when it changes. None of that is here, and since
			// 0.22.0 none of it writes into the project either.
			//
			// A Cadova model does not, and cannot: there is no file for the viewer
			// to open until a program has been built and run. Its pane does that
			// first and hosts the same viewer afterwards — see `CadovaPreviewView`.
			let waiting = tab.isPreview ? Self.provisionalRenderDelay : 0
			if let cadova = tab.cadova {
				let view = CadovaPreviewView(model: cadova)
				view.startAfter = waiting
				return view
			}
			return makeModelView(for: tab.url, startAfter: waiting)
		case .image:
			return ImageFileView(url: tab.url)
		case .plantuml:
			return makeDiagramView(for: tab)
		case .mermaid:
			return makeMermaidView(for: tab)
		case .drawio:
			return makeDrawioView(for: tab)
		case .pdf:
			return PdfFileView(url: tab.url)
		case .markdown, .none:
			return makePreviewView(for: tab)
		}
	}

	private func makePreviewView(for tab: Tab) -> NSView {
		let textView = MarkdownPreviewTextView()
		// Which document this is, and where its text is — the pane's own `Export ▸`
		// writes the diagrams in it beside it, and draws the buffer rather than
		// what is on disk, exactly as the `.mmd` pane does.
		textView.fileURL = tab.url
		textView.markdownSource = { [weak tab] in tab?.document?.rope.string }
		textView.isEditable = false
		textView.isSelectable = true
		textView.drawsBackground = true
		textView.backgroundColor = Theme.current.editorBackground
		textView.textColor = Theme.current.editorText
		textView.linkTextAttributes = [
			.foregroundColor: Theme.current.gitModified,
			.underlineStyle: NSUnderlineStyle.single.rawValue,
			.cursor: NSCursor.pointingHand,
		]
		textView.textContainerInset = NSSize(width: 28, height: 24)
		textView.isRichText = true

		let scrollView = NSScrollView()
		scrollView.documentView = textView
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		scrollView.scrollerStyle = .overlay

		// Width-tracking so text reflows with the pane.
		textView.autoresizingMask = [.width]
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.textContainer?.widthTracksTextView = true

		renderPreview(into: textView, tab: tab)

		// Keep the preview current while the source is edited.
		tab.document?.onSyntaxUpdated = { [weak self, weak tab, weak textView] in
			guard let self, let tab, let textView, tab.isShowingMarkdownPreview else { return }
			self.schedulePreviewRefresh(textView: textView, tab: tab)
		}

		// A ```mermaid fence is drawn in a web view and arrives after the page it
		// belongs on has already been laid out. The document is rendered again
		// when it does — which finds the drawing in the cache this time and puts
		// it where the "drawing this diagram" line was. The refresh is the same
		// debounced one the typing uses, so a document of twenty fences settles in
		// a handful of renders rather than twenty, and the scroll position is kept
		// across each of them.
		textView.whenDiagramDrawn { [weak self, weak tab, weak textView] in
			guard let self, let tab, let textView, tab.isShowingMarkdownPreview else { return }
			self.schedulePreviewRefresh(textView: textView, tab: tab)
		}
		return scrollView
	}

	/// The diagram a PlantUML file describes, kept current while it is edited.
	private func makeDiagramView(for tab: Tab) -> NSView {
		let view = PlantUMLPreviewView(projectRoot: project?.root)
		// Which file this is a picture of: the pane's own menu writes the picture
		// beside it, and a pane that did not know would have nowhere to write.
		view.fileURL = tab.url
		if let document = tab.document {
			view.show(document.rope.string)

			// Every edit, not every reparse: PlantUML has no grammar here, so
			// there is no parser whose finishing could be waited for. Drawing
			// means starting a JVM, so the view debounces on top of this.
			document.onTextChanged = { [weak view, weak document] in
				guard let view, let document else { return }
				view.show(document.rope.string)
			}
		}
		return view
	}

	/// The diagram a Mermaid file describes, kept current while it is edited.
	///
	/// The same shape as the PlantUML one beside it. What is different is
	/// underneath: nothing is discovered, nothing is fetched, and the pane needs
	/// no project to find a tool in — Mermaid is in the app.
	private func makeMermaidView(for tab: Tab) -> NSView {
		let view = MermaidPreviewView()
		view.fileURL = tab.url
		if let document = tab.document {
			view.show(document.rope.string)
			document.onTextChanged = { [weak view, weak document] in
				guard let view, let document else { return }
				view.show(document.rope.string)
			}
		}
		return view
	}

	/// A `.drawio` open in draw.io's own editor.
	///
	/// The other two diagram panes are given the text and draw a picture of it.
	/// This one is given the text and *is* the editor, so the wiring runs both
	/// ways: the document goes in, and what somebody draws comes back out into
	/// the same `TextDocument` every other tab uses. Nothing else in this
	/// controller knows the difference — the dot, ⌘S, the close prompt and
	/// auto-save all read `document.isDirty` as they always did.
	private func makeDrawioView(for tab: Tab) -> NSView {
		let view = DrawioPreviewView()
		view.fileURL = tab.url
		view.document = tab.document
		if let document = tab.document {
			view.show(document.rope.string)
			// Somebody else wrote the file — a `git checkout` on a branch with a
			// different diagram. The editor is given the new document, and
			// whatever was in draw.io's undo stack goes with it, which is the
			// same trade the text editor makes when it reloads.
			document.onTextChanged = { [weak view, weak document] in
				guard let view, let document else { return }
				view.show(document.rope.string)
			}
		}
		view.onEdited = { [weak self] in self?.refreshTabBar() }
		view.onSaveRequested = { [weak self] in self?.save() }
		return view
	}

	/// The diagram pane the file in front is showing, when it is showing one.
	///
	/// Found rather than kept: the pane may be the tab's whole content or one
	/// half of a split, and which of those it is changes with the preview mode.
	/// Either kind of diagram, because everything asking this — the Export
	/// command, the menu it offers — wants the pane rather than the tool.
	var diagramPreview: DiagramPaneView? { activeTab.flatMap { Self.pane(in: $0.contentView) } }

	/// The Cadova pane the file in front is showing, when it is showing one.
	///
	/// Found the same way and for the same reason as `diagramPreview`: it is half
	/// of a split or the whole of a tab, depending on the preview mode.
	var cadovaPreview: CadovaPreviewView? { activeTab.flatMap { Self.pane(in: $0.contentView) } }

	/// The picture pane the file in front is showing, when it is showing one.
	///
	/// A PNG is a tab's whole content and an SVG is half a split — the same two
	/// shapes a diagram comes in, and the same reason this is a search rather
	/// than something kept.
	var imagePreview: ImageFileView? { activeTab.flatMap { Self.pane(in: $0.contentView) } }

	/// The first pane of a kind anywhere under a view.
	///
	/// One walk rather than one per kind: the three above differ only in the type
	/// they are looking for, and a fourth copy of the same six lines is how the
	/// three of them come to disagree about what "under" means.
	private static func pane<Found: NSView>(in view: NSView) -> Found? {
		if let pane = view as? Found { return pane }
		for subview in view.subviews {
			if let found: Found = pane(in: subview) { return found }
		}
		return nil
	}

	/// What the tab in front actually is, when something looking for a pane in it
	/// did not find one.
	///
	/// **A driver that can only say "not found" lies by omission**, and 0507 is
	/// what that costs: `--cadova-watch` said `no cadova pane in the tab in front`
	/// for a file that had one built for it, and the report was believed for long
	/// enough to be written into an item as evidence. It was true and useless —
	/// the tab in front was not the file at all. So the negative answer now comes
	/// with the tab it was asked about, the mode that tab is in, and the classes
	/// in its content view, which between them say *which* of the possible reasons
	/// it is.
	/// Opens Quick Look on a binary-file notice, and says whether the panel came
	/// up — which is the half that cannot be photographed, since the panel is a
	/// window of its own and the shot is of this one.
	func quickLookForTesting() -> String {
		guard let tab = activeTab else { return "no tab" }
		guard let notice: FileNoticeView = Self.pane(in: tab.contentView) else {
			return "no notice view in \(tab.url.lastPathComponent)"
		}
		notice.showQuickLook()
		// **Asked a moment later, not in this turn.** `makeKeyAndOrderFront`
		// starts the handshake — the panel becomes key, then walks the responder
		// chain asking who wants to control it — and none of that has happened
		// by the time this line runs. Read synchronously it says `dataSource=none`
		// about a panel that is about to be handed over perfectly well.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak notice] in
			let panel = QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil
			print("QUICKLOOK settled: panel=\(panel?.isVisible == true ? "open" : "not open") "
				+ "controlling=\(panel?.dataSource === notice ? "the notice" : "somebody else") "
				+ "showing=\((panel?.currentPreviewItem?.previewItemURL?.lastPathComponent) ?? "nothing")")
			fflush(stdout)
		}
		return "asked for \(notice.urlForTesting.lastPathComponent)"
	}

	func doubleClickTabForTesting(index: Int) -> String {
		tabBar.doubleClickForTesting(index: index)
	}

	var activeTabDescriptionForTesting: String {
		let open = "open=[" + tabs.map(\.url.lastPathComponent).joined(separator: " ") + "]"
		guard let tab = activeTab else {
			return "no active tab (\(tabs.count) tabs, group \(groupID.uuidString.prefix(4))) \(open)"
		}
		return "tab=\(tab.url.path) mode=\(tab.previewMode) "
			+ "cadova=\(tab.cadova?.product ?? "none") \(open) "
			+ "content=[\(Self.classes(in: tab.contentView).joined(separator: " "))]"
	}

	/// The class names in a view tree, outermost first, for a driver's report.
	private static func classes(in view: NSView, depth: Int = 0) -> [String] {
		// Two levels of subviews is enough to tell a split from a scroll view and
		// far short of the hundreds a code view holds.
		guard depth < 3 else { return [] }
		return [String(describing: type(of: view))]
			+ view.subviews.flatMap { classes(in: $0, depth: depth + 1) }
	}

	/// The rendered Markdown pane the file in front is showing, when it is
	/// showing one.
	///
	/// Found the same way and for the same reason as `diagramPreview`: a Markdown
	/// document full of ```` ```mermaid ```` fences has an `Export ▸` of its own,
	/// and the pane it hangs on is the tab's whole content or half of a split
	/// depending on the preview mode.
	var markdownPreview: MarkdownPreviewTextView? {
		activeTab.flatMap { Self.markdownPane(in: $0.contentView) }
	}

	private static func markdownPane(in view: NSView) -> MarkdownPreviewTextView? {
		if let pane = view as? MarkdownPreviewTextView { return pane }
		for subview in view.subviews {
			if let found = markdownPane(in: subview) { return found }
		}
		return nil
	}

	private func renderPreview(into textView: NSTextView, tab: Tab) {
		guard let document = tab.document else { return }
		let rendered = MarkdownRenderer.render(
			document.rope.string,
			// Relative links and images resolve against the file's directory.
			baseURL: tab.url.deletingLastPathComponent()
		)
		textView.textStorage?.setAttributedString(rendered)
	}

	private var previewRefreshWork: DispatchWorkItem?

	/// Debounced: re-rendering the whole document on every keystroke would undo
	/// the point of the incremental editor.
	private func schedulePreviewRefresh(textView: NSTextView, tab: Tab) {
		previewRefreshWork?.cancel()
		let work = DispatchWorkItem { [weak textView, weak tab] in
			guard let textView, let tab else { return }
			let offset = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
			self.renderPreview(into: textView, tab: tab)
			// Preserve the scroll position across the re-render.
			textView.enclosingScrollView?.contentView.scroll(to: offset)
		}
		previewRefreshWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
	}

	/// True when the active tab is markdown, so the UI can offer the toggle.
	var canPreviewMarkdown: Bool { activeTab?.isMarkdown ?? false }
	var isShowingMarkdownPreview: Bool { activeTab?.isShowingMarkdownPreview ?? false }

	/// How long a provisional tab's model pane waits before it renders anything.
	///
	/// The same 0.4 s `PlantUMLPreviewView` debounces by, and for the same
	/// reason: arrowing down a directory gives each file a provisional tab that
	/// lives for as long as the next keypress takes, and a walk must not cost one
	/// render per row. 0470 measured that shape for usages and found the traffic
	/// was one `didOpen` per *file crossed* — which is the good answer there and
	/// the bad one here, because every row of a directory of models is a
	/// different file.
	private static let provisionalRenderDelay: TimeInterval = 0.4

	/// A tab showing a 3D model, hosted from GoSTL.
	///
	/// The viewer is a SwiftUI view from a package rather than a second
	/// application, so it lives in a tab beside the code like any other file.
	/// Hosts the 3D viewer on the editor's own background.
	///
	/// A SwiftUI view leaves its unpainted regions transparent, which against
	/// the window shows through as a different shade from the code beside it.
	/// The container settles that without GoSTL having to know about it.
	///
	/// The hosting view is built by the container rather than here, once the pane
	/// has actually been on screen for `startAfter`. Loading a model is not free
	/// and a `.scad` is the expensive end of it — GoSTL runs OpenSCAD, and it
	/// does so on the main actor, so however long the render takes is time this
	/// window is not drawing. Since 0483 that happens without being asked for,
	/// which is only affordable if it happens once for the file somebody stopped
	/// at rather than once for every file they went past.
	private func makeModelView(for fileURL: URL, startAfter: TimeInterval = 0) -> NSView {
		let container = ModelContainerView(color: Theme.current.editorBackground)
		container.startAfter = startAfter
		container.modelPath = fileURL.path
		container.makeViewer = { [weak container] in
			// The viewer sits in a pane rather than a window of its own: it takes
			// the editor's background so the split reads as one surface, and keeps
			// its menu panel folded away, since the panel is wider than the pane
			// often is.
			let hosting = NSHostingView(rootView: ContentView(
				fileURL: fileURL,
				embedding: ContentView.EmbeddingOptions(
					backgroundColor: Theme.current.editorBackground,
					showsMenuPanel: false,
					// Kept so a screenshot of this window can include the model.
					snapshotHandle: { [weak container] provider in container?.snapshot = provider }
				)
			))

			// Kept out of Auto Layout on purpose. NSHostingView publishes the
			// SwiftUI view's size as constraints and invalidates them from inside
			// the window's own constraint pass; splitting the editor re-parents the
			// view during exactly that pass, and AppKit raises rather than
			// re-entering it. The container sizes it directly instead, which is how
			// the rest of the editor lays out anyway.
			hosting.sizingOptions = []
			hosting.translatesAutoresizingMaskIntoConstraints = true
			return hosting
		}
		return container
	}

	/// Shows a view of the app's own in a tab, or brings back the one that is
	/// already open.
	///
	/// A page that wants to follow the zoom says so by being a `ScalingPage`;
	/// one that does not is left exactly as it is.
	///
	/// The URL is a name rather than a file: two pages must not collide, and a
	/// tab is found by it.
	@discardableResult
	func openPage(_ view: NSView, title: String, identifier: String, symbol: String = "square.grid.2x2") -> NSView {
		let url = URL(fileURLWithPath: "/ideai/page/" + identifier)
		if let index = tabs.firstIndex(where: { $0.pageTitle != nil && $0.url == url }) {
			activeIndex = nil
			activate(index: index, focusEditor: false)
			return tabs[index].contentView
		}

		let tab = Tab(url: url, document: nil, codeView: nil, contentView: view, isPreview: false)
		tab.pageTitle = title
		tab.pageSymbol = symbol
		tabs.append(tab)
		activeIndex = nil
		activate(index: tabs.count - 1, focusEditor: false)
		refreshTabBar()
		return view
	}

	/// The open page with this identifier, if it is open, whatever kind it is.
	func page(identifier: String) -> NSView? {
		let url = URL(fileURLWithPath: "/ideai/page/" + identifier)
		return tabs.first { $0.pageTitle != nil && $0.url == url }?.contentView
	}

	/// A tab showing a picture.
	///
	/// An SVG keeps its source: the control offers it and a split, since it is
	/// a drawing somebody may well have written by hand. A PNG has none, so the
	/// tab is the picture and nothing else.
	private func makeImageTab(for fileURL: URL, preview: Bool) -> Tab {
		let tab = Tab(
			url: fileURL,
			document: nil,
			codeView: nil,
			contentView: ImageFileView(url: fileURL),
			isPreview: preview
		)
		tab.previewMode = .preview
		return tab
	}

	/// A tab showing a PDF.
	///
	/// Like a picture's: the tab is the document and nothing else, since a PDF
	/// has no source half to offer and nothing here writes one.
	private func makePdfTab(for fileURL: URL, preview: Bool) -> Tab {
		let tab = Tab(
			url: fileURL,
			document: nil,
			codeView: nil,
			contentView: PdfFileView(url: fileURL),
			isPreview: preview
		)
		tab.previewMode = .preview
		return tab
	}

	/// A tab that is nothing but the model — a mesh, which has no source half.
	///
	/// The wait applies here too. A `.stl` is parsed rather than rendered, so it
	/// is the cheap end of this, but a directory of them is walked the same way
	/// and each row still costs a Metal device and a spatial index.
	private func makeModelTab(for fileURL: URL, preview: Bool) -> Tab {
		let tab = Tab(
			url: fileURL,
			document: nil,
			codeView: nil,
			contentView: makeModelView(
				for: fileURL, startAfter: preview ? Self.provisionalRenderDelay : 0
			),
			isPreview: preview
		)
		tab.previewMode = .preview
		return tab
	}

	/// A tab for a file that cannot be shown as text.
	private func makeNoticeTab(for fileURL: URL, reason: String, preview: Bool) -> Tab {
		let notice = FileNoticeView(url: fileURL, reason: reason)
		let tab = Tab(url: fileURL, document: nil, codeView: nil, contentView: notice, isPreview: preview)

		notice.onOpenExternally = { NSWorkspace.shared.open(fileURL) }
		notice.onPreviewModel = { MainWindowController.previewModel(at: fileURL) }
		notice.onOpenHexEditor = { [weak self, weak tab] in
			guard let self, let tab else { return }
			self.showHexEditor(for: tab)
		}
		return tab
	}

	/// Swaps a notice tab's content for a hex dump of the same file.
	private func showHexEditor(for tab: Tab) {
		guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }

		// Mapped rather than read: a 100 MB file costs no resident memory until
		// the visible rows are actually touched.
		guard let data = try? Data(contentsOf: tab.url, options: .mappedIfSafe) else {
			return
		}

		let viewer = HexViewerController(data: data)
		tab.contentView = viewer.scrollView
		// Inspecting a file is a commitment to the tab, same as editing one.
		tab.isPreview = false

		if activeIndex == index {
			activeIndex = nil
			activate(index: index, focusEditor: false)
		} else {
			refreshTabBar()
		}
	}

	private var activeTab: Tab? {
		guard let activeIndex, tabs.indices.contains(activeIndex) else { return nil }
		return tabs[activeIndex]
	}

	// MARK: - Activation

	private func activate(index: Int, focusEditor: Bool) {
		guard tabs.indices.contains(index) else { return }

		// Whether the keyboard is in the tab about to be taken off screen.
		//
		// Item 523, and the half of it that is not about the results list.
		// `removeFromSuperview` on a view that holds the window's first responder
		// does not move the responder along — it resets it to the **window**,
		// which is nobody at all, and every keystroke after that reaches nothing.
		// It is invisible whenever `focusEditor` is true, because the branch at
		// the bottom puts a responder back; it is exactly visible when it is
		// false, which is every open that is deliberately not meant to move the
		// keyboard. Measured with the caret in the editor and a result row
		// clicked: `who` said `NSWindow`.
		//
		// Asked before the removal, because after it the answer is gone.
		let keyboardWasInTheTabLeaving = (view.window?.firstResponder as? NSView)
			.map { $0.isDescendant(of: contentArea) } ?? false

		// Swap the installed content view; the outgoing one keeps its state.
		contentArea.subviews.forEach { $0.removeFromSuperview() }

		let tab = tabs[index]
		activeIndex = index

		let content = tab.contentView
		content.translatesAutoresizingMaskIntoConstraints = false
		contentArea.addSubview(content)
		NSLayoutConstraint.activate([
			content.topAnchor.constraint(equalTo: contentArea.topAnchor),
			content.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
			content.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
			content.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
		])

		// A binary tab has no language to report.
		statusLanguage = tab.document?.displayLanguageName
		// Nor a caret. The indicator is one control shared by the whole group,
		// so a tab arriving without saying where its caret is leaves the line
		// the *previous* tab was on next to the new tab's language. Easiest to
		// see with `abydos deep.txt:150 main.go`, which put "150:1 Go" beside a
		// two-line file — but any click between two tabs did the same.
		tab.codeView?.reportCaretPosition()
		// Find belongs to the tab, so the bar shows this one's. Placed here, with
		// the other things a tab brings with it, and deliberately clear of the
		// responder handling below — where the keyboard goes after a switch is
		// settled twice already, with the measurements in those comments.
		restoreFind(for: tab)
		onStatusChanged?(self)
		refreshServerState()
		updateChrome()
		refreshTabBar()
		onActivated?(self)

		if focusEditor {
			// A notice tab has no code view to focus.
			view.window?.makeFirstResponder(tab.codeView ?? tab.contentView)
		} else if keyboardWasInTheTabLeaving {
			// Nobody asked for the keyboard to move, and the removal above took it
			// from the view that had it. Putting it in the tab now showing is what
			// "do not move the keyboard" meant: it was in this editor before and it
			// is in this editor after. This can only ever *keep* the keyboard in
			// the editor — a responder outside `contentArea` never reaches here —
			// so a results row clicked with the keyboard in the list is untouched,
			// which is item 510's rule and must stay true.
			view.window?.makeFirstResponder(tab.codeView ?? tab.contentView)
		}
		onActiveFileChanged?(tab.url)
	}

	private func promoteToPermanent(index: Int) {
		guard tabs.indices.contains(index) else { return }
		tabs[index].isPreview = false
		activate(index: index, focusEditor: true)
	}

	private func refreshTabBar() {
		let items = tabs.map { tab in
			let scratch = ScratchFiles.isScratch(tab.url)
			return EditorTabItem(
				url: tab.url,
				title: tab.pageTitle
					?? (scratch ? ScratchFiles.title(for: tab.url) : tab.url.lastPathComponent),
				// A scratch keeps its dot whether or not it is written out. It
				// has nowhere in the project it belongs to, and the dot is what
				// says so — the same mark Sublime and Zed leave on one.
				isDirty: tab.isDirty || scratch,
				isPreview: tab.isPreview,
				subtitle: tab.pageTitle != nil
					? ""
					: tab.diffCommit ?? (tab.isDiff ? "diff" : (scratch ? "scratch" : relativeDirectory(for: tab.url))),
				pageSymbol: tab.pageSymbol,
				isExternal: tab.pageTitle == nil && !scratch && !tab.isDiff && isOutsideProject(tab.url)
			)
		}
		tabBar.setItems(items, activeIndex: activeIndex)
		onTabsChanged?()

		// The control belongs to the active tab: a file with no rendered form
		// shows none, so the strip does not offer something that does nothing.
		if let tab = activeTab, !tab.isDiff {
			let modes = availableModes(for: tab)
			tabBar.setPreview(
				// One mode is no choice: a PNG and a binary mesh each have only
				// their rendered form, and a control whose menu holds the item
				// that is already chosen is a button that does nothing.
				modes: modes.count > 1 ? modes : [],
				current: tab.previewMode
			)
		} else {
			tabBar.setPreview(modes: [], current: .source)
		}
	}

	private func relativeDirectory(for url: URL) -> String {
		guard let root = project?.root, !isOutsideProject(url) else { return outsideProject(url) }
		let base = FilePath.canonical(root)
		let path = FilePath.canonical(url)
		let relative = String(path.dropFirst(base.count + 1))
		return (relative as NSString).deletingLastPathComponent
	}

	/// Whether a file lives outside the project that is open.
	func isOutsideProject(_ url: URL) -> Bool {
		guard let root = project?.root else { return true }
		return !FilePath.canonical(url).hasPrefix(FilePath.canonical(root) + "/")
	}

	/// A file that is not in the project, said so.
	///
	/// Without this it reads like a file at the project's root — same tab, same
	/// blank subtitle — and editing the wrong copy of a file is a mistake that
	/// takes a while to notice.
	private func outsideProject(_ url: URL) -> String {
		let directory = url.deletingLastPathComponent().path
		let home = NSHomeDirectory()
		let shown = directory.hasPrefix(home + "/") || directory == home
			? "~" + directory.dropFirst(home.count)
			: directory[...]
		return "↗ " + shown
	}

	// MARK: - Closing

	private func closeTab(at index: Int) {
		guard tabs.indices.contains(index) else { return }
		let tab = tabs[index]

		// With auto save on, closing must not interrogate the user — it just
		// writes, which is the whole point of the setting.
		if tab.isDirty, tab.document?.autoSaveIfNeeded() != true, !confirmDiscard(for: tab) {
			return
		}

		removeTab(at: index)
		discardIfEmptyScratch(tab)
	}

	/// Takes a tab out and settles on what to show instead, asking nothing.
	private func removeTab(at index: Int) {
		guard tabs.indices.contains(index) else { return }

		announceClosed(tabs[index])
		teardown(tabs[index])
		tabs.remove(at: index)

		if tabs.isEmpty {
			activeIndex = nil
			contentArea.subviews.forEach { $0.removeFromSuperview() }
			updateChrome()
			refreshTabBar()
			onActiveFileChanged?(nil)
			onBecameEmpty?(self)
			return
		}

		// Prefer the tab that slid into this slot, else the one before it.
		let next = min(index, tabs.count - 1)
		activeIndex = nil
		activate(index: next, focusEditor: false)
	}

	/// Returns true if the caller should proceed with closing.
	private func confirmDiscard(for tab: Tab) -> Bool {
		let alert = NSAlert()
		alert.messageText = "Save changes to \(tab.url.lastPathComponent)?"
		alert.informativeText = "Your changes will be lost if you don't save them."
		alert.addButton(withTitle: "Save")
		alert.addButton(withTitle: "Discard")
		alert.addButton(withTitle: "Cancel")

		switch alert.runModal() {
		case .alertFirstButtonReturn:
			do {
				try tab.document?.save()
				return true
			} catch {
				Toast.post("Could not save \(tab.url.lastPathComponent)", detail: error.localizedDescription)
				return false
			}
		case .alertSecondButtonReturn:
			return true
		default:
			return false
		}
	}

	/// Tells the server about a file this group has stopped showing.
	///
	/// A file nobody has open is one the server can stop thinking about. Said
	/// once per tab that goes, and only when no other tab here is still showing
	/// the same file.
	private func announceClosed(_ closing: Tab) {
		guard let languageId = closing.document?.languageId,
		      let root = serverRoot(for: closing),
		      !tabs.contains(where: { $0 !== closing && $0.url == closing.url })
		else { return }
		LanguageService.shared.closed(
			url: closing.url, languageId: languageId, project: root
		)
	}

	private func teardown(_ tab: Tab) {
		if let scrollView = tab.contentView as? NSScrollView {
			NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
		}
		tab.document?.onSyntaxUpdated = nil
		tab.contentView.removeFromSuperview()
	}

	private func presentUnopenable(_ url: URL, reason: String) {
		Toast.post("Cannot open \(url.lastPathComponent)", detail: reason, kind: .warning)
	}

	// MARK: - Commands

	func save() {
		guard let tab = activeTab else { return }
		// A `.drawio` is edited by draw.io rather than by this app, and draw.io
		// reports a change a fraction of a second after it happens. That is soon
		// enough for the dot but not for ⌘S, which somebody may press while
		// still holding the shape they dragged — so the editor is asked what it
		// has before the file is written. Every other tab writes straight away,
		// exactly as it always did.
		if let pane: DrawioPreviewView = Self.pane(in: tab.contentView) {
			Task { @MainActor in
				await pane.flush()
				self.write(tab)
			}
			return
		}
		write(tab)
	}

	private func write(_ tab: Tab) {
		do {
			try tab.document?.save()
			refreshTabBar()
			told(tab, wasSaved: true)
		} catch {
			Toast.post("Could not save \(tab.url.lastPathComponent)", detail: error.localizedDescription)
		}
	}

	/// Tells the language server the file is now on disk.
	///
	/// **`didChange` is not `didSave`, and nothing was sending the second one for
	/// a save somebody made.** `LanguageService.saved` had exactly one caller,
	/// `reloadExternallyChangedFiles` — so a server was told a file had been
	/// saved when *something else* wrote it, and never when the person at the
	/// keyboard did. For most servers that is invisible: they answer about the
	/// text they were given either way, which is why it went unnoticed for as
	/// long as it did.
	///
	/// For jdtls it is the difference between a build that compiles and one that
	/// does nothing. Eclipse builds *resources*, not dirty working copies, so
	/// `vscode.java.buildWorkspace` after a save with no `didSave` recompiled
	/// nothing and answered "Build completed" — measured on the hot-swap example,
	/// where the source was saved at 05:52:38 and `target/classes` still held a
	/// class file from 05:51:04 with the old string in it.
	private func told(_ tab: Tab, wasSaved: Bool) {
		guard wasSaved, let document = tab.document, let languageId = document.languageId,
		      let root = serverRoot(for: tab)
		else { return }
		let url = tab.url
		let snapshot = document.rope
		Task { @MainActor in
			let text = await withCheckedContinuation { continuation in
				EditorViewController.languageTextQueue.async {
					continuation.resume(returning: snapshot.string(in: 0..<snapshot.byteCount))
				}
			}
			LanguageService.shared.saved(
				url: url, languageId: languageId, text: text, project: root
			)
		}
	}

	func closeActiveTab() {
		guard let activeIndex else { return }
		closeTab(at: activeIndex)
	}

	func selectNextTab(offset: Int) {
		guard !tabs.isEmpty, let activeIndex else { return }
		let next = (activeIndex + offset + tabs.count) % tabs.count
		activate(index: next, focusEditor: true)
	}

	/// Returns keyboard focus to the code view, used when the panel closes.
	func focusActiveEditor() {
		guard let tab = activeTab else { return }
		view.window?.makeFirstResponder(tab.codeView ?? tab.contentView)
	}

	/// Shows or hides who last touched each line, for the file in front.
	///
	/// Per editor rather than for all of them: blame is something you turn on
	/// to answer a question about one file, and a column of names beside every
	/// other file afterwards is not what anybody asked for.
	func toggleBlame() {
		guard let tab = activeTab, let codeView = tab.codeView else { return }
		let url = tab.url
		let showing = !codeView.isBlameVisible
		codeView.setBlameVisible(showing)
		guard showing else { return }

		guard let root = project?.root else { return }
		Task { @MainActor in
			let lines = await GitBlame.lines(for: url, in: root)
			// The tab may have been closed, or blame turned off again, while
			// git was reading a file with ten thousand lines in it.
			guard codeView.isBlameVisible else { return }
			codeView.setBlame(lines)
			if lines.isEmpty {
				Toast.post(
					"Nothing to blame",
					detail: "\(url.lastPathComponent) is not in this repository, or has never been committed.",
					kind: .information
				)
			}
		}
	}

	var isBlameVisible: Bool { activeTab?.codeView?.isBlameVisible ?? false }

	/// Flips soft wrap for every open editor and remembers the choice.
	func toggleWordWrap() {
		let enabled = !Settings.shared.wordWrap
		Settings.shared.wordWrap = enabled
		for tab in tabs { tab.codeView?.setWordWrap(enabled) }
	}

	func collapseAllFolds() { activeTab?.codeView?.collapseAllFolds() }
	func expandAllFolds() { activeTab?.codeView?.expandAllFolds() }

	var hasOpenFiles: Bool { !tabs.isEmpty }

	/// Asked for the whole window, by a double-click on a tab that is already
	/// permanent. The window owns the panes, so it owns the answer.
	var onMaximize: (() -> Void)?

	/// Whether the editor has the window, for the strip's own control.
	func setMaximized(_ maximized: Bool) { tabBar.setMaximized(maximized) }

	/// Told where the editor went, and where it stood before.
	var onNavigated: ((NavigationHistory.Place?, NavigationHistory.Place) -> Void)?
	/// Raised while an outer open reports the jump itself, with the line it
	/// asked for rather than the one the file happened to open at.
	private var isReportingSuppressed = 0

	private func reportNavigation(
		from departure: (url: URL, line: Int)?,
		to arrival: (url: URL, line: Int)
	) {
		guard isReportingSuppressed == 0 else { return }
		onNavigated?(
			departure.map { NavigationHistory.Place(file: $0.url, line: $0.line) },
			NavigationHistory.Place(file: arrival.url, line: arrival.line)
		)
	}

	/// The file and line the caret is in, for recording where you were before
	/// jumping somewhere else.
	var currentPlace: (url: URL, line: Int)? {
		guard let tab = activeTab else { return nil }
		return (tab.url, (tab.codeView?.caretLine ?? 0) + 1)
	}

	/// What this group has open, as plain values.
	func captureSession() -> ProjectSession {
		// Pages are left out: they are the app's own views, not files, and a
		// path like /ideai/page/launch is nothing to reopen.
		ProjectSession(
			files: tabs.filter { $0.pageTitle == nil }.map { tab in
				ProjectSession.OpenFile(
					path: tab.url.path,
					line: (tab.codeView?.caretLine ?? 0) + 1,
					isPreview: tab.isPreview,
					// Only for a file that has a rendered form. Every other tab is
					// `.source` and always will be, and writing that down for each
					// of them says nothing.
					previewMode: FilePreview.hasPreview(
						tab.url, facts: tab.previewFacts
					) ? tab.previewMode : nil,
					dividerFraction: tab.dividerFraction
				)
			},
			activePath: activeTab?.url.path
		)
	}

	/// Puts back what a project had open, without disturbing anything else.
	func restore(_ session: ProjectSession) {
		closeAllTabs()
		for file in session.files {
			let url = URL(fileURLWithPath: file.path)
			guard FileManager.default.fileExists(atPath: file.path) else { continue }
			open(
				fileURL: url,
				focusEditor: false,
				preview: file.isPreview,
				mode: file.previewMode,
				dividerFraction: file.dividerFraction
			)
			if file.line > 1 {
				// Deferred: a document that has just been opened has not laid
				// out, so scrolling to a line now would measure against nothing.
				DispatchQueue.main.async { [weak self] in
					self?.tabs.last(where: { $0.url.path == file.path })?
						.codeView?.reveal(line: file.line - 1)
				}
			}
		}
		if let activePath = session.activePath,
		   let index = tabs.firstIndex(where: { $0.url.path == activePath }) {
			activate(index: index, focusEditor: false)
		}
	}

	/// Closes the tabs on one side of a tab, or all but it.
	///
	/// Right to left, always: closing a tab shifts everything after it, and a
	/// loop that walks forwards would skip every other one.
	private func closeTabs(keeping index: Int) {
		guard let kept = tabs[safe: index] else { return }
		for position in tabs.indices.reversed() where tabs[position] !== kept {
			closeTab(at: position)
		}
	}

	private func closeTabs(before index: Int) {
		guard let anchor = tabs[safe: index] else { return }
		for position in (0..<index).reversed() where tabs.indices.contains(position) {
			guard tabs[position] !== anchor else { continue }
			closeTab(at: position)
		}
	}

	private func closeTabs(after index: Int) {
		guard tabs.indices.contains(index) else { return }
		for position in tabs.indices.reversed() where position > index {
			closeTab(at: position)
		}
	}

	/// Runs what a tab's menu runs, for the capture harness.
	func closeTabsForTesting(_ command: String, at index: Int) {
		switch command {
		case "others": closeTabs(keeping: index)
		case "left": closeTabs(before: index)
		case "right": closeTabs(after: index)
		case "all": closeAllTabs()
		default: closeTab(at: index)
		}
	}

	/// What the tab bar shows, in order. A provisional tab is marked, because
	/// "one tab for the whole list" is a claim about which kind of tab it is.
	var tabTitlesForTesting: [String] {
		tabs.map { ($0.pageTitle ?? $0.url.lastPathComponent) + ($0.isPreview ? "~" : "") }
	}

	/// Closes every tab, for swapping one project's editors for another's.
	func closeAllTabs() {
		while !tabs.isEmpty { closeTab(at: tabs.count - 1) }
	}

	/// Presses a key with modifiers, the way a keyboard would.
	///
	/// Through `keyDown` rather than by calling the command directly: what is
	/// being checked is that the system's key bindings reach the editor, not
	/// that the editor has a method with the right name.
	///
	/// The arrows, Page Up and Page Down, and the letters the emacs bindings
	/// use are all in here together. They are the same kind of key to a text
	/// view — something AppKit turns into a selector — and a second function
	/// differing only in a key code would be the one somebody forgets to keep
	/// up with this one. It was called `simulateArrow` while it knew only the
	/// six navigation keys, and ⌃B could not be pressed through it at all.
	func simulateKey(_ key: String, modifiers: NSEvent.ModifierFlags) {
		// Guarded like the typing verbs, and for the same reason: `--emacs-nav`
		// is mostly motion, but ⌃O opens a line and ⌃K takes one away. A verb
		// that reads as navigation still changes a file.
		guard let codeView = codeViewToDrive("--emacs-nav") else { return }
		view.window?.makeFirstResponder(codeView)

		let navigationKeys: [String: (code: Int, character: Int)] = [
			"left": (123, NSLeftArrowFunctionKey), "right": (124, NSRightArrowFunctionKey),
			"down": (125, NSDownArrowFunctionKey), "up": (126, NSUpArrowFunctionKey),
			"pageup": (116, NSPageUpFunctionKey), "pagedown": (121, NSPageDownFunctionKey),
		]
		// The emacs letters — ⌃A ⌃B ⌃D ⌃E ⌃F ⌃K ⌃N ⌃O ⌃P — whether or not
		// anything presses all of them today, because looking a key code up
		// again is the cost of leaving them out.
		let letterKeys = ["a": 0, "b": 11, "d": 2, "e": 14, "f": 3, "k": 40, "n": 45, "o": 31, "p": 35]

		let code: Int
		let characters: String
		let ignoringModifiers: String
		if let navigation = navigationKeys[key.lowercased()] {
			code = navigation.code
			characters = String(UnicodeScalar(navigation.character)!)
			ignoringModifiers = characters
		} else if let letter = letterKeys[key.lowercased()], let scalar = key.lowercased().unicodeScalars.first {
			code = letter
			// A letter held with Control reports the control character in
			// `characters` and the bare letter in `charactersIgnoringModifiers`
			// — Shift reaching only the second of the two. AppKit matches the
			// binding against the pair, so a key built with the same string in
			// both fields arrives as nothing at all.
			ignoringModifiers = modifiers.contains(.shift) ? key.uppercased() : key.lowercased()
			characters = modifiers.contains(.control)
				? String(UnicodeScalar(UInt8(scalar.value & 0x1F)))
				: ignoringModifiers
		} else {
			return
		}

		guard let event = NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: modifiers,
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: view.window?.windowNumber ?? 0,
			context: nil,
			characters: characters,
			charactersIgnoringModifiers: ignoringModifiers,
			isARepeat: false,
			keyCode: UInt16(code)
		) else { return }
		codeView.keyDown(with: event)
	}

	/// What the completion list is showing.
	var completionReportForTesting: String {
		guard completions.isVisible else { return "no list" }
		if let notice = completions.noticeForTesting { return "waiting: \(notice)" }
		let frame = completions.frameForTesting
		let caret = activeTab?.codeView?.caretScreenPoint() ?? .zero
		return "\(completions.labelsForTesting.count) items: "
			+ completions.labelsForTesting.prefix(6).joined(separator: ", ")
			+ String(format: " | list at (%.0f, %.0f) %.0fx%.0f, caret at (%.0f, %.0f)",
				frame.minX, frame.minY, frame.width, frame.height, caret.x, caret.y)
	}

	/// The first line of what the panel beside the list is showing, and how much
	/// of it there is.
	///
	/// A line rather than the page: a driver's output is read in a terminal, and
	/// `cube`'s documentation is a wiki page. The length is what says the rest
	/// arrived.
	var completionDocumentationForTesting: String {
		guard let prose = completions.documentationForTesting else { return "no documentation" }
		let first = prose.components(separatedBy: .newlines).first ?? ""
		return "\(prose.count) characters, first line: \(first)"
	}

	/// What the strip above the line says, which is the answer to "what goes
	/// here" once the list has closed.
	var parameterHintForTesting: String {
		guard let text = parameterHint.textForTesting else { return "no hint" }
		guard let range = parameterHint.emphasisForTesting else { return text }
		let units = Array(text.utf16)
		let clamped = range.clamped(to: 0..<units.count)
		return "\(text) | filling in: \(String(decoding: units[clamped], as: UTF16.self))"
	}

	/// The text of the active tab, drawn to a PNG.
	@discardableResult
	func writeEditorImageForTesting(to path: String) -> Bool {
		activeTab?.codeView?.writeImageForTesting(to: path) ?? false
	}

	@discardableResult
	func writeCompletionImageForTesting(to path: String) -> Bool {
		completions.writeImageForTesting(to: path)
	}

	/// Chooses from the list as pressing return would.
	func commitCompletionForTesting() -> Bool {
		completions.commitSelection()
	}

	func moveCompletionSelectionForTesting(by delta: Int) {
		completions.moveSelection(by: delta)
	}

	func moveCaretToEndForTesting() {
		guard let codeView = activeTab?.codeView, let document = activeTab?.document else { return }
		view.window?.makeFirstResponder(codeView)
		codeView.setCaretForTesting(document.rope.utf16Count)
	}

	/// A negative line counts back from the end, so -1 is the last line.
	func setCaretForTesting(line: Int, column: Int) {
		guard let codeView = activeTab?.codeView else { return }
		view.window?.makeFirstResponder(codeView)
		codeView.setCaretForTesting(line: line, column: column)
	}

	/// Where the caret is and what is selected, for checking a motion landed.
	var caretReportForTesting: String {
		guard let codeView = activeTab?.codeView else { return "no editor" }
		return codeView.caretReportForTesting
	}

	/// Whether what was last revealed is on screen, with the file it is in.
	var revealReportForTesting: String {
		guard let codeView = activeTab?.codeView, let tab = activeTab else { return "no editor" }
		return "\(tab.url.lastPathComponent) \(codeView.revealReportForTesting)"
	}

	/// The caret's line and the one after it, with `|` where the caret is.
	///
	/// `caretReportForTesting` prints the *selected* text, which is empty
	/// whenever the caret is collapsed — so a key that inserts a newline and
	/// leaves the caret where it was reads exactly like a key that did
	/// nothing. `textTailForTesting` is no help either: it reports the end of
	/// the file, and an edit in the middle of one does not reach it. A key
	/// that inserts text has to show the text.
	///
	/// Tabs come out as `⇥`, because the question a driver asks about an
	/// inserted line is usually whether it is empty or full of whitespace, and
	/// a real tab in a terminal transcript answers that invisibly.
	///
	/// The line count comes with them. A newline inserted at the end of a line
	/// leaves an empty line after it, and the line after *that* one was
	/// already there — so two lines of text are the same either side of the
	/// press and only the count says the file grew.
	var caretLinesForTesting: String {
		guard let codeView = activeTab?.codeView, let document = activeTab?.document else {
			return "no file"
		}
		let rope = document.rope
		let offset = codeView.caretOffset
		let index = rope.line(atByteOffset: rope.byteOffset(fromUTF16: offset))
		let start = rope.utf16Offset(fromByte: rope.lineByteRange(index).lowerBound)
		let units = Array(rope.lineText(index).utf16)
		let column = max(0, min(offset - start, units.count))
		let marked = String(decoding: units[0..<column], as: UTF16.self) + "|"
			+ String(decoding: units[column...], as: UTF16.self)
		let shown = { (text: String) in text.replacingOccurrences(of: "\t", with: "⇥") }
		let next = index + 1 < document.lineCount ? rope.lineText(index + 1) : nil
		return "line \(index) “\(shown(marked))”"
			+ (next.map { " then \(index + 1) “\(shown($0))”" } ?? " (last line)")
			+ " — \(document.lineCount) lines"
	}

	/// Presses ⌘/ over a caret or a selection the spec names.
	func toggleCommentForTesting(_ spec: String) -> (LineComment.Outcome, String)? {
		guard let codeView = codeViewToDrive("--comment") else { return nil }
		view.window?.makeFirstResponder(codeView)
		return codeView.toggleCommentForTesting(spec)
	}

	/// Selects whole lines and leaves the keyboard exactly where it was.
	///
	/// No `makeFirstResponder`, unlike every other verb here: the point of it is
	/// a selection this view is drawing while the keyboard is in the terminal.
	func selectLinesForTesting(fromLine: Int, toLine: Int) -> Bool {
		guard let codeView = activeTab?.codeView else { return false }
		codeView.selectLinesForTesting(fromLine: fromLine, toLine: toLine)
		return true
	}

	/// Indents or outdents whole lines, the way Tab and ⇧Tab do.
	func indentForTesting(fromLine: Int, toLine: Int, outdent: Bool) -> String? {
		guard let codeView = codeViewToDrive("--indent-block") else { return nil }
		view.window?.makeFirstResponder(codeView)
		codeView.indentForTesting(fromLine: fromLine, toLine: toLine, outdent: outdent)
		return codeView.textForTesting
	}

	/// What the editor is holding, saved or not — for checking what typing did.
	var textForTesting: String? { activeTab?.codeView?.textForTesting }

	/// Presses the strip menu's global item, says where the file landed, and
	/// takes it away again — a check that leaves nothing behind in somebody's
	/// notes.
	func globalScratchDirectoryForTesting() -> String {
		let before = Set(ScratchFiles.global().all())
		_ = tabBar.contextMenuTitlesForTesting(overTab: false)  // builds the same menu
		newScratch(global: true)
		guard let made = ScratchFiles.global().all().first(where: { !before.contains($0) })
		else { return "nothing created" }
		defer { try? FileManager.default.removeItem(at: made) }
		return made.deletingLastPathComponent().path
	}

	/// Where the strip and the file's view actually ended up.
	func layoutReportForTesting() -> String {
		let content = activeTab?.contentView
		let centre = tabBar.convert(NSPoint(x: tabBar.bounds.midX, y: tabBar.bounds.midY), to: nil)
		let onTop = view.window?.contentView?.hitTest(centre)
		return "strip hidden=\(tabBar.isHidden) alpha=\(tabBar.alphaValue) items=\(tabBar.items.count)"
			+ " frame=\(NSStringFromRect(tabBar.frame))"
			+ " onTopOfStrip=\(onTop.map { String(describing: type(of: $0)) } ?? "nothing")"
			+ " content=\(content.map { String(describing: type(of: $0)) } ?? "none")"
			+ " area=\(NSStringFromRect(contentArea.frame))"

	}

	/// What the tab strip's menu offers over a tab and over its empty part.
	func tabMenuTitlesForTesting(overTab: Bool) -> [String] {
		tabBar.contextMenuTitlesForTesting(overTab: overTab)
	}

	/// Clicks under the last line of the file that is showing.
	func clickBelowLastLineForTesting() -> String {
		guard let codeView = activeTab?.codeView else { return "no editor" }
		view.window?.makeFirstResponder(codeView)
		return codeView.clickBelowLastLineForTesting()
	}

	/// Routes text through `NSTextInputClient.insertText`, the same entry point
	/// a real keystroke takes.
	func simulateTyping(_ text: String) {
		guard let codeView = codeViewToDrive("--type") else { return }
		view.window?.makeFirstResponder(codeView)
		for character in text {
			// A newline is the return key, not a character. Inserted directly
			// it skips everything return does — the indent, the closing brace
			// — so a test that typed one was testing something nobody does.
			if character == "\n" {
				codeView.doCommand(by: #selector(NSStandardKeyBindingResponding.insertNewline(_:)))
				continue
			}
			codeView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
		}
	}

	/// What each keystroke costs the main thread, in the file that is open.
	///
	/// The performance suite has measured this since 0416, but only against a
	/// document built in memory: `Rope`, the highlighter and the fold finder,
	/// with no window, no project, no language server and no filesystem watcher.
	/// 0428 asks the same question in a file inside a large bundle in a large
	/// project, where all four of those exist and every one of them wants the
	/// same queue — and the difference between the two answers is the whole
	/// reason the item names keystroke latency separately.
	///
	/// Synchronous, one character after another with nothing in between, so what
	/// comes back is the cost of the keystroke rather than the interval it was
	/// typed at. Both clocks: the wall is what a person waits and the processor
	/// time is what changes when the code does, which is 0416's distinction and
	/// is why a run under load is still worth taking.
	func measureTypingForTesting(presses: Int) -> [(wall: TimeInterval, cpu: TimeInterval)] {
		guard let codeView = codeViewToDrive("--type-latency") else { return [] }
		view.window?.makeFirstResponder(codeView)
		let letters = Array("abcdefghijklmnopqrstuvwxyz")
		var costs: [(TimeInterval, TimeInterval)] = []
		for press in 0..<presses {
			var cpuStart = timespec(), cpuEnd = timespec()
			clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpuStart)
			let wallStart = DispatchTime.now().uptimeNanoseconds
			codeView.insertText(
				String(letters[press % letters.count]),
				replacementRange: NSRange(location: NSNotFound, length: 0)
			)
			let wall = Double(DispatchTime.now().uptimeNanoseconds - wallStart) / 1_000_000_000
			clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpuEnd)
			costs.append((wall, Double(cpuEnd.tv_sec - cpuStart.tv_sec)
				+ Double(cpuEnd.tv_nsec - cpuStart.tv_nsec) / 1_000_000_000))
		}
		return costs
	}

	/// Flushes every dirty document, used on focus loss and quit.
	func autoSaveAll() {
		for tab in tabs {
			tab.document?.autoSaveIfNeeded()
		}
		refreshTabBar()
	}

	/// Re-reads any open file that something else has written.
	///
	/// A file with unsaved edits is left alone: replacing it would throw away
	/// work the user has not seen saved, and the two versions cannot be merged
	/// without asking. Auto-save is on by default, so that window is short.
	func reloadExternallyChangedFiles() {
		for tab in tabs {
			guard let document = tab.document, !document.isDirty else { continue }
			guard document.hasChangedOnDisk else { continue }
			guard tab.codeView?.reloadFromDisk() == true else { continue }
			onFileReloaded?(tab.url)

			// And tell the language server, or its diagnostics go on describing
			// the file as it was — which after something else has just fixed
			// one of them is the wrong answer written in red.
			guard let languageId = document.languageId, let root = serverRoot(for: tab) else { continue }
			LanguageService.shared.changed(
				url: tab.url, languageId: languageId, text: text(of: document), project: root
			)
			LanguageService.shared.saved(
				url: tab.url, languageId: languageId, text: text(of: document), project: root
			)
		}
	}

	/// Re-reads settings that affect the editor and repaints.
	func applySettings() {
		tabBarHeightConstraint.constant = EditorTabBar.height
		placeholder.font = Theme.current.uiFont(13)
		styleScratchButton()
		tabBar.applyThemeChange()
		findBar.applyThemeChange()
		if !findBar.isHidden { findBarHeight.constant = Theme.current.scaled(34) }
		serverBanner.applyTheme()
		if !serverBanner.isHidden { serverBannerHeight.constant = LanguageServerBanner.height }
		for tab in tabs {
			tab.codeView?.setWordWrap(Settings.shared.wordWrap)
			tab.codeView?.applyThemeChange()
			// A page of the app's own is a view in a tab and nothing else in the
			// window walks into one, so without this it was the one thing that
			// did not follow ⌘+: settings opened at 1× kept 1× rows and 1× type
			// for as long as it stayed open.
			(tab.contentView as? ScalingPage)?.applySettings()
		}
	}

	func windowWillClose() {
		autoSaveAll()
		for tab in tabs { teardown(tab) }
		tabs.removeAll()
		NotificationCenter.default.removeObserver(self)
	}
}

/// A page of the app's own that re-reads the zoom and the palette when they
/// change, the way every pane of the window does.
///
/// A page lives in a tab rather than in the window's own furniture, so nothing
/// in `MainWindowController.applySettings` reaches one on its way round. This
/// is how a page asks to be included: the editor calls it for every tab holding
/// one, and a page that does not conform is left alone.
@MainActor
protocol ScalingPage: NSView {
	func applySettings()
}

/// Detects binary content so the editor does not try to render it.
enum FileInspector {
	static func isProbablyBinary(url: URL) -> Bool {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
		defer { try? handle.close() }
		guard let sample = try? handle.read(upToCount: 8_000), !sample.isEmpty else { return false }

		// A NUL byte in the first few KB is the standard heuristic — it is what
		// git itself uses to decide a file is binary.
		return sample.contains(0)
	}
}

// MARK: - Status bar

final class EditorStatusView: NSView {
	/// A language was chosen by hand; nil means "no highlighting".
	var onLanguageChosen: ((String?) -> Void)?

	private var positionText = ""
	private var languageText = ""
	private var languageRect = NSRect.zero
	private var isLanguageHovered = false
	private var trackingArea: NSTrackingArea?

	/// What the server chip says and what its tool tip says, already worked out.
	///
	/// Two strings and nothing else, which is the whole design: `setPosition` is
	/// called on every caret move and draws in this same view, so anything this
	/// bar has to *find out* would be found out beside every keystroke. The
	/// finding out happens in `LanguageService.footer(forLanguage:project:)`, is
	/// pushed here when a server starts, stops or is refused, and is a value by
	/// the time it arrives.
	private var serverText = ""
	private var serverDetail = ""
	private var serverRect = NSRect.zero
	private var isServerHovered = false
	/// The rectangle the tool tip is currently registered for, so it is put back
	/// only when it has moved rather than on every redraw. Nil asks for it to be
	/// registered again whatever the rectangle says.
	private var toolTipRect: NSRect?

	override var isFlipped: Bool { true }

	func setPosition(line: Int, column: Int) {
		positionText = "\(line):\(column)"
		needsDisplay = true
	}

	func setLanguage(_ name: String?) {
		languageText = name ?? "Plain Text"
		needsDisplay = true
	}

	/// Which server is answering for the file, or nothing at all.
	///
	/// **Nothing at all is the common case and the deliberate one.** Most files
	/// in most projects have no server, and a chip saying so on every one of them
	/// would be a footer people learn to stop reading — which would cost the
	/// sentence it is here to say. The strip above the file is what talks about a
	/// server that is missing; this only names one that exists.
	func setServer(_ footer: LanguageServerFooter?) {
		let text = footer?.text(containerMark: MainWindowController.containerMark) ?? ""
		let detail = footer?.detail ?? ""
		guard text != serverText || detail != serverDetail else { return }
		serverText = text
		serverDetail = detail
		toolTipRect = nil
		needsDisplay = true
	}

	// MARK: - The language control

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
			owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseMoved(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		let language = languageRect.contains(point)
		let server = !serverRect.isEmpty && serverRect.contains(point)
		guard language != isLanguageHovered || server != isServerHovered else { return }
		isLanguageHovered = language
		isServerHovered = server
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent) {
		guard isLanguageHovered || isServerHovered else { return }
		isLanguageHovered = false
		isServerHovered = false
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		if languageRect.contains(point) {
			showLanguageMenu(at: NSPoint(x: languageRect.minX, y: languageRect.maxY))
			return
		}

		// **The list of what is running, and not the settings page.** Both were
		// candidates and they answer different questions. The chip states a fact
		// about *this project* — this server, from here, now — and the questions
		// that follow from reading it are whether it is really running, what it
		// is costing, which executable the system resolved and how to stop it;
		// that window answers all four and has the Stop. Settings is where the
		// answer is *changed*, but a settings page knows no project — the spec
		// says as much where it explains why a chosen server's row is in the list
		// and not in Settings — so a click landing there would answer a question
		// nobody had just asked.
		guard !serverRect.isEmpty, serverRect.contains(point) else { return }
		RunningToolsWindowController.shared.show()
	}

	override func resetCursorRects() {
		super.resetCursorRects()
		addCursorRect(languageRect, cursor: .pointingHand)
		if !serverRect.isEmpty { addCursorRect(serverRect, cursor: .pointingHand) }
	}

	private func showLanguageMenu(at point: NSPoint) {
		let menu = NSMenu()

		let plain = NSMenuItem(title: "Plain Text", action: #selector(chooseLanguage(_:)), keyEquivalent: "")
		plain.target = self
		plain.state = languageText == "Plain Text" ? .on : .off
		menu.addItem(plain)
		menu.addItem(.separator())

		for language in LanguageRegistry.shared.selectableLanguages {
			let item = NSMenuItem(title: language.name, action: #selector(chooseLanguage(_:)), keyEquivalent: "")
			item.target = self
			item.representedObject = language.id
			item.state = language.name == languageText ? .on : .off
			menu.addItem(item)
		}

		menu.popUp(positioning: nil, at: point, in: self)
	}

	@objc private func chooseLanguage(_ sender: NSMenuItem) {
		onLanguageChosen?(sender.representedObject as? String)
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		// The editor's own background, not the sidebar's. This bar and the
		// panel's tab strip sat one on top of the other in the same shade with
		// the same hairline, so the pair read as a single band and the strip
		// took double-clicks meant for the bar — which maximises the panel.
		// Belonging to the editor is also what this bar is: it says where the
		// caret is.
		Theme.current.editorBackground.setFill()
		bounds.fill()

		// Along the top, between the text and this. The panel below draws its
		// own; two lines with nothing between them was the other half of the
		// problem.
		Theme.current.separator.setFill()
		NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()

		let attributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(11),
			.foregroundColor: Theme.current.gitIgnored,
		]

		// Right-aligned: server, then position, then language at the edge.
		//
		// **The order is about which one is allowed to lose.** The language and
		// the caret's position are a handful of characters and never more, so
		// they are laid out first and keep their place; the server is beside the
		// language — the same fact one layer down — and is the one that can be a
		// name and an image tag together, so it takes whatever room the other two
		// leave and truncates at the tail. 0458 hit this on a card and settled it
		// the same way: say the important part first.
		let gap = Theme.current.scaled(16)
		var x = bounds.width - Theme.current.scaled(12)
		for (index, text) in [languageText, positionText].enumerated() where !text.isEmpty {
			let attributed = NSAttributedString(string: text, attributes: attributes)
			let size = attributed.size()
			x -= size.width
			let origin = NSPoint(x: x, y: bounds.midY - size.height / 2)

			// The language is a control, so it gets a hit area and a hover
			// background — otherwise nothing suggests it can be clicked.
			if index == 0 {
				languageRect = chipRect(around: origin, size: size)
				if isLanguageHovered { highlight(languageRect) }
			}

			attributed.draw(at: origin)
			x -= gap
		}

		drawServer(leftOf: x, attributes: attributes)
	}

	/// The server chip, in the room the position and the language left.
	private func drawServer(leftOf right: CGFloat, attributes: [NSAttributedString.Key: Any]) {
		defer { refreshServerToolTip() }
		serverRect = .zero
		guard !serverText.isEmpty else { return }

		var truncating = attributes
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		truncating[.paragraphStyle] = paragraph
		let attributed = NSAttributedString(string: serverText, attributes: truncating)
		let size = attributed.size()

		// Whether there is room to say it, and how much of it is said, decided in
		// `LanguageServerFooter` — a rule the suite can reach rather than a
		// comparison written where the drawing is. 0467 is why: the rule used to
		// be here, it asked the wrong question, and nothing in the suite could
		// see it ask.
		let room = right - Theme.current.scaled(12) - Theme.current.scaled(10)
		guard let fits = LanguageServerFooter.chipWidth(
			text: Double(size.width),
			room: Double(room),
			legibleAt: Double(Theme.current.scaled(56))
		) else { return }
		let width = CGFloat(fits)

		let origin = NSPoint(x: right - Theme.current.scaled(12) - width, y: bounds.midY - size.height / 2)
		serverRect = chipRect(around: origin, size: NSSize(width: width, height: size.height))
		if isServerHovered { highlight(serverRect) }
		attributed.draw(in: NSRect(origin: origin, size: NSSize(width: width, height: size.height)))
	}

	/// The hit area and hover background of a chip, around the text it holds.
	private func chipRect(around origin: NSPoint, size: NSSize) -> NSRect {
		let padding = Theme.current.scaled(5)
		return NSRect(
			x: origin.x - padding,
			y: bounds.midY - size.height / 2 - padding / 2,
			width: size.width + padding * 2,
			height: size.height + padding
		)
	}

	private func highlight(_ rect: NSRect) {
		NSColor.white.withAlphaComponent(0.08).setFill()
		NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
	}

	/// Puts the tool tip back where the chip is now.
	///
	/// On the chip's rectangle rather than on the whole bar, because the bar is
	/// mostly empty and a tool tip over the empty part would be a sentence about
	/// a language server appearing under the mouse on its way somewhere else.
	/// Done here because here is where the rectangle is known — the caret's
	/// position changes width, so the chip beside it moves — and guarded so that
	/// a redraw for a caret that moved within the same line costs nothing.
	private func refreshServerToolTip() {
		guard serverRect != toolTipRect else { return }
		toolTipRect = serverRect
		removeAllToolTips()
		guard !serverRect.isEmpty else { return }
		addToolTip(serverRect, owner: serverDetail as NSString, userData: nil)
	}

	// MARK: - Testing

	/// What the bar is saying about the server, for a photograph to be checked
	/// against — the words and the rectangle they were measured into, since a
	/// card measured at one width and drawn at another is a fault this project
	/// has had twice.
	var serverReportForTesting: String {
		serverText.isEmpty
			? "no server"
			: "\(serverText) [\(Int(serverRect.width))×\(Int(serverRect.height))]"
	}
}
