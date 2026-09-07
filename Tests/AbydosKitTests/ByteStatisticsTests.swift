import Foundation
import Testing
@testable import AbydosKit

/// One pass over the file, and what everything draws from it.
struct ByteStatisticsTests {
	/// Deterministic noise: a linear congruential generator, so the test's
	/// "random" half is the same bytes every run.
	private func noise(_ count: Int, seed: UInt64 = 42) -> [UInt8] {
		var state = seed
		return (0..<count).map { _ in
			state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
			return UInt8(truncatingIfNeeded: state >> 33)
		}
	}

	@Test func theBlockSizeAimsAtAboutFourThousandBlocks() {
		#expect(ByteStatistics.blockSize(for: 100) == 16)
		#expect(ByteStatistics.blockSize(for: 64 * 1024) == 16)
		#expect(ByteStatistics.blockSize(for: 1 << 30) == 256 * 1024)
		let table = ByteStatistics(count: 1 << 30)
		#expect(table.blocks.count == 4096)
	}

	@Test func aBlockOfOneByteValueHasNoEntropyAndABlockOfNoiseHasNearlyEight() {
		let zeros = ByteStatistics.Block(of: Data(count: 4096))
		#expect(zeros.entropy == 0)
		#expect(zeros.zero == 4096)
		let random = ByteStatistics.Block(of: Data(noise(65536)))
		#expect(random.entropy > 7.9)
		#expect(random.high > 30_000)
	}

	@Test func theClassesAddUpToTheBlock() {
		let block = ByteStatistics.Block(of: Data([0, 0x41, 0x42, 0x01, 0x7F, 0xFF, 0x20]))
		#expect(block.zero == 1)
		#expect(block.printable == 3)
		#expect(block.control == 2)
		#expect(block.high == 1)
		#expect(block.length == 7)
	}

	@Test func aTextHeaderOverACompressedTailIsLowThenHighWithOneNote() {
		let header = Array(String(repeating: "the quick brown fox jumps over the lazy dog\n", count: 200).utf8)
		let tail = noise(header.count)
		let snapshot = ByteDocument(bytes: Data(header + tail)).snapshot()
		let table = ByteStatistics.computed(over: snapshot, blockSize: 256)

		let first = table.blocks[1]!, last = table.blocks[table.blocks.count - 2]!
		#expect(first.entropy < 5)
		#expect(last.entropy > 7)

		// One note, beginning in the group the noise starts in and running to
		// the end of the file.
		let notes = table.notes
		#expect(notes.count == 1)
		#expect((notes.first?.range.lowerBound ?? -1) > header.count - ByteStatistics.groupBytes)
		#expect((notes.first?.range.lowerBound ?? -1) <= header.count)
		#expect(notes.first?.range.upperBound == header.count + tail.count)
		#expect(notes.first?.said.contains("likely compressed or encrypted") == true)
	}

	/// A sixteen-byte block cannot read above four bits; the curve reads the
	/// kilobyte behind each block, and says 7.8 over noise as the note does.
	/// Before this, the curve sat at 3.9 over a file the note called 7.86.
	@Test func theCurveReadsAWindowAndNotABlock() {
		let table = ByteStatistics.computed(over: ByteDocument(bytes: Data(noise(8192))).snapshot())
		#expect(table.blockSize == 16)
		#expect(table.blocksPerWindow == 64)
		#expect((table.blocks[100]!).entropy < 4.1)
		#expect(table.curve(at: 100)! > 7.6)
		#expect(table.windowRange(ofBlock: 100) == (37 * 16)..<(101 * 16))
		// The first blocks have less than a window behind them and say so by
		// reading lower; by the sixty-fourth the window is whole.
		#expect(table.curve(at: 0)! < 4.1)
		#expect(table.curve(at: 63)! > 7.6)
	}

	/// A pass that starts mid-file warms its window with the blocks before
	/// it, so a recomputed stretch reads as it would have in the first pass.
	@Test func aPassStartingMidFileHasWholeWindows() async {
		let snapshot = ByteDocument(bytes: Data(noise(8192))).snapshot()
		let whole = ByteStatistics.computed(over: snapshot)
		var partial = ByteStatistics(count: 8192)
		for await delivery in ByteStatistics.pass(over: snapshot, blockSize: 16, indices: 256..<320) {
			partial.set(delivery)
		}
		#expect(partial.curve(at: 256) == whole.curve(at: 256))
		#expect(partial.curve(at: 319) == whole.curve(at: 319))
	}

	/// The curve may show sixteen-byte blocks; the note may not read them.
	@Test func aNoteIsNeverMadeFromBlocksTooSmallToJudge() {
		let table = ByteStatistics.computed(over: ByteDocument(bytes: Data(noise(600))).snapshot())
		#expect(table.blockSize == 16)
		#expect((table.blocks.first!!).entropy < 4.1)
		#expect(table.notes.isEmpty)
		let larger = ByteStatistics.computed(over: ByteDocument(bytes: Data(noise(8192))).snapshot())
		#expect(larger.notes.count == 1)
		#expect(larger.notes.first?.range == 0..<8192)
	}

	@Test func anEditRecomputesTheBlocksItTouchedAndNoOthers() {
		var table = ByteStatistics.computed(over: ByteDocument(bytes: Data(count: 10_000)).snapshot(), blockSize: 16)
		// Block 6, widened to its group of 256 blocks: the group's entropy is
		// recomputed from its first block.
		let stale = table.invalidate(100..<101, delta: 0)
		#expect(stale == 0..<256)
		#expect(table.completedBlocks == table.blocks.count - 256)
		#expect(table.groups[0] == nil)
		#expect(table.groups[1] != nil)
		// An insert moves everything after it.
		let shifted = table.invalidate(5000..<5001, delta: 1)
		#expect(shifted == 256..<table.blocks.count)
	}

	@Test func thePassDeliversInOrderAndCanBeStopped() async {
		let snapshot = ByteDocument(bytes: Data(noise(4096))).snapshot()
		var seen: [Int] = []
		for await delivery in ByteStatistics.pass(over: snapshot, blockSize: 256, indices: 0..<16) {
			seen.append(delivery.index)
			if seen.count == 4 { break }
		}
		#expect(seen == [0, 1, 2, 3])
	}

	/// The design's claim about a large file, with the load beside it.
	@Test func thePassOverALargeFileIsSecondsNotMinutes() throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("stats-\(UUID().uuidString).bin")
		let size = 128 * 1024 * 1024
		FileManager.default.createFile(atPath: url.path, contents: nil)
		let handle = try FileHandle(forWritingTo: url)
		try handle.seek(toOffset: UInt64(size - 1))
		try handle.write(contentsOf: Data([1]))
		try handle.close()
		defer { try? FileManager.default.removeItem(at: url) }

		let snapshot = try ByteDocument(url: url).snapshot()
		let started = Date()
		let table = ByteStatistics.computed(over: snapshot)
		let took = Date().timeIntervalSince(started)
		print("ByteStatisticsTests: the pass over \(size >> 20) MB took \(String(format: "%.3f", took)) s. \(MachineLoad.said)")
		#expect(table.isComplete)
		#expect(table.blocks.count == 4096)
		if Stopwatch.maySay("ByteStatisticsTests", "the pass over 128 MB") {
			#expect(took < 3)
		}
	}
}

/// The digests, against numbers other people published.
struct ChecksumsTests {
	private func snapshot(_ text: String) -> ByteDocument.Snapshot {
		ByteDocument(bytes: Data(text.utf8)).snapshot()
	}

	@Test func theEmptyFilesDigestsAreTheKnownOnes() {
		let empty = snapshot("")
		#expect(Checksums.compute(.sha256, over: empty) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
		#expect(Checksums.compute(.md5, over: empty) == "d41d8cd98f00b204e9800998ecf8427e")
		#expect(Checksums.compute(.sha1, over: empty) == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
		#expect(Checksums.compute(.crc32, over: empty) == "00000000")
		#expect(Checksums.compute(.adler32, over: empty) == "00000001")
	}

	@Test func theCheckValuesFromTheStandardsHold() {
		#expect(Checksums.compute(.crc32, over: snapshot("123456789")) == "cbf43926")
		#expect(Checksums.compute(.adler32, over: snapshot("Wikipedia")) == "11e60398")
		#expect(Checksums.compute(.sha512, over: snapshot("abc"))?.hasPrefix("ddaf35a193617aba") == true)
	}

	@Test func aDigestOverTheSelectionIsOfThoseBytesOnly() {
		let whole = snapshot("xx123456789yy")
		#expect(Checksums.compute(.crc32, over: whole, range: 2..<11) == "cbf43926")
	}

	/// The pieces are streamed, so an edit is in the digest and a large
	/// Adler-32 sum does not overflow.
	@Test func anEditedDocumentHashesAsItsBytes() {
		let document = ByteDocument(bytes: Data("12345X789".utf8))
		document.overwrite(Data("6".utf8), at: 5)
		#expect(Checksums.compute(.crc32, over: document.snapshot()) == "cbf43926")
		let long = ByteDocument(bytes: Data(repeating: 0xFF, count: 100_000)).snapshot()
		#expect(Checksums.compute(.adler32, over: long) != nil)
	}

	@Test func aCancelledDigestIsNil() {
		let long = ByteDocument(bytes: Data(count: 1000)).snapshot()
		#expect(Checksums.compute(.sha256, over: long, isCancelled: { true }) == nil)
	}

	@Test func theStreamEndsInTheDigest() async {
		var last: Checksums.Progress?
		for await progress in Checksums.stream(.md5, over: snapshot("")) {
			last = progress
		}
		#expect(last?.result == "d41d8cd98f00b204e9800998ecf8427e")
		#expect(last?.fraction == 1)
	}
}
