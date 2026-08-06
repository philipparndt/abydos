import Foundation

/// Highlighting a fragment of code that is not in a file.
///
/// A breakpoint's condition is code — `id == "lamarzocco"`, `len(os.Args) > 2`
/// — and it was typed into a plain text field, where a string and an operator
/// and a name all look the same. Anywhere else in this app that would be
/// coloured, and a condition is the one piece of code somebody writes without
/// the editor's help.
///
/// Tree-sitter parses the fragment on its own. A condition is not a program and
/// will not parse as one, which matters less than it sounds: the parser
/// recovers, and what comes back is right for the parts that are locally
/// unambiguous — quotes, numbers, operators, calls — which is the whole of what
/// there is to colour in one line.
public enum ExpressionHighlight {
	/// Tokens for a fragment, as UTF-16 ranges within it.
	public static func tokens(in text: String, languageId: String) -> [HighlightToken] {
		guard !text.isEmpty,
		      let engine = SyntaxEngine(languageId: languageId),
		      engine.hasHighlightQuery
		else { return [] }

		// Wrapped so it parses as something. A bare expression is a statement in
		// most languages and a syntax error in some; an assignment is a
		// declaration everywhere that has one, and the offset is subtracted
		// again below so ranges belong to what was typed.
		let prefix = wrapper(for: languageId)
		let rope = Rope(prefix + text)
		let start = prefix.utf8.count
		// Parsed first: the engine keeps a tree and highlights against it, and
		// an engine that has parsed nothing has nothing to say.
		engine.parse(rope: rope)

		return engine.highlights(rope: rope, byteRange: 0..<rope.byteCount)
			.compactMap { token in
				// Anything the wrapper contributed is not the fragment's.
				guard token.range.lowerBound >= start else { return nil }
				return HighlightToken(
					range: (token.range.lowerBound - start)..<(token.range.upperBound - start),
					kind: token.kind
				)
			}
	}

	/// What to put in front of a fragment so it parses.
	///
	/// Nothing for the languages whose grammars accept an expression as a whole
	/// file, which is most of them; the rest get the shortest thing that makes
	/// the fragment a value in a position a parser expects one.
	static func wrapper(for languageId: String) -> String {
		switch languageId {
		case "go": return "package p\nvar _ = "
		case "java", "kotlin", "c", "cpp", "csharp": return "var _ = "
		default: return ""
		}
	}

	/// The interpolations in a log message — `i is {i}` has one.
	///
	/// A log message is not code but it contains code, and the braces are what
	/// say which part. Returned as UTF-16 ranges of the whole `{…}`, braces
	/// included, since that is the run to colour.
	public static func interpolations(in text: String) -> [Range<Int>] {
		var found: [Range<Int>] = []
		var open: Int?
		var depth = 0

		for (offset, character) in Array(text.utf16).enumerated() {
			switch character {
			case UInt16(UnicodeScalar("{").value):
				if depth == 0 { open = offset }
				depth += 1
			case UInt16(UnicodeScalar("}").value):
				guard depth > 0 else { continue }
				depth -= 1
				if depth == 0, let start = open {
					found.append(start..<(offset + 1))
					open = nil
				}
			default:
				continue
			}
		}
		return found
	}
}
