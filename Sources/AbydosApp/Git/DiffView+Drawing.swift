import AppKit
import AbydosKit

/// How a diff is drawn: only the rows in view, one at a time, and the text
/// selection behind the glyphs of each.
///
/// **A file of its own so that `DiffView.swift` is the view and its two
/// selections rather than a painter as well** — the arrangement the window
/// controller's own layout and driving files already have. Nothing here decides
/// anything: it reads the rows, the font, the two selections and `DiffTextRun`,
/// and draws what they already say.
extension DiffView {

	override var intrinsicContentSize: NSSize {
		NSSize(
			width: NSView.noIntrinsicMetric,
			height: max(CGFloat(rows.count) * lineHeight + Theme.current.scaled(16), 10)
		)
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.fill()

		let top = Theme.current.scaled(8)
		// Only the rows in view are laid out, which is what keeps a huge diff
		// as cheap to scroll as a small one.
		let first = max(0, Int((dirtyRect.minY - top) / lineHeight))
		let last = min(rows.count, Int((dirtyRect.maxY - top) / lineHeight) + 1)
		guard last > first else { return }

		for position in first..<last {
			draw(rowAt: position, at: top + CGFloat(position) * lineHeight)
		}
	}

	/// One row, and the selection behind its glyphs.
	///
	/// Takes the row's index rather than the row, because everything about a
	/// selection is said in terms of it: which row is covered, how far into its
	/// text, and where that text is drawn from.
	private func draw(rowAt index: Int, at y: CGFloat) {
		switch rows[index] {
		case .header(let text):
			guard !text.isEmpty else { return }
			highlight(rowAt: index, in: .only, at: y)
			text.draw(at: NSPoint(x: textX, y: y), font: font, color: Theme.current.gitIgnored)

		case let .comment(comment, text, isFirst):
			// A tint of its own down the whole row, so a conversation reads as
			// something other than code at a glance.
			Theme.current.gitModified.withAlphaComponent(comment.isOutdated ? 0.05 : 0.10).setFill()
			NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()

			if selectedComment?.comment == comment {
				Theme.current.gitModified.withAlphaComponent(0.20).setFill()
				NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
				Theme.current.gitModified.setFill()
				NSRect(x: 0, y: y, width: Theme.current.scaled(3), height: lineHeight).fill()
			}
			highlight(rowAt: index, in: .only, at: y)
			let colour = comment.isOutdated
				? Theme.current.gitIgnored
				: (isFirst ? Theme.current.gitModified : Theme.current.sidebarText)
			// ✍️ for one being written here, 💬 for one that has been said.
			let marked = isFirst ? (comment.isPending ? "✍️ " : "💬 ") + text : "   " + text
			marked.draw(
				at: NSPoint(x: textX, y: y),
				font: isFirst ? boldFont : font,
				color: colour
			)

		case .scope(let text):
			// A rule with the declaration on it, rather than four lines of
			// preamble: the one thing git's `@@` line says that the pane around
			// it does not.
			Theme.current.gitIgnored.withAlphaComponent(0.12).setFill()
			NSRect(
				x: 0, y: y + lineHeight / 2, width: bounds.width, height: max(1, lineHeight * 0.06)
			).fill()
			guard !text.isEmpty else { return }
			let attributes: [NSAttributedString.Key: Any] = [
				.font: font,
				.foregroundColor: Theme.current.gitIgnored,
			]
			let measured = (text as NSString).size(withAttributes: attributes)
			// Sitting on the rule with the background cut out behind it, so it
			// reads as a label on a separator and not as a line of the file.
			let inset = Theme.current.scaled(6)
			Theme.current.editorBackground.setFill()
			NSRect(
				x: textX - inset, y: y, width: measured.width + inset * 2, height: lineHeight
			).fill()
			highlight(rowAt: index, in: .only, at: y)
			text.draw(at: NSPoint(x: textX, y: y), font: font, color: Theme.current.gitIgnored)

		case let .pair(left, right):
			drawPair(rowAt: index, left: left, right: right, at: y)

		case .hunkHeader(_, let text):
			NSColor.white.withAlphaComponent(0.05).setFill()
			NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
			highlight(rowAt: index, in: .only, at: y)
			text.draw(at: NSPoint(x: textX, y: y), font: boldFont, color: Theme.current.gitModified)

		case .line(let lineIndex, let line, let old, let new):
			let isSelected = selection.contains(lineIndex)

			if let background = background(for: line.kind) {
				background.setFill()
				NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
			}

			if isSelected {
				// A tint over the whole row plus a bar in the gutter: the tint
				// alone is hard to see against a row that already has one.
				Theme.current.gitModified.withAlphaComponent(0.20).setFill()
				NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
				Theme.current.gitModified.setFill()
				NSRect(x: 0, y: y, width: Theme.current.scaled(3), height: lineHeight).fill()
			}

			// The two numbers, right-aligned in their own columns and dimmer
			// than the code: they are there to be read off when you want one,
			// not to be read past on every line. **And they are where a whole
			// line is selected**, which is what a press on them does.
			let numbers = Theme.current.gitIgnored.withAlphaComponent(0.7)
			let numberFont = font
			func column(_ value: Int?, at x: CGFloat) {
				guard let value else { return }
				let text = "\(value)" as NSString
				let width = text.size(withAttributes: [.font: numberFont]).width
				text.draw(
					at: NSPoint(x: x + numberWidth - width - Theme.current.scaled(4), y: y),
					withAttributes: [.font: numberFont, .foregroundColor: numbers]
				)
			}
			let numbersX = Self.horizontalInset + Self.gutterWidth
			column(old, at: numbersX)
			column(new, at: numbersX + numberWidth)

			guard !line.marker.isEmpty || !line.text.isEmpty else { return }

			highlight(rowAt: index, in: .only, at: y)

			// The marker keeps the diff's own colour — it is what the line does,
			// not what it says — and the text is coloured as code. Which side a
			// line is on is carried by the tint behind it, the way it is in a
			// review: reading a diff is reading code, and code that is all one
			// colour is the thing syntax highlighting exists to fix.
			line.marker.draw(at: NSPoint(x: textX, y: y), font: font, color: color(for: line.kind))
			drawText(line, index: lineIndex, at: NSPoint(x: textOrigin(ofRow: index), y: y))
		}
	}

	/// The text selection, behind the glyphs of one row.
	///
	/// **It ends where the covered text ends, not at the edge of the view.** A
	/// highlight run to the margin makes a solid block with the text somewhere
	/// inside it, so what is selected has to be worked out rather than seen. A
	/// row the selection runs *through* gets a sliver past its last character
	/// for the line break, the way the editor draws the same thing.
	///
	/// Grey while the keyboard is somewhere else: a selection in the strong
	/// colour is a claim that the next key will act on it.
	private func highlight(rowAt index: Int, in column: Column, at y: CGFloat) {
		guard textRun.column == column, let covered = textRun.covered(row: index) else { return }

		let startX = textRun.x(ofOffset: covered.lowerBound, row: index, in: column)
		var endX = textRun.x(ofOffset: covered.upperBound, row: index, in: column)
		// A row the selection runs *through* gets a sliver past its last
		// character for the line break, the way the editor draws the same
		// thing.
		if index < textRun.end.row { endX += characterWidth * 0.6 }
		guard endX - startX > 0.5 else { return }

		Theme.current.selection(.text, hasKeyboard: hasKeyboard).setFill()
		NSRect(x: startX, y: y, width: endX - startX, height: lineHeight).fill()
	}

	/// Draws one row of a side-by-side diff: the old file on the left, the new
	/// on the right, and a rule between them.
	///
	/// Each half is clipped to its own column, so a long line runs to the middle
	/// and stops rather than across the other side of the file.
	private func drawPair(rowAt index: Int, left: Side?, right: Side?, at y: CGFloat) {
		let middle = pairMiddle

		func half(_ side: Side?, in column: NSRect, at which: Column) {
			if let side, let background = background(for: side.line.kind) {
				background.setFill()
				column.fill()
			} else if side == nil {
				// Nothing on this side of the row: a shade rather than the
				// editor's background, so a deletion with no replacement reads
				// as an absence rather than as a blank line of the file.
				Theme.current.gitIgnored.withAlphaComponent(0.06).setFill()
				column.fill()
			}
			guard let side else { return }

			if selection.contains(side.index) {
				Theme.current.gitModified.withAlphaComponent(0.20).setFill()
				column.fill()
				Theme.current.gitModified.setFill()
				NSRect(
					x: column.minX, y: y, width: Theme.current.scaled(3), height: lineHeight
				).fill()
			}

			let numbers = Theme.current.gitIgnored.withAlphaComponent(0.7)
			let number = "\(side.number)" as NSString
			let width = number.size(withAttributes: [.font: font]).width
			let numberX = column.minX + Self.gutterWidth + numberWidth - width - Theme.current.scaled(4)
			number.draw(
				at: NSPoint(x: numberX, y: y),
				withAttributes: [.font: font, .foregroundColor: numbers]
			)

			let start = textOrigin(ofRow: index, in: which)
			NSGraphicsContext.saveGraphicsState()
			NSRect(
				x: start, y: y, width: max(0, column.maxX - start), height: lineHeight
			).clip()
			highlight(rowAt: index, in: which, at: y)
			// The marker is dropped: which side a line is on is what the column
			// says, and a `+` down the left of every line of the right-hand file
			// is a column of punctuation.
			drawText(side.line, index: side.index, at: NSPoint(x: start, y: y))
			NSGraphicsContext.restoreGraphicsState()
		}

		half(left, in: NSRect(x: 0, y: y, width: middle - 1, height: lineHeight), at: .left)
		half(
			right,
			in: NSRect(x: middle + 1, y: y, width: bounds.width - middle - 1, height: lineHeight),
			at: .right
		)

		Theme.current.gitIgnored.withAlphaComponent(0.25).setFill()
		NSRect(x: middle, y: y, width: 1, height: lineHeight).fill()
	}

	/// Draws a line's text, in syntax colours where there are any.
	private func drawText(_ line: GitPatch.Line, index: Int, at origin: NSPoint) {
		guard !line.text.isEmpty else { return }
		let fallback = color(for: line.kind)

		guard let tokens = highlights[index], !tokens.isEmpty else {
			line.text.draw(at: origin, font: font, color: fallback)
			return
		}

		let attributed = NSMutableAttributedString(string: line.text, attributes: [
			.font: font,
			.foregroundColor: fallback,
		])
		for token in tokens {
			let lower = max(0, token.range.lowerBound)
			let upper = min(attributed.length, token.range.upperBound)
			guard upper > lower else { continue }
			attributed.addAttribute(
				.foregroundColor,
				value: Theme.current.color(for: token.kind),
				range: NSRange(location: lower, length: upper - lower)
			)
		}
		attributed.draw(at: origin)
	}

	private func background(for kind: GitPatch.Line.Kind) -> NSColor? {
		switch kind {
		case .added:   return Theme.current.gitAdded.withAlphaComponent(0.13)
		case .removed: return Theme.current.gitUnversioned.withAlphaComponent(0.13)
		default:       return nil
		}
	}

	private func color(for kind: GitPatch.Line.Kind) -> NSColor {
		switch kind {
		case .added:     return Theme.current.gitAdded
		case .removed:   return Theme.current.gitUnversioned
		case .noNewline: return Theme.current.gitIgnored
		case .context:   return Theme.current.sidebarText
		}
	}
}

private extension String {
	func draw(at point: NSPoint, font: NSFont, color: NSColor) {
		NSAttributedString(string: self, attributes: [
			.font: font,
			.foregroundColor: color,
		]).draw(at: point)
	}
}
