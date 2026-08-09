import Foundation
import Testing
@testable import AbydosKit

/// Against a real language server running from a container image.
///
/// This is the test the whole container path exists for, and the one thing it
/// proves that nothing else can: that a server which has never seen this
/// machine's filesystem answers about files on it. Every URI going out is
/// rewritten to the mount and every one coming back is rewritten home, so a
/// mapping that is subtly wrong shows up here as a diagnostic against a path
/// that does not exist — which is exactly how it would show up in the editor,
/// except that here it fails a test instead of looking like an unreliable
/// server.
///
/// Skipped unless one of the images is already on this machine, the way the
/// other live tests are skipped without their server. Get one with:
///
///     docker pull pharndt/abydos-gopls:dev    # what the catalogue lists
///     make tool-image-gopls                   # a build of ToolImages/gopls
struct ContainerLSPLiveTests {
	/// The images this will drive, best first.
	///
	/// Either, and the published one first, because the two answer different
	/// questions and only one of them is the question the catalogue asks.
	/// `abydos/gopls:dev` is whatever this machine last built, so a pass against
	/// it says the Dockerfile in this repository works — worth having while
	/// somebody is changing it, and no evidence at all about what a stranger
	/// pulls. `pharndt/abydos-gopls:dev` is the artefact in the registry, the
	/// one `ToolImageCatalogue` names, and the only one whose passing means the
	/// entry in that list is true. So it is tried first: on a machine that has
	/// both, the published image is the one that gets driven.
	static let images = ["pharndt/abydos-gopls:dev", "abydos/gopls:dev"]

	/// An image on this machine and a runtime that has it, or nil when there is
	/// no such pair.
	///
	/// Every runtime installed rather than only the preferred one, and it has to
	/// hold the image rather than merely exist: an image built with docker is
	/// not visible to Apple's `container`, and preferring Apple's — which is
	/// what the app does — would skip this test on a machine that can run it.
	///
	/// Image outermost, runtime innermost: the published image under whichever
	/// runtime has it beats the locally built one under the preferred runtime,
	/// because which image ran is what this test is evidence about.
	private var available: (runtime: ContainerRuntime, image: String)? {
		for image in Self.images {
			for preference in [ContainerRuntime.Preference.apple, .docker] {
				guard let runtime = ContainerRuntime.discover(preference: preference),
				      holdsImage(image, in: runtime)
				else { continue }
				return (runtime, image)
			}
		}
		return nil
	}

	private func holdsImage(_ image: String, in runtime: ContainerRuntime) -> Bool {
		let process = Process()
		let command = ContainerImages.inspect(image, using: runtime)
		process.executableURL = URL(fileURLWithPath: command.executable)
		process.arguments = command.arguments
		// Nowhere rather than into pipes. Only the exit status is wanted, and a
		// pipe nobody drains is how a subprocess capture hangs — see
		// `ProcessPipes`, which exists because of exactly that.
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		// Not a `Pipe()`: this process would hold its write end open, and a
		// runtime that reads standard input then waits for an end that never
		// comes. Apple's `container` does exactly that.
		process.standardInput = FileHandle.nullDevice
		guard (try? process.run()) != nil else { return false }

		// With a deadline of its own, because asking a runtime a question is not
		// always answered: Apple's `container` talks to a service that can wedge
		// — every subcommand then waits, `container ls` included — and a test
		// that waits with it is the hang this suite is meant not to have. A
		// runtime that cannot answer whether it has the image is a runtime this
		// test cannot use, which is the same as not having it.
		let deadline = Date().addingTimeInterval(5)
		while process.isRunning, Date() < deadline {
			Thread.sleep(forTimeInterval: 0.05)
		}
		guard !process.isRunning else {
			process.terminate()
			return false
		}
		return process.terminationStatus == 0
	}

	/// A Go module with one function calling another, which is the smallest
	/// project a server can say something interesting about — and an
	/// `.abydos/tools.json` naming the image, which is how somebody actually
	/// asks for one.
	private func makeProject(image: String) throws -> URL {
		let root = try JavaTestDirectory.make()
		try JavaTestDirectory.write(
			"module example.com/probe\n\ngo 1.24\n",
			to: root.appendingPathComponent("go.mod")
		)
		// The per-project route rather than the settings one. They meet at
		// `LanguageServers.resolve`, but everything before that differs: a file
		// on disk, parsed, keyed by the tool's name rather than the server's
		// command. A test that handed `resolve` a string would prove the half
		// that was never in doubt.
		try JavaTestDirectory.write(
			"{\"gopls\": \"\(image)\"}\n", to: ToolImages.url(in: root)
		)
		try JavaTestDirectory.write("""
		package main

		import "fmt"

		func greeting() string {
			return "hello"
		}

		func main() {
			fmt.Println(greeting())
		}
		""", to: root.appendingPathComponent("main.go"))
		// Canonical, because that is what the mount and every URI will use: a
		// temporary directory on macOS is under `/var`, which is a symlink.
		return URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)
	}

	@Test func goplsInAContainerAnswersAboutFilesOnThisMachine() async throws {
		guard let (runtime, image) = available else { return }
		let root = try makeProject(image: image)
		defer { try? FileManager.default.removeItem(at: root) }

		// Read back out of the project, the way the editor reads it: the tool's
		// key is `gopls`, which is the server definition's `toolKey`, and a file
		// that named it anything else would resolve to no image at all.
		let go = try #require(LanguageServers.definition(forLanguage: "go"))
		let named = try #require(ToolImages.inProject(root).image(for: go.toolKey))
		#expect(named == image)

		let resolved = try #require(LanguageServers.resolve(
			languageId: "go", project: root, image: named, runtime: runtime
		))

		// The image was chosen over anything installed, and the project is
		// mounted where the catalogue says it will be.
		let paths = try #require(resolved.launch.paths)
		#expect(paths.host == root.path)
		#expect(paths.container == "/workspace")

		let run = resolved.launch.invocation
		#expect(run.executable == runtime.path)
		#expect(run.arguments.contains("--rm"))
		#expect(run.arguments.contains("\(root.path):/workspace"))
		#expect(run.arguments.contains(image))
		// Nothing after the image: the server is the entry point.
		#expect(run.arguments.last == image)

		let client = LSPClient()
		client.containerPaths = paths
		client.callbackQueue = .global()
		defer { client.stop() }

		let file = root.appendingPathComponent("main.go")
		let fileURI = URL(fileURLWithPath: FilePath.canonical(file)).absoluteString

		let diagnosed = Diagnosed()
		client.onDiagnostics = { uri, _ in diagnosed.record(uri) }

		try client.start(
			executable: run.executable,
			arguments: run.arguments,
			workingDirectory: root,
			environment: LanguageServers.serverEnvironment
		)

		// Generous: starting a container and loading a module's packages is
		// seconds rather than milliseconds, and the machine running this may be
		// doing something else.
		let capabilities = try await client.initialize(rootURL: root, timeout: 60)
		#expect(capabilities["definitionProvider"] != nil)
		#expect(capabilities["documentSymbolProvider"] != nil)

		let text = try String(contentsOf: file, encoding: .utf8)
		client.didOpen(uri: fileURI, languageId: "go", version: 1, text: text)

		// Diagnostics are the server's first unprompted word about a file, and
		// the first chance to see a URI it chose rather than one it was given.
		for _ in 0..<120 where diagnosed.uri == nil {
			try? await Task.sleep(nanoseconds: 250_000_000)
		}
		// Named as this machine names it, not as /workspace/main.go.
		#expect(diagnosed.uri == fileURI)

		let symbols = try await client.documentSymbols(uri: fileURI)
		#expect(symbols.contains { $0.name == "greeting" })
		#expect(symbols.contains { $0.name == "main" })

		// And the answer that is a place rather than a name: the declaration of
		// `greeting`, from the call to it on the last line.
		let locations = try await client.definition(
			uri: fileURI, position: LSPPosition(line: 9, character: 14)
		)
		let declaration = try #require(locations.first)
		#expect(declaration.uri == fileURI)
		#expect(declaration.url?.path == file.path)
		// `func greeting()` is the fifth line, and lines are 0-based on the wire.
		#expect(declaration.range.start.line == 4)
	}

	/// Collects the callback from whichever thread it arrives on.
	private final class Diagnosed: @unchecked Sendable {
		private let lock = NSLock()
		private var value: String?

		var uri: String? { lock.lock(); defer { lock.unlock() }; return value }

		func record(_ uri: String) {
			lock.lock()
			value = uri
			lock.unlock()
		}
	}
}
