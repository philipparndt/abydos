import Testing
import Foundation
@testable import AbydosKit

/// Splitting porcelain output into the two sides of the index.
struct GitWorkingCopyParseTests {
	@Test func stagedAndUnstagedAreSeparated() {
		let status = GitWorkingCopy.parse(porcelain: """
		M  staged.swift
		 M unstaged.swift
		""")
		#expect(status.staged.map(\.path) == ["staged.swift"])
		#expect(status.unstaged.map(\.path) == ["unstaged.swift"])
	}

	/// The case that makes one combined status a lie: edited, staged, edited
	/// again. The commit would contain the first edit and not the second, so
	/// the file belongs in both lists.
	@Test func aPathCanBeInBothLists() {
		let status = GitWorkingCopy.parse(porcelain: "MM both.swift")
		#expect(status.staged.map(\.path) == ["both.swift"])
		#expect(status.unstaged.map(\.path) == ["both.swift"])
		#expect(status.staged[0].id != status.unstaged[0].id)
	}

	@Test func untrackedFilesAreUnstaged() {
		let status = GitWorkingCopy.parse(porcelain: "?? new.swift")
		#expect(status.unstaged.map(\.kind) == [.untracked])
		#expect(status.staged.isEmpty)
	}

	@Test func codesMapToKinds() {
		let status = GitWorkingCopy.parse(porcelain: """
		A  added.swift
		D  deleted.swift
		M  modified.swift
		T  typechanged.swift
		""")
		#expect(status.staged.map(\.kind) == [.added, .deleted, .modified, .modified])
	}

	/// A conflict is one unresolved path, not a staged change with an unstaged
	/// one beside it — offering to stage half of it would be wrong.
	@Test func conflictsAreOneUnstagedEntry() {
		for codes in ["UU", "AA", "DD", "AU", "UA", "DU", "UD"] {
			let status = GitWorkingCopy.parse(porcelain: "\(codes) conflict.swift")
			#expect(status.staged.isEmpty, "\(codes)")
			#expect(status.unstaged.map(\.kind) == [.conflicted], "\(codes)")
		}
		#expect(GitWorkingCopy.parse(porcelain: "UU x").hasConflicts)
	}

	@Test func quotedPathsAreUnescaped() {
		let status = GitWorkingCopy.parse(porcelain: #"?? "with space.swift""#)
		#expect(status.unstaged.map(\.path) == ["with space.swift"])
	}

	@Test func entriesAreSortedByPath() {
		let status = GitWorkingCopy.parse(porcelain: """
		M  z.swift
		M  a.swift
		""")
		#expect(status.staged.map(\.path) == ["a.swift", "z.swift"])
	}

	@Test func emptyOutputIsAnEmptyStatus() {
		#expect(GitWorkingCopy.parse(porcelain: "").isEmpty)
	}

	@Test func changeExposesNameAndDirectory() {
		let change = GitChange(path: "Sources/App/Main.swift", kind: .modified, isStaged: false)
		#expect(change.name == "Main.swift")
		#expect(change.directory == "Sources/App")
	}
}

/// Message assembly, which decides what history ends up recording.
struct GitCommitMessageTests {
	@Test func subjectAndBodyAreSeparatedByABlankLine() {
		#expect(GitWorkingCopy.message(subject: "Fix it", body: "Because.") == "Fix it\n\nBecause.")
	}

	@Test func anEmptyBodyLeavesJustTheSubject() {
		#expect(GitWorkingCopy.message(subject: "Fix it", body: "   ") == "Fix it")
	}

	/// Two -m flags rather than one embedded newline: git joins them with the
	/// blank line itself.
	@Test func commitUsesOneFlagPerParagraph() {
		let arguments = GitWorkingCopy.commitArguments(subject: "S", body: "B", amend: false)
		#expect(arguments == ["commit", "-m", "S", "-m", "B"])
	}

	@Test func anEmptyBodyContributesNoFlag() {
		#expect(GitWorkingCopy.commitArguments(subject: "S", body: "", amend: false) == ["commit", "-m", "S"])
	}

	@Test func amendComesBeforeTheMessage() {
		let arguments = GitWorkingCopy.commitArguments(subject: "S", body: "", amend: true)
		#expect(arguments == ["commit", "--amend", "-m", "S"])
	}

	@Test func surroundingWhitespaceIsTrimmed() {
		let arguments = GitWorkingCopy.commitArguments(subject: "  S  ", body: "\n B \n", amend: false)
		#expect(arguments == ["commit", "-m", "S", "-m", "B"])
	}
}

/// Against a real repository, because staging is the part where being wrong
/// costs someone their work.
struct GitStagingIntegrationTests {
	private func makeRepository() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-staging-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	private func git(_ arguments: [String], in root: URL) async {
		_ = await GitRepository.run(arguments, in: root)
	}

	private func initialise(_ root: URL) async throws {
		await git(["init", "-q"], in: root)
		await git(["config", "user.email", "test@example.com"], in: root)
		await git(["config", "user.name", "Test"], in: root)
		try "one\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
		await git(["add", "-A"], in: root)
		await git(["commit", "-qm", "initial"], in: root)
	}

	@Test func stagingMovesAFileBetweenTheLists() async throws {
		let root = try makeRepository()
		try await initialise(root)
		try "two\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)

		var status = await GitWorkingCopy.status(in: root)
		#expect(status.unstaged.map(\.path) == ["tracked.txt"])
		#expect(status.staged.isEmpty)

		await GitWorkingCopy.stage(paths: ["tracked.txt"], in: root)
		status = await GitWorkingCopy.status(in: root)
		#expect(status.staged.map(\.path) == ["tracked.txt"])
		#expect(status.unstaged.isEmpty)

		await GitWorkingCopy.unstage(paths: ["tracked.txt"], in: root)
		status = await GitWorkingCopy.status(in: root)
		#expect(status.unstaged.map(\.path) == ["tracked.txt"])
		#expect(status.staged.isEmpty)
	}

	/// Plain `git add` skips a deletion, which would quietly leave it out of the
	/// commit the user thought they had staged.
	@Test func stagingADeletionRecordsIt() async throws {
		let root = try makeRepository()
		try await initialise(root)
		try FileManager.default.removeItem(at: root.appendingPathComponent("tracked.txt"))

		await GitWorkingCopy.stage(paths: ["tracked.txt"], in: root)
		let status = await GitWorkingCopy.status(in: root)
		#expect(status.staged.map(\.kind) == [.deleted])
	}

	@Test func stagingAnUntrackedFileAddsIt() async throws {
		let root = try makeRepository()
		try await initialise(root)
		try "new\n".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

		await GitWorkingCopy.stage(paths: ["new.txt"], in: root)
		let status = await GitWorkingCopy.status(in: root)
		#expect(status.staged.map(\.kind) == [.added])
	}

	@Test func committingClearsTheStagedList() async throws {
		let root = try makeRepository()
		try await initialise(root)
		try "two\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
		await GitWorkingCopy.stage(paths: ["tracked.txt"], in: root)

		let result = await GitWorkingCopy.commit(subject: "Change it", body: "Why.", amend: false, in: root)
		#expect(result.exitCode == 0)

        let status = await GitWorkingCopy.status(in: root)
		#expect(status.isEmpty)

		let message = await GitWorkingCopy.lastCommitMessage(in: root)
		#expect(message?.subject == "Change it")
		#expect(message?.body == "Why.")
	}

	/// Unstaging before the first commit has no HEAD to restore from.
	@Test func unstagingWorksInARepositoryWithNoCommits() async throws {
		let root = try makeRepository()
		await git(["init", "-q"], in: root)
		try "new\n".write(to: root.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
		await GitWorkingCopy.stage(paths: ["new.txt"], in: root)
		#expect(await GitWorkingCopy.status(in: root).staged.count == 1)

		await GitWorkingCopy.unstage(paths: ["new.txt"], in: root)
		let status = await GitWorkingCopy.status(in: root)
		#expect(status.staged.isEmpty)
		#expect(status.unstaged.map(\.kind) == [.untracked])
	}

	@Test func diffsAreProducedForBothSidesAndForUntrackedFiles() async throws {
		let root = try makeRepository()
		try await initialise(root)
		try "two\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
		try "brand new\n".write(to: root.appendingPathComponent("fresh.txt"), atomically: true, encoding: .utf8)

		let unstaged = await GitWorkingCopy.diff(for: "tracked.txt", staged: false, in: root)
		#expect(unstaged.contains("-one"))
		#expect(unstaged.contains("+two"))

		await GitWorkingCopy.stage(paths: ["tracked.txt"], in: root)
		let staged = await GitWorkingCopy.diff(for: "tracked.txt", staged: true, in: root)
		#expect(staged.contains("+two"))

		// An untracked file has nothing to diff against, so git prints nothing
		// unless it is compared with /dev/null explicitly.
		let fresh = await GitWorkingCopy.diff(for: "fresh.txt", staged: false, in: root)
		#expect(fresh.contains("+brand new"))
	}
}
