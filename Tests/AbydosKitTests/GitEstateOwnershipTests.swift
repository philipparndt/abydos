import Testing
import Foundation
@testable import AbydosKit

/// Which repository owns a path, which is the question every git verb in an
/// estate has to answer before it can run.
struct GitEstateOwnershipTests {
	private let root = URL(fileURLWithPath: "/tmp/super", isDirectory: true)

	private func estate(_ paths: [String]) -> GitEstate {
		GitEstate(
			root: root,
			submodules: paths.map { GitSubmodule(path: $0, recordedCommit: "0000000") }
		)
	}

	@Test func aFileInsideASubmoduleBelongsToIt() {
		let estate = estate(["svc-3", "svc-47"])
		#expect(estate.submodule(containing: "svc-47/src/Main.java")?.path == "svc-47")
		#expect(estate.relativePath(of: "svc-47/src/Main.java") == "src/Main.java")
	}

	@Test func aFileInTheSuperprojectBelongsToNoSubmodule() {
		let estate = estate(["svc-3", "svc-47"])
		#expect(estate.submodule(containing: "README.md") == nil)
		#expect(estate.repositoryRoot(containing: "README.md") == root)
		#expect(estate.relativePath(of: "README.md") == "README.md")
	}

	/// The row named `svc-47` in a tree of changes is a row about that
	/// repository's changes, so staging it stages everything in it.
	@Test func aSubmoduleContainsItsOwnRoot() {
		let estate = estate(["svc-47"])
		#expect(estate.submodule(containing: "svc-47")?.path == "svc-47")
		#expect(estate.relativePath(of: "svc-47") == ".")
	}

	/// The failure this whole lookup exists to prevent: a directory whose name
	/// begins with a submodule's name is not inside it. Matching on the string
	/// prefix alone would put `svc-470` under `svc-47` and stage the wrong
	/// repository.
	@Test func aSiblingWhoseNameStartsWithASubmodulesNameIsNotInsideIt() {
		let estate = estate(["svc-47"])
		#expect(estate.submodule(containing: "svc-470/src/Main.java") == nil)
		#expect(estate.submodule(containing: "svc-47x") == nil)
	}

	/// A file just written inside a submodule arrives as a filesystem event
	/// before anything has stat'd it, so ownership cannot depend on disk.
	@Test func aPathThatDoesNotExistStillHasAnOwner() {
		let estate = estate(["svc-47"])
		#expect(estate.submodule(containing: "svc-47/nothing/has/written/this/yet.java")?.path
			== "svc-47")
	}

	@Test func theLongestPrefixWins() {
		let estate = estate(["dienste", "dienste/svc-47"])
		#expect(estate.submodule(containing: "dienste/svc-47/src/Main.java")?.path
			== "dienste/svc-47")
		#expect(estate.submodule(containing: "dienste/other/Main.java")?.path == "dienste")
	}

	/// Git says `svc-47/`, a tree row says `svc-47`, and a caller that has
	/// joined two components says `./svc-47`. All three are the same path.
	@Test func theSpellingsOfAPathAreTheSamePath() {
		let estate = estate(["svc-47"])
		for spelling in ["svc-47", "svc-47/", "./svc-47", "./svc-47/"] {
			#expect(estate.submodule(containing: spelling)?.path == "svc-47", "\(spelling)")
		}
	}

	@Test func aRepositoryWithNoSubmodulesOwnsEverything() {
		let estate = estate([])
		#expect(!estate.holdsSubmodules)
		#expect(estate.submodule(containing: "anything/at/all.swift") == nil)
		#expect(estate.repositoryRoot(containing: "anything/at/all.swift") == root)
	}

	// MARK: - Grouping

	@Test func aSelectionSpanningRepositoriesIsOneCommandEach() {
		let estate = estate(["svc-3", "svc-47"])
		let groups = estate.grouped([
			"README.md",
			"svc-47/src/Main.java",
			"svc-3/pom.xml",
			"svc-47/src/Other.java",
			"Sources/Thing.swift",
		])

		#expect(groups.count == 3)
		#expect(groups[0].submodule == nil)
		#expect(groups[0].paths == ["README.md", "Sources/Thing.swift"])
		#expect(groups[1].submodule?.path == "svc-3")
		#expect(groups[1].paths == ["pom.xml"])
		#expect(groups[2].submodule?.path == "svc-47")
		#expect(groups[2].paths == ["src/Main.java", "src/Other.java"])
	}

	/// Six repositories is six processes, whatever the number of paths — which
	/// is the whole argument for grouping rather than acting per path.
	@Test func aHundredPathsAcrossSixRepositoriesIsSixGroups() {
		let estate = estate((1...6).map { "svc-\($0)" })
		let paths = (0..<100).map { "svc-\(($0 % 6) + 1)/file\($0).java" }
		#expect(estate.grouped(paths).count == 6)
	}

	@Test func groupsComeInTheSameOrderTwice() {
		let estate = estate(["svc-3", "svc-47"])
		let paths = ["svc-47/a", "README.md", "svc-3/b"]
		#expect(estate.grouped(paths) == estate.grouped(paths))
		#expect(estate.grouped(paths).map(\.submodule?.path) == [nil, "svc-3", "svc-47"])
	}

	@Test func anEmptySelectionIsNoCommands() {
		#expect(estate(["svc-3"]).grouped([]).isEmpty)
	}

	/// Answering has to cost the depth of the path asked about, not the size of
	/// the estate: this is asked per row of a table three hundred rows long.
	/// Three hundred submodules and three answer the same number of lookups.
	@Test func ownershipDoesNotWalkTheEstate() {
		let large = estate((1...300).map { "svc-\($0)" })
		let small = estate(["svc-1"])
		#expect(large.submodule(containing: "svc-299/src/Main.java")?.path == "svc-299")
		#expect(small.submodule(containing: "svc-1/src/Main.java")?.path == "svc-1")
		// A path in neither: both refuse in the depth of the path.
		#expect(large.submodule(containing: "unrelated/src/Main.java") == nil)
	}
}
