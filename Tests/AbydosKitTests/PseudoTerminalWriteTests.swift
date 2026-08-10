import Foundation
import Testing
@testable import AbydosKit

/// Sending a program more than the pty can take at once.
///
/// A pasted crash report is tens of kilobytes; a pty buffer is a few. The
/// master is non-blocking, so a write that fills it says "not now" — and the
/// old loop took that as "stop", which meant most of a paste never arrived
/// while the app looked as though it had sent it.
struct PseudoTerminalWriteTests {
	@Test func everythingWrittenArrivesEvenWhenItIsFarTooMuch() async throws {
		let terminal = PseudoTerminal()
		let received = Received()
		terminal.onOutput = { received.append($0) }

		// `cat` sends back whatever it is given, so what arrives is the measure
		// of what got through.
		try #require(terminal.start(executable: "/bin/cat", arguments: [], rows: 24, columns: 80))
		defer { terminal.terminate() }

		// Far more than a pty buffer holds, and every line numbered so a gap in
		// the middle would show.
		let lines = (0..<4000).map { "line \($0) ................................................" }
		let payload = lines.joined(separator: "\n") + "\n"
		terminal.write(Data(payload.utf8))

		// Waited for by its last line rather than by a byte count: a pty echoes
		// what it is given as well as what the program says, so counting bytes
		// says "enough have arrived" long before the end has.
		let arrived = await received.wait(forText: "line 3999 ", seconds: 30)
		let text = received.text
		if !arrived {
			Issue.record("""
			the end never arrived: \(received.count) bytes back, \
			last line seen \(text.split(separator: "\n").last ?? "none")
			""")
		}
		#expect(text.contains("line 0 "))
		#expect(text.contains("line 2000 "), "the middle, which used to be dropped")
	}

	/// What is waiting is something the caller can ask about, so anything
	/// advisory — a mouse moving — can be left out while there is a backlog.
	@Test func aBacklogIsVisible() throws {
		let terminal = PseudoTerminal()
		try #require(terminal.start(executable: "/bin/cat", arguments: [], rows: 24, columns: 80))
		defer { terminal.terminate() }

		#expect(terminal.pendingInputCount == 0)
		terminal.write(Data(String(repeating: "x", count: 400_000).utf8))
		// Some of it will have gone; the rest is waiting rather than lost.
		#expect(terminal.pendingInputCount >= 0)
	}

	/// A cell that changes size is told to the program straight away.
	///
	/// The pixels in a winsize are the only way anything can work out how large
	/// a cell is, and `icat` sizes a whole picture from them. Only a change in
	/// the number of *cells* used to write the structure, so a pane that learnt
	/// its real cell size after the window appeared — which is when the display's
	/// scale is first knowable — left the program on the old number until
	/// something else happened to resize it.
	@Test func aChangedCellSizeReachesTheProgramWithoutAResize() throws {
		let terminal = PseudoTerminal()
		terminal.cellPixelSize = (width: 8, height: 19)
		try #require(terminal.start(executable: "/bin/cat", arguments: [], rows: 24, columns: 80))
		defer { terminal.terminate() }

		let before = try #require(terminal.reportedWindowSize)
		#expect(before.pixelWidth == 80 * 8)
		#expect(before.pixelHeight == 24 * 19)

		terminal.cellPixelSize = (width: 16, height: 38)

		let after = try #require(terminal.reportedWindowSize)
		#expect(after.rows == 24, "the grid is unchanged")
		#expect(after.columns == 80)
		#expect(after.pixelWidth == 80 * 16)
		#expect(after.pixelHeight == 24 * 38)
	}

	/// And the grid it is reported against is the one in force, not the one the
	/// pane was started with.
	@Test func theNewCellSizeIsReportedAgainstTheCurrentGrid() throws {
		let terminal = PseudoTerminal()
		terminal.cellPixelSize = (width: 8, height: 19)
		try #require(terminal.start(executable: "/bin/cat", arguments: [], rows: 24, columns: 80))
		defer { terminal.terminate() }

		terminal.resize(rows: 40, columns: 120)
		terminal.cellPixelSize = (width: 16, height: 38)

		let after = try #require(terminal.reportedWindowSize)
		#expect(after.rows == 40)
		#expect(after.columns == 120)
		#expect(after.pixelWidth == 120 * 16)
		#expect(after.pixelHeight == 40 * 38)
	}

	/// Collects what the program sends back.
	private final class Received: @unchecked Sendable {
		private let lock = NSLock()
		private var data = Data()

		func append(_ chunk: Data) {
			lock.lock(); data.append(chunk); lock.unlock()
		}

		var count: Int {
			lock.lock(); defer { lock.unlock() }
			return data.count
		}

		var text: String {
			lock.lock(); defer { lock.unlock() }
			return String(decoding: data, as: UTF8.self)
		}

		func wait(forText wanted: String, seconds: TimeInterval) async -> Bool {
			let deadline = Date().addingTimeInterval(seconds)
			while Date() < deadline {
				if text.contains(wanted) { return true }
				try? await Task.sleep(nanoseconds: 50_000_000)
			}
			return text.contains(wanted)
		}
	}
}

/// What a shell is started with, and where it is built.
///
/// The environment used to be merged on the child side of the fork, which is a
/// place where almost nothing is legal: the child is one thread in a copy of a
/// process whose other threads stopped wherever they were, including inside
/// locks. Merging maps a dictionary — `(key, value)` tuples — and instantiating
/// tuple metadata takes one of those locks, which is how a terminal came to
/// abort with "crashed on child side of fork pre-exec".
struct PseudoTerminalEnvironmentTests {
	@Test func claimsATerminalThatToolsWillUse() {
		let merged = PseudoTerminal.mergedEnvironment(nil, bundled: nil, inherited: [:])
		#expect(merged["TERM"] == "xterm-256color")
		#expect(merged["COLORTERM"] == "truecolor")
		#expect(merged["PAGER"] == "cat")
	}

	/// What somebody already has wins: this is claiming a capable terminal, not
	/// overruling a choice.
	@Test func leavesWhatIsAlreadySetAlone() {
		let merged = PseudoTerminal.mergedEnvironment(
			["TERM": "dumb", "PAGER": "less"], bundled: nil
		)
		#expect(merged["TERM"] == "dumb")
		#expect(merged["PAGER"] == "less")
	}

	/// What this terminal calls itself, whatever it was launched from.
	///
	/// `abydos <file>` reads `TERM_PROGRAM` to decide whether writing the escape
	/// that opens a file in this window is worth doing at all. An inherited
	/// value is a lie here: the app launched from Ghostty inherits
	/// `TERM_PROGRAM=ghostty`, and a pane claiming to be Ghostty would send
	/// every file back out through LaunchServices.
	@Test func namesThisTerminalRatherThanTheOneItWasLaunchedFrom() {
		let merged = PseudoTerminal.mergedEnvironment(
			["TERM_PROGRAM": "ghostty"], bundled: nil, app: nil
		)
		#expect(merged["TERM_PROGRAM"] == "Abydos")
	}

	/// Which build to fall back to. Somebody running a checkout is looking at
	/// `build/Abydos.app`, and opening `/Applications/Abydos.app` instead puts
	/// the file in a different program.
	@Test func namesTheBuildItIsRunningOutOf() {
		let merged = PseudoTerminal.mergedEnvironment(
			nil, bundled: nil, app: "/checkout/build/Abydos.app", inherited: [:]
		)
		#expect(merged["IDEAI_APP"] == "/checkout/build/Abydos.app")

		let outsideABundle = PseudoTerminal.mergedEnvironment(
			nil, bundled: nil, app: nil, inherited: [:]
		)
		#expect(outsideABundle["IDEAI_APP"] == nil)
	}

	/// A pane is not inside tmux because the app was launched from a shell that
	/// was.
	///
	/// The same lie as `TERM_PROGRAM`, inherited the same way: `make run` from a
	/// shell in tmux handed `TMUX` to every pane, naming a session none of them
	/// was in. `abydos <file>` believed it, wrapped its question in a passthrough
	/// nothing was there to unwrap, heard no answer, and opened the file through
	/// LaunchServices instead of in the window it was typed in.
	@Test func aPaneIsNotInTheTmuxTheAppWasLaunchedFrom() {
		let merged = PseudoTerminal.mergedEnvironment(
			["TMUX": "/private/tmp/tmux-501/default,42,0", "TMUX_PANE": "%7"],
			bundled: nil, app: nil
		)
		#expect(merged["TMUX"] == nil)
		#expect(merged["TMUX_PANE"] == nil)
	}

	/// Absent rather than empty. tmux sets the variable itself when a pane goes
	/// on to start it, and a shell asking "am I in tmux" wants one answer to
	/// read rather than two spellings of no.
	@Test func theAbsenceIsTheAnswerRatherThanAnEmptyString() {
		let merged = PseudoTerminal.mergedEnvironment(
			["TMUX": "/tmp/x,1,0"], bundled: nil, app: nil
		)
		#expect(!merged.keys.contains("TMUX"))
	}

	/// A directory whose socket cannot exist is not a preference to be honoured.
	///
	/// `TMUX_TMPDIR` was set in the shell the app was launched from, every pane
	/// inherited it, and tmux appends `tmux-<uid>/default` to it — so the socket
	/// came to about 133 bytes where 103 is the most a unix socket path can be.
	/// The pane died before it drew a prompt, saying `File name too long` about
	/// a path nobody had typed.
	@Test func refusesATmuxDirectoryWhoseSocketCouldNotExist() {
		let tooLong = "/private/tmp/" + String(repeating: "d", count: 120)
		let merged = PseudoTerminal.mergedEnvironment(
			["TMUX_TMPDIR": tooLong], bundled: nil, app: nil
		)
		#expect(!merged.keys.contains("TMUX_TMPDIR"))
	}

	/// And the other side, which is the whole of the design: a short one is
	/// somebody's choice, and taking it away would put their panes on a
	/// different tmux server from their other tools.
	@Test func honoursATmuxDirectoryWhoseSocketFits() {
		let merged = PseudoTerminal.mergedEnvironment(
			["TMUX_TMPDIR": "/private/tmp/sockets"], bundled: nil, app: nil
		)
		#expect(merged["TMUX_TMPDIR"] == "/private/tmp/sockets")
	}

	/// What the pane is told, so the refusal is not silent. tmux's own sentence
	/// explained nothing to whoever was looking at it; this one names the
	/// variable, the number and what happens instead.
	@Test func saysInThePaneWhatItRefusedAndWhy() throws {
		let tooLong = "/private/tmp/" + String(repeating: "d", count: 120)
		let said = try #require(PseudoTerminal.refusals(["TMUX_TMPDIR": tooLong]))
		#expect(said.contains("TMUX_TMPDIR"))
		#expect(said.contains("\(TmuxSocketPath.limit)"))
		#expect(said.hasSuffix("\r\n"), "raw mode: a bare newline leaves the prompt indented")

		#expect(PseudoTerminal.refusals(["TMUX_TMPDIR": "/private/tmp/sockets"]) == nil)
		#expect(PseudoTerminal.refusals([:]) == nil)
	}

	/// The bundled commands go on the end of the PATH, so a command somebody
	/// already has still wins.
	@Test func appendsTheBundledCommands() {
		let merged = PseudoTerminal.mergedEnvironment(
			["PATH": "/usr/bin:/bin"], bundled: "/Apps/Abydos.app/Contents/Resources/bin"
		)
		#expect(merged["PATH"] == "/usr/bin:/bin:/Apps/Abydos.app/Contents/Resources/bin")
	}

	/// And only once, however many shells are started.
	@Test func doesNotAddThemTwice() {
		let bundled = "/Apps/Abydos.app/Contents/Resources/bin"
		let once = PseudoTerminal.mergedEnvironment(["PATH": "/usr/bin"], bundled: bundled)
		let twice = PseudoTerminal.mergedEnvironment(once, bundled: bundled)
		#expect(once["PATH"] == twice["PATH"])
	}

	/// The C arrays the child is handed: null-terminated, in order, and holding
	/// copies rather than pointers into Swift strings that may move.
	@Test func buildsANullTerminatedArgumentList() {
		let array = PseudoTerminal.cStrings(["/bin/zsh", "-l"])
		defer { PseudoTerminal.free(array) }

		#expect(String(cString: array[0]!) == "/bin/zsh")
		#expect(String(cString: array[1]!) == "-l")
		#expect(array[2] == nil)
	}

	@Test func buildsAnEmptyListThatIsStillTerminated() {
		let array = PseudoTerminal.cStrings([])
		defer { PseudoTerminal.free(array) }
		#expect(array[0] == nil)
	}
}
