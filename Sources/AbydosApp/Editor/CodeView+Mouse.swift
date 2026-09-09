import AppKit
import AbydosKit

/// Hit testing and the pointer: what a click, a drag and a double-click select,
/// and what a right-click offers.
extension CodeView {
	// MARK: - Hit testing

	/// UTF-16 offset at a point in view coordinates.
	func offset(at point: NSPoint) -> Int {
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
		noteSecretsTouch()
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

		// A click on a cover reveals nothing — a click is exactly what a
		// presenter does absentmindedly on the screen everybody is watching.
		// It says how to look instead: the lock in the status bar, which is a
		// deliberate act with a state everybody can see.
		if concealsSecrets, !secretsRevealedAll {
			let visual = max(0, min(visibleLineCount - 1, Int(floor(point.y / lineHeight))))
			let docLine = documentLine(forVisualRow: visual)
			if let cover = secretCover(docLine: docLine, visualRow: visual),
			   cover.erase.contains(point) {
				onCoveredSecretClicked?()
			}
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
		if let menu = gutterMenu(at: point, scrollX: scrollX, event: event) {
			NSMenu.popUpContextMenu(menu, with: event, for: self)
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

	/// What a right-click in the gutter opens, or nil past it: a breakpoint's
	/// own menu on its marker, and everywhere else — the blame column, the
	/// numbers, the blank left of them — the gutter's menu, with the caret
	/// left where it is, since a right-click on a number is not a click on
	/// text. It used to be nothing, and only the fold strip at the gutter's
	/// edge reached the menu, which nobody could have known to aim for.
	private func gutterMenu(at point: NSPoint, scrollX: CGFloat, event: NSEvent) -> NSMenu? {
		guard point.x < scrollX + gutterWidth - Self.foldColumnWidth, let document else { return nil }
		let visual = max(0, min(visibleLineCount - 1, Int(floor(point.y / lineHeight))))
		let docLine = min(document.lineCount - 1, documentLine(forVisualRow: visual))
		if let mark = breakpointLines[docLine] {
			return breakpointMenu(for: docLine, mark: mark)
		}
		return menu(for: event)
	}

	/// What a right-click at a line's leftmost gutter pixel opens, by title.
	func gutterRightClickReportForTesting(line docLine: Int) -> String {
		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0
		let visual = firstVisualRow(forDocumentLine: docLine)
		let point = NSPoint(x: scrollX + 2, y: yPosition(forVisualLine: visual) + lineHeight / 2)
		guard let event = NSEvent.mouseEvent(
			with: .rightMouseDown, location: convert(point, to: nil), modifierFlags: [],
			timestamp: 0, windowNumber: window?.windowNumber ?? 0, context: nil,
			eventNumber: 0, clickCount: 1, pressure: 1
		), let menu = gutterMenu(at: point, scrollX: scrollX, event: event) else { return "no menu" }
		return menu.items.map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: " · ")
	}

	/// What can be done to the breakpoint that was right-clicked.
	private func breakpointMenu(for docLine: Int, mark: BreakpointMark) -> NSMenu {
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
		return menu
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

		// **The gutter answers for itself.** A right-click on the line numbers
		// used to open the text area's menu — Go to Definition, Cut, Paste —
		// none of which is about the gutter. The boundary is the same
		// scroll-adjusted width every gutter click already respects.
		let point = convert(event.locationInWindow, from: nil)
		let scrollX = enclosingScrollView?.contentView.bounds.origin.x ?? 0
		if point.x < scrollX + gutterWidth {
			let gutter = NSMenu()
			// A title, not a checkmark: the menu is transient and the state
			// lives visibly in the editor — the column is there or it is not.
			// A nil target walks the responder chain to the one implementation
			// the View menu and ⌥⌘B already share, so the three handles cannot
			// drift.
			let blame = NSMenuItem(
				title: isBlameVisible ? "Hide Blame" : "Show Blame",
				action: #selector(MainWindowController.toggleBlame(_:)),
				keyEquivalent: ""
			)
			gutter.addItem(blame)
			return gutter
		}

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
}
