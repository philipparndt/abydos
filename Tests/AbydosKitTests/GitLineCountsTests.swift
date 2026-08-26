import Foundation
import Testing
@testable import AbydosKit

/// Reading `--numstat`, against what git actually writes.
///
/// The strings here were taken from `git diff --cached --numstat -z` on a
/// repository built for the purpose — a binary file, a rename with a space in
/// its name, and an ordinary edit — and hexdumped to see where the separators
/// fall. Every one of the three is a case that would have been parsed wrongly by
/// something written from the documentation alone.
struct GitLineCountsTests {
	@Test func anOrdinaryFile() {
		let counts = GitLineCounts.parse("12\t3\tSources/App.swift\0")
		#expect(counts == ["Sources/App.swift": GitLineCount(added: 12, removed: 3)])
	}

	/// Git will not count a binary file and says so with `-` in both columns.
	/// Left out entirely: a row with no counts says nothing, where `0 0` would
	/// claim nothing changed.
	@Test func aBinaryFileHasNoCounts() {
		let counts = GitLineCounts.parse("-\t-\tblob.bin\0")
		#expect(counts.isEmpty)
	}

	/// A rename writes an empty path field and then the two names as records of
	/// their own. The count belongs to the new name, which is the row that
	/// exists — and the space in it is why `-z` is not optional.
	@Test func aRenameCountsAgainstTheNewName() {
		let counts = GitLineCounts.parse("0\t0\t\0renamed me.txt\0now here.txt\0")
		#expect(counts == ["now here.txt": GitLineCount(added: 0, removed: 0)])
		#expect(counts["renamed me.txt"] == nil, "the old name has no row")
	}

	/// The three together, in the order git wrote them.
	@Test func awholeRecordSetIsReadInOnePass() {
		let counts = GitLineCounts.parse(
			"-\t-\tblob.bin\0" + "0\t0\t\0renamed me.txt\0now here.txt\0" + "1\t0\ttracked.txt\0"
		)
		#expect(counts == [
			"now here.txt": GitLineCount(added: 0, removed: 0),
			"tracked.txt": GitLineCount(added: 1, removed: 0),
		], "the binary is absent, the rename is under its new name")
	}

	@Test func aPathWithASpaceKeepsIt() {
		let counts = GitLineCounts.parse("4\t1\tSources/My Folder/A File.swift\0")
		#expect(counts["Sources/My Folder/A File.swift"] == GitLineCount(added: 4, removed: 1))
	}

	@Test func nothingChangedIsNoCounts() {
		#expect(GitLineCounts.parse("").isEmpty)
		#expect(GitLineCounts.parse("\0").isEmpty)
	}

	/// A truncated answer — a killed git, a full pipe — must not be read as a
	/// count against the wrong path.
	@Test func aRecordCutOffMidWayIsDropped() {
		let counts = GitLineCounts.parse("2\t1\tone.txt\0" + "0\t0\t\0half a rename")
		#expect(counts == ["one.txt": GitLineCount(added: 2, removed: 1)])
	}

	@Test func countsAddUp() {
		let sum = GitLineCount(added: 3, removed: 1) + GitLineCount(added: 4, removed: 5)
		#expect(sum == GitLineCount(added: 7, removed: 6))
	}
}
