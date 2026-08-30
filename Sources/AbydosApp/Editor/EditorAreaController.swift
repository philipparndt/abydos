import AppKit
import AbydosKit

/// Hosts one or more editor groups in a tree of splits.
///
/// Each pane is a full editor group with its own tabs and find bar, rather than
/// a shared set of tabs shown twice. The status line is the exception: there is
/// one for the window, showing whichever pane is active, because caret position
/// and language describe where you are working, and you work in one pane. Splits are built from nested
/// two-child `NSSplitView`s, which keeps the arrangement recursive: any pane can
/// be split again, horizontally or vertically, to any depth.
///
/// The window talks to this controller, which forwards to whichever group is
/// active, so the rest of the app is unaware there is more than one.
final class EditorAreaController: NSViewController {
	/// A tab was pulled out of every window and wants one of its own.
	var onTearOffTab: ((EditorViewController.Tab, NSPoint) -> Void)?
	/// Every group here is empty, which for a torn-off window means it is done.
	var onBecameEmpty: (() -> Void)?

	init() {
		super.init(nibName: nil, bundle: nil)
		EditorAreas.register(self)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func group(withID id: UUID) -> EditorViewController? {
		groups.first { $0.groupID == id }
	}

	/// Takes a tab into whichever group is active.
	func adopt(_ tab: EditorViewController.Tab) {
		guard let target = activeGroup ?? groups.first else { return }
		target.adopt(tab)
		activeGroup = target
	}

	/// The group a dragged tab came from, in this window or any other.
	private func source(
		for payload: EditorTabDrag.Payload
	) -> (area: EditorAreaController, group: EditorViewController)? {
		if let mine = group(withID: payload.groupID) { return (self, mine) }
		return EditorAreas.owner(ofGroup: payload.groupID)
	}

	/// Called after a tab is taken out, since the window it left may now be an
	/// empty one that only existed to hold it.
	private func noteTabRemoved() {
		guard groups.allSatisfy(\.isEmpty) else { return }
		onBecameEmpty?()
	}

	private(set) var groups: [EditorViewController] = []
	private(set) var activeGroup: EditorViewController! {
		didSet { refreshStatus(from: activeGroup) }
	}

	private var project: Project?
	private var topInset: CGFloat = 40

	/// Holds the split tree. Separate from `view` so the status bar below it
	/// survives the tree being rebuilt.
	private var splitHost: NSView!
	private var statusBar: EditorStatusView!
	private var statusBarHeightConstraint: NSLayoutConstraint!

	// Forwarded from the active group.
	/// Files dropped on any group in this area, in the order they were dropped.
	///
	/// Passed straight out. What a dropped file *means* — a tab here, a project
	/// for a folder, the tree told, the panel making room — belongs to the
	/// window, which already answers all of that for a file opened from a
	/// terminal.
	var onFilesDropped: (([URL]) -> Void)?
	var onActiveFileChanged: ((URL?) -> Void)?
	var onToggleBreakpoint: ((URL, Int) -> Void)?
	var onSetBreakpointEnabled: ((URL, Int, Bool) -> Void)?
	var onDeleteBreakpoint: ((URL, Int) -> Void)?
	var onSetOtherBreakpointsEnabled: ((URL, Int, Bool) -> Void)?
	var onLinesChanged: ((URL, Int, Int, Int) -> Void)?
	var onFileReloaded: ((URL) -> Void)?
	var onRunLine: ((URL, Int) -> Void)?
	var onApplyDiffSelection: ((GitChange, String, Set<Int>) -> Void)?
	var onDiscardDiffSelection: ((GitChange, String, Set<Int>) -> Void)?
	/// Nil where stashing a hunk is not possible — an old git — so the menu
	/// item is absent rather than failing when pressed.
	var onStashDiffSelection: ((GitChange, String, Set<Int>) -> Void)?

	override func loadView() {
		let container = ColoredView(color: Theme.current.editorBackground)
		view = container

		splitHost = NSView()
		statusBar = EditorStatusView()
		for subview in [splitHost, statusBar] as [NSView] {
			container.addSubview(subview)
			subview.translatesAutoresizingMaskIntoConstraints = false
		}

		statusBar.onLanguageChosen = { [weak self] languageId in
			self?.activeGroup?.setActiveLanguage(languageId)
		}
		statusBarHeightConstraint = statusBar.heightAnchor.constraint(
			equalToConstant: Theme.current.scaled(24)
		)
		NSLayoutConstraint.activate([
			splitHost.topAnchor.constraint(equalTo: container.topAnchor),
			splitHost.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			splitHost.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			splitHost.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

			statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
			statusBarHeightConstraint,
		])

		let first = makeGroup()
		activeGroup = first
		install(rootView: first.view)
	}

	/// Shows the active group's caret position, language and server.
	///
	/// Every caret move comes through here, so all three are reads of values the
	/// group is already holding. `statusServer` in particular is worked out when
	/// a server starts, stops or is refused — never here: the three draw in one
	/// view, and a lookup on this path would be a lookup per keystroke.
	private func refreshStatus(from group: EditorViewController?) {
		guard let group, group === activeGroup else { return }
		statusBar.isHidden = group.isEmpty
		statusBar.setPosition(line: group.statusLine, column: group.statusColumn)
		statusBar.setLanguage(group.statusLanguage)
		statusBar.setServer(group.statusServer)
	}

	// MARK: - Groups

	private func makeGroup() -> EditorViewController {
		let group = EditorViewController()
		// Force the view to load so its callbacks exist before use.
		_ = group.view
		group.setTopInset(topInset)
		if let project { group.setProject(project) }

		group.onActiveFileChanged = { [weak self] url in
			self?.onActiveFileChanged?(url)
		}
		group.onMaximize = { [weak self] in self?.onMaximize?() }
		group.onNavigated = { [weak self] departure, arrival in
			guard let self, self.recordsNavigation else { return }
			self.onNavigated?(departure, arrival)
		}
		group.onToggleBreakpoint = { [weak self] url, line in
			self?.onToggleBreakpoint?(url, line)
		}
		group.onEditBreakpoint = onEditBreakpoint
		group.onSetBreakpointEnabled = { [weak self] url, line, enabled in
			self?.onSetBreakpointEnabled?(url, line, enabled)
		}
		group.onDeleteBreakpoint = { [weak self] url, line in
			self?.onDeleteBreakpoint?(url, line)
		}
		group.onSetOtherBreakpointsEnabled = { [weak self] url, line, enabled in
			self?.onSetOtherBreakpointsEnabled?(url, line, enabled)
		}
		group.onLinesChanged = { [weak self] url, first, removed, inserted in
			self?.onLinesChanged?(url, first, removed, inserted)
		}
		group.onFileReloaded = { [weak self] url in
			self?.onFileReloaded?(url)
		}
		group.onFindUsages = onFindUsages
		group.onRename = onRename
		group.onWatch = onWatch
		group.onFixWithAI = onFixWithAI
		group.setConditionalBreakpoints(conditionalBreakpoints)
		group.onRunLine = { [weak self] url, line in
			self?.onRunLine?(url, line)
		}
		group.setRunnableLines(runnableLines)
		group.onApplyDiffSelection = { [weak self] change, diff, selected in
			self?.onApplyDiffSelection?(change, diff, selected)
		}
		group.onDiscardDiffSelection = { [weak self] change, diff, selected in
			self?.onDiscardDiffSelection?(change, diff, selected)
		}
		group.onStashDiffSelection = onStashDiffSelection == nil ? nil : { [weak self] change, diff, selected in
			self?.onStashDiffSelection?(change, diff, selected)
		}
		group.onActivated = { [weak self] activated in
			self?.activeGroup = activated
		}
		group.onTearOffTab = { [weak self] group, index, screenPoint in
			self?.tearOff(from: group, index: index, at: screenPoint)
		}
		group.onBecameEmpty = { [weak self] empty in
			// The last group stays even when empty; it is the editor area itself.
			self?.removeGroup(empty)
		}
		group.onTabsChanged = { [weak self] in self?.recordOpenScratches() }
		group.onStatusChanged = { [weak self] reporting in
			self?.refreshStatus(from: reporting)
		}
		group.onTabDropped = { [weak self] payload, zone, target in
			self?.handleDrop(payload: payload, zone: zone, target: target)
		}
		group.onFilesDropped = { [weak self] urls in self?.onFilesDropped?(urls) }
		group.onTabDroppedOnTabBar = { [weak self] payload, index, target in
			self?.handleTabBarDrop(payload: payload, index: index, target: target)
		}

		groups.append(group)
		addChild(group)
		return group
	}

	private func install(rootView: NSView) {
		splitHost.subviews.forEach { $0.removeFromSuperview() }
		rootView.translatesAutoresizingMaskIntoConstraints = false
		splitHost.addSubview(rootView)
		NSLayoutConstraint.activate([
			rootView.topAnchor.constraint(equalTo: splitHost.topAnchor),
			rootView.bottomAnchor.constraint(equalTo: splitHost.bottomAnchor),
			rootView.leadingAnchor.constraint(equalTo: splitHost.leadingAnchor),
			rootView.trailingAnchor.constraint(equalTo: splitHost.trailingAnchor),
		])
	}

	// MARK: - Splitting

	private func handleDrop(
		payload: EditorTabDrag.Payload,
		zone: EditorTabDrag.Zone,
		target: EditorViewController
	) {
		guard let (sourceArea, source) = source(for: payload) else { return }

		// Dropping a group's only tab back into itself would destroy and rebuild
		// the same pane for no reason.
		if source === target, zone == .center { return }
		if source === target, source.tabCount <= 1 { return }

		let index = source.indexOfTab(withPath: payload.path) ?? payload.index
		guard let tab = source.detachTab(at: index) else { return }
		sourceArea.noteTabRemoved()

		guard let splitsVertically = zone.splitsVertically else {
			target.adopt(tab)
			activeGroup = target
			return
		}

		let newGroup = makeGroup()
		newGroup.adopt(tab)
		split(target: target, with: newGroup, vertical: splitsVertically, before: zone.insertsBefore)
		activeGroup = newGroup
	}

	/// Moves a dropped tab into `target`'s strip at the slot it was released over.
	///
	/// Within one group this is a reorder; across groups it moves the tab, which
	/// may leave the source group empty and collapse its split.
	private func handleTabBarDrop(
		payload: EditorTabDrag.Payload,
		index: Int,
		target: EditorViewController
	) {
		guard let (sourceArea, source) = source(for: payload) else { return }
		let from = source.indexOfTab(withPath: payload.path) ?? payload.index

		if source === target {
			// The slot is measured against the strip as it looks now, with the tab
			// still in it, so removing an earlier tab shifts every later slot left.
			source.moveTab(from: from, to: index > from ? index - 1 : index)
			activeGroup = target
			return
		}

		guard let tab = source.detachTab(at: from) else { return }
		sourceArea.noteTabRemoved()
		target.adopt(tab, at: index)
		activeGroup = target
		view.window?.makeKeyAndOrderFront(nil)
	}

	/// Replaces `target`'s position in the tree with a split holding both panes.
	private func split(
		target: EditorViewController,
		with newGroup: EditorViewController,
		vertical: Bool,
		before: Bool
	) {
		let targetView = target.view
		let parent = targetView.superview

		let split = EditorGroupSplitView(vertical: vertical)

		// Where the target sat, the split now sits.
		let isRoot = (parent === splitHost)
		var indexInParent: Int?
		if let parentSplit = parent as? NSSplitView {
			indexInParent = parentSplit.arrangedSubviews.firstIndex(of: targetView)
		}

		targetView.removeFromSuperview()
		targetView.translatesAutoresizingMaskIntoConstraints = true

		if before {
			split.addArrangedSubview(newGroup.view)
			split.addArrangedSubview(targetView)
		} else {
			split.addArrangedSubview(targetView)
			split.addArrangedSubview(newGroup.view)
		}

		if isRoot {
			install(rootView: split)
		} else if let parentSplit = parent as? NSSplitView, let index = indexInParent {
			split.translatesAutoresizingMaskIntoConstraints = true
			parentSplit.insertArrangedSubview(split, at: index)
		}

		// Even halves, which is what a split gesture implies.
		split.divideEvenly()
		DispatchQueue.main.async { [weak self] in self?.updateGroupInsets() }
	}

	/// Removes an empty group and collapses the split that held it.
	/// Pulls a tab out into a window of its own.
	private func tearOff(from group: EditorViewController, index: Int, at screenPoint: NSPoint) {
		// A window's only tab has nowhere to go: it would empty this window to
		// fill an identical new one.
		guard groups.count > 1 || group.tabCount > 1 else { return }
		guard let tab = group.detachTab(at: index) else { return }
		onTearOffTab?(tab, screenPoint)
	}

	// MARK: - Testing

	/// The active group's identifier, for building a drag payload in a test run.
	var activeGroupID: UUID? { (activeGroup ?? groups.first)?.groupID }

	/// The split holding the groups, so a capture run can move a divider
	/// without a mouse: a drag is a `setPosition` and a layout pass.
	/// Every open tab in the group in front, in strip order, with the active one
	/// marked — for a report about what a gesture opened.
	var openTabNamesForTesting: String {
		guard let group = activeGroup ?? groups.first else { return "no group" }
		return group.tabNamesForTesting
	}

	/// How many groups the area is split into.
	var groupCountForTesting: Int { groups.count }

	var rootSplitForTesting: NSSplitView? { splitHost.subviews.first as? NSSplitView }

	var activeTabCount: Int { (activeGroup ?? groups.first)?.tabCount ?? 0 }

	/// Tears a tab off as a drag ending outside every window would.
	func quickLookForTesting() -> String {
		activeGroup?.quickLookForTesting() ?? "no group"
	}

	func doubleClickTabForTesting(index: Int) -> String {
		activeGroup?.doubleClickTabForTesting(index: index) ?? "no group"
	}

	func tearOffForTesting(index: Int, at screenPoint: NSPoint) {
		guard let group = activeGroup ?? groups.first else { return }
		tearOff(from: group, index: index, at: screenPoint)
	}

	/// Drops a tab from another window onto this area's strip, as a drag would.
	func dropForTesting(payload: EditorTabDrag.Payload, at index: Int) {
		guard let target = activeGroup ?? groups.first else { return }
		handleTabBarDrop(payload: payload, index: index, target: target)
	}

	private func removeGroup(_ group: EditorViewController) {
		// The last pane is the editor area itself; an empty one is the "no file
		// open" state rather than something to remove.
		guard groups.count > 1 else { return }

		let groupView = group.view
		let parent = groupView.superview
		groups.removeAll { $0 === group }
		group.removeFromParent()
		groupView.removeFromSuperview()

		guard let parentSplit = parent as? NSSplitView else { return }

		// A split with one child left is no longer a split.
		if parentSplit.arrangedSubviews.count == 1 {
			let survivor = parentSplit.arrangedSubviews[0]
			let grandparent = parentSplit.superview
			survivor.removeFromSuperview()

			if grandparent === splitHost {
				install(rootView: survivor)
			} else if let grandSplit = grandparent as? NSSplitView,
			          let index = grandSplit.arrangedSubviews.firstIndex(of: parentSplit) {
				parentSplit.removeFromSuperview()
				survivor.translatesAutoresizingMaskIntoConstraints = true
				grandSplit.insertArrangedSubview(survivor, at: index)
			}
		}

		if activeGroup === group || activeGroup == nil {
			activeGroup = groups.first
		}
		DispatchQueue.main.async { [weak self] in self?.updateGroupInsets() }
	}

	// MARK: - Forwarding

	func setProject(_ project: Project) {
		self.project = project
		for group in groups { group.setProject(project) }
	}

	/// What is open across the area.
	///
	/// Flattened across split groups: the tabs come back, the arrangement they
	/// were split into does not.
	func captureSession() -> ProjectSession {
		var files: [ProjectSession.OpenFile] = []
		for group in groups { files += group.captureSession().files }
		return ProjectSession(files: files, activePath: activeGroup?.captureSession().activePath)
	}

	func restore(_ session: ProjectSession) {
		recordsNavigation = false
		rearranging { (activeGroup ?? groups.first)?.restore(session) }
		// After the opens have settled, since each reports itself a runloop
		// turn later.
		DispatchQueue.main.async { [weak self] in self?.recordsNavigation = true }
	}

	/// Reopens the project's scratches, in whichever group is in front.
	func restoreScratches() {
		rearranging { (activeGroup ?? groups.first)?.restoreScratches() }
	}

	/// Writes down which scratches are open, across every pane.
	///
	/// Called on any tab change rather than at quit: a window that never gets
	/// to say goodbye — a crash, a force quit — should still come back right.
	private func recordOpenScratches() {
		guard let project, !isClosing, suppressedRecording == 0 else { return }
		let open = groups.flatMap(\.openScratchURLs).map(\.path)
		OpenScratches().record(open, forProject: project.sessionRoot)

		// And what is open generally, on every change rather than at quit: a
		// window that never gets to say goodbye — a crash, a force quit, a
		// capture run — should still come back to the same files.
		//
		// Merged rather than written over. Only the editor's half is known
		// here; the terminals, the panel, the subproject and the chosen
		// configuration belong to the window, and writing what this knows over
		// what it does not would drop them every time a tab changed.
		var session = SessionStore.read(in: project.sessionRoot) ?? ProjectSession()
		let captured = captureSession()
		session.files = captured.files
		session.activePath = captured.activePath
		try? SessionStore.write(session, in: project.sessionRoot)
	}

	/// Emptying and refilling the window is not the user closing tabs.
	///
	/// Clearing first would otherwise record "nothing is open" and then read
	/// that back as what to restore, so swapping projects would quietly lose
	/// every scratch tab. Recorded once, when the dust has settled.
	private var suppressedRecording = 0
	private var isClosing = false

	private func rearranging(record: Bool = true, _ body: () -> Void) {
		suppressedRecording += 1
		body()
		suppressedRecording -= 1
		if record { recordOpenScratches() }
	}

	func openCommitDiff(commit: GitCommit, file: GitCommitFile, root: URL, text: String) {
		(activeGroup ?? groups.first)?.openCommitDiff(commit: commit, file: file, root: root, text: text)
	}

	func simulateKey(_ key: String, modifiers: NSEvent.ModifierFlags) {
		(activeGroup ?? groups.first)?.simulateKey(key, modifiers: modifiers)
	}

	var completionReportForTesting: String {
		(activeGroup ?? groups.first)?.completionReportForTesting ?? "none"
	}

	var completionDocumentationForTesting: String {
		(activeGroup ?? groups.first)?.completionDocumentationForTesting ?? "none"
	}

	var parameterHintForTesting: String {
		(activeGroup ?? groups.first)?.parameterHintForTesting ?? "none"
	}

	@discardableResult
	func writeEditorImageForTesting(to path: String) -> Bool {
		(activeGroup ?? groups.first)?.writeEditorImageForTesting(to: path) ?? false
	}

	@discardableResult
	func writeCompletionImageForTesting(to path: String) -> Bool {
		(activeGroup ?? groups.first)?.writeCompletionImageForTesting(to: path) ?? false
	}

	@discardableResult
	func commitCompletionForTesting() -> Bool {
		(activeGroup ?? groups.first)?.commitCompletionForTesting() ?? false
	}

	func moveCompletionSelectionForTesting(by delta: Int) {
		(activeGroup ?? groups.first)?.moveCompletionSelectionForTesting(by: delta)
	}

	func moveCaretToEndForTesting() {
		(activeGroup ?? groups.first)?.moveCaretToEndForTesting()
	}

	func setCaretForTesting(line: Int, column: Int) {
		(activeGroup ?? groups.first)?.setCaretForTesting(line: line, column: column)
	}

	var caretReportForTesting: String {
		(activeGroup ?? groups.first)?.caretReportForTesting ?? "no editor"
	}

	var revealReportForTesting: String {
		(activeGroup ?? groups.first)?.revealReportForTesting ?? "no editor"
	}

	var caretLinesForTesting: String {
		(activeGroup ?? groups.first)?.caretLinesForTesting ?? "no file"
	}

	func toggleFileHistory() {
		(activeGroup ?? groups.first)?.toggleFileHistory()
	}

	func focusForTesting() {
		guard let group = activeGroup ?? groups.first, let codeView = group.view.window else { return }
		_ = codeView
		group.focusForTesting()
	}

	func simulateReturn() {
		(activeGroup ?? groups.first)?.simulateReturn()
	}

	func simulateTab() {
		(activeGroup ?? groups.first)?.simulateTab()
	}

	func simulateEscape() {
		(activeGroup ?? groups.first)?.simulateEscape()
	}

	func textTailLinesForTesting(_ count: Int) -> [String] {
		(activeGroup ?? groups.first)?.textTailLinesForTesting(count) ?? []
	}

	func goToDefinitionForTesting(line: Int, character: Int) {
		(activeGroup ?? groups.first)?.goToDefinitionForTesting(line: line, character: character)
	}

	func hoverWithCommandForTesting(line: Int, character: Int) {
		(activeGroup ?? groups.first)?.hoverWithCommandForTesting(line: line, character: character)
	}

	func undoForTesting() {
		(activeGroup ?? groups.first)?.undoForTesting()
	}

	var textTailForTesting: String {
		(activeGroup ?? groups.first)?.textTailForTesting ?? "no file"
	}

	func lineTextForTesting(_ line: Int) -> String {
		(activeGroup ?? groups.first)?.lineTextForTesting(line) ?? "no file"
	}

	var fileHistoryReportForTesting: String {
		(activeGroup ?? groups.first)?.fileHistoryReportForTesting ?? "no file"
	}

	var historySummariesForTesting: [String] {
		(activeGroup ?? groups.first)?.historySummariesForTesting ?? []
	}

	func travelToHistoryRowForTesting(_ index: Int) {
		(activeGroup ?? groups.first)?.travelToHistoryRowForTesting(index)
	}

	func newScratch() {
		(activeGroup ?? groups.first)?.newScratch()
	}

	/// Every group follows a scratch that moved; only one of them has it open.
	func scratchMoved(from: URL, to destination: URL?) {
		for group in groups { group.scratchMoved(from: from, to: destination) }
	}

	func saveIfOpen(_ url: URL) {
		for group in groups { group.saveIfOpen(url) }
	}

	/// The scope moved: every group's files are announced to the servers for the
	/// new root.
	func rescope() {
		for group in groups { group.rescope() }
	}

	func clickScratchPlaceholderForTesting() -> Bool {
		(activeGroup ?? groups.first)?.clickScratchPlaceholderForTesting() ?? false
	}

	/// Empties the window, for swapping one project's editors for another's.
	///
	/// Deliberately leaves the record alone: this is always half of a swap, and
	/// what is restored a moment later is read from it.
	func closeAllTabs() {
		rearranging(record: false) { for group in groups { group.closeAllTabs() } }
	}

	func previewDropZoneForTesting(_ zone: EditorTabDrag.Zone) {
		(activeGroup?.view as? EditorDropView)?.previewZoneForTesting(zone)
	}

	func setTopInset(_ inset: CGFloat) {
		topInset = inset
		updateGroupInsets()
	}

	/// Applies the titlebar inset only to panes that actually touch the top.
	///
	/// The inset exists to clear the titlebar, which the window draws over the
	/// content view. A pane below a horizontal split has the pane above it as a
	/// neighbour, not the titlebar, so giving it the same inset leaves a band of
	/// empty space between the two.
	private func updateGroupInsets() {
		for group in groups {
			group.setTopInset(touchesTop(group) ? topInset : 0)
		}
	}

	/// Whether the titlebar is above this pane, rather than another pane.
	///
	/// Read from the split tree rather than by comparing frames. A pane's frame
	/// can still be the old one while its parent has already taken the new size
	/// — which is what a zoom change does, since the tool strip's width changes
	/// and everything to its right resizes. A pane that does touch the top then
	/// measures as though it does not, loses its inset, and tucks its tab bar
	/// under the titlebar, with no later layout pass to put it right.
	private func touchesTop(_ group: EditorViewController) -> Bool {
		var view: NSView = group.view
		while let parent = view.superview {
			// Only a stacked split puts a pane below another. Side by side, both
			// panes reach the top.
			if let split = parent as? NSSplitView, !split.isVertical,
			   split.arrangedSubviews.first !== view {
				return false
			}
			if parent === splitHost { return true }
			view = parent
		}
		return true
	}

	override func viewDidLayout() {
		super.viewDidLayout()
		updateGroupInsets()
	}

	func reloadExternallyChangedFiles() {
		for group in groups { group.reloadExternallyChangedFiles() }
	}

	/// The open document for a file, in whichever pane holds it.
	func document(for url: URL) -> TextDocument? {
		groups.lazy.compactMap { $0.document(for: url) }.first
	}

	/// Puts new text into an open file, wherever it is open.
	///
	/// Every pane, because one file can be open in two of them and a rename that
	/// changed the buffer in one would leave the other showing the old name over
	/// a file that no longer says it.
	@discardableResult
	func applyRenamedText(_ text: String, to url: URL) -> Bool {
		var changed = false
		for group in groups where group.applyRenamedText(text, to: url) { changed = true }
		return changed
	}

	/// Closes every tab on a file a workspace edit has moved or removed.
	@discardableResult
	func closeTab(showing url: URL) -> Bool {
		var closed = false
		for group in groups where group.closeTab(showing: url) { closed = true }
		return closed
	}

	func applySettings() {
		statusBarHeightConstraint.constant = Theme.current.scaled(24)
		statusBar.needsDisplay = true
		for group in groups { group.applySettings() }
	}

	func autoSaveAll() {
		for group in groups { group.autoSaveAll() }
	}

	func windowWillClose() {
		// What was open stays recorded: closing the window is not closing the
		// tabs, and this is exactly the state to come back to.
		isClosing = true
		EditorAreas.unregister(self)
		for group in groups { group.windowWillClose() }
	}

	/// Debug state is window-wide: a breakpoint belongs to the file, not a pane.
	func setBreakpoints(_ breakpoints: [String: [Int: CodeView.BreakpointMark]]) {
		for group in groups { group.setBreakpoints(breakpoints) }
	}

	/// Which breakpoints do more than stop every time, so they can be marked.
	func setConditionalBreakpoints(_ lines: [String: Set<Int>]) {
		conditionalBreakpoints = lines
		for group in groups { group.setConditionalBreakpoints(lines) }
	}

	private var conditionalBreakpoints: [String: Set<Int>] = [:]

	var onEditBreakpoint: ((URL, Int) -> Void)? {
		didSet { for group in groups { group.onEditBreakpoint = onEditBreakpoint } }
	}

	var onFixWithAI: ((URL, Int, LSPDiagnostic) -> Void)? {
		didSet { for group in groups { group.onFixWithAI = onFixWithAI } }
	}

	var onFindUsages: ((URL, Int, Int) -> Void)? {
		didSet { for group in groups { group.onFindUsages = onFindUsages } }
	}

	var onRename: ((URL, Int, Int) -> Void)? {
		didSet { for group in groups { group.onRename = onRename } }
	}

	var onWatch: ((String) -> Void)? {
		didSet { for group in groups { group.onWatch = onWatch } }
	}

	var onCopyLink: ((URL, CodeView.LinkForm, Int, Int?) -> Void)? {
		didSet { for group in groups { group.onCopyLink = onCopyLink } }
	}

	private var runnableLines: [String: Set<Int>] = [:]

	func setRunnableLines(_ lines: [String: Set<Int>]) {
		runnableLines = lines
		for group in groups { group.setRunnableLines(lines) }
	}

	func setExecutionLocation(file: String?, line: Int?) {
		for group in groups { group.setExecutionLocation(file: file, line: line) }
	}

	/// The stopped frame's variables, for the lines that name them. Every group,
	/// like the marker: the same file can be open in two of them.
	func setInlineValues(_ values: InlineValueSet?) {
		for group in groups { group.setInlineValues(values) }
	}

	/// Scrolls the file in front through every row it has, for the claim that
	/// drawing values asks the adapter for nothing.
	func scrollStoppedFileForTesting() { activeGroup.scrollStoppedFileForTesting() }

	/// Opens the first openable value on the stopped line, as a click would.
	func openFirstInlineValueForTesting() -> String? {
		activeGroup.openFirstInlineValueForTesting()
	}

	/// What the opened value is showing.
	func openValueReportForTesting() -> String { activeGroup.openValueReportForTesting() }

	/// Sends selectors at the editor the way a key binding would.
	func exerciseUnhandledMotionsForTesting() -> String {
		activeGroup.exerciseUnhandledMotionsForTesting()
	}

	/// Walks what is open with the arrow keys.
	func walkOpenValueForTesting(_ keys: [String]) -> String {
		activeGroup.walkOpenValueForTesting(keys)
	}

	/// The same, reported after the fetch the walk asked for.
	func walkOpenValueThenSettleForTesting(_ keys: [String], then say: @escaping (String) -> Void) {
		activeGroup.walkOpenValueThenSettleForTesting(keys, then: say)
	}

	/// What colour the opened value draws its selected row in.
	func openValueSelectionColourForTesting() -> String {
		activeGroup.openValueSelectionColourForTesting()
	}

	/// What the opened value's menu offers, and what it copies.
	func openValueMenuForTesting() -> String { activeGroup.openValueMenuForTesting() }

	/// Opens a field inside what is open.
	func expandInsideOpenValueForTesting() -> String {
		activeGroup.expandInsideOpenValueForTesting()
	}

	/// What a click on the value named would do, without doing it.
	func inlineValueClickForTesting(named name: String) -> String {
		activeGroup.inlineValueClickForTesting(named: name)
	}

	/// Where a value opened beside the code gets its children from.
	func setVariableChildren(_ fetch: ((Int) async -> [Variable])?) {
		for group in groups { group.onVariableChildren = fetch }
	}

	/// What a server said about the file in front, and how loudly it is drawn.
	func diagnosticReportForTesting() -> String {
		activeGroup.diagnosticReportForTesting()
	}

	/// What the file in front has beside its code, for a driver to print.
	func inlineValueReportForTesting() -> String {
		activeGroup.inlineValueReportForTesting()
	}

	var hasOpenFiles: Bool { groups.contains { !$0.isEmpty } }

	var currentPlace: (url: URL, line: Int)? { activeGroup.currentPlace }

	/// Told where the editor went, and where it was standing before.
	///
	/// Both halves matter: going back should return to the line somebody was
	/// reading, which is not where they arrived at that file.
	/// A tab was double-clicked and it was already permanent: the editor is
	/// asking for the window.
	var onMaximize: (() -> Void)?

	/// Every group's strip draws the control, so every one is told.
	func setMaximized(_ maximized: Bool) {
		groups.forEach { $0.setMaximized(maximized) }
	}
	var onNavigated: ((NavigationHistory.Place?, NavigationHistory.Place) -> Void)?

	/// Suspended while a session is restored, or opening yesterday's twelve
	/// tabs would fill the history before anybody navigated anywhere.
	var recordsNavigation = true

	func open(fileURL: URL, focusEditor: Bool = false, preview: Bool = false) {
		activeGroup.open(fileURL: fileURL, focusEditor: focusEditor, preview: preview)
	}

	func selectDiffHunkForTesting(_ hunk: Int) {
		activeGroup.selectDiffHunkForTesting(hunk)
	}

	func openDiff(for change: GitChange, root: URL, text: String) {
		activeGroup.openDiff(for: change, root: root, text: text)
	}

	func open(
		fileURL: URL,
		atLine line: Int,
		column: Int = 1,
		length: Int = 0,
		focusEditor: Bool = true,
		preview: Bool = false
	) {
		activeGroup.open(
			fileURL: fileURL, atLine: line, column: column, length: length,
			focusEditor: focusEditor, preview: preview
		)
	}

	/// Puts the caret on a 1-based line of whatever is open, for `:` in the
	/// palette.
	func goTo(line: Int) { activeGroup?.goTo(line: line) }

	func completeAtCaret() { activeGroup?.completeAtCaret() }

	func save() { activeGroup.save() }

	/// The file the active group is showing, for whoever needs to know what a
	/// save just wrote.
	var activeGroupTabURL: URL? { activeGroup.activeTabURL }
	func closeActiveTab() { activeGroup.closeActiveTab() }
	func selectNextTab(offset: Int) { activeGroup.selectNextTab(offset: offset) }
	func collapseAllFolds() { activeGroup.collapseAllFolds() }
	func expandAllFolds() { activeGroup.expandAllFolds() }
	func toggleWordWrap() { for group in groups { group.toggleWordWrap() } }
	func toggleBlame() { activeGroup.toggleBlame() }
	func toggleMarkdownPreview() { activeGroup.toggleMarkdownPreview() }
	func setPreviewMode(_ mode: PreviewMode) { activeGroup.setPreviewMode(mode) }
	var currentPreviewMode: PreviewMode { activeGroup.currentPreviewMode }
	func focusActiveEditor() { activeGroup.focusActiveEditor() }
	func simulateTyping(_ text: String) { activeGroup.simulateTyping(text) }
	func measureTypingForTesting(presses: Int) -> [(wall: TimeInterval, cpu: TimeInterval)] {
		activeGroup.measureTypingForTesting(presses: presses)
	}
	var textForTesting: String? { activeGroup.textForTesting }
	func clickBelowLastLineForTesting() -> String { activeGroup.clickBelowLastLineForTesting() }
	func globalScratchDirectoryForTesting() -> String {
		activeGroup.globalScratchDirectoryForTesting()
	}
	func layoutReportForTesting() -> String { activeGroup.layoutReportForTesting() }
	func tabMenuTitlesForTesting(overTab: Bool) -> [String] {
		activeGroup.tabMenuTitlesForTesting(overTab: overTab)
	}
	func indentForTesting(fromLine: Int, toLine: Int, outdent: Bool) -> String? {
		activeGroup.indentForTesting(fromLine: fromLine, toLine: toLine, outdent: outdent)
	}
	func selectLinesForTesting(fromLine: Int, toLine: Int) -> Bool {
		activeGroup.selectLinesForTesting(fromLine: fromLine, toLine: toLine)
	}
	func toggleCommentForTesting(_ spec: String) -> (LineComment.Outcome, String)? {
		activeGroup.toggleCommentForTesting(spec)
	}
	func exerciseSnippetForTesting(_ spec: String) { activeGroup.exerciseSnippetForTesting(spec) }

	/// The Cadova pane somebody is looking at, for the driver that watches one.
	///
	/// The active group first, because "the tab in front" is what the driver
	/// claims to be reporting — and then every other group, because **a pane that
	/// exists must not be reported missing**. 0507 spent an afternoon on a driver
	/// that said `no cadova pane in the tab in front` while the app plainly had
	/// one, and a report of absence is only worth having if it has looked
	/// everywhere it could have looked.
	var cadovaPreview: CadovaPreviewView? {
		if let front = (activeGroup ?? groups.first)?.cadovaPreview { return front }
		return groups.compactMap(\.cadovaPreview).first
	}

	func showFind() { activeGroup.showFind() }
	func showReplace() { activeGroup.showReplace() }
	@discardableResult
	func selectTextForTesting(_ text: String) -> Bool { activeGroup.selectTextForTesting(text) }
	var occurrenceReportForTesting: String { activeGroup.occurrenceReportForTesting }
	func replaceForTesting(query: String, replacement: String, all: Bool, regex: Bool) -> String {
		activeGroup.replaceForTesting(query: query, replacement: replacement, all: all, regex: regex)
	}

	var findBarIsShowingForTesting: Bool { activeGroup.findBarIsShowingForTesting }
	func setFindQuery(_ query: String) { activeGroup.setFindQuery(query) }
	func findNext() { activeGroup.findNext() }
	func findNextFromEditor(_ times: Int) { activeGroup.findNextFromEditor(times) }
	func findPrevious() { activeGroup.findPrevious() }
	func selectedTextForSearch() -> String? { activeGroup.selectedTextForSearch() }

	/// Splits the active group, showing the current file in the new pane.
	///
	/// The file is *opened* in the new pane rather than moved into it. Moving it
	/// would empty the source pane, which then collapses — so an explicit split
	/// of a single-tab group would appear to do nothing. Showing the same file
	/// twice is also what the command is usually for: two places in one file.
	func splitActiveGroup(vertical: Bool) {
		guard let url = activeGroup.activeTabURL else { return }

		let target = activeGroup!
		let newGroup = makeGroup()
		split(target: target, with: newGroup, vertical: vertical, before: false)

		newGroup.open(fileURL: url, focusEditor: true, preview: false)
		activeGroup = newGroup
	}
}
