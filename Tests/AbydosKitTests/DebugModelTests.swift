import Foundation
import Testing
@testable import AbydosKit

/// Breakpoints that do more than stop every time.
struct BreakpointOptionTests {
	@Test func isOrdinaryUntilGivenSomethingToDo() {
		let plain = Breakpoint(file: "/a.go", line: 10)
		#expect(!plain.isConditional)
		#expect(plain.wireFormat as? [String: Int] == ["line": 10])
	}

	@Test func carriesAConditionOnTheWire() {
		let breakpoint = Breakpoint(file: "/a.go", line: 10, condition: "i > 5")
		#expect(breakpoint.isConditional)
		#expect(breakpoint.wireFormat["condition"] as? String == "i > 5")
		#expect(breakpoint.wireFormat["line"] as? Int == 10)
	}

	@Test func carriesAHitCountAndALogMessage() {
		let counted = Breakpoint(file: "/a.go", line: 3, hitCondition: "> 5")
		#expect(counted.wireFormat["hitCondition"] as? String == "> 5")

		let logging = Breakpoint(file: "/a.go", line: 3, logMessage: "i is {i}")
		#expect(logging.wireFormat["logMessage"] as? String == "i is {i}")
		#expect(logging.isConditional)
	}

	/// An empty string is not a condition; it is somebody clearing one.
	@Test func treatsEmptyOptionsAsAbsent() {
		let breakpoint = Breakpoint(file: "/a.go", line: 1, condition: "", hitCondition: "", logMessage: "")
		#expect(!breakpoint.isConditional)
		#expect(breakpoint.wireFormat["condition"] == nil)
		#expect(breakpoint.wireFormat["hitCondition"] == nil)
		#expect(breakpoint.wireFormat["logMessage"] == nil)
	}
}

/// Setting and clearing breakpoint options through the session.
@MainActor
struct BreakpointEditingTests {
	private func makeSession() -> DebugSession {
		DebugSession(projectRoot: URL(fileURLWithPath: NSTemporaryDirectory()))
	}

	@Test func setsAndClearsACondition() {
		let session = makeSession()
		let file = NSTemporaryDirectory() + "a.go"

		session.toggleBreakpoint(file: file, line: 12)
		#expect(session.breakpoint(file: file, line: 12)?.isConditional == false)

		session.setBreakpointOptions(
			file: file, line: 12, condition: "n == 3", hitCondition: nil, logMessage: nil
		)
		#expect(session.breakpoint(file: file, line: 12)?.condition == "n == 3")
		#expect(session.breakpoint(file: file, line: 12)?.isConditional == true)

		session.setBreakpointOptions(
			file: file, line: 12, condition: nil, hitCondition: nil, logMessage: nil
		)
		#expect(session.breakpoint(file: file, line: 12)?.isConditional == false)
	}

	/// Setting options on a line with no breakpoint does nothing rather than
	/// inventing one.
	@Test func ignoresALineWithNoBreakpoint() {
		let session = makeSession()
		let file = NSTemporaryDirectory() + "a.go"
		session.setBreakpointOptions(
			file: file, line: 99, condition: "x", hitCondition: nil, logMessage: nil
		)
		#expect(session.breakpoint(file: file, line: 99) == nil)
	}

	/// However the path is spelled, it is the same breakpoint.
	///
	/// A real file, because resolving a path is `realpath`, and `realpath`
	/// cannot resolve what is not there — which is the whole reason breakpoints
	/// keyed one way never matched the debugger's spelling of the other.
	@Test func findsABreakpointHoweverThePathIsSpelled() throws {
		let session = makeSession()
		let file = URL(fileURLWithPath: "/tmp").appendingPathComponent("bp-\(UUID().uuidString).go")
		try "package main\n".write(to: file, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: file) }

		session.toggleBreakpoint(file: "/tmp/" + file.lastPathComponent, line: 5)
		#expect(session.breakpoint(file: "/private/tmp/" + file.lastPathComponent, line: 5) != nil)
	}
}

/// Watch expressions.
@MainActor
struct WatchExpressionTests {
	private func makeSession() -> DebugSession {
		DebugSession(projectRoot: URL(fileURLWithPath: NSTemporaryDirectory()))
	}

	@Test func keepsWhatWasAddedInOrder() {
		let session = makeSession()
		session.addWatch("count")
		session.addWatch("items[0]")
		#expect(session.watches.map(\.expression) == ["count", "items[0]"])
	}

	@Test func ignoresAnEmptyExpression() {
		let session = makeSession()
		session.addWatch("   ")
		session.addWatch("")
		#expect(session.watches.isEmpty)
	}

	@Test func trimsWhatWasTyped() {
		let session = makeSession()
		session.addWatch("  total  ")
		#expect(session.watches.first?.expression == "total")
	}

	@Test func removesOneAndAll() {
		let session = makeSession()
		session.addWatch("a")
		session.addWatch("b")
		let first = session.watches[0].id

		session.removeWatch(id: first)
		#expect(session.watches.map(\.expression) == ["b"])

		session.removeAllWatches()
		#expect(session.watches.isEmpty)
	}

	/// With nothing running there is no frame, so a watch has no value rather
	/// than a stale one.
	@Test func clearsValuesWhenThereIsNoFrame() async {
		let session = makeSession()
		session.addWatch("total")
		await session.refreshWatches()
		#expect(session.watches.first?.value == nil)
		#expect(session.watches.first?.failed == false)
	}
}

/// How a program ended.
@MainActor
struct ExitCodeTests {
	private func makeSession() -> DebugSession {
		DebugSession(projectRoot: URL(fileURLWithPath: NSTemporaryDirectory()))
	}

	/// Delve never sends an `exited` event; it says it in a sentence, which is
	/// the same place VS Code reads it from.
	@Test func readsAStatusOutOfTheAdaptersOwnWords() {
		let session = makeSession()
		session.noteExitCode(inOutput: "Process 4242 has exited with status 3\n")
		#expect(session.exitCode == 3)
	}

	@Test func readsAZeroAndANegative() {
		let clean = makeSession()
		clean.noteExitCode(inOutput: "Process 1 has exited with status 0\n")
		#expect(clean.exitCode == 0)

		let signalled = makeSession()
		signalled.noteExitCode(inOutput: "Process 1 has exited with status -1\n")
		#expect(signalled.exitCode == -1)
	}

	/// An adapter that reports it properly is believed over anything found in
	/// prose, so the first answer stands.
	@Test func doesNotOverwriteWhatWasAlreadyKnown() {
		let session = makeSession()
		session.noteExitCode(inOutput: "Process 1 has exited with status 0\n")
		session.noteExitCode(inOutput: "Process 1 has exited with status 7\n")
		#expect(session.exitCode == 0)
	}

	@Test func ignoresOutputThatSaysNothingAboutExiting() {
		let session = makeSession()
		session.noteExitCode(inOutput: "Building /tmp/app\n")
		session.noteExitCode(inOutput: "has exited with status banana\n")
		#expect(session.exitCode == nil)
	}
}
