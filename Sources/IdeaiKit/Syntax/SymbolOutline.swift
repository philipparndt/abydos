import Foundation

/// One declaration in a file, as the structure view lists it.
public struct DocumentSymbol: Equatable, Sendable, Identifiable {
	public enum Kind: String, Sendable, CaseIterable {
		case type, protocolType, enumeration, function, method, property, constant, module, other

		/// SF Symbol used for the row. Kept here so the ordering rules and the
		/// icons cannot drift apart.
		public var symbolName: String {
			switch self {
			case .type:         return "cube"
			case .protocolType: return "circle.dashed"
			case .enumeration:  return "list.bullet.rectangle"
			case .function:     return "function"
			case .method:       return "f.cursive"
			case .property:     return "diamond"
			case .constant:     return "c.square"
			case .module:       return "shippingbox"
			case .other:        return "circle"
			}
		}
	}

	public let name: String
	public let kind: Kind
	/// Zero-based line the declaration starts on.
	public let line: Int
	/// Byte range of the whole declaration, used to nest symbols.
	public let byteRange: Range<Int>
	public var children: [DocumentSymbol]

	public var id: String { "\(byteRange.lowerBound):\(name)" }

	public init(
		name: String,
		kind: Kind,
		line: Int,
		byteRange: Range<Int>,
		children: [DocumentSymbol] = []
	) {
		self.name = name
		self.kind = kind
		self.line = line
		self.byteRange = byteRange
		self.children = children
	}
}

/// Turns a grammar's `tags.scm` captures into a nested outline.
public enum SymbolOutline {
	/// Maps a tags capture name to a symbol kind.
	///
	/// The capture vocabulary is ctags', shared across grammars: every
	/// `tags.scm` names its definitions `@definition.<something>`. Unknown
	/// suffixes fall through to `.other` rather than being dropped — a symbol
	/// with a dull icon is more useful than a missing one.
	public static func kind(forCapture capture: String) -> DocumentSymbol.Kind? {
		guard capture.hasPrefix("definition.") else { return nil }

		switch String(capture.dropFirst("definition.".count)) {
		case "class", "struct", "type", "typedef": return .type
		case "interface", "protocol", "trait":     return .protocolType
		case "enum":                               return .enumeration
		case "function":                           return .function
		case "method":                             return .method
		case "field", "property", "member":        return .property
		case "constant", "constructor":            return .constant
		case "module", "namespace", "package":     return .module
		default:                                   return .other
		}
	}

	/// Nests a flat list of symbols by containment.
	///
	/// A method's byte range sits inside its type's, which is the only
	/// relationship the tags queries express — they capture declarations
	/// independently and say nothing about which encloses which.
	public static func nest(_ flat: [DocumentSymbol]) -> [DocumentSymbol] {
		// The same declaration can be captured by more than one pattern; keep
		// the first, which is the most specific the grammar offered.
		var seen = Set<String>()
		let unique = flat.filter { seen.insert("\($0.byteRange.lowerBound):\($0.byteRange.upperBound):\($0.name)").inserted }

		// Outermost first at each position, so a parent is always reached
		// before the children it encloses.
		let sorted = unique.sorted {
			$0.byteRange.lowerBound != $1.byteRange.lowerBound
				? $0.byteRange.lowerBound < $1.byteRange.lowerBound
				: $0.byteRange.upperBound > $1.byteRange.upperBound
		}

		var index = 0
		return build(sorted, &index, within: nil)
	}

	/// Consumes symbols from `index` while they fall inside `parent`.
	private static func build(
		_ symbols: [DocumentSymbol],
		_ index: inout Int,
		within parent: Range<Int>?
	) -> [DocumentSymbol] {
		var result: [DocumentSymbol] = []

		while index < symbols.count {
			let symbol = symbols[index]
			if let parent, !contains(parent, symbol.byteRange) { break }

			index += 1
			var node = symbol
			node.children = build(symbols, &index, within: symbol.byteRange)
			result.append(node)
		}
		return result
	}

	private static func contains(_ outer: Range<Int>, _ inner: Range<Int>) -> Bool {
		outer.lowerBound <= inner.lowerBound && outer.upperBound >= inner.upperBound
	}
}
