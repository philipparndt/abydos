import AppKit
import AbydosKit

/// What happens under the pointer without a click: the hover card, the
/// underlined link, and the blame beside the line.
extension CodeView {
	// MARK: - Hovering

	/// The tooltip follows the pointer, so an underline can say what is wrong.
	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		for area in trackingAreas where area.owner === self {
			removeTrackingArea(area)
		}
		addTrackingArea(NSTrackingArea(
			rect: bounds,
			options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self
		))
	}

	override func mouseMoved(with event: NSEvent) {
		super.mouseMoved(with: event)
		let hoverPoint = convert(event.locationInWindow, from: nil)
		// A pointing hand over a value with something under it. Asked only while
		// a session is stopped: `openableInlineValue` is one `guard` otherwise.
		if openableInlineValue(at: hoverPoint) != nil {
			NSCursor.pointingHand.set()
		} else if isOverInlineValue {
			NSCursor.iBeam.set()
		}
		isOverInlineValue = openableInlineValue(at: hoverPoint) != nil
		updateNavigableWord(
			at: hoverPoint,
			commandHeld: event.modifierFlags.contains(.command)
		)
		updateBlameHover(at: hoverPoint)

		guard hasDiagnostics, let document else {
			if toolTip != nil { toolTip = nil }
			return
		}

		let point = convert(event.locationInWindow, from: nil)
		guard point.x > gutterWidth else {
			toolTip = nil
			return
		}

		let offset = self.offset(at: point)
		let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: offset))
		let lineStart = document.rope.utf16Offset(fromByte: document.rope.byteOffset(ofLine: line))
		let column = offset - lineStart

		// The worst problem covering the pointer, since a place with an error
		// and a hint on it is somewhere the error is what matters.
		let covering = diagnostics(onLine: line).first { diagnostic in
			let start = diagnostic.range.start.character
			let end = diagnostic.range.end.line > line
				? Int.max
				: max(diagnostic.range.end.character, start + 1)
			return column >= start && column <= end
		}

		let text = covering.map { diagnostic -> String in
			guard let source = diagnostic.source else { return diagnostic.message }
			return "\(diagnostic.message)  (\(source))"
		}
		if text != toolTip { toolTip = text }
	}

	override func mouseExited(with event: NSEvent) {
		super.mouseExited(with: event)
		toolTip = nil
		updateNavigableWord(at: nil, commandHeld: false)
		updateBlameHover(at: nil)
	}

	/// Where the matches on one line fall, split by the depth each is painted at.
	///
	/// Measured here and painted by the caller, because the current match and the
	/// rest do not go on at the same moment: the others belong under the
	/// selection and the current one over it. Measured *once* for both, since the
	/// CTLine this asks for offsets from is not free and a row is redrawn on
	/// every caret blink.
	func searchHighlights(
		docLine: Int, segment: Int, rect: NSRect
	) -> (others: [NSRect], current: NSRect?, occurrences: [NSRect]) {
		guard let document, !searchMatches.isEmpty || !selectionOccurrences.isEmpty else {
			return ([], nil, [])
		}

		let lineRange = document.rope.lineByteRange(docLine)
		let lineStart = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let lineEnd = document.rope.utf16Offset(fromByte: lineRange.upperBound)
		let text = document.rope.string(in: lineRange)

		// **Measured along the row being painted, not along the whole line.**
		// This is 0540: the `CTLine` was built for the document line while
		// `rect` was one visual row of it, so every match past the first row was
		// placed at the x it would have had unwrapped. The caret's answer —
		// `point(forUTF16:)` — has always sliced the line into segments first,
		// and the two disagreeing is the fault. They now ask `WrapLayout` the
		// same question with the same arguments.
		var rowRangeInLine = 0..<(text as NSString).length
		var rowText = text
		if isWordWrapEnabled, let columns = wrapColumns {
			rowRangeInLine = WrapLayout.segmentRange(
				in: text, segment: segment, columns: columns, tabWidth: Theme.current.tabWidth
			)
			rowText = (text as NSString).substring(
				with: NSRange(location: rowRangeInLine.lowerBound, length: rowRangeInLine.count)
			)
		}

		let ctLine = CTLineCreateWithAttributedString(attributedLine(
			text: rowText,
			lineStartUTF16: lineStart + rowRangeInLine.lowerBound,
			tokenIndex: TokenIndex(tokens: [])
		))

		/// One range placed on this row, or nil when none of it falls here.
		///
		/// The two lists are asked the same question and the CTLine is built
		/// once for both: it is not free, and a row is redrawn on every caret
		/// blink.
		func band(for range: Range<Int>) -> NSRect? {
			guard let band = WrapLayout.bandRange(
				for: range, lineStart: lineStart, segment: rowRangeInLine
			) else { return nil }

			let startX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, band.lowerBound, nil)
			let endX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, band.upperBound, nil)
			return NSRect(
				x: startX,
				y: rect.minY,
				width: max(2, endX - startX),
				height: rect.height
			)
		}

		var occurrences: [NSRect] = []
		for range in selectionOccurrences {
			// Ordered, so the row can be left as soon as one starts past it.
			guard range.lowerBound <= lineEnd else { break }
			guard range.upperBound >= lineStart else { continue }
			if let rect = band(for: range) { occurrences.append(rect) }
		}

		var others: [NSRect] = []
		var current: NSRect?

		for (index, match) in searchMatches.enumerated() {
			// Matches are ordered, so stop once past this line.
			guard match.utf16Range.lowerBound <= lineEnd else { break }
			guard match.utf16Range.upperBound >= lineStart else { continue }

			// What of it falls on *this* row, in the row's own offsets. A match
			// crossing a wrap boundary is asked once per row and answers a piece
			// each time, which is the shape the old code could not express: it
			// returned one rectangle per match and had nowhere to put the rest.
			guard let rect = band(for: match.utf16Range) else { continue }

			if index == currentMatchIndex {
				current = rect
			} else {
				others.append(rect)
			}
		}
		return (others, current, occurrences)
	}

	func attributedLine(
		text: String,
		lineStartUTF16: Int,
		tokenIndex: TokenIndex
	) -> NSAttributedString {
		let paragraph = NSMutableParagraphStyle()
		// Explicit tab stops: CoreText otherwise collapses tabs to a default
		// width that does not match the gutter-relative grid.
		let tabColumns = CGFloat(Theme.current.tabWidth)
		paragraph.tabStops = (1...64).map {
			NSTextTab(textAlignment: .left, location: CGFloat($0) * charWidth * tabColumns, options: [:])
		}
		paragraph.defaultTabInterval = charWidth * tabColumns

		let attributed = NSMutableAttributedString(string: text, attributes: [
			.font: font,
			.foregroundColor: Theme.current.editorText,
			.paragraphStyle: paragraph,
		])

		let length = attributed.length
		guard length > 0 else { return attributed }

		for token in tokenIndex.tokens(overlapping: lineStartUTF16..<(lineStartUTF16 + length)) {
			let localStart = max(0, token.range.lowerBound - lineStartUTF16)
			let localEnd = min(length, token.range.upperBound - lineStartUTF16)
			guard localStart < localEnd else { continue }
			attributed.addAttribute(
				.foregroundColor,
				value: Theme.current.color(for: token.kind),
				range: NSRange(location: localStart, length: localEnd - localStart)
			)
		}
		return attributed
	}

	func drawSelection(
		ctLine: CTLine,
		lineStartUTF16: Int,
		lineEndUTF16: Int,
		selection: Range<Int>,
		rect: NSRect
	) {
		let from = max(selection.lowerBound, lineStartUTF16) - lineStartUTF16
		let to = min(selection.upperBound, lineEndUTF16) - lineStartUTF16
		guard to >= from else { return }

		let startX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, from, nil)
		var endX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, to, nil)

		// A selection spanning the newline should show the line break as a sliver
		// of highlight rather than nothing at all.
		if selection.upperBound > lineEndUTF16 {
			endX += charWidth * 0.6
		}

		// Gray while the keyboard is somewhere else — the terminal below, a
		// results list, another pane of a split. A selection drawn in the strong
		// highlight is a claim that the next key will act on it, and this view
		// used to make that claim whether or not it was true.
		Theme.current.selection(.text, hasKeyboard: hasKeyboard).setFill()
		NSRect(x: startX, y: rect.minY, width: max(1, endX - startX), height: rect.height).fill()
	}

	/// True when this view is the one keys are going to.
	///
	/// Asked of the window on each draw rather than kept, so it cannot go stale:
	/// AppKit posts nothing when the first responder changes, and a flag would
	/// need every route out of this view to remember to clear it.
	var hasKeyboard: Bool { window?.firstResponder === self }

	func drawFoldPlaceholder(at origin: NSPoint, hiddenLines: Int) {
		let label = hiddenLines > 0 ? "⋯ \(hiddenLines) lines" : "⋯"
		let attributed = NSAttributedString(string: label, attributes: [
			.font: NSFont.monospacedSystemFont(ofSize: Theme.current.fontSize - 1, weight: .regular),
			.foregroundColor: Theme.current.foldPlaceholderText,
		])
		let size = attributed.size()
		let box = NSRect(x: origin.x, y: origin.y + 2, width: size.width + 10, height: lineHeight - 4)

		let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
		Theme.current.foldPlaceholderBackground.setFill()
		path.fill()

		attributed.draw(at: NSPoint(x: box.minX + 5, y: box.midY - size.height / 2))
	}

	// MARK: - Blame

	/// Shows or hides the blame column. The caller does the asking of git.
	func setBlameVisible(_ visible: Bool) {
		guard visible != isBlameVisible else { return }
		isBlameVisible = visible
		if !visible {
			blame = []
			updateBlameHover(at: nil)
		}
		updateFrameSize()
		needsDisplay = true
	}

	func setBlame(_ lines: [GitBlame.Line]) {
		blame = lines
		needsDisplay = true
	}

	/// What the blame column says for a line, or nil when it should stay blank.
	///
	/// Blank for every line of a commit after its first: a run of forty lines
	/// from one commit says the same thing forty times otherwise, and the eye
	/// has to work out that they are one change rather than seeing it.
	private func blameLabel(forLine line: Int) -> String? {
		guard blame.indices.contains(line) else { return nil }
		if line > 0, blame.indices.contains(line - 1), blame[line - 1].commit == blame[line].commit {
			return nil
		}
		return blame[line].label(width: Self.blameColumns)
	}

	func drawBlame(rows: Range<Int>, scrollX: CGFloat) {
		guard isBlameVisible, !blame.isEmpty else { return }

		let width = blameWidth
		drawBlameHover(rows: rows, scrollX: scrollX, width: width)
		for visual in rows {
			let docLine = documentLine(forVisualRow: visual)
			guard docLine < blame.count else { break }
			guard wrapSegment(forVisualRow: visual) == 0 else { continue }
			let y = yPosition(forVisualLine: visual)

			// A line still being written stands out, since it is the one thing
			// in the column that is nobody's yet.
			let entry = blame[docLine]
			guard let label = blameLabel(forLine: docLine) else { continue }

			let text = NSAttributedString(string: label, attributes: [
				.font: font,
				.foregroundColor: entry.isUncommitted
					? Theme.current.gitModified
					: Theme.current.gutterText,
			])
			text.draw(in: NSRect(
				x: scrollX + Self.gutterPadding / 2,
				y: y + (lineHeight - text.size().height) / 2,
				width: width - Self.gutterPadding,
				height: text.size().height
			))
		}

		// A hairline between the column and the gutter, so the two do not read
		// as one wide margin of numbers and names.
		Theme.current.gutterText.withAlphaComponent(0.25).setFill()
		NSRect(
			x: scrollX + width - 1,
			y: CGFloat(rows.lowerBound) * lineHeight,
			width: 1,
			height: CGFloat(rows.count) * lineHeight
		).fill()
	}

	/// The lit run under the pointer: one rounded fill over every row of the
	/// commit's contiguous lines, so what will be clicked is what is lit.
	private func drawBlameHover(rows: Range<Int>, scrollX: CGFloat, width: CGFloat) {
		guard let hovered = hoveredBlameLine, let run = blameRun(containing: hovered) else { return }
		var top: CGFloat?, bottom: CGFloat?
		for visual in rows {
			let docLine = documentLine(forVisualRow: visual)
			guard docLine < blame.count else { break }
			guard run.contains(docLine) else { continue }
			let y = yPosition(forVisualLine: visual)
			top = min(top ?? y, y)
			bottom = max(bottom ?? y + lineHeight, y + lineHeight)
		}
		guard let top, let bottom else { return }
		Theme.current.gutterText.withAlphaComponent(0.14).setFill()
		NSBezierPath(
			roundedRect: NSRect(x: scrollX + 2, y: top + 1, width: width - 5, height: bottom - top - 2),
			xRadius: 4, yRadius: 4
		).fill()
	}

	/// The contiguous lines sharing a line's commit — what one label stands
	/// for, and what a click on any of them goes to.
	private func blameRun(containing line: Int) -> ClosedRange<Int>? {
		guard blame.indices.contains(line) else { return nil }
		let commit = blame[line].commit
		var first = line, last = line
		while first > 0, blame[first - 1].commit == commit { first -= 1 }
		while last + 1 < blame.count, blame[last + 1].commit == commit { last += 1 }
		return first...last
	}

	/// The pointer over the column, or not: the run under it lights, the
	/// pointing hand says it can be clicked, and after a rest the tip says
	/// where the click goes — the log page is a bigger thing than a click on
	/// a gutter usually does, so it is announced before it happens.
	private func updateBlameHover(at point: NSPoint?) {
		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0
		var line: Int?
		if let point, isBlameVisible, let document, point.x < scrollX + blameWidth {
			let visual = max(0, min(visibleLineCount - 1, Int(floor(point.y / lineHeight))))
			let docLine = min(document.lineCount - 1, documentLine(forVisualRow: visual))
			if blame.indices.contains(docLine) { line = docLine }
		}
		guard line != hoveredBlameLine else { return }
		hoveredBlameLine = line
		needsDisplay = true
		guard let line, let tip = blameTip(forLine: line) else {
			StyledTip.shared.hide()
			if !isOverInlineValue { NSCursor.iBeam.set() }
			return
		}
		NSCursor.pointingHand.set()
		let visual = firstVisualRow(forDocumentLine: line)
		let row = NSRect(x: scrollX, y: yPosition(forVisualLine: visual), width: blameWidth, height: lineHeight)
		StyledTip.shared.show(tip, from: row, of: self)
	}

	/// What resting on an entry says: the commit, and that a click goes to it.
	func blameTip(forLine line: Int) -> StyledTip.Tip? {
		guard let entry = blameEntry(forLine: line) else { return nil }
		if entry.isUncommitted {
			return StyledTip.Tip(title: "Not committed yet", detail: "This line has no commit to go to.")
		}
		let when = DateFormatter.localizedString(from: entry.date, dateStyle: .medium, timeStyle: .short)
		return StyledTip.Tip(
			title: entry.summary.isEmpty ? entry.shortCommit : entry.summary,
			detail: "\(entry.author) · \(when) · \(entry.shortCommit). "
				+ "Click to open the commit in the log, scoped to this file."
		)
	}

	/// The pointer put on a line's entry, and what that lit and said.
	func hoverBlameForTesting(line: Int) -> String {
		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0
		let visual = firstVisualRow(forDocumentLine: line)
		updateBlameHover(at: NSPoint(x: scrollX + 4, y: yPosition(forVisualLine: visual) + lineHeight / 2))
		guard let hovered = hoveredBlameLine, let run = blameRun(containing: hovered) else { return "nothing lit" }
		let tip = blameTip(forLine: hovered)?.reportForTesting ?? "no tip"
		return "lit \(run.lowerBound + 1)–\(run.upperBound + 1) · \(tip)"
	}

	/// Every line's entry, for a driven run to read the authors off.
	var blameEntriesForTesting: [GitBlame.Line] { blame }

	/// The commit on a line, for the menu and the tooltip.
	func blameEntry(forLine line: Int) -> GitBlame.Line? {
		blame.indices.contains(line) ? blame[line] : nil
	}


	func showBlameDetail(forLine line: Int) {
		guard let entry = blameEntry(forLine: line) else { return }
		onShowBlameDetail?(entry)
	}
}
