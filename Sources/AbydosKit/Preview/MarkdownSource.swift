import Foundation

/// The document as Foundation's markdown parser should see it.
///
/// The preview parses with `AttributedString(markdown:)`, which is cmark-gfm
/// behind an `AttributedString`, and two of the things it does are wrong rather
/// than merely absent:
///
/// - **A link's label is flattened.** `[a **b** c](url)` comes back as one run
///   carrying the link and nothing else; the `**` was parsed, its markers were
///   removed, and the attribute was dropped. There is no child to walk.
/// - **A stray `~` eats the emphasis it sits inside.** `**~ 211 €**` renders
///   literally, asterisks and all, because GFM's strikethrough extension pushes
///   that tilde on the delimiter stack as a closer, finds nothing it can close,
///   and records a lower bound that the `**` opener is now behind.
///
/// Neither is reachable through the parsing options — `.full` and
/// `.inlineOnlyPreservingWhitespace` behave the same, and there is no way to
/// turn the strikethrough extension off. So the repair is here, on **the copy
/// handed to the parser**: never the file on disk, never the text in the
/// editor, and never anything anybody typed.
public enum MarkdownSource {
	/// Both repairs, in the order they need: the tildes first, because the link
	/// lift parses each label on its own and would trip over the same bug.
	public static func repaired(_ markdown: String) -> String {
		liftedLinkEmphasis(escapedStrayTildes(markdown))
	}

	// MARK: - Stray tildes

	/// Escapes every `~` that could close a strikethrough and has nothing to
	/// close, which is exactly the shape that derails cmark's emphasis matching.
	///
	/// `\~` parses as the same character and is not a delimiter, so the text is
	/// unchanged and the trip hazard is gone. Runs are paired first, so
	/// `~~struck~~` and `~struck~` are left exactly as they were written.
	public static func escapedStrayTildes(_ markdown: String) -> String {
		let characters = Array(markdown)
		let protected = protectedMask(characters)

		// Every run of tildes the parser would look at, with how it flanks.
		struct Run {
			let range: Range<Int>
			let canOpen: Bool
			let canClose: Bool
		}
		var runs: [Run] = []
		var index = 0
		while index < characters.count {
			guard !protected[index], characters[index] == "~", !isEscaped(characters, at: index) else {
				index += 1
				continue
			}
			var end = index
			while end < characters.count, characters[end] == "~", !protected[end] { end += 1 }
			let (left, right) = flanking(characters, start: index, end: end)
			runs.append(Run(range: index..<end, canOpen: left, canClose: right))
			index = end
		}

		// The parser's own pairing, which is all that is needed to tell a run
		// that is part of a strikethrough from one that is only in the way. An
		// unmatched *opener* is left alone: it writes no lower bound, and
		// `**~211**` is already bold. Only an unmatched closer is escaped.
		var openers: [Int] = []
		var stray: Set<Int> = []
		for (number, run) in runs.enumerated() {
			if run.canClose, openers.popLast() != nil { continue }
			if run.canOpen { openers.append(number); continue }
			if run.canClose { stray.formUnion(run.range) }
		}
		guard !stray.isEmpty else { return markdown }

		var output = ""
		output.reserveCapacity(markdown.count + stray.count)
		for (position, character) in characters.enumerated() {
			if stray.contains(position) { output.append("\\") }
			output.append(character)
		}
		return output
	}

	// MARK: - Emphasis inside a link

	/// Moves inline markup out of a link's label and around the link instead.
	///
	/// `[a **b** c](url)` becomes `[a ](url)**[b](url)**[ c](url)`. Foundation
	/// keeps emphasis that is *around* a link, and two links to the same
	/// destination side by side come back as adjacent runs, so what the pane is
	/// given is what should have come out of the parser in the first place.
	///
	/// Code spans are deliberately left where they are: `` ` `` outside the link
	/// would stop being part of it, and a label that *is* a code span would stop
	/// being a link at all — a worse bug than the one this fixes.
	public static func liftedLinkEmphasis(_ markdown: String) -> String {
		let characters = Array(markdown)
		let protected = protectedMask(characters)
		var output = ""
		var index = 0

		while index < characters.count {
			guard !protected[index], characters[index] == "[", !isEscaped(characters, at: index),
			      !(index > 0 && characters[index - 1] == "!" && !isEscaped(characters, at: index - 1)),
			      let label = labelEnd(characters, from: index, protected: protected),
			      let destination = destinationEnd(characters, from: label + 1)
			else {
				output.append(characters[index])
				index += 1
				continue
			}

			let text = String(characters[(index + 1)..<label])
			let target = String(characters[(label + 1)...destination])
			if let lifted = lifted(label: text, destination: target) {
				output += lifted
			} else {
				output += String(characters[index...destination])
			}
			index = destination + 1
		}
		return output
	}

	/// One link, rewritten as a run of links with the markup outside them, or
	/// nil when its label carries nothing worth moving.
	private static func lifted(label: String, destination: String) -> String? {
		var options = AttributedString.MarkdownParsingOptions()
		options.interpretedSyntax = .inlineOnlyPreservingWhitespace
		options.failurePolicy = .returnPartiallyParsedIfPossible
		guard let parsed = try? AttributedString(markdown: label, options: options) else { return nil }

		let moveable: InlinePresentationIntent = [.stronglyEmphasized, .emphasized, .strikethrough]
		var pieces: [(text: String, intent: InlinePresentationIntent)] = []
		for run in parsed.runs {
			let text = String(parsed[run.range].characters)
			guard !text.isEmpty else { continue }
			pieces.append((text, run.inlinePresentationIntent ?? []))
		}
		guard pieces.contains(where: { !$0.intent.intersection(moveable).isEmpty }) else { return nil }

		var output = ""
		for piece in pieces {
			var markers = ""
			if piece.intent.contains(.strikethrough) { markers += "~~" }
			if piece.intent.contains(.stronglyEmphasized) { markers += "**" }
			if piece.intent.contains(.emphasized) { markers += "*" }
			output += markers
			output += "[" + escapedAsLabel(piece.text) + "]" + destination
			output += String(markers.reversed())
		}
		return output
	}

	/// The label is being written back out as source, so anything in it that
	/// would be read as markup has to say that it is not.
	private static func escapedAsLabel(_ text: String) -> String {
		var output = ""
		for character in text {
			if "\\`*_[]<>~".contains(character) { output.append("\\") }
			output.append(character)
		}
		return output
	}

	/// The `]` closing a label opened at `open`, honouring nesting and escapes.
	private static func labelEnd(_ characters: [Character], from open: Int, protected: [Bool]) -> Int? {
		var depth = 0
		var index = open
		while index < characters.count {
			defer { index += 1 }
			if protected[index] || isEscaped(characters, at: index) { continue }
			if characters[index] == "[" { depth += 1 }
			if characters[index] == "]" {
				depth -= 1
				if depth == 0 { return index }
			}
			// A label does not run past a blank line.
			if characters[index] == "\n", index + 1 < characters.count, characters[index + 1] == "\n" {
				return nil
			}
		}
		return nil
	}

	/// The `)` closing an inline destination, when the label is followed by one.
	private static func destinationEnd(_ characters: [Character], from open: Int) -> Int? {
		guard open < characters.count, characters[open] == "(" else { return nil }
		var depth = 0
		var index = open
		while index < characters.count {
			defer { index += 1 }
			if isEscaped(characters, at: index) { continue }
			if characters[index] == "(" { depth += 1 }
			if characters[index] == ")" {
				depth -= 1
				if depth == 0 { return index }
			}
			if characters[index] == "\n" { return nil }
		}
		return nil
	}

	// MARK: - What the inline parser does not look at

	/// True when the character at `index` is preceded by an odd number of
	/// backslashes, and so is itself rather than markup.
	private static func isEscaped(_ characters: [Character], at index: Int) -> Bool {
		var count = 0
		var position = index - 1
		while position >= 0, characters[position] == "\\" {
			count += 1
			position -= 1
		}
		return count % 2 == 1
	}

	/// Characters the inline parser will never look at, which must therefore
	/// come through exactly as written: fenced blocks, indented blocks, and
	/// inline code spans.
	///
	/// Indented blocks are here because of this repository's own backlog — an
	/// entry quoting `**~ 211**` as the bug it is about would otherwise have a
	/// backslash put into the quotation.
	private static func protectedMask(_ characters: [Character]) -> [Bool] {
		var mask = [Bool](repeating: false, count: characters.count)

		var lineStarts = [0]
		for (index, character) in characters.enumerated() where character == "\n" {
			lineStarts.append(index + 1)
		}
		var fence: Character?
		var fenceLength = 0
		var afterBlank = true
		var inIndentedBlock = false
		var inList = false
		for (number, start) in lineStarts.enumerated() {
			let end = number + 1 < lineStarts.count ? lineStarts[number + 1] : characters.count
			guard start < end else { continue }
			let line = characters[start..<end]
			let body = line.drop { $0 == " " || $0 == "\t" }
			let marker = body.first
			let run = (marker == "`" || marker == "~") ? body.prefix { $0 == marker }.count : 0

			if let open = fence {
				for index in start..<end { mask[index] = true }
				if marker == open, run >= fenceLength { fence = nil }
				continue
			}
			if run >= 3, let marker {
				fence = marker
				fenceLength = run
				for index in start..<end { mask[index] = true }
				afterBlank = false
				continue
			}

			// Four spaces is a code block only where a paragraph could have
			// started, and not inside a list, where the same indent is how a
			// second paragraph belongs to an item.
			let blank = body.first == nil || body.first == "\n"
			if blank {
				afterBlank = true
				continue
			}
			let indent = line.prefix { $0 == " " }.count + line.prefix { $0 == "\t" }.count * 4
			if indent >= 4, !inList, afterBlank || inIndentedBlock {
				inIndentedBlock = true
				for index in start..<end { mask[index] = true }
			} else {
				inIndentedBlock = false
				if indent < 4 { inList = isListItem(body) }
			}
			afterBlank = false
		}

		var index = 0
		while index < characters.count {
			guard !mask[index], characters[index] == "`", !isEscaped(characters, at: index) else {
				index += 1
				continue
			}
			var open = index
			while open < characters.count, characters[open] == "`" { open += 1 }
			let length = open - index

			// A code span ends at the next run of backticks of the same length.
			var search = open
			while search < characters.count {
				guard !mask[search], characters[search] == "`" else { search += 1; continue }
				var close = search
				while close < characters.count, characters[close] == "`" { close += 1 }
				if close - search == length {
					for position in index..<close { mask[position] = true }
					index = close
					break
				}
				search = close
			}
			if search >= characters.count { index = open }
		}
		return mask
	}

	/// True when a line opens a list item, whose indented continuation lines are
	/// prose rather than code.
	private static func isListItem(_ body: ArraySlice<Character>) -> Bool {
		guard let first = body.first else { return false }
		if "-+*".contains(first) {
			let next = body.dropFirst().first
			return next == " " || next == "\t"
		}
		let digits = body.prefix { $0.isNumber }
		guard !digits.isEmpty else { return false }
		let rest = body.dropFirst(digits.count)
		guard let dot = rest.first, dot == "." || dot == ")" else { return false }
		let next = rest.dropFirst().first
		return next == " " || next == "\t"
	}

	/// Whether a delimiter run flanks left, right, or both — CommonMark's rule,
	/// which is what decides whether a `~` can open or close a strikethrough.
	private static func flanking(
		_ characters: [Character], start: Int, end: Int
	) -> (left: Bool, right: Bool) {
		func isWhitespace(_ character: Character?) -> Bool {
			guard let character else { return true }
			return character.isWhitespace
		}
		func isPunctuation(_ character: Character?) -> Bool {
			guard let character else { return false }
			return character.isPunctuation || character.isSymbol
		}

		let before = start > 0 ? characters[start - 1] : nil
		let after = end < characters.count ? characters[end] : nil

		let left = !isWhitespace(after)
			&& (!isPunctuation(after) || isWhitespace(before) || isPunctuation(before))
		let right = !isWhitespace(before)
			&& (!isPunctuation(before) || isWhitespace(after) || isPunctuation(after))
		return (left, right)
	}
}
