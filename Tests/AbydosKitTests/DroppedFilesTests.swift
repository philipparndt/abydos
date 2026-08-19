import Foundation
import Testing
@testable import AbydosKit

/// What a drag carrying files means.
///
/// The editor reads the pasteboard, which is AppKit's and cannot be built here.
/// What is *decided* about the URLs it yields is what these assert, because those
/// decisions are where a drop can be wrong in a way somebody would act on.
struct DroppedFilesTests {
	/// A browser puts a web address on the drag board, and `NSURL` reads it
	/// perfectly well. Opening a tab for it would name a file that is not there.
	@Test func aWebAddressIsNotAFileToOpen() throws {
		let web = try #require(URL(string: "https://example.com/page.html"))
		let file = URL(fileURLWithPath: "/tmp/notes.md")

		#expect(DroppedFiles.filesOnly([web, file]) == [file])
		#expect(DroppedFiles.filesOnly([web]).isEmpty)
	}

	/// The order a drag carries them in is the order they open in, so the last
	/// one dropped is the one in front.
	@Test func theOrderIsKept() {
		let a = URL(fileURLWithPath: "/tmp/a.txt")
		let b = URL(fileURLWithPath: "/tmp/b.txt")
		let c = URL(fileURLWithPath: "/tmp/c.txt")
		#expect(DroppedFiles.filesOnly([a, b, c]) == [a, b, c])
	}

	/// A folder means a project and a file means a file; a drag holding both is
	/// not a case to invent behaviour for.
	@Test func aMixedDragSeparatesFoldersFromFiles() {
		let folder = URL(fileURLWithPath: "/tmp/a-project")
		let file = URL(fileURLWithPath: "/tmp/a-project/main.swift")
		let known: [String: Bool] = [folder.path: true, file.path: false]

		let (folders, files) = DroppedFiles.separate([file, folder]) { known[$0.path] }
		#expect(folders == [folder])
		#expect(files == [file])
	}

	/// Something that is not there is neither, and is left out rather than
	/// opened as an empty tab.
	@Test func somethingThatIsNotThereIsNeither() {
		let gone = URL(fileURLWithPath: "/tmp/deleted-since")
		let (folders, files) = DroppedFiles.separate([gone]) { _ in nil }
		#expect(folders.isEmpty)
		#expect(files.isEmpty)
	}

	/// And against the real file system, so the default check is exercised too.
	@Test func separatesWhatIsActuallyOnTheDisk() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("dropped-\(UUID().uuidString)", isDirectory: true)
		let inner = root.appendingPathComponent("inner", isDirectory: true)
		try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let file = root.appendingPathComponent("one.txt")
		try "x".write(to: file, atomically: true, encoding: .utf8)

		let (folders, files) = DroppedFiles.separate([file, inner, root])
		#expect(files == [file])
		#expect(folders == [inner, root])
	}
}
