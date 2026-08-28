import Foundation
import Testing
@testable import AbydosKit

/// The changes tree when the changes come from more than one repository.
struct GitEstateChangeTreeTests {
	private let root = URL(fileURLWithPath: "/tmp/super", isDirectory: true)

	private func estate(_ paths: [String]) -> GitEstate {
		GitEstate(
			root: root,
			submodules: paths.map { GitSubmodule(path: $0, recordedCommit: "aaaa") }
		)
	}

	private func change(_ path: String, _ kind: GitChange.Kind = .modified) -> GitChange {
		GitChange(path: path, kind: kind, isStaged: false)
	}

	/// The failure the repository row exists to prevent: `src/main/java` is a
	/// real path in every one of two hundred microservices, and one row for all
	/// of them would stage the wrong repository.
	@Test func theSamePathInTwoSubmodulesIsTwoBranchesOfTheTree() {
		let roots = GitChangeTree.build(
			[change("svc-3/src/Main.java"), change("svc-47/src/Main.java")],
			in: estate(["svc-3", "svc-47"])
		)
		#expect(roots.map(\.path) == ["svc-3", "svc-47"])
		#expect(roots.allSatisfy { $0.isRepository })
		#expect(roots[0].children.map(\.path) == ["svc-3/src"])
		#expect(roots[1].children.map(\.path) == ["svc-47/src"])
	}

	@Test func aSubmoduleIsARepositoryRowAndItsFoldersAreBeneathIt() {
		let roots = GitChangeTree.build(
			[change("svc-47/src/main/java/Log.java")], in: estate(["svc-47"])
		)
		#expect(roots.count == 1)
		#expect(roots[0].isRepository)
		#expect(roots[0].submodule?.path == "svc-47")

		let index = GitChangeTree.index(roots)
		#expect(index["svc-47/src"]?.isRepository == false, "a folder inside is still a folder")
		#expect(index["svc-47/src/main/java/Log.java"]?.change != nil)
	}

	/// A project with no submodules gains no row: a level with one child that is
	/// always the same child says nothing.
	@Test func aProjectWithNoSubmodulesGetsTheTreeItAlwaysHad() {
		let withEstate = GitChangeTree.build(
			[change("Sources/Thing.swift")], in: estate([])
		)
		let without = GitChangeTree.build([change("Sources/Thing.swift")])
		#expect(withEstate.map(\.path) == without.map(\.path))
		#expect(withEstate.allSatisfy { !$0.isRepository })
	}

	/// One submodule is one row. Two rows reading `svc-47` — a gitlink and a
	/// folder — would be the same thing twice with different verbs on it.
	@Test func aMovedGitlinkAndDirtyContentsAreOneRow() {
		let roots = GitChangeTree.build(
			[change("svc-47"), change("svc-47/src/Main.java")], in: estate(["svc-47"])
		)
		#expect(roots.count == 1)
		#expect(roots[0].path == "svc-47")
		#expect(roots[0].isRepository)
		#expect(roots[0].gitlink != nil, "it says it moved")
		#expect(roots[0].count == 1, "and it says what is dirty inside it, as one file")
	}

	/// A submodule that moved and is otherwise clean is still a row: `build`
	/// makes a folder only where something changed under it, and this is a
	/// change with nothing under it.
	@Test func aSubmoduleThatOnlyMovedIsStillARow() {
		let roots = GitChangeTree.build([change("svc-47")], in: estate(["svc-47"]))
		#expect(roots.map(\.path) == ["svc-47"])
		#expect(roots[0].isRepository)
		#expect(roots[0].gitlink != nil)
		#expect(roots[0].children.isEmpty)
	}

	@Test func theSuperprojectsOwnFilesSitBesideTheRepositories() {
		let roots = GitChangeTree.build(
			[change("README.md"), change("svc-47/src/Main.java")], in: estate(["svc-47"])
		)
		#expect(Set(roots.map(\.path)) == ["README.md", "svc-47"])
		#expect(roots.first(where: { $0.path == "README.md" })?.isRepository == false)
	}

	/// A submodule nested in a folder keeps the folder above it, because that
	/// folder is a real place in the superproject.
	@Test func aSubmoduleInsideAFolderKeepsTheFolderAboveIt() {
		let roots = GitChangeTree.build(
			[change("dienste/svc-47/src/Main.java")], in: estate(["dienste/svc-47"])
		)
		#expect(roots.map(\.path) == ["dienste"])
		#expect(roots[0].isRepository == false)
		#expect(roots[0].children.map(\.path) == ["dienste/svc-47"])
		#expect(roots[0].children[0].isRepository)
	}

	// MARK: - Flattening a status into one tree's worth of paths

	@Test func flatteningPutsTheRepositoryInFrontOfEveryPath() {
		let estate = estate(["svc-3", "svc-47"])
		let status = GitEstateStatus(
			superproject: GitWorkingCopyStatus(unstaged: [change("README.md")]),
			submodules: [
				"svc-3": GitWorkingCopyStatus(unstaged: [change("src/Main.java")]),
				"svc-47": GitWorkingCopyStatus(
					staged: [change("pom.xml")], unstaged: [change("src/Main.java")]
				),
			]
		)

		let flat = status.flattened(in: estate)
		#expect(flat.unstaged.map(\.path)
			== ["README.md", "svc-3/src/Main.java", "svc-47/src/Main.java"])
		#expect(flat.staged.map(\.path) == ["svc-47/pom.xml"])
	}

	@Test func aSubmoduleNotYetReadContributesNothingRatherThanNoChanges() {
		let estate = estate(["svc-3", "svc-47"])
		let status = GitEstateStatus(
			submodules: ["svc-3": GitWorkingCopyStatus(unstaged: [change("a.java")])]
		)
		#expect(status.flattened(in: estate).unstaged.map(\.path) == ["svc-3/a.java"])
	}

	/// What the tree is built from and what stages it are the same paths, read
	/// in both directions.
	@Test func aPathOutOfTheTreeGoesBackToItsOwnRepository() {
		let estate = estate(["svc-47"])
		let roots = GitChangeTree.build(
			[change("svc-47/src/Main.java")], in: estate
		)
		let index = GitChangeTree.index(roots)
		guard let leaf = index["svc-47/src/Main.java"] else { Issue.record("no leaf"); return }

		let groups = estate.grouped([leaf.path])
		#expect(groups.count == 1)
		#expect(groups[0].submodule?.path == "svc-47")
		#expect(groups[0].paths == ["src/Main.java"])
	}

	/// Selecting the repository row means everything in that repository.
	@Test func selectingARepositoryRowStagesTheWholeOfIt() {
		let estate = estate(["svc-47"])
		let groups = estate.grouped(["svc-47"])
		#expect(groups[0].submodule?.path == "svc-47")
		#expect(groups[0].paths == ["."])
	}
}
