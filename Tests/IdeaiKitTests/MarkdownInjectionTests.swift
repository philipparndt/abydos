import Foundation
import Testing
@testable import IdeaiKit

/// Code inside a markdown fence, coloured as the language it says it is.
struct MarkdownInjectionTests {
	private func tokens(_ text: String) -> [HighlightToken] {
		guard let engine = SyntaxEngine(languageId: "markdown") else { return [] }
		let rope = Rope(text)
		engine.parse(rope: rope)
		return engine.highlights(rope: rope, byteRange: 0..<rope.byteCount)
	}

	private func kinds(_ text: String, of word: String) -> [HighlightKind] {
		let ns = text as NSString
		let range = ns.range(of: word)
		guard range.location != NSNotFound else { return [] }
		return tokens(text)
			.filter { $0.range.lowerBound < range.location + range.length
				&& $0.range.upperBound > range.location }
			.map(\.kind)
	}

	/// A keyword inside a Swift fence is a keyword, not undifferentiated code.
	@Test func coloursSwiftInsideAFence() {
		let text = """
		# Title

		```swift
		func greet() { print("hi") }
		```
		"""
		#expect(kinds(text, of: "func").contains(.keyword))
		#expect(kinds(text, of: "\"hi\"").contains(.string))
	}

	@Test func coloursByTheNamePeopleActuallyType() {
		let text = """
		```golang
		func main() {}
		```
		"""
		#expect(kinds(text, of: "func").contains(.keyword))
	}

	/// A fence with no language, or one nothing is loaded for, stays as it was.
	@Test func leavesAnUnlabelledFenceAlone() {
		let text = """
		```
		func greet() {}
		```
		"""
		#expect(!kinds(text, of: "func").contains(.keyword))
	}

	@Test func leavesAnUnknownLanguageAlone() {
		let text = """
		```brainfuck
		func greet() {}
		```
		"""
		#expect(!kinds(text, of: "func").contains(.keyword))
	}

	/// Prose around the fence is still markdown.
	@Test func keepsTheMarkdownAroundIt() {
		let text = """
		# Heading

		```json
		{"a": 1}
		```
		"""
		// The heading is still a heading, and the fence is still JSON: a number
		// in it is a number rather than part of one flat code-coloured block.
		#expect(tokens(text).map(\.kind).contains(.heading))
		#expect(kinds(text, of: "1").contains(.number))
	}

	/// Fence info can carry more than a language name.
	@Test func readsALanguageOutOfADecoratedInfoString() {
		#expect(LanguageRegistry.shared.languageId(forFenceInfo: "swift title=Demo") == "swift")
		#expect(LanguageRegistry.shared.languageId(forFenceInfo: "sh") == "bash")
		#expect(LanguageRegistry.shared.languageId(forFenceInfo: "c++") == "cpp")
		#expect(LanguageRegistry.shared.languageId(forFenceInfo: "") == nil)
		#expect(LanguageRegistry.shared.languageId(forFenceInfo: "not-a-language") == nil)
	}
}
