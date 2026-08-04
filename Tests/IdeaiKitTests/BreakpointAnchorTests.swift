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

/// Anchoring a breakpoint to the code around it rather than to a line number.
///
/// The case text matching cannot follow: a function moves four hundred lines
/// because something above it was rewritten. "Third line of `setUp`" still
/// points at the same statement; line 42 does not, and a `}` four hundred
/// lines away is a coincidence rather than the same `}`.
struct BreakpointSymbolAnchorTests {
	/// Symbols with the line spans they cover, since a `DocumentSymbol` keeps
	/// bytes and the anchor thinks in lines.
	private func symbol(
		_ name: String,
		_ range: ClosedRange<Int>,
		_ children: [DocumentSymbol] = []
	) -> DocumentSymbol {
		DocumentSymbol(
			name: name,
			kind: .function,
			line: range.lowerBound,
			byteRange: range.lowerBound..<(range.upperBound + 1),
			children: children
		)
	}

	/// The span is the byte range here, which the tests use as lines.
	private func span(_ symbol: DocumentSymbol) -> Range<Int> {
		symbol.byteRange.lowerBound..<symbol.byteRange.upperBound
	}

	private var before: [DocumentSymbol] {
		[symbol("Config", 0...20, [symbol("setUp", 4...9), symbol("tearDown", 12...18)])]
	}

	@Test func aLineIsDescribedByWhatContainsIt() {
		let anchor = BreakpointAnchors.anchor(
			line: 6, text: "    start()", in: before, lineOf: span
		)
		#expect(anchor.path == ["Config", "setUp"], "the innermost symbol wins")
		#expect(anchor.offset == 2, "two lines into setUp")
	}

	/// The whole point: everything moved, and the breakpoint moved with its
	/// function rather than staying on a number.
	@Test func itFollowsItsFunctionAcrossTheFile() {
		let anchor = BreakpointAnchors.anchor(
			line: 6, text: "    start()", in: before, lineOf: span
		)
		let after = [symbol("Config", 400...460, [symbol("setUp", 420...430)])]

		#expect(BreakpointAnchors.resolve(anchor, in: after, lines: [], lineOf: span) == 422)
	}

	/// A function that lost lines does not push the breakpoint past its end.
	@Test func aShorterFunctionKeepsItInside() {
		let anchor = BreakpointAnchors.anchor(
			line: 8, text: "    finish()", in: before, lineOf: span
		)
		let after = [symbol("Config", 0...10, [symbol("setUp", 4...5)])]
		#expect(BreakpointAnchors.resolve(anchor, in: after, lines: [], lineOf: span) == 5)
	}

	/// The symbol is gone — renamed, or deleted. The text is the weaker claim
	/// that is tried next.
	@Test func withoutItsSymbolItFallsBackToTheText() {
		let anchor = BreakpointAnchors.Anchor(path: ["Config", "setUp"], offset: 3, text: "    start()")
		let lines = ["", "", "func other() {", "    start()", "}"]
		#expect(BreakpointAnchors.resolve(anchor, in: [], lines: lines, lineOf: span) == 4)
	}

	/// Neither the symbol nor the text: nothing is claimed, rather than
	/// putting a breakpoint on code nobody chose.
	@Test func withNeitherItSaysSoRatherThanGuessing() {
		let anchor = BreakpointAnchors.Anchor(path: ["Gone"], offset: 3, text: "    vanished()")
		#expect(BreakpointAnchors.resolve(anchor, in: [], lines: ["a", "b"], lineOf: span) == nil)
	}

	/// A line outside every symbol — an import at the top — is anchored by its
	/// text alone, and still finds its way.
	@Test func aLineOutsideEverySymbolStillHasItsText() {
		let anchor = BreakpointAnchors.anchor(
			line: 30, text: "import Foundation", in: before, lineOf: span
		)
		#expect(anchor.path.isEmpty)
		#expect(BreakpointAnchors.resolve(
			anchor, in: before, lines: ["", "import Foundation"], lineOf: span
		) == 2)
	}
}

/// What lines a symbol covers, which the parser does not say.
struct SymbolLineSpanTests {
	private func symbol(
		_ name: String,
		line: Int,
		declaration: Range<Int>,
		_ children: [DocumentSymbol] = []
	) -> DocumentSymbol {
		DocumentSymbol(
			name: name,
			kind: children.isEmpty ? .method : .type,
			line: line,
			byteRange: declaration,
			nameRange: (line * 100)..<(line * 100 + name.count),
			children: children
		)
	}

	/// The shape that makes the declaration range useless: Swift's grammar hangs
	/// every member's `@definition` capture on the enclosing type, so all three
	/// of these claim bytes 0..<400.
	private var holder: [DocumentSymbol] {
		[symbol("Holder", line: 0, declaration: 0..<400, [
			symbol("first", line: 1, declaration: 0..<400),
			symbol("second", line: 5, declaration: 0..<400),
		])]
	}

	@Test func aMemberCoversItsOwnLinesRatherThanItsTypes() {
		let spans = SymbolOutline.lineSpans(of: holder, lineCount: 10)
		#expect(spans[holder[0].children[0].id] == 2..<6, "first runs until second starts")
		#expect(spans[holder[0].children[1].id] == 6..<11, "second runs to the end of its type")
	}

	@Test func theLastSymbolRunsToTheEndOfTheFile() {
		#expect(SymbolOutline.lineSpans(of: holder, lineCount: 10)[holder[0].id] == 1..<11)
	}

	/// Two declarations on one line — `func a() {}; func b() {}` — still get a
	/// line each rather than an empty span nothing can be inside.
	@Test func aSymbolAlwaysCoversItsOwnLine() {
		let crowded = [
			symbol("a", line: 3, declaration: 0..<10),
			symbol("b", line: 3, declaration: 0..<10),
		]
		#expect(SymbolOutline.lineSpans(of: crowded, lineCount: 9)[crowded[0].id] == 4..<5)
	}
}

/// A whole file's breakpoints, after something else rewrote it.
struct BreakpointRewriteTests {
	private func symbol(_ name: String, line: Int, _ children: [DocumentSymbol] = []) -> DocumentSymbol {
		DocumentSymbol(
			name: name,
			kind: children.isEmpty ? .method : .type,
			line: line,
			byteRange: 0..<1000,
			nameRange: (line * 100)..<(line * 100 + name.count),
			children: children
		)
	}

	private func breakpoint(_ line: Int, path: [String], offset: Int, text: String) -> Breakpoint {
		Breakpoint(
			file: "/x.swift",
			line: line,
			anchor: BreakpointAnchors.Anchor(path: path, offset: offset, text: text)
		)
	}

	private func lines(_ count: Int, _ overrides: [Int: String] = [:]) -> [String] {
		(1...count).map { overrides[$0] ?? "" }
	}

	@Test func eachGoesWhereItsAnchorPoints() {
		let symbols = [symbol("Config", line: 9, [symbol("setUp", line: 11)])]
		let resolved = BreakpointAnchors.resolve(
			breakpoints: [breakpoint(3, path: ["Config", "setUp"], offset: 2, text: "start()")],
			in: symbols,
			lines: lines(20)
		)
		#expect(resolved.map(\.line) == [14])
	}

	/// The anchor is taken again against the file as it is now: measured from
	/// where the symbol used to be, the next rewrite lands somewhere else again.
	@Test func whatItFindsIsAnchoredAfresh() {
		let symbols = [symbol("Config", line: 9, [symbol("setUp", line: 11)])]
		let resolved = BreakpointAnchors.resolve(
			breakpoints: [breakpoint(3, path: ["Config", "setUp"], offset: 2, text: "start()")],
			in: symbols,
			lines: lines(20, [14: "\tstart()"])
		)
		#expect(resolved.first?.anchor?.path == ["Config", "setUp"])
		#expect(resolved.first?.anchor?.offset == 2)
		#expect(resolved.first?.anchor?.text == "\tstart()")
	}

	/// A line taken out of the function above the breakpoint. Counting lines
	/// from the top of the function puts it one statement past where it was;
	/// the text says which of the function's lines it actually is.
	@Test func insideTheFunctionTheTextPicksTheLine() {
		let symbols = [symbol("Config", line: 9, [symbol("setUp", line: 10)])]
		let resolved = BreakpointAnchors.resolve(
			breakpoints: [breakpoint(6, path: ["Config", "setUp"], offset: 2, text: "start()")],
			in: symbols,
			lines: lines(20, [12: "start()", 13: "finish()"])
		)
		#expect(resolved.map(\.line) == [12], "counting alone would have said 13")
		#expect(resolved.first?.anchor?.offset == 1, "and it knows it is one line in now")
	}

	/// The same text in the function below is a different line, so counting
	/// lines is what is left — a breakpoint in the wrong function is worse than
	/// one on the wrong line of the right one.
	@Test func theTextIsOnlyLookedForInsideItsOwnSymbol() {
		let symbols = [symbol("Config", line: 0, [
			symbol("setUp", line: 1),
			symbol("tearDown", line: 4),
		])]
		let resolved = BreakpointAnchors.resolve(
			breakpoints: [breakpoint(3, path: ["Config", "setUp"], offset: 1, text: "start()")],
			in: symbols,
			lines: lines(10, [6: "start()"])
		)
		#expect(resolved.map(\.line) == [3])
	}

	/// Neither its symbol nor its text is left. Deleting it would throw away
	/// something somebody set; it stays where it was, and is not claimed bound.
	@Test func oneThatCannotBeFoundStaysWhereItWas() {
		let resolved = BreakpointAnchors.resolve(
			breakpoints: [breakpoint(3, path: ["Gone"], offset: 3, text: "vanished()")],
			in: [],
			lines: lines(20)
		)
		#expect(resolved.map(\.line) == [3])
	}

	/// Half a second of a file being written without a temporary file: it has
	/// been truncated and the real text has not arrived. Nothing in it can be
	/// found, and everything about the breakpoint has to survive that or the
	/// text arriving a moment later has nothing left to be matched against.
	@Test func aFileCaughtMidWriteMovesNothing() {
		let one = breakpoint(400, path: ["Config", "setUp"], offset: 2, text: "\t\tstart()")
		let resolved = BreakpointAnchors.resolve(breakpoints: [one], in: [], lines: [])

		#expect(resolved.map(\.line) == [400])
		#expect(resolved.first?.anchor == one.anchor, "still describing where it belongs")
	}

	/// The file lost the code this was on. Putting it on the last line instead
	/// would be putting it on code nobody chose; it waits where it was, in case
	/// what it was on comes back.
	@Test func oneOffTheEndOfAShorterFileWaitsThere() {
		let resolved = BreakpointAnchors.resolve(
			breakpoints: [breakpoint(90, path: ["Gone"], offset: 90, text: "vanished()")],
			in: [],
			lines: lines(4)
		)
		#expect(resolved.map(\.line) == [90])
	}

	/// Renamed rather than moved: the path is dead, and the text is what finds
	/// it — searched for around where the breakpoint was, not around an offset
	/// into a symbol that is not there any more.
	@Test func aRenamedSymbolLeavesTheTextToFindIt() {
		let symbols = [symbol("Config", line: 0, [symbol("configure", line: 1)])]
		let resolved = BreakpointAnchors.resolve(
			breakpoints: [breakpoint(30, path: ["Config", "setUp"], offset: 2, text: "start()")],
			in: symbols,
			lines: lines(40, [33: "start()"])
		)
		#expect(resolved.map(\.line) == [33])
		#expect(resolved.first?.anchor?.path == ["Config", "configure"], "anchored to what is there now")
	}

	/// Two functions merged into one, and both breakpoints now name the same
	/// line. A line holds one breakpoint, and the conditions of the first stand.
	@Test func twoLandingTogetherBecomeOne() {
		var first = breakpoint(3, path: ["Config", "setUp"], offset: 1, text: "start()")
		first.condition = "n > 2"
		let second = breakpoint(8, path: ["Config", "setUp"], offset: 1, text: "start()")

		let symbols = [symbol("Config", line: 0, [symbol("setUp", line: 1)])]
		let resolved = BreakpointAnchors.resolve(
			breakpoints: [first, second], in: symbols, lines: lines(10)
		)
		#expect(resolved.map(\.line) == [3])
		#expect(resolved.first?.condition == "n > 2")
	}

	/// Everything about it but where it is survives the file being rewritten.
	@Test func whatWasSetOnItComesAlong() {
		var one = breakpoint(3, path: ["Config", "setUp"], offset: 2, text: "start()")
		one.isEnabled = false
		one.logMessage = "here"
		one.hitCondition = "> 5"

		let symbols = [symbol("Config", line: 9, [symbol("setUp", line: 11)])]
		let resolved = BreakpointAnchors.resolve(breakpoints: [one], in: symbols, lines: lines(20))
		#expect(resolved.first?.isEnabled == false)
		#expect(resolved.first?.logMessage == "here")
		#expect(resolved.first?.hitCondition == "> 5")
		#expect(resolved.first?.isVerified == false, "the adapter has not seen this line yet")
	}
}

/// Against the real grammar, since anchoring is only worth anything if it
/// survives what the parser actually reports for a file.
struct BreakpointAnchorGrammarTests {
	private func symbols(_ source: String) async -> (symbols: [DocumentSymbol], lines: [String]) {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-anchor-\(UUID().uuidString)")
			.appendingPathExtension("swift")
		try? source.write(to: url, atomically: true, encoding: .utf8)
		guard let document = try? TextDocument(url: url) else { return ([], []) }

		let held = Box(document)
		let found: [DocumentSymbol] = await withCheckedContinuation { continuation in
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
				held.value.symbols { continuation.resume(returning: $0) }
			}
		}
		return (found, source.components(separatedBy: "\n"))
	}

	/// The case a text search cannot get right: the function moved, and the line
	/// it was on is still sitting there in a different function that was put
	/// where it used to be. The symbol is what tells them apart.
	@Test func itFollowsItsMethodPastAnIdenticalLine() async {
		let before = await symbols("""
		struct Config {
			func setUp() {
				start()
			}
		}
		""")
		let anchor = BreakpointAnchors.anchor(
			line: 3, text: "\t\tstart()", in: before.symbols, lineCount: before.lines.count
		)
		#expect(anchor.path == ["Config", "setUp"])

		let after = await symbols("""
		struct Decoy {
			func setUp() {
				start()
			}
		}

		struct Config {
			func setUp() {
				start()
			}
		}
		""")
		#expect(
			BreakpointAnchors.resolve(anchor, in: after.symbols, lines: after.lines) == 9,
			"the one inside Config, not the identical line where it used to be"
		)
	}

	/// A file with no grammar to parse it has no symbols to anchor to, and falls
	/// back to the text rather than losing the breakpoint.
	@Test func withoutSymbolsTheTextStillCarriesIt() async {
		let after = ["", "", "", "start()"]
		let anchor = BreakpointAnchors.anchor(line: 1, text: "start()", in: [], lineCount: 2)
		#expect(anchor.path.isEmpty)
		#expect(BreakpointAnchors.resolve(anchor, in: [], lines: after) == 4)
	}
}

private final class Box<Value>: @unchecked Sendable {
	let value: Value
	init(_ value: Value) { self.value = value }
}
