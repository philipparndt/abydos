import Foundation
import Testing
@testable import AbydosKit

/// What one batch from FSEvents is turned into.
///
/// The names used to be thrown away and only the parent directories kept, which
/// is all the tree needs. 0446 is what that cost everything else: at directory
/// granularity, a language server writing `.classpath` into a bundle and
/// somebody adding a `main` method to a class in the same bundle are the same
/// event, so anything reacting to the second had to react to the first.
struct FileSystemWatcherTests {
	private let root = URL(fileURLWithPath: "/p")

	/// Named `batch` and not `change`, which is what it was. Every test binds
	/// its result to a `change`, and inside `#require` the macro re-expands the
	/// call *after* that binding is in scope — so the local shadowed the helper
	/// and the whole file stopped compiling with "cannot call value of
	/// non-function type 'FileSystemChange'".
	private func batch(
		_ paths: [String],
		flags: [FSEventStreamEventFlags]? = nil
	) -> FileSystemChange? {
		FileSystemWatcher.change(
			from: paths,
			flags: flags ?? Array(repeating: 0, count: paths.count),
			root: root,
			includesGitDirectory: false
		)
	}

	@Test func namesTheFilesAndTheirDirectories() throws {
		let change = try #require(batch([
			"/p/bundle/.classpath",
			"/p/bundle/src/App.java",
		]))

		#expect(Set(change.paths.map(\.path)) == [
			"/p/bundle/.classpath",
			"/p/bundle/src/App.java",
		])
		#expect(Set(change.directories.map(\.path)) == ["/p/bundle", "/p/bundle/src"])
		#expect(change.namesEveryPath)
	}

	/// A burst too large to describe file by file says so, because a filter over
	/// the names would otherwise silently pass a batch it never saw.
	@Test func aSubtreeScanAdmitsItDoesNotKnowTheNames() throws {
		let change = try #require(batch(
			["/p/bundle"],
			flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)]
		))

		#expect(!change.namesEveryPath)
		#expect(change.paths.isEmpty)
		#expect(change.directories.map(\.path) == ["/p/bundle"])
	}

	/// The project moved underneath us, so nothing named in the batch is a
	/// reliable account of what is now where.
	@Test func aMovedRootAdmitsTheSame() throws {
		let change = try #require(batch(
			["/p"],
			flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)]
		))

		#expect(!change.namesEveryPath)
		#expect(change.directories.map(\.path) == ["/p"])
	}

	@Test func skipsTheGitDirectoryAndDesktopServicesFiles() {
		#expect(batch(["/p/.git/index"]) == nil)
		#expect(batch(["/p/.DS_Store"]) == nil)
	}

	/// A batch that is entirely `.git` is nothing at all rather than an empty
	/// batch: an empty one would still cost every listener its guard.
	@Test func aBatchOfNothingIsNotDelivered() {
		#expect(batch([]) == nil)
	}

	/// The directories a scan was asked for are kept apart from the parents of
	/// named files: only the first say "something under here".
	@Test func aSubtreeScanSaysWhereToScan() throws {
		let change = try #require(batch(
			["/p/repos/wt", "/p/README.md"],
			flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs), 0]
		))
		#expect(change.rescanned.map(\.path) == ["/p/repos/wt"])
		#expect(Set(change.directories.map(\.path)) == ["/p/repos/wt", "/p"])
	}

	@Test func theRootMovingIsARescanOfTheRoot() throws {
		let change = try #require(batch(
			["/p"],
			flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)]
		))
		#expect(change.rescanned.map(\.path) == ["/p"])
	}

	// MARK: - Folding batches

	@Test func mergingKeepsEveryPathOnce() throws {
		var change = try #require(batch(["/p/a/one.swift", "/p/a/two.swift"]))
		change.merge(try #require(batch(["/p/a/two.swift", "/p/b/three.swift"])))

		#expect(Set(change.paths.map(\.path)) == ["/p/a/one.swift", "/p/a/two.swift", "/p/b/three.swift"])
		#expect(change.paths.count == 3)
		#expect(Set(change.directories.map(\.path)) == ["/p/a", "/p/b"])
		#expect(change.namesEveryPath)
	}

	/// A merged batch that forgot it could not name its paths would let
	/// everything filtering on `paths` trust a list missing the burst.
	@Test func aBatchThatCouldNotNameItsPathsStaysThatWay() throws {
		var change = try #require(batch(
			["/p/build"], flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)]
		))
		change.merge(try #require(batch(["/p/a.swift"])))
		#expect(!change.namesEveryPath)
		#expect(change.rescanned.map(\.path) == ["/p/build"])

		var named = try #require(batch(["/p/a.swift"]))
		named.merge(change)
		#expect(!named.namesEveryPath)
	}

	/// What makes the watcher deliver once per main-thread turnaround and not
	/// once per batch: the first offer schedules, the rest fold into it.
	@Test func batchesWaitingForTheMainQueueAreDeliveredAsOne() throws {
		let pending = PendingChange()
		#expect(pending.offer(try #require(batch(["/p/a.swift"]))))
		#expect(!pending.offer(try #require(batch(["/p/b.swift"]))))
		#expect(!pending.offer(try #require(batch(["/p/c.swift"]))))

		let delivered = try #require(pending.take())
		#expect(Set(delivered.paths.map(\.path)) == ["/p/a.swift", "/p/b.swift", "/p/c.swift"])
		#expect(pending.take() == nil)
		// And the next batch after a delivery schedules again.
		#expect(pending.offer(try #require(batch(["/p/d.swift"]))))
	}
}
