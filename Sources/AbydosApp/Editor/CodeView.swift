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
final class CodeView: NSView, NSTextInputClient, NSUserInterfaceValidations {

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// The field laid over a symbol while its new name is being typed.
	///
	/// A subview of this view rather than a panel above it, which is the whole
	/// difference between the two kinds of thing this editor puts on screen. The
	/// completion list is a child window because it has to hang past the
	/// editor's edges and must never take focus; this is the opposite of both —
	/// it is *in* the text, it scrolls with it because this view is the scroll
	/// view's document view, and typing into it is the entire point.
	let rename = RenameField()

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// Asked to say more about the commit on a line.
	var onShowBlameDetail: ((GitBlame.Line) -> Void)?

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// Where the last picture paste wrote its file, for the driven run's report.
	var lastPastedPictureForTesting: URL?
	/// Range of in-progress IME composition. Named distinctly from the
	/// `markedRange()` protocol method it backs.
	var composingRange = NSRange(location: NSNotFound, length: 0)

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// The word under the pointer while ⌘ is held, in line-relative UTF-16.
	var navigableWord: (line: Int, range: Range<Int>)?

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// How this file indents — the kind, and for spaces the width — read from
	/// the buffer when it arrives and whenever it is replaced wholesale, and
	/// changed by the footer's menu through `convertIndentation(to:)`. Every
	/// insertion follows it: ⇥, ⇧⇥, a block indent, return's auto-indent and
	/// the closing brace's dedent. Held once here rather than sampled per
	/// keypress — `usesTabsForIndent`, which this replaces, re-read the top
	/// of the file on every return.
	var indentStyle: IndentStyle = .spaces(width: Settings.shared.tabWidth)
	/// The default text of each stop, in the order Tab visits them.
	var snippetStopNames: [String] = []

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// Where the stops of the last completion are, while any are left to visit.
	/// Nil the rest of the time, which is nearly all of it.
	var snippetSession: SnippetSession?

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// The breakpoint being dragged out of the gutter, if one is.
	var draggingBreakpointLine: Int?
	/// Whether letting go now would throw the dragged breakpoint away.
	///
	/// A drag is not a decision until it ends. Deleting the moment the pointer
	/// passed the gutter meant a breakpoint was gone before the mouse button
	/// came up, with no way back but to put it on again — so the pointer says
	/// what will happen, and the button says whether to do it.
	var breakpointWouldBeRemoved = false
	/// Told to open a value, with where on screen it was.
	var onOpenInlineValue: ((InlineValueHint, NSRect) -> Void)?

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// A place that should be on screen and could not be worked out yet.
	///
	/// The other half of not betting on a turn count: where the pane has no size
	/// even after layout has been forced — a tab whose window is not on screen
	/// yet, a pane the layout pass has not reached — the request waits here, and
	/// `viewportChanged` brings it on screen the moment the pane is given one.
	/// Nothing retries on a timer and nothing scrolls to a number measured
	/// against a viewport of zero.
	var pendingReveal: (offset: Int, end: Int?)?
	/// Guards the drain against itself: the scroll below can change the frame,
	/// and a frame change is what called it.
	var isDrainingReveal = false
	// MARK: - Model

	private(set) var document: TextDocument?
	var folding = FoldingState()

	/// Row mapping when soft wrap is on. Empty means one row per line.
	var wrapLayout = WrapLayout()
	var isWordWrapEnabled = false

	/// Caret and selection anchor, in UTF-16 offsets.
	var caret = 0
	var selectionAnchor = 0

	/// Column the caret tries to keep while moving vertically, so travelling
	/// through short lines does not lose the original column.
	var desiredColumnX: CGFloat?

	var onCaretMoved: ((Int, Int) -> Void)?   // line, column (1-based)
	var onDirtyChanged: ((Bool) -> Void)?

	/// Search matches to highlight, and which one is current.
	var searchMatches: [SearchMatch] = []
	var currentMatchIndex: Int?
	/// Where the selected text also appears, in file order.
	///
	/// Never both these and `searchMatches`: find's matches win while find is
	/// showing, so one of the two lists is always empty. Kept as ranges rather
	/// than `SearchMatch` because a band needs an offset and nothing here reads
	/// a line's text.
	var selectionOccurrences: [Range<Int>] = []
	/// Which selection the bands above were found for.
	///
	/// Checked before anything is painted, because not every path that changes a
	/// selection reports the caret — `selectAllText` sets both ends and redraws —
	/// and a band left under text nobody selected is precisely the fault this
	/// feature must not introduce. Comparing two integers per draw is the price
	/// of not having to trust every present and future path to say so.
	var occurrencesSelection: Range<Int>?
	/// Scanning for the selection's other places, once it has settled.
	var occurrenceScan: DispatchWorkItem?

	/// Debugger state for this file: breakpoint lines and where execution stopped.
	var breakpointLines: [Int: BreakpointMark] = [:]
	var executionLine: Int?

	/// The variables of the frame execution stopped in, by name, or nil while
	/// nothing is stopped.
	///
	/// A dictionary rather than text per line: it is built once per stop, and a
	/// row's drawing is then a scan of that row's tokens against it. Nothing is
	/// worked out for a file this frame is not in — the editor does not hand it
	/// one — and nothing at all while this is nil, which is the ordinary state.
	var inlineValues: [String: Variable]?
	/// 1-based lines that have something runnable on them, and the click that
	/// runs it.
	var runnableLines: Set<Int> = []
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
	var diagnosticsByLine: [Int: [LSPDiagnostic]] = [:]

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
	var isOverInlineValue = false

	/// Whether the server that sent what is on screen had said it was preparing.
	var diagnosticsArePreparing = false

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

	var font: NSFont = Theme.current.editorFont
	var lineHeight: CGFloat = 18
	var baselineOffset: CGFloat = 4
	var charWidth: CGFloat = 7
	var gutterWidth: CGFloat = 60

	/// Which lines differ from HEAD, for the gutter's change marks. 1-based
	/// document lines, as `GitChangedLines` reads them off the diff.
	var changedLines = GitChangedLines()

	// MARK: - Secret covers

	/// Whether this file's values are drawn under redaction covers — set at
	/// open from the file's name, via `DotenvSecrets.conceals(fileNamed:)`.
	var concealsSecrets = false
	/// The file-wide reveal, toggled from the View menu and lasting until
	/// toggled back.
	private(set) var secretsRevealedAll = false
	/// A cover was clicked: the owner says how to unlock, this view stays out
	/// of the messaging business.
	var onCoveredSecretClicked: (() -> Void)?

	func setConcealsSecrets(_ conceals: Bool) {
		concealsSecrets = conceals
		refreshSecretRoles()
		needsDisplay = true
	}

	/// Every line's role, kept because a line's own text cannot say it: a
	/// YAML block scalar's value lives on the lines *after* `pk: |`, and
	/// classifying rows one at a time drew an RSA key in the clear under a
	/// covered indicator. Recomputed whole on every edit — a secrets file is
	/// small, and O(lines) per keystroke in one is cheaper than being wrong
	/// once.
	private var secretRoles: [DotenvSecrets.LineRole] = []

	private func refreshSecretRoles() {
		guard concealsSecrets, let document else {
			secretRoles = []
			return
		}
		secretRoles = DotenvSecrets.roles(
			forLines: (0..<document.lineCount).map { document.lineText($0) }
		)
	}

	var showsSecretCovers: Bool { concealsSecrets }

	/// How long a revealed file stays revealed with nobody touching it —
	/// five minutes, and then the covers come back on their own, so an
	/// unlocked document forgotten in the background does not sit open
	/// through the next call. A variable rather than a constant so a driven
	/// run can prove the re-conceal without five minutes of wall clock.
	var secretsIdleLimit: TimeInterval = 300

	/// When the document was last touched — a key, a click, a scroll, an
	/// edit — and the one deferred check. The check is re-armed for the
	/// remainder when it finds recent touches, so activity costs a `Date()`
	/// store and never a timer reset per keystroke.
	private var secretsLastTouched = Date()
	private var secretsIdleCheck: DispatchWorkItem?

	func setSecretsRevealed(_ revealed: Bool) {
		secretsRevealedAll = revealed
		needsDisplay = true
		secretsIdleCheck?.cancel()
		secretsIdleCheck = nil
		guard revealed, concealsSecrets else { return }
		secretsLastTouched = Date()
		scheduleIdleConceal(after: secretsIdleLimit)
	}

	/// A cover came back by itself; whoever owns the lock in the status bar
	/// wants to know.
	var onSecretsAutoConcealed: (() -> Void)?

	private func scheduleIdleConceal(after delay: TimeInterval) {
		let work = DispatchWorkItem { [weak self] in
			guard let self, secretsRevealedAll, concealsSecrets else { return }
			let idle = Date().timeIntervalSince(secretsLastTouched)
			if idle >= secretsIdleLimit {
				setSecretsRevealed(false)
				onSecretsAutoConcealed?()
			} else {
				scheduleIdleConceal(after: secretsIdleLimit - idle)
			}
		}
		secretsIdleCheck = work
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
	}

	/// The cheap half of the idle clock, called from the interaction paths.
	func noteSecretsTouch() {
		guard secretsRevealedAll else { return }
		secretsLastTouched = Date()
	}

	/// Scrolling is reading, and reading is interaction: without this the
	/// covers would come back over a long file somebody is in the middle of.
	override func scrollWheel(with event: NSEvent) {
		noteSecretsTouch()
		super.scrollWheel(with: event)
	}

	/// One word per line — covered, revealed, or plain — so a driven run can
	/// claim what an arrow-walk did and did not lift without reading pixels.
	func secretsReportForTesting() -> String {
		guard let document else { return "no document" }
		guard concealsSecrets else { return "not concealing" }
		var lines: [String] = []
		for docLine in 0..<min(document.lineCount, 40) {
			let covered: Bool
			if docLine < secretRoles.count {
				covered = secretRoles[docLine] != .plain
			} else {
				covered = DotenvSecrets.valueRange(inLine: document.lineText(docLine)) != nil
			}
			guard covered else {
				lines.append("\(docLine + 1) plain")
				continue
			}
			lines.append("\(docLine + 1) \(secretsRevealedAll ? "revealed" : "covered")")
		}
		return lines.joined(separator: "\n")
	}

	/// The context menu as a right-click at the gutter or in the text would
	/// build it, one title per line — so which menu answers where is a text
	/// claim rather than a screenshot.
	func contextMenuReportForTesting(atGutter: Bool) -> String {
		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0
		let x = atGutter ? scrollX + gutterWidth / 2 : scrollX + gutterWidth + 40
		let location = convert(NSPoint(x: x, y: lineHeight / 2), to: nil)
		guard let event = NSEvent.mouseEvent(
			with: .rightMouseDown, location: location, modifierFlags: [],
			timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil,
			eventNumber: 0, clickCount: 1, pressure: 1
		), let menu = menu(for: event) else { return "no menu" }
		return menu.items
			.map { $0.isSeparatorItem ? "—" : $0.title }
			.joined(separator: " · ")
	}

	/// The caret placed on a line, the way an arrow-walk arrives — which must
	/// reveal nothing, and a driven run proves it by doing exactly this.
	func moveCaretForTesting(toLine docLine: Int) {
		// A touch, as the arrow key it stands for would be.
		noteSecretsTouch()
		guard let document, docLine < document.lineCount else { return }
		let offset = document.rope.utf16Offset(
			fromByte: document.rope.byteOffset(ofLine: docLine)
		)
		setCaret(offset, extendingSelection: false)
	}



	/// The cover over one visual row: what is erased, and the pill drawn on it.
	///
	/// **The pill is one fixed width for every secret**, because a cover
	/// fitted to its value says how long the value is — which for a key is
	/// something. So the value's glyphs are erased from where the value starts
	/// to the row's edge (a dotenv value is the rest of its line), in the
	/// row's own background so the line simply appears to end, and the pill on
	/// top is the same twelve columns whatever it hides. A wrapped line's
	/// continuation rows are erased whole with no pill of their own.
	func secretCover(
		docLine: Int, visualRow: Int
	) -> (erase: NSRect, pill: NSRect?)? {
		guard concealsSecrets, !secretsRevealedAll, let document,
		      docLine < document.lineCount else { return nil }

		let y = yPosition(forVisualLine: visualRow)
		let row = NSRect(x: 0, y: y, width: 0, height: lineHeight)

		// A block scalar's content line: the whole row is the value, however
		// it is indented, and it gets the pill so thirty erased rows read as
		// a redaction rather than as the file ending early.
		if docLine < secretRoles.count, secretRoles[docLine] == .blockContent {
			return (
				erase: NSRect(
					x: textOriginX, y: row.minY,
					width: max(0, bounds.width - textOriginX), height: row.height
				),
				pill: wrapSegment(forVisualRow: visualRow) == 0
					? NSRect(
						x: textOriginX, y: row.minY + 1,
						width: charWidth * 12, height: row.height - 2
					)
					: nil
			)
		}
		if docLine < secretRoles.count, secretRoles[docLine] == .plain { return nil }

		let line = document.lineText(docLine)
		guard let range = DotenvSecrets.valueRange(inLine: line) else { return nil }

		if wrapSegment(forVisualRow: visualRow) > 0 {
			return (
				erase: NSRect(
					x: textOriginX, y: row.minY,
					width: max(0, bounds.width - textOriginX), height: row.height
				),
				pill: nil
			)
		}

		let prefix = String(line[..<range.lowerBound])
		let startX = textOriginX + NSAttributedString(
			string: prefix, attributes: [.font: font]
		).size().width
		return (
			erase: NSRect(
				x: startX, y: row.minY,
				width: max(0, bounds.width - startX), height: row.height
			),
			pill: NSRect(
				x: startX, y: row.minY + 1,
				width: charWidth * 12, height: row.height - 2
			)
		)
	}

	/// Who last touched each line, when blame is being shown.
	///
	/// One entry per line of the file as it was read; a file edited since is
	/// blamed again on the next save, and until then the entries still line up
	/// with what is on screen for everything above the edit.
	var blame: [GitBlame.Line] = []
	var isBlameVisible = false
	/// The line whose entry the pointer is over, lit with the rest of its
	/// commit's run, since the run is what the one label stands for.
	var hoveredBlameLine: Int?
	/// The width of the blame column, in characters.
	static let blameColumns = 18

	var blameWidth: CGFloat {
		isBlameVisible ? ceil(CGFloat(Self.blameColumns) * charWidth) + Self.gutterPadding : 0
	}

	static let gutterPadding: CGFloat = 10
	/// Clickable strip on the far left of the gutter, where a runnable line
	/// gets its play triangle.
	static var breakpointColumnWidth: CGFloat { Theme.current.scaled(18) }
	/// The strip at the right of the gutter that folds and unfolds.
	///
	/// Its own column now: a click on the line number makes a breakpoint, so
	/// folding needs somewhere of its own to be clicked — the chevron, and
	/// nothing else.
	static var foldColumnWidth: CGFloat { Theme.current.scaled(16) }
	static let textLeftPadding: CGFloat = 8
	/// Extra rows drawn beyond the viewport so fast scrolling does not flash.
	static let overscanLines = 2

	var longestLineColumns = 80

	// MARK: - Caret blinking

	var caretVisible = true
	var caretTimer: Timer?

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
		// **A wholesale replacement is not somebody typing.** The marks shift
		// with every edit and mark what an edit put there, which is the right
		// answer for a keystroke and the wrong one for a decrypt, a lock or a
		// reload: replacing every line marked every line, so a SOPS file
		// decrypted read as wholly modified in the gutter when git had nothing
		// to say about it at all. Cleared here; the group asks git for the
		// truth, which is the only thing that knows it.
		setChangedLines(GitChangedLines())
		// A buffer replaced wholesale — a decrypt, a lock, an external reload —
		// is a new text whose habit is new, and a choice made from the
		// footer's menu about the old one goes with it.
		redetectIndentStyle()

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
		// The conceal flag arrives at tab wiring, before this document does:
		// computed then, the roles were an empty array over a nil document and
		// a block scalar's key sat in the clear. Computed again here, they see
		// the file.
		refreshSecretRoles()
		// The file's indent habit, read once here rather than sampled on every
		// return keypress the way `usesTabsForIndent` used to: the footer's
		// chip needs a held answer, and the sample costs more than the holding.
		redetectIndentStyle()
		document.onLinesChanged = { [weak self] first, removed, inserted in
			// The change marks ride the same signal breakpoints anchor by,
			// before it is relayed: the marks are this view's own.
			self?.shiftChangedLines(from: first + 1, removed: removed, inserted: inserted)
			// And the secret roles, because an edit can open or close a block
			// scalar lines away from itself.
			if self?.concealsSecrets == true { self?.refreshSecretRoles() }
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
}
