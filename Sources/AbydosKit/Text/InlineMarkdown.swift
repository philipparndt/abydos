import Foundation

/// The emphasis inside one line of markdown, as spans a view can set fonts on.
///
/// `ServerDocumentation.inline` answers a different question about the same
/// markup — it *takes the markers off* for a panel that draws plain text — and
/// a task on a card is the other case: the words are worth drawing as the
/// person who wrote them meant, and `**Measure the build before settling
/// this.**` shown with its asterisks is markup leaking into the product.
///
/// Spans rather than an attributed string, because this module holds no view
/// code and because what a span becomes differs by where it is drawn: a bold
/// run is a heavier face in a tip and a `<strong>` somewhere else. The rule for
/// what is emphasis and what is prose can be checked without either.
public enum InlineMarkdown {
	/// A run of text and what the markup said about it.
	public struct Span: Equatable, Sendable {
		public let text: String
		public let bold: Bool
		public let italic: Bool
		/// Backticks: drawn in a monospaced face, and never looked inside.
		public let code: Bool

		public init(text: String, bold: Bool = false, italic: Bool = false, code: Bool = false) {
			self.text = text
			self.bold = bold
			self.italic = italic
			self.code = code
		}
	}

	/// The line broken into runs, with the markers taken out of the text.
	///
	/// **A marker with no partner is prose.** A lone asterisk is a bullet or a
	/// footnote and a lone backtick is somebody's apostrophe for a shell
	/// command; either turned into emphasis would swallow the rest of the line.
	/// So a marker is only a marker once its closing partner has been found.
	///
	/// **Underscores are left alone**, though markdown emphasises with them.
	/// A pair in this prose is nearly always one identifier —
	/// `is_file_revealing_enabled`, `MAX_SIZE` — and `ServerDocumentation`
	/// settled the same question the same way for the same reason.
	///
	/// Code is closed before emphasis is looked for, so `**` inside backticks
	/// stays as it was typed.
	public static func spans(of line: String) -> [Span] {
		var spans: [Span] = []
		var plain = ""
		var rest = Substring(line)

		func flush() {
			guard !plain.isEmpty else { return }
			spans.append(Span(text: plain))
			plain = ""
		}

		while let character = rest.first {
			if character == "`",
			   let closed = take(from: rest.dropFirst(), until: "`", markerLength: 1) {
				flush()
				spans.append(Span(text: String(closed.text), code: true))
				rest = closed.rest
				continue
			}
			if character == "*", let emphasis = takeEmphasis(&rest) {
				flush()
				spans.append(emphasis)
				continue
			}
			plain.append(character)
			rest = rest.dropFirst()
		}
		flush()
		// A line with no markup at all is one span, and a line that was only
		// markers is none — both are what the callers expect to draw.
		return spans
	}

	/// The emphasis starting here, if this asterisk opens one.
	///
	/// Longest marker first, or `**bold**` opens as italic and closes on the
	/// first of the two asterisks meant to end it.
	///
	/// **Emphasis does not open on a space.** `2 * 3 * 4` is arithmetic and
	/// `a * b` is a product, and markdown itself says so — a delimiter with
	/// whitespace after it is not left-flanking and opens nothing.
	private static func takeEmphasis(_ rest: inout Substring) -> Span? {
		for marker in ["***", "**", "*"] where rest.hasPrefix(marker) {
			let after = rest.dropFirst(marker.count)
			guard let first = after.first, !first.isWhitespace,
			      let closed = take(from: after, until: "*", markerLength: marker.count)
			else { continue }
			rest = closed.rest
			return Span(
				text: String(closed.text),
				bold: marker.count >= 2,
				italic: marker.count != 2
			)
		}
		return nil
	}

	/// The text up to the next unescaped run of `marker`, and what follows it.
	///
	/// Nil when there is no partner, which is what makes a lone marker prose.
	/// An empty pair — `****` — is nil as well: emphasis around nothing is four
	/// characters somebody typed on purpose.
	private static func take(from text: Substring, until marker: Character, markerLength: Int)
		-> (text: Substring, rest: Substring)? {
		var index = text.startIndex
		while index < text.endIndex {
			guard text[index] == marker else {
				index = text.index(after: index)
				continue
			}
			// The whole marker has to be there, and there has to be something
			// in front of it.
			let run = text[index...].prefix(while: { $0 == marker })
			guard run.count >= markerLength, index > text.startIndex else {
				index = text.index(index, offsetBy: max(1, run.count))
				continue
			}
			let closing = text.index(index, offsetBy: markerLength)
			return (text[text.startIndex..<index], text[closing...])
		}
		return nil
	}

	/// The line with its markers taken off and nothing else changed — for the
	/// places that measure or search the words rather than draw them.
	public static func plain(_ line: String) -> String {
		spans(of: line).map(\.text).joined()
	}
}
