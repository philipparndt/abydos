import Foundation
import Testing
@testable import AbydosKit

/// Deciding which project a directory belongs to.
struct ProjectRootTests {
	private func makeTree() -> URL {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("roots-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		return base
	}

	private func directory(_ url: URL) {
		try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
	}

	private func gitDirectory(at url: URL) {
		directory(url.appendingPathComponent(".git"))
	}

	private func gitFile(at url: URL, pointingTo target: String) {
		directory(url)
		try? "gitdir: \(target)\n".write(
			to: url.appendingPathComponent(".git"), atomically: true, encoding: .utf8
		)
	}

	@Test func aRepositoryIsItsOwnProject() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let repo = base.appendingPathComponent("repo")
		directory(repo.appendingPathComponent("src/deep"))
		gitDirectory(at: repo)

		#expect(ProjectRoot.find(from: repo)?.path == repo.path)
		#expect(ProjectRoot.find(from: repo.appendingPathComponent("src/deep"))?.path == repo.path)
	}

	@Test func aDirectoryOutsideAnyRepositoryHasNoProject() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let loose = base.appendingPathComponent("loose/deeper")
		directory(loose)
		#expect(ProjectRoot.find(from: loose) == nil)
	}

	/// The point of the rule: you step into a submodule to change something
	/// about the project you were already in.
	@Test func aSubmoduleBelongsToTheRepositoryAroundIt() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let repo = base.appendingPathComponent("repo")
		gitDirectory(at: repo)
		let sub = repo.appendingPathComponent("vendor/thing")
		gitFile(at: sub, pointingTo: "../../.git/modules/vendor/thing")
		directory(sub.appendingPathComponent("src"))

		#expect(ProjectRoot.find(from: sub)?.path == repo.path)
		#expect(ProjectRoot.find(from: sub.appendingPathComponent("src"))?.path == repo.path)
	}

	@Test func aSubmoduleInsideASubmoduleStillBelongsToTheOutermost() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let repo = base.appendingPathComponent("repo")
		gitDirectory(at: repo)
		let outer = repo.appendingPathComponent("a")
		gitFile(at: outer, pointingTo: "../.git/modules/a")
		let inner = outer.appendingPathComponent("b")
		gitFile(at: inner, pointingTo: "../../.git/modules/a/modules/b")

		#expect(ProjectRoot.find(from: inner)?.path == repo.path)
	}

	/// A linked worktree is somewhere you work, not part of what contains it.
	@Test func aWorktreeIsItsOwnProject() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let worktree = base.appendingPathComponent("feature-branch")
		gitFile(at: worktree, pointingTo: "/somewhere/main/.git/worktrees/feature-branch")
		directory(worktree.appendingPathComponent("src"))

		#expect(ProjectRoot.find(from: worktree)?.path == worktree.path)
		#expect(ProjectRoot.find(from: worktree.appendingPathComponent("src"))?.path == worktree.path)
	}

	/// A repository checked out inside another is not a submodule of it.
	@Test func aNestedRepositoryIsTheNearestOne() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let outer = base.appendingPathComponent("outer")
		gitDirectory(at: outer)
		let inner = outer.appendingPathComponent("vendor/other")
		directory(inner)
		gitDirectory(at: inner)

		#expect(ProjectRoot.find(from: inner)?.path == inner.path)
	}

	/// An unreadable or unfamiliar pointer stops where it is rather than
	/// climbing out of the project the user meant.
	@Test func anUnrecognisedPointerStandsAlone() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let repo = base.appendingPathComponent("repo")
		gitDirectory(at: repo)
		let odd = repo.appendingPathComponent("odd")
		gitFile(at: odd, pointingTo: "/somewhere/else/entirely")

		#expect(ProjectRoot.find(from: odd)?.path == odd.path)
	}

	@Test func theRootDirectoryDoesNotLoop() {
		#expect(ProjectRoot.find(from: URL(fileURLWithPath: "/")) == nil)
	}

	// MARK: - Working copies that are not git

	@Test func aMercurialCheckoutIsItsOwnProject() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let repo = base.appendingPathComponent("repo")
		directory(repo.appendingPathComponent(".hg"))
		directory(repo.appendingPathComponent("src/deep"))

		#expect(ProjectRoot.find(from: repo.appendingPathComponent("src/deep"))?.path
			== repo.path)
	}

	/// Subversion 1.7 and later: one `.svn` at the root, with `wc.db` in it.
	@Test func aSubversionWorkingCopyIsFoundFromInsideIt() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let workingCopy = base.appendingPathComponent("wc")
		subversionRoot(at: workingCopy)
		directory(workingCopy.appendingPathComponent("trunk/src"))

		#expect(ProjectRoot.find(from: workingCopy.appendingPathComponent("trunk/src"))?.path
			== workingCopy.path)
	}

	/// Before 1.7 every directory had a `.svn`, so the nearest one is the
	/// directory the shell is standing in and the root is the topmost of the run.
	@Test func aWorkingCopyWithMetadataInEveryDirectoryIsFoundAtItsTop() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let workingCopy = base.appendingPathComponent("wc")
		for path in ["", "trunk", "trunk/src"] {
			let directoryURL = path.isEmpty
				? workingCopy : workingCopy.appendingPathComponent(path)
			oldLayoutSubversionDirectory(at: directoryURL)
		}

		#expect(ProjectRoot.find(from: workingCopy.appendingPathComponent("trunk/src"))?.path
			== workingCopy.path)
	}

	/// The run of old-layout metadata must be answered before the climb reaches
	/// a repository above it, or the working copy is lost inside that repository.
	@Test func anOldLayoutWorkingCopyInsideARepositoryIsStillItsOwnProject() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let repo = base.appendingPathComponent("repo")
		gitDirectory(at: repo)
		let workingCopy = repo.appendingPathComponent("vendor/wc")
		oldLayoutSubversionDirectory(at: workingCopy)
		oldLayoutSubversionDirectory(at: workingCopy.appendingPathComponent("src"))

		#expect(ProjectRoot.find(from: workingCopy.appendingPathComponent("src"))?.path
			== workingCopy.path)
	}

	@Test func aWorkingCopyCheckedOutInsideAnotherIsTheNearestOne() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let outer = base.appendingPathComponent("outer")
		subversionRoot(at: outer)
		let inner = outer.appendingPathComponent("inner")
		subversionRoot(at: inner)
		directory(inner.appendingPathComponent("src"))

		#expect(ProjectRoot.find(from: inner.appendingPathComponent("src"))?.path
			== inner.path)
	}

	/// Not a mark version control left: this application's own note that
	/// somebody opened the folder as a project.
	@Test func aFolderSomebodyOpenedIsItsOwnProject() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let folder = base.appendingPathComponent("notes")
		directory(folder.appendingPathComponent(AbydosFolder.name))
		directory(folder.appendingPathComponent("data"))

		#expect(ProjectRoot.find(from: folder.appendingPathComponent("data"))?.path
			== folder.path)
	}

	@Test func theFolderTheAppUsedToWriteCountsTheSameWay() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let folder = base.appendingPathComponent("notes")
		directory(folder.appendingPathComponent(AbydosFolder.previousName))

		#expect(ProjectRoot.find(from: folder)?.path == folder.path)
	}

	/// Somebody who opens a submodule deliberately meant it, which is why this
	/// one mark is asked about before `.git`.
	@Test func aSubmoduleSomebodyOpenedIsItsOwnProjectAfterAll() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }

		let repo = base.appendingPathComponent("repo")
		gitDirectory(at: repo)
		let sub = repo.appendingPathComponent("vendor/thing")
		gitFile(at: sub, pointingTo: "../../.git/modules/vendor/thing")
		directory(sub.appendingPathComponent(AbydosFolder.name))

		#expect(ProjectRoot.find(from: sub)?.path == sub.path)
	}

	// MARK: - Helpers for the working copies above

	private func subversionRoot(at url: URL) {
		let metadata = url.appendingPathComponent(".svn")
		directory(metadata)
		try? Data().write(to: metadata.appendingPathComponent("wc.db"))
	}

	private func oldLayoutSubversionDirectory(at url: URL) {
		directory(url.appendingPathComponent(".svn"))
	}
}

/// What a window does about the directory its terminal is in.
///
/// Three pairs matter. A shell sitting still inside a project that is a
/// subdirectory of a checkout, and a shell that really walks out of it — 0509 was
/// the first of the two being read as the second. A shell in a folder that is in
/// no working copy, which used to move the window nowhere and say nothing about
/// why. And a shell in a working directory that has been deleted underneath it,
/// which is 0534.
struct WhereToFollowTests {
	private func makeTree() -> URL {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("follow-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		return base
	}

	private func directory(_ url: URL) {
		try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
	}

	/// A repository with a package inside it, and the package opened as the
	/// project — `abydos-examples/cadova-models`, which is where this was found.
	private func makeCheckout(_ base: URL) -> (repo: URL, package: URL) {
		let repo = base.appendingPathComponent("checkout")
		directory(repo.appendingPathComponent(".git"))
		let package = repo.appendingPathComponent("models")
		directory(package.appendingPathComponent("Sources"))
		return (repo, package)
	}

	/// A root, as a directory URL of the shape `ProjectRoot` answers with.
	///
	/// `URL` equality counts the trailing slash, so the same directory built by
	/// `appendingPathComponent` and by the climb inside `find` compares unequal
	/// while the two paths are identical. Both sides are said the same way here.
	private func at(_ url: URL) -> URL {
		URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
	}

	@Test func aShellSittingInTheProjectIsNotAMove() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let (_, package) = makeCheckout(base)

		#expect(ProjectRoot.whereToFollow(from: package, showing: .project(package)) == .stay)
	}

	/// The same rule the whole-repository case has always had, which is the one
	/// the subdirectory project was missing.
	@Test func aShellDeeperInTheProjectIsNotAMove() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let (repo, package) = makeCheckout(base)
		let sources = package.appendingPathComponent("Sources")

		#expect(ProjectRoot.whereToFollow(from: sources, showing: .project(package)) == .stay)
		#expect(ProjectRoot.whereToFollow(from: sources, showing: .project(repo)) == .stay)
	}

	/// `cd ..` out of the package and into the checkout around it. A real move,
	/// and still followed — the fix for 0509 must not cost this.
	@Test func aShellThatStepsOutIntoTheRepositoryIsFollowed() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let (repo, package) = makeCheckout(base)

		#expect(ProjectRoot.whereToFollow(from: repo, showing: .project(package))
			== .project(at(repo)))
	}

	@Test func aShellInAnotherCheckoutIsFollowed() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let (_, package) = makeCheckout(base)
		let other = base.appendingPathComponent("elsewhere")
		directory(other.appendingPathComponent(".git"))
		directory(other.appendingPathComponent("src"))

		#expect(ProjectRoot.whereToFollow(
			from: other.appendingPathComponent("src"), showing: .project(package))
			== .project(at(other)))
	}

	/// A window that is on nothing yet follows whatever the shell is in.
	@Test func aWindowOnNoProjectFollowsTheRepository() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let (repo, package) = makeCheckout(base)

		#expect(ProjectRoot.whereToFollow(from: package, showing: .nothing)
			== .project(at(repo)))
	}

	/// A sibling directory in the same checkout is outside the project, so it is
	/// a move — to the checkout, which is the project that contains it.
	@Test func aSiblingPackageWidensToTheCheckout() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let (repo, package) = makeCheckout(base)
		let sibling = repo.appendingPathComponent("other")
		directory(sibling)

		#expect(ProjectRoot.whereToFollow(from: sibling, showing: .project(package))
			== .project(at(repo)))
	}

	// MARK: - Folders that are in no working copy

	/// **Off unless it is asked for.** Following between projects moves the
	/// window when somebody goes to another piece of work; following into a
	/// folder in no working copy moves it whenever they go anywhere, there
	/// being no repository to say the walk was over. Two appetites, and the
	/// second is the one somebody has to choose.
	@Test func aFolderInNoWorkingCopyIsNotFollowedIntoByDefault() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let (_, package) = makeCheckout(base)
		let loose = base.appendingPathComponent("loose")
		directory(loose)

		#expect(ProjectRoot.whereToFollow(from: loose, showing: .project(package)) == .stay)
		#expect(ProjectRoot.whereToFollow(from: loose, showing: .nothing) == .stay)
	}

	/// This used to leave the window where it was, which is what the change
	/// replaces: a shell in a folder of notes moved the window nowhere and
	/// nothing said why.
	@Test func aShellInAFolderOutsideAnyWorkingCopyIsFollowedToTheFolder() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let (_, package) = makeCheckout(base)
		let loose = base.appendingPathComponent("loose")
		directory(loose)

		#expect(ProjectRoot.whereToFollow(
			from: loose, showing: .project(package), intoLooseFolders: true
		) == .looseFolder(at(loose)))
	}

	/// The folder itself, and not the directory above it: there is no marker to
	/// climb to, so where the shell is is the answer.
	@Test func aShellDeepInSuchAFolderIsFollowedToWhereItIs() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let deep = base.appendingPathComponent("notes/2026")
		directory(deep)

		#expect(ProjectRoot.whereToFollow(
			from: deep, showing: .nothing, intoLooseFolders: true
		) == .looseFolder(at(deep)))
	}

	/// Moving between two of them is a move. The containment rule is about a
	/// project, and a folder is not one — a window that stayed would leave the
	/// tree naming a directory the shell had left.
	@Test func aShellMovingBetweenTwoSuchFoldersIsFollowed() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let notes = base.appendingPathComponent("notes")
		let deeper = notes.appendingPathComponent("2026")
		directory(deeper)

		#expect(ProjectRoot.whereToFollow(
			from: deeper, showing: .looseFolder(notes), intoLooseFolders: true
		) == .looseFolder(at(deeper)))
		#expect(ProjectRoot.whereToFollow(
			from: notes, showing: .looseFolder(deeper), intoLooseFolders: true
		) == .looseFolder(at(notes)))

		// And with the option off, a window already showing one stays on it
		// rather than walking with the shell.
		#expect(ProjectRoot.whereToFollow(from: deeper, showing: .looseFolder(notes)) == .stay)
	}

	@Test func aShellSittingStillInSuchAFolderIsNotAMove() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let notes = base.appendingPathComponent("notes")
		directory(notes)

		#expect(ProjectRoot.whereToFollow(from: notes, showing: .looseFolder(notes)) == .stay)
	}

	/// A folder somebody opened by hand is a project, marker or no marker, so
	/// the rule that protects a project's tabs protects this one's.
	@Test func aShellInsideAFolderOpenedAsAProjectIsNotAMove() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let notes = base.appendingPathComponent("notes")
		let data = notes.appendingPathComponent("data")
		directory(data)

		#expect(ProjectRoot.whereToFollow(from: data, showing: .project(notes)) == .stay)
	}

	/// A shell in a Subversion working copy is followed to the working copy, the
	/// way a shell in a checkout is followed to the checkout.
	@Test func aShellInAWorkingCopyIsFollowedToItsRoot() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let workingCopy = base.appendingPathComponent("wc")
		let metadata = workingCopy.appendingPathComponent(".svn")
		directory(metadata)
		try? Data().write(to: metadata.appendingPathComponent("wc.db"))
		directory(workingCopy.appendingPathComponent("trunk/src"))

		#expect(ProjectRoot.whereToFollow(
			from: workingCopy.appendingPathComponent("trunk/src"), showing: .nothing)
			== .project(at(workingCopy)))
	}

	// MARK: - A working copy inside the project

	/// The trap `.abydos` sets without this: a folder opened at the home
	/// directory marks it for ever, and every checkout underneath it then counts
	/// as inside the project, so no `cd` moves the window again.
	@Test func aCheckoutInsideTheProjectIsAMoveIntoIt() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let wide = base.appendingPathComponent("wide")
		directory(wide.appendingPathComponent(AbydosFolder.name))
		let inner = wide.appendingPathComponent("dev/checkout")
		directory(inner.appendingPathComponent(".git"))
		directory(inner.appendingPathComponent("src"))

		#expect(ProjectRoot.whereToFollow(
			from: inner.appendingPathComponent("src"), showing: .project(wide))
			== .project(at(inner)))
	}

	/// And the case it must not cost: the checkout a package sits *in* is above
	/// the project, not inside it, so a shell that has not moved stays put. 0509.
	@Test func theCheckoutAroundTheProjectIsStillNotAMove() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let (_, package) = makeCheckout(base)

		#expect(ProjectRoot.whereToFollow(
			from: package.appendingPathComponent("Sources"), showing: .project(package))
			== .stay)
	}

	/// A submodule belongs to the repository around it, so stepping into one is
	/// not stepping into a project of its own — with or without the rule above.
	@Test func aSubmoduleInsideTheProjectIsNotAMove() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let repo = base.appendingPathComponent("repo")
		directory(repo.appendingPathComponent(".git"))
		let sub = repo.appendingPathComponent("vendor/thing")
		directory(sub)
		let pointer = "gitdir: ../../.git/modules/vendor/thing"
		try? pointer.write(
			to: sub.appendingPathComponent(".git"), atomically: true, encoding: .utf8
		)

		#expect(ProjectRoot.whereToFollow(from: sub, showing: .project(repo)) == .stay)
	}

	// MARK: - A directory that is not there

	/// 0534: a shell can be sitting in a working directory that has been deleted
	/// underneath it, and the path it reports then names nothing.
	@Test func aDeletedWorkingDirectoryIsNotFollowed() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let (_, package) = makeCheckout(base)
		let gone = base.appendingPathComponent("gone")

		#expect(ProjectRoot.whereToFollow(from: gone, showing: .project(package)) == .stay)
	}

	/// And asked before the climb, or the repository that used to contain it
	/// answers for it and the window moves somewhere nobody named.
	@Test func aDeletedDirectoryInsideARepositoryIsNotFollowedToTheRepository() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let (repo, _) = makeCheckout(base)
		let gone = repo.appendingPathComponent("was-here")

		#expect(ProjectRoot.whereToFollow(from: gone, showing: .nothing) == .stay)
	}

	/// A file is not a directory, and a window cannot show one as its root.
	@Test func aPathThatNamesAFileIsNotFollowed() {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let file = base.appendingPathComponent("notes.txt")
		try? "hello\n".write(to: file, atomically: true, encoding: .utf8)

		#expect(ProjectRoot.whereToFollow(from: file, showing: .nothing) == .stay)
	}
}

/// What `ideai <path>` opens.
struct ProjectForAPathTests {
	private func makeRepository() throws -> URL {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("cli-\(UUID().uuidString)")
		let source = base.appendingPathComponent("cmd/app")
		try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(
			at: base.appendingPathComponent(".git"), withIntermediateDirectories: true
		)
		try "package main\n".write(
			to: source.appendingPathComponent("main.go"), atomically: true, encoding: .utf8
		)
		return base
	}

	/// Naming a file deep in a repository opens the repository, not the folder
	/// the file happens to sit in.
	@Test func aFileOpensTheRepositoryAroundIt() throws {
		let base = try makeRepository()
		defer { try? FileManager.default.removeItem(at: base) }

		let file = base.appendingPathComponent("cmd/app/main.go")
		#expect(Project.root(containing: file).path == base.standardizedFileURL.path)
	}

	@Test func aDirectoryInsideARepositoryOpensTheRepository() throws {
		let base = try makeRepository()
		defer { try? FileManager.default.removeItem(at: base) }

		#expect(Project.root(containing: base.appendingPathComponent("cmd")).path
			== base.standardizedFileURL.path)
	}

	/// A file with no repository around it still opens something: the folder
	/// it is in.
	@Test func aLooseFileOpensItsOwnFolder() throws {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("loose-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: base) }

		let file = base.appendingPathComponent("notes.txt")
		try "hello\n".write(to: file, atomically: true, encoding: .utf8)
		#expect(Project.root(containing: file).path == base.standardizedFileURL.path)
	}

	/// The improvement `find` gaining `.svn` gives this for nothing: a file in a
	/// working copy opens the working copy rather than the folder it sits in,
	/// which is what it has always done for a checkout.
	@Test func aFileInAWorkingCopyOpensTheWorkingCopy() throws {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("wc-\(UUID().uuidString)")
		let metadata = base.appendingPathComponent(".svn")
		try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
		try Data().write(to: metadata.appendingPathComponent("wc.db"))
		let source = base.appendingPathComponent("trunk/src")
		try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: base) }

		let file = source.appendingPathComponent("main.c")
		try "int main(void) { return 0; }\n".write(to: file, atomically: true, encoding: .utf8)
		#expect(Project.root(containing: file).path == base.standardizedFileURL.path)
	}
}

/// What a project is when it is a folder somebody walked into.
struct LooseFolderProjectTests {
	@Test func anExplicitlyOpenedFolderIsAProject() {
		let folder = URL(fileURLWithPath: "/tmp/notes")
		#expect(Project(root: folder).isLooseFolder == false)
	}

	@Test func aFolderTheWindowFollowedIntoIsNotAProject() {
		let folder = URL(fileURLWithPath: "/tmp/notes")
		#expect(Project(root: folder, isLooseFolder: true).isLooseFolder)
	}
}

/// What a folder remembers, and where.
struct FolderSessionTests {
	private func makeTree() -> URL {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("folder-session-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		return base
	}

	private func session(file path: String) -> ProjectSession {
		ProjectSession(files: [ProjectSession.OpenFile(path: path, line: 7)])
	}

	/// The whole point of the shared file: a folder somebody walked through must
	/// not come away with a `.abydos` in it.
	@Test func writingAFoldersSessionLeavesNothingBesideTheFolder() throws {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let folder = base.appendingPathComponent("notes")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let shared = base.appendingPathComponent("shared.json")

		try SessionStore.write(
			session(file: "/a/b.swift"), in: nil, driven: false, sharedFile: shared
		)

		#expect(FileManager.default.fileExists(atPath: shared.path))
		#expect(!AbydosFolder.exists(in: folder))
	}

	@Test func everyFolderReadsTheOneSession() throws {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let shared = base.appendingPathComponent("shared.json")

		try SessionStore.write(
			session(file: "/a/todo.md"), in: nil, driven: false, sharedFile: shared
		)
		let read = try #require(SessionStore.read(in: nil, driven: false, sharedFile: shared))

		#expect(read.files.map(\.path) == ["/a/todo.md"])
		#expect(read.files.first?.line == 7)
	}

	/// A project's own session still goes beside the project, which is the half
	/// of this that must not change.
	@Test func aProjectStillKeepsItsSessionBesideItself() throws {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let shared = base.appendingPathComponent("shared.json")

		try SessionStore.write(
			session(file: "/a/b.swift"), in: base, driven: false, sharedFile: shared
		)

		#expect(AbydosFolder.exists(in: base))
		#expect(!FileManager.default.fileExists(atPath: shared.path))
	}

	/// A folder is not set up to do anything, so a shell in one is a shell
	/// somebody is using rather than one the folder came with.
	@Test func aFoldersSessionCarriesTheFilesAndNotTheTerminals() throws {
		let base = makeTree()
		defer { try? FileManager.default.removeItem(at: base) }
		let shared = base.appendingPathComponent("shared.json")

		var full = session(file: "/a/b.swift")
		full.terminals = [ProjectSession.OpenTerminal(name: "zsh", directory: "/a")]
		full.tmuxWindow = "3"
		full.selectedConfiguration = "run"
		full.subprojectPath = "sub"
		try SessionStore.write(full, in: nil, driven: false, sharedFile: shared)

		let read = try #require(SessionStore.read(in: nil, driven: false, sharedFile: shared))
		#expect(read.files.map(\.path) == ["/a/b.swift"])
		#expect(read.terminals.isEmpty)
		#expect(read.tmuxWindow == nil)
		#expect(read.selectedConfiguration == nil)
		#expect(read.subprojectPath == nil)
	}

	/// The stripping is one expression, so it is worth its own claim: a project's
	/// session keeps everything a folder's loses.
	@Test func onlyTheFilesSurviveTheStripping() {
		var full = session(file: "/a/b.swift")
		full.activePath = "/a/b.swift"
		full.isPanelVisible = true
		full.terminals = [ProjectSession.OpenTerminal(name: "zsh", directory: "/a")]
		full.tmuxWindow = "3"
		full.selectedConfiguration = "run"
		full.subprojectPath = "sub"
		full.breakpoints = ["/a/b.swift": []]
		full.xcodeDestinations = ["scheme": "id"]

		let only = full.filesOnly
		#expect(only.files == full.files)
		#expect(only.activePath == "/a/b.swift")
		#expect(only.isPanelVisible)
		#expect(only.terminals.isEmpty)
		#expect(only.tmuxWindow == nil)
		#expect(only.selectedConfiguration == nil)
		#expect(only.subprojectPath == nil)
		#expect(only.breakpoints.isEmpty)
		#expect(only.xcodeDestinations.isEmpty)
	}
}
