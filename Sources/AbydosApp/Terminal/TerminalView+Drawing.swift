import AppKit
import AbydosKit

/// Drawing the grid: the metrics a frame is laid out on, and the drawing
/// itself.
///
/// The hot path of this app. Everything here is called sixty times a second
/// over every cell on screen, which is why it is written the way it is and why
/// it is worth having on its own.
extension TerminalView {
	// MARK: - Metrics

	/// Logged once, so "which font is it actually using?" has a definite answer.
	private static var didLogFont = false

	func updateMetrics() {
		font = Theme.terminalFont(size: Theme.current.fontSize)
		if !Self.didLogFont {
			Self.didLogFont = true
			FileHandle.standardError.write(Data("Abydos terminal font: \(font.fontName)\n".utf8))
		}

		// Cell metrics are rounded to whole points.
		//
		// A fractional advance accumulates across a row, so run backgrounds land
		// on sub-pixel boundaries and leave hairline seams between them — visible
		// as a step where a powerline separator meets the next segment. Whole-point
		// cells make neighbouring fills abut exactly.
		faces = TerminalFaces(base: font)
		glyphs.clear()
		let advance = faces.advance
		cellWidth = max(1, advance.rounded())
		cellHeight = max(1, (font.ascender - font.descender + font.leading).rounded() + 2)
		baselineOffset = (-font.descender + font.leading).rounded()
		// Where NSAttributedString would have put the baseline had it laid the
		// line out itself, which is what the glyphs have to line up with.
		baselineFromTop = (font.ascender + font.leading).rounded()
		updateCellPixelSize()
	}

	/// Tells the emulator and the process how large a cell is, in real pixels.
	///
	/// Pixels rather than points, and so scaled by the display. A program sizing
	/// a picture to the cell grid is sizing it to what will actually be shown,
	/// and reporting points on a Retina screen asks it for an image at half the
	/// resolution the screen can draw — which is the difference between a sharp
	/// picture and a soft one.
	///
	/// The screen when there is no window yet, rather than a flat two. Cells are
	/// measured before the view is in a window — the font is known long before
	/// anything is on screen — and assuming Retina there is a lie on a display
	/// that is not one: the pane told its program a cell was 16×38 where it is
	/// 8×19, and kitty's `icat`, which sizes a picture from exactly this, asked
	/// for half the cells it needed. The picture then changed size the moment
	/// anything resized the pane and the true number went out.
	/// A scale of zero is skipped rather than believed — see `CellPixelSize`,
	/// which is where that decision and its consequences are written down.
	func updateCellPixelSize() {
		let size = CellPixelSize.pixels(
			cellWidth: Double(cellWidth),
			cellHeight: Double(cellHeight),
			scales: [
				window.map { Double($0.backingScaleFactor) },
				window?.screen.map { Double($0.backingScaleFactor) },
				NSScreen.main.map { Double($0.backingScaleFactor) },
				// A machine with no display at all, which is where 0397 left the
				// flat two: the last resort rather than the first answer.
				2,
			]
		)
		guard let size else { return }
		emulator.cellPixelSize = size
		pty.cellPixelSize = size
	}

	func applyThemeChange() {
		updateMetrics()
		layer?.backgroundColor = TerminalPalette.background.cgColor
		enclosingScrollView?.backgroundColor = TerminalPalette.background
		metal?.renderer.clearGlyphs()
		updateMetalEnabled()
		recomputeGridSize()
		repaint()
	}

	/// How many rows of the grid this pane actually shows.
	///
	/// Everything that walks rows — both renderers, the selection, the mouse,
	/// the document height — goes through this one definition rather than
	/// through the screen's own count.
	var shownLineCount: Int { sizeAndHistory.totalLineCount }

	/// How big the terminal is and how much history it has — **not a snapshot**.
	///
	/// Everything on this side of the seam that wants a count rather than a row goes
	/// through here, because the alternative is what item 0492 was: `emulator.grid`,
	/// asked once per delivery of output, copying eleven thousand cells out of
	/// libghostty-vt to read one integer. For our own engine the two are the same
	/// five field reads.
	///
	/// The environment variable is `TerminalCatchUp`'s, and it is here so that the
	/// before and the after can be measured out of one binary rather than two.
	var sizeAndHistory: TerminalMetrics {
		guard TerminalCatchUp.perWrite else { return emulator.metrics }
		let grid = emulator.grid
		return TerminalMetrics(
			rows: grid.rows, columns: grid.columns,
			totalLineCount: grid.totalLineCount,
			scrollbackCount: grid.scrollbackCount,
			discardedLineCount: grid.discardedLineCount)
	}

	/// How much of the pane's height is not a whole row.
	///
	/// Always less than one row, and usually a point or two — which is why it
	/// went unnoticed at 1×. Scaling multiplies it: a four-point sliver becomes
	/// eight at 2×, which is enough of a line to read as a broken one against
	/// the top of the viewport. Reported so the panel can give it back rather
	/// than show it.
	var heightRemainder: CGFloat {
		guard let clip = enclosingScrollView?.contentView else { return 0 }
		let usable = clip.bounds.height - Self.verticalInset * 2
		guard usable > 0, cellHeight > 0 else { return 0 }
		return usable - floor(usable / cellHeight) * cellHeight
	}

	/// Keeps the grid the size of the pane, whatever else happened.
	///
	/// Everything that changes the pane's size or the size of a cell already
	/// asks for this, and a missed one is invisible until somebody types: the
	/// grid stays as wide as the pane used to be, the program is told the same,
	/// and every line then runs off the right-hand edge instead of wrapping —
	/// while the program's own idea of the text stays perfectly correct, so
	/// pressing return shows it laid out properly and nothing looks broken
	/// afterwards. Checking here costs a comparison per layout pass and repairs
	/// it whatever the cause was.
	override func layout() {
		super.layout()
		recomputeGridSize()
	}

	/// Derives rows and columns from the pane size and tells both the emulator
	/// and the process.
	func recomputeGridSize() {
		guard let clip = enclosingScrollView?.contentView else { return }
		// Nothing to measure yet, so nothing is decided. A tab made without being
		// brought to the front is not laid out until somebody reveals it, and a
		// pane of no width answers the floor of `max(20, …)` — twenty columns.
		//
		// Harmless for a shell, which is told its size when it starts and is not
		// running before that. Permanent for a pane that is *written into* while
		// it is hidden, because scrollback does not reflow: 0459 photographed
		// four hundred lines of a build wrapped into a twenty-character column
		// down the left of a pane that was full width by the time anybody saw it.
		// Keeping the eighty columns it was made with is both wider and more
		// honest — eighty is a width, and twenty was a measurement of a view that
		// is not on screen.
		guard clip.bounds.width > 1, clip.bounds.height > 1 else { return }
		let usableWidth = clip.bounds.width - Self.horizontalInset * 2
		let usableHeight = clip.bounds.height - Self.verticalInset * 2

		let columns = max(20, Int(floor(usableWidth / max(1, cellWidth))))
		let rows = max(4, Int(floor(usableHeight / max(1, cellHeight))))

		// Recorded for whatever pane opens next, which may start its process
		// before it is ever laid out. Before the early return below, not after:
		// a size that has not changed is still a size that was measured, and for
		// a pane that was born at the right width that is the only place it is
		// ever learnt.
		Self.lastMeasuredGrid = (rows: rows, columns: columns)

		let size = sizeAndHistory
		guard rows != size.rows || columns != size.columns else { return }
		// A resize reflows what the absolute rows mean, and there is no honest
		// mapping from the old grid to the new one.
		setSelection(nil)
		emulator.resize(rows: rows, columns: columns)
		pty.resize(rows: rows, columns: columns)
		updateFrameSize()
	}

	func updateFrameSize() {
		// `sizeAndHistory` rather than `emulator.grid`, and it matters: this runs once
		// per turn of the main queue while output pours in, and for libghostty-vt a
		// snapshot means copying every visible cell across the FFI boundary (0492).
		let size = sizeAndHistory
		let totalRows = emulator.isAlternateScreen ? size.rows : size.totalLineCount
		let height = CGFloat(totalRows) * cellHeight + Self.verticalInset * 2
		let width = enclosingScrollView?.contentSize.width ?? bounds.width
		let newSize = NSSize(width: max(width, 10), height: max(height, 10))
		if abs(newSize.height - frame.height) > 0.5 || abs(newSize.width - frame.width) > 0.5 {
			setFrameSize(newSize)
		}
	}

	/// Puts the view at the top of the document, where the alternate screen is.
	func scrollToTop() {
		guard let scrollView = enclosingScrollView, scrollView.contentView.bounds.origin.y != 0
		else { return }
		scrollView.contentView.scroll(to: .zero)
		scrollView.reflectScrolledClipView(scrollView.contentView)
	}

	func scrollToBottom() {
		guard let scrollView = enclosingScrollView else { return }
		let maxY = max(0, frame.height - scrollView.contentSize.height)
		scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
		scrollView.reflectScrolledClipView(scrollView.contentView)
	}

	/// Called by the container when the clip view's bounds change.
	func viewportChanged() {
		guard let scrollView = enclosingScrollView else {
			recomputeGridSize()
			return
		}

		// Decided before the grid changes, not after. A resize moves the bottom
		// of the document, so comparing the old offset against the new maximum
		// unpins a view that was following the output — leaving the prompt off
		// screen with stale lines showing in its place.
		let offset = scrollView.contentView.bounds.origin.y
		let maxY = max(0, frame.height - scrollView.contentSize.height)
		isPinnedToBottom = offset >= maxY - cellHeight

		recomputeGridSize()
		if metal != nil { needsRender = true }

		if isPinnedToBottom { scrollToBottom() }
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		StallWatch.mark("terminal draw") { drawMarked(dirtyRect) }
	}

	private func drawMarked(_ dirtyRect: NSRect) {
		defer { if metal == nil { noteKeystrokeShown() } }
		TerminalPalette.background.setFill()
		dirtyRect.fill()

		let screen = emulator.grid
		let firstRow = max(0, Int(floor((dirtyRect.minY - Self.verticalInset) / cellHeight)))
		let lastRow = min(shownLineCount, Int(ceil((dirtyRect.maxY - Self.verticalInset) / cellHeight)) + 1)
		guard lastRow > firstRow else { return }

		// A picture below the text is drawn first so the characters land on top of
		// it; one above covers them. That is what the z key means, and it is the
		// only ordering the protocol asks for.
		drawImages(from: firstRow, to: lastRow, above: false)

		for index in firstRow..<lastRow {
			guard let line = screen.line(at: index) else { continue }
			draw(line: line, atRow: index)
		}

		drawImages(from: firstRow, to: lastRow, above: true)

		drawCursor()
		drawDropHighlight()
	}

	/// Draws the pictures whose rows fall in the band being repainted.
	private func drawImages(from firstRow: Int, to lastRow: Int, above: Bool) {
		let placements = emulator.graphics.placements + placeholderPlacements(from: firstRow, to: lastRow)
		guard !placements.isEmpty else { return }
		guard let context = NSGraphicsContext.current?.cgContext else { return }

		// Sorted so overlapping pictures stack the way the program asked, and
		// equal depths keep the order they were placed in.
		let shown = placements
			.filter { (above ? $0.z >= 0 : $0.z < 0) && $0.rowRange.overlaps(firstRow..<lastRow) }
			.sorted { $0.z < $1.z }
		guard !shown.isEmpty else { return }

		context.saveGState()
		// A picture is placed on a cell grid, so it is almost always being scaled
		// by some fraction to reach a whole number of cells. Left to the default
		// that scaling stair-steps every edge.
		context.interpolationQuality = .high
		for placement in shown {
			guard let image = cachedImage(for: placement.imageID),
			      let cropped = crop(image, to: placement.source)
			else { continue }

			// Turned over inside its own box: this view counts rows from the
			// top, and CoreGraphics draws a picture up from the bottom, so
			// without this every image comes out upside down. The Metal
			// renderer has its own orientation and gets it right, which is why
			// it showed in screenshots and not on screen.
			let box = rect(for: placement)
			context.saveGState()
			context.translateBy(x: 0, y: box.midY)
			context.scaleBy(x: 1, y: -1)
			context.translateBy(x: 0, y: -box.midY)
			context.draw(cropped, in: box)
			context.restoreGState()
		}
		context.restoreGState()
	}

	/// The pictures spelled out by placeholder characters on the rows being
	/// repainted.
	///
	/// Worked out from the grid every time rather than remembered, which is the
	/// point of the whole mechanism: the cells are ordinary text, so whatever
	/// moved them — scrolling, tmux redrawing its pane, a narrower window —
	/// has already moved the picture, and reading where they are now is reading
	/// where the picture is now.
	func placeholderPlacements(from firstRow: Int, to lastRow: Int) -> [TerminalImagePlacement] {
		guard emulator.graphics.hasVirtualPlacements else { return [] }
		var runs: [UnicodePlaceholder.Run] = []
		for index in firstRow..<lastRow {
			guard let line = emulator.grid.line(at: index) else { continue }
			runs += UnicodePlaceholder.runs(in: line.cells, screenRow: index)
		}
		guard !runs.isEmpty else { return [] }
		return emulator.graphics.placements(for: runs)
	}

	/// Where on the view a placement goes.
	private func rect(for placement: TerminalImagePlacement) -> NSRect {
		let scale = window?.backingScaleFactor ?? 2
		let x = Self.horizontalInset + CGFloat(placement.column) * cellWidth
			+ CGFloat(placement.offsetX) / scale
		let y = Self.verticalInset + CGFloat(placement.row) * cellHeight
			+ CGFloat(placement.offsetY) / scale
		return NSRect(
			x: x.rounded(),
			y: y.rounded(),
			width: (CGFloat(placement.columns) * cellWidth).rounded(),
			height: (CGFloat(placement.rows) * cellHeight).rounded()
		)
	}

	/// The image behind an id, built once and kept.
	///
	/// Turning a few megabytes of pixels into a `CGImage` on every repaint would
	/// cost more than everything else the terminal draws put together, and a
	/// picture on screen is repainted whenever anything near it changes.
	private func cachedImage(for id: UInt32) -> CGImage? {
		if let cached = imageCache[id] { return cached }
		guard let image = emulator.graphics.images[id] else { return nil }

		guard let provider = CGDataProvider(data: Data(image.pixels) as CFData) else { return nil }

		let built = CGImage(
			width: image.width,
			height: image.height,
			bitsPerComponent: 8,
			bitsPerPixel: 32,
			bytesPerRow: image.width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
			provider: provider,
			decode: nil,
			shouldInterpolate: true,
			intent: .defaultIntent
		)
		imageCache[id] = built
		return built
	}

	/// The part of an image a placement shows, or the whole of it.
	private func crop(_ image: CGImage, to source: TerminalImagePlacement.Rectangle) -> CGImage? {
		guard source.x != 0 || source.y != 0
			|| source.width != image.width || source.height != image.height
		else { return image }
		return image.cropping(to: CGRect(
			x: source.x, y: source.y, width: source.width, height: source.height
		))
	}

	/// Drops cached images the emulator no longer holds.
	func pruneImageCache() {
		guard emulator.graphics.generation != lastGraphicsGeneration else { return }
		lastGraphicsGeneration = emulator.graphics.generation
		let live = emulator.graphics.images
		imageCache = imageCache.filter { live[$0.key] != nil }
	}

	/// Draws one row, batching neighbouring cells that share attributes.
	private func draw(line: TerminalLine, atRow index: Int) {
		let y = (Self.verticalInset + CGFloat(index) * cellHeight).rounded()

		var column = 0
		while column < line.cells.count {
			let attributes = line.cells[column].attributes

			// Extend the run while attributes match.
			var end = column + 1
			while end < line.cells.count, line.cells[end].attributes == attributes {
				end += 1
			}

			let x = (Self.horizontalInset + CGFloat(column) * cellWidth).rounded()
			// Computed from the run's end rather than its length, so consecutive
			// runs share an edge exactly instead of each rounding independently.
			let endX = (Self.horizontalInset + CGFloat(end) * cellWidth).rounded()
			let resolved = attributes.resolved

			// **`isForeground` follows the swap, and that is the whole of the
			// inverse fix.** `resolved` puts the foreground in the background
			// slot for an inverse cell, so a `.default` sitting there means the
			// default *foreground* — asking for it as a background gave back the
			// background colour, which is what made `\u{1B}[7m` with no colours
			// set draw exactly like plain text. Prompts, `less` and `man` all
			// ask for it that way.
			let background = TerminalPalette.color(
				for: resolved.background, isForeground: attributes.inverse, bold: false
			)
			if resolved.background != .default || attributes.inverse {
				background.setFill()
				NSRect(x: x, y: y.rounded(), width: endX - x, height: cellHeight).fill()
			}

			// Separators are filled shapes in the run's foreground colour, sized to
			// the cell exactly — which is what removes the seam and the height
			// mismatch a font glyph leaves behind. Hidden means hidden, so they
			// are skipped along with the text.
			if !attributes.hidden {
				drawSeparators(of: line, from: column, to: end, attributes: attributes, y: y)
				drawText(of: line, from: column, to: end, attributes: attributes, y: y)
			}

			column = end
		}

		drawSelection(on: line, atRow: index, y: y)
	}

	/// A border while files are held over the view, so the drop has a target.
	private func drawDropHighlight() {
		guard isDropTarget else { return }
		let outline = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
		outline.lineWidth = 2
		Theme.current.gitModified.setStroke()
		outline.stroke()
	}

	/// The columns a row is highlighted across, or nil when it is not selected.
	///
	/// **One place, asked by both renderers.** The Core Text path draws a rect
	/// from it and the Metal path builds an overlay from it, and two copies of
	/// this expression would disagree first on exactly the rows this is about —
	/// the short ones, where the answer changed from the width of the grid to
	/// the width of the text.
	func selectionRange(on line: TerminalLine, atRow index: Int) -> Range<Int>? {
		selection?.columnRange(onRow: index, columns: line.usedColumns)
	}

	/// Tints the selected cells.
	///
	/// Drawn over the text rather than behind it, so the characters keep their
	/// own colours — a terminal's palette carries meaning, and repainting a
	/// selected region in system selection colours would throw that away.
	private func drawSelection(on line: TerminalLine, atRow index: Int, y: CGFloat) {
		guard let range = selectionRange(on: line, atRow: index) else { return }

		let x = (Self.horizontalInset + CGFloat(range.lowerBound) * cellWidth).rounded()
		let endX = (Self.horizontalInset + CGFloat(range.upperBound) * cellWidth).rounded()

		NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35).setFill()
		NSRect(x: x, y: y.rounded(), width: endX - x, height: cellHeight).fill()
	}

	/// Draws the powerline separators in a run as geometry filling their cells.
	private func drawSeparators(
		of line: TerminalLine,
		from start: Int,
		to end: Int,
		attributes: TerminalAttributes,
		y: CGFloat
	) {
		let colour = TerminalPalette.color(
			for: attributes.resolved.foreground,
			isForeground: true,
			bold: attributes.bold
		)

		for cellIndex in start..<end {
			let scalar = line.cells[cellIndex].scalar
			guard PowerlineGlyph.isSeparator(scalar) else { continue }

			let cellX = (Self.horizontalInset + CGFloat(cellIndex) * cellWidth).rounded()
			let cellEnd = (Self.horizontalInset + CGFloat(cellIndex + 1) * cellWidth).rounded()
			PowerlineGlyph.draw(
				scalar: scalar,
				in: NSRect(x: cellX, y: y.rounded(), width: cellEnd - cellX, height: cellHeight),
				color: colour
			)
		}
	}

	/// Draws one attribute run's characters, each on its own grid column.
	///
	/// Split into segments rather than drawn as one string. The cell width is a
	/// whole number of points so run backgrounds abut exactly, but the font's
	/// own advance is fractional — letting it lay out a whole run makes the text
	/// creep away from the grid by a fraction of a pixel per character, which
	/// reaches a full cell by the time a prompt and a command have been typed.
	/// The cursor is drawn on the grid, so the text ends up sitting a character
	/// away from it.
	private func drawText(
		of line: TerminalLine,
		from start: Int,
		to end: Int,
		attributes: TerminalAttributes,
		y: CGFloat
	) {
		let faceIndex = TerminalFaces.index(bold: attributes.bold, italic: attributes.italic)
		let drawFont = faces.face(bold: attributes.bold, italic: attributes.italic)

		let resolved = attributes.resolved
		var foreground = TerminalPalette.color(
			for: resolved.foreground,
			isForeground: true,
			bold: attributes.bold
		)
		if attributes.dim { foreground = foreground.withAlphaComponent(TerminalPalette.dimAmount) }

		guard let context = NSGraphicsContext.current?.cgContext else { return }
		context.saveGState()
		// The view is flipped, so the glyphs would come out upside down without
		// undoing that for the text alone.
		context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
		context.setFillColor(foreground.cgColor)

		let baseline = y + baselineFromTop
		var runGlyphs: [CGGlyph] = []
		var runPositions: [CGPoint] = []
		var runFont: CTFont?

		// One glyph per cell, deliberately: no ligatures. A terminal is a grid,
		// and shaping a run as a whole so `->` becomes an arrow also lets the
		// text drift off that grid. Not wanted here, and drawing per cell is
		// what makes a screen of individually coloured cells affordable.
		//
		// Glyphs are drawn in batches sharing a font. Almost every batch is the
		// whole run; a batch ends only where a character had to come from a
		// fallback face, which is rare enough to be worth not checking for.
		func flush() {
			guard let font = runFont, !runGlyphs.isEmpty else {
				runGlyphs.removeAll(keepingCapacity: true)
				runPositions.removeAll(keepingCapacity: true)
				return
			}
			CTFontDrawGlyphs(font, runGlyphs, runPositions, runGlyphs.count, context)
			runGlyphs.removeAll(keepingCapacity: true)
			runPositions.removeAll(keepingCapacity: true)
			runFont = nil
		}

		// Ligatures, where they are asked for and where they can happen.
		//
		// Shaping is the opposite of what the rest of this does — it decides
		// its own positions, and those drift off a whole-point grid — so the
		// shaper is asked only *which* characters join, and the result is put
		// back on the columns. A run with no two ligature-forming marks side by
		// side cannot join anything, and that is nearly every run.
		//
		// Shaped in the stretches of the run the font can be asked about,
		// rather than in one piece. One character it cannot be asked about
		// used to take the whole run's ligatures with it, and that is the bug
		// this had: a tmux pane border is drawn in the *default* colour while
		// its pane is not the active one, so it shares the attributes of the
		// text either side and lands in the same run. Every line the border
		// crossed lost its ligatures, and making the other pane active —
		// which paints the border green — gave them back.
		var ligated = [Bool](repeating: false, count: max(0, end - start))
		if Settings.shared.fontLigatures {
			let spans = Ligatures.spans(in: start..<end) { canShape(line.cells[$0]) }
			for span in spans {
				guard Ligatures.mayLigate(line.cells[span].lazy.map(\.scalar)),
				      drawLigated(
					of: line, from: span.lowerBound, to: span.upperBound,
					font: drawFont, baseline: baseline, context: context
				      )
				else { continue }
				for cellIndex in span { ligated[cellIndex - start] = true }
			}
		}

		for cellIndex in start..<end {
			// Already drawn, by the shaper, with whatever it chose to join.
			if ligated[cellIndex - start] { continue }
			let cell = line.cells[cellIndex]
			// The trailing half of a wide glyph carries no character of its own.
			if cell.isWideTrailer { continue }
			// Blanks have nothing to draw, and separators are drawn as geometry.
			if cell.scalar == 0x20 || cell.scalar == 0 { continue }
			// A placeholder is a piece of a picture, not a character. Drawn as
			// one it is a private-use codepoint no font has, so the picture
			// arrives under a grid of missing-glyph boxes.
			if cell.scalar == UnicodePlaceholder.scalar { continue }
			if PowerlineGlyph.isSeparator(cell.scalar) { continue }

			guard let found = glyphs.glyph(for: cell.scalar, face: drawFont, faceIndex: faceIndex) else {
				continue
			}
			if let current = runFont, current !== found.font { flush() }
			runFont = found.font

			// Each glyph sits on its own column rather than following the one
			// before it. The cell width is a whole number of points while the
			// font's advance is fractional, and letting the text lay itself out
			// makes it creep off the grid by a fraction of a pixel per
			// character — a whole cell by the end of a typed command, which
			// leaves the text sitting a character away from the cursor.
			let x = (Self.horizontalInset + CGFloat(cellIndex) * cellWidth).rounded()
			runGlyphs.append(found.glyph)
			runPositions.append(CGPoint(x: x, y: -baseline))
		}
		flush()
		context.restoreGState()

		if attributes.underline || attributes.strikethrough {
			drawTextDecoration(from: start, to: end, y: y, colour: foreground, attributes: attributes)
		}
	}

	/// Whether a cell's character can be handed to the font at all.
	///
	/// A powerline separator is drawn as geometry, a box drawing is not
	/// something to let a shaper join, and a placeholder is a piece of a
	/// picture rather than a character. None of them belongs in a shaped span,
	/// and a span stops at one rather than giving up on the whole run.
	private func canShape(_ cell: TerminalCell) -> Bool {
		cell.scalar != 0 && cell.scalar != UnicodePlaceholder.scalar
			&& !PowerlineGlyph.isSeparator(cell.scalar) && !BoxDrawing.draws(cell.scalar)
			&& UnicodeScalar(cell.scalar) != nil
	}

	/// Draws a span with its ligatures joined, and says whether it could.
	///
	/// The shaper is asked what joins; where each piece goes is decided here.
	/// A ligature glyph replaces the characters it covers, so it is drawn at
	/// the column of the first of them — and in a monospaced font its advance
	/// is exactly that many cells, so the grid is kept without forcing it.
	///
	/// Returns false for a span this cannot handle — anything drawn as geometry
	/// rather than from the font, or a picture's placeholder — leaving the
	/// per-cell path to do it. Callers hand it spans that hold none of those,
	/// so this is a guard rather than the way out of a run.
	private func drawLigated(
		of line: TerminalLine,
		from start: Int,
		to end: Int,
		font drawFont: NSFont,
		baseline: CGFloat,
		context: CGContext
	) -> Bool {
		var text = ""
		// Which cell each UTF-16 offset of `text` came from.
		var cellOfOffset: [Int] = []
		for cellIndex in start..<end {
			let cell = line.cells[cellIndex]
			if cell.isWideTrailer { continue }
			if cell.scalar == 0 { return false }
			if cell.scalar == UnicodePlaceholder.scalar { return false }
			if PowerlineGlyph.isSeparator(cell.scalar) || BoxDrawing.draws(cell.scalar) { return false }
			guard let scalar = UnicodeScalar(cell.scalar) else { return false }
			let piece = cell.combining ?? String(Character(scalar))
			text += piece
			cellOfOffset.append(contentsOf: Array(repeating: cellIndex, count: piece.utf16.count))
		}
		guard !text.isEmpty else { return false }

		let attributed = NSAttributedString(string: text, attributes: [.font: drawFont])
		let ctLine = CTLineCreateWithAttributedString(attributed)
		guard let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] else { return false }

		for run in runs {
			let count = CTRunGetGlyphCount(run)
			guard count > 0 else { continue }
			var glyphs = [CGGlyph](repeating: 0, count: count)
			var indices = [CFIndex](repeating: 0, count: count)
			CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
			CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)

			let attributes = CTRunGetAttributes(run) as NSDictionary
			guard let runFont = attributes[kCTFontAttributeName as String] as! CTFont? else { continue }

			var positions = [CGPoint]()
			positions.reserveCapacity(count)
			for index in 0..<count {
				let offset = Int(indices[index])
				guard offset >= 0, offset < cellOfOffset.count else { return false }
				let column = cellOfOffset[offset]
				positions.append(CGPoint(
					x: (Self.horizontalInset + CGFloat(column) * cellWidth).rounded(),
					y: -baseline
				))
			}
			CTFontDrawGlyphs(runFont, glyphs, positions, count, context)
		}
		return true
	}

	/// Underlines and strikethroughs, which the glyphs no longer carry with them.
	private func drawTextDecoration(
		from start: Int,
		to end: Int,
		y: CGFloat,
		colour: NSColor,
		attributes: TerminalAttributes
	) {
		let x = (Self.horizontalInset + CGFloat(start) * cellWidth).rounded()
		let endX = (Self.horizontalInset + CGFloat(end) * cellWidth).rounded()
		let thickness = max(1, (cellHeight / 14).rounded())
		colour.setFill()

		if attributes.underline {
			// Just below the baseline, where a font would put it.
			let underlineY = (y + baselineFromTop + thickness).rounded()
			NSRect(x: x, y: underlineY, width: endX - x, height: thickness).fill()
		}
		if attributes.strikethrough {
			let strikeY = (y + baselineFromTop - cellHeight / 4).rounded()
			NSRect(x: x, y: strikeY, width: endX - x, height: thickness).fill()
		}
	}

	/// Draws the block cursor, turning the cell under it inside out.
	///
	/// The block is the cursor's colour and the character is cut out of it in
	/// the colour behind. Laying a translucent block over the character instead
	/// leaves it the same colour as what is now behind it, which is how it
	/// becomes unreadable exactly where you are looking.
	private func drawCursor() {
		guard let place = cursorPlace() else { return }
		// A cursor parked on a row this pane does not show — tmux putting it on
		// its own status bar while it draws there — would otherwise be drawn at
		// the foot of the pane, on a line that is not the one it is on.
		guard place.row < shownLineCount else { return }

		let screen = emulator.grid
		let row = place.row
		let column = place.column
		let x = (Self.horizontalInset + CGFloat(column) * cellWidth).rounded()
		let endX = (Self.horizontalInset + CGFloat(column + 1) * cellWidth).rounded()
		let y = (Self.verticalInset + CGFloat(row) * cellHeight).rounded()

		let box = NSRect(x: x, y: y, width: endX - x, height: cellHeight)

		// Outlined when the keyboard is somewhere else — the cursor is still
		// where it was, and the character underneath stays as it was written.
		guard hasKeyboardFocus else {
			TerminalPalette.cursor.setStroke()
			let path = NSBezierPath(rect: box.insetBy(dx: 0.75, dy: 0.75))
			path.lineWidth = 1.5
			path.stroke()
			return
		}

		TerminalPalette.cursor.setFill()
		box.fill()

		// The character again, in the colour of what is now behind it.
		guard let line = screen.line(at: row), column < line.cells.count else { return }
		let cell = line.cells[column]
		guard cell.scalar != 0x20, cell.scalar != 0, !cell.attributes.hidden else { return }

		var attributes = cell.attributes
		attributes.foreground = .default
		attributes.background = .default
		attributes.inverse = true
		drawText(of: line, from: column, to: column + 1, attributes: attributes, y: y)
	}

	/// Repaints when the window gains or loses the keyboard.
	///
	/// Becoming first responder is not the only way focus moves: switching to
	/// another app leaves this view first responder in a window that is no
	/// longer key, and the cursor has to say so.
	func watchWindowFocus() {
		let centre = NotificationCenter.default
		for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
			centre.removeObserver(self, name: name, object: nil)
			guard let window else { continue }
			centre.addObserver(
				forName: name, object: window, queue: .main
			) { [weak self] _ in self?.repaint() }
		}
	}

	/// Whether the cursor is drawn at all.
	///
	/// A program repainting hides the cursor, draws, and shows it again. Those
	/// are three writes and they need not arrive in the same frame — so
	/// honouring the hide the instant it arrives turns an ordinary repaint into
	/// a blink, which is what a flickering cursor is. A hide is believed only
	/// once it has lasted longer than a repaint would.
	func cursorPlace() -> (row: Int, column: Int)? {
		guard cursorVisible else { return nil }

		let here = (
			row: emulator.metrics.scrollbackCount + emulator.cursorRow,
			column: emulator.cursorColumn
		)
		guard !emulator.isCursorVisible else {
			cursorHiddenSince = nil
			settledCursor = here
			return here
		}

		// Hidden. A program does that while it repaints — park the cursor
		// somewhere convenient, write, put it back — and both showing it where
		// it was parked and taking it away for those few milliseconds are
		// wrong: one is a cursor that jumps about, the other is a cursor that
		// blinks. So it stays where it last settled.
		guard let since = cursorHiddenSince else {
			cursorHiddenSince = Date()
			// The hide may be meant, and nothing more may arrive to say so;
			// the screen has to be asked again once the moment has passed.
			DispatchQueue.main.asyncAfter(deadline: .now() + Self.cursorHideGrace) { [weak self] in
				self?.repaint()
			}
			return settledCursor
		}

		// Unless it stays hidden, which is a program saying it means it.
		guard -since.timeIntervalSinceNow < Self.cursorHideGrace else { return nil }
		return settledCursor
	}

	/// How long a hide has to last before it is taken seriously — longer than
	/// the gap between the writes of one repaint, shorter than a glance.
	private static let cursorHideGrace: TimeInterval = 0.12

	/// Whether typing would go into this terminal.
	///
	/// Which is what the cursor says: filled here, outlined everywhere else.
	var hasKeyboardFocus: Bool {
		guard let window, window.isKeyWindow else { return false }
		return window.firstResponder === self
	}

	/// The cursor is drawn solid rather than blinking.
	///
	/// A blink repaints the whole view twice a second whatever the program is
	/// doing, which on a busy screen is indistinguishable from the program
	/// being slow — and there is nothing to gain from it: the cursor is already
	/// the only filled block on the line.
	func startCursorBlink() {
		cursorTimer?.invalidate()
		cursorTimer = nil
		cursorVisible = true
	}

	override func becomeFirstResponder() -> Bool {
		cursorVisible = true
		reportFocus(true)
		repaint()
		announceKeyboardFocusChange()
		return true
	}

	override func resignFirstResponder() -> Bool {
		reportFocus(false)
		repaint()
		announceKeyboardFocusChange()
		return true
	}

	/// Tells a program that the window gained or lost the keyboard.
	///
	/// Only when it has asked (mode 1004). tmux passes it through to whatever
	/// is in the pane, which is how a full-screen program knows to stop
	/// animating while nobody is looking at it.
	private func reportFocus(_ hasFocus: Bool) {
		guard emulator.reportsFocus else { return }
		pty.write(hasFocus ? "\u{1B}[I" : "\u{1B}[O")
	}
}
