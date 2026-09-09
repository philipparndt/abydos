import Foundation

/// One package a project depends on, named rather than pathed.
///
/// The unit of the project view's Dependencies section, and the answer to the
/// three questions item 508 was filed for: *which package is this file in*
/// (`name`), *where did it come from* (`origin`, `version`) and *what is beside
/// it* (`localPath`, which the tree lists like any other directory).
///
/// `localPath` is optional and that is not an oversight. A package can be
/// resolved and not fetched — a fresh checkout with a `Package.resolved` and no
/// `.build`, a `go.mod` naming a module that was never downloaded — and the
/// honest row for one of those names the package and offers nothing to open.
/// Pointing at a directory that is not there would make the tree show an empty
/// folder, which reads as a package with no files in it.
public struct ExternalDependency: Equatable, Sendable {
	/// What to call it: the repository's own name where there is one, so the
	/// row matches the directory the sources are in and the import somebody
	/// wrote.
	public let name: String
	/// The version or revision the resolver settled on, as it is written down.
	/// Nil when nothing names one.
	public let version: String?
	/// Where it came from, as the manifest or lock file writes it — a URL for a
	/// Swift package, a module path for a Go module, the registry or the git URL
	/// for a Cargo crate.
	public let origin: String
	/// The sources on disk, when they have been fetched.
	public let localPath: URL?
	/// Other copies of the same checkout on this machine.
	///
	/// A Swift package genuinely has two: `swift build` fetches into the
	/// project's `.build/checkouts`, and sourcekit-lsp — started with a
	/// `--scratch-path` under `~/Library/Caches/abydos/index`, because its index
	/// is derived data and does not belong in the checkout — fetches its own.
	/// Same revision, same files, two paths.
	///
	/// `localPath` is the one the section *shows*; these are the ones it will
	/// still recognise. Without them a file opened from the other copy has no
	/// row in the section and falls back to the ordinary tree, which for a
	/// Swift package means opening `.build` and walking ten levels down to the
	/// same file — the duplicate the section exists to replace.
	public let otherPaths: [URL]
	/// The one file this dependency resolved to, when it resolved to a file
	/// rather than to sources.
	///
	/// The JVM is why this exists. Maven and Gradle both fetch a **jar**, and a
	/// jar is not a directory — `localPath` has to stay nil for one, because a
	/// package row *is* a directory and pointing it at the folder the jar sits in
	/// draws a package whose files are a jar and a checksum. But `not fetched` is
	/// false about a dependency whose jar is right there on disk, so the tooltip
	/// names the artefact instead, and the row stays unexpandable.
	public let artefact: URL?

	public init(
		name: String, version: String?, origin: String, localPath: URL?,
		otherPaths: [URL] = [], artefact: URL? = nil
	) {
		self.name = name
		self.version = version
		self.origin = origin
		self.localPath = localPath
		self.otherPaths = otherPaths
		self.artefact = artefact
	}

	/// The origin without the noise, for a row eleven characters wide.
	///
	/// `https://github.com/tomasf/Cadova.git` is mostly scheme and mostly the
	/// same as the row above it; `github.com/tomasf` is what tells one package's
	/// provenance from another's at a glance. The whole of it stays available in
	/// the tooltip — this is what is *drawn*, not what is known.
	public var shortOrigin: String {
		var text = origin
		for prefix in ["https://", "http://", "git@", "ssh://"] where text.hasPrefix(prefix) {
			text = String(text.dropFirst(prefix.count))
		}
		if text.hasSuffix(".git") { text = String(text.dropLast(4)) }
		// The last component is the package's own name, which the row already
		// says. What is left is who it came from.
		let parts = text.split(separator: "/")
		guard parts.count > 1 else { return text }
		return parts.dropLast().joined(separator: "/")
	}
}

/// A build system whose dependencies this section knows how to talk about.
///
/// Deliberately a list of every kind `RunConfiguration.Source` can open rather
/// than a list of the kinds that are read: a project whose dependencies nothing
/// here can read must still appear, saying so. A section that quietly omitted
/// Maven would read as "this project has no dependencies", and that is the one
/// failure item 508 named in advance.
public enum DependencyKind: String, Sendable, CaseIterable {
	case swiftPackage
	case goModule
	case cargo
	case npm
	case maven
	case gradle
	case bazel
	case conan

	/// What the section calls it.
	public var title: String {
		switch self {
		case .swiftPackage: return "Swift packages"
		case .goModule: return "Go modules"
		case .cargo: return "Cargo"
		case .npm: return "npm"
		case .maven: return "Maven"
		case .gradle: return "Gradle"
		case .bazel: return "Bazel"
		case .conan: return "Conan"
		}
	}

	/// The files whose presence says a directory is a project of this kind.
	///
	/// Names only, checked with `fileExists` — the whole scan for a project with
	/// eight subprojects is a few dozen stats, which is what makes it affordable
	/// to do on load rather than behind a button.
	public var markers: [String] {
		switch self {
		case .swiftPackage: return ["Package.swift"]
		case .goModule: return ["go.mod"]
		case .cargo: return ["Cargo.toml"]
		case .npm: return ["package.json"]
		case .maven: return ["pom.xml"]
		case .gradle: return ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
		case .bazel: return ["MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel", "WORKSPACE.bzlmod"]
		case .conan: return ["conanfile.py", "conanfile.txt"]
		}
	}

	/// The backlog item that will teach this kind, for the kinds not read yet.
	///
	/// On the row, in the app, because that is the point of the note: somebody
	/// looking at a Maven project can see both that its dependencies are not
	/// read and where that is written down, without going to look for the
	/// backlog. Nil for a kind that is read.
	public var pendingItem: Int? {
		switch self {
		// Every kind is read as of 0515, so nothing names an item. The switch
		// stays exhaustive rather than becoming `return nil`: a kind added later
		// has to answer this, and answering it is how its rows say "not read yet
		// (0NNN)" instead of quietly rendering as no dependencies at all.
		case .swiftPackage, .goModule, .cargo, .npm, .maven, .gradle, .bazel, .conan: return nil
		}
	}
}

/// What one root's dependencies came out as.
///
/// Four answers and not two, because "nothing to show" has two quite different
/// causes and a row that conflated them would be the failure this whole item is
/// about: a kind nothing here can read, and a project of a kind that *is* read
/// which has resolved nothing yet.
