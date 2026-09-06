import Foundation
import Testing
@testable import AbydosKit

/// The fourteen parsers, each over a file made here from the format's own
/// definition, small enough to read in the test.
struct BinaryFormatTests {
	private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
	private func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16 & 0xFFFF) }
	private func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
	private func be32(_ v: Int) -> [UInt8] { be16(v >> 16 & 0xFFFF) + be16(v & 0xFFFF) }
	private func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }
	private func padded(_ s: String, _ n: Int) -> [UInt8] { Array((ascii(s) + [UInt8](repeating: 0, count: n)).prefix(n)) }

	private func explain(_ bytes: [UInt8], _ ext: String = "") -> StructureNode? {
		BinaryFormats.explain(ByteDocument(bytes: Data(bytes)).snapshot(), extension: ext)
	}

	/// Depth-first, the first node with this name.
	private func find(_ node: StructureNode, _ name: String) -> StructureNode? {
		if node.name == name { return node }
		for child in node.children { if let found = find(child, name) { return found } }
		return nil
	}

	private func problems(_ node: StructureNode) -> [StructureNode] {
		(node.source == .problem ? [node] : []) + node.children.flatMap(problems)
	}

	// MARK: - Fixtures

	private var png: [UInt8] {
		[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
			+ be32(13) + ascii("IHDR") + be32(2) + be32(3) + [8, 6, 0, 0, 0] + be32(0x1234_5678)
			+ be32(0) + ascii("IDAT") + be32(0)
			+ be32(0) + ascii("IEND") + be32(0xAE42_6082)
	}

	@Test func aPNGsHeaderFieldsAreNamedAndTheCaretKnowsItsField() throws {
		let tree = try #require(explain(png, "png"))
		#expect(tree.name == "PNG")
		#expect(tree.children.map(\.name) == ["signature", "IHDR", "IDAT", "IEND"])
		let header = try #require(find(tree, "IHDR"))
		#expect(find(header, "width")?.value == "2")
		#expect(find(header, "height")?.value == "3")
		#expect(find(header, "colour")?.value == "RGBA")
		#expect(find(header, "width")?.range == 16..<20)
		#expect(tree.label(at: 0x10) == "IHDR › width")
		#expect(tree.label(at: 0x14) == "IHDR › height")
		#expect(tree.label(at: 0) == "signature")
		#expect(problems(tree).isEmpty)
	}

	@Test func aJPEGsFrameSaysItsSize() throws {
		let jpeg: [UInt8] = [0xFF, 0xD8]
			+ [0xFF, 0xE0] + be16(16) + ascii("JFIF") + [0, 1, 1, 0] + be16(1) + be16(1) + [0, 0]
			+ [0xFF, 0xC0] + be16(11) + [8] + be16(20) + be16(30) + [1] + [1, 0x11, 0]
			+ [0xFF, 0xD9]
		let tree = try #require(explain(jpeg))
		#expect(tree.children.map(\.name) == ["SOI", "APP0 JFIF", "SOF0 baseline frame", "EOI"])
		#expect(find(tree, "width")?.value == "30")
		#expect(find(tree, "height")?.value == "20")
		#expect(tree.label(at: 27) == "SOF0 baseline frame › frame › width")
	}

	@Test func aGIFHasItsScreenAndItsTrailer() throws {
		let gif = ascii("GIF89a") + le16(4) + le16(5) + [0, 0, 0] + [0x3B]
		let tree = try #require(explain(gif))
		#expect(tree.children.map(\.name) == ["header", "logical screen", "trailer"])
		#expect(find(tree, "width")?.value == "4")
	}

	@Test func aBMPNamesItsDIBHeader() throws {
		let bmp = ascii("BM") + le32(30) + le16(0) + le16(0) + le32(26)
			+ le32(12) + le16(1) + le16(1) + le16(1) + le16(24) + [0, 0, 0, 0]
		let tree = try #require(explain(bmp))
		#expect(tree.children.map(\.name) == ["file header", "BITMAPCOREHEADER", "pixel data"])
		#expect(find(tree, "bits per pixel")?.value == "24")
	}

	private func zipEntry(_ name: String, _ content: String) -> [UInt8] {
		[0x50, 0x4B, 0x03, 0x04] + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0)
			+ le32(content.utf8.count) + le32(content.utf8.count) + le16(name.utf8.count) + le16(0)
			+ ascii(name) + ascii(content)
	}

	private func zipCentral(_ name: String, _ content: String, at offset: Int) -> [UInt8] {
		[0x50, 0x4B, 0x01, 0x02] + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0)
			+ le32(content.utf8.count) + le32(content.utf8.count) + le16(name.utf8.count) + le16(0) + le16(0)
			+ le16(0) + le16(0) + le32(0) + le32(offset) + ascii(name)
	}

	private var zip: [UInt8] {
		let first = zipEntry("a.txt", "hi")
		let second = zipEntry("b.txt", "there")
		let central = zipCentral("a.txt", "hi", at: 0) + zipCentral("b.txt", "there", at: first.count)
		let end: [UInt8] = [0x50, 0x4B, 0x05, 0x06] + le16(0) + le16(0) + le16(2) + le16(2)
			+ le32(central.count) + le32(first.count + second.count) + le16(0)
		return first + second + central + end
	}

	@Test func aZIPListsItsEntriesByName() throws {
		let tree = try #require(explain(zip, "zip"))
		#expect(tree.name == "ZIP")
		let names = tree.children.map(\.name)
		#expect(names == ["local file header 1", "local file header 2", "central directory entry 1", "central directory entry 2", "end of central directory"])
		#expect(tree.children[0].value == "a.txt")
		#expect(find(tree.children[1], "compression")?.value == "stored")
		#expect(find(tree, "entries")?.value == "2")
	}

	@Test func aJARIsAZIPNamedByItsExtension() throws {
		let tree = try #require(explain(zip, "jar"))
		#expect(tree.name == "JAR (ZIP)")
	}

	@Test func aTruncatedZIPKeepsTwoEntriesAndSaysWhereItStopped() throws {
		let cut = zipEntry("a.txt", "hi") + zipEntry("b.txt", "there") + Array(zipEntry("c.txt", "and").prefix(20))
		let tree = try #require(explain(cut))
		#expect(tree.children.count == 3)
		#expect(tree.children[0].value == "a.txt")
		#expect(tree.children[1].value == "b.txt")
		let problem = try #require(problems(tree).first)
		#expect(problem.name.hasPrefix("truncated at 0x"))
		#expect(problem.name.contains("in local file header 3"))
		#expect(tree.children[2].name == "local file header 3")
		#expect(tree.children[2].children.last?.source == .problem)
	}

	@Test func aGzipNamesItsOriginalFile() throws {
		let gz: [UInt8] = [0x1F, 0x8B, 8, 0x08] + le32(1_700_000_000) + [0, 3] + ascii("x.txt") + [0]
			+ [0x4B, 0x04, 0x00] + le32(0x1234) + le32(1)
		let tree = try #require(explain(gz))
		#expect(find(tree, "original name")?.value == "“x.txt”")
		#expect(find(tree, "made on")?.value == "Unix")
		#expect(find(tree, "modified")?.value == "2023-11-14 22:13:20 UTC")
		#expect(find(tree, "uncompressed size")?.value == "1")
	}

	@Test func aTarListsItsFilesWithTheirSizes() throws {
		var header = padded("hello.txt", 100) + padded("0000644", 8) + padded("0001750", 8) + padded("0001750", 8)
			+ padded("00000000005", 12) + padded("14612620000", 12) + padded("        ", 8) + [0x30]
			+ padded("", 100) + padded("ustar", 6) + padded("00", 2) + padded("me", 32) + padded("us", 32)
			+ padded("0000000", 8) + padded("0000000", 8) + padded("", 155)
		header += [UInt8](repeating: 0, count: 512 - header.count)
		let tar = header + padded("hello", 512) + [UInt8](repeating: 0, count: 1024)
		let tree = try #require(explain(tar))
		#expect(tree.children.first?.name == "entry 1")
		#expect(tree.children.first?.value == "hello.txt")
		#expect(tree.children.first?.meaning == "5 bytes")
		#expect(find(tree, "kind")?.value == "regular file")
		#expect(tree.children.last?.name == "end of archive")
	}

	@Test func anELFHeaderSaysItsClassOrderAndMachine() throws {
		let elf: [UInt8] = [0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0, 0] + [UInt8](repeating: 0, count: 7)
			+ le16(2) + le16(0x3E) + le32(1) + [UInt8](repeating: 0, count: 8) + [UInt8](repeating: 0, count: 8) + [UInt8](repeating: 0, count: 8)
			+ le32(0) + le16(64) + le16(56) + le16(0) + le16(64) + le16(0) + le16(0)
		let tree = try #require(explain(elf))
		#expect(find(tree, "word size")?.value == "64-bit")
		#expect(find(tree, "byte order")?.value == "little-endian")
		#expect(find(tree, "architecture")?.value == "x86-64")
		#expect(find(tree, "kind")?.value == "executable")
		#expect(problems(tree).isEmpty)
	}

	private var thinMachO: [UInt8] {
		[0xCF, 0xFA, 0xED, 0xFE] + le32(0x0100_000C) + le32(0) + le32(2) + le32(1) + le32(24) + le32(0x20_0085) + le32(0)
			+ le32(0x1B) + le32(24) + [UInt8](repeating: 0xAB, count: 16)
	}

	@Test func aMachOListsItsLoadCommands() throws {
		let tree = try #require(explain(thinMachO))
		#expect(find(tree, "architecture")?.value == "arm64")
		#expect(find(tree, "kind")?.value == "executable")
		let uuid = try #require(find(tree, "LC_UUID"))
		#expect(uuid.value == String(repeating: "AB", count: 16))
	}

	@Test func aFatMachOHasASlicePerArchitecture() throws {
		var fat: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE] + be32(1)
			+ be32(0x0100_000C) + be32(0) + be32(64) + be32(thinMachO.count) + be32(12)
		fat += [UInt8](repeating: 0, count: 64 - fat.count)
		fat += thinMachO
		let tree = try #require(explain(fat))
		#expect(tree.children.map(\.name) == ["fat header", "arm64 slice"])
		#expect(find(tree.children[1], "LC_UUID") != nil)
	}

	@Test func aPEHeaderSaysItsMachineAndSections() throws {
		var dos = ascii("MZ") + [UInt8](repeating: 0, count: 58) + le32(64)
		dos += ascii("PE") + [0, 0] + le16(0x8664) + le16(1) + le32(1_700_000_000) + le32(0) + le32(0) + le16(0) + le16(0x22)
		dos += padded(".text", 8) + le32(100) + le32(0x1000) + le32(512) + le32(512) + le32(0) + le32(0) + le16(0) + le16(0) + le32(0x6000_0020)
		let tree = try #require(explain(dos))
		#expect(find(tree, "architecture")?.value == "x86-64")
		#expect(find(tree, "linked")?.value == "2023-11-14 22:13:20 UTC")
		#expect(find(tree, ".text") != nil)
	}

	@Test func anSQLiteHeaderIsReadAndItsPagesTyped() throws {
		var db = ascii("SQLite format 3\0") + be16(512) + [1, 1, 0, 64, 32, 32] + be32(1) + be32(1) + be32(0) + be32(0)
			+ be32(1) + be32(4) + be32(0) + be32(0) + be32(1) + be32(0) + be32(0) + be32(0)
			+ [UInt8](repeating: 0, count: 20) + be32(1) + be32(3_045_000)
		db += [13, 0, 0, 0, 0, 0, 0, 0, 0]
		db += [UInt8](repeating: 0, count: 512 - db.count)
		let tree = try #require(explain(db))
		#expect(find(tree, "text")?.value == "UTF-8")
		#expect(find(tree, "page 1")?.value == "leaf table b-tree")
		#expect(find(tree, "layout")?.value == "1 pages of 512 bytes")
	}

	@Test func aWAVsFormatChunkIsReadIntoFields() throws {
		let wav = ascii("RIFF") + le32(36) + ascii("WAVE") + ascii("fmt ") + le32(16)
			+ le16(1) + le16(1) + le32(8000) + le32(8000) + le16(1) + le16(8)
			+ ascii("data") + le32(4) + [128, 128, 128, 128]
		let tree = try #require(explain(wav))
		#expect(tree.children.first?.value == "WAVE")
		#expect(find(tree, "sample rate")?.value == "8000")
		#expect(find(tree, "encoding")?.value == "PCM")
		#expect(find(tree, "samples")?.range.count == 4)
	}

	@Test func aJavaClassNamesItselfAndIsNotMistakenForAFatMachO() throws {
		let cls: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE] + be16(0) + be16(52) + be16(3)
			+ [1] + be16(3) + ascii("Foo") + [7] + be16(1)
			+ be16(0x21) + be16(2) + be16(2) + be16(0) + be16(0) + be16(0) + be16(0)
		let tree = try #require(explain(cls, "class"))
		#expect(tree.name == "Java class")
		#expect(find(tree, "Java")?.value == "8")
		#expect(find(tree, "class")?.value == "Foo")
		#expect(find(tree, "#1 Utf8")?.value == "Foo")
	}

	@Test func aWebAssemblyModuleListsItsExports() throws {
		let wasm: [UInt8] = [0x00, 0x61, 0x73, 0x6D] + le32(1) + [7, 5, 1, 1] + ascii("f") + [0, 0]
		let tree = try #require(explain(wasm))
		#expect(tree.children.map(\.name) == ["magic", "version", "export section"])
		let export = try #require(find(tree, "export 0"))
		#expect(export.value == "f")
		#expect(export.meaning == "function")
	}

	@Test func aFileNobodyRecognisesIsNil() {
		#expect(explain([1, 2, 3, 4, 5, 6, 7, 8]) == nil)
		#expect(explain([]) == nil)
	}

	/// The cap is a node that counts, not a quiet end.
	@Test func aRepeatedSectionIsCappedWithACount() throws {
		let builder = StructureBuilder(snapshot: ByteDocument(bytes: Data(count: 10_000)).snapshot(), root: "test")
		try builder.repeating(5000, of: "things", cap: 10) { _ in try builder.u8("thing") }
		let tree = builder.finish()
		#expect(tree.children.count == 11)
		#expect(tree.children.last?.name == "4990 more things not listed")
		#expect(tree.children.last?.value == "5000 in all")
	}
}
