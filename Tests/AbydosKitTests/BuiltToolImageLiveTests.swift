import Foundation
import Testing
@testable import AbydosKit

/// Against a language server built on this machine from a Dockerfile this
/// repository ships.
///
/// `ContainerLSPLiveTests` proves the container path against an image that was
/// published and pulled. This proves the other route end to end — the recipe is
/// found, fingerprinted, built by the runtime, and the server inside answers
/// about a file on this machine — and it does it with the tool that route was
/// chosen for: `openscad-lsp` is installed by `cargo install`, which means a
/// Rust toolchain for one binary, so a hover that works here is not the host's
/// copy replying. There is no host copy.
///
/// **A build is minutes, so a plain `make test` never starts one.** The test
/// runs when the image is already on the machine, and otherwise only when it is
/// asked for by name:
///
///     ABYDOS_BUILD_TOOL_IMAGES=1 xcrun swift test --filter BuiltToolImageLiveTests
///
/// One run of that builds it; every run afterwards drives it and takes seconds.
struct BuiltToolImageLiveTests {
	/// Whether a build may be started, which is a decision and not a discovery.
	private var mayBuild: Bool {
		ProcessInfo.processInfo.environment["ABYDOS_BUILD_TOOL_IMAGES"] != nil
	}

	/// A runtime on this machine, whichever it is.
	///
	/// Unlike the published-image test there is nothing to prefer: the image
	/// does not exist anywhere yet, so whichever runtime is here is the one that
	/// will make it and the one that will hold it.
	private var runtime: ContainerRuntime? {
		ContainerRuntime.discover(preference: .automatic)
	}

	private func holdsImage(_ image: String, in runtime: ContainerRuntime) -> Bool {
		let command = ContainerImages.inspect(image, using: runtime)
		// The same deadline the store uses to ask the question, and for the same
		// reason: a runtime whose service has wedged answers nothing at all, and
		// a test that waits with it is the hang this suite is meant not to have.
		return RuntimeCommand.run(command, deadline: 5).exitCode == 0
	}

	/// A directory with a model in it, which is the whole of an OpenSCAD
	/// project: the server has no root markers, so anywhere a `.scad` is opened
	/// is somewhere it can answer.
	private func makeProject() throws -> URL {
		let root = try JavaTestDirectory.make()
		try JavaTestDirectory.write(
			"{\"openscad-lsp\": \"build\"}\n", to: ToolImages.url(in: root)
		)
		try JavaTestDirectory.write("""
		module bracket(width = 10, depth = 5) {
			cube([width, depth, 2]);
		}

		module plate() {
			cube([40, 40, 1]);
		}

		bracket(20);
		plate();
		""", to: root.appendingPathComponent("part.scad"))
		// Canonical, because that is what the mount and every URI will use: a
		// temporary directory on macOS is under `/var`, which is a symlink.
		return URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)
	}

	@Test func openscadLspBuiltHereAnswersAboutAScadFileOnThisMachine() async throws {
		guard let recipe = ToolImageRecipes.recipe(forTool: "openscad-lsp"),
		      let runtime
		else { return }
		let alreadyBuilt = holdsImage(recipe.image, in: runtime)
		guard alreadyBuilt || mayBuild else { return }

		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		// Read out of the project the way the editor reads it. `build` is what
		// is checked in; the name with the fingerprint in it is worked out here
		// and never written down.
		let asked = try #require(ToolImages.inProject(root).image(for: "openscad-lsp"))
		#expect(asked == ToolImageRecipes.buildHere)

		let resolved = try #require(LanguageServers.resolve(
			languageId: "openscad", project: root, image: asked, runtime: runtime
		))
		let image = try #require(resolved.launch.image)
		#expect(image.name == recipe.image)

		// The part this test exists for: no registry is involved. The image is
		// not there, so it is made from the Dockerfile in this repository.
		let store = ContainerImageStore()
		let outcome = await store.ensure(image.name, using: runtime)
		#expect(outcome.isReady)
		if !alreadyBuilt {
			// Built, not fetched. Nothing published this and nothing could have
			// pulled it, so an outcome saying `fetched` would mean the branch
			// that recognises this app's own names had not been taken.
			#expect(outcome == .built)
		}

		let run = resolved.launch.invocation
		#expect(run.executable == runtime.path)
		#expect(run.arguments.contains("\(root.path):/workspace"))
		#expect(run.arguments.last == recipe.image)

		let paths = try #require(resolved.launch.paths)
		let client = LSPClient()
		client.containerPaths = paths
		client.callbackQueue = .global()
		defer { client.stop() }

		let file = root.appendingPathComponent("part.scad")
		let fileURI = URL(fileURLWithPath: FilePath.canonical(file)).absoluteString

		try client.start(
			executable: run.executable,
			arguments: run.arguments,
			workingDirectory: root,
			environment: LanguageServers.serverEnvironment
		)

		let capabilities = try await client.initialize(rootURL: root, timeout: 60)
		#expect(capabilities["documentSymbolProvider"] != nil)
		#expect(capabilities["definitionProvider"] != nil)

		let text = try String(contentsOf: file, encoding: .utf8)
		client.didOpen(uri: fileURI, languageId: "openscad", version: 1, text: text)

		// The modules the file declares, named by a server that has never seen
		// this filesystem.
		let symbols = try await client.documentSymbols(uri: fileURI)
		#expect(symbols.contains { $0.name == "bracket" })
		#expect(symbols.contains { $0.name == "plate" })

		// And the answer that is a place rather than a name: `bracket(20);` on
		// the eighth line, declared on the first. Every URI went out rewritten
		// to /workspace and came back rewritten home, and a mapping that was
		// subtly wrong would name a file that does not exist here.
		let locations = try await client.definition(
			uri: fileURI, position: LSPPosition(line: 8, character: 2)
		)
		let declaration = try #require(locations.first)
		#expect(declaration.uri == fileURI)
		#expect(declaration.url?.path == file.path)
		#expect(declaration.range.start.line == 0)
	}
}
