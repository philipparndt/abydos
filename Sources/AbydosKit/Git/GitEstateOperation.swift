import Foundation

/// What one repository did when an operation swept the estate.
///
/// An operation over two hundred repositories is not atomic and this program
/// will not pretend otherwise: nothing here makes two hundred commits one
/// transaction, and the rollback that would pretend so is `git reset --hard` in
/// repositories somebody may already have fetched. So the design's job is to
/// make the partiality legible instead of hiding it — a failure at the hundred
/// and fortieth of two hundred leaves a hundred and thirty-nine correct
/// commits, and destroying those to preserve a symmetry nobody asked for is
/// worse than saying which they are.
public struct GitEstateOutcome: Sendable, Equatable, Identifiable {
	public enum Result: Sendable, Equatable {
		/// It happened. `detail` names what came of it — a commit, usually.
		case done(String?)
		/// Git refused, and this is what it said.
		case failed(String)
		/// There was nothing to do here, and this is why.
		case skipped(String)
	}

	/// The submodule, or nil for the superproject.
	public let submodule: GitSubmodule?
	/// Where the command ran.
	public let root: URL
	public let result: Result

	public var id: String { submodule?.path ?? "" }
	/// What to call this repository in a report.
	public var name: String { submodule?.path ?? "." }

	public var didHappen: Bool { if case .done = result { return true } else { return false } }
	public var didFail: Bool { if case .failed = result { return true } else { return false } }

	public init(submodule: GitSubmodule?, root: URL, result: Result) {
		self.submodule = submodule
		self.root = root
		self.result = result
	}
}

/// Verbs that act on more than one repository at once.
///
/// Every one of them groups its paths by the repository that owns each and runs
/// one command per repository. That is not a tidiness: `git add`, `restore`,
/// `reset`, `clean` and `ls-files` all resolve a pathspec against the repository
/// they run in, so one command over a selection spanning three submodules would
/// compose the paths wrongly in all three — the `warning: could not open
/// directory 'sub/sub/'` failure `Project.gitRoot` already records, at estate
/// scale. Grouping also bounds the cost: a hundred paths across six repositories
/// is six processes rather than a hundred.
public enum GitEstateOperation {
	/// Stages paths in whichever repositories own them.
	@discardableResult
	public static func stage(
		paths: [String], in estate: GitEstate
	) async -> [GitEstateOutcome] {
		await perGroup(paths, in: estate) { group in
			await GitWorkingCopy.stage(paths: group.paths, in: group.root)
		}
	}

	@discardableResult
	public static func unstage(
		paths: [String], in estate: GitEstate
	) async -> [GitEstateOutcome] {
		await perGroup(paths, in: estate) { group in
			await GitWorkingCopy.unstage(paths: group.paths, in: group.root)
		}
	}

	@discardableResult
	public static func discard(
		paths: [String], in estate: GitEstate
	) async -> [GitEstateOutcome] {
		await perGroup(paths, in: estate) { group in
			await GitWorkingCopy.discard(paths: group.paths, in: group.root)
		}
	}

	/// Runs one command per owning repository, in a fixed order.
	///
	/// Serial rather than fanned out, and deliberately: these write, and two
	/// hundred concurrent writers is a different risk from two hundred
	/// concurrent readers. Reading is where the parallelism is worth having and
	/// where it was measured; a stage of six repositories is six quick commands
	/// and its cost is not what anybody is waiting on.
	private static func perGroup(
		_ paths: [String],
		in estate: GitEstate,
		_ act: (GitEstate.PathGroup) async -> GitRepository.ProcessResult
	) async -> [GitEstateOutcome] {
		var outcomes: [GitEstateOutcome] = []
		for group in estate.grouped(paths) {
			let result = await act(group)
			outcomes.append(GitEstateOutcome(
				submodule: group.submodule,
				root: group.root,
				result: result.exitCode == 0
					? .done(nil)
					: .failed(complaint(result))
			))
		}
		return outcomes
	}

	// MARK: - Committing

	/// Commits every submodule with something staged, then the superproject.
	///
	/// The order is the only one that works: a submodule's commit is what moves
	/// its gitlink, so the superproject cannot record where the submodules got
	/// to until they have got there.
	///
	/// **`stagingGitlinks` is the open question, made explicit rather than
	/// decided quietly.** Committing submodules without bumping the gitlinks
	/// leaves the superproject dirty and the estate half-recorded; bumping them
	/// automatically commits something nobody reviewed. Both readings are
	/// defensible, so the caller says which it meant.
	///
	/// Every repository in the estate gets an outcome, including the ones that
	/// had nothing to do — a partial run that names only what it touched cannot
	/// be told from a complete one.
	@discardableResult
	public static func commit(
		subject: String,
		body: String,
		in estate: GitEstate,
		status: GitEstateStatus,
		stagingGitlinks: Bool = true
	) async -> [GitEstateOutcome] {
		var outcomes: [GitEstateOutcome] = []
		var committed: [String] = []

		for submodule in estate.submodules {
			let root = estate.root.appendingPathComponent(submodule.path)

			guard submodule.isCheckedOut else {
				outcomes.append(GitEstateOutcome(
					submodule: submodule, root: root,
					result: .skipped("not checked out")
				))
				continue
			}
			guard let own = status.status(of: submodule.path) else {
				outcomes.append(GitEstateOutcome(
					submodule: submodule, root: root,
					result: .skipped("not read")
				))
				continue
			}
			guard !own.staged.isEmpty else {
				outcomes.append(GitEstateOutcome(
					submodule: submodule, root: root,
					result: .skipped(own.isEmpty ? "nothing changed" : "nothing staged")
				))
				continue
			}

			let result = await GitWorkingCopy.commit(
				subject: subject, body: body, amend: false, in: root
			)
			if result.exitCode == 0 {
				committed.append(submodule.path)
				outcomes.append(GitEstateOutcome(
					submodule: submodule, root: root,
					result: .done(await headCommit(in: root))
				))
			} else {
				// And the run carries on. The repositories after this one are
				// not made wrong by it, and stopping would leave them
				// unexplained as well as unchanged.
				outcomes.append(GitEstateOutcome(
					submodule: submodule, root: root, result: .failed(complaint(result))
				))
			}
		}

		outcomes.append(await commitSuperproject(
			subject: subject, body: body, in: estate, status: status,
			bumping: stagingGitlinks ? committed : []
		))
		return outcomes
	}

	private static func commitSuperproject(
		subject: String,
		body: String,
		in estate: GitEstate,
		status: GitEstateStatus,
		bumping gitlinks: [String]
	) async -> GitEstateOutcome {
		if !gitlinks.isEmpty {
			_ = await GitWorkingCopy.stage(paths: gitlinks, in: estate.root)
		}

		// Asked again rather than taken from `status`: the submodule commits
		// above have moved gitlinks since it was read, and committing on a stale
		// answer is how a run reports success over an empty commit.
		let fresh = await GitWorkingCopy.status(in: estate.root)
		guard !fresh.staged.isEmpty else {
			return GitEstateOutcome(
				submodule: nil, root: estate.root, result: .skipped("nothing staged")
			)
		}

		let result = await GitWorkingCopy.commit(
			subject: subject, body: body, amend: false, in: estate.root
		)
		return GitEstateOutcome(
			submodule: nil, root: estate.root,
			result: result.exitCode == 0
				? .done(await headCommit(in: estate.root))
				: .failed(complaint(result))
		)
	}

	static func headCommit(in root: URL) async -> String? {
		let result = await GitRepository.run(["rev-parse", "--short", "HEAD"], in: root)
		guard result.exitCode == 0 else { return nil }
		let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		return text.isEmpty ? nil : text
	}

	/// What git said, preferring stderr — which is where it says it.
	static func complaint(_ result: GitRepository.ProcessResult) -> String {
		let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
		if !stderr.isEmpty { return stderr }
		let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		if !stdout.isEmpty { return stdout }
		return "git exited \(result.exitCode)"
	}
}
