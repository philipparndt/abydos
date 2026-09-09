import AppKit
import AbydosKit

/// Debugging marks in the text, finding text in it, and the helpers the
/// selection is worked out with.
extension CodeView {
	// MARK: - Debugging

	/// Lines with a play button, given 1-based as the run configurations
	/// report them.
	func setRunnableLines(_ lines: Set<Int>) {
		guard lines != runnableLines else { return }
		runnableLines = lines
		needsDisplay = true
		window?.invalidateCursorRects(for: self)
	}

	/// An I-beam over the text, and a pointing hand over each play button.
	///
	/// The rest of the gutter keeps the arrow: the breakpoint column responds to
	/// a click too, but a play button is the only part that reads as a control,
	/// and marking everything would say nothing.
	///
	/// **The I-beam has to be a cursor rect, not a `set()`.** There were three
	/// `NSCursor.iBeam.set()` calls already and the pointer was still an arrow
	/// over the text, because every one of them is behind a *transition*:
	/// `updateNavigableWord` returns unless the ⌘-hover word changed, and
	/// `mouseMoved` only asks when leaving an inline value. Moving across plain
	/// text runs none of them — and a bare `set()` would not have held anyway,
	/// since AppKit re-applies the cursor from these rects as the pointer moves.
	/// The hands below still win where they fire: they are set from `mouseMoved`,
	/// which runs after the rects have been applied for that event.
	///
	/// Added before the play buttons, and before their `guard`, so that a file
	/// with nothing runnable in it — most files — still gets the I-beam.
	override func resetCursorRects() {
		super.resetCursorRects()

		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0
		let visible = enclosingScrollView?.contentView.bounds ?? bounds

		// From where the gutter ends to the right edge. The gutter floats at the
		// scroll origin, which is why this starts there rather than at zero, and
		// it covers the padding before the first glyph because a click there
		// puts the caret on the line like any other.
		let textLeft = scrollX + gutterWidth
		if visible.maxX > textLeft {
			addCursorRect(
				NSRect(
					x: textLeft,
					y: visible.minY,
					width: visible.maxX - textLeft,
					height: visible.height
				),
				cursor: .iBeam
			)
		}

		guard !runnableLines.isEmpty else { return }
		for visual in visualLineRange(in: visible) {
			let docLine = documentLine(forVisualRow: visual)
			guard runnableLines.contains(docLine + 1), breakpointLines[docLine] == nil else { continue }
			guard wrapSegment(forVisualRow: visual) == 0 else { continue }

			addCursorRect(
				NSRect(
					x: scrollX,
					y: yPosition(forVisualLine: visual),
					width: Self.breakpointColumnWidth,
					height: lineHeight
				),
				cursor: .pointingHand
			)
		}
	}

	/// Breakpoints to draw, keyed by 0-based line.
	func setBreakpoints(_ lines: [Int: BreakpointMark]) {
		guard lines != breakpointLines else { return }
		breakpointLines = lines
		needsDisplay = true
		window?.invalidateCursorRects(for: self)
	}

	/// What the gutter is marking, for a driven run: a picture of a gutter
	/// cannot say whether three marks are the right three.
	var changedLinesReportForTesting: String {
		guard !changedLines.marks.isEmpty || !changedLines.deletedAfter.isEmpty else {
			return "no marks"
		}
		let marks = changedLines.marks.sorted { $0.key < $1.key }
			.map { "\($0.key)=\($0.value)" }
			.joined(separator: " ")
		let deleted = changedLines.deletedAfter.sorted().map(String.init).joined(separator: ",")
		return marks + (deleted.isEmpty ? "" : " deletedAfter=\(deleted)")
	}

	/// Which lines differ from HEAD, for the gutter's change marks.
	func setChangedLines(_ lines: GitChangedLines) {
		guard lines != changedLines else { return }
		changedLines = lines
		needsDisplay = true
	}

	/// Keeps the marks beside the lines they belong to while somebody types,
	/// and marks what the edit touched — the breakpoint anchoring's shape. An
	/// approximation by design: the next save's diff replaces the whole
	/// answer; a mark visibly pointing at the line below the one it means, in
	/// the meantime, is worse than no mark.
	func shiftChangedLines(from firstLine: Int, removed: Int, inserted: Int) {
		var marks: [Int: GitChangedLines.Mark] = [:]
		for (line, mark) in changedLines.marks {
			if line < firstLine {
				marks[line] = mark
			} else if line >= firstLine + removed {
				marks[line - removed + inserted] = mark
			}
			// A mark inside the replaced range dies with the lines it marked;
			// the touched range below is marked afresh.
		}
		var deleted: Set<Int> = []
		for line in changedLines.deletedAfter {
			if line < firstLine {
				deleted.insert(line)
			} else if line >= firstLine + removed {
				deleted.insert(line - removed + inserted)
			}
		}
		// The lines the edit put there read as modified until the diff says
		// better — immediate feedback is the point of shifting at all.
		if inserted > 0 {
			for line in firstLine..<(firstLine + inserted) {
				marks[line] = marks[line] ?? .modified
			}
		} else if removed > 0 {
			deleted.insert(max(0, firstLine - 1))
		}
		changedLines = GitChangedLines(marks: marks, deletedAfter: deleted)
		needsDisplay = true
	}

	/// The line execution is stopped on, or nil when not stopped here.
	/// The values to draw beside the code, or nil while nothing is stopped.
	///
	/// Beside `setExecutionLine` and `setBreakpoints` because it is the same
	/// kind of thing — per-file debug state the editor pushes in — and it
	/// arrives by the same route, `EditorViewController.applyDebugState`.
	func setInlineValues(_ values: [String: Variable]?) {
		let wanted = (values?.isEmpty ?? true) ? nil : values
		guard wanted != inlineValues else { return }
		inlineValues = wanted
		needsDisplay = true
	}

	func setExecutionLine(_ line: Int?) {
		guard line != executionLine else { return }
		executionLine = line
		if let line {
			folding.reveal(line: line)
			updateFrameSize()
			reveal(line: line + 1)
		}
		needsDisplay = true
	}

	// MARK: - Search

	/// Highlights matches. The current one is drawn more strongly and scrolled to.
	func setSearchMatches(_ matches: [SearchMatch], current: Int?) {
		searchMatches = matches
		currentMatchIndex = current
		if !matches.isEmpty { dropOccurrences() }
		if let current, matches.indices.contains(current) {
			// Select the match so Escape leaves the caret somewhere sensible.
			let range = matches[current].utf16Range
			selectionAnchor = range.lowerBound
			caret = range.upperBound
			revealCurrentMatch()
		}
		needsDisplay = true
	}

	/// The same highlights, moved, without moving the caret.
	///
	/// `setSearchMatches` selects the current match and scrolls to it, which is
	/// right when somebody asked to be taken there — a query typed, ⌘G — and
	/// wrong on every keystroke of an edit: the caret is where they are typing,
	/// and dragging it to the nearest match on each character would make the file
	/// impossible to type in with find open.
	func updateSearchMatches(_ matches: [SearchMatch], current: Int?) {
		searchMatches = matches
		currentMatchIndex = current
		if !matches.isEmpty { dropOccurrences() }
		needsDisplay = true
	}

	func clearSearchMatches() {
		searchMatches = []
		currentMatchIndex = nil
		needsDisplay = true
		// Find has stopped answering, so a selection standing behind it may say
		// something again.
		selectionChanged()
	}

	/// Takes the occurrence bands away without asking for new ones.
	///
	/// For find arriving: its matches win while it is showing, and the bands
	/// would otherwise sit under them meaning something else.
	private func dropOccurrences() {
		occurrenceScan?.cancel()
		occurrenceScan = nil
		selectionOccurrences = []
		occurrencesSelection = nil
	}

	private func revealCurrentMatch() {
		guard let document, let index = currentMatchIndex, searchMatches.indices.contains(index) else { return }
		let match = searchMatches[index]
		let byte = document.rope.byteOffset(fromUTF16: match.utf16Range.lowerBound)
		let line = document.rope.line(atByteOffset: byte)

		folding.reveal(line: line)
		widenForTheLongestLine(upTo: line)
		updateFrameSize()
		// The match's start rather than the caret, which `setSearchMatches` has
		// left at its end: what somebody wants to read is the match, and on a long
		// line the two are not the same place. The whole match rather than its
		// start, so a long one is not called visible on the strength of its first
		// character.
		bringOnScreen(utf16: match.utf16Range.lowerBound, extendingTo: match.utf16Range.upperBound)
		needsDisplay = true
	}

	/// Moves the caret to a 1-based line and column and brings it on screen.
	/// Used when jumping to a review finding or a search result.
	///
	/// The scrolling half of this is `bringOnScreen`, which needs a pane that has
	/// been laid out. So layout is *made* to have happened here rather than waited
	/// for: a reveal on a tab that has just been installed runs before the layout
	/// pass that gives its scroll view a size, and everything below — the wrap
	/// layout the point is measured in, the viewport it is centred against — is
	/// measured against that size. This used to be a `DispatchQueue.main.async` in
	/// `EditorViewController.open`, which is a bet on the work taking one turn of
	/// the main loop rather than two (item 533).
	///
	/// `length` is how much of the line is being pointed at — a search match's own
	/// length, in UTF-16 units, and zero for a place rather than a span. It only
	/// affects the sideways answer, where the difference between a caret and a
	/// forty-character match is the difference between visible and mostly off
	/// screen.
	func reveal(line: Int, column: Int = 1, length: Int = 0) {
		guard let document else { return }
		window?.contentView?.layoutSubtreeIfNeeded()

		let target = max(0, min(line - 1, document.lineCount - 1))
		folding.reveal(line: target)

		let lineRange = document.rope.lineByteRange(target)
		let start = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let end = document.rope.utf16Offset(fromByte: lineRange.upperBound)
		let offset = min(end, start + max(0, column - 1))

		widenForTheLongestLine(upTo: target)
		updateFrameSize()
		setCaret(offset, extendingSelection: false)
		// Clamped to the line: a length that ran past its end would measure a
		// point on the next one and read as a span of negative width.
		bringOnScreen(utf16: offset, extendingTo: length > 0 ? min(end, offset + length) : nil)
	}

	/// Makes sure the view is wide enough to scroll to the end of one line.
	///
	/// `measureLongestLine` runs off the main thread and leaves 120 columns
	/// standing in until it answers, so the view can be narrower than the line
	/// being revealed — and then the scroll to a match far along it is clamped
	/// short of the match. Measuring the one line is a line's worth of work, and
	/// the real answer is never smaller.
	func widenForTheLongestLine(upTo line: Int) {
		longestLineColumns = max(longestLineColumns, displayColumns(ofLine: line) + 2)
	}

	/// The same for a run of lines, which is what an edit that moved lines about
	/// has just written.
	func widenForTheLongestLine(lines: ClosedRange<Int>) {
		guard let document else { return }
		let last = min(lines.upperBound, document.lineCount - 1)
		let first = max(0, lines.lowerBound)
		guard first <= last else { return }
		for line in first...last { widenForTheLongestLine(upTo: line) }
	}


	/// Scrolls so a document offset — or a span starting at it — is on screen,
	/// leaving the view alone when it already is.
	///
	/// The arithmetic is `RevealScroll` in AbydosKit, where it can be asked
	/// without a window: which axes have to move, how far, and — the answer that
	/// matters here — whether the pane is in a state to be measured at all.
	///
	/// `extendingTo` is the far end of what is being shown, when there is one. It
	/// is measured here rather than counted in characters because a column is not
	/// a distance: a tab, a wide glyph or a ligature all make the same number of
	/// UTF-16 units a different number of points, and this view already has the
	/// one function that knows — `point(forUTF16:)`, the same one the caret uses.
	private func bringOnScreen(utf16 offset: Int, extendingTo end: Int? = nil) {
		guard let scrollView = enclosingScrollView, window != nil else {
			pendingReveal = (offset, end)
			return
		}
		// Nil is an offset inside a collapsed fold, which is nothing to show
		// rather than something to wait for: every caller unfolds first.
		guard let point = point(forUTF16: offset) else { return }

		// Only when both ends are on the same visual row. A match that wraps, or
		// that a server reported as running onto the next line, has no width on
		// this one — and a difference taken across rows would be a nonsense.
		var width: CGFloat = 0
		if let end, end > offset, let far = self.point(forUTF16: end), far.y == point.y {
			width = max(0, far.x - point.x)
		}

		let answer = RevealScroll.answer(
			bringing: point,
			width: width,
			onScreenIn: RevealScroll.Pane(
				size: scrollView.contentSize,
				offset: scrollView.contentView.bounds.origin,
				documentSize: frame.size,
				gutterWidth: gutterWidth,
				lineHeight: lineHeight,
				characterWidth: charWidth,
				wraps: isWordWrapEnabled
			)
		)
		switch answer {
		case .notLaidOut:
			pendingReveal = (offset, end)
		case .stay:
			pendingReveal = nil
		case let .scroll(to):
			pendingReveal = nil
			scrollView.contentView.scroll(to: to)
			scrollView.reflectScrolledClipView(scrollView.contentView)
		}
	}

	/// Brings a reveal that had nothing to measure against on screen, now that
	/// the pane has been given a size.
	///
	/// Called from `viewportChanged`, which is the clip view saying its frame
	/// changed — the event the reveal was waiting for, rather than a turn of the
	/// main loop it was hoping for.
	func drainPendingReveal() {
		guard let waiting = pendingReveal, !isDrainingReveal else { return }
		isDrainingReveal = true
		pendingReveal = nil
		// The rows are laid out for the size the pane has now, which is what the
		// answer is measured in.
		updateFrameSize()
		bringOnScreen(utf16: waiting.offset, extendingTo: waiting.end)
		isDrainingReveal = false
	}


	// MARK: - Selection helpers

	func selectedUTF16Range() -> Range<Int> {
		let lower = min(caret, selectionAnchor)
		let upper = max(caret, selectionAnchor)
		return lower..<upper
	}

	func setCaret(_ offset: Int, extendingSelection: Bool) {
		guard let document else { return }
		let clamped = max(0, min(offset, document.rope.utf16Count))
		caret = clamped
		if !extendingSelection { selectionAnchor = clamped }

		// A caret inside a collapsed region would be invisible.
		let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: clamped))
		if folding.isHidden(line: line) {
			folding.reveal(line: line)
			updateFrameSize()
		}

		restartCaretBlink()
		scrollCaretToVisible()
		needsDisplay = true
		reportCaretPosition()
	}

	/// Says where the caret is, for whatever is showing it.
	///
	/// Called on every move, and once more when a tab is brought to the front:
	/// the indicator is one control shared by every tab in the group, so a tab
	/// that never speaks up leaves the last one's line on display.
	func reportCaretPosition() {
		guard let document else { return }
		let byteOffset = document.rope.byteOffset(fromUTF16: caret)
		let line = document.rope.line(atByteOffset: byteOffset)
		let lineStart = document.rope.byteOffset(ofLine: line)
		let column = document.rope.utf16Offset(fromByte: byteOffset) - document.rope.utf16Offset(fromByte: lineStart)
		onCaretMoved?(line + 1, column + 1)
		selectionChanged()
	}

	/// The selection may have changed, so what was drawn about the old one goes.
	///
	/// Called from `reportCaretPosition`, which every path that moves the caret
	/// or extends a selection already goes through — drag included. That
	/// function's name is about the caret and this makes it also mean "the
	/// selection may have changed", which is worth saying out loud rather than
	/// leaving to be found.
	///
	/// The bands are dropped now rather than replaced later. Unlike the find
	/// matches after an edit, there is nothing here to carry across: the
	/// selection *is* the query, so the moment it changes every band is about a
	/// question nobody is asking, and the honest state until the scan answers is
	/// no bands at all.
	func selectionChanged() {
		occurrenceScan?.cancel()
		if !selectionOccurrences.isEmpty {
			selectionOccurrences = []
			occurrencesSelection = nil
			needsDisplay = true
		}

		// Find's matches win while find is showing: two kinds of band on one page
		// meaning two different things is worse than one kind meaning one, and
		// the one somebody asked for is find's.
		guard searchMatches.isEmpty, let document else { return }

		let selected = selectedUTF16Range()
		guard !selected.isEmpty else { return }
		let rope = document.rope
		let text = rope.string(in: rope.byteOffset(fromUTF16: selected.lowerBound)
			..< rope.byteOffset(fromUTF16: selected.upperBound))
		// Asked before anything is scheduled: a one-character selection, an
		// indent or a block spanning lines schedules nothing at all, which is
		// most of what a person selects while moving text about.
		guard SelectionOccurrences.isWorthHighlighting(text) else { return }

		// Debounced, so dragging a selection across a paragraph is one scan at
		// the end rather than one for every position the pointer passed through.
		let work = DispatchWorkItem { [weak self] in
			self?.findOccurrences(of: text, selected: selected)
		}
		occurrenceScan = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
	}

	private func findOccurrences(of text: String, selected: Range<Int>) {
		occurrenceScan = nil
		// The selection may have moved on while the debounce was waiting.
		guard let document, searchMatches.isEmpty, selectedUTF16Range() == selected else { return }

		let found = SelectionOccurrences.ranges(
			of: text, in: document.rope.string, excluding: selected
		)
		guard !found.isEmpty || !selectionOccurrences.isEmpty else { return }
		selectionOccurrences = found
		occurrencesSelection = selected
		needsDisplay = true
	}

	/// Selects the first place `text` appears, the way a person would drag over
	/// it, and leaves it selected.
	@discardableResult
	func selectTextForTesting(_ text: String) -> Bool {
		guard let document else { return false }
		let haystack = document.rope.string as NSString
		let hit = haystack.range(of: text, options: [.literal])
		guard hit.location != NSNotFound else { return false }
		selectionAnchor = hit.location
		caret = hit.location + hit.length
		needsDisplay = true
		// With the keyboard, because a person selecting text has it. The
		// selection is drawn in two colours and the unfocused one is the dimmer
		// of them — a shot taken without this compares the bands against a
		// selection nobody would be looking at.
		window?.makeFirstResponder(self)
		// Through the funnel a mouse or a key would go through, so what this
		// proves is the path and not a private shortcut into it.
		reportCaretPosition()
		return true
	}

	/// What is selected and what lit up because of it, offsets included.
	///
	/// The offsets are the claim: a count would be the same whether the bands
	/// were over the right characters or over the wrong ones.
	var occurrenceReportForTesting: String {
		let selected = selectedUTF16Range()
		let places = selectionOccurrences
			.prefix(8)
			.map { "\($0.lowerBound)..<\($0.upperBound)" }
			.joined(separator: ",")
		return "selected=\(selected.lowerBound)..<\(selected.upperBound)"
			+ " occurrences=\(selectionOccurrences.count) at=[\(places)]"
			+ " findMatches=\(searchMatches.count)"
	}

	func scrollCaretToVisible() {
		guard let point = caretPoint() else { return }
		let rect = NSRect(x: max(0, point.x - 40), y: point.y, width: 80, height: lineHeight)
		scrollToVisible(rect)
	}
}
