import AbydosKit
import Foundation

/// What the changes pane knows about a repository that holds submodules.
///
/// Its own type rather than three properties on `ChangesPane`, because it is
/// three properties that are only ever right together: the inventory, the
/// status of each repository in it, and the rule that decides which of them a
/// filesystem event made stale. A pane that held them loose would be one edit
/// away from re-reading two hundred repositories to draw one changed file.
///
/// **Empty is the ordinary case and not a special one.** A repository with no
/// submodules has an empty inventory, `flattened` gives back its own status
/// unchanged, and `GitChangeTree.build` marks no rows — so the pane above is
/// the pane it always was, down the same code path.
@MainActor
final class EstateChanges {
	private let root: URL

	/// The submodules the repository holds. Read whenever the whole estate is,
	/// which is the only occasion on which one can have appeared.
	private(set) var estate: GitEstate

	/// What each repository has changed. Kept between reads so a partial one
	/// can leave the rest alone.
	private(set) var status = GitEstateStatus()

	init(root: URL) {
		self.root = root
		self.estate = GitEstate(root: root)
	}

	var holdsSubmodules: Bool { estate.holdsSubmodules }

	/// How much of the estate to read.
	enum Read: Equatable {
		/// The inventory and every repository in it. What a commit, a checkout,
		/// a pull or a branch switch calls for: each of those can move every
		/// gitlink at once, and none of them happens per keystroke.
		case everything
		/// Only these submodules, and the superproject. 0.01 s a repository,
		/// against 0.45 s to sweep two hundred.
		case only([String])
		/// The event was about somewhere else entirely.
		case nothing

		/// Both reads as one, for a read asked for while another runs.
		func merged(with other: Read) -> Read {
			switch (self, other) {
			case (.everything, _), (_, .everything): return .everything
			case (.nothing, let read), (let read, .nothing): return read
			case let (.only(first), .only(second)):
				return .only(Array(Set(first).union(second)).sorted())
			}
		}
	}

	/// Which repositories a filesystem event made stale.
	///
	/// The event that arrives dozens a minute is a file being written, and this
	/// is what keeps it from costing the estate. `GitEstateRefresh` does the
	/// attribution, of the paths a batch named and of the directories it could
	/// only say to scan again.
	///
	/// **This used to be the wrong way round.** It read "everything" for every
	/// batch whose paths were all named — every saved file, in a superproject
	/// of 190 submodules a sweep of all of them — and attributed the batches
	/// FSEvents could not enumerate, whose path list is empty, to nothing at
	/// all. Attribution works the same with no submodules: the estate is then
	/// one repository, and the answer is the superproject or nothing.
	func read(after change: FileSystemChange) -> Read {
		Self.read(GitEstateRefresh.work(for: change, in: estate))
	}

	/// Which repositories a change under the git directory made stale.
	///
	/// **Nothing attributed is read as everything here**, unlike a work-tree
	/// event. Every directory the repository watcher reports is inside the git
	/// directory by construction, so one that attributes nowhere means the two
	/// spell that directory differently — the estate assumes `root/.git` until
	/// its first read, and the watcher has `rev-parse --absolute-git-dir`, which
	/// resolves symlinks. A read too many is slow; one too few is a pane that
	/// stays wrong after a commit.
	func read(afterGitDirectoriesChanged directories: [URL]) -> Read {
		let work = GitEstateRefresh.work(forChangedDirectories: directories, in: estate)
		return work.isEmpty ? .everything : Self.read(work)
	}

	static func read(_ work: GitEstateRefresh.Work) -> Read {
		if work.inventory { return .everything }
		if work.isEmpty { return .nothing }
		return .only(work.submodulePaths)
	}

	/// Reads what `read` asked for, and gives back the estate's changes as one
	/// pair of lists with every path relative to the superproject.
	/// - Parameter onProgress: told how many repositories have answered out of
	///   how many, while a whole-estate read is under way. Only the whole-estate
	///   read reports: a partial one is a handful of repositories at 0.01 s
	///   each, and a count that appears and vanishes says less than nothing.
	func refresh(
		_ read: Read,
		onProgress: (@Sendable (Int, Int) -> Void)? = nil
	) async -> GitWorkingCopyStatus {
		guard read != .nothing else { return status.flattened(in: estate) }

		if case .only(let paths) = read {
			var merged = await GitEstateReader.status(of: estate, only: paths)
			// What was not asked about keeps the answer it had. A partial read
			// that dropped the rest would empty two hundred rows because one
			// file was saved.
			for (path, was) in status.submodules where merged.submodules[path] == nil {
				merged.submodules[path] = was
			}
			status = merged
			return merged.flattened(in: estate)
		}

		// The inventory is two git calls and 0.01 s over two hundred submodules,
		// so it is re-read whenever the whole estate is rather than being
		// tracked for staleness.
		estate = await GitEstate.read(from: root)
		status = await GitEstateReader.status(of: estate, onProgress: onProgress)
		return status.flattened(in: estate)
	}

	/// How far each moved gitlink has moved, asked only of the submodules the
	/// superproject has already said moved.
	///
	/// Two hundred clean repositories cost nothing here: with
	/// `--ignore-submodules=dirty` the superproject's own status has already
	/// named the ones that moved, so the answer to "which shall I ask" is in
	/// hand before anything is run.
	func movements() async -> [String: GitGitlinkMovement] {
		let moved = status.movedGitlinks(in: estate)
		guard !moved.isEmpty else { return [:] }
		return await GitGitlink.movements(of: moved, in: root)
	}
}
