import Foundation
import Testing
@testable import AbydosKit

/// Tab and ⇧Tab over a block of lines.
struct LineIndentTests {
	@Test func indentsEveryLine() {
		let block = "one\ntwo\nthree"
		#expect(LineIndent.indent(block, using: "\t") == "\tone\n\ttwo\n\tthree")
	}

	/// A blank line inside a block belongs to the block, but adding whitespace
	/// to it leaves trailing spaces on an otherwise empty line — which every
	/// linter complains about and every diff shows.
	@Test func leavesBlankLinesBlank() {
		#expect(LineIndent.indent("one\n\ntwo", using: "\t") == "\tone\n\n\ttwo")
	}

	@Test func outdentsOneTab() {
		#expect(LineIndent.outdent("\tone\n\ttwo", tabWidth: 4) == "one\ntwo")
	}

	/// Spaces come off a level at a time, however many there are — a file
	/// indented with four takes four, and one indented with two takes two.
	@Test func outdentsUpToOneLevelOfSpaces() {
		#expect(LineIndent.outdent("    one", tabWidth: 4) == "one")
		#expect(LineIndent.outdent("  one", tabWidth: 4) == "one")
		#expect(LineIndent.outdent("        one", tabWidth: 4) == "    one")
	}

	/// A line already at the margin stays there. Pulling it into the line above
	/// would be a deletion, and ⇧Tab is not a deletion.
	@Test func leavesALineWithNoIndentationAlone() {
		#expect(LineIndent.outdent("one\n\ttwo", tabWidth: 4) == "one\ntwo")
		#expect(LineIndent.outdent("one", tabWidth: 4) == "one")
	}

	/// Mixed indentation is what real files have, and each line is judged on
	/// its own rather than by what the first one used.
	@Test func handlesTabsAndSpacesTogether() {
		#expect(LineIndent.outdent("\tone\n    two\n  three", tabWidth: 4) == "one\ntwo\nthree")
	}

	/// A selection that ends on a newline covers the line after it, and the
	/// empty last piece has to survive the round trip or that line's break is
	/// swallowed.
	@Test func keepsATrailingEmptyLine() {
		#expect(LineIndent.indent("one\ntwo\n", using: "\t") == "\tone\n\ttwo\n")
		#expect(LineIndent.outdent("\tone\n\ttwo\n", tabWidth: 4) == "one\ntwo\n")
	}

	/// What the caret on the first line should move by, so it keeps its place
	/// in the text rather than jumping to the margin.
	@Test func saysHowFarTheFirstLineMoved() {
		#expect(LineIndent.firstLineShift(from: "one", to: "\tone") == 1)
		#expect(LineIndent.firstLineShift(from: "    one", to: "one") == -4)
		#expect(LineIndent.firstLineShift(from: "one", to: "one") == 0)
	}

	@Test func indentsWithSpacesWhenThatIsTheUnit() {
		#expect(LineIndent.indent("one\ntwo", using: "  ") == "  one\n  two")
	}
}
