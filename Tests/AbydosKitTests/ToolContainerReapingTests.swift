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

		// And Apple's, which spells the same thing differently and is now proven
		// to do it — see `ToolContainerAppleLiveTests`.
		let apple = ToolContainers.removal(
			of: ["abydos-a", "abydos-b"], using: .apple("/usr/local/bin/container")
		)
		#expect(apple.executable == "/usr/local/bin/container")
		#expect(apple.arguments == ["rm", "--force", "abydos-a", "abydos-b"])
	}

	/// Both are asked for names and nothing else, so neither answer has to be
	/// read out of a table — and both are asked for the stopped ones too, which
	/// is most of what a crashed run leaves behind.
	@Test func theSweepAsksBothRuntimesForNamesAndNothingElse() throws {
		let docker = try #require(ToolContainers.listing(using: .docker("/usr/bin/docker")))
		#expect(docker.arguments.contains("{{.Names}}"))
		#expect(docker.arguments.contains("name=abydos-"))
		#expect(docker.arguments.contains("-a"))

		// Apple's `--quiet` prints one container id per line, and for everything
		// this app starts the id is the name. It has no filter, which costs
		// nothing: `stale` keeps only our own names anyway.
		let apple = try #require(ToolContainers.listing(using: .apple("/usr/local/bin/container")))
		#expect(apple.arguments == ["ls", "--all", "--quiet"])
	}

	/// Apple's `inspect` has no `--format`, so the whole record comes back and
	/// the two things wanted are read out of it.
	@Test func applesInspectIsReadRatherThanSearched() {
		let record = """
		[{"id":"abydos-plantuml-1-1","configuration":{"image":{"reference":"plantuml/plantuml"}},
		  "status":{"state":"running","networks":[{"ipv4Address":"192.168.64.14/24",
		  "ipv4Gateway":"192.168.64.1","network":"default"}]}}]
		"""
		#expect(AppleInspection.state(record) == "running")
		#expect(AppleInspection.isRunning(record))
		// Without the prefix length, which is not part of an address to ask.
		#expect(AppleInspection.address(record) == "192.168.64.14")

		// Whatever the CLI wrote before the JSON is stepped over: both of a
		// command's streams arrive here together.
		#expect(AppleInspection.address("[6/6] Starting container\n" + record) == "192.168.64.14")

		// And nothing readable is nil rather than a guess.
		#expect(AppleInspection.state("Error: container not found") == nil)
		#expect(AppleInspection.address("") == nil)
		#expect(AppleInspection.address(#"[{"id":"x","status":{"state":"stopped","networks":[]}}]"#)
			== nil)
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

/// Removing what you started, rather than everything anybody started.
///
/// The register is process-wide, and a test suite is one process running several
/// suites at once. A test that empties the whole of it removes the container the
/// suite beside it is in the middle of using — which is not a fault in the other
/// suite, however much it looks like one from there.
struct ContainerCleanupTests {
	/// The prefixes are the caller's own roles, and everything else registered
	/// stays registered.
	@Test func aToolRemovesItsOwnContainersRatherThanEveryones() {
		let containers = ToolContainers()
		// Something that exists and does nothing: what is being tested is which
		// names are chosen, not what a runtime does with them.
		let runtime = ContainerRuntime.docker("/usr/bin/true")
		let server = ToolContainers.mint("plantuml-server")
		let devcontainer = ToolContainers.mint("devcontainer")
		// Another copy of this app's, by the pid in the name.
		let somebodyElses = "abydos-plantuml-server-1-1"
		for name in [server, devcontainer, somebodyElses] {
			containers.register(name, runtime: runtime)
		}

		#expect(containers.release(withPrefixes: ["abydos-plantuml-server-"]) == [server])
		// The devcontainer another suite has a shell in is untouched, and so is
		// the container belonging to something else running now.
		#expect(containers.names == [devcontainer, somebodyElses].sorted())
	}

	/// That no test empties the register.
	///
	/// `removeAll` is the app's exit path and belongs to the app: it takes every
	/// container this process registered, whoever registered it and whatever
	/// they are still doing with it. In a test it took the devcontainer out from
	/// under the suite running beside it, whose shell then answered "No such
	/// container" — a red run four separate people investigated in one day
	/// before each concluding it was not theirs. That cost is why this is a test
	/// rather than a comment.
	///
	/// The name it looks for is assembled rather than written out, so this file
	/// is scanned like every other instead of having to exempt itself.
	@Test func noTestEmptiesTheWholeRegister() throws {
		let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		let forbidden = "Containers.shared." + "removeAll()"
		var offenders: [String] = []
		for name in try FileManager.default.contentsOfDirectory(atPath: tests.path)
			where name.hasSuffix(".swift") {
			let text = try String(contentsOf: tests.appendingPathComponent(name), encoding: .utf8)
			if text.contains(forbidden) { offenders.append(name) }
		}
		let named = offenders.sorted().joined(separator: ", ")
		#expect(offenders.isEmpty, """
		a test removes the containers it made, by name — release(withPrefixes:) — \
		rather than every container this process started: \(named)
		""")
	}
}

/// Which runtime, now that a container can be removed on either.
struct ContainerRuntimePreferenceTests {
	/// Docker first when nothing is asked for. The reason is no longer cleanup —
	/// that is proven on both — but the one thing that does not work on Apple's:
	/// nothing here can reach one of its containers over the network.
	@Test func automaticPrefersTheOneItsContainersCanBeReachedOn() {
		let found = ContainerRuntime.discover(locate: { name in
			["container": "/usr/local/bin/container", "docker": "/usr/bin/docker"][name]
		})
		#expect(found == .docker("/usr/bin/docker"))
	}

	/// Apple's is still found when it is the only one here, and everything except
	/// a published port works on it.
	@Test func appleIsStillFoundWhenItIsAllThereIs() {
		let found = ContainerRuntime.discover(
			locate: { $0 == "container" ? "/usr/local/bin/container" : nil }
		)
		#expect(found == .apple("/usr/local/bin/container"))
		// And it is not silent about the one thing it cannot do. It no longer
		// warns about removal, which is proven.
		let caveat = try? #require(found?.caveat)
		#expect(caveat?.contains("over the network") == true)
		#expect(caveat?.contains("removing a container by name") == false)
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
/// **Run for both runtimes**, which is the point of it. This was docker's proof
/// alone, and 0406 set Apple's aside because its service was wedged badly enough
/// that `--help` never returned — the one state in which a cleanup cannot be
/// demonstrated. It answers again, so it gets the same test rather than a
/// promise, and `rm --force` is no longer read off documentation.
///
/// Skipped, per runtime, unless that runtime and a small image are both here.
/// To run all of it:
///
///     docker pull alpine:3
///     container image pull alpine:3
///
/// Serialized: two of these on the same runtime at once are two sweeps, and a
/// sweep is a machine-wide thing.
@Suite(.serialized) struct ToolContainerLiveTests {
	static let image = "alpine:3"

	/// That runtime, if it is here and already holds the image.
	private func runtime(_ preference: ContainerRuntime.Preference) -> ContainerRuntime? {
		guard let found = ContainerRuntime.discover(preference: preference) else { return nil }
		let inspect = RuntimeCommand.run(
			ContainerImages.inspect(Self.image, using: found), deadline: 20
		)
		return inspect.succeeded ? found : nil
	}

	private func exists(_ name: String, using runtime: ContainerRuntime) -> Bool {
		switch runtime {
		case .docker:
			return RuntimeCommand.run(
				(runtime.path, ["inspect", "--type", "container", name]), deadline: 10
			).succeeded
		case .apple:
			return RuntimeCommand.run(
				ToolContainers.inspection(of: name, using: runtime), deadline: 10
			).succeeded
		}
	}

	/// Whether the runtime says the container is up, rather than merely there.
	private func isRunning(_ name: String, using runtime: ContainerRuntime) -> Bool {
		let asked = RuntimeCommand.run(
			DevContainers.stateCommand(name: name, using: runtime), deadline: 15
		)
		return asked.succeeded && DevContainers.isRunning(asked.output, using: runtime)
	}

	/// Whether a sweep would find this name at all — the listing that a sweep
	/// starts from, asked directly.
	private func listed(_ name: String, using runtime: ContainerRuntime) -> Bool {
		guard let listing = ToolContainers.listing(using: runtime) else { return false }
		let found = RuntimeCommand.run(listing, deadline: 20)
		return found.succeeded && found.output
			.split(separator: "\n")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.contains(name)
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

	@Test(arguments: [ContainerRuntime.Preference.docker, .apple])
	func killingTheProcessLeavesTheContainerAndRemovingItByNameDoesNot(
		_ preference: ContainerRuntime.Preference
	) throws {
		guard let runtime = runtime(preference) else { return }
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

		#expect(
			waitFor(120) { isRunning(name, using: runtime) },
			"the container never started on \(runtime.name)"
		)

		// The bug, demonstrated: the process is killed outright and the
		// container carries on. `--rm` only fires for a container that ends of
		// its own accord.
		kill(process.processIdentifier, SIGKILL)
		process.waitUntilExit()
		Thread.sleep(forTimeInterval: 3)
		#expect(exists(name, using: runtime), "a killed `run` used to be the whole story")
		// Not merely still listed — still *running*, minutes of `sleep` later,
		// with nothing left on this side that could stop it.
		#expect(isRunning(name, using: runtime), "the container should outlive its starter")
		// And a sweep can see it, which is the other half of not leaving one
		// behind: a listing that misses it is a sweep that removes nothing.
		#expect(listed(name, using: runtime), "the listing a sweep starts from cannot see it")

		// And the fix: asked by name, the runtime removes it.
		containers.release(name)
		#expect(!exists(name, using: runtime))
		#expect(!listed(name, using: runtime))
		#expect(containers.names.isEmpty)
	}

	/// What an app that was killed outright leaves behind, cleared by the next
	/// one to start — on a container the sweep did not start and knows nothing
	/// about except its name.
	@Test(arguments: [ContainerRuntime.Preference.docker, .apple])
	func theSweepTakesWhatAnEarlierRunLeft(_ preference: ContainerRuntime.Preference) throws {
		guard let runtime = runtime(preference) else { return }
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
		#expect(listed(name, using: runtime), "the sweep's listing cannot see it")

		let removed = ToolContainers().sweep(using: runtime, isAlive: { $0 != dead })
		// Contains rather than equals: every other `abydos-…` is reported alive
		// by the closure above and so must be left alone, but a container this
		// test did not make is not this test's to assert about.
		#expect(removed.contains(name))
		#expect(!exists(name, using: runtime))
	}
}
