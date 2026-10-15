import Foundation
import Testing
@testable import AbydosKit

/// Turning a filesystem event into the repositories it made stale.
///
/// The claim is that an event costs one repository and not the estate: 0.01 s
/// against 0.45 s over 200 submodules, on a schedule of dozens a minute.
struct GitEstateRefreshTests {
	private let root = URL(fileURLWithPath: "/tmp/super", isDirectory: true)

	private func estate(_ paths: [String], names: [String: String] = [:]) -> GitEstate {
		GitEstate(
			root: root,
			submodules: paths.map {
				GitSubmodule(path: $0, recordedCommit: "0000000", name: names[$0])
			}
		)
	}

	private func url(_ relative: String) -> URL {
		root.appendingPathComponent(relative)
	}

	@Test func aWriteInOneSubmoduleMakesOneRepositoryStale() {
		let work = GitEstateRefresh.work(
			forChangedPaths: [url("svc-47/src/Main.java")],
			in: estate(["svc-3", "svc-47", "svc-99"])
		)
		#expect(work.submodulePaths == ["svc-47"])
		#expect(!work.superproject)
		#expect(!work.inventory)
	}

	@Test func aWriteInTheSuperprojectMakesOnlyItStale() {
		let work = GitEstateRefresh.work(
			forChangedPaths: [url("Sources/Thing.swift")],
			in: estate(["svc-3", "svc-47"])
		)
		#expect(work.submodulePaths.isEmpty)
		#expect(work.superproject)
	}

	/// A repository with no submodules is an estate of one, and attribution
	/// works the same: a saved file is the superproject stale and nothing
	/// else — not the inventory, which is what the pane used to re-read on
	/// every event because plain repositories were routed around this type
	/// entirely.
	@Test func aPlainRepositoryAttributesToItselfWithoutTheInventory() {
		let work = GitEstateRefresh.work(
			forChangedPaths: [url("Sources/Thing.swift")],
			in: estate([])
		)
		#expect(work.superproject)
		#expect(!work.inventory)
		#expect(work.submodulePaths.isEmpty)
	}

	/// And its `.gitmodules` appearing is the one event that must still ask
	/// for the inventory: the first submodule arriving is invisible otherwise.
	@Test func gitmodulesArrivingInAPlainRepositoryAsksForTheInventory() {
		let work = GitEstateRefresh.work(
			forChangedPaths: [url(".gitmodules")],
			in: estate([])
		)
		#expect(work.inventory)
	}

	/// The layout the two-watcher design rests on: a submodule's refs live under
	/// the superproject's own `.git/modules`, so an event there is about that
	/// submodule and not about the superproject.
	@Test func aRefWrittenUnderModulesBelongsToItsSubmodule() {
		let work = GitEstateRefresh.work(
			forChangedPaths: [url(".git/modules/svc-47/refs/heads")],
			in: estate(["svc-3", "svc-47"])
		)
		#expect(work.submodulePaths == ["svc-47"])
		#expect(!work.superproject)
	}

	/// A submodule moved with `git mv` keeps the name it was added with, so its
	/// git directory and its work tree stop agreeing. Matching on the path would
	/// attribute every ref change in it to nothing at all.
	@Test func aSubmoduleWhoseNameIsNotItsPathIsStillFound() {
		let moved = estate(["dienste/new-place"], names: ["dienste/new-place": "old-name"])
		let work = GitEstateRefresh.work(
			forChangedPaths: [url(".git/modules/old-name/refs/heads")], in: moved
		)
		#expect(work.submodulePaths == ["dienste/new-place"])
	}

	@Test func aNameHoldingSlashesIsStillOneName() {
		let nested = estate(["dienste/svc"], names: ["dienste/svc": "acme/svc"])
		let work = GitEstateRefresh.work(
			forChangedPaths: [url(".git/modules/acme/svc/refs/heads")], in: nested
		)
		#expect(work.submodulePaths == ["dienste/svc"])
	}

	/// A git directory under a name this inventory does not know is a submodule
	/// added or removed since it was read.
	@Test func anUnknownGitDirectoryAsksForTheInventoryAgain() {
		let work = GitEstateRefresh.work(
			forChangedPaths: [url(".git/modules/svc-new/refs/heads")],
			in: estate(["svc-3"])
		)
		#expect(work.inventory)
		#expect(work.submodulePaths.isEmpty)
	}

	@Test func theIndexMovingAsksForTheInventoryAgain() {
		let work = GitEstateRefresh.work(
			forChangedPaths: [url(".git/index")], in: estate(["svc-3"])
		)
		#expect(work.inventory)
		#expect(work.superproject)
	}

	@Test func gitmodulesMovingAsksForTheInventoryAgain() {
		let work = GitEstateRefresh.work(
			forChangedPaths: [url(".gitmodules")], in: estate(["svc-3"])
		)
		#expect(work.inventory)
	}

	/// A watcher that reports directories cannot tell an index write from a ref
	/// write. Re-reading the inventory is 0.01 s, so being conservative there is
	/// affordable; sweeping two hundred repositories would not be.
	@Test func theBareGitDirectoryIsTreatedAsThoughTheIndexMoved() {
		let work = GitEstateRefresh.work(
			forChangedDirectories: [url(".git")], in: estate(["svc-3"])
		)
		#expect(work.inventory)
		#expect(work.superproject)
	}

	@Test func aRefWrittenInTheSuperprojectIsNotAnInventoryChange() {
		let work = GitEstateRefresh.work(
			forChangedDirectories: [url(".git/refs/heads")], in: estate(["svc-3"])
		)
		#expect(work.superproject)
		#expect(!work.inventory)
	}

	/// A watcher can be pointed at a directory that is no longer the project.
	@Test func aPathOutsideTheEstateMakesNothingStale() {
		let work = GitEstateRefresh.work(
			forChangedPaths: [URL(fileURLWithPath: "/tmp/somewhere/else/file.swift")],
			in: estate(["svc-3"])
		)
		#expect(work.isEmpty)
	}

	@Test func manyEventsInOneSubmoduleAreOneRepository() {
		let work = GitEstateRefresh.work(
			forChangedPaths: (0..<50).map { url("svc-47/src/File\($0).java") },
			in: estate(["svc-3", "svc-47"])
		)
		#expect(work.submodulePaths == ["svc-47"])
	}

	@Test func eventsAcrossRepositoriesComeBackInPathOrder() {
		let work = GitEstateRefresh.work(
			forChangedPaths: [url("svc-9/a"), url("svc-3/b"), url("svc-9/c"), url("README.md")],
			in: estate(["svc-3", "svc-9"])
		)
		#expect(work.submodulePaths == ["svc-3", "svc-9"])
		#expect(work.superproject)
	}

	/// A repository with no submodules takes the same path through all of this.
	@Test func aRepositoryWithNoSubmodulesOnlyEverStalesItself() {
		let work = GitEstateRefresh.work(
			forChangedPaths: [url("Sources/Thing.swift"), url("svc-47/src/Main.java")],
			in: estate([])
		)
		#expect(work.superproject)
		#expect(work.submodulePaths.isEmpty)
	}

	// MARK: - A whole batch from the work tree's watcher

	private func change(
		paths: [String] = [],
		rescanned: [String] = [],
		namesEveryPath: Bool? = nil
	) -> FileSystemChange {
		FileSystemChange(
			directories: [],
			paths: paths.map(url),
			namesEveryPath: namesEveryPath ?? rescanned.isEmpty,
			rescanned: rescanned.map { $0.isEmpty ? root : url($0) }
		)
	}

	/// The bug this pins read the flag the wrong way round: a batch whose
	/// paths were all named — every saved file — swept every repository, and
	/// the spec's own scenario for a write in one submodule never held.
	@Test func aNamedBatchIsAttributedAndNotSwept() {
		let work = GitEstateRefresh.work(
			for: change(paths: ["svc-47/src/Main.java"]),
			in: estate(["svc-3", "svc-47", "svc-99"])
		)
		#expect(work == GitEstateRefresh.Work(submodulePaths: ["svc-47"]))
	}

	/// The other half of the same bug: a batch FSEvents could not enumerate
	/// has no paths, so attributing only those made it stale nothing at all.
	@Test func aRescanOfADirectoryInsideASubmoduleMakesThatSubmoduleStale() {
		let work = GitEstateRefresh.work(
			for: change(rescanned: ["svc-47/build"]),
			in: estate(["svc-3", "svc-47"])
		)
		#expect(work == GitEstateRefresh.Work(submodulePaths: ["svc-47"]))
	}

	/// The reproduction: a worktree added under `repos/` is in no submodule
	/// and holds none, so it is the superproject's business and nobody else's.
	@Test func aRescanBesideTheSubmodulesIsTheSuperprojectAlone() {
		let work = GitEstateRefresh.work(
			for: change(rescanned: ["repos/svc-3-wt-x"]),
			in: estate(["repos/svc-3", "repos/svc-47"])
		)
		#expect(work == GitEstateRefresh.Work(superproject: true))
	}

	/// A directory can hold repositories as well as sit in one: every
	/// submodule under it is stale, at any depth, and nothing beside it is.
	@Test func aRescanOfADirectoryHoldingSubmodulesMakesThemStale() {
		let work = GitEstateRefresh.work(
			for: change(rescanned: ["repos"]),
			in: estate(["repos/svc-3", "repos/svc-3/lib/leaf", "tools/gen"])
		)
		#expect(work == GitEstateRefresh.Work(
			superproject: true,
			submodulePaths: ["repos/svc-3", "repos/svc-3/lib/leaf"]
		))
	}

	/// Nested the other way: a scan inside one submodule that holds another.
	@Test func aRescanInsideASubmoduleReachesTheOneNestedBelowIt() {
		let work = GitEstateRefresh.work(
			for: change(rescanned: ["svc-3/lib"]),
			in: estate(["svc-3", "svc-3/lib/leaf"])
		)
		#expect(work == GitEstateRefresh.Work(submodulePaths: ["svc-3", "svc-3/lib/leaf"]))
	}

	/// The root itself — a scan of everything, or the project moving — is the
	/// one rescan that asks about every repository.
	@Test func aRescanOfTheRootIsEverything() {
		let work = GitEstateRefresh.work(
			for: change(rescanned: [""]),
			in: estate(["svc-3"])
		)
		#expect(work.inventory)
	}

	/// Unnamed and with nowhere said is a batch that could be anything.
	@Test func anUnnamedBatchThatSaysNowhereIsEverything() {
		let work = GitEstateRefresh.work(
			for: change(namesEveryPath: false),
			in: estate(["svc-3"])
		)
		#expect(work.inventory)
	}

	/// A batch can name some paths and only say "scan" for others; both count.
	@Test func namedPathsAndRescansInOneBatchAreBothAttributed() {
		let work = GitEstateRefresh.work(
			for: change(paths: ["svc-3/a.swift"], rescanned: ["svc-47/build"]),
			in: estate(["svc-3", "svc-47", "svc-99"])
		)
		#expect(work == GitEstateRefresh.Work(submodulePaths: ["svc-3", "svc-47"]))
	}

	// MARK: - Directories the repository watcher reports

	/// The reproduction's other half: a worktree of a submodule is bookkeeping
	/// under that submodule's git directory, and its business alone.
	@Test func aSubmodulesWorktreeIsThatSubmodulesBusiness() {
		let work = GitEstateRefresh.work(
			forChangedDirectories: [url(".git/modules/repos/svc-1/worktrees/svc-1-wt-x")],
			in: estate(["repos/svc-1", "repos/svc-2"], names: ["repos/svc-1": "repos/svc-1"])
		)
		#expect(work == GitEstateRefresh.Work(submodulePaths: ["repos/svc-1"]))
	}

	/// A worktree of the superproject moves the superproject's refs, and says
	/// nothing about which submodules exist.
	@Test func aSuperprojectWorktreeIsTheSuperprojectAlone() {
		let work = GitEstateRefresh.work(
			forChangedDirectories: [url(".git/worktrees/wt"), url(".git/refs/heads")],
			in: estate(["svc-3"])
		)
		#expect(work == GitEstateRefresh.Work(superproject: true))
	}
}
