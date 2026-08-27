import Foundation

/// One submodule of a superproject: where it is, and which commit the
/// superproject records for it.
///
/// The commit here is the *gitlink* — what the superproject's index says the
/// submodule should be at. Where the submodule actually is, is a question for
/// that repository and not for this structure, and keeping the two apart is the
/// whole of what makes a moved gitlink legible.
public struct GitSubmodule: Equatable, Sendable, Identifiable {
	/// Path relative to the superproject's work tree root, with no trailing
	/// slash. This is the identity: `.gitmodules` names are decoration and can
	/// be absent, wrong, or duplicated across a rename.
	public let path: String

	/// The object name the superproject's index records for this submodule.
	public let recordedCommit: String

	/// The name `.gitmodules` gives it, when `.gitmodules` mentions it at all.
	public let name: String?

	/// The URL `.gitmodules` gives it, when `.gitmodules` mentions it at all.
	public let url: String?

	/// Whether there is a repository at `path` on disk.
	///
	/// A submodule the index names and disk lacks is ordinary: it is what a
	/// fresh clone without `--recurse-submodules` leaves, and what removing a
	/// service mid-refactoring leaves for everybody who has not pulled yet. It
	/// is shown as absent rather than fetched — the estate is read, not
	/// administered.
	public let isCheckedOut: Bool

	public var id: String { path }
	public var displayName: String { name ?? path }

	public init(
		path: String,
		recordedCommit: String,
		name: String? = nil,
		url: String? = nil,
		isCheckedOut: Bool = true
	) {
		self.path = path
		self.recordedCommit = recordedCommit
		self.name = name
		self.url = url
		self.isCheckedOut = isCheckedOut
	}
}

/// Reading which submodules a repository has.
///
/// **From the index, not from `git submodule`.** `git submodule status` is a
/// shell and a process per submodule, run serially: measured at 5.37 s for 200
/// submodules, against 0.01 s for the one `ls-files` call below — ten cores,
/// load averages 4.9 to 21.2, git 2.54.0. `--cached` does not help; it was
/// 5.82 s. Nothing here may cost a process per submodule, because the estates
/// this exists for hold three hundred.
public enum GitSubmodules {
	/// The mode git gives a gitlink in a tree or an index entry.
	static let gitlinkMode = "160000"

	/// Every submodule the index names, sorted by path.
	///
	/// Two calls, neither of which grows a process per submodule. The index
	/// decides what exists; `.gitmodules` only decorates it with a name and a
	/// URL, because the two disagree routinely and only one of them is what git
	/// will act on: a submodule removed from the index but left in
	/// `.gitmodules`, and one added to the index by somebody whose `.gitmodules`
	/// you have not pulled, are both ordinary states mid-refactoring.
	public static func inventory(in root: URL) async -> [GitSubmodule] {
		let listed = await gitlinks(in: root)
		guard !listed.isEmpty else { return [] }

		let configured = await configuredSubmodules(in: root)
		let manager = FileManager.default

		return listed
			.map { entry in
				let decoration = configured[entry.path]
				// `.git` rather than the directory: an empty directory is what
				// an uninitialised submodule leaves behind, and it exists.
				let dotGit = root.appendingPathComponent(entry.path)
					.appendingPathComponent(".git")
				return GitSubmodule(
					path: entry.path,
					recordedCommit: entry.commit,
					name: decoration?.name,
					url: decoration?.url,
					isCheckedOut: manager.fileExists(atPath: dotGit.path)
				)
			}
			.sorted { $0.path < $1.path }
	}

	/// The gitlinks in the index: one `git ls-files --stage`, filtered by mode.
	static func gitlinks(in root: URL) async -> [(path: String, commit: String)] {
		let result = await GitRepository.run(["ls-files", "--stage", "-z"], in: root)
		guard result.exitCode == 0 else { return [] }
		return parseStage(result.stdout)
	}

	/// Parses `git ls-files --stage -z`, keeping only gitlinks.
	///
	/// Records are `<mode> SP <object> SP <stage> TAB <path>`, NUL-separated.
	/// `-z` because without it git escapes any path that is not plain ASCII, and
	/// the escaped form is not a path any later command can find — the same
	/// reason `GitWorkingCopy.status` asks for it.
	static func parseStage(_ output: String) -> [(path: String, commit: String)] {
		var found: [(path: String, commit: String)] = []
		for record in output.split(separator: "\0", omittingEmptySubsequences: true) {
			guard let tab = record.firstIndex(of: "\t") else { continue }
			let fields = record[record.startIndex..<tab].split(separator: " ")
			guard fields.count >= 2, fields[0] == gitlinkMode else { continue }
			let path = String(record[record.index(after: tab)...])
			guard !path.isEmpty else { continue }
			found.append((path: path, commit: String(fields[1])))
		}
		return found
	}

	/// What `.gitmodules` says, keyed by the path it gives — which is the only
	/// key that can be matched against the index.
	static func configuredSubmodules(
		in root: URL
	) async -> [String: (name: String, url: String?)] {
		let result = await GitRepository.run(
			["config", "--file", ".gitmodules", "--list", "-z"], in: root
		)
		// A superproject need not have a `.gitmodules` at all, and git exits
		// non-zero when it does not. That is not a failure to report.
		guard result.exitCode == 0 else { return [:] }
		return parseGitmodules(result.stdout)
	}

	/// Parses `git config --list -z`, whose records are `key LF value`.
	///
	/// Keys are `submodule.<name>.<setting>`, and a name may itself contain
	/// dots — a submodule called `github.com/acme/svc` is legal — so the name is
	/// what is left after taking the known prefix off the front and the setting
	/// off the back, not the second component.
	static func parseGitmodules(_ output: String) -> [String: (name: String, url: String?)] {
		var paths: [String: String] = [:]  // name -> path
		var urls: [String: String] = [:]   // name -> url

		for record in output.split(separator: "\0", omittingEmptySubsequences: true) {
			let halves = record.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
			guard halves.count == 2 else { continue }
			let key = String(halves[0]), value = String(halves[1])
			guard key.hasPrefix("submodule.") else { continue }
			let rest = String(key.dropFirst("submodule.".count))
			guard let lastDot = rest.lastIndex(of: ".") else { continue }
			let name = String(rest[rest.startIndex..<lastDot])
			let setting = String(rest[rest.index(after: lastDot)...])
			guard !name.isEmpty else { continue }
			if setting == "path" { paths[name] = value }
			if setting == "url" { urls[name] = value }
		}

		var byPath: [String: (name: String, url: String?)] = [:]
		for (name, path) in paths {
			byPath[path] = (name: name, url: urls[name])
		}
		return byPath
	}
}
