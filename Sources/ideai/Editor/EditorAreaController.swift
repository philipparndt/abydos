import AppKit
import IdeaiKit

/// Hosts one or more editor groups in a tree of splits.
///
/// Each pane is a full editor group with its own tabs, find bar and status line,
/// rather than a shared set of tabs shown twice. Splits are built from nested
/// two-child `NSSplitView`s, which keeps the arrangement recursive: any pane can
/// be split again, horizontally or vertically, to any depth.
///
/// The window talks to this controller, which forwards to whichever group is
/// active, so the rest of the app is unaware there is more than one.
final class EditorAreaController: NSViewController {
	private(set) var groups: [EditorViewController] = []
	private(set) var activeGroup: EditorViewController!

	private var project: Project?
	private var topInset: CGFloat = 40

	// Forwarded from the active group.
	var onActiveFileChanged: ((URL?) -> Void)?
	var onToggleBreakpoint: ((URL, Int) -> Void)?

	override func loadView() {
		let container = ColoredView(color: Theme.current.editorBackground)
		view = container

		let first = makeGroup()
		activeGroup = first
		install(rootView: first.view)
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
		group.onActivated = { [weak self] activated in
			self?.activeGroup = activated
		}
		group.onBecameEmpty = { [weak self] empty in
			// The last group stays even when empty; it is the editor area itself.
			self?.removeGroup(empty)
		}
		group.onTabDropped = { [weak self] payload, zone, target in
			self?.handleDrop(payload: payload, zone: zone, target: target)
		}

		groups.append(group)
		addChild(group)
		return group
	}

	private func install(rootView: NSView) {
		view.subviews.forEach { $0.removeFromSuperview() }
		rootView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(rootView)
		NSLayoutConstraint.activate([
			rootView.topAnchor.constraint(equalTo: view.topAnchor),
			rootView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			rootView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			rootView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
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
		let isRoot = (parent === view)
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
		DispatchQueue.main.async { [weak split] in
			guard let split else { return }
			let total = vertical ? split.bounds.width : split.bounds.height
			split.setPosition(total / 2, ofDividerAt: 0)
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

			if grandparent === view {
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
	}

	// MARK: - Forwarding

	func setProject(_ project: Project) {
		self.project = project
		for group in groups { group.setProject(project) }
	}

	func setTopInset(_ inset: CGFloat) {
		topInset = inset
		for group in groups { group.setTopInset(inset) }
	}

	func applySettings() {
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

	func setExecutionLocation(file: String?, line: Int?) {
		for group in groups { group.setExecutionLocation(file: file, line: line) }
	}

	var hasOpenFiles: Bool { groups.contains { !$0.isEmpty } }

	func open(fileURL: URL, focusEditor: Bool = false, preview: Bool = false) {
		activeGroup.open(fileURL: fileURL, focusEditor: focusEditor, preview: preview)
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
