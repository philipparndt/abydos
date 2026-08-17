import Foundation

/// A compiler's or an SDK's own sources — the files nobody declared.
///
/// Every reader behind the Dependencies section answers one question: *what did
/// this project declare, and what did that resolve to*. A `Package.resolved`, a
/// `go.mod`'s `require`s and a `Cargo.lock` are all answers to it. A toolchain's
/// own sources are an answer to nothing, because no manifest names them: they
/// arrive with the compiler. So `time.go` out of `$GOROOT/src/time` — the file
/// item 539 was reported about — falls out of that model rather than being
/// mishandled by it, and this is the row it gets instead.
public struct Toolchain: Equatable, Sendable {
	/// What the row is called. Not a package name, because it is not a package:
	/// `Go standard library`, `macOS SDK`.
	public let name: String
	/// The version, where the toolchain writes one down. `go1.26.6`, `27.0`.
	public let version: String?
	/// The word that stands where a package row's origin stands.
	///
	/// A package row's grey half is `version  ·  where it came from`, and a
	/// toolchain has no origin in that sense — there is no registry, no
	/// repository and no lock file entry. It is still not allowed to be blank:
	/// a row reading `go1.26.6` and nothing else would look like a package
	/// whose origin this program failed to read, which is a different and
	/// worse claim. So it says what it *is* — `toolchain`, `SDK` — which is
	/// the honest answer to "where did this come from".
	public let provenance: String
	/// The directory the row lists: the one whose children are worth having.
	public let sources: URL
	/// The toolchain's own root, which is where the tooltip points.
	public let home: URL
	/// The first line of the tooltip, saying what these files are.
	public let summary: String

	public init(
		name: String, version: String?, provenance: String,
		sources: URL, home: URL, summary: String
	) {
		self.name = name
		self.version = version
		self.provenance = provenance
		self.sources = sources
		self.home = home
		self.summary = summary
	}
}

/// Recognises a toolchain from a path that has already been handed to us.
///
/// **Nothing here asks a tool anything, and nothing here guesses.** The rule the
/// dependencies section is held to — see `ExternalDependencies` — is that no
/// reader runs a build tool, and `go env GOROOT` is running a build tool. The
/// two shapes already in this project for finding a cache outside the project,
/// `goModuleCache()` and `cargoHome()`, dodge that with the tool's own
/// environment variable and then a default under the home directory; both are
/// guesses that are right on a machine nobody has reconfigured.
///
/// This needs neither, because it is asked a different question. The section is
/// built when a project opens and has to *find* the caches; this runs when a
/// file has already been opened and its path is in hand — the language server
/// has just answered `textDocument/definition` with an absolute path, and that
/// path is authoritative in a way `$GOROOT` never is. So the toolchain root is
/// **read out of the answer**: the ancestor of that file which looks like a
/// toolchain, confirmed by one small file sitting in it. No subprocess, no
/// environment variable, no default under `~`, and no possibility of naming a
/// toolchain other than the one the file actually came from.
///
/// The cost of that choice, and it is the honest one: a toolchain has no row
/// until somebody has been into it. There is no `Go standard library` row on a
/// freshly opened project. That is right rather than merely cheap — a row for a
/// toolchain nobody has visited would be this program guessing which `go` the
/// project builds with, and it would be wrong on the first machine with two.
public enum ToolchainSources {
	/// The toolchain a file belongs to, if it belongs to one.
	///
	/// Ordered cheapest first, and every recogniser tests the *shape of the
	/// path* before it touches the disk — this is called as tabs are switched,
	/// and an ordinary file in an ordinary project must cost string comparisons
	/// and nothing else.
	public static func identify(_ file: URL) -> Toolchain? {
		let path = FilePath.canonical(file)
		let components = path.split(separator: "/").map(String.init)
		return goToolchain(of: components) ?? appleSDK(of: components)
	}

	/// A URL for the first `count` components of an absolute path.
	private static func directory(_ components: [String], upTo count: Int) -> URL {
		URL(fileURLWithPath: "/" + components.prefix(count).joined(separator: "/"), isDirectory: true)
	}

	// MARK: - Go

	/// `$GOROOT`, recognised rather than asked for.
	///
	/// A Go distribution is `VERSION` and `src/` in the same directory, and
	/// `VERSION`'s first line is the version — `go1.26.6` — which is the same
	/// string `go env GOROOT`'s neighbour `go version` would print. Both the
	/// installed toolchain (`/usr/local/go`, Homebrew's `…/go/libexec`) and the
	/// ones Go 1.21 downloads as modules
	/// (`$GOMODCACHE/golang.org/toolchain@v0.0.1-go1.24.13.darwin-arm64`) have
	/// exactly that shape, so both are found by the same test.
	///
	/// The **outermost** `src` wins. `$GOROOT/src/vendor/golang.org/x/net` is
	/// inside the standard library rather than beside it, and answering with
	/// the inner directory would give it a row of its own.
	///
	/// The names are read and compared exactly rather than asked of
	/// `fileExists`, for the reason `FilePath.entryNames` exists: a Mac formats
	/// a disk case-insensitively, so `fileExists` says yes to `VERSION` for any
	/// directory holding an ordinary `version` file.
	static func goToolchain(of components: [String]) -> Toolchain? {
		for (index, component) in components.enumerated() where component == "src" {
			// The file has to be *inside* `src`, not be it: a row rooted at a
			// directory the tab is not under could never place the tab.
			guard index + 1 < components.count else { continue }
			let home = directory(components, upTo: index)
			guard let names = FilePath.entryNames(in: home),
			      names.contains("VERSION"), names.contains("src"),
			      let version = goVersion(in: home)
			else { continue }
			return Toolchain(
				name: "Go standard library",
				version: version,
				provenance: "toolchain",
				// Rooted at `src` and not at `$GOROOT`. The children of `src`
				// are the standard library's packages — `time`, `fmt`, `net` —
				// which is the list somebody following a symbol into `time.go`
				// wants beside it. `$GOROOT` itself lists `api`, `bin`, `lib`,
				// `misc`, `pkg` and `test` as well, so the row would open onto
				// a distribution and the packages would be one level further
				// down, behind six directories nobody is looking for.
				sources: home.appendingPathComponent("src"),
				home: home,
				summary: "the Go toolchain's own sources — declared by no go.mod"
			)
		}
		return nil
	}

	/// The first line of `$GOROOT/VERSION`, which is `go1.26.6`.
	///
	/// The rest of the file is a build timestamp. Checked for the `go` prefix
	/// and a digit rather than taken on trust: this is what tells a Go
	/// distribution from any other directory that happens to hold a `VERSION`
	/// file and a `src` directory, which is not a rare shape.
	static func goVersion(in home: URL) -> String? {
		guard let text = try? String(
			contentsOf: home.appendingPathComponent("VERSION"), encoding: .utf8
		) else { return nil }
		let first = text.split(separator: "\n", maxSplits: 1).first?
			.trimmingCharacters(in: .whitespaces) ?? ""
		guard first.hasPrefix("go"), first.dropFirst(2).first?.isNumber == true else { return nil }
		return first
	}

	// MARK: - Apple's SDKs

	/// An `.sdk`, which is where C and C++ system headers come from.
	///
	/// clangd is given the SDK on its command line and answers with real paths
	/// inside it — `…/MacOSX.sdk/usr/include/stdio.h` — so the same recognition
	/// works: an ancestor whose name ends in `.sdk` and which holds an
	/// `SDKSettings.json`, which is JSON and names the SDK and its version.
	///
	/// Rooted at the `.sdk` itself, unlike Go's. There is no one subtree: the
	/// headers are under `usr/include`, the frameworks under
	/// `System/Library/Frameworks`, and the Swift modules under `usr/lib/swift`
	/// — so a row rooted at any of the three would fail to place a file from
	/// the other two.
	static func appleSDK(of components: [String]) -> Toolchain? {
		for (index, component) in components.enumerated() where component.hasSuffix(".sdk") {
			guard index + 1 < components.count else { continue }
			let home = directory(components, upTo: index + 1)
			guard let names = FilePath.entryNames(in: home), names.contains("SDKSettings.json"),
			      let settings = (try? Data(contentsOf: home.appendingPathComponent("SDKSettings.json")))
			      	.flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any]
			else { continue }
			let version = settings["Version"] as? String
			let platform = sdkPlatform(displayName: settings["DisplayName"] as? String, version: version)
			return Toolchain(
				name: (platform.map { $0 + " " } ?? "") + "SDK",
				version: version,
				provenance: "SDK",
				sources: home,
				home: home,
				summary: "the SDK's own headers and modules — declared by no manifest"
			)
		}
		return nil
	}

	/// `macOS` out of `macOS 27.0`, so the row does not read `macOS 27.0 SDK —
	/// 27.0 · SDK`. The whole display name where it does not end in the
	/// version, since inventing a shorter name is worse than a long row.
	static func sdkPlatform(displayName: String?, version: String?) -> String? {
		guard let displayName, !displayName.isEmpty else { return nil }
		guard let version, displayName.hasSuffix(" " + version) else { return displayName }
		return String(displayName.dropLast(version.count + 1))
	}
}
