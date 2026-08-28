import AppKit
import AbydosKit

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
	/// Where the selected text also appears, in file order.
	///
	/// Never both these and `searchMatches`: find's matches win while find is
	/// showing, so one of the two lists is always empty. Kept as ranges rather
	/// than `SearchMatch` because a band needs an offset and nothing here reads
	/// a line's text.
	private var selectionOccurrences: [Range<Int>] = []
	/// Which selection the bands above were found for.
	///
	/// Checked before anything is painted, because not every path that changes a
	/// selection reports the caret — `selectAllText` sets both ends and redraws —
	/// and a band left under text nobody selected is precisely the fault this
	/// feature must not introduce. Comparing two integers per draw is the price
	/// of not having to trust every present and future path to say so.
	private var occurrencesSelection: Range<Int>?
	/// Scanning for the selection's other places, once it has settled.
	private var occurrenceScan: DispatchWorkItem?

	/// Debugger state for this file: breakpoint lines and where execution stopped.
	private var breakpointLines: [Int: BreakpointMark] = [:]
	private var executionLine: Int?

	/// The variables of the frame execution stopped in, by name, or nil while
	/// nothing is stopped.
	///
	/// A dictionary rather than text per line: it is built once per stop, and a
	/// row's drawing is then a scan of that row's tokens against it. Nothing is
	/// worked out for a file this frame is not in — the editor does not hand it
	/// one — and nothing at all while this is nil, which is the ordinary state.
	private var inlineValues: [String: Variable]?
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
	/// Asked for everywhere the symbol under the caret is used.
	var onFindUsages: ((_ line: Int, _ character: Int) -> Void)?
	/// Asked to rename the symbol under the caret, everywhere it is used.
	var onRename: ((_ line: Int, _ character: Int) -> Void)?
	/// Asked to put an agent on the problem the caret is in.
	var onFixWithAI: ((_ line: Int, _ diagnostic: LSPDiagnostic) -> Void)?
	/// Asked to watch what is selected while debugging.
	var onWatch: ((_ expression: String) -> Void)?
	/// Which of the two forms to copy.
	enum LinkForm { case reference, permalink }
	/// Copy this place, in that form. The window does it: a reference needs the
	/// project root and a permalink needs git, and neither is a text view's
	/// business.
	var onCopyLink: ((_ form: LinkForm, _ line: Int, _ endLine: Int?) -> Void)?
	/// The text changed and the caret is in a word — or on a character the
	/// server asked to be woken by: offer completions for it.
	var onRequestCompletions: ((_ prefix: String, _ wasTriggered: Bool, _ caret: NSPoint) -> Void)?

	/// Asks for completions because somebody asked, rather than because they
	/// typed. Answered even where there is no prefix at all.
	var onRequestCompletionsNow: ((_ prefix: String) -> Void)?
	/// The characters this file's server wants to be asked on, over and above a
	/// word being typed.
	///
	/// Held here rather than asked for, because this is decided on the keystroke
	/// and `LanguageService` is a lookup away from a view that should not be
	/// reaching for it. Empty until a server is running, which is the same as
	/// "ask on words only".
	var completionTriggerCharacters: Set<Character> = []
	/// And the ones it wants to be asked about the *call* on — `(` and `[` to
	/// begin with, `,` and `:` to ask again as the arguments go in.
	///
	/// Empty for a server with no signature help, which is how openscad-lsp is
	/// never sent a request it does not answer.
	var signatureTriggerCharacters: Set<Character> = []
	/// One of those was typed: ask what call the caret is in now.
	var onRequestSignatureHelp: (() -> Void)?
	/// The stop being filled in changed — its default text, or nothing when the
	/// session has ended.
	///
	/// The name is what the snippet called it: `${1:size}` is `size`, which is
	/// the heading a server's prose has for that parameter. Captured when the
	/// text goes in, because by the time somebody has typed over it the default
	/// is gone and the name with it.
	var onSnippetStopChanged: ((_ name: String?) -> Void)?
	/// A key the completion list wants first. Returns true if it took it.
	var completionKeyHandler: ((Selector) -> Bool)?
	/// Nothing to complete any more.
	var onDismissCompletions: (() -> Void)?

	/// What a language server says is wrong here, by zero-based line.
	private var diagnosticsByLine: [Int: [LSPDiagnostic]] = [:]

	/// Replaces what is underlined as a problem.
	/// What a server last said about this file, and whether it had told us it
	/// was not ready when it said it.
	///
	/// `fromPreparingServer` is not about the diagnostics: it is about the
	/// server. **And it has to be able to change on its own**, which is why the
	/// early return below tests it. Preparation ends when a progress token
	/// closes, and the last diagnostic may have arrived thirty seconds earlier —
	/// a view that only redrew when something new arrived would keep a dimmed
	/// error on screen after the server was ready, which is worse than the state
	/// this is fixing.
	func setDiagnostics(_ diagnostics: [LSPDiagnostic], fromPreparingServer isPreparing: Bool = false) {
		var grouped: [Int: [LSPDiagnostic]] = [:]
		for diagnostic in diagnostics {
			// A problem spanning lines is marked on the line it starts at, which
			// is where the cause is; underlining all of them buries it.
			grouped[diagnostic.range.start.line, default: []].append(diagnostic)
		}
		guard grouped != diagnosticsByLine || isPreparing != diagnosticsArePreparing else { return }
		diagnosticsByLine = grouped
		diagnosticsArePreparing = isPreparing
		needsDisplay = true
	}

	/// Whether the pointer was over an openable value last time it moved, so the
	/// cursor is put back exactly once when it leaves.
	private var isOverInlineValue = false

	/// Whether the server that sent what is on screen had said it was preparing.
	private var diagnosticsArePreparing = false

	/// Every diagnostic on this file, and the weight it is drawn at.
	///
	/// The weight is the whole subject and it is a colour, so a photograph can
	/// show it and cannot be diffed — and the transition being asserted here
	/// happens a minute after the file opens, when nothing else on screen
	/// changes. This says it in words, from the same function the drawing uses.
	var diagnosticReportForTesting: String {
		var lines = ["server preparing: \(diagnosticsArePreparing)"]
		for line in diagnosticsByLine.keys.sorted() {
			for diagnostic in diagnostics(onLine: line) {
				let weight = DiagnosticWeight.weight(
					of: diagnostic.severity, fromPreparingServer: diagnosticsArePreparing
				)
				lines.append("  \(line + 1): \(diagnostic.severity) drawn as \(weight)"
					+ " — \(diagnostic.message.prefix(60))")
			}
		}
		if lines.count == 1 { lines.append("  nothing on this file") }
		return lines.joined(separator: "\n")
	}

	/// The problems on a line, worst first.
	func diagnostics(onLine line: Int) -> [LSPDiagnostic] {
		(diagnosticsByLine[line] ?? []).sorted { $0.severity < $1.severity }
	}

	var hasDiagnostics: Bool { !diagnosticsByLine.isEmpty }

	/// Called when the gutter is clicked in the breakpoint column.
	var onToggleBreakpoint: ((Int) -> Void)?
	/// Clicked an existing marker: off if it was on, on if it was off.
	var onSetBreakpointEnabled: ((Int, Bool) -> Void)?
	/// Dragged a marker out of the gutter, or chose Delete.
	var onDeleteBreakpoint: ((Int) -> Void)?
	/// Chose "Disable other breakpoints" — or the reverse.
	var onSetOtherBreakpointsEnabled: ((Int, Bool) -> Void)?
	/// The text moved under the breakpoints: an edit starting at this 0-based
	/// line took out `removed` lines and put in `inserted`.
	var onLinesChanged: ((Int, Int, Int) -> Void)?

	/// The same edit in the unit a find match is in: which UTF-16 range went and
	/// how much came in its place.
	///
	/// Fanned out here rather than taken from the document, whose own
	/// `onTextReplaced` is one closure and is already the snippet session's. A
	/// second assignment there would take a snippet's tab stops away silently,
	/// which is the fault this whole hook exists to avoid the other way round.
	var onTextReplaced: ((Range<Int>, Int) -> Void)?

	/// What the gutter needs to know about a breakpoint to draw it.
	struct BreakpointMark: Equatable {
		var isEnabled = true
		/// The adapter bound it. An unverified marker is drawn hollow, because
		/// a solid one where execution can never stop is a lie.
		var isVerified = false
		/// It has a condition, a hit count, or a message: worth showing, since
		/// a breakpoint that does not always stop looks identical otherwise.
		var isConditional = false
	}

	// MARK: - Metrics

	private var font: NSFont = Theme.current.editorFont
	private var lineHeight: CGFloat = 18
	private var baselineOffset: CGFloat = 4
	private var charWidth: CGFloat = 7
	private(set) var gutterWidth: CGFloat = 60

	/// Who last touched each line, when blame is being shown.
	///
	/// One entry per line of the file as it was read; a file edited since is
	/// blamed again on the next save, and until then the entries still line up
	/// with what is on screen for everything above the edit.
	private var blame: [GitBlame.Line] = []
	private(set) var isBlameVisible = false
	/// The width of the blame column, in characters.
	private static let blameColumns = 18

	private var blameWidth: CGFloat {
		isBlameVisible ? ceil(CGFloat(Self.blameColumns) * charWidth) + Self.gutterPadding : 0
	}

	private static let gutterPadding: CGFloat = 10
	/// Clickable strip on the far left of the gutter, where a runnable line
	/// gets its play triangle.
	private static var breakpointColumnWidth: CGFloat { Theme.current.scaled(18) }
	/// The strip at the right of the gutter that folds and unfolds.
	///
	/// Its own column now: a click on the line number makes a breakpoint, so
	/// folding needs somewhere of its own to be clicked — the chevron, and
	/// nothing else.
	private static var foldColumnWidth: CGFloat { Theme.current.scaled(16) }
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

	/// Replaces the whole of an open document's text, through the rope.
	///
	/// **The half of a workspace edit that is not a file.** A file with an
	/// editor on it cannot be written behind the editor's back — the buffer and
	/// the disk would then say different things and whichever the person saved
	/// next would win — so the change goes through `TextDocument.replace`, which
	/// is the same door a keystroke goes through: the rope moves, tree-sitter is
	/// told, the folds are recomputed, the tab goes dirty.
	///
	/// One `replace` of the whole file rather than one per edit the server sent,
	/// and that is deliberate: `TextDocument` records an undo node per `replace`,
	/// so forty edits in one file would be forty presses of ⌘Z inside that file
	/// on top of the forty files. One node here is the document's share of the
	/// one undo this gesture gets.
	///
	/// The caret, the collapsed folds and the scroll position are put back the
	/// way `reloadFromDisk` puts them back, and for the same reason: the file
	/// under somebody's eyes changed, and losing their place in it is a second
	/// thing that happened to them.
	@discardableResult
	func replaceAllText(with text: String) -> Bool {
		guard let document, text != document.rope.string else { return false }

		let rope = document.rope
		let caretByte = rope.byteOffset(fromUTF16: caret)
		let caretLine = rope.line(atByteOffset: caretByte)
		let caretColumn = caret - rope.utf16Offset(fromByte: rope.lineByteRange(caretLine).lowerBound)
		let collapsed = folding.collapsed
		let scrollOffset = enclosingScrollView?.contentView.bounds.origin ?? .zero

		let length = rope.utf16Offset(fromByte: rope.byteCount)
		document.replace(utf16Range: 0..<length, with: text, caretBefore: caret)

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
		enclosingScrollView?.contentView.scroll(to: scrollOffset)
		if let scrollView = enclosingScrollView {
			scrollView.reflectScrolledClipView(scrollView.contentView)
		}

		needsDisplay = true
		reportCaretPosition()
		return true
	}

	func load(document: TextDocument) {
		self.document = document
		// Breakpoints follow the text they were put on rather than the line
		// number they were put at.
		document.onLinesChanged = { [weak self] first, removed, inserted in
			self?.onLinesChanged?(first, removed, inserted)
			// Every line the edit put in, and not only the one the caret ended
			// on: a paste drops a block, and the widest line in it can be any of
			// them. Proportional to what was just pasted, which is work the
			// paste has already done once.
			self?.widenForTheLongestLine(lines: first...(first + inserted))
		}
		// A snippet's stops follow the text under them the same way, a span at
		// a time rather than a line at a time.
		document.onTextReplaced = { [weak self] range, inserted in
			self?.snippetSessionSaw(edit: range, insertedLength: inserted)
			self?.onTextReplaced?(range, inserted)
			// The text moved under the bands. Dropped and asked again, the same
			// as when the selection itself changes: an offset into text that no
			// longer exists is the fault `find-and-replace` was written to fix.
			self?.selectionChanged()
		}
		snippetSession = nil
		caret = 0
		selectionAnchor = 0
		// An offset in the file being replaced is not a place in the new one.
		pendingReveal = nil
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

	/// What the editor can be scrolled across, and how much of it is on screen.
	///
	/// The one number this view could never be asked for, and the reason
	/// horizontal scrolling could break without anything noticing: the document
	/// width is worked out from `longestLineColumns`, which was measured once
	/// when the file was opened and never again — so a line *typed* wider than
	/// the pane left the view exactly as wide as the pane, and there was no
	/// scroller, no scroll range, and nothing that could say so.
	var scrollReportForTesting: String {
		let clip = enclosingScrollView?.contentSize.width ?? 0
		let visible = enclosingScrollView?.documentVisibleRect ?? .zero
		return "doc=\(Int(frame.width)) clip=\(Int(clip)) "
			+ "longest=\(longestLineColumns) wrap=\(isWordWrapEnabled) "
			+ "scrollable=\(frame.width > clip + 0.5) at=\(Int(visible.minX))"
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

	private func updateFrameSize() {
		guard let document else { return }
		let digits = max(2, String(document.lineCount).count)
		// The extra column on the left is the breakpoint gutter.
		gutterWidth = ceil(CGFloat(digits) * charWidth) + Self.gutterPadding * 2 + 14
			+ Self.breakpointColumnWidth + blameWidth

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

	/// The word under the pointer while ⌘ is held, in line-relative UTF-16.
	private var navigableWord: (line: Int, range: Range<Int>)?

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
	private func updateNavigableWord(at point: NSPoint?, commandHeld: Bool) {
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

	/// Told to open a value, with where on screen it was.
	var onOpenInlineValue: ((InlineValueHint, NSRect) -> Void)?

	/// The hints on one line and where each of them is, in this view.
	///
	/// **Worked out from the line's own text and the frame's values** — the same
	/// two things the drawing is made from — rather than recorded while drawing.
	/// Storing a rect per hint per row would put bookkeeping on the drawing path
	/// and leave it stale the moment a line is edited; the editor font is
	/// monospaced, so the same answer can be had when somebody actually clicks.
	private func hintsWithRects(onVisualRow visual: Int) -> [(hint: InlineValueHint, rect: NSRect)] {
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
		let hoverPoint = convert(event.locationInWindow, from: nil)
		// A pointing hand over a value with something under it. Asked only while
		// a session is stopped: `openableInlineValue` is one `guard` otherwise.
		if openableInlineValue(at: hoverPoint) != nil {
			NSCursor.pointingHand.set()
		} else if isOverInlineValue {
			NSCursor.iBeam.set()
		}
		isOverInlineValue = openableInlineValue(at: hoverPoint) != nil
		updateNavigableWord(
			at: hoverPoint,
			commandHeld: event.modifierFlags.contains(.command)
		)

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
		updateNavigableWord(at: nil, commandHeld: false)
	}

	/// Where the matches on one line fall, split by the depth each is painted at.
	///
	/// Measured here and painted by the caller, because the current match and the
	/// rest do not go on at the same moment: the others belong under the
	/// selection and the current one over it. Measured *once* for both, since the
	/// CTLine this asks for offsets from is not free and a row is redrawn on
	/// every caret blink.
	private func searchHighlights(
		docLine: Int, segment: Int, rect: NSRect
	) -> (others: [NSRect], current: NSRect?, occurrences: [NSRect]) {
		guard let document, !searchMatches.isEmpty || !selectionOccurrences.isEmpty else {
			return ([], nil, [])
		}

		let lineRange = document.rope.lineByteRange(docLine)
		let lineStart = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let lineEnd = document.rope.utf16Offset(fromByte: lineRange.upperBound)
		let text = document.rope.string(in: lineRange)

		// **Measured along the row being painted, not along the whole line.**
		// This is 0540: the `CTLine` was built for the document line while
		// `rect` was one visual row of it, so every match past the first row was
		// placed at the x it would have had unwrapped. The caret's answer —
		// `point(forUTF16:)` — has always sliced the line into segments first,
		// and the two disagreeing is the fault. They now ask `WrapLayout` the
		// same question with the same arguments.
		var rowRangeInLine = 0..<(text as NSString).length
		var rowText = text
		if isWordWrapEnabled, let columns = wrapColumns {
			rowRangeInLine = WrapLayout.segmentRange(
				in: text, segment: segment, columns: columns, tabWidth: Theme.current.tabWidth
			)
			rowText = (text as NSString).substring(
				with: NSRange(location: rowRangeInLine.lowerBound, length: rowRangeInLine.count)
			)
		}

		let ctLine = CTLineCreateWithAttributedString(attributedLine(
			text: rowText,
			lineStartUTF16: lineStart + rowRangeInLine.lowerBound,
			tokenIndex: TokenIndex(tokens: [])
		))

		/// One range placed on this row, or nil when none of it falls here.
		///
		/// The two lists are asked the same question and the CTLine is built
		/// once for both: it is not free, and a row is redrawn on every caret
		/// blink.
		func band(for range: Range<Int>) -> NSRect? {
			guard let band = WrapLayout.bandRange(
				for: range, lineStart: lineStart, segment: rowRangeInLine
			) else { return nil }

			let startX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, band.lowerBound, nil)
			let endX = textOriginX + CTLineGetOffsetForStringIndex(ctLine, band.upperBound, nil)
			return NSRect(
				x: startX,
				y: rect.minY,
				width: max(2, endX - startX),
				height: rect.height
			)
		}

		var occurrences: [NSRect] = []
		for range in selectionOccurrences {
			// Ordered, so the row can be left as soon as one starts past it.
			guard range.lowerBound <= lineEnd else { break }
			guard range.upperBound >= lineStart else { continue }
			if let rect = band(for: range) { occurrences.append(rect) }
		}

		var others: [NSRect] = []
		var current: NSRect?

		for (index, match) in searchMatches.enumerated() {
			// Matches are ordered, so stop once past this line.
			guard match.utf16Range.lowerBound <= lineEnd else { break }
			guard match.utf16Range.upperBound >= lineStart else { continue }

			// What of it falls on *this* row, in the row's own offsets. A match
			// crossing a wrap boundary is asked once per row and answers a piece
			// each time, which is the shape the old code could not express: it
			// returned one rectangle per match and had nowhere to put the rest.
			guard let rect = band(for: match.utf16Range) else { continue }

			if index == currentMatchIndex {
				current = rect
			} else {
				others.append(rect)
			}
		}
		return (others, current, occurrences)
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

		// Gray while the keyboard is somewhere else — the terminal below, a
		// results list, another pane of a split. A selection drawn in the strong
		// highlight is a claim that the next key will act on it, and this view
		// used to make that claim whether or not it was true.
		Theme.current.selection(.text, hasKeyboard: hasKeyboard).setFill()
		NSRect(x: startX, y: rect.minY, width: max(1, endX - startX), height: rect.height).fill()
	}

	/// True when this view is the one keys are going to.
	///
	/// Asked of the window on each draw rather than kept, so it cannot go stale:
	/// AppKit posts nothing when the first responder changes, and a flag would
	/// need every route out of this view to remember to clear it.
	private var hasKeyboard: Bool { window?.firstResponder === self }

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

	// MARK: - Blame

	/// Shows or hides the blame column. The caller does the asking of git.
	func setBlameVisible(_ visible: Bool) {
		guard visible != isBlameVisible else { return }
		isBlameVisible = visible
		if !visible { blame = [] }
		updateFrameSize()
		needsDisplay = true
	}

	func setBlame(_ lines: [GitBlame.Line]) {
		blame = lines
		needsDisplay = true
	}

	/// What the blame column says for a line, or nil when it should stay blank.
	///
	/// Blank for every line of a commit after its first: a run of forty lines
	/// from one commit says the same thing forty times otherwise, and the eye
	/// has to work out that they are one change rather than seeing it.
	private func blameLabel(forLine line: Int) -> String? {
		guard blame.indices.contains(line) else { return nil }
		if line > 0, blame.indices.contains(line - 1), blame[line - 1].commit == blame[line].commit {
			return nil
		}
		return blame[line].label(width: Self.blameColumns)
	}

	private func drawBlame(rows: Range<Int>, scrollX: CGFloat) {
		guard isBlameVisible, !blame.isEmpty else { return }

		let width = blameWidth
		for visual in rows {
			let docLine = documentLine(forVisualRow: visual)
			guard docLine < blame.count else { break }
			guard wrapSegment(forVisualRow: visual) == 0 else { continue }
			let y = yPosition(forVisualLine: visual)

			// A line still being written stands out, since it is the one thing
			// in the column that is nobody's yet.
			let entry = blame[docLine]
			guard let label = blameLabel(forLine: docLine) else { continue }

			let text = NSAttributedString(string: label, attributes: [
				.font: font,
				.foregroundColor: entry.isUncommitted
					? Theme.current.gitModified
					: Theme.current.gutterText,
			])
			text.draw(in: NSRect(
				x: scrollX + Self.gutterPadding / 2,
				y: y + (lineHeight - text.size().height) / 2,
				width: width - Self.gutterPadding,
				height: text.size().height
			))
		}

		// A hairline between the column and the gutter, so the two do not read
		// as one wide margin of numbers and names.
		Theme.current.gutterText.withAlphaComponent(0.25).setFill()
		NSRect(
			x: scrollX + width - 1,
			y: CGFloat(rows.lowerBound) * lineHeight,
			width: 1,
			height: CGFloat(rows.count) * lineHeight
		).fill()
	}

	/// The commit on a line, for the menu and the tooltip.
	func blameEntry(forLine line: Int) -> GitBlame.Line? {
		blame.indices.contains(line) ? blame[line] : nil
	}

	/// Asked to say more about the commit on a line.
	var onShowBlameDetail: ((GitBlame.Line) -> Void)?

	private func showBlameDetail(forLine line: Int) {
		guard let entry = blameEntry(forLine: line), !entry.isUncommitted else { return }
		onShowBlameDetail?(entry)
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

		drawBlame(rows: rows, scrollX: scrollX)

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
				drawRunMarker(y: y, scrollX: scrollX + blameWidth)
			} else {
				drawBreakpoint(docLine: docLine, y: y, scrollX: scrollX + blameWidth)
			}

			// On the marker when there is one, and the number goes white on it:
			// the tag is the breakpoint, so it has to be legible on top of it.
			let mark = breakpointLines[docLine]
			let colour: NSColor
			if let mark {
				colour = mark.isEnabled ? .white : Theme.current.gutterText
			} else {
				colour = isCurrent ? Theme.current.gutterCurrentLineText : Theme.current.gutterText
			}
			let number = NSAttributedString(string: "\(docLine + 1)", attributes: [
				.font: font,
				.foregroundColor: colour,
			])
			let size = number.size()
			// Right-aligned against the fold column.
			number.draw(at: NSPoint(
				x: scrollX + gutterWidth - Self.foldColumnWidth - Self.gutterPadding / 2 - size.width,
				y: y + (lineHeight - size.height) / 2
			))

			if folding.isFoldable(line: docLine) {
				drawFoldHandle(
					at: NSPoint(x: scrollX + gutterWidth - Self.foldColumnWidth / 2, y: y + lineHeight / 2),
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

	/// Which part of the gutter a point is in.
	private enum GutterZone {
		/// The play triangle's strip, on the far left.
		case run
		/// The line number: where a breakpoint is made, and where its marker is.
		case number
		/// The chevron at the right, which folds and nothing else.
		case fold
	}

	private func gutterZone(at point: NSPoint, scrollX: CGFloat) -> GutterZone {
		if point.x >= scrollX + gutterWidth - Self.foldColumnWidth { return .fold }
		if point.x < scrollX + blameWidth + Self.breakpointColumnWidth { return .run }
		return .number
	}

	/// The tag behind a line number, the way Xcode marks a breakpoint.
	///
	/// The number sits inside it rather than beside it: the marker is the line
	/// number, which is why clicking the number is how one is made and why
	/// there is no separate little dot to aim at.
	private func breakpointTag(y: CGFloat, scrollX: CGFloat) -> NSBezierPath {
		let left = scrollX + blameWidth + Self.gutterPadding / 2
		let right = scrollX + gutterWidth - Self.foldColumnWidth
		let rect = NSRect(
			x: left,
			y: y + Theme.current.scaled(1.5),
			width: max(10, right - left),
			height: lineHeight - Theme.current.scaled(3)
		)
		let radius = Theme.current.scaled(3)
		let point = min(Theme.current.scaled(6), rect.height / 2)

		// Rounded on the left, pointed on the right — a tag pointing at the
		// line it stops on.
		let path = NSBezierPath()
		path.move(to: NSPoint(x: rect.minX + radius, y: rect.minY))
		path.line(to: NSPoint(x: rect.maxX - point, y: rect.minY))
		path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
		path.line(to: NSPoint(x: rect.maxX - point, y: rect.maxY))
		path.line(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
		path.appendArc(
			withCenter: NSPoint(x: rect.minX + radius, y: rect.maxY - radius),
			radius: radius, startAngle: 90, endAngle: 180
		)
		path.appendArc(
			withCenter: NSPoint(x: rect.minX + radius, y: rect.minY + radius),
			radius: radius, startAngle: 180, endAngle: 270
		)
		path.close()
		return path
	}

	private func drawBreakpoint(docLine: Int, y: CGFloat, scrollX: CGFloat) {
		guard let mark = breakpointLines[docLine] else { return }

		let tag = breakpointTag(y: y, scrollX: scrollX - blameWidth)
		let colour = NSColor.hex(0x4C7EDB)

		if mark.isEnabled {
			(mark.isVerified ? colour : colour.withAlphaComponent(0.75)).setFill()
			tag.fill()
			if !mark.isVerified {
				// Not bound: outlined rather than solid, since execution cannot
				// actually stop there yet.
				colour.setStroke()
				tag.lineWidth = 1
				tag.stroke()
			}
		} else {
			// Off, but still there: pale, the way Xcode leaves one you have
			// switched off rather than deleted.
			colour.withAlphaComponent(0.28).setFill()
			tag.fill()
		}

		// A conditional breakpoint says so, because "why did it not stop" and
		// "why did it stop" are both answered by remembering it has a
		// condition on it.
		guard mark.isConditional else { return }
		let dot = NSRect(
			x: tag.bounds.minX + Theme.current.scaled(3),
			y: tag.bounds.midY - Theme.current.scaled(1.5),
			width: Theme.current.scaled(3),
			height: Theme.current.scaled(3)
		)
		(mark.isEnabled ? NSColor.white : colour).setFill()
		NSBezierPath(ovalIn: dot).fill()
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

	private func caretPoint() -> NSPoint? { point(forUTF16: caret) }

	/// Where an offset in the document falls, in this view's coordinates.
	///
	/// This was the caret's own position and nothing else until a rename needed
	/// the top-left of a *symbol* rather than of the caret. Folding, word wrap
	/// and the shaping of the line are the same work for both, and two copies of
	/// that is two copies to keep agreeing.
	func point(forUTF16 caret: Int) -> NSPoint? {
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
		// The whole view, not the caret's rect: `restartCaretBlink` ends in
		// `needsDisplay = true`, which is also what puts the selection back into
		// the strong colour. Said here because it is now load-bearing for
		// something other than the caret — a redraw narrowed to the caret would
		// leave the selection gray with the keyboard in this view.
		restartCaretBlink()
		announceKeyboardFocusChange()
		return true
	}

	override func resignFirstResponder() -> Bool {
		caretTimer?.invalidate()
		caretVisible = false
		needsDisplay = true
		announceKeyboardFocusChange()
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

	/// Breakpoints to draw, keyed by 0-based line.
	func setBreakpoints(_ lines: [Int: BreakpointMark]) {
		guard lines != breakpointLines else { return }
		breakpointLines = lines
		needsDisplay = true
		window?.invalidateCursorRects(for: self)
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
	private func widenForTheLongestLine(upTo line: Int) {
		longestLineColumns = max(longestLineColumns, displayColumns(ofLine: line) + 2)
	}

	/// The same for a run of lines, which is what an edit that moved lines about
	/// has just written.
	private func widenForTheLongestLine(lines: ClosedRange<Int>) {
		guard let document else { return }
		let last = min(lines.upperBound, document.lineCount - 1)
		let first = max(0, lines.lowerBound)
		guard first <= last else { return }
		for line in first...last { widenForTheLongestLine(upTo: line) }
	}

	/// A place that should be on screen and could not be worked out yet.
	///
	/// The other half of not betting on a turn count: where the pane has no size
	/// even after layout has been forced — a tab whose window is not on screen
	/// yet, a pane the layout pass has not reached — the request waits here, and
	/// `viewportChanged` brings it on screen the moment the pane is given one.
	/// Nothing retries on a timer and nothing scrolls to a number measured
	/// against a viewport of zero.
	private var pendingReveal: (offset: Int, end: Int?)?

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
	private func drainPendingReveal() {
		guard let waiting = pendingReveal, !isDrainingReveal else { return }
		isDrainingReveal = true
		pendingReveal = nil
		// The rows are laid out for the size the pane has now, which is what the
		// answer is measured in.
		updateFrameSize()
		bringOnScreen(utf16: waiting.offset, extendingTo: waiting.end)
		isDrainingReveal = false
	}

	/// Guards the drain against itself: the scroll below can change the frame,
	/// and a frame change is what called it.
	private var isDrainingReveal = false

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

	/// The breakpoint being dragged out of the gutter, if one is.
	private var draggingBreakpointLine: Int?
	/// Whether letting go now would throw the dragged breakpoint away.
	///
	/// A drag is not a decision until it ends. Deleting the moment the pointer
	/// passed the gutter meant a breakpoint was gone before the mouse button
	/// came up, with no way back but to put it on again — so the pointer says
	/// what will happen, and the button says whether to do it.
	private var breakpointWouldBeRemoved = false

	/// The click that activates the window also places the caret.
	///
	/// Clicking into an inactive window otherwise brings the app forward and
	/// throws the click away, so somebody who clicked at a line to start typing
	/// there is left with the caret wherever it was — and finds out a keystroke
	/// later, in the wrong place.
	///
	/// A click in text moves a caret and nothing else, which is what the
	/// default behaviour exists to protect against elsewhere.
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		// **Before anything else, and only while stopped.** A hint sits past the
		// end of the line, where a click would otherwise put the caret at the
		// line's end — so this is the one place it can be claimed, and it claims
		// nothing when there is no session, no hint, or nothing under the hint.
		if inlineValues != nil {
			let visual = max(0, min(visibleLineCount - 1, Int(floor(point.y / lineHeight))))
			if let found = hintsWithRects(onVisualRow: visual)
				.first(where: { $0.hint.isOpenable && $0.rect.contains(point) }) {
				onOpenInlineValue?(found.hint, found.rect)
				return
			}
		}

		window?.makeFirstResponder(self)
		draggingBreakpointLine = nil

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
			updateNavigableWord(at: nil, commandHeld: false)
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

		// A right-click on a marker offers what can be done to it. It is where
		// the breakpoint is, so it is where somebody aims to change it.
		if point.x < scrollX + gutterWidth - Self.foldColumnWidth, let document {
			let visual = max(0, min(visibleLineCount - 1, Int(floor(point.y / lineHeight))))
			let docLine = min(document.lineCount - 1, documentLine(forVisualRow: visual))
			guard let mark = breakpointLines[docLine] else { return }
			showBreakpointMenu(for: docLine, mark: mark, event: event)
			return
		}

		// The menu acts on what was pointed at, so the caret goes there first —
		// otherwise "find usages" answers about wherever the caret happened to
		// be left.
		if selectedUTF16Range().isEmpty {
			setCaret(offset(at: point), extendingSelection: false)
		}
		super.rightMouseDown(with: event)
	}

	/// What can be done to the breakpoint that was right-clicked.
	private func showBreakpointMenu(for docLine: Int, mark: BreakpointMark, event: NSEvent) {
		let menu = NSMenu()
		func add(_ title: String, _ action: @escaping () -> Void) {
			let item = NSMenuItem(title: title, action: #selector(runBlock(_:)), keyEquivalent: "")
			item.target = self
			item.representedObject = Block(action)
			menu.addItem(item)
		}

		add("Edit Breakpoint…") { [weak self] in self?.onEditBreakpoint?(docLine) }
		add(mark.isEnabled ? "Disable Breakpoint" : "Enable Breakpoint") { [weak self] in
			self?.onSetBreakpointEnabled?(docLine, !mark.isEnabled)
		}
		add("Disable Other Breakpoints") { [weak self] in
			self?.onSetOtherBreakpointsEnabled?(docLine, false)
		}
		add("Enable Other Breakpoints") { [weak self] in
			self?.onSetOtherBreakpointsEnabled?(docLine, true)
		}
		menu.addItem(.separator())
		add("Delete Breakpoint") { [weak self] in self?.onDeleteBreakpoint?(docLine) }

		NSMenu.popUpContextMenu(menu, with: event, for: self)
	}

	/// A closure a menu item can carry, since `NSMenuItem` takes a selector.
	private final class Block: NSObject {
		let run: () -> Void
		init(_ run: @escaping () -> Void) { self.run = run }
	}

	@objc private func runBlock(_ sender: NSMenuItem) {
		(sender.representedObject as? Block)?.run()
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		guard document != nil else { return nil }
		let menu = NSMenu()

		func item(_ title: String, _ selector: Selector) -> NSMenuItem {
			let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			entry.target = self
			return entry
		}

		menu.addItem(item("Go to Definition", #selector(goToDefinitionFromMenu)))
		menu.addItem(item("Find Usages", #selector(findUsagesFromMenu)))
		// Beside find-usages, because it is the same question with something
		// done about the answer, and the two are reached from the same place in
		// every editor anybody has used.
		menu.addItem(item("Rename…", #selector(renameFromMenu)))
		// Only with a selection, because what would be watched is the selection:
		// an expression is `things[i].name`, which no rule about identifiers
		// under the caret would have picked out on its own.
		if onWatch != nil, selectedText() != nil {
			menu.addItem(item("Watch", #selector(watchFromMenu)))
		}
		if diagnosticAtCaret() != nil {
			menu.addItem(.separator())
			menu.addItem(item("Fix with AI", #selector(fixWithAIFromMenu)))
		}
		// **Two entries rather than one with a submenu.** A reference and a
		// permalink are different in kind, not in format: one costs nothing and
		// is always there, the other needs a repository with a remote and may
		// have something to say about itself. A submenu hides the second behind
		// a hover for no gain, and one item that picks for you is an item nobody
		// trusts. The permalink is absent where there is nothing to link to,
		// which the window answers, not this view.
		if onCopyLink != nil {
			menu.addItem(.separator())
			menu.addItem(item("Copy Reference", #selector(copyReferenceFromMenu)))
			menu.addItem(item("Copy Permalink", #selector(copyPermalinkFromMenu)))
		}
		menu.addItem(.separator())
		menu.addItem(item("Cut", #selector(NSText.cut(_:))))
		menu.addItem(item("Copy", #selector(NSText.copy(_:))))
		menu.addItem(item("Paste", #selector(NSText.paste(_:))))
		menu.addItem(.separator())
		menu.addItem(item("Select All", #selector(NSText.selectAll(_:))))
		return menu
	}

	/// Where the caret is, as the protocol counts.
	func caretPositionForRequest() -> (line: Int, character: Int)? {
		guard let document else { return nil }
		let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: caret))
		let lineStart = document.rope.utf16Offset(fromByte: document.rope.byteOffset(ofLine: line))
		return (line, caret - lineStart)
	}

	@objc private func goToDefinitionFromMenu() {
		guard let position = caretPositionForRequest() else { return }
		onGoToDefinition?(position.line, position.character)
	}

	/// The lines a reference names: the caret's line, or every line a selection
	/// touches.
	///
	/// **Counted from 1**, which is how `CodePlace` counts and how everything
	/// that prints a line number counts. A selection that ends at the very start
	/// of a line does not include that line — dragging down to the beginning of
	/// line 19 selects up to the end of 18, and saying 19 would name a line
	/// nobody highlighted.
	func lineSpanForReference() -> (line: Int, endLine: Int?)? {
		guard let document else { return nil }
		let selection = selectedUTF16Range()
		let rope = document.rope
		func line(at offset: Int) -> Int {
			rope.line(atByteOffset: rope.byteOffset(fromUTF16: offset)) + 1
		}
		let start = line(at: selection.lowerBound)
		guard !selection.isEmpty else { return (start, nil) }

		var end = line(at: selection.upperBound)
		let lastLineStart = rope.utf16Offset(fromByte: rope.byteOffset(ofLine: end - 1))
		if end > start, selection.upperBound == lastLineStart { end -= 1 }
		return (start, end > start ? end : nil)
	}

	@objc private func copyReferenceFromMenu() {
		guard let span = lineSpanForReference() else { return }
		onCopyLink?(.reference, span.line, span.endLine)
	}

	@objc private func copyPermalinkFromMenu() {
		guard let span = lineSpanForReference() else { return }
		onCopyLink?(.permalink, span.line, span.endLine)
	}

	@objc private func fixWithAIFromMenu() {
		guard let found = diagnosticAtCaret() else { return }
		onFixWithAI?(found.line, found.diagnostic)
	}

	@objc private func watchFromMenu() {
		guard let expression = selectedText() else { return }
		onWatch?(expression)
	}

	@objc private func findUsagesFromMenu() {
		guard let position = caretPositionForRequest() else { return }
		onFindUsages?(position.line, position.character)
	}

	@objc func renameFromMenu() {
		guard let position = caretPositionForRequest() else { return }
		onRename?(position.line, position.character)
	}

	// MARK: - Renaming a symbol

	/// The field laid over a symbol while its new name is being typed.
	///
	/// A subview of this view rather than a panel above it, which is the whole
	/// difference between the two kinds of thing this editor puts on screen. The
	/// completion list is a child window because it has to hang past the
	/// editor's edges and must never take focus; this is the opposite of both —
	/// it is *in* the text, it scrolls with it because this view is the scroll
	/// view's document view, and typing into it is the entire point.
	private let rename = RenameField()

	var isRenaming: Bool { rename.isOpen }

	/// The word the caret is in, as a range and as text.
	///
	/// What a rename is offered for when the server has no `prepareRename` — and
	/// what tells "the caret is in an identifier" from "the caret is on a comma"
	/// before anything is asked of anybody.
	func wordAtCaret() -> (range: Range<Int>, text: String)? {
		guard let document else { return nil }
		let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: caret))
		let lineRange = document.rope.lineByteRange(line)
		let lineStart = document.rope.utf16Offset(fromByte: lineRange.lowerBound)
		let text = document.rope.string(in: lineRange) as NSString

		let column = caret - lineStart
		guard column >= 0, column <= text.length else { return nil }

		func isWord(_ unit: unichar) -> Bool {
			let scalar = Unicode.Scalar(unit)
			return scalar.map { CharacterSet.alphanumerics.contains($0) || $0 == "_" } ?? false
		}

		var start = column
		while start > 0, isWord(text.character(at: start - 1)) { start -= 1 }
		var end = column
		while end < text.length, isWord(text.character(at: end)) { end += 1 }
		guard end > start else { return nil }

		return (
			range: (lineStart + start)..<(lineStart + end),
			text: text.substring(with: NSRange(location: start, length: end - start))
		)
	}

	/// Opens the field over a range of the document.
	///
	/// Returns false when the range cannot be put on screen — a symbol inside a
	/// fold, most likely — because a field placed at a guess would be a field
	/// over the wrong word.
	@discardableResult
	func beginRename(
		utf16Range: Range<Int>, name: String, caveat: String?,
		commit: @escaping (String) -> Bool
	) -> Bool {
		guard let start = point(forUTF16: utf16Range.lowerBound),
		      let end = point(forUTF16: utf16Range.upperBound),
		      end.y == start.y
		else { return false }

		rename.onCommit = commit
		rename.onCancel = { [weak self] in self?.window?.makeFirstResponder(self) }
		rename.begin(
			over: NSRect(
				x: start.x, y: start.y,
				width: max(end.x - start.x, Theme.current.scaled(24)), height: lineHeight
			),
			in: self,
			name: name,
			font: Theme.current.editorFont,
			caveat: caveat
		)
		return true
	}

	func refuseRename(_ title: String, detail: String? = nil) { rename.refuse(title, detail: detail) }

	func endRename() { rename.end() }

	/// Types a name into the open field and presses Return, for a test with no
	/// keyboard.
	@discardableResult
	func commitRenameForTesting(_ name: String) -> Bool { rename.commitForTesting(name) }

	/// What the open field says, so a driver can show the field really opened on
	/// the symbol rather than on whatever was nearby.
	var renameTextForTesting: String? { rename.textForTesting }

	override func mouseDragged(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)

		// A marker dragged out of the gutter is thrown away, as it is in Xcode.
		// Well clear of it: a wobble while clicking is not somebody deleting a
		// breakpoint. Shown while dragging and done on release — dragging back
		// into the gutter takes it back.
		if draggingBreakpointLine != nil {
			let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0
			let wouldRemove = point.x > scrollX + gutterWidth + Theme.current.scaled(24)
			guard wouldRemove != breakpointWouldBeRemoved else { return }

			breakpointWouldBeRemoved = wouldRemove
			// The puff cursor Xcode shows: a marker that simply vanishes reads
			// as a misclick rather than as something done on purpose. This is
			// the cursor rather than the animation `NSAnimationEffect` used to
			// play, which macOS 14 deprecated in favour of exactly this.
			if wouldRemove { NSCursor.disappearingItem.set() } else { NSCursor.arrow.set() }
			return
		}

		guard point.x >= gutterWidth || caret != selectionAnchor else { return }
		setCaret(offset(at: point), extendingSelection: true)
	}

	override func mouseUp(with event: NSEvent) {
		// Where a drag out of the gutter is decided: let go beyond it and the
		// breakpoint is thrown away, let go anywhere else — including back over
		// the gutter — and it stays exactly where it was.
		if let line = draggingBreakpointLine, breakpointWouldBeRemoved {
			onDeleteBreakpoint?(line)
		}
		draggingBreakpointLine = nil

		// The puff belongs to the drag that ended. Left set, it would follow the
		// pointer around the file as though everything under it were about to be
		// thrown away too.
		if breakpointWouldBeRemoved {
			breakpointWouldBeRemoved = false
			NSCursor.arrow.set()
		}
		super.mouseUp(with: event)
	}

	private func handleGutterClick(at point: NSPoint) {
		guard let document else { return }
		let visual = max(0, min(visibleLineCount - 1, Int(floor(point.y / lineHeight))))
		let docLine = min(document.lineCount - 1, documentLine(forVisualRow: visual))

		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0

		// The blame column, when it is showing, is in front of everything else
		// the gutter does — and it is for reading, not for clicking.
		if isBlameVisible, point.x < scrollX + blameWidth {
			showBlameDetail(forLine: docLine)
			return
		}

		// The leftmost strip is the breakpoint column, or the run button when
		// the line has one.
		switch gutterZone(at: point, scrollX: scrollX) {
		case .run:
			if runnableLines.contains(docLine + 1), breakpointLines[docLine] == nil {
				onRunLine?(docLine + 1)
			}

		case .number:
			// Held on an existing marker, this may become a drag out of the
			// gutter, which is how one is thrown away.
			if breakpointLines[docLine] != nil { draggingBreakpointLine = docLine }
			// Xcode's rule: clicking the number makes a breakpoint, and
			// clicking the marker that is already there turns it off rather
			// than throwing it away — deleting is dragging it out, or the menu.
			if let mark = breakpointLines[docLine] {
				onSetBreakpointEnabled?(docLine, !mark.isEnabled)
			} else {
				onToggleBreakpoint?(docLine)
			}

		case .fold:
			// Only here. The line number belongs to breakpoints now, and a
			// click that folded the code somebody was aiming a breakpoint at
			// would be maddening.
			guard folding.isFoldable(line: docLine) else { return }
			folding.toggle(line: docLine)
			updateFrameSize()
			needsDisplay = true
		}
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

	/// Whether the caret is on the screen, and where the pane is looking.
	///
	/// The claim of item 533 is about a *place being visible*, which the caret
	/// line and the scroll offset only jointly answer, so it is one line with both
	/// in it and the verdict spelled out: a driver that had to compare two numbers
	/// itself would be reimplementing the thing under test. `on=no` is the report,
	/// on any file and at any window size.
	var revealReportForTesting: String {
		guard let document, let scrollView = enclosingScrollView else { return "no pane" }
		let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: caret)) + 1
		let visible = scrollView.contentView.bounds
		guard let point = caretPoint() else {
			return "line=\(line) point=none pending=\(pendingReveal != nil)"
		}
		// The gutter is drawn over the viewport's left edge, so text under it is
		// text nobody can read — the same boundary `RevealScroll` answers with.
		let onScreen = point.y >= visible.minY
			&& point.y + lineHeight <= visible.maxY
			&& point.x >= visible.minX + gutterWidth
			&& point.x <= visible.maxX
		return "line=\(line) on=\(onScreen ? "yes" : "no")"
			+ " point=\(Int(point.x)),\(Int(point.y))"
			+ " visible=\(Int(visible.minX)),\(Int(visible.minY))"
			+ "+\(Int(visible.width))x\(Int(visible.height))"
			+ " frame=\(Int(frame.width))x\(Int(frame.height))"
			+ " pending=\(pendingReveal != nil)"
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
		// ← and → arrive as `moveLeft:`/`moveRight:`; ⌃B and ⌃F arrive as
		// `moveBackward:`/`moveForward:`, which are selectors of their own —
		// visual order against logical order — and had no case here, so they
		// fell through `default:`. The emacs motions worked vertically, where
		// ⌃P and ⌃N are plain `moveUp:`/`moveDown:`, and did nothing at all
		// horizontally.
		//
		// The pairing is not logical order bent into visual order, though it
		// looks like it: `moveHorizontally` is `caret + delta` in document
		// offsets, so the motion these four share is *already* the logical one
		// and it is `moveRight:` that is misnamed. In right-to-left text ⌃F
		// would be correct and → would be wrong, exactly as wrong as it was
		// before this line. Nothing in this editor does bidi — layout is
		// offsets and only `CTLine` reorders, at the moment it draws — so
		// there is no second, visual order to route the arrows to, and
		// building one is not this switch's job. The word motions below have
		// paired the same two orders since they were written.
		case #selector(moveLeft(_:)), #selector(moveBackward(_:)):
			moveHorizontally(-1, extending: false)
		case #selector(moveRight(_:)), #selector(moveForward(_:)):
			moveHorizontally(1, extending: false)
		case #selector(moveLeftAndModifySelection(_:)),
		     #selector(moveBackwardAndModifySelection(_:)):
			moveHorizontally(-1, extending: true)
		case #selector(moveRightAndModifySelection(_:)),
		     #selector(moveForwardAndModifySelection(_:)):
			moveHorizontally(1, extending: true)
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
		// The paragraph family, which is where ⌃A and ⌃E arrive: macOS binds
		// them to `moveToBeginningOfParagraph:`/`moveToEndOfParagraph:` and
		// not to the line selectors above, so reading this switch used to say
		// those two keys worked while pressing them did nothing at all.
		//
		// A paragraph here is one line of the file — the text between two hard
		// breaks, which is what Cocoa means by the word and, in source, a
		// line. These therefore go to the *hard* edge of that line and share
		// no code with `moveToLineEdge`, whose first press stops at the first
		// non-blank. That stop is an affordance of the Home key and cannot be
		// reused here: AppKit sends ⌥↑ as `moveBackward:` followed by
		// `moveToBeginningOfParagraph:`, so the second selector runs one
		// character to the left of where the caret was, and a stop that reads
		// the caret to decide where to go sends it straight back. Measured:
		// ⌥↑ dead at the first non-blank of an indented line, and correct on
		// every unindented one. A selector used inside a sequence has to be a
		// function of the position and not a toggle over it.
		//
		// `moveParagraph…AndModifySelection:` is the same family and the
		// opposite half: ⌥⇧↓ and ⌥⇧↑ send one selector with no nudge in front,
		// so those two are the ones that have to step to the next paragraph by
		// themselves when the caret already sits on an edge. They have no bare
		// twin to pair them with and it is not an omission here — AppKit
		// declares no `moveParagraphForward:` or `moveParagraphBackward:` at
		// all, and `StandardKeyBinding.dict` binds no key to one.
		case #selector(moveToBeginningOfParagraph(_:)):
			moveToParagraphEdge(start: true, extending: false)
		case #selector(moveToEndOfParagraph(_:)):
			moveToParagraphEdge(start: false, extending: false)
		case #selector(moveToBeginningOfParagraphAndModifySelection(_:)):
			moveToParagraphEdge(start: true, extending: true)
		case #selector(moveToEndOfParagraphAndModifySelection(_:)):
			moveToParagraphEdge(start: false, extending: true)
		case #selector(moveParagraphBackwardAndModifySelection(_:)):
			extendSelectionByParagraph(-1)
		case #selector(moveParagraphForwardAndModifySelection(_:)):
			extendSelectionByParagraph(1)
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
		// ⌃K, and the twin nothing presses. These two *can* share the line
		// code, unlike the motions above: `deleteToLineEdge` already works to
		// the hard edge of the line and has no toggle in it. The newline is
		// the boundary of a paragraph rather than part of one, so ⌃K at the
		// end of a line takes nothing and does not join it to the next.
		case #selector(deleteToBeginningOfParagraph(_:)): deleteToLineEdge(start: true)
		case #selector(deleteToEndOfParagraph(_:)):       deleteToLineEdge(start: false)
		case #selector(moveToBeginningOfDocument(_:)): moveToDocumentEdge(start: true, extending: false)
		case #selector(moveToEndOfDocument(_:)):      moveToDocumentEdge(start: false, extending: false)
		// ⌘⇧↑ and ⌘⇧↓ are selectors of their own, and arrived here as nothing at
		// all: the plain pair moved and the shifted pair fell through `default:`
		// and looked like two dead keys. The same sentence as ⇧⇞ and ⇧⇟ below,
		// one item earlier, and these were the last two motions in this switch
		// whose `AndModifySelection` twin was missing.
		case #selector(moveToBeginningOfDocumentAndModifySelection(_:)):
			moveToDocumentEdge(start: true, extending: true)
		case #selector(moveToEndOfDocumentAndModifySelection(_:)):
			moveToDocumentEdge(start: false, extending: true)
		case #selector(scrollPageUp(_:)), #selector(pageUp(_:)):     movePage(-1, extending: false)
		case #selector(scrollPageDown(_:)), #selector(pageDown(_:)): movePage(1, extending: false)
		// ⇧⇞ and ⇧⇟ are selectors of their own and arrived here as nothing at
		// all, so the page keys moved the caret and left the selection behind.
		// Found by pressing them from outside the app while watching ⇧↓ at the
		// end of a file, which is the same sentence one key bigger.
		case #selector(pageUpAndModifySelection(_:)):   movePage(-1, extending: true)
		case #selector(pageDownAndModifySelection(_:)): movePage(1, extending: true)
		case #selector(deleteBackward(_:)):      deleteBackward()
		case #selector(deleteForward(_:)):       deleteForward()
		case #selector(insertNewline(_:)):       insertNewlineWithIndent()
		case #selector(insertTab(_:)):
			if !moveToSnippetStop(1) { indentSelectionOrInsertTab() }
		case #selector(insertBacktab(_:)):
			if !moveToSnippetStop(-1) { outdentSelection() }
		case #selector(cancelOperation(_:)):
			// Escape is how somebody says they have finished with the stops and
			// wants Tab back. Nothing else here answers to it.
			snippetSession = nil
			reportSnippetStop()
		case #selector(selectAll(_:)):           selectAllText()
		case #selector(insertLineBreak(_:)):     insertTextAtCaret("\n")
		// ⌃O, which macOS sends as this selector and then `moveBackward:` —
		// two selectors from one key, in that order. A **bare** newline and
		// not `insertNewlineWithIndent()`: the newline goes in, the caret ends
		// up after it, and the `moveBackward:` that follows steps back over
		// it, so the caret finishes where it started with the line split
		// beneath it. That is open-line, and it only composes because the
		// insertion moves the caret exactly one character. Copying the indent
		// would move it by one plus the indent, and `moveBackward:` would land
		// the caret inside the whitespace it had just written — on a line the
		// caret is not supposed to be on at all.
		case #selector(insertNewlineIgnoringFieldEditor(_:)): insertTextAtCaret("\n")
		default:
			// Unhandled selectors are common (e.g. noop:); staying silent is right.
			UnhandledMotions.note(selector)
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

		// A whole character, as a reader means it.
		//
		// **This used to step by UTF-8 sequence and the difference is 0504.**
		// Aligning `caret + delta` to a sequence start is right for "do not land
		// inside an encoded code point" and says nothing about characters: an
		// emoji is one four-byte sequence and moved as one, while `e` followed
		// by a combining acute is two sequences with two valid starts, so →
		// stopped between the letter and its mark. The emoji working is what let
		// it hide.
		let offset = delta == 0
			? caret
			: document.rope.graphemeStep(fromUTF16: caret, by: delta)
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
		// The row the caret is *on*, not the first row of its line. With soft
		// wrap a long line is several rows, and asking folding alone put the
		// caret on the line's first row: ↓ from the middle of a wrapped line
		// then landed on the row it was already on and looked like a dead key.
		let visual = firstVisualRow(forDocumentLine: docLine)
			+ (isWordWrapEnabled ? wrapSegmentForOffset(caret, line: docLine) : 0)

		let motion = VerticalMotion.outcome(from: visual, by: delta, rows: visibleLineCount)
		guard motion != .stay else { return }

		// Remember the x the caret started from so a run of ups and downs keeps
		// returning to the same column — the jumps to either end of the file
		// included, or ⇧↓ to the end of the file and then ↑ would come back to
		// whatever column the last line happened to end at.
		if desiredColumnX == nil {
			desiredColumnX = caretPoint().map { $0.x } ?? textOriginX
		}
		let column = desiredColumnX ?? textOriginX

		let target: Int
		switch motion {
		case .stay:            return
		case .startOfDocument: target = 0
		case .endOfDocument:   target = document.rope.utf16Count
		case .row(let row):
			let point = NSPoint(x: column, y: yPosition(forVisualLine: row) + lineHeight / 2)
			target = offset(at: point)
		}

		setCaret(target, extendingSelection: extending)
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

	/// ⌃A and ⌃E, and the second half of ⌥↑ and ⌥↓.
	///
	/// The hard edge of the line the caret is on, with no first-non-blank stop
	/// and no soft-wrap row — a paragraph is bounded by hard breaks, so
	/// neither question arises. `moveToLineEdge` answers both of them for the
	/// Home key and this is deliberately not that function; the comment in
	/// `doCommand` says what goes wrong when it is.
	private func moveToParagraphEdge(start: Bool, extending: Bool) {
		guard let document else { return }
		desiredColumnX = nil
		let rope = document.rope
		let line = rope.line(atByteOffset: rope.byteOffset(fromUTF16: caret))
		let range = rope.lineByteRange(line)
		setCaret(
			rope.utf16Offset(fromByte: start ? range.lowerBound : range.upperBound),
			extendingSelection: extending
		)
	}

	/// ⌥⇧↑ and ⌥⇧↓.
	///
	/// The edge of this paragraph, or the edge of the next one when the caret
	/// is already on it. That extra step is what tells this apart from
	/// `moveToParagraphEdge`, and it is not a preference: the keys that send
	/// these selectors send them alone, while the keys that send the other two
	/// put a one-character nudge in front to get the same effect. A run of ⌥⇧↑
	/// therefore keeps taking one more line, rather than reaching the start of
	/// the first one and stopping there.
	///
	/// No `extending:` parameter, unlike every other motion here, because
	/// there is nothing to pass it: AppKit declares only the shifted form of
	/// this selector, so the only caller extends.
	private func extendSelectionByParagraph(_ direction: Int) {
		guard let document else { return }
		desiredColumnX = nil
		let rope = document.rope
		func edge(of line: Int) -> Int {
			let range = rope.lineByteRange(line)
			return rope.utf16Offset(fromByte: direction < 0 ? range.lowerBound : range.upperBound)
		}

		let line = rope.line(atByteOffset: rope.byteOffset(fromUTF16: caret))
		var target = edge(of: line)
		if target == caret {
			let neighbour = line + direction
			// At the first line going back, or the last going forward, there
			// is no neighbour and the caret stays on the edge it is already on.
			if neighbour >= 0, neighbour < rope.lineCount { target = edge(of: neighbour) }
		}
		setCaret(target, extendingSelection: true)
	}

	/// ⌘↑ and ⌘↓, with Shift and without.
	///
	/// The remembered column is left alone rather than cleared, so a ↑ after
	/// ⌘⇧↓ comes back to the column the run started at, the same as a ↑ after
	/// ⇧↓ does. That is 0494's rule about the ends of a file, and the jump is
	/// the longest version of the same motion.
	private func moveToDocumentEdge(start: Bool, extending: Bool) {
		guard let document else { return }
		setCaret(start ? 0 : document.rope.utf16Count, extendingSelection: extending)
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

		// Whether this block is waiting to be closed, asked of the file rather
		// than assumed: a `{` typed inside an already-balanced block would
		// otherwise gain a `}` nothing needs.
		let unclosed = ReturnIndent.closingCharacter(for: before).map { closing in
			ReturnIndent.isUnclosed(
				document.rope.string(in: 0..<document.rope.byteCount),
				opening: closing == "}" ? "{" : (closing == ")" ? "(" : "["),
				closing: closing
			)
		} ?? false

		let result = ReturnIndent.result(
			before: before,
			after: after,
			usesTabs: usesTabsForIndent,
			indentWidth: Theme.current.tabWidth,
			unclosed: unclosed
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

	/// Tab: one tab where the caret is, or a level of indentation on every line
	/// the selection touches.
	///
	/// Pressing it with a block selected used to replace the block with a
	/// single tab — the selection gone and the work with it, which is the sort
	/// of thing that costs an undo and a moment's fright.
	private func indentSelectionOrInsertTab() {
		guard shiftLines(by: .indent) else {
			insertTextAtCaret("\t")
			return
		}
	}

	/// ⇧Tab: a level off every line the selection touches, or off the line the
	/// caret is on when nothing is selected.
	private func outdentSelection() {
		_ = shiftLines(by: .outdent, includingCaretLine: true)
	}

	private enum LineShift { case indent, outdent }

	/// Moves the lines a selection covers, and keeps them selected.
	///
	/// Returns false when there is nothing to do — no selection and no line to
	/// outdent — so Tab can fall back to inserting one.
	@discardableResult
	private func shiftLines(by shift: LineShift, includingCaretLine: Bool = false) -> Bool {
		guard let document else { return false }
		let selection = selectedUTF16Range()
		guard !selection.isEmpty || includingCaretLine else { return false }
		guard let block = selectedLineBlock() else { return false }

		let start = block.range.lowerBound
		let end = block.range.upperBound
		let before = block.text
		let after = shift == .indent
			? LineIndent.indent(before, using: "\t")
			: LineIndent.outdent(before, tabWidth: Settings.shared.tabWidth)
		guard after != before else { return false }

		_ = document.replace(utf16Range: start..<end, with: after, caretBefore: caret)

		// The same lines, still selected — an indent that dropped the selection
		// could not be pressed twice.
		let grew = after.utf16.count - before.utf16.count
		if selection.isEmpty {
			let shifted = LineIndent.firstLineShift(from: before, to: after)
			afterEdit(caret: max(start, caret + shifted))
		} else {
			selectionAnchor = start
			afterEdit(caret: end + grew)
			selectionAnchor = start
		}
		return true
	}

	/// The whole lines the selection touches, as a UTF-16 range and their text.
	///
	/// The geometry is the rope's — `lineSpan(touchingUTF16:)` — so that ⇥ and ⌘/
	/// agree about which lines a selection is on. They did not have to before
	/// there were two of them, and two copies of "a selection ending at a line's
	/// start stops at the line above" is exactly the kind of rule that drifts.
	private func selectedLineBlock() -> (range: Range<Int>, text: String)? {
		guard let document else { return nil }
		let rope = document.rope
		let range = rope.lineSpan(touchingUTF16: selectedUTF16Range())
		let startByte = rope.byteOffset(fromUTF16: range.lowerBound)
		let endByte = rope.byteOffset(fromUTF16: range.upperBound)
		return (range, rope.string(in: startByte..<endByte))
	}

	/// ⌘/: comments out the lines the selection touches, or takes the comment
	/// off if they all already carry one.
	///
	/// Everything that decides *what* happens is in `LineComment`, which is a
	/// value in the engine and therefore something the suite can drive. What is
	/// left here is the two things only a view can do: cut the block out of the
	/// rope and put it back as **one** replacement — one ⌘Z for the whole press,
	/// however many lines — and move the selection so it still covers the same
	/// characters afterwards.
	///
	/// The outcome is returned rather than acted on, because the one case that
	/// has to be said out loud belongs to whoever owns the window's corner.
	@discardableResult
	func toggleLineComment() -> LineComment.Outcome {
		guard let document, let block = selectedLineBlock() else { return .nothing }

		let outcome = LineComment.toggle(
			block.text, syntax: CommentSyntax.forLanguage(document.languageId)
		)
		guard case let .toggled(toggle) = outcome else { return outcome }

		let selection = selectedUTF16Range()
		let start = block.range.lowerBound
		let anchor = selectionAnchor
		let grew = toggle.text.utf16.count - block.text.utf16.count

		// The same characters afterwards, carried along by whatever went in in
		// front of them — not the whole lines. ⇥ widens the selection to the
		// lines it moved, which is right for indenting because indenting *is*
		// about the lines; a ⌘/ that did it would answer the second press with a
		// different range than the first, and pressing it twice would no longer
		// leave the file as it was found.
		//
		// An offset past the end of the block moves by the whole change and not
		// through the per-line arithmetic. That is the selection whose end sits
		// on the *next* line's first column: the block deliberately stops before
		// that line, so the offset is outside it and has to be carried rather
		// than clamped to the block's end, which would eat a character.
		func moved(_ offset: Int) -> Int {
			guard offset >= start else { return offset }
			let within = offset - start
			guard within <= block.text.utf16.count else { return offset + grew }
			return start + toggle.offset(
				within, isStartOfSelection: !selection.isEmpty && offset == selection.lowerBound
			)
		}

		let movedCaret = moved(caret)
		let movedAnchor = moved(anchor)
		_ = document.replace(utf16Range: block.range, with: toggle.text, caretBefore: caret)

		afterEdit(caret: movedCaret)
		// `afterEdit` collapses the selection onto the caret, so the anchor goes
		// back afterwards rather than before, the way `shiftLines` does it.
		if !selection.isEmpty { selectionAnchor = movedAnchor }
		return outcome
	}

	/// Replaces a range with text, as an edit made in this view.
	///
	/// For find's Replace and Replace All. It goes through the document like
	/// every other edit — one undo entry, the tab marked dirty, the matches told
	/// through `onTextReplaced` — and then through `afterEdit`, which is the part
	/// a caller outside this class cannot do for itself.
	func replace(utf16Range range: Range<Int>, with text: String) {
		guard let document else { return }
		afterEdit(caret: document.replace(utf16Range: range, with: text, caretBefore: range.lowerBound))
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
	/// Only after typing something a word can be made of — a newline, a bracket
	/// or a space ends the word rather than continuing it, and a list that
	/// stayed up through those would be in the way of the next thing typed — or
	/// after one of the characters the server asked to be woken by.
	///
	/// **The second half is why an enum case could never be offered.** The
	/// caret after a `.` is in no word at all, so what a word-shaped rule can
	/// say about it is nothing, and `.` is exactly where every Swift enum case
	/// belongs. sourcekit-lsp names `.` and `(` at the handshake; openscad-lsp
	/// names none, so a `.scad` is unchanged by this.
	private func requestCompletionsIfTyping(_ typed: String) {
		guard let document else { return }
		guard typed.count == 1, let character = typed.first else {
			onDismissCompletions?()
			return
		}

		// `(`, `[`, `,` and `:` are how a server says "ask me about this call
		// again". Independent of the completion list — the two questions are
		// asked at different moments and one is not the other's fallback.
		if signatureTriggerCharacters.contains(character) { onRequestSignatureHelp?() }

		let isTrigger = completionTriggerCharacters.contains(character)
		let continuesAWord = character.isLetter || character.isNumber || character == "_"
		guard isTrigger || continuesAWord else {
			onDismissCompletions?()
			return
		}

		let prefix = currentWordPrefix()
		guard isTrigger || !prefix.isEmpty else {
			onDismissCompletions?()
			return
		}

		guard let point = caretPoint() else {
			onDismissCompletions?()
			return
		}
		onRequestCompletions?(prefix, isTrigger, point)
		_ = document
	}

	/// Offers completions here, whatever is or is not being typed.
	///
	/// **The difference from the rule above is the whole point.** Typing offers
	/// a list only for a word of two letters or a character the server asked to
	/// be woken by, because a list that appeared on every keystroke would be in
	/// the way. Asking is not typing: the caret may be in the middle of nothing
	/// at all, which is exactly when somebody wants to be told what can go there.
	func requestCompletionsNow() {
		onRequestCompletionsNow?(currentWordPrefix())
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
	///
	/// A snippet with somewhere to go next — `cube(size = ${1:size}, center =
	/// false);$0` has two places — starts a session on the first of them, with
	/// the default selected so that typing replaces it. One with a single
	/// place, and plain text, simply put the caret where the snippet said.
	func applyCompletion(_ snippet: Snippet, replacingPrefixOfLength length: Int) {
		guard let document else { return }
		let start = max(0, caret - length)
		let newCaret = document.replace(
			utf16Range: start..<caret, with: snippet.text, caretBefore: caret
		)

		// `afterEdit` first, and the session after it: inserting the text is
		// itself an edit, and a session started before it would be handed its
		// own arrival as the first thing to follow.
		if snippet.caret < snippet.text.utf16.count {
			afterEdit(caret: start + snippet.caret)
		} else {
			afterEdit(caret: newCaret)
		}

		guard let session = SnippetSession(snippet, insertedAt: start) else {
			snippetStopNames = []
			reportSnippetStop()
			return
		}
		// The defaults, in the order Tab visits them, read out of the text that
		// was just inserted rather than out of the document — which is the same
		// string now and will not be in a moment.
		let units = Array(snippet.text.utf16)
		snippetStopNames = snippet.stops.map { stop in
			let range = stop.range.clamped(to: 0..<units.count)
			return String(decoding: units[range], as: UTF16.self)
		}
		snippetSession = session
		select(session.current)
		reportSnippetStop()
	}

	/// The default text of each stop, in the order Tab visits them.
	private var snippetStopNames: [String] = []

	/// Says which stop is being filled in now, or that none is.
	private func reportSnippetStop() {
		guard let session = snippetSession, snippetStopNames.indices.contains(session.index) else {
			onSnippetStopChanged?(nil)
			return
		}
		onSnippetStopChanged?(snippetStopNames[session.index])
	}

	// MARK: - Snippet stops

	/// Where the stops of the last completion are, while any are left to visit.
	/// Nil the rest of the time, which is nearly all of it.
	private var snippetSession: SnippetSession?

	/// Selects a range, so that typing replaces it.
	///
	/// A stop's default text is text to type over, and a caret sitting at one
	/// end of it would leave somebody to select the word themselves — which is
	/// the work this is meant to save.
	private func select(_ range: Range<Int>) {
		guard let document else { return }
		let upper = min(range.upperBound, document.rope.utf16Count)
		selectionAnchor = min(range.lowerBound, upper)
		caret = upper
		restartCaretBlink()
		scrollCaretToVisible()
		needsDisplay = true
		reportCaretPosition()
	}

	/// Keeps the stops on the text they mark, and lets the session go as soon
	/// as an edit lands anywhere but the stop being typed into.
	private func snippetSessionSaw(edit range: Range<Int>, insertedLength: Int) {
		guard var session = snippetSession else { return }
		snippetSession = session.edited(replacing: range, insertedLength: insertedLength)
			? session
			: nil
		// The hint goes with the session: an edit away from the stops ends it,
		// and a strip still naming a parameter nobody is filling in any more is
		// worse than no strip.
		if snippetSession == nil { reportSnippetStop() }
	}

	/// Tab and ⇧Tab while a snippet is being filled in. Says whether it took
	/// the key; when it did not, Tab means what it always means.
	private func moveToSnippetStop(_ direction: Int) -> Bool {
		guard var session = snippetSession else { return false }

		// Clicked somewhere else and pressed Tab: that is somebody indenting a
		// line, not stepping through a snippet they have visibly left.
		guard session.covers(caret: caret) else {
			snippetSession = nil
			reportSnippetStop()
			return false
		}

		guard let range = session.advance(direction) else {
			// Forwards off the end finishes the session; backwards at the
			// first stop stays put. Both eat the key, because the alternative
			// at either end is a tab character in the middle of a call
			// somebody has just filled in.
			if direction > 0 {
				snippetSession = nil
				reportSnippetStop()
			}
			return true
		}
		snippetSession = session
		select(range)
		reportSnippetStop()
		return true
	}

	/// Draws the visible text to a PNG.
	///
	/// **Because a window capture is not evidence about the editor.** What the
	/// bottom panel is doing decides how much of the window the editor gets, and
	/// a run whose panel happens to be large photographs a terminal — which is
	/// how 0540's own "after" picture came out showing no code at all. This
	/// captures the view, at whatever size it has, and nothing else.
	@discardableResult
	func writeImageForTesting(to path: String) -> Bool {
		let visible = enclosingScrollView?.documentVisibleRect ?? bounds
		guard visible.width > 1, visible.height > 1 else { return false }
		guard let rep = bitmapImageRepForCachingDisplay(in: visible) else { return false }
		cacheDisplay(in: visible, to: rep)
		guard let data = rep.representation(using: .png, properties: [:]) else { return false }
		return (try? data.write(to: URL(fileURLWithPath: path))) != nil
	}

	/// Where the caret is on screen, for putting the list under it.
	func caretScreenPoint() -> NSPoint? {
		guard let point = caretPoint(), let window else { return nil }
		let inWindow = convert(NSPoint(x: point.x, y: point.y), to: nil)
		return window.convertPoint(toScreen: inWindow)
	}

	var lineHeightForTesting: CGFloat { lineHeight }

	/// Selects whole lines and presses Tab or ⇧Tab, the way somebody would.
	/// Puts a caret or a selection where the spec says, presses ⌘/, and says what
	/// came of it.
	///
	/// `from:to` selects those whole lines; `line@column` is a bare caret. The
	/// caret report is half the answer and the more interesting half: whether the
	/// same characters are still selected afterwards is invisible in a picture of
	/// a commented block, and it is the whole of what decides whether the second
	/// press acts on the same thing as the first.
	func toggleCommentForTesting(_ spec: String) -> (LineComment.Outcome, String) {
		guard let document else { return (.nothing, "no document") }
		let rope = document.rope

		if let at = spec.firstIndex(of: "@"),
		   let line = Int(spec[..<at]),
		   let column = Int(spec[spec.index(after: at)...]) {
			let start = rope.utf16Offset(fromByte: rope.byteOffset(ofLine: line))
			setCaret(start + column, extendingSelection: false)
		} else {
			let lines = spec.split(separator: ":").compactMap { Int($0) }
			guard lines.count == 2 else {
				return (.nothing, "spec should be from:to or line@column")
			}
			let start = rope.utf16Offset(fromByte: rope.byteOffset(ofLine: lines[0]))
			let end = rope.utf16Offset(fromByte: rope.lineByteRange(lines[1]).upperBound)
			selectionAnchor = start
			setCaret(end, extendingSelection: true)
		}

		return (toggleLineComment(), caretReportForTesting)
	}

	/// Selects whole lines and leaves them selected, taking nothing else.
	///
	/// For the half of item 510 that can only be judged by eye: a selection in
	/// this view drawn while the keyboard is somewhere else. Every other verb
	/// that makes a selection here — indenting, commenting — makes the editor
	/// the first responder first, because it is about to type into it, and one
	/// that did that would put the keyboard back in the very view whose
	/// unfocused colour is the thing being photographed.
	func selectLinesForTesting(fromLine: Int, toLine: Int) {
		guard let document else { return }
		let rope = document.rope
		let start = rope.utf16Offset(fromByte: rope.byteOffset(ofLine: fromLine))
		let end = rope.utf16Offset(fromByte: rope.lineByteRange(toLine).upperBound)
		selectionAnchor = start
		setCaret(end, extendingSelection: true)
	}

	func indentForTesting(fromLine: Int, toLine: Int, outdent: Bool) {
		guard let document else { return }
		let rope = document.rope
		let start = rope.utf16Offset(fromByte: rope.byteOffset(ofLine: fromLine))
		let end = rope.utf16Offset(fromByte: rope.lineByteRange(toLine).upperBound)
		selectionAnchor = start
		setCaret(end, extendingSelection: true)
		if outdent { outdentSelection() } else { indentSelectionOrInsertTab() }
	}

	/// The document as it stands, for a test to read back.
	/// Clicks in the empty space under the last line and says where the caret
	/// went, and what the click landed on.
	///
	/// Through the window's hit testing rather than by calling `mouseDown`
	/// directly: what was wrong was not where the click was translated to but
	/// that the click never reached this view at all, and a test that dispatched
	/// the event by hand would have agreed with the view while the empty space
	/// under a short file still did nothing.
	func clickBelowLastLineForTesting() -> String {
		guard let window, let root = window.contentView else { return "no window" }

		// A point in the gap: below the text, inside the viewport, and to the
		// right of the gutter so it counts as text rather than as a fold.
		let textBottom = CGFloat(visibleLineCount) * lineHeight
		let viewport = enclosingScrollView?.contentSize.height ?? bounds.height
		guard viewport > textBottom + lineHeight else { return "no empty space below the text" }
		let target = NSPoint(x: gutterWidth + 60, y: textBottom + (viewport - textBottom) / 2)

		let inWindow = convert(target, to: nil)
		let hit = root.hitTest(inWindow)
		let landedHere = hit === self

		if let hit, landedHere {
			hit.mouseDown(with: NSEvent.mouseEvent(
				with: .leftMouseDown, location: inWindow, modifierFlags: [],
				timestamp: ProcessInfo.processInfo.systemUptime,
				windowNumber: window.windowNumber, context: nil,
				eventNumber: 0, clickCount: 1, pressure: 1
			) ?? NSEvent())
		}

		let line = document.map { document -> Int in
			document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: caret)) + 1
		} ?? 0
		let hitName = hit.map { String(describing: type(of: $0)) } ?? "nothing"
		return "hit=\(landedHere ? "editor" : hitName)"
			+ " caretLine=\(line) of \(document?.lineCount ?? 0)"
			+ " frame=\(Int(frame.height)) viewport=\(Int(enclosingScrollView?.contentSize.height ?? -1))"
			+ " text=\(Int(textBottom)) point=\(Int(target.x)),\(Int(target.y))"
	}

	var textForTesting: String {
		guard let document else { return "" }
		return document.rope.string(in: 0..<document.rope.byteCount)
	}

	func setCaretForTesting(_ offset: Int) {
		setCaret(offset, extendingSelection: false)
	}

	/// Puts the caret at a line and column. A negative line counts back from the
	/// end, so -1 is the last line — which is where a driver watching ↓ at the
	/// bottom of the file has to start, and which it cannot work out from an
	/// offset without knowing the file.
	///
	/// The column stops at the end of that line rather than running on into the
	/// next one: a driver that asked for column 40 of a line of eight would
	/// otherwise be watching the keys from a line it did not name.
	///
	/// It forgets the remembered column as a click does, so each thing a driver
	/// tries is a run of its own. Without that, a ⇧↓ placed after an earlier
	/// press returns to the column of that earlier press and the report reads
	/// as a bug in the column memory rather than as the driver's own doing.
	func setCaretForTesting(line: Int, column: Int) {
		guard let document else { return }
		desiredColumnX = nil
		let rope = document.rope
		let wanted = line < 0 ? document.lineCount + line : line
		let resolved = min(max(0, wanted), document.lineCount - 1)
		let range = rope.lineByteRange(resolved)
		let start = rope.utf16Offset(fromByte: range.lowerBound)
		let end = rope.utf16Offset(fromByte: range.upperBound)
		setCaret(min(start + max(0, column), end), extendingSelection: false)
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

		// A whole character, and the same one the caret steps over.
		//
		// This said "composed character" and stepped by UTF-8 sequence, so ⌫
		// after `é` written as `e` + U+0301 took the accent and left the letter.
		// Deleting and moving now ask the same question, which is what stops
		// them drifting apart later — 0504 is exactly the shape of that drift.
		let start = document.rope.graphemeStep(fromUTF16: caret, by: -1)
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

		// ⌦ had its own copy of the byte walk — forwards over continuation
		// bytes — with the same fault and one more implementation of it. All
		// four of these now ask the rope the one question.
		let end = document.rope.graphemeStep(fromUTF16: caret, by: 1)
		let newCaret = document.replace(utf16Range: caret..<end, with: "", caretBefore: caret)
		afterEdit(caret: newCaret)
	}

	private func afterEdit(caret newCaret: Int) {
		guard let document else { return }
		folding.setAvailable(document.folds)
		caret = newCaret
		selectionAnchor = newCaret
		desiredColumnX = nil

		// The line that was just edited may be longer than anything the file
		// held when it was opened, and `longestLineColumns` is measured once at
		// load and never again. Without this, typing or pasting a line wider
		// than the pane produces a document view no wider than the pane: no
		// scroll range, no horizontal scroller, and no way to reach the text
		// that was just typed. `reveal` has widened for one line since it was
		// written — the same call, at the other place a line's width can change.
		widenForTheLongestLine(upTo: document.rope.line(
			atByteOffset: document.rope.byteOffset(fromUTF16: newCaret)
		))
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

	/// The document's undo is not the rename field's.
	///
	/// While a name is being typed the field is a subview of this one, so the
	/// field editor's responder chain runs through here — and ⌘Z over a field
	/// means "take back what I just typed into it", not "take back the last edit
	/// to the file". Answering no is what lets the field editor have it.
	///
	/// `responds(to:)` rather than a no-op body, which is the same lesson the
	/// navigator learned: `tryToPerform` asks this and not the method, so a body
	/// that did nothing would *swallow* ⌘Z and leave the field with no undo at
	/// all.
	override func responds(to selector: Selector!) -> Bool {
		if selector == #selector(undo(_:)) || selector == #selector(redo(_:)) {
			guard !isRenaming else { return false }
		}
		return super.responds(to: selector)
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
