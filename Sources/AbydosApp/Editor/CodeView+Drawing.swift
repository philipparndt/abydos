import AppKit
import AbydosKit

/// Drawing the text, and everything drawn over it: the selection, the current
/// line, the change marks and the folds.
extension CodeView {
	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		guard let context = NSGraphicsContext.current?.cgContext else { return }

		// Bands the selection has moved out from under, dropped before anything
		// is painted. See `occurrencesSelection`.
		if !selectionOccurrences.isEmpty, selectedUTF16Range() != occurrencesSelection {
			selectionOccurrences = []
			occurrencesSelection = nil
		}

		Theme.current.editorBackground.setFill()
		dirtyRect.fill()

		guard let document else { return }
		let rows = visualLineRange(in: dirtyRect)
		guard !rows.isEmpty else { return }

		let firstDocLine = documentLine(forVisualRow: rows.lowerBound)
		let lastDocLine = min(document.lineCount - 1, documentLine(forVisualRow: max(rows.lowerBound, rows.upperBound - 1)))

		// One syntax query for the whole visible span, rather than per line.
		let tokens = document.highlights(forLineRange: firstDocLine..<(lastDocLine + 1))
		let tokenIndex = TokenIndex(tokens: tokens)

		let caretLine = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: caret))
		let selection = selectedUTF16Range()

		// The gutter stays pinned to the left edge while the text scrolls under
		// it, so it is positioned against the clip view rather than the document.
		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0

		context.saveGState()
		context.clip(to: NSRect(
			x: scrollX + gutterWidth,
			y: dirtyRect.minY,
			width: bounds.width,
			height: dirtyRect.height
		))

		for visual in rows {
			let docLine = documentLine(forVisualRow: visual)
			guard docLine < document.lineCount else { break }
			let segment = wrapSegment(forVisualRow: visual)

			let y = yPosition(forVisualLine: visual)
			let rowRect = NSRect(x: 0, y: y, width: bounds.width, height: lineHeight)

			// The line execution is stopped on wins over the caret's own band.
			if docLine == executionLine {
				NSColor.hex(0x3A4A2A).setFill()
				NSRect(x: scrollX + gutterWidth, y: y, width: bounds.width, height: lineHeight).fill()
			} else if docLine == caretLine, selection.isEmpty {
				Theme.current.currentLineBackground.setFill()
				NSRect(x: scrollX + gutterWidth, y: y, width: bounds.width, height: lineHeight).fill()
			}

			// The matches on this row, at the two depths they are painted at. The
			// others go on here, under the selection; the current one goes to
			// `drawLine`, which puts it on *over* the selection — see there.
			let matches = searchHighlights(docLine: docLine, segment: segment, rect: rowRect)
			// Where the selected text also appears, at the same depth and never
			// on the same row as a find match: one of the two lists is always
			// empty, because find wins while it is showing.
			if !matches.occurrences.isEmpty {
				Theme.current.selectionOccurrenceBackground.setFill()
				for band in matches.occurrences { band.fill() }
			}
			if !matches.others.isEmpty {
				Theme.current.searchMatchBackground.setFill()
				for band in matches.others { band.fill() }
			}

			drawLine(
				docLine: docLine,
				segment: segment,
				rect: rowRect,
				tokenIndex: tokenIndex,
				selection: selection,
				currentMatch: matches.current,
				context: context
			)
		}

		// **The redaction covers take the top of the paint order** — over the
		// text, the selection and every match band, under the caret alone —
		// which is the place the editor spec states for them: a redaction
		// anything can be painted over is not one. A click's reveal lives
		// exactly as long as the caret stays on that line; checked here rather
		// than on every caret move, because this is where every caret move
		// ends up.
		if concealsSecrets, !secretsRevealedAll {
			// Darker than the text it replaces, and one blend away from the
			// theme rather than a fixed colour, so a light theme's redaction
			// is a dark pill on paper and a dark theme's is a deeper shadow.
			let pillColour = Theme.current.gutterText
				.blended(withFraction: 0.55, of: .black) ?? Theme.current.gutterText
			for visual in rows {
				let docLine = documentLine(forVisualRow: visual)
				guard docLine < document.lineCount else { break }
				guard let cover = secretCover(docLine: docLine, visualRow: visual) else { continue }
				// Erased in the row's own background, so the line appears to
				// end where the value began — the caret's line keeps its band.
				(docLine == caretLine
					? Theme.current.currentLineBackground
					: Theme.current.editorBackground).setFill()
				cover.erase.fill()
				if let pill = cover.pill {
					pillColour.setFill()
					NSBezierPath(roundedRect: pill, xRadius: 3, yRadius: 3).fill()
				}
			}
		}
		context.restoreGState()

		drawGutter(rows: rows, caretLine: caretLine, scrollX: scrollX, context: context)

		if caretVisible, hasKeyboard, selection.isEmpty {
			drawCaret(context: context)
		}
	}

	/// Builds the attributed line and draws text, selection, and any fold marker.
	private func drawLine(
		docLine: Int,
		segment: Int = 0,
		rect: NSRect,
		tokenIndex: TokenIndex,
		selection: Range<Int>,
		currentMatch: NSRect? = nil,
		context: CGContext
	) {
		guard let document else { return }

		let lineRange = document.rope.lineByteRange(docLine)
		var lineStartUTF16 = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		var text = document.rope.string(in: lineRange)

		// With wrap on, a row shows one slice of its line. Slicing by UTF-16
		// offset keeps the highlight ranges valid without re-mapping them.
		if isWordWrapEnabled, let columns = wrapColumns {
			let ns = text as NSString
			let range = WrapLayout.segmentRange(
				in: text,
				segment: segment,
				columns: columns,
				tabWidth: Theme.current.tabWidth
			)
			guard !range.isEmpty || segment == 0 else { return }
			text = ns.substring(with: NSRange(
				location: range.lowerBound,
				length: range.count
			))
			lineStartUTF16 += range.lowerBound
		}

		let attributed = attributedLine(
			text: text,
			lineStartUTF16: lineStartUTF16,
			tokenIndex: tokenIndex
		)

		let ctLine = CTLineCreateWithAttributedString(attributed)
		let baseline = rect.maxY - baselineOffset

		// Selection sits behind the glyphs.
		let lineEndUTF16 = lineStartUTF16 + (text as NSString).length
		if !selection.isEmpty, selection.lowerBound <= lineEndUTF16, selection.upperBound >= lineStartUTF16 {
			drawSelection(
				ctLine: ctLine,
				lineStartUTF16: lineStartUTF16,
				lineEndUTF16: lineEndUTF16,
				selection: selection,
				rect: rect
			)
		}

		// **The current match goes on after the selection, and that ordering is
		// the whole of 0536.** Revealing a match selects it, so the two cover the
		// same pixels — and the selection, painted second, turned the one match
		// meant to be findable at a glance into the dimmest thing on the screen:
		// in dark `abydos` the current match is 5.6 against the editor ground and
		// the unfocused selection that covered it is 1.4, below the 2.2 of every
		// *other* match on the page. The strongest became the weakest, which is
		// what was reported.
		//
		// Painting it last states which of the two claims wins where they
		// coincide rather than leaving it to the order two functions happen to be
		// called in. It is not a case of skipping the selection: a selection
		// somebody has extended past the match still draws in full, and only the
		// match's own rectangle is covered — which is also why "coincide" needs
		// no definition here. Nothing depends on the unfocused selection's
		// colour, so this holds with the keyboard in the editor too, where the
		// covering colour was 1.5 rather than 1.4 and the inversion was milder
		// but the same shape.
		if let currentMatch {
			Theme.current.searchMatchCurrentBackground.setFill()
			currentMatch.fill()
		}

		// This view is flipped, which inverts the context's y-axis. CoreText would
		// otherwise render every glyph upside down, so the text matrix flips it
		// back. (AppKit's own -[NSAttributedString drawAtPoint:] compensates
		// internally, which is why the gutter and tab labels need no such fix.)
		context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
		context.textPosition = CGPoint(x: textOriginX, y: baseline)
		CTLineDraw(ctLine, context)

		drawDiagnostics(docLine: docLine, ctLine: ctLine, lineStartUTF16: lineStartUTF16, rect: rect)
		drawInlineDiagnostic(docLine: docLine, ctLine: ctLine, rect: rect)
		drawInlineValues(docLine: docLine, text: text, ctLine: ctLine, rect: rect)
		drawNavigableWord(docLine: docLine, ctLine: ctLine, lineStartUTF16: lineStartUTF16, rect: rect)

		// A collapsed region gets a "{…}" chip after its first line.
		if folding.isCollapsed(line: docLine) {
			let textWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
			drawFoldPlaceholder(
				at: NSPoint(x: textOriginX + textWidth + 6, y: rect.minY),
				hiddenLines: folding.foldRange(startingAt: docLine)?.hiddenLineCount ?? 0
			)
		}
	}


	/// Underlines the word ⌘-clicking would follow.
	///
	/// The same affordance a link has, for the same reason: the pointer is
	/// already over the word, and something has to say that pressing here goes
	/// somewhere rather than putting the caret down.
	private func drawNavigableWord(docLine: Int, ctLine: CTLine, lineStartUTF16: Int, rect: NSRect) {
		guard let word = navigableWord, word.line == docLine else { return }
		let length = CTLineGetStringRange(ctLine).length

		// Line-relative, like a diagnostic's columns: a word in a later wrapped
		// segment falls outside the piece being drawn and is skipped.
		let from = word.range.lowerBound
		guard from >= 0, from < length else { return }
		let to = min(word.range.upperBound, length)
		guard to > from else { return }

		let startX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, from, nil)
		let endX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, to, nil)

		Theme.current.color(for: HighlightKind.function).setStroke()
		let underline = NSBezierPath()
		underline.lineWidth = 1
		let y = rect.maxY - Theme.current.scaled(2.5)
		underline.move(to: NSPoint(x: startX, y: y))
		underline.line(to: NSPoint(x: endX, y: y))
		underline.stroke()
	}

	/// Works out what ⌘ would follow at this point, and repaints if it changed.
	func updateNavigableWord(at point: NSPoint?, commandHeld: Bool) {
		let found: (line: Int, range: Range<Int>)? = {
			guard commandHeld, let point, let document, point.x > gutterWidth else { return nil }

			let offset = self.offset(at: point)
			let byte = document.rope.byteOffset(fromUTF16: offset)
			let line = document.rope.line(atByteOffset: byte)
			let lineRange = document.rope.lineByteRange(line)
			let lineStart = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
			let text = document.rope.string(in: lineRange) as NSString

			func isWordCharacter(_ index: Int) -> Bool {
				guard index >= 0, index < text.length else { return false }
				let unit = text.character(at: index)
				guard let scalar = Unicode.Scalar(unit) else { return false }
				return CharacterSet.alphanumerics.contains(scalar)
					|| unit == UInt16(UnicodeScalar("_").value)
			}

			var start = max(0, min(offset - lineStart, text.length))
			var end = start
			// Pointing just past a word counts as pointing at it; pointing at
			// whitespace does not.
			if !isWordCharacter(start), isWordCharacter(start - 1) { start -= 1; end = start }
			guard isWordCharacter(start) else { return nil }

			while isWordCharacter(start - 1) { start -= 1 }
			while isWordCharacter(end) { end += 1 }
			return (line, start..<end)
		}()

		let changed = found?.line != navigableWord?.line || found?.range != navigableWord?.range
		guard changed else { return }
		navigableWord = found
		// The pointer says the same thing the underline does.
		if found != nil { NSCursor.pointingHand.set() } else { NSCursor.iBeam.set() }
		needsDisplay = true
	}

	/// Pretends the pointer is at a line and column with ⌘ held.
	func hoverWithCommandForTesting(line: Int, character: Int) {
		guard let document else { return }
		let lineStart = document.rope.utf16Offset(fromByte: document.rope.byteOffset(ofLine: line))
		let point = pointForTesting(offset: lineStart + character, line: line)
		updateNavigableWord(at: point, commandHeld: true)
	}

	private func pointForTesting(offset: Int, line: Int) -> NSPoint {
		let row = firstVisualRow(forDocumentLine: line)
		return NSPoint(
			x: textOriginX + CGFloat(offset - document!.rope.utf16Offset(
				fromByte: document!.rope.byteOffset(ofLine: line)
			)) * charWidth + charWidth / 2,
			y: CGFloat(row) * lineHeight + lineHeight / 2
		)
	}

	override func flagsChanged(with event: NSEvent) {
		super.flagsChanged(with: event)
		guard let window else { return }
		let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
		updateNavigableWord(
			at: bounds.contains(point) ? point : nil,
			commandHeld: event.modifierFlags.contains(.command)
		)
	}

	/// The message itself, after the end of the line.
	///
	/// A squiggle says where a problem is; it does not say what it is, and
	/// reading it means putting the pointer on a few characters and waiting.
	/// The worst problem on a line is written out beside it instead, dimmed and
	/// out of the way of the code, which is the arrangement Error Lens made
	/// popular because it works: the message is read without aiming at it.
	private func drawInlineDiagnostic(docLine: Int, ctLine: CTLine, rect: NSRect) {
		guard Settings.shared.showsInlineDiagnostics else { return }
		guard let worst = diagnosticsByLine[docLine]?.min(by: { $0.severity < $1.severity })
		else { return }

		let message = worst.message
			.replacingOccurrences(of: "\n", with: " ")
			.trimmingCharacters(in: .whitespaces)
		guard !message.isEmpty else { return }

		let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
		let x = textOriginX + lineWidth + charWidth * 3
		// Room enough to be worth drawing: on a very long line the squiggle and
		// the hover are what is left.
		let available = bounds.maxX - x - Theme.current.scaled(12)
		guard available > charWidth * 8 else { return }

		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let text = NSAttributedString(string: message, attributes: [
			.font: Theme.current.editorFont,
			.foregroundColor: colour(for: worst.severity).withAlphaComponent(0.55),
			.paragraphStyle: paragraph,
		])
		text.draw(in: NSRect(
			x: x,
			y: rect.maxY - baselineOffset - text.size().height * 0.78,
			width: available,
			height: text.size().height
		))
	}

	/// What the variables on this line are, while execution is stopped above it.
	///
	/// **The same shape as the inline diagnostic above**, deliberately: an
	/// annotation at the end of a line already had a way of being drawn here —
	/// placed past the glyphs, truncating rather than wrapping, dimmed, and
	/// given up on when there is no room left. A second way of doing it would
	/// have been a second set of decisions about all of that.
	///
	/// **Only at or above the line execution stopped on.** Below it a value is
	/// either left over from a previous pass or has not been assigned at all,
	/// and it would be drawn in the same grey as one that is true.
	///
	/// One `guard` when nothing is stopped, which is nearly always.
	private func drawInlineValues(docLine: Int, text: String, ctLine: CTLine, rect: NSRect) {
		guard let inlineValues, let executionLine, docLine <= executionLine else { return }

		let hints = InlineValues.hints(in: text, from: inlineValues)
		guard !hints.isEmpty else { return }

		let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
		let x = textOriginX + lineWidth + charWidth * 3
		let available = bounds.maxX - x - Theme.current.scaled(12)
		guard available > charWidth * 8 else { return }

		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let drawn = NSAttributedString(
			string: Self.joined(hints),
			attributes: [
				.font: Theme.current.editorFont,
				.foregroundColor: Theme.current.gitIgnored,
				.paragraphStyle: paragraph,
			]
		)
		drawn.draw(in: NSRect(
			x: x,
			y: rect.maxY - baselineOffset - drawn.size().height * 0.78,
			width: available,
			height: drawn.size().height
		))

		// A hint with something under it is underlined, which is the whole of
		// how a door is told from a piece of text before it is pressed. Drawn
		// rather than an attribute so that it stops where the hint does and not
		// where the string does.
		Theme.current.gitIgnored.withAlphaComponent(0.5).setFill()
		for hint in hints where hint.isOpenable {
			var band = hintRect(hint, in: hints, from: x, rect: rect)
			band.origin.y = rect.maxY - Theme.current.scaled(3)
			band.size.height = 1
			guard band.maxX <= bounds.maxX - Theme.current.scaled(12) else { continue }
			band.fill()
		}
	}

	/// The hints of a line as one string, in one place, so the drawing and the
	/// hit test cannot come to disagree about where anything is.
	private static func joined(_ hints: [InlineValueHint]) -> String {
		hints.map(\.text).joined(separator: Self.hintSeparator)
	}

	private static let hintSeparator = "   "

	/// Where one hint sits, from the arithmetic the drawing already does.
	///
	/// **Not recorded while drawing.** Storing a rect per hint per row would put
	/// bookkeeping on the drawing path and leave it stale the moment a line is
	/// edited or the window resized; the editor font is monospaced, so the same
	/// answer can be worked out when somebody actually clicks — which is once,
	/// rather than on every repaint of every row.
	private func hintRect(
		_ hint: InlineValueHint, in hints: [InlineValueHint], from x: CGFloat, rect: NSRect
	) -> NSRect {
		var characters = 0
		for other in hints {
			if other == hint { break }
			characters += other.text.count + Self.hintSeparator.count
		}
		return NSRect(
			x: x + CGFloat(characters) * charWidth,
			y: rect.minY,
			width: CGFloat(hint.text.count) * charWidth,
			height: rect.height
		)
	}


	/// The hints on one line and where each of them is, in this view.
	///
	/// **Worked out from the line's own text and the frame's values** — the same
	/// two things the drawing is made from — rather than recorded while drawing.
	/// Storing a rect per hint per row would put bookkeeping on the drawing path
	/// and leave it stale the moment a line is edited; the editor font is
	/// monospaced, so the same answer can be had when somebody actually clicks.
	func hintsWithRects(onVisualRow visual: Int) -> [(hint: InlineValueHint, rect: NSRect)] {
		guard let inlineValues, let executionLine, let document else { return [] }
		let docLine = min(document.lineCount - 1, documentLine(forVisualRow: visual))
		guard docLine <= executionLine else { return [] }

		let range = document.rope.lineByteRange(docLine)
		let text = document.rope.string(in: range)
		let hints = InlineValues.hints(in: text, from: inlineValues)
		guard !hints.isEmpty else { return [] }

		// The same x the drawing starts at, from the same measurement.
		let attributed = attributedLine(
			text: text,
			lineStartUTF16: document.rope.utf16Offset(fromByte: range.lowerBound),
			// An empty index: this wants the width of the line's glyphs, and
			// what colour they are drawn in does not change it.
			tokenIndex: TokenIndex(tokens: [])
		)
		let ctLine = CTLineCreateWithAttributedString(attributed)
		let lineWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
		let x = textOriginX + lineWidth + charWidth * 3
		let row = NSRect(
			x: 0, y: CGFloat(visual) * lineHeight, width: bounds.width, height: lineHeight
		)
		return hints.map { ($0, hintRect($0, in: hints, from: x, rect: row)) }
	}

	/// The hint under a point, if there is one and it can be opened.
	func openableInlineValue(at point: NSPoint) -> InlineValueHint? {
		guard inlineValues != nil else { return nil }
		let visual = max(0, min(visibleLineCount - 1, Int(floor(point.y / lineHeight))))
		return hintsWithRects(onVisualRow: visual)
			.first { $0.hint.isOpenable && $0.rect.contains(point) }?.hint
	}

	/// Draws every row this file has, which is what scrolling past all of them
	/// costs. For the claim that drawing values asks the adapter for nothing.
	func drawEveryRowForTesting() {
		guard let document else { return }
		for line in 0..<document.lineCount {
			let text = document.rope.string(in: document.rope.lineByteRange(line))
			guard let inlineValues, let executionLine, line <= executionLine else { continue }
			_ = InlineValues.hints(in: text, from: inlineValues)
		}
	}

	/// The first value on this file that can be opened, and where it is — as a
	/// click would find it, through the same function a click uses.
	func firstOpenableInlineValueForTesting() -> (hint: InlineValueHint, rect: NSRect)? {
		guard inlineValues != nil, executionLine != nil else { return nil }
		for visual in 0..<max(visibleLineCount, 1) {
			if let found = hintsWithRects(onVisualRow: visual).first(where: { $0.hint.isOpenable }) {
				return found
			}
		}
		return nil
	}

	/// What a click in the middle of the value named would find — for the claim
	/// that a value with nothing under it is not a door. Nil where no value of
	/// that name is drawn.
	func clickAnswerForTesting(named name: String) -> String? {
		for visual in 0..<max(visibleLineCount, 1) {
			guard let found = hintsWithRects(onVisualRow: visual)
				.first(where: { $0.hint.name == name }) else { continue }
			let middle = NSPoint(x: found.rect.midX, y: found.rect.midY)
			let hit = openableInlineValue(at: middle)
			return hit == nil
				? "\(name): nothing opens, and the click is the editor's"
				: "\(name): opens"
		}
		return nil
	}

	/// Every line of this file that has values beside it, for a driver to print.
	///
	/// A photograph shows that *something* is drawn at the end of a line; it
	/// cannot be diffed, and at the width a value gets it cannot always be read.
	/// This is the same answer the drawing uses, from the same function.
	func inlineValueReportForTesting() -> String {
		guard let inlineValues, let executionLine, let document else {
			return "nothing is stopped here"
		}
		var lines: [String] = []
		for docLine in 0...min(executionLine, max(document.lineCount - 1, 0)) {
			let text = document.rope.string(in: document.rope.lineByteRange(docLine))
			let hints = InlineValues.hints(in: text, from: inlineValues)
			guard !hints.isEmpty else { continue }
			// The door is marked, because which hints can be opened is the claim
			// being checked and a photograph cannot say it.
			lines.append("  \(docLine + 1): " + hints.map {
				$0.isOpenable ? "\($0.text) [opens, ref \($0.variablesReference)]" : $0.text
			}.joined(separator: "   "))
		}
		return lines.isEmpty ? "no line names a variable in this frame" : lines.joined(separator: "\n")
	}

	/// Underlines what a language server objects to on this line.
	///
	/// A squiggle rather than a background: a problem is a property of a few
	/// characters, and tinting the whole row would fight with the current-line
	/// band, the selection and the search highlights, all of which are also
	/// backgrounds and all of which mean something else.
	private func drawDiagnostics(docLine: Int, ctLine: CTLine, lineStartUTF16: Int, rect: NSRect) {
		let diagnostics = diagnosticsByLine[docLine] ?? []
		guard !diagnostics.isEmpty else { return }
		let length = CTLineGetStringRange(ctLine).length

		for diagnostic in diagnostics.sorted(by: { $0.severity > $1.severity }) {
			let start = diagnostic.range.start.character
			// A range ending on a later line runs to the end of this one; a
			// zero-width range still gets something to see and hover over.
			let end = diagnostic.range.end.line > docLine
				? length
				: max(diagnostic.range.end.character, start + 1)

			let from = max(0, min(start, length))
			let to = max(from, min(end, length))
			let startX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, from, nil)
			var endX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, to, nil)
			// An empty line, or a problem past its end, still needs a mark.
			if endX <= startX { endX = startX + charWidth }

			colour(for: diagnostic.severity).setStroke()
			squiggle(from: startX, to: endX, y: rect.maxY - Theme.current.scaled(2)).stroke()
		}
	}

	/// The worst problem on the line the caret is on, for the menu.
	func diagnosticAtCaret() -> (line: Int, diagnostic: LSPDiagnostic)? {
		guard let position = caretPositionForRequest() else { return nil }
		guard let worst = diagnosticsByLine[position.line]?.min(by: { $0.severity < $1.severity })
		else { return nil }
		return (position.line, worst)
	}

	/// The wavy line, drawn as one path so it strokes in a single pass.
	private func squiggle(from startX: CGFloat, to endX: CGFloat, y: CGFloat) -> NSBezierPath {
		let path = NSBezierPath()
		path.lineWidth = 1
		let amplitude = Theme.current.scaled(1.4)
		let period = Theme.current.scaled(4)

		path.move(to: NSPoint(x: startX, y: y))
		var x = startX
		var up = true
		while x < endX {
			let next = min(x + period, endX)
			path.line(to: NSPoint(x: next, y: y + (up ? -amplitude : amplitude)))
			x = next
			up.toggle()
		}
		return path
	}

	/// The colour a diagnostic is drawn in, from the weight it is worth.
	///
	/// **No third literal for the provisional weight**, which was the outcome to
	/// rule out: `quiet` is `gitIgnored`, the colour `hint` and `information`
	/// have always been drawn in, so a scheme that has been thought about is
	/// thought about here too. Moving the two severities into the scheme files —
	/// as 0536 did for the find highlights — remains worth doing and is a change
	/// of its own; this one does not need it, because it adds no colour.
	static func color(for weight: DiagnosticWeight) -> NSColor {
		switch weight {
		case .error: return .hex(0xE05252)
		// Amber rather than the git blue: blue is what this window uses for
		// "changed", and a warning is not a change.
		case .warning: return .hex(0xD9A343)
		case .quiet: return Theme.current.gitIgnored
		}
	}

	/// What a diagnostic on screen is worth, which is its severity unless the
	/// server that sent it had said it was still preparing.
	private func colour(for severity: LSPDiagnostic.Severity) -> NSColor {
		Self.color(for: DiagnosticWeight.weight(
			of: severity, fromPreparingServer: diagnosticsArePreparing
		))
	}
}
