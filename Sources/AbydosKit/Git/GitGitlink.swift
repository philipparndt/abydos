import Foundation

/// How far a submodule has moved from where the superproject records it.
///
/// **A gitlink has no lines.** Every other changed row in this program carries a
/// `+n −m`, and for a submodule that number is `+1 −1` whatever happened
/// underneath — the whole of its content is one object name. `+1 −1` for a
/// service that advanced by forty commits is a true number that says nothing.
/// So the count for a gitlink is commits.
public struct GitGitlinkMovement: Sendable, Equatable {
	public enum Relation: Sendable, Equatable {
		/// Where the superproject records it is where it is.
		case level
		/// The submodule is this many commits past what is recorded.
		case ahead(Int)
		/// The submodule is this many commits behind what is recorded, which is
		/// what a checkout of an older superproject commit leaves.
		case behind(Int)
		/// Both sides moved: they share an ancestor and nothing since.
		case diverged(ahead: Int, behind: Int)
		/// The recorded commit is not in this submodule's object store.
		///
		/// What an estate looks like before somebody fetches, and git refuses
		/// the question rather than answering nought: `fatal: Invalid symmetric
		/// difference expression`. Saying so is the point — a row reading
		/// `level` about a commit nobody has is the sentence this exists to
		/// avoid.
		case notHere
	}

	public let submodule: GitSubmodule
	/// Where the superproject's index says it should be.
	public let recorded: String
	/// Where it is, or nil when HEAD could not be read.
	public let current: String?
	public let relation: Relation
	/// The subject of the commit it now points at, when there is one to name.
	public let subject: String?

	public var hasMoved: Bool { relation != .level }

	public init(
		submodule: GitSubmodule,
		recorded: String,
		current: String?,
		relation: Relation,
		subject: String?
	) {
		self.submodule = submodule
		self.recorded = recorded
		self.current = current
		self.relation = relation
		self.subject = subject
	}
}

/// Reading how far gitlinks have moved.
public enum GitGitlink {
	/// The one command this asks, per changed repository.
	///
	/// `--left-right` marks each commit with the side it is on, so one call
	/// answers both directions, divergence, and the subject of the commit the
	/// submodule now points at. Asking `rev-list --count` instead would answer
	/// the counts and leave the subject to a second process, and the subject is
	/// the sentence that identifies where a service has actually got to.
	///
	/// `%x1f` — the unit separator — between the fields, because a commit
	/// subject may contain anything else, tabs included.
	static func arguments(recorded: String) -> [String] {
		["log", "--left-right", "--pretty=format:%m%x1f%H%x1f%s", "\(recorded)...HEAD"]
	}

	/// How far one submodule has moved.
	///
	/// Asked only of submodules the superproject has already said moved: with
	/// `--ignore-submodules=dirty` that answer is in hand before this runs, so
	/// two hundred clean repositories cost nothing here. See
	/// `movements(of:in:)`.
	public static func movement(
		of submodule: GitSubmodule, in superprojectRoot: URL
	) async -> GitGitlinkMovement {
		let root = superprojectRoot.appendingPathComponent(submodule.path)
		let result = await GitRepository.run(arguments(recorded: submodule.recordedCommit), in: root)

		guard result.exitCode == 0 else {
			return GitGitlinkMovement(
				submodule: submodule, recorded: submodule.recordedCommit,
				current: nil, relation: .notHere, subject: nil
			)
		}
		return parse(result.stdout, for: submodule)
	}

	/// How far each of these submodules has moved, fanned out under the same
	/// ceiling as reading their statuses and for the same reason.
	public static func movements(
		of submodules: [GitSubmodule], in superprojectRoot: URL
	) async -> [String: GitGitlinkMovement] {
		let wanted = submodules.filter(\.isCheckedOut)
		guard !wanted.isEmpty else { return [:] }

		return await withTaskGroup(
			of: (String, GitGitlinkMovement).self
		) { group -> [String: GitGitlinkMovement] in
			var next = 0
			var collected: [String: GitGitlinkMovement] = [:]

			func addWork() -> Bool {
				guard next < wanted.count, !Task.isCancelled else { return false }
				let submodule = wanted[next]
				next += 1
				group.addTask {
					(submodule.path, await movement(of: submodule, in: superprojectRoot))
				}
				return true
			}

			for _ in 0..<min(GitEstateReader.concurrency, wanted.count) { _ = addWork() }
			while let (path, movement) = await group.next() {
				collected[path] = movement
				_ = addWork()
			}
			return collected
		}
	}

	/// Parses `git log --left-right`: one line a commit, marked with the side it
	/// is on. `>` is the submodule's own history, `<` is the superproject's
	/// record of it.
	static func parse(_ output: String, for submodule: GitSubmodule) -> GitGitlinkMovement {
		var ahead = 0, behind = 0
		var subject: String?
		var current: String?

		for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
			// `%m%x1f%H%x1f%s` puts a separator *after* the marker as well as
			// between the hash and the subject, so the marker is a field of its
			// own rather than the first character of the hash. Reading it as a
			// prefix gave an empty hash and a subject that happened to land in
			// the right place — which the fixtures agreed with and no real
			// repository did.
			let fields = line.split(
				separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false
			)
			guard fields.count >= 2 else { continue }

			if fields[0] == ">" {
				ahead += 1
				// The first `>` line is the tip: git logs newest first.
				if current == nil {
					current = String(fields[1])
					subject = fields.count > 2 ? String(fields[2]) : nil
				}
			} else if fields[0] == "<" {
				behind += 1
			}
		}

		let relation: GitGitlinkMovement.Relation
		switch (ahead, behind) {
		case (0, 0): relation = .level
		case (let a, 0): relation = .ahead(a)
		case (0, let b): relation = .behind(b)
		case (let a, let b): relation = .diverged(ahead: a, behind: b)
		}

		return GitGitlinkMovement(
			submodule: submodule,
			recorded: submodule.recordedCommit,
			current: current,
			relation: relation,
			subject: subject
		)
	}
}
