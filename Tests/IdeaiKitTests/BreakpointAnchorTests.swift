import Foundation
import Testing
@testable import IdeaiKit

/// Breakpoints staying on the code they were put on.
///
/// Stored as a plain line number, a breakpoint stops meaning anything the
/// moment somebody types above it: the number stays and the code moves out
/// from under it.
struct BreakpointAnchorTests {
	/// Three lines pasted above line 20 leave it on line 23.
	@Test func linesAddedAboveMoveItDown() {
		#expect(BreakpointAnchors.moved(line: 20, editedFrom: 4, removed: 0, inserted: 3) == 23)
	}

	@Test func linesRemovedAboveMoveItUp() {
		#expect(BreakpointAnchors.moved(line: 20, editedFrom: 4, removed: 3, inserted: 0) == 17)
	}

	/// Editing inside the line it sits on leaves it there: that is still its
	/// code, however much of the line changed.
	@Test func anEditWithinItsOwnLineLeavesItAlone() {
		#expect(BreakpointAnchors.moved(line: 20, editedFrom: 19, removed: 0, inserted: 0) == 20)
	}

	/// Deleting the line takes the breakpoint with it. Left behind, it would
	/// sit on whatever moved up into its place — which is not what anybody put
	/// it on, and is how a debugger comes to stop somewhere surprising.
	@Test func deletingItsLineDeletesIt() {
		// Lines 20 and 21 replaced by nothing, from the start of line 20.
		#expect(BreakpointAnchors.moved(line: 21, editedFrom: 19, removed: 2, inserted: 0) == nil)
	}

	@Test func anEditBelowChangesNothing() {
		#expect(BreakpointAnchors.moved(line: 20, editedFrom: 40, removed: 5, inserted: 9) == 20)
	}

	/// A paste that replaces a block with a longer one: what was inside is
	/// gone, what follows moves down by the difference.
	@Test func replacingABlockMovesWhatFollows() {
		let lines = [10: "a", 12: "b", 30: "c"]
		let moved = BreakpointAnchors.moved(lines: lines, editedFrom: 9, removed: 3, inserted: 6)

		#expect(moved[10] == "a", "the first line of the edit keeps its breakpoint")
		#expect(moved[12] == nil, "inside what was replaced")
		#expect(moved[33] == "c", "below, moved down by three")
		#expect(moved.count == 2)
	}

	/// Undo puts them back where they were, because it is an edit like any
	/// other: three lines removed where three were added.
	@Test func undoingBringsThemBack() {
		let after = BreakpointAnchors.moved(line: 20, editedFrom: 4, removed: 0, inserted: 3)
		#expect(after == 23)
		#expect(BreakpointAnchors.moved(line: after!, editedFrom: 4, removed: 3, inserted: 0) == 20)
	}
}

/// A file changed by something other than the editor — an agent rewriting it,
/// a checkout, a formatter. There are no edits to shift by: the file is simply
/// different when it is read again, and the only thing left to go on is what
/// was on the line.
struct BreakpointReboundTests {
	private let before = [
		"func main() {",
		"    setUp()",
		"    run()",
		"    tearDown()",
		"}",
	]

	@Test func anUnchangedLineKeepsItsBreakpoint() {
		#expect(BreakpointAnchors.rebound(line: 3, text: "    run()", in: before) == 3)
	}

	/// Two lines added above by somebody else: the code it was put on is three
	/// lines further down, and that is where it goes.
	@Test func itFollowsItsLineDownwards() {
		let after = ["import Foundation", "", "func main() {", "    setUp()", "    run()", "}"]
		#expect(BreakpointAnchors.rebound(line: 3, text: "    run()", in: after) == 5)
	}

	@Test func itFollowsItsLineUpwards() {
		let after = ["func main() {", "    run()", "}"]
		#expect(BreakpointAnchors.rebound(line: 3, text: "    run()", in: after) == 2)
	}

	/// The nearest match wins. A line like `}` is everywhere, and the one three
	/// lines away is far likelier to be the same one than the one two hundred
	/// lines up.
	@Test func theNearestMatchWins() {
		let after = ["}", "a", "b", "c", "}", "d"]
		#expect(BreakpointAnchors.rebound(line: 4, text: "}", in: after) == 5)
	}

	/// The line is gone entirely: nothing to move it to, and pretending
	/// otherwise would put a breakpoint on code nobody chose.
	@Test func aLineThatIsGoneHasNowhereToGo() {
		let after = ["func main() {", "    setUp()", "}"]
		#expect(BreakpointAnchors.rebound(line: 3, text: "    run()", in: after) == nil)
	}

	/// Far away is not the same line. A match four hundred lines off is a
	/// coincidence, not the code it was put on.
	@Test func aMatchTooFarAwayIsNotIt() {
		var after = Array(repeating: "filler", count: 200)
		after.append("    run()")
		#expect(BreakpointAnchors.rebound(line: 3, text: "    run()", in: after, radius: 40) == nil)
	}

	/// A blank line has nothing to match on, so it stays where it was rather
	/// than binding itself to the first blank line in the file.
	@Test func aBlankLineStaysPut() {
		#expect(BreakpointAnchors.rebound(line: 2, text: "   ", in: before) == 2)
	}
}
