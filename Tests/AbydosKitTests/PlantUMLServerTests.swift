import Foundation
import Testing
@testable import AbydosKit

/// The address a kept server is asked at, and what it refuses to be asked.
struct PlantUMLServerAddressTests {
	/// `~h` and the hex of the plain source — the form the image's own server
	/// understands, and the one that can be pasted into a browser off a log
	/// line. No compressed encoding needed.
	@Test func theDiagramIsTheAddress() throws {
		let path = try #require(PlantUMLServers.path(for: "@startuml\n@enduml\n", format: .png))
		#expect(path.hasPrefix("/plantuml/png/~h"))
		let hex = String(path.dropFirst("/plantuml/png/~h".count))
		let decoded = stride(from: 0, to: hex.count, by: 2).compactMap { offset -> UInt8? in
			let start = hex.index(hex.startIndex, offsetBy: offset)
			let end = hex.index(start, offsetBy: 2)
			return UInt8(hex[start..<end], radix: 16)
		}
		#expect(String(decoding: decoded, as: UTF8.self) == "@startuml\n@enduml\n")

		// And the same picture in the other format is the same address with one
		// word changed.
		let svg = try #require(PlantUMLServers.path(for: "@startuml\n@enduml\n", format: .svg))
		#expect(svg.hasPrefix("/plantuml/svg/~h"))
		#expect(svg.dropFirst("/plantuml/svg/~h".count) == hex[...])
	}

	@Test func theWholeAddressIsOnTheLoopback() throws {
		let url = try #require(PlantUMLServers.url(port: 32768, source: "@startuml\n@enduml", format: .png))
		#expect(url.absoluteString.hasPrefix("http://127.0.0.1:32768/plantuml/png/~h"))
	}

	/// A diagram larger than a request line should hold is not an error: it is
	/// drawn the old way, which has no such limit. Measured against this image,
	/// half a megabyte of source in a one-megabyte request line still came back
	/// as a picture, so the cap is a long way inside what works.
	@Test func anEnormousDiagramGoesTheOldWay() {
		let huge = String(repeating: "a", count: PlantUMLServers.sourceLimit + 1)
		#expect(PlantUMLServers.path(for: huge, format: .png) == nil)
		#expect(PlantUMLServers.url(port: 1, source: huge, format: .png) == nil)
		// And a real diagram is nowhere near it: the largest in the examples
		// repository is 1.3 KB.
		#expect(PlantUMLServers.sourceLimit > 100 * 1024)
	}

	/// Detached, named, and on a port the runtime picks — a port chosen here is
	/// a port that can be taken between choosing it and using it.
	@Test func theServerIsStartedDetachedAndNamed() {
		let command = PlantUMLServers.startCommand(
			image: "plantuml/plantuml", name: "abydos-plantuml-server-9-1",
			using: .docker("/usr/bin/docker")
		)
		#expect(command.executable == "/usr/bin/docker")
		#expect(command.arguments == [
			"run", "-d", "--rm", "--name", "abydos-plantuml-server-9-1",
			"-p", "127.0.0.1::8080",
			"plantuml/plantuml", "--http-server:8080",
		])
		#expect(ToolContainers.isOurs("abydos-plantuml-server-9-1"))
	}

	@Test func thePortIsReadOffTheRuntimesAnswer() {
		#expect(PlantUMLServers.port(from: "127.0.0.1:32768\n") == 32768)
		// More than one published address, which is what a runtime says when it
		// has bound both families.
		#expect(PlantUMLServers.port(from: "0.0.0.0:49154\n[::]:49154\n") == 49154)
		#expect(PlantUMLServers.port(from: "") == nil)
		#expect(PlantUMLServers.port(from: "no such container") == nil)
	}

	/// Docker only, and on purpose — but no longer because of cleanup, which is
	/// proven on both now (0406). What is left is that a server kept on Apple's
	/// runtime has no address this app may ask: its published ports are accepted
	/// and reset, and its containers' own addresses answer a plain `connect` with
	/// `EHOSTUNREACH`. `canKeepWarm` writes that out in full.
	@Test func onlyTheRuntimeThisAppCanReachAServerOnKeepsOne() async {
		#expect(PlantUMLServers.canKeepWarm(.docker("/usr/bin/docker")))
		#expect(!PlantUMLServers.canKeepWarm(.apple("/usr/local/bin/container")))

		// And asking anyway answers nil, which is the caller's signal to draw the
		// diagram the way it always did — without starting anything at all.
		let servers = PlantUMLServers()
		let drawn = await servers.render(
			"@startuml\nAlice -> Bob\n@enduml\n",
			image: "plantuml/plantuml",
			using: .apple("/usr/local/bin/container")
		)
		#expect(drawn == nil)
		#expect(await servers.images.isEmpty)
	}
}

/// Against a real PlantUML: that the kept server draws the same picture much
/// faster, and that removing it does not break the preview.
///
/// Skipped unless docker has the image already, the way the other live tests
/// are skipped without their server.
///
/// Serialized, and each test tidies up only the containers it started itself:
/// two of these running at once were removing each other's servers mid-render,
/// which is a fine demonstration of the fallback and a useless test.
@Suite(.serialized) struct PlantUMLServerLiveTests {
	static let image = "plantuml/plantuml"
	static let diagram = "@startuml\nAlice -> Bob: hello\n@enduml\n"

	private var runtime: ContainerRuntime? {
		guard let docker = ContainerRuntime.discover(preference: .docker) else { return nil }
		return RuntimeCommand.run(
			ContainerImages.inspect(Self.image, using: docker), deadline: 10
		).succeeded ? docker : nil
	}

	/// The names this test has seen, so that its cleanup takes its own
	/// containers and nothing else's.
	private final class Started: @unchecked Sendable {
		private let lock = NSLock()
		private var names: Set<String> = []

		func note(_ found: [String]) {
			lock.lock()
			names.formUnion(found)
			lock.unlock()
		}

		var all: [String] {
			lock.lock()
			defer { lock.unlock() }
			return names.sorted()
		}
	}

	/// Nothing of this test's left behind, however it ended.
	///
	/// **Only the names this test noted**, which is every server its own
	/// `PlantUMLServers` reported holding after each render. It used to add to
	/// those every container in the process register whose name began
	/// `abydos-plantuml-server-` and carried this pid, on the reasoning that a
	/// test which fails part way through must not leave one behind.
	///
	/// That scan never found one of this suite's — they are all noted already —
	/// and it did find `DiagramExportLiveTests`', which runs beside this one and
	/// keeps a server with the same role and the same pid in its name. So the
	/// safety net caught only the neighbour, and removed the server the neighbour
	/// was drawing through. It is the same mistake this suite was on the
	/// receiving end of, written out by hand; see 0435 and the note on
	/// `DiagramExportLiveTests`. A role is not an owner.
	///
	/// The scan also looked for `abydos-probe-pipe-`, and there was never one to
	/// find: `drawTheOldWay` runs its container with `--rm` and registers nothing,
	/// so it takes itself away when the render ends.
	private func removeAll(_ started: Started, using runtime: ContainerRuntime) {
		let names = started.all
		if names.isEmpty { return }
		_ = RuntimeCommand.run(
			ToolContainers.removal(of: names, using: runtime), deadline: 30
		)
	}

	/// The render as it was before any of this: a container and a JVM, per
	/// diagram.
	private func drawTheOldWay(using runtime: ContainerRuntime) -> Data {
		let run = PlantUML.invocation(
			for: .image(ToolContainer(image: Self.image), runtime),
			name: ToolContainers.mint("probe-pipe")
		)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: run.executable)
		process.arguments = run.arguments
		let input = Pipe(), output = Pipe(), errors = Pipe()
		process.standardInput = input
		process.standardOutput = output
		process.standardError = errors
		guard (try? process.run()) != nil else { return Data() }
		return ProcessPipes.drain(
			process, out: output, err: errors, input: Data(Self.diagram.utf8), stdin: input
		).stdout
	}

	/// Patient enough that starting a container is never what this suite
	/// reports on.
	///
	/// The app's sixty seconds is the point at which it gives up on the
	/// optimisation and draws the diagram the way it always did — which costs a
	/// user nothing but time. These tests are asking whether the optimisation is
	/// *correct*, and a start that gave up leaves them nothing to compare, so
	/// they wait longer than the app would. 0435 is what inheriting the app's
	/// number cost.
	private func madeServers() -> PlantUMLServers {
		PlantUMLServers(patience: Patience.forAContainer)
	}

	@Test func theSecondDiagramIsTheSamePictureAndArrivesAtOnce() async throws {
		guard let runtime else { return }
		let servers = madeServers()
		// Whatever the test did, no container of its own is left running.
		let started = Started()
		defer { removeAll(started, using: runtime) }

		let old = Date()
		let pipe = drawTheOldWay(using: runtime)
		let oldSeconds = Date().timeIntervalSince(old)
		#expect(!pipe.isEmpty)

		// The first one pays for the container, the JVM and the JIT.
		//
		// Asked through `draw` rather than `render` so that a failure says what
		// happened. This line used to be `try #require(first)` over an optional,
		// and the three quite different things it can mean — the runtime would
		// not start a container, the JVM never answered inside a minute, the
		// request itself timed out — all arrived as "expected a value". 0435 is
		// what that cost.
		let firstBegan = Date()
		let first = await servers.draw(Self.diagram, image: Self.image, using: runtime)
		let startSeconds = Date().timeIntervalSince(firstBegan)
		started.note(await servers.containerNames)
		guard let firstDrawing = drawn(first, "the first render", after: startSeconds) else {
			return
		}
		let warm = firstDrawing.data
		#expect(firstDrawing.fault == nil)
		#expect(await servers.images == [Self.image])

		// The second is the one the whole item is about.
		let servedBy = await servers.containerNames
		let asked = Date()
		let second = await servers.draw(Self.diagram, image: Self.image, using: runtime)
		let warmSeconds = Date().timeIntervalSince(asked)
		started.note(await servers.containerNames)
		guard let againDrawing = drawn(second, "the warm render", after: warmSeconds) else {
			return
		}
		let again = againDrawing.data

		// The same picture, byte for byte, from a server as from the pipe. True at
		// any load, so it is asserted at any load.
		#expect(again == warm)
		#expect(again == pipe)
		print("PERF plantuml: start \(String(format: "%.2f", startSeconds))s, "
			+ "pipe \(String(format: "%.2f", oldSeconds))s, "
			+ "warm \(String(format: "%.3f", warmSeconds))s, \(again.count) bytes, "
			+ MachineLoad.said)
		// A warm render served by a *different* container is not a slow warm
		// render: it is a cold one, because something removed the server between
		// the two draws and `draw` quietly started another. The seconds that costs
		// then arrive here as `warmSeconds < 0.5` failing, which reads as the
		// optimisation not working and is nothing of the kind.
		//
		// This is the same move `Refusal` made for the render that gives up, for
		// the failure that is not a refusal: the two shapes 0435 was made of are a
		// removed container either way, and each now says so in its own words
		// rather than leaving somebody to infer it from a number. It is checked
		// before the stopwatch and at any load, because whether the server was
		// replaced is a fact rather than a measurement.
		let servingNow = await servers.containerNames
		guard servingNow == servedBy else {
			Issue.record("""
				the warm render came from a different server: \(servedBy) before, \
				\(servingNow) after. Something removed the container between the two \
				renders, so the \(String(format: "%.3f", warmSeconds))s this took is a \
				container starting rather than a diagram being drawn — \(MachineLoad.said)
				""")
			await servers.stopAll()
			return
		}

		// **Something arrives at once is kept, and 0435 is the argument for keeping
		// it.** The one time a bound here went red it was telling the truth — the
		// server really had been taken away and the render really did take seconds
		// — and deleting it would have removed the only thing in the suite that
		// noticed. A live test whose title is "arrives at once" has to assert that
		// something arrives at once, or it is asserting that two renders agree,
		// which they would with no server at all.
		//
		// So the *ratio* is asserted at any load and the absolute is not. This is
		// the one place in this suite where 0472's first candidate answer is
		// actually available: `oldSeconds` is a pipe render taken in *this* run,
		// seconds apart from the warm one, on the same machine. A loaded machine
		// slows both, so the quarter holds where half a second does not — and the
		// quarter is the claim, which is that the server is being reused rather
		// than that the wall clock read some particular number. Half a second of
		// wall clock on a machine with nothing left to give says nothing about
		// reuse; the byte-for-byte comparison above and the container-name check
		// below it do, and both are made at any load.
		#expect(warmSeconds < oldSeconds / 4, """
			warm \(warmSeconds)s against \(oldSeconds)s through the pipe \
			— \(MachineLoad.said)
			""")
		guard Stopwatch.maySay("PERF plantuml", "the warm render") else {
			await servers.stopAll()
			return
		}
		#expect(warmSeconds < 0.5)

		await servers.stopAll()
	}

	/// The drawing, or a failure that says what happened instead.
	///
	/// The whole of 0435 is that this used to be `try #require` over an optional:
	/// a render that gave up because the machine could not start a JVM in a
	/// minute, and a render that gave up because the image is broken, both
	/// arrived as "expected a value" and cost five people a day telling them
	/// apart. `Refusal` knows which, so the failure says which.
	private func drawn(
		_ outcome: Result<PlantUMLServers.Drawing, PlantUMLServers.Refusal>,
		_ what: String,
		after seconds: TimeInterval
	) -> PlantUMLServers.Drawing? {
		switch outcome {
		case let .success(drawing):
			return drawing
		case let .failure(why):
			Issue.record("""
				\(what) gave up after \(String(format: "%.1f", seconds))s: \
				\(why) — \(MachineLoad.said)
				""")
			return nil
		}
	}

	/// The server removed behind this app's back, which is what happens when
	/// somebody tidies up their containers by hand — or when the runtime is
	/// restarted. The diagram still arrives.
	@Test func aServerRemovedBehindItsBackStillDrawsTheDiagram() async throws {
		guard let runtime else { return }
		let servers = madeServers()
		let started = Started()
		defer { removeAll(started, using: runtime) }

		let began = Date()
		let first = await servers.draw(Self.diagram, image: Self.image, using: runtime)
		started.note(await servers.containerNames)
		guard drawn(first, "the first render", after: Date().timeIntervalSince(began)) != nil
		else { return }
		let name = try #require(await servers.containerNames.first)

		// Taken away without telling anybody.
		let removed = RuntimeCommand.run(
			ToolContainers.removal(of: [name], using: runtime), deadline: 30
		)
		#expect(removed.succeeded)

		// And a render still answers with a picture — from a new server, which
		// is what the old one's failure is worth doing about.
		let again = Date()
		let second = await servers.draw(Self.diagram, image: Self.image, using: runtime)
		started.note(await servers.containerNames)
		guard let replacement = drawn(
			second, "the render after the server was removed",
			after: Date().timeIntervalSince(again)
		) else { return }
		let drawn = replacement.data
		#expect(!drawn.isEmpty)
		#expect(await servers.containerNames.first != name)

		await servers.stopAll()
	}
}
