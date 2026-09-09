import AppKit
import AbydosKit

/// Forwarding to whichever group has the keyboard, and the driving verbs that
/// ask this controller what the editor area is showing.
///
/// Most of this controller's surface and none of its meaning: every one of
/// these is "ask the group in front", which is one sentence said ninety times.
extension EditorAreaController {
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

	func removeGroup(_ group: EditorViewController) {
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

	/// The pages open across every group, in the order the tabs are in.
	///
	/// Pages are left out of `captureSession` — a page is not a file and its
	/// synthetic path is nothing to reopen — so they are asked for separately
	/// and reopened by whoever owns them.
	func openPageIdentifiers() -> [String] {
		var seen: Set<String> = []
		var identifiers: [String] = []
		for group in groups {
			for identifier in group.openPageIdentifiers() where !seen.contains(identifier) {
				seen.insert(identifier)
				identifiers.append(identifier)
			}
		}
		return identifiers
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
	func recordOpenScratches() {
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

	/// ⌘V over a picture into the active group's document, from a board of the
	/// run's own.
	func pastePictureForTesting(_ picture: URL) {
		(activeGroup ?? groups.first)?.pastePictureForTesting(picture)
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
	func updateGroupInsets() {
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


	/// Every group's strip draws the control, so every one is told.
	func setMaximized(_ maximized: Bool) {
		groups.forEach { $0.setMaximized(maximized) }
	}


	func open(fileURL: URL, focusEditor: Bool = false, preview: Bool = false) {
		activeGroup.open(fileURL: fileURL, focusEditor: focusEditor, preview: preview)
	}

	/// Opens the file as a tab of its own and turns that tab into the hex
	/// editor, whatever the file would otherwise have opened as.
	func openArchiveEntry(at url: URL, origin: ArchiveOrigin, focusEditor: Bool) {
		activeGroup.openArchiveEntry(at: url, origin: origin, focusEditor: focusEditor)
	}

	func openAsHex(fileURL: URL) {
		activeGroup.open(fileURL: fileURL, focusEditor: true)
		activeGroup.openActiveAsHex()
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
	func showBlame() { activeGroup.showBlame() }
	func toggleRevealSecrets() {
		activeGroup.toggleRevealSecrets()
		// The lock has to turn the moment it is pressed, not at the next
		// caret move.
		refreshStatus(from: activeGroup)
	}
	var secretsState: (conceals: Bool, revealed: Bool) { activeGroup.secretsState }
	func secretsForTesting(_ steps: String) { activeGroup.secretsForTesting(steps) }
	func editorMenuForTesting(_ steps: String) { activeGroup.editorMenuForTesting(steps) }
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
	func goToOffset() { activeGroup.goToOffset() }
	func openActiveAsHex() { activeGroup.openActiveAsHex() }
	func openActiveAsText() { activeGroup.openActiveAsText() }
	var activeTabIsHex: Bool { activeGroup?.activeTabIsHex ?? false }
	var activeTabCanOpenAsText: Bool { activeGroup?.activeTabCanOpenAsText ?? false }
	/// The driver's steps on the front tab, as bytes.
	func hexStepsForTesting(_ steps: String) async -> String {
		await activeGroup.hexStepsForTesting(steps)
	}
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
