import AppKit
import AbydosKit

/// A text field with room around its text.
///
/// The commit subject draws its own background, and a field's text otherwise
/// sits hard against the left edge of it.
final class InsetTextField: NSTextField {
	override class var cellClass: AnyClass? {
		get { InsetTextFieldCell.self }
		set { super.cellClass = newValue }
	}
}

final class InsetTextFieldCell: NSTextFieldCell {
	/// Inset from the edges, and sitting in the middle of them.
	///
	/// A field taller than its line — which this one is, to be comfortable to
	/// click — draws the text against the top otherwise, and the placeholder
	/// sits above the line everything else is on.
	private func inset(_ rect: NSRect) -> NSRect {
		let room = rect.insetBy(dx: 5, dy: 0)
		let height = ceil(font?.boundingRectForFont.height ?? room.height)
		guard height < room.height else { return room }
		return NSRect(
			x: room.minX,
			y: room.minY + ((room.height - height) / 2).rounded(),
			width: room.width,
			height: height
		)
	}

	override func drawingRect(forBounds rect: NSRect) -> NSRect {
		super.drawingRect(forBounds: inset(rect))
	}

	override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
		super.edit(withFrame: inset(rect), in: view, editor: editor, delegate: delegate, event: event)
	}

	override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
		super.select(withFrame: inset(rect), in: view, editor: editor, delegate: delegate, start: start, length: length)
	}
}
