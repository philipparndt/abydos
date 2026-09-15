import AppKit
import AbydosKit

/// The gutter and the caret: the numbers down the side, the breakpoints and
/// folds in it, and where the caret is and what it does when it gets there.
extension CodeView {
	// MARK: - Gutter

	func drawGutter(rows: Range<Int>, caretLine: Int, scrollX: CGFloat, context: CGContext) {
		guard let document else { return }

		// Opaque so text scrolling underneath is hidden rather than showing through.
		Theme.current.editorBackground.setFill()
		NSRect(x: scrollX,
		       y: CGFloat(rows.lowerBound) * lineHeight,
		       width: gutterWidth,
		       height: CGFloat(rows.count) * lineHeight).fill()

		drawBlame(rows: rows, scrollX: scrollX)

		let scale = Theme.current.scale, markX = scrollX + GutterMetrics.markX(
			gutterWidth: gutterWidth, foldColumnWidth: Self.foldColumnWidth, scale: scale)
		for visual in rows {
			let docLine = documentLine(forVisualRow: visual)
			guard docLine < document.lineCount else { break }
			// Continuation rows leave the gutter blank, as every editor does.
			guard wrapSegment(forVisualRow: visual) == 0 else { continue }
			let y = yPosition(forVisualLine: visual)

			let isCurrent = docLine == caretLine
			// A run marker takes the breakpoint column when the line has one:
			// a `func main` is far more often something you want to run than
			// something you want to stop inside, and both cannot fit in 18pt.
			if runnableLines.contains(docLine + 1), breakpointLines[docLine] == nil {
				drawRunMarker(y: y, scrollX: scrollX + blameWidth)
			} else {
				drawBreakpoint(docLine: docLine, y: y, scrollX: scrollX + blameWidth)
			}

			if let timeline {
				if showsTimeCodes { drawTimeCode(timeline, docLine: docLine, y: y, scrollX: scrollX) }
				if showsTimelineBars { drawTimeline(timeline, docLine: docLine, y: y, scrollX: scrollX) }
			}

			// On the marker when there is one, and the number goes white on it:
			// the tag is the breakpoint, so it has to be legible on top of it.
			let mark = breakpointLines[docLine]
			let colour: NSColor
			if let mark {
				colour = mark.isEnabled ? .white : Theme.current.gutterText
			} else {
				colour = isCurrent ? Theme.current.gutterCurrentLineText : Theme.current.gutterText
			}
			let number = NSAttributedString(string: "\(docLine + 1)", attributes: [
				.font: font,
				.foregroundColor: colour,
			])
			let size = number.size()
			number.draw(at: NSPoint(
				x: GutterMetrics.numberRight(markX: markX, scale: scale) - size.width,
				y: y + (lineHeight - size.height) / 2
			))

			if folding.isFoldable(line: docLine) {
				drawFoldHandle(
					at: NSPoint(x: scrollX + gutterWidth - Self.foldColumnWidth / 2, y: y + lineHeight / 2),
					collapsed: folding.isCollapsed(line: docLine)
				)
			}

			// The change marks, in the slot between the number and the fold
			// chevron — a fixed place, so they neither move when blame toggles
			// nor collide with the breakpoint column on the far left. The
			// marks are keyed 1-based, as the diff writes lines.
			if let mark = changedLines.marks[docLine + 1] {
				(mark == .added ? Theme.current.gitAdded : Theme.current.gitModified).setFill()
				NSRect(x: markX, y: y, width: (GutterMetrics.markWidth * scale).rounded(), height: lineHeight).fill()
			}
			// A deletion has no line to sit beside: the wedge sits on the
			// boundary the lines vanished from — under this line, or above the
			// first for lines deleted at the top of the file.
			if changedLines.deletedAfter.contains(docLine + 1) {
				drawDeletionMark(atY: y + lineHeight, x: markX)
			}
			if docLine == 0, changedLines.deletedAfter.contains(0) {
				drawDeletionMark(atY: y, x: markX)
			}
		}
	}

	/// The left edge of a song's columns: the time codes, then the bars.
	func songColumnsX(scrollX: CGFloat) -> CGFloat {
		scrollX + blameWidth + Self.breakpointColumnWidth
	}

	/// How wide the time-code column is: `0:00.000`, or `10:00.000` for a song
	/// of ten minutes or more, and a gap.
	var timeCodeWidth: CGFloat {
		guard let timeline, showsTimeCodes else { return 0 }
		return ceil(CGFloat(timeline.seconds >= 600 ? 9 : 8) * charWidth) + Self.gutterPadding
	}

	/// Both song columns together; nothing for a file with no timeline.
	var songColumnsWidth: CGFloat {
		guard timeline != nil else { return 0 }
		return timeCodeWidth + (showsTimelineBars ? Self.timelineColumnWidth : 0)
	}

	/// The left edge of the timeline column.
	func timelineColumnX(scrollX: CGFloat) -> CGFloat {
		songColumnsX(scrollX: scrollX) + timeCodeWidth
	}

	/// A line's time code: where it is first heard, quiet, and brighter on a
	/// line heard now.
	private func drawTimeCode(_ timeline: LineTimeline, docLine: Int, y: CGFloat, scrollX: CGFloat) {
		guard let code = timeline.timeCode(line: docLine) else { return }
		let colour = soundingLines.contains(docLine)
			? Theme.current.gutterCurrentLineText
			: Theme.current.gutterText.withAlphaComponent(0.75)
		let text = NSAttributedString(string: code, attributes: [.font: font, .foregroundColor: colour])
		let size = text.size()
		let right = songColumnsX(scrollX: scrollX) + timeCodeWidth - Self.gutterPadding / 2
		text.draw(at: NSPoint(x: right - size.width, y: y + (lineHeight - size.height) / 2))
	}

	/// A line's bar: the whole song, faint, and lit where the line is heard.
	/// A line heard nowhere draws nothing, so the column is quiet beside
	/// settings and comments.
	private func drawTimeline(_ timeline: LineTimeline, docLine: Int, y: CGFloat, scrollX: CGFloat) {
		let fractions = timeline.fractions(line: docLine)
		guard !fractions.isEmpty else { return }
		let (left, width) = timelineBarSpan(scrollX: scrollX)
		let height = max(2, Theme.current.scaled(4)).rounded()
		let top = (y + (lineHeight - height) / 2).rounded()
		Theme.current.gutterText.withAlphaComponent(0.22).setFill()
		NSRect(x: left, y: top, width: width, height: height).fill()
		Theme.current.gitModified.setFill()
		for range in fractions {
			// At least a pixel: a single hit in a four-minute song is still there.
			let from = (left + CGFloat(range.lowerBound) * width).rounded(.down)
			let to = max(from + 1, (left + CGFloat(range.upperBound) * width).rounded(.up))
			NSRect(x: from, y: top, width: to - from, height: height).fill()
		}
		// The playhead through the bar, taller than it so it reads as one line
		// down the column, and pinned at the end during the song's tail.
		if let playhead = timelinePlayhead, timeline.seconds > 0 {
			let fraction = CGFloat(min(1, max(0, playhead / timeline.seconds)))
			let tick = max(1, Theme.current.scaled(1.5))
			let reach = Theme.current.scaled(3)
			Theme.current.caret.setFill()
			NSRect(
				x: (left + fraction * width - tick / 2).rounded(), y: top - reach,
				width: tick, height: height + reach * 2
			).fill()
		}
	}

	/// The bar's inner edges, which a click and the tick both measure from.
	func timelineBarSpan(scrollX: CGFloat) -> (left: CGFloat, width: CGFloat) {
		let inset = Theme.current.scaled(4)
		return (timelineColumnX(scrollX: scrollX) + inset, Self.timelineColumnWidth - inset * 2)
	}

	/// The moment of the song under a point in the bar column.
	func timelineSeconds(atX x: CGFloat, scrollX: CGFloat) -> Double? {
		guard let timeline, timeline.seconds > 0 else { return nil }
		let (left, width) = timelineBarSpan(scrollX: scrollX)
		guard width > 0 else { return nil }
		return Double(min(1, max(0, (x - left) / width))) * timeline.seconds
	}

	/// Which device pixel of the bar the tick falls on, for deciding whether it
	/// moved.
	func timelinePlayheadPixel() -> Int? {
		guard let playhead = timelinePlayhead, let timeline, timeline.seconds > 0 else { return nil }
		let (_, width) = timelineBarSpan(scrollX: 0)
		let scale = window?.backingScaleFactor ?? 2
		return Int((min(1, max(0, playhead / timeline.seconds)) * Double(width * scale)).rounded())
	}

	/// Presses a line's bar at a fraction of its width, and drags to another
	/// before letting go when asked — real events, through `mouseDown`.
	func clickTimelineForTesting(line: Int, at fraction: Double, dragTo: Double?) {
		guard let window else { return }
		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0
		let (left, width) = timelineBarSpan(scrollX: scrollX)
		let y = yPosition(forVisualLine: firstVisualRow(forDocumentLine: line - 1)) + lineHeight / 2
		func event(_ type: NSEvent.EventType, _ f: Double) -> NSEvent? {
			let local = NSPoint(x: left + CGFloat(f) * width, y: y)
			return NSEvent.mouseEvent(
				with: type, location: convert(local, to: nil), modifierFlags: [], timestamp: 0,
				windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
			)
		}
		if let down = event(.leftMouseDown, fraction) { mouseDown(with: down) }
		if let to = dragTo, let drag = event(.leftMouseDragged, to) { mouseDragged(with: drag) }
		if let up = event(.leftMouseUp, dragTo ?? fraction) { mouseUp(with: up) }
	}

	/// Presses a line's time code — a real event, through `mouseDown`.
	func clickTimeCodeForTesting(line: Int) {
		guard let window, timeCodeWidth > 0 else { return }
		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0
		let local = NSPoint(
			x: songColumnsX(scrollX: scrollX) + timeCodeWidth / 2,
			y: yPosition(forVisualLine: firstVisualRow(forDocumentLine: line - 1)) + lineHeight / 2
		)
		for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
			guard let event = NSEvent.mouseEvent(
				with: type, location: convert(local, to: nil), modifierFlags: [], timestamp: 0,
				windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
			) else { continue }
			if type == .leftMouseDown { mouseDown(with: event) } else { mouseUp(with: event) }
		}
	}

	/// Where the song pane has got to: the tick through the bars, and whether
	/// the lines heard there are marked.
	func setSongPlayhead(_ seconds: Double?, marking: Bool) {
		timelineMarking = marking && seconds != nil
		timelinePlayhead = seconds
	}

	/// Only the rows of these lines, gutter and text: the marks move with the
	/// music, several times a second, and a whole file redrawn for each is
	/// most of a code view's frames spent on rows that did not change.
	func redrawRows(of lines: some Collection<Int>) {
		guard !lines.isEmpty, let document else { return }
		for line in lines where line < document.lineCount {
			let top = yPosition(forVisualLine: firstVisualRow(forDocumentLine: line))
			let next = line + 1 < document.lineCount
				? yPosition(forVisualLine: firstVisualRow(forDocumentLine: line + 1))
				: top + lineHeight
			setNeedsDisplay(NSRect(x: 0, y: top, width: bounds.width, height: max(lineHeight, next - top)))
		}
	}

	/// The line a breakpoint stopped the song on, or nil when it plays on.
	/// Scrolled to, as the debugger scrolls to where it stopped.
	func setSongStoppedLine(_ line: Int?) {
		guard line != songStoppedLine else { return }
		songStoppedLine = line
		if let line {
			folding.reveal(line: line)
			updateFrameSize()
			reveal(line: line + 1)
		}
		needsDisplay = true
	}

	/// A small wedge pointing at the boundary lines were deleted from.
	private func drawDeletionMark(atY y: CGFloat, x: CGFloat) {
		let size = Theme.current.scaled(7)
		let path = NSBezierPath()
		path.move(to: NSPoint(x: x - size / 2, y: y - size / 2))
		path.line(to: NSPoint(x: x + size / 2, y: y))
		path.line(to: NSPoint(x: x - size / 2, y: y + size / 2))
		path.close()
		Theme.current.gitConflict.setFill()
		path.fill()
	}

	/// Draws the breakpoint marker, and the arrow for the stopped line.
	/// The play triangle beside a runnable line.
	private func drawRunMarker(y: CGFloat, scrollX: CGFloat) {
		let size = Theme.current.scaled(9)
		let centre = NSPoint(x: scrollX + Self.breakpointColumnWidth / 2, y: y + lineHeight / 2)

		let triangle = NSBezierPath()
		triangle.move(to: NSPoint(x: centre.x - size / 2.6, y: centre.y - size / 2))
		triangle.line(to: NSPoint(x: centre.x + size / 2, y: centre.y))
		triangle.line(to: NSPoint(x: centre.x - size / 2.6, y: centre.y + size / 2))
		triangle.close()

		Theme.current.gitAdded.setFill()
		triangle.fill()
	}

	/// Which part of the gutter a point is in.
	enum GutterZone {
		/// The play triangle's strip, on the far left.
		case run
		/// The line number: where a breakpoint is made, and where its marker is.
		case number
		/// The chevron at the right, which folds and nothing else.
		case fold
		/// A song's timeline bars, which are for reading.
		case timeline
	}

	func gutterZone(at point: NSPoint, scrollX: CGFloat) -> GutterZone {
		if point.x >= scrollX + gutterWidth - Self.foldColumnWidth { return .fold }
		if point.x < scrollX + blameWidth + Self.breakpointColumnWidth { return .run }
		if timeline != nil, point.x < songColumnsX(scrollX: scrollX) + songColumnsWidth { return .timeline }
		return .number
	}

	/// The tag behind a line number, the way Xcode marks a breakpoint.
	///
	/// The number sits inside it rather than beside it: the marker is the line
	/// number, which is why clicking the number is how one is made and why
	/// there is no separate little dot to aim at.
	private func breakpointTag(y: CGFloat, scrollX: CGFloat) -> NSBezierPath {
		// Beside a song's columns rather than under them: a tag behind the bars
		// and the time codes would be a breakpoint nobody could read.
		let song = songColumnsWidth > 0 ? Self.breakpointColumnWidth + songColumnsWidth : 0
		let left = scrollX + blameWidth + song + Self.gutterPadding / 2
		let right = scrollX + gutterWidth - Self.foldColumnWidth
		let rect = NSRect(
			x: left,
			y: y + Theme.current.scaled(1.5),
			width: max(10, right - left),
			height: lineHeight - Theme.current.scaled(3)
		)
		let radius = Theme.current.scaled(3)
		let point = min(Theme.current.scaled(6), rect.height / 2)

		// Rounded on the left, pointed on the right — a tag pointing at the
		// line it stops on.
		let path = NSBezierPath()
		path.move(to: NSPoint(x: rect.minX + radius, y: rect.minY))
		path.line(to: NSPoint(x: rect.maxX - point, y: rect.minY))
		path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
		path.line(to: NSPoint(x: rect.maxX - point, y: rect.maxY))
		path.line(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
		path.appendArc(
			withCenter: NSPoint(x: rect.minX + radius, y: rect.maxY - radius),
			radius: radius, startAngle: 90, endAngle: 180
		)
		path.appendArc(
			withCenter: NSPoint(x: rect.minX + radius, y: rect.minY + radius),
			radius: radius, startAngle: 180, endAngle: 270
		)
		path.close()
		return path
	}

	private func drawBreakpoint(docLine: Int, y: CGFloat, scrollX: CGFloat) {
		guard let mark = breakpointLines[docLine] else { return }

		let tag = breakpointTag(y: y, scrollX: scrollX - blameWidth)
		let colour = NSColor.hex(0x4C7EDB)

		if mark.isEnabled {
			(mark.isVerified ? colour : colour.withAlphaComponent(0.75)).setFill()
			tag.fill()
			if !mark.isVerified {
				// Not bound: outlined rather than solid, since execution cannot
				// actually stop there yet.
				colour.setStroke()
				tag.lineWidth = 1
				tag.stroke()
			}
		} else {
			// Off, but still there: pale, the way Xcode leaves one you have
			// switched off rather than deleted.
			colour.withAlphaComponent(0.28).setFill()
			tag.fill()
		}

		// A conditional breakpoint says so, because "why did it not stop" and
		// "why did it stop" are both answered by remembering it has a
		// condition on it.
		guard mark.isConditional else { return }
		let dot = NSRect(
			x: tag.bounds.minX + Theme.current.scaled(3),
			y: tag.bounds.midY - Theme.current.scaled(1.5),
			width: Theme.current.scaled(3),
			height: Theme.current.scaled(3)
		)
		(mark.isEnabled ? NSColor.white : colour).setFill()
		NSBezierPath(ovalIn: dot).fill()
	}

	private func drawFoldHandle(at center: NSPoint, collapsed: Bool) {
		let path = NSBezierPath()
		let size: CGFloat = 3.5
		if collapsed {
			// Right-pointing chevron.
			path.move(to: NSPoint(x: center.x - size / 2, y: center.y - size))
			path.line(to: NSPoint(x: center.x + size / 2, y: center.y))
			path.line(to: NSPoint(x: center.x - size / 2, y: center.y + size))
		} else {
			// Down-pointing chevron.
			path.move(to: NSPoint(x: center.x - size, y: center.y - size / 2))
			path.line(to: NSPoint(x: center.x, y: center.y + size / 2))
			path.line(to: NSPoint(x: center.x + size, y: center.y - size / 2))
		}
		path.lineWidth = 1.3
		path.lineCapStyle = .round
		path.lineJoinStyle = .round
		Theme.current.gutterText.setStroke()
		path.stroke()
	}

	// MARK: - Caret

	func drawCaret(context: CGContext) {
		guard let position = caretPoint() else { return }
		Theme.current.caret.setFill()
		NSRect(x: position.x, y: position.y, width: 2, height: lineHeight).fill()
	}

	func caretPoint() -> NSPoint? { point(forUTF16: caret) }

	/// Where an offset in the document falls, in this view's coordinates.
	///
	/// This was the caret's own position and nothing else until a rename needed
	/// the top-left of a *symbol* rather than of the caret. Folding, word wrap
	/// and the shaping of the line are the same work for both, and two copies of
	/// that is two copies to keep agreeing.
	func point(forUTF16 caret: Int) -> NSPoint? {
		guard let document else { return nil }
		let byteOffset = document.rope.byteOffset(fromUTF16: caret)
		let docLine = document.rope.line(atByteOffset: byteOffset)
		guard !folding.isHidden(line: docLine) else { return nil }

		let visual = firstVisualRow(forDocumentLine: docLine)
			+ (isWordWrapEnabled ? wrapSegmentForOffset(caret, line: docLine) : 0)
		let lineRange = document.rope.lineByteRange(docLine)
		let lineStartUTF16 = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let text = document.rope.string(in: lineRange)

		var segmentStart = lineStartUTF16
		var segmentText = text
		if isWordWrapEnabled, let columns = wrapColumns {
			let ns = text as NSString
			let range = WrapLayout.segmentRange(
				in: text,
				segment: wrapSegmentForOffset(caret, line: docLine),
				columns: columns,
				tabWidth: Theme.current.tabWidth
			)
			segmentText = ns.substring(with: NSRange(location: range.lowerBound, length: range.count))
			segmentStart += range.lowerBound
		}

		let ctLine = CTLineCreateWithAttributedString(attributedLine(
			text: segmentText,
			lineStartUTF16: segmentStart,
			tokenIndex: TokenIndex(tokens: [])
		))
		let offset = CTLineGetOffsetForStringIndex(ctLine, max(0, caret - segmentStart), nil)
		return NSPoint(x: textOriginX + offset, y: yPosition(forVisualLine: visual))
	}

	/// Which wrapped segment an offset falls in.
	func wrapSegmentForOffset(_ offset: Int, line: Int) -> Int {
		guard let document, let columns = wrapColumns, columns > 0 else { return 0 }
		let lineRange = document.rope.lineByteRange(line)
		let lineStart = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		return WrapLayout.segment(
			forOffset: max(0, offset - lineStart),
			in: document.rope.string(in: lineRange),
			columns: columns,
			tabWidth: Theme.current.tabWidth
		)
	}

	func restartCaretBlink() {
		caretTimer?.invalidate()
		caretVisible = true
		caretTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
			guard let self else { return }
			self.caretVisible.toggle()
			self.setNeedsDisplay(self.caretRedrawRect())
		}
		needsDisplay = true
	}

	private func caretRedrawRect() -> NSRect {
		guard let point = caretPoint() else { return .zero }
		return NSRect(x: point.x - 1, y: point.y, width: 4, height: lineHeight)
	}

	override func becomeFirstResponder() -> Bool {
		// The whole view, not the caret's rect: `restartCaretBlink` ends in
		// `needsDisplay = true`, which is also what puts the selection back into
		// the strong colour. Said here because it is now load-bearing for
		// something other than the caret — a redraw narrowed to the caret would
		// leave the selection gray with the keyboard in this view.
		restartCaretBlink()
		announceKeyboardFocusChange()
		return true
	}

	override func resignFirstResponder() -> Bool {
		caretTimer?.invalidate()
		caretVisible = false
		needsDisplay = true
		announceKeyboardFocusChange()
		return true
	}

	/// Current caret position, in UTF-16 offsets.
	var caretOffset: Int { caret }

	/// The selected text, if any — used to seed the find field.
	func selectedText() -> String? {
		guard let document else { return nil }
		let selection = selectedUTF16Range()
		guard !selection.isEmpty else { return nil }
		let start = document.rope.byteOffset(fromUTF16: selection.lowerBound)
		let end = document.rope.byteOffset(fromUTF16: selection.upperBound)
		return document.rope.string(in: start..<end)
	}
}
