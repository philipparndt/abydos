import Foundation

/// A grammar-independent token category.
///
/// tree-sitter grammars each invent their own capture names ("function.method",
/// "variable.parameter.builtin", "string.special.path", …). Collapsing them here
/// means the theme has one small set of cases to colour instead of hundreds of
/// grammar-specific strings.
public enum HighlightKind: UInt8, Sendable, CaseIterable {
	case plain
	case keyword
	case type
	case function
	case method
	case property
	case variable
	case parameter
	case constant
	case string
	case escape
	case number
	case boolean
	case comment
	case documentation
	case operatorToken
	case punctuation
	case tag
	case attribute
	case label
	case namespace
	case heading
	case link
	case emphasis
	case error

	/// Resolves a capture name to a category, most specific component first.
	///
	/// Capture names are dot-separated and ordered general→specific
	/// ("function.method.builtin"). Trying successively shorter prefixes means an
	/// unrecognised specialisation still lands on its general category rather
	/// than falling through to `plain`.
	public static func from(captureName name: String) -> HighlightKind {
		if let exact = lookup[name] { return exact }

		var components = name.split(separator: ".").map(String.init)
		while components.count > 1 {
			components.removeLast()
			if let match = lookup[components.joined(separator: ".")] { return match }
		}
		return .plain
	}

	private static let lookup: [String: HighlightKind] = [
		// Keywords and control flow
		"keyword": .keyword,
		"conditional": .keyword,
		"repeat": .keyword,
		"include": .keyword,
		"import": .keyword,
		"exception": .keyword,
		"storageclass": .keyword,
		"modifier": .keyword,
		"define": .keyword,
		"preproc": .keyword,

		// Types
		"type": .type,
		"class": .type,
		"struct": .type,
		"enum": .type,
		"interface": .type,
		"constructor": .type,

		// Callables
		"function": .function,
		"function.method": .method,
		"method": .method,
		"function.macro": .keyword,

		// Values and identifiers
		"variable": .variable,
		"variable.parameter": .parameter,
		"parameter": .parameter,
		"variable.member": .property,
		"property": .property,
		"field": .property,
		"attribute": .attribute,
		"constant": .constant,
		"constant.builtin": .boolean,
		"number": .number,
		"float": .number,
		"boolean": .boolean,
		"character": .string,
		"string": .string,
		"string.escape": .escape,
		"escape": .escape,
		"string.special": .link,

		// Comments
		"comment": .comment,
		"comment.documentation": .documentation,
		"spell": .comment,

		// Symbols
		"operator": .operatorToken,
		"punctuation": .punctuation,
		"punctuation.bracket": .punctuation,
		"punctuation.delimiter": .punctuation,
		"punctuation.special": .operatorToken,

		// Markup (Markdown, HTML)
		"tag": .tag,
		"tag.attribute": .attribute,
		"label": .label,
		"namespace": .namespace,
		"module": .namespace,
		"text.title": .heading,
		"markup.heading": .heading,
		"text.uri": .link,
		"markup.link": .link,
		"markup.link.url": .link,
		"text.emphasis": .emphasis,
		"markup.italic": .emphasis,
		"markup.strong": .emphasis,
		"markup.raw": .string,

		// Problems
		"error": .error,
	]
}

/// A resolved syntax span: a UTF-16 range in the document and its category.
///
/// UTF-16 because this is consumed directly by the text view, and that is the
/// unit AppKit and CoreText work in.
public struct HighlightToken: Sendable, Equatable {
	public var range: Range<Int>
	public var kind: HighlightKind

	public init(range: Range<Int>, kind: HighlightKind) {
		self.range = range
		self.kind = kind
	}
}
