import CryptoKit
import Foundation

/// The tools this app ships a Dockerfile for, and the image built from one on
/// the machine that wants it.
///
/// The third answer to "where does the tool come from", beside the copy
/// installed here and the image somebody names. `ToolImageCatalogue` lists
/// images that are published, pulled and driven, which is honest and is a
/// standing commitment: a repository per tool, a tag to move when upstream
/// moves, and a registry account that has to stay alive for the app to keep
/// working. Shipping the *recipe* instead costs a text file in this repository
/// and a build the first time somebody uses it.
///
/// What that buys, and it is most of the argument: nothing is pushed, nothing
/// is pulled from a repository this project owns, and no multi-architecture
/// build happens — the machine builds for the architecture it is, which is the
/// only one it will ever run. Measured while publishing gopls, that is the
/// expensive half outright: 17 seconds for arm64 native against 110 for amd64
/// under emulation, in the same build.
///
/// What it costs is that the first use is a build rather than a pull, minutes
/// rather than seconds, and that a build can fail in ways a pull cannot. Both
/// are dealt with where they happen — `ContainerImageStore` says which of them
/// it was — rather than pretended away here.
public enum ToolImageRecipes {
	/// A Dockerfile this app ships, and the image it makes.
	public struct Recipe: Equatable, Sendable {
		/// The tool's key, which is the directory's name under `ToolImages/`
		/// and the same key `.abydos/tools.json` and settings use.
		public let tool: String
		/// The build context: the directory holding the Dockerfile.
		public let context: URL
		/// What the built image is called, including the tag derived from the
		/// recipe's own contents.
		public let image: String

		public init(tool: String, context: URL, image: String) {
			self.tool = tool
			self.context = context
			self.image = image
		}
	}

	/// The value a project or a settings page stores to mean "the Dockerfile
	/// this app ships".
	///
	/// A word rather than an image name, because the name cannot be written
	/// down: it carries the recipe's fingerprint, so a checked-in
	/// `.abydos/tools.json` naming one would pin the project to whatever the
	/// Dockerfile said on the day somebody chose it, and stop rebuilding on the
	/// day it was edited — which is the one behaviour this whole route exists
	/// to have.
	public static let buildHere = "build"

	/// The repository part of every image built here.
	///
	/// Not `abydos/…`, which is what a published image would plausibly be
	/// called and would therefore be pulled by somebody's `docker pull` one day.
	/// This one is local by construction: nothing pushes it and nothing fetches
	/// it, and a name that says so is a name nobody mistakes for an artefact.
	public static let namespace = "abydos-built"

	// MARK: - Finding the recipes

	/// The directory the Dockerfiles are in, or nil when there is none.
	///
	/// Two places, and the second is not a fallback for the first failing but
	/// for a different way of running: the `.app` carries them under its own
	/// resources, and a checkout — a test, `swift run`, a debug build launched
	/// from the build directory — still has them in the source tree. The same
	/// shape `FontRegistry` uses for the bundled fonts, and for the same reason.
	public static func directory() -> URL? {
		var candidates: [URL] = []
		if let resources = Bundle.main.resourceURL {
			candidates.append(resources.appendingPathComponent("ToolImages", isDirectory: true))
		}
		candidates.append(
			URL(fileURLWithPath: #filePath)
				.deletingLastPathComponent()   // Run
				.deletingLastPathComponent()   // AbydosKit
				.deletingLastPathComponent()   // Sources
				.deletingLastPathComponent()   // repository root
				.appendingPathComponent("ToolImages", isDirectory: true)
		)
		return candidates.first { directoryExists($0) }
	}

	/// The recipe for a tool, or nil when this app ships none for it.
	///
	/// Nil is the ordinary answer and not an error: only two tools have a
	/// Dockerfile here, and the option to build one is offered for those two
	/// rather than for everything in the catalogue.
	public static func recipe(forTool tool: String) -> Recipe? {
		guard !tool.isEmpty, let directory = directory() else { return nil }
		let context = directory.appendingPathComponent(tool, isDirectory: true)
		guard FileManager.default.fileExists(
			atPath: context.appendingPathComponent("Dockerfile").path
		) else { return nil }
		guard let fingerprint = fingerprint(of: context) else { return nil }
		return Recipe(tool: tool, context: context, image: "\(namespace)/\(tool):\(fingerprint)")
	}

	/// Which recipe an image name came from, or nil when the name is not one of
	/// ours.
	///
	/// This is how a build stays invisible to everything that only deals in
	/// image names. A launch carries an image and a runtime and nothing else —
	/// `LanguageServerLaunch.image`, `ContainerImageStore.ensure` — and
	/// threading "and here is how to make it" through all of that would put a
	/// parameter on every one of them for the sake of two tools. The name
	/// already says everything, because the name is derived from the recipe: the
	/// namespace says it is built here, the repository says which tool, and the
	/// tag is the fingerprint.
	///
	/// A name in this namespace whose fingerprint no longer matches the
	/// Dockerfile on disk answers with the *current* recipe rather than nil.
	/// That is deliberate: the only way to hold a stale name is to have written
	/// one down somewhere it should not have been, and building the recipe this
	/// app actually ships is the useful thing to do about it.
	public static func recipe(forImage image: String) -> Recipe? {
		guard isBuiltHere(image) else { return nil }
		let rest = image.dropFirst(namespace.count + 1)
		let tool = rest.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
		return recipe(forTool: tool)
	}

	/// Whether an image name is one this app makes rather than one a registry
	/// has.
	///
	/// The name alone, and deliberately cheaper than `recipe(forImage:)`, which
	/// walks the build context and hashes every file in it to work out what the
	/// current fingerprint is. Something that only wants to *say* which of a
	/// build and a fetch is about to happen — the name of a tab, a sentence in
	/// front of somebody — should not pay for a directory walk to find out, and
	/// the namespace is the whole answer to that question anyway.
	public static func isBuiltHere(_ image: String) -> Bool {
		image.hasPrefix(namespace + "/")
	}

	/// What a stored value means, once. Anything that is not the "build it here"
	/// word is an image name and is left exactly as it was.
	public static func resolve(image stored: String, forTool tool: String) -> String? {
		guard stored == buildHere else { return stored.isEmpty ? nil : stored }
		return recipe(forTool: tool)?.image
	}

	// MARK: - The fingerprint

	/// A short digest of everything in the build context.
	///
	/// The whole directory rather than the Dockerfile alone. Today both recipes
	/// are a single file, so the two would agree — and that is a fact about
	/// today rather than a rule: the moment a context gains an entrypoint script
	/// or a pinned lock file, a tag derived from the Dockerfile would leave an
	/// edited script running out of an image that never rebuilt, which is a
	/// wrong answer that looks like a caching bug.
	///
	/// The path goes into the digest as well as the contents, so moving a file
	/// changes the answer and two files swapping contents do not cancel out.
	static func fingerprint(of context: URL) -> String? {
		let manager = FileManager.default
		guard let walk = manager.enumerator(
			at: context, includingPropertiesForKeys: [.isRegularFileKey]
		) else { return nil }

		var files: [(String, Data)] = []
		for case let url as URL in walk {
			guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
			      let data = try? Data(contentsOf: url)
			else { continue }
			files.append((url.lastPathComponentRelative(to: context), data))
		}
		guard !files.isEmpty else { return nil }

		var digest = SHA256()
		for (name, data) in files.sorted(by: { $0.0 < $1.0 }) {
			digest.update(data: Data(name.utf8))
			digest.update(data: Data([0]))
			digest.update(data: data)
			digest.update(data: Data([0]))
		}
		// Twelve hex characters. Long enough that two recipes colliding is not
		// something anybody will see, and short enough to read in a log line
		// beside the image it names.
		return digest.finalize().map { String(format: "%02x", $0) }.joined().prefix(12).lowercased()
	}

	// MARK: - Building

	/// The command that builds it.
	///
	/// No `--platform`: the machine builds for the architecture it is, which is
	/// the only one it will ever run this image on. That is the saving, and
	/// naming a platform here would spend it.
	///
	/// **And no `--build-arg`, which 0462 asked about and decided against for
	/// now.** It would work, and the condition on it is the thing worth writing
	/// down rather than the answer: the image is named `<tool>:<fingerprint of
	/// the context>`, so an argument that is *not* in the fingerprint would give
	/// two different images one name, and the next project would silently get the
	/// one built for the last. Hashing the arguments beside the files is a few
	/// lines and makes the naming hold again — a different argument is a
	/// different image, which is exactly what "an edited recipe rebuilds" already
	/// says. `.abydos/tools.json` has the room to ask for one, too: its object
	/// shape was added for exactly this kind of thing.
	///
	/// What is missing is a use. The case it was raised for is Rust, and neither
	/// half of Rust wants it: a pinned *release* already works, because rustup
	/// inside the image fetches a release it has not got, and a pinned *custom
	/// channel* cannot be built at all — there is nothing for rustup to install
	/// it from, whatever it is told the name is. So the mechanism would cost a
	/// full toolchain image per project and answer neither, which is the shape of
	/// thing this repository already refuses to list as known-good elsewhere. See
	/// `ToolchainPin`.
	///
	/// The day something does want it — a jdtls image on the JDK a project's
	/// `.java-version` names, once an image without a network makes Java stop
	/// hiding this — the argument goes in the fingerprint first.
	public static func build(
		_ recipe: Recipe, using runtime: ContainerRuntime
	) -> (executable: String, arguments: [String]) {
		// The same verb in both, unlike `pull`: docker and Apple's `container`
		// each take `build -t <name> <context>`.
		(runtime.path, ["build", "-t", recipe.image, recipe.context.path])
	}

	/// How long a build gets.
	///
	/// Longer than a pull, and it has to be: `cargo install openscad-lsp`
	/// compiles a tree-sitter grammar and some hundreds of crates, which is
	/// minutes on an idle machine and more on a busy one. The deadline is here
	/// to catch a build that has stopped rather than one that is slow.
	public static let buildDeadline: TimeInterval = 2400

	/// What to say while it is happening.
	///
	/// Deliberately not the same sentence as a pull. The first use of a
	/// build-here tool is minutes with nothing to show for it, and somebody who
	/// is told "fetching" will conclude their network is broken.
	public static func progressMessage(for recipe: Recipe) -> String {
		"Building \(recipe.tool) from the Dockerfile Abydos ships. "
			+ "This happens once, and takes a few minutes."
	}

	/// Why a build failed, in a sentence somebody can act on.
	///
	/// A build fails in ways a pull cannot, which is the honest cost of this
	/// route: the base image has to be fetched, a compiler has to work, and a
	/// package index has to be reachable. Each of those has a different answer,
	/// and the runtime's own output — hundreds of lines of build log — says
	/// which one only if you read all of it.
	public static func explain(_ output: String, recipe: Recipe) -> String {
		let text = output.lowercased()

		if text.contains("cannot connect") || text.contains("is the docker daemon running")
			|| text.contains("daemon") {
			return "The container runtime is not running, so \(recipe.tool) could not be built."
		}
		if text.contains("no such host") || text.contains("dial tcp")
			|| text.contains("network is unreachable")
			|| text.contains("temporary failure in name resolution")
			|| text.contains("could not resolve host")
			|| text.contains("failed to fetch") || text.contains("tls handshake timeout") {
			return "\(recipe.tool) could not be built because the network was not there: "
				+ "the base image and the packages in \(recipe.context.lastPathComponent)/Dockerfile "
				+ "are both fetched during the build. A proxy that is not configured "
				+ "for the runtime looks the same from here."
		}
		if text.contains("unauthorized") || text.contains("authentication required")
			|| text.contains("denied") {
			return "The registry refused the base image \(recipe.tool)'s Dockerfile builds on. "
				+ "Log in with the runtime's own command and try again."
		}
		if text.contains("no space left on device") {
			return "There was no room to build \(recipe.tool). "
				+ "The runtime's disk is what fills up, not this machine's."
		}
		// Everything else is the recipe itself failing — a compiler error, a
		// version that no longer exists, a step that returned non-zero — and
		// this app has nothing useful to add about which. What it can do is say
		// where the file is, since unlike a published image it is one somebody
		// can open and change.
		let last = output
			.split(separator: "\n", omittingEmptySubsequences: true)
			.last
			.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
		return "Building \(recipe.tool) failed"
			+ (last.isEmpty ? "" : ": \(last)")
			+ ". The recipe is \(recipe.context.path)/Dockerfile."
	}

	private static func directoryExists(_ url: URL) -> Bool {
		var isDirectory: ObjCBool = false
		let there = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
		return there && isDirectory.boolValue
	}
}

private extension URL {
	/// This URL's path with `base`'s prefix removed, for a name that is stable
	/// wherever the context happens to live — the source tree on one machine and
	/// an app bundle on another have to fingerprint the same.
	func lastPathComponentRelative(to base: URL) -> String {
		let mine = standardizedFileURL.path
		let theirs = base.standardizedFileURL.path
		guard mine.hasPrefix(theirs + "/") else { return lastPathComponent }
		return String(mine.dropFirst(theirs.count + 1))
	}
}
