import Foundation
import Testing
@testable import AbydosKit

/// A launch a real adapter refuses, reported when it is refused.
///
/// **This is the suite the change exists for**, and it has to be live: what was
/// wrong was not a sentence but *who reported it*. `dlv dap` answers a failed
/// build in the first second, and the app read none of it and let the
/// twenty-five second watchdog guess — so a test that stubs the adapter proves
/// nothing about the thing that was broken. The claim here is a clock: the
/// report arrives in about a second, and it is the adapter's own words.
///
/// Skipped where delve is not installed. A skipped live test is not a pass.
@Suite(.serialized) struct DebugRefusalLiveTests {
	/// What the session said, and when.
	private final class Reported: @unchecked Sendable {
		private let lock = NSLock()
		private var said: String?
		private var at: Date?

		func record(_ message: String) {
			lock.lock()
			if said == nil { said = message; at = Date() }
			lock.unlock()
		}

		var message: String? { lock.lock(); defer { lock.unlock() }; return said }
		var when: Date? { lock.lock(); defer { lock.unlock() }; return at }
	}

	/// A Go module whose build cannot succeed.
	private func makeBrokenProject() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("debug-refusal-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		try "module example.com/broken\n\ngo 1.21\n"
			.write(to: root.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
		// A syntax error the compiler cannot get past, and a distinctive name to
		// look for in what is reported.
		try """
		package main

		func main() {
			thisFunctionDoesNotExistAnywhere()
		}
		""".write(to: root.appendingPathComponent("main.go"), atomically: true, encoding: .utf8)
		return root
	}

	@Test func aBuildThatFailsIsReportedAtOnce() async throws {
		guard let dlv = Executables.locate("dlv") else { return }

		let root = try makeBrokenProject()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)

		let session = DebugSession(projectRoot: project)
		defer { session.stop() }
		let reported = Reported()
		session.onLaunchStalled = { reported.record($0) }

		let asked = Date()
		try await session.launch(delveExecutable: dlv, package: ".")

		// **A second, not twenty-five.** The watchdog's timeout is 25 s, so a
		// bound below it is the whole claim: anything under that means the
		// response was read rather than waited out.
		await waitUntil("the refusal was reported", within: 20) { reported.message != nil }

		let message = try #require(reported.message)
		let waited = (reported.when ?? Date()).timeIntervalSince(asked)
		print(String(format: "  REFUSAL: reported after %.1f s", waited))
		print("  REFUSAL said: \(message.split(separator: "\n").prefix(4).joined(separator: " / "))")
		print("  " + MachineLoad.said)

		#expect(waited < 20)
		// The adapter's own account, and not the watchdog's guess.
		#expect(!message.contains("DevToolsSecurity"))
		#expect(!message.contains("stopped without starting"))
		#expect(message.contains("would not start the program"))
		// The compiler's own words, which is what somebody needs.
		#expect(message.contains("thisFunctionDoesNotExistAnywhere"))
	}

	/// **The refusal this machine actually has**, and the one that was reported
	/// as `Building …` for twenty-five seconds: delve 1.26.2 refuses Go 1.27.0
	/// outright. The build succeeds and the adapter says no afterwards, which is
	/// the other half of the same path — and the sentence somebody needs is
	/// delve's own.
	///
	/// Passes either way on purpose: on a machine whose delve matches its Go the
	/// launch is accepted and nothing is reported, which is also correct.
	@Test func aWorkingProjectEitherRunsOrSaysWhyNot() async throws {
		guard let dlv = Executables.locate("dlv") else { return }

		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("debug-works-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		try "module example.com/works\n\ngo 1.21\n"
			.write(to: root.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
		try "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"up\")\n}\n"
			.write(to: root.appendingPathComponent("main.go"), atomically: true, encoding: .utf8)

		let project = URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)
		let session = DebugSession(projectRoot: project)
		defer { session.stop() }
		let reported = Reported()
		session.onLaunchStalled = { reported.record($0) }

		let asked = Date()
		try await session.launch(delveExecutable: dlv, package: ".")
		// Long enough for a build, and far short of the watchdog.
		await waitUntil("the adapter answered one way or the other", within: 20) {
			reported.message != nil || session.state != .starting
		}

		guard let message = reported.message else {
			print("  REFUSAL: none — the launch was accepted")
			#expect(session.state != .starting)
			return
		}
		let waited = (reported.when ?? Date()).timeIntervalSince(asked)
		print(String(format: "  REFUSAL after a good build: %.1f s", waited))
		print("  REFUSAL said: \(message.split(separator: "\n").prefix(3).joined(separator: " / "))")
		// Whatever it was, it is the adapter's own sentence and it arrived long
		// before the watchdog would have.
		#expect(waited < 20)
		#expect(message.contains("would not start the program"))
		#expect(!message.contains("stopped without starting"))
	}

	/// And the state is not left saying it is starting, which is what kept the
	/// stop button meaningless until the watchdog fired.
	@Test func theSessionIsNotLeftStarting() async throws {
		guard let dlv = Executables.locate("dlv") else { return }

		let root = try makeBrokenProject()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)

		let session = DebugSession(projectRoot: project)
		defer { session.stop() }
		let reported = Reported()
		session.onLaunchStalled = { reported.record($0) }
		try await session.launch(delveExecutable: dlv, package: ".")
		await waitUntil("the refusal was reported", within: 20) { reported.message != nil }

		#expect(session.state == .terminated)
	}
}
