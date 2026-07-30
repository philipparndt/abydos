import AppKit
import IdeaiKit

/// Debugger UI: execution controls, call stack, and variables.
///
/// A native front end over DAP rather than Delve's terminal UI, so breakpoints
/// live in the editor gutter and inspecting a value is a disclosure triangle
/// instead of a `print` command.
final class DebugPane: NSView {
	/// Called to show the file and line execution stopped at.
	var onNavigate: ((URL, Int) -> Void)?

	private let session: DebugSession
	private let projectRoot: URL

	/// The session this pane drives, so the window can reach it for breakpoints.
	var debugSession: DebugSession { session }

	private var toolbar: DebugToolbar!
	private var stackTable: NSTableView!
	private var variablesOutline: NSOutlineView!

	/// Flattened variable tree for the outline view.
	private final class VariableNode {
		let variable: Variable
		let scopeIndex: Int
		let path: [Int]
		var children: [VariableNode] = []

		init(variable: Variable, scopeIndex: Int, path: [Int]) {
			self.variable = variable
			self.scopeIndex = scopeIndex
			self.path = path
		}
	}

	private final class ScopeNode {
		let scope: Scope
		let index: Int
		var children: [VariableNode] = []

		init(scope: Scope, index: Int) {
			self.scope = scope
			self.index = index
		}
	}

	private var scopeNodes: [ScopeNode] = []

	init(session: DebugSession, projectRoot: URL) {
		self.session = session
		self.projectRoot = projectRoot
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
		wireSession()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func build() {
		toolbar = DebugToolbar()
		toolbar.onContinue = { [weak self] in self?.session.resume() }
		toolbar.onPause = { [weak self] in self?.session.pause() }
		toolbar.onStepOver = { [weak self] in self?.session.stepOver() }
		toolbar.onStepInto = { [weak self] in self?.session.stepInto() }
		toolbar.onStepOut = { [weak self] in self?.session.stepOut() }
		toolbar.onStop = { [weak self] in self?.session.stop() }

		// Stack on the left, variables on the right — the arrangement every
		// debugger uses, because you pick a frame and then read its values.
		let stack = NSTableView()
		stack.headerView = nil
		stack.backgroundColor = Theme.current.editorBackground
		stack.selectionHighlightStyle = .regular
		stack.rowSizeStyle = .custom
		stack.intercellSpacing = .zero
		stack.gridStyleMask = []
		stack.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("frame")))
		stack.delegate = self
		stack.dataSource = self
		stack.target = self
		stack.action = #selector(frameClicked)
		stackTable = stack

		let variables = NSOutlineView()
		variables.headerView = nil
		variables.backgroundColor = Theme.current.editorBackground
		variables.selectionHighlightStyle = .regular
		variables.rowSizeStyle = .custom
		variables.rowHeight = Theme.current.scaled(20)
		variables.intercellSpacing = .zero
		variables.indentationPerLevel = Theme.current.scaled(13)
		variables.gridStyleMask = []
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("variable"))
		variables.addTableColumn(column)
		variables.outlineTableColumn = column
		variables.delegate = self
		variables.dataSource = self
		variablesOutline = variables

		let stackScroll = makeScrollView(document: stack)
		let variablesScroll = makeScrollView(document: variables)

		let split = ThinDividerSplitView()
		split.isVertical = true
		split.dividerStyle = .thin
		split.addArrangedSubview(stackScroll)
		split.addArrangedSubview(variablesScroll)

		addSubview(toolbar)
		addSubview(split)
		toolbar.translatesAutoresizingMaskIntoConstraints = false
		split.translatesAutoresizingMaskIntoConstraints = false

		toolbarHeight = toolbar.heightAnchor.constraint(equalToConstant: Theme.current.scaled(30))
		NSLayoutConstraint.activate([
			toolbar.topAnchor.constraint(equalTo: topAnchor),
			toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
			toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
			toolbarHeight,

			split.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
			split.leadingAnchor.constraint(equalTo: leadingAnchor),
			split.trailingAnchor.constraint(equalTo: trailingAnchor),
			split.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		DispatchQueue.main.async { [weak split] in
			guard let split else { return }
			split.setPosition(split.bounds.width * 0.38, ofDividerAt: 0)
		}
	}

	private var toolbarHeight: NSLayoutConstraint!

	private func makeScrollView(document: NSView) -> NSScrollView {
		let scrollView = NSScrollView()
		scrollView.documentView = document
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		scrollView.scrollerStyle = .overlay
		return scrollView
	}

	private func wireSession() {
		session.onStateChange = { [weak self] state in
			self?.toolbar.update(state: state)
		}
		session.onStackChanged = { [weak self] in
			self?.stackTable.reloadData()
			if let self, !self.session.stackFrames.isEmpty {
				self.stackTable.selectRowIndexes([0], byExtendingSelection: false)
			}
		}
		session.onVariablesChanged = { [weak self] in
			self?.rebuildVariableTree()
		}
		session.onStoppedAt = { [weak self] file, line in
			self?.onNavigate?(URL(fileURLWithPath: file), line)
		}
	}

	func applySettings() {
		toolbarHeight.constant = Theme.current.scaled(30)
		variablesOutline.rowHeight = Theme.current.scaled(20)
		variablesOutline.indentationPerLevel = Theme.current.scaled(13)
		stackTable.reloadData()
		variablesOutline.reloadData()
		toolbar.needsDisplay = true
	}

	func shutdown() {
		session.stop()
	}

	// MARK: - Variables

	private func rebuildVariableTree() {
		scopeNodes = session.scopes.enumerated().map { index, scope in
			let node = ScopeNode(scope: scope, index: index)
			node.children = build(variables: scope.variables, scopeIndex: index, prefix: [])
			return node
		}
		variablesOutline.reloadData()

		// Scopes open by default; the whole point is to see the values.
		for node in scopeNodes { variablesOutline.expandItem(node) }
		restoreExpansion(nodes: scopeNodes.flatMap(\.children))
	}

	private func build(variables: [Variable], scopeIndex: Int, prefix: [Int]) -> [VariableNode] {
		variables.enumerated().map { index, variable in
			let path = prefix + [index]
			let node = VariableNode(variable: variable, scopeIndex: scopeIndex, path: path)
			node.children = build(variables: variable.children ?? [], scopeIndex: scopeIndex, prefix: path)
			return node
		}
	}

	/// Re-opens rows the session still reports as expanded, so loading children
	/// does not collapse the tree the user just opened.
	private func restoreExpansion(nodes: [VariableNode]) {
		for node in nodes where node.variable.isExpanded {
			variablesOutline.expandItem(node)
			restoreExpansion(nodes: node.children)
		}
	}

	@objc private func frameClicked() {
		let row = stackTable.clickedRow >= 0 ? stackTable.clickedRow : stackTable.selectedRow
		guard session.stackFrames.indices.contains(row) else { return }
		let frame = session.stackFrames[row]

		Task { await session.selectFrame(id: frame.id) }
		if let file = frame.file {
			onNavigate?(URL(fileURLWithPath: file), frame.line)
		}
	}
}

// MARK: - Call stack

extension DebugPane: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int {
		session.stackFrames.count
	}

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		Theme.current.scaled(34)
	}

	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		DebugRowView()
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard session.stackFrames.indices.contains(row) else { return nil }
		return StackFrameCell(stackFrame: session.stackFrames[row], projectRoot: projectRoot)
	}
}

// MARK: - Variables

extension DebugPane: NSOutlineViewDataSource, NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if item == nil { return scopeNodes.count }
		if let scope = item as? ScopeNode { return scope.children.count }
		if let variable = item as? VariableNode {
			// Report one child before loading, so the triangle appears and can be
			// clicked; the real children arrive on expansion.
			if variable.children.isEmpty && variable.variable.isExpandable { return 1 }
			return variable.children.count
		}
		return 0
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if item == nil { return scopeNodes[index] }
		if let scope = item as? ScopeNode { return scope.children[index] }
		if let variable = item as? VariableNode {
			if variable.children.isEmpty && variable.variable.isExpandable {
				return PlaceholderNode()
			}
			return variable.children[index]
		}
		return PlaceholderNode()
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		if item is ScopeNode { return true }
		if let variable = item as? VariableNode { return variable.variable.isExpandable }
		return false
	}

	func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
		guard let node = item as? VariableNode else { return true }
		// Children load asynchronously; the tree rebuilds when they arrive.
		if node.children.isEmpty {
			Task { await session.toggleExpansion(scopeIndex: node.scopeIndex, path: node.path) }
		}
		return true
	}

	func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
		Theme.current.scaled(20)
	}

	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		DebugRowView()
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		if let scope = item as? ScopeNode {
			return ScopeCell(name: scope.scope.name)
		}
		if let variable = item as? VariableNode {
			return VariableCell(variable: variable.variable)
		}
		return VariableCell(variable: Variable(name: "…", value: "", type: nil, variablesReference: 0))
	}
}

private final class PlaceholderNode {}

private final class DebugRowView: NSTableRowView {
	override func drawSelection(in dirtyRect: NSRect) {
		Theme.current.selectionActive.setFill()
		bounds.fill()
	}
}

// MARK: - Cells

private final class StackFrameCell: NSView {
	// Named `stackFrame`, since `frame` is NSView's own.
	private let stackFrame: StackFrame
	private let projectRoot: URL

	init(stackFrame: StackFrame, projectRoot: URL) {
		self.stackFrame = stackFrame
		self.projectRoot = projectRoot
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
		let inset = Theme.current.scaled(10)

		let name = NSAttributedString(string: stackFrame.name, attributes: [
			.font: Theme.current.uiFont(11.5, weight: .medium),
			.foregroundColor: isSelected ? NSColor.hex(0xE8EAED) : Theme.current.sidebarHeaderText,
		])
		name.draw(in: NSRect(
			x: inset, y: Theme.current.scaled(4),
			width: max(0, bounds.width - inset * 2), height: Theme.current.scaled(14)
		))

		guard let file = stackFrame.file else { return }
		// Paths are shown relative to the project; absolute ones are unreadable
		// in a narrow pane and mostly identical prefix.
		var display = file
		if file.hasPrefix(projectRoot.path + "/") {
			display = String(file.dropFirst(projectRoot.path.count + 1))
		} else {
			display = (file as NSString).lastPathComponent
		}

		let location = NSAttributedString(string: "\(display):\(stackFrame.line)", attributes: [
			.font: Theme.terminalFont(size: Theme.current.uiFont(10).pointSize),
			.foregroundColor: isSelected ? NSColor.hex(0xC8CBD0) : Theme.current.gitIgnored,
		])
		location.draw(in: NSRect(
			x: inset, y: Theme.current.scaled(18),
			width: max(0, bounds.width - inset * 2), height: Theme.current.scaled(13)
		))
	}
}

private final class ScopeCell: NSView {
	private let name: String

	init(name: String) {
		self.name = name
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let label = NSAttributedString(string: name.uppercased(), attributes: [
			.font: Theme.current.uiFont(10, weight: .semibold),
			.foregroundColor: Theme.current.gitIgnored,
		])
		label.draw(at: NSPoint(x: 0, y: bounds.midY - label.size().height / 2))
	}
}

private final class VariableCell: NSView {
	private let variable: Variable

	init(variable: Variable) {
		self.variable = variable
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
		let font = Theme.terminalFont(size: Theme.current.uiFont(11).pointSize)
		var x: CGFloat = 0

		let name = NSAttributedString(string: variable.name, attributes: [
			.font: font,
			.foregroundColor: isSelected ? NSColor.hex(0xE8EAED) : NSColor.hex(0xC77DBB),
		])
		name.draw(at: NSPoint(x: x, y: bounds.midY - name.size().height / 2))
		x += name.size().width + Theme.current.scaled(6)

		// The type sits between name and value, dimmed, because it is context
		// rather than the thing being read.
		if let type = variable.type, !type.isEmpty {
			let typeString = NSAttributedString(string: type, attributes: [
				.font: font,
				.foregroundColor: Theme.current.gitIgnored,
			])
			typeString.draw(at: NSPoint(x: x, y: bounds.midY - typeString.size().height / 2))
			x += typeString.size().width + Theme.current.scaled(8)
		}

		let value = NSAttributedString(string: variable.value, attributes: [
			.font: font,
			.foregroundColor: isSelected ? NSColor.hex(0xE8EAED) : Theme.current.gitAdded,
		])
		value.draw(in: NSRect(
			x: x,
			y: bounds.midY - value.size().height / 2,
			width: max(0, bounds.width - x - Theme.current.scaled(8)),
			height: value.size().height
		))
	}
}

// MARK: - Toolbar

private final class DebugToolbar: NSView {
	var onContinue: (() -> Void)?
	var onPause: (() -> Void)?
	var onStepOver: (() -> Void)?
	var onStepInto: (() -> Void)?
	var onStepOut: (() -> Void)?
	var onStop: (() -> Void)?

	private var state: DebugSession.State = .idle
	private var buttonFrames: [(NSRect, () -> Void)] = []

	override var isFlipped: Bool { true }

	func update(state: DebugSession.State) {
		self.state = state
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		for (rect, action) in buttonFrames where rect.contains(point) {
			action()
			return
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

		buttonFrames = []
		var x = Theme.current.scaled(10)
		let size = Theme.current.scaled(22)
		let y = bounds.midY - size / 2

		let isStopped: Bool
		if case .stopped = state { isStopped = true } else { isStopped = false }
		let isRunning = state == .running

		// Continue and pause occupy the same slot, as in every debugger.
		if isRunning {
			addButton(at: &x, y: y, size: size, symbol: "pause.fill", enabled: true, action: { self.onPause?() })
		} else {
			addButton(at: &x, y: y, size: size, symbol: "play.fill", enabled: isStopped, action: { self.onContinue?() })
		}

		addButton(at: &x, y: y, size: size, symbol: "arrow.turn.down.right", enabled: isStopped, action: { self.onStepOver?() })
		addButton(at: &x, y: y, size: size, symbol: "arrow.down.to.line", enabled: isStopped, action: { self.onStepInto?() })
		addButton(at: &x, y: y, size: size, symbol: "arrow.up.to.line", enabled: isStopped, action: { self.onStepOut?() })
		x += Theme.current.scaled(8)
		addButton(at: &x, y: y, size: size, symbol: "stop.fill", enabled: state != .idle && state != .terminated, action: { self.onStop?() })

		let label = NSAttributedString(string: statusText, attributes: [
			.font: Theme.current.uiFont(11),
			.foregroundColor: Theme.current.sidebarText,
		])
		label.draw(at: NSPoint(x: x + Theme.current.scaled(10), y: bounds.midY - label.size().height / 2))
	}

	private var statusText: String {
		switch state {
		case .idle: return "Not running"
		case .starting: return "Starting…"
		case .running: return "Running"
		case let .stopped(reason): return "Paused — \(reason)"
		case .terminated: return "Finished"
		}
	}

	private func addButton(
		at x: inout CGFloat,
		y: CGFloat,
		size: CGFloat,
		symbol: String,
		enabled: Bool,
		action: @escaping () -> Void
	) {
		let rect = NSRect(x: x, y: y, width: size, height: size)
		let color = enabled ? Theme.current.sidebarHeaderText : Theme.current.gitIgnored.withAlphaComponent(0.4)

		if let icon = Theme.symbol(symbol, size: 11 * Theme.current.scale, color: color) {
			let glyph = Theme.current.scaled(13)
			icon.draw(
				in: NSRect(x: rect.midX - glyph / 2, y: rect.midY - glyph / 2, width: glyph, height: glyph),
				from: .zero, operation: .sourceOver, fraction: 1.0,
				respectFlipped: true, hints: nil
			)
		}
		if enabled { buttonFrames.append((rect, action)) }
		x += size + Theme.current.scaled(2)
	}
}
