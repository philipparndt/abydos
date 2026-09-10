import Foundation
import Testing
@testable import AbydosKit

/// Where a printed web address begins and ends on a row, in columns.
///
/// Feedback of 2026-09-10: ⌘ over a link should underline it and a click open
/// it, as every other terminal on this platform does. An address a program
/// merely printed was text here, so this is the rule for finding one — and the
/// rule has to say where the address *ends*, because a URL at the end of a
/// sentence must not carry the full stop into the browser.
struct WebAddressTests {
	private func line(_ text: String) -> TerminalLine {
		var line = TerminalLine(columns: text.count + 4)
		var column = 0
		for character in text {
			line.cells[column] = TerminalCell(character: character)
			column += 1
		}
		return line
	}

	private func found(_ text: String) -> [(String, Range<Int>)] {
		line(text).webAddresses().map { ($0.url.absoluteString, $0.columns) }
	}

	@Test func anAddressIsFoundWithItsColumns() {
		let hits = found("pushed to https://github.com/example/repo/pull/12 just now")
		#expect(hits.count == 1)
		#expect(hits.first?.0 == "https://github.com/example/repo/pull/12")
		#expect(hits.first?.1 == 10..<49)
	}

	@Test func anAddressAtTheEndOfASentenceLeavesTheFullStop() {
		#expect(found("See https://example.org/page.").first?.0 == "https://example.org/page")
		#expect(found("Try https://example.org, or not").first?.0 == "https://example.org")
		#expect(found("Is it https://example.org?").first?.0 == "https://example.org")
	}

	@Test func aWikipediaAddressKeepsItsBracket() {
		#expect(found("https://en.wikipedia.org/wiki/Diff_(computing)").first?.0
			== "https://en.wikipedia.org/wiki/Diff_(computing)")
	}

	@Test func aBracketTheAddressDidNotOpenIsNotPartOfIt() {
		#expect(found("(see https://example.org)").first?.0 == "https://example.org")
		// Both at once: the bracket first, then the full stop the sentence put
		// after it.
		#expect(found("(see https://example.org).").first?.0 == "https://example.org")
	}

	@Test func anAddressInAngleBracketsComesOutWithoutThem() {
		let hits = found("From: <https://example.org/x> today")
		#expect(hits.first?.0 == "https://example.org/x")
		#expect(hits.first?.1 == 7..<28)
	}

	@Test func twoAddressesOnOneLineAreTwo() {
		let hits = found("http://a.example and mailto:someone@example.org")
		#expect(hits.map(\.0) == ["http://a.example", "mailto:someone@example.org"])
	}

	/// **The reason this is over the cells.** An emoji is one character and two
	/// columns; a range found in the row's text would be one column short for
	/// every wide glyph to the address's left.
	@Test func aWideCharacterBeforeTheAddressDoesNotShiftItsColumns() {
		var line = TerminalLine(columns: 40)
		line.cells[0] = TerminalCell(scalar: 0x1F600)          // 😀, two columns wide
		line.cells[1] = TerminalCell(scalar: 0x20, isWideTrailer: true)
		line.cells[2] = TerminalCell(character: " ")
		for (offset, character) in "https://x.example".enumerated() {
			line.cells[3 + offset] = TerminalCell(character: character)
		}
		let hits = line.webAddresses()
		#expect(hits.first?.url.absoluteString == "https://x.example")
		#expect(hits.first?.columns == 3..<20)
	}

	@Test func anAddressWithoutASchemeIsNotOne() {
		#expect(found("open www.example.org or README.md").isEmpty)
		#expect(found("file:///Users/somebody/notes.txt").isEmpty)
	}

	@Test func aSchemeOnItsOwnIsProseAboutAddresses() {
		#expect(found("the https:// prefix").isEmpty)
	}

	@Test func aLineWithNoAddressFindsNone() {
		#expect(found("just words, and a colon: here").isEmpty)
		#expect(TerminalLine(columns: 80).webAddresses().isEmpty)
	}
}
