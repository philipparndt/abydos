import AppKit
import AbydosKit

/// How the compare view is drawn: only the rows in view, each half of each,
/// the marks and the selection behind the glyphs, and the curves between the
/// halves for the changes whose rows are on screen.
///
/// A file of its own for the reason `DiffView+Drawing` is one: the view is the
/// rows and the selection, and this reads them and paints.
extension FileCompareView {
	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.intersection(bounds).fill()
		guard !shown.isEmpty else { return }

		// The gutter's two edges, so the halves read as two documents.
		Theme.current.gitIgnored.withAlphaComponent(0.25).setFill()
		NSRect(x: halfWidth, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
		NSRect(x: halfWidth + gutterWidth - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()

		let first = rowIndex(atY: dirtyRect.minY) ?? 0
		let last = rowIndex(atY: dirtyRect.maxY) ?? (shown.count - 1)
		guard last >= first else { return }
		for index in first...last { draw(rowAt: index) }
		drawCurves(visibleRows: first...last)
	}

	private func draw(rowAt index: Int) {
		let y = top(ofRow: index)
		let height = height(ofRow: index)
		switch shown[index] {
		case .fold(let rows):
			drawFold(count: rows.count, y: y, height: height)
		case .row(let rowIndex):
			let row = diff.rows[rowIndex]
			drawHalf(.left, row: row, shownIndex: index, y: y, height: height)
			drawHalf(.right, row: row, shownIndex: index, y: y, height: height)
		}
	}

	/// A run of equal lines folded away: one row saying how many, on both
	/// halves, drawn as a band rather than as a line of either file.
	private func drawFold(count: Int, y: CGFloat, height: CGFloat) {
		Theme.current.gitIgnored.withAlphaComponent(0.08).setFill()
		NSRect(x: 0, y: y, width: bounds.width, height: height).fill()
		let text = "\(count) Unchanged Line\(count == 1 ? "" : "s")" as NSString
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: Theme.current.gitIgnored,
		]
		let width = text.size(withAttributes: attributes).width
		for column in [DiffTextRun.Column.left, .right] {
			let x = halfMinX(column) + (halfWidth - width) / 2
			text.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
		}
	}

	private func drawHalf(_ column: DiffTextRun.Column, row: TextDiff.Row, shownIndex: Int, y: CGFloat, height: CGFloat) {
		let rect = NSRect(x: halfMinX(column), y: y, width: halfWidth, height: height)
		let line = column == .left ? row.left : row.right
		if let background = background(for: row.kind, in: column, present: line != nil) {
			background.setFill()
			rect.fill()
		}
		guard let line else { return }

		// The number, right-aligned in its column and dimmer than the code.
		let number = "\(line + 1)" as NSString
		let numberWidth = number.size(withAttributes: [.font: font]).width
		number.draw(
			at: NSPoint(x: rect.minX + Self.horizontalInset + self.numberWidth - numberWidth, y: y),
			withAttributes: [.font: font, .foregroundColor: Theme.current.gitIgnored.withAlphaComponent(0.7)]
		)

		let text = column == .left ? diff.leftLines[line] : diff.rightLines[line]
		guard !text.isEmpty else {
			// An empty line can still be selected through, and the sliver
			// for the line break is what shows that.
			drawSelectionSliver(shownIndex: shownIndex, in: column, y: y)
			return
		}
		let tokens = (column == .left ? leftTokens : rightTokens)[line] ?? []
		let marks = (column == .left ? row.leftMarks : row.rightMarks) ?? []
		NSGraphicsContext.saveGraphicsState()
		NSRect(x: textOrigin(in: column), y: y, width: max(0, rect.maxX - textOrigin(in: column)), height: height).clip()
		drawText(text, tokens: tokens, marks: marks, kind: row.kind, shownIndex: shownIndex, in: column, y: y)
		NSGraphicsContext.restoreGraphicsState()
	}

	/// The text of one half, one visual row at a time: the selection behind
	/// it, the marks behind that, and the glyphs in the language's colours.
	private func drawText(
		_ text: String, tokens: [HighlightToken], marks: [Range<Int>], kind: TextDiff.Kind,
		shownIndex: Int, in column: DiffTextRun.Column, y: CGFloat
	) {
		let attributed = NSMutableAttributedString(string: text, attributes: [
			.font: font,
			.foregroundColor: Theme.current.sidebarText,
		])
		for token in tokens {
			let lower = max(0, token.range.lowerBound)
			let upper = min(attributed.length, token.range.upperBound)
			guard upper > lower else { continue }
			attributed.addAttribute(
				.foregroundColor, value: Theme.current.color(for: token.kind),
				range: NSRange(location: lower, length: upper - lower)
			)
		}
		let origin = textOrigin(in: column)
		let covered = textRun.column == column ? textRun.covered(row: shownIndex) : nil
		let markColour = markColour(for: kind, in: column)

		for (visualRow, segment) in segments(ofRow: shownIndex, in: column).enumerated() {
			let rowY = y + CGFloat(visualRow) * lineHeight
			let piece = attributed.attributedSubstring(from: NSRange(location: segment.lowerBound, length: segment.count))
			let measured = CTLineCreateWithAttributedString(piece)
			func x(_ offset: Int) -> CGFloat {
				origin + CTLineGetOffsetForStringIndex(measured, offset - segment.lowerBound, nil)
			}

			if let covered, let band = WrapLayout.bandRange(for: covered, lineStart: 0, segment: segment) {
				var endX = x(band.upperBound + segment.lowerBound)
				// A row the selection runs through gets a sliver past its last
				// character for the line break, the way the editor draws it.
				if shownIndex < textRun.end.row, segment.upperBound == text.utf16.count { endX += characterWidth * 0.6 }
				let startX = x(band.lowerBound + segment.lowerBound)
				if endX - startX > 0.5 {
					Theme.current.selection(.text, hasKeyboard: keyboardIsHere).setFill()
					NSRect(x: startX, y: rowY, width: endX - startX, height: lineHeight).fill()
				}
			}
			for mark in marks {
				guard let band = WrapLayout.bandRange(for: mark, lineStart: 0, segment: segment) else { continue }
				let startX = x(band.lowerBound + segment.lowerBound)
				let endX = x(band.upperBound + segment.lowerBound)
				guard endX - startX > 0.5 else { continue }
				markColour.setFill()
				NSRect(x: startX, y: rowY + 1, width: endX - startX, height: lineHeight - 2).fill()
			}
			piece.draw(at: NSPoint(x: origin, y: rowY))
		}
	}

	private func drawSelectionSliver(shownIndex: Int, in column: DiffTextRun.Column, y: CGFloat) {
		guard textRun.column == column, textRun.covered(row: shownIndex) != nil, shownIndex < textRun.end.row else { return }
		Theme.current.selection(.text, hasKeyboard: keyboardIsHere).setFill()
		NSRect(x: textOrigin(in: column), y: y, width: characterWidth * 0.6, height: lineHeight).fill()
	}

	private func background(for kind: TextDiff.Kind, in column: DiffTextRun.Column, present: Bool) -> NSColor? {
		// Nothing on this side of the row: a shade rather than the editor's
		// background, so a deletion with no replacement reads as an absence
		// rather than as a blank line of the file.
		guard present else { return Theme.current.gitIgnored.withAlphaComponent(0.06) }
		switch kind {
		case .equal: return nil
		case .changed: return Theme.current.gitModified.withAlphaComponent(0.10)
		case .leftOnly: return Theme.current.gitUnversioned.withAlphaComponent(0.13)
		case .rightOnly: return Theme.current.gitAdded.withAlphaComponent(0.13)
		}
	}

	private func markColour(for kind: TextDiff.Kind, in column: DiffTextRun.Column) -> NSColor {
		// What was taken out is marked in the removal's colour on the left
		// and what came in is marked in the addition's on the right, so the
		// comma reads as a comma added rather than as a pair of stains.
		(column == .left ? Theme.current.gitUnversioned : Theme.current.gitAdded).withAlphaComponent(0.35)
	}

	// MARK: - The curves

	/// The rows a change occupies on each side. Within a change the pairs come
	/// first and then the extras of one side, so each side's lines are a
	/// contiguous run from the change's first row — which is what lets a
	/// removal with a shorter replacement be drawn gapless on both halves and
	/// joined by one shape.
	private func extents(of change: TextDiff.Change) -> (start: Int, left: Int, right: Int)? {
		guard let start = shownIndex(ofDiffRow: change.rows.lowerBound) else { return nil }
		return (start, change.leftLines.count, change.rightLines.count)
	}

	private func drawCurves(visibleRows: ClosedRange<Int>) {
		let gutterLeft = halfWidth
		let gutterRight = halfWidth + gutterWidth
		for (index, change) in diff.changes.enumerated() {
			guard let (start, left, right) = extents(of: change) else { continue }
			let rowsSpanned = max(left, right, 1)
			guard start <= visibleRows.upperBound, start + rowsSpanned - 1 >= visibleRows.lowerBound else { continue }

			let topY = top(ofRow: start)
			func bottom(after lines: Int) -> CGFloat {
				lines == 0 ? topY : top(ofRow: start + lines - 1) + height(ofRow: start + lines - 1)
			}
			let leftBottom = bottom(after: left)
			let rightBottom = bottom(after: right)

			// A straight edge along the top and a curve along the bottom, from
			// where the change ends on the right to where it ends on the left:
			// the shape pinches to a point on a side the change touches nothing
			// of, which is how a pure removal reads as "went to here".
			let path = NSBezierPath()
			path.move(to: NSPoint(x: gutterLeft, y: topY))
			path.line(to: NSPoint(x: gutterRight, y: topY))
			path.line(to: NSPoint(x: gutterRight, y: rightBottom))
			let middle = (gutterLeft + gutterRight) / 2
			path.curve(
				to: NSPoint(x: gutterLeft, y: leftBottom),
				controlPoint1: NSPoint(x: middle, y: rightBottom),
				controlPoint2: NSPoint(x: middle, y: leftBottom)
			)
			path.close()

			let colour = curveColour(for: change.kind)
			let isCurrent = index == currentChange
			colour.withAlphaComponent(isCurrent ? 0.32 : 0.16).setFill()
			path.fill()
			colour.withAlphaComponent(isCurrent ? 0.9 : 0.45).setStroke()
			path.lineWidth = isCurrent ? 1.5 : 1
			path.stroke()
		}
	}

	private func curveColour(for kind: TextDiff.Change.Kind) -> NSColor {
		switch kind {
		case .added: return Theme.current.gitAdded
		case .removed: return Theme.current.gitUnversioned
		case .changed: return Theme.current.gitModified
		}
	}
}
