import AppKit
import GoSTL
import IdeaiKit
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
	/// Asked for everywhere a symbol is used, at a zero-based position.
	var onFindUsages: ((URL, Int, Int) -> Void)?
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
	var activeDocument: TextDocument? { activeTab?.document }

	/// Breakpoints to draw, per absolute file path, with verification state.
	private var breakpointsByFile: [String: [Int: Bool]] = [:]
	private var runnableLinesByFile: [String: Set<Int>] = [:]
	/// Where execution is currently stopped.
	private var executionLocation: (file: String, line: Int)?

	// MARK: - View

	override func loadView() {
		let container = EditorDropView(color: Theme.current.editorBackground)

		tabBar = EditorTabBar()
		tabBar.onSelect = { [weak self] index in self?.activate(index: index, focusEditor: true) }
		tabBar.onClose = { [weak self] index in self?.closeTab(at: index) }
		tabBar.onPromote = { [weak self] index in self?.promoteToPermanent(index: index) }
		tabBar.onNewScratch = { [weak self] in self?.newScratch() }
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

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(diagnosticsChanged(_:)),
			name: .ideaiDiagnosticsChanged,
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

		for subview in [tabBar, findBar, contentArea, placeholder, scratchButton] as [NSView] {
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

		NSLayoutConstraint.activate([
			tabBarTopConstraint,
			tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			tabBarHeightConstraint,

			findBar.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
			findBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			findBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			findBarHeight,

			contentArea.topAnchor.constraint(equalTo: findBar.bottomAnchor),
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
		onStatusChanged?(self)
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
	func newScratch() {
		guard let root = project?.root else { return }
		do {
			let url = try ScratchFiles(projectRoot: root).create()
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
	func open(fileURL: URL, focusEditor: Bool = false, preview: Bool = false) {
		let departure = currentPlace
		defer {
			DispatchQueue.main.async { [weak self] in
				guard let self, let arrival = self.currentPlace else { return }
				self.reportNavigation(from: departure, to: arrival)
			}
		}

		if let existing = tabs.firstIndex(where: { $0.url == fileURL }) {
			// Committing to a file that is currently provisional pins it.
			if !preview { tabs[existing].isPreview = false }
			activate(index: existing, focusEditor: focusEditor)
			return
		}

		guard let tab = makeTab(for: fileURL, preview: preview) else { return }

		if preview, let previewIndex = tabs.firstIndex(where: { $0.isPreview }) {
			// Replace the provisional tab in place, so it does not jump position.
			teardown(tabs[previewIndex])
			tabs[previewIndex] = tab
			activate(index: previewIndex, focusEditor: focusEditor)
		} else {
			let insertAt = activeIndex.map { $0 + 1 } ?? tabs.count
			tabs.insert(tab, at: min(insertAt, tabs.count))
			activate(index: min(insertAt, tabs.count - 1), focusEditor: focusEditor)
		}
	}

	private func makeTab(for fileURL: URL, preview: Bool) -> Tab? {
		// Rendering a huge or binary blob as text helps nobody, but refusing to
		// open it is not the answer either — the tab explains itself and offers
		// the hex viewer instead.
		// A mesh has no source worth reading, so it opens rendered. Checked
		// before the size and binary tests, both of which an STL fails on its
		// way to being useful.
		if FilePreview.defaultMode(for: fileURL) == .preview, FilePreview.hasPreview(fileURL) {
			return makeModelTab(for: fileURL, preview: preview)
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
			LanguageService.shared.saved(
				url: fileURL, languageId: languageId, text: self.text(of: document), project: project.root
			)
		}

		codeView.onToggleBreakpoint = { [weak self] line in
			// The gutter works in 0-based lines; everything outside is 1-based.
			self?.onToggleBreakpoint?(fileURL, line + 1)
		}
		codeView.onEditBreakpoint = { [weak self] line in
			self?.onEditBreakpoint?(fileURL, line + 1)
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
				url: fileURL, languageId: languageId, text: text(of: document), project: project.root
			)
			codeView.setDiagnostics(LanguageService.shared.diagnostics(for: fileURL))
		}
		return tab
	}

	// MARK: - Language servers

	/// Whole text of a document, which is what full synchronisation sends.
	private func text(of document: TextDocument) -> String {
		document.rope.string(in: 0..<document.rope.byteCount)
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
			LanguageService.shared.changed(
				url: tab.url, languageId: languageId, text: self.text(of: document), project: project.root
			)
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
				project: project.root
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
			codeView?.applyCompletion(item.insertText, replacingPrefixOfLength: self.completionPrefixLength)
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
				project: project.root
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
	func setBreakpoints(_ breakpoints: [String: [Int: Bool]]) {
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
		codeView.setBreakpoints(
			Dictionary(uniqueKeysWithValues: stored.map { ($0.key - 1, $0.value) })
		)
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
		guard let text = activeTab?.codeView?.selectedText(), !text.isEmpty, !text.contains("\n") else {
			return nil
		}
		return text
	}

	// MARK: - Find in file

	/// Opens the find bar, seeded with the selection when there is one.
	func showFind() {
		guard activeTab?.codeView != nil else { return }
		findBar.isHidden = false
		findBarHeight.constant = Theme.current.scaled(34)

		if let selected = activeTab?.codeView?.selectedText(), !selected.isEmpty, !selected.contains("\n") {
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
	func open(fileURL: URL, atLine line: Int) {
		let departure = currentPlace
		isReportingSuppressed += 1
		open(fileURL: fileURL, focusEditor: true, preview: false)
		isReportingSuppressed -= 1
		reportNavigation(
			from: departure,
			to: (fileURL, line)
		)
		// Deferred: a freshly opened document has not laid out yet, so scrolling
		// now would compute against a zero-height view.
		DispatchQueue.main.async { [weak self] in
			self?.activeTab?.codeView?.reveal(line: line)
		}
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

	/// The view for a tab in a given mode.
	private func makeContentView(for tab: Tab, mode: PreviewMode) -> NSView {
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

		DispatchQueue.main.async { [weak split] in
			guard let split else { return }
			let total = mode.splitsSideBySide ? split.bounds.width : split.bounds.height
			guard total > 0 else { return }
			split.setPosition(total / 2, ofDividerAt: 0)
		}
		return split
	}

	/// The rendered form of a file, whichever kind it has.
	private func makePreview(for tab: Tab) -> NSView {
		switch FilePreview.kind(for: tab.url) {
		case .model:
			return makeModelView(for: tab.url)
		case .markdown, .none:
			return makePreviewView(for: tab)
		}
	}

	private func makePreviewView(for tab: Tab) -> NSView {
		let textView = NSTextView()
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
		return scrollView
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

	/// A tab showing a 3D model, hosted from GoSTL.
	///
	/// The viewer is a SwiftUI view from a package rather than a second
	/// application, so it lives in a tab beside the code like any other file.
	/// Hosts the 3D viewer on the editor's own background.
	///
	/// A SwiftUI view leaves its unpainted regions transparent, which against
	/// the window shows through as a different shade from the code beside it.
	/// The container settles that without GoSTL having to know about it.
	private func makeModelView(for fileURL: URL) -> NSView {
		let container = ModelContainerView(color: Theme.current.editorBackground)
		// The viewer sits in a pane rather than a window of its own: it takes the
		// editor's background so the split reads as one surface, and keeps its
		// menu panel folded away, since the panel is wider than the pane often is.
		let hosting = NSHostingView(rootView: ContentView(
			fileURL: fileURL,
			embedding: ContentView.EmbeddingOptions(
				backgroundColor: Theme.current.editorBackground,
				showsMenuPanel: false
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
		hosting.frame = container.bounds
		container.addSubview(hosting)
		return container
	}

	/// Shows a view of the app's own in a tab, or brings back the one that is
	/// already open.
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

	/// The open page with this identifier, if it is open.
	func page(identifier: String) -> NSView? {
		let url = URL(fileURLWithPath: "/ideai/page/" + identifier)
		return tabs.first { $0.pageTitle != nil && $0.url == url }?.contentView
	}

	private func makeModelTab(for fileURL: URL, preview: Bool) -> Tab {
		let tab = Tab(
			url: fileURL,
			document: nil,
			codeView: nil,
			contentView: makeModelView(for: fileURL),
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
		onStatusChanged?(self)
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
			tabBar.setPreview(
				modes: FilePreview.availableModes(for: tab.url),
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

		// A file nobody has open is one the server can stop thinking about.
		let closing = tabs[index]
		if let project, let languageId = closing.document?.languageId,
		   !tabs.contains(where: { $0 !== closing && $0.url == closing.url }) {
			LanguageService.shared.closed(url: closing.url, languageId: languageId, project: project.root)
		}

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
					isPreview: tab.isPreview
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
			open(fileURL: url, focusEditor: false, preview: file.isPreview)
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

	func simulateTyping(_ text: String) {
		guard let tab = activeTab, let codeView = tab.codeView else { return }
		view.window?.makeFirstResponder(codeView)
		for character in text {
			codeView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
		}
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

			// And tell the language server, or its diagnostics go on describing
			// the file as it was — which after something else has just fixed
			// one of them is the wrong answer written in red.
			guard let project, let languageId = document.languageId else { continue }
			LanguageService.shared.changed(
				url: tab.url, languageId: languageId, text: text(of: document), project: project.root
			)
			LanguageService.shared.saved(
				url: tab.url, languageId: languageId, text: text(of: document), project: project.root
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
		for tab in tabs {
			tab.codeView?.setWordWrap(Settings.shared.wordWrap)
			tab.codeView?.applyThemeChange()
		}
	}

	func windowWillClose() {
		autoSaveAll()
		for tab in tabs { teardown(tab) }
		tabs.removeAll()
		NotificationCenter.default.removeObserver(self)
	}
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

	override var isFlipped: Bool { true }

	func setPosition(line: Int, column: Int) {
		positionText = "\(line):\(column)"
		needsDisplay = true
	}

	func setLanguage(_ name: String?) {
		languageText = name ?? "Plain Text"
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
		let inside = languageRect.contains(convert(event.locationInWindow, from: nil))
		guard inside != isLanguageHovered else { return }
		isLanguageHovered = inside
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent) {
		guard isLanguageHovered else { return }
		isLanguageHovered = false
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		guard languageRect.contains(point) else { return }
		showLanguageMenu(at: NSPoint(x: languageRect.minX, y: languageRect.maxY))
	}

	override func resetCursorRects() {
		super.resetCursorRects()
		addCursorRect(languageRect, cursor: .pointingHand)
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
		Theme.current.sidebarBackground.setFill()
		bounds.fill()

		Theme.current.separator.setFill()
		NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()

		let attributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(11),
			.foregroundColor: Theme.current.gitIgnored,
		]

		// Right-aligned, position then language.
		var x = bounds.width - Theme.current.scaled(12)
		for (index, text) in [languageText, positionText].enumerated() where !text.isEmpty {
			let attributed = NSAttributedString(string: text, attributes: attributes)
			let size = attributed.size()
			x -= size.width
			let origin = NSPoint(x: x, y: bounds.midY - size.height / 2)

			// The language is a control, so it gets a hit area and a hover
			// background — otherwise nothing suggests it can be clicked.
			if index == 0 {
				let padding = Theme.current.scaled(5)
				languageRect = NSRect(
					x: origin.x - padding,
					y: bounds.midY - size.height / 2 - padding / 2,
					width: size.width + padding * 2,
					height: size.height + padding
				)
				if isLanguageHovered {
					NSColor.white.withAlphaComponent(0.08).setFill()
					NSBezierPath(roundedRect: languageRect, xRadius: 4, yRadius: 4).fill()
				}
			}

			attributed.draw(at: origin)
			x -= Theme.current.scaled(16)
		}
	}
}

/// Holds the 3D preview, sized by hand.
///
/// The preview is a SwiftUI view, and letting it size itself through Auto
/// Layout puts it in the window's constraint pass — where re-parenting it, as
/// splitting the editor does, raises.
private final class ModelContainerView: ColoredView {
	override func layout() {
		super.layout()
		for subview in subviews { subview.frame = bounds }
	}
}
