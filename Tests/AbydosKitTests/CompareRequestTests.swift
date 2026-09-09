import Testing
import Foundation
@testable import AbydosKit

/// The `compare` verb on the wire `abydos` already uses.
struct CompareRequestTests {
	private func base64(_ text: String) -> String { Data(text.utf8).base64EncodedString() }

	@Test func aCompareCarriesTwoAbsolutePaths() {
		let request = TerminalOpenRequest(body: "compare;\(base64("/tmp/a.txt"));\(base64("/tmp/b.txt"))")
		#expect(request?.path == "/tmp/a.txt")
		#expect(request?.comparePath == "/tmp/b.txt")
		#expect(request?.line == nil)
	}

	@Test func aCompareWithOneSideIsDropped() {
		#expect(TerminalOpenRequest(body: "compare;\(base64("/tmp/a.txt"))") == nil)
		#expect(TerminalOpenRequest(body: "compare;\(base64("/tmp/a.txt"));\(base64("relative"))") == nil)
	}

	@Test func anOpenStillHasNoOtherSide() {
		let request = TerminalOpenRequest(body: "open;\(base64("/tmp/a.txt"));12")
		#expect(request?.comparePath == nil)
		#expect(request?.line == 12)
	}

	@Test func theSequenceRoundTrips() throws {
		let request = TerminalOpenRequest(path: "/tmp/a", comparePath: "/tmp/b")
		let sequence = request.sequence
		#expect(sequence.hasPrefix("\u{1B}]440;compare;"))
		let body = sequence.dropFirst("\u{1B}]440;".count).dropLast(2)
		let parsed = try #require(TerminalOpenRequest(body: String(body)))
		#expect(parsed == request)
	}
}
