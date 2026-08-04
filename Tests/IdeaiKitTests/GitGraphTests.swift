import Foundation
import Testing
@testable import IdeaiKit

/// Laying a history out in lanes.
///
/// The shapes here are the ones that make a graph hard: a branch that runs
/// beside the mainline and merges back, two of them at once, and a merge whose
/// side is longer than the page. Written as commits and parents rather than
/// made in a repository, because the interesting histories are miserable to
/// build by hand and impossible to build repeatably.
struct GitGraphTests {
	private func node(_ hash: String, _ parents: String...) -> GitGraph.Node {
		GitGraph.Node(hash: hash, parents: parents)
	}

	/// A straight line: one lane, every commit in it.
	@Test func aLineIsOneLane() {
		let rows = GitGraph.lay(out: [
			node("c", "b"),
			node("b", "a"),
			node("a"),
		])
		#expect(rows.map(\.lane) == [0, 0, 0])
		#expect(rows.map(\.width) == [1, 1, 1])
		#expect(rows.allSatisfy { $0.branch == rows[0].branch }, "one line of descent")
	}

	/// The last commit has no parent, so nothing carries on below it.
	@Test func theFirstCommitEndsItsLane() {
		let rows = GitGraph.lay(out: [node("b", "a"), node("a")])
		#expect(rows.last?.edges.isEmpty == true)
	}

	/// A merge: the mainline keeps lane 0 and the branch gets one of its own,
	/// which closes when its last commit is reached.
	@Test func aMergedBranchTakesALaneOfItsOwn() {
		//  m ── merge of main (b) and side (s)
		//  |\
		//  b s
		//  |/
		//  a
		let rows = GitGraph.lay(out: [
			node("m", "b", "s"),
			node("b", "a"),
			node("s", "a"),
			node("a"),
		])

		#expect(rows[0].lane == 0, "the merge stays on the mainline")
		#expect(rows[0].width == 2, "and opens a lane for the side")
		#expect(rows[1].lane == 0)
		#expect(rows[2].lane == 1, "the side commit is beside it")
		#expect(rows[3].lane == 0, "and the two meet again at the root")
		#expect(rows[0].branch != rows[2].branch, "different lines, different colours")
	}

	/// The merge row carries a line to the lane its second parent will sit in,
	/// which is what the curve on screen is.
	@Test func aMergeDrawsALineToTheSide() {
		let rows = GitGraph.lay(out: [
			node("m", "b", "s"),
			node("b", "a"),
			node("s", "a"),
			node("a"),
		])
		#expect(rows[0].edges.contains { $0.from == 0 && $0.to == 1 })
	}

	/// A branch keeps its colour all the way down, including the last stretch
	/// where it comes back into the commit both sides share.
	///
	/// Drawn in the colour of the commit it arrives at, a branch changed colour
	/// halfway down for no reason the history gives — the side ran green from
	/// the merge and then turned blue as it rejoined.
	@Test func aBranchKeepsItsColourWhereItRejoins() {
		let rows = GitGraph.lay(out: [
			node("m", "b", "s"),
			node("b", "a"),
			node("s", "a"),
			node("a"),
		])

		let side = rows[2].branch
		let arriving = rows[3].edges.first { $0.from == 1 && $0.to == 0 }
		#expect(arriving?.branch == side, "the side's own colour, not the root's")
		#expect(side != rows[3].branch, "which is not the same colour")
	}

	/// Two branches open at once: three lanes, and nothing shares one while
	/// both are alive.
	@Test func twoBranchesAtOnce() {
		let rows = GitGraph.lay(out: [
			node("t", "u", "x"),
			node("u", "v", "y"),
			node("x", "v"),
			node("y", "v"),
			node("v"),
		])
		#expect(rows.map(\.width).max() == 3)
		#expect(Set(rows.dropLast().map(\.lane)).count >= 2)
	}

	// MARK: - What can be folded away

	@Test func aMergeKnowsHowMuchItBroughtIn() {
		let rows = GitGraph.lay(out: [
			node("m", "b", "s2"),
			node("b", "a"),
			node("s2", "s1"),
			node("s1", "a"),
			node("a"),
		])
		#expect(rows[0].collapsible == 2, "s1 and s2 belong to the side")
		#expect(rows[1].collapsible == 0, "an ordinary commit brought nothing in")
	}

	/// Commits on both sides of a merge belong to the mainline, and folding the
	/// merge away must not take them.
	@Test func whatIsAlsoOnTheMainlineIsNotTheSide() {
		let rows = GitGraph.lay(out: [
			node("m", "b", "a"),
			node("b", "a"),
			node("a"),
		])
		#expect(rows[0].collapsible == 0)
	}

	@Test func nothingToLayOutIsNoRows() {
		#expect(GitGraph.lay(out: []).isEmpty)
	}
}
