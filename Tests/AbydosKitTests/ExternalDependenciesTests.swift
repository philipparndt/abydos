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

	// MARK: - Cargo

	/// A real lock file, from `cargo add serde --features derive`, `cargo add
	/// --path helper` and `cargo add --git https://github.com/dtolnay/anyhow`,
	/// cut to one of each kind. Every shape this reader has to tell apart is in
	/// it: a registry crate, a git crate, a path dependency and the workspace
	/// member that is the project itself.
	private let cargoLock = """
	# This file is automatically @generated by Cargo.
	# It is not intended for manual editing.
	version = 4

	[[package]]
	name = "anyhow"
	version = "1.0.104"
	source = "git+https://github.com/dtolnay/anyhow#bf3ed9149f4334c984c1ad252b534107b307078c"

	[[package]]
	name = "helper"
	version = "0.1.0"

	[[package]]
	name = "probe"
	version = "0.1.0"
	dependencies = [
	 "anyhow",
	 "helper",
	 "serde",
	]

	[[package]]
	name = "serde"
	version = "1.0.229"
	source = "registry+https://github.com/rust-lang/crates.io-index"
	checksum = "4148590afebada386688f18773da617792bf2ef03ffc1e4cbd2b1d45b023e0ba"
	dependencies = [
	 "serde_core",
	]
	"""

	/// The resolved graph is in the lock file and the row names the version on
	/// disk — `Cargo.toml` says `serde = "1"`, which is not an answer.
	@Test func aCargoLockNamesEveryCrateAndTheVersionItResolvedTo() throws {
		let root = try makeRoot()
		try write(cargoLock, to: root.appendingPathComponent("Cargo.lock"))

		let set = ExternalDependencies.read(root: root, kind: .cargo)
		#expect(set.packages.map(\.name) == ["anyhow", "serde"])
		#expect(set.packages.first { $0.name == "serde" }?.version == "1.0.229")
	}

	/// **A path dependency and the project's own crate are not external.** Both
	/// are written into `Cargo.lock` with no `source` at all, and both are
	/// directories the tree already shows — listing them here would show the
	/// project's own source twice, under a heading saying it came from outside.
	@Test func aPathDependencyAndTheProjectsOwnCrateAreLeftOut() throws {
		let root = try makeRoot()
		try write(cargoLock, to: root.appendingPathComponent("Cargo.lock"))

		let set = ExternalDependencies.read(root: root, kind: .cargo)
		#expect(!set.packages.contains { $0.name == "helper" })
		#expect(!set.packages.contains { $0.name == "probe" })
	}

	/// A crate from the one registry every Rust project uses says `crates.io`,
	/// not the index it happens to be served from. `github.com/rust-lang` on two
	/// hundred rows reads as though the crate came from that repository, and
	/// says nothing that tells one row from another.
	@Test func aRegistryCrateSaysCratesIoAndAGitOneSaysWhereItWasCloned() throws {
		let root = try makeRoot()
		try write(cargoLock, to: root.appendingPathComponent("Cargo.lock"))

		let set = ExternalDependencies.read(root: root, kind: .cargo)
		let serde = try #require(set.packages.first { $0.name == "serde" })
		#expect(serde.origin == "crates.io")
		#expect(serde.shortOrigin == "crates.io")

		let anyhow = try #require(set.packages.first { $0.name == "anyhow" })
		// The whole source, revision and all, for the tooltip — cut back to the
		// owner for the row.
		#expect(anyhow.origin
			== "https://github.com/dtolnay/anyhow#bf3ed9149f4334c984c1ad252b534107b307078c")
		#expect(anyhow.shortOrigin == "github.com/dtolnay")
	}

	/// The sparse index has been the default since Rust 1.68 and the git index
	/// is still in every lock file written before it. They are the same registry
	/// and a row that called them different things would be sorting by the age
	/// of somebody's checkout.
	@Test func bothSpellingsOfTheCratesIoIndexAreTheSameOrigin() {
		#expect(ExternalDependencies.cargoOrigin(
			of: "registry+https://github.com/rust-lang/crates.io-index") == "crates.io")
		#expect(ExternalDependencies.cargoOrigin(
			of: "sparse+https://index.crates.io/") == "crates.io")
		// A registry of somebody's own keeps its URL: there the host is the answer.
		#expect(ExternalDependencies.cargoOrigin(
			of: "registry+https://crates.example.com/index") == "https://crates.example.com/index")
	}

	/// The `dependencies` array under a package holds bare strings, and in the
	/// version 1 and 2 layouts they are whole package ids with `?branch=main`
	/// inside them. A parser splitting every line on its first `=` reads that
	/// fragment as a key of the table it is in.
	@Test func theDependenciesArrayIsNotMistakenForKeysOfTheTable() {
		let packages = ExternalDependencies.parseCargoLock("""
		[[package]]
		name = "app"
		version = "0.1.0"
		dependencies = [
		 "anyhow 1.0.104 (git+https://github.com/dtolnay/anyhow?branch=main#bf3ed914)",
		]

		[metadata]
		"checksum anyhow 1.0.104 (registry+https://github.com/rust-lang/crates.io-index)" = "abc"
		""")
		#expect(packages == [
			ExternalDependencies.CargoLockPackage(name: "app", version: "0.1.0", source: nil),
		])
	}

	/// **Two caches, two layouts, and neither inside the project.** The registry
	/// directory has a hash of the registry URL in its name — made by a function
	/// inside cargo that is written down nowhere and has changed once already —
	/// so it is listed rather than computed; a git dependency is somewhere else
	/// entirely, under `git/checkouts/<repo>-<hash>/<short revision>`, and cargo
	/// does not promise how short, which is why the revision is matched by
	/// prefix.
	///
	/// One test and not two on purpose: `CARGO_HOME` is process-wide and this
	/// suite runs in parallel, so two tests moving it at once would be two tests
	/// reading each other's cache.
	@Test func aCratesSourcesAreFoundInWhicheverCacheFetchedIt() throws {
		let root = try makeRoot()
		let home = try makeRoot()
		try write(cargoLock, to: root.appendingPathComponent("Cargo.lock"))
		try write("pub fn parse() {}\n", to: home.appendingPathComponent(
			"registry/src/index.crates.io-1949cf8c6b5b557f/serde-1.0.229/src/lib.rs"
		))
		try write("pub fn bail() {}\n", to: home.appendingPathComponent(
			"git/checkouts/anyhow-df9bb94f3a1acfc0/bf3ed91/src/lib.rs"
		))

		let previous = ProcessInfo.processInfo.environment["CARGO_HOME"]
		setenv("CARGO_HOME", home.path, 1)
		defer {
			if let previous { setenv("CARGO_HOME", previous, 1) } else { unsetenv("CARGO_HOME") }
		}

		let set = ExternalDependencies.read(root: root, kind: .cargo)
		#expect(set.packages.first { $0.name == "serde" }?.localPath?.lastPathComponent
			== "serde-1.0.229")
		#expect(set.packages.first { $0.name == "anyhow" }?.localPath?.lastPathComponent
			== "bf3ed91")

		// And the files under either are browsable from the row, which is the
		// whole of what the section is for.
		let tree = try #require(DependencyTree(sets: [set], project: root))
		let opened = home.appendingPathComponent(
			"git/checkouts/anyhow-df9bb94f3a1acfc0/bf3ed91/src/lib.rs"
		)
		#expect(tree.package(containing: opened)?.name == "anyhow")
	}

	/// A crate nobody fetched has nothing to open, rather than a path to a
	/// directory that is not there — which the tree would draw as a package with
	/// no files in it.
	@Test func aCrateThatWasNeverFetchedHasNoSources() throws {
		let root = try makeRoot()
		try write("""
		version = 4

		[[package]]
		name = "a-crate-nobody-has"
		version = "0.0.1-never"
		source = "registry+https://github.com/rust-lang/crates.io-index"
		""", to: root.appendingPathComponent("Cargo.lock"))

		let set = ExternalDependencies.read(root: root, kind: .cargo)
		#expect(set.packages.count == 1)
		#expect(set.packages.first?.localPath == nil)
	}

	/// **A Cargo project that has resolved nothing says so in cargo's words.**
	/// An empty list would read as a crate depending on nothing, which is the
	/// failure the whole section was built to avoid.
	@Test func aCargoProjectWithNoLockFileSaysWhatWouldMakeOne() throws {
		let root = try makeRoot()
		try write("[package]\nname = \"probe\"\n", to: root.appendingPathComponent("Cargo.toml"))

		let set = ExternalDependencies.read(root: root, kind: .cargo)
		guard case let .unresolved(reason) = set.contents else {
			Issue.record("expected unresolved, got \(set.contents)")
			return
		}
		#expect(reason == "no Cargo.lock — run cargo fetch")

		let tree = try #require(DependencyTree(sets: [set], project: root))
		#expect(tree.report() == ["Dependencies — Cargo", "  no Cargo.lock — run cargo fetch"])
	}

	/// **A member of a workspace is not a project that has resolved nothing.**
	/// A workspace has one `Cargo.lock`, at its root, and every member is a
	/// subproject with a row of its own — so `run cargo fetch` on a member would
	/// send somebody to run a command that writes nothing there. Found by
	/// pointing the app at the first real Rust project, whose one path
	/// dependency said exactly that.
	@Test func aWorkspaceMemberSaysWhereItsLockFileIsRatherThanThatThereIsNone() throws {
		let workspace = try makeRoot()
		try write("[package]\nname = \"probe\"\n", to: workspace.appendingPathComponent("Cargo.toml"))
		try write(cargoLock, to: workspace.appendingPathComponent("Cargo.lock"))
		let member = workspace.appendingPathComponent("crates/helper")
		try write("[package]\nname = \"helper\"\n", to: member.appendingPathComponent("Cargo.toml"))

		let set = ExternalDependencies.read(root: member, kind: .cargo)
		#expect(set.contents == .unresolved(
			"resolved in the workspace at \(workspace.lastPathComponent)"
		))
		// And the workspace's own list is not copied under the member: it is the
		// whole workspace's resolved set, not this crate's.
		#expect(set.packages.isEmpty)
	}

	/// A lock file of nothing but the project's own crates is a project with no
	/// external dependencies, and that is a reading rather than a failure to
	/// read — the same claim `go.mod` with no `require` makes.
	@Test func aWorkspaceThatDependsOnNothingOutsideItselfIsReadAsHavingNone() throws {
		let root = try makeRoot()
		try write("""
		version = 4

		[[package]]
		name = "probe"
		version = "0.1.0"
		""", to: root.appendingPathComponent("Cargo.lock"))

		let set = ExternalDependencies.read(root: root, kind: .cargo)
		guard case let .packages(packages) = set.contents else {
			Issue.record("expected packages, got \(set.contents)")
			return
		}
		#expect(packages.isEmpty)
	}

	/// The row as the section draws it, which is the claim somebody can check by
	/// looking at the app.
	@Test func aCargoProjectsSectionReadsAsNameVersionAndOrigin() throws {
		let root = try makeRoot()
		try write(cargoLock, to: root.appendingPathComponent("Cargo.lock"))

		let tree = try #require(DependencyTree(sets: [
			ExternalDependencies.read(root: root, kind: .cargo),
		], project: root))
		#expect(tree.report() == [
			"Dependencies — Cargo",
			"  anyhow — 1.0.104  ·  github.com/dtolnay",
			"  serde — 1.0.229  ·  crates.io",
		])
	}

	// MARK: - npm

	/// A version 3 lock file cut from a real one, keeping one of every shape the
	/// reader has to tell apart: a plain package, a scoped one, a nested copy of
	/// a package that is already at the top level, a workspace member (which
	/// appears twice — once by its path and once symlinked into `node_modules`
	/// with `link: true`), a git dependency and a package with no `resolved`.
	private let packageLock = """
	{
	  "name": "probe",
	  "version": "1.0.0",
	  "lockfileVersion": 3,
	  "requires": true,
	  "packages": {
	    "": {
	      "name": "probe",
	      "version": "1.0.0",
	      "workspaces": ["packages/*"],
	      "dependencies": { "lodash": "^4.17.21" }
	    },
	    "packages/app": { "name": "@probe/app", "version": "0.1.0" },
	    "node_modules/@probe/app": { "resolved": "packages/app", "link": true },
	    "node_modules/lodash": {
	      "version": "4.17.21",
	      "resolved": "https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz",
	      "integrity": "sha512-v2kDEe57lecTulaDIuNTPy3Ry4gLGJ6Z1O3vE1krgXZNrsQ+LFTGHVxVjcXPs17LhbZVGedAJv8XZ1tvj5FvSg=="
	    },
	    "node_modules/@types/node": {
	      "version": "22.10.1",
	      "dev": true,
	      "resolved": "https://registry.npmjs.org/@types/node/-/node-22.10.1.tgz"
	    },
	    "node_modules/jest/node_modules/chalk": {
	      "version": "2.4.2",
	      "resolved": "https://registry.yarnpkg.com/chalk/-/chalk-2.4.2.tgz"
	    },
	    "node_modules/anyhow": {
	      "version": "1.0.104",
	      "resolved": "git+https://github.com/dtolnay/anyhow.git#bf3ed914"
	    },
	    "node_modules/bundled-thing": { "version": "0.3.0" }
	  }
	}
	"""

	// MARK: - Bazel

	/// The 7.2-and-later lock: `registryFileHashes`, whose keys are every
	/// registry file consulted.
	private let bazelLockRegistryHashes = """
	{
	  "lockFileVersion": 11,
	  "registryFileHashes": {
	    "https://bcr.bazel.build/bazel_registry.json": "0000",
	    "https://bcr.bazel.build/modules/gazelle/0.38.0/source.json": "1111",
	    "https://bcr.bazel.build/modules/rules_go/0.46.0/MODULE.bazel": "2222",
	    "https://bcr.bazel.build/modules/rules_go/0.49.0/MODULE.bazel": "3333",
	    "https://bcr.bazel.build/modules/rules_go/0.50.1/MODULE.bazel": "4444",
	    "https://bcr.bazel.build/modules/rules_go/0.50.1/source.json": "5555"
	  }
	}
	"""

	/// The resolved tree is the lock file, and the row names the version on disk
	/// — `package.json` says `^4.17.21`, which is not an answer.
	@Test func aPackageLockNamesEveryPackageAndTheVersionItResolvedTo() throws {
		let root = try makeRoot()
		try write(packageLock, to: root.appendingPathComponent("package-lock.json"))

		let set = ExternalDependencies.read(root: root, kind: .npm)
		#expect(set.packages.map(\.name) == [
			"@types/node", "anyhow", "bundled-thing", "chalk", "lodash",
		])
		#expect(set.packages.first { $0.name == "lodash" }?.version == "4.17.21")
	}

	/// **The name is everything after the *last* `node_modules/`.** One rule for
	/// both hard cases: a scoped package keeps its `@scope/`, and a nested copy —
	/// npm's answer to two packages needing different versions of a third — is
	/// named after itself rather than after whatever it is buried under.
	@Test func aPackagesNameIsWhateverFollowsTheLastNodeModules() {
		#expect(ExternalDependencies.npmPackageName(inPath: "node_modules/lodash") == "lodash")
		#expect(ExternalDependencies.npmPackageName(inPath: "node_modules/@types/node")
			== "@types/node")
		#expect(ExternalDependencies.npmPackageName(
			inPath: "node_modules/jest/node_modules/@babel/core") == "@babel/core")
		// The project itself, and a workspace member by its own path: neither is
		// something that came from outside.
		#expect(ExternalDependencies.npmPackageName(inPath: "") == nil)
		#expect(ExternalDependencies.npmPackageName(inPath: "packages/app") == nil)
	}

	/// **The project and its workspace members are not external.** A member is in
	/// the lock file twice — once by its path, once symlinked into `node_modules`
	/// with `link: true` and a `resolved` pointing back inside the project — and
	/// both are directories the tree already has rows for.
	@Test func theProjectAndItsWorkspaceMembersAreLeftOut() throws {
		let root = try makeRoot()
		try write(packageLock, to: root.appendingPathComponent("package-lock.json"))

		let set = ExternalDependencies.read(root: root, kind: .npm)
		#expect(!set.packages.contains { $0.name == "@probe/app" })
		#expect(!set.packages.contains { $0.name == "probe" })
	}

	/// **The lock file's own keys are the paths**, which is why npm is the one
	/// kind here with no cache to locate: `node_modules/lodash` appended to the
	/// project root *is* the sources. A package that was resolved and never
	/// installed has nothing to open instead of a path to a directory that is not
	/// there, and the nested copy answers for its own directory rather than the
	/// top-level one of the same name.
	@Test func aPackagesSourcesAreTheLockFilesOwnKeyUnderTheProject() throws {
		let root = try makeRoot()
		try write(packageLock, to: root.appendingPathComponent("package-lock.json"))
		try write("module.exports = {}\n",
			to: root.appendingPathComponent("node_modules/lodash/index.js"))
		try write("module.exports = {}\n",
			to: root.appendingPathComponent("node_modules/jest/node_modules/chalk/index.js"))

		let set = ExternalDependencies.read(root: root, kind: .npm)
		let lodash = try #require(set.packages.first { $0.name == "lodash" })
		#expect(lodash.localPath?.path == root.appendingPathComponent("node_modules/lodash").path)
		let chalk = try #require(set.packages.first { $0.name == "chalk" })
		#expect(chalk.localPath?.path
			== root.appendingPathComponent("node_modules/jest/node_modules/chalk").path)
		// Resolved, never installed: no `npm install` has been run for these.
		#expect(set.packages.first { $0.name == "@types/node" }?.localPath == nil)

		// And the files under a package are browsable from its row, which is the
		// whole of what the section is for.
		let tree = try #require(DependencyTree(sets: [set], project: root))
		let opened = root.appendingPathComponent("node_modules/lodash/index.js")
		#expect(tree.package(containing: opened)?.name == "lodash")
	}

	/// The registry and not the tarball. `registry.npmjs.org/lodash/-` is what
	/// `shortOrigin` makes of a tarball URL, and it would say it on eight hundred
	/// rows; yarn's mirror is the same registry under another host, which is 513's
	/// two-spellings finding turning up in a file npm itself wrote.
	@Test func aRegistryPackageSaysTheRegistryAndAGitOneSaysWhereItWasCloned() throws {
		let root = try makeRoot()
		try write(packageLock, to: root.appendingPathComponent("package-lock.json"))

		let set = ExternalDependencies.read(root: root, kind: .npm)
		#expect(set.packages.first { $0.name == "lodash" }?.origin == "npmjs.com")
		#expect(set.packages.first { $0.name == "chalk" }?.origin == "npmjs.com")

		let anyhow = try #require(set.packages.first { $0.name == "anyhow" })
		#expect(anyhow.origin == "https://github.com/dtolnay/anyhow.git#bf3ed914")
		#expect(anyhow.shortOrigin == "github.com/dtolnay")

		// A registry of somebody's own is the host, because there the host is the
		// answer. A package with no `resolved` claims no origin at all, which the
		// row draws as a version and nothing else.
		#expect(ExternalDependencies.npmOrigin(
			of: "https://npm.pkg.github.com/@acme/thing/-/thing-1.0.0.tgz")
			== "npm.pkg.github.com")
		#expect(set.packages.first { $0.name == "bundled-thing" }?.origin == "")
	}

	/// npm 6 wrote a `dependencies` tree keyed by name and nested where two
	/// packages needed different versions of a third, and those lock files are
	/// still in projects nobody has reinstalled. Refusing to read one would empty
	/// the section on an old checkout — the same refusal `Package.resolved`'s two
	/// layouts are both read to avoid.
	@Test func theFirstLayoutOfPackageLockIsStillRead() throws {
		let root = try makeRoot()
		try write("""
		{
		  "name": "probe",
		  "lockfileVersion": 1,
		  "dependencies": {
		    "@babel/highlight": {
		      "version": "7.10.4",
		      "resolved": "https://registry.npmjs.org/@babel/highlight/-/highlight-7.10.4.tgz",
		      "dependencies": {
		        "chalk": {
		          "version": "2.4.2",
		          "resolved": "https://registry.npmjs.org/chalk/-/chalk-2.4.2.tgz"
		        }
		      }
		    }
		  }
		}
		""", to: root.appendingPathComponent("package-lock.json"))
		try write("x\n", to: root.appendingPathComponent(
			"node_modules/@babel/highlight/node_modules/chalk/index.js"
		))

		let set = ExternalDependencies.read(root: root, kind: .npm)
		#expect(set.packages.map(\.name) == ["@babel/highlight", "chalk"])
		// The path is built by descending, because the version 1 layout has no
		// paths in it — the nested copy is under the package that needed it.
		#expect(set.packages.first { $0.name == "chalk" }?.localPath?.path
			== root.appendingPathComponent(
				"node_modules/@babel/highlight/node_modules/chalk").path)
	}

	/// A version 2 lock file carries both layouts, for tools that only understand
	/// the older one. `packages` wins: it is the one with the paths in it, and the
	/// `dependencies` half of the same file leaves out anything hoisted.
	@Test func theNewerLayoutWinsInALockFileThatCarriesBoth() throws {
		let root = try makeRoot()
		try write("""
		{
		  "lockfileVersion": 2,
		  "packages": {
		    "": { "name": "probe" },
		    "node_modules/lodash": { "version": "4.17.21" }
		  },
		  "dependencies": {
		    "an-older-answer": { "version": "0.0.1" }
		  }
		}
		""", to: root.appendingPathComponent("package-lock.json"))

		let set = ExternalDependencies.read(root: root, kind: .npm)
		#expect(set.packages.map(\.name) == ["lodash"])
	}

	/// `npm-shrinkwrap.json` is `package-lock.json` byte for byte and npm prefers
	/// it where a project publishes one, so a project with one is not a project
	/// that has resolved nothing.
	@Test func aShrinkwrapIsReadTheSameWayAndIsPreferred() throws {
		let root = try makeRoot()
		try write(packageLock, to: root.appendingPathComponent("npm-shrinkwrap.json"))

		let set = ExternalDependencies.read(root: root, kind: .npm)
		#expect(set.packages.contains { $0.name == "lodash" })
		// And writing one reloads the section, which is the other half of it.
		#expect(ExternalDependencies.definingFileNames.contains("npm-shrinkwrap.json"))
	}

	/// **An npm project that has installed nothing says so in npm's words**, and
	/// an empty list would read as a project depending on nothing.
	@Test func anNpmProjectWithNoLockFileSaysWhatWouldMakeOne() throws {
		let root = try makeRoot()
		try write("{ \"name\": \"probe\" }\n", to: root.appendingPathComponent("package.json"))

		let set = ExternalDependencies.read(root: root, kind: .npm)
		let tree = try #require(DependencyTree(sets: [set], project: root))
		#expect(tree.report() == ["Dependencies — npm", "  no package-lock.json — run npm install"])
	}

	/// **A pnpm or a yarn project is not a project that has installed nothing.**
	/// `package.json` is the marker for all three tools, so both reach this
	/// reader — and `run npm install` would be an instruction to install a
	/// second, conflicting tree over a project that is already installed. The row
	/// names the tool that did resolve it, and the item that will read its lock
	/// file.
	@Test func aPnpmOrAYarnProjectSaysWhichToolResolvedIt() throws {
		let pnpm = try makeRoot()
		try write("{ \"name\": \"probe\" }\n", to: pnpm.appendingPathComponent("package.json"))
		try write("lockfileVersion: '9.0'\n", to: pnpm.appendingPathComponent("pnpm-lock.yaml"))
		#expect(ExternalDependencies.read(root: pnpm, kind: .npm).contents
			== .unresolved("resolved by pnpm — pnpm-lock.yaml not read yet (0525)"))

		let yarn = try makeRoot()
		try write("{ \"name\": \"probe\" }\n", to: yarn.appendingPathComponent("package.json"))
		try write("# yarn lockfile v1\n", to: yarn.appendingPathComponent("yarn.lock"))
		#expect(ExternalDependencies.read(root: yarn, kind: .npm).contents
			== .unresolved("resolved by yarn — yarn.lock not read yet (0525)"))

		// And a project with both a `yarn.lock` and npm's own lock file is read:
		// npm's is the one this can answer for.
		try write(packageLock, to: yarn.appendingPathComponent("package-lock.json"))
		#expect(ExternalDependencies.read(root: yarn, kind: .npm).packages.contains {
			$0.name == "lodash"
		})
	}

	/// **A workspace member is not a project that has installed nothing.** An npm
	/// workspace has one lock file, at its root, and hoists every dependency into
	/// the root's `node_modules` — so `run npm install` in a member is worse
	/// advice than cargo's was, because npm will do it and leave a second
	/// `node_modules` inside the member. 513's finding, in npm's spelling.
	@Test func aWorkspaceMemberSaysWhereTheLockFileIsRatherThanThatThereIsNone() throws {
		let workspace = try makeRoot()
		try write("{ \"name\": \"probe\", \"workspaces\": [\"packages/*\"] }\n",
			to: workspace.appendingPathComponent("package.json"))
		try write(packageLock, to: workspace.appendingPathComponent("package-lock.json"))
		let member = workspace.appendingPathComponent("packages/app")
		try write("{ \"name\": \"@probe/app\" }\n", to: member.appendingPathComponent("package.json"))

		let set = ExternalDependencies.read(root: member, kind: .npm)
		#expect(set.contents == .unresolved(
			"resolved in the workspace at \(workspace.lastPathComponent)"
		))
		// The workspace's own list is not copied under the member: it is the whole
		// workspace's resolved set, not this package's.
		#expect(set.packages.isEmpty)
	}

	/// **Which root a hoisted dependency is filed under: the one that owns the
	/// lock file.** A workspace hoists its members' dependencies into the root's
	/// `node_modules`, and the lock file that records them is the root's — so
	/// that is the only root with anything to read, and a member's row says where
	/// its lock file is instead. A dependency npm could *not* hoist, because two
	/// members want different versions of it, is written at
	/// `packages/app/node_modules/<name>` in the same lock file and is filed the
	/// same way, under the root, with its own path.
	@Test func aWorkspacesDependenciesAreAllFiledUnderTheRootThatOwnsTheLockFile() throws {
		let workspace = try makeRoot()
		try write("{ \"name\": \"probe\", \"workspaces\": [\"packages/*\"] }\n",
			to: workspace.appendingPathComponent("package.json"))
		try write("""
		{
		  "lockfileVersion": 3,
		  "packages": {
		    "": { "name": "probe", "workspaces": ["packages/*"] },
		    "packages/app": { "name": "@probe/app", "version": "0.1.0" },
		    "node_modules/@probe/app": { "resolved": "packages/app", "link": true },
		    "node_modules/lodash": { "version": "4.17.21" },
		    "packages/app/node_modules/lodash": { "version": "3.10.1" }
		  }
		}
		""", to: workspace.appendingPathComponent("package-lock.json"))

		let set = ExternalDependencies.read(root: workspace, kind: .npm)
		#expect(set.packages.map(\.name) == ["lodash", "lodash"])
		// Two versions of one package, told apart by where they are — which is
		// what the un-hoisted copy exists to be.
		#expect(Set(set.packages.compactMap(\.version)) == ["4.17.21", "3.10.1"])
	}

	/// A `package.json` inside a repository that is *not* a workspace has
	/// genuinely not been installed, and `npm install` is the right thing to tell
	/// it. The ancestor has to declare the workspace, not merely have a lock file.
	@Test func aNestedProjectUnderANonWorkspaceRootIsToldToInstall() throws {
		let root = try makeRoot()
		try write("{ \"name\": \"probe\" }\n", to: root.appendingPathComponent("package.json"))
		try write(packageLock, to: root.appendingPathComponent("package-lock.json"))
		let docs = root.appendingPathComponent("docs")
		try write("{ \"name\": \"docs\" }\n", to: docs.appendingPathComponent("package.json"))

		#expect(ExternalDependencies.read(root: docs, kind: .npm).contents
			== .unresolved("no package-lock.json — run npm install"))
	}

	/// A lock file naming nothing but the project itself is a project with no
	/// external dependencies, and that is a reading rather than a failure to read
	/// — the same claim a `go.mod` with no `require` makes.
	@Test func aLockFileOfNothingButTheProjectIsReadAsHavingNoDependencies() throws {
		let root = try makeRoot()
		try write("{ \"lockfileVersion\": 3, \"packages\": { \"\": { \"name\": \"probe\" } } }\n",
			to: root.appendingPathComponent("package-lock.json"))

		let set = ExternalDependencies.read(root: root, kind: .npm)
		guard case let .packages(packages) = set.contents else {
			Issue.record("expected packages, got \(set.contents)")
			return
		}
		#expect(packages.isEmpty)
	}

	/// The row as the section draws it, which is the claim somebody can check by
	/// looking at the app.
	@Test func anNpmProjectsSectionReadsAsNameVersionAndOrigin() throws {
		let root = try makeRoot()
		try write(packageLock, to: root.appendingPathComponent("package-lock.json"))

		let tree = try #require(DependencyTree(sets: [
			ExternalDependencies.read(root: root, kind: .npm),
		], project: root))
		#expect(tree.report() == [
			"Dependencies — npm",
			"  @types/node — 22.10.1  ·  npmjs.com",
			"  anyhow — 1.0.104  ·  github.com/dtolnay",
			// No `resolved` in the lock file, so no origin is claimed.
			"  bundled-thing — 0.3.0",
			"  chalk — 2.4.2  ·  npmjs.com",
			"  lodash — 4.17.21  ·  npmjs.com",
		])
	}

	/// **The trap in the newer lock, and the reason this reader is not two
	/// lines.** Minimal version selection fetches the `MODULE.bazel` of every
	/// candidate version to compare them and only fetches `source.json` for the
	/// one it settles on. So three versions of `rules_go` are named in the file
	/// and exactly one of them is a dependency — a reader taking every key would
	/// draw three rows for one module, each claiming to be what the project uses.
	@Test func aBazelLockNamesTheVersionSelectedAndNotTheOnesConsidered() throws {
		let root = try makeRoot()
		try write(bazelLockRegistryHashes, to: root.appendingPathComponent("MODULE.bazel.lock"))

		let set = ExternalDependencies.read(root: root, kind: .bazel)
		guard case let .packages(packages) = set.contents else {
			Issue.record("expected packages, got \(set.contents)")
			return
		}
		#expect(packages.map(\.name) == ["gazelle", "rules_go"])
		#expect(packages.map(\.version) == ["0.38.0", "0.50.1"])
		// Where it came from is the registry, which this layout does write down.
		#expect(packages.allSatisfy { $0.origin == "https://bcr.bazel.build" })
	}

	/// The 7.0/7.1 lock, which said it outright and which projects on disk still
	/// have. Reading only the newer layout would empty the section for them.
	@Test func theOlderBazelLockLayoutIsReadToo() throws {
		let root = try makeRoot()
		try write("""
		{
		  "lockFileVersion": 3,
		  "moduleDepGraph": {
		    "": { "name": "my_project", "version": "" },
		    "rules_cc@0.0.9": {
		      "name": "rules_cc", "version": "0.0.9", "registry": "https://bcr.bazel.build"
		    },
		    "bazel_tools@_": { "name": "bazel_tools", "version": "" }
		  }
		}
		""", to: root.appendingPathComponent("MODULE.bazel.lock"))

		let set = ExternalDependencies.read(root: root, kind: .bazel)
		guard case let .packages(packages) = set.contents else {
			Issue.record("expected packages, got \(set.contents)")
			return
		}
		// The root module is keyed by the empty string and is the project itself —
		// every file of it already has a row in the first tree.
		#expect(packages.map(\.name) == ["bazel_tools", "rules_cc"])
		#expect(packages.map(\.version) == [nil, "0.0.9"])
	}

	/// No lock: the manifest, which names the direct dependencies exactly.
	///
	/// Less than the lock and not nothing, which is the right way round for a
	/// workspace nobody has built yet.
	@Test func aBazelWorkspaceWithNoLockReadsItsDirectDependencies() throws {
		let root = try makeRoot()
		try write("""
		module(name = "my_project", version = "1.0")

		bazel_dep(name = "rules_go", version = "0.50.1")

		# buildifier breaks a long one across lines, so name and version are not
		# on the same one.
		bazel_dep(
		    name = "gazelle",
		    version = "0.38.0",
		)

		bazel_dep(repo_name = "gtest", name = "googletest", version = "1.15.2")
		""", to: root.appendingPathComponent("MODULE.bazel"))

		let set = ExternalDependencies.read(root: root, kind: .bazel)
		guard case let .packages(packages) = set.contents else {
			Issue.record("expected packages, got \(set.contents)")
			return
		}
		#expect(packages.map(\.name) == ["gazelle", "googletest", "rules_go"])
		#expect(packages.map(\.version) == ["0.38.0", "1.15.2", "0.50.1"])
	}

	/// **`repo_name` written before `name`, which is what made `attribute` scan
	/// every occurrence.** The old reader found `name` inside `repo_name`, saw
	/// the underscore in front of it, and gave the whole line up — so the module
	/// vanished from the list rather than being read wrongly, which is the kind
	/// of failure a test has to name because nothing on screen would.
	@Test func anAttributeIsFoundPastAnEarlierWordThatContainsIt() {
		#expect(BazelBuild.attribute(
			"name", in: "bazel_dep(repo_name = \"gtest\", name = \"googletest\")"
		) == "googletest")
		#expect(BazelBuild.attribute(
			"version", in: "bazel_dep(name = \"a version of it\", version = \"2.0\")"
		) == "2.0")
	}

	/// The sources, found by following the convenience symlink Bazel leaves and
	/// **listing** what is under the output base.
	///
	/// The output base itself is named by an md5 of the workspace path, so it is
	/// not computed. And the separator between a module and its version has been
	/// `~`, `+`, `+` with nothing after it and nothing at all across releases, so
	/// the directory is matched rather than spelled.
	@Test func aBazelRepositoryIsFoundWhateverSeparatorTheReleaseUsed() throws {
		let root = try makeRoot()
		let outputBase = try makeRoot()
		try FileManager.default.createDirectory(
			at: outputBase.appendingPathComponent("execroot/_main/bazel-out"),
			withIntermediateDirectories: true
		)
		try FileManager.default.createSymbolicLink(
			at: root.appendingPathComponent("bazel-out"),
			withDestinationURL: outputBase.appendingPathComponent("execroot/_main/bazel-out")
		)
		for repository in ["rules_go+0.50.1", "gazelle~0.38.0", "googletest+", "rules_google+9.9"] {
			try write("x\n", to: outputBase.appendingPathComponent("external/\(repository)/BUILD"))
		}

		let repositories = ExternalDependencies.bazelRepositoryDirectories(for: root)
		#expect(repositories.count == 4)
		#expect(ExternalDependencies.bazelSources(named: "rules_go", in: repositories)?
			.lastPathComponent == "rules_go+0.50.1")
		#expect(ExternalDependencies.bazelSources(named: "gazelle", in: repositories)?
			.lastPathComponent == "gazelle~0.38.0")
		#expect(ExternalDependencies.bazelSources(named: "googletest", in: repositories)?
			.lastPathComponent == "googletest+")
		// The near miss the strictness is for: `rules_google+9.9` starts with
		// `rules_go` and belongs to another module entirely.
		#expect(ExternalDependencies.bazelSources(named: "rules_g", in: repositories) == nil)
	}

	/// **What is honestly not read, and what it says instead.** A `WORKSPACE`
	/// workspace declares its repositories in Starlark macros, so there is no
	/// file to read — and unlike every other unresolved row in this section there
	/// is no command that would make one, so the row does not invent one.
	@Test func aWorkspaceOnlyBazelProjectSaysWhyRatherThanNamingACommand() throws {
		let root = try makeRoot()
		try write("workspace(name = \"my_project\")\n", to: root.appendingPathComponent("WORKSPACE"))

		let set = ExternalDependencies.read(root: root, kind: .bazel)
		#expect(set.contents == .unresolved(
			"WORKSPACE dependencies are Starlark — nothing on disk lists them"
		))
	}

	/// **Found by looking at it.** Every one of these sentences is longer than
	/// the pane is wide, so the row shows `WORKSPACE dependencies are…` and the
	/// rest of it has to be somewhere. The tooltip is where everything too long
	/// for the pane goes, and a note's was saying only which kind it was.
	@Test func aNotesTooltipCarriesTheWholeSentenceThePaneCuts() throws {
		let root = try makeRoot()
		try write("workspace(name = \"my_project\")\n", to: root.appendingPathComponent("WORKSPACE"))

		let tree = try #require(DependencyTree(sets: [
			ExternalDependencies.read(root: root, kind: .bazel),
		], project: root))
		let note = try #require(tree.root.childNodes.first)
		#expect(note.detail?.hasPrefix(
			"WORKSPACE dependencies are Starlark — nothing on disk lists them"
		) == true)
	}

	/// The row as the section draws it.
	@Test func aBazelProjectsSectionReadsAsNameVersionAndRegistry() throws {
		let root = try makeRoot()
		try write(bazelLockRegistryHashes, to: root.appendingPathComponent("MODULE.bazel.lock"))

		let tree = try #require(DependencyTree(sets: [
			ExternalDependencies.read(root: root, kind: .bazel),
		], project: root))
		#expect(tree.report() == [
			"Dependencies — Bazel",
			"  gazelle — 0.38.0  ·  bcr.bazel.build",
			"  rules_go — 0.50.1  ·  bcr.bazel.build",
		])
	}

	// MARK: - Conan

	private let conanLock = """
	{
	  "version": "0.5",
	  "requires": [
	    "zlib/1.3.1#b8bc2603263cf7eccbd6e17e66b0ed76%1720557532.108",
	    "fmt/10.2.1#a1b2c3d4%1720557532.108",
	    "mylib/2.0@acme/stable#f00d%1720557532.108"
	  ],
	  "build_requires": [
	    "cmake/3.29.3#deadbeef%1720557532.108"
	  ],
	  "python_requires": []
	}
	"""

	/// A Conan 2 lock is JSON and is the resolved graph, so the recipe never has
	/// to run.
	@Test func aConanLockIsReadIntoPackages() throws {
		let root = try makeRoot()
		try write(conanLock, to: root.appendingPathComponent("conan.lock"))

		let set = ExternalDependencies.read(root: root, kind: .conan)
		guard case let .packages(packages) = set.contents else {
			Issue.record("expected packages, got \(set.contents)")
			return
		}
		#expect(packages.map(\.name) == ["cmake", "fmt", "mylib", "zlib"])
		#expect(packages.map(\.version) == ["3.29.3", "10.2.1", "2.0", "1.3.1"])
		// The recipe revision and the timestamp are not the version, and neither
		// is the user and channel — which is the only provenance a lock records.
		#expect(packages.first { $0.name == "mylib" }?.origin == "acme/stable")
		#expect(packages.first { $0.name == "zlib" }?.origin == "")
	}

	/// **A Conan 1 lock parses perfectly and says none of this.** It keys
	/// everything under `graph_lock`, so a reader that took "parsed, no
	/// `requires`" for an answer would draw `no dependencies` over a project with
	/// forty of them — the exact lie this section was built to stop.
	@Test func aConan1LockIsRefusedRatherThanReadAsEmpty() throws {
		let root = try makeRoot()
		try write("""
		{
		  "graph_lock": {
		    "nodes": { "0": { "ref": "zlib/1.2.11", "options": "shared=False" } }
		  },
		  "version": "0.4",
		  "profile_host": "[settings]\\narch=x86_64\\n"
		}
		""", to: root.appendingPathComponent("conan.lock"))

		let set = ExternalDependencies.read(root: root, kind: .conan)
		#expect(set.contents == .unresolved("conan.lock is a Conan 1 lock — run conan lock create ."))
	}

	/// A recipe with no lock is the honest unresolved case, and the row names the
	/// command — `conan install` does not write one in Conan 2, which is the
	/// mistake the message is worded around.
	@Test func aConanRecipeWithNoLockNamesTheCommandThatWritesOne() throws {
		let root = try makeRoot()
		try write("class Pkg(ConanFile):\n    name = \"mine\"\n",
		          to: root.appendingPathComponent("conanfile.py"))

		let set = ExternalDependencies.read(root: root, kind: .conan)
		#expect(set.contents == .unresolved("no conan.lock — run conan lock create ."))
	}

	/// The cache folder is named for a hash of the whole resolved package, so it
	/// is listed and matched. **Strictly**: a prefix alone would give `fmt` the
	/// folder belonging to `fmtlog` and open another package's headers under a
	/// row saying `fmt`.
	@Test func aConanPackageFolderIsMatchedByItsHashAndNotItsPrefix() throws {
		let cache = try makeRoot()
		for folder in ["fmtlogb1c2d3", "fmt9a8b7c6d", "zlibnothex"] {
			try write("x\n", to: cache.appendingPathComponent("\(folder)/p/include/x.h"))
		}
		let directories = try FileManager.default.contentsOfDirectory(
			at: cache, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
		).sorted { $0.lastPathComponent < $1.lastPathComponent }

		let found = ExternalDependencies.conanSources(named: "fmt", in: directories)
		#expect(found?.path == cache.appendingPathComponent("fmt9a8b7c6d/p").path)
		// `nothex` is not a hash, so this is some other folder that happens to
		// start with the name.
		#expect(ExternalDependencies.conanSources(named: "zlib", in: directories) == nil)
	}

	/// The row as the section draws it. A Conan lock records no remote, so most
	/// rows carry a version and nothing else rather than a guessed registry.
	@Test func aConanProjectsSectionReadsAsNameAndVersion() throws {
		let root = try makeRoot()
		try write(conanLock, to: root.appendingPathComponent("conan.lock"))

		let tree = try #require(DependencyTree(sets: [
			ExternalDependencies.read(root: root, kind: .conan),
		], project: root))
		#expect(tree.report() == [
			"Dependencies — Conan",
			"  cmake — 3.29.3",
			"  fmt — 10.2.1",
			"  mylib — 2.0  ·  acme",
			"  zlib — 1.3.1",
		])
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
		#expect(tree.report() == ["Dependencies — Maven", "  not read yet (0515)"])
	}

	/// Every kind this program can open is in the list, whether or not it is
	/// read — that is what stops a project's dependencies being silently
	/// omitted, which is the failure the item named in advance.
	@Test func everyKindEitherIsReadOrNamesTheItemThatWillReadIt() {
		for kind in DependencyKind.allCases {
			switch kind {
			case .swiftPackage, .goModule, .cargo, .npm, .bazel, .conan:
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
