import Testing
import Foundation
@testable import IdeaiKit

/// The rope is validated against plain `String`/`Array<UInt8>` as a reference
/// model. Anything the rope reports must match what the naive version says.
struct RopeTests {
	// MARK: - Basics

	@Test func emptyRope() {
		let r = Rope()
		#expect(r.byteCount == 0)
		#expect(r.lineCount == 1)
		#expect(r.string == "")
		#expect(r.isEmpty)
	}

	@Test func roundTripsSmallText() {
		let text = "hello\nworld\n"
		let r = Rope(text)
		#expect(r.string == text)
		#expect(r.byteCount == text.utf8.count)
		#expect(r.lineCount == 3) // trailing newline does not open a line
	}

	@Test func roundTripsTextLargerThanOneChunk() {
		// Force a multi-level tree.
		let line = "let x = someFunction(argument, another) // padding padding\n"
		let text = String(repeating: line, count: 5_000)
		let r = Rope(text)
		#expect(r.string == text)
		#expect(r.byteCount == text.utf8.count)
		#expect(r.lineCount == 5_001)
	}

	// MARK: - Unicode

	@Test func countsUTF16ForNonASCII() {
		// "é" is 2 UTF-8 bytes / 1 UTF-16 unit; "𝄞" is 4 bytes / 2 units (surrogate pair).
		let text = "aé𝄞b"
		let r = Rope(text)
		#expect(r.byteCount == text.utf8.count)
		#expect(r.utf16Count == text.utf16.count)
	}

	@Test func convertsBetweenByteAndUTF16Offsets() {
		let text = "aé𝄞b\nsecond é line\n𝄞"
		let r = Rope(text)

		// Walk every UTF-16 offset and compare against Foundation's own mapping.
		let ns = text as NSString
		for u in 0...ns.length {
			// Skip offsets that land inside a surrogate pair.
			if u > 0 && u < ns.length {
				let c = ns.character(at: u)
				if c >= 0xDC00 && c <= 0xDFFF { continue }
			}
			let byte = r.byteOffset(fromUTF16: u)
			#expect(r.utf16Offset(fromByte: byte) == u, "utf16 \(u) round-trip")
		}
	}

	@Test func chunkBoundariesNeverSplitCodepoints() {
		// Multi-byte characters repeated past the chunk size; if a chunk boundary
		// split a codepoint the decoded string would contain replacement chars.
		let text = String(repeating: "héllo wörld 𝄞 ", count: 2_000)
		let r = Rope(text)
		#expect(r.string == text)
		#expect(!r.string.contains("\u{FFFD}"))
	}

	// MARK: - Lines

	@Test func lineLookupsMatchReference() {
		let text = (0..<800).map { "line \($0) with some trailing content" }.joined(separator: "\n")
		let r = Rope(text)
		let expected = text.components(separatedBy: "\n")

		#expect(r.lineCount == expected.count)
		for i in 0..<expected.count {
			#expect(r.lineText(i) == expected[i], "line \(i)")
		}
	}

	@Test func lineForByteOffsetMatchesReference() {
		let text = "alpha\nbeta\ngamma\ndelta"
		let r = Rope(text)
		let bytes = Array(text.utf8)

		for offset in 0...bytes.count {
			let expected = bytes[0..<offset].filter { $0 == 0x0A }.count
			#expect(r.line(atByteOffset: offset) == expected, "offset \(offset)")
		}
	}

	@Test func lineTextStripsCRLF() {
		let r = Rope("alpha\r\nbeta\r\n")
		#expect(r.lineText(0) == "alpha")
		#expect(r.lineText(1) == "beta")
	}

	@Test func handlesFileWithoutTrailingNewline() {
		let r = Rope("a\nb")
		#expect(r.lineCount == 2)
		#expect(r.lineText(0) == "a")
		#expect(r.lineText(1) == "b")
	}

	@Test func handlesConsecutiveBlankLines() {
		let text = "a\n\n\nb\n"
		let r = Rope(text)
		#expect(r.lineCount == 5)
		#expect(r.lineText(1) == "")
		#expect(r.lineText(2) == "")
		#expect(r.lineText(3) == "b")
	}

	// MARK: - Editing

	@Test func insertsAndDeletesLikeReference() {
		var r = Rope("hello world")
		r.replace(byteRange: 5..<5, with: ",")
		#expect(r.string == "hello, world")

		r.replace(byteRange: 0..<6, with: "goodbye,")
		#expect(r.string == "goodbye, world")

		r.replace(byteRange: 0..<r.byteCount, with: "")
		#expect(r.string == "")
		#expect(r.lineCount == 1)
	}

	@Test func editsKeepMetricsConsistent() {
		var r = Rope(String(repeating: "abcdefgh\n", count: 3_000))
		var reference = r.string

		// A deterministic pseudo-random edit sequence; each step is checked in full.
		var seed: UInt64 = 0x2545F4914F6CDD1D
		func next(_ bound: Int) -> Int {
			seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
			return bound == 0 ? 0 : Int(seed % UInt64(bound))
		}

		for step in 0..<200 {
			let refBytes = Array(reference.utf8)
			let lo = next(refBytes.count + 1)
			let hi = min(refBytes.count, lo + next(40))
			let inserted = step % 3 == 0 ? "XY\nZ" : "q"

			r.replace(byteRange: lo..<hi, with: inserted)

			var newRef = Array(refBytes[0..<lo])
			newRef.append(contentsOf: Array(inserted.utf8))
			newRef.append(contentsOf: Array(refBytes[hi...]))
			reference = String(decoding: newRef, as: UTF8.self)

			#expect(r.string == reference, "content diverged at step \(step)")
			#expect(r.byteCount == reference.utf8.count, "byteCount diverged at step \(step)")
			#expect(r.utf16Count == reference.utf16.count, "utf16Count diverged at step \(step)")
			#expect(r.lineCount == reference.components(separatedBy: "\n").count,
			        "lineCount diverged at step \(step)")
		}
	}

	@Test func staysBalancedUnderManyAppends() {
		var r = Rope()
		for i in 0..<4_000 {
			r.replace(byteRange: r.byteCount..<r.byteCount, with: "line \(i)\n")
		}
		#expect(r.lineCount == 4_001)

		// A degenerate (list-like) tree would have height ~n. Verify it stayed
		// logarithmic, which is what makes lookups fast.
		let height = r.root.height
		#expect(height < 40, "tree height \(height) suggests balancing failed")
	}

	@Test func staysBalancedUnderManyPrepends() {
		// Prepending is the adversarial case for a naively-joined rope.
		var r = Rope()
		for i in 0..<4_000 {
			r.replace(byteRange: 0..<0, with: "line \(i)\n")
		}
		#expect(r.lineCount == 4_001)
		#expect(r.root.height < 40, "tree height \(r.root.height) suggests balancing failed")
	}

	// MARK: - Snapshots

	@Test func snapshotsAreUnaffectedByLaterEdits() {
		// This is what lets a background parse read a stable version while typing
		// continues on the main thread.
		let original = Rope("original content\nsecond line\n")
		var edited = original
		edited.replace(byteRange: 0..<8, with: "CHANGED")

		#expect(original.string == "original content\nsecond line\n")
		#expect(edited.string.hasPrefix("CHANGED"))
	}

	// MARK: - Chunk reads

	@Test func chunkReadsCoverWholeRope() {
		let text = String(repeating: "some content for chunking\n", count: 1_000)
		let r = Rope(text)

		// Walking chunk-by-chunk is exactly how tree-sitter reads the buffer.
		var assembled = [UInt8]()
		var offset = 0
		while offset < r.byteCount {
			guard let (bytes, start) = r.chunk(containing: offset) else { break }
			let local = offset - start
			assembled.append(contentsOf: bytes[local...])
			offset = start + bytes.count
		}
		#expect(String(decoding: assembled, as: UTF8.self) == text)
	}

	@Test func subrangeReadsMatchReference() {
		let text = String(repeating: "0123456789", count: 500)
		let r = Rope(text)
		let bytes = Array(text.utf8)

		for (lo, hi) in [(0, 0), (0, 10), (5, 5000), (4999, 5000), (1234, 2345), (0, bytes.count)] {
			#expect(r.bytes(in: lo..<hi) == Array(bytes[lo..<hi]), "range \(lo)..<\(hi)")
		}
	}

	@Test func clampsOutOfBoundsRanges() {
		let r = Rope("short")
		#expect(r.bytes(in: -10..<2) == Array("sh".utf8))
		#expect(r.bytes(in: 3..<9_999) == Array("rt".utf8))
		#expect(r.bytes(in: 100..<200) == [])
	}
}

/// Sizing the horizontal scroll range. Byte length is the wrong unit: a tab is
/// one byte and several columns, so measuring bytes leaves the document too
/// narrow to scroll to the end of tab-indented code.
struct RopeDisplayWidthTests {
	@Test func plainLinesMeasureTheirLength() {
		let rope = Rope("abc\nabcdef\nab\n")
		#expect(rope.longestLineDisplayColumns(tabWidth: 4) == 6)
	}

	@Test func tabsExpandToTheNextStop() {
		// One tab, then "x": 4 + 1 columns.
		#expect(Rope("\tx\n").longestLineDisplayColumns(tabWidth: 4) == 5)
		#expect(Rope("ab\tx\n").longestLineDisplayColumns(tabWidth: 4) == 5)
	}

	@Test func tabWidthIsRespected() {
		#expect(Rope("\tx\n").longestLineDisplayColumns(tabWidth: 8) == 9)
	}

	/// A multi-byte character is one column, not one per byte.
	@Test func multiByteCharactersCountOnce() {
		#expect(Rope("über\n").longestLineDisplayColumns(tabWidth: 4) == 4)
		#expect(Rope("日本語\n").longestLineDisplayColumns(tabWidth: 4) == 3)
	}

	@Test func theLastLineCountsWithoutATrailingNewline() {
		#expect(Rope("a\nlongest").longestLineDisplayColumns(tabWidth: 4) == 7)
	}

	@Test func anEmptyRopeIsZeroWide() {
		#expect(Rope("").longestLineDisplayColumns(tabWidth: 4) == 0)
	}
}

/// Re-reading a file that something else wrote.
struct ExternalChangeTests {
	private func makeFile(_ contents: String) throws -> URL {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-external-\(UUID().uuidString).txt")
		try contents.write(to: url, atomically: true, encoding: .utf8)
		return url
	}

	@Test func anUntouchedFileReportsNoChange() throws {
		let document = try TextDocument(url: makeFile("one\ntwo\n"))
		#expect(!document.hasChangedOnDisk)
		#expect(try document.reloadFromDisk() == false)
	}

	@Test func aWrittenFileIsDetectedAndReloaded() throws {
		let url = try makeFile("one\n")
		let document = try TextDocument(url: url)

		try "one\ntwo\nthree\n".write(to: url, atomically: true, encoding: .utf8)
		#expect(document.hasChangedOnDisk)
		#expect(try document.reloadFromDisk() == true)
		#expect(document.lineCount == 4)
		#expect(document.rope.lineText(1) == "two")
	}

	/// An agent that rewrites a file twice in the same second is not unusual,
	/// and a date alone would call the second write unchanged.
	@Test func aSameSecondRewriteOfADifferentLengthIsDetected() throws {
		let url = try makeFile("aaaa\n")
		let document = try TextDocument(url: url)

		let date = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
		try "bb\n".write(to: url, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.modificationDate: date as Any], ofItemAtPath: url.path)

		#expect(document.hasChangedOnDisk)
	}

	/// Saving is agreement with the file, not a change to react to — otherwise
	/// every save would trigger a reload of what was just written.
	@Test func savingDoesNotLookLikeAnExternalChange() throws {
		let document = try TextDocument(url: makeFile("one\n"))
		document.replace(utf16Range: 0..<0, with: "new ", caretBefore: 0)
		try document.save()
		#expect(!document.hasChangedOnDisk)
	}

	/// A deleted file is not something to reload: doing so would replace the
	/// buffer with nothing.
	@Test func aDeletedFileIsNotAChange() throws {
		let url = try makeFile("one\n")
		let document = try TextDocument(url: url)
		try FileManager.default.removeItem(at: url)
		#expect(!document.hasChangedOnDisk)
	}

	@Test func reloadingClearsTheDirtyFlag() throws {
		let url = try makeFile("one\n")
		let document = try TextDocument(url: url)
		document.replace(utf16Range: 0..<0, with: "local ", caretBefore: 0)
		#expect(document.isDirty)

		try "external\n".write(to: url, atomically: true, encoding: .utf8)
		#expect(try document.reloadFromDisk() == true)
		#expect(!document.isDirty)
		#expect(document.rope.lineText(0) == "external")
	}
}

/// The sequence that matters: an agent rewrites the file, then the user types.
/// The saved result has to contain both, not one overwriting the other.
struct ExternalChangeThenLocalEditTests {
	@Test func aLocalEditLandsOnTopOfTheExternalOne() throws {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-merge-\(UUID().uuidString).swift")
		try "let a = 1\n".write(to: url, atomically: true, encoding: .utf8)

		let document = try TextDocument(url: url)

		// The agent writes while the file is open and unmodified.
		try "// agent\nlet a = 1\n".write(to: url, atomically: true, encoding: .utf8)
		#expect(try document.reloadFromDisk() == true)

		// The user then types, and saves.
        _ = document.replace(
			utf16Range: document.rope.utf16Count..<document.rope.utf16Count,
			with: "let b = 2\n",
			caretBefore: document.rope.utf16Count
		)
		try document.save()

		let saved = try String(contentsOf: url, encoding: .utf8)
		#expect(saved == "// agent\nlet a = 1\nlet b = 2\n")
	}

	/// Without the reload, the buffer still holds the pre-agent text and saving
	/// would write the agent's work away — which is the failure this exists to
	/// prevent.
	@Test func savingWithoutReloadingWouldDiscardTheExternalEdit() throws {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("ideai-clobber-\(UUID().uuidString).swift")
		try "let a = 1\n".write(to: url, atomically: true, encoding: .utf8)

		let document = try TextDocument(url: url)
		try "// agent\nlet a = 1\n".write(to: url, atomically: true, encoding: .utf8)

		// No reload: save writes what the buffer still holds.
		try document.save()
		#expect(try String(contentsOf: url, encoding: .utf8) == "let a = 1\n")
	}
}
