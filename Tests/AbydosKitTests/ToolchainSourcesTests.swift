import Foundation
import Testing
@testable import AbydosKit

/// The files nobody declared: a compiler's own sources and an SDK's.
///
/// Item 539 was reported as `time.go` open in a tab marked `↗`, out of the Go
/// toolchain's `src/time`, with nothing in the tree able to reveal it — while
/// the `Dependencies` node correctly said `go-service — no dependencies`,
/// because that is the truth about its `go.mod`. Every claim here is about the
/// two halves of that: recognising a toolchain **from the path the language
/// server handed back**, and giving it a row that behaves like a package's.
struct ToolchainSourcesTests {
	private func makeRoot() throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("abydos-toolchain-tests-\(UUID().uuidString)")
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

	/// A Go distribution: `VERSION` beside `src`, which is what one is.
	@discardableResult
	private func makeGoRoot(_ home: URL, version: String = "go1.24.13") throws -> URL {
		try write("\(version)\ntime 2026-08-11T00:40:52Z\n", to: home.appendingPathComponent("VERSION"))
		return try write(
			"package time\n\nfunc runtimeNano() int64\n",
			to: home.appendingPathComponent("src/time/time.go")
		)
	}

	// MARK: - Go

	/// The reported case: the toolchain is read out of the path, not asked for.
	@Test func aGoStandardLibraryFileNamesTheToolchainItCameFrom() throws {
		let home = try makeRoot().appendingPathComponent("go/libexec")
		let file = try makeGoRoot(home)

		let toolchain = try #require(ToolchainSources.identify(file))
		#expect(toolchain.name == "Go standard library")
		#expect(toolchain.version == "go1.24.13")
		#expect(toolchain.provenance == "toolchain")
		#expect(FilePath.canonical(toolchain.home) == FilePath.canonical(home))
		// Rooted at `src`, so the row opens onto the standard library's
		// packages rather than onto `api`, `bin`, `lib`, `misc` and `pkg`.
		#expect(toolchain.sources.lastPathComponent == "src")
	}

	/// **Nothing is guessed and nothing is asked.** `GOROOT` is not read, `go
	/// env` is not run, and `~/go` is not assumed: the answer comes from the
	/// path the file was opened at, so a machine with three Go installations
	/// gets the one the definition actually came from.
	@Test func theToolchainFoundIsTheOneTheFileIsIn() throws {
		let root = try makeRoot()
		let first = root.appendingPathComponent("go-1.22")
		let second = root.appendingPathComponent("go-1.24")
		try makeGoRoot(first, version: "go1.22.9")
		let file = try makeGoRoot(second, version: "go1.24.13")

		#expect(ToolchainSources.identify(file)?.version == "go1.24.13")
	}

	/// The toolchains Go 1.21 and later download as modules have the same shape
	/// and are found by the same test — `$GOMODCACHE/golang.org/toolchain@v0.0.1-go1.24.13.darwin-arm64`.
	@Test func aToolchainInstalledAsAModuleIsFoundToo() throws {
		let home = try makeRoot()
			.appendingPathComponent("pkg/mod/golang.org/toolchain@v0.0.1-go1.24.13.darwin-arm64")
		let file = try makeGoRoot(home)

		#expect(ToolchainSources.identify(file)?.version == "go1.24.13")
	}

	/// A `src` directory is not a toolchain, which is the whole risk of
	/// recognising one by the shape of a path: half the repositories on this
	/// machine have one.
	@Test func anOrdinarySourceDirectoryIsNotAToolchain() throws {
		let root = try makeRoot()
		let file = try write("int main(void) { return 0; }\n", to: root.appendingPathComponent("src/main.c"))
		#expect(ToolchainSources.identify(file) == nil)

		// And a `VERSION` file that is not Go's does not make it one.
		try write("2.4.1\n", to: root.appendingPathComponent("VERSION"))
		#expect(ToolchainSources.identify(file) == nil)
	}

	/// The outermost `src` wins. `$GOROOT/src/vendor/golang.org/x/net` is
	/// inside the standard library rather than beside it.
	@Test func aVendoredDirectoryInsideTheStandardLibraryIsStillTheStandardLibrary() throws {
		let home = try makeRoot()
		try makeGoRoot(home)
		let vendored = try write(
			"package http\n",
			to: home.appendingPathComponent("src/vendor/golang.org/x/net/http/h2.go")
		)

		let toolchain = try #require(ToolchainSources.identify(vendored))
		#expect(FilePath.canonical(toolchain.sources) == FilePath.canonical(home) + "/src")
	}

	// MARK: - Apple's SDKs

	/// C and C++ system headers, which clangd answers with as real paths inside
	/// the `.sdk` it was given on its command line.
	@Test func aSystemHeaderNamesTheSDKItCameFrom() throws {
		let sdk = try makeRoot().appendingPathComponent(
			"Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
		)
		try write(
			#"{"DisplayName":"macOS 27.0","Version":"27.0","CanonicalName":"macosx27.0"}"#,
			to: sdk.appendingPathComponent("SDKSettings.json")
		)
		let header = try write("int printf(const char *, ...);\n",
			to: sdk.appendingPathComponent("usr/include/stdio.h"))

		let toolchain = try #require(ToolchainSources.identify(header))
		// The version is not said twice: `macOS 27.0 SDK — 27.0 · SDK` is what
		// taking the display name whole produced.
		#expect(toolchain.name == "macOS SDK")
		#expect(toolchain.version == "27.0")
		#expect(toolchain.provenance == "SDK")
		// Rooted at the `.sdk` itself: the headers are under `usr/include`, the
		// frameworks under `System/Library/Frameworks` and the Swift modules
		// under `usr/lib/swift`, so no one subtree holds all three.
		#expect(FilePath.canonical(toolchain.sources) == FilePath.canonical(sdk))
	}

	/// A directory named `.sdk` with nothing in it is not an SDK.
	@Test func aDirectoryNamedLikeAnSDKIsNotOne() throws {
		let sdk = try makeRoot().appendingPathComponent("Fake.sdk")
		let file = try write("\n", to: sdk.appendingPathComponent("usr/include/thing.h"))
		#expect(ToolchainSources.identify(file) == nil)
	}

	/// A display name that does not end in the version is kept whole rather
	/// than trimmed to something shorter and invented.
	@Test func anSDKNameThatDoesNotEndInItsVersionIsLeftAlone() {
		#expect(ToolchainSources.sdkPlatform(displayName: "iOS 18.2", version: "18.2") == "iOS")
		#expect(ToolchainSources.sdkPlatform(displayName: "macOS", version: "27.0") == "macOS")
		#expect(ToolchainSources.sdkPlatform(displayName: nil, version: "27.0") == nil)
	}

	// MARK: - The row it gets

	/// The gap 539 is about, end to end: a `go.mod` that requires nothing is
	/// still `no dependencies`, and the file from the toolchain is revealed
	/// anyway — under a row of its own, with its siblings beside it.
	@Test func aToolchainFileIsRevealedBesideTheModuleThatDeclaresNothing() throws {
		let project = try makeRoot()
		try write("module go-service\n\ngo 1.24\n", to: project.appendingPathComponent("go.mod"))
		let home = try makeRoot()
		let file = try makeGoRoot(home)
		let toolchain = try #require(ToolchainSources.identify(file))

		let set = ExternalDependencies.read(root: project, kind: .goModule)
		#expect(set.contents == .packages([]))

		let tree = try #require(DependencyTree(sets: [set], toolchains: [toolchain], project: project))
		#expect(tree.report() == [
			"Dependencies — Go modules",
			"  no dependencies",
			"  Go standard library — go1.24.13  ·  toolchain",
		])

		let located = try #require(tree.locate(file))
		#expect(located.node.name == "time.go")
		#expect(located.chain.last?.title == "Go standard library")
		// It is not a package, and nothing pretends it is: there is no origin
		// to report because no manifest names one.
		#expect(tree.package(containing: file) == nil)
	}

	/// **Nothing walks it.** An SDK's headers are tens of thousands of files
	/// and a JDK's classes more; the row costs one `FileNode` until somebody
	/// opens it, which is exactly what a package row costs.
	@Test func openingTheSectionDoesNotListTheToolchain() throws {
		let project = try makeRoot()
		try write("module go-service\n\ngo 1.24\n", to: project.appendingPathComponent("go.mod"))
		let home = try makeRoot()
		let file = try makeGoRoot(home)
		let toolchain = try #require(ToolchainSources.identify(file))

		let tree = try #require(DependencyTree(
			sets: [ExternalDependencies.read(root: project, kind: .goModule)],
			toolchains: [toolchain], project: project
		))
		let row = try #require(tree.root.childNodes.last)
		let fileRoot = try #require(row.fileRoot)
		#expect(row.isExpandable)
		#expect(!fileRoot.hasLoadedChildren)

		// And when it is opened, it is the standard library's packages that are
		// under it — `time`, and not `api`, `bin`, `pkg` and `test`.
		#expect(fileRoot.children.map(\.name) == ["time"])
	}

	/// A project of no recognised kind that somebody has followed a symbol out
	/// of gets a section holding the toolchain alone.
	///
	/// The rule 508 wrote was never "only a project with a manifest has a
	/// second root" — it was that an *empty* section is worse than none, and
	/// this one is not empty.
	@Test func aProjectWithNoBuildSystemStillShowsAToolchainItWasNavigatedInto() throws {
		let project = try makeRoot()
		let home = try makeRoot()
		let file = try makeGoRoot(home)
		let toolchain = try #require(ToolchainSources.identify(file))

		#expect(DependencyTree(sets: [], project: project) == nil)
		let tree = try #require(DependencyTree(sets: [], toolchains: [toolchain], project: project))
		#expect(tree.report() == ["Dependencies", "  Go standard library — go1.24.13  ·  toolchain"])
		#expect(tree.locate(file)?.node.name == "time.go")
	}

	/// The grey half is never a version on its own. `go1.24.13` and nothing
	/// else reads as a package whose origin this program failed to read, which
	/// is a different and worse claim than "this came with the compiler".
	@Test func theRowSaysWhatItIsWhereAPackageSaysWhereItCameFrom() throws {
		let home = try makeRoot()
		let file = try makeGoRoot(home)
		let toolchain = try #require(ToolchainSources.identify(file))
		let node = DependencyNode(row: .toolchain(toolchain))

		#expect(node.subtitle == "go1.24.13  ·  toolchain")
		let detail = try #require(node.detail)
		#expect(detail.hasPrefix("the Go toolchain's own sources — declared by no go.mod"))
		#expect(detail.contains(home.path))

		// A toolchain that wrote no version down still says what it is.
		let unversioned = Toolchain(
			name: "Go standard library", version: nil, provenance: "toolchain",
			sources: home.appendingPathComponent("src"), home: home, summary: "…"
		)
		#expect(DependencyNode(row: .toolchain(unversioned)).subtitle == "toolchain")
	}

	/// The row survives the section being reread, which happens whenever a lock
	/// file is written — and it has to, because nothing on disk would put it
	/// back: it was learned from a path, once.
	@Test func aToolchainRowKeepsItsIdentityAcrossARebuild() throws {
		let project = try makeRoot()
		let home = try makeRoot()
		let toolchain = try #require(ToolchainSources.identify(try makeGoRoot(home)))
		let first = try #require(DependencyTree(sets: [], toolchains: [toolchain], project: project))
		let second = try #require(DependencyTree(sets: [], toolchains: [toolchain], project: project))

		#expect(first.root.childNodes.map(\.identity) == second.root.childNodes.map(\.identity))
		#expect(first.root.childNodes.first?.identity == "toolchain:" + home.path)
	}
}
