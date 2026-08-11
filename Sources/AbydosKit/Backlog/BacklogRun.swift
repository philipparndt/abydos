import Foundation

/// One item being worked on somewhere else on this machine.
///
/// Not in the backlog folder, and deliberately: a worktree at
/// `/Users/somebody/dev/abydos-backlog-0443` is one person's disk and means
/// nothing to anybody who pulls this branch. The item's *state* is committed —
/// it is in `in-progress/` and everybody can see that — and where the checkout
/// happens to be is not.
public struct BacklogRun: Codable, Sendable, Equatable, Identifiable {
	public let number: Int
	public let branch: String
	public let worktreePath: String
	/// Which assistant was started, by its identifier. A plain string because
	/// a run recorded by a newer version naming a tool this one does not know
	/// should still list, and still be removable.
	public let assistant: String
	public let startedAt: Date

	public var id: Int { number }
	public var worktree: URL { URL(fileURLWithPath: worktreePath, isDirectory: true) }

	/// Whether the checkout is still there. A run whose directory somebody
	/// deleted is over, whatever this file says.
	public var isPresent: Bool {
		FileManager.default.fileExists(atPath: worktreePath)
	}

	/// The item as it stands in the checkout the work is happening in.
	///
	/// The project's copy and the branch's copy are the same file in two
	/// checkouts, and they answer different questions. Where an item *is* —
	/// which state folder it sits in — is the project's answer, because a branch
	/// nobody has merged is not something anybody else can act on. How far along
	/// it is is the branch's answer, because that is where the ticking happens:
	/// an agent ticks a step in the commit that finishes it, in its own worktree,
	/// and the project's copy stays at whatever it said when the item was picked
	/// up until the branch lands — which is the moment nobody needs to watch it
	/// any more. Measured while 0454 was being worked: 0 of 6 in the project, 3
	/// of 6 on the branch.
	///
	/// Found **by number and not by path**: an agent that has run `done` has
	/// moved its copy to `completed/` on the branch while the project still has
	/// it in `in-progress/`, so the two copies are not at the same path and a
	/// path is the one thing that cannot be assumed here.
	///
	/// `nil` where the checkout is gone, or where the branch has no readable copy
	/// of the item — the caller then has the project's copy, which is all there
	/// is, and should say so rather than pass it off as the branch's.
	public var itemInWorktree: BacklogItem? {
		guard isPresent else { return nil }
		return Backlog(projectRoot: worktree).item(number: number)
	}

	public init(number: Int, branch: String, worktree: URL, assistant: String, startedAt: Date = Date()) {
		self.number = number
		self.branch = branch
		self.worktreePath = worktree.path
		self.assistant = assistant
		self.startedAt = startedAt
	}
}

/// The runs this machine has going, as a file beside the project.
public struct BacklogRuns: Sendable {
	public let projectRoot: URL

	public init(projectRoot: URL) {
		self.projectRoot = projectRoot
	}

	/// Outside `backlog/`, which is the whole reason it is not ignored by
	/// accident: `.abydos/.gitignore` ignores everything and then lets the
	/// backlog through, so anything that should stay on this machine belongs
	/// next to the backlog rather than inside it.
	public var file: URL {
		AbydosFolder.url(in: projectRoot).appendingPathComponent("backlog-runs.json")
	}

	public func all() -> [BacklogRun] {
		let decoder = JSONDecoder()
		// Matched to the encoder below. A date written one way and read
		// another is a file that round-trips in the tests and returns nothing
		// on the machine, because the failure is a decode of the whole array.
		decoder.dateDecodingStrategy = .iso8601
		guard let data = try? Data(contentsOf: file),
		      let runs = try? decoder.decode([BacklogRun].self, from: data)
		else { return [] }
		return runs.sorted { $0.number < $1.number }
	}

	public func run(for number: Int) -> BacklogRun? {
		all().first { $0.number == number }
	}

	public func record(_ run: BacklogRun) throws {
		var runs = all().filter { $0.number != run.number }
		runs.append(run)
		try write(runs)
	}

	public func forget(_ number: Int) throws {
		try write(all().filter { $0.number != number })
	}

	/// Drops the runs whose checkouts are gone.
	@discardableResult
	public func prune() throws -> [BacklogRun] {
		let all = self.all()
		let gone = all.filter { !$0.isPresent }
		guard !gone.isEmpty else { return [] }
		try write(all.filter(\.isPresent))
		return gone
	}

	private func write(_ runs: [BacklogRun]) throws {
		try FileManager.default.createDirectory(
			at: file.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		encoder.dateEncodingStrategy = .iso8601
		try encoder.encode(runs.sorted { $0.number < $1.number }).write(to: file, options: .atomic)
	}
}
