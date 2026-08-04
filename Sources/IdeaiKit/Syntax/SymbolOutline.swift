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
	/// Byte range of just the name, which is where the symbol actually is.
	public let nameRange: Range<Int>
	public var children: [DocumentSymbol]

	public var id: String { "\(nameRange.lowerBound):\(name)" }

	public init(
		name: String,
		kind: Kind,
		line: Int,
		byteRange: Range<Int>,
		nameRange: Range<Int>? = nil,
		children: [DocumentSymbol] = []
	) {
		self.name = name
		self.kind = kind
		self.line = line
		self.byteRange = byteRange
		self.nameRange = nameRange ?? byteRange
		self.children = children
	}

	/// Whether this symbol can hold others.
	var isContainer: Bool {
		switch kind {
		case .type, .protocolType, .enumeration, .module: return true
		default: return false
		}
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
		let unique = flat.filter { seen.insert("\($0.nameRange.lowerBound):\($0.name)").inserted }

		// Ordered by where the *name* is, which is where the symbol reads as
		// being. Ties go to the container, so a type is seen before the members
		// that share its declaration range.
		let sorted = unique.sorted {
			if $0.nameRange.lowerBound != $1.nameRange.lowerBound {
				return $0.nameRange.lowerBound < $1.nameRange.lowerBound
			}
			if $0.byteRange != $1.byteRange {
				return $0.byteRange.upperBound > $1.byteRange.upperBound
			}
			return $0.isContainer && !$1.isContainer
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
			if let parent, !contains(parent, symbol.nameRange) { break }

			index += 1
			var node = symbol
			// Only a container adopts. Several grammars capture a type and every
			// one of its members with the *same* declaration range, so treating
			// any enclosing range as a parent chains the members into each other
			// — one property nested inside the last, all the way down.
			if symbol.isContainer {
				node.children = build(symbols, &index, within: symbol.byteRange)
			}
			result.append(node)
		}
		return result
	}

	/// Whether a declaration's range holds a name, not counting the name of the
	/// declaration itself.
	private static func contains(_ outer: Range<Int>, _ inner: Range<Int>) -> Bool {
		outer.lowerBound <= inner.lowerBound && outer.upperBound >= inner.upperBound
	}

	/// The lines each symbol covers, 1-based and half-open, keyed by symbol id.
	///
	/// Not the declaration's own byte range: several grammars — Swift's among
	/// them — hang a method's `@definition` capture on the *enclosing type*, so
	/// every member of a type claims the type's whole span and a line inside one
	/// method reads as being inside all of them.
	///
	/// What can be trusted is where each name is and how the outline nests, so a
	/// symbol runs from its own declaration to wherever the next thing at its
	/// level starts — or to the end of whatever contains it, for the last one.
	/// That over-claims the blank lines and comments between two functions,
	/// which is the right way round: a breakpoint on the comment above a
	/// function belongs to the function above it either way, and no line is left
	/// belonging to nothing.
	public static func lineSpans(
		of symbols: [DocumentSymbol],
		lineCount: Int
	) -> [String: Range<Int>] {
		var spans: [String: Range<Int>] = [:]

		func walk(_ siblings: [DocumentSymbol], endingAt end: Int) {
			for (index, symbol) in siblings.enumerated() {
				let start = symbol.line + 1          // outline counts from 0, breakpoints from 1
				let next = index + 1 < siblings.count ? siblings[index + 1].line + 1 : end
				// A symbol always covers its own declaration line, even when the
				// next one starts on it.
				let span = start..<max(start + 1, next)
				spans[symbol.id] = span
				walk(symbol.children, endingAt: span.upperBound)
			}
		}

		walk(symbols, endingAt: lineCount + 1)
		return spans
	}
}
