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
	/// "duplicate" — and it is the one collision that cannot be an accident, so
	/// it is answered with a name rather than a refusal.
	///
	/// This asserted the opposite until the behaviour was asked for: a
	/// self-collision used to be refused, on the argument that renaming a
	/// newcomer invents a file nobody asked for. That argument holds for two
	/// *different* files, which is still refused a few tests below; it does not
	/// hold here, because there is nothing else the gesture could have meant.
	@Test func copyingAFileOntoItsOwnFolderDuplicatesIt() {
		let plan = FileTransfer.plan(
			[URL(fileURLWithPath: "/p/Sources/a.swift")], into: sources, operation: .copy,
			projectRoot: root, exists: disk("/p/Sources/a.swift")
		)
		#expect(plan.collisions.isEmpty)
		#expect(plan.transfers.map(\.destination.lastPathComponent) == ["a-1.swift"])
		// And nothing to apologise for, since nothing was skipped.
		#expect(plan.summary(operation: .copy, done: 1) == nil)
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

/// Copying a file into the folder it is already in.
///
/// The one collision that cannot be an accident, and so the one that is
/// answered with a name rather than a refusal.
struct FileDuplicateTests {
	private let folder = URL(fileURLWithPath: "/p/src")
	private var file: URL { folder.appendingPathComponent("main.py") }

	private func plan(
		_ sources: [URL], onDisk: Set<String>
	) -> FileTransfer.Plan {
		FileTransfer.plan(
			sources, into: folder, operation: .copy, projectRoot: URL(fileURLWithPath: "/p"),
			exists: { onDisk.contains($0.standardizedFileURL.path) }
		)
	}

	@Test func aCopyOntoItsOwnFolderTakesTheNextName() {
		let made = plan([file], onDisk: [file.path])
		#expect(made.collisions.isEmpty)
		#expect(made.transfers.map(\.destination.path) == ["/p/src/main-1.py"])
	}

	/// The extension is what the file *is*, so it stays on the end.
	@Test func theNumberGoesBeforeTheExtension() {
		let made = plan([file], onDisk: [file.path])
		#expect(made.transfers.first?.destination.pathExtension == "py")
	}

	@Test func theNextFreeNumberIsTakenRatherThanTheNextCount() {
		let made = plan([file], onDisk: [file.path, "/p/src/main-1.py", "/p/src/main-2.py"])
		#expect(made.transfers.map(\.destination.lastPathComponent) == ["main-3.py"])
	}

	/// Duplicating `main-1.py` must not quietly take `main-2.py`, which may be
	/// the next thing in somebody's series.
	@Test func duplicatingANumberedFileAppendsRatherThanCounting() {
		let numbered = folder.appendingPathComponent("chapter-1.md")
		let made = plan([numbered], onDisk: [numbered.path])
		#expect(made.transfers.map(\.destination.lastPathComponent) == ["chapter-1-1.md"])
	}

	@Test func aNameThatIsAllExtensionKeepsItsDot() {
		let dotfile = folder.appendingPathComponent(".gitignore")
		let made = plan([dotfile], onDisk: [dotfile.path])
		#expect(made.transfers.map(\.destination.lastPathComponent) == [".gitignore-1"])
	}

	/// Two duplicates in one gesture. Nothing is on disk yet, so the plan has to
	/// remember what it has already promised.
	@Test func twoAtOnceDoNotBothGetTheSameNumber() {
		let other = folder.appendingPathComponent("other.py")
		let made = plan([file, other], onDisk: [file.path, other.path])
		#expect(made.transfers.map(\.destination.lastPathComponent) == ["main-1.py", "other-1.py"])
	}

	/// A picture pasted from the clipboard has no name of its own, so it gets
	/// the first one free in the folder.
	@Test func aFileWithNoNameGetsTheFirstOneFree() {
		let made = FileTransfer.freeName(
			stem: "picture", extension: "png", in: folder, isTaken: { _ in false }
		)
		#expect(made.lastPathComponent == "picture-1.png")
	}

	/// A gap is a free name: the number is the first one free, not the count.
	@Test func aGapInTheNumbersIsTakenBeforeTheNextCount() {
		let made = FileTransfer.freeName(
			stem: "picture", extension: "png", in: folder,
			isTaken: { ["/p/src/picture-1.png", "/p/src/picture-3.png"].contains($0.standardizedFileURL.path) }
		)
		#expect(made.lastPathComponent == "picture-2.png")
	}

	/// A folder duplicates the same way, having no extension to preserve.
	@Test func aFolderDuplicatesToo() {
		let sub = folder.appendingPathComponent("Resources")
		let made = plan([sub], onDisk: [sub.path])
		#expect(made.transfers.map(\.destination.lastPathComponent) == ["Resources-1"])
	}

	/// A *move* onto its own folder is still nothing at all — a slip of the hand
	/// two pixels from where the drag started must not make a second copy.
	@Test func aMoveOntoItsOwnFolderIsStillNothing() {
		let made = FileTransfer.plan(
			[file], into: folder, operation: .move, projectRoot: URL(fileURLWithPath: "/p"),
			exists: { $0.standardizedFileURL.path == self.file.path }
		)
		#expect(made.transfers.isEmpty)
		#expect(made.unchanged == [file])
	}

	/// Two *different* files colliding is unchanged: still refused, never renamed.
	@Test func aCollisionBetweenTwoDifferentFilesStillRefuses() {
		let elsewhere = URL(fileURLWithPath: "/p/other/main.py")
		let made = plan([elsewhere], onDisk: [elsewhere.path, file.path])
		#expect(made.transfers.isEmpty)
		#expect(made.collisions == [elsewhere])
	}
}
