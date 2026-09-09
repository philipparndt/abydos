import Foundation

public struct DependencySet: Equatable, Sendable {
	public enum Contents: Equatable, Sendable {
		/// Read, and this is what it says. Possibly empty — a `go.mod` with no
		/// `require` is a module with no dependencies, and saying so is right.
		case packages([ExternalDependency])
		/// Read, real, and known to be **incomplete** — with the caveat that says
		/// in what way, in the words of the tool that holds the rest.
		///
		/// The fourth answer, added by 0515, and the JVM is why. Every kind read
		/// before it resolves whole from disk: a `Package.resolved`, a `go.mod`, a
		/// `Cargo.lock` are all the finished graph. A `pom.xml` is the *input* to
		/// resolution — no transitives, and a version that may be managed by a BOM
		/// in `~/.m2` — and a Gradle build with no lock file is the same. That
		/// list is not `.unresolved`: the rows in it are true, and dropping them
		/// would hide dependencies a project really has. Nor is it `.packages`,
		/// which reads as the whole of what a project depends on. So it is its own
		/// answer, drawn as the rows *and* a note that says what is missing.
		case partial([ExternalDependency], caveat: String)
		/// The kind is recognised and nothing here reads it yet.
		case notRead
		/// The kind is read, and there is nothing resolved to read. The string
		/// says what is missing, in the words of the tool that would make it.
		case unresolved(String)
	}

	/// The directory this was read from: the project, or one of its subprojects.
	public let root: URL
	public let kind: DependencyKind
	/// The tool that actually resolved this root, when the kind does not name it.
	///
	/// **0525, and only JavaScript needs it.** `DependencyKind` is keyed off the
	/// marker file, and `package.json` is npm's, pnpm's and yarn's alike — so one
	/// kind covers three tools and its own name is wrong for two of them. Three
	/// kinds would be worse: `kinds(at:)` filters on markers, so every JavaScript
	/// project would grow three sets, two of them saying nothing, which is the
	/// empty-list failure 508 was filed to prevent wearing three headings.
	///
	/// So the kind stays one and the *title* is read off the lock file that is
	/// there, once, when the section is read — not while it is drawn. A tooltip
	/// that cost four `stat`s per hover would be the rule this whole type is
	/// written against.
	public let tool: String?
	public let contents: Contents

	public init(root: URL, kind: DependencyKind, tool: String? = nil, contents: Contents) {
		self.root = root
		self.kind = kind
		self.tool = tool
		self.contents = contents
	}

	/// What the section calls this set: the tool that resolved it where that is
	/// known, and the kind's own name otherwise.
	public var title: String { tool ?? kind.title }

	public var packages: [ExternalDependency] {
		switch contents {
		case let .packages(packages): return packages
		case let .partial(packages, _): return packages
		case .notRead, .unresolved: return []
		}
	}
}

/// Finds what a project depends on, from what is already on disk.
///
/// **No subprocess, from any reader, ever.** `SwiftPackage`'s own comment has
/// the measurements: `swift package dump-package` costs the better part of a
/// second per manifest, leaves a `.build` directory behind as a side effect of
/// being *asked*, and answers with whichever toolchain is first on the PATH.
/// The same argument applies to `go list -m all`, `mvn dependency:list` and
/// `bazel query`, and it applies harder here — this runs when a project opens
/// and again whenever a lock file is written, so anything expensive is paid
/// over and over while somebody is trying to read a file.
///
/// 0516 asked whether Bazel and Conan could be an exception, since neither has
/// a lock file this obviously reads, and the answer came back a firmer no than
