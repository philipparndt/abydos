import Testing
import Foundation
@testable import AbydosKit

/// The emulator is UI-free, so escape-sequence handling is checked by feeding
/// bytes in and reading the grid back out.
struct TerminalEmulatorTests {
	private func makeEmulator(rows: Int = 6, columns: Int = 20) -> TerminalEmulator {
		TerminalEmulator(rows: rows, columns: columns)
	}

	/// Visible text of a row, trailing blanks trimmed.
	private func row(_ emulator: TerminalEmulator, _ index: Int) -> String {
		emulator.screen[index].text
	}

	// MARK: - Plain text

	@Test func writesPlainText() {
		let emulator = makeEmulator()
		emulator.write("hello")
		#expect(row(emulator, 0) == "hello")
		#expect(emulator.cursorColumn == 5)
	}

	@Test func carriageReturnAndLineFeed() {
		let emulator = makeEmulator()
		emulator.write("one\r\ntwo")
		#expect(row(emulator, 0) == "one")
		#expect(row(emulator, 1) == "two")
	}

	/// Writing exactly `columns` characters must not wrap early — the wrap is
	/// deferred until the next character actually arrives.
	@Test func deferredWrapAtRightMargin() {
		let emulator = makeEmulator(rows: 4, columns: 5)
		emulator.write("abcde")
		#expect(row(emulator, 0) == "abcde")
		#expect(row(emulator, 1) == "", "wrapped a line too early")

		emulator.write("f")
		#expect(row(emulator, 1) == "f")
	}

	@Test func scrollsWhenPastTheBottom() {
		let emulator = makeEmulator(rows: 3, columns: 10)
		emulator.write("a\r\nb\r\nc\r\nd")
		// 'a' scrolled off into scrollback.
		#expect(row(emulator, 0) == "b")
		#expect(row(emulator, 2) == "d")
		#expect(emulator.screen.scrollback.last?.text == "a")
	}

	@Test func tabAdvancesToNextStop() {
		let emulator = makeEmulator(rows: 2, columns: 40)
		emulator.write("ab\tc")
		#expect(emulator.cursorColumn == 9)
		#expect(row(emulator, 0).hasPrefix("ab"))
	}

	// MARK: - Cursor movement

	@Test func absolutePositioning() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[3;5Hx")
		// CUP is 1-based.
		#expect(emulator.cursorRow == 2)
		#expect(row(emulator, 2) == "    x")
	}

	@Test func relativeMovement() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[2B\u{1B}[3C" + "z")
		#expect(emulator.cursorRow == 2)
		#expect(row(emulator, 2) == "   z")
	}

	@Test func movementClampsToScreen() {
		let emulator = makeEmulator(rows: 4, columns: 10)
		emulator.write("\u{1B}[99;99H")
		#expect(emulator.cursorRow == 3)
		#expect(emulator.cursorColumn == 9)
	}

	@Test func saveAndRestoreCursor() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[2;3H\u{1B}[s\u{1B}[5;5H\u{1B}[u" + "x")
		#expect(emulator.cursorRow == 1)
		#expect(row(emulator, 1) == "  x")
	}

	// MARK: - Erase

	@Test func eraseToEndOfLine() {
		let emulator = makeEmulator()
		emulator.write("abcdef")
		emulator.write("\u{1B}[3G")     // column 3
		emulator.write("\u{1B}[K")      // erase to end
		#expect(row(emulator, 0) == "ab")
	}

	@Test func eraseWholeDisplay() {
		let emulator = makeEmulator()
		emulator.write("one\r\ntwo\r\nthree")
		emulator.write("\u{1B}[2J")
		#expect(row(emulator, 0) == "")
		#expect(row(emulator, 1) == "")
		#expect(row(emulator, 2) == "")
	}

	@Test func deleteAndInsertCharacters() {
		let emulator = makeEmulator()
		emulator.write("abcdef")
		emulator.write("\u{1B}[2G")     // column 2
		emulator.write("\u{1B}[2P")     // delete two
		#expect(row(emulator, 0) == "adef")

		emulator.write("\u{1B}[2G\u{1B}[1@")
		#expect(row(emulator, 0) == "a def")
	}

	// MARK: - Colour

	@Test func basicForegroundColour() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[31mR\u{1B}[0mN")
		#expect(emulator.screen[0].cells[0].attributes.foreground == .indexed(1))
		#expect(emulator.screen[0].cells[1].attributes.foreground == .default)
	}

	@Test func brightAndBoldAttributes() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[1;92mX")
		#expect(emulator.screen[0].cells[0].attributes.bold)
		#expect(emulator.screen[0].cells[0].attributes.foreground == .indexed(10))
	}

	@Test func extended256Colour() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[38;5;200mX")
		#expect(emulator.screen[0].cells[0].attributes.foreground == .indexed(200))
	}

	@Test func trueColour() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[38;2;10;20;30mX\u{1B}[48;2;1;2;3mY")
		#expect(emulator.screen[0].cells[0].attributes.foreground == .rgb(10, 20, 30))
		#expect(emulator.screen[0].cells[1].attributes.background == .rgb(1, 2, 3))
	}

	@Test func resetClearsAllAttributes() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[1;4;7;31m\u{1B}[0mX")
		let attributes = emulator.screen[0].cells[0].attributes
		#expect(!attributes.bold && !attributes.underline && !attributes.inverse)
		#expect(attributes.foreground == .default)
	}

	/// Colon subparameters must not be mistaken for SGR 0.
	@Test func colonSubparametersDoNotResetEverything() {
		let emulator = makeEmulator()
		// Red, then a curly underline written in the colon form.
		emulator.write("\u{1B}[31m\u{1B}[4:3mX")
		let attributes = emulator.screen[0].cells[0].attributes
		#expect(attributes.foreground == .indexed(1), "colour was wiped by a colon subparameter")
		#expect(attributes.underline)
	}

	@Test func underlineColourIsIgnoredWithoutResetting() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[1;31m\u{1B}[58:2::10:20:30mX")
		let attributes = emulator.screen[0].cells[0].attributes
		#expect(attributes.bold)
		#expect(attributes.foreground == .indexed(1))
	}

	// MARK: - UTF-8 and width

	@Test func decodesMultiByteCharacters() {
		let emulator = makeEmulator()
		emulator.write("héllo →")
		#expect(row(emulator, 0) == "héllo →")
	}

	/// A read can split a UTF-8 sequence; the emulator must carry the partial
	/// bytes across writes rather than emitting replacement characters.
	@Test func handlesUTF8SplitAcrossWrites() {
		let emulator = makeEmulator()
		let bytes = Array("é".utf8)
		emulator.write([bytes[0]])
		emulator.write([bytes[1]])
		#expect(row(emulator, 0) == "é")
	}

	/// Powerline separators live in the Private Use Area. They were being given
	/// zero width and merged into the previous cell, which erased them from every
	/// starship and powerlevel10k prompt.
	@Test func powerlineGlyphsOccupyAColumn() {
		#expect(TerminalEmulator.displayWidth(of: "\u{E0B0}") == 1)
		#expect(TerminalEmulator.displayWidth(of: "\u{E0B2}") == 1)
		#expect(TerminalEmulator.displayWidth(of: "\u{E0A0}") == 1)

		let emulator = makeEmulator(rows: 3, columns: 20)
		emulator.write("a\u{E0B0}b")
		#expect(row(emulator, 0) == "a\u{E0B0}b")
		#expect(emulator.cursorColumn == 3, "the separator must advance the cursor")
	}

	/// Malformed UTF-8 is shown, not guessed at or allowed to stall the stream.
	@Test func malformedUTF8BecomesAReplacement() {
		// An overlong encoding of "A", which must not decode as one.
		var emulator = TerminalEmulator(rows: 2, columns: 10)
		emulator.write([0xC1, 0x81, 0x42])
		#expect(row(emulator, 0).hasPrefix("\u{FFFD}"))
		#expect(row(emulator, 0).contains("B"))

		// An overlong three-byte encoding of "/".
		emulator = TerminalEmulator(rows: 2, columns: 10)
		emulator.write([0xE0, 0x80, 0xAF])
		#expect(row(emulator, 0) == "\u{FFFD}")

		// A surrogate half, which is not a scalar at all.
		emulator = TerminalEmulator(rows: 2, columns: 10)
		emulator.write([0xED, 0xA0, 0x80])
		#expect(row(emulator, 0) == "\u{FFFD}")

		// A stray continuation byte with nothing to continue.
		emulator = TerminalEmulator(rows: 2, columns: 10)
		emulator.write([0x80, 0x43])
		#expect(row(emulator, 0) == "\u{FFFD}C")
	}

	/// A sequence cut short must not swallow what comes after it.
	@Test func aTruncatedSequenceDoesNotEatTheNextCharacter() {
		let emulator = TerminalEmulator(rows: 2, columns: 10)
		// The lead byte of "é" followed by an ordinary letter.
		emulator.write([0xC3, 0x44])
		#expect(row(emulator, 0) == "\u{FFFD}D")
	}

	/// Four-byte sequences reach the planes where emoji live.
	@Test func fourByteSequencesDecode() {
		let emulator = TerminalEmulator(rows: 2, columns: 10)
		emulator.write("\u{1F600}")
		#expect(row(emulator, 0).hasPrefix("\u{1F600}"))
	}

	/// Split anywhere, not merely between characters.
	@Test func handlesAFourByteCharacterSplitAcrossWrites() {
		let emulator = TerminalEmulator(rows: 2, columns: 10)
		let bytes = Array("\u{1F600}".utf8)
		emulator.write(Array(bytes[0..<1]))
		emulator.write(Array(bytes[1..<3]))
		emulator.write(Array(bytes[3...]))
		#expect(row(emulator, 0).hasPrefix("\u{1F600}"))
	}

	@Test func combiningMarksStillTakeNoColumn() {
		// U+0301 combining acute — genuinely zero-width.
		#expect(TerminalEmulator.displayWidth(of: "\u{0301}") == 0)
		let emulator = makeEmulator()
		emulator.write("e\u{0301}")
		#expect(emulator.cursorColumn == 1)
	}

	@Test func wideCharactersOccupyTwoColumns() {
		let emulator = makeEmulator(rows: 3, columns: 10)
		emulator.write("日本")
		#expect(emulator.screen[0].cells[1].isWideTrailer)
		#expect(emulator.screen[0].cells[3].isWideTrailer)
		#expect(emulator.cursorColumn == 4)
	}

	// MARK: - Scroll region

	@Test func scrollRegionConfinesScrolling() {
		let emulator = makeEmulator(rows: 5, columns: 10)
		emulator.write("\u{1B}[2;4r")          // region = rows 2..4
		emulator.write("\u{1B}[2;1H")          // top of region
		emulator.write("a\r\nb\r\nc\r\nd")     // one line more than fits

		// Row 0 is outside the region and must be untouched.
		#expect(row(emulator, 0) == "")
		#expect(row(emulator, 3) == "d")
	}

	// MARK: - Alternate screen

	@Test func alternateScreenIsSeparateAndRestores() {
		let emulator = makeEmulator(rows: 4, columns: 10)
		emulator.write("main text")

		emulator.write("\u{1B}[?1049h")
		#expect(emulator.isAlternateScreen)
		#expect(row(emulator, 0) == "", "alternate screen should start blank")

		emulator.write("full screen")
		emulator.write("\u{1B}[?1049l")

		#expect(!emulator.isAlternateScreen)
		#expect(row(emulator, 0) == "main text", "main screen was not restored")
	}

	@Test func alternateScreenDoesNotPolluteScrollback() {
		let emulator = makeEmulator(rows: 2, columns: 10)
		emulator.write("\u{1B}[?1049h")
		for index in 0..<10 { emulator.write("line\(index)\r\n") }
		emulator.write("\u{1B}[?1049l")
		#expect(emulator.screen.scrollback.isEmpty, "full-screen apps must not fill history")
	}

	// MARK: - Modes and replies

	@Test func cursorVisibilityToggles() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[?25l")
		#expect(!emulator.isCursorVisible)
		emulator.write("\u{1B}[?25h")
		#expect(emulator.isCursorVisible)
	}

	/// A shell blocks waiting for this reply, so it must be answered.
	@Test func answersDeviceStatusReport() {
		let emulator = makeEmulator()
		var responses: [String] = []
		emulator.onResponse = { responses.append($0) }

		emulator.write("\u{1B}[3;7H\u{1B}[6n")
		#expect(responses.contains("\u{1B}[3;7R"))
	}

	@Test func applicationCursorKeysChangeEncoding() {
		let emulator = makeEmulator()
		#expect(emulator.encodeArrow(.up) == "\u{1B}[A")
		emulator.write("\u{1B}[?1h")
		#expect(emulator.encodeArrow(.up) == "\u{1B}OA")
	}

	/// Primary and secondary DA are different questions. Answering the secondary
	/// one with a primary response is what left `^[[?6c` on screen under tmux:
	/// the reply was not what the program was parsing, so it fell through to the
	/// shell, which echoed it as input.
	@Test func primaryAndSecondaryDeviceAttributesDiffer() {
		let emulator = makeEmulator()
		var responses: [String] = []
		emulator.onResponse = { responses.append($0) }

		emulator.write("\u{1B}[c")
		emulator.write("\u{1B}[>c")

		#expect(responses.count == 2)
		#expect(responses[0].hasPrefix("\u{1B}[?"), "primary DA must reply with ?-prefixed attributes")
		#expect(responses[1].hasPrefix("\u{1B}[>"), "secondary DA must reply with >-prefixed attributes")
		#expect(responses[0] != responses[1])
	}

	@Test func answersTerminalStatusReport() {
		let emulator = makeEmulator()
		var responses: [String] = []
		emulator.onResponse = { responses.append($0) }
		emulator.write("\u{1B}[5n")
		#expect(responses.contains("\u{1B}[0n"))
	}

	// MARK: - Mouse

	@Test func mouseIsSilentUntilEnabled() {
		let emulator = makeEmulator()
		#expect(emulator.mouseTracking == .off)
		#expect(emulator.encodeMouse(button: .left, row: 1, column: 1, isRelease: false) == nil)
	}

	@Test func enablesSGRMouseReporting() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[?1002h\u{1B}[?1006h")
		#expect(emulator.mouseTracking == .buttonEvent)
		#expect(emulator.sgrMouseEncoding)

		let press = emulator.encodeMouse(button: .left, row: 3, column: 7, isRelease: false)
		#expect(press == "\u{1B}[<0;7;3M")

		let release = emulator.encodeMouse(button: .left, row: 3, column: 7, isRelease: true)
		#expect(release == "\u{1B}[<0;7;3m")
	}

	@Test func dragIsSuppressedInClickOnlyMode() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[?1000h\u{1B}[?1006h")
		#expect(emulator.encodeMouse(button: .left, row: 2, column: 2, isRelease: false, isDrag: true) == nil)
	}

	@Test func modifiersAreEncodedInMouseReports() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[?1000h\u{1B}[?1006h")
		// Control adds 16 to the button code.
		let sequence = emulator.encodeMouse(button: .left, row: 1, column: 1, isRelease: false, control: true)
		#expect(sequence == "\u{1B}[<16;1;1M")
	}

	@Test func mouseTrackingTurnsOff() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[?1003h")
		#expect(emulator.mouseTracking == .anyEvent)
		emulator.write("\u{1B}[?1003l")
		#expect(emulator.mouseTracking == .off)
	}

	@Test func readsWindowTitle() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}]0;my title\u{07}")
		#expect(emulator.title == "my title")
	}

	/// Unknown sequences must be swallowed whole rather than leaking their
	/// parameter bytes into the visible grid.
	@Test func ignoresUnknownSequencesCleanly() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[>4;2m" + "ok")
		#expect(row(emulator, 0) == "ok")
	}

	@Test func charsetDesignationIsSwallowed() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}(B" + "ok")
		#expect(row(emulator, 0) == "ok")
	}

	// MARK: - Resize

	@Test func resizeGrowingRecoversScrollback() {
		let emulator = makeEmulator(rows: 2, columns: 10)
		emulator.write("one\r\ntwo\r\nthree")
		#expect(emulator.screen.scrollback.count == 1)

		emulator.resize(rows: 4, columns: 10)
		// The retired line comes back rather than leaving a blank band.
		#expect(row(emulator, 0) == "one")
	}

	@Test func resizeShrinkingRetiresFromTop() {
		let emulator = makeEmulator(rows: 4, columns: 10)
		emulator.write("a\r\nb\r\nc\r\nd")
		emulator.resize(rows: 2, columns: 10)
		#expect(emulator.screen.rows == 2)
		#expect(row(emulator, 1) == "d", "the cursor's line must survive shrinking")
	}

	@Test func resizeNarrowingTruncatesColumns() {
		let emulator = makeEmulator(rows: 2, columns: 20)
		emulator.write("abcdefghij")
		emulator.resize(rows: 2, columns: 5)
		#expect(emulator.screen.columns == 5)
		#expect(row(emulator, 0) == "abcde")
	}

	// MARK: - Realistic output

	/// A prompt-like sequence combining colour, positioning and erasure — the
	/// shape of what a shell or agent CLI actually emits.
	@Test func handlesRealisticPromptSequence() {
		let emulator = makeEmulator(rows: 4, columns: 40)
		emulator.write("\u{1B}[1;32m➜\u{1B}[0m  \u{1B}[1;36mideai\u{1B}[0m git:(\u{1B}[31mmain\u{1B}[0m) ")
		let text = row(emulator, 0)
		#expect(text.contains("ideai"))
		#expect(text.contains("main"))
		#expect(!text.contains("["), "escape parameters leaked into the grid")
	}
}

/// The PTY runs real processes, so these are integration tests.
///
/// Serialized deliberately: `forkpty` forks a multithreaded process, and several
/// tests forking at once is a genuine hazard rather than a test-harness quirk.
@Suite(.serialized)
struct PseudoTerminalTests {
	/// Waits for a condition on the main queue, with a timeout.
	///
	/// The timeout is a hang detector rather than an assertion, and it comes
	/// from `Patience` so that it is one number rather than this suite's own.
	/// Twenty seconds was already meant to be generous — "a machine with every
	/// core busy can take seconds to get round to a `/bin/echo`" — and it was
	/// still missed: `runsACommandAndCapturesOutput` went red at 5.1 runnable
	/// threads per core while this item was being measured, waiting on
	/// `/bin/echo`. Nothing about that red was about the terminal.
	///
	/// **And nothing about it was about this number either**, which 0472 established
	/// by trying to widen it and measuring instead. There is no value of this that
	/// helps: when the red happens the output has been discarded rather than
	/// delayed, so the wait is a hang detector detecting a real hang. Left exactly
	/// as it is, and 0476 is the defect.
	private func wait(
		timeout: TimeInterval = Patience.seconds, until condition: @escaping () -> Bool
	) async -> Bool {
		let deadline = Date().addingTimeInterval(timeout)
		while Date() < deadline {
			if condition() { return true }
			try? await Task.sleep(nanoseconds: 20_000_000)
		}
		return condition()
	}

	/// Callbacks are delivered off the main queue, which a test process does not
	/// service.
	private func makePTY() -> PseudoTerminal {
		let pty = PseudoTerminal()
		pty.callbackQueue = DispatchQueue(label: "ideai.tests.pty.callbacks")
		return pty
	}

	@Test func runsACommandAndCapturesOutput() async {
		let pty = makePTY()
		let collected = Collector()

		pty.onOutput = { data in collected.append(data) }

		let started = pty.start(
			executable: "/bin/echo",
			arguments: ["hello-from-pty"],
			rows: 24,
			columns: 80
		)
		#expect(started)

		let sawOutput = await wait { collected.text.contains("hello-from-pty") }
		// **A red here is 0476 and it is not the machine being busy.** It was read
		// that way three times — 124 s, 126.6 s and 124 s, at 5.4 to 6.5 runnable
		// threads per core — and 0472 went looking for a timing assertion to widen
		// and found a defect: a child that writes and exits before anything has read
		// the master loses its output outright, so this wait is not waiting for
		// something slow, it is waiting for something that is gone. 0476 has the
		// reproduction, and what has already been ruled out.
		//
		// The load and the bytes are in the message so the next person reading a red
		// has both without re-running the suite. `""` rather than a partial line is
		// the tell: that is loss, not slowness.
		#expect(sawOutput, """
			no output after \(Patience.seconds)s, got: \
			\(collected.text.debugDescription) — this is 0476 rather than a slow \
			machine if it is empty — \(pty.diagnostics) — \(MachineLoad.said)
			""")
		pty.terminate()
	}

	/// A command that has already finished still shows what it printed.
	///
	/// **This is what `runsACommandAndCapturesOutput` going red was.** 0472 filed
	/// it as a timeout of the same shape as Mermaid's budget — 124 s at load 54,
	/// 126.6 s and 124 s at load 65, against a `/bin/echo` costing 0.028–0.35 s on
	/// its own — and it was not that. Nothing was slow. A macOS pty gives output
	/// the child has written 600 ms to be read and then discards it, so a reading
	/// queue that does not get a thread inside 600 ms comes back to an empty
	/// terminal. The output was not late; it was thrown away, and the wait then ran
	/// its whole deadline for something that was never going to arrive. 0476 has the
	/// measurement, and `PseudoTerminal` holds a descriptor on the child's end of
	/// the terminal now, which is what takes the deadline away.
	///
	/// So the 120 seconds was never the fault, and raising or lowering it would have
	/// fixed nothing: a hang detector is allowed to be generous, and this one was
	/// detecting a real hang. What it could not do was say which.
	///
	/// Written against the exit rather than against a clock, and that is the part
	/// worth keeping. 0472's version gave each attempt five seconds to produce its
	/// line, which is a second race on a busy machine: twenty `/bin/echo`s at five
	/// seconds each cannot tell whether output was lost or the machine was slow,
	/// and that confusion is what the whole item came out of. What the fix promises
	/// is an *order* — the exit is not announced until everything the program
	/// printed has been handed over — so this waits for the exit, with the suite's
	/// ordinary hang detector, and asks what had arrived by the time it came. A red
	/// here cannot be a slow machine.
	///
	/// Twenty of them, because the losing side of a race needs a busy machine, and
	/// one lost is already the failure — reported with the attempt and the load so
	/// a red here is read rather than re-run.
	@Test func aCommandThatIsAlreadyOverDoesNotLoseItsOutput() async {
		for attempt in 0..<20 {
			let pty = makePTY()
			let collected = Collector()
			let outputWhenItExited = Box<String?>(nil)
			let codeWhenItExited = Box<Int32?>(nil)
			pty.onOutput = { collected.append($0) }
			// Read from inside the exit callback rather than after it. The claim
			// is that output is delivered before the exit is announced, so what
			// has been collected at this moment is the whole of the answer — and
			// the callback queue is serial, so this runs after every delivery.
			pty.onExit = { code in
				outputWhenItExited.value = collected.text
				codeWhenItExited.value = code
			}

			let word = "gone-\(attempt)"
			#expect(pty.start(executable: "/bin/echo", arguments: [word]))

			let exited = await wait { outputWhenItExited.value != nil }
			// Asked before `terminate()`, which closes the terminal and would take
			// the answer with it.
			let diagnostics = pty.diagnostics
			pty.terminate()

			guard exited else {
				Issue.record("""
					attempt \(attempt + 1) of 20: a /bin/echo never reported its exit \
					within \(Patience.seconds)s — \(diagnostics) — \(MachineLoad.said)
					""")
				return
			}
			guard outputWhenItExited.value?.contains(word) == true else {
				// The exit status is in the message because "no output" has two
				// causes and they want different fixes: 0 means `/bin/echo` printed
				// its line and this lost it, and 127 means the exec never happened,
				// so there was nothing to lose and the machine is the story after
				// all. Guessing which cost this item most of a day.
				Issue.record("""
					attempt \(attempt + 1) of 20 lost the output of a /bin/echo that \
					had already finished: by the time it said it had exited — \
					status \(codeWhenItExited.value.map(String.init) ?? "none") — it \
					had delivered \((outputWhenItExited.value ?? "").debugDescription) \
					— \(diagnostics) — \(MachineLoad.said)
					""")
				return
			}
		}
	}

	/// Output survives a reader that does not read for two seconds.
	///
	/// The same defect as `aCommandThatIsAlreadyOverDoesNotLoseItsOutput`, arranged
	/// rather than waited for. That one needs a machine loaded enough that the
	/// reading queue waits longer than the pty's 600 ms grace period for a thread,
	/// which is a thing you can provoke and not a thing you can ask for; this one
	/// suspends the reader outright, which is the same condition and arrives every
	/// time. It is the test to run while working on this, and the reason the other
	/// one is not the only evidence.
	///
	/// Two seconds because the deadline is 600 ms and the point is to be well past
	/// it. A pty that is going to throw output away has done it by then.
	@Test func outputSurvivesAReaderThatIsNotReading() async {
		let pty = makePTY()
		let collected = Collector()
		pty.onOutput = { collected.append($0) }

		#expect(pty.start(executable: "/bin/echo", arguments: ["survived"]))
		pty.setReadingSuspended(true)
		try? await Task.sleep(nanoseconds: 2_000_000_000)
		pty.setReadingSuspended(false)

		let arrived = await wait { collected.text.contains("survived") }
		#expect(arrived, """
			a /bin/echo's output did not survive two seconds of nobody reading: \
			got \(collected.text.debugDescription) — \(pty.diagnostics)
			""")
		pty.terminate()
	}

	/// Twenty terminals come and go without leaving a descriptor or a child.
	///
	/// Here because the fix for 0476 makes both newly possible to get wrong. It
	/// holds a second descriptor — the child's end of the terminal — so there are
	/// two to close rather than one. And holding it is exactly what lets the
	/// child's exit wait indefinitely for somebody to read, so a terminal that
	/// stopped reading without also closing would leave a process alive for ever.
	/// A pty that leaks either of those is worse than the bug it was fixing.
	@Test func leavesNoDescriptorAndNoChildBehind() async {
		let before = Self.openDescriptorCount()
		var children: [pid_t] = []

		for _ in 0..<20 {
			let pty = makePTY()
			let exited = Box<Bool>(false)
			pty.onExit = { _ in exited.value = true }
			#expect(pty.start(executable: "/bin/echo", arguments: ["tidy"]))
			// `childProcessID` and not `state`, which stops naming the process the
			// moment it exits — and a `/bin/echo` can be gone before the next line
			// of this test runs, which is how this first went red.
			children.append(pty.childProcessID)
			#expect(await wait { exited.value })
			pty.terminate()
		}

		#expect(children.count == 20, "every attempt should have reported a pid")

		// Nothing left unreaped. Asked about each pid this test started rather
		// than with `waitpid(-1)`, which would take a child belonging to another
		// suite running beside this one and break whoever was waiting for it.
		// ECHILD is the answer that means somebody has already reaped it.
		for pid in children {
			var status: Int32 = 0
			let found = waitpid(pid, &status, WNOHANG)
			#expect(
				found == -1 && errno == ECHILD,
				"pid \(pid) is still a child of this process"
			)
		}

		// The descriptors close on the reading queue, once the read source has
		// finished with them, so they are not all gone the instant `terminate()`
		// returns — a moment to settle, rather than an assertion about how fast.
		let settled = await wait { Self.openDescriptorCount() <= before + 2 }
		#expect(settled, """
			descriptors went from \(before) to \(Self.openDescriptorCount()) over \
			twenty terminals — two leaked per terminal would be forty
			""")
	}

	/// How many descriptors this process has open.
	///
	/// The number itself means nothing; that twenty terminals do not move it is
	/// the whole assertion.
	private static func openDescriptorCount() -> Int {
		var count = 0
		for descriptor in 0..<Int32(getdtablesize()) where fcntl(descriptor, F_GETFD) >= 0 {
			count += 1
		}
		return count
	}

	@Test func reportsExitCode() async {
		let pty = makePTY()
		let exitCode = Box<Int32?>(nil)
		pty.onExit = { code in exitCode.value = code }

		#expect(pty.start(executable: "/bin/sh", arguments: ["-c", "exit 3"]))

		let exited = await wait { exitCode.value != nil }
		#expect(exited)
		#expect(exitCode.value == 3)
	}

	/// The whole reason for using a PTY: programs must believe they have a tty.
	@Test func childSeesATerminal() async {
		let pty = makePTY()
		let collected = Collector()
		pty.onOutput = { collected.append($0) }

		#expect(pty.start(
			executable: "/bin/sh",
			arguments: ["-c", "test -t 1 && echo IS_TTY || echo NOT_TTY"]
		))

		let sawOutput = await wait { collected.text.contains("TTY") }
		#expect(sawOutput)
		#expect(collected.text.contains("IS_TTY"), "child did not get a terminal")
		pty.terminate()
	}

	@Test func windowSizeIsReportedToTheChild() async {
		let pty = makePTY()
		let collected = Collector()
		pty.onOutput = { collected.append($0) }

		#expect(pty.start(
			executable: "/bin/sh",
			arguments: ["-c", "stty size"],
			rows: 30,
			columns: 100
		))

		let sawOutput = await wait { collected.text.contains("30") }
		#expect(sawOutput, "expected size, got: \(collected.text)")
		#expect(collected.text.contains("30 100"))
		pty.terminate()
	}

	@Test func writesReachTheChild() async {
		let pty = makePTY()
		let collected = Collector()
		pty.onOutput = { collected.append($0) }

		#expect(pty.start(executable: "/bin/cat"))
		try? await Task.sleep(nanoseconds: 200_000_000)
		pty.write("round-trip\n")

		let echoed = await wait { collected.text.contains("round-trip") }
		#expect(echoed, "got: \(collected.text)")
		pty.terminate()
	}
}

/// Reference-typed helpers so callbacks can accumulate without capture issues.
private final class Collector {
	private var data = Data()
	private let lock = NSLock()

	func append(_ chunk: Data) {
		lock.lock(); defer { lock.unlock() }
		data.append(chunk)
	}

	var text: String {
		lock.lock(); defer { lock.unlock() }
		return String(decoding: data, as: UTF8.self)
	}
}

private final class Box<T> {
	var value: T
    init(_ value: T) { self.value = value }
}

/// Resizing is where a terminal most visibly gets things wrong: rows have to be
/// taken from whichever end holds nothing, and the cursor has to follow the
/// content it was sitting on. A shell redraws its prompt at the cursor after
/// SIGWINCH, so a cursor left on the wrong line duplicates output.
struct TerminalResizeTests {
	private func makeEmulator(rows: Int = 10, columns: Int = 20) -> TerminalEmulator {
		TerminalEmulator(rows: rows, columns: columns)
	}

	private func row(_ emulator: TerminalEmulator, _ index: Int) -> String {
		emulator.screen[index].text
	}

	/// The case the user hit: a short session, shrunk, lost its history.
	@Test func shrinkingTakesUnusedRowsFromTheBottom() {
		let emulator = makeEmulator(rows: 10)
		emulator.write("one\r\ntwo\r\nthree\r\n$ ")
		// Cursor sits on row 3; rows 4-9 were never written to.
		#expect(emulator.cursorRow == 3)

		emulator.resize(rows: 6, columns: 20)

		#expect(row(emulator, 0) == "one")
		#expect(row(emulator, 1) == "two")
		#expect(row(emulator, 2) == "three")
		#expect(emulator.screen.scrollback.count == 0)
		// The prompt stays under the cursor, so the redraw overwrites itself.
		#expect(emulator.cursorRow == 3)
	}

	/// Once the blank tail runs out, content does have to go — but the cursor
	/// moves with it rather than being clamped.
	@Test func shrinkingPastTheBlankTailRetiresFromTheTop() {
		let emulator = makeEmulator(rows: 6)
		emulator.write("a\r\nb\r\nc\r\nd\r\ne\r\nf")
		#expect(emulator.cursorRow == 5)

		emulator.resize(rows: 4, columns: 20)

		#expect(row(emulator, 0) == "c")
		#expect(row(emulator, 3) == "f")
		#expect(emulator.screen.scrollback.count == 2)
		#expect(emulator.cursorRow == 3)
	}

	/// Growing pulls history back down, which pushes the cursor down with it.
	/// Without the shift the shell would redraw its prompt over recovered text.
	@Test func growingRecoversScrollbackAndMovesTheCursorWithIt() {
		let emulator = makeEmulator(rows: 3)
		emulator.write("a\r\nb\r\nc\r\nd\r\ne")
		// Two lines have scrolled off by now.
		#expect(emulator.screen.scrollback.count == 2)
		#expect(emulator.cursorRow == 2)

		emulator.resize(rows: 5, columns: 20)

		#expect(row(emulator, 0) == "a")
		#expect(row(emulator, 4) == "e")
		#expect(emulator.screen.scrollback.count == 0)
		#expect(emulator.cursorRow == 4)
	}

	/// With no history to recover, new rows are appended and nothing moves.
	@Test func growingWithoutScrollbackLeavesTheCursorAlone() {
		let emulator = makeEmulator(rows: 4)
		emulator.write("a\r\nb")
		emulator.resize(rows: 8, columns: 20)

		#expect(row(emulator, 0) == "a")
		#expect(emulator.cursorRow == 1)
	}

	/// A resize inside tmux must also reshape the grid tmux will be handed back,
	/// or leaving it restores a screen of the wrong size.
	@Test func resizeAlsoReshapesTheSavedNormalScreen() {
		let emulator = makeEmulator(rows: 6, columns: 20)
		emulator.write("history\r\n$ ")
		emulator.write("\u{1B}[?1049h")            // enter alternate screen
		#expect(emulator.isAlternateScreen)

		emulator.resize(rows: 9, columns: 30)
		#expect(emulator.screen.rows == 9)

		emulator.write("\u{1B}[?1049l")            // leave it again
		#expect(!emulator.isAlternateScreen)
		#expect(emulator.screen.rows == 9)
		#expect(emulator.screen.columns == 30)
		#expect(row(emulator, 0) == "history")
	}

	@Test func narrowingTruncatesRowsRatherThanLosingThem() {
		let emulator = makeEmulator(rows: 4, columns: 20)
		emulator.write("abcdefghij")
		emulator.resize(rows: 4, columns: 5)
		#expect(row(emulator, 0) == "abcde")
		#expect(emulator.cursorColumn == 4)
	}

	@Test func resizeToTheSameSizeChangesNothing() {
		let emulator = makeEmulator(rows: 5, columns: 20)
		emulator.write("a\r\nb")
		emulator.resize(rows: 5, columns: 20)
		#expect(emulator.cursorRow == 1)
		#expect(row(emulator, 0) == "a")
	}
}

/// Selection is expressed over the whole buffer, scrollback included, so it is
/// checked the same way: write output, scroll some of it off, select across it.
struct TerminalSelectionTests {
	private func makeEmulator(rows: Int = 4, columns: Int = 20) -> TerminalEmulator {
		TerminalEmulator(rows: rows, columns: columns)
	}

	@Test func selectsWithinOneRow() {
		let emulator = makeEmulator()
		emulator.write("hello world")
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 6),
			head: TerminalPosition(row: 0, column: 11)
		)
		#expect(emulator.screen.text(in: selection) == "world")
	}

	@Test func selectsBackwardsAsThoughForwards() {
		let emulator = makeEmulator()
		emulator.write("hello world")
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 11),
			head: TerminalPosition(row: 0, column: 6)
		)
		#expect(emulator.screen.text(in: selection) == "world")
	}

	/// Middle rows run to the right edge, and trailing blanks are dropped so a
	/// copied block does not carry a tail of spaces into the paste.
	@Test func selectsAcrossRowsWithoutTrailingBlanks() {
		let emulator = makeEmulator()
		emulator.write("one\r\ntwo\r\nthree")
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 0),
			head: TerminalPosition(row: 2, column: 5)
		)
		#expect(emulator.screen.text(in: selection) == "one\ntwo\nthree")
	}

	@Test func selectionReachesIntoScrollback() {
		let emulator = makeEmulator(rows: 2)
		emulator.write("a\r\nb\r\nc\r\nd")
		#expect(emulator.screen.scrollback.count == 2)

		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 0),
			head: TerminalPosition(row: 3, column: 1)
		)
		#expect(emulator.screen.text(in: selection) == "a\nb\nc\nd")
	}

	@Test func emptySelectionCopiesNothing() {
		let emulator = makeEmulator()
		emulator.write("hello")
		let point = TerminalPosition(row: 0, column: 2)
		#expect(emulator.screen.text(in: TerminalSelection(anchor: point, head: point)).isEmpty)
	}

	/// A double-click in a terminal is nearly always aimed at a path, so the
	/// word has to survive dots and slashes.
	@Test func doubleClickSelectsAWholePath() {
		let emulator = makeEmulator(columns: 40)
		emulator.write("file ./Package.resolved here")
		let selection = emulator.screen.wordSelection(atRow: 0, column: 8)
		#expect(selection.map { emulator.screen.text(in: $0) } == "./Package.resolved")
	}

	@Test func doubleClickOnBlankSelectsNothing() {
		let emulator = makeEmulator()
		emulator.write("ab cd")
		#expect(emulator.screen.wordSelection(atRow: 0, column: 2) == nil)
	}

	@Test func tripleClickTakesTheWholeRow() {
		let emulator = makeEmulator()
		emulator.write("one two\r\nthree")
		let selection = emulator.screen.lineSelection(atRow: 0)
		#expect(selection.map { emulator.screen.text(in: $0) } == "one two")
	}

	@Test func selectAllSpansScrollbackAndScreen() {
		let emulator = makeEmulator(rows: 2)
		emulator.write("a\r\nb\r\nc")
		let selection = emulator.screen.fullSelection
		#expect(selection.map { emulator.screen.text(in: $0) } == "a\nb\nc")
	}

	/// The highlight has to stop where the selection does on the last row, but
	/// run to the edge on the rows above it.
	@Test func highlightRunsToTheEdgeOnMiddleRows() {
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 1, column: 3),
			head: TerminalPosition(row: 3, column: 4)
		)
		#expect(selection.columnRange(onRow: 0, columns: 20) == nil)
		#expect(selection.columnRange(onRow: 1, columns: 20) == 3..<20)
		#expect(selection.columnRange(onRow: 2, columns: 20) == 0..<20)
		#expect(selection.columnRange(onRow: 3, columns: 20) == 0..<4)
		#expect(selection.columnRange(onRow: 4, columns: 20) == nil)
	}
}

/// Detection has to cope with extensions that are real but unknown, which is
/// most of what a build system leaves lying around.
struct LanguageDetectionTests {
	private func write(_ contents: String, to name: String) throws -> URL {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-detect-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let url = directory.appendingPathComponent(name)
		try contents.write(to: url, atomically: true, encoding: .utf8)
		return url
	}

	/// The case that prompted this: Package.resolved is JSON.
	@Test func recognisesJSONBehindAnUnknownExtension() throws {
		let url = try write("{\n  \"pins\" : [\n  ]\n}\n", to: "Package.resolved")
		#expect(LanguageRegistry.shared.languageId(for: url) == "json")
	}

	@Test func recognisesAJSONArray() throws {
		let url = try write("[\n  1, 2\n]\n", to: "data.unknownext")
		#expect(LanguageRegistry.shared.languageId(for: url) == "json")
	}

	/// A brace also opens a C block, so a bare one is not enough evidence.
	@Test func doesNotClaimEveryBraceIsJSON() throws {
		let url = try write("{\n  int x = 1;\n}\n", to: "snippet.unknownext")
		#expect(LanguageRegistry.shared.languageId(for: url) == nil)
	}

	@Test func recognisesXMLAndHTML() throws {
		#expect(try LanguageRegistry.shared.languageId(
			for: write("<?xml version=\"1.0\"?><root/>", to: "a.unknownext")
		) == "html")
		#expect(try LanguageRegistry.shared.languageId(
			for: write("<!DOCTYPE html>\n<html></html>", to: "b.unknownext")
		) == "html")
	}

	@Test func recognisesAYAMLDocumentMarker() throws {
		let url = try write("---\nkey: value\n", to: "config.unknownext")
		#expect(LanguageRegistry.shared.languageId(for: url) == "yaml")
	}

	@Test func shebangStillWinsForExtensionlessScripts() throws {
		let url = try write("#!/usr/bin/env python3\nprint(1)\n", to: "runme")
		#expect(LanguageRegistry.shared.languageId(for: url) == "python")
	}

	/// A known extension is trusted over the contents; a .md file that opens
	/// with front matter is still Markdown.
	@Test func extensionBeatsContent() throws {
		let url = try write("---\ntitle: post\n---\n# Hello\n", to: "post.md")
		#expect(LanguageRegistry.shared.languageId(for: url) == "markdown")
	}

	@Test func plainProseIsLeftAlone() throws {
		let url = try write("just some notes\n", to: "notes.unknownext")
		#expect(LanguageRegistry.shared.languageId(for: url) == nil)
	}

	/// The status bar's picker needs a stable, named list to offer.
	@Test func selectableLanguagesAreNamedAndSorted() {
		let languages = LanguageRegistry.shared.selectableLanguages
		#expect(languages.count > 10)
		#expect(languages.contains { $0.id == "json" })
		#expect(languages.map(\.name) == languages.map(\.name).sorted {
			$0.localizedCaseInsensitiveCompare($1) == .orderedAscending
		})
	}
}

/// Sequences that modern TUIs emit and older emulators never saw.
struct TerminalModernSequenceTests {
	private func makeEmulator() -> TerminalEmulator {
		TerminalEmulator(rows: 4, columns: 40)
	}

	/// `4:0` is "no underline". Reading it as a plain 4 underlines everything
	/// the application asked to be left alone.
	@Test func underlineStyleZeroTurnsUnderlineOff() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[4ma\u{1B}[4:0mb")
		#expect(emulator.screen[0].cells[0].attributes.underline)
		#expect(!emulator.screen[0].cells[1].attributes.underline)
	}

	@Test func otherUnderlineStylesStillUnderline() {
		for style in [1, 2, 3, 4, 5] {
			let emulator = makeEmulator()
			emulator.write("\u{1B}[4:\(style)mx")
			#expect(emulator.screen[0].cells[0].attributes.underline, "4:\(style)")
		}
	}

	/// Underline colour carries a doubled colon; it must not be read as a reset.
	@Test func underlineColourIsIgnoredWithoutClearingAttributes() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[1m\u{1B}[58:2::255:0:0mx")
		#expect(emulator.screen[0].cells[0].attributes.bold)
	}

	/// A title is arbitrary text and routinely holds an emoji.
	@Test func titlesAreDecodedAsUTF8() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}]0;⏳ building\u{07}")
		#expect(emulator.title == "⏳ building")
	}

	@Test func titlesTerminatedByStringTerminatorAlsoDecode() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}]2;héllo\u{1B}\\")
		#expect(emulator.title == "héllo")
	}
}

/// Private-prefixed CSI sequences share final bytes with standard ones.
struct TerminalPrivateSequenceTests {
	private func makeEmulator() -> TerminalEmulator {
		TerminalEmulator(rows: 4, columns: 40)
	}

	/// XTMODKEYS, which Claude Code sends on startup. Read as SGR it means
	/// "underline, dim", which underlines the entire application.
	@Test func modifyOtherKeysIsNotStyling() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[>4;2mx")
		let attributes = emulator.screen[0].cells[0].attributes
		#expect(!attributes.underline)
		#expect(!attributes.dim)
	}

	@Test func resettingModifyOtherKeysIsAlsoIgnored() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[1m\u{1B}[>4;mx")
		// The private sequence must not reset the bold that preceded it either.
		#expect(emulator.screen[0].cells[0].attributes.bold)
	}

	@Test func ordinarySGRStillApplies() {
		let emulator = makeEmulator()
		emulator.write("\u{1B}[4;2mx")
		let attributes = emulator.screen[0].cells[0].attributes
		#expect(attributes.underline)
		#expect(attributes.dim)
	}
}

/// The progress tail the review pane shows while an agent is working.
struct TerminalRecentLinesTests {
	@Test func returnsTheLastNonBlankLinesInOrder() {
		let emulator = TerminalEmulator(rows: 8, columns: 20)
		emulator.write("one\r\ntwo\r\n\r\nthree\r\n\r\n")
		#expect(emulator.screen.recentLines(2) == ["two", "three"])
	}

	@Test func asksForMoreLinesThanExist() {
		let emulator = TerminalEmulator(rows: 8, columns: 20)
		emulator.write("only\r\n")
		#expect(emulator.screen.recentLines(5) == ["only"])
	}

	@Test func reachesBackIntoScrollback() {
		let emulator = TerminalEmulator(rows: 2, columns: 20)
		emulator.write("a\r\nb\r\nc\r\nd")
		#expect(emulator.screen.recentLines(3) == ["b", "c", "d"])
	}

	@Test func anEmptyScreenHasNothingToShow() {
		#expect(TerminalEmulator(rows: 4, columns: 20).screen.recentLines(3).isEmpty)
	}
}

/// Regressions from the first agent review of this code.
struct TerminalReviewRegressionTests {
	@Test func stringTerminatorDoesNotLeaveABackslashOnScreen() {
		let emulator = TerminalEmulator(rows: 4, columns: 20)
		emulator.write("\u{1B}]0;title\u{1B}\\after")
		#expect(emulator.title == "title")
		#expect(emulator.screen[0].text == "after")
	}

	/// A selection made while the grid was wider outlives the resize.
	@Test func columnRangeSurvivesTheGridNarrowing() {
		let selection = TerminalSelection(
			anchor: TerminalPosition(row: 0, column: 60),
			head: TerminalPosition(row: 0, column: 90)
		)
		#expect(selection.columnRange(onRow: 0, columns: 20) == nil)
	}

	@Test func tertiaryDeviceAttributesGetNoPrimaryReply() {
		let emulator = TerminalEmulator(rows: 4, columns: 20)
		var replies: [String] = []
		emulator.onResponse = { replies.append($0) }
		emulator.write("\u{1B}[=c")
		#expect(replies.isEmpty)
	}

	@Test func primaryAndSecondaryDeviceAttributesStillAnswer() {
		let emulator = TerminalEmulator(rows: 4, columns: 20)
		var replies: [String] = []
		emulator.onResponse = { replies.append($0) }
		emulator.write("\u{1B}[c\u{1B}[>c")
		#expect(replies.count == 2)
		#expect(replies[1].contains(">"))
	}

	/// Discarded lines renumber every absolute row above them.
	@Test func discardedLineCountTracksTrimmedScrollback() {
		var screen = TerminalScreen(rows: 2, columns: 10)
		screen.maximumScrollback = 3
		#expect(screen.discardedLineCount == 0)

		for _ in 0..<10 { screen.scrollUp(top: 0, bottom: 1, attributes: TerminalAttributes()) }
		#expect(screen.discardedLineCount > 0)
		#expect(screen.scrollback.count <= 3)
	}
}

/// The progress tail has to skip a TUI's frame, which is what sits at the
/// bottom of the screen while the interesting output is above it.
struct TerminalActivityFilterTests {
	@Test func decorationOnlyLinesAreNotSubstantive() {
		for frame in ["───────", "│   │", "╭──╮", "  ›  ", "···", "  "] {
			#expect(!TerminalScreen.isSubstantive(frame), "\(frame)")
		}
	}

	@Test func linesWithWordsOrNumbersAreSubstantive() {
		for text in ["Thinking…", "✳ Herding (30s)", "12"] {
			#expect(TerminalScreen.isSubstantive(text), "\(text)")
		}
	}

	@Test func recentLinesSkipsTheInputBoxAndFindsTheStatus() {
		let emulator = TerminalEmulator(rows: 8, columns: 40)
		emulator.write("✳ Reviewing TerminalView.swift\r\n")
		emulator.write("╭──────────────────╮\r\n")
		emulator.write("│ >                │\r\n")
		emulator.write("╰──────────────────╯\r\n")
		#expect(emulator.screen.recentLines(1) == ["✳ Reviewing TerminalView.swift"])
	}
}

/// Mode and status queries block the program that sends them, so silence is
/// the one answer that is never acceptable.
struct TerminalQueryReplyTests {
	private func replies(to input: String) -> [String] {
		let emulator = TerminalEmulator(rows: 4, columns: 20)
		var captured: [String] = []
		emulator.onResponse = { captured.append($0) }
		emulator.write(input)
		return captured
	}

	/// DECRQM: `CSI ? Pa $ p`. tmux and modern shells probe synchronised output
	/// (mode 2026) this way and wait for the answer.
	@Test func decrqmIsAnswered() {
		let replies = replies(to: "\u{1B}[?2026$p")
		#expect(replies.count == 1)
		#expect(replies.first?.contains("2026") == true)
		#expect(replies.first?.hasSuffix("$y") == true)
	}

	/// DECXCPR: `CSI ? 6 n`, the private form of the cursor position report. Its
	/// reply carries the `?` back so the sender can tell the two apart.
	@Test func extendedCursorPositionIsAnswered() {
		let replies = replies(to: "\u{1B}[3;5H\u{1B}[?6n")
		#expect(replies.count == 1)
		#expect(replies.first == "\u{1B}[?3;5R")
	}

	@Test func plainCursorPositionStillAnswersWithoutTheMarker() {
		let replies = replies(to: "\u{1B}[3;5H\u{1B}[6n")
		#expect(replies == ["\u{1B}[3;5R"])
	}

	@Test func terminalStatusIsAnswered() {
		#expect(replies(to: "\u{1B}[5n") == ["\u{1B}[0n"])
	}
}

/// The guard that stops private sequences being read as their ANSI namesakes
/// has to let through exactly the handlers that check the introducer, and no
/// more. Both directions are easy to get wrong and neither fails loudly.
struct TerminalIntroducerGuardTests {
	private func replies(to input: String) -> [String] {
		let emulator = TerminalEmulator(rows: 4, columns: 20)
		var captured: [String] = []
		emulator.onResponse = { captured.append($0) }
		emulator.write(input)
		return captured
	}

	/// Every final in the set must reach a handler that checks the introducer.
	@Test func everyAllowedFinalHasAnIntroducerAwareHandler() {
		// `h` and `l` are checked by their effect rather than a reply.
		let emulator = TerminalEmulator(rows: 4, columns: 20)
		emulator.write("\u{1B}[?7h")
		#expect(emulator.screen.rows == 4)      // parsed, not dropped

		#expect(!replies(to: "\u{1B}[?c").isEmpty == false)   // `?` DA: no answer
		#expect(!replies(to: "\u{1B}[>c").isEmpty)            // secondary DA
		#expect(!replies(to: "\u{1B}[?2026$p").isEmpty)       // DECRQM
		#expect(!replies(to: "\u{1B}[?6n").isEmpty)           // DECXCPR
	}

	/// And nothing outside it may be run as an ANSI command.
	@Test func privateFormsOfStylingAndMovementAreIgnored() {
		let emulator = TerminalEmulator(rows: 4, columns: 20)
		emulator.write("\u{1B}[>4;2mx")
		#expect(!emulator.screen[0].cells[0].attributes.underline)

		emulator.write("\u{1B}[?3B")
		#expect(emulator.cursorRow == 0)
	}
}

/// Keys with a fixed sequence, and what Option does to them.
struct TerminalKeyEncodingTests {
	private func meta(_ key: TerminalKeys.Key) -> String? {
		TerminalKeys.sequence(for: key).map {
			TerminalKeys.applyingMeta($0, key: key, optionHeld: true)
		}
	}

	private func plain(_ key: TerminalKeys.Key) -> String? {
		TerminalKeys.sequence(for: key).map {
			TerminalKeys.applyingMeta($0, key: key, optionHeld: false)
		}
	}

	/// The one people notice: a prompt that submits on Return uses ESC Return
	/// for "newline without submitting", so a bare CR sends the message the
	/// user was trying to break in half.
	@Test func optionReturnSendsEscapeThenReturn() {
		#expect(plain(.Return) == "\r")
		#expect(meta(.Return) == "\u{1B}\r")
	}

	/// Delete-word-backwards, which shells read as ESC DEL.
	@Test func optionBackspaceSendsEscapeThenDelete() {
		#expect(plain(.backspace) == "\u{7F}")
		#expect(meta(.backspace) == "\u{1B}\u{7F}")
	}

	@Test func backspaceSendsDeleteNotBackspace() {
		// BS (0x08) would move the cursor rather than delete.
		#expect(plain(.backspace) == "\u{7F}")
	}

	/// Arrows spell the modifier inside their CSI sequence; prefixing one
	/// produces ESC ESC [ D, which nothing parses.
	@Test func arrowsDoNotTakeAMetaPrefix() {
		for key in [TerminalKeys.Key.upArrow, .downArrow, .leftArrow, .rightArrow] {
			#expect(!TerminalKeys.takesMetaPrefix(key), "\(key)")
		}
	}

	@Test func navigationKeysDoNotTakeAMetaPrefix() {
		for key in [TerminalKeys.Key.home, .end, .pageUp, .pageDown] {
			#expect(!TerminalKeys.takesMetaPrefix(key), "\(key)")
		}
	}

	/// Arrow encoding depends on the cursor-key mode, which only the emulator
	/// tracks, so the table has nothing to say about them.
	@Test func arrowsHaveNoFixedSequence() {
		#expect(TerminalKeys.sequence(for: .leftArrow) == nil)
	}

	@Test func theFixedSequencesAreTheStandardOnes() {
		#expect(plain(.home) == "\u{1B}[H")
		#expect(plain(.end) == "\u{1B}[F")
		#expect(plain(.pageUp) == "\u{1B}[5~")
		#expect(plain(.pageDown) == "\u{1B}[6~")
		#expect(plain(.forwardDelete) == "\u{1B}[3~")
		#expect(plain(.tab) == "\t")
		#expect(plain(.escape) == "\u{1B}")
	}

	@Test func keyCodesMatchTheOnesMacOSSends() {
		#expect(TerminalKeys.Key(rawValue: 36) == .Return)
		#expect(TerminalKeys.Key(rawValue: 51) == .backspace)
		#expect(TerminalKeys.Key(rawValue: 123) == .leftArrow)
		#expect(TerminalKeys.Key(rawValue: 99) == nil)
	}
}

/// Moving around a line, the way macOS users expect and every line editor
/// understands.
struct TerminalNavigationKeyTests {
	private func sequence(_ key: TerminalKeys.Key, option: Bool = false, command: Bool = false) -> String? {
		TerminalKeys.editingSequence(for: key, option: option, command: command)
	}

	/// ⌥← / ⌥→ move by word. Sent as meta-b and meta-f rather than a CSI with a
	/// modifier parameter: a program has to opt into parsing the latter, while
	/// every line editor has understood the former for decades.
	@Test func optionArrowsMoveByWord() {
		#expect(sequence(.leftArrow, option: true) == "\u{1B}b")
		#expect(sequence(.rightArrow, option: true) == "\u{1B}f")
	}

	/// ⌘← / ⌘→ go to the ends of the line, matching every native text field.
	@Test func commandArrowsGoToTheLineEnds() {
		#expect(sequence(.leftArrow, command: true) == "\u{01}")
		#expect(sequence(.rightArrow, command: true) == "\u{05}")
	}

	@Test func commandBackspaceClearsToTheStartOfTheLine() {
		#expect(sequence(.backspace, command: true) == "\u{15}")
	}

	/// ⌥⌫ stays with the meta rule, where it becomes ESC DEL — one word, not
	/// the whole line.
	@Test func optionBackspaceIsLeftToTheMetaRule() {
		#expect(sequence(.backspace, option: true) == nil)
		#expect(TerminalKeys.takesMetaPrefix(.backspace))
	}

	/// Command wins when both are held, since it is the coarser movement.
	@Test func commandTakesPrecedenceOverOption() {
		#expect(sequence(.leftArrow, option: true, command: true) == "\u{01}")
	}

	/// An unmodified arrow still goes through the emulator, which knows the
	/// cursor-key mode the program selected.
	@Test func unmodifiedArrowsHaveNoEditingSequence() {
		#expect(sequence(.leftArrow) == nil)
		#expect(sequence(.rightArrow) == nil)
	}

	@Test func verticalArrowsAreNotRemapped() {
		#expect(sequence(.upArrow, option: true) == nil)
		#expect(sequence(.downArrow, command: true) == nil)
	}
}

/// Dropping files onto a terminal types their paths.
struct TerminalDropTests {
	@Test func anOrdinaryPathIsNotQuoted() {
		#expect(TerminalDrop.quoted("/Users/x/dev/main.go") == "/Users/x/dev/main.go")
	}

	/// A shell would read these as syntax rather than as part of the name.
	@Test func awkwardPathsAreQuoted() {
		#expect(TerminalDrop.quoted("/a b/c.txt") == "'/a b/c.txt'")
		#expect(TerminalDrop.quoted("/a$b") == "'/a$b'")
		#expect(TerminalDrop.quoted("/a;rm -rf/") == "'/a;rm -rf/'")
		#expect(TerminalDrop.quoted("/a*b") == "'/a*b'")
	}

	/// A single quote cannot appear inside a single-quoted string, so it is
	/// closed, escaped and reopened.
	@Test func embeddedSingleQuotesAreEscaped() {
		#expect(TerminalDrop.quoted("/it's here") == "'/it'\\''s here'")
	}

	@Test func severalFilesAreSeparated() {
		let text = TerminalDrop.text(for: [
			URL(fileURLWithPath: "/a/one.txt"),
			URL(fileURLWithPath: "/a/two.txt"),
		])
		#expect(text == "/a/one.txt /a/two.txt ")
	}

	/// The trailing space matters: whatever is typed or dropped next would
	/// otherwise run into the last path.
	@Test func theTextEndsWithASpace() {
		#expect(TerminalDrop.text(for: [URL(fileURLWithPath: "/a/x")]).hasSuffix(" "))
	}

	@Test func droppingNothingTypesNothing() {
		#expect(TerminalDrop.text(for: []).isEmpty)
	}
}

/// Synchronised output: a program saying "I am part-way through a repaint".
struct SynchronisedOutputTests {
	@Test func modeIsTrackedBothWays() {
		let emulator = TerminalEmulator(rows: 4, columns: 20)
		#expect(!emulator.isSynchronizingOutput)

		emulator.write("\u{1B}[?2026h")
		#expect(emulator.isSynchronizingOutput)

		emulator.write("\u{1B}[?2026l")
		#expect(!emulator.isSynchronizingOutput)
	}

	/// A program only uses the mode if the terminal says it has it, so the
	/// query has to answer properly rather than plead ignorance.
	@Test func theModeQueryReportsWhetherItIsSet() {
		let emulator = TerminalEmulator(rows: 4, columns: 20)
		var replies: [String] = []
		emulator.onResponse = { replies.append($0) }

		emulator.write("\u{1B}[?2026$p")
		#expect(replies.last == "\u{1B}[?2026;2$y", "reset")

		emulator.write("\u{1B}[?2026h")
		emulator.write("\u{1B}[?2026$p")
		#expect(replies.last == "\u{1B}[?2026;1$y", "set")
	}

	/// Anything else is still answered, so nothing is left waiting.
	@Test func anUnknownModeIsStillAnswered() {
		let emulator = TerminalEmulator(rows: 4, columns: 20)
		var replies: [String] = []
		emulator.onResponse = { replies.append($0) }

		emulator.write("\u{1B}[?9999$p")
		#expect(replies.last == "\u{1B}[?9999;0$y")
	}

	/// The screen keeps being written while the mode is on; only showing it
	/// waits.
	@Test func outputStillArrivesWhileSynchronised() {
		let emulator = TerminalEmulator(rows: 4, columns: 20)
		emulator.write("\u{1B}[?2026h")
		emulator.write("hello")
		#expect(emulator.screen.lines[0].text.hasPrefix("hello"))
	}
}

/// How much of the view a line of output asks to have redrawn.
///
/// This is the number that decides what output costs on the CoreGraphics path:
/// `TerminalView.invalidateChangedRows` repaints the rows in the dirty range, and
/// gives up and repaints the whole viewport once that range covers half of it. A
/// seam that reported the whole buffer where it used to report a row would draw a
/// screenful for every line printed, at forty times the cost, with nothing else
/// in the program having changed.
///
/// **Nothing asserted any of this before item 0487**, which is why ruling it out
/// meant reading the code rather than running something. Asserted through
/// `TerminalEngine` on purpose: the range crossing the seam is exactly the part
/// that can change while none of the emulator's own code does.
struct TerminalDirtyRangeTests {
	/// A printed line dirties the row it landed on and the blank one that
	/// replaced it. Two rows out of five thousand, not five thousand.
	///
	/// Two rather than one because the line scrolls: the text keeps its absolute
	/// index as it becomes history, and the new bottom row is a different index.
	/// Both have to be drawn, and that is what the range says.
	@Test func aPrintedLineDirtiesTwoRows() {
		let engine: TerminalEngine = TerminalEmulator(rows: 6, columns: 20)
		// Fill the grid first, and take what filling it dirtied, so the next line
		// scrolls and the range below is one line's worth and nothing else.
		engine.write(String(repeating: "filler\r\n", count: 20))
		_ = engine.takeDirtyRange()

		engine.write("one more line\r\n")
		let range = engine.takeDirtyRange()
		#expect(range?.count == 2, "one printed line: \(String(describing: range))")
		#expect(range?.upperBound == engine.grid.totalLineCount - 1)
		// The number the view's own decision turns on: fewer than half a viewport,
		// so it repaints two rows rather than all of them.
		#expect((range?.count ?? .max) < engine.grid.rows / 2)

		// And nothing left once it has been taken, which is what makes the frame
		// after a frame free.
		#expect(engine.takeDirtyRange() == nil)
	}

	/// A line falling out of history renumbers every absolute index, and *that*
	/// really is the whole document.
	///
	/// The other half of the claim above: the range is not always small, and the
	/// case where it is not is the case it must not be small in. Kept beside it so
	/// that anybody narrowing the range for speed has to argue with this one too.
	///
	/// Enough lines to fill the default history and then push one out of it: the
	/// emulator's scrollback limit cannot be set from outside it, so this reaches
	/// the limit rather than shortening it. Forty kilobytes, a couple of
	/// milliseconds.
	@Test func aDiscardedLineDirtiesEverything() {
		let engine: TerminalEngine = TerminalEmulator(rows: 4, columns: 20)
		engine.write(String(repeating: "filler\r\n", count: 5_010))
		let before = engine.grid.discardedLineCount
		#expect(before > 0, "the history has to be full for this to be the case being tested")
		_ = engine.takeDirtyRange()

		engine.write("this one pushes a line off the top\r\n")
		#expect(engine.grid.discardedLineCount > before)
		let range = engine.takeDirtyRange()
		#expect(range?.lowerBound == 0)
		#expect((range?.count ?? 0) >= engine.grid.totalLineCount)
	}
}
