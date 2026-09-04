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

/// A picture on the board, which ⌘V in the tree writes as a file.
///
/// The same scratch board: what somebody has on their clipboard while the
/// suite runs is theirs.
struct PicturePasteboardTests {
	private func scratch(_ name: String = #function) -> NSPasteboard {
		NSPasteboard(name: NSPasteboard.Name("abydos.test.\(name).\(UUID().uuidString)"))
	}

	/// A small opaque bitmap of a known size, so what comes back can be
	/// measured against what went in.
	private func bitmap(width: Int, height: Int) -> NSBitmapImageRep {
		let rep = NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
			samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
			bytesPerRow: 0, bitsPerPixel: 0
		)!
		for x in 0..<width {
			for y in 0..<height {
				rep.setColor(x < width / 2 ? .red : .blue, atX: x, y: y)
			}
		}
		return rep
	}

	private func size(of png: Data) -> (Int, Int)? {
		guard let rep = NSBitmapImageRep(data: png) else { return nil }
		return (rep.pixelsWide, rep.pixelsHigh)
	}

	/// A PNG the board already holds is the PNG that comes back, byte for byte:
	/// the program that put it there had encoded it once, and once is enough.
	@Test func aPngOnTheBoardComesBackAsItWas() {
		let board = scratch()
		let png = bitmap(width: 6, height: 4).representation(using: .png, properties: [:])!
		board.clearContents()
		board.setData(png, forType: .png)

		#expect(FilePasteboard.hasPicture(on: board))
		#expect(FilePasteboard.picture(on: board) == png)
	}

	/// A board with TIFF and nothing else — what some programs put there alone —
	/// comes back as a PNG of the same size.
	@Test func aTiffOnlyBoardComesBackAsAPngOfTheSameSize() {
		let board = scratch()
		board.clearContents()
		board.setData(bitmap(width: 7, height: 5).tiffRepresentation!, forType: .tiff)

		#expect(FilePasteboard.hasPicture(on: board))
		let png = FilePasteboard.picture(on: board)
		#expect(png != nil)
		#expect(png.flatMap(size) ?? (0, 0) == (7, 5))
		// It is a PNG and not the TIFF handed back under another name.
		#expect(png?.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
	}

	/// Text is not a picture, so a board holding a path or a paragraph leaves
	/// Paste grey for pixels as it does for files.
	@Test func textIsNotAPicture() {
		let board = scratch()
		board.clearContents()
		board.setString("not a picture", forType: .string)
		#expect(!FilePasteboard.hasPicture(on: board))
		#expect(FilePasteboard.picture(on: board) == nil)
	}

	/// A file copied in the Finder can carry pixels beside its URL. The file is
	/// still listed: which of the two ⌘V pastes is the tree's decision, and it
	/// needs to be able to see both.
	@Test func aFileBesidePixelsIsStillAFile() {
		let board = scratch()
		FilePasteboard.write([URL(fileURLWithPath: "/tmp/abydos-test/logo.png")], to: board)
		board.addTypes([.png], owner: nil)
		board.setData(bitmap(width: 2, height: 2).representation(using: .png, properties: [:])!, forType: .png)

		#expect(FilePasteboard.files(on: board).count == 1)
		#expect(FilePasteboard.hasPicture(on: board))
	}

	/// A board may declare a type and carry rubbish under it. Nothing is written
	/// under a `.png` name that no decoder opens; the paste says no instead.
	@Test func bytesTheDecoderRefusesAreNotAPicture() {
		let board = scratch()
		board.clearContents()
		board.setData(Data("definitely not an image".utf8), forType: .png)
		#expect(FilePasteboard.hasPicture(on: board), "the type is declared, so the menu may offer it")
		#expect(FilePasteboard.picture(on: board) == nil, "but the bytes do not decode, so there is nothing to write")
	}
}
