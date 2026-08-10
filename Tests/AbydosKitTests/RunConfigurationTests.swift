import Testing
import Foundation
@testable import AbydosKit

/// Makefile targets. The file format has more shapes that are *not* targets
/// than shapes that are.
/// A Makefile's targets, as things to jump to.
///
/// ⇧⌘O on a Makefile listed nothing for as long as this existed, because it
/// asked whether the language was `makefile` — and a Makefile is highlighted
/// with bash's grammar, so the language is `bash` and the answer was always no.
struct MakefileSymbolTests {
	private func write(_ text: String, named name: String = "Makefile") throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("mk-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		let url = root.appendingPathComponent(name)
		try text.write(to: url, atomically: true, encoding: .utf8)
		return url
	}

	@Test func recognisesTheNamesMakeItselfLooksFor() {
		let base = URL(fileURLWithPath: "/tmp/p")
		#expect(Makefile.isMakefile(base.appendingPathComponent("Makefile")))
		#expect(Makefile.isMakefile(base.appendingPathComponent("makefile")))
		#expect(Makefile.isMakefile(base.appendingPathComponent("GNUmakefile")))
		#expect(Makefile.isMakefile(base.appendingPathComponent("common.mk")))
		#expect(!Makefile.isMakefile(base.appendingPathComponent("main.go")))
		#expect(!Makefile.isMakefile(base.appendingPathComponent("Makefile.md")))
	}

	@Test func everyTargetIsSomethingToJumpTo() throws {
		let url = try write("""
		BINARY := build/app

		.PHONY: build
		build: ## Build it
		\tgo build -o $(BINARY)

		.PHONY: test
		test:
		\tgo test ./...
		""")
		defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

		let symbols = Makefile.symbols(at: url)
		#expect(symbols.map(\.name) == ["build", "test"])
		// The comment beside a target is what tells one apart from another in a
		// list of twenty.
		#expect(symbols.first?.container == "Build it")
	}

	/// The line has to be the rule's own, so jumping to `install` does not land
	/// on `installed:` further up.
	@Test func aTargetLandsOnItsOwnRule() throws {
		let url = try write("""
		installed:
		\techo no

		install:
		\techo yes
		""")
		defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

		let symbols = Makefile.symbols(at: url)
		let install = try #require(symbols.first { $0.name == "install" })
		#expect(install.location.range.start.line == 3)
	}
}

struct MakefileParseTests {
	private func targets(_ text: String) -> [String] {
		RunConfigurationDiscovery
			.parseMakefile(text, path: "/p/Makefile", directory: "/p")
			.map(\.name)
	}

	@Test func findsPlainTargets() {
		#expect(targets("build:\n\techo hi\nclean:\n\trm -rf x\n") == ["build", "clean"])
	}

	@Test func targetsWithPrerequisitesCount() {
		#expect(targets("run: build\n\t./x\n") == ["run"])
	}

	/// .PHONY is a directive, not something to run.
	@Test func directivesAreNotTargets() {
		#expect(targets(".PHONY: build\nbuild:\n\techo\n") == ["build"])
	}

	@Test func variableAssignmentsAreNotTargets() {
		#expect(targets("GO = go\nGOFLAGS := -v\nCONFIG ::= x\nbuild:\n\techo\n") == ["build"])
	}

	@Test func patternRulesAreSkipped() {
		#expect(targets("%.o: %.c\n\tcc\nbuild:\n\techo\n") == ["build"])
	}

	@Test func recipeLinesAreNotTargets() {
		// A recipe starts with a tab, and may well contain a colon.
		#expect(targets("build:\n\tdocker run a:b\n") == ["build"])
	}

	@Test func commentsAreSkipped() {
		#expect(targets("# note: this\nbuild:\n\techo\n") == ["build"])
	}

	@Test func duplicatesAreListedOnce() {
		#expect(targets("build:\n\techo\nbuild: extra\n\techo\n") == ["build"])
	}

	@Test func theTargetLineIsRecorded() {
		let found = RunConfigurationDiscovery.parseMakefile(
			"# header\n\nbuild:\n\techo\n", path: "/p/Makefile", directory: "/p"
		)
		#expect(found.first?.line == 3)
		#expect(found.first?.file == "/p/Makefile")
	}

	@Test func theCommandIsMakeTarget() {
		let found = RunConfigurationDiscovery.parseMakefile(
			"build:\n\techo\n", path: "/p/Makefile", directory: "/p"
		)
		#expect(found.first?.commandLine == "make build")
		#expect(found.first?.workingDirectory == "/p")
	}
}

/// Go entry points. `go run` needs the directory of a main package.
struct GoMainDetectionTests {
	@Test func findsMainInAMainPackage() {
		#expect(RunConfigurationDiscovery.mainFunctionLine(in: """
		package main

		func main() {
		}
		""") == 3)
	}

	/// A `main` function in a library package is not an entry point.
	@Test func ignoresMainOutsidePackageMain() {
		#expect(RunConfigurationDiscovery.mainFunctionLine(in: """
		package helper

		func main() {
		}
		""") == nil)
	}

	@Test func ignoresIndentedMain() {
		// A nested function is not the entry point.
		#expect(RunConfigurationDiscovery.mainFunctionLine(in: """
		package main

		func wrapper() {
			func main() {}
		}
		""") == nil)
	}

	@Test func aPackageWithNoMainHasNoEntryPoint() {
		#expect(RunConfigurationDiscovery.mainFunctionLine(in: "package main\n\nfunc helper() {}\n") == nil)
	}
}

/// launch.json is JSON with comments and trailing commas, which
/// JSONSerialization rejects outright.
struct JSONCommentStrippingTests {
	private func strip(_ text: String) -> String {
		RunConfigurationDiscovery.stripJSONComments(text)
	}

	@Test func removesLineComments() {
		#expect(strip("{\n // note\n \"a\": 1\n}").contains("note") == false)
	}

	@Test func removesBlockComments() {
		#expect(strip("{ /* note */ \"a\": 1 }").contains("note") == false)
	}

	/// The case a naive strip corrupts: a URL inside a string contains `//`.
	@Test func leavesSlashesInsideStringsAlone() {
		let text = "{ \"url\": \"https://example.com/x\" }"
		#expect(strip(text) == text)
	}

	@Test func removesTrailingCommas() {
		let stripped = strip("{ \"a\": [1, 2,], }")
		#expect((try? JSONSerialization.jsonObject(with: Data(stripped.utf8))) != nil)
	}

	@Test func keepsOrdinaryCommas() {
		let stripped = strip("{ \"a\": 1, \"b\": 2 }")
		let object = (try? JSONSerialization.jsonObject(with: Data(stripped.utf8))) as? [String: Any]
		#expect(object?.count == 2)
	}
}

struct VSCodeLaunchTests {
	private let root = URL(fileURLWithPath: "/proj")

	@Test func readsAGoConfiguration() {
		let json = """
		{
		  // launch config
		  "version": "0.2.0",
		  "configurations": [
		    {
		      "name": "Run app",
		      "type": "go",
		      "request": "launch",
		      "program": "${workspaceFolder}/app",
		      "args": ["--config", "${workspaceFolder}/c.json"],
		      "cwd": "${workspaceFolder}/app",
		      "env": { "LOG": "debug" },
		    },
		  ]
		}
		"""
		let found = RunConfigurationDiscovery.parseLaunchJSON(Data(json.utf8), root: root)
		#expect(found.count == 1)
		#expect(found.first?.name == "Run app")
		#expect(found.first?.workingDirectory == "/proj/app")
		#expect(found.first?.arguments == ["run", "/proj/app", "--config", "/proj/c.json"])
		#expect(found.first?.environment["LOG"] == "debug")
	}

	/// Only Go is understood; offering a configuration that cannot run is worse
	/// than not listing it.
	@Test func skipsTypesThatAreNotUnderstood() {
		let json = """
		{"configurations": [{"name": "node thing", "type": "node", "program": "x.js"}]}
		"""
		#expect(RunConfigurationDiscovery.parseLaunchJSON(Data(json.utf8), root: root).isEmpty)
	}

	@Test func malformedJSONIsNotACrash() {
		#expect(RunConfigurationDiscovery.parseLaunchJSON(Data("{ not json".utf8), root: root).isEmpty)
	}
}

struct ArgumentSplittingTests {
	@Test func splitsOnWhitespace() {
		#expect(RunConfigurationDiscovery.splitArguments("--a b  c") == ["--a", "b", "c"])
	}

	@Test func keepsQuotedRunsTogether() {
		#expect(RunConfigurationDiscovery.splitArguments("--path \"/a b/c\"") == ["--path", "/a b/c"])
		#expect(RunConfigurationDiscovery.splitArguments("'one two'") == ["one two"])
	}

	@Test func anEmptyStringIsNoArguments() {
		#expect(RunConfigurationDiscovery.splitArguments("   ").isEmpty)
	}
}

/// Against a project laid out the way real ones are: the module in a
/// subdirectory, not at the root.
struct RunDiscoveryIntegrationTests {
	private func makeProject() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-run-\(UUID().uuidString)")
		let app = root.appendingPathComponent("app")
		try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

		try "module example.com/thing\n".write(
			to: app.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
		try "package main\n\nfunc main() {\n}\n".write(
			to: app.appendingPathComponent("main.go"), atomically: true, encoding: .utf8)
		try "build:\n\techo build\nrun: build\n\t./x\n".write(
			to: app.appendingPathComponent("Makefile"), atomically: true, encoding: .utf8)
		return root
	}

	/// The case that used to report "this project has no go.mod at its root".
	@Test func findsAModuleInASubdirectory() throws {
		let root = try makeProject()
		let found = RunConfigurationDiscovery.discover(in: root)
		let go = found.filter { $0.source == .goModule }
		#expect(go.count == 1)
		#expect(go.first?.workingDirectory.hasSuffix("/app") == true)
	}

	@Test func findsMakeTargetsInASubdirectory() throws {
		let root = try makeProject()
		let make = RunConfigurationDiscovery.discover(in: root).filter { $0.source == .make }
		#expect(Set(make.map(\.name)) == ["build", "run"])
	}

	@Test func aGoEntryPointCarriesItsFileAndLine() throws {
		let root = try makeProject()
		let go = RunConfigurationDiscovery.discover(in: root).first { $0.source == .goModule }
		#expect(go?.file?.hasSuffix("app/main.go") == true)
		#expect(go?.line == 3)
	}

	@Test func readsAnIntelliJWorkspaceConfiguration() throws {
		let root = try makeProject()
		let idea = root.appendingPathComponent(".idea")
		try FileManager.default.createDirectory(at: idea, withIntermediateDirectories: true)
		try """
		<project version="4">
		  <component name="RunManager">
		    <configuration name="go build thing" type="GoApplicationRunConfiguration" factoryName="Go Application">
		      <working_directory value="$PROJECT_DIR$/app" />
		      <parameters value="$PROJECT_DIR$/production/config.json" />
		      <kind value="PACKAGE" />
		      <filePath value="$PROJECT_DIR$/app/main.go" />
		    </configuration>
		  </component>
		</project>
		""".write(to: idea.appendingPathComponent("workspace.xml"), atomically: true, encoding: .utf8)

		let found = RunConfigurationDiscovery.discover(in: root).filter { $0.source == .intelliJ }
		#expect(found.count == 1)
		#expect(found.first?.name == "go build thing")
		#expect(found.first?.workingDirectory.hasSuffix("/app") == true)
		#expect(found.first?.arguments.contains { $0.hasSuffix("production/config.json") } == true)
	}

	@Test func nonGoIntelliJConfigurationsAreSkipped() throws {
		let root = try makeProject()
		let idea = root.appendingPathComponent(".idea")
		try FileManager.default.createDirectory(at: idea, withIntermediateDirectories: true)
		try """
		<project version="4"><component name="RunManager">
		  <configuration name="npm start" type="js.build_tools.npm" />
		</component></project>
		""".write(to: idea.appendingPathComponent("workspace.xml"), atomically: true, encoding: .utf8)

		#expect(RunConfigurationDiscovery.discover(in: root).allSatisfy { $0.source != .intelliJ })
	}

	@Test func dependencyDirectoriesAreNotScanned() throws {
		let root = try makeProject()
		let vendored = root.appendingPathComponent("node_modules/dep")
		try FileManager.default.createDirectory(at: vendored, withIntermediateDirectories: true)
		try "build:\n\techo\n".write(
			to: vendored.appendingPathComponent("Makefile"), atomically: true, encoding: .utf8)

		let make = RunConfigurationDiscovery.discover(in: root).filter { $0.source == .make }
		#expect(make.allSatisfy { !$0.workingDirectory.contains("node_modules") })
	}
}

/// Paths handed to other processes have to be real, not merely comparable.
struct CanonicalPathTests {
	/// Foundation's resolvingSymlinksInPath rewrites a leading /private back to
	/// /tmp, which is the opposite of resolving. Comparisons still matched, so
	/// the bug only showed when the path reached `go`.
	@Test func resolvesRatherThanRewriting() throws {
		let directory = URL(fileURLWithPath: "/tmp")
			.appendingPathComponent("ideai-canon-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let resolved = RunConfigurationDiscovery.canonicalPath(directory)
		#expect(resolved.hasPrefix("/private/tmp/"))
		#expect(FileManager.default.fileExists(atPath: resolved))
	}

	/// The same file reached two ways still compares equal.
	@Test func twoRoutesToOneFileAgree() throws {
		let name = "ideai-canon-\(UUID().uuidString)"
		let viaTmp = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
		try FileManager.default.createDirectory(at: viaTmp, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: viaTmp) }

		let viaPrivate = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(name)
		#expect(
			RunConfigurationDiscovery.canonicalPath(viaTmp)
				== RunConfigurationDiscovery.canonicalPath(viaPrivate)
		)
	}

	@Test func aMissingPathIsReturnedUnchanged() {
		let missing = URL(fileURLWithPath: "/no/such/place/at/all")
		#expect(RunConfigurationDiscovery.canonicalPath(missing) == "/no/such/place/at/all")
	}
}

/// Which writes are worth rescanning a project for.
///
/// 0446: opening the Eclipse Platform corpus spent 668 seconds of processor
/// time in the first ninety, because a language server importing a Tycho
/// reactor writes Eclipse metadata into a thousand bundles and each of those
/// writes started a fresh walk of 45,772 Java files looking for `main`.
struct RunConfigurationRescanTests {
	private let bundle = URL(fileURLWithPath: "/p/org.eclipse.ui.workbench")

	/// The files jdtls writes while it imports. None of them can add a way to
	/// run anything, and there are a thousand bundles' worth of them.
	@Test func languageServerMetadataIsNotWorthAScan() {
		#expect(!RunConfigurationDiscovery.couldDefineConfiguration(
			bundle.appendingPathComponent(".project")))
		#expect(!RunConfigurationDiscovery.couldDefineConfiguration(
			bundle.appendingPathComponent(".classpath")))
		#expect(!RunConfigurationDiscovery.couldDefineConfiguration(
			bundle.appendingPathComponent(".settings/org.eclipse.jdt.core.prefs")))
		#expect(!RunConfigurationDiscovery.couldDefineConfiguration(
			bundle.appendingPathComponent("META-INF/MANIFEST.MF")))
		#expect(!RunConfigurationDiscovery.couldDefineConfiguration(
			bundle.appendingPathComponent("target/classes/Foo.class")))
	}

	/// And the files that really do decide what a project can run.
	@Test func sourceAndBuildFilesAreWorthAScan() {
		for path in [
			"src/main/java/org/eclipse/App.java",
			"src/Main.kt",
			"pom.xml",
			"Makefile",
			"go.mod",
			"build.gradle.kts",
			"BUILD.bazel",
			"conanfile.py",
			".idea/workspace.xml",
			".idea/runConfigurations/Serve.xml",
			".vscode/launch.json",
			"App.xcodeproj/project.pbxproj",
		] {
			#expect(
				RunConfigurationDiscovery.couldDefineConfiguration(
					bundle.appendingPathComponent(path)),
				"\(path) should be worth a scan"
			)
		}
	}

	@Test func aBatchOfMetadataIsSkippedWholesale() {
		let change = FileSystemChange(
			directories: [bundle],
			paths: [
				bundle.appendingPathComponent(".project"),
				bundle.appendingPathComponent(".classpath"),
				bundle.appendingPathComponent(".settings/org.eclipse.m2e.core.prefs"),
			],
			namesEveryPath: true
		)
		#expect(!RunConfigurationDiscovery.deservesRescan(after: change))
	}

	/// One source file among a hundred metadata writes still earns the scan:
	/// that is the case where a `main` method really did appear.
	@Test func oneSourceFileAmongTheMetadataEarnsTheScan() {
		var paths = (0..<100).map {
			bundle.appendingPathComponent("bundle\($0)/.classpath")
		}
		paths.append(bundle.appendingPathComponent("src/App.java"))

		let change = FileSystemChange(directories: [bundle], paths: paths, namesEveryPath: true)
		#expect(RunConfigurationDiscovery.deservesRescan(after: change))
	}

	/// A burst too large for FSEvents to describe file by file could be a
	/// checkout that brought a whole module in, so it is scanned. A scan too
	/// many is slow; a scan too few is a play button that never appears.
	@Test func aBatchWithoutNamesIsAlwaysScanned() {
		let change = FileSystemChange(directories: [bundle], paths: [], namesEveryPath: false)
		#expect(RunConfigurationDiscovery.deservesRescan(after: change))
	}
}
