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
/// Every stop leaves its default text behind, and `stops` says where each one
/// ended up, so an editor can put the caret on them in turn. `SnippetSession`
/// is what holds those places while somebody types into them.
///
/// Two limits, both deliberate:
///
/// - **A number mentioned twice is one stop, at its first mention.** The later
///   `${1:x}` stays as text. Mirroring — typing in one and having the other
///   follow — is a larger feature than this, and a wrong guess at it would
///   silently write the old default into somebody's file.
/// - **A stop inside another stop's default is not a stop.** `${1:${2:i}}`
///   leaves `i`, visitable as stop 1 and not as stop 2. Nested stops overlap
///   by construction, and a range that contains another cannot be typed into
///   without destroying it.
public struct Snippet: Equatable, Sendable {
	/// A place the caret can be put, and the text it starts out holding.
	public struct Stop: Equatable, Sendable {
		/// The number the snippet gave it. `0` is the last one, by definition.
		public let number: Int
		/// UTF-16 offsets into `text`. Empty when the stop had no default.
		public let range: Range<Int>

		public init(number: Int, range: Range<Int>) {
			self.number = number
			self.range = range
		}
	}

	/// The text to insert.
	public let text: String
	/// Where the caret belongs, as a UTF-16 offset into `text`.
	///
	/// Where it goes when nobody is stepping through the stops: `$0` if the
	/// snippet said one, otherwise the first stop, otherwise the end.
	public let caret: Int
	/// The stops in the order Tab visits them — `$1`, `$2`, … and `$0` last.
	public let stops: [Stop]

	public init(text: String, caret: Int, stops: [Stop] = []) {
		self.text = text
		self.caret = caret
		self.stops = stops
	}

	/// Reads a snippet. Anything that is not one comes back unchanged, with the
	/// caret at the end — which is what inserting a plain completion does.
	public static func expand(_ source: String) -> Snippet {
		var text = ""
		// In the order they were written, which is not the order they are
		// visited in; sorting comes after, once they all have their places.
		var found: [Stop] = []
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
				let here = text.utf16.count
				found.append(Stop(number: Int(number) ?? 0, range: here..<here))
				index = cursor
				continue
			}

			// `${…}`
			if next == "{", let close = closingBrace(in: characters, from: index + 1) {
				let body = String(characters[(index + 2)..<close])
				let (stop, replacement) = placeholder(body)
				let here = text.utf16.count
				append(replacement)
				found.append(Stop(number: stop, range: here..<text.utf16.count))
				index = close + 1
				continue
			}

			// A bare `$` that begins nothing is a dollar sign.
			append(String(character))
			index += 1
		}

		// A number said twice is one stop, at the first place it was said.
		var seen = Set<Int>()
		let stops = found
			.filter { seen.insert($0.number).inserted }
			// `$0` is last however early it was written, and the rest go in
			// the order they are numbered rather than the order they appear.
			.sorted { visitingOrder($0.number) < visitingOrder($1.number) }

		// `$0` when there is one; otherwise the first thing to type over;
		// otherwise the end, which is where a plain completion leaves it.
		let caret = stops.last.flatMap { $0.number == 0 ? $0.range.lowerBound : nil }
			?? stops.first?.range.lowerBound
			?? text.utf16.count
		return Snippet(text: text, caret: caret, stops: stops)
	}

	/// `$0` is the one the caret finishes on, so it sorts after every other.
	private static func visitingOrder(_ number: Int) -> Int {
		number == 0 ? .max : number
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
