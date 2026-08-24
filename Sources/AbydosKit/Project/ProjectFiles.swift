import Foundation

/// The files a project is made of, listed as cheaply as the project allows.
///
/// Two callers want this list and they used to want it from one place each:
/// project search walked the tree, and nothing else asked at all. The walk's
/// rules — which directories to skip, how big is too big, symlinks — are the
/// right ones and are not worth having twice, so they live here and
/// `ProjectSearch` asks for them rather than owning them. A directory name added
/// to the excluded directories setting is then skipped by both without either
/// being changed.
///
/// **Where there is a repository, git is asked instead, and it is not close.**
/// Measured on a work tree of 24,691 tracked files:
///
///     git ls-files                                        24,691   0.03 s
///     git ls-files --cached --others --exclude-standard    24,692   4.56 s
///     the walk below, with its exclusions                  25,564   3.05 s
///     the same walk excluding only .git                    79,056   7.90 s
///
/// The second line is the one that decides it. Asking git for untracked files
/// that are not ignored costs a hundred times more than asking for tracked ones
/// and, on that repository, finds *one* extra file — because to know what is
/// untracked git has to walk the work tree, which is the same reason
/// `git status -uall` was slow enough to make switching projects feel broken.
///
/// So: tracked files where there is a repository, the walk where there is not.
/// What that gives up is a file created a moment ago and never committed, which
/// is why `FileIndex` watches for those rather than asking git again.
public enum ProjectFiles {
	/// Files worth listing, as paths relative to the project root.
	///
    /// Relative because that is what everything downstream wants: it is what is
	/// matched against, what is shown, and what stays true if the project is
	/// moved. The absolute path is one `appendingPathComponent` away.
	public static func list(
		in root: URL, maximumFileSize: Int = defaultMaximumFileSize
	) async -> [String] {
		if let tracked = await tracked(in: root) { return tracked }
		return walk(in: root, maximumFileSize: maximumFileSize)
			.compactMap { relativePath(of: $0, under: root) }
	}

	/// The size past which a file is not worth listing.
	///
	/// The same 4 MB `ProjectSearch` has always used: a file bigger than that is
	/// generated, and nobody is looking for it by name either.
	public static let defaultMaximumFileSize = 4 * 1024 * 1024

	// MARK: - Asking git

	/// Tracked files, or nil where this is not a work tree.
	///
	/// Deliberately `--cached` only. See the measurement above for what asking
	/// about untracked files costs and what it buys.
	public static func tracked(in root: URL) async -> [String]? {
		let result = await GitRepository.run(["ls-files", "-z", "--cached"], in: root)
		guard result.exitCode == 0 else { return nil }
		let paths = result.stdout
			.split(separator: "\0", omittingEmptySubsequences: true)
			.map(String.init)
		// An empty answer from a real repository is a real answer — a work tree
		// with nothing committed yet — and is not the same as "no repository",
		// which is the non-zero exit above.
		return paths
	}

	// MARK: - Walking

	/// Files worth listing, skipping excluded directories and things too big.
	///
	/// This is `ProjectSearch`'s walk, moved rather than copied. Pruning at the
	/// directory level is what keeps it affordable: skipping `node_modules`
	/// wholesale is the difference between a walk of 25,564 files and one of
	/// 79,056.
	public static func walk(
		in root: URL, maximumFileSize: Int = defaultMaximumFileSize
	) -> [URL] {
		let excluded = Set(Settings.shared.excludedDirectories)
		var results: [URL] = []

		let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]
		guard let enumerator = FileManager.default.enumerator(
			at: root,
			includingPropertiesForKeys: keys,
			options: [.skipsHiddenFiles, .skipsPackageDescendants]
		) else { return [] }

		for case let url as URL in enumerator {
			let name = url.lastPathComponent
			guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }

			if values.isDirectory == true {
				if excluded.contains(name) || name == ".git" {
					enumerator.skipDescendants()
				}
				continue
			}

			if let size = values.fileSize, size > maximumFileSize { continue }
			if values.isSymbolicLink == true { continue }
			results.append(url)
		}
		return results
	}

	/// A path relative to the project root, or nil when it is not under it.
	///
	/// Canonical on both sides. The enumerator answers with the real path —
	/// `/private/tmp/…` where the root holds `/tmp/…` — and without this every
	/// file in a project under `/tmp` failed to be under its own root. Same
	/// asymmetry as 0430.
	///
	/// **`EvenIfMissing` for the file, and it is not a nicety.** The busiest
	/// caller is a filesystem event, and half of those are about a file that has
	/// just been *deleted*: `realpath` fails on a path that is not there, so the
	/// plain form answers with something that is not under the root, and the
	/// index quietly kept every file anybody removed. The root itself is really
	/// there, so it keeps the strict form.
	public static func relativePath(of url: URL, under root: URL) -> String? {
		let base = FilePath.canonical(root)
		let path = FilePath.canonicalEvenIfMissing(url)
		guard path.hasPrefix(base + "/") else { return nil }
		return String(path.dropFirst(base.count + 1))
	}
}
