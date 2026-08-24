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
}
