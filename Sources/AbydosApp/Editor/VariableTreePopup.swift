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
			// **Titled and resizable, not borderless.** A struct is why this
			// window exists and a struct is not 420 by 260 — the first thing
			// anybody does with one is make it bigger. A title bar is what
			// gives it a grab handle, a close button and, with `.resizable`,
			// edges that can be dragged; borderless had none of the three.
			styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
			backing: .buffered,
			defer: true
		)
		isFloatingPanel = true
		level = .floating
		hidesOnDeactivate = true
		title = root.name.isEmpty ? "Value" : root.name
		titlebarAppearsTransparent = true
		backgroundColor = Theme.current.editorBackground
		hasShadow = true
		// Small enough to be a hint about one variable, big enough that the
		// first drag is not immediately necessary.
		minSize = NSSize(width: 260, height: 120)
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
		// The same three the panel's tree offers, worded the same. A window you
		// opened to read a struct is a window you copy out of — a field's value
		// into a message, a name into a search — and having to go back to the
		// panel to do it is the trip this window exists to save.
		let menu = NSMenu()
		menu.autoenablesItems = false
		menu.delegate = self
		outline.menu = menu
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

	/// **It can take the keyboard**, which a borderless panel cannot.
	///
	/// The tree walks itself once it has it — ↑↓ move, → opens a row, ← closes
	/// it — so this is the whole of the keyboard work here. Non-activating still:
	/// opening a value should not take the app's focus away from the editor, and
	/// this becomes key only because it was asked for.
	override var canBecomeKey: Bool { true }

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
		// The tree, not the window: the arrows have to arrive somewhere that
		// knows what to do with them, and a row selected is where the first one
		// starts from.
		makeKey()
		makeFirstResponder(outline)
		if outline.numberOfRows > 0 {
			outline.selectRowIndexes([0], byExtendingSelection: false)
		}
		watchForAClickOutside()
	}

	/// Escape closes it; so does a click that is not in it.
	private func watchForAClickOutside() {
		monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) {
			[weak self] event in
			guard let self else { return event }
			if event.type == .keyDown {
				// 53 is Escape. Anything else is either somebody typing in the
				// editor or an arrow this window's tree is about to walk on, and
				// neither is this monitor's business.
				guard event.keyCode == 53 else { return event }
				self.dismiss()
				return nil
			}
			// A click in this window is somebody reaching into the tree, or
			// dragging its title bar, or pulling its edge — all of which are
			// this window being used rather than left.
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

			// **What was selected, kept across the reload.** Reported from use:
			// pressing → to open a row lost the selection, so the next ↓ started
			// again from nowhere and walking the tree with the keyboard fell
			// apart at the first branch. `reloadItem(_:reloadChildren:)` rebuilds
			// the rows under a node and the outline drops a selection it can no
			// longer place — so it is remembered by *item*, which survives the
			// rebuild, rather than by row, which does not.
			let selected = self.outline.selectedRow >= 0
				? self.outline.item(atRow: self.outline.selectedRow)
				: nil

			self.outline.reloadItem(node, reloadChildren: true)
			self.outline.expandItem(node)

			guard let selected else { return }
			let row = self.outline.row(forItem: selected)
			guard row >= 0 else { return }
			self.outline.selectRowIndexes([row], byExtendingSelection: false)
		}
	}

	/// The row the menu was opened on.
	private var clickedNode: Node? {
		let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
		guard row >= 0 else { return nil }
		return outline.item(atRow: row) as? Node
	}

	private func copy(_ text: String) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	@objc private func copyValue() {
		guard let node = clickedNode else { return }
		copy(node.variable.value)
	}

	@objc private func copyName() {
		guard let node = clickedNode else { return }
		copy(node.variable.name)
	}

	/// `name = value`, which is what goes into a note or a message.
	@objc private func copyBoth() {
		guard let node = clickedNode else { return }
		copy("\(node.variable.name) = \(node.variable.value)")
	}

	/// **The whole subtree, as it is shown.** A struct is why somebody opened
	/// this window, and copying it a field at a time is the thing they came here
	/// to stop doing. Only what has been fetched and is expanded, because that
	/// is what is on screen: copying would otherwise mean a burst of requests to
	/// an adapter for rows nobody has looked at.
	@objc private func copyEverythingShown() {
		copy(reportForTesting)
	}

	/// What the menu offers, for a driver to print.
	var menuTitlesForTesting: String {
		let menu = NSMenu()
		menuNeedsUpdate(menu)
		return menu.items.map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: ", ")
	}

	/// Copies as the menu item would, and says what landed on the pasteboard.
	func copyForTesting(_ which: String) -> String {
		let saved = NSPasteboard.general.string(forType: .string)
		defer {
			NSPasteboard.general.clearContents()
			if let saved { NSPasteboard.general.setString(saved, forType: .string) }
		}
		outline.selectRowIndexes([0], byExtendingSelection: false)
		switch which {
		case "name": copyName()
		case "value": copyValue()
		case "tree": copyEverythingShown()
		default: copyBoth()
		}
		return (NSPasteboard.general.string(forType: .string) ?? "nothing")
			.replacingOccurrences(of: "\n", with: " ⏎ ")
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
		let walker = firstResponder === outline
		return "visible=\(isVisible) at \(Int(frame.minX)),\(Int(frame.minY))"
			+ " \(Int(frame.width))x\(Int(frame.height))"
			+ " resizable=\(styleMask.contains(.resizable))"
			+ " tree has the keyboard=\(walker) selected=\(outline.selectedRow)"
	}

	/// Walks with the arrows and waits for whatever the walk asked the adapter
	/// for, so that what is reported is the state after the fetch rather than
	/// before it — which is where the selection used to be lost.
	func walkThenSettleForTesting(_ keys: [String], then say: @escaping (String) -> Void) {
		_ = walkForTesting(keys)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
			say(self?.walkForTesting([]) ?? "the window has gone")
		}
	}

	/// Walks the tree the way the arrow keys do, and says where it ended up.
	///
	/// Through the outline view's own key handling — `keyDown` on the view that
	/// would receive it — rather than through the actions those keys map to, so
	/// what is driven is what a key does.
	func walkForTesting(_ keys: [String]) -> String {
		// **The characters matter, not only the key code.** AppKit translates a
		// key press into an action through `interpretKeyEvents`, which reads the
		// characters; an event carrying an arrow's code and an empty string is
		// translated into nothing at all, and the tree sits where it was. The
		// arrows are the function-key range: ↑ is 0xF700 and the rest follow.
		let arrows: [String: (UInt16, Int)] = [
			"up": (126, NSUpArrowFunctionKey), "down": (125, NSDownArrowFunctionKey),
			"left": (123, NSLeftArrowFunctionKey), "right": (124, NSRightArrowFunctionKey),
		]
		for key in keys {
			guard let arrow = arrows[key],
			      let scalar = UnicodeScalar(UInt32(arrow.1)) else { continue }
			let characters = String(Character(scalar))
			guard let event = NSEvent.keyEvent(
				with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
				windowNumber: windowNumber, context: nil, characters: characters,
				charactersIgnoringModifiers: characters, isARepeat: false, keyCode: arrow.0
			) else { continue }
			outline.keyDown(with: event)
		}
		let row = outline.selectedRow
		guard row >= 0, let node = outline.item(atRow: row) as? Node else {
			return "nothing is selected"
		}
		return "row \(row): \(node.variable.name.isEmpty ? "(the pointee)" : node.variable.name)"
			+ " expanded=\(outline.isItemExpanded(node))"
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

extension VariableTreePopup: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()
		func item(_ title: String, _ selector: Selector) -> NSMenuItem {
			let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			entry.target = self
			return entry
		}
		menu.addItem(item("Copy Value", #selector(copyValue)))
		menu.addItem(item("Copy Name", #selector(copyName)))
		menu.addItem(item("Copy Name and Value", #selector(copyBoth)))
		menu.addItem(.separator())
		menu.addItem(item("Copy Everything Shown", #selector(copyEverythingShown)))
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
