import Foundation
import Testing
@testable import AbydosKit

/// Following a log that is handed over as a tail rather than as a stream.
struct LogTailTests {
	@Test func theFirstTailIsAllNew() {
		var tail = LogTail()
		#expect(tail.newLines(in: "one\ntwo\n") == ["one", "two"])
	}

	/// The same answer twice is the common case while a program sits idle, and
	/// it must produce nothing rather than the log again.
	@Test func askingAgainWithNothingNewYieldsNothing() {
		var tail = LogTail()
		_ = tail.newLines(in: "one\ntwo\n")
		#expect(tail.newLines(in: "one\ntwo\n").isEmpty)
		#expect(tail.newText(in: "one\ntwo\n") == "")
	}

	@Test func onlyWhatWasAddedComesBack() {
		var tail = LogTail()
		_ = tail.newLines(in: "one\ntwo\n")
		#expect(tail.newLines(in: "one\ntwo\nthree\n") == ["three"])
		#expect(tail.newText(in: "one\ntwo\nthree\nfour\n") == "four\n")
	}

	/// The window slides once the program has printed more than the tail holds:
	/// the oldest lines fall off the front and the overlap is what is left.
	@Test func aSlidingWindowIsMatchedByItsOverlap() {
		var tail = LogTail()
		_ = tail.newLines(in: "one\ntwo\nthree\n")
		#expect(tail.newLines(in: "two\nthree\nfour\n") == ["four"])
	}

	/// A program that prints the same line over and over is where a naive
	/// comparison goes wrong: the overlap has to be the longest one, not the
	/// first that matches.
	@Test func repeatedLinesAreNotMistakenForOldOnes() {
		var tail = LogTail()
		_ = tail.newLines(in: "tick\ntick\ntick\n")
		#expect(tail.newLines(in: "tick\ntick\ntick\ntick\n") == ["tick"])
	}

	/// Nothing in common means the program was restarted, or the tail jumped
	/// further than the window: all of it is new, since dropping it would lose
	/// output nobody can ask for again.
	@Test func anEntirelyDifferentTailIsAllNew() {
		var tail = LogTail()
		_ = tail.newLines(in: "one\ntwo\n")
		#expect(tail.newLines(in: "nine\nten\n") == ["nine", "ten"])
	}

	/// A tail with no trailing newline, and an empty one, are both ordinary.
	@Test func survivesTailsThatAreNotTidy() {
		var tail = LogTail()
		#expect(tail.newLines(in: "").isEmpty)
		#expect(tail.newLines(in: "\n") == [""])
		var other = LogTail()
		#expect(other.newLines(in: "one\ntwo") == ["one", "two"])
		#expect(other.newLines(in: "one\ntwo").isEmpty)
	}

	/// A blank line between two others is a line, not a gap to be skipped:
	/// programs separate their output with them.
	@Test func blankLinesInTheMiddleAreKept() {
		var tail = LogTail()
		#expect(tail.newLines(in: "one\n\ntwo\n") == ["one", "", "two"])
		#expect(tail.newLines(in: "one\n\ntwo\n\n") == [""])
	}

	/// What is remembered is bounded, so a program printing all day does not
	/// turn the follower into a second copy of the log.
	@Test func theHistoryItKeepsIsBounded() {
		var tail = LogTail(memory: 3)
		_ = tail.newLines(in: (1...10).map { "line \($0)" }.joined(separator: "\n") + "\n")
		// Only the last three are still known, so a tail starting before them
		// cannot be matched and comes back whole.
		#expect(tail.newLines(in: "line 8\nline 9\nline 10\nline 11\n") == ["line 11"])
	}
}
