import Foundation
import Testing
@testable import AbydosKit

/// Ending a container, rather than ending the process that started one.
///
/// The distinction is the whole of 0406: `kill -9` on a `docker run` leaves the
/// container running and `--rm` never fires, so everything that ended processes
/// was ending the wrong thing. A container is ended by asking the runtime to
/// remove it, which means it has to have a name.
struct ToolContainerNameTests {
	/// Everything this app starts is `abydos-…`, so anything found later is
	/// obviously ours and obviously safe to remove.
	@Test func everyNameSaysWhoseItIsAndWhoStartedIt() {
		let name = ToolContainers.mint("plantuml")
		#expect(name.hasPrefix("abydos-"))
		#expect(ToolContainers.isOurs(name))
		#expect(name.contains("plantuml"))
		// The process id, which is what makes a container found tomorrow
		// answerable: is whatever started this still here?
		#expect(ToolContainers.owner(of: name) == ProcessInfo.processInfo.processIdentifier)
		// And no two alike, or the second one fails with "name already in use".
		#expect(ToolContainers.mint("plantuml") != name)
	}

	/// A tool key is not always a container name: docker's are a narrower
	/// alphabet than a settings file's keys.
	@Test func aNameIsMadeOfWhatDockerAccepts() {
		let name = ToolContainers.mint("typescript-language-server/tsserver")
		#expect(name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
		#expect(!name.contains("--"))
	}

	/// Somebody else's container is not ours to remove, and one of ours whose
	/// shape is unfamiliar — written by an older version — reads as unowned,
	/// which is the same answer as a dead owner.
	@Test func onlyOurOwnNamesAreUnderstood() {
		#expect(!ToolContainers.isOurs("laughing_ptolemy"))
		#expect(ToolContainers.owner(of: "laughing_ptolemy") == nil)
		#expect(ToolContainers.owner(of: "abydos-plantuml") == nil)
		#expect(ToolContainers.owner(of: "abydos-plantuml-4321-7") == 4321)
	}

	/// The name goes on the command line that starts it, before the image.
	@Test func theInvocationCarriesTheName() {
		let run = ToolContainer(image: "plantuml/plantuml", name: "abydos-plantuml-1-1")
			.invocation(using: .docker("/usr/bin/docker"), arguments: ["-pipe"])
		#expect(run.arguments == [
			"run", "--rm", "-i", "--name", "abydos-plantuml-1-1", "plantuml/plantuml", "-pipe",
		])
		// And nothing is named that was not given a name — a command line shown
		// to somebody should not invent one.
		#expect(!ToolContainer(image: "plantuml/plantuml")
			.invocation(using: .docker("/usr/bin/docker")).arguments.contains("--name"))
	}

	/// Removal is by name and forced: what is being removed is usually the thing
	/// this app has just given up waiting for, and asking it politely to finish
	/// means waiting for the very thing that hung.
	@Test func removalIsByNameAndForced() {
		let docker = ToolContainers.removal(
			of: ["abydos-a", "abydos-b"], using: .docker("/usr/bin/docker")
		)
		#expect(docker.executable == "/usr/bin/docker")
		#expect(docker.arguments == ["rm", "-f", "abydos-a", "abydos-b"])
	}

	/// Docker's listing says exactly what is wanted. Apple's is not guessed at:
	/// its output format could not be checked while its service was wedged, and
	/// a sweep that parses a format nobody has seen removes either nothing or
	/// the wrong thing.
	@Test func theSweepOnlyReadsAListItHasSeen() {
		let docker = try? #require(ToolContainers.listing(using: .docker("/usr/bin/docker")))
		#expect(docker?.arguments.contains("{{.Names}}") == true)
		#expect(docker?.arguments.contains("name=abydos-") == true)
		#expect(ToolContainers.listing(using: .apple("/usr/local/bin/container")) == nil)
	}

	/// What a previous run left is what nothing is running any more. Two copies
	/// of this app open at once therefore leave each other's containers alone.
	@Test func staleMeansItsStarterIsGone() {
		let names = [
			"abydos-plantuml-100-1",   // started by something still running
			"abydos-plantuml-200-4",   // started by something that has gone
			"abydos-lsp-gopls",        // ours, from a version that named them differently
			"laughing_ptolemy",        // not ours at all
		]
		let stale = ToolContainers.stale(among: names, isAlive: { $0 == 100 })
		#expect(stale == ["abydos-plantuml-200-4", "abydos-lsp-gopls"])
	}

	/// A language server started from an image is a container with a name, so
	/// stopping the server can stop the container as well.
	@Test func aLanguageServerNamesItsContainer() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		try JavaTestDirectory.write(
			"module example.com/probe\n\ngo 1.24\n", to: root.appendingPathComponent("go.mod")
		)

		let resolved = try #require(LanguageServers.resolve(
			languageId: "go", project: root,
			image: "abydos/gopls:dev", runtime: .docker("/usr/bin/docker")
		))
		let container = try #require(resolved.launch.container)
		#expect(ToolContainers.isOurs(container.name))
		#expect(container.name.contains("gopls"))
		#expect(resolved.launch.invocation.arguments.contains("--name"))
		// Still nothing after the image: the server is the entry point.
		#expect(resolved.launch.invocation.arguments.last == "abydos/gopls:dev")
	}

	/// And so does a diagram, which is where the eleven came from.
	@Test func aDiagramNamesItsContainer() {
		let tool = PlantUML.Tool.image(
			ToolContainer(image: "plantuml/plantuml"), .docker("/usr/bin/docker")
		)
		let run = PlantUML.invocation(for: tool, name: "abydos-plantuml-9-2")
		#expect(run.arguments == [
			"run", "--rm", "-i", "--name", "abydos-plantuml-9-2",
			"plantuml/plantuml", "-pipe", "-tpng", "-charset", "UTF-8",
		])
	}
}

/// Which runtime, now that a container has to be removable again.
struct ContainerRuntimePreferenceTests {
	/// Docker first when nothing is asked for — a reversal, and the reason is
	/// removal: it is the runtime this app can prove it can clean up after.
	@Test func automaticPrefersTheOneWhoseCleanupIsProven() {
		let found = ContainerRuntime.discover(locate: { name in
			["container": "/usr/local/bin/container", "docker": "/usr/bin/docker"][name]
		})
		#expect(found == .docker("/usr/bin/docker"))
	}

	/// Apple's is still found when it is the only one here: an app that draws no
	/// diagrams would be a worse answer than one that draws them and says what
	/// it cannot promise.
	@Test func appleIsStillFoundWhenItIsAllThereIs() {
		let found = ContainerRuntime.discover(
			locate: { $0 == "container" ? "/usr/local/bin/container" : nil }
		)
		#expect(found == .apple("/usr/local/bin/container"))
		// And it is not silent about it.
		let caveat = found?.caveat
		#expect(caveat?.contains("removing a container by name") == true)
		#expect(ContainerRuntime.docker("/usr/bin/docker").caveat == nil)
	}

	/// The case that stays: somebody who asks for Apple's gets Apple's.
	@Test func aStatedPreferenceIsStillHonoured() {
		let both: (String) -> String? = { name in
			["container": "/usr/local/bin/container", "docker": "/usr/bin/docker"][name]
		}
		#expect(ContainerRuntime.discover(preference: .apple, locate: both)
			== .apple("/usr/local/bin/container"))
		#expect(ContainerRuntime.discover(preference: .docker, locate: both)
			== .docker("/usr/bin/docker"))
	}
}

/// Against a real runtime: that a container outlives the process which started
/// it, and that removing it by name is what actually ends it.
///
/// Skipped unless docker and a small image are both here, the way the other
/// live tests are skipped without their server.
struct ToolContainerLiveTests {
	static let image = "alpine:3"

	/// Docker, and only docker: the removal verb is proven there, and this test
	/// is the proof. See 0406's decision.
	private var runtime: ContainerRuntime? {
		guard let docker = ContainerRuntime.discover(preference: .docker) else { return nil }
		let inspect = RuntimeCommand.run(
			ContainerImages.inspect(Self.image, using: docker), deadline: 10
		)
		return inspect.succeeded ? docker : nil
	}

	private func exists(_ name: String, using runtime: ContainerRuntime) -> Bool {
		RuntimeCommand.run(
			(runtime.path, ["inspect", "--type", "container", name]), deadline: 10
		).succeeded
	}

	/// Waits for something to become true, rather than sleeping a guessed
	/// amount: starting a container is half a second on a quiet machine and
	/// several on a busy one.
	private func waitFor(_ seconds: TimeInterval, until condition: () -> Bool) -> Bool {
		let deadline = Date().addingTimeInterval(seconds)
		while Date() < deadline {
			if condition() { return true }
			Thread.sleep(forTimeInterval: 0.2)
		}
		return condition()
	}

	@Test func killingTheProcessLeavesTheContainerAndRemovingItByNameDoesNot() throws {
		guard let runtime else { return }
		let name = ToolContainers.mint("probe-outlives")
		let containers = ToolContainers()
		defer {
			// Whatever happened above, nothing of this test's is left running.
			_ = RuntimeCommand.run(
				ToolContainers.removal(of: [name], using: runtime), deadline: 20
			)
		}

		let run = ToolContainer(image: Self.image, command: ["sleep", "120"], name: name)
			.invocation(using: runtime)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: run.executable)
		process.arguments = run.arguments
		// Nowhere, all three. A pipe nobody drains is how a subprocess capture
		// hangs, and a `Pipe()` on standard input is worse — the child waits for
		// an end that never comes.
		process.standardInput = FileHandle.nullDevice
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		containers.register(name, runtime: runtime)
		try process.run()

		#expect(waitFor(60) { exists(name, using: runtime) }, "the container never started")

		// The bug, demonstrated: the process is killed outright and the
		// container carries on. `--rm` only fires for a container that ends of
		// its own accord.
		kill(process.processIdentifier, SIGKILL)
		process.waitUntilExit()
		Thread.sleep(forTimeInterval: 1)
		#expect(exists(name, using: runtime), "a killed `run` used to be the whole story")

		// And the fix: asked by name, the runtime removes it.
		containers.release(name)
		#expect(!exists(name, using: runtime))
		#expect(containers.names.isEmpty)
	}

	/// What an app that was killed outright leaves behind, cleared by the next
	/// one to start.
	@Test func theSweepTakesWhatAnEarlierRunLeft() throws {
		guard let runtime else { return }
		// A name of ours whose owner is a process id this test declares dead.
		// Only that one: every other `abydos-…` on this machine belongs to
		// somebody whose app may well be running, and a sweep that took those
		// would be a worse bug than the one being fixed.
		// Unique per run, both of them. Two suites running at once — two agents,
		// or a suite beside a `make test` — otherwise pick the same dead pid and
		// the same container name, and each sweeps the other's container out
		// from under it. That is not a fault in the sweep; it is this test
		// having claimed a name it does not own.
		let dead = pid_t(400_000 + Int.random(in: 1 ... 99_999))
		let name = "abydos-probe-sweep-\(dead)-1"
		defer {
			_ = RuntimeCommand.run(
				ToolContainers.removal(of: [name], using: runtime), deadline: 20
			)
		}

		let started = RuntimeCommand.run(
			(runtime.path, ["run", "-d", "--name", name, Self.image, "sleep", "120"]),
			deadline: 60
		)
		#expect(started.succeeded, "could not start the container: \(started.output)")
		#expect(exists(name, using: runtime))

		let removed = ToolContainers().sweep(using: runtime, isAlive: { $0 != dead })
		// Contains rather than equals: every other `abydos-…` is reported alive
		// by the closure above and so must be left alone, but a container this
		// test did not make is not this test's to assert about.
		#expect(removed.contains(name))
		#expect(!exists(name, using: runtime))
	}
}
