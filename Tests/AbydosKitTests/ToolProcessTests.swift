import Foundation
import Testing
@testable import AbydosKit

/// Ending what this app started, and not starting an unbounded number of it.
///
/// Written after eleven `container run` processes were found on a machine, the
/// oldest a day old, left by app runs that had ended — and with enough of them
/// there the container runtime's own service stopped answering, so everything
/// started afterwards hung and left another one behind.
struct ToolProcessTests {
	/// A program that will not end on its own.
	private func sleeper() -> Process {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = ["-c", "sleep 120"]
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		process.standardInput = FileHandle.nullDevice
		return process
	}

	@Test func everythingItHoldsIsEndedTogether() throws {
		let processes = ToolProcesses()
		var started: [Process] = []
		for _ in 0..<3 {
			let process = sleeper()
			try process.run()
			processes.adopt(process)
			started.append(process)
		}
		#expect(processes.count == 3)

		processes.terminateAll()
		// Ended, and let go of: what is dead is not still being counted.
		for process in started {
			#expect(!process.isRunning)
		}
		#expect(processes.count == 0)
	}

	/// The runaway backstop. Nothing legitimate comes near it — one pane draws
	/// one diagram at a time — so reaching it means the ones already running are
	/// not finishing, and starting another would only make that worse.
	@Test func pastTheCapItSaysNo() throws {
		let processes = ToolProcesses()
		defer { processes.terminateAll() }

		var refusals = 0
		for _ in 0..<(ToolProcesses.limit + 3) {
			let process = sleeper()
			try process.run()
			if !processes.adopt(process) {
				refusals += 1
				process.terminate()
			}
		}
		#expect(processes.count == ToolProcesses.limit)
		#expect(refusals == 3)
	}

	/// A language server is not subject to the cap: it is started once and kept,
	/// and refusing one because a dozen renders are stuck answers the wrong
	/// question. It is still ended with the app, which is the point.
	@Test func aTrackedProcessIsKeptEvenPastTheCap() throws {
		let processes = ToolProcesses()
		defer { processes.terminateAll() }

		for _ in 0..<ToolProcesses.limit {
			let process = sleeper()
			try process.run()
			processes.adopt(process)
		}
		let server = sleeper()
		try server.run()
		processes.track(server)

		#expect(processes.count == ToolProcesses.limit + 1)
		processes.terminateAll()
		#expect(!server.isRunning)
	}

	/// One that ended on its own is not still counted against the cap.
	@Test func whatHasFinishedIsNotHeldAgainstTheLimit() throws {
		let processes = ToolProcesses()
		let quick = Process()
		quick.executableURL = URL(fileURLWithPath: "/usr/bin/true")
		try quick.run()
		processes.adopt(quick)
		quick.waitUntilExit()
		#expect(processes.count == 0)
	}
}

/// A runtime that stops answering is reported once, not waited on for ever.
struct SilentRuntimeTests {
	/// A stand-in for a runtime whose service is down: it accepts the command
	/// and then waits, which is exactly what `container` does with no
	/// apiserver running.
	private func silentRuntime() throws -> (ContainerRuntime, URL) {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("silent-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let script = directory.appendingPathComponent("never-answers")
		try Data("#!/bin/sh\nsleep 120\n".utf8).write(to: script)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755], ofItemAtPath: script.path
		)
		return (.docker(script.path), directory)
	}

	@Test func aRuntimeThatNeverAnswersIsGivenUpOnAndSaidOnce() async throws {
		let (runtime, directory) = try silentRuntime()
		defer { try? FileManager.default.removeItem(at: directory) }

		// A second rather than the twenty the app gives it: what is being
		// tested is that there is a deadline and what happens at it, not how
		// long it is.
		let store = ContainerImageStore(inspectDeadline: 1)
		let began = Date()
		let first = await store.ensure("a/b", using: runtime)
		let waited = Date().timeIntervalSince(began)

		guard case let .failed(reason) = first else {
			Issue.record("expected a failure, got \(first)")
			return
		}
		#expect(reason.contains("did not answer"))
		#expect(waited >= 1)
		#expect(waited < 10, "the deadline, not the program, is what ended it")

		// And the second asker is told the same thing without waiting again.
		// This is the whole point: every pane and every server asks, and each
		// wait is another process left holding whatever the runtime is stuck on.
		let secondBegan = Date()
        let second = await store.ensure("c/d", using: runtime)
		#expect(Date().timeIntervalSince(secondBegan) < 1)
		#expect(second == first)
	}
}
