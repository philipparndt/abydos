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
