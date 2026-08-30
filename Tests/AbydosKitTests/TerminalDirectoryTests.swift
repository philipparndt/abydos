import Foundation
import Testing
@testable import AbydosKit

/// Reading a terminal's working directory from the system.
struct TerminalDirectoryTests {
	/// The process asking is a process like any other, so it can answer about
	/// itself — which is enough to know the reading path works at all.
	@Test func readsTheDirectoryOfAProcess() {
		let mine = TerminalDirectory.directory(of: getpid())
		#expect(mine != nil)
		// Resolved through the same call the real path goes through, so a
		// symlinked temporary directory does not make this fail.
		#expect(mine?.path == FileManager.default.currentDirectoryPath)
	}

	@Test func readsTheNameOfAProcess() {
		let name = TerminalDirectory.processName(of: getpid())
		#expect(name != nil)
		#expect(!(name?.isEmpty ?? true))
	}

	@Test func hasNoAnswerForADescriptorThatIsNotATerminal() {
		#expect(TerminalDirectory.current(masterDescriptor: -1, slaveName: nil) == nil)
	}

	/// A client tmux has never heard of gets no answer rather than a wrong one.
	@Test func anUnknownTmuxClientGivesNothing() {
		#expect(TerminalDirectory.tmuxPaneDirectory(client: "/dev/ttys999") == nil)
	}
}

/// Following a terminal only while it is *waiting*.
///
/// **A window follows where somebody walked, not where a script went.** The
/// foreground process's own working directory is the command's while one is
/// running, and a command that changes directory — `brew` does, several times —
/// dragged the window through every one of them.
@Suite(.serialized)
struct SettledDirectoryTests {
	/// Waits for a condition, with a bound that says what it was waiting for.
	/// No timing is asserted: the bound is only there so a wedged test fails
	/// rather than hanging.
	private func until(_ what: String, _ ready: () -> Bool) throws {
		for _ in 0..<200 {
			if ready() { return }
			usleep(25_000)
		}
		throw TestFailure(what)
	}

	private struct TestFailure: Error { let what: String; init(_ what: String) { self.what = what } }

	@Test func aDescriptorThatIsNotATerminalHasNoAnswer() {
		#expect(TerminalDirectory.settled(masterDescriptor: -1, slaveName: nil, shell: 1) == nil)
	}

	/// **The claim, in one pty.** A shell sitting at its prompt answers with
	/// where it is; the same shell running something answers nothing at all,
	/// even though the thing it is running has a working directory of its own
	/// and `current` would happily report it.
	@Test func aShellIsFollowedAtItsPromptAndNotWhileItRuns() async throws {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("settled-\(UUID().uuidString)")
		let elsewhere = base.appendingPathComponent("elsewhere")
		try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: base) }

		let terminal = PseudoTerminal()
		terminal.callbackQueue = DispatchQueue(label: "abydos.tests.pty.settled")
		try #require(terminal.start(
			executable: "/bin/sh", arguments: ["-i"],
			workingDirectory: base, environment: ["PS1": "$ "],
			rows: 24, columns: 80
		))
		defer { terminal.terminate() }

		try until("the shell to reach its prompt") { terminal.settledDirectory() != nil }

		// Where it was started, because `cd` is a builtin and nothing has run.
		let atRest = terminal.settledDirectory()
		#expect(atRest?.resolvingSymlinksInPath().path == base.resolvingSymlinksInPath().path)

		// A command that does not finish. `current` answers about *it*; this
		// answers about nobody, which is the whole point.
		terminal.write(Data("sleep 30\n".utf8))
		try until("the shell to be running something") { terminal.settledDirectory() == nil }
		#expect(terminal.currentDirectory() != nil, "there is a foreground process to ask about")

		// And back, once it is over.
		terminal.write(Data([0x03]))  // ⌃C
		try until("the shell to come back to its prompt") { terminal.settledDirectory() != nil }

		// A `cd` at the prompt is followed, because the shell never leaves the
		// foreground to do one.
		terminal.write(Data("cd '\(elsewhere.path)'\n".utf8))
		try until("the cd to land") {
			terminal.settledDirectory()?.resolvingSymlinksInPath().path
				== elsewhere.resolvingSymlinksInPath().path
		}
	}
}
