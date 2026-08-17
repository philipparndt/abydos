import Foundation
import Testing
@testable import AbydosKit

/// Reducing a server's prose to something the panel beside the completion list
/// can draw.
///
/// `Fixtures/openscad-cube-documentation.md` is not written by hand: it is the
/// 1530 characters the installed `openscad-lsp` answers `cub` with, saved as
/// they arrived. The reported fault was that none of it reached the screen —
/// `cube(size = size, center = false);` went in with `size` selected and nothing
/// said what `size` was, while the server had already said it twice.
struct ServerDocumentationTests {
	private func cubeDocumentation() throws -> String {
		let url = try #require(Bundle.module.url(
			forResource: "openscad-cube-documentation", withExtension: "md", subdirectory: "Fixtures"
		))
		return try String(contentsOf: url, encoding: .utf8)
	}

	@Test func theSentenceSomebodyIsLookingForSurvives() throws {
		let readable = ServerDocumentation.readable(try cubeDocumentation())

		// The whole point of the change, in two lines of somebody else's wiki.
		#expect(readable.contains("single value, cube with all sides this length"))
		#expect(readable.contains("3 value array [x,y,z], cube with dimensions x, y and z."))
		#expect(readable.contains("size"))
		#expect(readable.contains("center"))
	}

	@Test func noMarkupReachesTheScreen() throws {
		let readable = ServerDocumentation.readable(try cubeDocumentation())

		#expect(!readable.contains("```"))
		#expect(!readable.contains("**"))
		#expect(!readable.contains("<a href"))
		#expect(!readable.contains("<img"))
		#expect(!readable.contains("</a>"))
	}

	/// The documentation carries two `<img>` tags pointing at Wikimedia. A panel
	/// that fetched them would put a completion list on the network, which is
	/// not a thing a keystroke should do.
	@Test func aRemoteImageIsDroppedRatherThanFetched() throws {
		let readable = ServerDocumentation.readable(try cubeDocumentation())

		#expect(!readable.contains("https://upload.wikimedia.org"))
		#expect(!readable.contains("wikibooks.org"))
	}

	/// What is *inside* a fence is the example, and the examples are half of
	/// what makes this documentation worth showing.
	@Test func codeInsideAFenceIsKept() throws {
		let readable = ServerDocumentation.readable(try cubeDocumentation())

		#expect(readable.contains("cube(size = [ x, y, z ], center = true / false);"))
		#expect(readable.contains("module cube(size, center=false)"))
	}

	/// A vector in prose is not a link, and this documentation is full of them.
	@Test func bracketsThatAreNotLinksAreLeftAlone() {
		#expect(ServerDocumentation.readable("3 value array [x,y,z], of numbers")
			== "3 value array [x,y,z], of numbers")
	}

	@Test func aLinkBecomesItsText() {
		#expect(ServerDocumentation.readable("see [the manual](https://example.com/a) for more")
			== "see the manual for more")
	}

	/// An alt text on a line of its own reads as a caption for a picture that is
	/// not there.
	@Test func anImageBecomesNothing() {
		#expect(ServerDocumentation.readable("![a cube](https://example.com/cube.jpg)").isEmpty)
	}

	/// A pair of underscores in this prose is nearly always one identifier, and
	/// `isFileRevealingEnabled` mangled into one word is worse than an
	/// underscore left where somebody meant italics.
	@Test func underscoresInIdentifiersSurvive() {
		#expect(ServerDocumentation.readable("set is_file_revealing_enabled to false")
			== "set is_file_revealing_enabled to false")
	}

	/// A `<` with no `>` after it is arithmetic, not a tag, and eating the rest
	/// of the line for it would be the worse mistake.
	@Test func anUnclosedAngleBracketIsProse() {
		#expect(ServerDocumentation.readable("true when a < b") == "true when a < b")
	}

	@Test func aMarkerThatNeverClosesKeepsIt() {
		#expect(ServerDocumentation.readable("2 * 3 is six") == "2 * 3 is six")
	}

	/// A page written with a blank line between every heading arrives as mostly
	/// nothing otherwise.
	@Test func runsOfBlankLinesBecomeOne() {
		#expect(ServerDocumentation.readable("one\n\n\n\n\ntwo") == "one\n\ntwo")
	}
}
