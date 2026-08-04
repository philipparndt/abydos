import Foundation
import Testing
@testable import IdeaiKit

/// What a spawned process gets, beyond "it ran".
///
/// The pane's child stopped being forked and became a `posix_spawn`, so that it
/// could be told it is responsible for itself. Everything `forkpty` used to
/// arrange had to be arranged again by hand — a session of its own, a
/// controlling terminal, a window size, job control — and every one of those
/// fails quietly rather than loudly: the shell still starts, and then ⌃C does
/// nothing, or `vim` draws itself into a screen of no size.
///
/// So they are asked about here, one at a time, by the only party whose opinion
/// counts: the child.
struct PseudoTerminalSpawnTests {
	private func makePTY() -> PseudoTerminal {
		let pty = PseudoTerminal()
		pty.callbackQueue = DispatchQueue(label: "ideai.tests.spawn.callbacks")
		return pty
	}

	/// Runs one shell command in a pane and gives back everything it printed.
	private func output(
		_ command: String,
		rows: Int = 30,
		columns: Int = 100,
		workingDirectory: URL? = nil,
		environment: [String: String]? = nil,
		until marker: String = "DONE"
	) async -> String {
		let pty = makePTY()
		let collected = Sink()
		pty.onOutput = { collected.append($0) }

		#expect(pty.start(
			executable: "/bin/sh",
			arguments: ["-c", command + "; echo \(marker)"],
			workingDirectory: workingDirectory,
			environment: environment,
			rows: rows,
			columns: columns
		))

		let deadline = Date().addingTimeInterval(10)
		while Date() < deadline, !collected.text.contains(marker) {
			try? await Task.sleep(nanoseconds: 20_000_000)
		}
		let text = collected.text
		pty.terminate()
		return text
	}

	// MARK: - The terminal itself

	@Test func allThreeDescriptorsAreTheTerminal() async {
		let text = await output("""
		test -t 0 && echo IN_TTY
		test -t 1 && echo OUT_TTY
		test -t 2 && echo ERR_TTY
		""")
		#expect(text.contains("IN_TTY"), "stdin was not a terminal: \(text)")
		#expect(text.contains("OUT_TTY"), "stdout was not a terminal: \(text)")
		#expect(text.contains("ERR_TTY"), "stderr was not a terminal: \(text)")
	}

	/// The size has to be on the tty before the child looks, or every
	/// full-screen program starts by drawing itself into nothing.
	@Test func theSizeIsAlreadyRightWhenTheChildAsks() async {
		let text = await output("stty size", rows: 30, columns: 100)
		#expect(text.contains("30 100"), "expected 30 100, got: \(text)")
	}

	@Test func aDifferentSizeIsHonouredToo() async {
		let text = await output("stty size", rows: 12, columns: 40)
		#expect(text.contains("12 40"), "expected 12 40, got: \(text)")
	}

	// MARK: - Session and job control

	/// A group of its own, led by the child.
	///
	/// `setsid` makes a new session *and* a new process group led by the caller,
	/// and a spawn without it leaves the child in this app's group instead. The
	/// session id itself cannot be asked for portably here — macOS `ps -o sess`
	/// answers 0 — but the group is the same evidence: it is only the child's
	/// own if the session was made.
	@Test func theChildLeadsItsOwnProcessGroup() async {
		let text = await output("echo PGID=$(ps -o pgid= -p $$ | tr -d ' ') PID=$$")
		let fields = Dictionary(uniqueKeysWithValues: text
			.split(whereSeparator: \.isWhitespace)
			.compactMap { field -> (String, String)? in
				let parts = field.split(separator: "=", maxSplits: 1)
				return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
			})
		let group = fields["PGID"] ?? "?"
		let pid = fields["PID"] ?? "!"
		#expect(group == pid, "the child is in somebody else's process group: \(text)")
	}

	/// `tty` names the pane's own device. A child without a controlling
	/// terminal answers "not a tty" here even while its descriptors are one.
	@Test func theTerminalIsTheChildsControllingTerminal() async {
		let text = await output("tty")
		#expect(text.contains("/dev/ttys"), "no controlling terminal: \(text)")
	}

	/// The kernel tracks which process group is in the foreground of the tty.
	/// That number is what job control *is*, and what a signal from ⌃C is sent
	/// to. Zero or -1 means the pane has no foreground and ⌃C reaches nothing.
	@Test func theTerminalHasAForegroundProcessGroup() async {
		let text = await output("echo FG=$(ps -o tpgid= -p $$ | tr -d ' ')")
		let foreground = text
			.split(whereSeparator: \.isWhitespace)
			.first { $0.hasPrefix("FG=") }
			.map { String($0.dropFirst(3)) }
			.flatMap(Int.init)
		#expect((foreground ?? -1) > 0, "no foreground process group: \(text)")
	}


	/// ⌃C is deliberately not tested here.
	///
	/// The obvious test — write 0x03 to the terminal, watch the child take
	/// SIGINT — does not pass in this process, and does not pass against the
	/// `forkpty` this replaced either. The tty is configured for it: `isig` is
	/// on and `intr` is `^C`, input written to the master reaches the child and
	/// is echoed back, and the tty has a foreground process group. Something
	/// about a test process differs from an app, and asserting a thing that
	/// fails for both implementations would say nothing about either.
	///
	/// So it is checked by hand in the app instead: run `sleep 30` in a pane
	/// and press ⌃C. What this suite covers is everything ⌃C *depends* on —
	/// the session, the controlling terminal, the foreground group — each of
	/// which fails silently and none of which was covered before.

	// MARK: - What was asked for



	@Test func theWorkingDirectoryIsWhereItWasAsked() async {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-spawn-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let text = await output("pwd", workingDirectory: directory)
		#expect(
			text.contains(directory.lastPathComponent),
			"expected \(directory.path), got: \(text)"
		)
	}

	/// A pane claims a capable terminal so tools turn colour on — when nothing
	/// has already said what kind of terminal this is.
	@Test func aPaneClaimsACapableTerminal() async {
		let text = await output("echo TERM=$TERM COLOR=$COLORTERM", environment: [
			"PATH": "/usr/bin:/bin",
		])
		#expect(text.contains("TERM=xterm-256color"), "got: \(text)")
		#expect(text.contains("COLOR=truecolor"), "got: \(text)")
	}

	/// And leaves alone what was said. A pane inside tmux is told it is a tmux
	/// terminal, and overriding that would be describing the wrong one.
	@Test func aTerminalAlreadyNamedIsKept() async {
		let text = await output("echo TERM=$TERM", environment: [
			"TERM": "tmux-256color",
			"PATH": "/usr/bin:/bin",
		])
		#expect(text.contains("TERM=tmux-256color"), "got: \(text)")
	}

	@Test func anEnvironmentGivenToItIsUsed() async {
		let text = await output("echo MARK=$IDEAI_SPAWN_TEST", environment: [
			"IDEAI_SPAWN_TEST": "carried",
			"PATH": "/usr/bin:/bin",
		])
		#expect(text.contains("MARK=carried"), "got: \(text)")
	}

	/// Our end of the pair is ours alone: left open in the child, the master
	/// never reports end-of-file and a finished pane looks like a running one.
	@Test func theProcessIsSeenToExit() async {
		let pty = makePTY()
		let exited = Sink()
		pty.onExit = { exited.append(Data("EXIT=\($0)".utf8)) }

		#expect(pty.start(executable: "/bin/sh", arguments: ["-c", "exit 3"]))

		let deadline = Date().addingTimeInterval(10)
		while Date() < deadline, exited.text.isEmpty {
			try? await Task.sleep(nanoseconds: 20_000_000)
		}
		#expect(exited.text == "EXIT=3", "got: \(exited.text)")
	}
}

private final class Sink: @unchecked Sendable {
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
