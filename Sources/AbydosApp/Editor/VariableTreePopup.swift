import AppKit
import AbydosKit

/// One variable, opened up: its fields under it, expandable, over the frame the
/// value beside the code came from.
///
/// **A panel rather than an `NSPopover`.** A popover is dismissed by the next
/// click anywhere, which is exactly the gesture somebody makes reaching into a
/// tree to expand a row — the completion list is a panel for the same reason.
/// So this follows the completion list's rules: it appears at what it is about,
/// Escape closes it, a click outside closes it, and it goes when execution
/// resumes, because a tree of values from a program that is running again is
/// worse than no tree at all.
///
/// **Addressed by reference, not by a path.** `DebugSession.toggleExpansion` is
/// keyed by position in `scopes`, which a popup opened from a name on a line
/// does not have and should not have to reconstruct. `variables(reference:)` is
/// already public and is exactly what an adapter answers a container with, so
/// this keeps its own small tree and asks for children by the number the adapter
/// gave. The panel's tree is untouched, and there is no second way into the
/// same fetching — only a second caller of the one that was already there.
final class VariableTreePopup: NSPanel {
	/// Fetches the children of a container, by the reference the adapter gave.
	private let children: (Int) async -> [Variable]
	private var outline: NSOutlineView!
	private var nodes: [Node] = []
	private var monitor: Any?

	/// A variable in this tree, with whatever has been fetched for it so far.
	private final class Node {
		let variable: Variable
		var children: [Node]?
		/// **Asked for, and not back yet.** Opening a row and the outline view's
		/// own `shouldExpandItem` both reach for the same node, and `children`
		/// is still nil between the two — so without this the adapter is asked
		/// twice for one gesture. Counted rather than reasoned about: the driven
		/// check said three requests where two had been asked for.
		var isFetching = false
		init(_ variable: Variable) { self.variable = variable }
	}

	init(root: Variable, children: @escaping (Int) async -> [Variable]) {
		self.children = children
		super.init(
			contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: true
		)
		isFloatingPanel = true
		level = .popUpMenu
		hidesOnDeactivate = true
		backgroundColor = Theme.current.editorBackground
		hasShadow = true
		nodes = [Node(root)]
		build()
		// The root is what was asked about, so it opens showing its fields
		// rather than showing itself and waiting to be asked again.
		expand(nodes[0])
	}

	private func build() {
		let outline = NSOutlineView()
		outline.headerView = nil
		outline.backgroundColor = Theme.current.editorBackground
		outline.rowSizeStyle = .custom
		outline.gridStyleMask = []
		outline.indentationPerLevel = Theme.current.scaled(14)
		outline.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("variable")))
		outline.outlineTableColumn = outline.tableColumns.first
		outline.dataSource = self
		outline.delegate = self
		self.outline = outline

		let scroll = NSScrollView()
		scroll.documentView = outline
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.editorBackground
		scroll.borderType = .noBorder
		scroll.translatesAutoresizingMaskIntoConstraints = false

		let content = NSView()
		content.wantsLayer = true
		content.layer?.backgroundColor = Theme.current.editorBackground.cgColor
		content.layer?.borderColor = Theme.current.separator.cgColor
		content.layer?.borderWidth = 1
		content.layer?.cornerRadius = Theme.current.scaled(6)
		content.addSubview(scroll)
		NSLayoutConstraint.activate([
			scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 1),
			scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 1),
			scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -1),
			scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -1),
		])
		contentView = content
	}

	/// Shows it at a hint, below the line where there is room and above it where
	/// there is not — the same answer the completion list gives to the same
	/// problem.
	func show(over host: NSView, at rect: NSRect) {
		guard let window = host.window else { return }
		let inWindow = host.convert(rect, to: nil)
		let onScreen = window.convertToScreen(inWindow)
		var frame = self.frame
		frame.origin.x = min(
			onScreen.minX,
			(window.screen?.visibleFrame.maxX ?? onScreen.maxX) - frame.width - 8
		)
		let below = onScreen.minY - frame.height - 4
		let floor = window.screen?.visibleFrame.minY ?? 0
		frame.origin.y = below > floor ? below : onScreen.maxY + 4
		setFrame(frame, display: false)

		window.addChildWindow(self, ordered: .above)
		orderFront(nil)
		watchForAClickOutside()
	}

	/// Escape closes it; so does a click that is not in it.
	private func watchForAClickOutside() {
		monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) {
			[weak self] event in
			guard let self else { return event }
			if event.type == .keyDown {
				// 53 is Escape. Anything else is somebody typing in the editor,
				// which is not this window's business.
				guard event.keyCode == 53 else { return event }
				self.dismiss()
				return nil
			}
			if event.window !== self { self.dismiss() }
			return event
		}
	}

	func dismiss() {
		if let monitor { NSEvent.removeMonitor(monitor) }
		monitor = nil
		parent?.removeChildWindow(self)
		orderOut(nil)
	}

	deinit {
		if let monitor { NSEvent.removeMonitor(monitor) }
	}

	/// Fetches a node's children once, and redraws when they arrive.
	private func expand(_ node: Node) {
		guard node.children == nil, !node.isFetching, node.variable.isExpandable else { return }
		node.isFetching = true
		let reference = node.variable.variablesReference
		Task { @MainActor [weak self] in
			guard let self else { return }
			let fetched = await self.children(reference)
			node.isFetching = false
			node.children = fetched.map(Node.init)
			self.outline.reloadItem(node, reloadChildren: true)
			self.outline.expandItem(node)
		}
	}

	/// Opens the first field under the root that has anything under it, as
	/// clicking its triangle would — for the claim that children arrive on the
	/// gesture rather than with the tree.
	func expandFirstChildForTesting() -> String {
		guard let children = nodes.first?.children else { return "the root has not arrived yet" }
		guard let node = children.first(where: { $0.variable.isExpandable }) else {
			return "no field under it has anything under it"
		}
		expand(node)
		outline.expandItem(node)
		return "expanding \(node.variable.name.isEmpty ? "the pointee" : node.variable.name)"
	}

	/// Where it is and whether it is up, since a child panel is not in a window
	/// capture and a photograph therefore cannot say either.
	var placementForTesting: String {
		"visible=\(isVisible) at \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
	}

	/// What this window is showing, for a driver to print.
	var reportForTesting: String {
		var lines: [String] = []
		func walk(_ nodes: [Node], depth: Int) {
			for node in nodes {
				lines.append(String(repeating: "  ", count: depth)
					+ "\(node.variable.name) = \(node.variable.value.prefix(40))")
				if let children = node.children, outline.isItemExpanded(node) {
					walk(children, depth: depth + 1)
				}
			}
		}
		walk(nodes, depth: 0)
		return lines.joined(separator: "\n")
	}
}

extension VariableTreePopup: NSOutlineViewDataSource, NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		guard let node = item as? Node else { return nodes.count }
		return node.children?.count ?? 0
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		guard let node = item as? Node else { return nodes[index] }
		return node.children?[index] ?? Node(Variable(name: "…", value: "", type: nil, variablesReference: 0))
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		(item as? Node)?.variable.isExpandable ?? false
	}

	func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
		if let node = item as? Node { expand(node) }
		return true
	}

	func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
		Theme.current.scaled(20)
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? Node else { return nil }
		// The panel's own row, so the two trees cannot come to look different.
		return VariableCell(variable: node.variable)
	}
}
