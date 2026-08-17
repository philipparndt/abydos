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
	@Test func bothKindsAreEndedWhenTheAppEnds() throws {
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
		for process in tools + servers {
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
		#expect(reason.contains("did not answer"))
		#expect(waited >= 1)
		// The claim is that the deadline ended it rather than the program, and
		// the only thing it has to be told apart from is the program's own
		// `sleep 120`. Stated against that, rather than against a number of its
		// own: a bound of ten seconds was failing at 12.3 on a loaded machine
		// while the deadline was working perfectly, which is 0435 exactly.
		#expect(waited < 60, "the deadline, not the program's `sleep 120`, is what ended it")

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
