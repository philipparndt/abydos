import AppKit
import AbydosKit

/// The views the checklist is made of: its table, its rows, and the two cells.
///
/// They are here rather than beside `ResultChecklist` because none of them
/// needs anything of it. Each owns what it draws — a row view asks the window
/// who has the keyboard rather than being told, and a cell is handed the match
/// and the tick it is drawing and keeps nothing else.
/// What the list's undo manager holds instead of the view, for the reason
/// `FileUndoTarget` exists: a registered undo keeps its target alive.
final class ChecklistUndoTarget {
	weak var list: ResultChecklist?
}

/// The results table, which answers ⌘Z for the ticks and hands its keys to the
/// list first.
///
/// `undo:` is answered here and not through an `undoManager` override, exactly
/// as `NavigatorOutlineView` does it: the property would hand this stack to any
/// field editor that came asking, and the two stacks would become one.
///
/// ⌫ and ⌘⌫ are not answered and are not bound. In the tree ⌘⌫ moves the
/// selection to the trash, and the two panes look alike enough that a
/// half-remembered key must do nothing here rather than something.
final class ChecklistTable: NSTableView {
	var onKeyDown: ((NSEvent) -> Bool)?
	/// The selection was moved by a key, with whether that key was held down.
	var onSelectionMovedByKey: ((Bool) -> Void)?
	var markUndoManager: (() -> UndoManager?)?

	override var acceptsFirstResponder: Bool { true }

	@objc func undo(_ sender: Any?) { markUndoManager?()?.undo() }
	@objc func redo(_ sender: Any?) { markUndoManager?()?.redo() }

	override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		// Greyed out over an empty stack rather than swallowing the key: an Undo
		// that is enabled and does nothing is the same lie as one that undoes the
		// wrong thing, only quieter.
		if item.action == #selector(undo(_:)) { return markUndoManager?()?.canUndo ?? false }
		if item.action == #selector(redo(_:)) { return markUndoManager?()?.canRedo ?? false }
		return super.validateUserInterfaceItem(item)
	}

	/// A right-click outside the selection takes the row under the pointer.
	///
	/// The standard table behaviour, and the one that matters here: without it
	/// the menu would act on whatever happened to be selected somewhere else in
	/// the list, which for a gesture that ticks a hundred rows at once is a
	/// surprise nobody wants.
	override func menu(for event: NSEvent) -> NSMenu? {
		let point = convert(event.locationInWindow, from: nil)
		let clicked = row(at: point)
		if clicked >= 0, !selectedRowIndexes.contains(clicked) {
			selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
		}
		return super.menu(for: event)
	}

	override func keyDown(with event: NSEvent) {
		if onKeyDown?(event) == true { return }
		// Around `super`, because the arrow keys are its own: what a press did to
		// the selection is the difference between before and after it.
		let before = selectedRowIndexes
		super.keyDown(with: event)
		if selectedRowIndexes != before {
			onSelectionMovedByKey?(event.isARepeat)
		}
	}

	override func becomeFirstResponder() -> Bool {
		redrawSelection()
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		redrawSelection()
		return super.resignFirstResponder()
	}

	/// The rows, because the selection changes colour with the keyboard.
	///
	/// The table's own `needsDisplay` is not enough and never was: a row view is
	/// a subview and invalidates itself, and the *cell* inside it is a subview
	/// again. The cell is the half that would go wrong quietly — its text turns
	/// near-white over a selected row, and near-white on the unfocused gray is
	/// unreadable in a light scheme. Same reason `redrawVisibleRows` exists in
	/// the project tree.
	private func redrawSelection() {
		needsDisplay = true
		enumerateAvailableRowViews { rowView, _ in
			rowView.needsDisplay = true
			for cell in rowView.subviews { cell.needsDisplay = true }
		}
	}
}

final class ChecklistRowView: NSTableRowView {
	/// True when the table this row is drawn in holds the keyboard.
	///
	/// Asked of the window rather than kept as a flag, exactly as
	/// `NavigatorRowView` asks it: a row view is made and thrown away on every
	/// reload, and a flag would have to be pushed into each of them by whoever
	/// noticed the keyboard move.
	var hasKeyboard: Bool {
		guard let table = superview, let responder = window?.firstResponder as? NSView
		else { return false }
		return responder === table || responder.isDescendant(of: table)
	}

	override func drawSelection(in dirtyRect: NSRect) {
		Theme.current.selection(.row, hasKeyboard: hasKeyboard).setFill()
		bounds.fill()
	}
}

final class ChecklistFileCell: NSView {
	private let result: FileSearchResult
	private let isCollapsed: Bool
	private let done: Int
	private let isDone: Bool

	init(result: FileSearchResult, isCollapsed: Bool, done: Int, isDone: Bool) {
		self.result = result
		self.isCollapsed = isCollapsed
		self.done = done
		self.isDone = isDone
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		var x = Theme.current.scaled(8)

		if let chevron = Theme.symbol(
			isCollapsed ? "chevron.right" : "chevron.down",
			size: 9 * Theme.current.scale,
			color: Theme.current.gitIgnored
		) {
			let size = Theme.current.scaled(10)
			chevron.drawFitted(in: NSRect(x: x, y: bounds.midY - size / 2, width: size, height: size))
		}
		x += Theme.current.scaled(14)

		let node = FileNode(url: result.url, isDirectory: false)
		if let icon = FileIcon.image(for: node, isExpanded: false) {
			let size = Theme.current.scaled(13)
			icon.drawFitted(in: NSRect(x: x, y: bounds.midY - size / 2, width: size, height: size))
			x += size + Theme.current.scaled(5)
		}

		let name = (result.relativePath as NSString).lastPathComponent
		let directory = (result.relativePath as NSString).deletingLastPathComponent

		var nameAttributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(12, weight: .medium),
			.foregroundColor: isDone ? Theme.current.gitIgnored : Theme.current.sidebarHeaderText,
		]
		if isDone { nameAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
		let nameString = NSAttributedString(string: name, attributes: nameAttributes)
		nameString.draw(at: NSPoint(x: x, y: bounds.midY - nameString.size().height / 2))
		x += nameString.size().width + Theme.current.scaled(8)

		if !directory.isEmpty {
			let path = NSAttributedString(string: directory, attributes: [
				.font: Theme.current.uiFont(10.5),
				.foregroundColor: Theme.current.gitIgnored,
			])
			path.draw(at: NSPoint(x: x, y: bounds.midY - path.size().height / 2))
			x += path.size().width + Theme.current.scaled(8)
		}

		// The right-hand end of a row is where its state lives, on headings and
		// on matches alike: a tick when the whole file is done, "2/5" while it is
		// part way, the plain count when none of it has been looked at.
		var right = bounds.width - Theme.current.scaled(12)
		if isDone, let tick = Theme.symbol(
			"checkmark", size: 10 * Theme.current.scale, color: Theme.current.gitAdded
		) {
			let size = Theme.current.scaled(11)
			right -= size
			tick.drawFitted(in: NSRect(x: right, y: bounds.midY - size / 2, width: size, height: size))
			right -= Theme.current.scaled(5)
		}

		let count = NSAttributedString(
			string: done > 0 && !isDone ? "\(done)/\(result.matches.count)" : "\(result.matches.count)",
			attributes: [
				.font: Theme.current.uiFont(10.5),
				.foregroundColor: Theme.current.gitIgnored,
			]
		)
		count.draw(at: NSPoint(
			x: right - count.size().width,
			y: bounds.midY - count.size().height / 2
		))
	}
}

final class ChecklistMatchCell: NSView {
	private let match: SearchMatch
	private let isDone: Bool

	init(match: SearchMatch, isDone: Bool) {
		self.match = match
		self.isDone = isDone
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		// Selected *and* the list has the keyboard: the light-on-dark text goes
		// with the strong highlight, and putting it on the unfocused gray would
		// be near-white on a pale band in a light scheme.
		let row = superview as? ChecklistRowView
		let isSelected = (row?.isSelected ?? false) && (row?.hasKeyboard ?? false)
		let x = Theme.current.scaled(34)

		let number = NSAttributedString(string: "\(match.line + 1)", attributes: [
			.font: Theme.terminalFont(size: Theme.current.uiFont(10.5).pointSize),
			.foregroundColor: Theme.current.gutterText,
		])
		// Right-aligned in its own column so the code lines up regardless of
		// how many digits the line number has.
		number.draw(at: NSPoint(
			x: x - number.size().width - Theme.current.scaled(6),
			y: bounds.midY - number.size().height / 2
		))

		var right = bounds.width - Theme.current.scaled(12)
		// The tick, in the same column the file heading's goes in, so a done row
		// is legible without reading the line: struck-through text alone is easy
		// to miss in a monospaced font at eleven points.
		if isDone, let tick = Theme.symbol(
			"checkmark", size: 10 * Theme.current.scale, color: Theme.current.gitAdded
		) {
			let size = Theme.current.scaled(11)
			right -= size
			tick.drawFitted(in: NSRect(x: right, y: bounds.midY - size / 2, width: size, height: size))
			right -= Theme.current.scaled(4)
		}

		// Leading whitespace is trimmed so deeply indented code stays readable in
		// a narrow panel.
		let trimmed = match.lineText.drop { $0 == " " || $0 == "\t" }
		var attributes: [NSAttributedString.Key: Any] = [
			.font: Theme.terminalFont(size: Theme.current.uiFont(11).pointSize),
			.foregroundColor: isDone
				? Theme.current.gitIgnored
				: (isSelected ? NSColor.hex(0xE8EAED) : Theme.current.editorText),
		]
		if isDone { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
		let text = NSAttributedString(string: String(trimmed), attributes: attributes)
		text.draw(in: NSRect(
			x: x,
			y: bounds.midY - text.size().height / 2,
			width: max(0, right - x),
			height: text.size().height
		))
	}
}
