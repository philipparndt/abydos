import Foundation
import Testing
@testable import AbydosKit

/// Acting on more than one repository at once.
struct GitEstateOperationTests {
	/// The failure this grouping exists to prevent: `git add` resolves a
	/// pathspec against the repository it runs in, so a submodule's file staged
	/// in the superproject stages nothing and says `pathspec did not match`.
	@Test func aFileInsideASubmoduleIsStagedInThatSubmodule() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "stage")
		defer { estate.remove() }
		try estate.dirty("svc-2")

		let read = await GitEstate.read(from: estate.root)
		let outcomes = await GitEstateOperation.stage(
			paths: ["svc-2/src/Main.java"], in: read
		)

		#expect(outcomes.count == 1)
		#expect(outcomes.first?.submodule?.path == "svc-2")
		#expect(outcomes.first?.didHappen == true)

		let after = await GitWorkingCopy.status(in: estate.root.appendingPathComponent("svc-2"))
		#expect(after.staged.map(\.path) == ["src/Main.java"])
		#expect(after.unstaged.isEmpty)
	}

	@Test func aSelectionSpanningRepositoriesIsOneCommandEach() async throws {
		let estate = try SyntheticEstate.make(count: 3, named: "spanning")
		defer { estate.remove() }
		try estate.dirty("svc-1")
		try estate.dirty("svc-3")
		try "changed\n".write(
			to: estate.root.appendingPathComponent("README.md"),
			atomically: true, encoding: .utf8
		)

		let read = await GitEstate.read(from: estate.root)
		let outcomes = await GitEstateOperation.stage(
			paths: ["README.md", "svc-3/src/Main.java", "svc-1/src/Main.java"], in: read
		)

		#expect(outcomes.map(\.name) == [".", "svc-1", "svc-3"], "superproject first, then path order")
		#expect(outcomes.filter(\.didHappen).count == 3)
		for name in ["svc-1", "svc-3"] {
			let status = await GitWorkingCopy.status(in: estate.root.appendingPathComponent(name))
			#expect(status.staged.map(\.path) == ["src/Main.java"], "\(name)")
		}
	}

	/// Selecting the row named `svc-47` means everything in `svc-47`.
	@Test func stagingASubmodulesOwnRowStagesEverythingInIt() async throws {
		let estate = try SyntheticEstate.make(count: 1, named: "wholerow")
		defer { estate.remove() }
		try estate.dirty("svc-1")
		try "new\n".write(
			to: estate.root.appendingPathComponent("svc-1/added.txt"),
			atomically: true, encoding: .utf8
		)

		let read = await GitEstate.read(from: estate.root)
		await GitEstateOperation.stage(paths: ["svc-1"], in: read)

		let after = await GitWorkingCopy.status(in: estate.root.appendingPathComponent("svc-1"))
		#expect(after.staged.map(\.path).sorted() == ["added.txt", "src/Main.java"])
	}

	@Test func discardingActsInTheRepositoryThatOwnsThePath() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "discard")
		defer { estate.remove() }
		try estate.dirty("svc-1")

		let read = await GitEstate.read(from: estate.root)
		await GitEstateOperation.discard(paths: ["svc-1/src/Main.java"], in: read)

		let after = await GitWorkingCopy.status(in: estate.root.appendingPathComponent("svc-1"))
		#expect(after.isEmpty, "the change is gone")
	}

	// MARK: - Committing

	@Test func committingTheEstateCommitsEachSubmoduleThenTheSuperproject() async throws {
		let estate = try SyntheticEstate.make(count: 3, named: "commit")
		defer { estate.remove() }
		try estate.dirty("svc-1")
		try estate.dirty("svc-3")

		var read = await GitEstate.read(from: estate.root)
		await GitEstateOperation.stage(
			paths: ["svc-1/src/Main.java", "svc-3/src/Main.java"], in: read
		)
		read = await GitEstate.read(from: estate.root)
		let status = await GitEstateReader.status(of: read)

		let outcomes = await GitEstateOperation.commit(
			subject: "one message", body: "", in: read, status: status
		)

		// Every repository has an outcome, including the ones with nothing to do.
		#expect(outcomes.map(\.name) == ["svc-1", "svc-2", "svc-3", "."])
		#expect(outcomes.filter(\.didHappen).map(\.name) == ["svc-1", "svc-3", "."])
		#expect(outcomes.first(where: { $0.name == "svc-2" })?.result
			== .skipped("nothing changed"))

		// And each commit is named, so a partial run can be read afterwards.
		for outcome in outcomes where outcome.didHappen {
			guard case .done(let commit) = outcome.result else { continue }
			#expect(commit?.isEmpty == false, "\(outcome.name)")
		}

		// The gitlinks the submodule commits moved are recorded by the
		// superproject's own commit, so the estate is not left half-recorded.
		let after = await GitWorkingCopy.status(in: estate.root)
		#expect(after.isEmpty, "nothing left over: \(after)")
	}

	/// Committing without bumping the gitlinks is the other reading, and the
	/// caller says which it meant rather than this deciding quietly.
	@Test func theSuperprojectIsLeftAloneWhenTheGitlinksAreNotBumped() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "nobump")
		defer { estate.remove() }
		try estate.dirty("svc-1")

		var read = await GitEstate.read(from: estate.root)
		await GitEstateOperation.stage(paths: ["svc-1/src/Main.java"], in: read)
		read = await GitEstate.read(from: estate.root)
		let status = await GitEstateReader.status(of: read)

		let outcomes = await GitEstateOperation.commit(
			subject: "just the submodules", body: "", in: read, status: status,
			stagingGitlinks: false
		)

		#expect(outcomes.first(where: { $0.name == "svc-1" })?.didHappen == true)
		#expect(outcomes.last?.result == .skipped("nothing staged"))

		let after = await GitWorkingCopy.status(in: estate.root)
		#expect(after.unstaged.map(\.path) == ["svc-1"], "the moved gitlink is left to be reviewed")
	}

	/// A failure at one repository leaves the others' commits standing. There is
	/// no rollback, and there must not be: undoing them is `git reset --hard` in
	/// repositories somebody may already have fetched.
	@Test func aRepositoryThatRefusesDoesNotUndoTheOnesBeforeIt() async throws {
		let estate = try SyntheticEstate.make(count: 3, named: "refuses")
		defer { estate.remove() }
		for name in ["svc-1", "svc-2", "svc-3"] { try estate.dirty(name) }

		var read = await GitEstate.read(from: estate.root)
		await GitEstateOperation.stage(
			paths: ["svc-1", "svc-2", "svc-3"], in: read
		)

		// A pre-commit hook that refuses, in the middle repository only.
		let hooks = estate.root.appendingPathComponent(".git/modules/svc-2/hooks")
		try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
		let hook = hooks.appendingPathComponent("pre-commit")
		try "#!/bin/sh\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755], ofItemAtPath: hook.path
		)

		read = await GitEstate.read(from: estate.root)
		let status = await GitEstateReader.status(of: read)
		let outcomes = await GitEstateOperation.commit(
			subject: "across the estate", body: "", in: read, status: status
		)

		#expect(outcomes.first(where: { $0.name == "svc-1" })?.didHappen == true)
		#expect(outcomes.first(where: { $0.name == "svc-2" })?.didFail == true)
		#expect(outcomes.first(where: { $0.name == "svc-3" })?.didHappen == true,
			"the run carries on past a refusal")

		// The two that worked are still committed.
		for name in ["svc-1", "svc-3"] {
			let after = await GitWorkingCopy.status(in: estate.root.appendingPathComponent(name))
			#expect(after.isEmpty, "\(name) kept its commit")
		}
		let refused = await GitWorkingCopy.status(
			in: estate.root.appendingPathComponent("svc-2")
		)
		#expect(!refused.staged.isEmpty, "svc-2's work is still there to try again")
	}

	/// Repeating a partial run acts on what is still dirty and leaves what
	/// succeeded alone.
	@Test func aPartialRunIsResumable() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "resume")
		defer { estate.remove() }
		try estate.dirty("svc-1")

		var read = await GitEstate.read(from: estate.root)
		await GitEstateOperation.stage(paths: ["svc-1"], in: read)
		read = await GitEstate.read(from: estate.root)
		var status = await GitEstateReader.status(of: read)
		await GitEstateOperation.commit(subject: "first", body: "", in: read, status: status)

		// Now the second repository changes, and the run is repeated.
		try estate.dirty("svc-2")
		read = await GitEstate.read(from: estate.root)
		await GitEstateOperation.stage(paths: ["svc-2"], in: read)
		read = await GitEstate.read(from: estate.root)
		status = await GitEstateReader.status(of: read)
		let outcomes = await GitEstateOperation.commit(
			subject: "second", body: "", in: read, status: status
		)

		#expect(outcomes.first(where: { $0.name == "svc-1" })?.result
			== .skipped("nothing changed"), "what succeeded is left alone")
		#expect(outcomes.first(where: { $0.name == "svc-2" })?.didHappen == true)
	}

	@Test func anAbsentSubmoduleIsSkippedAndSaidToBe() async throws {
		let estate = try SyntheticEstate.make(count: 2, named: "absentcommit")
		defer { estate.remove() }
		try FileManager.default.removeItem(at: estate.root.appendingPathComponent("svc-2"))

		let read = await GitEstate.read(from: estate.root)
		let status = await GitEstateReader.status(of: read)
		let outcomes = await GitEstateOperation.commit(
			subject: "x", body: "", in: read, status: status
		)
		#expect(outcomes.first(where: { $0.name == "svc-2" })?.result
			== .skipped("not checked out"))
	}
}
