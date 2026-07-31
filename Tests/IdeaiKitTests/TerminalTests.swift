import Testing
import Foundation
@testable import IdeaiKit

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
	private func wait(timeout: TimeInterval = 5, until condition: @escaping () -> Bool) async -> Bool {
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
		#expect(sawOutput, "expected output, got: \(collected.text)")
		pty.terminate()
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
