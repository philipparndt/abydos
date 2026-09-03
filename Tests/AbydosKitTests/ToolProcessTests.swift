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
			processes.adopt(process, as: "diagram render")
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

	/// The other half of the same promise, and the one 0538 could have broken:
	/// the long-lived processes live in a list of their own now so that they do
	/// not spend the cap, and a list of their own is exactly how something comes
	/// to be forgotten at the end. So: a full cap, servers as well, and after
	/// the app has gone nothing of either kind is left running.
	@Test func bothKindsAreEndedWhenTheAppEnds() async throws {
		let processes = ToolProcesses()
		defer { processes.terminateAll() }

		var tools: [Process] = []
		for _ in 0..<ToolProcesses.limit {
			let process = sleeper()
			try process.run()
			#expect(processes.adopt(process, as: "diagram render"))
			tools.append(process)
		}
		var servers: [Process] = []
		for _ in 0..<4 {
			let server = sleeper()
			try server.run()
			processes.track(server)
			servers.append(server)
		}
		#expect(processes.count == ToolProcesses.limit + 4)

		processes.terminateAll()
		// **Waited for, not read straight after.** `terminateAll` sends a
		// signal; the kernel decides when the process is gone and reaps it, and
		// under load that is not the same instant. Reading `isRunning` on the
		// next line asserted that the machine had already got round to it,
		// which is not what this test is about — it is about every process
		// being ended, and that is still true a moment later.
		for process in tools + servers {
			#expect(await process.hasStopped(), "still running after terminateAll")
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
			if !processes.adopt(process, as: "diagram render") {
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
			processes.adopt(process, as: "diagram render")
		}
		let server = sleeper()
		try server.run()
		processes.track(server)

		#expect(processes.count == ToolProcesses.limit + 1)
		processes.terminateAll()
		#expect(!server.isRunning)
	}

	/// 0538 itself: a session's servers went into the array the cap counted, so
	/// a project of a few languages spent the whole budget before any tool ran,
	/// and the first Cadova build of the day was refused with a sentence about
	/// container images. Twice the cap in servers, and a build still starts.
	@Test func aDozenServersDoNotRefuseARender() throws {
		let processes = ToolProcesses()
		defer { processes.terminateAll() }

		for _ in 0..<(ToolProcesses.limit * 2) {
			let server = sleeper()
			try server.run()
			processes.track(server)
		}
		#expect(processes.capped == 0)

		let build = sleeper()
		try build.run()
		#expect(processes.adopt(build, as: "Cadova build"))
	}

	/// One that ended on its own is not still counted against the cap.
	@Test func whatHasFinishedIsNotHeldAgainstTheLimit() throws {
		let processes = ToolProcesses()
		let quick = Process()
		quick.executableURL = URL(fileURLWithPath: "/usr/bin/true")
		try quick.run()
		processes.adopt(quick, as: "diagram render")
		quick.waitUntilExit()
		#expect(processes.count == 0)
	}
}

/// What a refusal says, which 0538 is as much about as the refusal itself.
///
/// The old sentence was written once and claimed three things — that the tools
/// came from images, that a container runtime was in the path, and that it had
/// stopped answering. For a Cadova preview's `swift run` all three are false,
/// and somebody read it and went to restart a runtime that could not have
/// helped.
struct TooManyMessageTests {
	private func sleeper() -> Process {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = ["-c", "sleep 120"]
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		process.standardInput = FileHandle.nullDevice
		return process
	}

	private func fill(
		_ processes: ToolProcesses, _ counts: [(what: String, fromImage: Bool, many: Int)]
	) throws {
		for kind in counts {
			for _ in 0..<kind.many {
				let process = sleeper()
				try process.run()
				processes.adopt(process, as: kind.what, fromImage: kind.fromImage)
			}
		}
	}

	@Test func itNamesWhatIsHoldingTheSlots() throws {
		let processes = ToolProcesses()
		defer { processes.terminateAll() }
		try fill(processes, [
			("Cadova build", false, 2),
			("diagram render", true, 9),
			("diagram export", true, 1),
		])

		let said = processes.tooManyMessage
		// Biggest group first: the thing to go and look at is the thing read
		// first, and the plural is only put on when there is more than one.
		#expect(said.contains("12 tools are already running"))
		#expect(said.contains("9 diagram renders, 2 Cadova builds and 1 diagram export"))
	}

	/// The claim the item is named for. Nothing here came from an image, so
	/// nothing in the sentence may say one did.
	@Test func aToolThatCameFromNoImageIsNotDescribedAsOne() throws {
		let processes = ToolProcesses()
		defer { processes.terminateAll() }
		try fill(processes, [("Cadova build", false, ToolProcesses.limit)])

		let said = processes.tooManyMessage
		#expect(said.contains("\(ToolProcesses.limit) Cadova builds"))
		#expect(!said.lowercased().contains("image"))
		#expect(!said.lowercased().contains("container"))
		#expect(!said.lowercased().contains("runtime"))
	}

	/// And where it *is* every one of them, the runtime is worth naming: that
	/// advice was right for the case it was written for, and is kept for it.
	@Test func whereEveryOneIsFromAnImageTheRuntimeIsNamed() throws {
		let processes = ToolProcesses()
		defer { processes.terminateAll() }
		try fill(processes, [("diagram render", true, ToolProcesses.limit)])

		let said = processes.tooManyMessage
		#expect(said.contains("container runtime has stopped answering"))
	}

	/// A mixture is not every one of them, and the runtime is not blamed for a
	/// cap a local build is holding a slot in.
	@Test func oneLocalToolIsEnoughToLeaveTheRuntimeOutOfIt() throws {
		let processes = ToolProcesses()
		defer { processes.terminateAll() }
		try fill(processes, [
			("diagram render", true, ToolProcesses.limit - 1),
			("Cadova build", false, 1),
		])

		#expect(!processes.tooManyMessage.lowercased().contains("runtime"))
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
		// **"did not answer" is the deadline's own words**, and the program
		// told to `sleep 120` has none: it never answers, so no other path
		// produces this reason. That is the classification, complete, with no
		// clock in it.
		#expect(reason.contains("did not answer"))
		// A lower bound is safe at any load — load only ever makes it later.
		#expect(waited >= 1)
		// The upper bound is gone. It was a midpoint of sixty seconds between
		// a one-second deadline and a two-minute sleep, guarded for load, and
		// it still went red at 97 seconds inside a full suite with the deadline
		// working perfectly — the guard reads a one-minute load average, and
		// the suite's own parallelism arrives after it has been asked. The
		// number is said instead, with the load beside it.
		print(String(
			format: "DEADLINE: the inspect gave up after %.1f s (asked for 1). %@",
			waited, MachineLoad.said
		))

		// And the second asker is told the same thing without waiting again.
		// This is the whole point: every pane and every server asks, and each
		// wait is another process left holding whatever the runtime is stuck on.
		let secondBegan = Date()
        let second = await store.ensure("c/d", using: runtime)
		// Against the first wait rather than against a second of its own, for the
		// same reason: what is being claimed is that this one did not wait, and
		// "did not wait" only means anything beside the one that did.
		#expect(Date().timeIntervalSince(secondBegan) < waited / 2)
		#expect(second == first)
	}
}


private extension Process {
	/// Whether this process has ended, waited for rather than assumed.
	///
	/// A signal is a request. The kernel ends the process and reaps it when it
	/// gets to it, and on a loaded machine that is measurably later than the
	/// line after the one that asked — which is where a test that reads
	/// `isRunning` immediately goes red for no fault of the code.
	///
	/// Generous on purpose: this is a hang detector, not a bound. See
	/// `Patience`.
	func hasStopped(within seconds: TimeInterval = Patience.seconds) async -> Bool {
		let deadline = Date().addingTimeInterval(seconds)
		while Date() < deadline {
			if !isRunning { return true }
			try? await Task.sleep(nanoseconds: 20_000_000)
		}
		return !isRunning
	}
}
