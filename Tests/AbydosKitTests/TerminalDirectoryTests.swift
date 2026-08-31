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

/// Following the shell's own directory, whatever runs in front of it.
///
/// **A window follows where somebody walked, not where a script went.** The
/// foreground process's working directory is the command's while one runs, and
/// a command that changes directory — `brew` does, several times — dragged the
/// window through every one of them. The first fix answered nothing while
/// anything ran, which deselected the project a script was started from and
/// made a tab holding a Claude session impossible to follow into at all. The
/// shell's own directory is all three answers at once: a script never moves
/// it, a typed `cd` always does, and it is always there to read.
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
	/// where it is; the same shell running something *still answers with its
	/// own place* — where the command was started from — however far the
	/// command wanders; and a typed `cd` moves the answer the moment it lands.
	@Test func aShellAnswersWithItsOwnPlaceWhateverItRuns() async throws {
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

		// Until it answers with where it was *started*, not merely answers: a
		// freshly forked shell is read between the fork and its `chdir` for a
		// moment, and under load the first read can land in that moment.
		try until("the shell to reach the directory it was started in") {
			terminal.settledDirectory()?.resolvingSymlinksInPath().path
				== base.resolvingSymlinksInPath().path
		}

		// A command that does not finish, run from a subdirectory the command
		// itself then leaves. The shell's own answer holds still at the place
		// the command was started from: the project a script belongs to stays
		// selected for as long as it runs — and a pane running something
		// long-lived, a Claude session say, can still be followed into.
		terminal.write(Data("cd '\(elsewhere.path)' && /bin/sh -c 'cd /; sleep 30'\n".utf8))
		try until("the command to be running somewhere else") {
			terminal.currentDirectory()?.path == "/"
		}
		#expect(
			terminal.settledDirectory()?.resolvingSymlinksInPath().path
				== elsewhere.resolvingSymlinksInPath().path,
			"the shell's own place, not the command's wandering"
		)

		// And back at the prompt, a `cd` is followed at once.
		terminal.write(Data([0x03]))  // ⌃C
		terminal.write(Data("cd '\(base.path)'\n".utf8))
		try until("the cd to land") {
			terminal.settledDirectory()?.resolvingSymlinksInPath().path
				== base.resolvingSymlinksInPath().path
		}
	}
}
