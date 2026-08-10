import Foundation
import Testing
@testable import AbydosKit

/// A language server inside the project's own devcontainer, answering about
/// files on this machine.
///
/// `ContainerLSPLiveTests` proved this for a container started *for* the server;
/// this is step four of 0424, which is the same proof for the container the
/// project is already open in. What is different is everything about whose
/// container it is: it was up before the server, it holds somebody's terminal,
/// the project is mounted where the *file* said rather than at `/workspace`, and
/// stopping the server must not take it away.
///
/// Skipped unless the image is already here, the way the other live tests skip
/// without their server. Build it with:
///
///     make tool-image TOOL=gopls
@Suite(.serialized) struct DevContainerLSPLiveTests {
	/// What `ToolImages/gopls/Dockerfile` builds: gopls, and the Go toolchain it
	/// is a front end for. Used here as a devcontainer's image rather than as a
	/// tool image, which is the point — it is a container with a project's
	/// toolchain in it, which is what a devcontainer is.
	static let image = "abydos/gopls:dev"

	/// Docker only, because that is the runtime this image was built with and an
	/// image built there is not visible to Apple's.
	private var available: ContainerRuntime? {
		guard let runtime = ContainerRuntime.discover(preference: .docker),
		      RuntimeCommand.run(
		      	ContainerImages.inspect(Self.image, using: runtime), deadline: 20
		      ).succeeded
		else { return nil }
		return runtime
	}

	/// A Go module with one function calling another, and a devcontainer file
	/// that mounts it somewhere that is not `/workspace`.
	private func makeProject() throws -> URL {
		let root = try JavaTestDirectory.make()
		try JavaTestDirectory.write("""
		{
			"name": "Go, in the container the project names",
			"image": "\(Self.image)",
			// Deliberately not /workspace and not the default /workspaces/<name>:
			// the workspace folder is the file's to choose, and a mapping that
			// quietly used this app's own default would name files that exist on
			// neither side.
			"workspaceMount": "source=${localWorkspaceFolder},target=/src,type=bind",
			"workspaceFolder": "/src",
			"postCreateCommand": "echo ready > /tmp/lsp-ready",
		}
		""", to: root.appendingPathComponent(".devcontainer/devcontainer.json"))
		try JavaTestDirectory.write(
			"module example.com/probe\n\ngo 1.24\n", to: root.appendingPathComponent("go.mod")
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
		// Canonical, because that is what the mount and every URI will use.
		return URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)
	}

	@Test func goplsInsideTheProjectsDevcontainerAnswersAboutFilesOnThisMachine() async throws {
		guard let runtime = available else { return }
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let outcome = await DevContainers.shared.session(for: root, using: runtime)
		guard case let .running(session)? = outcome else {
			Issue.record("the devcontainer did not start: \(String(describing: outcome))")
			return
		}
		defer { Task { await DevContainers.shared.stop(project: root) } }

		// The two steps compose: the container was set up by its lifecycle
		// command before anything was asked of it.
		#expect(RuntimeCommand.run(
			DevContainers.execCommand(session, arguments: ["cat", "/tmp/lsp-ready"]), deadline: 30
		).output.contains("ready"))

		// The container has gopls, which is a question this side cannot answer by
		// reading and does not have to guess at.
		let provided = await DevContainers.shared.provides(["gopls", "rust-analyzer"], in: session)
		#expect(provided == ["gopls"])

		let resolved = try #require(LanguageServers.resolve(
			languageId: "go", project: root, inDevContainer: session
		))

		// The devcontainer's mapping, not this app's default.
		let paths = try #require(resolved.launch.paths)
		#expect(paths.host == root.path)
		#expect(paths.container == "/src")

		// Nothing is started for this server and nothing is removed with it: the
		// container is the project's.
		#expect(resolved.launch.image == nil)
		#expect(resolved.launch.container == nil)

		let run = resolved.launch.invocation
		#expect(run.executable == runtime.path)
		#expect(run.arguments.first == "exec")
		#expect(run.arguments.contains(session.name))
		// The bare command, resolved by the container's PATH. Not a path from
		// this machine and above all not one from `xcrun`: the server is not
		// here, and a path found here names nothing there.
		#expect(run.arguments.last == "gopls")
		#expect(!run.arguments.contains { $0.hasPrefix("/usr/local/bin/") })
		// Rooted where the manifest is, in the container's own names.
		#expect(run.arguments.contains("/src"))

		let client = LSPClient()
		client.containerPaths = paths
		client.containerLaunch = resolved.launch.container
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

		let capabilities = try await client.initialize(rootURL: root, timeout: 60)
		#expect(capabilities["definitionProvider"] != nil)

		let text = try String(contentsOf: file, encoding: .utf8)
		client.didOpen(uri: fileURI, languageId: "go", version: 1, text: text)

		// Diagnostics are the server's first unprompted word about a file, and
		// the first chance to see a URI it chose rather than one it was given.
		for _ in 0..<120 where diagnosed.uri == nil {
			try? await Task.sleep(nanoseconds: 250_000_000)
		}
		// Named as this machine names it, not as /src/main.go.
		#expect(diagnosed.uri == fileURI)

		let symbols = try await client.documentSymbols(uri: fileURI)
		#expect(symbols.contains { $0.name == "greeting" })

		// And the answer that is a place rather than a name: the declaration of
		// `greeting`, from the call to it on the last line.
		let locations = try await client.definition(
			uri: fileURI, position: LSPPosition(line: 9, character: 14)
		)
		let declaration = try #require(locations.first)
		#expect(declaration.uri == fileURI)
		#expect(declaration.url?.path == file.path)
		#expect(declaration.range.start.line == 4)

		// It really is in there, asked of the container's own process table
		// rather than of this object's opinion — 0427 is exactly the item about
		// servers that are running when nothing thinks they are.
		#expect(goplsCount(in: session) >= 1)

		// Stopping the server ends the server. The protocol's own `exit` is what
		// does it, which is the only thing that reaches inside: killing the
		// `exec` on this side leaves the process in there.
		await client.shutdown()
		var left = goplsCount(in: session)
		for _ in 0..<40 where left > 0 {
			try? await Task.sleep(nanoseconds: 250_000_000)
			left = goplsCount(in: session)
		}
		#expect(left == 0, "gopls was still running inside the container after shutdown")

		// And the container is still up, because it is the project's and not the
		// server's — somebody's terminal is in it.
		let running = RuntimeCommand.run(
			DevContainers.stateCommand(name: session.name, using: runtime), deadline: 20
		)
		#expect(DevContainers.isRunning(running.output, using: runtime))

		await DevContainers.shared.stop(project: root)
		#expect(isGone(session.name, using: runtime), "the container was not removed")
	}

	/// How many gopls processes the container has, read out of `/proc` because
	/// `ps` is not in every image and this is.
	private func goplsCount(in session: DevContainers.Session) -> Int {
		let counted = RuntimeCommand.run(
			DevContainers.execCommand(session, arguments: [
				"/bin/sh", "-c",
				"grep -l '^gopls$' /proc/[0-9]*/comm 2>/dev/null | wc -l",
			]),
			deadline: 30
		)
		return Int(counted.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
	}

	private func isGone(_ name: String, using runtime: ContainerRuntime) -> Bool {
		guard let listing = ToolContainers.listing(using: runtime) else { return false }
		let deadline = Date().addingTimeInterval(30)
		while Date() < deadline {
			let listed = RuntimeCommand.run(listing, deadline: 15)
			if listed.succeeded, !listed.output.contains(name) { return true }
			Thread.sleep(forTimeInterval: 0.5)
		}
		return false
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
