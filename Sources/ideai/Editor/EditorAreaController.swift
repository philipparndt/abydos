import AppKit
import IdeaiKit

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
	var onActiveFileChanged: ((URL?) -> Void)?
	var onToggleBreakpoint: ((URL, Int) -> Void)?
	var onRunLine: ((URL, Int) -> Void)?
	var onApplyDiffSelection: ((GitChange, String, Set<Int>) -> Void)?
	var onDiscardDiffSelection: ((GitChange, String, Set<Int>) -> Void)?

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

	/// Shows the active group's caret position and language.
	private func refreshStatus(from group: EditorViewController?) {
		guard let group, group === activeGroup else { return }
		statusBar.isHidden = group.isEmpty
		statusBar.setPosition(line: group.statusLine, column: group.statusColumn)
		statusBar.setLanguage(group.statusLanguage)
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
		group.onToggleBreakpoint = { [weak self] url, line in
			self?.onToggleBreakpoint?(url, line)
		}
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
		group.onActivated = { [weak self] activated in
			self?.activeGroup = activated
		}
		group.onBecameEmpty = { [weak self] empty in
			// The last group stays even when empty; it is the editor area itself.
			self?.removeGroup(empty)
		}
		group.onStatusChanged = { [weak self] reporting in
			self?.refreshStatus(from: reporting)
		}
		group.onTabDropped = { [weak self] payload, zone, target in
			self?.handleDrop(payload: payload, zone: zone, target: target)
		}
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
		guard let source = groups.first(where: { $0.groupID == payload.groupID }) else { return }

		// Dropping a group's only tab back into itself would destroy and rebuild
		// the same pane for no reason.
		if source === target, zone == .center { return }
		if source === target, source.tabCount <= 1 { return }

		let index = source.indexOfTab(withPath: payload.path) ?? payload.index
		guard let tab = source.detachTab(at: index) else { return }

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
		guard let source = groups.first(where: { $0.groupID == payload.groupID }) else { return }
		let from = source.indexOfTab(withPath: payload.path) ?? payload.index

		if source === target {
			// The slot is measured against the strip as it looks now, with the tab
			// still in it, so removing an earlier tab shifts every later slot left.
			source.moveTab(from: from, to: index > from ? index - 1 : index)
			activeGroup = target
			return
		}

		guard let tab = source.detachTab(at: from) else { return }
		target.adopt(tab, at: index)
		activeGroup = target
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

		let split = ThinDividerSplitView()
		split.isVertical = vertical
		split.dividerStyle = .thin

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
		DispatchQueue.main.async { [weak self, weak split] in
			guard let split else { return }
			let total = vertical ? split.bounds.width : split.bounds.height
			split.setPosition(total / 2, ofDividerAt: 0)
			self?.updateGroupInsets()
		}
	}

	/// Removes an empty group and collapses the split that held it.
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

	func applySettings() {
		statusBarHeightConstraint.constant = Theme.current.scaled(24)
		statusBar.needsDisplay = true
		for group in groups { group.applySettings() }
	}

	func autoSaveAll() {
		for group in groups { group.autoSaveAll() }
	}

	func windowWillClose() {
		for group in groups { group.windowWillClose() }
	}

	/// Debug state is window-wide: a breakpoint belongs to the file, not a pane.
	func setBreakpoints(_ breakpoints: [String: [Int: Bool]]) {
		for group in groups { group.setBreakpoints(breakpoints) }
	}

	private var runnableLines: [String: Set<Int>] = [:]

	func setRunnableLines(_ lines: [String: Set<Int>]) {
		runnableLines = lines
		for group in groups { group.setRunnableLines(lines) }
	}

	func setExecutionLocation(file: String?, line: Int?) {
		for group in groups { group.setExecutionLocation(file: file, line: line) }
	}

	var hasOpenFiles: Bool { groups.contains { !$0.isEmpty } }

	func open(fileURL: URL, focusEditor: Bool = false, preview: Bool = false) {
		activeGroup.open(fileURL: fileURL, focusEditor: focusEditor, preview: preview)
	}

	func selectDiffHunkForTesting(_ hunk: Int) {
		activeGroup.selectDiffHunkForTesting(hunk)
	}

	func openDiff(for change: GitChange, root: URL, text: String) {
		activeGroup.openDiff(for: change, root: root, text: text)
	}

	func open(fileURL: URL, atLine line: Int) {
		activeGroup.open(fileURL: fileURL, atLine: line)
	}

	func save() { activeGroup.save() }
	func closeActiveTab() { activeGroup.closeActiveTab() }
	func selectNextTab(offset: Int) { activeGroup.selectNextTab(offset: offset) }
	func collapseAllFolds() { activeGroup.collapseAllFolds() }
	func expandAllFolds() { activeGroup.expandAllFolds() }
	func toggleWordWrap() { for group in groups { group.toggleWordWrap() } }
	func toggleMarkdownPreview() { activeGroup.toggleMarkdownPreview() }
	func setPreviewMode(_ mode: PreviewMode) { activeGroup.setPreviewMode(mode) }
	func focusActiveEditor() { activeGroup.focusActiveEditor() }
	func simulateTyping(_ text: String) { activeGroup.simulateTyping(text) }

	func showFind() { activeGroup.showFind() }
	func setFindQuery(_ query: String) { activeGroup.setFindQuery(query) }
	func findNext() { activeGroup.findNext() }
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
