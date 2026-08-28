import Foundation
import Testing
@testable import AbydosKit

/// What it costs to read a superproject, measured rather than asserted from
/// memory.
///
/// The whole submodule design rests on one comparison: git's own recursion
/// walks every submodule serially inside one process, and asking each submodule
/// separately parallelises. Measured while the design was being written, on a
/// synthetic superproject of 200 submodules of eight files each — ten cores,
/// load averages 4.9 to 21.2, `git version 2.54.0 (Apple Git-157)`:
///
///     what GitWorkingCopy.status used to run              1.61 s
///     the same call with --ignore-submodules=all          0.09 s
///     git submodule status                                5.37 s
///     one submodule asked on its own                      0.01 s
///     all 200 asked at once, twelve concurrent            0.45 s
///     the inventory from git ls-files --stage             0.01 s
///
/// This suite is the part of that a machine can re-run. It is forty submodules
/// rather than two hundred, because building two hundred repositories is a
/// minute this suite should not spend; the shape of the claim does not depend
/// on the number, and neither does the ratio.
///
/// **The bound is only asserted by `make timing`.** Under `make test`'s own
/// parallelism the fan-out is the half of this comparison that suffers — it
/// wants cores the suite is already using — so a ratio measured there is a
/// measurement of the harness. The numbers are printed either way, with the
/// load beside them, which is the whole point of `MachineLoad.said`.
struct EstatePerformanceTests {
	private static let submodules = 40

	@Test func askingEachSubmoduleBeatsLettingGitRecurse() async throws {
		let estate = try SyntheticEstate.make(
			count: Self.submodules, named: "timing"
		)
		defer { estate.remove() }

		// Something to find, so neither side is measuring an empty answer.
		for name in ["svc-1", "svc-20", "svc-39"] { try estate.dirty(name) }

		let read = await GitEstate.read(from: estate.root)
		#expect(read.count == Self.submodules)

		// What this program used to run: one call, recursing serially.
		let recursive = await time {
			_ = await GitRepository.run(
				["status", "--porcelain=v1", "-unormal", "--no-renames", "-z"],
				in: estate.root
			)
		}

		// What it runs now: the superproject with the flag, and every submodule
		// fanned out under the ceiling.
		let split = await time { _ = await GitEstateReader.status(of: read) }

		// And the obvious approach, for the comparison that killed it.
		let submoduleStatus = await time {
			_ = await GitRepository.run(["submodule", "status"], in: estate.root)
		}

		print("""
			estate: \(Self.submodules) submodules — \
			recursive \(seconds(recursive)), \
			split \(seconds(split)), \
			git submodule status \(seconds(submoduleStatus)). \
			\(MachineLoad.said)
			""")

		guard Stopwatch.maySay("estate", "reading a superproject") else { return }
		#expect(split < recursive, """
			the fan-out is meant to beat the recursion: \(seconds(split)) against \
			\(seconds(recursive)). \(MachineLoad.said)
			""")
		#expect(recursive < submoduleStatus, """
			`git submodule status` is meant to be the worst of the three: \
			\(seconds(submoduleStatus)). \(MachineLoad.said)
			""")
	}

	/// The inventory is what the overview is drawn from before any status has
	/// been asked for, so it has to be quick enough to be free.
	@Test func theInventoryIsCheapEnoughToDrawFrom() async throws {
		let estate = try SyntheticEstate.make(
			count: Self.submodules, named: "inventorytiming"
		)
		defer { estate.remove() }

		let inventory = await time { _ = await GitEstate.read(from: estate.root) }
		let sweep = await time {
			_ = await GitEstateReader.status(of: await GitEstate.read(from: estate.root))
		}

		print("""
			estate: inventory \(seconds(inventory)) against a full sweep \
			\(seconds(sweep)) over \(Self.submodules) submodules. \(MachineLoad.said)
			""")

		guard Stopwatch.maySay("estate", "reading the inventory") else { return }
		#expect(inventory < sweep, """
			the inventory is two calls and the sweep is one per repository: \
			\(seconds(inventory)) against \(seconds(sweep)). \(MachineLoad.said)
			""")
	}

	/// Ownership is asked per row of a table three hundred rows long, so it must
	/// not walk the estate. This is that claim as a measurement: three hundred
	/// submodules and three answer in the same order of time.
	@Test func ownershipCostsTheDepthOfThePathAndNotTheSizeOfTheEstate() async {
		func estate(_ count: Int) -> GitEstate {
			GitEstate(
				root: URL(fileURLWithPath: "/tmp/super"),
				submodules: (1...count).map {
					GitSubmodule(path: "svc-\($0)", recordedCommit: "0000000")
				}
			)
		}

		let small = estate(3), large = estate(300)
		let question = "svc-2/src/main/java/com/acme/Thing.java"
		let rounds = 20_000

		let smallCost = await time {
			for _ in 0..<rounds { _ = small.submodule(containing: question) }
		}
		let largeCost = await time {
			for _ in 0..<rounds { _ = large.submodule(containing: question) }
		}

		print("""
			estate: \(rounds) ownership questions — 3 submodules \(seconds(smallCost)), \
			300 submodules \(seconds(largeCost)). \(MachineLoad.said)
			""")

		guard Stopwatch.maySay("estate", "ownership at scale") else { return }
		// A hundredfold more submodules for no more than twice the time. A walk
		// over the inventory would be a hundred times worse, which is the shape
		// this is defending against rather than any particular constant.
		#expect(largeCost < smallCost * 2 + 0.05, """
			ownership looks like it walks the estate: \(seconds(largeCost)) against \
			\(seconds(smallCost)). \(MachineLoad.said)
			""")
	}

	// MARK: - Measuring

	private func time(_ work: () async -> Void) async -> TimeInterval {
		let started = Date()
		await work()
		return Date().timeIntervalSince(started)
	}

	private func seconds(_ interval: TimeInterval) -> String {
		String(format: "%.3f s", interval)
	}
}
