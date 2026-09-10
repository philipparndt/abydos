import Foundation

/// A web address a program printed, found in a row of cells.
///
/// **Found in the cells and not in the row's text**, because what the underline
/// and the hit test need are columns. A wide character before an address puts
/// the text one index behind the grid — an emoji is one character and two
/// columns — so a range found in `text` would underline the wrong cells by one
/// for every wide glyph to its left. The scan walks the cells, skips the
/// trailers, and carries the column each character came from.
///
/// This is the second kind of link a pane knows. The first is one a program
/// marks with OSC 8, which arrives with its own address and its own cells; a
/// row's printed addresses are the ones nobody marked, which is most of them —
/// a `git push` result, a stack trace, an agent's answer.
extension TerminalLine {
	/// One address: the columns it spans on this row, and where it points.
	public struct WebAddress: Equatable, Sendable {
		public let columns: Range<Int>
		public let url: URL
	}

	/// The addresses printed on this row, left to right.
	///
	/// **A scheme is required.** `http://`, `https://` and `mailto:` are the
	/// three; `www.` and bare domains are not found, because every rule for
	/// them also matches `README.md`, a version number or a package name, and
	/// an underline that lies is worse than one that is missing. `file://` is
	/// not found either: what it would open is the Finder, and the pane has
	/// `abydos <file>` for that.
	///
	/// **Where an address ends.** At whitespace, a quote, or an angle bracket —
	/// `<https://…>` is a common way to quote one, and comes out without the
	/// brackets. Trailing `.`, `,`, `;`, `:`, `!` and `?` are not part of it: a
	/// URL at the end of a sentence does not carry the full stop. A trailing
	/// `)` is dropped only when the run has no `(` to match it, so
	/// `https://en.wikipedia.org/wiki/Diff_(computing)` keeps its bracket and
	/// `(see https://example.org)` does not.
	public func webAddresses() -> [WebAddress] {
		// The row as characters, each remembering its column.
		var characters: [Character] = []
		var columns: [Int] = []
		characters.reserveCapacity(cells.count)
		columns.reserveCapacity(cells.count)
		for (column, cell) in cells.enumerated() where !cell.isWideTrailer {
			characters.append(cell.character)
			columns.append(column)
		}

		var found: [WebAddress] = []
		var index = 0
		while index < characters.count {
			guard let scheme = Self.scheme(at: index, in: characters) else {
				index += 1
				continue
			}
			var end = index + scheme
			while end < characters.count, !Self.ends(characters[end]) { end += 1 }
			// A closing bracket the address did not open, then the punctuation
			// a sentence puts after it — in that order, so `…org).` sheds both.
			while end > index + scheme {
				let last = characters[end - 1]
				if Self.trailingPunctuation.contains(last) {
					end -= 1
				} else if last == ")",
				          characters[index..<end].filter({ $0 == "(" }).count
				            < characters[index..<end].filter({ $0 == ")" }).count {
					end -= 1
				} else {
					break
				}
			}
			// Something after the scheme, or `https://` on its own is prose
			// about addresses rather than one.
			if end > index + scheme,
			   let url = URL(string: String(characters[index..<end])) {
				found.append(WebAddress(columns: columns[index]..<(columns[end - 1] + 1), url: url))
			}
			index = max(end, index + 1)
		}
		return found
	}

	private static let schemes: [[Character]] = [
		Array("https://"), Array("http://"), Array("mailto:"),
	]
	private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?"]

	/// The length of the scheme starting here, or nil when none does.
	private static func scheme(at index: Int, in characters: [Character]) -> Int? {
		for scheme in schemes where index + scheme.count <= characters.count {
			var matches = true
			for (offset, character) in scheme.enumerated() where characters[index + offset] != character {
				matches = false
				break
			}
			if matches { return scheme.count }
		}
		return nil
	}

	private static func ends(_ character: Character) -> Bool {
		character.isWhitespace || character == "\"" || character == "'"
			|| character == "<" || character == ">"
	}
}
