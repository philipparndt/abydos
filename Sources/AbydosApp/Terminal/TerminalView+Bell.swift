import AppKit
import AbydosKit

/// The bell, and the frame the view is willing to hold back for.
///
/// Both are about *when* to draw rather than what: a bell flashes for a fixed
/// time whatever else happens, and a frame is held only so long before it is
/// drawn with whatever has arrived.
extension TerminalView {
	// MARK: - Bell


	/// How long the picture takes to settle again.
	///
	/// Long enough to read as a fault in the tape rather than a glitch in the
	/// app, short enough that a program which rings twice in a second does not
	/// leave the screen permanently swimming.
	private static let bellDuration: TimeInterval = 0.65

	func ringBell() {
		switch Settings.shared.terminalBellStyle {
		case "none":
			return
		case "vhs":
			// The visual bell is a shader. With the GPU renderer off there is
			// nothing to run it, so the beep stands in rather than the bell
			// doing nothing at all.
			guard metal != nil else {
				NSSound.beep()
				return
			}
			bellRangAt = Date()
			repaint()
		default:
			NSSound.beep()
		}
	}

	/// How much of the bell is left to show, and how long it has been going.
	func bellState() -> (strength: Float, elapsed: Float) {
		guard let bellRangAt else { return (0, 0) }
		let elapsed = -bellRangAt.timeIntervalSinceNow
		guard elapsed < Self.bellDuration else {
			self.bellRangAt = nil
			return (0, 0)
		}

		// Decays as a curve rather than a line: most of the movement happens
		// early, which is how a tape settles, and the last of it fades out
		// instead of stopping.
		let remaining = Float(1 - elapsed / Self.bellDuration)
		return (remaining * remaining, Float(elapsed))
	}

	/// Whether the picture is still moving and needs another frame.
	var isBellShowing: Bool { bellRangAt != nil }

	/// How long to believe a program that says it is mid-repaint.
	static let longestHeldFrame: TimeInterval = 0.1

	/// Draws what is on screen.
	func renderMetal() {
		guard let metal, !isPositioningMetalView else { return }
		metal.renderer.bell = bellState()
		let probing = MetalProbe.enabled
		positionMetalView()

		let visible = visibleRect
		guard visible.width >= 1, visible.height >= 1 else { return }

		let screen = emulator.grid
		let first = max(0, Int(floor((visible.minY - Self.verticalInset) / cellHeight)))
		let last = min(shownLineCount, Int(ceil((visible.maxY - Self.verticalInset) / cellHeight)) + 1)
		guard last > first else { return }

		var rows: [(index: Int, line: TerminalLine)] = []
		rows.reserveCapacity(last - first)
		for index in first..<last {
			guard let line = screen.line(at: index) else { continue }
			rows.append((index, line))
		}

		var overlays: [TerminalMetalRenderer.Overlay] = []
		if selection != nil {
			for index in first..<last {
				guard let line = screen.line(at: index),
				      let range = selectionRange(on: line, atRow: index)
				else { continue }
				overlays.append(.init(
					row: index,
					columns: range,
					colour: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35).components
				))
			}
		}
		metal.renderer.hoveredLink = hoveredLink.map { .init(row: $0.row, columns: $0.columns) }

		var cursor: TerminalMetalRenderer.Cursor?
		if let place = cursorPlace(), place.row < shownLineCount {
			cursor = .init(
				row: place.row,
				column: place.column,
				colour: TerminalPalette.cursor.components,
				shape: emulator.cursorShape,
				// Outlined when the keyboard is somewhere else: the cursor is
				// still where it was, and typing would not go there.
				isFilled: hasKeyboardFocus,
				thickness: Float(1.5)
			)
		}

			InputProbe.frame(
				cursor: cursor != nil,
				row: cursor?.row ?? -1,
				column: cursor?.column ?? -1
			)

		let background = TerminalPalette.background.components
		let buildStart = probing ? Date() : nil
		let frame = TerminalMetalRenderer.Frame(
			cellSize: CGSize(width: cellWidth, height: cellHeight),
			inset: CGPoint(x: Self.horizontalInset, y: Self.verticalInset),
			origin: visible.origin,
			background: background,
			foreground: TerminalPalette.foreground.components,
			discardedLineCount: screen.discardedLineCount
		)
		// Before the cells: what this decides about pictures behind the text is
		// what stops those cells painting over them.
		metal.renderer.buildImages(
			placements: emulator.graphics.placements.filter { $0.rowRange.overlaps(first..<last) }
				+ placeholderPlacements(from: first, to: last),
			store: emulator.graphics,
			frame: frame
		)
		metal.renderer.build(
			rows: rows,
			// Everything the engine has reported since the last frame, as line
			// numbers. Taken here rather than in `invalidateChangedRows`, which
			// runs several times per frame and only gathers.
			changed: dirtyRows.take(discardedLineCount: screen.discardedLineCount),
			frame: frame,
			faces: faces,
			overlays: overlays,
			cursor: cursor
		)

		if let buildStart { MetalProbe.buildSeconds += -buildStart.timeIntervalSinceNow }

		let drawableStart = probing ? Date() : nil
		guard let drawable = metal.view.nextDrawable() else { return }
		if let drawableStart { MetalProbe.drawableSeconds += -drawableStart.timeIntervalSinceNow }

		let encodeStart = probing ? Date() : nil
		metal.renderer.render(
			to: drawable.texture,
			clear: background,
			viewport: SIMD2(Float(visible.width), Float(visible.height)),
			drawable: drawable
		)
		if let encodeStart { MetalProbe.encodeSeconds += -encodeStart.timeIntervalSinceNow }
		MetalProbe.renders += 1
		MetalProbe.cells += metal.renderer.cellsBuilt
		MetalProbe.rows += metal.renderer.rowsBuilt
		MetalProbe.instances += metal.renderer.instanceCount
	}

	/// Repaints the lines that changed, rather than the whole view.
	///
	/// Marking the whole view means AppKit cannot keep any of what it already
	/// has, which matters most while output streams past: a printed line changes
	/// one row, and the rest can be scrolled rather than drawn again.
	func invalidateChangedRows() {
		pruneImageCache()
		if metal != nil {
			// Gathered rather than acted on. Output is parsed to a budget and
			// several batches of it arrive between two frames, so what the frame
			// needs is the union of what each of them changed — and the engine
			// hands its answer over once and forgets it.
			//
			// It used to be thrown away here, with a comment saying the GPU
			// redraws what is on screen and does not care how much of it
			// changed. That is true of the GPU and was never true of the work of
			// handing it the cells: item 0488 measured a quarter of a second per
			// second spent building 10,904 cells forty-three times, while the
			// GPU that received them idled at 9 ms.
			dirtyRows.note(emulator.takeDirtyRange())
			requestFrame()
			return
		}

		guard let range = emulator.takeDirtyRange() else {
			// The cursor may still have moved, which is a repaint of its own.
			invalidateCursorRows()
			return
		}

		// Beyond a certain share of the view, working out what to keep costs
		// more than painting it.
		let visibleRows = Int(ceil(visibleRect.height / max(1, cellHeight))) + 1
		guard range.count < max(4, visibleRows / 2) else {
			repaint()
			return
		}

		setNeedsDisplay(rect(forAbsoluteRows: range))
		invalidateCursorRows()
	}

	/// The cursor is drawn over a cell that is otherwise unchanged, so both the
	/// row it left and the row it is on have to be repainted.
	private func invalidateCursorRows() {
		let row = sizeAndHistory.scrollbackCount + emulator.cursorRow
		guard row != lastDrawnCursorRow else { return }
		if let previous = lastDrawnCursorRow {
			setNeedsDisplay(rect(forAbsoluteRows: previous...previous))
		}
		setNeedsDisplay(rect(forAbsoluteRows: row...row))
		lastDrawnCursorRow = row
	}

	private func rect(forAbsoluteRows range: ClosedRange<Int>) -> NSRect {
		let top = Self.verticalInset + CGFloat(range.lowerBound) * cellHeight
		let height = CGFloat(range.count) * cellHeight
		return NSRect(x: 0, y: top - 1, width: bounds.width, height: height + 2)
	}
}
