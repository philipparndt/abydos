import Testing
import Foundation
@testable import AbydosKit

/// Status rules exercised against `git status --porcelain` fixtures, so the
/// navigator's colouring can be checked without creating real repositories.
struct GitStatusTests {
	private func repository(_ porcelain: String) async -> GitRepository {
		let repo = GitRepository(root: URL(fileURLWithPath: "/tmp/fixture"))
		await repo.parse(porcelain: porcelain)
		return repo
	}

	// MARK: - Files

	@Test func mapsPorcelainCodesToStatuses() async {
		let repo = await repository("""
		 M modified.txt
		A  added.txt
		?? untracked.txt
		!! ignored.txt
		 D deleted.txt
		UU conflicted.txt
		""")

		#expect(await repo.status(forRelativePath: "modified.txt", isDirectory: false) == .modified)
		#expect(await repo.status(forRelativePath: "added.txt", isDirectory: false) == .added)
		#expect(await repo.status(forRelativePath: "untracked.txt", isDirectory: false) == .unversioned)
		#expect(await repo.status(forRelativePath: "ignored.txt", isDirectory: false) == .ignored)
		#expect(await repo.status(forRelativePath: "deleted.txt", isDirectory: false) == .deleted)
		#expect(await repo.status(forRelativePath: "conflicted.txt", isDirectory: false) == .conflicted)
		#expect(await repo.status(forRelativePath: "untouched.txt", isDirectory: false) == .unmodified)
	}

	// MARK: - Directory rollups

	/// The regression this file exists for: a tracked directory that merely
	/// *contains* ignored output must not itself render as ignored, or most of a
	/// normal project greys out.
	@Test func directoryContainingIgnoredFilesIsNotItselfIgnored() async {
		let repo = await repository("""
		!! app/build/
		!! app/web/node_modules/
		""")

		#expect(await repo.status(forRelativePath: "app", isDirectory: true) == .unmodified,
		        "a directory holding ignored output must not be dimmed")
		#expect(await repo.status(forRelativePath: "app/web", isDirectory: true) == .unmodified)
		// The ignored directories themselves still report ignored.
		#expect(await repo.status(forRelativePath: "app/build", isDirectory: true) == .ignored)
		#expect(await repo.status(forRelativePath: "app/web/node_modules", isDirectory: true) == .ignored)
	}

	/// A directory that stops being ignored stops being drawn as ignored.
	///
	/// Editing an ignore file changes the status of things that did not
	/// themselves change — `!backlog/` un-ignores two folders nobody touched —
	/// and re-reading the status has to be enough to see it. It was not: the
	/// directory entries were kept across reads rather than replaced, so a
	/// folder that had once been ignored stayed grey for the life of the
	/// project, however many times git was asked.
	@Test func aDirectoryThatStopsBeingIgnoredIsNotStillIgnored() async {
		let repo = await repository("!! .abydos/backlog/\n!! app/build/\n")
		#expect(await repo.status(forRelativePath: ".abydos/backlog", isDirectory: true) == .ignored)

		// The same repository after `!backlog/` was added and saved.
		await repo.parse(porcelain: "!! app/build/\n?? .abydos/backlog/open/0001.md\n")
		#expect(await repo.status(forRelativePath: ".abydos/backlog", isDirectory: true) != .ignored)
		#expect(await repo.status(forRelativePath: ".abydos/backlog/open/0001.md", isDirectory: false)
			== .unversioned)
		// And what is still ignored still is.
		#expect(await repo.status(forRelativePath: "app/build", isDirectory: true) == .ignored)
	}

	@Test func filesInsideAnIgnoredDirectoryInheritIgnored() async {
		let repo = await repository("!! app/build/\n")
		// git does not list files inside an ignored directory, so the status has
		// to be inherited from the nearest ignored ancestor.
		#expect(await repo.status(forRelativePath: "app/build/output.o", isDirectory: false) == .ignored)
		#expect(await repo.status(forRelativePath: "app/build/nested/deep.o", isDirectory: false) == .ignored)
	}

	@Test func directoryTakesMostSevereChildStatus() async {
		let repo = await repository("""
		 M src/a.swift
		?? src/b.swift
		!! src/ignored.log
		""")
		// modified outranks unversioned; ignored is excluded entirely.
		#expect(await repo.status(forRelativePath: "src", isDirectory: true) == .modified)
	}

	@Test func directoryWithOnlyUntrackedChildrenReportsUnversioned() async {
		let repo = await repository("?? new/file.txt\n")
		#expect(await repo.status(forRelativePath: "new", isDirectory: true) == .unversioned)
	}

	@Test func unrelatedDirectoryIsUnmodified() async {
		let repo = await repository(" M src/a.swift\n")
		#expect(await repo.status(forRelativePath: "docs", isDirectory: true) == .unmodified)
	}

	/// Prefix matching must respect path boundaries: "src2" is not inside "src".
	@Test func rollupDoesNotMatchSiblingPrefixes() async {
		let repo = await repository(" M src2/a.swift\n")
		#expect(await repo.status(forRelativePath: "src", isDirectory: true) == .unmodified)
		#expect(await repo.status(forRelativePath: "src2", isDirectory: true) == .modified)
	}

	// MARK: - Path parsing

	@Test func handlesQuotedPaths() async {
		let repo = await repository("""
		 M "file with spaces.txt"
		""")
		#expect(await repo.status(forRelativePath: "file with spaces.txt", isDirectory: false) == .modified)
	}

	// MARK: - Asking for the whole tree at once

	/// The navigator asks for one node at a time, which is one hop onto this
	/// actor and one continuation back per row — thousands of them per refresh,
	/// all landing on the main queue. Asking once has to give exactly the same
	/// answers, in the order they were asked, or the tree colours the wrong rows.
	@Test func manyPathsAtOnceAgreeWithAskingOneAtATime() async {
		let repo = await repository("""
		 M src/a.swift
		?? src/new.swift
		!! build/
		A  docs/guide.md
		""")

		let queries: [(path: String, isDirectory: Bool)] = [
			("", true),
			("src", true),
			("src/a.swift", false),
			("src/new.swift", false),
			("build", true),
			("build/out.o", false),
			("docs", true),
			("docs/guide.md", false),
			("elsewhere", true),
		]

		let together = await repo.statuses(for: queries)
		var separately: [GitFileStatus] = []
		for query in queries {
			separately.append(
				await repo.status(forRelativePath: query.path, isDirectory: query.isDirectory)
			)
		}

		#expect(together == separately)
		// And not vacuously: a run of `.unmodified` would satisfy the line above.
		#expect(together.contains(.modified))
		#expect(together.contains(.ignored))
		#expect(together.count == queries.count)
	}

	@Test func askingForNothingAnswersNothing() async {
		let repo = await repository(" M a.swift\n")
		#expect(await repo.statuses(for: []).isEmpty)
	}
}
