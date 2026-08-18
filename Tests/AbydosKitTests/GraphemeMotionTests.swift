import Foundation
import Testing
@testable import AbydosKit

/// Stepping over a whole character, as a reader means it.
///
/// 0504: the caret could come to rest between an `e` and the combining acute
/// after it. What was there stepped by UTF-8 sequence, which is right for "do
/// not land inside an encoded code point" and says nothing about characters —
/// and it is why an emoji worked while an accent did not. An emoji is one
/// four-byte sequence; `e` + U+0301 is two, and both starts are valid.
struct GraphemeMotionTests {
	private func rope(_ text: String) -> Rope { Rope(text) }

	/// The case in the report, at the offsets it names.
	@Test func aDecomposedAccentIsOneStep() {
		let rope = rope("le\u{0301}gume")
		// l = 0, e = 1, U+0301 = 2, g = 3
		#expect(rope.graphemeStep(fromUTF16: 1, by: 1) == 3)
		#expect(rope.graphemeStep(fromUTF16: 3, by: -1) == 1)
	}

	@Test func theByteAlignmentIsWhatItAlwaysWas() {
		// Kept, and kept honest: it is about encoding, and it stops between the
		// letter and its mark, which is the fault this replaces for the caret.
		let rope = rope("le\u{0301}gume")
		let caret = rope.byteOffset(fromUTF16: 2)
		#expect(rope.alignToBoundary(caret) == caret)
	}

	@Test func anEmojiIsStillOneStep() {
		let rope = rope("a🙂b")
		#expect(rope.graphemeStep(fromUTF16: 1, by: 1) == 3)
		#expect(rope.graphemeStep(fromUTF16: 3, by: -1) == 1)
	}

	/// The one the other candidate would have failed:
	/// `CFStringGetRangeOfComposedCharactersAtIndex` splits this into the people
	/// in it.
	@Test func aZWJSequenceIsOneStep() {
		let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
		let rope = rope("a\(family)b")
		let after = rope.graphemeStep(fromUTF16: 1, by: 1)
		#expect(after == 1 + family.utf16.count)
		#expect(rope.graphemeStep(fromUTF16: after, by: -1) == 1)
	}

	@Test func aSkinToneModifierGoesWithItsEmoji() {
		let waving = "\u{1F44B}\u{1F3FD}"
		let rope = rope("a\(waving)b")
		let after = rope.graphemeStep(fromUTF16: 1, by: 1)
		#expect(after == 1 + waving.utf16.count)
		#expect(rope.graphemeStep(fromUTF16: after, by: -1) == 1)
	}

	@Test func aRegionalIndicatorPairIsOneFlag() {
		let flag = "\u{1F1EC}\u{1F1E7}"
		let rope = rope("a\(flag)b")
		#expect(rope.graphemeStep(fromUTF16: 1, by: 1) == 1 + flag.utf16.count)
	}

	/// ⌃O works today *because* of the byte stepping, so it is the case most
	/// likely to be broken by this: a lone carriage return must stay one step,
	/// and a CRLF pair must be one too, since Swift counts it as one character.
	@Test func aCarriageReturnIsOneStepAndSoIsACRLF() {
		let lone = rope("a\rb")
		#expect(lone.graphemeStep(fromUTF16: 1, by: 1) == 2)

		let pair = rope("a\r\nb")
		#expect(pair.graphemeStep(fromUTF16: 1, by: 1) == 3)
		#expect(pair.graphemeStep(fromUTF16: 3, by: -1) == 1)
	}

	@Test func theEndsOfTheDocumentAreWhereItStops() {
		let rope = rope("ab")
		#expect(rope.graphemeStep(fromUTF16: 0, by: -1) == 0)
		#expect(rope.graphemeStep(fromUTF16: 2, by: 1) == 2)
		#expect(rope.graphemeStep(fromUTF16: 0, by: 0) == 0)
	}

	@Test func anEmptyDocumentGoesNowhere() {
		let rope = rope("")
		#expect(rope.graphemeStep(fromUTF16: 0, by: 1) == 0)
		#expect(rope.graphemeStep(fromUTF16: 0, by: -1) == 0)
	}

	/// A caret deep in a large file steps by looking at a window, not at the
	/// file — which is the claim the comment makes and the reason this is
	/// affordable on every keystroke.
	@Test func aStepInALargeFileIsStillOneCharacter() {
		let line = String(repeating: "the quick brown fox ", count: 60_000)
		let rope = rope(line + "e\u{0301}!")
		let mark = rope.utf16Count - 2
		#expect(rope.graphemeStep(fromUTF16: mark - 1, by: 1) == mark + 1)
	}

	/// The other candidate, measured rather than assumed.
	///
	/// **The obvious argument against it turned out to be false, and a better
	/// one turned up.** `CFStringGetRangeOfComposedCharactersAtIndex` — which is
	/// what `-[NSString rangeOfComposedCharacterSequenceAtIndex:]` calls — was
	/// expected to split a ZWJ family into the people in it, and on macOS 27 it
	/// does not: family, skin tone, flag and combining mark all come back whole,
	/// the same as Swift's `Character`.
	///
	/// Where they differ is `\r\n`, and that is the one that decides it: the
	/// narrower API answers 1 and would let → come to rest between the carriage
	/// return and the line feed, which is the same class of fault as landing
	/// between a letter and its mark. Swift's `Character` takes both.
	@Test func theTwoCandidatesDifferOverACarriageReturnPair() {
		// Agreed, all of them.
		for text in [
			"\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}",
			"\u{1F44B}\u{1F3FD}",
			"e\u{0301}",
			"\u{1F1EC}\u{1F1E7}",
		] {
			let composed = (text as NSString).rangeOfComposedCharacterSequence(at: 0)
			#expect(composed.length == text.utf16.count, "the narrower API split \(text.debugDescription)")
			#expect(text.count == 1)
		}

		// And the one they do not agree on.
		let crlf = "\r\n"
		#expect((crlf as NSString).rangeOfComposedCharacterSequence(at: 0).length == 1)
		#expect(crlf.count == 1)
		// The rope steps by the second answer, so a caret cannot land inside it.
		#expect(rope("a\r\nb").graphemeStep(fromUTF16: 1, by: 1) == 3)
	}

	/// What each costs over the same window, since this runs on every keystroke.
	@Test func theTwoCandidatesCostAboutTheSame() {
		let window = String(repeating: "the quick brown fox ", count: 13)
		let text = window as NSString
		let rounds = 20_000

		var swiftAt = window.startIndex
		let swiftStarted = Date()
		for _ in 0..<rounds {
			swiftAt = window.index(after: swiftAt)
			if swiftAt >= window.endIndex { swiftAt = window.startIndex }
		}
		let swiftEach = Date().timeIntervalSince(swiftStarted) / Double(rounds)

		var index = 0
		let foundationStarted = Date()
		for _ in 0..<rounds {
			index = NSMaxRange(text.rangeOfComposedCharacterSequence(at: index))
			if index >= text.length { index = 0 }
		}
		let foundationEach = Date().timeIntervalSince(foundationStarted) / Double(rounds)

		print("GRAPHEME candidates: Character \(swiftEach * 1_000_000) µs, "
			+ "composed-sequence \(foundationEach * 1_000_000) µs")
		#expect(swiftEach < 0.001)
		#expect(foundationEach < 0.001)
	}

	/// Ten thousand steps in a megabyte, so a keystroke's cost is a number
	/// somebody can check rather than a claim.
	@Test func steppingIsCheapEnoughForEveryKeystroke() {
		let rope = rope(String(repeating: "the quick brown fox jumps over ", count: 40_000))
		let middle = rope.utf16Count / 2

		let started = Date()
		var offset = middle
		for _ in 0..<10_000 { offset = rope.graphemeStep(fromUTF16: offset, by: 1) }
		let each = Date().timeIntervalSince(started) / 10_000

		#expect(offset > middle)
		print("GRAPHEME: a step took \(each * 1_000_000) µs")
		// Generous by a wide margin against what was measured — this is here to
		// catch somebody making it read the whole document, not to police
		// microseconds.
		#expect(each < 0.001, "a step took \(each * 1_000_000) µs")
	}
}
