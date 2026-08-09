import Foundation

/// Fenced blocks a Markdown preview draws rather than prints.
///
/// Foundation's parser reports a fence's *language* and its text, which is
/// enough to colour it and not enough to replace it: the runs come back with
/// the fence markers already gone, so there is no way to put a picture where the
/// block was and keep everything around it. The preview therefore cuts the
/// blocks out of the source first, exactly as it already cuts out pipe tables,
/// and hands the parser what is left.
///
/// The cutting is string work with right answers, so it lives here and is tested
/// without a window. What is done with a block — drawn, or shown with its
/// complaint beside it — is the renderer's business.
public enum MarkdownFence {
	/// A fenced block worth drawing, or the prose between two of them.
	public enum Piece: Equatable, Sendable {
		/// Markdown to parse as it always was.
		case prose(String)
		/// A block to draw, with the line its opening fence is on so a complaint
		/// about line 3 of the diagram can be counted from somewhere real.
		case drawn(Drawn)
	}

	/// One fenced block this app can draw.
	public struct Drawn: Equatable, Sendable {
		/// What the info string said, lowercased: `mermaid` today and nothing
		/// else, kept as text so a second tool is a case rather than a type.
		public let language: String
		/// The block's content, with the fence's own indent taken off.
		public let source: String
		/// Which line of the file the opening fence is on, counting from 1.
		public let openingLine: Int

		public init(language: String, source: String, openingLine: Int) {
			self.language = language
			self.source = source
			self.openingLine = openingLine
		}
	}

	/// The languages a fence may claim to have a picture drawn of it.
	///
	/// One, and it is the one that needs nothing installed. A ```` ```plantuml ````
	/// fence is deliberately not here: drawing it means a container and a JVM per
	/// block, and a README with four of them would start four (0425, and 0422 for
	/// what one costs).
	public static let drawnLanguages: Set<String> = ["mermaid"]

	/// The document as prose and pictures.
	///
	/// Everything that is not a drawable fence — including every other fenced
	/// block, and a fence that is never closed — comes back as prose, character
	/// for character, so the parser downstream sees what it always saw.
	public static func split(_ markdown: String) -> [Piece] {
		let lines = markdown.components(separatedBy: "\n")
		var pieces: [Piece] = []
		var prose: [String] = []
		var index = 0

		func flushProse() {
			guard !prose.isEmpty else { return }
			pieces.append(.prose(prose.joined(separator: "\n")))
			prose = []
		}

		while index < lines.count {
			guard let opening = openingFence(lines[index]) else {
				prose.append(lines[index])
				index += 1
				continue
			}

			// Where this block ends, whatever kind it is. A fence is scanned past
			// as a unit either way: a `|` row or a `#` inside one is content, and
			// the passes that follow must not see it as anything else.
			var end = index + 1
			while end < lines.count, !closesFence(lines[end], opening: opening) { end += 1 }
			let closed = end < lines.count
			let body = Array(lines[(index + 1)..<end])

			// An unclosed fence runs to the end of the file by CommonMark's rule,
			// and a diagram drawn from one is a diagram somebody is still typing.
			// It is left as prose so the parser makes its own code block of it,
			// which is what the preview showed before this existed.
			guard drawnLanguages.contains(opening.language), closed else {
				prose.append(contentsOf: lines[index...min(end, lines.count - 1)])
				index = end + 1
				continue
			}

			flushProse()
			pieces.append(.drawn(Drawn(
				language: opening.language,
				source: body.map { stripped($0, by: opening.indent) }.joined(separator: "\n"),
				openingLine: index + 1
			)))
			index = end + 1
		}

		flushProse()
		return pieces
	}

	// MARK: - Reading a fence

	private struct Opening {
		let marker: Character
		let length: Int
		let indent: Int
		let language: String
	}

	/// A line that opens a fenced block, and what it says about itself.
	///
	/// CommonMark's rules, and only the ones that change an answer here: up to
	/// three spaces of indent, three or more backticks or tildes, and an info
	/// string whose first word names the language. A backtick fence's info string
	/// may not contain a backtick — that is what keeps `` `code` `` in a paragraph
	/// from being read as the top of a block.
	private static func openingFence(_ line: String) -> Opening? {
		let indent = line.prefix { $0 == " " }.count
		guard indent <= 3 else { return nil }
		let body = line.dropFirst(indent)
		guard let marker = body.first, marker == "`" || marker == "~" else { return nil }
		let length = body.prefix { $0 == marker }.count
		guard length >= 3 else { return nil }

		let info = body.dropFirst(length).trimmingCharacters(in: .whitespaces)
		guard marker != "`" || !info.contains("`") else { return nil }
		let language = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first ?? ""
		return Opening(
			marker: marker, length: length, indent: indent,
			language: language.lowercased()
		)
	}

	/// A line that closes the block this one opened: the same character, at least
	/// as many of them, and nothing else on the line.
	private static func closesFence(_ line: String, opening: Opening) -> Bool {
		let indent = line.prefix { $0 == " " }.count
		guard indent <= 3 else { return false }
		let body = line.dropFirst(indent)
		guard body.first == opening.marker else { return false }
		let length = body.prefix { $0 == opening.marker }.count
		guard length >= opening.length else { return false }
		return body.dropFirst(length).allSatisfy { $0 == " " || $0 == "\t" }
	}

	/// A content line with the opening fence's own indent removed, and no more.
	///
	/// A block indented two spaces inside a list item is written at column 0 in
	/// the diagram; a line indented *further* than the fence keeps the difference,
	/// which in Mermaid is how a subgraph is laid out to be read.
	private static func stripped(_ line: String, by indent: Int) -> String {
		var removed = 0
		var rest = Substring(line)
		while removed < indent, rest.first == " " {
			rest = rest.dropFirst()
			removed += 1
		}
		return String(rest)
	}
}
