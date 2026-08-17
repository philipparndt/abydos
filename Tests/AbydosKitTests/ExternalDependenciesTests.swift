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

	// MARK: - Maven

	/// A POM with everything in it that moves a version: a plain one, one from a
	/// `<properties>` entry, and one with no `<version>` at all because a BOM in
	/// `~/.m2` manages it.
	private let pom = """
	<project xmlns="http://maven.apache.org/POM/4.0.0">
		<modelVersion>4.0.0</modelVersion>
		<groupId>com.example</groupId>
		<artifactId>service</artifactId>
		<version>1.0.0</version>
		<properties>
			<jackson.version>2.17.1</jackson.version>
		</properties>
		<dependencies>
			<dependency>
				<groupId>org.apache.commons</groupId>
				<artifactId>commons-lang3</artifactId>
				<version>3.14.0</version>
			</dependency>
			<dependency>
				<groupId>com.fasterxml.jackson.core</groupId>
				<artifactId>jackson-databind</artifactId>
				<version>${jackson.version}</version>
			</dependency>
			<dependency>
				<groupId>org.junit.jupiter</groupId>
				<artifactId>junit-jupiter</artifactId>
				<scope>test</scope>
			</dependency>
		</dependencies>
	</project>
	"""

	/// **The list is real and it is also incomplete, and the section says both.**
	/// `pom.xml` is the input to resolution — no transitives anywhere in it — so
	/// the rows are the direct dependencies and a note under them says what is
	/// not there. A `.packages` list would claim to be the whole graph, and
	/// `.unresolved` would throw away rows that are true.
	@Test func aPomsDirectDependenciesAreReadAndTheListSaysItIsOnlyThose() throws {
		let root = try makeRoot()
		try write(pom, to: root.appendingPathComponent("pom.xml"))

		let set = ExternalDependencies.read(root: root, kind: .maven)
		guard case let .partial(packages, caveat) = set.contents else {
			Issue.record("expected partial, got \(set.contents)")
			return
		}
		#expect(packages.map(\.name) == ["commons-lang3", "jackson-databind", "junit-jupiter"])
		// The groupId is where it came from, the way a module path is for Go.
		#expect(packages.first?.origin == "org.apache.commons")
		#expect(caveat == "direct dependencies only — Maven resolves the transitive ones "
			+ "and one of these versions")
	}

	/// `${jackson.version}` is resolved from `<properties>`; a dependency whose
	/// version a BOM manages has none here, and reads as absent rather than as
	/// the literal `${…}`, which is not a version anybody has on disk.
	@Test func aVersionFromAPropertyIsResolvedAndOneFromABomIsNot() throws {
		let root = try makeRoot()
		try write(pom, to: root.appendingPathComponent("pom.xml"))

		let set = ExternalDependencies.read(root: root, kind: .maven)
		#expect(set.packages.first { $0.name == "jackson-databind" }?.version == "2.17.1")
		#expect(set.packages.first { $0.name == "junit-jupiter" }?.version == nil)
	}

	/// **A parent in the checkout is merged; one that is not stops the chain and
	/// is said out loud.** The properties and the `<dependencyManagement>` that
	/// resolve a child's versions live up there, and so do dependencies the child
	/// inherits without naming.
	@Test func aParentInTheCheckoutIsMergedIntoTheChild() throws {
		let root = try makeRoot()
		try write("""
		<project>
			<groupId>com.example</groupId>
			<artifactId>parent</artifactId>
			<version>1.0.0</version>
			<packaging>pom</packaging>
			<properties><slf4j.version>2.0.13</slf4j.version></properties>
			<dependencies>
				<dependency>
					<groupId>org.slf4j</groupId>
					<artifactId>slf4j-api</artifactId>
					<version>${slf4j.version}</version>
				</dependency>
			</dependencies>
			<dependencyManagement>
				<dependencies>
					<dependency>
						<groupId>com.google.guava</groupId>
						<artifactId>guava</artifactId>
						<version>33.2.1-jre</version>
					</dependency>
				</dependencies>
			</dependencyManagement>
		</project>
		""", to: root.appendingPathComponent("pom.xml"))
		let module = root.appendingPathComponent("service")
		try write("""
		<project>
			<parent>
				<groupId>com.example</groupId>
				<artifactId>parent</artifactId>
				<version>1.0.0</version>
			</parent>
			<artifactId>service</artifactId>
			<dependencies>
				<dependency>
					<groupId>com.google.guava</groupId>
					<artifactId>guava</artifactId>
				</dependency>
			</dependencies>
		</project>
		""", to: module.appendingPathComponent("pom.xml"))

		let set = ExternalDependencies.read(root: module, kind: .maven)
		// Guava's version comes from the parent's dependencyManagement, and
		// slf4j is a dependency the child never names but has.
		#expect(set.packages.map(\.name) == ["guava", "slf4j-api"])
		#expect(set.packages.first { $0.name == "guava" }?.version == "33.2.1-jre")
		#expect(set.packages.first { $0.name == "slf4j-api" }?.version == "2.0.13")
		// Nothing is missing but the transitives, so that is all the caveat says.
		guard case let .partial(_, caveat) = set.contents else {
			Issue.record("expected partial, got \(set.contents)")
			return
		}
		#expect(caveat == "direct dependencies only — Maven resolves the transitive ones")
	}

	/// **`<relativePath/>` written empty means "not beside me".** Read as absent
	/// it would default to `../pom.xml`, and the chain would climb out of the
	/// project into whatever POM happens to sit one directory up — here, a
	/// parent that has nothing to do with this module. The row says instead that
	/// there is a parent this checkout does not hold.
	@Test func anEmptyRelativePathIsNotAParentBesideTheModule() throws {
		let root = try makeRoot()
		try write("""
		<project>
			<artifactId>somebody-elses-parent</artifactId>
			<properties><spring.version>6.1.0</spring.version></properties>
		</project>
		""", to: root.appendingPathComponent("pom.xml"))
		let module = root.appendingPathComponent("service")
		try write("""
		<project>
			<parent>
				<groupId>org.springframework.boot</groupId>
				<artifactId>spring-boot-starter-parent</artifactId>
				<version>3.3.0</version>
				<relativePath/>
			</parent>
			<artifactId>service</artifactId>
			<dependencies>
				<dependency>
					<groupId>org.springframework</groupId>
					<artifactId>spring-core</artifactId>
					<version>${spring.version}</version>
				</dependency>
			</dependencies>
		</project>
		""", to: module.appendingPathComponent("pom.xml"))

		let set = ExternalDependencies.read(root: module, kind: .maven)
		// The property is up in a POM this checkout does not hold, so there is no
		// version — and emphatically not `6.1.0`, which is the wrong project's.
		#expect(set.packages.map(\.version) == [nil])
		guard case let .partial(_, caveat) = set.contents else {
			Issue.record("expected partial, got \(set.contents)")
			return
		}
		#expect(caveat == "direct dependencies only — Maven resolves the transitive ones, "
			+ "one of these versions and a parent POM this checkout does not hold")
	}

	/// **The jar, and the tooltip that used to lie about it.** The JVM resolves
	/// to a jar rather than to sources, so `localPath` stays nil — a package row
	/// *is* a directory, and pointing it at the folder the jar sits in draws a
	/// package whose files are a jar and a checksum. But `not fetched` is false
	/// about a jar that is right there, so the row names the artefact instead.
	@Test func aMavenDependencyNamesItsJarRatherThanSayingItIsNotFetched() throws {
		let root = try makeRoot()
		let repository = try makeRoot()
		try write(pom, to: root.appendingPathComponent("pom.xml"))
		try write("not really a jar\n", to: repository.appendingPathComponent(
			"org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
		))
		// The sources jar sits beside it when somebody asked for one, and is not
		// the artefact.
		try write("nor this\n", to: repository.appendingPathComponent(
			"org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0-sources.jar"
		))

		guard case let .partial(packages, _) = ExternalDependencies.readMavenPackages(
			at: root, repository: repository
		) else {
			Issue.record("expected partial")
			return
		}
		let lang3 = try #require(packages.first { $0.name == "commons-lang3" })
		#expect(lang3.localPath == nil)
		#expect(lang3.artefact?.lastPathComponent == "commons-lang3-3.14.0.jar")

		// And the tooltip says where it is rather than that it is not there.
		let node = DependencyNode(row: .package(lang3))
		#expect(node.detail?.contains("commons-lang3-3.14.0.jar") == true)
		#expect(node.detail?.contains("not fetched") == false)
		#expect(node.isExpandable == false)

		// A dependency whose version nothing here knows has no jar to name.
		#expect(packages.first { $0.name == "junit-jupiter" }?.artefact == nil)
	}

	/// An aggregator declares no dependencies and its modules are subprojects
	/// with rows of their own — 0513's workspace member the other way up. "no
	/// dependencies" would be true of the POM and false about the build.
	@Test func anAggregatorPomSaysItsModulesHaveTheDependencies() throws {
		let root = try makeRoot()
		try write("""
		<project>
			<artifactId>everything</artifactId>
			<packaging>pom</packaging>
			<modules><module>service</module></modules>
		</project>
		""", to: root.appendingPathComponent("pom.xml"))

		let set = ExternalDependencies.read(root: root, kind: .maven)
		#expect(set.contents == .unresolved("an aggregator POM — its modules have the dependencies"))
	}

	/// `~/.m2/repository`, unless `settings.xml` moves it — which is the only
	/// thing that can, since Maven has no environment variable for it.
	@Test func theLocalRepositoryIsWhateverSettingsXmlSays() throws {
		let home = try makeRoot()
		#expect(ExternalDependencies.mavenLocalRepository(home: home).path
			== home.appendingPathComponent(".m2/repository").path)

		try write("""
		<settings>
			<localRepository>${user.home}/somewhere/else</localRepository>
		</settings>
		""", to: home.appendingPathComponent(".m2/settings.xml"))
		#expect(ExternalDependencies.mavenLocalRepository(home: home).path
			== home.appendingPathComponent("somewhere/else").path)
	}

	// MARK: - Gradle

	/// **Gradle turned out to be the better case, not the worse one.** A build
	/// that opted into `dependencyLocking` has the resolved graph on disk,
	/// transitives and all — as complete as a `Cargo.lock`, and read with no
	/// caveat at all.
	@Test func aGradleLockfileIsTheWholeGraphAndNeedsNoCaveat() throws {
		let root = try makeRoot()
		try write("build.gradle\n", to: root.appendingPathComponent("build.gradle"))
		try write("""
		# This is a Gradle generated file for dependency locking.
		# Manual edits can break the build and are not advised.
		com.google.guava:guava:33.2.1-jre=compileClasspath,runtimeClasspath
		org.slf4j:slf4j-api:2.0.13=compileClasspath,runtimeClasspath
		# A transitive one, which is the whole point of the file.
		com.google.guava:failureaccess:1.0.2=runtimeClasspath
		empty=annotationProcessor,testAnnotationProcessor
		""", to: root.appendingPathComponent("gradle.lockfile"))

		let set = ExternalDependencies.read(root: root, kind: .gradle)
		guard case let .packages(packages) = set.contents else {
			Issue.record("expected packages with no caveat, got \(set.contents)")
			return
		}
		#expect(packages.map(\.name) == ["failureaccess", "guava", "slf4j-api"])
		#expect(packages.first { $0.name == "guava" }?.version == "33.2.1-jre")
		#expect(packages.first { $0.name == "guava" }?.origin == "com.google.guava")
	}

	/// Gradle 5 wrote one file per configuration under `gradle/dependency-locks`,
	/// and plenty of builds still have that layout.
	@Test func theOlderPerConfigurationLockFilesAreReadToo() throws {
		let root = try makeRoot()
		try write("build.gradle\n", to: root.appendingPathComponent("build.gradle"))
		try write("# locked\ncom.google.guava:guava:31.1-jre\n",
			to: root.appendingPathComponent("gradle/dependency-locks/compileClasspath.lockfile"))
		try write("com.google.guava:guava:31.1-jre\norg.slf4j:slf4j-api:1.7.36\n",
			to: root.appendingPathComponent("gradle/dependency-locks/runtimeClasspath.lockfile"))

		let set = ExternalDependencies.read(root: root, kind: .gradle)
		#expect(set.contents == .packages([
			ExternalDependency(
				name: "guava", version: "31.1-jre", origin: "com.google.guava", localPath: nil
			),
			ExternalDependency(
				name: "slf4j-api", version: "1.7.36", origin: "org.slf4j", localPath: nil
			),
		]))
	}

	/// **The trap the pre-read named: `dependencies { }` is also what
	/// `buildscript { }` calls its plugin classpath.** Read without counting
	/// braces, a Spring Boot build claims to depend on the Spring Boot Gradle
	/// plugin, which is what builds it rather than what it is built from.
	@Test func aBuildscriptBlockIsNotTheProjectsDependencies() throws {
		let root = try makeRoot()
		try write("""
		buildscript {
			repositories { mavenCentral() }
			dependencies {
				classpath 'org.springframework.boot:spring-boot-gradle-plugin:3.3.0'
			}
		}

		apply plugin: 'java'

		dependencies {
			implementation 'com.google.guava:guava:33.2.1-jre'
		}
		""", to: root.appendingPathComponent("build.gradle"))

		let set = ExternalDependencies.read(root: root, kind: .gradle)
		#expect(set.packages.map(\.name) == ["guava"])
	}

	/// Every spelling a build file uses, in one file — the Kotlin DSL's
	/// parentheses, Groovy's bare quotes, `platform(…)`, the map form, an
	/// interpolated version and a `project(":…")` that is not external at all.
	@Test func aBuildFileWithoutALockfileGivesTheDirectDependenciesOnly() throws {
		let root = try makeRoot()
		try write("""
		plugins { id("java") }

		val slf4jVersion = "2.0.13"

		dependencies {
			implementation("com.google.guava:guava:33.2.1-jre")
			implementation 'org.apache.commons:commons-lang3:3.14.0'
			testImplementation(platform("org.junit:junit-bom:5.10.2"))
			implementation group: 'com.squareup.okhttp3', name: 'okhttp', version: '4.12.0'
			implementation("org.slf4j:slf4j-api:$slf4jVersion")
			implementation(project(":common"))
			implementation(files("libs/local.jar"))
		}
		""", to: root.appendingPathComponent("build.gradle.kts"))

		let set = ExternalDependencies.read(root: root, kind: .gradle)
		guard case let .partial(packages, caveat) = set.contents else {
			Issue.record("expected partial, got \(set.contents)")
			return
		}
		// `project(":common")` is a directory the tree already shows, the way a
		// Cargo `path` dependency is; `files(…)` is not a package at all.
		#expect(packages.map(\.name) == [
			"commons-lang3", "guava", "junit-bom", "okhttp", "slf4j-api",
		])
		// `"$slf4jVersion"` interpolates, and the literal is not a version.
		#expect(packages.first { $0.name == "slf4j-api" }?.version == nil)
		#expect(packages.first { $0.name == "okhttp" }?.version == "4.12.0")
		#expect(caveat == "direct dependencies only — Gradle resolves the transitive ones "
			+ "and one of these versions")
	}

	/// **Without the version catalog a modern build yields no rows at all.**
	/// Every line in its `dependencies { }` is `libs.something`, and the
	/// coordinates are in `gradle/libs.versions.toml` — which belongs to the
	/// build root, so a module one directory down still finds it.
	@Test func aVersionCatalogSuppliesTheCoordinatesTheBuildFileOnlyRefersTo() throws {
		let root = try makeRoot()
		try write("""
		[versions]
		jackson = "2.17.1"

		[libraries]
		jackson-databind = { module = "com.fasterxml.jackson.core:jackson-databind", version.ref = "jackson" }
		guava = { group = "com.google.guava", name = "guava", version = "33.2.1-jre" }
		commons-lang3 = "org.apache.commons:commons-lang3:3.14.0"
		""", to: root.appendingPathComponent("gradle/libs.versions.toml"))
		let module = root.appendingPathComponent("service")
		try write("""
		dependencies {
			implementation(libs.jackson.databind)
			implementation(libs.guava)
			// The accessor turns every separator into a dot, so both sides have
			// to be normalised or `commons-lang3` and `commons.lang3` never meet.
			implementation(libs.commons.lang3)
		}
		""", to: module.appendingPathComponent("build.gradle.kts"))

		let set = ExternalDependencies.read(root: module, kind: .gradle)
		#expect(set.packages.map(\.name) == ["commons-lang3", "guava", "jackson-databind"])
		#expect(set.packages.first { $0.name == "jackson-databind" }?.version == "2.17.1")
		#expect(set.packages.first { $0.name == "commons-lang3" }?.version == "3.14.0")
	}

	/// Gradle's cache puts a **checksum directory** between the version and the
	/// jar, and nothing outside Gradle can compute it — 0513's registry hash in a
	/// second spelling. So the level is listed rather than built.
	@Test func aGradleDependencyNamesTheJarUnderItsChecksumDirectory() throws {
		let root = try makeRoot()
		let home = try makeRoot()
		try write("build.gradle\n", to: root.appendingPathComponent("build.gradle"))
		try write("com.google.guava:guava:33.2.1-jre=runtimeClasspath\n",
			to: root.appendingPathComponent("gradle.lockfile"))
		try write("not really a jar\n", to: home.appendingPathComponent(
			"caches/modules-2/files-2.1/com.google.guava/guava/33.2.1-jre/"
				+ "4ee0a0dbcbd0b1ee0a0dbcbd0b1ee0a0dbcbd0b1/guava-33.2.1-jre.jar"
		))

		guard case let .packages(packages) = ExternalDependencies.readGradlePackages(
			at: root, gradleHome: home
		) else {
			Issue.record("expected packages")
			return
		}
		let guava = try #require(packages.first)
		#expect(guava.localPath == nil)
		#expect(guava.artefact?.lastPathComponent == "guava-33.2.1-jre.jar")
	}

	/// A settings file and no build file is the root of a multi-project build,
	/// whose projects are subprojects with rows of their own — the Gradle
	/// spelling of what a Cargo workspace member says.
	@Test func aSettingsOnlyRootSaysItsProjectsHaveTheDependencies() throws {
		let root = try makeRoot()
		try write("rootProject.name = \"everything\"\ninclude(\":service\")\n",
			to: root.appendingPathComponent("settings.gradle.kts"))

		let set = ExternalDependencies.read(root: root, kind: .gradle)
		#expect(set.contents == .unresolved(
			"a settings file only — its projects have the dependencies"
		))
	}

	/// A build file with no `dependencies { }` at all depends on nothing, and
	/// that is a reading rather than a failure to read — the same claim `go.mod`
	/// with no `require` makes. `abydos-examples/java/gradle-service` is exactly
	/// this build.
	@Test func aGradleBuildThatDeclaresNoDependenciesIsReadAsHavingNone() throws {
		let root = try makeRoot()
		try write("plugins { application }\n", to: root.appendingPathComponent("build.gradle.kts"))

		#expect(ExternalDependencies.read(root: root, kind: .gradle).contents == .packages([]))
	}

	/// **How a partial list says it is partial, as the section draws it**: the
	/// rows, and under them one note in the same shape as "no dependencies".
	@Test func aPartialListDrawsItsCaveatAsANoteUnderTheRows() throws {
		let root = try makeRoot()
		try write(pom, to: root.appendingPathComponent("pom.xml"))

		let tree = try #require(DependencyTree(sets: [
			ExternalDependencies.readMavenPackages(at: root, repository: try makeRoot()),
		].map { DependencySet(root: root, kind: .maven, contents: $0) }, project: root))
		#expect(tree.report() == [
			"Dependencies — Maven",
			"  commons-lang3 — 3.14.0  ·  org.apache.commons",
			"  jackson-databind — 2.17.1  ·  com.fasterxml.jackson.core",
			// No version: the row is the name and where it came from, and the
			// note underneath is what says why the version is missing.
			"  junit-jupiter — org.junit.jupiter",
			"  direct dependencies only — Maven resolves the transitive ones "
				+ "and one of these versions",
		])
	}

	/// **The caveat is a sentence and the pane is not that wide.** Found by
	/// looking at it: a sidebar four hundred points across drew `direct
	/// dependencies only — Maven resolv.` and the tooltip said only which kind
	/// this was, so the half that mattered was reachable from nowhere.
	@Test func aNotesTooltipCarriesTheWholeOfWhatTheRowCannotShow() throws {
		let root = try makeRoot()
		try write(pom, to: root.appendingPathComponent("pom.xml"))

		let tree = try #require(DependencyTree(sets: [
			ExternalDependencies.read(root: root, kind: .maven),
		], project: root))
		let note = try #require(tree.root.childNodes.last)
		#expect(note.title.hasPrefix("direct dependencies only"))
		#expect(note.detail?.hasPrefix(note.title) == true)
		#expect(note.detail?.contains("Maven in " + root.path) == true)
	}

	// MARK: - Kinds nothing reads yet

	/// **The claim that makes shipping some kinds honest.** A project of a kind
	/// nothing reads does not show an empty section; it shows a row saying its
	/// dependencies are not read, with the number of the item that will read
	/// them.
	///
	/// The example was Maven until 0515 taught it, and is Bazel until 0516 does.
	/// The claim is about the row and not about the kind, so it moves each time
	/// rather than being deleted — the day it has no subject left is the day
	/// every kind is read, and that is when it goes.
	@Test func aKindNobodyHasTaughtSaysSoRatherThanShowingNothing() throws {
		let root = try makeRoot()
		try write("module(name = \"probe\")\n", to: root.appendingPathComponent("MODULE.bazel"))

		let set = ExternalDependencies.read(root: root, kind: .bazel)
		#expect(set.contents == .notRead)

		let tree = try #require(DependencyTree(sets: [set], project: root))
		// The heading names the kind, because with one root there are no group
		// rows and nothing else would say what is not being read.
		// The kind is named once, by the heading. The note under it is the
		// message and nothing else — `Maven — Maven not read yet` is what
		// repeating it produced.
		#expect(tree.report() == ["Dependencies — Bazel", "  not read yet (0516)"])
	}

	/// Every kind this program can open is in the list, whether or not it is
	/// read — that is what stops a project's dependencies being silently
	/// omitted, which is the failure the item named in advance.
	@Test func everyKindEitherIsReadOrNamesTheItemThatWillReadIt() {
		for kind in DependencyKind.allCases {
			switch kind {
			case .swiftPackage, .goModule, .cargo, .maven, .gradle:
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
