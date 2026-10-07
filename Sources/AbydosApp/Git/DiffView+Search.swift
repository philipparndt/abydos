import AppKit
import AbydosKit

/// Finding text in a diff: which rows are searched, where the matches are
/// drawn, and how the one being looked at survives the rows being rebuilt.
///
/// **What counts as a match is `DiffSearch`'s**, in AbydosKit, where it is
/// tested without a window. What is decided here is which rows are handed to it
/// and how its answers are put back on the screen. The bar the query is typed
/// in belongs to whoever hosts the view — a scroll view's document view is the
/// wrong place for a strip that must not scroll away with the text.
///
/// **The search is held here, and re-run after every rebuild**, rather than
/// by each host after each thing it does. The rows are rebuilt by a new file, by
/// the whole-file switch, by a remark being written, by side by side being
/// flipped from the View menu, by a zoom — and a host remembering all five is a
/// host that forgets the sixth.
extension DiffView {
	/// One match: the row, the column it is drawn in, and where in that
	/// column's text.
	struct Match: Equatable {
		let row: Int
		let column: Column
		let range: Range<Int>
	}

	/// Where a line is in the files rather than in the rows — the one thing
	/// about it that a rebuild does not change.
	///
	/// **The new file's number where there is one**, so an unchanged line is
	/// the same place in either arrangement: unified it carries both numbers,
	/// side by side its right half carries the new one.
	struct Place: Equatable {
		let isOld: Bool
		let number: Int
	}

	/// What keeps a match current across a rebuild.
	struct MatchKey: Equatable {
		let place: Place
		let offset: Int
	}

	/// The first row's top, which the drawing and the scrolling agree on.
	var rowsTop: CGFloat { Theme.current.scaled(8) }

	// MARK: - Asking

	/// Searches for `text`, and makes the first match at or below the top of
	/// what is on screen current — so a search does not throw the reader back
	/// to the start of a long diff.
	func search(for text: String, options: SearchOptions) {
		searchQuery = (text, options)
		findMatches(keeping: nil, reveal: true)
	}

	/// Puts the search away: no query, no marks.
	func endSearch() {
		searchQuery = nil
		matches = []
		currentMatch = nil
		needsDisplay = true
		onMatchesChanged?()
	}

	/// The next match, or the one before, wrapping at either end as a file's
	/// search does.
	func stepMatch(by delta: Int) {
		guard !matches.isEmpty else { return }
		let from = currentMatch ?? (delta > 0 ? -1 : 0)
		currentMatch = ((from + delta) % matches.count + matches.count) % matches.count
		selectCurrentMatch(reveal: true)
		onMatchesChanged?()
	}

	/// The current match, said in terms a rebuild cannot change. Nil where the
	/// row it is on has no line number — which a code row always has.
	var currentMatchKey: MatchKey? {
		guard let currentMatch, matches.indices.contains(currentMatch) else { return nil }
		let match = matches[currentMatch]
		guard let place = place(ofRow: match.row, in: match.column) else { return nil }
		return MatchKey(place: place, offset: match.range.lowerBound)
	}

	/// Runs the query again over rows that have just been rebuilt.
	///
	/// - Parameters:
	///   - kept: the match that was current, when it is the same diff and it
	///     should stay current if it is still there.
	///   - reveal: whether to scroll the current match into view. Not for a
	///     remark being written: the reader has scrolled to where they are
	///     writing, and being taken back to a match is not what they asked for.
	func findMatches(keeping kept: MatchKey?, reveal: Bool) {
		guard let query = searchQuery else { return }
		let lines = searchableLines()
		let hits = DiffSearch.matches(in: lines.map(\.text), query: query.text, options: query.options)
		matches = hits.map { hit in
			let line = lines[hit.line]
			return Match(row: line.row, column: line.column, range: hit.utf16Range)
		}

		currentMatch = nil
		if let kept {
			currentMatch = matches.firstIndex { match in
				match.range.lowerBound == kept.offset
					&& place(ofRow: match.row, in: match.column) == kept.place
			}
		}
		if currentMatch == nil, !matches.isEmpty {
			let top = topVisibleRow
			currentMatch = matches.firstIndex { $0.row >= top } ?? 0
		}
		selectCurrentMatch(reveal: reveal)
		needsDisplay = true
		onMatchesChanged?()
	}

	/// The rows a search reads, and which column of each.
	///
	/// Code rows only: a hunk header, a scope rule, git's preamble and a remark
	/// are furniture, and an identifier found in somebody's paragraph takes the
	/// reader away from the code they were searching. **Side by side, the left
	/// half of an unchanged pair is left out**: it is the right half again, and
	/// counting it would make the same search say twice as much in one
	/// arrangement as in the other.
	func searchableLines() -> [(row: Int, column: Column, text: String)] {
		var lines: [(row: Int, column: Column, text: String)] = []
		for (index, row) in rows.enumerated() {
			switch row {
			case let .line(_, line, _, _):
				guard line.kind != .noNewline else { continue }
				lines.append((index, .only, line.text))
			case let .pair(left, right):
				if let left, right == nil || left.line.kind != .context {
					lines.append((index, .left, left.line.text))
				}
				if let right { lines.append((index, .right, right.line.text)) }
			default:
				continue
			}
		}
		return lines
	}

	// MARK: - Places

	/// Where a row's line is in the files, for the column asked about.
	func place(ofRow index: Int, in column: Column) -> Place? {
		guard rows.indices.contains(index) else { return nil }
		switch rows[index] {
		case let .line(_, _, old, new):
			if let new { return Place(isOld: false, number: new) }
			return old.map { Place(isOld: true, number: $0) }
		case let .pair(left, right):
			if column == .left { return left.map { Place(isOld: true, number: $0.number) } }
			if let right { return Place(isOld: false, number: right.number) }
			return left.map { Place(isOld: true, number: $0.number) }
		default:
			return nil
		}
	}

	/// The row on screen's top edge, by index.
	///
	/// **Clamped, and asked whether the rect is a number at all.** A driven run
	/// took the app down here: `Int(_:)` of a `Double` that is not finite traps,
	/// and a view between layouts can be asked for its visible rect and answer
	/// with one.
	var topVisibleRow: Int { row(atY: visibleRect.minY) }

	/// The row a y in the view falls on, clamped to the rows there are.
	func row(atY y: CGFloat) -> Int {
		guard lineHeight > 0, y.isFinite, !rows.isEmpty else { return 0 }
		let row = ((y - rowsTop) / lineHeight).rounded(.down)
		return Int(min(max(0, row), CGFloat(rows.count - 1)))
	}

	/// The place of the first code row at or below the top of the screen — what
	/// a switch of arrangement keeps where it was.
	func topPlace() -> Place? {
		guard !rows.isEmpty else { return nil }
		for index in min(topVisibleRow, rows.count - 1)..<rows.count {
			if let place = place(ofRow: index, in: .right) { return place }
		}
		return nil
	}

	/// Scrolls the row holding `place` to the top of the screen.
	func scrollToTop(_ place: Place) {
		let found = rows.indices.first { index in
			self.place(ofRow: index, in: .right) == place || self.place(ofRow: index, in: .left) == place
		}
		guard let found else { return }
		settleLayout()
		scroll(NSPoint(x: visibleRect.minX, y: rowsTop + CGFloat(found) * lineHeight))
	}

	/// The height the rows want, given to the scroll view now rather than at the
	/// next layout pass — a scroll to a row past the old height lands short of it.
	private func settleLayout() {
		enclosingScrollView?.layoutSubtreeIfNeeded()
	}

	// MARK: - Showing

	/// Selects the current match as text, so ⌘C copies it as `diff-selection`
	/// says, and scrolls its row into view if asked and it is not already there.
	private func selectCurrentMatch(reveal: Bool) {
		needsDisplay = true
		guard let currentMatch, matches.indices.contains(currentMatch) else { return }
		let match = matches[currentMatch]
		textRun.press(row: match.row, offset: match.range.lowerBound, in: match.column)
		textRun.extend(toRow: match.row, offset: match.range.upperBound)
		guard reveal else { return }
		// Sideways first, so a match off to the right of a long line is shown
		// and not only selected — the gap this view's find bar shipped with.
		revealSideways(
			from: textRun.x(ofOffset: match.range.lowerBound, row: match.row, in: match.column),
			to: textRun.x(ofOffset: match.range.upperBound, row: match.row, in: match.column),
			in: match.column
		)
		settleLayout()
		let rowRect = NSRect(
			x: visibleRect.minX,
			y: rowsTop + CGFloat(match.row) * lineHeight,
			width: 1,
			height: lineHeight
		)
		guard !visibleRect.contains(rowRect) else { return }
		// A little of what is around it, rather than the match against the
		// edge of the pane where the eye is not.
		scrollToVisible(rowRect.insetBy(dx: 0, dy: -lineHeight * 3))
	}

	/// Whether the current match's row is on screen.
	var currentMatchIsVisible: Bool {
		guard let currentMatch, matches.indices.contains(currentMatch) else { return false }
		let row = matches[currentMatch].row
		return row >= topVisibleRow && row <= self.row(atY: visibleRect.maxY)
	}

	/// Whether the text selection is exactly the current match — in which case
	/// the match's own mark says it, and the selection is not drawn over it.
	var selectionIsCurrentMatch: Bool {
		guard let currentMatch, matches.indices.contains(currentMatch), !textRun.isEmpty else { return false }
		let match = matches[currentMatch]
		return textRun.column == match.column
			&& textRun.start == DiffTextPoint(row: match.row, offset: match.range.lowerBound)
			&& textRun.end == DiffTextPoint(row: match.row, offset: match.range.upperBound)
	}

	/// The marks behind one row's glyphs in one column.
	///
	/// **Binary-searched by row**, because this runs for every row drawn and a
	/// search for `e` holds five thousand matches: a frame showing forty rows
	/// looks at the forty rows' matches and no others.
	func drawMatches(rowAt index: Int, in column: Column, at y: CGFloat) {
		guard !matches.isEmpty else { return }
		var low = 0
		var high = matches.count
		while low < high {
			let middle = (low + high) / 2
			if matches[middle].row < index { low = middle + 1 } else { high = middle }
		}
		var position = low
		while position < matches.count, matches[position].row == index {
			let match = matches[position]
			if match.column == column {
				let startX = textRun.x(ofOffset: match.range.lowerBound, row: index, in: column)
				let endX = textRun.x(ofOffset: match.range.upperBound, row: index, in: column)
				(position == currentMatch
					? Theme.current.searchMatchCurrentBackground
					: Theme.current.searchMatchBackground).setFill()
				NSRect(x: startX, y: y, width: max(1, endX - startX), height: lineHeight).fill()
			}
			position += 1
		}
	}

	// MARK: - Driving

	/// What the search says, for a driven run: the count, which is current, and
	/// where it is.
	var searchReportForTesting: String {
		guard let query = searchQuery else { return "no search" }
		var said = "query=\u{201C}\(query.text)\u{201D} matches=\(matches.count)"
		if let currentMatch, matches.indices.contains(currentMatch) {
			let match = matches[currentMatch]
			let place = self.place(ofRow: match.row, in: match.column)
			let text = (self.text(ofRow: match.row, in: match.column) as NSString)
				.substring(with: NSRange(location: match.range.lowerBound, length: match.range.count))
			said += " current=\(currentMatch + 1) row=\(match.row)\(match.column.said)"
				+ " \(place.map { ($0.isOld ? "old " : "new ") + "\($0.number)" } ?? "-")"
				+ " offset=\(match.range.lowerBound) text=\u{201C}\(text)\u{201D}"
		}
		said += " visible=\(topVisibleRow)-\(row(atY: visibleRect.maxY))"
		if !visibleRect.minY.isFinite || !visibleRect.maxY.isFinite {
			said += " rect=\(visibleRect) frame=\(frame)"
		}
		return said
	}
}
