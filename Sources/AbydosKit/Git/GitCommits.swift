import Foundation

/// What can be done to one commit that is already made.
///
/// These are the verbs the log had no room for: its menu offered
/// `Copy Commit Hash` and `Copy Subject` and nothing else, because a verb in
/// this app lives on the menu of the pane that draws its object, and nothing
/// drew a commit as something you could act on.
///
/// **Each of them can stop half-done**, which is the whole reason this is not
/// four calls to `GitRepository.run` at the call sites. A revert or a
/// cherry-pick that hits a conflict exits non-zero having *already* written
/// conflict markers into the work tree and left `CHERRY_PICK_HEAD` behind:
/// reporting that as a failure would say "it did not happen" about something
/// that half happened, and leave somebody looking at a working copy they did
/// not ask for with no idea why.
public enum GitCommits {
	/// How an operation over a commit ended.
	public enum Outcome: Sendable, Equatable {
		/// It applied.
		case done
		/// It stopped in a conflict, naming the paths that are unmerged.
		///
		/// The work tree holds the half-applied result and the operation is
		/// still in progress as far as git is concerned — `--abort` is what
		/// undoes it, which is why the caller is told which state it is in
		/// rather than being told it failed.
		case conflicted([String])
		/// It did not happen, in git's own words.
		case failed(String)
	}

	/// What `reset` is being asked to move.
	public enum ResetMode: String, Sendable, CaseIterable {
		/// The branch moves; the index and the work tree keep everything.
		case soft
		/// The branch and the index move; the work tree keeps everything.
		case mixed
		/// All three move, and uncommitted work is gone.
		///
		/// The one that needs `GitBackup` in front of it.
		case hard
	}

	/// Makes a commit that undoes another, on top of what is there now.
	///
	/// `--no-edit`, because the message git writes — `Revert "<subject>"` — is
	/// the one that gets used, and an editor opening behind a window nobody
	/// asked to leave is how a GUI git operation appears to hang.
	public static func revert(
		_ commit: String,
		in root: URL
	) async -> Outcome {
		await outcome(of: ["revert", "--no-edit", commit], in: root)
	}

	/// Applies the change one commit made, here.
	public static func cherryPick(
		_ commit: String,
		in root: URL
	) async -> Outcome {
		await outcome(of: ["cherry-pick", commit], in: root)
	}

	/// Moves the current branch to another commit.
	///
	/// - Parameter mode: what else moves with it. `.hard` throws away
	///   uncommitted work and is the caller's job to insure first.
	public static func reset(
		to commit: String,
		mode: ResetMode,
		in root: URL
	) async -> Outcome {
		await outcome(of: ["reset", "--\(mode.rawValue)", commit], in: root)
	}

	/// Abandons a revert or cherry-pick that stopped in a conflict.
	///
	/// The other half of reporting `.conflicted` honestly: having been told the
	/// work tree is half-changed, there has to be a way to say "put it back".
	public static func abort(in root: URL) async -> Outcome {
		// Whichever one is in progress; git knows which and the sequencer is
		// shared, so asking for the wrong one is an error rather than a mess.
		if await isInProgress("CHERRY_PICK_HEAD", in: root) {
			return await outcome(of: ["cherry-pick", "--abort"], in: root)
		}
		if await isInProgress("REVERT_HEAD", in: root) {
			return await outcome(of: ["revert", "--abort"], in: root)
		}
		return .done
	}

	/// How many commits are on `branch` and not on `other`.
	///
	/// What a dialog leads with. "3 commits leave main" is read where "this
	/// cannot be undone" is not.
	public static func count(
		of branch: String,
		notIn other: String,
		in root: URL
	) async -> Int {
		let result = await GitRepository.run(
			["rev-list", "--count", "\(other)..\(branch)"], in: root
		)
		guard result.exitCode == 0 else { return 0 }
		return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
	}

	/// Paths git reports as unmerged.
	public static func conflictedPaths(in root: URL) async -> [String] {
		let result = await GitRepository.run(
			["diff", "--name-only", "--diff-filter=U"], in: root
		)
		guard result.exitCode == 0 else { return [] }
		return result.stdout
			.split(separator: "\n")
			.map(String.init)
			.filter { !$0.isEmpty }
	}

	// MARK: - Reading what happened

	private static func outcome(
		of arguments: [String],
		in root: URL
	) async -> Outcome {
		let result = await GitRepository.run(arguments, in: root)
		guard result.exitCode != 0 else { return .done }

		// A conflict is not a failure, and telling them apart is what this
		// whole type is for. Asked of the work tree rather than matched against
		// git's wording, which is translated and has changed between versions.
		let unmerged = await conflictedPaths(in: root)
		if !unmerged.isEmpty { return .conflicted(unmerged) }

		let said = result.stderr.isEmpty ? result.stdout : result.stderr
		return .failed(said.trimmingCharacters(in: .whitespacesAndNewlines))
	}

	private static func isInProgress(_ file: String, in root: URL) async -> Bool {
		let result = await GitRepository.run(["rev-parse", "--git-dir"], in: root)
		guard result.exitCode == 0 else { return false }
		let directory = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !directory.isEmpty else { return false }
		// `--git-dir` answers relative to the work tree for an ordinary
		// checkout and absolutely for a worktree, so both are handled.
		let base = directory.hasPrefix("/")
			? URL(fileURLWithPath: directory)
			: root.appendingPathComponent(directory)
		return FileManager.default.fileExists(atPath: base.appendingPathComponent(file).path)
	}
}
