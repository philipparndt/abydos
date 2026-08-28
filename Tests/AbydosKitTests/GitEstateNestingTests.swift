import Foundation
import Testing
@testable import AbydosKit

/// Submodules inside submodules, and submodules inside a linked worktree.
///
/// Both were non-goals while the estate was being built, and both turn out to
/// be one fact: a submodule's git directory is always its parent's git
/// directory plus `modules/<name>`. Everything here checks that against a real
/// repository, because it is a claim about what git does with directories and
/// no fixture can answer it.
struct GitEstateNestingTests {
	// MARK: - Nesting

	@Test func aSubmoduleInsideASubmoduleIsInTheInventory() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "nested")
		defer { estate.remove() }
		let inner = try estate.nest("leaf", inside: "svc-1", at: "lib/leaf")

		let read = await GitEstate.read(from: estate.root)
		#expect(read.submodules.map(\.path) == ["svc-1", "svc-1/lib/leaf", "svc-2"])
		#expect(inner == "svc-1/lib/leaf")

		let nested = read.submodule(at: inner)
		#expect(nested?.depth == 1)
		#expect(read.submodule(at: "svc-1")?.depth == 0)
	}

	/// The rule the watching rests on, at depth. Verified against what git
	/// actually wrote rather than against what this program assumed.
	@Test func aNestedSubmodulesGitDirectoryIsItsParentsPlusModules() async throws {
		let estate = try SyntheticEstate.make(count: 1, named: "nestedgitdir")
		defer { estate.remove() }
		let inner = try estate.nest("leaf", inside: "svc-1", at: "lib/leaf")

		let read = await GitEstate.read(from: estate.root)
		#expect(read.submodule(at: "svc-1")?.gitDirectorySuffix == "modules/svc-1")
		#expect(read.submodule(at: inner)?.gitDirectorySuffix == "modules/svc-1/modules/lib/leaf")

		// And that is where git put it.
		let suffix = read.submodule(at: inner)?.gitDirectorySuffix ?? ""
		let expected = read.gitDirectoryOrDefault.appendingPathComponent(suffix)
		#expect(FileManager.default.fileExists(atPath: expected.path), "\(expected.path)")
	}

	/// A flat estate must not pay for nesting it does not have: recursing is
	/// gated on a `.gitmodules` existing, which is a stat and not a process.
	@Test func aFlatEstateIsNotRecursedInto() async throws {
		let estate = try SyntheticEstate.make(count: 3, named: "flatnest")
		defer { estate.remove() }

		let read = await GitEstate.read(from: estate.root)
		#expect(read.submodules.map(\.path) == ["svc-1", "svc-2", "svc-3"])
		#expect(read.submodules.filter { $0.depth == 0 }.count == 3)
		for submodule in read.submodules {
			#expect(!FileManager.default.fileExists(
				atPath: estate.root.appendingPathComponent(submodule.path)
					.appendingPathComponent(".gitmodules").path
			), "\(submodule.path) has no submodules to declare")
		}
	}

	@Test func aNestedSubmodulesChangesAreReadLikeAnyOthers() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "nestedstatus")
		defer { estate.remove() }
		let inner = try estate.nest("leaf", inside: "svc-1", at: "lib/leaf")

		try "changed\n".write(
			to: estate.root.appendingPathComponent(inner).appendingPathComponent("src/Inner.java"),
			atomically: true, encoding: .utf8
		)

		let read = await GitEstate.read(from: estate.root)
		let status = await GitEstateReader.status(of: read)
		#expect(status.changedSubmodules(in: read).map(\.path) == [inner])
		#expect(status.status(of: inner)?.unstaged.map(\.path) == ["src/Inner.java"])
	}

	/// Ownership already handled nesting; this says so against a real one.
	@Test func aFileInANestedSubmoduleBelongsToIt() async throws {
		let estate = try SyntheticEstate.make(count: 1, named: "nestedowner")
		defer { estate.remove() }
		let inner = try estate.nest("leaf", inside: "svc-1", at: "lib/leaf")

		let read = await GitEstate.read(from: estate.root)
		#expect(read.submodule(containing: "\(inner)/src/Inner.java")?.path == inner)
		#expect(read.relativePath(of: "\(inner)/src/Inner.java") == "src/Inner.java")
		// And a file in the middle repository still belongs to the middle one.
		#expect(read.submodule(containing: "svc-1/src/Main.java")?.path == "svc-1")
	}

	/// A ref written in a nested submodule is attributed to it, which needs the
	/// whole `modules/…/modules/…` suffix: matching on the name alone cannot
	/// tell one level from two.
	@Test func aRefWrittenDeepIsAttributedToTheNestedSubmodule() async throws {
		let estate = try SyntheticEstate.make(count: 1, named: "nestedrefs")
		defer { estate.remove() }
		let inner = try estate.nest("leaf", inside: "svc-1", at: "lib/leaf")

		let read = await GitEstate.read(from: estate.root)
		let deep = read.gitDirectoryOrDefault
			.appendingPathComponent("modules/svc-1/modules/lib/leaf/refs/heads")
		#expect(GitEstateRefresh.work(forChangedPaths: [deep], in: read).submodulePaths == [inner])

		// And the level above it is still its own repository.
		let shallow = read.gitDirectoryOrDefault.appendingPathComponent("modules/svc-1/refs/heads")
		#expect(GitEstateRefresh.work(forChangedPaths: [shallow], in: read).submodulePaths
			== ["svc-1"])
	}

	/// Committing outwards would record where the inner ones were *before* they
	/// moved: a superproject pointing at a commit that is already history the
	/// moment it is written.
	@Test func committingWorksOutwardsFromTheDeepest() async throws {
		let estate = try SyntheticEstate.make(count: 1, named: "nestedcommit")
		defer { estate.remove() }
		let inner = try estate.nest("leaf", inside: "svc-1", at: "lib/leaf")

		try "changed\n".write(
			to: estate.root.appendingPathComponent(inner).appendingPathComponent("src/Inner.java"),
			atomically: true, encoding: .utf8
		)

		var read = await GitEstate.read(from: estate.root)
		await GitEstateOperation.stage(paths: ["\(inner)/src/Inner.java"], in: read)
		read = await GitEstate.read(from: estate.root)
		let status = await GitEstateReader.status(of: read)

		let outcomes = await GitEstateOperation.commit(
			subject: "across three levels", body: "", in: read, status: status
		)

		// The leaf committed, and the two above it recorded where it got to.
		#expect(outcomes.first(where: { $0.name == inner })?.didHappen == true)
		#expect(outcomes.first(where: { $0.name == "svc-1" })?.didHappen == true)
		#expect(outcomes.first(where: { $0.name == "." })?.didHappen == true)

		// Nothing is left over at any level, which is the whole claim.
		for place in ["", "svc-1", inner] {
			let where_ = place.isEmpty
				? estate.root
				: estate.root.appendingPathComponent(place)
			let after = await GitWorkingCopy.status(in: where_)
			#expect(after.isEmpty, "\(place.isEmpty ? "." : place) left \(after)")
		}
	}

	/// A gitlink is the containing repository's index entry, so `svc-1/lib/leaf`
	/// is staged in `svc-1` and never in the superproject, which has no such
	/// path.
	@Test func aGitlinkIsStagedInTheRepositoryThatHoldsIt() async throws {
		let estate = try SyntheticEstate.make(count: 1, named: "nestedgitlink")
		defer { estate.remove() }
		let inner = try estate.nest("leaf", inside: "svc-1", at: "lib/leaf")

		let read = await GitEstate.read(from: estate.root)
		let deep = GitEstateOperation.directChildren(
			of: read.submodule(at: "svc-1"), in: read, committed: [inner]
		)
		#expect(deep == ["lib/leaf"], "relative to svc-1, not to the superproject")

		let shallow = GitEstateOperation.directChildren(
			of: nil, in: read, committed: [inner, "svc-1"]
		)
		#expect(shallow == ["svc-1"], "the superproject holds svc-1 and nothing deeper")
	}

	// MARK: - Linked worktrees

	/// **The failure this fixes.** A worktree's `.git` is a file pointing
	/// outside the work tree, so a rule that looked for `.git/` under the work
	/// tree attributed nothing: a commit or a checkout made in a worktree
	/// changed no row at all.
	@Test func aWorktreesGitDirectoryIsNotUnderItsWorkTree() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "worktree")
		defer { estate.remove() }
		let worktree = estate.worktree(named: "review", on: "review")

		let read = await GitEstate.read(from: worktree)
		let gitDirectory = read.gitDirectoryOrDefault
		#expect(gitDirectory.path.contains("/worktrees/review"))
		#expect(!gitDirectory.path.hasPrefix(worktree.standardizedFileURL.path + "/"),
			"it is not under the work tree, which is the whole difficulty")
	}

	@Test func aWorktreeSeesTheSameSubmodules() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "worktreelist")
		defer { estate.remove() }
		let worktree = estate.worktree(named: "review", on: "review")

		let read = await GitEstate.read(from: worktree)
		#expect(read.submodules.map(\.path) == ["svc-1", "svc-2"])
		#expect(read.submodules.filter(\.isCheckedOut).count == 2)
	}

	/// A submodule inside a worktree keeps its refs under the *worktree's* git
	/// directory, not the main one — so attributing against `.git/modules`
	/// would have found nothing.
	@Test func aRefWrittenInAWorktreesSubmoduleIsAttributedToIt() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "worktreerefs")
		defer { estate.remove() }
		let worktree = estate.worktree(named: "review", on: "review")

		let read = await GitEstate.read(from: worktree)
		let refs = read.gitDirectoryOrDefault.appendingPathComponent("modules/svc-2/refs/heads")
		#expect(FileManager.default.fileExists(atPath: refs.path), "\(refs.path)")
		#expect(GitEstateRefresh.work(forChangedPaths: [refs], in: read).submodulePaths
			== ["svc-2"])
	}

	@Test func theWorktreesOwnIndexIsStillTheSuperprojects() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "worktreeindex")
		defer { estate.remove() }
		let worktree = estate.worktree(named: "review", on: "review")

		let read = await GitEstate.read(from: worktree)
		let index = read.gitDirectoryOrDefault.appendingPathComponent("index")
		let work = GitEstateRefresh.work(forChangedPaths: [index], in: read)
		#expect(work.superproject)
		#expect(work.inventory)
	}

	@Test func aFileWrittenInAWorktreesSubmoduleIsAttributedToIt() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "worktreefiles")
		defer { estate.remove() }
		let worktree = estate.worktree(named: "review", on: "review")

		let read = await GitEstate.read(from: worktree)
		let file = worktree.appendingPathComponent("svc-1/src/Main.java")
		#expect(GitEstateRefresh.work(forChangedPaths: [file], in: read).submodulePaths
			== ["svc-1"])
	}

	/// Both at once, which is the shape neither non-goal covered.
	@Test func aNestedSubmoduleInsideAWorktree() async throws {
		let estate = try SyntheticEstate.make(count: 1, named: "worktreenested")
		defer { estate.remove() }
		let inner = try estate.nest("leaf", inside: "svc-1", at: "lib/leaf")
		let worktree = estate.worktree(named: "review", on: "review")

		let read = await GitEstate.read(from: worktree)
		#expect(read.submodules.map(\.path) == ["svc-1", inner])

		let deep = read.gitDirectoryOrDefault
			.appendingPathComponent("modules/svc-1/modules/lib/leaf/refs/heads")
		#expect(FileManager.default.fileExists(atPath: deep.path), "\(deep.path)")
		#expect(GitEstateRefresh.work(forChangedPaths: [deep], in: read).submodulePaths == [inner])
	}
}
