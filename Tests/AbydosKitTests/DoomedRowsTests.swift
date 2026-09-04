import Foundation
import Testing
@testable import AbydosKit

/// The rows a trash has taken but the disk has not.
///
/// Reported as ⌘⌫ doing nothing visible for as long as the trash took, and then
/// as an error on the second press.
struct DoomedRowsTests {
	private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

	/// **A marked row is hidden and its siblings are not.** The whole of what
	/// the tree asks this value.
	@Test func aMarkedRowIsHiddenAndItsSiblingsAreNot() {
		var doomed = DoomedRows()
		doomed.mark([url("/p/src/main.py")])

		#expect(doomed.hides(url("/p/src/main.py")))
		#expect(!doomed.hides(url("/p/src/other.py")))
		#expect(!doomed.hides(url("/p/src")))
	}

	@Test func nothingIsHiddenBeforeAnythingIsMarked() {
		let doomed = DoomedRows()

		#expect(doomed.isEmpty)
		#expect(!doomed.hides(url("/p/src/main.py")))
	}

	/// Two trashes can be out at once, so clearing one leaves the other's rows
	/// away.
	@Test func clearingTwoOfThreeLeavesOne() {
		var doomed = DoomedRows()
		doomed.mark([url("/p/a.txt"), url("/p/b.txt"), url("/p/c.txt")])
		doomed.clear([url("/p/a.txt"), url("/p/b.txt")])

		#expect(!doomed.hides(url("/p/a.txt")))
		#expect(!doomed.hides(url("/p/b.txt")))
		#expect(doomed.hides(url("/p/c.txt")))
		#expect(!doomed.isEmpty)
	}

	@Test func clearingTheLastOneEmptiesIt() {
		var doomed = DoomedRows()
		doomed.mark([url("/p/a.txt")])
		doomed.clear([url("/p/a.txt")])

		#expect(doomed.isEmpty)
	}

	/// **The same file named two ways is one row.** The URLs come from two
	/// places — a node the directory read built and a path a flag or a
	/// completion carried — and a trailing slash or a `/private` prefix is how
	/// they differ.
	@Test func oneFileNamedTwoWaysIsOneRow() {
		var doomed = DoomedRows()
		doomed.mark([url("/tmp/proj/src/../src/main.py")])

		#expect(doomed.hides(url("/tmp/proj/src/main.py")))
	}

	/// Three files in two folders are two re-reads, not three.
	@Test func theParentsOfThreeFilesInTwoFoldersAreTwoFolders() {
		let parents = DoomedRows.parents(of: [
			url("/p/src/main.py"), url("/p/src/other.py"), url("/p/docs/read.md"),
		])

		#expect(parents.map(\.lastPathComponent) == ["src", "docs"])
	}

	/// A folder's parent is the folder above it, which is the row the trash
	/// takes it out of — the case the watcher never handled, because a folder
	/// nobody expanded is a directory the tree never listed.
	@Test func aFoldersParentIsTheFolderAboveIt() {
		let parents = DoomedRows.parents(of: [url("/p/src/generated")])

		#expect(parents.map(\.path) == ["/p/src"])
	}

	@Test func theParentsOfNothingAreNoFolders() {
		#expect(DoomedRows.parents(of: []).isEmpty)
	}
}
