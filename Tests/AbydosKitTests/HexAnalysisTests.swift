import Foundation
import Testing
@testable import AbydosKit

/// The ask to Claude: bounded on the way out, marked on the way back.
struct HexAnalysisTests {
	private func snapshot(_ count: Int) -> ByteDocument.Snapshot {
		ByteDocument(bytes: Data((0..<count).map { UInt8($0 & 0xFF) })).snapshot()
	}

	@Test func aLargeFileIsSampledAndNeverSent() {
		let large = snapshot(1 << 20)
		let ask = HexAnalysis.ask(large, fileName: "big.bin")
		#expect(ask.sampledBytes == HexAnalysis.headBytes + HexAnalysis.tailBytes)
		#expect(ask.prompt.count < 40_000)
		#expect(ask.prompt.contains("1,048,576 bytes") || ask.prompt.contains("1048576 bytes"))
		#expect(ask.prompt.contains("00000000  00 01 02 03"))
		#expect(ask.prompt.contains("The last 1024 bytes"))
	}

	@Test func aSelectionIsSentUpToItsLimitAndSaidToBeCut() {
		let large = snapshot(1 << 20)
		let ask = HexAnalysis.ask(large, fileName: "big.bin", selection: 0x10000..<0x20000)
		#expect(ask.about == 0x10000..<0x20000)
		#expect(ask.sampledBytes == HexAnalysis.headBytes + HexAnalysis.tailBytes + HexAnalysis.selectionBytes)
		#expect(ask.prompt.contains("the first 8192 of 65536 selected"))
	}

	@Test func aSmallFileGoesWhole() {
		let ask = HexAnalysis.ask(snapshot(100), fileName: "tiny.bin")
		#expect(ask.sampledBytes == 100)
		#expect(!ask.prompt.contains("The last"))
	}

	@Test func theParsedTreeAndTheStringsRideAlong() {
		let bytes = ByteDocument(bytes: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array("usage: x".utf8))).snapshot()
		let tree = StructureNode(name: "PNG", range: 0..<16, children: [StructureNode(name: "signature", range: 0..<8, value: "89 50")])
		let strings = PrintableStrings.list(in: bytes)
		let ask = HexAnalysis.ask(bytes, fileName: "a.png", strings: strings, structure: tree)
		#expect(ask.prompt.contains("signature @0x0 +8 = 89 50"))
		#expect(ask.prompt.contains("0x8: usage: x"))
		let without = HexAnalysis.ask(bytes, fileName: "a.png")
		#expect(without.prompt.contains("No built-in parser recognised the format."))
	}

	@Test func aGoodAnswerBecomesASummaryAndRowsMarkedAsClaudes() throws {
		let text = """
		{"summary": "A little-endian table.", "fields": [
		  {"name": "count", "offset": 4, "length": 2, "meaning": "number of rows"},
		  {"name": "magic", "offset": "0x0", "length": 4, "meaning": "the signature"}]}
		"""
		let answer = try #require(HexAnalysis.parse(text, count: 100, prompt: "p"))
		#expect(answer.summary == "A little-endian table.")
		#expect(answer.nodes.map(\.name) == ["magic", "count"])
		#expect(answer.nodes.allSatisfy { $0.source == .claude })
		#expect(answer.nodes[1].range == 4..<6)
		#expect(answer.prompt == "p")
	}

	@Test func aFencedAnswerWithAPreambleStillParses() throws {
		let text = "Here is the analysis:\n```json\n{\"summary\": \"Noise.\", \"fields\": []}\n```\n"
		let answer = try #require(HexAnalysis.parse(text, count: 10, prompt: ""))
		#expect(answer.summary == "Noise.")
		#expect(answer.nodes.isEmpty)
	}

	@Test func aRowPastTheEndIsDroppedAndTheRestKept() throws {
		let text = """
		{"summary": "s", "fields": [{"name": "ok", "offset": 0, "length": 4}, {"name": "beyond", "offset": 96, "length": 8}]}
		"""
		let answer = try #require(HexAnalysis.parse(text, count: 100, prompt: ""))
		#expect(answer.nodes.map(\.name) == ["ok"])
	}

	@Test func somethingThatIsNotAnAnswerIsNil() {
		#expect(HexAnalysis.parse("I cannot help with that.", count: 10, prompt: "") == nil)
		#expect(HexAnalysis.parse("{\"summary\": \"\", \"fields\": []}", count: 10, prompt: "") == nil)
	}

	/// The button is not there when the command is not, and the search
	/// honours an empty `PATH` with nowhere else to look.
	@Test func absentWithoutTheCommand() {
		#expect(ClaudeCommand.executable(environment: ["PATH": ""], besides: []) == nil)
		#expect(ClaudeDraft.executable(environment: ["PATH": ""], besides: []) == nil)
	}

	@Test func theDumpReadsLikeTheEditor() {
		let bytes = ByteDocument(bytes: Data(Array("Hello, world!!!!".utf8) + [0, 0xFF])).snapshot()
		let dump = HexAnalysis.dump(bytes, 0..<18)
		let lines = dump.split(separator: "\n")
		#expect(lines.count == 2)
		#expect(lines[0].hasPrefix("00000000  48 65 6C 6C 6F 2C 20 77 6F 72 6C 64 21 21 21 21  Hello, world!!!!"))
		#expect(lines[1].hasPrefix("00000010  00 FF"))
		#expect(lines[1].hasSuffix(".."))
	}
}
