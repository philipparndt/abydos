import AppKit
import AbydosKit

/// Debugger UI: execution controls, call stack, and variables.
///
/// A native front end over DAP rather than Delve's terminal UI, so breakpoints
/// live in the editor gutter and inspecting a value is a disclosure triangle
/// instead of a `print` command.
final class DebugPane: NSView {
	/// Called to show the file and line execution stopped at.
	var onNavigate: ((URL, Int) -> Void)?
	/// Asked to start the program again, once it has finished.
	var onRunAgain: (() -> Void)?
	var onDebugAgain: (() -> Void)?

	private let session: DebugSession
	private let projectRoot: URL

	/// The session this pane drives, so the window can reach it for breakpoints.
	var debugSession: DebugSession { session }

	/// Whether the program being debugged is still going, for the tab's colour.
	var isSessionActive: Bool { session.isActive }

	/// The project this was started for.
	///
	/// A window that follows its terminal can be looking at another project by
	/// the time somebody comes back to this pane, and a debugger belongs to the
	/// sources it is stopped in.
	var debuggedProject: URL { projectRoot }

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

	/// A watched expression in the tree, above the scopes.
	private final class WatchNode {
		let watch: WatchExpression
		init(watch: WatchExpression) { self.watch = watch }
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
	private var watchNodes: [WatchNode] = []
	private var watchField: NSTextField!
	private var threadPopUp: NSPopUpButton!

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

	private var console: TerminalPane!
	private var clearButton: NSButton!
	private var variablesScroll: NSScrollView!
	private var rightSide: NSView!
	private var sideTabs: NSSegmentedControl!
	/// Output arrived while the console was not the one showing.
	private var hasUnreadOutput = false

	/// Appends adapter or program output, keeping the newest visible.
	func appendOutput(_ text: String) {
		guard !text.isEmpty else { return }
		// A debug adapter hands over whole lines without the carriage return a
		// terminal expects, which would otherwise staircase down the screen.
		// Normalised first, or output that already ends its lines properly gets
		// a second carriage return and a blank line between every line.
		let lines = text
			.replacingOccurrences(of: "\r\n", with: "\n")
			.replacingOccurrences(of: "\n", with: "\r\n")
		console.terminalView.append(lines)

		// A hidden log has to say when it has something, or a build error is
		// invisible behind a tab nobody had a reason to press.
		guard console.isHidden else { return }
		hasUnreadOutput = true
		sideTabs.setLabel("Console •", forSegment: 1)
	}

	@objc private func clearConsole() {
		console.terminalView.clear()
	}

	@objc private func sideTabChanged() {
		let showsConsole = sideTabs.selectedSegment == 1
		console.isHidden = !showsConsole
		clearButton.isHidden = !showsConsole
		variablesScroll.isHidden = showsConsole
		watchField.isHidden = showsConsole
		if showsConsole {
			hasUnreadOutput = false
			sideTabs.setLabel("Console", forSegment: 1)
		}
	}

	/// Shows the log, for when something has gone wrong and it is the only
	/// thing worth looking at.
	func showConsole() {
		sideTabs.selectedSegment = 1
		sideTabChanged()
	}

	/// Shows the variables, which is what stopping somewhere is *for*.
	///
	/// The two do not fit side by side at any panel height somebody would
	/// choose, so the pane follows the session instead of asking: a program
	/// that is running has a log worth reading and no variables to speak of,
	/// and the instant it stops that reverses.
	func showVariables() {
		sideTabs.selectedSegment = 0
		sideTabChanged()
	}

	/// Watches something chosen in the editor.
	///
	/// The tab changes with it, because a watch added from the editor is added
	/// by somebody looking at the editor: leaving it on the console would put
	/// the answer somewhere they are not looking, and the question would seem
	/// to have done nothing.
	func watch(_ expression: String) {
		let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		showVariables()
		session.addWatch(trimmed)
	}

	var toolbarToolTipsForTesting: [String] { toolbar.toolTipsForTesting() }

	/// Copies the first variable row the way the menu does, and says what
	/// landed on the pasteboard.
	func copyFirstVariableForTesting() -> String {
		for row in 0..<variablesOutline.numberOfRows {
			guard let node = variablesOutline.item(atRow: row) as? VariableNode else { continue }
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(
				"\(node.variable.name) = \(node.variable.value)", forType: .string
			)
			return NSPasteboard.general.string(forType: .string) ?? "nothing"
		}
		return "no variable rows"
	}

	@discardableResult
	func writeToolbarImageForTesting(to path: String) -> Bool {
		toolbar.writeImageForTesting(to: path, state: session.state, exitCode: session.exitCode)
	}

	var showsConsoleForTesting: Bool { !console.isHidden }
	var consoleTabLabelForTesting: String { sideTabs.label(forSegment: 1) ?? "" }

	private func build() {
		toolbar = DebugToolbar()
		toolbar.onContinue = { [weak self] in self?.session.resume() }
		toolbar.onPause = { [weak self] in self?.session.pause() }
		toolbar.onStepOver = { [weak self] in self?.session.stepOver() }
		toolbar.onStepInto = { [weak self] in self?.session.stepInto() }
		toolbar.onStepOut = { [weak self] in self?.session.stepOut() }
		toolbar.onStop = { [weak self] in self?.session.stop() }
		// Not the session's to do: what to start is a launch configuration, and
		// the window is what holds those.
		toolbar.onRunAgain = { [weak self] in self?.onRunAgain?() }
		toolbar.onDebugAgain = { [weak self] in self?.onDebugAgain?() }
		// Where this session runs, when that is somewhere else.
		toolbar.location = session.location

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
		variables.menu = makeVariablesMenu()
		variablesOutline = variables

		// A goroutine picker above the stack: the one that hit the breakpoint is
		// rarely the only one worth looking at, and a deadlock is a question
		// about the others.
		threadPopUp = NSPopUpButton()
		threadPopUp.controlSize = .small
		threadPopUp.font = Theme.current.uiFont(10.5)
		threadPopUp.target = self
		threadPopUp.action = #selector(threadChosen)
		threadPopUp.isEnabled = false

		// A watch field under it: an expression is the thing you actually want
		// the value of, and hunting for it in a tree of locals is not the same.
		watchField = NSTextField()
		watchField.placeholderString = "Watch an expression…"
		watchField.font = Theme.current.uiFont(11)
		watchField.controlSize = .small
		watchField.focusRingType = .none
		watchField.target = self
		watchField.action = #selector(watchEntered)

		let stackScroll = makeScrollView(document: stack)
		let variablesScroll = makeScrollView(document: variables)
		self.variablesScroll = variablesScroll

		let leftSide = NSView()
		leftSide.addSubview(threadPopUp)
		leftSide.addSubview(stackScroll)

		let split = ThinDividerSplitView()
		split.isVertical = true
		split.dividerStyle = .thin
		split.addArrangedSubview(leftSide)

		// Variables and the log share the right-hand side rather than the log
		// taking a permanent strip along the bottom. It is worth looking at
		// when something has gone wrong and worth nothing the rest of the time,
		// which is exactly what a tab is for.
		let rightSide = NSView()
		rightSide.addSubview(watchField)
		rightSide.addSubview(variablesScroll)
		split.addArrangedSubview(rightSide)
		self.rightSide = rightSide

		addSubview(toolbar)
		addSubview(split)

		// The adapter's own output — build errors, the program's stdout, and
		// anything that went wrong starting it. Without somewhere to put this,
		// a failed launch looks identical to one that simply has not stopped
		// yet.
		// The same terminal the panel runs commands in, minus the shell: a
		// program under the debugger prints the colours it always prints, and
		// anything else would show them as escape sequences.
		console = TerminalPane(readOnly: ())
		console.isHidden = true
		rightSide.addSubview(console)

		clearButton = NSButton(title: "", target: self, action: #selector(clearConsole))
		clearButton.isBordered = false
		clearButton.image = Theme.symbol("trash", size: 10 * Theme.current.scale, color: Theme.current.gitIgnored)
		clearButton.imagePosition = .imageOnly
		clearButton.toolTip = "Clear the console (⌘K)"
		clearButton.isHidden = true

		sideTabs = NSSegmentedControl(
			labels: ["Variables", "Console"], trackingMode: .selectOne,
			target: self, action: #selector(sideTabChanged)
		)
		// The log, until there is something to look at. A session that has just
		// started is compiling, linking and printing — and has no variables at
		// all until it stops somewhere. `showVariables` takes over the moment
		// it does.
		sideTabs.selectedSegment = 1
		sideTabs.controlSize = .small
		sideTabs.font = Theme.current.uiFont(10.5)
		addSubview(sideTabs)
		addSubview(clearButton)

		for view in [console, variablesScroll, sideTabs, clearButton, threadPopUp, watchField, stackScroll]
			as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
		}
		toolbar.translatesAutoresizingMaskIntoConstraints = false
		split.translatesAutoresizingMaskIntoConstraints = false

		toolbarHeight = toolbar.heightAnchor.constraint(equalToConstant: Theme.current.scaled(30))
		NSLayoutConstraint.activate([
			toolbar.topAnchor.constraint(equalTo: topAnchor),
			toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
			toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
			toolbarHeight,

			// In the toolbar's own row, at the far end: it belongs to the pane
			// rather than to the row of stepping buttons.
			sideTabs.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
			sideTabs.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(10)),

			// Beside the tabs, and only while the console is the one showing.
			clearButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
			clearButton.trailingAnchor.constraint(
				equalTo: sideTabs.leadingAnchor, constant: -Theme.current.scaled(8)
			),
			clearButton.widthAnchor.constraint(equalToConstant: Theme.current.scaled(18)),
			clearButton.heightAnchor.constraint(equalToConstant: Theme.current.scaled(18)),

			split.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
			split.leadingAnchor.constraint(equalTo: leadingAnchor),
			split.trailingAnchor.constraint(equalTo: trailingAnchor),
			split.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		let inset = Theme.current.scaled(6)
		NSLayoutConstraint.activate([
			threadPopUp.topAnchor.constraint(equalTo: leftSide.topAnchor, constant: inset / 2),
			threadPopUp.leadingAnchor.constraint(equalTo: leftSide.leadingAnchor, constant: inset),
			threadPopUp.trailingAnchor.constraint(equalTo: leftSide.trailingAnchor, constant: -inset),

			stackScroll.topAnchor.constraint(equalTo: threadPopUp.bottomAnchor, constant: inset / 2),
			stackScroll.leadingAnchor.constraint(equalTo: leftSide.leadingAnchor),
			stackScroll.trailingAnchor.constraint(equalTo: leftSide.trailingAnchor),
			stackScroll.bottomAnchor.constraint(equalTo: leftSide.bottomAnchor),

			watchField.topAnchor.constraint(equalTo: rightSide.topAnchor, constant: inset / 2),
			watchField.leadingAnchor.constraint(equalTo: rightSide.leadingAnchor, constant: inset),
			watchField.trailingAnchor.constraint(equalTo: rightSide.trailingAnchor, constant: -inset),

			variablesScroll.topAnchor.constraint(equalTo: watchField.bottomAnchor, constant: inset / 2),
			variablesScroll.leadingAnchor.constraint(equalTo: rightSide.leadingAnchor),
			variablesScroll.trailingAnchor.constraint(equalTo: rightSide.trailingAnchor),
			variablesScroll.bottomAnchor.constraint(equalTo: rightSide.bottomAnchor),

			console.topAnchor.constraint(equalTo: rightSide.topAnchor),
			console.leadingAnchor.constraint(equalTo: rightSide.leadingAnchor),
			console.trailingAnchor.constraint(equalTo: rightSide.trailingAnchor),
			console.bottomAnchor.constraint(equalTo: rightSide.bottomAnchor),
		])

		// The views' own hidden flags are set above, one by one; this makes them
		// agree with whichever segment is selected, so the two cannot drift
		// apart when the starting tab changes.
		sideTabChanged()

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

	/// Told when the debugger starts or stops, so the tab can wear it.
	var onRunningChanged: (() -> Void)?

	private func wireSession() {
		session.observeState { [weak self, weak session] state in
			self?.toolbar.update(state: state, exitCode: session?.exitCode)
			self?.onRunningChanged?()
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
		session.onWatchesChanged = { [weak self] in
			self?.rebuildWatches()
		}
		session.onThreadsChanged = { [weak self] in
			self?.rebuildThreads()
		}
		session.observeStopped { [weak self] file, line in
			// Stopping is what the variables are for, and the console has
			// nothing new to say while nothing is running. Switched rather than
			// shown beside: at any panel height somebody would actually use,
			// the two together give each half of too little.
			self?.showVariables()
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

	// MARK: - Copying

	private func makeVariablesMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		menu.delegate = self
		return menu
	}

	/// The row the menu was opened on, whichever kind it is.
	private var clickedRowItem: Any? {
		let row = variablesOutline.clickedRow >= 0
			? variablesOutline.clickedRow
			: variablesOutline.selectedRow
		guard row >= 0 else { return nil }
		return variablesOutline.item(atRow: row)
	}

	private func copy(_ text: String) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	@objc private func copyValue() {
		switch clickedRowItem {
		case let node as VariableNode: copy(node.variable.value)
		case let node as WatchNode: copy(node.watch.value ?? "")
		default: break
		}
	}

	@objc private func copyName() {
		switch clickedRowItem {
		case let node as VariableNode: copy(node.variable.name)
		case let node as WatchNode: copy(node.watch.expression)
		default: break
		}
	}

	/// Copies `name: value`, which is what goes into a note or a message.
	@objc private func copyBoth() {
		switch clickedRowItem {
		case let node as VariableNode: copy("\(node.variable.name) = \(node.variable.value)")
		case let node as WatchNode: copy("\(node.watch.expression) = \(node.watch.value ?? "")")
		default: break
		}
	}

	/// Watches whatever was clicked, so a local can be followed across frames.
	@objc private func watchClicked() {
		switch clickedRowItem {
		case let node as VariableNode: session.addWatch(node.variable.name)
		case let node as WatchNode: session.addWatch(node.watch.expression)
		default: break
		}
	}

	@objc private func removeClickedWatch() {
		guard let node = clickedRowItem as? WatchNode else { return }
		session.removeWatch(id: node.watch.id)
	}

	@objc private func removeAllWatches() {
		session.removeAllWatches()
	}

	// MARK: - Watches and threads

	@objc private func watchEntered() {
		let expression = watchField.stringValue
		guard !expression.trimmingCharacters(in: .whitespaces).isEmpty else { return }
		session.addWatch(expression)
		watchField.stringValue = ""
	}

	@objc private func threadChosen() {
		let index = threadPopUp.indexOfSelectedItem
		guard session.threads.indices.contains(index) else { return }
		let thread = session.threads[index]
		Task { await session.selectThread(id: thread.id) }
	}

	private func rebuildThreads() {
		threadPopUp.removeAllItems()
		let threads = session.threads
		threadPopUp.isEnabled = threads.count > 1

		guard !threads.isEmpty else {
			threadPopUp.addItem(withTitle: "No goroutines")
			return
		}
		for thread in threads {
			threadPopUp.addItem(withTitle: thread.name.isEmpty ? "Thread \(thread.id)" : thread.name)
		}
		if let selected = session.selectedThreadID,
		   let index = threads.firstIndex(where: { $0.id == selected }) {
			threadPopUp.selectItem(at: index)
		}
	}

	private func rebuildWatches() {
		watchNodes = session.watches.map { WatchNode(watch: $0) }
		variablesOutline.reloadData()
		for node in scopeNodes { variablesOutline.expandItem(node) }
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

extension DebugPane: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()

		func item(_ title: String, _ selector: Selector) -> NSMenuItem {
			let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			entry.target = self
			return entry
		}

		let clicked = clickedRowItem
		guard clicked is VariableNode || clicked is WatchNode else {
			if !session.watches.isEmpty {
				menu.addItem(item("Remove All Watches", #selector(removeAllWatches)))
			}
			return
		}

		menu.addItem(item("Copy Value", #selector(copyValue)))
		menu.addItem(item("Copy Name", #selector(copyName)))
		menu.addItem(item("Copy Name and Value", #selector(copyBoth)))
		menu.addItem(.separator())

		if clicked is WatchNode {
			menu.addItem(item("Remove Watch", #selector(removeClickedWatch)))
			menu.addItem(item("Remove All Watches", #selector(removeAllWatches)))
		} else {
			menu.addItem(item("Add to Watches", #selector(watchClicked)))
		}
	}
}

extension DebugPane: NSOutlineViewDataSource, NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		// Watches first, then the scopes: what you asked to see before what you
		// were given.
		if item == nil { return watchNodes.count + scopeNodes.count }
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
		if item == nil {
			return index < watchNodes.count ? watchNodes[index] : scopeNodes[index - watchNodes.count]
		}
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
		if let watch = item as? WatchNode {
			return VariableCell(
				variable: Variable(
					name: watch.watch.expression,
					value: watch.watch.value ?? "…",
					type: nil,
					variablesReference: watch.watch.variablesReference
				),
				isFaded: watch.watch.failed
			)
		}
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
		//
		// Canonical on both sides: the frame's path comes from the debug
		// adapter, which answers with the real one, and the project root is
		// whatever the project was opened by. Under `/tmp` or `/var` — symlinks,
		// both — the two shared no prefix, every frame fell to its last
		// component, and two `main.go`s in different packages were drawn as the
		// same line. Same asymmetry as 0430.
		let path = FilePath.canonical(file)
		let base = FilePath.canonical(projectRoot)
		var display = path
		if path.hasPrefix(base + "/") {
			display = String(path.dropFirst(base.count + 1))
		} else {
			display = (path as NSString).lastPathComponent
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
	/// A watch that could not be evaluated in this frame is drawn quietly: it
	/// is out of scope here, not wrong.
	private let isFaded: Bool

	init(variable: Variable, isFaded: Bool = false) {
		self.variable = variable
		self.isFaded = isFaded
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

		let valueColour = isFaded
			? Theme.current.gitIgnored
			: (isSelected ? NSColor.hex(0xE8EAED) : Theme.current.gitAdded)
		let value = NSAttributedString(string: variable.value, attributes: [
			.font: font,
			.foregroundColor: valueColour,
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
	/// Start it again, once it is over — with or without the debugger.
	var onRunAgain: (() -> Void)?
	var onDebugAgain: (() -> Void)?

	/// What a button is, which decides its glyph, its name and what it does.
	private enum Kind {
		case play, pause, stepOver, stepInto, stepOut, stop
		/// Only once it is over, where Continue was: continuing a program that
		/// has ended means nothing, and starting it again is the one thing
		/// somebody standing here wants.
		case runAgain, debugAgain

		var tooltip: String {
			switch self {
			case .play: return "Continue (F9)"
			case .pause: return "Pause"
			case .stepOver: return "Step Over (F8)"
			case .stepInto: return "Step Into (F7)"
			case .stepOut: return "Step Out (\u{21E7}F8)"
			case .stop: return "Stop (\u{2318}F2)"
			case .runAgain: return "Run Again"
			case .debugAgain: return "Debug Again"
			}
		}
	}

	private struct Button {
		let rect: NSRect
		let kind: Kind
		let isEnabled: Bool
	}

	private var state: DebugSession.State = .idle
	private var exitCode: Int?
	private var buttons: [Button] = []
	private var labelOrigin: CGFloat = 0
	/// Tooltip text by the tag AppKit handed back for it.
	private var toolTipsByTag: [NSView.ToolTipTag: String] = [:]

	override var isFlipped: Bool { true }

	func update(state: DebugSession.State, exitCode: Int? = nil) {
		guard state != self.state || exitCode != self.exitCode else { return }
		self.state = state
		self.exitCode = exitCode
		rebuild()
	}

	override func layout() {
		super.layout()
		rebuild()
	}

	// MARK: - Layout

	/// Works out where the buttons are, and registers their tooltips.
	///
	/// Deliberately not done while drawing: registering a tooltip mutates
	/// tracking state, which is not something to do from inside `draw`.
	private func rebuild() {
		let isStopped: Bool
		if case .stopped = state { isStopped = true } else { isStopped = false }
		let isRunning = state == .running
		let canStop = state != .idle && state != .terminated

		let size = Theme.current.scaled(22)
		let gap = Theme.current.scaled(2)
		let y = bounds.midY - size / 2
		var x = Theme.current.scaled(10)

		func place(_ kind: Kind, enabled: Bool, extraGap: CGFloat = 0) -> Button {
			x += extraGap
			let button = Button(
				rect: NSRect(x: x, y: y, width: size, height: size), kind: kind, isEnabled: enabled
			)
			x += size + gap
			return button
		}

		// Over and done with: the stepping buttons have nothing to step, and
		// the slot they were in is where starting it again belongs.
		if !canStop {
			buttons = [
				place(.runAgain, enabled: true),
				place(.debugAgain, enabled: true),
			]
		} else {
			// Continue and pause occupy the same slot, as in every debugger.
			buttons = [
				isRunning ? place(.pause, enabled: true) : place(.play, enabled: isStopped),
				place(.stepOver, enabled: isStopped),
				place(.stepInto, enabled: isStopped),
				place(.stepOut, enabled: isStopped),
				place(.stop, enabled: canStop, extraGap: Theme.current.scaled(8)),
			]
		}
		labelOrigin = x + Theme.current.scaled(10)

		removeAllToolTips()
		toolTipsByTag = [:]
		for button in buttons {
			// Owned by the view, with the text kept here. Passing a bridged
			// string as the owner instead crashes on hover: AppKit does not
			// retain it, so by the time somebody points at the button the
			// string it reads back has been freed.
			let tag = addToolTip(button.rect, owner: self, userData: nil)
			toolTipsByTag[tag] = button.kind.tooltip
		}
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		guard let button = buttons.first(where: { $0.isEnabled && $0.rect.contains(point) })
		else { return }

		switch button.kind {
		case .play: onContinue?()
		case .pause: onPause?()
		case .stepOver: onStepOver?()
		case .stepInto: onStepInto?()
		case .stepOut: onStepOut?()
		case .stop: onStop?()
		case .runAgain: onRunAgain?()
		case .debugAgain: onDebugAgain?()
		}
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

		if buttons.isEmpty { rebuild() }

		for button in buttons {
			let colour = button.isEnabled
				? Theme.current.sidebarHeaderText
				: Theme.current.gitIgnored.withAlphaComponent(0.4)
			draw(kind: button.kind, in: button.rect, colour: colour)
		}

		let failed = state == .terminated && (exitCode ?? 0) != 0
		let label = NSAttributedString(string: statusText, attributes: [
			.font: Theme.current.uiFont(11),
			.foregroundColor: failed ? NSColor.hex(0xE05252) : Theme.current.sidebarText,
		])
		label.draw(at: NSPoint(x: labelOrigin, y: bounds.midY - label.size().height / 2))

		guard let location, !location.isEmpty else { return }
		drawTag(location, after: labelOrigin + label.size().width)
	}

	/// The tag: a rounded chip in the colour the rest of this app uses for
	/// something running elsewhere.
	private func drawTag(_ text: String, after x: CGFloat) {
		let attributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(10),
			.foregroundColor: Theme.current.sidebarBackground,
		]
		let label = NSAttributedString(string: text, attributes: attributes)
		let size = label.size()
		let padding = Theme.current.scaled(6)
		let gap = Theme.current.scaled(10)

		let chip = NSRect(
			x: x + gap,
			y: bounds.midY - (size.height + Theme.current.scaled(3)) / 2,
			width: size.width + padding * 2,
			height: size.height + Theme.current.scaled(3)
		)
		// Not drawn at all rather than clipped: a pod name cut in half is worse
		// than no tag, and the toolbar is narrow when the panel is.
		guard chip.maxX < bounds.width - Theme.current.scaled(120) else { return }

		let path = NSBezierPath(roundedRect: chip, xRadius: chip.height / 2, yRadius: chip.height / 2)
		Theme.current.gitModified.setFill()
		path.fill()
		label.draw(at: NSPoint(x: chip.minX + padding, y: chip.midY - size.height / 2))
	}

	/// The three stepping glyphs are drawn rather than borrowed.
	///
	/// No SF Symbol says "step over": the nearest are corner arrows that read
	/// as "into" or "out" just as readily, which is no use on a row of three
	/// buttons differing only in that. Drawn, they say what every debugger has
	/// said for twenty years — an arc hopping over the call, an arrow down
	/// into it, an arrow back up out of it, with the call itself as a dot.
	private func draw(kind: Kind, in rect: NSRect, colour: NSColor) {
		let glyph = Theme.current.scaled(14)
		let box = NSRect(
			x: rect.midX - glyph / 2, y: rect.midY - glyph / 2, width: glyph, height: glyph
		)

		switch kind {
		case .play, .pause, .stop, .runAgain, .debugAgain:
			let symbol: String
			switch kind {
			case .pause: symbol = "pause.fill"
			case .stop: symbol = "stop.fill"
			case .debugAgain: symbol = "ladybug.fill"
			default: symbol = "play.fill"
			}
			Theme.symbol(symbol, size: 11 * Theme.current.scale, color: colour)?.drawFitted(in: box)

		case .stepOver:
			// Curves rather than arc angles: this view is flipped, and angles
			// measured the usual way come out mirrored in it.
			colour.setStroke()
			let arc = NSBezierPath()
			arc.lineWidth = Theme.current.scaled(1.5)
			let left = NSPoint(x: box.minX + box.width * 0.04, y: box.maxY - box.height * 0.34)
			let right = NSPoint(x: box.maxX - box.width * 0.16, y: box.maxY - box.height * 0.38)
			arc.move(to: left)
			arc.curve(
				to: right,
				controlPoint1: NSPoint(x: box.minX + box.width * 0.08, y: box.minY),
				controlPoint2: NSPoint(x: box.maxX - box.width * 0.12, y: box.minY)
			)
			arc.stroke()
			arrowhead(
				at: NSPoint(x: right.x + box.width * 0.06, y: right.y + box.height * 0.26),
				pointing: .down, size: box.width * 0.34, colour: colour
			)
			callDot(in: box, colour: colour)

		case .stepInto:
			colour.setStroke()
			let into = NSBezierPath()
			into.lineWidth = Theme.current.scaled(1.5)
			into.move(to: NSPoint(x: box.midX, y: box.minY))
			into.line(to: NSPoint(x: box.midX, y: box.midY + box.height * 0.02))
			into.stroke()
			arrowhead(
				at: NSPoint(x: box.midX, y: box.midY + box.height * 0.26),
				pointing: .down, size: box.width * 0.4, colour: colour
			)
			callDot(in: box, colour: colour)

		case .stepOut:
			colour.setStroke()
			let out = NSBezierPath()
			out.lineWidth = Theme.current.scaled(1.5)
			out.move(to: NSPoint(x: box.midX, y: box.midY + box.height * 0.18))
			out.line(to: NSPoint(x: box.midX, y: box.minY + box.height * 0.28))
			out.stroke()
			arrowhead(
				at: NSPoint(x: box.midX, y: box.minY),
				pointing: .up, size: box.width * 0.4, colour: colour
			)
			callDot(in: box, colour: colour)
		}
	}

	/// The call being stepped over, into or out of.
	private func callDot(in box: NSRect, colour: NSColor) {
		let size = box.width * 0.26
		colour.withAlphaComponent(0.8).setFill()
		NSBezierPath(ovalIn: NSRect(
			x: box.midX - size / 2, y: box.maxY - size, width: size, height: size
		)).fill()
	}

	private enum Direction { case up, down }

	/// A filled triangle. The view is flipped, so a downward arrow's base sits
	/// at a smaller y than its tip.
	private func arrowhead(at tip: NSPoint, pointing: Direction, size: CGFloat, colour: NSColor) {
		let path = NSBezierPath()
		let half = size / 2
		let back = pointing == .down ? tip.y - size * 0.85 : tip.y + size * 0.85
		path.move(to: tip)
		path.line(to: NSPoint(x: tip.x - half, y: back))
		path.line(to: NSPoint(x: tip.x + half, y: back))
		path.close()
		colour.setFill()
		path.fill()
	}

	/// Asks for each tooltip the way AppKit does when somebody hovers.
	func toolTipsForTesting() -> [String] {
		toolTipsByTag.keys.sorted().map {
			view(self, stringForToolTip: $0, point: .zero, userData: nil)
		}
	}

	/// Draws the toolbar to a PNG, so the glyphs can be looked at.
	@discardableResult
	func writeImageForTesting(to path: String, state: DebugSession.State, exitCode: Int? = nil) -> Bool {
		// Wide enough for the tag to have somewhere to go: it is left out when
		// the toolbar is narrow, which is right in the panel and useless here.
		frame = NSRect(x: 0, y: 0, width: location == nil ? 360 : 620, height: 30)
		self.state = state
		self.exitCode = exitCode
		rebuild()
		guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return false }
		cacheDisplay(in: bounds, to: rep)
		guard let data = rep.representation(using: .png, properties: [:]) else { return false }
		return (try? data.write(to: URL(fileURLWithPath: path))) != nil
	}

	/// Where this is running, when it is not here. Drawn as a tag beside the
	/// state, because a session in a pod is otherwise indistinguishable from
	/// one on this machine — same toolbar, same stack, same variables.
	var location: String? { didSet { needsDisplay = true } }

	private var statusText: String {
		switch state {
		case .idle: return "Not running"
		case .starting: return "Starting\u{2026}"
		case .running: return "Running"
		case let .stopped(reason): return "Paused \u{2014} \(reason)"
		case .terminated:
			guard let exitCode else { return "Finished" }
			return exitCode == 0 ? "Finished — exit code 0" : "Failed — exit code \(exitCode)"
		}
	}
}

/// The toolbar on its own, for looking at.
///
/// A session in a pod cannot be conjured in a capture run — it needs a cluster
/// — so the one thing that differs is drawn directly: the state it would be in,
/// and the tag saying where.
enum DebugToolbarPreview {
	@discardableResult
	static func write(to path: String, location: String?) -> Bool {
		let toolbar = DebugToolbar()
		toolbar.location = location
		return toolbar.writeImageForTesting(
			to: path, state: .stopped(reason: "breakpoint"), exitCode: nil
		)
	}
}

extension DebugToolbar: NSViewToolTipOwner {
	func view(
		_ view: NSView,
		stringForToolTip tag: NSView.ToolTipTag,
		point: NSPoint,
		userData: UnsafeMutableRawPointer?
	) -> String {
		toolTipsByTag[tag] ?? ""
	}
}
