import Testing
import Foundation
@testable import AbydosKit

/// What a discard covers, and what it says it is about to do.
///
/// The wording is tested because it is the safety: discard is the one thing the
/// changes pane does that has no way back, and a confirmation that miscounts, or
/// that calls deleting a file "reverting" it, is worse than no confirmation.
struct GitDiscardWordingTests {
	private let unstaged = [
		GitChange(path: "Sources/App/Main.swift", kind: .modified, isStaged: false),
		GitChange(path: "Sources/App/New.swift", kind: .untracked, isStaged: false),
		GitChange(path: "Sources/Kit/Old.swift", kind: .deleted, isStaged: false),
		GitChange(path: "README.md", kind: .modified, isStaged: false),
	]

	@Test func aFolderCoversEverythingUnderIt() {
		let covered = GitDiscard.changes(unstaged, under: ["Sources/App"])
		#expect(covered.map(\.path) == ["Sources/App/Main.swift", "Sources/App/New.swift"])
	}

	/// A prefix is not a parent. `Sources/App` must not swallow `Sources/Apple`.
	@Test func aFolderDoesNotCoverASiblingItsNameStartsWith() {
		let changes = [GitChange(path: "Sources/Apple.swift", kind: .modified, isStaged: false)]
		#expect(GitDiscard.changes(changes, under: ["Sources/App"]).isEmpty)
	}

	@Test func aFileCoversItself() {
		#expect(GitDiscard.changes(unstaged, under: ["README.md"]).map(\.path) == ["README.md"])
	}

	/// The count is files, not rows: this is the number the confirmation says.
	@Test func severalRowsCoverTheirFilesOnce() {
		let covered = GitDiscard.changes(unstaged, under: ["Sources", "README.md"])
		#expect(covered.count == 4)
	}

	@Test func aTrackedFileIsOfferedAsDiscardingChanges() {
		#expect(GitDiscard.menuTitle(subject: .file("Main.swift"), files: 1, untracked: 0)
			== "Discard Changes\u{2026}")
		#expect(GitDiscard.question(subject: .file("Main.swift"), files: 1, untracked: 0)
			== "Discard changes to “Main.swift”?")
		#expect(GitDiscard.buttonTitle(files: 1, untracked: 0) == "Discard")
	}

	/// "Discard Changes" over a file git has never seen is false — there are no
	/// changes, there is a file, and it is about to stop existing.
	@Test func anUntrackedFileIsOfferedAsDeletingIt() {
		#expect(GitDiscard.menuTitle(subject: .file("New.swift"), files: 1, untracked: 1)
			== "Delete “New.swift”\u{2026}")
		#expect(GitDiscard.question(subject: .file("New.swift"), files: 1, untracked: 1)
			== "Delete “New.swift”?")
		#expect(GitDiscard.buttonTitle(files: 1, untracked: 1) == "Delete")
	}

	/// A folder says how many files it is about to take, the way Stage does.
	@Test func aFolderSaysHowManyFiles() {
		#expect(GitDiscard.menuTitle(subject: .folder("Sources"), files: 40, untracked: 0)
			== "Discard Changes in “Sources” (40 files)\u{2026}")
		#expect(GitDiscard.question(subject: .folder("Sources"), files: 40, untracked: 0)
			== "Discard changes in 40 files under “Sources”?")
	}

	/// Untracked and modified files under one folder are two different
	/// operations on one gesture, and the number that matters is the second one.
	@Test func aMixedFolderSaysHowManyAreUntracked() {
		#expect(GitDiscard.menuTitle(subject: .folder("Sources"), files: 40, untracked: 12)
			== "Discard Changes in “Sources” (40 files, 12 untracked)\u{2026}")

		let explanation = GitDiscard.explanation(files: 40, untracked: 12)
		#expect(explanation.contains("12 of them are untracked"))
		#expect(explanation.contains("deleted from the disk"))
		#expect(explanation.contains("The other 28"))
	}

	@Test func aFolderOfNothingButNewFilesIsADeletion() {
		#expect(GitDiscard.menuTitle(subject: .folder("Generated"), files: 3, untracked: 3)
			== "Delete “Generated” (3 files)\u{2026}")
		#expect(GitDiscard.question(subject: .folder("Generated"), files: 3, untracked: 3)
			== "Delete 3 files under “Generated”?")
	}

	@Test func severalRowsAreNamedByTheirCount() {
		#expect(GitDiscard.menuTitle(subject: .rows, files: 3, untracked: 0)
			== "Discard Changes in 3 Files\u{2026}")
		#expect(GitDiscard.menuTitle(subject: .rows, files: 3, untracked: 1)
			== "Discard Changes in 3 Files (1 untracked)\u{2026}")
		#expect(GitDiscard.menuTitle(subject: .rows, files: 3, untracked: 3)
			== "Delete 3 Files\u{2026}")
	}

	/// The pane already has stash, which is discard with a way back. Naming it
	/// is the cheapest thing the confirmation can do for somebody who opened it
	/// meaning something slightly different.
	@Test func theConfirmationAlwaysNamesStash() {
		for (files, untracked) in [(1, 0), (1, 1), (6, 0), (6, 2), (6, 6)] {
			let explanation = GitDiscard.explanation(files: files, untracked: untracked)
			#expect(explanation.contains("Stash"), "\(files)/\(untracked)")
			#expect(explanation.contains("cannot be undone"), "\(files)/\(untracked)")
		}
	}

	/// The two losses are different, and only one of them can be put back.
	@Test func theExplanationSeparatesDeletingFromReverting() {
		let deleting = GitDiscard.explanation(files: 2, untracked: 2)
		#expect(deleting.contains("no version to put back"))
		#expect(!deleting.contains("index"))

		let reverting = GitDiscard.explanation(files: 2, untracked: 0)
		#expect(reverting.contains("the version in the index"))
		#expect(!reverting.contains("deleted"))
	}

	/// Which of the clicked rows `git checkout` may be handed. A folder stays
	/// one argument; a row with nothing tracked under it is dropped, because a
	/// pathspec matching nothing fails the whole command.
	@Test func onlyPathsGitTracksSomethingUnderAreRestorable() {
		let known = ["Sources/App/Main.swift", "README.md"]
		#expect(GitDiscard.paths(["Sources/App"], coveringAnyOf: known) == ["Sources/App"])
		#expect(GitDiscard.paths(["README.md"], coveringAnyOf: known) == ["README.md"])
		#expect(GitDiscard.paths(["Generated"], coveringAnyOf: known).isEmpty)
		#expect(GitDiscard.paths(["Sources/App", "Generated"], coveringAnyOf: known)
			== ["Sources/App"])
	}

	/// The work tree root is nothing's prefix, so it has to be said rather than
	/// derived — and "throw away the lot" is the first thing anybody tries.
	@Test func theWorkTreeRootCoversEverythingGitKnows() {
		#expect(GitDiscard.paths(["."], coveringAnyOf: ["README.md"]) == ["."])
		#expect(GitDiscard.paths(["."], coveringAnyOf: []).isEmpty)
	}
}

/// Against a real repository, because discard is where being wrong costs
/// somebody their work and there is nothing to get it back from.
struct GitDiscardIntegrationTests {
	private func makeRepository() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-discard-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	private func git(_ arguments: [String], in root: URL) async {
		_ = await GitRepository.run(arguments, in: root)
	}

	private func write(_ text: String, to path: String, in root: URL) throws {
		let url = root.appendingPathComponent(path)
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true
		)
		try text.write(to: url, atomically: true, encoding: .utf8)
	}

	private func read(_ path: String, in root: URL) -> String? {
		try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
	}

	private func exists(_ path: String, in root: URL) -> Bool {
		FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
	}

	private func initialise(_ root: URL) async throws {
		await git(["init", "-q"], in: root)
		await git(["config", "user.email", "test@example.com"], in: root)
		await git(["config", "user.name", "Test"], in: root)
		try write("one\n", to: "Sources/tracked.txt", in: root)
		try write("keep\n", to: "README.md", in: root)
		await git(["add", "-A"], in: root)
		await git(["commit", "-qm", "initial"], in: root)
	}

	@Test func discardingAModifiedFileRestoresIt() async throws {
		let root = try makeRepository()
		try await initialise(root)
		try write("two\n", to: "Sources/tracked.txt", in: root)

		let result = await GitWorkingCopy.discard(paths: ["Sources/tracked.txt"], in: root)
		#expect(result.exitCode == 0)
		#expect(read("Sources/tracked.txt", in: root) == "one\n")
		#expect(await GitWorkingCopy.status(in: root).isEmpty)
	}

	/// The one git has no object for. `clean` takes it off the disk, and
	/// `checkout` used to be handed the same path afterwards and fail with
	/// "pathspec did not match any file(s) known to git" — a git error on screen
	/// for an operation that had already worked.
	@Test func discardingAnUntrackedFileDeletesItAndSaysNothingWentWrong() async throws {
		let root = try makeRepository()
		try await initialise(root)
		try write("brand new\n", to: "Sources/new.txt", in: root)

		let result = await GitWorkingCopy.discard(paths: ["Sources/new.txt"], in: root)
		#expect(result.exitCode == 0)
		#expect(result.stderr.isEmpty)
		#expect(!exists("Sources/new.txt", in: root))
	}

	/// The case that used to lose the tracked half: git validates every pathspec
	/// before restoring anything, so one untracked path in the selection aborted
	/// the whole `checkout` — after `clean` had already deleted the untracked
	/// file. The gesture destroyed what it could and reverted nothing.
	@Test func discardingAMixedSelectionRestoresTheTrackedOnes() async throws {
		let root = try makeRepository()
		try await initialise(root)
		try write("two\n", to: "Sources/tracked.txt", in: root)
		try write("brand new\n", to: "Sources/new.txt", in: root)

		let result = await GitWorkingCopy.discard(
			paths: ["Sources/tracked.txt", "Sources/new.txt"], in: root
		)
		#expect(result.exitCode == 0)
		#expect(read("Sources/tracked.txt", in: root) == "one\n")
		#expect(!exists("Sources/new.txt", in: root))
	}

	/// A folder is one path, and one path is both operations at once.
	@Test func discardingAFolderTakesBothKindsUnderIt() async throws {
		let root = try makeRepository()
		try await initialise(root)
		try write("two\n", to: "Sources/tracked.txt", in: root)
		try write("brand new\n", to: "Sources/deep/new.txt", in: root)

		let result = await GitWorkingCopy.discard(paths: ["Sources"], in: root)
		#expect(result.exitCode == 0)
		#expect(read("Sources/tracked.txt", in: root) == "one\n")
		#expect(!exists("Sources/deep/new.txt", in: root))
		#expect(await GitWorkingCopy.status(in: root).isEmpty)
	}

	/// A folder holding nothing but new files: after `clean` there is no folder
	/// left, and nothing for `checkout` to be asked about.
	@Test func discardingAFolderOfNothingButNewFilesRemovesIt() async throws {
		let root = try makeRepository()
		try await initialise(root)
		try write("a\n", to: "Generated/a.txt", in: root)
		try write("b\n", to: "Generated/b.txt", in: root)

		let result = await GitWorkingCopy.discard(paths: ["Generated"], in: root)
		#expect(result.exitCode == 0)
		#expect(!exists("Generated", in: root))
	}

	/// `clean -fd`, never `-fdx`. Throwing away a folder's changes must not also
	/// take the build output somebody's `.gitignore` keeps out of the way.
	@Test func discardingLeavesIgnoredFilesAlone() async throws {
		let root = try makeRepository()
		try await initialise(root)
		try write("build/\n", to: ".gitignore", in: root)
		await git(["add", "-A"], in: root)
		await git(["commit", "-qm", "ignore"], in: root)
		try write("output\n", to: "build/out.o", in: root)
		try write("two\n", to: "Sources/tracked.txt", in: root)

		await GitWorkingCopy.discard(paths: ["."], in: root)
		#expect(exists("build/out.o", in: root))
		#expect(read("Sources/tracked.txt", in: root) == "one\n")
	}

	/// Discard restores from the *index*, which is why it is not offered on a
	/// staged row: a file staged and then edited again loses only the later
	/// edit, and what is staged is still staged afterwards.
	@Test func discardingAFileStagedAndEditedAgainKeepsWhatIsStaged() async throws {
		let root = try makeRepository()
		try await initialise(root)
		try write("two\n", to: "Sources/tracked.txt", in: root)
		await GitWorkingCopy.stage(paths: ["Sources/tracked.txt"], in: root)
		try write("three\n", to: "Sources/tracked.txt", in: root)

		let result = await GitWorkingCopy.discard(paths: ["Sources/tracked.txt"], in: root)
		#expect(result.exitCode == 0)
		#expect(read("Sources/tracked.txt", in: root) == "two\n")

		let status = await GitWorkingCopy.status(in: root)
		#expect(status.staged.map(\.path) == ["Sources/tracked.txt"])
		#expect(status.unstaged.isEmpty)
	}

	/// An unstaged deletion is a change like any other, and discarding it brings
	/// the file back.
	@Test func discardingADeletionBringsTheFileBack() async throws {
		let root = try makeRepository()
		try await initialise(root)
		try FileManager.default.removeItem(at: root.appendingPathComponent("Sources/tracked.txt"))

		let result = await GitWorkingCopy.discard(paths: ["Sources/tracked.txt"], in: root)
		#expect(result.exitCode == 0)
		#expect(read("Sources/tracked.txt", in: root) == "one\n")
	}
}
