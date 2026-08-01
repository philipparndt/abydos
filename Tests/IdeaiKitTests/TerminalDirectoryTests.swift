import Foundation
import Testing
@testable import IdeaiKit

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
