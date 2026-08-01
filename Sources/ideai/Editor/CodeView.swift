import AppKit
import IdeaiKit

/// The text surface: draws only the lines in the viewport and handles editing.
///
/// The performance story is entirely about what is *not* done. There is no
/// layout manager and no attributed string for the document — only the ~60 lines
/// on screen are ever turned into `CTLine`s, and only the visible byte range is
/// ever handed to the syntax query. Scrolling a 200 MB file therefore costs the
/// same as scrolling a small one, because the work is proportional to the window,
/// not the file.
final class CodeView: NSView, NSTextInputClient {
	// MARK: - Model

	private(set) var document: TextDocument?
	private var folding = FoldingState()

	/// Row mapping when soft wrap is on. Empty means one row per line.
	private var wrapLayout = WrapLayout()
	private(set) var isWordWrapEnabled = false

	/// Caret and selection anchor, in UTF-16 offsets.
	private var caret = 0
	private var selectionAnchor = 0

	/// Column the caret tries to keep while moving vertically, so travelling
	/// through short lines does not lose the original column.
	private var desiredColumnX: CGFloat?

	var onCaretMoved: ((Int, Int) -> Void)?   // line, column (1-based)
	var onDirtyChanged: ((Bool) -> Void)?

	/// Search matches to highlight, and which one is current.
	private var searchMatches: [SearchMatch] = []
	private var currentMatchIndex: Int?

	/// Debugger state for this file: breakpoint lines and where execution stopped.
	private var breakpointLines: [Int: Bool] = [:]   // line -> verified
	private var executionLine: Int?
	/// 1-based lines that have something runnable on them, and the click that
	/// runs it.
	private var runnableLines: Set<Int> = []
	var onRunLine: ((Int) -> Void)?
	/// Right-clicked a breakpoint: edit what it does. Zero-based line.
	var onEditBreakpoint: ((Int) -> Void)?
	/// Which lines have a breakpoint that does more than stop every time.
	private var conditionalBreakpointLines: Set<Int> = []

	func setConditionalBreakpoints(_ lines: Set<Int>) {
		guard lines != conditionalBreakpointLines else { return }
		conditionalBreakpointLines = lines
		needsDisplay = true
	}

	/// ⌘-clicked a symbol: go to where it is defined.
	var onGoToDefinition: ((_ line: Int, _ character: Int) -> Void)?
	/// The text changed and the caret is in a word: offer completions for it.
	var onRequestCompletions: ((_ prefix: String, _ caret: NSPoint) -> Void)?
	/// A key the completion list wants first. Returns true if it took it.
	var completionKeyHandler: ((Selector) -> Bool)?
	/// Nothing to complete any more.
	var onDismissCompletions: (() -> Void)?

	/// What a language server says is wrong here, by zero-based line.
	private var diagnosticsByLine: [Int: [LSPDiagnostic]] = [:]

	/// Replaces what is underlined as a problem.
	func setDiagnostics(_ diagnostics: [LSPDiagnostic]) {
		var grouped: [Int: [LSPDiagnostic]] = [:]
		for diagnostic in diagnostics {
			// A problem spanning lines is marked on the line it starts at, which
			// is where the cause is; underlining all of them buries it.
			grouped[diagnostic.range.start.line, default: []].append(diagnostic)
		}
		guard grouped != diagnosticsByLine else { return }
		diagnosticsByLine = grouped
		needsDisplay = true
	}

	/// The problems on a line, worst first.
	func diagnostics(onLine line: Int) -> [LSPDiagnostic] {
		(diagnosticsByLine[line] ?? []).sorted { $0.severity < $1.severity }
	}

	var hasDiagnostics: Bool { !diagnosticsByLine.isEmpty }

	/// Called when the gutter is clicked in the breakpoint column.
	var onToggleBreakpoint: ((Int) -> Void)?

	// MARK: - Metrics

	private var font: NSFont = Theme.current.editorFont
	private var lineHeight: CGFloat = 18
	private var baselineOffset: CGFloat = 4
	private var charWidth: CGFloat = 7
	private(set) var gutterWidth: CGFloat = 60

	private static let gutterPadding: CGFloat = 10
	/// Clickable strip on the far left of the gutter for breakpoints.
	private static var breakpointColumnWidth: CGFloat { Theme.current.scaled(18) }
	private static let textLeftPadding: CGFloat = 8
	/// Extra rows drawn beyond the viewport so fast scrolling does not flash.
	private static let overscanLines = 2

	private var longestLineColumns = 80

	// MARK: - Caret blinking

	private var caretVisible = true
	private var caretTimer: Timer?

	// MARK: - Init

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		updateMetrics()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		caretTimer?.invalidate()
	}

	override var isFlipped: Bool { true }
	override var acceptsFirstResponder: Bool { true }

	/// Re-reads font and spacing from the theme, then relays out. Called when
	/// preferences change.
	func applyThemeChange() {
		updateMetrics()
		updateFrameSize()
		needsDisplay = true
	}

	private func updateMetrics() {
		font = Theme.current.editorFont
		let ascent = font.ascender
		let descent = -font.descender
		let leading = font.leading
		lineHeight = ceil((ascent + descent + leading) * Theme.current.lineHeightMultiple)
		baselineOffset = ceil(descent + leading + (lineHeight - (ascent + descent + leading)) / 2)
		charWidth = font.maximumAdvancement.width
		// A monospaced font reports a uniform advance; measure "0" for accuracy.
		charWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
	}

	// MARK: - Loading

	/// Re-reads the file after something else wrote it, putting the user back
	/// where they were.
	///
	/// Position is kept as a line and column rather than a character offset:
	/// an offset into the old text names a different place in the new one, and
	/// an agent editing a file above the caret would silently move it. Line and
	/// column survive edits elsewhere in the file, which is the common case.
	///
	/// The line the caret is on, counting from zero.
	///
	/// Read when a project is put away, so returning to it comes back to the
	/// line that was being worked on rather than the top of the file.
	var caretLine: Int {
		guard let document else { return 0 }
		let rope = document.rope
		return rope.line(atByteOffset: rope.byteOffset(fromUTF16: caret))
	}

	/// Returns false when the file had not actually changed.
	@discardableResult
	func reloadFromDisk() -> Bool {
		guard let document else { return false }

		let rope = document.rope
		let caretByte = rope.byteOffset(fromUTF16: caret)
		let caretLine = rope.line(atByteOffset: caretByte)
		let caretColumn = caret - rope.utf16Offset(fromByte: rope.lineByteRange(caretLine).lowerBound)
		let collapsed = folding.collapsed
		let scrollOffset = enclosingScrollView?.contentView.bounds.origin ?? .zero

		guard (try? document.reloadFromDisk()) == true else { return false }

		// Folds are recomputed from the new parse; the ones that still exist at
		// the same line stay closed.
		folding = FoldingState()
		folding.setAvailable(document.folds)
		for line in collapsed where folding.isFoldable(line: line) {
			folding.toggle(line: line)
		}

		let line = min(caretLine, max(0, document.lineCount - 1))
		let lineRange = document.rope.lineByteRange(line)
		let lineStart = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let lineLength = document.rope.utf16Offset(fromByte: lineRange.upperBound) - lineStart
		caret = lineStart + min(caretColumn, max(0, lineLength))
		selectionAnchor = caret

		measureLongestLine()
		rebuildWrapLayout()
		updateFrameSize()
		// Restored after the frame is resized, or the offset is clamped against
		// a document that has not grown yet.
		enclosingScrollView?.contentView.scroll(to: scrollOffset)
		enclosingScrollView?.reflectScrolledClipView(enclosingScrollView!.contentView)

		needsDisplay = true
		reportCaretPosition()
		return true
	}

	func load(document: TextDocument) {
		self.document = document
		caret = 0
		selectionAnchor = 0
		folding = FoldingState()
		folding.setAvailable(document.folds)

		document.onSyntaxUpdated = { [weak self] in
			guard let self, let document = self.document else { return }
			// Editing may have invalidated regions; keep collapse state where the
			// regions survived.
			self.folding.setAvailable(document.folds)
			self.rebuildWrapLayout()
			self.updateFrameSize()
			self.needsDisplay = true
		}

		measureLongestLine()
		updateFrameSize()
		scroll(NSPoint(x: 0, y: 0))
		needsDisplay = true
		restartCaretBlink()
		reportCaretPosition()
	}

	/// Measured off the main thread; a very large file should not delay the
	/// first paint just to learn how wide its scroll range is.
	private func measureLongestLine() {
		guard let document else { return }
		let snapshot = document.rope
		// Start with something reasonable so the view is usable immediately.
		longestLineColumns = 120
		let tabWidth = Theme.current.tabWidth
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let longest = snapshot.longestLineDisplayColumns(tabWidth: tabWidth)
			DispatchQueue.main.async {
				guard let self else { return }
				self.longestLineColumns = max(40, longest)
				self.updateFrameSize()
			}
		}
	}

	// MARK: - Geometry

	private var visibleLineCount: Int {
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
	private var wrapColumns: Int? {
		isWordWrapEnabled ? wrapLayout.columns : nil
	}

	/// Display width of a line in columns, expanding tabs.
	private func displayColumns(ofLine line: Int) -> Int {
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

	private func rebuildWrapLayout() {
		guard let document, isWordWrapEnabled else { return }
		// Built from what fits now, not from what the last layout used, and
		// counted by the same walk that slices the rows.
		let columns = availableColumns
		let tabWidth = Theme.current.tabWidth
		wrapLayout.rebuild(
			documentLineCount: document.lineCount,
			columns: columns,
			folding: folding
		) { [weak self] line in
			guard let self, let document = self.document, let columns else { return 1 }
			return WrapLayout.rowCount(
				in: document.rope.lineText(line),
				columns: columns,
				tabWidth: tabWidth
			)
		}
	}

	/// Document line for a visual row, honouring both folding and wrapping.
	private func documentLine(forVisualRow row: Int) -> Int {
		if isWordWrapEnabled { return wrapLayout.position(forRow: row).line }
		return folding.documentLine(forVisualLine: row)
	}

	/// Which wrapped segment of its line a row shows.
	private func wrapSegment(forVisualRow row: Int) -> Int {
		isWordWrapEnabled ? wrapLayout.position(forRow: row).segment : 0
	}

	private func firstVisualRow(forDocumentLine line: Int) -> Int {
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
		guard isWordWrapEnabled, availableColumns != wrapLayout.columns else { return }
		updateFrameSize()
		needsDisplay = true
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

	private func updateFrameSize() {
		guard let document else { return }
		let digits = max(2, String(document.lineCount).count)
		// The extra column on the left is the breakpoint gutter.
		gutterWidth = ceil(CGFloat(digits) * charWidth) + Self.gutterPadding * 2 + 14 + Self.breakpointColumnWidth

		if isWordWrapEnabled { rebuildWrapLayout() }

		let height = CGFloat(visibleLineCount) * lineHeight + lineHeight
		let clipWidth = enclosingScrollView?.contentSize.width ?? bounds.width

		// Wrapped text never scrolls horizontally, so the document is exactly as
		// wide as the viewport.
		let width = isWordWrapEnabled
			? clipWidth
			: gutterWidth + Self.textLeftPadding + CGFloat(longestLineColumns) * charWidth + 40

		setFrameSize(NSSize(width: max(width, clipWidth), height: max(height, 10)))
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		needsDisplay = true
	}

	/// Visual rows intersecting a rect, clamped to the document.
	private func visualLineRange(in rect: NSRect) -> Range<Int> {
		let first = max(0, Int(floor(rect.minY / lineHeight)) - Self.overscanLines)
		let last = min(visibleLineCount, Int(ceil(rect.maxY / lineHeight)) + Self.overscanLines)
		guard last > first else { return 0..<0 }
		return first..<last
	}

	private func yPosition(forVisualLine visual: Int) -> CGFloat {
		CGFloat(visual) * lineHeight
	}

	private var textOriginX: CGFloat { gutterWidth + Self.textLeftPadding }

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		guard let context = NSGraphicsContext.current?.cgContext else { return }

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

			drawSearchHighlights(docLine: docLine, rect: rowRect)

			drawLine(
				docLine: docLine,
				segment: segment,
				rect: rowRect,
				tokenIndex: tokenIndex,
				selection: selection,
				context: context
			)
		}
		context.restoreGState()

		drawGutter(rows: rows, caretLine: caretLine, scrollX: scrollX, context: context)

		if caretVisible, window?.firstResponder === self, selection.isEmpty {
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

		// This view is flipped, which inverts the context's y-axis. CoreText would
		// otherwise render every glyph upside down, so the text matrix flips it
		// back. (AppKit's own -[NSAttributedString drawAtPoint:] compensates
		// internally, which is why the gutter and tab labels need no such fix.)
		context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
		context.textPosition = CGPoint(x: textOriginX, y: baseline)
		CTLineDraw(ctLine, context)

		drawDiagnostics(docLine: docLine, ctLine: ctLine, lineStartUTF16: lineStartUTF16, rect: rect)

		// A collapsed region gets a "{…}" chip after its first line.
		if folding.isCollapsed(line: docLine) {
			let textWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
			drawFoldPlaceholder(
				at: NSPoint(x: textOriginX + textWidth + 6, y: rect.minY),
				hiddenLines: folding.foldRange(startingAt: docLine)?.hiddenLineCount ?? 0
			)
		}
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

			Self.color(for: diagnostic.severity).setStroke()
			squiggle(from: startX, to: endX, y: rect.maxY - Theme.current.scaled(2)).stroke()
		}
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

	static func color(for severity: LSPDiagnostic.Severity) -> NSColor {
		switch severity {
		case .error: return .hex(0xE05252)
		// Amber rather than the git blue: blue is what this window uses for
		// "changed", and a warning is not a change.
		case .warning: return .hex(0xD9A343)
		case .information, .hint: return Theme.current.gitIgnored
		}
	}

	// MARK: - Hovering

	/// The tooltip follows the pointer, so an underline can say what is wrong.
	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		for area in trackingAreas where area.owner === self {
			removeTrackingArea(area)
		}
		addTrackingArea(NSTrackingArea(
			rect: bounds,
			options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self
		))
	}

	override func mouseMoved(with event: NSEvent) {
		super.mouseMoved(with: event)
		guard hasDiagnostics, let document else {
			if toolTip != nil { toolTip = nil }
			return
		}

		let point = convert(event.locationInWindow, from: nil)
		guard point.x > gutterWidth else {
			toolTip = nil
			return
		}

		let offset = self.offset(at: point)
		let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: offset))
		let lineStart = document.rope.utf16Offset(fromByte: document.rope.byteOffset(ofLine: line))
		let column = offset - lineStart

		// The worst problem covering the pointer, since a place with an error
		// and a hint on it is somewhere the error is what matters.
		let covering = diagnostics(onLine: line).first { diagnostic in
			let start = diagnostic.range.start.character
			let end = diagnostic.range.end.line > line
				? Int.max
				: max(diagnostic.range.end.character, start + 1)
			return column >= start && column <= end
		}

		let text = covering.map { diagnostic -> String in
			guard let source = diagnostic.source else { return diagnostic.message }
			return "\(diagnostic.message)  (\(source))"
		}
		if text != toolTip { toolTip = text }
	}

	override func mouseExited(with event: NSEvent) {
		super.mouseExited(with: event)
		toolTip = nil
	}

	/// Paints match backgrounds for one line.
	private func drawSearchHighlights(docLine: Int, rect: NSRect) {
		guard !searchMatches.isEmpty, let document else { return }

		let lineRange = document.rope.lineByteRange(docLine)
		let lineStart = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let lineEnd = document.rope.utf16Offset(fromByte: lineRange.upperBound)

		let text = document.rope.string(in: lineRange)
		let ctLine = CTLineCreateWithAttributedString(attributedLine(
			text: text,
			lineStartUTF16: lineStart,
			tokenIndex: TokenIndex(tokens: [])
		))

		for (index, match) in searchMatches.enumerated() {
			// Matches are ordered, so stop once past this line.
			guard match.utf16Range.lowerBound <= lineEnd else { break }
			guard match.utf16Range.upperBound >= lineStart else { continue }

			let from = max(match.utf16Range.lowerBound, lineStart) - lineStart
			let to = min(match.utf16Range.upperBound, lineEnd) - lineStart
			guard to > from else { continue }

			let startX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, from, nil)
			let endX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, to, nil)

			// The current match is stronger, so it is findable at a glance among
			// the others.
			let isCurrent = index == currentMatchIndex
			(isCurrent ? NSColor.hex(0xC77B3B) : NSColor.hex(0x5A4A2A)).setFill()
			NSRect(x: startX, y: rect.minY, width: max(2, endX - startX), height: rect.height).fill()
		}
	}

	private func attributedLine(
		text: String,
		lineStartUTF16: Int,
		tokenIndex: TokenIndex
	) -> NSAttributedString {
		let paragraph = NSMutableParagraphStyle()
		// Explicit tab stops: CoreText otherwise collapses tabs to a default
		// width that does not match the gutter-relative grid.
		let tabColumns = CGFloat(Theme.current.tabWidth)
		paragraph.tabStops = (1...64).map {
			NSTextTab(textAlignment: .left, location: CGFloat($0) * charWidth * tabColumns, options: [:])
		}
		paragraph.defaultTabInterval = charWidth * tabColumns

		let attributed = NSMutableAttributedString(string: text, attributes: [
			.font: font,
			.foregroundColor: Theme.current.editorText,
			.paragraphStyle: paragraph,
		])

		let length = attributed.length
		guard length > 0 else { return attributed }

		for token in tokenIndex.tokens(overlapping: lineStartUTF16..<(lineStartUTF16 + length)) {
			let localStart = max(0, token.range.lowerBound - lineStartUTF16)
			let localEnd = min(length, token.range.upperBound - lineStartUTF16)
			guard localStart < localEnd else { continue }
			attributed.addAttribute(
				.foregroundColor,
				value: Theme.current.color(for: token.kind),
				range: NSRange(location: localStart, length: localEnd - localStart)
			)
		}
		return attributed
	}

	private func drawSelection(
		ctLine: CTLine,
		lineStartUTF16: Int,
		lineEndUTF16: Int,
		selection: Range<Int>,
		rect: NSRect
	) {
		let from = max(selection.lowerBound, lineStartUTF16) - lineStartUTF16
		let to = min(selection.upperBound, lineEndUTF16) - lineStartUTF16
		guard to >= from else { return }

		let startX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, from, nil)
		var endX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, to, nil)

		// A selection spanning the newline should show the line break as a sliver
		// of highlight rather than nothing at all.
		if selection.upperBound > lineEndUTF16 {
			endX += charWidth * 0.6
		}

		Theme.current.selectionBackground.setFill()
		NSRect(x: startX, y: rect.minY, width: max(1, endX - startX), height: rect.height).fill()
	}

	private func drawFoldPlaceholder(at origin: NSPoint, hiddenLines: Int) {
		let label = hiddenLines > 0 ? "⋯ \(hiddenLines) lines" : "⋯"
		let attributed = NSAttributedString(string: label, attributes: [
			.font: NSFont.monospacedSystemFont(ofSize: Theme.current.fontSize - 1, weight: .regular),
			.foregroundColor: Theme.current.foldPlaceholderText,
		])
		let size = attributed.size()
		let box = NSRect(x: origin.x, y: origin.y + 2, width: size.width + 10, height: lineHeight - 4)

		let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
		Theme.current.foldPlaceholderBackground.setFill()
		path.fill()

		attributed.draw(at: NSPoint(x: box.minX + 5, y: box.midY - size.height / 2))
	}

	// MARK: - Gutter

	private func drawGutter(rows: Range<Int>, caretLine: Int, scrollX: CGFloat, context: CGContext) {
		guard let document else { return }

		// Opaque so text scrolling underneath is hidden rather than showing through.
		Theme.current.editorBackground.setFill()
		NSRect(x: scrollX,
		       y: CGFloat(rows.lowerBound) * lineHeight,
		       width: gutterWidth,
		       height: CGFloat(rows.count) * lineHeight).fill()

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
				drawRunMarker(y: y, scrollX: scrollX)
			} else {
				drawBreakpoint(docLine: docLine, y: y, scrollX: scrollX)
			}

			let number = NSAttributedString(string: "\(docLine + 1)", attributes: [
				.font: font,
				.foregroundColor: isCurrent ? Theme.current.gutterCurrentLineText : Theme.current.gutterText,
			])
			let size = number.size()
			// Right-aligned against the fold column.
			number.draw(at: NSPoint(
				x: scrollX + gutterWidth - 14 - Self.gutterPadding - size.width,
				y: y + (lineHeight - size.height) / 2
			))

			if folding.isFoldable(line: docLine) {
				drawFoldHandle(
					at: NSPoint(x: scrollX + gutterWidth - 12, y: y + lineHeight / 2),
					collapsed: folding.isCollapsed(line: docLine)
				)
			}
		}
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

	private func drawBreakpoint(docLine: Int, y: CGFloat, scrollX: CGFloat) {
		let size = Theme.current.scaled(9)
		let centre = NSPoint(
			x: scrollX + Self.breakpointColumnWidth / 2,
			y: y + lineHeight / 2
		)

		if let verified = breakpointLines[docLine] {
			let rect = NSRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
			let path = NSBezierPath(ovalIn: rect)
			if verified {
				NSColor.hex(0xD16969).setFill()
				path.fill()
			} else {
				// Hollow when unbound: a solid marker where execution can never
				// stop would be a lie.
				NSColor.hex(0xD16969).withAlphaComponent(0.7).setStroke()
				path.lineWidth = 1.5
				path.stroke()
			}

			// A conditional breakpoint is marked, because "why did it not
			// stop" and "why did it stop" are both answered by remembering
			// that this one has a condition on it.
			if conditionalBreakpointLines.contains(docLine) {
				let tick = NSBezierPath()
				tick.lineWidth = 1.6
				tick.move(to: NSPoint(x: rect.minX + 1.5, y: rect.midY + 1))
				tick.line(to: NSPoint(x: rect.midX, y: rect.maxY - 1.5))
				tick.line(to: NSPoint(x: rect.maxX - 1, y: rect.minY + 1.5))
				(verified ? NSColor.hex(0x2B2B2B) : NSColor.hex(0xD16969)).setStroke()
				tick.stroke()
			}
		}

		guard docLine == executionLine else { return }
		// A small arrow marking the current statement.
		let arrow = NSBezierPath()
		let half = size / 2
		arrow.move(to: NSPoint(x: centre.x - half, y: centre.y - half))
		arrow.line(to: NSPoint(x: centre.x + half, y: centre.y))
		arrow.line(to: NSPoint(x: centre.x - half, y: centre.y + half))
		arrow.close()
		NSColor.hex(0xE8BF6A).setFill()
		arrow.fill()
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

	private func drawCaret(context: CGContext) {
		guard let position = caretPoint() else { return }
		Theme.current.caret.setFill()
		NSRect(x: position.x, y: position.y, width: 2, height: lineHeight).fill()
	}

	private func caretPoint() -> NSPoint? {
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
	private func wrapSegmentForOffset(_ offset: Int, line: Int) -> Int {
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

	private func restartCaretBlink() {
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
		restartCaretBlink()
		return true
	}

	override func resignFirstResponder() -> Bool {
		caretTimer?.invalidate()
		caretVisible = false
		needsDisplay = true
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

	// MARK: - Debugging

	/// Lines with a play button, given 1-based as the run configurations
	/// report them.
	func setRunnableLines(_ lines: Set<Int>) {
		guard lines != runnableLines else { return }
		runnableLines = lines
		needsDisplay = true
		window?.invalidateCursorRects(for: self)
	}

	/// A pointing hand over each play button.
	///
	/// The rest of the gutter keeps the arrow: the breakpoint column responds to
	/// a click too, but a play button is the only part that reads as a control,
	/// and marking everything would say nothing.
	override func resetCursorRects() {
		super.resetCursorRects()
		guard !runnableLines.isEmpty else { return }

		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0
		let visible = enclosingScrollView?.contentView.bounds ?? bounds
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

	/// Breakpoints to draw, keyed by 0-based line, with whether the adapter
	/// verified each one.
	func setBreakpoints(_ lines: [Int: Bool]) {
		breakpointLines = lines
		needsDisplay = true
	}

	/// The line execution is stopped on, or nil when not stopped here.
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
		if let current, matches.indices.contains(current) {
			// Select the match so Escape leaves the caret somewhere sensible.
			let range = matches[current].utf16Range
			selectionAnchor = range.lowerBound
			caret = range.upperBound
			revealCurrentMatch()
		}
		needsDisplay = true
	}

	func clearSearchMatches() {
		searchMatches = []
		currentMatchIndex = nil
		needsDisplay = true
	}

	private func revealCurrentMatch() {
		guard let document, let index = currentMatchIndex, searchMatches.indices.contains(index) else { return }
		let match = searchMatches[index]
		let byte = document.rope.byteOffset(fromUTF16: match.utf16Range.lowerBound)
		let line = document.rope.line(atByteOffset: byte)

		folding.reveal(line: line)
		updateFrameSize()

		guard let point = caretPoint(), let scrollView = enclosingScrollView else { return }
		let height = scrollView.contentSize.height
		// Only scroll when the match is off screen, so stepping through nearby
		// matches does not make the view jump on every step.
		let visible = scrollView.contentView.bounds
		if point.y < visible.minY + lineHeight || point.y > visible.maxY - lineHeight * 2 {
			scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, point.y - height / 2)))
			scrollView.reflectScrolledClipView(scrollView.contentView)
		}
		needsDisplay = true
	}

	/// Moves the caret to a 1-based line and scrolls it into view.
	/// Used when jumping to a review finding or a search result.
	func reveal(line: Int, column: Int = 1) {
		guard let document else { return }
		let target = max(0, min(line - 1, document.lineCount - 1))
		folding.reveal(line: target)

		let lineRange = document.rope.lineByteRange(target)
		let start = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let end = document.rope.utf16Offset(fromByte: lineRange.upperBound)
		let offset = min(end, start + max(0, column - 1))

		updateFrameSize()
		setCaret(offset, extendingSelection: false)

		// Centre the line rather than merely making it visible, so there is
		// context around what was jumped to.
		if let point = caretPoint(), let scrollView = enclosingScrollView {
			let height = scrollView.contentSize.height
			let y = max(0, point.y - height / 2)
			scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
			scrollView.reflectScrolledClipView(scrollView.contentView)
		}
	}

	// MARK: - Selection helpers

	private func selectedUTF16Range() -> Range<Int> {
		let lower = min(caret, selectionAnchor)
		let upper = max(caret, selectionAnchor)
		return lower..<upper
	}

	private func setCaret(_ offset: Int, extendingSelection: Bool) {
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

	private func reportCaretPosition() {
		guard let document else { return }
		let byteOffset = document.rope.byteOffset(fromUTF16: caret)
		let line = document.rope.line(atByteOffset: byteOffset)
		let lineStart = document.rope.byteOffset(ofLine: line)
		let column = document.rope.utf16Offset(fromByte: byteOffset) - document.rope.utf16Offset(fromByte: lineStart)
		onCaretMoved?(line + 1, column + 1)
	}

	private func scrollCaretToVisible() {
		guard let point = caretPoint() else { return }
		let rect = NSRect(x: max(0, point.x - 40), y: point.y, width: 80, height: lineHeight)
		scrollToVisible(rect)
	}

	// MARK: - Hit testing

	/// UTF-16 offset at a point in view coordinates.
	private func offset(at point: NSPoint) -> Int {
		guard let document else { return 0 }

		let visual = max(0, min(visibleLineCount - 1, Int(floor(point.y / lineHeight))))
		let docLine = min(document.lineCount - 1, documentLine(forVisualRow: visual))
		let segment = wrapSegment(forVisualRow: visual)

		let lineRange = document.rope.lineByteRange(docLine)
		var lineStartUTF16 = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		var text = document.rope.string(in: lineRange)

		if isWordWrapEnabled, let columns = wrapColumns {
			let ns = text as NSString
			let range = WrapLayout.segmentRange(
				in: text,
				segment: segment,
				columns: columns,
				tabWidth: Theme.current.tabWidth
			)
			text = ns.substring(with: NSRange(location: range.lowerBound, length: range.count))
			lineStartUTF16 += range.lowerBound
		}

		let ctLine = CTLineCreateWithAttributedString(attributedLine(
			text: text,
			lineStartUTF16: lineStartUTF16,
			tokenIndex: TokenIndex(tokens: [])
		))
		// CTLine hit testing handles tabs and non-monospace fallback glyphs,
		// which dividing by a fixed advance would get wrong.
		let index = CTLineGetStringIndexForPosition(ctLine, CGPoint(x: point.x - textOriginX, y: 0))
		let local = max(0, min((text as NSString).length, index))
		return lineStartUTF16 + local
	}

	// MARK: - Mouse

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let point = convert(event.locationInWindow, from: nil)

		// Gutter clicks toggle folds rather than moving the caret. The gutter is
		// pinned to the clip view, so its hit area moves with horizontal scroll.
		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0
		if point.x < scrollX + gutterWidth {
			handleGutterClick(at: point)
			return
		}

		desiredColumnX = nil
		let offset = self.offset(at: point)

		// ⌘-click follows a symbol, as it does in every other editor. The caret
		// moves there first, so the place jumped from is where it was left.
		if event.modifierFlags.contains(.command), let document {
			setCaret(offset, extendingSelection: false)
			let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: offset))
			let lineStart = document.rope.utf16Offset(fromByte: document.rope.byteOffset(ofLine: line))
			onGoToDefinition?(line, offset - lineStart)
			return
		}

		switch event.clickCount {
		case 2:
			selectWord(at: offset)
		case 3:
			selectLine(at: offset)
		default:
			setCaret(offset, extendingSelection: event.modifierFlags.contains(.shift))
		}
	}

	override func rightMouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0

		// A right-click in the breakpoint column edits that breakpoint. It is
		// where the breakpoint is, so it is where somebody aims to change it.
		if point.x < scrollX + Self.breakpointColumnWidth, let document {
			let visual = max(0, min(visibleLineCount - 1, Int(floor(point.y / lineHeight))))
			let docLine = min(document.lineCount - 1, documentLine(forVisualRow: visual))
			onEditBreakpoint?(docLine)
			return
		}
		super.rightMouseDown(with: event)
	}

	override func mouseDragged(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		guard point.x >= gutterWidth || caret != selectionAnchor else { return }
		setCaret(offset(at: point), extendingSelection: true)
	}

	private func handleGutterClick(at point: NSPoint) {
		guard let document else { return }
		let visual = max(0, min(visibleLineCount - 1, Int(floor(point.y / lineHeight))))
		let docLine = min(document.lineCount - 1, documentLine(forVisualRow: visual))

		// The leftmost strip is the breakpoint column, or the run button when
		// the line has one.
		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0
		if point.x < scrollX + Self.breakpointColumnWidth {
			if runnableLines.contains(docLine + 1), breakpointLines[docLine] == nil {
				onRunLine?(docLine + 1)
			} else {
				onToggleBreakpoint?(docLine)
			}
			return
		}


		guard folding.isFoldable(line: docLine) else { return }

		folding.toggle(line: docLine)
		updateFrameSize()
		needsDisplay = true
	}

	private func selectWord(at offset: Int) {
		guard let document else { return }
		let byteOffset = document.rope.byteOffset(fromUTF16: offset)
		let line = document.rope.line(atByteOffset: byteOffset)
		let lineRange = document.rope.lineByteRange(line)
		let lineStartUTF16 = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let text = document.rope.string(in: lineRange) as NSString

		var start = max(0, min(offset - lineStartUTF16, text.length))
		var end = start

		func isWordCharacter(_ index: Int) -> Bool {
			guard index >= 0 && index < text.length else { return false }
			let scalar = text.character(at: index)
			guard let unicode = Unicode.Scalar(scalar) else { return false }
			return CharacterSet.alphanumerics.contains(unicode) || scalar == UInt16(UnicodeScalar("_").value)
		}

		while isWordCharacter(start - 1) { start -= 1 }
		while isWordCharacter(end) { end += 1 }
		guard end > start else { return }

		selectionAnchor = lineStartUTF16 + start
		caret = lineStartUTF16 + end
		restartCaretBlink()
		needsDisplay = true
		reportCaretPosition()
	}

	private func selectLine(at offset: Int) {
		guard let document else { return }
		let byteOffset = document.rope.byteOffset(fromUTF16: offset)
		let line = document.rope.line(atByteOffset: byteOffset)
		let range = document.rope.lineByteRange(line)
		selectionAnchor = document.rope.utf16Offset(fromByte: range.lowerBound)
		caret = document.rope.utf16Offset(fromByte: range.upperBound)
		restartCaretBlink()
		needsDisplay = true
	}

	// MARK: - Keyboard

	/// Caret offset and selection, for checking that a motion landed.
	var caretReportForTesting: String {
		let selection = selectedUTF16Range()
		let text = document.map { document -> String in
			let range = selection.isEmpty ? caret..<caret : selection
			let lower = document.rope.byteOffset(fromUTF16: range.lowerBound)
			let upper = document.rope.byteOffset(fromUTF16: range.upperBound)
			return document.rope.string(in: lower..<upper)
		} ?? ""
		return "caret=\(caret) selection=\(selection.lowerBound)..<\(selection.upperBound) “\(text)”"
	}

	override func keyDown(with event: NSEvent) {
		// Routes through the input system so dead keys, IME, and the standard
		// key bindings all behave as they do in a native text view.
		interpretKeyEvents([event])
	}

	override func doCommand(by selector: Selector) {
		// The list is on screen and these keys belong to it: up and down move
		// the highlight, return takes the highlighted one, escape puts it away.
		// Everything else keeps going into the document, so the list narrows as
		// typing continues rather than swallowing it.
		if completionKeyHandler?(selector) == true { return }

		switch selector {
		case #selector(moveLeft(_:)):            moveHorizontally(-1, extending: false)
		case #selector(moveRight(_:)):           moveHorizontally(1, extending: false)
		case #selector(moveLeftAndModifySelection(_:)):  moveHorizontally(-1, extending: true)
		case #selector(moveRightAndModifySelection(_:)): moveHorizontally(1, extending: true)
		case #selector(moveUp(_:)):              moveVertically(-1, extending: false)
		case #selector(moveDown(_:)):            moveVertically(1, extending: false)
		case #selector(moveUpAndModifySelection(_:)):    moveVertically(-1, extending: true)
		case #selector(moveDownAndModifySelection(_:)):  moveVertically(1, extending: true)
		case #selector(moveToBeginningOfLine(_:)), #selector(moveToLeftEndOfLine(_:)):
			moveToLineEdge(start: true, extending: false)
		case #selector(moveToEndOfLine(_:)), #selector(moveToRightEndOfLine(_:)):
			moveToLineEdge(start: false, extending: false)
		case #selector(moveToBeginningOfLineAndModifySelection(_:)), #selector(moveToLeftEndOfLineAndModifySelection(_:)):
			moveToLineEdge(start: true, extending: true)
		case #selector(moveToEndOfLineAndModifySelection(_:)), #selector(moveToRightEndOfLineAndModifySelection(_:)):
			moveToLineEdge(start: false, extending: true)
		case #selector(moveWordLeft(_:)), #selector(moveWordBackward(_:)):
			moveByWord(-1, extending: false)
		case #selector(moveWordRight(_:)), #selector(moveWordForward(_:)):
			moveByWord(1, extending: false)
		case #selector(moveWordLeftAndModifySelection(_:)),
		     #selector(moveWordBackwardAndModifySelection(_:)):
			moveByWord(-1, extending: true)
		case #selector(moveWordRightAndModifySelection(_:)),
		     #selector(moveWordForwardAndModifySelection(_:)):
			moveByWord(1, extending: true)
		case #selector(deleteWordBackward(_:)):  deleteByWord(-1)
		case #selector(deleteWordForward(_:)):   deleteByWord(1)
		case #selector(deleteToBeginningOfLine(_:)): deleteToLineEdge(start: true)
		case #selector(deleteToEndOfLine(_:)):   deleteToLineEdge(start: false)
		case #selector(moveToBeginningOfDocument(_:)):   setCaret(0, extendingSelection: false)
		case #selector(moveToEndOfDocument(_:)):
			setCaret(document?.rope.utf16Count ?? 0, extendingSelection: false)
		case #selector(scrollPageUp(_:)), #selector(pageUp(_:)):     movePage(-1, extending: false)
		case #selector(scrollPageDown(_:)), #selector(pageDown(_:)): movePage(1, extending: false)
		case #selector(deleteBackward(_:)):      deleteBackward()
		case #selector(deleteForward(_:)):       deleteForward()
		case #selector(insertNewline(_:)):       insertNewlineWithIndent()
		case #selector(insertTab(_:)):           insertTextAtCaret("\t")
		case #selector(selectAll(_:)):           selectAllText()
		case #selector(insertLineBreak(_:)):     insertTextAtCaret("\n")
		default:
			// Unhandled selectors are common (e.g. noop:); staying silent is right.
			break
		}
	}

	// MARK: Movement

	private func moveHorizontally(_ delta: Int, extending: Bool) {
		guard let document else { return }
		desiredColumnX = nil

		let selection = selectedUTF16Range()
		// Collapsing a selection with an arrow key should jump to its edge.
		if !extending, !selection.isEmpty {
			setCaret(delta < 0 ? selection.lowerBound : selection.upperBound, extendingSelection: false)
			return
		}

		// Step by composed character so emoji and combining marks move as one.
		let target = document.rope.utf16Count
		var offset = caret + delta
		offset = max(0, min(offset, target))
		if delta != 0 {
			let byte = document.rope.alignToBoundary(document.rope.byteOffset(fromUTF16: offset))
			offset = document.rope.utf16Offset(fromByte: byte)
		}
		setCaret(offset, extendingSelection: extending)
	}

	/// ⌥← and ⌥→.
	///
	/// The text either side of the caret is read as a window rather than the
	/// whole document: a word is a few characters away, and asking a rope for a
	/// megabyte to find the next space would make the arrow key slower the
	/// longer the file got.
	private func wordTarget(_ direction: Int) -> Int? {
		guard let document else { return nil }
		let total = document.rope.utf16Count

		// Wide enough for any word anybody writes, and for the run of
		// whitespace before it; grown once if the answer lands on the edge.
		var span = 256
		while true {
			let lower = max(0, caret - (direction < 0 ? span : 0))
			let upper = min(total, caret + (direction > 0 ? span : 0))
			let lowerByte = document.rope.byteOffset(fromUTF16: lower)
			let upperByte = document.rope.byteOffset(fromUTF16: upper)
			let window = Array(document.rope.string(in: lowerByte..<upperByte).utf16)

			let local = caret - lower
			let target = direction < 0
				? WordMotion.startOfWord(before: local, in: window)
				: WordMotion.endOfWord(after: local, in: window)
			let absolute = lower + target

			// Landing on the edge of the window means the answer may be past it
			// — unless the edge is the edge of the document.
			let clipped = direction < 0 ? (absolute == lower && lower > 0) : (absolute == upper && upper < total)
			guard clipped, span < 65_536 else { return absolute }
			span *= 8
		}
	}

	private func moveByWord(_ direction: Int, extending: Bool) {
		desiredColumnX = nil
		guard let target = wordTarget(direction) else { return }
		setCaret(target, extendingSelection: extending)
	}

	/// ⌥⌫ and ⌥⌦: take the word, not the character.
	private func deleteByWord(_ direction: Int) {
		guard let document else { return }
		let selection = selectedUTF16Range()
		if !selection.isEmpty {
			afterEdit(caret: document.replace(
				utf16Range: selection, with: "", caretBefore: selection.upperBound
			))
			return
		}

		guard let target = wordTarget(direction), target != caret else { return }
		let range = direction < 0 ? target..<caret : caret..<target
		afterEdit(caret: document.replace(utf16Range: range, with: "", caretBefore: caret))
	}

	/// ⌘⌫ and ⌘⌦, which the same key mapping produces.
	private func deleteToLineEdge(start: Bool) {
		guard let document else { return }
		let byteOffset = document.rope.byteOffset(fromUTF16: caret)
		let line = document.rope.line(atByteOffset: byteOffset)
		let lineRange = document.rope.lineByteRange(line)
		let lineStart = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let lineEnd = document.rope.utf16Offset(fromByte: lineRange.upperBound)

		let range = start ? lineStart..<caret : caret..<lineEnd
		guard !range.isEmpty else { return }
		afterEdit(caret: document.replace(utf16Range: range, with: "", caretBefore: caret))
	}

	private func moveVertically(_ delta: Int, extending: Bool) {
		guard let document else { return }

		let byteOffset = document.rope.byteOffset(fromUTF16: caret)
		let docLine = document.rope.line(atByteOffset: byteOffset)
		let visual = folding.visualLine(forDocumentLine: docLine)

		let targetVisual = max(0, min(visibleLineCount - 1, visual + delta))
		guard targetVisual != visual else { return }

		// Remember the x the caret started from so a run of ups and downs keeps
		// returning to the same column.
		if desiredColumnX == nil {
			desiredColumnX = caretPoint().map { $0.x } ?? textOriginX
		}
		let x = desiredColumnX ?? textOriginX

		let point = NSPoint(x: x, y: yPosition(forVisualLine: targetVisual) + lineHeight / 2)
		let column = desiredColumnX
		setCaret(offset(at: point), extendingSelection: extending)
		desiredColumnX = column
	}

	private func movePage(_ direction: Int, extending: Bool) {
		let rows = max(1, Int((enclosingScrollView?.contentSize.height ?? bounds.height) / lineHeight) - 2)
		moveVertically(direction * rows, extending: extending)
	}

	private func moveToLineEdge(start: Bool, extending: Bool) {
		guard let document else { return }
		desiredColumnX = nil
		let byteOffset = document.rope.byteOffset(fromUTF16: caret)
		let line = document.rope.line(atByteOffset: byteOffset)
		let range = document.rope.lineByteRange(line)

		if start {
			// First press goes to the first non-blank character, which is what a
			// code editor should do; only then to column zero.
			let text = document.rope.string(in: range)
			let indent = text.prefix { $0 == " " || $0 == "\t" }
			let indentEnd = document.rope.utf16Offset(fromByte: range.lowerBound) + (String(indent) as NSString).length
			let lineStart = document.rope.utf16Offset(fromByte: range.lowerBound)
			setCaret(caret == indentEnd ? lineStart : indentEnd, extendingSelection: extending)
		} else {
			setCaret(document.rope.utf16Offset(fromByte: range.upperBound), extendingSelection: extending)
		}
	}

	private func selectAllText() {
		guard let document else { return }
		selectionAnchor = 0
		caret = document.rope.utf16Count
		needsDisplay = true
	}

	// MARK: Editing

	/// Return: keep the indent, add a level after an opening, and put a closing
	/// brace on its own line when splitting a pair.
	private func insertNewlineWithIndent() {
		guard let document else { return }
		let selection = selectedUTF16Range()
		let range = selection.isEmpty ? caret..<caret : selection

		// The line as it will be once the selection is gone: what is left of
		// the caret and what is right of it.
		let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: range.lowerBound))
		let lineRange = document.rope.lineByteRange(line)
		let lineStart = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let lineEnd = document.rope.utf16Offset(fromByte: lineRange.upperBound)
		let text = document.rope.string(in: lineRange) as NSString

		let before = text.substring(
			with: NSRange(location: 0, length: max(0, min(range.lowerBound - lineStart, text.length)))
		)
		let afterStart = max(0, min(range.upperBound - lineStart, text.length))
		let after = text.substring(from: afterStart)
			.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
		_ = lineEnd

		let result = ReturnIndent.result(
			before: before,
			after: after,
			usesTabs: usesTabsForIndent,
			indentWidth: Theme.current.tabWidth
		)

		let newCaret = document.replace(
			utf16Range: range, with: result.text, caretBefore: range.lowerBound
		)
		// The caret lands where the result says, which for a split pair is the
		// blank line between the halves rather than after the closing one.
		afterEdit(caret: range.lowerBound + result.caretOffset)
		_ = newCaret
	}

	/// A closing brace typed on an otherwise blank line moves out a level, so
	/// it lines up with whatever opened the block instead of with its contents.
	private func dedentIfClosingBrace(_ typed: String) {
		guard let document, typed.count == 1, let character = typed.first else { return }

		let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: caret))
		let lineRange = document.rope.lineByteRange(line)
		let lineStart = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let text = document.rope.string(in: lineRange) as NSString

		// Everything before the brace that was just typed.
		let beforeLength = max(0, min(caret - lineStart - 1, text.length))
		let before = text.substring(with: NSRange(location: 0, length: beforeLength))
		guard ReturnIndent.shouldDedent(afterTyping: character, lineBefore: before) else { return }

		let dedented = ReturnIndent.dedented(
			before, usesTabs: usesTabsForIndent, indentWidth: Theme.current.tabWidth
		)
		guard dedented != before else { return }

		let newCaret = document.replace(
			utf16Range: lineStart..<(lineStart + beforeLength),
			with: dedented,
			caretBefore: caret
		)
		afterEdit(caret: newCaret + 1)
	}

	/// Whether this file indents with tabs, judged by what it already does.
	private var usesTabsForIndent: Bool {
		guard let document else { return false }
		// A window of the top of the file: enough to see the habit, cheap on a
		// file of any size.
		let sample = document.rope.string(in: 0..<min(document.rope.byteCount, 8192))
		return ReturnIndent.usesTabs(in: sample, default: false)
	}

	private func insertTextAtCaret(_ text: String) {
		guard let document else { return }
		let selection = selectedUTF16Range()
		let range = selection.isEmpty ? caret..<caret : selection

		let newCaret = document.replace(utf16Range: range, with: text, caretBefore: range.lowerBound)
		afterEdit(caret: newCaret)
		dedentIfClosingBrace(text)
		requestCompletionsIfTyping(text)
	}

	/// Offers completions for whatever word the caret is now in.
	///
	/// Only after typing something a word can be made of. A newline, a bracket
	/// or a space ends the word rather than continuing it, and a list that
	/// stayed up through those would be in the way of the next thing typed.
	private func requestCompletionsIfTyping(_ typed: String) {
		guard let document else { return }
		guard typed.count == 1, let character = typed.first,
		      character.isLetter || character.isNumber || character == "_" || character == "."
		else {
			onDismissCompletions?()
			return
		}

		let prefix = currentWordPrefix()
		guard !prefix.isEmpty || character == "." else {
			onDismissCompletions?()
			return
		}

		guard let point = caretPoint() else {
			onDismissCompletions?()
			return
		}
		onRequestCompletions?(prefix, point)
		_ = document
	}

	/// The identifier being typed immediately before the caret.
	func currentWordPrefix() -> String {
		guard let document else { return "" }
		let lower = max(0, caret - 128)
		let lowerByte = document.rope.byteOffset(fromUTF16: lower)
		let caretByte = document.rope.byteOffset(fromUTF16: caret)
		let window = Array(document.rope.string(in: lowerByte..<caretByte).utf16)
		return WordMotion.prefix(before: window.count, in: window)
	}

	/// Replaces the word being typed with what was chosen.
	func applyCompletion(_ text: String, replacingPrefixOfLength length: Int) {
		guard let document else { return }
		let start = max(0, caret - length)
		let newCaret = document.replace(utf16Range: start..<caret, with: text, caretBefore: caret)
		afterEdit(caret: newCaret)
	}

	/// Where the caret is on screen, for putting the list under it.
	func caretScreenPoint() -> NSPoint? {
		guard let point = caretPoint(), let window else { return nil }
		let inWindow = convert(NSPoint(x: point.x, y: point.y), to: nil)
		return window.convertPoint(toScreen: inWindow)
	}

	var lineHeightForTesting: CGFloat { lineHeight }

	func setCaretForTesting(_ offset: Int) {
		setCaret(offset, extendingSelection: false)
	}

	/// The document jumped to another state: everything measured from its text
	/// has to be worked out again.
	func reloadAfterHistoryTravel() {
		guard let document else { return }
		folding.setAvailable(document.folds)
		caret = min(caret, document.rope.utf16Count)
		selectionAnchor = caret
		updateFrameSize()
		scrollCaretToVisible()
		needsDisplay = true
		reportCaretPosition()
		onDirtyChanged?(document.isDirty)
	}

	private func deleteBackward() {
		guard let document else { return }
		let selection = selectedUTF16Range()

		if !selection.isEmpty {
			let newCaret = document.replace(utf16Range: selection, with: "", caretBefore: selection.upperBound)
			afterEdit(caret: newCaret)
			return
		}
		guard caret > 0 else { return }

		// Delete a whole composed character, not one UTF-16 unit.
		let byteEnd = document.rope.byteOffset(fromUTF16: caret)
		let byteStart = document.rope.alignToBoundary(byteEnd - 1)
		let start = document.rope.utf16Offset(fromByte: byteStart)

		let newCaret = document.replace(utf16Range: start..<caret, with: "", caretBefore: caret)
		afterEdit(caret: newCaret)
	}

	private func deleteForward() {
		guard let document else { return }
		let selection = selectedUTF16Range()

		if !selection.isEmpty {
			let newCaret = document.replace(utf16Range: selection, with: "", caretBefore: selection.upperBound)
			afterEdit(caret: newCaret)
			return
		}
		guard caret < document.rope.utf16Count else { return }

		let byteStart = document.rope.byteOffset(fromUTF16: caret)
		var byteEnd = min(document.rope.byteCount, byteStart + 1)
		while byteEnd < document.rope.byteCount,
		      Rope.isContinuation(document.rope.bytes(in: byteEnd..<(byteEnd + 1)).first ?? 0) {
			byteEnd += 1
		}
		let end = document.rope.utf16Offset(fromByte: byteEnd)

		let newCaret = document.replace(utf16Range: caret..<end, with: "", caretBefore: caret)
		afterEdit(caret: newCaret)
	}

	private func afterEdit(caret newCaret: Int) {
		guard let document else { return }
		folding.setAvailable(document.folds)
		caret = newCaret
		selectionAnchor = newCaret
		desiredColumnX = nil

		updateFrameSize()
		restartCaretBlink()
		scrollCaretToVisible()
		needsDisplay = true
		reportCaretPosition()
		onDirtyChanged?(document.isDirty)
	}

	// MARK: - Standard actions

	@objc func undo(_ sender: Any?) {
		guard let document, let restored = document.undo() else { return }
		afterEdit(caret: restored)
	}

	@objc func redo(_ sender: Any?) {
		guard let document, let restored = document.redo() else { return }
		afterEdit(caret: restored)
	}

	@objc override func selectAll(_ sender: Any?) {
		selectAllText()
	}

	@objc func copy(_ sender: Any?) {
		guard let document else { return }
		let selection = selectedUTF16Range()
		guard !selection.isEmpty else { return }

		let start = document.rope.byteOffset(fromUTF16: selection.lowerBound)
		let end = document.rope.byteOffset(fromUTF16: selection.upperBound)
		let text = document.rope.string(in: start..<end)

		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	@objc func cut(_ sender: Any?) {
		copy(sender)
		guard let document else { return }
		let selection = selectedUTF16Range()
		guard !selection.isEmpty else { return }
		let newCaret = document.replace(utf16Range: selection, with: "", caretBefore: selection.upperBound)
		afterEdit(caret: newCaret)
	}

	@objc func paste(_ sender: Any?) {
		guard let text = NSPasteboard.general.string(forType: .string) else { return }
		insertTextAtCaret(text)
	}

	// MARK: - Folding commands

	func collapseAllFolds() {
		folding.collapseAll()
		updateFrameSize()
		needsDisplay = true
	}

	func expandAllFolds() {
		folding.expandAll()
		updateFrameSize()
		needsDisplay = true
	}

	// MARK: - NSTextInputClient

	// Implemented so marked text (IME composition, dead keys) reaches the buffer
	// correctly instead of arriving as raw keystrokes.

	/// Range of in-progress IME composition. Named distinctly from the
	/// `markedRange()` protocol method it backs.
	private var composingRange = NSRange(location: NSNotFound, length: 0)

	func insertText(_ string: Any, replacementRange: NSRange) {
		let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
		guard !text.isEmpty else { return }

		if composingRange.location != NSNotFound {
			// Replace the in-progress composition with the committed text.
			guard let document else { return }
			let range = composingRange.location..<(composingRange.location + composingRange.length)
			let newCaret = document.replace(utf16Range: range, with: text, caretBefore: range.lowerBound)
			composingRange = NSRange(location: NSNotFound, length: 0)
			afterEdit(caret: newCaret)
			return
		}
		insertTextAtCaret(text)
	}

	func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
		guard let document else { return }
		let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""

		let replaceRange: Range<Int>
		if composingRange.location != NSNotFound {
			replaceRange = composingRange.location..<(composingRange.location + composingRange.length)
		} else {
			let selection = selectedUTF16Range()
			replaceRange = selection.isEmpty ? caret..<caret : selection
		}

		let newCaret = document.replace(utf16Range: replaceRange, with: text, caretBefore: replaceRange.lowerBound)
		let length = (text as NSString).length
		composingRange = length > 0
			? NSRange(location: replaceRange.lowerBound, length: length)
			: NSRange(location: NSNotFound, length: 0)
		afterEdit(caret: newCaret)
	}

	func unmarkText() {
		composingRange = NSRange(location: NSNotFound, length: 0)
	}

	func selectedRange() -> NSRange {
		let selection = selectedUTF16Range()
		return NSRange(location: selection.lowerBound, length: selection.count)
	}

	func markedRange() -> NSRange { composingRange }

	func hasMarkedText() -> Bool { composingRange.location != NSNotFound }

	func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
		guard let document else { return nil }
		let lower = max(0, min(range.location, document.rope.utf16Count))
		let upper = max(lower, min(range.location + range.length, document.rope.utf16Count))
		let start = document.rope.byteOffset(fromUTF16: lower)
		let end = document.rope.byteOffset(fromUTF16: upper)
		actualRange?.pointee = NSRange(location: lower, length: upper - lower)
		return NSAttributedString(string: document.rope.string(in: start..<end))
	}

	func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

	func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
		guard let point = caretPoint(), let window else { return .zero }
		let viewRect = NSRect(x: point.x, y: point.y, width: 1, height: lineHeight)
		return window.convertToScreen(convert(viewRect, to: nil))
	}

	func characterIndex(for point: NSPoint) -> Int {
		guard let window else { return 0 }
		let local = convert(window.convertPoint(fromScreen: point), from: nil)
		return offset(at: local)
	}
}

/// Binary-searchable view over the visible highlight spans.
///
/// The renderer asks for the tokens on each line in turn; scanning the whole
/// token array per line would be quadratic across the viewport.
private struct TokenIndex {
	private let tokens: [HighlightToken]

	init(tokens: [HighlightToken]) {
		self.tokens = tokens.sorted { $0.range.lowerBound < $1.range.lowerBound }
	}

	func tokens(overlapping range: Range<Int>) -> ArraySlice<HighlightToken> {
		guard !tokens.isEmpty else { return [] }

		// First token that could reach into `range`.
		var low = 0
		var high = tokens.count
		while low < high {
			let mid = (low + high) / 2
			if tokens[mid].range.upperBound <= range.lowerBound {
				low = mid + 1
			} else {
				high = mid
			}
		}
		let start = low

		var end = start
		while end < tokens.count && tokens[end].range.lowerBound < range.upperBound {
			end += 1
		}
		return tokens[start..<end]
	}
}
