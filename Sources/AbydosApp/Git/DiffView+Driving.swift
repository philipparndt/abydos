import AppKit
import AbydosKit

/// What a driven run can ask a diff, and say about it.
///
/// **A file of its own so that `DiffView.swift` is the diff and not the
/// harness**, which is the arrangement the window controller's driving verbs
/// already have. Two rules hold across everything here, and they are worth
/// stating once rather than at every function:
///
///  * **A gesture is the gesture the pointer makes.** A press goes through the
///    same `region(at:)` dispatch and the same `pressText`/`pressLine` a real
///    press runs, so what a run proves is the behaviour and not a second
///    implementation of it.
///  * **Nothing here writes the general pasteboard** except the one function
///    named for doing so. The clipboard belongs to whoever is using this
///    machine, and a capture that clobbered it on every report would take away
///    what they had copied.
extension DiffView {
	/// How much of a diff is on screen, for a driver that cannot photograph it.
	var reportForTesting: String {
		guard !rows.isEmpty else { return "empty" }
		let remarks = rows.filter {
			if case .comment(_, _, true) = $0 { return true }
			return false
		}.count
		return remarks == 0 ? "\(rows.count) rows" : "\(rows.count) rows, \(remarks) comments"
	}

	/// The conversation as it is drawn, for a run that cannot photograph it.
	func commentsForTesting() -> [String] {
		rows.compactMap { row in
			guard case let .comment(comment, text, isFirst) = row, isFirst else { return nil }
			return (comment.isOutdated ? "outdated: " : "at a line: ") + text
		}
	}

	/// Leaves a remark on a run of lines, for a driven run that has no pointer.
	func commentOnLinesForTesting(from: Int, to: Int) -> Bool {
		let available = Set(commentableLinesForTesting())
		guard available.contains(from), available.contains(to) else { return false }
		onCommentOnLines?(from, to)
		return true
	}

	/// Selects a run of lines the way a drag does, so a run can then ask the
	/// menu what it would offer.
	func selectLinesForTesting(from: Int, to: Int) {
		selection = []
		for row in rows {
			let place: (index: Int, number: Int)?
			switch row {
			case let .line(index, _, _, new): place = new.map { (index, $0) }
			case let .pair(_, right):         place = right.map { ($0.index, $0.number) }
			default:                          place = nil
			}
			guard let place, place.number >= from, place.number <= to else { continue }
			selection.insert(place.index)
		}
		selectedComment = nil
		// The last gesture wins, and this one is a drag down the numbers.
		textRun.clear()
		needsDisplay = true
	}

	/// What the menu over a selection would offer, and whether pressing it
	/// would reach anything.
	///
	/// **The second half is the claim.** The menu is built here for any diff
	/// that is not read-only, so its items appear whether or not the view has
	/// been told what to do with them — which is how the commit page came to
	/// offer "Stage Selected Lines" over its own diff and do nothing at all
	/// when it was pressed.
	func verbsForTesting() -> String {
		"readOnly=\(isReadOnly)"
			+ " apply=\(onApplySelection == nil ? "none" : "wired")"
			+ " discard=\(onDiscardSelection == nil ? "none" : "wired")"
			+ " stash=\(onStashSelection == nil ? "none" : "wired")"
	}

	/// Selects the first `count` lines that can be staged and applies them, the
	/// way the menu item does.
	func applyFirstLinesForTesting(_ count: Int) -> String {
		let selectable = patch.selectableIndices().prefix(count)
		guard !selectable.isEmpty else { return "nothing selectable" }
		setLineSelection(Set(selectable))
		guard onApplySelection != nil else { return "\(selectable.count) selected, nothing wired" }
		onApplySelection?(selection)
		return "\(selectable.count) selected, applied"
	}

	/// The remark the selection is on, if it is on one.
	func selectedCommentForTesting() -> String? {
		guard let comment = selectedComment?.comment else { return nil }
		return "\(comment.author) · \(comment.place)"
			+ (comment.isPending ? " · not sent" : "")
	}

	/// Selects a remark the way a click does, by the line it is on.
	@discardableResult
	func selectCommentForTesting(onLine line: Int) -> Bool {
		for (position, row) in rows.enumerated() {
			guard case let .comment(comment, _, isFirst) = row, isFirst, comment.line == line,
			      let block = commentBlock(startingAt: position)
			else { continue }
			selectComment(comment, rows: block)
			return true
		}
		return false
	}

	/// The line numbers a remark could be left on, so a run can name one.
	func commentableLinesForTesting() -> [Int] {
		rows.compactMap {
			switch $0 {
			case let .line(_, _, _, new): return new
			case let .pair(_, right):     return right?.number
			default:                      return nil
			}
		}
	}

	// MARK: - What a driven run can say about a selection

	/// What ⌘C would copy — read back rather than written out, because the
	/// general pasteboard belongs to whoever is using this machine and a run
	/// that clobbered it on every report would take away what they had copied.
	/// `copyToPasteboardForTesting` is the one thing that writes it.
	func copiedTextForTesting() -> String { copiedText ?? "nothing selected" }

	/// Presses ⌘C for real, for a step that asks for it by name.
	func copyToPasteboardForTesting() -> String {
		copy(nil)
		return copiedText ?? "nothing selected"
	}

	/// Where the text selection is: rows and offsets, so a run can see the drag
	/// land rather than only what it copied.
	func textSelectionForTesting() -> String { textRun.said }

	/// A press at a point in a row, through the same dispatch `mouseDown` runs:
	/// the numbers take lines, the code takes characters, and a hunk header
	/// takes its hunk. `x` is in points from the left edge of the view — the
	/// boundaries `regionsForTesting` prints.
	///
	/// **This is the claim the gesture moved**, and it is the one worth making
	/// through the real dispatch rather than around it.
	@discardableResult
	func pressAtForTesting(row: Int, x: Int, clicks: Int = 1, shift: Bool = false) -> String {
		guard rows.indices.contains(row) else { return "no such row" }
		let point = NSPoint(x: CGFloat(x), y: middleOfRow(row))
		switch region(at: point) {
		case .none:
			return "nothing there"
		case let .header(row):
			guard case let .hunkHeader(hunk, _) = rows[row] else { return "not a hunk header" }
			selectedComment = nil
			selectHunk(hunk)
			anchorRow = row
		case let .numbers(row, _):
			pressLine(row: row, shift: shift, command: false)
		case let .text(row, column):
			pressText(
				row: row,
				in: column,
				offset: offset(at: point, ofRow: row, in: column),
				clicks: clicks,
				shift: shift
			)
		}
		return selectionForTesting()
	}

	/// The rest of that gesture: the pointer, still down, at another point.
	@discardableResult
	func dragToForTesting(row: Int, x: Int) -> String {
		guard rows.indices.contains(row) else { return "no such row" }
		let point = NSPoint(x: CGFloat(x), y: middleOfRow(row))

		if textRun.isPressed {
			textRun.extend(
				toRow: row, offset: offset(at: point, ofRow: row, in: textRun.column)
			)
			if !textRun.isEmpty { selectedComment = nil }
			needsDisplay = true
			return selectionForTesting()
		}

		guard let anchor = anchorRow else { return "nothing pressed" }
		var updated: Set<Int> = []
		for position in min(anchor, row)...max(anchor, row) {
			if let index = lineIndex(atRow: position) { updated.insert(index) }
		}
		selection = updated
		needsDisplay = true
		return selectionForTesting()
	}

	/// The middle of a row, vertically, which is where a press lands.
	private func middleOfRow(_ row: Int) -> CGFloat {
		Theme.current.scaled(8) + CGFloat(row) * lineHeight + lineHeight / 2
	}

	/// What is selected now, whichever of the two it is — the answer every
	/// gesture step gives back, so a run can see that one selection put the
	/// other away.
	func selectionForTesting() -> String {
		if hasTextSelection { return "text " + textSelectionForTesting() }
		guard !selection.isEmpty else {
			return selectedComment == nil ? "nothing selected" : "a remark"
		}
		let numbers = selectedNewLines.map(String.init).joined(separator: ",")
		return "lines \(numbers.isEmpty ? "\(selection.count) of them" : numbers)"
	}

	/// A press on the code, through the same code a pointer's press runs.
	@discardableResult
	func pressTextForTesting(
		row: Int, offset: Int, clicks: Int = 1, shift: Bool = false, onLeft: Bool = false
	) -> String {
		guard rows.indices.contains(row) else { return "no such row" }
		let column: Column = onLeft ? .left : (isSideBySide ? .right : .only)
		pressText(row: row, in: column, offset: offset, clicks: clicks, shift: shift)
		return textSelectionForTesting()
	}

	/// The rest of the drag, likewise: the head moves and the half does not.
	@discardableResult
	func dragTextForTesting(row: Int, offset: Int) -> String {
		guard textRun.isPressed else { return "nothing pressed" }
		guard rows.indices.contains(row) else { return "no such row" }
		textRun.extend(
			toRow: row,
			offset: min(offset, text(ofRow: row, in: textRun.column).utf16.count)
		)
		if !textRun.isEmpty { selectedComment = nil }
		needsDisplay = true
		return textSelectionForTesting()
	}

	/// A drag from one place in the code to another, which is the whole gesture.
	@discardableResult
	func selectTextForTesting(
		fromRow: Int, offset from: Int, toRow: Int, offset to: Int, onLeft: Bool = false
	) -> String {
		let pressed = pressTextForTesting(row: fromRow, offset: from, onLeft: onLeft)
		guard pressed != "no such row" else { return pressed }
		return dragTextForTesting(row: toRow, offset: to)
	}

	/// A double-click and a triple-click, without a pointer.
	func selectWordForTesting(row: Int, offset: Int) -> String {
		pressTextForTesting(row: row, offset: offset, clicks: 2)
	}

	func selectRowTextForTesting(row: Int) -> String {
		pressTextForTesting(row: row, offset: 0, clicks: 3)
	}

	/// What the view says a point is over, probed either side of every boundary
	/// the drawing uses — so a run can *see* the boundaries rather than trust
	/// them.
	func regionsForTesting(row: Int) -> String {
		guard rows.indices.contains(row) else { return "no such row" }
		let y = Theme.current.scaled(8) + CGFloat(row) * lineHeight + lineHeight / 2
		var probes: [CGFloat] = [2, textX - 2, textX + 2]
		if isSideBySide {
			probes += [pairMiddle - 2, pairMiddle + 2]
			for column in [Column.left, .right] {
				let origin = textOrigin(ofRow: row, in: column)
				probes += [pairMinX(column) + 2, origin - 2, origin + 2]
			}
		}
		return probes.sorted().map { x in
			"x=\(Int(x.rounded())) \(said(region(at: NSPoint(x: x, y: y))))"
		}.joined(separator: " ")
	}

	/// Every row, numbered, as `text(ofRow:in:)` gives it — which is how a run
	/// names a row in a `text:` step, and how it can see that what was copied is
	/// what was drawn.
	///
	/// Side by side, both halves of a row, because a selection belongs to one of
	/// them.
	func rowTextsForTesting(_ limit: Int = 40) -> String {
		guard !rows.isEmpty else { return "empty" }
		let said = rows.indices.prefix(limit).map { index -> String in
			guard isSideBySide, case .pair = rows[index] else {
				return "\(index): \(text(ofRow: index))"
			}
			return "\(index): left |\(text(ofRow: index, in: .left))|"
				+ " right |\(text(ofRow: index, in: .right))|"
		}.joined(separator: "\n")
		guard rows.count > limit else { return said }
		return said + "\n… and \(rows.count - limit) more rows not printed"
	}

	/// What the menu over the diff holds over whatever is selected, in order —
	/// which is how a run sees *Copy* at the top of it.
	func menuTitlesForTesting() -> String {
		guard let menu = menu(atRow: nil) else { return "no menu" }
		return menu.items.map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: ", ")
	}

	/// ⌘A, and what it selected.
	func selectAllTextForTesting() -> String {
		selectAll(nil)
		return textSelectionForTesting()
	}

	/// A drag down the whole diff, and a draw of the same rows — the two costs
	/// this change has to keep in proportion, with the load beside them.
	///
	/// **A number without the load beside it cannot be told from a regression**,
	/// which is why `LaunchClock.loadSaid` is in the same sentence. Nothing here
	/// asserts a bound: a driven run is not the place for one (see `Stopwatch`
	/// and `make timing`), and what this answers is whether selecting a diff
	/// costs the same order as scrolling it.
	///
	/// The drag is the pointer's own path — a point per row, hit-tested through
	/// Core Text, which is what fills the measured-row cache. The draw is the
	/// view drawing every row into a bitmap, a band at a time, which is what
	/// scrolling from top to bottom does.
	func timingForTesting() -> String {
		guard !rows.isEmpty else { return "empty" }
		let column: Column = isSideBySide ? .right : .only
		let x = textOrigin(ofRow: 0, in: column) + characterWidth * 20
		let top = Theme.current.scaled(8)

		textRun.forget()
		let draggedFrom = Date()
		pressText(row: 0, in: column, offset: 0, clicks: 1, shift: false)
		for row in rows.indices {
			let point = NSPoint(x: x, y: top + CGFloat(row) * lineHeight + lineHeight / 2)
			guard let hit = clampedRow(at: point) else { continue }
			textRun.extend(toRow: hit, offset: offset(at: point, ofRow: hit, in: textRun.column))
		}
		let dragged = Date().timeIntervalSince(draggedFrom)
		let measured = textRun.measuredRows

		let copiedFrom = Date()
		let copied = copiedText?.utf16.count ?? 0
		let copying = Date().timeIntervalSince(copiedFrom)

		// A band at a time, top to bottom: the frames a scroll of the whole
		// diff asks for.
		let band = lineHeight * 40
		let drawnFrom = Date()
		var y: CGFloat = 0
		while y < CGFloat(rows.count) * lineHeight {
			let rect = NSRect(x: 0, y: y, width: max(1, bounds.width), height: band)
			if let bitmap = bitmapImageRepForCachingDisplay(in: rect) {
				cacheDisplay(in: rect, to: bitmap)
			}
			y += band
		}
		let drawn = Date().timeIntervalSince(drawnFrom)

		func said(_ seconds: TimeInterval) -> String { String(format: "%.0f ms", seconds * 1000) }
		return "\(rows.count) rows: dragged over them in \(said(dragged))"
			+ " (\(measured) rows measured), drew them in \(said(drawn))"
			+ ", copied \(copied) characters in \(said(copying)) — \(LaunchClock.loadSaid)"
	}

	/// How many rows have been measured, so a run can watch the cache empty
	/// when the rows are rebuilt.
	var measuredRowsForTesting: Int { textRun.measuredRows }

	private func said(_ region: Region) -> String {
		switch region {
		case let .numbers(row, column): return "numbers(row \(row)\(column.said))"
		case let .text(row, column):    return "text(row \(row)\(column.said))"
		case let .header(row):          return "header(row \(row))"
		case .none:                     return "nothing"
		}
	}
}
