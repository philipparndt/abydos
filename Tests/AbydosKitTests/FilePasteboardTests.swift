import AppKit
import Foundation
import Testing
@testable import AbydosKit

/// ⌘C in the project tree, which has to be two things at once.
///
/// On a scratch board rather than the general one: the suite must not reach
/// into whatever the person running it had copied a moment ago.
struct FilePasteboardTests {
	private func scratch(_ name: String = #function) -> NSPasteboard {
		NSPasteboard(name: NSPasteboard.Name("abydos.test.\(name).\(UUID().uuidString)"))
	}

	private let files = [
		URL(fileURLWithPath: "/tmp/abydos-test/Makefile"),
		URL(fileURLWithPath: "/tmp/abydos-test/Package.swift"),
	]

	/// The whole point: one gesture, and both a terminal and the Finder get what
	/// they can use.
	@Test func filesAreOnTheBoardAsFilesAndAsPaths() {
		let board = scratch()
		FilePasteboard.write(files, to: board)

		#expect(FilePasteboard.files(on: board).map(\.path) == files.map(\.path))
		#expect(
			board.string(forType: .string)
				== "/tmp/abydos-test/Makefile\n/tmp/abydos-test/Package.swift"
		)
	}

	/// The trap this exists to mark, kept as a test so nobody re-derives it:
	/// `writeObjects([NSURL])` is the obvious swap, and it puts nothing readable
	/// as text on the board at all. Making ⌘C paste as a file that way would
	/// have silently destroyed the terminal paste.
	@Test func theObviousSwapLosesTheTextEntirely() {
		let board = scratch()
		board.clearContents()
		board.writeObjects(files.map { $0 as NSURL })

		#expect(FilePasteboard.files(on: board).count == 2, "it does put files on the board")
		#expect(board.string(forType: .string) == nil, "and no text at all, which is the fault")
	}

	/// AppKit joins the per-item strings itself, so the text form is what a
	/// single `setString(paths.joined(separator: "\n"))` produced before — which
	/// is what makes this a change nothing else has to be told about.
	@Test func theTextIsCharacterForCharacterWhatItWas() {
		let board = scratch()
		FilePasteboard.write(files, to: board)
		#expect(board.string(forType: .string) == files.map(\.path).joined(separator: "\n"))
	}

	/// One file reads as one path, with no stray newline on the end.
	@Test func oneFileIsOnePathWithNothingAfterIt() {
		let board = scratch()
		FilePasteboard.write([files[0]], to: board)
		#expect(board.string(forType: .string) == "/tmp/abydos-test/Makefile")
		#expect(FilePasteboard.files(on: board).count == 1)
	}

	/// A board holding nothing but text is not a list of files, so ⌘V in the
	/// tree has nothing to paste rather than a folder full of nonsense.
	@Test func plainTextIsNotAListOfFiles() {
		let board = scratch()
		board.clearContents()
		board.setString("/tmp/abydos-test/Makefile", forType: .string)
		#expect(FilePasteboard.files(on: board).isEmpty)
	}

	/// Nothing selected clears the board rather than leaving the last copy on
	/// it, so ⌘V cannot paste what ⌘C did not copy.
	@Test func nothingToCopyLeavesNothingBehind() {
		let board = scratch()
		FilePasteboard.write(files, to: board)
		FilePasteboard.write([], to: board)
		#expect(FilePasteboard.files(on: board).isEmpty)
		#expect(board.string(forType: .string) == nil)
	}
}
