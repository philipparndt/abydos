import AppKit
import AbydosKit

/// Snippet stops, the standard editing actions AppKit sends, the folding
/// commands, and `NSTextInputClient`.
extension CodeView {
	// MARK: - Snippet stops


	/// Selects a range, so that typing replaces it.
	///
	/// A stop's default text is text to type over, and a caret sitting at one
	/// end of it would leave somebody to select the word themselves — which is
	/// the work this is meant to save.
	func select(_ range: Range<Int>) {
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
	func snippetSessionSaw(edit range: Range<Int>, insertedLength: Int) {
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
	func moveToSnippetStop(_ direction: Int) -> Bool {
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
		// With undo, redo and this: the three doors by which the text goes
		// back to a former state. The habit is that state's — an undo that
		// restored a conversion's tabs while the chip still claimed the
		// conversion is a lie somebody would type against.
		redetectIndentStyle()
		reportCaretPosition()
		onDirtyChanged?(document.isDirty)
	}

	func deleteBackward() {
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

	func deleteForward() {
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

	func afterEdit(caret newCaret: Int) {
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
		// The text went back to a former state; its habit is that state's.
		// The undo of a conversion is the case, and the chip follows the
		// text back rather than claiming the conversion still stands.
		redetectIndentStyle()
	}

	@objc func redo(_ sender: Any?) {
		guard let document, let restored = document.redo() else { return }
		afterEdit(caret: restored)
		// The mirror of undo's reason: redo re-applies what the text went
		// back to, conversion included.
		redetectIndentStyle()
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

	/// Paste greys itself out over a board with nothing this view can paste:
	/// text, or a picture in a document whose language has a syntax for one.
	/// Asked of the board's types, since a menu validates every time it opens.
	/// Every other item this view answers stays enabled, which is what it was
	/// before this method existed.
	func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		guard item.action == #selector(paste(_:)) else { return true }
		let board = NSPasteboard.general
		if board.availableType(from: [.string]) != nil { return true }
		return FilePasteboard.hasPicture(on: board) && PictureReference.hasSyntax(document?.languageId)
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
		paste(from: .general)
	}

	/// The board's text, as always — or, when it has none, its picture: a file
	/// in `images` beside the document and a reference to it at the caret.
	///
	/// Text first, because this is a text editor and ⌘V over text has always
	/// pasted the text. The picture path is taken only when there is no string
	/// at all, and only in a document whose language has a syntax for a
	/// picture; pixels into a Swift file do nothing, as they always did, since
	/// a file written into the source tree that nothing references is a stray
	/// screenshot in the repository.
	///
	/// The file is written first and the reference inserted second, as one
	/// replace: ⌘Z here takes the reference back and leaves the file, which is
	/// in the tree, where the tree's own ⌘Z removes it. Two stacks, and focus
	/// decides which — a text undo must never delete a file.
	func paste(from board: NSPasteboard) {
		if let text = board.string(forType: .string) {
			insertTextAtCaret(text)
			return
		}
		guard let document, FilePasteboard.hasPicture(on: board) else { return }
		guard let reference = PictureReference.make(
			for: document.url, language: document.languageId,
			isTaken: { FileManager.default.fileExists(atPath: $0.path) }
		) else { return }
		guard let png = FilePasteboard.picture(on: board) else {
			Toast.post("Cannot paste that picture", detail: "The clipboard's picture could not be read.")
			return
		}
		do {
			try FileManager.default.createDirectory(
				at: reference.folder, withIntermediateDirectories: true
			)
			try png.write(to: reference.file, options: .withoutOverwriting)
		} catch {
			// Nothing inserted: a reference to a file that is not there is
			// worse than no paste.
			Toast.post("Cannot paste that picture", detail: error.localizedDescription)
			return
		}
		let selection = selectedUTF16Range()
		let range = selection.isEmpty ? caret..<caret : selection
		document.replace(utf16Range: range, with: reference.text, caretBefore: range.lowerBound)
		// Inside the empty description rather than after the reference, so the
		// next thing typed is the alt text.
		afterEdit(caret: range.lowerBound + reference.caretOffset)
		lastPastedPictureForTesting = reference.file
		// A scratch has a folder — the scratch directory — so the paste works,
		// but a scratch saved elsewhere later carries a reference that no
		// longer resolves. Said now rather than discovered then.
		if ScratchFiles.isScratch(document.url) {
			Toast.post(
				"Pasted beside the scratch",
				detail: "The picture is in the scratch folder; saving the scratch elsewhere leaves it behind.",
				kind: .information
			)
		}
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
