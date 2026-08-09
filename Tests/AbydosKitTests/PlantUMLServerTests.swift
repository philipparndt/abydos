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
	private func removeAll(_ started: Started, using runtime: ContainerRuntime) {
		// What the test saw, and any *server or pipe of this suite's* still
		// registered by this process that nothing has got round to removing — a
		// test that fails part way through must not leave a container behind
		// either.
		//
		// Named, rather than everything this process registered: that took the
		// devcontainer out from under `DevContainerLiveTests` running beside it,
		// and the shell in it then answered "No such container". Sharing a pid is
		// not owning each other's containers.
		let ours = ["abydos-plantuml-server-", "abydos-probe-pipe-"]
		let mine = ToolContainers.shared.names.filter { name in
			ToolContainers.owner(of: name) == ProcessInfo.processInfo.processIdentifier
				&& ours.contains { name.hasPrefix($0) }
		}
		let names = Set(started.all).union(mine).sorted()
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

	@Test func theSecondDiagramIsTheSamePictureAndArrivesAtOnce() async throws {
		guard let runtime else { return }
		let servers = PlantUMLServers()
		// Whatever the test did, no container of its own is left running.
		let started = Started()
		defer { removeAll(started, using: runtime) }

		let old = Date()
		let pipe = drawTheOldWay(using: runtime)
		let oldSeconds = Date().timeIntervalSince(old)
		#expect(!pipe.isEmpty)

		// The first one pays for the container, the JVM and the JIT.
		let first = await servers.render(Self.diagram, image: Self.image, using: runtime)
		let warm = try #require(first)
		started.note(await servers.containerNames)
		#expect(await servers.images == [Self.image])

		// The second is the one the whole item is about.
		let asked = Date()
		let again = try #require(
			await servers.render(Self.diagram, image: Self.image, using: runtime)
		)
		let warmSeconds = Date().timeIntervalSince(asked)

		// The same picture, byte for byte, from a server as from the pipe.
		#expect(again == warm)
		#expect(again == pipe)
		print("PERF plantuml: pipe \(String(format: "%.2f", oldSeconds))s, "
			+ "warm \(String(format: "%.3f", warmSeconds))s, \(again.count) bytes")
		// Generous by an order of magnitude against what was measured — hundredths
		// of a second warm against seconds for the pipe — so this fails when the
		// server has stopped being used, not when the machine is busy.
		#expect(warmSeconds < 0.5)
		#expect(warmSeconds < oldSeconds / 4)

		await servers.stopAll()
	}

	/// The server removed behind this app's back, which is what happens when
	/// somebody tidies up their containers by hand — or when the runtime is
	/// restarted. The diagram still arrives.
	@Test func aServerRemovedBehindItsBackStillDrawsTheDiagram() async throws {
		guard let runtime else { return }
		let servers = PlantUMLServers()
		let started = Started()
		defer { removeAll(started, using: runtime) }

		_ = try #require(await servers.render(Self.diagram, image: Self.image, using: runtime))
		started.note(await servers.containerNames)
		let name = try #require(await servers.containerNames.first)

		// Taken away without telling anybody.
		let removed = RuntimeCommand.run(
			ToolContainers.removal(of: [name], using: runtime), deadline: 30
		)
		#expect(removed.succeeded)

		// And a render still answers with a picture — from a new server, which
		// is what the old one's failure is worth doing about.
		let drawn = try #require(
			await servers.render(Self.diagram, image: Self.image, using: runtime)
		)
		started.note(await servers.containerNames)
		#expect(!drawn.isEmpty)
		#expect(await servers.containerNames.first != name)

		await servers.stopAll()
	}
}
