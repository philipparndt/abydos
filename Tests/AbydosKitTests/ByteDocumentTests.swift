import Foundation
import Testing
@testable import AbydosKit

/// A file edited as bytes, without ever being copied.
///
/// The claim under all of these is the design's: an edit is a split of a
/// piece list, so a one-byte change to a gigabyte costs bytes, and a save
/// writes the pieces through a temporary rather than over the mapping this
/// process is reading from.
struct ByteDocumentTests {
	private func scratch(_ name: String) throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("bytes-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory.appendingPathComponent(name)
	}

	private func bytes(_ values: UInt8...) -> Data { Data(values) }

	@Test func aByteIsOverwrittenAndTheRestStayWhereTheyWere() {
		let document = ByteDocument(bytes: bytes(0, 1, 2, 3, 4))
		document.overwrite(bytes(0xFF), at: 2)
		#expect(document.bytes(in: 0..<5) == bytes(0, 1, 0xFF, 3, 4))
		#expect(document.count == 5)
		#expect(document.editedRanges == [2..<3])
		#expect(document.isDirty)
	}

	@Test func anInsertShiftsEverythingAfterItByOne() {
		let document = ByteDocument(bytes: bytes(0, 1, 2, 3))
		document.insert(bytes(0x41), at: 1)
		#expect(document.bytes(in: 0..<5) == bytes(0, 0x41, 1, 2, 3))
		#expect(document.count == 5)
	}

	@Test func aDeleteClosesTheGap() {
		let document = ByteDocument(bytes: bytes(0, 1, 2, 3, 4))
		document.delete(1..<3)
		#expect(document.bytes(in: 0..<3) == bytes(0, 3, 4))
		#expect(document.count == 3)
		#expect(document.editedRanges.isEmpty)
	}

	/// Typing at the last byte is how a byte is added to a file.
	@Test func anOverwritePastTheEndAppends() {
		let document = ByteDocument(bytes: bytes(0, 1))
		document.overwrite(bytes(2, 3), at: 2)
		#expect(document.bytes(in: 0..<4) == bytes(0, 1, 2, 3))
	}

	@Test func undoPutsTheBytesBackAndRedoTakesThemAgain() {
		let document = ByteDocument(bytes: bytes(0, 1, 2))
		let undo = UndoManager()
		undo.groupsByEvent = false
		document.undoManager = undo

		undo.beginUndoGrouping()
		document.overwrite(bytes(9), at: 1)
		undo.endUndoGrouping()
		#expect(document.byte(at: 1) == 9)

		undo.undo()
		#expect(document.bytes(in: 0..<3) == bytes(0, 1, 2))
		#expect(document.editedRanges.isEmpty)

		undo.redo()
		#expect(document.byte(at: 1) == 9)
		#expect(document.editedRanges == [1..<2])
	}

	/// A hundred typed bytes are one piece, not two hundred.
	@Test func bytesTypedOneAfterAnotherCoalesceIntoOneRun() {
		let document = ByteDocument(bytes: Data(count: 1000))
		for offset in 100..<200 {
			document.overwrite(bytes(UInt8(offset & 0xFF)), at: offset)
		}
		#expect(document.pieceCountForTesting == 3)
		#expect(document.editedRanges == [100..<200])
		#expect(document.byte(at: 150) == 150)
	}

	@Test func aRunIsASliceAndNotACopy() {
		let document = ByteDocument(bytes: Data(count: 4096))
		document.overwrite(bytes(1), at: 1000)
		#expect(document.run(at: 0).count == 1000)
		#expect(document.run(at: 1000).count == 1)
		#expect(document.run(at: 1001).count == 3095)
		#expect(document.run(at: 4096).isEmpty)
	}

	@Test func aSnapshotDoesNotMoveWhileTheDocumentIsEdited() {
		let document = ByteDocument(bytes: bytes(0, 1, 2, 3))
		let before = document.snapshot()
		document.overwrite(bytes(0xEE), at: 0)
		document.insert(bytes(0xDD), at: 4)
		#expect(before.bytes(in: 0..<4) == bytes(0, 1, 2, 3))
		#expect(before.count == 4)
		#expect(document.count == 5)
	}

	@Test func aSaveWritesTheFileByteForByteAndClearsTheMarks() throws {
		let url = try scratch("file.bin")
		var content = Data((0..<10_000).map { UInt8($0 & 0xFF) })
		try content.write(to: url)

		let document = try ByteDocument(url: url)
		document.overwrite(bytes(0xAA, 0xBB, 0xCC), at: 5000)
		document.insert(bytes(0x11), at: 0)
		document.delete(9999..<10_001)
		try document.save()

		content.replaceSubrange(5000..<5003, with: bytes(0xAA, 0xBB, 0xCC))
		content.insert(0x11, at: 0)
		content.removeSubrange(9999..<10_001)
		#expect(try Data(contentsOf: url) == content)
		#expect(!document.isDirty)
		#expect(document.editedRanges.isEmpty)
		#expect(document.count == content.count)
		#expect(document.byte(at: 5001) == 0xAA)

		let again = try ByteDocument(url: url)
		#expect(again.bytes(in: 0..<again.count) == content)
	}

	/// The temporary is beside the file, and is gone afterwards either way.
	@Test func aSaveLeavesNoTemporaryBehind() throws {
		let url = try scratch("tidy.bin")
		try bytes(1, 2, 3).write(to: url)
		let document = try ByteDocument(url: url)
		document.overwrite(bytes(9), at: 0)
		try document.save()
		let left = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
		#expect(left == ["tidy.bin"])
	}

	@Test func aByteDocumentNeverAutoSaves() throws {
		let url = try scratch("never.bin")
		try bytes(1, 2, 3).write(to: url)
		let document = try ByteDocument(url: url)
		document.overwrite(bytes(9), at: 0)
		#expect(document.autoSaveIfNeeded() == false)
		#expect(try Data(contentsOf: url) == bytes(1, 2, 3))
		#expect(document.isDirty)
	}

	/// The design's claim, measured: a large file with one byte changed is
	/// two runs of the mapping and one byte of buffer, and the file was not
	/// read to do it.
	@Test func aOneByteEditToALargeFileCostsBytes() throws {
		let url = try scratch("large.bin")
		let size = 256 * 1024 * 1024
		// Sparse: the file system does not write the zeros, and neither does
		// this test wait for it to.
		let handle = try FileHandle(forWritingTo: {
			FileManager.default.createFile(atPath: url.path, contents: nil)
			return url
		}())
		try handle.seek(toOffset: UInt64(size - 1))
		try handle.write(contentsOf: bytes(0))
		try handle.close()

		let footprintBefore = residentMemory()
		let document = try ByteDocument(url: url)
		document.overwrite(bytes(0x42), at: size / 2)
		let grown = residentMemory() - footprintBefore

		#expect(document.pieceCountForTesting == 3)
		#expect(document.count == size)
		#expect(document.byte(at: size / 2) == 0x42)
		print("ByteDocumentTests: a one-byte edit to \(size >> 20) MB grew the process by "
			+ "\(grown >> 10) KB. \(MachineLoad.said)")
		// Bytes, not the file: the whole mapping being touched would be 256 MB.
		#expect(grown < 32 * 1024 * 1024)
	}

	private func residentMemory() -> Int {
		var info = mach_task_basic_info()
		var count = mach_msg_type_number_t(
			MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
		)
		let result = withUnsafeMutablePointer(to: &info) {
			$0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
				task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
			}
		}
		return result == KERN_SUCCESS ? Int(info.resident_size) : 0
	}
}
