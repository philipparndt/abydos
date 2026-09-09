import AppKit
import AbydosKit

/// The keyboard: which key does what, moving the caret, and editing the text.
extension CodeView {
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
		// A keystroke that would type into a read-only document says so out
		// loud, once per key, rather than being swallowed in silence; the
		// document itself declines the edit, this only makes the refusal heard.
		if document?.isReadOnly == true, let typed = event.characters, !typed.isEmpty,
		   !event.modifierFlags.contains(.command), typed.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) {
			NSSound.beep()
			return
		}
		noteSecretsTouch()
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

	func selectAllText() {
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
			usesTabs: indentStyle == .tabs,
			indentWidth: indentSpaceWidth,
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
			before, usesTabs: indentStyle == .tabs, indentWidth: indentSpaceWidth
		)
		guard dedented != before else { return }

		let newCaret = document.replace(
			utf16Range: lineStart..<(lineStart + beforeLength),
			with: dedented,
			caretBefore: caret
		)
		afterEdit(caret: newCaret + 1)
	}


	/// Reads the buffer's habit into the style, at open and after a wholesale
	/// replacement. The same 8 KB window the old per-keypress sample read.
	func redetectIndentStyle() {
		guard let document else { return }
		let sample = document.rope.string(in: 0..<min(document.rope.byteCount, 8192))
		indentStyle = IndentStyle.detect(in: sample, fallbackWidth: Settings.shared.tabWidth)
	}

	/// The footer menu's pick: the buffer's indentation converted to the
	/// chosen style — every leading level becomes a level of it, alignment
	/// after the first non-blank left alone — and the style made the one
	/// that is inserted from here. One edit, so one ⌘Z returns the file to
	/// what it was.
	func convertIndentation(to style: IndentStyle) {
		guard let document else { return }
		let text = document.rope.string(in: 0..<document.rope.byteCount)
		replaceAllText(with: IndentStyle.converted(text, from: indentStyle, to: style))
		// The choice stands over the re-read a wholesale replacement does: a
		// conversion is the one replacement whose style is known without
		// reading the buffer, because it was chosen — a file converted to
		// tabs that has no indented line yet must not fall back to spaces
		// the moment its own menu item is taken.
		indentStyle = style
	}

	/// The width a spaces style inserts at; for a tabs file, the setting —
	/// which `ReturnIndent` ignores for tabs and `LineIndent` needs only for
	/// the space branch of an outdent.
	private var indentSpaceWidth: Int {
		if case .spaces(let width) = indentStyle { return width }
		return Settings.shared.tabWidth
	}

	/// Tab: one level of the file's own style where the caret is, or a level
	/// on every line the selection touches.
	///
	/// Pressing it with a block selected used to replace the block with a
	/// single tab — the selection gone and the work with it, which is the sort
	/// of thing that costs an undo and a moment's fright.
	func indentSelectionOrInsertTab() {
		guard shiftLines(by: .indent) else {
			insertTextAtCaret(indentStyle.unit)
			return
		}
	}

	/// ⇧Tab: a level off every line the selection touches, or off the line the
	/// caret is on when nothing is selected.
	func outdentSelection() {
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
			? LineIndent.indent(before, using: indentStyle.unit)
			: LineIndent.outdent(before, tabWidth: indentSpaceWidth)
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

	func insertTextAtCaret(_ text: String) {
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


	/// Says which stop is being filled in now, or that none is.
	func reportSnippetStop() {
		guard let session = snippetSession, snippetStopNames.indices.contains(session.index) else {
			onSnippetStopChanged?(nil)
			return
		}
		onSnippetStopChanged?(snippetStopNames[session.index])
	}
}
