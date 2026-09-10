import Foundation
import Testing
@testable import AbydosKit

/// The emphasis inside one line, as spans a view can set fonts on.
///
/// Reported 2026-09-10 against the task tip on a card: the tasks are lines of a
/// markdown checklist, and they were drawn exactly as the file has them, so a
/// card showed `5.2 **Measure the build before settling this.**
/// `buildWorkspace` is a` with its asterisks and backticks in the words.
struct InlineMarkdownTests {
	private func spans(_ line: String) -> [InlineMarkdown.Span] {
		InlineMarkdown.spans(of: line)
	}

	private func plain(_ text: String) -> InlineMarkdown.Span { .init(text: text) }
	private func bold(_ text: String) -> InlineMarkdown.Span { .init(text: text, bold: true) }
	private func italic(_ text: String) -> InlineMarkdown.Span { .init(text: text, italic: true) }
	private func code(_ text: String) -> InlineMarkdown.Span { .init(text: text, code: true) }

	@Test func aLineWithNoMarkupIsOneSpan() {
		#expect(spans("just words") == [plain("just words")])
	}

	@Test func boldItalicAndCodeAreTakenOffTheWordsTheyWrap() {
		#expect(spans("**bold**") == [bold("bold")])
		#expect(spans("*italic*") == [italic("italic")])
		#expect(spans("***both***") == [.init(text: "both", bold: true, italic: true)])
		#expect(spans("`code`") == [code("code")])
	}

	/// The line from the report, which is prose with three kinds of markup in
	/// it and the shape the tip actually draws.
	@Test func theReportedLineComesApartWhereItsMarkupIs() {
		let line = "5.2 **Measure the build before settling this.** `buildWorkspace` is a"
		#expect(spans(line) == [
			plain("5.2 "),
			bold("Measure the build before settling this."),
			plain(" "),
			code("buildWorkspace"),
			plain(" is a"),
		])
		#expect(InlineMarkdown.plain(line)
			== "5.2 Measure the build before settling this. buildWorkspace is a")
	}

	/// **A marker with no partner is prose.** A lone asterisk is a bullet and a
	/// lone backtick is somebody's apostrophe; either taken as emphasis would
	/// swallow the rest of the line.
	@Test func aMarkerWithNoPartnerIsLeftWhereItIs() {
		#expect(spans("2 * 3 is six") == [plain("2 * 3 is six")])
		#expect(spans("a `quote that never closes") == [plain("a `quote that never closes")])
		#expect(spans("**opened and not closed") == [plain("**opened and not closed")])
	}

	/// Emphasis does not open on a space, which is what markdown itself says
	/// and what keeps a product out of a multiplication.
	@Test func emphasisDoesNotOpenOnASpace() {
		#expect(spans("width * height * depth") == [plain("width * height * depth")])
	}

	/// Underscores are somebody's identifier far more often than they are
	/// italics, and `ServerDocumentation` settled the same question the same
	/// way.
	@Test func underscoresAreLeftAlone() {
		#expect(spans("is_file_revealing_enabled") == [plain("is_file_revealing_enabled")])
	}

	/// Backticks close before emphasis is looked for, so markup inside a code
	/// span is text.
	@Test func markupInsideCodeIsText() {
		#expect(spans("`a ** b`") == [code("a ** b")])
	}

	@Test func markupAroundNothingIsTheCharactersSomebodyTyped() {
		#expect(spans("****") == [plain("****")])
		#expect(spans("``") == [plain("``")])
	}

	@Test func twoEmphasesInOneLineAreTwoSpans() {
		#expect(spans("*one* and *two*") == [
			italic("one"),
			plain(" and "),
			italic("two"),
		])
	}
}
