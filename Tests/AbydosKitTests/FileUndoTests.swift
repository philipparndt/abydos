import Foundation
import Testing
@testable import AbydosKit

/// Taking a gesture back: what goes home, what goes to the trash, and what the
/// one message says when neither can happen.
struct FileUndoTests {
	private let root = URL(fileURLWithPath: "/p")
	private let sources = URL(fileURLWithPath: "/p/Sources")

	/// A disk, as a set of paths.
	private func disk(_ paths: String...) -> (URL) -> Bool {
		let set = Set(paths)
		return { set.contains($0.standardizedFileURL.path) }
	}

	/// Nothing has been written since, which is what the change check compares
	/// against.
	private let unchanged: (URL) -> Date? = { _ in nil }

	// MARK: - The trash

	/// The whole reason the item exists: the map `recycle` answers with, kept,
	/// and read back the other way round.
	@Test func aTrashGoesBackToWhereEachFileCameFrom() {
		let action = FileUndo.trashed([
			URL(fileURLWithPath: "/p/a.swift"): URL(fileURLWithPath: "/T/a.swift"),
			URL(fileURLWithPath: "/p/Sources/a.swift"): URL(fileURLWithPath: "/T/a 2.swift"),
		])
		#expect(action.gesture == .trash)
		let reversal = FileUndo.reverse(
			action, exists: disk("/T/a.swift", "/T/a 2.swift", "/p", "/p/Sources"),
			modified: unchanged
		)
		#expect(reversal.refusals.isEmpty)
		#expect(reversal.restores.map(\.from.path) == ["/T/a 2.swift", "/T/a.swift"])
		#expect(reversal.restores.map(\.to.path) == ["/p/Sources/a.swift", "/p/a.swift"])
	}

	/// And the half that cannot be worked out afterwards: two files called
	/// `main.py` from different folders do not both keep the name in the trash,
	/// so the name in there is never derived from the name that went in.
	@Test func theNameInTheTrashIsTakenFromTheMapAndNotTheFile() {
		let action = FileUndo.trashed([
			URL(fileURLWithPath: "/p/one/main.py"): URL(fileURLWithPath: "/T/main.py"),
			URL(fileURLWithPath: "/p/two/main.py"): URL(fileURLWithPath: "/T/main 2.py"),
		])
		let reversal = FileUndo.reverse(
			action, exists: disk("/T/main.py", "/T/main 2.py", "/p/one", "/p/two"),
			modified: unchanged
		)
		#expect(reversal.restores.count == 2)
		// Each goes back to its own folder, and neither takes the other's name.
		let pairs = Dictionary(uniqueKeysWithValues: reversal.restores.map { ($0.to.path, $0.from.path) })
		#expect(pairs["/p/one/main.py"] == "/T/main.py")
		#expect(pairs["/p/two/main.py"] == "/T/main 2.py")
	}

	/// The trash was emptied. Said in the trash's own words, and with the name
	/// the file had rather than the one the trash gave it.
	@Test func anEmptiedTrashRefusesWithASentence() {
		let action = FileUndo.trashed([
			URL(fileURLWithPath: "/p/main.py"): URL(fileURLWithPath: "/T/main 7.py"),
		])
		let reversal = FileUndo.reverse(action, exists: disk("/p"), modified: unchanged)
		#expect(!reversal.hasWork)
		#expect(reversal.refusals == ["“main.py” is no longer in the trash."])
		let said = reversal.summary(gesture: .trash, done: 0)
		#expect(said?.title == "Nothing was put back")
		#expect(said?.detail == "“main.py” is no longer in the trash.")
	}

	/// Something else has taken the name in the meantime. Never overwritten —
	/// an undo that wrote over a file would want an undo of its own.
	@Test func anOccupiedDestinationRefusesRatherThanOverwrites() {
		let action = FileUndo.trashed([
			URL(fileURLWithPath: "/p/a.swift"): URL(fileURLWithPath: "/T/a.swift"),
		])
		let reversal = FileUndo.reverse(
			action, exists: disk("/T/a.swift", "/p", "/p/a.swift"), modified: unchanged
		)
		#expect(!reversal.hasWork)
		#expect(reversal.refusals == ["“a.swift” cannot go back: something else is there now."])
	}

	/// Trash a file, then trash the folder it was in — which is an ordinary
	/// thing to do a minute later. The refusal names the folder rather than
	/// arriving as whatever the file system says about a missing path.
	@Test func aFolderThatHasItselfGoneIsItsOwnRefusal() {
		let action = FileUndo.trashed([
			URL(fileURLWithPath: "/p/Sources/a.swift"): URL(fileURLWithPath: "/T/a.swift"),
		])
		let reversal = FileUndo.reverse(action, exists: disk("/T/a.swift"), modified: unchanged)
		#expect(!reversal.hasWork)
		#expect(reversal.refusals
			== ["“a.swift” cannot go back: the folder “Sources” is no longer there."])
	}

	/// Three trashed together, one of them since emptied out of the trash: the
	/// two that can go home go, and one message says what happened to the third.
	@Test func theOnesThatCanGoBackGoAndTheDropSaysSoOnce() {
		let action = FileUndo.trashed([
			URL(fileURLWithPath: "/p/a.swift"): URL(fileURLWithPath: "/T/a.swift"),
			URL(fileURLWithPath: "/p/b.swift"): URL(fileURLWithPath: "/T/b.swift"),
			URL(fileURLWithPath: "/p/c.swift"): URL(fileURLWithPath: "/T/c.swift"),
		])
		let reversal = FileUndo.reverse(
			action, exists: disk("/T/a.swift", "/T/c.swift", "/p"), modified: unchanged
		)
		#expect(reversal.restores.count == 2)
		let said = reversal.summary(gesture: .trash, done: 2)
		#expect(said?.title == "Not everything was put back")
		#expect(said?.detail == "“b.swift” is no longer in the trash. The other 2 were put back.")
	}

	// MARK: - Rename and move

	@Test func aRenameGoesBackToTheNameItHad() {
		let action = FileUndo.renamed(
			from: URL(fileURLWithPath: "/p/a.swift"), to: URL(fileURLWithPath: "/p/b.swift")
		)
		#expect(action.gesture == .rename)
		let reversal = FileUndo.reverse(action, exists: disk("/p", "/p/b.swift"), modified: unchanged)
		#expect(reversal.restores == [FileUndo.Restore(
			from: URL(fileURLWithPath: "/p/b.swift"), to: URL(fileURLWithPath: "/p/a.swift")
		)])
	}

	/// Renamed again by hand, or by something else, since. The sentence names
	/// the name the file has now, because that is the one that has gone.
	@Test func aRenameThatWasRenamedAgainRefuses() {
		let action = FileUndo.renamed(
			from: URL(fileURLWithPath: "/p/a.swift"), to: URL(fileURLWithPath: "/p/b.swift")
		)
		let reversal = FileUndo.reverse(action, exists: disk("/p"), modified: unchanged)
		#expect(reversal.refusals == ["“b.swift” is no longer there."])
	}

	/// A move undoes as a move the other way, and it is the same walk the
	/// trash's is — which is the point of there being two reversals and not five.
	@Test func aMoveGoesBackToTheFolderItCameFrom() {
		let action = FileUndo.transferred(
			[FileTransfer.Transfer(
				source: URL(fileURLWithPath: "/p/a.swift"),
				destination: URL(fileURLWithPath: "/p/Sources/a.swift")
			)],
			operation: .move, modified: unchanged
		)
		#expect(action.gesture == .move)
		#expect(action.discards.isEmpty)
		let reversal = FileUndo.reverse(
			action, exists: disk("/p", "/p/Sources/a.swift"), modified: unchanged
		)
		#expect(reversal.restores.map(\.to.path) == ["/p/a.swift"])
	}

	// MARK: - Copies, and the one undo that destroys something

	/// Undoing a copy trashes it rather than unlinking it. ⌘Z is pressed by
	/// reflex, often twice, and the second press is not a decision.
	@Test func undoingACopyTrashesItRatherThanDeletingIt() {
		let action = FileUndo.transferred(
			[FileTransfer.Transfer(
				source: URL(fileURLWithPath: "/p/a.swift"),
				destination: URL(fileURLWithPath: "/p/Sources/a.swift")
			)],
			operation: .copy, modified: unchanged
		)
		#expect(action.gesture == .copy)
		#expect(action.restores.isEmpty)
		let reversal = FileUndo.reverse(
			action, exists: disk("/p/Sources/a.swift"), modified: unchanged
		)
		#expect(reversal.discards.map(\.path) == ["/p/Sources/a.swift"])
	}

	/// A new file, written in and saved, and then ⌘Z back in the tree. Throwing
	/// away what somebody just typed is exactly the behaviour that teaches
	/// people not to trust undo, so it refuses instead.
	@Test func aFileWrittenInSinceIsNotThrownAway() {
		let made = Date(timeIntervalSince1970: 1000)
		let action = FileUndo.created(
			URL(fileURLWithPath: "/p/notes.md"), isDirectory: false, modified: { _ in made }
		)
		#expect(action.gesture == .newFile)
		let reversal = FileUndo.reverse(
			action, exists: disk("/p/notes.md"),
			modified: { _ in Date(timeIntervalSince1970: 2000) }
		)
		#expect(!reversal.hasWork)
		#expect(reversal.refusals == ["“notes.md” has changed since it was made."])
		#expect(reversal.summary(gesture: .newFile, done: 0)?.title == "Nothing was moved to the trash")
	}

	/// Untouched since, so it goes.
	@Test func aFileNothingHasTouchedGoesToTheTrash() {
		let made = Date(timeIntervalSince1970: 1000)
		let action = FileUndo.created(
			URL(fileURLWithPath: "/p/notes.md"), isDirectory: false, modified: { _ in made }
		)
		let reversal = FileUndo.reverse(
			action, exists: disk("/p/notes.md"), modified: { _ in made }
		)
		#expect(reversal.discards.map(\.path) == ["/p/notes.md"])
		#expect(reversal.refusals.isEmpty)
	}

	/// A date that could not be read is not a reason to refuse: that would be a
	/// refusal about the wrong thing.
	@Test func anUnreadableDateSkipsTheCheckRatherThanRefusing() {
		let action = FileUndo.created(
			URL(fileURLWithPath: "/p/notes.md"), isDirectory: false, modified: { _ in nil }
		)
		let reversal = FileUndo.reverse(
			action, exists: disk("/p/notes.md"), modified: { _ in Date() }
		)
		#expect(reversal.discards.count == 1)
	}

	/// The copy was moved away, or trashed by hand, before ⌘Z arrived.
	@Test func aCopyThatHasAlreadyGoneIsSaidRatherThanIgnored() {
		let action = FileUndo.transferred(
			[FileTransfer.Transfer(
				source: URL(fileURLWithPath: "/p/a.swift"),
				destination: URL(fileURLWithPath: "/p/Sources/a.swift")
			)],
			operation: .copy, modified: unchanged
		)
		let reversal = FileUndo.reverse(action, exists: disk("/p"), modified: unchanged)
		#expect(!reversal.hasWork)
		#expect(reversal.refusals == ["“a.swift” is no longer there."])
	}

	@Test func aNewFolderIsItsOwnGestureInTheMenu() {
		let action = FileUndo.created(
			URL(fileURLWithPath: "/p/docs"), isDirectory: true, modified: { _ in nil }
		)
		#expect(action.gesture == .newFolder)
		#expect(action.gesture.title == "New Folder")
	}

	// MARK: - The stack

	/// Nothing to take back is nothing to put on the stack. A ⌘Z that pops an
	/// entry and does nothing has eaten the one before it.
	@Test func aGestureThatDidNothingLeavesNothingOnTheStack() {
		#expect(FileUndo.trashed([:]).isEmpty)
		#expect(FileUndo.transferred([], operation: .move, modified: unchanged).isEmpty)
		#expect(FileUndo.transferred([], operation: .copy, modified: unchanged).isEmpty)
		#expect(!FileUndo.renamed(
			from: URL(fileURLWithPath: "/p/a"), to: URL(fileURLWithPath: "/p/b")
		).isEmpty)
	}

	/// What the Edit menu says ⌘Z will do, per gesture.
	@Test func eachGestureNamesItselfForTheMenu() {
		#expect(FileUndo.Gesture.trash.title == "Move to Trash")
		#expect(FileUndo.Gesture.rename.title == "Rename")
		#expect(FileUndo.Gesture.move.title == "Move")
		#expect(FileUndo.Gesture.copy.title == "Copy")
		#expect(FileUndo.Gesture.newFile.title == "New File")
	}

	/// Everything worked, so nothing is said. The tree showing the file back
	/// where it was is the whole of what was asked for.
	@Test func anUndoThatWorkedSaysNothing() {
		let action = FileUndo.renamed(
			from: URL(fileURLWithPath: "/p/a.swift"), to: URL(fileURLWithPath: "/p/b.swift")
		)
		let reversal = FileUndo.reverse(action, exists: disk("/p", "/p/b.swift"), modified: unchanged)
		#expect(reversal.summary(gesture: .rename, done: 1) == nil)
	}
}
