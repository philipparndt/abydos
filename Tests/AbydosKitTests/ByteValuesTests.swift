import Foundation
import Testing
@testable import AbydosKit

/// What the inspector says about the bytes at the caret.
struct ByteValuesTests {
	private func snapshot(_ values: UInt8...) -> ByteDocument.Snapshot {
		ByteDocument(bytes: Data(values)).snapshot()
	}

	@Test func aThirtyTwoBitIntegerReadsBothWays() {
		let bytes = snapshot(0x01, 0x00, 0x00, 0x00)
		#expect(ByteValues.integer(UInt32.self, at: 0, in: bytes, order: .little) == 1)
		#expect(ByteValues.integer(UInt32.self, at: 0, in: bytes, order: .big) == 16_777_216)
	}

	@Test func aNegativeNumberIsSigned() {
		let bytes = snapshot(0xFF, 0xFF)
		#expect(ByteValues.integer(Int16.self, at: 0, in: bytes, order: .little) == -1)
		#expect(ByteValues.integer(UInt16.self, at: 0, in: bytes, order: .little) == 65535)
	}

	@Test func aTimeIsSaidInUTC() {
		let bytes = ByteDocument(bytes: ByteValues.bytes(of: UInt32(1_700_000_000), order: .little)).snapshot()
		let reading = ByteValues.reading(.unixTime32, at: 0, in: bytes, order: .little, encoding: .ascii)
		#expect(reading.text == "2023-11-14 22:13:20 UTC")
		#expect(reading.length == 4)
	}

	@Test func aNumberThatIsNotATimeSaysSo() {
		#expect(ByteValues.unixTime(Int64.max) == "not a time")
	}

	/// The last byte has an 8-bit value and nothing wider.
	@Test func atTheEndTheWiderReadingsAreUnavailableRatherThanPadded() {
		let bytes = snapshot(0x00, 0x01)
		let readings = ByteValues.readings(at: 1, in: bytes, order: .little, encoding: .ascii)
		let byName = Dictionary(uniqueKeysWithValues: readings.map { ($0.field, $0) })
		#expect(byName[.uint8]?.text == "1")
		#expect(byName[.uint16]?.text == nil)
		#expect(byName[.uint16]?.unavailable == "needs 2 bytes")
		#expect(byName[.float64]?.text == nil)
		#expect(byName[.binary]?.text == "00000001")
	}

	@Test func aFloatReadsAsTheShortestTextThatIsIt() {
		let bytes = ByteDocument(bytes: ByteValues.bytes(of: Float(0.1).bitPattern, order: .little)).snapshot()
		let reading = ByteValues.reading(.float32, at: 0, in: bytes, order: .little, encoding: .ascii)
		#expect(reading.text == "0.1")
	}

	@Test func anLEB128IsReadWithItsLength() {
		// 624485 in LEB128 is E5 8E 26.
		let bytes = snapshot(0xE5, 0x8E, 0x26, 0x00)
		let value = ByteValues.leb128(at: 0, in: bytes)
		#expect(value?.0 == 624_485)
		#expect(value?.1 == 3)
		// A continuation bit at the end of the file is not a number.
		#expect(ByteValues.leb128(at: 0, in: snapshot(0x80)) == nil)
	}

	@Test func aCharacterIsReadInTheColumnsEncoding() {
		let euro = snapshot(0xE2, 0x82, 0xAC)
		#expect(ByteEncoding.utf8.character(at: 0, in: euro)?.0 == "€")
		#expect(ByteEncoding.utf8.character(at: 0, in: euro)?.1 == 3)
		#expect(ByteEncoding.ascii.character(at: 0, in: euro) == nil)
		#expect(ByteEncoding.latin1.character(at: 0, in: snapshot(0xE9))?.0 == "é")
		#expect(ByteEncoding.utf16LittleEndian.character(at: 0, in: snapshot(0x41, 0x00))?.0 == "A")
	}

	@Test func aTypedValueBecomesBytesInTheChosenOrder() throws {
		#expect(try ByteValues.encode("258", as: .uint16, order: .little).get() == Data([0x02, 0x01]))
		#expect(try ByteValues.encode("258", as: .uint16, order: .big).get() == Data([0x01, 0x02]))
		#expect(try ByteValues.encode("-1", as: .int8, order: .little).get() == Data([0xFF]))
		#expect(try ByteValues.encode("0xFF", as: .uint8, order: .little).get() == Data([0xFF]))
		#expect(try ByteValues.encode("1.0", as: .float32, order: .big).get() == Data([0x3F, 0x80, 0x00, 0x00]))
	}

	/// "300 does not fit" rather than "300 is not a number", which it is.
	@Test func aValueThatDoesNotFitSaysSoInThoseWords() {
		guard case .failure(let problem) = ByteValues.encode("300", as: .uint8, order: .little) else {
			Issue.record("300 fitted in a byte")
			return
		}
		#expect(problem.said == "300 does not fit in UInt8")
		guard case .failure(let other) = ByteValues.encode("many", as: .uint8, order: .little) else {
			Issue.record("“many” was a number")
			return
		}
		#expect(other.said == "“many” is not a number")
	}
}

/// Finding bytes, in chunks, across seams.
struct ByteSearchTests {
	private func document(_ bytes: [UInt8]) -> ByteDocument.Snapshot {
		ByteDocument(bytes: Data(bytes)).snapshot()
	}

	@Test func aHexPatternWithAWildcardFindsEveryVariant() throws {
		// Three ZIP-shaped signatures with different third bytes and one that
		// differs in the fourth, which must not match.
		let bytes: [UInt8] = [0x50, 0x4B, 0x03, 0x04, 0, 0, 0x50, 0x4B, 0x07, 0x04, 0, 0x50, 0x4B, 0x03, 0x05, 0x50, 0x4B, 0x01, 0x04]
		let pattern = try BytePattern.hex("50 4B ?? 04").get()
		#expect(pattern.said == "50 4B ?? 04")
		#expect(ByteSearch.matches(of: pattern, in: document(bytes)) == [0, 6, 15])
	}

	@Test func aNumberIsFoundInItsByteOrderAndNotTheOther() throws {
		var bytes = [UInt8](repeating: 0, count: 0x40)
		bytes += [0xE8, 0x03, 0x00, 0x00]
		let snapshot = document(bytes)
		let little = try BytePattern.number("1000", width: 32, order: .little).get()
		let big = try BytePattern.number("1000", width: 32, order: .big).get()
		#expect(ByteSearch.matches(of: little, in: snapshot) == [0x40])
		#expect(ByteSearch.matches(of: big, in: snapshot).isEmpty)
	}

	@Test func textIsFoundInTheEncodingAsked() throws {
		let bytes = Array("--usage: thing--".utf8)
		let ascii = try BytePattern.text("usage", encoding: .ascii).get()
		#expect(ByteSearch.matches(of: ascii, in: document(bytes)) == [2])
		let wide = try BytePattern.text("AB", encoding: .utf16LittleEndian).get()
		#expect(wide.bytes == [0x41, 0x00, 0x42, 0x00])
	}

	/// The seam between two chunks, and the seam between two pieces of an
	/// edited document, are the same seam.
	@Test func aMatchAcrossAChunkBoundaryIsFoundOnce() throws {
		var bytes = [UInt8](repeating: 0xAA, count: 100)
		bytes.replaceSubrange(30..<34, with: [1, 2, 3, 4])
		bytes.replaceSubrange(62..<66, with: [1, 2, 3, 4])
		let pattern = try BytePattern.hex("01020304").get()
		#expect(ByteSearch.matches(of: pattern, in: document(bytes), chunk: 32) == [30, 62])
		#expect(ByteSearch.matches(of: pattern, in: document(bytes), chunk: 7) == [30, 62])

		// The same file with an edit in the middle of the second match.
		let edited = ByteDocument(bytes: Data(bytes))
		edited.overwrite(Data([3]), at: 64)
		#expect(edited.pieceCountForTesting == 3)
		#expect(ByteSearch.matches(of: pattern, in: edited.snapshot()) == [30, 62])
	}

	@Test func halfAByteIsRefusedInASentence() {
		guard case .failure(let problem) = BytePattern.hex("50 4") else {
			Issue.record("half a byte was searched")
			return
		}
		#expect(problem.said == "“50 4” is not whole bytes")
		guard case .failure(let hex) = BytePattern.hex("5G") else {
			Issue.record("5G was hex")
			return
		}
		#expect(hex.said == "“5g” is not hex")
	}

	@Test func aNumberTooWideForItsWidthIsRefused() {
		guard case .failure(let problem) = BytePattern.number("70000", width: 16, order: .little) else {
			Issue.record("70000 fitted in 16 bits")
			return
		}
		#expect(problem.said == "70000 does not fit in 16 bits")
	}

	@Test func aPatternOfOnlyWildcardsIsCapped() throws {
		let pattern = try BytePattern.hex("????").get()
		let found = ByteSearch.matches(of: pattern, in: document([UInt8](repeating: 0, count: 50)), limit: 10)
		#expect(found.count == 10)
	}

	@Test func theStreamDeliversProgressAndFinishes() async throws {
		var bytes = [UInt8](repeating: 0, count: 300)
		bytes[10] = 0x7F
		bytes[250] = 0x7F
		let pattern = try BytePattern.hex("7F").get()
		var found: [Int] = []
		var last: ByteSearch.Progress?
		for await batch in ByteSearch.search(for: pattern, in: document(bytes), chunk: 100) {
			found += batch.found
			last = batch
		}
		#expect(found == [10, 250])
		#expect(last?.finished == true)
		#expect(last?.scanned == 300)
		#expect(last?.fraction == 1)
	}
}

/// The strings list.
struct PrintableStringsTests {
	@Test func runsOfFourOrMoreAreListedWithTheirOffsets() {
		var bytes: [UInt8] = [0, 1, 2]
		bytes += Array("usage: thing".utf8)
		bytes += [0, 0xFF]
		bytes += Array("ok".utf8)
		bytes += [0]
		bytes += Array("done".utf8)
		let listing = PrintableStrings.list(in: ByteDocument(bytes: Data(bytes)).snapshot())
		#expect(listing.strings.map(\.text) == ["usage: thing", "done"])
		#expect(listing.strings.first?.offset == 3)
		#expect(listing.strings.first?.length == 12)
		#expect(listing.unlisted == 0)
	}

	@Test func theCapIsSaidRatherThanSilent() {
		var bytes: [UInt8] = []
		for _ in 0..<10 { bytes += Array("word".utf8) + [0] }
		let listing = PrintableStrings.list(in: ByteDocument(bytes: Data(bytes)).snapshot(), cap: 3)
		#expect(listing.strings.count == 3)
		#expect(listing.unlisted == 7)
	}

	@Test func wideStringsAreFoundOnEitherAlignment() {
		var bytes: [UInt8] = [0x00]
		for character in "Hello".utf8 { bytes += [character, 0] }
		bytes += [0x99, 0x99]
		let listing = PrintableStrings.list(
			in: ByteDocument(bytes: Data(bytes)).snapshot(), encoding: .utf16LittleEndian
		)
		#expect(listing.strings.map(\.text) == ["Hello"])
		#expect(listing.strings.first?.offset == 1)
	}

	@Test func utf8RunsKeepTheirMultibyteCharacters() {
		let bytes = [0] + Array("Größe".utf8) + [0]
		let listing = PrintableStrings.list(in: ByteDocument(bytes: Data(bytes)).snapshot(), encoding: .utf8)
		#expect(listing.strings.map(\.text) == ["Größe"])
	}
}
