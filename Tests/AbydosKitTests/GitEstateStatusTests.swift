import Foundation
import Testing
@testable import AbydosKit

/// Reading an estate without the recursive status.
///
/// The claim under test is a split: what only the superproject knows comes from
/// the superproject's own call, and what only a submodule knows comes from that
/// submodule's. Neither half is a fixture — both are claims about what git
/// prints — so all of this runs against real repositories.
struct GitEstateStatusTests {
	/// The flag the whole design rests on, in the one place that spells the
	/// command. `all` would be silent about a moved gitlink, which is the one
	/// fact about a submodule that only the superproject holds.
	@Test func theStatusThisProgramRunsNeverRecursesIntoASubmodule() {
		#expect(GitWorkingCopy.statusArguments.contains("--ignore-submodules=dirty"))
		#expect(!GitWorkingCopy.statusArguments.contains("--ignore-submodules=all"))
	}

	/// Measured at 1.61 s against 0.09 s over 200 submodules, on a call that
	/// runs per filesystem event. This is that difference stated as behaviour:
	/// a dirty submodule work tree is invisible to the superproject, and a
	/// moved gitlink is not.
	@Test func theSuperprojectSeesAMovedGitlinkAndNotADirtyWorkTree() async throws {
		let estate = try SyntheticEstate.make(count: 3, named: "split")
		defer { estate.remove() }

		try estate.dirty("svc-1")
		try estate.dirty("svc-2")
		estate.advance("svc-3")

		let superproject = await GitWorkingCopy.status(in: estate.root)
		let named = Set((superproject.staged + superproject.unstaged).map(\.path))
		#expect(named == ["svc-3"], "saw \(named.sorted())")
	}

	/// The other half of the split: the detail the superproject gave up is
	/// asked for per submodule, and it is all there.
	@Test func eachSubmodulesOwnWorkTreeIsReadByItsOwnRepository() async throws {
		let estate = try SyntheticEstate.make(count: 3, named: "fanout")
		defer { estate.remove() }

		try estate.dirty("svc-1")
		try estate.dirty("svc-2")
		estate.advance("svc-3")

		let read = await GitEstate.read(from: estate.root)
		let status = await GitEstateReader.status(of: read)

		#expect(status.changedSubmodules(in: read).map(\.path) == ["svc-1", "svc-2"])
		#expect(status.movedGitlinks(in: read).map(\.path) == ["svc-3"],
			"a moved gitlink comes from the superproject, not from the submodule")
		#expect(status.status(of: "svc-1")?.unstaged.map(\.path) == ["src/Main.java"])
		#expect(status.status(of: "svc-3")?.isEmpty == true,
			"advancing a submodule leaves its own work tree clean")
	}

	/// A change carries the repository it is in, because the path alone stops
	/// identifying it: `src/Main.java` is a real path in every one of them.
	@Test func theSamePathInTwoSubmodulesIsTwoChanges() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "samepath")
		defer { estate.remove() }

		try estate.dirty("svc-1")
		try estate.dirty("svc-2")

		let read = await GitEstate.read(from: estate.root)
		let changes = await GitEstateReader.status(of: read).changes(in: read)

		#expect(changes.count == 2)
		#expect(Set(changes.map(\.path)) == ["svc-1/src/Main.java", "svc-2/src/Main.java"])
		#expect(Set(changes.map(\.id)).count == 2, "two rows, not one")
		#expect(changes.allSatisfy { $0.change.path == "src/Main.java" },
			"each change keeps the path its own repository knows it by")
	}

	/// Drawn before the statuses land, a row must not say clean. Empty and
	/// unread are both empty and only one of them is a fact about the code.
	@Test func aSubmoduleNotYetReadIsNotSaidToBeClean() async throws {
		let estate = try SyntheticEstate.make(count: 3, named: "unread")
		defer { estate.remove() }

		let read = await GitEstate.read(from: estate.root)
		let partial = await GitEstateReader.status(of: read, only: ["svc-1"])

		#expect(partial.hasBeenRead("svc-1"))
		#expect(!partial.hasBeenRead("svc-2"))
		#expect(partial.status(of: "svc-2") == nil)
		#expect(GitEstateStatus().hasBeenRead("svc-1") == false)
	}

	/// A filesystem event names one repository, and re-reading the estate for
	/// it would be the sweep this design exists to avoid.
	@Test func readingOneSubmoduleAsksAboutOneSubmodule() async throws {
		let estate = try SyntheticEstate.make(count: 3, named: "one")
		defer { estate.remove() }

		try estate.dirty("svc-1")
		try estate.dirty("svc-3")

		let read = await GitEstate.read(from: estate.root)
		let status = await GitEstateReader.status(of: read, only: ["svc-3"])

		#expect(status.submodules.keys.sorted() == ["svc-3"])
		#expect(status.status(of: "svc-3")?.isEmpty == false)
	}

	/// Nothing is run in a repository that is not on disk.
	@Test func anAbsentSubmoduleIsNotAsked() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "absentread")
		defer { estate.remove() }
		try FileManager.default.removeItem(at: estate.root.appendingPathComponent("svc-2"))

		let read = await GitEstate.read(from: estate.root)
		let status = await GitEstateReader.status(of: read)
		#expect(status.submodules.keys.sorted() == ["svc-1"])
	}

	@Test func aRepositoryWithNoSubmodulesReadsAsItAlwaysDid() async throws {
		let estate = try SyntheticEstate.make(count: 0, named: "plainread")
		defer { estate.remove() }

		try "changed\n".write(
			to: estate.root.appendingPathComponent("README.md"),
			atomically: true, encoding: .utf8
		)

		let read = await GitEstate.read(from: estate.root)
		let status = await GitEstateReader.status(of: read)
		#expect(status.superproject.unstaged.map(\.path) == ["README.md"])
		#expect(status.submodules.isEmpty)
	}

	/// **The sweep says how far through it is.** Warm, two hundred repositories
	/// answer in half a second and nobody asks. Cold, the same sweep took 89 s
	/// at 9 % processor — all of it waiting on the disk — and a spinner over
	/// that is indistinguishable from a pane that has hung. The count is the
	/// pane's answer, and it can only be honest if it comes from the sweep.
	@Test func theSweepSaysHowFarThroughItIs() async throws {
		let estate = try SyntheticEstate.make(count: 4, named: "progress")
		defer { estate.remove() }
		let read = await GitEstate.read(from: estate.root)

		// Collected off whatever thread each answer lands on, so the lock is
		// the test's own rather than an assumption about which one that is.
		let seen = Progress()
		let status = await GitEstateReader.status(of: read) { done, total in
			seen.record(done: done, total: total)
		}

		#expect(status.submodules.count == 4)
		// One report per repository, counting up, and the total never moves.
		#expect(seen.dones == [1, 2, 3, 4])
		#expect(seen.totals == [4, 4, 4, 4])
	}

	/// A partial read reports nothing: it is a handful of repositories at
	/// 0.01 s each, and a count that appears and vanishes says less than a
	/// spinner does.
	@Test func aPartialReadDoesNotCount() async throws {
		let estate = try SyntheticEstate.make(count: 3, named: "progresspartial")
		defer { estate.remove() }
		let read = await GitEstate.read(from: estate.root)

		let seen = Progress()
		_ = await GitEstateReader.status(of: read, only: ["svc-2"]) { done, total in
			seen.record(done: done, total: total)
		}
		// It does report, being the same call — what does not report is the
		// pane's partial refresh, which passes no callback. Here the claim is
		// that the total is the number actually asked for and not the estate's.
		#expect(seen.totals == [1])
		#expect(seen.dones == [1])
	}

	/// Somewhere to put the reports from whatever thread they arrive on.
	private final class Progress: @unchecked Sendable {
		private let lock = NSLock()
		private var pairs: [(Int, Int)] = []

		func record(done: Int, total: Int) {
			lock.lock()
			pairs.append((done, total))
			lock.unlock()
		}

		var dones: [Int] { lock.withLock { pairs.map(\.0) } }
		var totals: [Int] { lock.withLock { pairs.map(\.1) } }
	}

	/// Unbounded is three hundred processes against ten cores while a build is
	/// running. The ceiling is the point; the measured plateau is where it sits.
	@Test func theNumberOfGitProcessesAtOnceIsCapped() {
		#expect(GitEstateReader.concurrency >= 1)
		#expect(GitEstateReader.concurrency <= 12)
		#expect(GitEstateReader.concurrency <= ProcessInfo.processInfo.activeProcessorCount)
	}
}
