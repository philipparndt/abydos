import Testing
import Foundation
@testable import AbydosKit

/// Which files a typed word finds, and in what order.
///
/// The order is the whole feature. A plain "contains" answers `Git` with every
/// file in a directory called `Git`, and the file actually called `Git.swift` is
/// somewhere in that list rather than at the top — which is the behaviour that
/// makes somebody give up and go back to the tree.
struct FileMatchingTests {
	// MARK: - The rule the feature stands on

	/// The scenario written into the spec.
	@Test func aMatchInTheFilesOwnNameBeatsOneInADirectoryAboveIt() {
		let paths = [
			"Sources/Git/Client.swift",
			"Sources/Git/Remote.swift",
			"Sources/Model/Git.swift",
		]

		let found = FileMatching.matches(for: "Git", in: paths)

		#expect(found.first == "Sources/Model/Git.swift", "\(found)")
	}

	@Test func anExactNameBeatsALongerOneContainingIt() {
		let paths = ["Sources/GitRepository.swift", "Sources/Repo.swift"]
		#expect(FileMatching.matches(for: "Repo", in: paths).first == "Sources/Repo.swift")
	}

	/// A name that begins with the query beats one with it in the middle.
	@Test func aNameStartingWithTheQueryComesFirst() {
		let paths = ["a/MyGitThing.swift", "a/GitThing.swift"]
		#expect(FileMatching.matches(for: "Git", in: paths).first == "a/GitThing.swift")
	}

	// MARK: - Matching at all

	@Test func theWholePathIsMatchedNotOnlyTheName() {
		let paths = ["Sources/AbydosKit/Git/GitRepository.swift", "README.md"]
		#expect(FileMatching.matches(for: "Kit/Git", in: paths) == [paths[0]])
	}

	@Test func matchingIgnoresCase() {
		let paths = ["Sources/GitRepository.swift"]
		#expect(FileMatching.matches(for: "gitrepo", in: paths) == paths)
		#expect(FileMatching.matches(for: "GITREPO", in: paths) == paths)
	}

	@Test func nothingMatchesAnEmptyQuery() {
		#expect(FileMatching.matches(for: "", in: ["a.swift"]).isEmpty)
		#expect(FileMatching.matches(for: "   ", in: ["a.swift"]).isEmpty)
		#expect(FileMatching.rank(of: "a.swift", for: "") == nil)
	}

	@Test func aQueryThatMatchesNothingFindsNothing() {
		#expect(FileMatching.matches(for: "zzz", in: ["a.swift", "b/c.swift"]).isEmpty)
	}

	// MARK: - The cap

	/// The palette caps projects for the reason its own comment gives — without
	/// a limit the sections underneath are pushed off — and 25,564 candidates
	/// would push branches and actions out of reach.
	@Test func onlyAsManyAsAskedForAreReturned() {
		let paths = (0..<200).map { "dir/file\($0).swift" }
		#expect(FileMatching.matches(for: "file", in: paths, limit: 10).count == 10)
		#expect(FileMatching.matches(for: "file", in: paths, limit: 0).isEmpty)
	}

	/// The same query twice gives the same list. A list that reshuffled between
	/// two keystrokes would be one nobody could click.
	@Test func theSameQueryGivesTheSameOrderTwice() {
		let paths = (0..<50).map { "dir\($0 % 5)/thing\($0).swift" }
		let once = FileMatching.matches(for: "thing", in: paths, limit: 20)
		let twice = FileMatching.matches(for: "thing", in: paths, limit: 20)
		#expect(once == twice)
	}

	/// Numbers read as numbers where nothing else separates two paths.
	@Test func numbersInNamesBreakTiesAsNumbers() {
		let paths = ["a/thing10.swift", "a/thing9.swift", "a/thing1.swift"]
		let found = FileMatching.matches(for: "a/thing", in: paths)
		#expect(found == ["a/thing1.swift", "a/thing9.swift", "a/thing10.swift"], "\(found)")
	}

	// MARK: - Cost

	/// Ranked once and sorted, not ranked inside a comparator. At tens of
	/// thousands of paths that is one pass against n log n of them, and this
	/// runs while somebody is typing.
	///
	/// **Against prepared candidates, because that is what the index holds.**
	/// The first version of this measured `[String]`, which lower-cased every
	/// path on every call, and it read 25 ms here while the app read 110–157 ms
	/// per keystroke on a real work tree — synthetic paths a third the length
	/// were hiding most of it. Preparing once is the fix and this is the test
	/// that would notice it being undone.
	@Test func matchingALargeProjectIsCheapEnoughToDoWhileTyping() {
		let paths = (0..<25_000).map {
			"module\($0 % 300)/src/main/java/com/example/platform/part\($0 % 20)/File\($0).java"
		}
		let prepared = paths.map(FileMatching.Candidate.init)

		let elapsed = PerformanceTests.cpuTime("match 25,000 prepared paths") {
			_ = FileMatching.matches(for: "File1234", in: prepared)
		}

		guard Stopwatch.maySay("PERF", "palette file matching") else { return }
		#expect(elapsed < 0.05, "matching took \(elapsed)s — \(MachineLoad.said)")
	}

	/// What preparing buys, printed side by side so the next person does not
	/// have to take the paragraph above on trust.
	@Test func preparingOnceIsWhyTypingIsAffordable() {
		let paths = (0..<25_000).map {
			"module\($0 % 300)/src/main/java/com/example/platform/part\($0 % 20)/File\($0).java"
		}
		let prepared = paths.map(FileMatching.Candidate.init)

		let raw = PerformanceTests.cpuTime("match 25,000 raw paths") {
			_ = FileMatching.matches(for: "File1234", in: paths)
		}
		let ready = PerformanceTests.cpuTime("match 25,000 prepared paths") {
			_ = FileMatching.matches(for: "File1234", in: prepared)
		}
		print(String(format: "PERF preparing saves %.1fx  (%@)", raw / max(ready, 0.000_001), MachineLoad.said))

		// Not a bound on either number — only that the same answer comes back.
		#expect(
			FileMatching.matches(for: "File1234", in: paths)
				== FileMatching.matches(for: "File1234", in: prepared)
		)
	}
}
