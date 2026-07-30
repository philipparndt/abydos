import AppKit
import IdeaiKit

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
	private final class Tab {
		let url: URL
		/// nil for anything not opened as text.
		var document: TextDocument?
		var codeView: CodeView?
		/// The view installed in the content area.
		var contentView: NSView
		/// Provisional tabs are replaced by the next preview open instead of
		/// accumulating. Exactly one may exist at a time.
		var isPreview: Bool

		/// The source view, kept so the markdown preview can toggle back to it.
		var sourceView: NSView?
		var isShowingMarkdownPreview = false
		var isMarkdown: Bool { document?.languageId == "markdown" }

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

	private var tabBar: EditorTabBar!
	private var tabBarTopConstraint: NSLayoutConstraint!
	private var tabBarHeightConstraint: NSLayoutConstraint!
	private var statusBarHeightConstraint: NSLayoutConstraint!
	private var contentArea: NSView!
	private var statusBar: EditorStatusView!
	private var placeholder: NSTextField!

	/// Notifies the window when the active file changes, so the tree can follow.
	var onActiveFileChanged: ((URL?) -> Void)?

	/// Called when the breakpoint gutter is clicked, with a 1-based line.
	var onToggleBreakpoint: ((URL, Int) -> Void)?

	/// Breakpoints to draw, per absolute file path, with verification state.
	private var breakpointsByFile: [String: [Int: Bool]] = [:]
	/// Where execution is currently stopped.
	private var executionLocation: (file: String, line: Int)?

	// MARK: - View

	override func loadView() {
		let container = ColoredView(color: Theme.current.editorBackground)

		tabBar = EditorTabBar()
		tabBar.onSelect = { [weak self] index in self?.activate(index: index, focusEditor: true) }
		tabBar.onClose = { [weak self] index in self?.closeTab(at: index) }
		tabBar.onPromote = { [weak self] index in self?.promoteToPermanent(index: index) }

		contentArea = NSView()
		statusBar = EditorStatusView()

		findBar = FindBar()
		findBar.isHidden = true
		findBar.onQueryChanged = { [weak self] query, options in
			self?.scheduleFind(query: query, options: options)
		}
		findBar.onNext = { [weak self] in self?.stepMatch(by: 1) }
		findBar.onPrevious = { [weak self] in self?.stepMatch(by: -1) }
		findBar.onClose = { [weak self] in self?.closeFind() }

		placeholder = NSTextField(labelWithString: "Select a file to open")
		placeholder.font = Theme.current.uiFont(13)
		placeholder.textColor = Theme.current.gitIgnored
		placeholder.alignment = .center

		for subview in [tabBar, findBar, contentArea, statusBar, placeholder] as [NSView] {
			container.addSubview(subview)
			subview.translatesAutoresizingMaskIntoConstraints = false
		}

		// Set from the window's actual titlebar height rather than hardcoded; the
		// titlebar is taller with a toolbar than without, and guessing clips the
		// tab bar.
		tabBarTopConstraint = tabBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 40)
		tabBarHeightConstraint = tabBar.heightAnchor.constraint(equalToConstant: EditorTabBar.height)
		statusBarHeightConstraint = statusBar.heightAnchor.constraint(equalToConstant: Theme.current.scaled(24))
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
			contentArea.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

			statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
			statusBarHeightConstraint,

			placeholder.centerXAnchor.constraint(equalTo: container.centerXAnchor),
			placeholder.centerYAnchor.constraint(equalTo: container.centerYAnchor),
		])

		view = container
		updateChrome()
	}

	private func updateChrome() {
		let hasTabs = !tabs.isEmpty
		placeholder.isHidden = hasTabs
		tabBar.isHidden = !hasTabs
		statusBar.isHidden = !hasTabs
		contentArea.isHidden = !hasTabs
	}

	/// Distance from the top of the window to the first row of content.
	func setTopInset(_ inset: CGFloat) {
		tabBarTopConstraint.constant = inset
	}

	// MARK: - Project

	func setProject(_ project: Project) {
		self.project = project
	}

	// MARK: - Opening

	/// Opens a file.
	///
	/// - `preview`: a single click in the tree opens provisionally, reusing the
	///   one preview slot. A double-click (or editing) makes it permanent.
	/// - Already-open files are activated rather than reopened, which is what
	///   makes clicking a file in the tree select its existing tab.
	func open(fileURL: URL, focusEditor: Bool = false, preview: Bool = false) {
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
		scrollView.scrollerStyle = .overlay
		scrollView.contentView.postsBoundsChangedNotifications = true

		// The gutter is drawn relative to the clip view, so a horizontal scroll
		// has to repaint even though the document content did not change.
		NotificationCenter.default.addObserver(
			forName: NSView.boundsDidChangeNotification,
			object: scrollView.contentView,
			queue: .main
		) { [weak codeView] _ in
			codeView?.needsDisplay = true
		}

		let tab = Tab(url: fileURL, document: document, codeView: codeView, contentView: scrollView, isPreview: preview)

		codeView.onCaretMoved = { [weak self] line, column in
			guard let self, self.activeTab === tab else { return }
			self.statusBar.setPosition(line: line, column: column)
		}
		codeView.onDirtyChanged = { [weak self] _ in
			// Editing a provisional tab is a commitment to it, the same rule
			// VS Code and IDEA use.
			tab.isPreview = false
			self?.refreshTabBar()
		}
		// Auto save clears the dirty marker without any further user action.
		document.onAutoSaved = { [weak self] in
			self?.refreshTabBar()
		}

		codeView.onToggleBreakpoint = { [weak self] line in
			// The gutter works in 0-based lines; everything outside is 1-based.
			self?.onToggleBreakpoint?(fileURL, line + 1)
		}
		codeView.load(document: document)
		codeView.setWordWrap(Settings.shared.wordWrap)
		applyDebugState(to: tab)
		tab.sourceView = scrollView
		return tab
	}

	// MARK: - Debugging

	/// Sets the breakpoints to draw, keyed by absolute path.
	func setBreakpoints(_ breakpoints: [String: [Int: Bool]]) {
		breakpointsByFile = breakpoints
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
		let path = tab.url.standardizedFileURL.path

		codeView.setBreakpoints(breakpointsByFile[path] ?? [:])

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
		open(fileURL: fileURL, focusEditor: true, preview: false)
		// Deferred: a freshly opened document has not laid out yet, so scrolling
		// now would compute against a zero-height view.
		DispatchQueue.main.async { [weak self] in
			self?.activeTab?.codeView?.reveal(line: line)
		}
	}

	// MARK: - Markdown preview

	/// Swaps the active markdown tab between source and rendered preview.
	func toggleMarkdownPreview() {
		guard let tab = activeTab, tab.isMarkdown, let index = activeIndex else { return }

		if tab.isShowingMarkdownPreview {
			guard let source = tab.sourceView else { return }
			tab.contentView = source
			tab.isShowingMarkdownPreview = false
		} else {
			tab.contentView = makePreviewView(for: tab)
			tab.isShowingMarkdownPreview = true
		}

		activeIndex = nil
		activate(index: index, focusEditor: false)
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

	/// A tab for a file that cannot be shown as text.
	private func makeNoticeTab(for fileURL: URL, reason: String, preview: Bool) -> Tab {
		let notice = FileNoticeView(url: fileURL, reason: reason)
		let tab = Tab(url: fileURL, document: nil, codeView: nil, contentView: notice, isPreview: preview)

		notice.onOpenExternally = { NSWorkspace.shared.open(fileURL) }
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
		statusBar.setLanguage(tab.document?.displayLanguageName)
		updateChrome()
		refreshTabBar()

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
			EditorTabItem(
				url: tab.url,
				isDirty: tab.isDirty,
				isPreview: tab.isPreview,
				subtitle: relativeDirectory(for: tab.url)
			)
		}
		tabBar.setItems(items, activeIndex: activeIndex)
	}

	private func relativeDirectory(for url: URL) -> String {
		guard let root = project?.root, url.path.hasPrefix(root.path + "/") else { return "" }
		let relative = String(url.path.dropFirst(root.path.count + 1))
		return (relative as NSString).deletingLastPathComponent
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

		teardown(tab)
		tabs.remove(at: index)

		if tabs.isEmpty {
			activeIndex = nil
			contentArea.subviews.forEach { $0.removeFromSuperview() }
			updateChrome()
			refreshTabBar()
			onActiveFileChanged?(nil)
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
				NSAlert(error: error).runModal()
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
		let alert = NSAlert()
		alert.alertStyle = .informational
		alert.messageText = "Cannot open \(url.lastPathComponent)"
		alert.informativeText = reason
		alert.runModal()
	}

	// MARK: - Commands

	func save() {
		guard let tab = activeTab else { return }
		do {
			try tab.document?.save()
			refreshTabBar()
		} catch {
			NSAlert(error: error).runModal()
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

	/// Routes text through `NSTextInputClient.insertText`, the same entry point
	/// a real keystroke takes.
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

	/// Re-reads settings that affect the editor and repaints.
	func applySettings() {
		tabBarHeightConstraint.constant = EditorTabBar.height
		statusBarHeightConstraint.constant = Theme.current.scaled(24)
		placeholder.font = Theme.current.uiFont(13)
		tabBar.applyThemeChange()
		findBar.applyThemeChange()
		if !findBar.isHidden { findBarHeight.constant = Theme.current.scaled(34) }
		statusBar.needsDisplay = true
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

private final class EditorStatusView: NSView {
	private var positionText = ""
	private var languageText = ""

	override var isFlipped: Bool { true }

	func setPosition(line: Int, column: Int) {
		positionText = "\(line):\(column)"
		needsDisplay = true
	}

	func setLanguage(_ name: String?) {
		languageText = name ?? "Plain Text"
		needsDisplay = true
	}

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
		for text in [languageText, positionText] where !text.isEmpty {
			let attributed = NSAttributedString(string: text, attributes: attributes)
			let size = attributed.size()
			x -= size.width
			attributed.draw(at: NSPoint(x: x, y: bounds.midY - size.height / 2))
			x -= Theme.current.scaled(16)
		}
	}
}
