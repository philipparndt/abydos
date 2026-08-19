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

	/// Several refreshes at once, which is the ordinary case rather than an
	/// exotic one: adding a watch starts a refresh, and so does every stop and
	/// every change of frame.
	///
	/// This crashed — a bad access inside `Array._makeMutableAndUnique`, from
	/// two threads writing into the same array — and it crashed the whole test
	/// process rather than failing a test, which is the sort of failure that
	/// gets blamed on the runner. It is a race, so passing once proves less than
	/// failing once does; twenty watches and eight refreshes is enough that it
	/// showed up reliably before the lock.
	@Test func refreshesFromEveryDirectionAtOnceLeaveTheListWhole() async {
		let session = makeSession()
		for index in 0..<20 { session.addWatch("total\(index)") }

		await withTaskGroup(of: Void.self) { group in
			for _ in 0..<8 {
				group.addTask { await session.refreshWatches() }
			}
		}
		#expect(session.watches.count == 20)
		#expect(session.watches.map(\.expression).first == "total0")
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

/// What a session leaves on screen once the program has gone.
///
/// The report: stop a Go service at a breakpoint and the goroutine list still
/// shows `* [Go 1] main.main (Thread 27497960)`. Driven against the real Delve
/// before this was written — `frames=0 scopes=0 threads=7` after the stop — so
/// these are claims about a fault that was measured, not one that was read.
@MainActor
struct EndOfSessionTests {
	private func makeSession() -> DebugSession {
		DebugSession(projectRoot: URL(fileURLWithPath: NSTemporaryDirectory()))
	}

	private func running(_ session: DebugSession) {
		session.fillForTesting(
			threads: [
				DebugThread(id: 1, name: "* [Go 1] main.main (Thread 27497960)"),
				DebugThread(id: 2, name: "[Go 2] runtime.gopark"),
			],
			frames: [StackFrame(id: 1000, name: "main.main", file: "/p/main.go", line: 40)],
			scopes: [Scope(name: "Locals", variablesReference: 1001)]
		)
	}

	/// **`threads` was cleared by nothing anywhere in the file.** The frames and
	/// the scopes were emptied on both paths and the goroutines were left, so
	/// the list belonged to a process that had ended.
	@Test func stoppingLeavesNothingOfTheProgram() {
		let session = makeSession()
		running(session)
		#expect(!session.threads.isEmpty)

		session.stop()

		#expect(session.threads.isEmpty)
		#expect(session.stackFrames.isEmpty)
		#expect(session.scopes.isEmpty)
		#expect(session.selectedThreadID == nil)
		#expect(session.state == .terminated)
	}

	/// The other path to the same place. Two paths that disagreed about what is
	/// left over is what put the clearing in one function.
	@Test func theAdaptersOwnEndingLeavesNothingEither() async {
		let session = makeSession()
		running(session)

		session.adapterSaidItEnded(body: [:])
		await Task.yield()

		#expect(session.threads.isEmpty)
		#expect(session.stackFrames.isEmpty)
		#expect(session.scopes.isEmpty)
	}

	/// The table is told, or it goes on drawing what it last had —
	/// `onThreadsChanged` is fired by `refreshThreads` and by nothing else.
	@Test func theThreadsTableIsToldTheListChanged() async {
		let session = makeSession()
		running(session)

		let told = Counter()
		session.onThreadsChanged = { told.bump() }
		session.stop()
		await Task.yield()

		#expect(told.count == 1)
	}

	/// A console that simply stops cannot be told from one that is waiting, and
	/// every other word in it is the adapter's.
	@Test func theConsoleIsToldTheSessionEnded() async {
		let session = makeSession()
		let said = Recorder()
		session.onOutput = { said.append($0) }

		session.stop()
		await Task.yield()

		#expect(said.all.contains { $0.contains("Finished") })
	}

	/// The words are the toolbar's: it says `Finished — exit code 0`, so this
	/// does. Two sentences for one fact is how somebody comes to believe they
	/// are two facts.
	@Test func theWordsMatchTheToolbars() async {
		let session = makeSession()
		let said = Recorder()
		session.onOutput = { said.append($0) }

		session.noteExitCode(inOutput: "Process 1 has exited with status 0\n")
		session.stop()
		await Task.yield()

		#expect(said.all.contains { $0.contains("Finished \u{2014} exit code 0") })
	}

	@Test func aNonZeroStatusIsAFailure() async {
		let session = makeSession()
		let said = Recorder()
		session.onOutput = { said.append($0) }

		session.noteExitCode(inOutput: "Process 1 has exited with status 3\n")
		session.stop()
		await Task.yield()

		#expect(said.all.contains { $0.contains("Failed \u{2014} exit code 3") })
	}

	/// **The line waits for the status rather than racing it.**
	///
	/// Driven against Delve: a program that reaches its own end produces
	/// `total 6`, then the ending, then `Process … has exited with status 0`.
	/// Written on the event, the console said "Finished" while the toolbar said
	/// "Finished — exit code 0" — and a console line cannot be taken back.
	@Test func theEndingWaitsForAStatusThatArrivesAfterTheEvent() async {
		let session = makeSession()
		let said = Recorder()
		session.onOutput = { said.append($0) }

		// The adapter says it is over and names no code, which is Delve.
		session.adapterSaidItEnded(body: [:])
		// The sentence arrives after, as it does on a real run.
		session.noteExitCode(inOutput: "Process 97912 has exited with status 0\n")
		await Task.yield()
		await Task.yield()

		#expect(session.exitCode == 0)
		// Not a bare "Finished" beside a toolbar that knows the code.
		#expect(said.all.contains { $0.contains("Finished \u{2014} exit code 0") })
		#expect(!said.all.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "[Finished]" })
	}

    /// Both paths can be travelled for one session — a stopped program often
    /// produces the event as well — and the line belongs there once.
	@Test func theEndIsAnnouncedExactlyOnce() async {
		let session = makeSession()
		let said = Recorder()
		session.onOutput = { said.append($0) }

		session.stop()
		session.adapterSaidItEnded(body: [:])
		session.adapterSaidItEnded(body: ["exitCode": 0])
		await Task.yield()

		#expect(said.all.filter { $0.contains("Finished") }.count == 1)
	}

	/// **The status arrives after the state does, and must still be shown.**
	///
	/// Delve reports it in prose on its way out, so on a user-initiated stop it
	/// lands after the session is already terminated — which is why
	/// `noteExitCode` publishes `.terminated` a second time. Killing the adapter
	/// before reading meant that never happened and the toolbar kept a bare
	/// "Finished"; keeping the stream open until `disconnect` is answered is
	/// what puts the code back.
	@Test func aStatusArrivingAfterTheStopStillReachesTheToolbar() async {
		let session = makeSession()
		running(session)

		let seen = Recorder()
		session.observeState { seen.append(String(describing: $0)) }

		session.stop()
		await Task.yield()
		#expect(session.exitCode == nil)

		// What Delve says on its way out, read because the stream was still open.
		session.noteExitCode(inOutput: "Process 51241 has exited with status 0\n")
		await Task.yield()

		#expect(session.exitCode == 0)
		// Published again, so anything showing the state asks for the code once
		// more. Without this the toolbar keeps the answer it had.
		#expect(seen.all.filter { $0.contains("terminated") }.count >= 1)
	}

	private final class Counter: @unchecked Sendable {
		private let lock = NSLock()
		private var value = 0
		var count: Int { lock.lock(); defer { lock.unlock() }; return value }
		func bump() { lock.lock(); value += 1; lock.unlock() }
	}

	private final class Recorder: @unchecked Sendable {
		private let lock = NSLock()
		private var items: [String] = []
		var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
		func append(_ text: String) { lock.lock(); items.append(text); lock.unlock() }
	}
}
