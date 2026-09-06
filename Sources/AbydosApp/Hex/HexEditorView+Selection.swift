import AbydosKit
import AppKit

/// The caret and the selection, from the pointer and from the keyboard.
extension HexEditorView {
	// MARK: - Moving

	/// Puts the caret somewhere, keeping or dropping the anchor, and says so.
	func moveCaret(to offset: Int, extending: Bool, column: Column? = nil) {
		let clamped = max(0, min(document.count, offset))
		pendingNibble = nil
		if extending {
			if anchor == nil { anchor = caret }
		} else {
			anchor = nil
		}
		caret = clamped
		if let column { activeColumn = column }
		scrollCaretToVisible()
		needsDisplay = true
		onCaretChanged?(self)
	}

	func select(_ range: Range<Int>, column: Column? = nil) {
		let lower = max(0, min(document.count, range.lowerBound))
		let upper = max(lower, min(document.count, range.upperBound))
		pendingNibble = nil
		anchor = lower
		caret = upper
		if let column { activeColumn = column }
		scrollCaretToVisible()
		needsDisplay = true
		onCaretChanged?(self)
	}

	func scrollCaretToVisible() {
		let row = caret / bytesPerRow
		let rect = NSRect(x: 0, y: rowY(row), width: 1, height: rowHeight)
		scrollToVisible(rect.insetBy(dx: 0, dy: -rowHeight))
	}

	/// Scrolls so the offset's row is in the middle of the view.
	func scroll(toShow offset: Int) {
		guard let clip = enclosingScrollView?.contentView else { return }
		let row = max(0, min(document.count, offset)) / bytesPerRow
		let y = max(0, rowY(row) - clip.bounds.height / 2)
		clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(y, max(0, bounds.height - clip.bounds.height))))
		enclosingScrollView?.reflectScrolledClipView(clip)
	}

	/// The bytes whose rows are on screen.
	var visibleRange: Range<Int> {
		guard let clip = enclosingScrollView?.contentView else { return 0..<0 }
		let rows = rows(in: clip.bounds)
		return min(document.count, rows.lowerBound * bytesPerRow)..<min(document.count, rows.upperBound * bytesPerRow)
	}

	private var rowsPerPage: Int {
		guard let clip = enclosingScrollView?.contentView else { return 16 }
		return max(1, Int(clip.bounds.height / rowHeight) - 1)
	}

	// MARK: - The pointer

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let point = convert(event.locationInWindow, from: nil)
		guard let (offset, column) = offset(at: point) else { return }
		let extending = event.modifierFlags.contains(.shift)
		if extending {
			// The pressed byte joins the selection on whichever side it is.
			let base = anchor ?? caret
			moveCaret(to: offset >= base ? min(document.count, offset + 1) : offset, extending: true, column: column)
		} else {
			moveCaret(to: offset, extending: false, column: column)
			if event.clickCount == 2, offset < document.count {
				// A double-click takes the word of eight the byte is in.
				let start = offset - offset % 8
				select(start..<min(document.count, start + 8), column: column)
			}
		}
	}

	override func mouseDragged(with event: NSEvent) {
		autoscroll(with: event)
		let point = convert(event.locationInWindow, from: nil)
		guard let (offset, _) = offset(at: point) else { return }
		let base = anchor ?? caret
		if anchor == nil { anchor = caret }
		let target = offset >= base ? min(document.count, offset + 1) : offset
		if target != caret {
			caret = target
			needsDisplay = true
			onCaretChanged?(self)
		}
	}

	// MARK: - The keyboard

	override func keyDown(with event: NSEvent) {
		interpretKeyEvents([event])
	}

	override func doCommand(by selector: Selector) {
		let extending = NSStringFromSelector(selector).hasSuffix("AndModifySelection:")
		switch selector {
		case #selector(moveLeft(_:)), #selector(moveLeftAndModifySelection(_:)):
			moveCaret(to: caret - 1, extending: extending)
		case #selector(moveRight(_:)), #selector(moveRightAndModifySelection(_:)):
			moveCaret(to: caret + 1, extending: extending)
		case #selector(moveUp(_:)), #selector(moveUpAndModifySelection(_:)):
			moveCaret(to: caret - bytesPerRow, extending: extending)
		case #selector(moveDown(_:)), #selector(moveDownAndModifySelection(_:)):
			moveCaret(to: caret + bytesPerRow, extending: extending)
		case #selector(moveWordLeft(_:)), #selector(moveWordLeftAndModifySelection(_:)),
			 #selector(moveWordBackward(_:)), #selector(moveWordBackwardAndModifySelection(_:)):
			// A word is eight bytes: the gap in the row is where they end.
			moveCaret(to: caret % 8 == 0 ? caret - 8 : caret - caret % 8, extending: extending)
		case #selector(moveWordRight(_:)), #selector(moveWordRightAndModifySelection(_:)),
			 #selector(moveWordForward(_:)), #selector(moveWordForwardAndModifySelection(_:)):
			moveCaret(to: caret - caret % 8 + 8, extending: extending)
		case #selector(moveToBeginningOfLine(_:)), #selector(moveToBeginningOfLineAndModifySelection(_:)),
			 #selector(moveToLeftEndOfLine(_:)), #selector(moveToLeftEndOfLineAndModifySelection(_:)):
			moveCaret(to: caret - caret % bytesPerRow, extending: extending)
		case #selector(moveToEndOfLine(_:)), #selector(moveToEndOfLineAndModifySelection(_:)),
			 #selector(moveToRightEndOfLine(_:)), #selector(moveToRightEndOfLineAndModifySelection(_:)):
			moveCaret(to: caret - caret % bytesPerRow + bytesPerRow, extending: extending)
		case #selector(moveToBeginningOfDocument(_:)), #selector(moveToBeginningOfDocumentAndModifySelection(_:)):
			moveCaret(to: 0, extending: extending)
		case #selector(moveToEndOfDocument(_:)), #selector(moveToEndOfDocumentAndModifySelection(_:)):
			moveCaret(to: document.count, extending: extending)
		case #selector(pageUp(_:)), #selector(pageUpAndModifySelection(_:)), #selector(scrollPageUp(_:)):
			moveCaret(to: caret - rowsPerPage * bytesPerRow, extending: extending)
		case #selector(pageDown(_:)), #selector(pageDownAndModifySelection(_:)), #selector(scrollPageDown(_:)):
			moveCaret(to: caret + rowsPerPage * bytesPerRow, extending: extending)
		case #selector(insertTab(_:)), #selector(insertBacktab(_:)):
			// Tab is the way between the two columns without the pointer.
			activeColumn = activeColumn == .hex ? .text : .hex
			pendingNibble = nil
			needsDisplay = true
			onCaretChanged?(self)
		case #selector(deleteBackward(_:)):
			deleteBackward()
		case #selector(deleteForward(_:)):
			deleteForward()
		case #selector(cancelOperation(_:)):
			if anchor != nil { moveCaret(to: caret, extending: false) } else { pendingNibble = nil; needsDisplay = true }
		case #selector(insertNewline(_:)):
			break
		default:
			super.doCommand(by: selector)
		}
	}

	@objc override func selectAll(_ sender: Any?) {
		select(0..<document.count)
	}

	/// Where the eight-byte word under the caret begins, for the double-click
	/// and ⌥ moves, so they agree on what a word is.
	var wordStart: Int { caret - caret % 8 }
}
