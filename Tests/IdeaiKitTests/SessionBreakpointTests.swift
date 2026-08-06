import Foundation
import Testing
@testable import IdeaiKit

/// Breakpoints surviving a project being closed.
///
/// They did not: the session file held what was open, which terminal was where
/// and what the play button pointed at, and nothing about the gutter. A
/// breakpoint is a note about where to look, and looking takes more than one
/// sitting — closing a project to answer something else and coming back to a
/// swept gutter is what teaches people to keep line numbers in a scratch file.
struct SessionBreakpointTests {
	static func project() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("session-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	@Test func writesAndReadsThemBack() throws {
		let root = try Self.project()
		defer { try? FileManager.default.removeItem(at: root) }

		var stopping = Breakpoint(file: "/p/app/main.go", line: 42)
		stopping.condition = "id == \"lamarzocco\""
		stopping.hitCondition = "> 5"
		var disabled = Breakpoint(file: "/p/app/main.go", line: 7)
		disabled.isEnabled = false

		try SessionStore.write(
			ProjectSession(breakpoints: ["/p/app/main.go": [stopping, disabled]]),
			in: root
		)

		let read = try #require(SessionStore.read(in: root))
		let list = try #require(read.breakpoints["/p/app/main.go"])
		#expect(list.count == 2)

		// The condition comes back, which is the part that took thought.
		let restored = try #require(list.first { $0.line == 42 })
		#expect(restored.condition == "id == \"lamarzocco\"")
		#expect(restored.hitCondition == "> 5")
		#expect(restored.isEnabled)
		#expect(list.first { $0.line == 7 }?.isEnabled == false)
	}

	/// Whether a line can be stopped on is a fact about a running program, and
	/// nothing is running when a project is opened. Restored breakpoints are
	/// unverified, so the gutter draws them hollow until an adapter says
	/// otherwise — a filled marker where execution can never stop is a lie.
	@Test func comesBackUnverified() throws {
		let root = try Self.project()
		defer { try? FileManager.default.removeItem(at: root) }

		var verified = Breakpoint(file: "/p/main.go", line: 3)
		verified.isVerified = true
		try SessionStore.write(ProjectSession(breakpoints: ["/p/main.go": [verified]]), in: root)

		#expect(SessionStore.read(in: root)?.breakpoints["/p/main.go"]?.first?.isVerified == false)
	}

	/// A session that is only breakpoints is still a session worth keeping:
	/// somebody who marked three lines and closed the window has done work.
	@Test func breakpointsAloneAreWorthAFile() throws {
		let root = try Self.project()
		defer { try? FileManager.default.removeItem(at: root) }

		let session = ProjectSession(breakpoints: ["/p/main.go": [Breakpoint(file: "/p/main.go", line: 1)]])
		#expect(!session.isEmpty)
		try SessionStore.write(session, in: root)
		#expect(SessionStore.read(in: root)?.breakpoints.isEmpty == false)
	}

	/// Written in a fixed order, so a file that gains and loses a breakpoint
	/// does not rewrite itself differently each time and turn into a diff.
	@Test func writesThemInAStableOrder() throws {
		let root = try Self.project()
		defer { try? FileManager.default.removeItem(at: root) }

		let session = ProjectSession(breakpoints: [
			"/p/b.go": [Breakpoint(file: "/p/b.go", line: 2)],
			"/p/a.go": [Breakpoint(file: "/p/a.go", line: 9), Breakpoint(file: "/p/a.go", line: 4)],
		])
		try SessionStore.write(session, in: root)
		let first = try String(contentsOf: IdeaiFolder.sessionFile(in: root), encoding: .utf8)

		try SessionStore.write(session, in: root)
		let second = try String(contentsOf: IdeaiFolder.sessionFile(in: root), encoding: .utf8)
		#expect(first == second)

		// a.go before b.go, and line 4 before line 9.
		let aFirst = try #require(first.range(of: "a.go"))
		let bFirst = try #require(first.range(of: "b.go"))
		#expect(aFirst.lowerBound < bFirst.lowerBound)
		#expect(try #require(first.range(of: "\"line\" : 4")).lowerBound
			< #require(first.range(of: "\"line\" : 9")).lowerBound)
	}

	@Test func aFileWithoutBreakpointsLeavesNothingBehind() throws {
		let root = try Self.project()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(ProjectSession(files: [.init(path: "/p/main.go")]), in: root)
		let text = try String(contentsOf: IdeaiFolder.sessionFile(in: root), encoding: .utf8)
		#expect(!text.contains("breakpoints"))
	}
}

/// Handing a set of breakpoints to a session that is about to start.
struct BreakpointAdoptionTests {
	/// The one that switched itself back on. A session was seeded by replaying
	/// each breakpoint as a toggle, and `toggleBreakpoint` builds a fresh one —
	/// which is enabled. So a breakpoint somebody had deliberately switched off
	/// came back on the moment they pressed Debug, was sent to the adapter, and
	/// stopped there.
	@Test func keepsABreakpointThatWasSwitchedOff() {
		let session = DebugSession(projectRoot: URL(fileURLWithPath: "/p"))

		var off = Breakpoint(file: "/p/main.go", line: 12)
		off.isEnabled = false
		var conditional = Breakpoint(file: "/p/main.go", line: 40)
		conditional.condition = "i > 5"
		conditional.hitCondition = "> 3"
		conditional.logMessage = "i is {i}"

		session.adopt(["/p/main.go": [conditional, off]])

		let list = session.breakpoints(inFile: "/p/main.go")
		#expect(list.map(\.line) == [12, 40])
		#expect(list.first { $0.line == 12 }?.isEnabled == false)

		// Everything else a breakpoint carries survives too — the conditions
		// were replayed before, but only because a second call put them back.
		let kept = list.first { $0.line == 40 }
		#expect(kept?.condition == "i > 5")
		#expect(kept?.hitCondition == "> 3")
		#expect(kept?.logMessage == "i is {i}")
	}

	/// Nothing is bound before anything runs, whatever the file said.
	@Test func adoptsNothingAsVerified() {
		let session = DebugSession(projectRoot: URL(fileURLWithPath: "/p"))
		var verified = Breakpoint(file: "/p/main.go", line: 3)
		verified.isVerified = true

		session.adopt(["/p/main.go": [verified]])
		#expect(session.breakpoints(inFile: "/p/main.go").first?.isVerified == false)
	}
}
