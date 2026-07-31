import Foundation
import SwiftTreeSitter
// For TSInputEncodingUTF8: the encoding constants live in the C module, which
// SwiftTreeSitter wraps but does not re-export.
import TreeSitter

/// Owns the parse tree for one document and answers highlight queries.
///
/// Two decisions carry the performance here:
///
/// 1. **Incremental reparse.** Every edit is reported to tree-sitter as an
///    `InputEdit` before reparsing, so the old tree is reused and only the
///    damaged spine is rebuilt. Typing in a 50k-line file costs microseconds,
///    not a full reparse.
/// 2. **Viewport-scoped queries.** Highlights are extracted only for the byte
///    range actually on screen. Running a highlights query over a whole large
///    file is the single most expensive thing an editor can do, and it is also
///    entirely unnecessary — nobody can see the other 99%.
public final class SyntaxEngine {
	public let languageId: String

	private let configuration: LanguageConfiguration
	private let foldQuery: Query?
	private let parser = Parser()
	private var tree: MutableTree?

	/// Above this size the initial parse moves off the main thread so opening a
	/// file is never blocked on it.
	public static let asyncParseThreshold = 256 * 1024

	public init?(languageId: String) {
		guard let configuration = LanguageRegistry.shared.configuration(for: languageId) else {
			return nil
		}
		self.languageId = languageId
		self.configuration = configuration
		self.foldQuery = LanguageRegistry.shared.foldQuery(for: languageId)

		do {
			try parser.setLanguage(configuration.language)
		} catch {
			return nil
		}
	}

	public var hasHighlightQuery: Bool { configuration.queries[.highlights] != nil }

	// MARK: - Parsing

	/// Reads the rope in chunks for tree-sitter.
	///
	/// The rope hands back whole leaves, so the parser walks the document
	/// without the buffer ever being flattened into one contiguous allocation.
	private static func readBlock(for rope: Rope) -> Parser.ReadBlock {
		{ byteOffset, _ in
			guard let (bytes, start) = rope.chunk(containing: byteOffset) else {
				return nil // EOF
			}
			let local = byteOffset - start
			guard local >= 0 && local < bytes.count else { return nil }
			return Data(bytes[local...])
		}
	}

	/// Full parse, discarding any previous tree.
	public func parse(rope: Rope) {
		// UTF-8 so byte offsets line up with the rope; the default is UTF-16.
		tree = parser.parse(tree: nil as MutableTree?, encoding: TSInputEncodingUTF8, readBlock: Self.readBlock(for: rope))
	}

	/// Reports an edit and reparses against the existing tree.
	///
	/// `edit` must be applied before the reparse, otherwise tree-sitter cannot
	/// map old positions onto new ones and silently produces a full reparse.
	public func applyEdit(_ edit: InputEdit, newRope: Rope) {
		tree?.edit(edit)
		tree = parser.parse(tree: tree, encoding: TSInputEncodingUTF8, readBlock: Self.readBlock(for: newRope))
	}

	public var hasTree: Bool { tree != nil }

	// MARK: - Highlighting

	/// Highlight spans covering `byteRange`, as non-overlapping UTF-16 ranges.
	///
	/// Grammars deliberately emit overlapping captures — a general pattern plus a
	/// more specific one for the same node. `highlights()` orders them
	/// least-specific first, so painting them in order into a per-character array
	/// lets the most specific capture win, which is the resolution rule
	/// tree-sitter intends.
	public func highlights(rope: Rope, byteRange: Range<Int>) -> [HighlightToken] {
		guard let tree,
		      let root = tree.rootNode,
		      let query = configuration.queries[.highlights]
		else { return [] }

		let lo = max(0, min(byteRange.lowerBound, rope.byteCount))
		let hi = max(lo, min(byteRange.upperBound, rope.byteCount))
		guard hi > lo else { return [] }

		// `ts_query_cursor_exec` does not touch start_byte/end_byte, so setting
		// the range after execute is correct; matching is lazy and driven by
		// `next()`, which reads the range then.
		let cursor = query.execute(node: root, in: tree)
		cursor.setByteRange(range: UInt32(lo)..<UInt32(hi))

		// Predicates such as (#match? @x "^[A-Z]") need to read document text.
		//
		// The NSRange handed to the provider comes from `Node.range`, which
		// SwiftTreeSitter derives as byteOffset / 2 because it assumes UTF-16
		// input. We parse as UTF-8, so `.byteRange` (which multiplies by 2) is
		// what recovers the true byte offsets.
		let context = Predicate.Context(textProvider: { range, _ in
			let bytes = range.byteRange
			return rope.string(in: Int(bytes.lowerBound)..<Int(bytes.upperBound))
		})

		var matches: [QueryMatch] = []
		var resolving = cursor.resolve(with: context)
		while let match = resolving.next() {
			matches.append(match)
		}

		// Paint into a per-UTF-16-unit array over the visible slice only.
		let startUTF16 = rope.utf16Offset(fromByte: lo)
		let endUTF16 = rope.utf16Offset(fromByte: hi)
		let width = endUTF16 - startUTF16
		guard width > 0 else { return [] }

		var canvas = [HighlightKind](repeating: .plain, count: width)
		for named in matches.highlights() {
			let kind = HighlightKind.from(captureName: named.name)
			guard kind != .plain else { continue }

			// `tsRange.bytes` holds the real byte offsets. `NamedRange.range`
			// must not be used here — it applies the same UTF-16 halving.
			let bytes = named.tsRange.bytes
			let spanStart = rope.utf16Offset(fromByte: Int(bytes.lowerBound))
			let spanEnd = rope.utf16Offset(fromByte: Int(bytes.upperBound))

			let clampedStart = max(startUTF16, spanStart) - startUTF16
			let clampedEnd = min(endUTF16, spanEnd) - startUTF16
			guard clampedStart < clampedEnd, clampedStart >= 0, clampedEnd <= width else { continue }

			for i in clampedStart..<clampedEnd { canvas[i] = kind }
		}

		// Coalesce equal neighbours into runs so the renderer sets far fewer
		// attribute spans than there are characters.
		var tokens: [HighlightToken] = []
		var runStart = 0
		var runKind = canvas[0]
		for i in 1..<width where canvas[i] != runKind {
			if runKind != .plain {
				tokens.append(HighlightToken(range: (startUTF16 + runStart)..<(startUTF16 + i), kind: runKind))
			}
			runStart = i
			runKind = canvas[i]
		}
		if runKind != .plain {
			tokens.append(HighlightToken(range: (startUTF16 + runStart)..<(startUTF16 + width), kind: runKind))
		}
		return tokens
	}

	// MARK: - Folding

	/// All foldable regions in the document, as line ranges.
	///
	/// Uses the grammar's `folds.scm` when it ships one and otherwise derives
	/// regions structurally from any multi-line node — which covers braces,
	/// brackets and indentation blocks well enough that every language folds,
	/// not just the handful with fold queries.
	/// The file's declarations, nested by containment.
	///
	/// Driven by the grammar's `tags.scm`, which pairs a `@definition.<kind>`
	/// capture covering the whole declaration with a `@name` capture inside it.
	/// Runs over the whole tree rather than a viewport: an outline that only
	/// listed what is on screen would be useless for navigating.
	public func symbols(rope: Rope) -> [DocumentSymbol] {
		guard let tree,
		      let root = tree.rootNode,
		      let query = LanguageRegistry.shared.tagsQuery(for: languageId)
		else { return [] }

		var flat: [DocumentSymbol] = []
		let cursor = query.execute(node: root, in: tree)

		while let match = cursor.next() {
			var definition: (kind: DocumentSymbol.Kind, range: Range<Int>)?
			var name: String?
			var nameRange: Range<Int>?
			var nameNode: Node?

			for capture in match.captures {
				guard let captureName = capture.name, !captureName.isEmpty else { continue }

				// `.byteRange` rather than `.range`: SwiftTreeSitter halves byte
				// offsets assuming UTF-16 input, and we parse UTF-8.
				let bytes = capture.node.byteRange
				let range = Int(bytes.lowerBound)..<Int(bytes.upperBound)

				if captureName == "name" {
					name = rope.string(in: range)
					nameRange = range
					nameNode = capture.node
				} else if let kind = SymbolOutline.kind(forCapture: captureName) {
					definition = (kind, range)
				}
			}

			guard let definition, let name, let nameRange, !name.isEmpty else { continue }

			// A `let` inside a function body is a local, not a member. Grammars
			// capture both the same way, so the tree is what tells them apart —
			// and an outline listing every local is one nobody can read.
			if definition.kind == .property || definition.kind == .constant,
			   let nameNode, isInsideFunctionBody(nameNode) {
				continue
			}

			flat.append(DocumentSymbol(
				name: name,
				kind: definition.kind,
				// The name's line, not the definition's. Several grammars —
				// Swift's among them — hang `@definition.method` on the
				// *enclosing* type, so the definition range starts at the type
				// and every member would report the same line.
				line: rope.line(atByteOffset: nameRange.lowerBound),
				byteRange: definition.range,
				nameRange: nameRange
			))
		}

		return SymbolOutline.nest(flat)
	}

	/// Whether a node sits inside a callable's body rather than a type's.
	///
	/// Walks up until it reaches something that holds declarations: a function
	/// on the way up means the node is a local.
	private func isInsideFunctionBody(_ node: Node) -> Bool {
		var current = node.parent
		while let candidate = current {
			guard let type = candidate.nodeType else {
				current = candidate.parent
				continue
			}

			// Reached a type body first, so it is a member.
			if type.contains("class_body") || type.contains("enum_class_body")
				|| type.contains("protocol_body") || type.contains("struct_type")
				|| type.contains("declaration_list") || type.contains("field_declaration_list") {
				return false
			}
			if type.contains("function") || type.contains("lambda")
				|| type.contains("closure") || type.contains("method") {
				return true
			}
			current = candidate.parent
		}
		return false
	}

	public func foldRanges(rope: Rope) -> [FoldRange] {
		guard let tree, let root = tree.rootNode else { return [] }

		var ranges: [FoldRange] = []
		if let foldQuery {
			let cursor = foldQuery.execute(node: root, in: tree)
			while let match = cursor.next() {
				for capture in match.captures {
					append(node: capture.node, rope: rope, to: &ranges)
				}
			}
		} else {
			collectStructural(node: root, rope: rope, into: &ranges)
		}

		// One fold per start line, preferring the widest, so nested nodes that
		// begin together (`} else {`) do not produce duplicate handles.
		var widest: [Int: FoldRange] = [:]
		for range in ranges {
			if let existing = widest[range.startLine], existing.endLine >= range.endLine { continue }
			widest[range.startLine] = range
		}
		return widest.values.sorted { $0.startLine < $1.startLine }
	}

	private func append(node: Node, rope: Rope, to ranges: inout [FoldRange]) {
		let startLine = rope.line(atByteOffset: Int(node.byteRange.lowerBound))
		let endLine = rope.line(atByteOffset: Int(node.byteRange.upperBound))
		// Only worth folding if it hides at least one line.
		guard endLine > startLine else { return }
		ranges.append(FoldRange(startLine: startLine, endLine: endLine))
	}

	private func collectStructural(node: Node, rope: Rope, into ranges: inout [FoldRange]) {
		let startLine = rope.line(atByteOffset: Int(node.byteRange.lowerBound))
		let endLine = rope.line(atByteOffset: Int(node.byteRange.upperBound))

		if endLine > startLine, node.childCount > 0 {
			ranges.append(FoldRange(startLine: startLine, endLine: endLine))
		}

		// Nodes are ordered, so once a child starts past the end there is nothing
		// left to visit.
		for index in 0..<node.childCount {
			guard let child = node.child(at: index) else { continue }
			collectStructural(node: child, rope: rope, into: &ranges)
		}
	}
}

/// A foldable region, expressed in lines.
///
/// Lines rather than byte offsets because folding is a display concern: the
/// first line stays visible and everything through `endLine` is hidden.
public struct FoldRange: Sendable, Equatable, Hashable {
	public var startLine: Int
	public var endLine: Int

	public init(startLine: Int, endLine: Int) {
		self.startLine = startLine
		self.endLine = endLine
	}

	public var hiddenLineCount: Int { endLine - startLine }
}
