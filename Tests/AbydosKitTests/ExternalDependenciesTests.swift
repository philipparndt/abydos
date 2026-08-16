import Foundation
import Testing
@testable import AbydosKit

/// What a project depends on, read from what is already on disk.
///
/// The section this feeds exists because a file opened by following a symbol —
/// `Extrusion.swift`, out of Cadova, under `.build/checkouts` — had nowhere to
/// be shown. Every claim here is about one of the three questions that file
/// raises: which package is this, where did it come from, and what is beside it.
struct ExternalDependenciesTests {
	private func makeRoot() throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("abydos-deps-tests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return URL(fileURLWithPath: FilePath.canonical(url), isDirectory: true)
	}

	@discardableResult
	private func write(_ contents: String, to url: URL) throws -> URL {
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true
		)
		try Data(contents.utf8).write(to: url)
		return url
	}

	private let resolvedVersion3 = """
	{
	  "originHash" : "0594b075",
	  "pins" : [
	    {
	      "identity" : "cadova",
	      "kind" : "remoteSourceControl",
	      "location" : "https://github.com/tomasf/Cadova.git",
	      "state" : { "revision" : "5aa45a17f4ae09422d55d539910b58d4473924f8", "version" : "0.9.1" }
	    },
	    {
	      "identity" : "apus",
	      "kind" : "remoteSourceControl",
	      "location" : "https://github.com/tomasf/Apus.git",
	      "state" : { "revision" : "3ccc37d6", "version" : "0.1.4" }
	    }
	  ],
	  "version" : 3
	}
	"""

	// MARK: - Swift packages

	/// The name on the row is the repository's, not SwiftPM's identity.
	///
	/// `identity` is lower-cased — "cadova" — so a row taken from it would match
	/// neither the directory the sources are in nor the `import Cadova` somebody
	/// wrote. Sorted by name, because the section is browsed rather than read in
	/// resolution order.
	@Test func aResolvedSwiftPackageIsNamedAfterItsRepository() throws {
		let root = try makeRoot()
		try write(resolvedVersion3, to: root.appendingPathComponent("Package.resolved"))

		let set = ExternalDependencies.read(root: root, kind: .swiftPackage)
		#expect(set.packages.map(\.name) == ["Apus", "Cadova"])
		#expect(set.packages.first(where: { $0.name == "Cadova" })?.version == "0.9.1")
		#expect(set.packages.first(where: { $0.name == "Cadova" })?.origin
			== "https://github.com/tomasf/Cadova.git")
	}

	/// The checkout under `.build` is what makes the siblings browsable, and a
	/// package that has not been fetched says so by having nothing to open
	/// rather than by pointing at a directory that is not there.
	@Test func aPackageKnowsItsCheckoutWhenOneHasBeenFetched() throws {
		let root = try makeRoot()
		try write(resolvedVersion3, to: root.appendingPathComponent("Package.resolved"))
		try write("// a source\n", to: root.appendingPathComponent(
			".build/checkouts/Cadova/Sources/Cadova/Extrusion.swift"
		))

		let set = ExternalDependencies.read(root: root, kind: .swiftPackage)
		let cadova = try #require(set.packages.first { $0.name == "Cadova" })
		#expect(cadova.localPath?.lastPathComponent == "Cadova")
		// Apus is in the same `Package.resolved` and was never fetched.
		#expect(set.packages.first { $0.name == "Apus" }?.localPath == nil)
	}

	/// **The copy the language server opens, and not the one `swift build`
	/// makes.** sourcekit-lsp is started with `--scratch-path` under
	/// `~/Library/Caches/abydos/index`, so following a symbol lands in *that*
	/// checkout — a section that knew only about `.build/checkouts` gave the
	/// file in the tab no home, which is the failure this item exists to fix,
	/// and it looked correct against every fixture until the real gesture was
	/// tried in the app.
	@Test func theIndexersCheckoutIsPreferredToTheOneUnderBuild() throws {
		let root = try makeRoot()
		try write(resolvedVersion3, to: root.appendingPathComponent("Package.resolved"))
		try write("// built\n", to: root.appendingPathComponent(
			".build/checkouts/Cadova/Sources/Cadova/Extrusion.swift"
		))
		let indexed = LanguageServers.indexScratchPath(for: root)
			.appendingPathComponent("checkouts/Cadova")
		try write("// indexed\n", to: indexed.appendingPathComponent("Sources/Cadova/Extrusion.swift"))
		defer { try? FileManager.default.removeItem(at: LanguageServers.indexScratchPath(for: root)) }

		let set = ExternalDependencies.read(root: root, kind: .swiftPackage)
		let cadova = try #require(set.packages.first { $0.name == "Cadova" })
		#expect(cadova.localPath?.path == indexed.path)

		// And the file the editor would be showing is found in it.
		let tree = try #require(DependencyTree(sets: [set], project: root))
		let opened = indexed.appendingPathComponent("Sources/Cadova/Extrusion.swift")
		#expect(tree.package(containing: opened)?.name == "Cadova")

		// The other copy is still recognised, and resolves to the row the
		// section is drawing — otherwise a file opened from `.build` falls back
		// to the ordinary tree, which opens `.build` and walks ten levels down
		// to the same file. That duplicate is what the section replaces.
		let built = root.appendingPathComponent(
			".build/checkouts/Cadova/Sources/Cadova/Extrusion.swift"
		)
		let located = try #require(tree.locate(built))
		#expect(located.node.url.path == opened.path)
	}

	/// A checkout resolved by an older Xcode writes `object.pins` with
	/// `repositoryURL`. Refusing to read it would make the section empty itself
	/// on an old checkout, which reads as "this project has no dependencies".
	@Test func theFirstLayoutOfPackageResolvedIsStillRead() throws {
		let root = try makeRoot()
		try write("""
		{
		  "object" : {
		    "pins" : [
		      {
		        "package" : "Alamofire",
		        "repositoryURL" : "https://github.com/Alamofire/Alamofire.git",
		        "state" : { "revision" : "abcdef1234567890", "version" : "5.8.0" }
		      }
		    ]
		  },
		  "version" : 1
		}
		""", to: root.appendingPathComponent("Package.resolved"))

		let set = ExternalDependencies.read(root: root, kind: .swiftPackage)
		#expect(set.packages.map(\.name) == ["Alamofire"])
		#expect(set.packages.first?.version == "5.8.0")
	}

	/// A branch or a bare revision is a version too — the point of the field is
	/// "which one of it", and a package pinned to a branch has an answer.
	@Test func aPinWithNoVersionShowsWhateverItIsPinnedTo() throws {
		let root = try makeRoot()
		try write("""
		{ "pins" : [
		  { "identity" : "alpha", "location" : "https://example.com/alpha.git",
		    "state" : { "branch" : "main", "revision" : "0123456789abcdef" } },
		  { "identity" : "beta", "location" : "https://example.com/beta.git",
		    "state" : { "revision" : "fedcba9876543210" } }
		], "version" : 3 }
		""", to: root.appendingPathComponent("Package.resolved"))

		let set = ExternalDependencies.read(root: root, kind: .swiftPackage)
		#expect(set.packages.map(\.version) == ["main", "fedcba9"])
	}

	/// A package that is read and has resolved nothing is not the same as one
	/// nothing can read, and the section says which.
	@Test func aSwiftPackageWithNothingResolvedSaysSoRatherThanShowingNothing() throws {
		let root = try makeRoot()
		try write("// swift-tools-version: 6.0\n", to: root.appendingPathComponent("Package.swift"))

		let set = ExternalDependencies.read(root: root, kind: .swiftPackage)
		guard case let .unresolved(reason) = set.contents else {
			Issue.record("expected unresolved, got \(set.contents)")
			return
		}
		#expect(reason.contains("Package.resolved"))
	}

	// MARK: - Go modules

	/// `go.mod` is the manifest and the resolved set at once, and both forms of
	/// `require` are in the same file in every real project.
	@Test func goModulesComeOutOfBothFormsOfRequire() throws {
		let root = try makeRoot()
		try write("""
		module gokcat

		go 1.24.4

		require github.com/spf13/cobra v1.10.1

		require (
			github.com/IBM/sarama v1.46.3
			github.com/hamba/avro/v2 v2.30.0 // indirect
		)
		""", to: root.appendingPathComponent("go.mod"))

		let set = ExternalDependencies.read(root: root, kind: .goModule)
		#expect(set.packages.map(\.name) == [
			"github.com/hamba/avro/v2", "github.com/IBM/sarama", "github.com/spf13/cobra",
		])
		#expect(set.packages.first { $0.name == "github.com/IBM/sarama" }?.version == "v1.46.3")
	}

	/// A module path is where it came from: Go has no separate URL, and a
	/// module is fetched by being named.
	@Test func aGoModulesOriginIsItsModulePath() throws {
		let root = try makeRoot()
		try write("module m\n\nrequire golang.org/x/net v0.30.0\n",
			to: root.appendingPathComponent("go.mod"))

		let set = ExternalDependencies.read(root: root, kind: .goModule)
		#expect(set.packages.first?.origin == "golang.org/x/net")
		#expect(set.packages.first?.shortOrigin == "golang.org/x")
	}

	/// The module cache escapes an upper-case letter rather than lower-casing
	/// it, because case alone cannot name a directory on this file system.
	/// Without this every module with a capital in its path had no sources and
	/// looked like one nobody had fetched.
	@Test func theModuleCacheEscapesCapitalsWithABang() {
		#expect(ExternalDependencies.escapeGoPath("github.com/IBM/sarama")
			== "github.com/!i!b!m/sarama")
		#expect(ExternalDependencies.escapeGoPath("github.com/spf13/cobra")
			== "github.com/spf13/cobra")
	}

	/// A module with no `require` at all has no dependencies, and that is a
	/// reading rather than a failure to read.
	@Test func aGoModuleWithNoRequiresIsReadAsHavingNone() throws {
		let root = try makeRoot()
		try write("module github.com/philipparndt/abydos-examples/go-service\n\ngo 1.24\n",
			to: root.appendingPathComponent("go.mod"))

		let set = ExternalDependencies.read(root: root, kind: .goModule)
		guard case let .packages(packages) = set.contents else {
			Issue.record("expected packages, got \(set.contents)")
			return
		}
		#expect(packages.isEmpty)
	}

	/// The sources are outside the project entirely — the case this item is
	/// really about, and the one a Swift-only version never meets.
	@Test func aGoModulesSourcesAreFoundInTheModuleCache() throws {
		let root = try makeRoot()
		let cache = try makeRoot()
		try write("module m\n\nrequire github.com/IBM/sarama v1.46.3\n",
			to: root.appendingPathComponent("go.mod"))
		try write("package sarama\n", to: cache.appendingPathComponent(
			"github.com/!i!b!m/sarama@v1.46.3/broker.go"
		))

		let previous = ProcessInfo.processInfo.environment["GOMODCACHE"]
		setenv("GOMODCACHE", cache.path, 1)
		defer {
			if let previous { setenv("GOMODCACHE", previous, 1) } else { unsetenv("GOMODCACHE") }
		}

		let set = ExternalDependencies.read(root: root, kind: .goModule)
		let sarama = try #require(set.packages.first)
		#expect(sarama.localPath?.lastPathComponent == "sarama@v1.46.3")
	}

	// MARK: - Kinds nothing reads yet

	/// **The claim that makes shipping two kinds honest.** A Maven project does
	/// not show an empty section; it shows a row saying its dependencies are not
	/// read, with the number of the item that will read them.
	@Test func aKindNobodyHasTaughtSaysSoRatherThanShowingNothing() throws {
		let root = try makeRoot()
		try write("<project/>\n", to: root.appendingPathComponent("pom.xml"))

		let set = ExternalDependencies.read(root: root, kind: .maven)
		#expect(set.contents == .notRead)

		let tree = try #require(DependencyTree(sets: [set], project: root))
		// The heading names the kind, because with one root there are no group
		// rows and nothing else would say what is not being read.
		// The kind is named once, by the heading. The note under it is the
		// message and nothing else — `Maven — Maven not read yet` is what
		// repeating it produced.
		#expect(tree.report() == ["Dependencies — Maven", "  not read yet (0512)"])
	}

	/// Every kind this program can open is in the list, whether or not it is
	/// read — that is what stops a project's dependencies being silently
	/// omitted, which is the failure the item named in advance.
	@Test func everyKindEitherIsReadOrNamesTheItemThatWillReadIt() {
		for kind in DependencyKind.allCases {
			switch kind {
			case .swiftPackage, .goModule:
				#expect(kind.pendingItem == nil)
			default:
				#expect(kind.pendingItem != nil, "\(kind) says nothing about itself")
			}
		}
	}

	/// The kinds are found by the marks a build system leaves, the same rule
	/// `Subprojects` follows — and a directory with two of them has two
	/// dependency graphs, not one.
	@Test func aDirectoryWithTwoBuildSystemsHasTwoSets() throws {
		let root = try makeRoot()
		try write("<project/>\n", to: root.appendingPathComponent("pom.xml"))
		try write("{}\n", to: root.appendingPathComponent("package.json"))

		#expect(ExternalDependencies.kinds(at: root) == [.npm, .maven])
	}

	// MARK: - The tree

	/// One root's worth needs no heading: the packages hang straight off the
	/// section, because a lone group row answers a question nobody asked.
	@Test func aLoneRootPutsItsPackagesStraightUnderTheSection() throws {
		let root = try makeRoot()
		try write(resolvedVersion3, to: root.appendingPathComponent("Package.resolved"))

		let tree = try #require(DependencyTree(sets: [
			ExternalDependencies.read(root: root, kind: .swiftPackage),
		], project: root))
		#expect(tree.report() == [
			"Dependencies — Swift packages",
			"  Apus — 0.1.4  ·  github.com/tomasf",
			"  Cadova — 0.9.1  ·  github.com/tomasf",
		])
	}

	/// Two subprojects may resolve different versions of the same package, so a
	/// dependency has to say whose it is.
	@Test func moreThanOneRootIsGroupedByTheSubprojectItBelongsTo() throws {
		let project = try makeRoot()
		let models = project.appendingPathComponent("cadova-models")
		let service = project.appendingPathComponent("services/go-service")
		try write(resolvedVersion3, to: models.appendingPathComponent("Package.resolved"))
		try write("module svc\n\nrequire golang.org/x/net v0.30.0\n",
			to: service.appendingPathComponent("go.mod"))

		let tree = try #require(DependencyTree(sets: [
			ExternalDependencies.read(root: models, kind: .swiftPackage),
			ExternalDependencies.read(root: service, kind: .goModule),
		], project: project))
		#expect(tree.report() == [
			"Dependencies",
			"  cadova-models — Swift packages",
			"    Apus — 0.1.4  ·  github.com/tomasf",
			"    Cadova — 0.9.1  ·  github.com/tomasf",
			// The path relative to the project, not the last component: two
			// subprojects called `service` are exactly what this row tells apart.
			"  services/go-service — Go modules",
			"    golang.org/x/net — v0.30.0  ·  golang.org/x",
		])
	}

	/// A project of no recognised kind gets no section rather than an empty one.
	@Test func aProjectWithNoBuildSystemHasNoSection() throws {
		let root = try makeRoot()
		#expect(ExternalDependencies.read(project: root).isEmpty)
		#expect(DependencyTree(sets: [], project: root) == nil)
	}

	/// **The item's own case.** A file reached by following a symbol has a place
	/// in the section: which package it is in, and a node whose siblings are the
	/// rest of that package's directory.
	@Test func aFileInsideACheckoutIsFoundInTheSection() throws {
		let root = try makeRoot()
		try write(resolvedVersion3, to: root.appendingPathComponent("Package.resolved"))
		let extrusion = try write("// Extrusion\n", to: root.appendingPathComponent(
			".build/checkouts/Cadova/Sources/Cadova/Extrusion.swift"
		))
		try write("// Sphere\n", to: root.appendingPathComponent(
			".build/checkouts/Cadova/Sources/Cadova/Sphere.swift"
		))

		let tree = try #require(DependencyTree(sets: [
			ExternalDependencies.read(root: root, kind: .swiftPackage),
		], project: root))

		let found = try #require(tree.locate(extrusion))
		#expect(found.node.name == "Extrusion.swift")
		#expect(tree.package(containing: extrusion)?.name == "Cadova")
		#expect(tree.package(containing: extrusion)?.origin
			== "https://github.com/tomasf/Cadova.git")

		// And the siblings, which is the other half of what was asked for.
		let folder = try #require(found.node.parentNodeForTesting)
		#expect(folder.children.map(\.name).sorted() == ["Extrusion.swift", "Sphere.swift"])
	}

	/// A file that is in neither the project nor any package is in neither, and
	/// the tree says nothing rather than picking the nearest package.
	@Test func aFileInNoPackageIsNotFound() throws {
		let root = try makeRoot()
		try write(resolvedVersion3, to: root.appendingPathComponent("Package.resolved"))
		try write("x\n", to: root.appendingPathComponent(".build/checkouts/Cadova/README.md"))

		let tree = try #require(DependencyTree(sets: [
			ExternalDependencies.read(root: root, kind: .swiftPackage),
		], project: root))
		#expect(tree.locate(URL(fileURLWithPath: "/etc/hosts")) == nil)
	}
}

private extension FileNode {
	/// The folder a found node sits in, for the sibling claim.
	var parentNodeForTesting: FileNode? { parent }
}
