import Testing
import Foundation
@testable import AbydosKit

/// What text a query predicate is given to match against.
///
/// **A node at an odd byte offset used to be handed one byte too much.**
/// `Node.range` is `byteRange.range`, which divides by two because
/// SwiftTreeSitter assumes UTF-16 input; this parses UTF-8, so the recovery
/// multiplied by two again. That round trip is lossless only for even offsets,
/// and the byte it loses is the one an anchored pattern needs.
///
/// The symptom was `///` lines being different colours in the same comment
/// block: `(#match? @comment.documentation "^///[^/]")` saw a leading newline
/// on roughly half of them — whichever happened to start at an odd offset — so
/// those were highlighted as ordinary comments. It reads as random, and it is
/// not: it is arithmetic.
struct PredicateTextTests {
	/// The kinds each line of a Swift source gets, by line number.
	private func kinds(of source: String) throws -> [Int: Set<HighlightKind>] {
		let engine = try #require(SyntaxEngine(languageId: "swift"))
		let rope = Rope(source)
		engine.parse(rope: rope)

		var lineStart: [Int] = []
		var offset = 0
		for line in source.components(separatedBy: "\n") {
			lineStart.append(offset)
			offset += line.utf16.count + 1
		}

		var found: [Int: Set<HighlightKind>] = [:]
		for token in engine.highlights(rope: rope, byteRange: 0..<rope.byteCount) {
			let line = (lineStart.lastIndex { $0 <= token.range.lowerBound } ?? 0) + 1
			found[line, default: []].insert(token.kind)
		}
		return found
	}

	/// Every line of one doc block is documentation, whatever byte each starts
	/// at. The odd `x` shifts the whole block by one, so between the two cases
	/// every line has been on both sides of the parity.
	@Test(arguments: ["", "x"])
	func everyDocCommentLineIsDocumentation(padding: String) throws {
		let source = """
		let a\(padding) = 1
		/// One.
		/// Two.
		///
		/// Four.
		/// Five.
		let value = 100.0

		"""
		let byLine = try kinds(of: source)
		for line in 2...6 {
			#expect(byLine[line] == [.documentation],
				"line \(line) with padding '\(padding)': \(byLine[line] ?? [])")
		}
	}

	/// The distinction still exists: an ordinary comment is not documentation.
	@Test func anOrdinaryCommentIsStillAComment() throws {
		let byLine = try kinds(of: "// MARK: - Here\n/// Doc.\nlet a = 1\n")
		#expect(byLine[1] == [.comment])
		#expect(byLine[2] == [.documentation])
	}

	/// `////` is a rule, not documentation — which is what `[^/]` is for, and
	/// the case that proves the anchor is being matched rather than ignored.
	@Test func fourSlashesAreNotDocumentation() throws {
		let byLine = try kinds(of: "let a = 1\n//// not a doc comment\nlet b = 2\n")
		#expect(byLine[2] == [.comment])
	}
}
