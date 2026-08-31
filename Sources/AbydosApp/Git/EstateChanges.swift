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
	}

	/// Which repositories a filesystem event made stale.
	///
	/// The event that arrives dozens a minute is a file being written, and this
	/// is what keeps it from costing the estate. `GitEstateRefresh` does the
	/// attribution; a batch FSEvents could not enumerate — `namesEveryPath` —
	/// is treated as "everything", because it is.
	func read(after change: FileSystemChange) -> Read {
		guard !change.namesEveryPath else { return .everything }
		// Attribution works the same with no submodules at all — the estate
		// is then one repository, and the answer is the superproject or
		// nothing. The old guard sent every plain repository to `.everything`,
		// so the cheap path this type exists for never applied to the common
		// case, and every saved file re-read the inventory too.
		let work = GitEstateRefresh.work(forChangedPaths: change.paths, in: estate)
		if work.inventory { return .everything }
		if work.isEmpty { return .nothing }
		return .only(work.submodulePaths)
	}

	/// Reads what `read` asked for, and gives back the estate's changes as one
	/// pair of lists with every path relative to the superproject.
	func refresh(_ read: Read) async -> GitWorkingCopyStatus {
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
		status = await GitEstateReader.status(of: estate)
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
