import Testing
import Foundation
@testable import AbydosKit

/// Two texts aligned line by line, and the marks inside a changed pair.
struct TextDiffTests {
	@Test func aLineAddedInTheMiddleIsOneChange() {
		let diff = TextDiff("one\ntwo\nthree\n", "one\ntwo\ntwo point five\nthree\n")
		#expect(diff.rows.map(\.kind) == [.equal, .equal, .rightOnly, .equal])
		#expect(diff.changes.count == 1)
		#expect(diff.changes[0].kind == .added)
		#expect(diff.changes[0].rows == 2..<3)
		#expect(diff.counts == TextDiff.Counts(additions: 1, deletions: 0, changes: 0))
		#expect(diff.counts.said == "1 Addition, 0 Deletions, 0 Changes")
	}

	@Test func aLineRemovedIsOneChange() {
		let diff = TextDiff("a\nb\nc\n", "a\nc\n")
		#expect(diff.rows.map(\.kind) == [.equal, .leftOnly, .equal])
		#expect(diff.changes.map(\.kind) == [.removed])
		#expect(diff.rows[1].left == 1)
		#expect(diff.rows[1].right == nil)
	}

	@Test func aReplacedLineIsPairedWithItsReplacement() {
		let diff = TextDiff("a\nb\nc\n", "a\nB\nc\n")
		#expect(diff.rows.map(\.kind) == [.equal, .changed, .equal])
		#expect(diff.rows[1].left == 1)
		#expect(diff.rows[1].right == 1)
		#expect(diff.changes.map(\.kind) == [.changed])
		#expect(diff.counts.changes == 1)
	}

	@Test func aRunOfRemovalsPairsWithTheRunOfAdditionsAfterIt() {
		let diff = TextDiff("a\nx1\nx2\nx3\nz\n", "a\ny1\ny2\nz\n")
		#expect(diff.rows.map(\.kind) == [.equal, .changed, .changed, .leftOnly, .equal])
		#expect(diff.changes.count == 1)
		#expect(diff.changes[0].leftLines == 1..<4)
		#expect(diff.changes[0].rightLines == 1..<3)
	}

	@Test func aCommaAddedIsMarkedAsACommaAndNotAParagraph() {
		let left = "Build here push into a development pod"
		let right = "Build here, push into a development pod"
		let diff = TextDiff(left + "\n", right + "\n")
		#expect(diff.rows.count == 1)
		#expect(diff.rows[0].kind == .changed)
		#expect(diff.rows[0].leftMarks == [])
		#expect(diff.rows[0].rightMarks == [10..<11])
	}

	@Test func aLineReplacedWholesaleIsColouredWhole() {
		let diff = TextDiff("let text = try String(contentsOf: url)\n", "#!/bin/zsh -f\n")
		#expect(diff.rows[0].kind == .changed)
		#expect(diff.rows[0].leftMarks == nil)
		#expect(diff.rows[0].rightMarks == nil)
	}

	@Test func twoIdenticalFilesHaveNoChanges() {
		let text = (1...50).map { "line \($0)" }.joined(separator: "\n") + "\n"
		let diff = TextDiff(text, text)
		#expect(diff.changes.isEmpty)
		#expect(diff.rows.allSatisfy { $0.kind == .equal })
		#expect(diff.counts.said == "0 Additions, 0 Deletions, 0 Changes")
		// Nothing folds when there is no change to start on.
		#expect(diff.shown(opened: []).count == 50)
	}

	@Test func aMinifiedLineIsNotDiffedByCharacter() {
		let long = String(repeating: "a", count: TextDiff.intralineLimit + 1)
		let diff = TextDiff(long + "\n", long + "b\n")
		#expect(diff.rows[0].kind == .changed)
		#expect(diff.rows[0].leftMarks == nil)
	}

	@Test func aTrailingNewlineIsNotAnExtraLine() {
		#expect(TextDiff.lines(of: "a\nb\n") == ["a", "b"])
		#expect(TextDiff.lines(of: "a\nb") == ["a", "b"])
		#expect(TextDiff.lines(of: "") == [])
		#expect(TextDiff.lines(of: "\n") == [""])
	}

	@Test func aLongUnchangedRunFoldsAndKeepsContextBesideTheChange() {
		let left = (1...40).map { "line \($0)" }.joined(separator: "\n") + "\n"
		let right = (1...40).map { $0 == 20 ? "LINE 20" : "line \($0)" }.joined(separator: "\n") + "\n"
		let diff = TextDiff(left, right)
		let shown = diff.shown(opened: [], context: 3, minimum: 10)
		// Rows 0..<16 fold away — nothing to keep at the top of the file —
		// then three of context, the change, three more, and the tail folds.
		#expect(shown.first == .fold(rows: 0..<16))
		#expect(shown[1...3] == [.row(16), .row(17), .row(18)])
		#expect(shown[4] == .row(19))
		#expect(shown[5...7] == [.row(20), .row(21), .row(22)])
		#expect(shown.last == .fold(rows: 23..<40))
		// Opened by its first row, it shows its rows.
		let opened = diff.shown(opened: [0], context: 3, minimum: 10)
		#expect(opened.first == .row(0))
		#expect(opened.count == 16 + 7 + 1)
	}

	@Test func aRunShorterThanTheMinimumIsNotFolded() {
		let left = (1...8).map { "l\($0)" }.joined(separator: "\n") + "\nchanged\n"
		let right = (1...8).map { "l\($0)" }.joined(separator: "\n") + "\nCHANGED\n"
		let shown = TextDiff(left, right).shown(opened: [], context: 3, minimum: 10)
		#expect(shown.allSatisfy { if case .row = $0 { return true } else { return false } })
	}

	@Test func aMovedBlockMatchesWhereItWent() {
		let left = "a\nb\nc\nd\ne\nf\n"
		let right = "d\ne\nf\na\nb\nc\n"
		let diff = TextDiff(left, right)
		// Six lines, three of which survive in order on the shortest path: the
		// other three are removed before and added after.
		#expect(diff.rows.filter { $0.kind == .equal }.count == 3)
		#expect(diff.counts.additions == 3)
		#expect(diff.counts.deletions == 3)
	}

	@Test func aDiffIsMinimalOnTheClassicExample() {
		// The paper's own example: ABCABBA against CBABAC has five edits.
		let a = ["A", "B", "C", "A", "B", "B", "A"]
		let b = ["C", "B", "A", "B", "A", "C"]
		let diff = TextDiff(leftLines: a, rightLines: b)
		let edits = diff.rows.filter { $0.kind != .equal }.reduce(0) { $0 + ($1.kind == .changed ? 2 : 1) }
		#expect(edits == 5)
	}

	@Test func twoUnrelatedLargeFilesFinishInBoundedTime() {
		let left = (0..<20_000).map { "left \($0)" }.joined(separator: "\n")
		let right = (0..<20_000).map { "right \($0)" }.joined(separator: "\n")
		let started = Date()
		let diff = TextDiff(left, right)
		let elapsed = Date().timeIntervalSince(started)
		#expect(diff.rows.filter { $0.kind == .equal }.isEmpty)
		#expect(diff.rows.count == 20_000)
		// A claim about shape: unbounded, the search took 21 seconds in debug
		// on this input; bounded near the square root it takes a fraction of
		// one. Sixty is the line between the two shapes, not a budget, and it
		// is still a duration, so it is asserted only when the machine is
		// quiet enough for a duration to mean anything.
		print("TextDiffTests: two unrelated files of 20,000 lines took \(String(format: "%.3f", elapsed)) s. \(MachineLoad.said)")
		if Stopwatch.maySay("TextDiffTests", "the bounded search") {
			#expect(elapsed < 60, "\(elapsed) s")
		}
	}

	@Test func aChangeWithNothingOnOneSideAnchorsBetweenItsNeighbours() {
		let diff = TextDiff("a\nb\nc\n", "a\nb\nX\nc\n")
		let change = diff.changes[0]
		#expect(change.leftLines == 2..<2)
		#expect(change.rightLines == 2..<3)
	}
}
