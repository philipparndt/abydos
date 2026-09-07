import Foundation
import Testing
@testable import AbydosKit

/// A document nobody may change: an entry inside an archive.
///
/// Every edit the view makes goes through `replace(utf16Range:with:caretBefore:)`,
/// so the refusal is one guard there rather than nine in the view.
struct ReadOnlyDocumentTests {
	@Test func aReadOnlyDocumentDeclinesEveryReplaceAndStaysClean() throws {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("values-\(UUID().uuidString).yaml")
		try "replicaCount: 1\n".write(to: url, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: url) }

		let document = try TextDocument(url: url)
		document.isReadOnly = true
		let caret = document.replace(utf16Range: 0..<0, with: "x", caretBefore: 0)
		#expect(caret == 0)
		#expect(document.lineText(0).hasPrefix("replicaCount: 1"))
		#expect(!document.isDirty)

		document.isReadOnly = false
		_ = document.replace(utf16Range: 0..<0, with: "x", caretBefore: 0)
		#expect(document.lineText(0).hasPrefix("xreplicaCount: 1"))
		#expect(document.isDirty)
	}
}
