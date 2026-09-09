import AppKit
import AbydosKit

/// Where everything is: what a line's height is, where a character sits, and
/// how big the document is that the scroll view is looking at.
extension CodeView {
	// MARK: - Geometry

	var visibleLineCount: Int {
		guard let document else { return 1 }
		if isWordWrapEnabled { return wrapLayout.totalRows }
		return folding.visibleLineCount(documentLineCount: document.lineCount)
	}

	/// Columns of text that currently fit. Used when building the layout.
	private var availableColumns: Int? {
		guard isWordWrapEnabled else { return nil }
		let available = (enclosingScrollView?.contentSize.width ?? bounds.width)
			- gutterWidth - Self.textLeftPadding - Theme.current.scaled(16)
		return max(20, Int(available / max(1, charWidth)))
	}

	/// Columns the visible layout was built with.
	///
	/// Drawing reads this rather than measuring the viewport again. The two can
	/// differ for a moment after a resize, and disagreeing about the width means
	/// rows the layout allocated have no text to put in them — which is how a
	/// resized window ended up with blank gaps between wrapped lines.
	var wrapColumns: Int? {
		isWordWrapEnabled ? wrapLayout.columns : nil
	}

	/// Display width of a line in columns, expanding tabs.
	func displayColumns(ofLine line: Int) -> Int {
		guard let document else { return 0 }
		let text = document.rope.lineText(line)
		guard text.contains("\t") else { return (text as NSString).length }

		let tabWidth = Theme.current.tabWidth
		var columns = 0
		for character in text {
			if character == "\t" {
				columns += tabWidth - (columns % tabWidth)
			} else {
				columns += 1
			}
		}
		return columns
	}

	func rebuildWrapLayout() {
		guard let document, isWordWrapEnabled else { return }
		// Built from what fits now, not from what the last layout used, and
		// counted by the same walk that slices the rows.
		let columns = availableColumns
		let tabWidth = Theme.current.tabWidth

		// **Asked before any counting.** `updateFrameSize` calls this, and
		// `viewportChanged` calls that on both `frameDidChangeNotification` and
		// `boundsDidChangeNotification` — and the clip view's bounds move on
		// every scroll. So this ran on each scroll event and each frame of a
		// live resize, and at 68,608 lines it is 100 ms of main-thread work in
		// release. A scroll changes nothing the layout is built from.
		guard !wrapLayout.isCurrent(
			documentLineCount: document.lineCount,
			columns: columns,
			folding: folding,
			documentRevision: document.contentRevision
		) else { return }

		// One walk over the rope's chunks rather than a tree descent per line,
		// which is what `lineText` per line was: 68,608 descents, 92 ms in
		// release and twenty seconds in debug. `forEachLine` is the shape
		// `longestLineDisplayColumns` already uses for the same reason.
		var counts: [Int32] = []
		if let columns {
			counts.reserveCapacity(document.lineCount)
			document.rope.forEachLine { text in
				counts.append(
					Int32(WrapLayout.rowCount(in: text, columns: columns, tabWidth: tabWidth))
				)
			}
		}

		wrapLayout.rebuild(
			documentLineCount: document.lineCount,
			columns: columns,
			folding: folding,
			documentRevision: document.contentRevision
		) { line in
			line >= 0 && line < counts.count ? Int(counts[line]) : 1
		}
	}

	/// Document line for a visual row, honouring both folding and wrapping.
	func documentLine(forVisualRow row: Int) -> Int {
		if isWordWrapEnabled { return wrapLayout.position(forRow: row).line }
		return folding.documentLine(forVisualLine: row)
	}

	/// Which wrapped segment of its line a row shows.
	func wrapSegment(forVisualRow row: Int) -> Int {
		isWordWrapEnabled ? wrapLayout.position(forRow: row).segment : 0
	}

	func firstVisualRow(forDocumentLine line: Int) -> Int {
		if isWordWrapEnabled { return wrapLayout.firstRow(forLine: line) }
		return folding.visualLine(forDocumentLine: line)
	}

	/// Re-lays out after the pane's width changed.
	///
	/// Wrap width is derived from the viewport, so a window resize, a split or a
	/// divider drag changes how many columns fit. Without this the layout keeps
	/// the old width, and rows it allocated for a wider line have nothing left
	/// to show.
	func viewportChanged() {
		// A pane that has just been given its size is a pane a waiting reveal can
		// finally be measured against. Deferred to the end so it is decided
		// against the layout this call is about to fix rather than the one it
		// found.
		defer { drainPendingReveal() }

		if isWordWrapEnabled, availableColumns != wrapLayout.columns {
			updateFrameSize()
			needsDisplay = true
			return
		}

		// Nothing re-wrapped, but a viewport that grew taller than the document
		// leaves the view short of the space under the last line — which is
		// space a click has to land in.
		let wanted = frameHeight()
		guard abs(frame.height - wanted) > 0.5 else { return }
		setFrameSize(NSSize(width: frame.width, height: wanted))
	}

	/// Turns soft wrap on or off and re-lays out.
	func setWordWrap(_ enabled: Bool) {
		guard enabled != isWordWrapEnabled else { return }
		isWordWrapEnabled = enabled
		if enabled { rebuildWrapLayout() }
		updateFrameSize()
		needsDisplay = true
		scrollCaretToVisible()
	}

	func updateFrameSize() {
		guard let document else { return }
		let digits = max(2, String(document.lineCount).count)
		// The extra column on the left is the breakpoint gutter.
		gutterWidth = ceil(CGFloat(digits) * charWidth) + Self.gutterPadding * 2 + 14
			+ GutterMetrics.columnWidth(scale: Theme.current.scale) + Self.breakpointColumnWidth + blameWidth

		if isWordWrapEnabled { rebuildWrapLayout() }

		let height = frameHeight()
		let clipWidth = enclosingScrollView?.contentSize.width ?? bounds.width

		// Wrapped text never scrolls horizontally, so the document is exactly as
		// wide as the viewport.
		let width = isWordWrapEnabled
			? clipWidth
			: gutterWidth + Self.textLeftPadding + CGFloat(longestLineColumns) * charWidth + 40

		setFrameSize(NSSize(width: max(width, clipWidth), height: max(height, 10)))
	}

	/// How tall the view is: the text, or the viewport when the text is shorter.
	///
	/// A ten-line file left the view ten lines tall, and everything under it
	/// belonged to the scroll view — so clicking in the empty space below the
	/// last line reached nothing and the caret stayed where it was. Filling the
	/// viewport puts that space inside the text view, where a click lands on the
	/// last line, which is what it looks like it should do.
	private func frameHeight() -> CGFloat {
		let text = CGFloat(visibleLineCount) * lineHeight + lineHeight
		let viewport = enclosingScrollView?.contentSize.height ?? 0
		return max(text, viewport)
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		needsDisplay = true
	}

	/// Visual rows intersecting a rect, clamped to the document.
	func visualLineRange(in rect: NSRect) -> Range<Int> {
		let first = max(0, Int(floor(rect.minY / lineHeight)) - Self.overscanLines)
		let last = min(visibleLineCount, Int(ceil(rect.maxY / lineHeight)) + Self.overscanLines)
		guard last > first else { return 0..<0 }
		return first..<last
	}

	func yPosition(forVisualLine visual: Int) -> CGFloat {
		CGFloat(visual) * lineHeight
	}

	var textOriginX: CGFloat { gutterWidth + Self.textLeftPadding }
}
