import Testing
import Foundation
@testable import AbydosKit

/// What the navigator's colouring costs, and what it still answers correctly
/// after being made to cost less.
///
/// The status read runs on every filesystem event, so on a work tree full of
/// build output it ran dozens of times a minute. It used to ask for
/// `-uall --ignored=matching`, and those two flags between them switch off git's
/// untracked cache: four consecutive runs on a repository with 69,829 untracked
/// files took 6.4 s, 16.2 s, 59.7 s and 26.8 s. It never warmed up, because
/// there was no cache to warm.
///
/// These tests pin the two things that made dropping those flags safe — a
/// collapsed directory's contents are still coloured, and a directory's rollup
/// is still the worst thing beneath it — and the schedule that keeps the
/// expensive question off the event path.
struct GitStatusCostTests {
	private func repository(_ porcelain: String) async -> GitRepository {
		let repo = GitRepository(root: URL(fileURLWithPath: "/tmp/fixture"))
		await repo.parse(porcelain: porcelain)
		return repo
	}

	// MARK: - What a collapsed directory says about its contents

	/// `-unormal` answers a wholly untracked directory as one entry. Every row
	/// under it is still untracked — that is *why* git collapsed it — so the
	/// colour comes from the directory rather than from an entry per file.
	@Test func filesInsideACollapsedUntrackedDirectoryAreStillUntracked() async {
		let repo = await repository("?? build/\n")

		#expect(await repo.status(forRelativePath: "build", isDirectory: true) == .unversioned)
		#expect(await repo.status(forRelativePath: "build/classes/App.class", isDirectory: false)
			== .unversioned)
		#expect(await repo.status(forRelativePath: "build/classes", isDirectory: true)
			== .unversioned)
	}

	/// The same for an ignored directory, which is the case that already worked
	/// and had to keep working.
	@Test func filesInsideAnIgnoredDirectoryAreStillIgnored() async {
		let repo = await repository("!! node_modules/\n")

		#expect(await repo.status(forRelativePath: "node_modules/left-pad/index.js", isDirectory: false)
			== .ignored)
	}

	/// The nearest answer wins, not the first one found on the way up. An
	/// ignored directory inside an untracked one is an ordinary shape — a new
	/// project directory with its own `.gitignore` in it.
	@Test func theNearestEnclosingDirectoryDecides() async {
		let repo = await repository("?? fresh/\n!! fresh/build/\n")

		#expect(await repo.status(forRelativePath: "fresh/src/App.java", isDirectory: false)
			== .unversioned)
		#expect(await repo.status(forRelativePath: "fresh/build/App.class", isDirectory: false)
			== .ignored)
	}

	// MARK: - Rollups

	/// A directory is as bad as the worst thing under it, however deep that is.
	///
	/// The answer is the same as before; how it is reached is not. It used to
	/// sweep the whole status cache prefix-matching every key, per directory —
	/// O(rows × changes), synchronously on the actor, which is what everything
	/// else waited behind.
	@Test func aDirectoryTakesTheWorstStatusBeneathIt() async {
		let repo = await repository("""
		?? a/b/new.txt
		 M a/b/c/edited.txt
		UU a/b/c/d/conflicted.txt
		""")

		#expect(await repo.status(forRelativePath: "a/b/c/d", isDirectory: true) == .conflicted)
		#expect(await repo.status(forRelativePath: "a/b/c", isDirectory: true) == .conflicted)
		#expect(await repo.status(forRelativePath: "a/b", isDirectory: true) == .conflicted)
		#expect(await repo.status(forRelativePath: "a", isDirectory: true) == .conflicted)
		// The project's own row, which is the empty path.
		#expect(await repo.status(forRelativePath: "", isDirectory: true) == .conflicted)
	}

	/// A sibling's change does not colour a directory it is not under. The
	/// rollup walks each entry's own ancestors, and an off-by-one there would
	/// spread a change sideways.
	@Test func aChangeDoesNotColourItsSiblings() async {
		let repo = await repository(" M src/touched/file.swift\n")

		#expect(await repo.status(forRelativePath: "src/touched", isDirectory: true) == .modified)
		#expect(await repo.status(forRelativePath: "src/untouched", isDirectory: true) == .unmodified)
		#expect(await repo.status(forRelativePath: "unrelated", isDirectory: true) == .unmodified)
	}

	/// Severity order decides, not the order git happened to list things in.
	@Test func theWorstStatusWinsWhicheverOrderTheyArriveIn() async {
		let worstLast = await repository(" M dir/a.txt\nUU dir/b.txt\n")
		let worstFirst = await repository("UU dir/b.txt\n M dir/a.txt\n")

		#expect(await worstLast.status(forRelativePath: "dir", isDirectory: true) == .conflicted)
		#expect(await worstFirst.status(forRelativePath: "dir", isDirectory: true) == .conflicted)
	}

	/// Still true, and the reason the rollup skips ignored entries: almost every
	/// project keeps build output inside a tracked directory, and dimming those
	/// would grey out most of the tree.
	@Test func ignoredContentsDoNotDimTheDirectoryHoldingThem() async {
		let repo = await repository("!! app/build/\n M app/src/Main.java\n")

		#expect(await repo.status(forRelativePath: "app", isDirectory: true) == .modified)
	}

	// MARK: - The branch, read without waiting for the actor

	/// The branch pill reads the head without a hop onto the actor, so opening
	/// the menu does not queue behind a status parse. It has to be the same
	/// answer.
	@Test func theHeadCanBeReadWithoutTouchingTheActor() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		try await initialise(root)

		let repo = GitRepository(root: root)
		// Before any refresh there is nothing to know, and saying "detached" is
		// how every caller already reads "no branch name to show".
		#expect(repo.lastKnownHead == .detached(nil), "and no commit either")

		await repo.refresh()
		let onTheActor = await repo.currentHead().name
		#expect(repo.lastKnownHead.name == onTheActor)
		#expect(repo.lastKnownHead.name != nil)

		_ = await GitRepository.run(["checkout", "-q", "-b", "sideways"], in: root)
		await repo.refresh()
		#expect(repo.lastKnownHead.name == "sideways")
	}

	// MARK: - When the expensive question is asked

	/// The ignored set is read when the ignore *rules* move, and not when a
	/// build writes a file. That distinction is the whole saving: `--ignored`
	/// cannot use git's untracked cache, so it walks the work tree cold every
	/// time it is asked.
	@Test func theIgnoredSetIsRereadOnlyWhenTheRulesChange() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		try await initialise(root)
		try "*.log\n".write(
			to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8
		)
		_ = await GitRepository.run(["add", "-A"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "ignore logs"], in: root)

		let repo = GitRepository(root: root)
		// Never read, so it is worth reading.
		#expect(await repo.needsIgnoredRefresh())
		await repo.refreshIgnored()
		#expect(!(await repo.needsIgnoredRefresh()))

		// A build writing files is not a change to the rules.
		try "noise\n".write(
			to: root.appendingPathComponent("build.log"), atomically: true, encoding: .utf8
		)
		#expect(!(await repo.needsIgnoredRefresh()),
		        "a file appearing is not a reason to walk the work tree again")

		// Saving the ignore file is.
		try "*.log\n*.tmp\n".write(
			to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8
		)
		#expect(await repo.needsIgnoredRefresh())
	}

	/// **An uncommitted `.gitignore` is still an ignore rule.** Git honours the
	/// file on disk whether or not it has ever been committed, and the first
	/// thing anybody does in a new repository is write one — so the case where
	/// it is untracked is the case a project spends its first hour in.
	///
	/// The fingerprint found the ignore files with `ls-files --cached`, which
	/// lists only tracked ones, so writing rules into an uncommitted
	/// `.gitignore` changed nothing the app could see and the greying-out never
	/// arrived. The comment above it argued that an untracked `.gitignore` needs
	/// no watching, because the directory holding one is itself untracked and
	/// everything under it inherits that. True of a subdirectory. Not true of the
	/// work tree root, which is never untracked — and that is where a project's
	/// `.gitignore` lives.
	@Test func rulesInAnUncommittedGitignoreAreNoticed() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		try await initialise(root)

		try FileManager.default.createDirectory(
			at: root.appendingPathComponent("build"), withIntermediateDirectories: true
		)
		try "x\n".write(
			to: root.appendingPathComponent("build/out.o"), atomically: true, encoding: .utf8
		)

        let repo = GitRepository(root: root)
		await repo.refresh()
		await repo.refreshIgnored()
		#expect(
			await repo.status(forRelativePath: "build", isDirectory: true) == .unversioned,
			"nothing ignores it yet"
		)

		// Written and *not* committed, which is what git honours anyway.
		try "build/\n".write(
			to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8
		)
		await repo.refresh()

		#expect(
			await repo.needsIgnoredRefresh(),
			"an uncommitted .gitignore was saved; the rules have moved"
		)
		await repo.refreshIgnored()
		#expect(
			await repo.status(forRelativePath: "build", isDirectory: true) == .ignored,
			"git ignores it, so the tree should grey it out"
		)
	}

	/// **An ignored directory inside an untracked one is ignored, not untracked.**
	///
	/// The reported fault, and it is about precedence rather than about reading.
	/// `-unormal` collapses the untracked parent to one `project/` entry, and
	/// `--ignored=traditional` still names `project/build/` inside it — so both
	/// answers are in hand. The lookup consulted them in the wrong order: it
	/// walked up to the collapsed ancestor and returned *untracked* before ever
	/// asking whether git had said something about this very path.
	///
	/// So a folder git ignores was drawn in the colour of uncommitted work,
	/// which is the one thing the tint is for.
	@Test func anIgnoredFolderInsideAnUntrackedOneIsGreyNotOrange() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		try await initialise(root)

		// A folder nothing tracks, holding its own ignore rules — a checkout
		// somebody has dropped into the work tree, or a new module.
		let project = root.appendingPathComponent("project")
		try FileManager.default.createDirectory(
			at: project.appendingPathComponent("build"), withIntermediateDirectories: true
		)
		try FileManager.default.createDirectory(
			at: project.appendingPathComponent("src"), withIntermediateDirectories: true
		)
		try "build/\n".write(
			to: project.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8
		)
		try "o\n".write(
			to: project.appendingPathComponent("build/out.o"), atomically: true, encoding: .utf8
		)
		try "s\n".write(
			to: project.appendingPathComponent("src/main.swift"), atomically: true, encoding: .utf8
		)

		let repo = GitRepository(root: root)
		await repo.refresh()
		await repo.refreshIgnored()

		#expect(
			await repo.status(forRelativePath: "project", isDirectory: true) == .unversioned,
			"the folder itself is untracked, which git says and is true"
		)
		#expect(
			await repo.status(forRelativePath: "project/build", isDirectory: true) == .ignored,
			"git named it `!! project/build/`; it is not uncommitted work"
		)
		#expect(
			await repo.status(forRelativePath: "project/build/out.o", isDirectory: false) == .ignored,
			"and what is inside an ignored folder is ignored"
		)
		#expect(
			await repo.status(forRelativePath: "project/src", isDirectory: true) == .unversioned,
			"while a folder git did *not* ignore still inherits from the parent"
		)
	}

	/// And what it reads is used: an ignored file gets its colour from the
	/// separate read, not from the one on the event path.
	@Test func theSeparateReadIsWhatColoursIgnoredFiles() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		try await initialise(root)
		try "*.log\n".write(
			to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8
		)
		_ = await GitRepository.run(["add", "-A"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "ignore logs"], in: root)
		try "noise\n".write(
			to: root.appendingPathComponent("build.log"), atomically: true, encoding: .utf8
		)

		let repo = GitRepository(root: root)
		await repo.refresh()
		// The fast read does not ask about ignored files, so it does not know.
		#expect(await repo.status(forRelativePath: "build.log", isDirectory: false) == .unmodified)

		await repo.refreshIgnored()
		#expect(await repo.status(forRelativePath: "build.log", isDirectory: false) == .ignored)
	}

	/// A folder that stops being ignored stops being grey, which is the fault
	/// the whole-replacement in `refreshIgnored` exists to avoid.
	@Test func aFolderThatStopsBeingIgnoredStopsBeingGrey() async throws {
		let root = try makeRepository()
		defer { try? FileManager.default.removeItem(at: root) }
		try await initialise(root)
		try FileManager.default.createDirectory(
			at: root.appendingPathComponent("out"), withIntermediateDirectories: true
		)
		try "x\n".write(
			to: root.appendingPathComponent("out/thing.txt"), atomically: true, encoding: .utf8
		)
		try "out/\n".write(
			to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8
		)
		_ = await GitRepository.run(["add", ".gitignore"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "ignore out"], in: root)

		let repo = GitRepository(root: root)
		await repo.refresh()
		await repo.refreshIgnored()
		#expect(await repo.status(forRelativePath: "out", isDirectory: true) == .ignored)

		try "\n".write(
			to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8
		)
		#expect(await repo.needsIgnoredRefresh())
		await repo.refresh()
		await repo.refreshIgnored()
		#expect(await repo.status(forRelativePath: "out", isDirectory: true) != .ignored)
	}

	// MARK: - Helpers

	private func makeRepository() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-status-cost-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	private func initialise(_ root: URL) async throws {
		_ = await GitRepository.run(["init", "-q"], in: root)
		_ = await GitRepository.run(["config", "user.email", "test@example.com"], in: root)
		_ = await GitRepository.run(["config", "user.name", "Test"], in: root)
		try "one\n".write(
			to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8
		)
        _ = await GitRepository.run(["add", "-A"], in: root)
		_ = await GitRepository.run(["commit", "-qm", "initial"], in: root)
	}
}
