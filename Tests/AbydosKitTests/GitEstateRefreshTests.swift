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
}
