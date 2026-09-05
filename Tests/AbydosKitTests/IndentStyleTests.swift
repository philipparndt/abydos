import Testing
import AbydosKit
import Foundation

/// How a file indents, judged once from what the file already does — the
/// claims `ReturnIndent.usesTabs` used to hold, moved here when the two
/// detections became one, beside the width, which is the newer question.
struct IndentStyleTests {
	@Test func aTabIndentedFileIsTabs() {
		let text = "func a() {\n\tlet x = 1\n\tlet y = 2\n}\n"
		#expect(IndentStyle.detect(in: text, fallbackWidth: 4) == .tabs)
	}

	@Test func aTwoSpaceFileIsSpacesOfTwo() {
		let yaml = "values:\n  host: db\n  port: 5432\n"
		#expect(IndentStyle.detect(in: yaml, fallbackWidth: 4) == .spaces(width: 2))
	}

	/// A continuation line appears once; the step appears at every level.
	@Test func continuationLinesCannotOutvoteTheStep() {
		var lines = ["func a() {"]
		for _ in 0..<6 { lines.append("    body: 1") }
		lines.append("      continuation")
		#expect(IndentStyle.detect(in: lines.joined(separator: "\n"), fallbackWidth: 4) == .spaces(width: 4))
	}

	@Test func aTieBetweenWidthsGoesToTheNarrower() {
		let text = "a:\n  one\nb:\n    two\nc:\n  three\nd:\n    four\n"
		#expect(IndentStyle.detect(in: text, fallbackWidth: 4) == .spaces(width: 2))
	}

	/// A mixed file stays on the side its existing lines are mostly on.
	@Test func aTieBetweenKindsGoesToTabs() {
		let mixed = "a:\n\tone\nb:\n  two\n"
		#expect(IndentStyle.detect(in: mixed, fallbackWidth: 4) == .tabs)
	}

	@Test func aFileWithNoIndentationTakesTheFallbackAsSpaces() {
		#expect(IndentStyle.detect(in: "one\ntwo\n", fallbackWidth: 4) == .spaces(width: 4))
		#expect(IndentStyle.detect(in: "", fallbackWidth: 3) == .spaces(width: 3))
	}

	@Test func theUnitIsOneLevelOfTheStyle() {
		#expect(IndentStyle.tabs.unit == "\t")
		#expect(IndentStyle.spaces(width: 2).unit == "  ")
		#expect(IndentStyle.spaces(width: 0).unit == " ")
	}

	// MARK: - The menu's widths

	@Test func theMenuOffersTheStandingWidthsAndTheFilesOwn() {
		#expect(IndentStyle.offeredWidths(currentWidth: nil) == [2, 4, 8])
		#expect(IndentStyle.offeredWidths(currentWidth: 2) == [2, 4, 8])
		#expect(IndentStyle.offeredWidths(currentWidth: 3) == [2, 3, 4, 8])
	}

	// MARK: - Converting, level by level

	@Test func tabsBecomeSpacesLevelByLevel() {
		let text = "func a() {\n\tlet x = 1\n\t\treturn x\n}\n"
		let converted = IndentStyle.converted(text, from: .tabs, to: .spaces(width: 2))
		#expect(converted == "func a() {\n  let x = 1\n    return x\n}\n")
	}

	@Test func spacesBecomeTabsWithThePartialLevelKept() {
		let text = "a:\n    one\n      two\n"
		let converted = IndentStyle.converted(text, from: .spaces(width: 4), to: .tabs)
		#expect(converted == "a:\n\tone\n\t  two\n")
	}

	@Test func oneSpaceWidthBecomesAnotherLevelByLevel() {
		let text = "a:\n  one\n    two\n"
		let converted = IndentStyle.converted(text, from: .spaces(width: 2), to: .spaces(width: 4))
		#expect(converted == "a:\n    one\n        two\n")
	}

	/// A tab after the first non-blank is alignment, and alignment is a
	/// choice rather than a habit.
	@Test func alignmentAfterTheFirstNonBlankIsLeftAlone() {
		let text = "a:\n\tb:\tx\tc\n"
		#expect(IndentStyle.converted(text, from: .tabs, to: .spaces(width: 2)) == "a:\n  b:\tx\tc\n")
	}

	/// The style cannot read an intent into a tabs file's stray leading
	/// spaces, so it keeps them.
	@Test func aTabFilesStrayLeadingSpacesAreKept() {
		let text = "a:\n  b\n"
		#expect(IndentStyle.converted(text, from: .tabs, to: .spaces(width: 4)) == "a:\n  b\n")
	}

	@Test func convertingToWhatItAlreadyIsChangesNothing() {
		let text = "a:\n\tb\n"
		#expect(IndentStyle.converted(text, from: .tabs, to: .tabs) == text)
	}

	@Test func aWhitespaceOnlyLineConvertsAndTheTrailingBreakSurvives() {
		let text = "a:\n\tb\n\t\n"
		let converted = IndentStyle.converted(text, from: .tabs, to: .spaces(width: 2))
		#expect(converted == "a:\n  b\n  \n")
	}
}