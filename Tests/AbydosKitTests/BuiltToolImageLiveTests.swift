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
///
/// Serialized since 0457 put a second case here: each one starts a container
/// with a language server in it reading a project, and two of those at once on
/// the machine that is also building them is a measurement of the machine.
@Suite(.serialized) struct BuiltToolImageLiveTests {
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
			languageId: "openscad", project: root, image: asked, runtime: runtime,
			choosing: .none
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

	// MARK: - kmp-lsp, and the two directories it reads outside the project

	/// A home directory made for this test, with a Maven repository in it.
	///
	/// The person's own `~/.m2` is deliberately not what is driven. What is
	/// wanted is a dependency whose *source* jar is there, and a real local
	/// repository is a thousand compiled jars and almost no sources — `mvn` does
	/// not fetch them unless asked — so a test against the real one would pass
	/// or fail on what somebody happened to have downloaded. This is the same
	/// layout, three files, and the same code path: `LanguageServers.resolve`
	/// takes the home directory as a parameter for exactly this reason.
	private func makeMavenHome() throws -> URL {
		let home = URL(
			fileURLWithPath: FilePath.canonical(try JavaTestDirectory.make()), isDirectory: true
		)
		let staging = home.appendingPathComponent("staging", isDirectory: true)
		try JavaTestDirectory.write("""
		package com.example.greeter;

		public class Greeter {
			public String greeting() {
				return "hello";
			}
		}
		""", to: staging.appendingPathComponent("com/example/greeter/Greeter.java"))

		// `<group as directories>/<artifact>/<version>/<artifact>-<version>-sources.jar`,
		// which is the whole of Maven's layout and the whole of what the fork
		// added: the same pipeline that walks the Gradle cache, told about a
		// second place to look.
		let jar = home.appendingPathComponent(
			".m2/repository/com/example/greeter/1.0/greeter-1.0-sources.jar"
		)
		try FileManager.default.createDirectory(
			at: jar.deletingLastPathComponent(), withIntermediateDirectories: true
		)
		let zipped = RuntimeCommand.run(
			("/usr/bin/zip", ["-q", "-r", jar.path, "com"]), deadline: 30, directory: staging
		)
		#expect(zipped.exitCode == 0, "could not make the sources jar: \(zipped.errorOutput)")
		try? FileManager.default.removeItem(at: staging)
		return home
	}

	/// A two-module Maven reactor: a root that is only a pom, and one module
	/// with a class of its own and an import of the dependency that exists
	/// nowhere but the repository above.
	///
	/// The shape matters and it took a wrong turn to find out. Written first as
	/// one module — `pom.xml` and `src/main/java` in the same directory — the
	/// server indexed the project, found the sources jar, and answered `null` for
	/// two minutes. The reason is `detect_build_layout_source_paths`: with no
	/// `workspace.json` it probes `<root>/src/*/java`, and everything under a
	/// path it returns is classified `SourceSet::Library` — so the workspace has
	/// no Kotlin/Java sources of its *own*, and the gate in front of the whole
	/// dependency pipeline stays shut. `jar: no Kotlin/Java sources in the
	/// workspace` is the one line in the log that says so.
	///
	/// A reactor has no `src` at its root, so nothing is probed, nothing is
	/// misclassified, and the pipeline runs. That is also the shape 0450 measured
	/// against, which is why it never saw this. It is a fault in the server
	/// rather than in anything here — worth an upstream issue, and written down
	/// in 0457 — but a test has to be about one thing, and this one is about the
	/// mounts.
	private func makeMavenProject(image: String) throws -> URL {
		let root = try JavaTestDirectory.make()
		try JavaTestDirectory.write("""
		{"languages": {"java": "kmp-lsp"}, "kmp-lsp": "\(image)"}
		""", to: ToolImages.url(in: root))
		try JavaTestDirectory.write("""
		<project>
			<modelVersion>4.0.0</modelVersion>
			<groupId>com.example</groupId>
			<artifactId>reactor</artifactId>
			<version>1.0</version>
			<packaging>pom</packaging>
			<modules><module>app</module></modules>
		</project>
		""", to: root.appendingPathComponent("pom.xml"))
		try JavaTestDirectory.write("""
		<project>
			<modelVersion>4.0.0</modelVersion>
			<parent>
				<groupId>com.example</groupId>
				<artifactId>reactor</artifactId>
				<version>1.0</version>
			</parent>
			<artifactId>app</artifactId>
		</project>
		""", to: root.appendingPathComponent("app/pom.xml"))
		try JavaTestDirectory.write("""
		package app;

		import com.example.greeter.Greeter;

		public class App {
		    public static void main(String[] args) {
		        Greeter greeter = new Greeter();
		        System.out.println(greeter.greeting());
		    }
		}
		""", to: root.appendingPathComponent("app/src/main/java/app/App.java"))
		return URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)
	}

	/// The one this whole item is about: a Java project in a container, and
	/// go-to-definition into a dependency that lives in `~/.m2`.
	///
	/// It is the exact answer 0450 measured on this machine going from `null` to
	/// a file and a line, asked of a server that has never seen this filesystem.
	/// Everything has to hold at once for it to come back: the image has to
	/// carry `kmp-jar-indexer`, or the jar pipeline never runs; the repository
	/// has to be mounted where the image looks for it, or it is an empty cache;
	/// the scratch directory has to be mounted writable, or the source is
	/// unpacked somewhere this machine cannot see; and every URI has to cross
	/// both ways, or the answer names a file that does not exist here. Any one
	/// of them wrong is `null` or a path that opens nothing, which is what the
	/// project would show.
	@Test func kmpLspBuiltHereReachesADependencyInTheMavenRepositoryOnThisMachine() async throws {
		guard let recipe = ToolImageRecipes.recipe(forTool: "kmp-lsp"), let runtime else { return }
		let alreadyBuilt = holdsImage(recipe.image, in: runtime)
		guard alreadyBuilt || mayBuild else { return }

		let home = try makeMavenHome()
		let root = try makeMavenProject(image: ToolImageRecipes.buildHere)
		defer {
			try? FileManager.default.removeItem(at: home)
			try? FileManager.default.removeItem(at: root)
		}

		let asked = try #require(ToolImages.inProject(root).image(for: "kmp-lsp"))
		let resolved = try #require(LanguageServers.resolve(
			languageId: "java", project: root, image: asked, runtime: runtime,
			choosing: LanguageServerChoices.settings(["java": "kmp-lsp"]), home: home
		))
		#expect(resolved.definition.name == "kmp-lsp")
		let image = try #require(resolved.launch.image)
		#expect(image.name == recipe.image)

		let store = ContainerImageStore()
		#expect(await store.ensure(image.name, using: runtime).isReady)

		let run = resolved.launch.invocation
		// Three mounts and not one, which is the item: the project, the Maven
		// repository read-only, and the scratch directory the server unpacks
		// into. The Gradle cache is not on this fixture home and so is not here.
		#expect(run.arguments.contains("\(root.path):/workspace"))
		#expect(run.arguments.contains(
			"\(home.appendingPathComponent(".m2/repository").path):/root/.m2/repository:ro"
		))
		#expect(run.arguments.contains(
			"\(home.appendingPathComponent(".cache/kmp-lsp").path):/root/.cache/kmp-lsp"
		))

		let paths = try #require(resolved.launch.paths)
		let client = LSPClient()
		client.containerPaths = paths
		client.callbackQueue = .global()
		defer { client.stop() }

		let file = root.appendingPathComponent("app/src/main/java/app/App.java")
		let fileURI = URL(fileURLWithPath: FilePath.canonical(file)).absoluteString
		try client.start(
			executable: run.executable, arguments: run.arguments,
			workingDirectory: root, environment: LanguageServers.serverEnvironment
		)
		_ = try await client.initialize(rootURL: root, timeout: 60)
		let text = try String(contentsOf: file, encoding: .utf8)
		client.didOpen(uri: fileURI, languageId: "java", version: 1, text: text)

		// The project's own half first, which works with no mount but the
		// project and is what 0450 called the half that matters most.
		let symbols = try await client.documentSymbols(uri: fileURI)
		#expect(symbols.contains { $0.name.hasPrefix("App") })

		// And then across the boundary. Asked in a loop because the jar phase is
		// beside the critical path rather than on it: the workspace is ready in
		// well under a second and the repository is walked after it, so a single
		// question at a fixed delay measures the delay. 0450 made the same point
		// about `--lsp-wait`.
		let declaration = try await answer(deadline: 120) {
			try await client.definition(
				uri: fileURI, position: LSPPosition(line: 6, character: 10)
			).first
		}
		let target = try #require(
			declaration,
			"go-to-definition into the Maven dependency answered nothing, which is the state before the mounts"
		)

		// A file on *this* machine, in the directory the container unpacked it
		// into, holding the source that was inside the jar. Named `Greeter.java`
		// under the jar's own entry path, the way the editor would open it.
		let unpacked = try #require(target.url)
		#expect(unpacked.lastPathComponent == "Greeter.java")
		#expect(unpacked.path.hasPrefix(home.appendingPathComponent(".cache/kmp-lsp").path))
		#expect(FileManager.default.fileExists(atPath: unpacked.path))
		let source = try String(contentsOf: unpacked, encoding: .utf8)
		#expect(source.contains("class Greeter"))
		#expect(target.range.start.line == 2)
	}

	/// The answer once there is one, or nil when the deadline passes.
	///
	/// A poll rather than a sleep, for the reason 0450 gives: a fixed wait can
	/// only report whether the guess was long enough.
	private func answer<T>(
		deadline: TimeInterval, _ ask: () async throws -> T?
	) async throws -> T? {
		let until = Date().addingTimeInterval(deadline)
		while Date() < until {
			if let found = try await ask() { return found }
			try await Task.sleep(nanoseconds: 500_000_000)
		}
		return nil
	}
}
