import AppKit
import AbydosKit

/// Renaming a symbol in place: the field over the word, and what has to be
/// true before it opens.
extension CodeView {
	// MARK: - Renaming a symbol


	var isRenaming: Bool { rename.isOpen }

	/// The word the caret is in, as a range and as text.
	///
	/// What a rename is offered for when the server has no `prepareRename` — and
	/// what tells "the caret is in an identifier" from "the caret is on a comma"
	/// before anything is asked of anybody.
	func wordAtCaret() -> (range: Range<Int>, text: String)? {
		guard let document else { return nil }
		let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: caret))
		let lineRange = document.rope.lineByteRange(line)
		let lineStart = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let text = document.rope.string(in: lineRange) as NSString

		let column = caret - lineStart
		guard column >= 0, column <= text.length else { return nil }

		func isWord(_ unit: unichar) -> Bool {
			let scalar = Unicode.Scalar(unit)
			return scalar.map { CharacterSet.alphanumerics.contains($0) || $0 == "_" } ?? false
		}

		var start = column
		while start > 0, isWord(text.character(at: start - 1)) { start -= 1 }
		var end = column
		while end < text.length, isWord(text.character(at: end)) { end += 1 }
		guard end > start else { return nil }

		return (
			range: (lineStart + start)..<(lineStart + end),
			text: text.substring(with: NSRange(location: start, length: end - start))
		)
	}

	/// Opens the field over a range of the document.
	///
	/// Returns false when the range cannot be put on screen — a symbol inside a
	/// fold, most likely — because a field placed at a guess would be a field
	/// over the wrong word.
	@discardableResult
	func beginRename(
		utf16Range: Range<Int>, name: String, caveat: String?,
		commit: @escaping (String) -> Bool
	) -> Bool {
		guard let start = point(forUTF16: utf16Range.lowerBound),
		      let end = point(forUTF16: utf16Range.upperBound),
		      end.y == start.y
		else { return false }

		rename.onCommit = commit
		rename.onCancel = { [weak self] in self?.window?.makeFirstResponder(self) }
		rename.begin(
			over: NSRect(
				x: start.x, y: start.y,
				width: max(end.x - start.x, Theme.current.scaled(24)), height: lineHeight
			),
			in: self,
			name: name,
			font: Theme.current.editorFont,
			caveat: caveat
		)
		return true
	}

	func refuseRename(_ title: String, detail: String? = nil) { rename.refuse(title, detail: detail) }

	func endRename() { rename.end() }

	/// Types a name into the open field and presses Return, for a test with no
	/// keyboard.
	@discardableResult
	func commitRenameForTesting(_ name: String) -> Bool { rename.commitForTesting(name) }

	/// What the open field says, so a driver can show the field really opened on
	/// the symbol rather than on whatever was nearby.
	var renameTextForTesting: String? { rename.textForTesting }

	override func mouseDragged(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)

		// A marker dragged out of the gutter is thrown away, as it is in Xcode.
		// Well clear of it: a wobble while clicking is not somebody deleting a
		// breakpoint. Shown while dragging and done on release — dragging back
		// into the gutter takes it back.
		if draggingBreakpointLine != nil {
			let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0
			let wouldRemove = point.x > scrollX + gutterWidth + Theme.current.scaled(24)
			guard wouldRemove != breakpointWouldBeRemoved else { return }

			breakpointWouldBeRemoved = wouldRemove
			// The puff cursor Xcode shows: a marker that simply vanishes reads
			// as a misclick rather than as something done on purpose. This is
			// the cursor rather than the animation `NSAnimationEffect` used to
			// play, which macOS 14 deprecated in favour of exactly this.
			if wouldRemove { NSCursor.disappearingItem.set() } else { NSCursor.arrow.set() }
			return
		}

		guard point.x >= gutterWidth || caret != selectionAnchor else { return }
		setCaret(offset(at: point), extendingSelection: true)
	}

	override func mouseUp(with event: NSEvent) {
		// Where a drag out of the gutter is decided: let go beyond it and the
		// breakpoint is thrown away, let go anywhere else — including back over
		// the gutter — and it stays exactly where it was.
		if let line = draggingBreakpointLine, breakpointWouldBeRemoved {
			onDeleteBreakpoint?(line)
		}
		draggingBreakpointLine = nil

		// The puff belongs to the drag that ended. Left set, it would follow the
		// pointer around the file as though everything under it were about to be
		// thrown away too.
		if breakpointWouldBeRemoved {
			breakpointWouldBeRemoved = false
			NSCursor.arrow.set()
		}
		super.mouseUp(with: event)
	}

	func handleGutterClick(at point: NSPoint) {
		guard let document else { return }
		let visual = max(0, min(visibleLineCount - 1, Int(floor(point.y / lineHeight))))
		let docLine = min(document.lineCount - 1, documentLine(forVisualRow: visual))

		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0

		// The blame column, when it is showing, is in front of everything else
		// the gutter does — and it is for reading, not for clicking.
		if isBlameVisible, point.x < scrollX + blameWidth {
			showBlameDetail(forLine: docLine)
			return
		}

		// The leftmost strip is the breakpoint column, or the run button when
		// the line has one.
		switch gutterZone(at: point, scrollX: scrollX) {
		case .run:
			if runnableLines.contains(docLine + 1), breakpointLines[docLine] == nil {
				onRunLine?(docLine + 1)
			}

		case .number:
			// Held on an existing marker, this may become a drag out of the
			// gutter, which is how one is thrown away.
			if breakpointLines[docLine] != nil { draggingBreakpointLine = docLine }
			// Xcode's rule: clicking the number makes a breakpoint, and
			// clicking the marker that is already there turns it off rather
			// than throwing it away — deleting is dragging it out, or the menu.
			if let mark = breakpointLines[docLine] {
				onSetBreakpointEnabled?(docLine, !mark.isEnabled)
			} else {
				onToggleBreakpoint?(docLine)
			}

		case .fold:
			// Only here. The line number belongs to breakpoints now, and a
			// click that folded the code somebody was aiming a breakpoint at
			// would be maddening.
			guard folding.isFoldable(line: docLine) else { return }
			folding.toggle(line: docLine)
			updateFrameSize()
			needsDisplay = true
		}
	}

	func selectWord(at offset: Int) {
		guard let document else { return }
		let byteOffset = document.rope.byteOffset(fromUTF16: offset)
		let line = document.rope.line(atByteOffset: byteOffset)
		let lineRange = document.rope.lineByteRange(line)
		let lineStartUTF16 = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let text = document.rope.string(in: lineRange) as NSString

		var start = max(0, min(offset - lineStartUTF16, text.length))
		var end = start

		func isWordCharacter(_ index: Int) -> Bool {
			guard index >= 0 && index < text.length else { return false }
			let scalar = text.character(at: index)
			guard let unicode = Unicode.Scalar(scalar) else { return false }
			return CharacterSet.alphanumerics.contains(unicode) || scalar == UInt16(UnicodeScalar("_").value)
		}

		while isWordCharacter(start - 1) { start -= 1 }
		while isWordCharacter(end) { end += 1 }
		guard end > start else { return }

		selectionAnchor = lineStartUTF16 + start
		caret = lineStartUTF16 + end
		restartCaretBlink()
		needsDisplay = true
		reportCaretPosition()
	}

	func selectLine(at offset: Int) {
		guard let document else { return }
		let byteOffset = document.rope.byteOffset(fromUTF16: offset)
		let line = document.rope.line(atByteOffset: byteOffset)
		let range = document.rope.lineByteRange(line)
		selectionAnchor = document.rope.utf16Offset(fromByte: range.lowerBound)
		caret = document.rope.utf16Offset(fromByte: range.upperBound)
		restartCaretBlink()
		needsDisplay = true
	}
}
