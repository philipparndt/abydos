import Foundation
import Testing
@testable import AbydosKit

/// The debug pane's Stack as a tree: threads at the root, grouped when they
/// share a group, and frames under them — nested when the adapter says.
struct CallTreeTests {
	@Test func threadsShareAGroupOnlyWhenThereAreSeveral() {
		let threads = [
			DebugThread(id: 1, name: "pad · chords", group: "chords", isQuiet: false),
			DebugThread(id: 2, name: "melody · verse", group: nil, isQuiet: false),
			DebugThread(id: 3, name: "keys · resting", group: "chords", isQuiet: true),
			DebugThread(id: 4, name: "bass · line", group: "bass", isQuiet: false),
		]
		let tree = CallTree.describe(CallTree.nodes(threads: threads, stacks: [:]))
		#expect(tree == [
			"[chords]",
			"  pad · chords",
			"  keys · resting (quiet)",
			"melody · verse",
			"bass · line",
		])
	}

	@Test func aDebuggersFramesStayAListUnderTheirThread() {
		let frames = [
			StackFrame(id: 1, name: "handle", file: "/p/main.go", line: 12),
			StackFrame(id: 2, name: "main", file: "/p/main.go", line: 40),
		]
		let tree = CallTree.describe(CallTree.nodes(threads: [DebugThread(id: 7, name: "goroutine 7")], stacks: [7: frames]))
		#expect(tree == ["goroutine 7", "  handle@12", "  main@40"], "innermost first, as a stack reads")
	}

	@Test func aSongsFramesNestOutermostFirstWithSiblingsInLineOrder() {
		// As the adapter lists them: sounding first, so the hat above the kick.
		let frames = [
			StackFrame(id: 111, name: "hat: x", file: nil, line: 4, parentID: 102),
			StackFrame(id: 110, name: "kick: X", file: nil, line: 3, parentID: 102, isSubtle: true),
			StackFrame(id: 102, name: "pattern beat", file: nil, line: 2, parentID: 101),
			StackFrame(id: 101, name: "play beat", file: nil, line: 9, parentID: 100),
			StackFrame(id: 100, name: "track drums", file: nil, line: 8),
		]
		let nodes = CallTree.nodes(threads: [DebugThread(id: 1, name: "drums · beat")], stacks: [1: frames])
		#expect(CallTree.describe(nodes) == [
			"drums · beat",
			"  track drums@8",
			"    play beat@9",
			"      pattern beat@2",
			"        kick: X@3 (subtle)",
			"        hat: x@4",
		])
		#expect(nodes.first?.key == "t:1")
		#expect(nodes.first?.children.first?.key == "f:1:100")
	}
}
