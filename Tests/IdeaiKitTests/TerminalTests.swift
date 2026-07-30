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
