import AppKit
import AbydosKit

/// One variable in a tree: its name, its value, and its type where the adapter
/// gave one.
///
/// **Shared rather than copied.** It was `private` in `DebugPane.swift` while
/// the panel's tree was the only place a variable was drawn. A value beside the
/// code can be opened into a tree of its own now, and two rows drawn two ways
/// would be one appearance today and two after somebody changes a colour.
final class VariableCell: NSView {
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
