import Foundation
import Testing
@testable import AbydosKit

/// Which runs are worth handing to a shaper.
struct LigatureTests {
	private func scalars(_ text: String) -> [UInt32] {
		text.unicodeScalars.map(\.value)
	}

	@Test func ordinaryTextIsNotWorthShaping() {
		#expect(!Ligatures.mayLigate(scalars("hello world")))
		#expect(!Ligatures.mayLigate(scalars("let count = 3")))
		#expect(!Ligatures.mayLigate(scalars("")))
		#expect(!Ligatures.mayLigate(scalars("a")))
	}

	/// Two side by side is the whole test. `= 3` has a candidate but no pair.
	@Test func twoPunctuationMarksSideBySideAre() {
		#expect(Ligatures.mayLigate(scalars("a -> b")))
		#expect(Ligatures.mayLigate(scalars("if a != b")))
		#expect(Ligatures.mayLigate(scalars("Foo::bar")))
		#expect(Ligatures.mayLigate(scalars("x |> f")))
		#expect(Ligatures.mayLigate(scalars("...")))
	}

	/// A space between them is not side by side, and nothing ligates across one.
	@Test func aGapBreaksThePair() {
		#expect(!Ligatures.mayLigate(scalars("a - > b")))
		#expect(!Ligatures.mayLigate(scalars("= =")))
	}

	/// Letters and digits are not candidates: a font that ligates `www` is not
	/// worth shaping every word of prose on the screen for.
	@Test func lettersAndDigitsAreNotCandidates() {
		#expect(!Ligatures.isCandidate(0x61))
		#expect(!Ligatures.isCandidate(0x30))
		#expect(Ligatures.isCandidate(0x3D))
		#expect(Ligatures.isCandidate(0x2D))
	}
}
