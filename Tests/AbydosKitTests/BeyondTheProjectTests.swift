import Foundation
import Testing
@testable import AbydosKit

/// A language server that reads something which is not in the project.
///
/// A tool container is given the project and nothing else, and everything
/// outside it is refused rather than guessed at. That is right for every server
/// but one: kmp-lsp has no classpath and runs no build tool, so it finds a
/// library's source by walking `~/.m2/repository` and `~/.gradle/caches` — and
/// a copy of it in a container with one mount indexes the project perfectly and
/// answers nothing at every dependency boundary, which is the failure 0450's
/// fork was written to end.
///
/// So a definition may name directories beyond the project, and this is what
/// holds that to being a short list somebody wrote down rather than a mapping
/// that will translate any path to any other.
struct BeyondTheProjectTests {
	private let runtime = ContainerRuntime.docker("/usr/bin/docker")

	/// A home directory with nothing in it, so what a test is about is what it
	/// puts there and never what this machine happens to have.
	private func makeHome() throws -> URL {
		let home = try JavaTestDirectory.make()
		return URL(fileURLWithPath: FilePath.canonical(home), isDirectory: true)
	}

	private func makeProject() throws -> URL {
		let root = try JavaTestDirectory.make()
		try JavaTestDirectory.write("<project/>\n", to: root.appendingPathComponent("pom.xml"))
		try JavaTestDirectory.write(
			"class Main {}\n", to: root.appendingPathComponent("src/Main.java")
		)
		return URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)
	}

	private var kmp: LanguageServerDefinition {
		get throws { try #require(LanguageServers.server(named: "kmp-lsp")) }
	}

	// MARK: - What the table says

	@Test func theServerSaysWhichDirectoriesItReadsAndWhichOfThemItWritesTo() throws {
		let outside = try kmp.outside
		#expect(outside.map(\.home) == [".m2/repository", ".gradle/caches", ".cache/kmp-lsp"])
		// The two dependency caches are somebody's build tools' and are read.
		// The third is the server's own scratch, where it unpacks a file out of
		// a jar so that this editor can open it, and it is the only one it may
		// write to.
		#expect(outside.filter { !$0.isReadOnly }.map(\.home) == [".cache/kmp-lsp"])
	}

	/// The caches, not the tool homes — and this is the difference that matters
	/// rather than a tidier path. `~/.m2/settings.xml` and
	/// `~/.gradle/gradle.properties` are where registry passwords and signing
	/// keys live, and nothing here has any reason to see them.
	@Test func whatIsMountedIsTheCacheAndNotTheDirectoryAboveIt() throws {
		for directory in try kmp.outside {
			#expect(directory.home != ".m2")
			#expect(directory.home != ".gradle")
		}
	}

	/// Every other server is given the project and nothing else, which is the
	/// rule this is an exception to rather than the exception becoming the rule.
	@Test func everyOtherServerAsksForNothingBeyondTheProject() {
		for definition in LanguageServers.known where definition.name != "kmp-lsp" {
			#expect(definition.outside.isEmpty, "\(definition.name) asks for a directory outside the project")
		}
	}

	// MARK: - A directory that is not there

	/// A machine with no `~/.m2` is an ordinary machine, and a bind mount of a
	/// path that does not exist is a runtime error on one runtime and a
	/// root-owned empty directory conjured into somebody's home folder on the
	/// other. Neither is a thing to do to a machine because an editor opened a
	/// file: the mount is left out, and the server reports no jars, which is
	/// the truth.
	@Test func aReadOnlyDirectoryThatIsNotThereIsLeftOutRatherThanCreated() throws {
		let home = try makeHome()
		defer { try? FileManager.default.removeItem(at: home) }

		let mounts = LanguageServers.mounts(outsideTheProjectFor: try kmp, home: home)
		#expect(!mounts.contains { $0.host.hasSuffix(".m2/repository") })
		#expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".m2").path))
	}

	/// The writable one is the opposite case, and for a reason rather than for
	/// symmetry: it is not somebody's cache, it is where the server puts a file
	/// this side then has to open. Left out, the server writes inside the
	/// container instead and answers with the name of a file that exists
	/// nowhere here — which looks like an answer and opens nothing.
	@Test func theWritableOneIsMadeWhenItIsMissing() throws {
		let home = try makeHome()
		defer { try? FileManager.default.removeItem(at: home) }

		let mounts = LanguageServers.mounts(outsideTheProjectFor: try kmp, home: home)
		let scratch = try #require(mounts.first { $0.container == "/root/.cache/kmp-lsp" })
		#expect(!scratch.isReadOnly)
		#expect(FileManager.default.fileExists(atPath: scratch.host))
	}

	@Test func aDirectoryThatIsThereIsMountedWhereTheImageLooksForIt() throws {
		let home = try makeHome()
		defer { try? FileManager.default.removeItem(at: home) }
		try JavaTestDirectory.write(
			"x\n", to: home.appendingPathComponent(".m2/repository/marker")
		)
		try JavaTestDirectory.write(
			"x\n", to: home.appendingPathComponent(".gradle/caches/marker")
		)

		let mounts = LanguageServers.mounts(outsideTheProjectFor: try kmp, home: home)
		#expect(mounts.count == 3)
		let maven = try #require(mounts.first { $0.container == "/root/.m2/repository" })
		#expect(maven.host == home.appendingPathComponent(".m2/repository").path)
		#expect(maven.isReadOnly)
		// The flag both runtimes take, with the `:ro` on the end: a language
		// server has no business writing to a dependency cache.
		#expect(maven.flag.hasSuffix(":/root/.m2/repository:ro"))
	}

	// MARK: - What the container is started with

	@Test func theProjectIsStillFirstAndTheRestFollowIt() throws {
		let home = try makeHome()
		let project = try makeProject()
		defer {
			try? FileManager.default.removeItem(at: home)
			try? FileManager.default.removeItem(at: project)
		}
		try JavaTestDirectory.write(
			"x\n", to: home.appendingPathComponent(".m2/repository/marker")
		)

		let resolved = try #require(LanguageServers.resolve(
			languageId: "java", project: project,
			image: "example/kmp-lsp:1", runtime: runtime,
			choosing: .settings(["java": "kmp-lsp"]), home: home
		))
		let arguments = resolved.launch.invocation.arguments
		let mounted = zip(arguments, arguments.dropFirst())
			.filter { $0.0 == "-v" }
			.map(\.1)
		#expect(mounted.first == "\(project.path):/workspace")
		#expect(mounted.contains(
			"\(home.appendingPathComponent(".m2/repository").path):/root/.m2/repository:ro"
		))
		// The Gradle cache is not on this fixture home, so it is not on the
		// command line either.
		#expect(!mounted.contains { $0.contains("/root/.gradle/caches") })
	}

	/// The other half, and the half that decides whether any of it is worth
	/// having: a server given a directory it can read will name files in it
	/// back at us, and a name that cannot be brought home is a
	/// go-to-definition that opens nothing.
	@Test func aFileInOneOfThemCrossesInBothDirections() throws {
		let home = try makeHome()
		let project = try makeProject()
		defer {
			try? FileManager.default.removeItem(at: home)
			try? FileManager.default.removeItem(at: project)
		}
		try JavaTestDirectory.write(
			"x\n", to: home.appendingPathComponent(".cache/kmp-lsp/marker")
		)

		let resolved = try #require(LanguageServers.resolve(
			languageId: "java", project: project,
			image: "example/kmp-lsp:1", runtime: runtime,
			choosing: .settings(["java": "kmp-lsp"]), home: home
		))
		let paths = try #require(resolved.launch.paths)

		let unpacked = home.appendingPathComponent(".cache/kmp-lsp/jar-sources/x/A.java").path
		let inside = "/root/.cache/kmp-lsp/jar-sources/x/A.java"
		#expect(paths.toContainer(path: unpacked) == inside)
		#expect(paths.toHost(path: inside) == unpacked)

		// And the project still answers first, which is what almost every
		// question is about.
		#expect(paths.toContainer(path: project.appendingPathComponent("src/Main.java").path)
			== "/workspace/src/Main.java")
	}

	/// Everything else is still refused. This is the sentence the whole feature
	/// has to keep true: what changed is that the list of what a container can
	/// see is longer, not that a path can be translated into whatever seems
	/// plausible.
	@Test func anythingInNoneOfThemIsStillRefused() throws {
		let home = try makeHome()
		let project = try makeProject()
		defer {
			try? FileManager.default.removeItem(at: home)
			try? FileManager.default.removeItem(at: project)
		}
		try JavaTestDirectory.write(
			"x\n", to: home.appendingPathComponent(".m2/repository/marker")
		)

		let resolved = try #require(LanguageServers.resolve(
			languageId: "java", project: project,
			image: "example/kmp-lsp:1", runtime: runtime,
			choosing: .settings(["java": "kmp-lsp"]), home: home
		))
		let paths = try #require(resolved.launch.paths)
		#expect(paths.toContainer(path: "/etc/passwd") == nil)
		#expect(paths.toContainer(path: home.appendingPathComponent(".ssh/id_rsa").path) == nil)
		// The directory above the mount, which is where the credentials are.
		#expect(paths.toContainer(path: home.appendingPathComponent(".m2/settings.xml").path) == nil)
		#expect(paths.toHost(path: "/root/.m2/settings.xml") == nil)
	}

	/// And a server that asks for nothing gets nothing, which is every other
	/// server in the table.
	@Test func aServerThatAsksForNothingIsGivenOneMountAsBefore() throws {
		let home = try makeHome()
		let project = try JavaTestDirectory.make()
		defer {
			try? FileManager.default.removeItem(at: home)
			try? FileManager.default.removeItem(at: project)
		}
		try JavaTestDirectory.write(
			"module example.com/x\n", to: project.appendingPathComponent("go.mod")
		)

		let resolved = try #require(LanguageServers.resolve(
			languageId: "go", project: project,
			image: "example/gopls:1", runtime: runtime, choosing: .none, home: home
		))
		let paths = try #require(resolved.launch.paths)
		#expect(paths.beyond.isEmpty)
		#expect(resolved.launch.invocation.arguments.filter { $0 == "-v" }.count == 1)
	}
}
