import Foundation
import Testing
@testable import AbydosKit

/// A project holds the repository *and* the submodules it holds.
@MainActor
struct ProjectEstateTests {
	@Test func openingASuperprojectReadsWhatItHolds() async throws {
		let built = try SyntheticEstate.make(count: 3, named: "projectestate")
		defer { built.remove() }

		let project = Project(root: built.root)
		await project.loadGit()

		#expect(project.estate.holdsSubmodules)
		#expect(project.estate.submodules.map(\.path) == ["svc-1", "svc-2", "svc-3"])
		#expect(project.estate.root == built.root.standardizedFileURL)
	}

	/// `git` still means the repository this project is, which is what every
	/// caller that has ever asked for it meant. The estate is the second
	/// question — which repository owns *this path* — and it is asked separately
	/// so that nobody is moved from one to the other by a rename.
	@Test func theRepositoryIsStillTheSuperproject() async throws {
		let built = try SyntheticEstate.make(count: 2, named: "stillsuper")
		defer { built.remove() }

		let project = Project(root: built.root)
		await project.loadGit()

		#expect(project.gitRoot == built.root.standardizedFileURL)
		#expect(project.estate.submodule(containing: "svc-2/src/Main.java")?.path == "svc-2")
		#expect(
			project.estate.repositoryRoot(containing: "svc-2/src/Main.java")
				== built.root.standardizedFileURL.appendingPathComponent("svc-2")
		)
	}

	/// **One answer for every verb that got it wrong.** Compare, History, the
	/// diff tab, the line-level apply and discard, blame and the gutter's
	/// change marks all aimed git at the superproject for a file inside a
	/// submodule, where a diff, a log and a blame come back empty or fail — and
	/// empty reads as "nothing changed", "no history", "never committed".
	@Test func aFileIsPlacedInTheRepositoryThatOwnsIt() async throws {
		let built = try SyntheticEstate.make(count: 2, named: "projectplace")
		defer { built.remove() }

		let project = Project(root: built.root)
		await project.loadGit()

		let inside = project.place(of: built.root.appendingPathComponent("svc-2/src/Main.java"))
		#expect(inside?.root == built.root.standardizedFileURL.appendingPathComponent("svc-2"))
		#expect(inside?.path == "src/Main.java")
		#expect(inside?.estatePath == "svc-2/src/Main.java")

		// The superproject's own file is the superproject's, under one name.
		let own = project.place(of: built.root.appendingPathComponent("README.md"))
		#expect(own?.root == built.root.standardizedFileURL)
		#expect(own?.path == "README.md")

		#expect(project.place(of: URL(fileURLWithPath: "/elsewhere/README.md")) == nil)
	}

	/// **Before the inventory exists there is nothing to place with**, and the
	/// project's own root is the answer — right for a repository with no
	/// submodules, and wrong for a file inside one. It is why the window asks
	/// the gutter again once `loadGit` has finished: the first ask happens as
	/// the tab opens, seconds earlier, and nothing else would re-ask.
	@Test func beforeGitIsReadTheProjectsOwnRootIsTheAnswer() throws {
		let built = try SyntheticEstate.make(count: 1, named: "projectplacecold")
		defer { built.remove() }

		let project = Project(root: built.root)
		let cold = project.place(of: built.root.appendingPathComponent("svc-1/src/Main.java"))
		#expect(cold?.root == built.root.standardizedFileURL)
		#expect(cold?.path == "svc-1/src/Main.java")
	}

	/// A repository with no submodules is an estate of one, on the same code
	/// path rather than around it.
	@Test func aProjectWithNoSubmodulesIsAnEstateOfOne() async throws {
		let built = try SyntheticEstate.make(count: 0, named: "projectplain")
		defer { built.remove() }

		let project = Project(root: built.root)
		await project.loadGit()

		#expect(!project.estate.holdsSubmodules)
		#expect(project.estate.repositoryRoot(containing: "README.md")
			== built.root.standardizedFileURL)
	}
}
