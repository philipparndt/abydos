import AppKit
import AbydosKit

/// The verbs on the terminal's own menu, and `NSTextInputClient` — which is
/// how a dead key, an input method and a character palette reach a program that
/// only understands bytes.
extension TerminalView {
	// MARK: - Actions

	@objc func copy(_ sender: Any?) {
		// Only what is selected. Copying the entire buffer when nothing is
		// selected is a surprise nobody wants pasted somewhere else.
		guard let selection else { return }
		let text = emulator.grid.text(in: selection)
		guard !text.isEmpty else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	@objc override func selectAll(_ sender: Any?) {
		setSelection(emulator.grid.fullSelection)
	}

	@objc func clearSelection() {
		setSelection(nil)
	}

	@objc func paste(_ sender: Any?) {
		guard let text = NSPasteboard.general.string(forType: .string) else { return }
		isPinnedToBottom = true
		scrollToBottom()

		// Through tmux, tmux does the pasting.
		//
		// Bracketed paste is a promise to the program reading the keyboard, and
		// through tmux there are two of them: tmux, which asks for the markers
		// so it can receive a paste, and whatever is in the pane, which asks
		// separately and changes its mind constantly — a shell turns them off
		// while a command runs and on while it is editing a line. What this
		// terminal sees is tmux's answer, so writing the markers ourselves is
		// answering the wrong program, and losing that race puts `^[[200~` in
		// the command line.
		if let tty = pty.ttyName {
			Task { @MainActor [weak self] in
				let took = await TmuxMirror.pasteRetrying(text, forClient: tty)
				self?.putOnWire(text, throughTmux: true, tmuxTook: took)
			}
			return
		}
		putOnWire(text, throughTmux: false, tmuxTook: false)
	}

	/// Puts a paste on the wire by the rule `TmuxPaste.plan` decides.
	///
	/// **Never a bracketed-paste marker the inner program did not ask for.**
	/// Through tmux the terminal's own mode is the outer client's and not the
	/// program's, so a tmux paste that failed is written raw — the plan carries
	/// the whole of why. A bare pane keeps its markers, where the emulator's
	/// mode is the real one.
	private func putOnWire(_ text: String, throughTmux: Bool, tmuxTook: Bool) {
		switch TmuxPaste.plan(
			text: text,
			throughTmux: throughTmux,
			tmuxAccepted: tmuxTook,
			bracketedPaste: emulator.bracketedPaste
		) {
		case .tmuxTook: break
		case let .write(bytes): pty.write(bytes)
		}
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
		emulator.grid.recentLines(count)
	}

	/// Writes text as though typed. Used to drive a session programmatically —
	/// the same entry point an agent prompt will take.
	func send(_ text: String) {
		isPinnedToBottom = true
		pty.write(text)
		scrollToBottom()
	}

	// MARK: - Composition



	/// A key the input manager refused rather than composed.
	///
	/// Return pressed while an accent is pending: the layout commits the accent
	/// and passes the Return on as an editing command. Nothing here edits text,
	/// but the program is still owed that keystroke.
	override func doCommand(by selector: Selector) {
		guard let event = composingEvent, let bytes = encode(event: event) else { return }
		send(typed: bytes)
	}

	/// Shows or hides the composed text at the cursor.
	///
	/// A label on top rather than characters written into the screen: the grid
	/// belongs to the program, and a pending accent is not something the program
	/// has been sent. It also keeps working when the Metal renderer is drawing,
	/// which paints from the grid and knows nothing about this.
	private func setComposition(_ text: String) {
		guard markedText != text else { return }
		markedText = text

		guard !text.isEmpty, let place = cursorPlace(), place.row < shownLineCount else {
			compositionLabel.isHidden = true
			return
		}

		compositionLabel.attributedStringValue = NSAttributedString(
			string: text,
			attributes: [
				.font: font,
				.foregroundColor: TerminalPalette.foreground,
				.backgroundColor: TerminalPalette.background,
				// Underlined, which is how every input method says "not typed yet".
				.underlineStyle: NSUnderlineStyle.single.rawValue,
				.underlineColor: TerminalPalette.cursor,
			]
		)
		compositionLabel.sizeToFit()
		compositionLabel.frame.origin = CGPoint(
			x: (Self.horizontalInset + CGFloat(place.column) * cellWidth).rounded(),
			y: (Self.verticalInset + CGFloat(place.row) * cellHeight).rounded()
		)
		compositionLabel.frame.size.height = cellHeight
		if compositionLabel.superview !== self {
			addSubview(compositionLabel, positioned: .above, relativeTo: nil)
		}
		compositionLabel.isHidden = false
	}

	// MARK: - NSTextInputClient

	// Minimal conformance so IME candidates commit into the terminal.

	func insertText(_ string: Any, replacementRange: NSRange) {
		let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
		setComposition("")
		guard !text.isEmpty else { return }
		send(typed: text)
	}

	/// The half-finished text the layout is holding.
	///
	/// A dead key composes in two presses: the first shows the accent, the
	/// second decides whether it becomes `â` or stays `^` in front of whatever
	/// followed. The first press has to be visible or the keyboard looks broken,
	/// and the terminal itself must not see it — nothing has been typed yet.
	func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
		setComposition((string as? String) ?? (string as? NSAttributedString)?.string ?? "")
	}

	func unmarkText() { setComposition("") }
	func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }

	func markedRange() -> NSRange {
		markedText.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: markedText.utf16.count)
	}

	func hasMarkedText() -> Bool { !markedText.isEmpty }
	func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
	func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
	func characterIndex(for point: NSPoint) -> Int { 0 }

	func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
		guard let window else { return .zero }
		let row = emulator.metrics.scrollbackCount + emulator.cursorRow
		let rect = NSRect(
			x: Self.horizontalInset + CGFloat(emulator.cursorColumn) * cellWidth,
			y: Self.verticalInset + CGFloat(row) * cellHeight,
			width: cellWidth,
			height: cellHeight
		)
		return window.convertToScreen(convert(rect, to: nil))
	}
}
