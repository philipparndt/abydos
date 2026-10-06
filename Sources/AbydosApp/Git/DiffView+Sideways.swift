import AppKit
import AbydosKit

/// Scrolling a diff's text sideways, a column at a time.
///
/// **The text moves and nothing else does.** A line wider than its column used
/// to run to the edge and stop — side by side, to the middle — so a change at
/// column 140 could not be read at all without checking the branch out. Each
/// text column now has an offset of its own, and `textOrigin(ofRow:in:)`
/// subtracts it; because drawing and `DiffTextRun`'s hit-testing both ask that
/// one number, the glyphs, their highlight, the find marks and a press all move
/// together, and the line numbers, the gutter and the row colours, which never
/// asked it, stay put. The number is how a reader says which line they are on,
/// and losing it to read the end of a line is the wrong trade.
///
/// **Not the scroll view's own horizontal scroller.** One offset for the whole
/// view would take the numbers with it and could not move the two halves
/// separately, which is the point of the link.
extension DiffView {
	/// The columns that can scroll in the arrangement on screen.
	var scrollingColumns: [Column] { isSideBySide ? [.left, .right] : [.only] }

	/// Whether the two halves move together — `Settings`, so a reader who
	/// unlinked them once does not do it again on every file.
	var halvesScrollTogether: Bool { Settings.shared.diffHalvesScrollTogether }

	// MARK: - Geometry

	/// Where a column's text area begins and ends, in the view.
	func textArea(of column: Column) -> ClosedRange<CGFloat> {
		let minX: CGFloat
		let maxX: CGFloat
		switch column {
		case .only:
			// The marker is one character of the code face, and the text starts
			// after it — the same place `textStart` puts a `.line` row's text.
			minX = textX + characterWidth
			maxX = bounds.width
		case .left, .right:
			minX = pairMinX(column) + Self.gutterWidth + numberWidth + Theme.current.scaled(6)
			maxX = column == .left ? pairMiddle - 1 : bounds.width
		}
		return minX...max(minX, maxX)
	}

	/// How much of a column's text can be seen at once. A character short of the
	/// edge, so the last character of the widest line is not flush against it.
	func visibleTextWidth(of column: Column) -> CGFloat {
		let area = textArea(of: column)
		return max(0, area.upperBound - area.lowerBound - characterWidth)
	}

	/// How far a column can scroll: as far as its widest line goes past it.
	func maxSidewaysOffset(of column: Column) -> CGFloat {
		max(0, (widestLines[column] ?? 0) - visibleTextWidth(of: column))
	}

	/// A column's offset, clamped on the way out — so a pane made wider, or a
	/// rebuild that took the long line away, never leaves the text scrolled past
	/// its end.
	func sidewaysOffset(of column: Column) -> CGFloat {
		min(max(0, sidewaysOffsets[column] ?? 0), maxSidewaysOffset(of: column))
	}

	// MARK: - Moving

	/// Puts a column at an offset, and — side by side and linked — the other
	/// half at the same one, each stopping at its own end.
	///
	/// **Linked means level**: both halves at one value, clamped separately, so
	/// scrolling the long side past the short one's end and back again brings
	/// them back together rather than leaving them a distance apart.
	func setSidewaysOffset(_ value: CGFloat, of column: Column) {
		lastScrolledColumn = column
		let wanted = min(max(0, value), maxSidewaysOffset(of: column))
		if isSideBySide, halvesScrollTogether, column != .only {
			for each in [Column.left, .right] {
				sidewaysOffsets[each] = min(wanted, maxSidewaysOffset(of: each))
			}
		} else {
			sidewaysOffsets[column] = wanted
		}
		needsDisplay = true
		sidewaysBar?.update()
	}

	func scrollSideways(by delta: CGFloat, column: Column) {
		setSidewaysOffset(sidewaysOffset(of: column) + delta, of: column)
	}

	/// Links or unlinks the halves. Linking levels the other half to the one
	/// scrolled last, so that linked is never two offsets apart.
	func setHalvesLinked(_ linked: Bool) {
		Settings.shared.diffHalvesScrollTogether = linked
		if linked, isSideBySide {
			setSidewaysOffset(sidewaysOffset(of: lastScrolledColumn), of: lastScrolledColumn)
		}
		sidewaysBar?.update()
	}

	/// Brings a range of a column's text into view sideways, with a few
	/// characters of margin, if it is not already — for the find bar's current
	/// match. Nothing moves for a range already in view.
	func revealSideways(from startX: CGFloat, to endX: CGFloat, in column: Column) {
		guard scrollingColumns.contains(column) else { return }
		let area = textArea(of: column)
		let margin = characterWidth * 4
		let offset = sidewaysOffset(of: column)
		if startX < area.lowerBound {
			setSidewaysOffset(offset - (area.lowerBound - startX) - margin, of: column)
		} else if endX > area.upperBound - characterWidth {
			setSidewaysOffset(offset + (endX - area.upperBound) + margin, of: column)
		}
	}

	// MARK: - The wheel

	/// A sideways swipe, or ⇧ and the wheel, scrolls the column under the
	/// pointer — both halves when linked; anything else is the scroll view's.
	///
	/// **Mostly vertical goes wholly to `super`**: a slightly diagonal swipe
	/// should read a page down, not drift sideways as it goes.
	override func scrollWheel(with event: NSEvent) {
		let dx = event.scrollingDeltaX
		guard abs(dx) > abs(event.scrollingDeltaY), dx != 0 else {
			return super.scrollWheel(with: event)
		}
		let point = convert(event.locationInWindow, from: nil)
		let column: Column = isSideBySide ? (point.x < pairMiddle ? .left : .right) : .only
		guard maxSidewaysOffset(of: column) > 0 else { return super.scrollWheel(with: event) }
		// A wheel's delta is in lines, a trackpad's in points.
		let points = event.hasPreciseScrollingDeltas ? dx : dx * characterWidth * 3
		scrollSideways(by: -points, column: column)
	}

	// MARK: - Measuring

	/// The widest line of each column, measured cheaply.
	///
	/// **Twenty measured, not every one.** Measuring each row is the 104 ms the
	/// `DiffTextRun` comment records for five thousand of them. The code face is
	/// monospace, so length ranks lines by width, and it is ranked in UTF-8
	/// bytes: a CJK character or an emoji is three or four bytes and about two
	/// columns, so it ranks at least as wide as it draws. Ranked by UTF-16 units
	/// instead, a line of sixty Chinese characters was sixty units and a hundred
	/// and twenty columns, lost to every hundred-character line of ASCII, and was
	/// never measured. A tab counts as one byte and draws as four columns, which
	/// is the one way a line can rank narrower than it is; measuring the twenty
	/// longest rather than the one is the margin for that.
	func measureWidestLines() {
		// One pass, keeping the longest twenty per column as it goes, ranked by
		// UTF-8 bytes — which a native string knows without walking it. Walking
		// every line's UTF-16 to weigh each unit was 10–17 ms over twenty
		// thousand rows, measured, for a ranking that only has to be roughly
		// right.
		var longest: [Column: [(text: String, units: Int)]] = [:]
		func consider(_ text: String, in column: Column) {
			let units = text.utf8.count
			var kept = longest[column, default: []]
			if kept.count == Self.measuredLongest {
				guard let shortest = kept.indices.min(by: { kept[$0].units < kept[$1].units }),
				      kept[shortest].units < units
				else { return }
				kept[shortest] = (text, units)
			} else {
				kept.append((text, units))
			}
			longest[column] = kept
		}
		for row in rows {
			switch row {
			case let .line(_, line, _, _):
				consider(line.text, in: .only)
			case let .pair(left, right):
				if let left { consider(left.line.text, in: .left) }
				if let right { consider(right.line.text, in: .right) }
			default:
				continue
			}
		}
		widestLines = longest.mapValues { kept in
			kept.map { NSAttributedString(string: $0.text, attributes: [.font: font]).size().width }.max() ?? 0
		}
		sidewaysBar?.update()
	}

	static let measuredLongest = 20

	// MARK: - The bar

	/// How much of the bottom the bar takes, which the rows make room for.
	var sidewaysBarHeight: CGFloat {
		guard let sidewaysBar, !sidewaysBar.isHidden else { return 0 }
		return sidewaysBar.frame.height
	}

	/// The bar goes into whichever scroll view the diff is put in, and comes out
	/// with it — a picture diff takes the scroll view's document view, and the
	/// bar must not stay behind over the picture.
	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
		guard let scroll = enclosingScrollView else {
			sidewaysBar?.removeFromSuperview()
			return
		}
		let bar = sidewaysBar ?? DiffSidewaysBar(diff: self)
		sidewaysBar = bar
		if bar.superview !== scroll { scroll.addSubview(bar) }
		bar.update()
	}

	override func layout() {
		super.layout()
		sidewaysBar?.update()
	}

	/// A double-click two characters in from the visible left edge of a column's
	/// text, found from the *point* as a press would find it — so a run can show
	/// that scrolled text is hit where it is drawn, not where it would be
	/// unscrolled.
	func doubleClickAtLeftEdgeForTesting(row: Int, column: Column) -> String {
		guard rows.indices.contains(row) else { return "no such row" }
		let x = textArea(of: column).lowerBound + characterWidth * 2.5
		let offset = self.offset(at: NSPoint(x: x, y: 0), ofRow: row, in: column)
		pressText(row: row, in: column, offset: offset, clicks: 2, shift: false)
		return "x=\(Int(x)) offset=\(offset) selected=\u{201C}\(copiedText ?? "")\u{201D}"
	}

	/// How long the widths take over the rows on screen, with the load beside
	/// it — a number without the load cannot be told from a regression.
	func measureTimingForTesting() -> String {
		let started = Date()
		measureWidestLines()
		let elapsed = Date().timeIntervalSince(started) * 1000
		var load = [Double](repeating: 0, count: 3)
		getloadavg(&load, 3)
		let cores = ProcessInfo.processInfo.activeProcessorCount
		return String(
			format: "%d rows measured in %.1f ms — load %.1f over %d cores (%.1f per core)",
			rows.count, elapsed, load[0], cores, load[0] / Double(cores)
		)
	}

	/// Every line of a column measured, which `measureWidestLines` declines to
	/// do — so a run can say whether the twenty it did measure found the widest.
	func exactWidestForTesting(_ column: Column) -> CGFloat {
		rows.compactMap { row -> String? in
			switch row {
			case let .line(_, line, _, _) where column == .only: return line.text
			case let .pair(left, _) where column == .left:       return left?.line.text
			case let .pair(_, right) where column == .right:     return right?.line.text
			default:                                             return nil
			}
		}.map { NSAttributedString(string: $0, attributes: [.font: font]).size().width }.max() ?? 0
	}

	/// For a driven run: each column's offset, widest line and room, and the
	/// bar's state.
	var sidewaysReportForTesting: String {
		let columns = scrollingColumns.map { column -> String in
			let name = column == .only ? "only" : (column == .left ? "left" : "right")
			return "\(name)=\(Int(sidewaysOffset(of: column)))/\(Int(maxSidewaysOffset(of: column)))"
				+ " widest=\(Int(widestLines[column] ?? 0)) exact=\(Int(exactWidestForTesting(column)))"
				+ " visible=\(Int(visibleTextWidth(of: column)))"
		}
		return columns.joined(separator: " ")
			+ " linked=\(halvesScrollTogether) last=\(lastScrolledColumn == .left ? "left" : "right")"
			+ " \(sidewaysBar?.reportForTesting ?? "no bar")"
	}
}
