import Foundation
import Testing
@testable import AbydosKit

/// Dropping and pasting files into a folder: what goes, what does not, and what
/// the one message afterwards says.
struct FileTransferTests {
	private let root = URL(fileURLWithPath: "/p")
	private let sources = URL(fileURLWithPath: "/p/Sources")
	private let tests = URL(fileURLWithPath: "/p/Tests")

	/// A disk, as a set of paths.
	private func disk(_ paths: String...) -> (URL) -> Bool {
		let set = Set(paths)
		return { set.contains($0.standardizedFileURL.path) }
	}

	/// The plain case, and the one the whole item is for: a file lands in the
	/// folder it was dropped on.
	@Test func oneFileGoesWhereItWasDropped() {
		let plan = FileTransfer.plan(
			[URL(fileURLWithPath: "/p/a.swift")], into: sources, operation: .move,
			projectRoot: root, exists: disk("/p/a.swift")
		)
		#expect(plan.transfers == [FileTransfer.Transfer(
			source: URL(fileURLWithPath: "/p/a.swift"),
			destination: URL(fileURLWithPath: "/p/Sources/a.swift")
		)])
		#expect(plan.hasWork)
		#expect(plan.summary(operation: .move, done: 1) == nil, "nothing to say when it all worked")
	}

	/// The one design question in 0436, settled: the nine that were fine go, the
	/// three that collide stay, and one message says so.
	@Test func twelveDroppedWhereThreeCollideMovesNineAndSaysSoOnce() {
		let names = (1...12).map { "f\($0).swift" }
		let dropped = names.map { URL(fileURLWithPath: "/p/\($0)") }
		let onDisk = dropped.map(\.path) + ["/p/Sources/f2.swift", "/p/Sources/f5.swift", "/p/Sources/f9.swift"]

		let plan = FileTransfer.plan(
			dropped, into: sources, operation: .move, projectRoot: root,
			exists: { Set(onDisk).contains($0.path) }
		)
		#expect(plan.transfers.count == 9)
		#expect(plan.collisions.map(\.lastPathComponent) == ["f2.swift", "f5.swift", "f9.swift"])
		#expect(plan.refusals.isEmpty)

		let summary = plan.summary(operation: .move, done: 9)
		#expect(summary?.title == "Not everything was moved")
		#expect(summary?.detail
			== "“f2.swift”, “f5.swift” and “f9.swift” already exist here. The other 9 were moved.")
	}

	/// And nothing is ever overwritten, which is the rule `commitRename` already
	/// keeps for one file.
	@Test func aCollisionNeverOverwrites() {
		let plan = FileTransfer.plan(
			[URL(fileURLWithPath: "/p/a.swift")], into: sources, operation: .copy,
			projectRoot: root, exists: disk("/p/a.swift", "/p/Sources/a.swift")
		)
		#expect(plan.transfers.isEmpty)
		#expect(!plan.hasWork, "the drop is refused rather than accepted and then explained")
		let summary = plan.summary(operation: .copy, done: 0)
		#expect(summary?.title == "Nothing was copied")
		#expect(summary?.detail == "“a.swift” already exists here.")
	}

	/// How a tree gets eaten. Both halves: onto itself, and onto something
	/// inside it.
	@Test func aFolderCannotGoInsideItself() {
		let intoItself = FileTransfer.plan(
			[sources], into: sources, operation: .move, projectRoot: root, exists: disk("/p/Sources")
		)
		#expect(intoItself.transfers.isEmpty)
		#expect(intoItself.refusals == ["“Sources” cannot go inside itself."])

		let intoADescendant = FileTransfer.plan(
			[sources], into: URL(fileURLWithPath: "/p/Sources/Kit/Project"), operation: .move,
			projectRoot: root, exists: disk("/p/Sources")
		)
		#expect(intoADescendant.transfers.isEmpty)
		#expect(intoADescendant.refusals == ["“Sources” cannot go inside itself."])
	}

	/// A prefix is not an ancestor: `/p/Sources` is not inside `/p/Source`.
	@Test func aSharedPrefixIsNotADescendant() {
		let plan = FileTransfer.plan(
			[URL(fileURLWithPath: "/p/Source")], into: sources, operation: .move,
			projectRoot: root, exists: disk("/p/Source")
		)
		#expect(plan.transfers.count == 1)
	}

	/// The project root goes nowhere, and says why in its own words rather than
	/// through the "inside itself" rule.
	@Test func theProjectRootGoesNowhere() {
		let plan = FileTransfer.plan(
			[root], into: tests, operation: .move, projectRoot: root, exists: disk("/p")
		)
		#expect(plan.transfers.isEmpty)
		#expect(plan.refusals == ["“p” is the project root."])
	}

	/// Dropped two pixels from where it started. Nothing happens and nothing is
	/// said — a message for a slip of the hand is worse than silence.
	@Test func aMoveIntoTheFolderItIsAlreadyInIsSilent() {
		let plan = FileTransfer.plan(
			[URL(fileURLWithPath: "/p/Sources/a.swift")], into: sources, operation: .move,
			projectRoot: root, exists: disk("/p/Sources/a.swift")
		)
		#expect(plan.transfers.isEmpty)
		#expect(!plan.hasWork)
		#expect(plan.unchanged.map(\.lastPathComponent) == ["a.swift"])
		#expect(plan.summary(operation: .move, done: 0) == nil)
	}

	/// ⌥-dragging a file onto its own folder is the one gesture that reads as
	/// "duplicate", and duplicating is not in this item — so it collides with
	/// itself and says so, rather than quietly inventing "a copy.swift".
	@Test func copyingAFileOntoItsOwnFolderCollidesWithItself() {
		let plan = FileTransfer.plan(
			[URL(fileURLWithPath: "/p/Sources/a.swift")], into: sources, operation: .copy,
			projectRoot: root, exists: disk("/p/Sources/a.swift")
		)
		#expect(plan.transfers.isEmpty)
		#expect(plan.collisions.map(\.lastPathComponent) == ["a.swift"])
	}

	/// ⌘C, then the file is trashed in the Finder, then ⌘V. The board still
	/// names it; the disk does not.
	@Test func aSourceThatHasGoneIsRefusedRatherThanFailed() {
		let plan = FileTransfer.plan(
			[URL(fileURLWithPath: "/p/gone.swift"), URL(fileURLWithPath: "/p/here.swift")],
			into: sources, operation: .copy, projectRoot: root, exists: disk("/p/here.swift")
		)
		#expect(plan.transfers.count == 1)
		#expect(plan.refusals == ["“gone.swift” is no longer there."])
		#expect(plan.summary(operation: .copy, done: 1)?.detail
			== "“gone.swift” is no longer there. The other one was copied.")
	}

	/// The file system can still say no after everything here has said yes —
	/// permissions, a full disk — and that lands in the same one message rather
	/// than a second toast.
	@Test func aFailureFromTheDiskJoinsTheSameMessage() {
		let plan = FileTransfer.plan(
			[URL(fileURLWithPath: "/p/a.swift"), URL(fileURLWithPath: "/p/b.swift")],
			into: sources, operation: .move, projectRoot: root,
			exists: disk("/p/a.swift", "/p/b.swift")
		)
		let summary = plan.summary(
			operation: .move, done: 1, failures: ["“b.swift”: Permission denied."]
		)
		#expect(summary?.title == "Not everything was moved")
		#expect(summary?.detail == "“b.swift”: Permission denied. The other one was moved.")
	}

	/// A toast naming twelve files is a toast nobody finishes reading.
	@Test func aLongListStopsAtFourAndCountsTheRest() {
		#expect(FileTransfer.list(["a"]) == "a")
		#expect(FileTransfer.list(["a", "b"]) == "a and b")
		#expect(FileTransfer.list(["a", "b", "c"]) == "a, b and c")
		#expect(FileTransfer.list(["a", "b", "c", "d"]) == "a, b, c and d")
		#expect(FileTransfer.list(["a", "b", "c", "d", "e", "f"]) == "a, b, c, d and 2 more")
	}

	/// Refusals and collisions in the same drop are one message, in that order:
	/// what could never have worked before what merely did not fit.
	@Test func refusalsAndCollisionsShareOneMessage() {
		let plan = FileTransfer.plan(
			[root, URL(fileURLWithPath: "/p/a.swift"), URL(fileURLWithPath: "/p/b.swift")],
			into: tests, operation: .move, projectRoot: root,
			exists: disk("/p", "/p/a.swift", "/p/b.swift", "/p/Tests/a.swift")
		)
		#expect(plan.transfers.count == 1)
		#expect(plan.summary(operation: .move, done: 1)?.detail
			== "“p” is the project root. “a.swift” already exists here. The other one was moved.")
	}
}
