import Foundation

/// A completion written in the snippet syntax, turned into text and a caret.
///
/// Servers answer with more than the word: `union() $0` puts the caret between
/// the braces that follow, `${1:name}` offers a default to type over. Inserted
/// as written, that is a syntax error somebody has to go back and delete —
/// which is what `unio` + Tab produced here, an OpenSCAD file containing
/// `union() $0`.
///
/// The grammar, as far as it is worth going:
///
/// - `$0` … `$9` — a tab stop. `$0` is where the caret ends up.
/// - `${1:default}` — a tab stop with text to leave behind.
/// - `${1|one,two|}` — a choice; the first is what goes in.
/// - `\$`, `\}`, `\\` — the character itself.
///
/// Tab stops other than `$0` leave their default text and are otherwise
/// dropped: jumping between them needs the editor to hold a list of ranges
/// through subsequent edits, which is a feature rather than a fix.
public struct Snippet: Equatable, Sendable {
	/// The text to insert.
	public let text: String
	/// Where the caret belongs, as a UTF-16 offset into `text`.
	public let caret: Int

	public init(text: String, caret: Int) {
		self.text = text
		self.caret = caret
	}

	/// Reads a snippet. Anything that is not one comes back unchanged, with the
	/// caret at the end — which is what inserting a plain completion does.
	public static func expand(_ source: String) -> Snippet {
		var text = ""
		var caret: Int?
		var firstStop: Int?
		let characters = Array(source)
		var index = 0

		func append(_ string: String) { text += string }

		while index < characters.count {
			let character = characters[index]

			// An escape is the character after it, whatever that character is.
			if character == "\\", index + 1 < characters.count {
				append(String(characters[index + 1]))
				index += 2
				continue
			}

			guard character == "$", index + 1 < characters.count else {
				append(String(character))
				index += 1
				continue
			}

			let next = characters[index + 1]

			// `$0`, `$1`, …
			if next.isNumber {
				var cursor = index + 1
				var number = ""
				while cursor < characters.count, characters[cursor].isNumber {
					number.append(characters[cursor])
					cursor += 1
				}
				let stop = Int(number) ?? 0
				if stop == 0 { caret = text.utf16.count } else if firstStop == nil {
					firstStop = text.utf16.count
				}
				index = cursor
				continue
			}

			// `${…}`
			if next == "{", let close = closingBrace(in: characters, from: index + 1) {
				let body = String(characters[(index + 2)..<close])
				let (stop, replacement) = placeholder(body)
				if stop == 0 { caret = text.utf16.count } else if firstStop == nil {
					firstStop = text.utf16.count
				}
				append(replacement)
				index = close + 1
				continue
			}

			// A bare `$` that begins nothing is a dollar sign.
			append(String(character))
			index += 1
		}

		// `$0` when there is one; otherwise the first thing to type over;
		// otherwise the end, which is where a plain completion leaves it.
		return Snippet(text: text, caret: caret ?? firstStop ?? text.utf16.count)
	}

	/// The number and the text a `${…}` leaves behind.
	static func placeholder(_ body: String) -> (stop: Int, text: String) {
		// `1|one,two|` — a choice, of which the first is taken.
		if let bar = body.firstIndex(of: "|"), body.hasSuffix("|") {
			let number = Int(body[body.startIndex..<bar]) ?? 1
			let choices = body[body.index(after: bar)..<body.index(before: body.endIndex)]
			return (number, choices.split(separator: ",").first.map(String.init) ?? "")
		}

		// `1:default`
		if let colon = body.firstIndex(of: ":") {
			let number = Int(body[body.startIndex..<colon]) ?? 1
			// Nested placeholders in the default are expanded too, since a
			// default is a snippet — `${1:${2:inner}}` happens.
			return (number, expand(String(body[body.index(after: colon)...])).text)
		}

		// `1` — a stop with nothing to leave.
		return (Int(body) ?? 1, "")
	}

	/// The `}` that closes the `{` at `open`, allowing for nesting.
	static func closingBrace(in characters: [Character], from open: Int) -> Int? {
		var depth = 0
		var index = open
		while index < characters.count {
			switch characters[index] {
			case "\\": index += 1
			case "{": depth += 1
			case "}":
				depth -= 1
				if depth == 0 { return index }
			default: break
			}
			index += 1
		}
		return nil
	}
}
