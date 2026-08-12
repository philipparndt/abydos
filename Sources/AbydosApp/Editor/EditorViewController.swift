import AppKit
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
	private var searchMatches: [SearchMatch] = []
	private var currentMatchIndex: Int?
	private var findDebounce: DispatchWorkItem?
	private var languageSyncWork: DispatchWorkItem?
	/// The list of completions, shared by every tab in this group: only one can
	/// be typing at a time.
	private let completions = CompletionPopup()
	private var completionWork: DispatchWorkItem?
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
	/// Which of source, preview or a split the file in front is being shown in.
	var currentPreviewMode: PreviewMode { activeTab?.previewMode ?? .source }
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

		guard let project, let languageId = document.languageId else { return true }
		LanguageService.shared.changed(
			url: tab.url, languageId: languageId, text: text, project: project.scopeRoot
		)
		LanguageService.shared.saved(
			url: tab.url, languageId: languageId, text: text, project: project.scopeRoot
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
		guard let moved = note.object as? URL, let project else { return }
		guard moved.standardizedFileURL.path == project.scopeRoot.standardizedFileURL.path else {
			return
		}
		rescope()
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
		guard let project,
		      let tab = activeTab,
		      !tab.isDiff,
		      let languageId = tab.document?.languageId,
		      !dismissedSuggestions.contains(languageId),
		      let notice = LanguageService.shared.notice(
		      	forLanguage: languageId,
		      	project: project.scopeRoot,
		      	ignoring: Set(Settings.shared.ignoredLanguageServers)
		      )
		else {
			hideServerBanner()
			return
		}

		serverBanner.show(notice)
		serverBanner.isHidden = false
		serverBannerHeight.constant = LanguageServerBanner.height
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
		if let project, let tab = activeTab, !tab.isDiff, let languageId = tab.document?.languageId {
			footer = LanguageService.shared.footer(
				forLanguage: languageId, project: project.scopeRoot
			)
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
			LanguageService.shared.useDevContainer(for: project.scopeRoot)
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
		guard let root = project?.root else { return }

		// No record yet — the first launch after this was added, or a project
		// only ever opened before it. What it has is the best guess at what it
		// had open.
		let remembered = OpenScratches().existing(forProject: root)
			?? ScratchFiles(projectRoot: root).all()

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
		guard let project else { return }
		for tab in tabs {
			guard !tab.isDiff, let document = tab.document, let languageId = document.languageId
			else { continue }
			LanguageService.shared.opened(
				url: tab.url, languageId: languageId, text: text(of: document),
				project: project.scopeRoot
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

		let byteSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
		if byteSize > 64 * 1024 * 1024 {
			let formatted = ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
			return makeNoticeTab(for: fileURL, reason: "This file is \(formatted) — too large to open as text.", preview: preview)
		}
		if FileInspector.isProbablyBinary(url: fileURL) {
			return makeNoticeTab(for: fileURL, reason: "This looks like a binary file.", preview: preview)
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
			guard let self, let project = self.project, let languageId = document.languageId else { return }
			let root = project.scopeRoot
			// The other half of what repeats. An auto-save follows every typing
			// pause, so this built the whole file as a `String` on the main
			// thread as often as the sync above did.
			self.withText(of: document) { text in
				LanguageService.shared.saved(
					url: fileURL, languageId: languageId, text: text, project: root
				)
			}
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
		codeView.onRequestCompletions = { [weak self] prefix, _ in
			self?.scheduleCompletions(for: tab, prefix: prefix)
		}
		codeView.onDismissCompletions = { [weak self] in
			self?.completionWork?.cancel()
			self?.completions.hide()
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
		if let project, let languageId = document.languageId {
			LanguageService.shared.opened(
				url: fileURL, languageId: languageId, text: text(of: document), project: project.scopeRoot
			)
			codeView.setDiagnostics(LanguageService.shared.diagnostics(for: fileURL))
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
		let opening = FilePreview.restoredMode(mode, for: fileURL)
		if opening != .source, FilePreview.hasPreview(fileURL) {
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
		label: "ideai.languagetext", qos: .userInitiated
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
			      let project = self.project, let languageId = document.languageId
			else { return }
			let url = tab.url
			let root = project.scopeRoot
			withText(of: document) { text in
				LanguageService.shared.changed(
					url: url, languageId: languageId, text: text, project: root
				)
			}
		}
		languageSyncWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
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

	/// The last few lines of the file, for looking at what typing produced.
	func textTailLinesForTesting(_ count: Int) -> [String] {
		guard let document = activeTab?.document else { return [] }
		let text = document.rope.string(in: 0..<document.rope.byteCount)
		let lines: [String] = text.components(separatedBy: "\n")
		return Array(lines.suffix(count))
	}

	func goToDefinitionForTesting(line: Int, character: Int) {
		guard let tab = activeTab else { return }
		goToDefinition(from: tab, line: line, character: character)
	}

	func hoverWithCommandForTesting(line: Int, character: Int) {
		activeTab?.codeView?.hoverWithCommandForTesting(line: line, character: character)
	}

	func undoForTesting() {
		activeTab?.codeView?.undo(nil)
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
	private func scheduleCompletions(for tab: Tab, prefix: String) {
		completionWork?.cancel()
		guard prefix.count >= 2 else {
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

	@MainActor
	private func showCompletions(for tab: Tab, prefix: String) async {
		guard activeTab === tab, let codeView = tab.codeView, let document = tab.document else { return }

		// The prefix may have moved on while this was being asked for.
		guard codeView.currentWordPrefix() == prefix else { return }

		var items: [CompletionItem] = []
		if let project, let languageId = document.languageId {
			let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: codeView.caretOffset))
			let lineStart = document.rope.utf16Offset(fromByte: document.rope.byteOffset(ofLine: line))
			let character = codeView.caretOffset - lineStart

			let fromServer = await LanguageService.shared.completions(
				url: tab.url,
				position: LSPPosition(line: line, character: character),
				languageId: languageId,
				project: project.scopeRoot
			)
			// A server answers about types and scope; the words in the file
			// cannot, so anything it says is worth more than anything they do.
			items = fromServer
				.filter { $0.label.lowercased().hasPrefix(prefix.lowercased()) }
				.prefix(20)
				.map(CompletionItem.init)
		}

		if items.isEmpty {
			let text = document.rope.string(in: 0..<document.rope.byteCount)
			items = WordCompletions
				.candidates(matching: prefix, in: text, near: codeView.caretOffset)
				.map { CompletionItem(label: $0, isFromServer: false) }
		}

		guard !items.isEmpty, codeView.currentWordPrefix() == prefix else {
			completions.hide()
			return
		}

		completionPrefixLength = prefix.utf16.count
		completions.onCommit = { [weak codeView, weak self] item in
			guard let self else { return }
			// A snippet is not text to paste: `union() $0` means "put the caret
			// between the braces", and inserted as written it is a syntax
			// error somebody has to go back and delete.
			let snippet = item.isSnippet
				? Snippet.expand(item.insertText)
				: Snippet(text: item.insertText, caret: item.insertText.utf16.count)
			codeView?.applyCompletion(
				snippet.text,
				replacingPrefixOfLength: self.completionPrefixLength,
				caretOffset: snippet.caret
			)
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
				project: project.scopeRoot
			)
			guard let first = locations.first, let url = first.url else { return }
			open(fileURL: url, atLine: first.range.start.line + 1)
		}
	}

	/// Applies whatever a server last said about the files that are open.
	@objc private func diagnosticsChanged(_ notification: Notification) {
		guard let url = notification.object as? URL else { return }
		for tab in tabs where tab.url.absoluteString == url.absoluteString {
			tab.codeView?.setDiagnostics(LanguageService.shared.diagnostics(for: url))
		}
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
	func showFind() {
		guard activeTab?.codeView != nil || pdfPreview != nil else { return }
		findBar.isHidden = false
		findBarHeight.constant = Theme.current.scaled(34)

		if let selected = selectedTextForSearch() {
			findBar.setQuery(selected)
		}
		findBar.focusField()
		runFind(query: findBar.query, options: findBar.options)
	}

	func setFindQuery(_ query: String) {
		showFind()
		findBar.setQuery(query)
	}

	func closeFind() {
		findBar.isHidden = true
		findBarHeight.constant = 0
		searchMatches = []
		currentMatchIndex = nil
		activeTab?.codeView?.clearSearchMatches()
		pdfPreview?.clearFind()
		focusActiveEditor()
	}

	var isFindVisible: Bool { !findBar.isHidden }

	/// Debounced so a search does not run on every keystroke of a long query.
	private func scheduleFind(query: String, options: SearchOptions) {
		findDebounce?.cancel()
		let work = DispatchWorkItem { [weak self] in
			self?.runFind(query: query, options: options)
		}
		findDebounce = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
	}

	private func runFind(query: String, options: SearchOptions) {
		// A PDF has no rope to search, so PDFKit searches it and the bar is told
		// the same two numbers it is told for a source file. Whole-word and regex
		// are not offered by `PDFDocument.findString`, so those switches do
		// nothing here — the bar keeps showing them because they still apply to
		// the next file, and a search that quietly ignored them would find more
		// than it said rather than less.
		if let pdf = pdfPreview {
			let count = pdf.find(query, caseSensitive: options.caseSensitive)
			findBar.setStatus(matchCount: count, currentIndex: pdf.currentMatchIndex)
			return
		}

		guard let tab = activeTab, let document = tab.document, let codeView = tab.codeView else { return }

		guard !query.isEmpty else {
			searchMatches = []
			currentMatchIndex = nil
			codeView.clearSearchMatches()
			findBar.setStatus(matchCount: 0, currentIndex: nil)
			return
		}

		searchMatches = TextSearch.matches(in: document.rope, query: query, options: options)
		// Start from the match nearest the caret rather than the top of the file.
		let caret = codeView.caretOffset
		currentMatchIndex = searchMatches.firstIndex { $0.utf16Range.lowerBound >= caret }
			?? (searchMatches.isEmpty ? nil : 0)

		codeView.setSearchMatches(searchMatches, current: currentMatchIndex)
		findBar.setStatus(matchCount: searchMatches.count, currentIndex: currentMatchIndex)
	}

	private func stepMatch(by delta: Int) {
		if let pdf = pdfPreview {
			pdf.stepMatch(by: delta)
			findBar.setStatus(matchCount: pdf.matchCount, currentIndex: pdf.currentMatchIndex)
			return
		}

		guard !searchMatches.isEmpty else { return }
		let current = currentMatchIndex ?? -1
		// Wraps, which is what every find bar does at the ends.
		let next = ((current + delta) % searchMatches.count + searchMatches.count) % searchMatches.count
		currentMatchIndex = next
		activeTab?.codeView?.setSearchMatches(searchMatches, current: next)
		findBar.setStatus(matchCount: searchMatches.count, currentIndex: next)
	}

	func findNext() { stepMatch(by: 1) }
	func findPrevious() { stepMatch(by: -1) }

	/// Opens a file and jumps to a line — the target of review findings and
	/// search results.
	///
	/// `focusEditor` and `preview` are what tell "take me to this one" from "show
	/// me this one": a checklist being walked with ↓ asks for the provisional tab
	/// and leaves the keyboard in the list, so 263 usages cost one tab rather than
	/// 263, and the next ↓ still reaches the next row. Both keep the defaults the
	/// call has always had, so a click and a review finding are unchanged.
	func open(fileURL: URL, atLine line: Int, focusEditor: Bool = true, preview: Bool = false) {
		let departure = currentPlace
		isReportingSuppressed += 1
		open(fileURL: fileURL, focusEditor: focusEditor, preview: preview)
		isReportingSuppressed -= 1
		reportNavigation(
			from: departure,
			to: (fileURL, line)
		)
		// Deferred: a freshly opened document has not laid out yet, so scrolling
		// now would compute against a zero-height view.
		//
		// The tab this call opened, rather than whichever is active by the time
		// the block runs. `abydos deep.txt:150 main.go` opens both in one turn,
		// and reading it late revealed line 150 on `main.go` — a two-line file
		// scrolled to a line it does not have, while the file that asked for
		// line 150 sat at the top. Weakly, since a tab closed in between is one
		// with nothing left to reveal.
		let opened = activeTab
		DispatchQueue.main.async { [weak opened] in
			opened?.codeView?.reveal(line: line)
		}
	}

	/// Puts the caret on a 1-based line of the file being edited.
	///
	/// Nothing happens when no file is open: `:` in the palette is a question
	/// about a document, and there is no document to ask it of.
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
		guard FilePreview.availableModes(for: tab.url).contains(mode) else { return }
		guard mode != tab.previewMode else { return }

		tab.previewMode = mode
		tab.contentView = makeContentView(for: tab, mode: mode)

		activeIndex = nil
		activate(index: index, focusEditor: mode == .source)
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
		switch FilePreview.kind(for: tab.url) {
		case .model:
			// A provisional tab waits before rendering; one somebody committed to
			// does not. `makeModelView` says why the wait exists at all.
			return makeModelView(
				for: tab.url, startAfter: tab.isPreview ? Self.provisionalRenderDelay : 0
			)
		case .image:
			return ImageFileViewer(url: tab.url).scrollView
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
	var diagramPreview: DiagramPaneView? {
		activeTab.flatMap { Self.diagramPane(in: $0.contentView) }
	}

	private static func diagramPane(in view: NSView) -> DiagramPaneView? {
		if let pane = view as? DiagramPaneView { return pane }
		for subview in view.subviews {
			if let found = diagramPane(in: subview) { return found }
		}
		return nil
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
			contentView: ImageFileViewer(url: fileURL).scrollView,
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
		onStatusChanged?(self)
		refreshServerState()
		updateChrome()
		refreshTabBar()
		onActivated?(self)

		if focusEditor {
			// A notice tab has no code view to focus.
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
			let modes = FilePreview.availableModes(for: tab.url)
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
		guard let project, let languageId = closing.document?.languageId,
		      !tabs.contains(where: { $0 !== closing && $0.url == closing.url })
		else { return }
		LanguageService.shared.closed(
			url: closing.url, languageId: languageId, project: project.scopeRoot
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
		if let pane = Self.diagramPane(in: tab.contentView) as? DrawioPreviewView {
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
		} catch {
			Toast.post("Could not save \(tab.url.lastPathComponent)", detail: error.localizedDescription)
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
					previewMode: FilePreview.hasPreview(tab.url) ? tab.previewMode : nil,
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

	/// Routes text through `NSTextInputClient.insertText`, the same entry point
	/// a real keystroke takes.
	/// Presses an arrow key with modifiers, the way a keyboard would.
	///
	/// Through `keyDown` rather than by calling the command directly: what is
	/// being checked is that the system's key bindings reach the editor, not
	/// that the editor has a method with the right name.
	func simulateArrow(_ direction: String, modifiers: NSEvent.ModifierFlags) {
		guard let tab = activeTab, let codeView = tab.codeView else { return }
		view.window?.makeFirstResponder(codeView)

		let keyCodes = ["left": 123, "right": 124, "down": 125, "up": 126]
		let characters = [
			"left": NSLeftArrowFunctionKey, "right": NSRightArrowFunctionKey,
			"down": NSDownArrowFunctionKey, "up": NSUpArrowFunctionKey,
		]
		guard let code = keyCodes[direction], let character = characters[direction] else { return }
		let text = String(UnicodeScalar(character)!)

		guard let event = NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: modifiers,
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: view.window?.windowNumber ?? 0,
			context: nil,
			characters: text,
			charactersIgnoringModifiers: text,
			isARepeat: false,
			keyCode: UInt16(code)
		) else { return }
		codeView.keyDown(with: event)
	}

	/// What the completion list is showing.
	var completionReportForTesting: String {
		guard completions.isVisible else { return "no list" }
		let frame = completions.frameForTesting
		let caret = activeTab?.codeView?.caretScreenPoint() ?? .zero
		return "\(completions.labelsForTesting.count) items: "
			+ completions.labelsForTesting.prefix(6).joined(separator: ", ")
			+ String(format: " | list at (%.0f, %.0f) %.0fx%.0f, caret at (%.0f, %.0f)",
				frame.minX, frame.minY, frame.width, frame.height, caret.x, caret.y)
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

	/// Where the caret is and what is selected, for checking a motion landed.
	var caretReportForTesting: String {
		guard let codeView = activeTab?.codeView else { return "no editor" }
		return codeView.caretReportForTesting
	}

	/// Presses ⌘/ over a caret or a selection the spec names.
	func toggleCommentForTesting(_ spec: String) -> (LineComment.Outcome, String)? {
		guard let codeView = activeTab?.codeView else { return nil }
		view.window?.makeFirstResponder(codeView)
		return codeView.toggleCommentForTesting(spec)
	}

	/// Indents or outdents whole lines, the way Tab and ⇧Tab do.
	func indentForTesting(fromLine: Int, toLine: Int, outdent: Bool) -> String? {
		guard let tab = activeTab, let codeView = tab.codeView else { return nil }
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

	func simulateTyping(_ text: String) {
		guard let tab = activeTab, let codeView = tab.codeView else { return }
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
		guard let tab = activeTab, let codeView = tab.codeView else { return [] }
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
			guard let project, let languageId = document.languageId else { continue }
			LanguageService.shared.changed(
				url: tab.url, languageId: languageId, text: text(of: document), project: project.scopeRoot
			)
			LanguageService.shared.saved(
				url: tab.url, languageId: languageId, text: text(of: document), project: project.scopeRoot
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

/// Holds the 3D preview, sized by hand.
///
/// The preview is a SwiftUI view, and letting it size itself through Auto
/// Layout puts it in the window's constraint pass — where re-parenting it, as
/// splitting the editor does, raises.
private final class ModelContainerView: ColoredView, SnapshotDrawable {
	/// GoSTL's way of rendering the current scene into an image.
	///
	/// The viewer draws through Metal, and a window capture walks the view
	/// tree — where a Metal layer's contents are not. Without this the model
	/// photographs as an empty rectangle.
	var snapshot: ContentView.EmbeddingOptions.SnapshotProvider?

	/// Builds the viewer, and is thrown away once it has.
	var makeViewer: (() -> NSView)?

	/// How long this pane must have been on screen before that happens.
	var startAfter: TimeInterval = 0

	private var pending: DispatchWorkItem?

	/// Built on being *shown*, not on being made.
	///
	/// Which is the whole guard. A provisional tab is created, activated and then
	/// replaced in place by the next row of the tree, so a pane that leaves the
	/// window before its delay is up has its work cancelled and renders nothing;
	/// and a session restored with twenty model tabs lays out only the one in
	/// front, so the other nineteen cost nothing at all until somebody clicks
	/// them. Keying off creation instead would have paid for all twenty at once,
	/// on the main actor, before the window was even up.
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		guard window != nil else {
			pending?.cancel()
			pending = nil
			return
		}
		guard makeViewer != nil, pending == nil else { return }
		let work = DispatchWorkItem { [weak self] in
			guard let self, let make = self.makeViewer else { return }
			// Cleared first: the viewer is built once, and this pane may be shown
			// and hidden many times.
			self.makeViewer = nil
			self.pending = nil
			let viewer = make()
			viewer.frame = self.bounds
			self.addSubview(viewer)
		}
		pending = work
		DispatchQueue.main.asyncAfter(deadline: .now() + startAfter, execute: work)
	}

	override func layout() {
		super.layout()
		for subview in subviews { subview.frame = bounds }
	}

	func snapshotImage(size: CGSize) -> CGImage? { snapshot?(size) }
}
