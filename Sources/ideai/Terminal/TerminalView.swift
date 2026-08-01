import AppKit
import IdeaiKit

/// Renders a `TerminalEmulator`'s grid and forwards input to its process.
///
/// Same virtualisation principle as the code view: only the rows in the
/// viewport are drawn, and cells are batched into runs of identical attributes
/// so a full-colour screen costs a handful of draw calls rather than one per
/// character.
final class TerminalView: NSView, NSTextInputClient {
	private let emulator: TerminalEmulator
	private let pty: PseudoTerminal

	/// Fired when the process exits, so the panel can label the tab.
	var onProcessExit: ((Int32) -> Void)?
	/// Fired when output arrives, for views that summarise a session they are
	/// not showing.
	var onOutput: (() -> Void)?
	var onTitleChange: ((String) -> Void)?

	private var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
	/// Glyphs already looked up, thrown away when the font changes.
	private let glyphs = GlyphCache()
	/// Distance from the top of a cell to the baseline the text sits on.
	private var baselineFromTop: CGFloat = 12
	/// The four faces a cell can ask for, worked out once per font change.
	///
	/// Deriving a bold or italic face goes through NSFontManager, which is not
	/// cheap, and it was being asked for once per run of every frame — several
	/// hundred times a frame on a busy screen.
	private var faces = TerminalFaces(base: .monospacedSystemFont(ofSize: 12, weight: .regular))
	private var cellWidth: CGFloat = 7
	private var cellHeight: CGFloat = 16
	private var baselineOffset: CGFloat = 4

	/// Follows output unless the user scrolls up to read history.
	private var isPinnedToBottom = true

	/// Highlighted while files are held over the view.
	private var isDropTarget = false
	/// Where the cursor was last painted, so the cell it leaves is repainted.
	private var lastDrawnCursorRow: Int?

	/// Output read from the process but not yet parsed.
	///
	/// Parsed a little at a time rather than all at once. A program can produce
	/// output faster than any terminal can show it — a full-screen animation
	/// does exactly that — and parsing every byte the moment it arrives leaves
	/// the main thread no time to draw or to listen, which reads as a freeze
	/// however fast the parser is.
	private var pending: [Data] = []
	private var pendingBytes = 0
	private var drainScheduled = false
	private var isReadingSuspended = false

	/// How long parsing may take before yielding so the screen can be drawn.
	private static let parseBudget: TimeInterval = 0.006
	/// Backlog at which the process is made to wait, and the one it resumes at.
	private static let backlogHighWater = 4 << 20
	private static let backlogLowWater = 1 << 20
	/// Text selected with the mouse, in absolute rows. Nil when nothing is.
	private var selection: TerminalSelection?
	private var isSelecting = false
	private var lastDiscardedLineCount = 0
	private var cursorVisible = true
	private var cursorTimer: Timer?

	private static let horizontalInset: CGFloat = 8
	private static let verticalInset: CGFloat = 4

	/// Coalesces repaints to one per runloop turn.
	///
	/// A full-screen program repaints by emitting many small writes; redrawing on
	/// each one both wastes work and visibly tears, because the screen is
	/// composited mid-update. Batching to a single pass per turn is what removes
	/// the flicker.
	private var redrawScheduled = false

	// MARK: - Init

	init(workingDirectory: URL?, command: (executable: String, arguments: [String])? = nil) {
		emulator = TerminalEmulator(rows: 24, columns: 80)
		pty = PseudoTerminal()
		super.init(frame: .zero)

		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		updateMetrics()

		emulator.onUpdate = { [weak self] in
			self?.realignSelectionForDiscardedLines()
			self?.scheduleRedraw()
			self?.onOutput?()
		}
		// Replies such as the cursor-position report must go back to the process,
		// otherwise shells that ask for it hang.
		emulator.onResponse = { [weak self] response in
			self?.pty.write(response)
		}
		emulator.onBell = { NSSound.beep() }

		pty.onOutput = { [weak self] data in
			self?.enqueue(data)
		}
		pty.onExit = { [weak self] code in
			self?.emulator.write("\r\n[process exited with status \(code)]\r\n")
			self?.onProcessExit?(code)
		}

		self.pendingLaunch = (workingDirectory, command)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		cursorTimer?.invalidate()
		pty.terminate()
	}

	private var pendingLaunch: (URL?, (executable: String, arguments: [String])?)?

	override var isFlipped: Bool { true }
	override var acceptsFirstResponder: Bool { true }

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		guard window != nil, let launch = pendingLaunch else { return }
		pendingLaunch = nil

		// Files dropped from the tree, or from any app that offers URLs.
		registerForDraggedTypes([.fileURL])

		launchWhenSized(launch)
	}

	/// Waits until the pane has a real size before starting the child.
	///
	/// Measuring too early yields a grid a few rows tall. A full-screen program
	/// like tmux lays its status bar out once, at whatever size it was told, and
	/// never learns better unless something resizes afterwards — which is why the
	/// status line ended up near the top until the pane was dragged.
	private func launchWhenSized(_ launch: (URL?, (executable: String, arguments: [String])?), attempt: Int = 0) {
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }

			let height = self.enclosingScrollView?.contentView.bounds.height ?? 0
			let width = self.enclosingScrollView?.contentView.bounds.width ?? 0
			let isSized = height >= self.cellHeight * 4 && width >= self.cellWidth * 20

			// Give layout a few turns, then start anyway rather than never.
			guard isSized || attempt >= 20 else {
				self.launchWhenSized(launch, attempt: attempt + 1)
				return
			}

			self.recomputeGridSize()
			if let command = launch.1 {
				self.pty.start(
					executable: command.executable,
					arguments: command.arguments,
					workingDirectory: launch.0,
					rows: self.emulator.screen.rows,
					columns: self.emulator.screen.columns
				)
			} else {
				self.pty.startLoginShell(
					workingDirectory: launch.0,
					rows: self.emulator.screen.rows,
					columns: self.emulator.screen.columns
				)
			}
			self.startCursorBlink()
		}
	}

	/// Takes output from the process and asks for it to be parsed soon.
	private func enqueue(_ data: Data) {
		pending.append(data)
		pendingBytes += data.count

		// Far enough behind that the process should wait for us.
		if !isReadingSuspended, pendingBytes >= Self.backlogHighWater {
			isReadingSuspended = true
			pty.setReadingSuspended(true)
		}
		scheduleDrain()
	}

	private func scheduleDrain() {
		guard !drainScheduled, !pending.isEmpty else { return }
		drainScheduled = true
		// A delay rather than an immediate hop: blocks queued on the main queue
		// are all run before the display cycle, so re-queueing at once would
		// starve drawing exactly as parsing everything inline did.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.002) { [weak self] in
			self?.drain()
		}
	}

	/// Parses what has arrived, for as long as the budget allows.
	private func drain() {
		drainScheduled = false
		let deadline = Date().addingTimeInterval(Self.parseBudget)

		while !pending.isEmpty {
			let chunk = pending.removeFirst()
			pendingBytes -= chunk.count
			emulator.write(chunk)
			if Date() >= deadline { break }
		}

		if let title = emulator.title { onTitleChange?(title) }

		// Caught up enough that the process may carry on.
		if isReadingSuspended, pendingBytes <= Self.backlogLowWater {
			isReadingSuspended = false
			pty.setReadingSuspended(false)
		}
		scheduleDrain()
	}

	private func scheduleRedraw() {
		guard !redrawScheduled else { return }
		redrawScheduled = true
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.redrawScheduled = false

			// On the alternate screen the document never grows and there is no
			// history to follow, so resizing and autoscrolling there would fight
			// the program's own repainting.
			if !self.emulator.isAlternateScreen {
				self.updateFrameSize()
				if self.isPinnedToBottom { self.scrollToBottom() }
			}
			self.invalidateChangedRows()
		}
	}

	/// Repaints the lines that changed, rather than the whole view.
	///
	/// Marking the whole view means AppKit cannot keep any of what it already
	/// has, which matters most while output streams past: a printed line changes
	/// one row, and the rest can be scrolled rather than drawn again.
	private func invalidateChangedRows() {
		guard let range = emulator.takeDirtyRange() else {
			// The cursor may still have moved, which is a repaint of its own.
			invalidateCursorRows()
			return
		}

		// Beyond a certain share of the view, working out what to keep costs
		// more than painting it.
		let visibleRows = Int(ceil(visibleRect.height / max(1, cellHeight))) + 1
		guard range.count < max(4, visibleRows / 2) else {
			needsDisplay = true
			return
		}

		setNeedsDisplay(rect(forAbsoluteRows: range))
		invalidateCursorRows()
	}

	/// The cursor is drawn over a cell that is otherwise unchanged, so both the
	/// row it left and the row it is on have to be repainted.
	private func invalidateCursorRows() {
		let row = emulator.screen.scrollback.count + emulator.cursorRow
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

	// MARK: - Metrics

	/// Logged once, so "which font is it actually using?" has a definite answer.
	private static var didLogFont = false

	private func updateMetrics() {
		font = Theme.terminalFont(size: Theme.current.fontSize)
		if !Self.didLogFont {
			Self.didLogFont = true
			FileHandle.standardError.write(Data("ideai terminal font: \(font.fontName)\n".utf8))
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
	}

	func applyThemeChange() {
		updateMetrics()
		recomputeGridSize()
		needsDisplay = true
	}

	/// Derives rows and columns from the pane size and tells both the emulator
	/// and the process.
	private func recomputeGridSize() {
		guard let clip = enclosingScrollView?.contentView else { return }
		let usableWidth = clip.bounds.width - Self.horizontalInset * 2
		let usableHeight = clip.bounds.height - Self.verticalInset * 2

		let columns = max(20, Int(floor(usableWidth / max(1, cellWidth))))
		let rows = max(4, Int(floor(usableHeight / max(1, cellHeight))))

		guard rows != emulator.screen.rows || columns != emulator.screen.columns else { return }
		// A resize reflows what the absolute rows mean, and there is no honest
		// mapping from the old grid to the new one.
		setSelection(nil)
		emulator.resize(rows: rows, columns: columns)
		pty.resize(rows: rows, columns: columns)
		updateFrameSize()
	}

	private func updateFrameSize() {
		let totalRows = emulator.isAlternateScreen
			? emulator.screen.rows
			: emulator.screen.totalLineCount
		let height = CGFloat(totalRows) * cellHeight + Self.verticalInset * 2
		let width = enclosingScrollView?.contentSize.width ?? bounds.width
		let newSize = NSSize(width: max(width, 10), height: max(height, 10))
		if abs(newSize.height - frame.height) > 0.5 || abs(newSize.width - frame.width) > 0.5 {
			setFrameSize(newSize)
		}
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

		if isPinnedToBottom { scrollToBottom() }
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.fill()

		let screen = emulator.screen
		let firstRow = max(0, Int(floor((dirtyRect.minY - Self.verticalInset) / cellHeight)))
		let lastRow = min(screen.totalLineCount, Int(ceil((dirtyRect.maxY - Self.verticalInset) / cellHeight)) + 1)
		guard lastRow > firstRow else { return }

		for index in firstRow..<lastRow {
			guard let line = screen.line(at: index) else { continue }
			draw(line: line, atRow: index)
		}

		drawCursor()
		drawDropHighlight()
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

			let background = TerminalPalette.color(for: resolved.background, isForeground: false, bold: false)
			if resolved.background != .default {
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

	/// Tints the selected cells.
	///
	/// Drawn over the text rather than behind it, so the characters keep their
	/// own colours — a terminal's palette carries meaning, and repainting a
	/// selected region in system selection colours would throw that away.
	private func drawSelection(on line: TerminalLine, atRow index: Int, y: CGFloat) {
		guard let selection,
		      let range = selection.columnRange(onRow: index, columns: line.cells.count)
		else { return }

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
		if attributes.dim { foreground = foreground.withAlphaComponent(0.6) }

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

		for cellIndex in start..<end {
			let cell = line.cells[cellIndex]
			// The trailing half of a wide glyph carries no character of its own.
			if cell.isWideTrailer { continue }
			// Blanks have nothing to draw, and separators are drawn as geometry.
			if cell.scalar == 0x20 || cell.scalar == 0 { continue }
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

	private func drawCursor() {
		guard emulator.isCursorVisible, cursorVisible, window?.firstResponder === self else { return }

		let row = emulator.screen.scrollback.count + emulator.cursorRow
		let x = Self.horizontalInset + CGFloat(emulator.cursorColumn) * cellWidth
		let y = Self.verticalInset + CGFloat(row) * cellHeight

		Theme.current.caret.withAlphaComponent(0.8).setFill()
		NSRect(x: x, y: y, width: cellWidth, height: cellHeight).fill()
	}

	/// The cursor is drawn solid rather than blinking.
	///
	/// A blink repaints the whole view twice a second whatever the program is
	/// doing, which on a busy screen is indistinguishable from the program
	/// being slow — and there is nothing to gain from it: the cursor is already
	/// the only filled block on the line.
	private func startCursorBlink() {
		cursorTimer?.invalidate()
		cursorTimer = nil
		cursorVisible = true
	}

	override func becomeFirstResponder() -> Bool {
		cursorVisible = true
		needsDisplay = true
		return true
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		return true
	}

	// MARK: - Input

	/// Claims the ⌘ movement keys before the menu sees them.
	///
	/// A ⌘ combination is offered around as a key equivalent first, and one
	/// that nothing claims never arrives as a keyDown. Only the three the
	/// terminal has a meaning for are taken — ⌘C, ⌘V and the rest stay with the
	/// menu, where they belong.
	override func performKeyEquivalent(with event: NSEvent) -> Bool {
		guard window?.firstResponder === self,
		      event.modifierFlags.contains(.command),
		      let key = TerminalKeys.Key(rawValue: event.keyCode),
		      let sequence = TerminalKeys.editingSequence(for: key, option: false, command: true)
		else { return super.performKeyEquivalent(with: event) }

		isPinnedToBottom = true
		pty.write(sequence)
		scrollToBottom()
		return true
	}

	var totalRowsForTesting: Int { max(1, emulator.screen.totalLineCount) }

	/// Feeds output straight to the emulator, bypassing the process.
	func writeForTesting(_ text: String) {
		emulator.write(text)
		displayIfNeeded()
	}

	// MARK: - Dropping files

	/// Files dropped here are typed as paths.
	///
	/// What the terminal is running does not matter: the path arrives as
	/// keystrokes, so it works at a shell prompt and equally in an agent's
	/// prompt, which is the case this exists for.
	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		guard !droppedURLs(from: sender).isEmpty else { return [] }
		isDropTarget = true
		needsDisplay = true
		return .copy
	}

	override func draggingExited(_ sender: NSDraggingInfo?) {
		isDropTarget = false
		needsDisplay = true
	}

	override func draggingEnded(_ sender: NSDraggingInfo) {
		isDropTarget = false
		needsDisplay = true
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		isDropTarget = false
		needsDisplay = true

		let urls = droppedURLs(from: sender)
		guard !urls.isEmpty else { return false }

		window?.makeFirstResponder(self)
		send(TerminalDrop.text(for: urls))
		return true
	}

	private func droppedURLs(from sender: NSDraggingInfo) -> [URL] {
		let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
		let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
		return (objects as? [URL]) ?? []
	}

	override func keyDown(with event: NSEvent) {
		guard let bytes = encode(event: event) else { return }
		// Typing always jumps back to the prompt, as every terminal does.
		isPinnedToBottom = true
		pty.write(bytes)
		scrollToBottom()
	}

	/// Translates a key event into the bytes a terminal would send.
	private func encode(event: NSEvent) -> String? {
		let flags = event.modifierFlags

		// Keys with a fixed sequence, and the Option-as-Meta rule that goes with
		// them. Applied here rather than after the switch: returning early was
		// how ⌥Return came to send a bare carriage return, which submits the
		// line instead of breaking it.
		if let key = TerminalKeys.Key(rawValue: event.keyCode) {
			// Modified navigation first: ⌥← is a word movement, not an arrow
			// with a prefix, and ⌘← is the start of the line.
			if let editing = TerminalKeys.editingSequence(
				for: key,
				option: flags.contains(.option),
				command: flags.contains(.command)
			) {
				return editing
			}

			let base: String?
			switch key {
			case .upArrow:    base = emulator.encodeArrow(.up)
			case .downArrow:  base = emulator.encodeArrow(.down)
			case .rightArrow: base = emulator.encodeArrow(.right)
			case .leftArrow:  base = emulator.encodeArrow(.left)
			default:          base = TerminalKeys.sequence(for: key)
			}

			guard let base else { return nil }
			return TerminalKeys.applyingMeta(base, key: key, optionHeld: flags.contains(.option))
		}

		guard var characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return nil }

		if flags.contains(.control) {
			// ⌃A…⌃Z and the handful of punctuation controls.
			guard let scalar = characters.lowercased().unicodeScalars.first else { return nil }
			switch scalar {
			case "a"..."z":
				return String(UnicodeScalar(scalar.value - 96)!)
			case "[": return "\u{1B}"
			case "\\": return "\u{1C}"
			case "]": return "\u{1D}"
			case " ", "2": return "\u{0}"
			default: return nil
			}
		}

		// Option is Meta: prefix with ESC, which is what shells expect for
		// word-wise editing (⌥B, ⌥F).
		if flags.contains(.option) {
			return "\u{1B}" + characters
		}

		// Otherwise send what was actually typed, so dead keys and IME work.
		if let typed = event.characters, !typed.isEmpty {
			characters = typed
		}
		return characters
	}

	// MARK: - Mouse

	/// Grid position under a pointer event, 1-based as the protocol expects.
	/// The cell under the pointer, in absolute rows including scrollback.
	///
	/// Rounded to the nearest boundary rather than truncated, so a drag that
	/// ends halfway across a cell includes the half it covers — which is what
	/// makes selecting up to the last character possible.
	private func selectionPosition(for event: NSEvent) -> TerminalPosition {
		position(for: event, roundingToBoundary: true)
	}

	/// The character under the pointer, as opposed to the nearest gap.
	///
	/// A double-click on the right half of a cell rounds up to the next
	/// boundary, which as a character index is the cell after the one that was
	/// clicked — so the word picked was the one to its right.
	private func characterPosition(for event: NSEvent) -> TerminalPosition {
		position(for: event, roundingToBoundary: false)
	}

	private func position(for event: NSEvent, roundingToBoundary: Bool) -> TerminalPosition {
		let point = convert(event.locationInWindow, from: nil)
		let row = Int(floor((point.y - Self.verticalInset) / max(1, cellHeight)))
		let exact = (point.x - Self.horizontalInset) / max(1, cellWidth)
		let column = Int(roundingToBoundary ? exact.rounded() : exact.rounded(.down))
		let lastRow = max(0, emulator.screen.totalLineCount - 1)
		return TerminalPosition(
			row: max(0, min(row, lastRow)),
			column: max(0, min(column, emulator.screen.columns))
		)
	}

	/// Selection is for reading output, so a program that tracks the mouse gets
	/// the events instead — unless Shift is held, the usual escape hatch.
	private var mouseSelects: Bool {
		emulator.mouseTracking == .off
	}

	/// Follows the selection when lines fall out of the top of scrollback.
	///
	/// Absolute rows are stable while the buffer only grows; once it is full,
	/// every discarded line renumbers everything above the selection, and a
	/// selection left alone would drift down the screen on its own.
	private func realignSelectionForDiscardedLines() {
		let discarded = emulator.screen.discardedLineCount
		defer { lastDiscardedLineCount = discarded }

		let shift = discarded - lastDiscardedLineCount
		guard shift > 0, var updated = selection else { return }

		updated.anchor.row -= shift
		updated.head.row -= shift
		// Scrolled off entirely; there is nothing left to keep highlighted.
		guard max(updated.anchor.row, updated.head.row) >= 0 else {
			setSelection(nil)
			return
		}
		updated.anchor.row = max(0, updated.anchor.row)
		updated.head.row = max(0, updated.head.row)
		setSelection(updated)
	}

	private func setSelection(_ new: TerminalSelection?) {
		guard new != selection else { return }
		selection = new
		needsDisplay = true
	}

	private func gridPosition(for event: NSEvent) -> (row: Int, column: Int) {
		let point = convert(event.locationInWindow, from: nil)
		let column = Int((point.x - Self.horizontalInset) / max(1, cellWidth)) + 1
		var row = Int((point.y - Self.verticalInset) / max(1, cellHeight))
		// The protocol addresses the visible grid, so scrollback is subtracted.
		row -= emulator.screen.scrollback.count
		return (max(1, row + 1), max(1, column))
	}

	private func modifiers(_ event: NSEvent) -> (Bool, Bool, Bool) {
		let flags = event.modifierFlags
		return (flags.contains(.shift), flags.contains(.option), flags.contains(.control))
	}

	/// Forwards a pointer event, returning true when the program consumed it.
	private func forwardMouse(
		_ event: NSEvent,
		button: TerminalEmulator.MouseButton,
		isRelease: Bool,
		isDrag: Bool = false
	) -> Bool {
		// Shift is the conventional override for "let the terminal handle it",
		// which is how selection stays possible while a program grabs the mouse.
		guard !event.modifierFlags.contains(.shift) else { return false }

		let position = gridPosition(for: event)
		let (shift, option, control) = modifiers(event)
		guard let sequence = emulator.encodeMouse(
			button: button,
			row: position.row,
			column: position.column,
			isRelease: isRelease,
			isDrag: isDrag,
			shift: shift,
			option: option,
			control: control
		) else { return false }

		pty.write(sequence)
		return true
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)

		guard mouseSelects || event.modifierFlags.contains(.shift) else {
			_ = forwardMouse(event, button: .left, isRelease: false)
			return
		}

		switch event.clickCount {
		case 2:
			let position = characterPosition(for: event)
			setSelection(emulator.screen.wordSelection(atRow: position.row, column: position.column))
		case 3...:
			setSelection(emulator.screen.lineSelection(atRow: characterPosition(for: event).row))
		default:
			let position = selectionPosition(for: event)
			isSelecting = true
			setSelection(TerminalSelection(anchor: position, head: position))
		}
	}

	override func mouseUp(with event: NSEvent) {
		if isSelecting {
			isSelecting = false
			// A click that never moved is a click, not an empty selection.
			if selection?.isEmpty == true { setSelection(nil) }
			return
		}
		_ = forwardMouse(event, button: .left, isRelease: true)
	}

	override func mouseDragged(with event: NSEvent) {
		guard isSelecting else {
			_ = forwardMouse(event, button: .left, isRelease: false, isDrag: true)
			return
		}
		guard var updated = selection else { return }
		updated.head = selectionPosition(for: event)
		setSelection(updated)

		// Dragging past an edge should keep going, the way it does in a list.
		autoscroll(with: event)
	}

	override func rightMouseDown(with event: NSEvent) {
		guard mouseSelects else {
			_ = forwardMouse(event, button: .right, isRelease: false)
			return
		}
		NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
	}

	override func rightMouseUp(with event: NSEvent) {
		guard mouseSelects else {
			_ = forwardMouse(event, button: .right, isRelease: true)
			return
		}
	}

	private func makeContextMenu() -> NSMenu {
		let menu = NSMenu()
		// AppKit recomputes isEnabled from the responder chain by default, which
		// discards whatever the items were built with.
		menu.autoenablesItems = false

		func item(_ title: String, _ selector: Selector, enabled: Bool = true) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			item.target = self
			item.isEnabled = enabled
			return item
		}

		menu.addItem(item("Copy", #selector(copy(_:)), enabled: selection != nil))
		menu.addItem(item("Paste", #selector(paste(_:))))
		menu.addItem(.separator())
		menu.addItem(item("Select All", #selector(selectAll(_:))))
		menu.addItem(item("Clear Selection", #selector(clearSelection), enabled: selection != nil))
		return menu
	}

	override func scrollWheel(with event: NSEvent) {
		// A program tracking the mouse gets wheel events as button 64/65.
		if emulator.mouseTracking != .off, !event.modifierFlags.contains(.shift) {
			let steps = max(1, min(5, Int(abs(event.scrollingDeltaY) / max(1, cellHeight)) + 1))
			let button: TerminalEmulator.MouseButton = event.scrollingDeltaY > 0 ? .scrollUp : .scrollDown
            let position = gridPosition(for: event)
			for _ in 0..<steps {
				if let sequence = emulator.encodeMouse(
					button: button,
					row: position.row,
					column: position.column,
					isRelease: false
				) {
					pty.write(sequence)
				}
			}
			return
		}

		// On the alternate screen there is no scrollback to move through, so the
		// wheel drives the program's own cursor instead of doing nothing.
		if emulator.isAlternateScreen {
			let steps = max(1, min(5, Int(abs(event.scrollingDeltaY) / max(1, cellHeight)) + 1))
			let key: TerminalEmulator.ArrowKey = event.scrollingDeltaY > 0 ? .up : .down
			pty.write(String(repeating: emulator.encodeArrow(key), count: steps))
			return
		}

		super.scrollWheel(with: event)
	}

	// MARK: - Actions

	@objc func copy(_ sender: Any?) {
		// Only what is selected. Copying the entire buffer when nothing is
		// selected is a surprise nobody wants pasted somewhere else.
		guard let selection else { return }
		let text = emulator.screen.text(in: selection)
		guard !text.isEmpty else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	@objc override func selectAll(_ sender: Any?) {
		setSelection(emulator.screen.fullSelection)
	}

	@objc private func clearSelection() {
		setSelection(nil)
	}

	@objc func paste(_ sender: Any?) {
		guard let text = NSPasteboard.general.string(forType: .string) else { return }
		isPinnedToBottom = true
		// Bracketed paste tells the program the text arrived at once, which stops
		// shells from executing every pasted line as it lands.
		if emulator.bracketedPaste {
			pty.write("\u{1B}[200~" + text + "\u{1B}[201~")
		} else {
			pty.write(text)
		}
		scrollToBottom()
	}

	func sendInterrupt() {
		pty.interrupt()
	}

	func terminateProcess() {
		pty.terminate()
	}

	var isProcessRunning: Bool { pty.isRunning }

	/// The last few non-blank lines, for a progress summary elsewhere.
	func recentOutput(_ count: Int) -> [String] {
		emulator.screen.recentLines(count)
	}

	/// Writes text as though typed. Used to drive a session programmatically —
	/// the same entry point an agent prompt will take.
	func send(_ text: String) {
		isPinnedToBottom = true
		pty.write(text)
		scrollToBottom()
	}

	// MARK: - NSTextInputClient

	// Minimal conformance so IME candidates commit into the terminal.

	func insertText(_ string: Any, replacementRange: NSRange) {
		let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
		guard !text.isEmpty else { return }
		pty.write(text)
	}

	func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
	func unmarkText() {}
	func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
	func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
	func hasMarkedText() -> Bool { false }
	func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
	func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
	func characterIndex(for point: NSPoint) -> Int { 0 }

	func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
		guard let window else { return .zero }
		let row = emulator.screen.scrollback.count + emulator.cursorRow
		let rect = NSRect(
			x: Self.horizontalInset + CGFloat(emulator.cursorColumn) * cellWidth,
			y: Self.verticalInset + CGFloat(row) * cellHeight,
			width: cellWidth,
			height: cellHeight
		)
		return window.convertToScreen(convert(rect, to: nil))
	}
}

/// Scrolling container that keeps the terminal sized to its viewport.
final class TerminalPane: NSView {
	let terminalView: TerminalView
	private let scrollView = NSScrollView()

	init(workingDirectory: URL?, command: (executable: String, arguments: [String])? = nil) {
		terminalView = TerminalView(workingDirectory: workingDirectory, command: command)
		super.init(frame: .zero)

		scrollView.documentView = terminalView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		scrollView.scrollerStyle = .overlay
		scrollView.contentView.postsBoundsChangedNotifications = true

		addSubview(scrollView)
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
		])

		NotificationCenter.default.addObserver(
			forName: NSView.boundsDidChangeNotification,
			object: scrollView.contentView,
			queue: .main
		) { [weak self] _ in
			self?.terminalView.viewportChanged()
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		// The grid is measured in cells, so a resize changes rows and columns.
		terminalView.viewportChanged()
	}

	override func layout() {
		super.layout()
		// Catches the case where the pane gains its real size through layout
		// rather than an explicit frame change.
		terminalView.viewportChanged()
	}

	func focus() {
		window?.makeFirstResponder(terminalView)
	}
}

/// The four faces a terminal cell can ask for, and what each one advances by.
///
/// Derived once per font change. Asking NSFontManager to convert a font is
/// slow enough to matter when it happens for every run of every frame, and the
/// advance was being measured through a string-keyed cache that allocated its
/// key on each lookup.
private struct TerminalFaces {
	let regular: NSFont
	let bold: NSFont
	let italic: NSFont
	let boldItalic: NSFont
	/// Advance of the regular face, which is what the cell grid is built on.
	let advance: CGFloat

	private let advances: (CGFloat, CGFloat, CGFloat, CGFloat)

	init(base: NSFont) {
		let manager = NSFontManager.shared
		regular = base
		bold = manager.convert(base, toHaveTrait: .boldFontMask)
		italic = manager.convert(base, toHaveTrait: .italicFontMask)
		boldItalic = manager.convert(bold, toHaveTrait: .italicFontMask)

		func width(_ font: NSFont) -> CGFloat {
			("0" as NSString).size(withAttributes: [.font: font]).width
		}
		advances = (width(regular), width(bold), width(italic), width(boldItalic))
		advance = advances.0
	}

	/// Which of the four faces a pair of flags asks for.
	static func index(bold isBold: Bool, italic isItalic: Bool) -> UInt8 {
		(isBold ? 1 : 0) | (isItalic ? 2 : 0)
	}

	func face(bold isBold: Bool, italic isItalic: Bool) -> NSFont {
		switch (isBold, isItalic) {
		case (false, false): return regular
		case (true, false):  return bold
		case (false, true):  return italic
		case (true, true):   return boldItalic
		}
	}

	func advance(bold isBold: Bool, italic isItalic: Bool) -> CGFloat {
		switch (isBold, isItalic) {
		case (false, false): return advances.0
		case (true, false):  return advances.1
		case (false, true):  return advances.2
		case (true, true):   return advances.3
		}
	}
}


/// A glyph for one code point, together with the font that actually has it.
///
/// Looked up once and kept. Turning a character into a glyph means asking
/// CoreText, and asking it for a font that can draw one means asking the whole
/// fallback cascade — neither is something to do sixty times a second for every
/// cell on the screen.
private struct CachedGlyph {
	let glyph: CGGlyph
	let font: CTFont
}

private struct GlyphKey: Hashable {
	let scalar: UInt32
	/// Which of the four faces asked for it.
	let face: UInt8
}

/// Glyphs by code point and face.
///
/// Kept on the view rather than shared, so changing the font throws away the
/// glyphs that went with it.
private final class GlyphCache {
	private var entries: [GlyphKey: CachedGlyph?] = [:]

	func clear() { entries.removeAll(keepingCapacity: true) }

	/// The glyph to draw for a code point, or nil when nothing can draw it.
	fileprivate func glyph(for scalar: UInt32, face: NSFont, faceIndex: UInt8) -> CachedGlyph? {
		let key = GlyphKey(scalar: scalar, face: faceIndex)
		if let known = entries[key] { return known }

		let found = Self.lookUp(scalar: scalar, in: face)
		entries[key] = found
		return found
	}

	fileprivate static func lookUp(scalar: UInt32, in face: NSFont) -> CachedGlyph? {
		guard let unicode = UnicodeScalar(scalar) else { return nil }
		var utf16 = Array(String(unicode).utf16)
		var glyphs = [CGGlyph](repeating: 0, count: utf16.count)

		let ctFace = face as CTFont
		if CTFontGetGlyphsForCharacters(ctFace, &utf16, &glyphs, utf16.count), glyphs[0] != 0 {
			return CachedGlyph(glyph: glyphs[0], font: ctFace)
		}

		// The terminal's own face has no glyph for it — emoji, CJK and the
		// powerline range all come from somewhere else. CoreText knows where.
		let fallback = CTFontCreateForString(ctFace, String(unicode) as CFString, CFRange(location: 0, length: utf16.count))
		if CTFontGetGlyphsForCharacters(fallback, &utf16, &glyphs, utf16.count), glyphs[0] != 0 {
			return CachedGlyph(glyph: glyphs[0], font: fallback)
		}
		return nil
	}
}
