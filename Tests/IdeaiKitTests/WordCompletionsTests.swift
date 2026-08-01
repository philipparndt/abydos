import Foundation
import Testing
@testable import IdeaiKit

/// Completions taken from the words already in the file.
struct WordCompletionsTests {
	private let source = """
	struct Greeter {
	    let greeting: String
	    let greetingCount: Int

	    func greetEverybody() {
	        print(greeting)
	    }
	}
	"""

	@Test func offersWordsThatStartWithWhatIsTyped() {
		let found = WordCompletions.candidates(matching: "greet", in: source)
		#expect(found.contains("greeting"))
		#expect(found.contains("greetingCount"))
		#expect(found.contains("greetEverybody"))
		#expect(!found.contains("struct"))
	}

	/// The word being typed is not a completion of itself.
	@Test func neverOffersTheWordItself() {
		#expect(!WordCompletions.candidates(matching: "greeting", in: source).contains("greeting"))
	}

	/// The name you want is nearly always the one you last looked at.
	@Test func prefersTheNearestUse() {
		let text = """
		let alphaFar = 1
		// ... a long way down ...
		let alphaNear = 2
		alph
		"""
		let caret = text.utf16.count
		let found = WordCompletions.candidates(matching: "alph", in: text, near: caret)
		#expect(found.first == "alphaNear")
	}

	@Test func matchesWithoutRegardToCaseButPrefersExact() {
		let text = "Value value valuation"
		let found = WordCompletions.candidates(matching: "val", in: text)
		// Both are offered; the one spelled as typed comes first.
		#expect(found.contains("value"))
		#expect(found.contains("Value"))
		#expect(found.first == "value" || found.first == "valuation")
	}

	@Test func staysQuietForNothingToGoOn() {
		#expect(WordCompletions.candidates(matching: "", in: source).isEmpty)
		#expect(WordCompletions.candidates(matching: "zzz", in: source).isEmpty)
	}

	@Test func keepsTheListShort() {
		let text = (0..<200).map { "prefix\($0)" }.joined(separator: " ")
		#expect(WordCompletions.candidates(matching: "prefix", in: text, limit: 5).count == 5)
	}

	/// An underscore is part of a name; a number is not a name.
	@Test func readsIdentifiersTheWayTheEditorDoes() {
		let words = WordCompletions.words(in: "some_name = 42 other").map(\.0)
		#expect(words.contains("some_name"))
		#expect(words.contains("other"))
		#expect(!words.contains("42"))
	}

	@Test func saysWhereEachWordIs() {
		let words = WordCompletions.words(in: "alpha beta")
		#expect(words.first?.0 == "alpha")
		#expect(words.first?.1 == 0)
		#expect(words.last?.1 == 6)
	}
}
