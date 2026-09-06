import Foundation

/// One field, section or note in the explanation of a file.
///
/// The one thing the outline, the byte highlighting, the caret's *IHDR ›
/// height* label and Claude's answer all speak. A parser produces them, Claude
/// is asked to answer in them, and `source` says which — so a row Claude
/// contributed is never drawn as parsed fact.
public struct StructureNode: Sendable, Equatable {
	public enum Source: Sendable, Equatable {
		/// Read from the bytes by a parser that knows the format.
		case parsed
		/// Said by Claude about a sample.
		case claude
		/// The parser stopped here and this says why.
		case problem
	}

	public let name: String
	public let range: Range<Int>
	/// The field's value, said: `13`, `0x89504E47`, `IHDR`, `RGBA`.
	public var value: String?
	/// What the value means, when the value alone does not say: `colour type
	/// 6 is RGBA`, `little-endian`.
	public var meaning: String?
	public var children: [StructureNode]
	public let source: Source

	public init(
		name: String,
		range: Range<Int>,
		value: String? = nil,
		meaning: String? = nil,
		children: [StructureNode] = [],
		source: Source = .parsed
	) {
		self.name = name
		self.range = range
		self.value = value
		self.meaning = meaning
		self.children = children
		self.source = source
	}

	/// The chain of nodes from this one down to the innermost that holds
	/// `offset`, for the label above the bytes. Empty when it is outside.
	public func path(at offset: Int) -> [StructureNode] {
		guard range.contains(offset) || (range.isEmpty && range.lowerBound == offset) else { return [] }
		for child in children {
			let below = child.path(at: offset)
			if !below.isEmpty { return [self] + below }
		}
		return [self]
	}

	/// *IHDR › height*, from the path without the root, which is the file.
	public func label(at offset: Int) -> String? {
		let chain = path(at: offset).dropFirst()
		guard !chain.isEmpty else { return nil }
		return chain.map(\.name).joined(separator: " › ")
	}

	/// How many nodes there are, all the way down.
	public var totalCount: Int { 1 + children.reduce(0) { $0 + $1.totalCount } }
}

/// A read that ran off the end of the file.
public struct Truncated: Error, Sendable, Equatable {
	public let offset: Int
	public let field: String
}

/// A file the parser gives up on, with a sentence about where and why.
public struct Malformed: Error, Sendable, Equatable {
	public let offset: Int
	public let said: String

	public init(offset: Int, said: String) {
		self.offset = offset
		self.said = said
	}
}

/// What a parser knows how to explain.
///
/// Swift parsers over a small builder, and the tree is the contract. Not a
/// pattern language: Kaitai needs a compiled parser per format or an
/// interpreter for the whole language, ImHex's patterns need a language
/// implementation, and a YAML of our own would grow one conditional at a
/// time until it was one too. Fourteen parsers are less than any of those.
public protocol BinaryFormat {
	/// The name shown at the root.
	static var name: String { get }
	/// Whether the first bytes are this format. `head` is at most the first
	/// kilobyte, and the extension is for a ZIP under another name.
	static func recognises(_ head: Data, extension fileExtension: String) -> Bool
	/// What to call the root for this file, when the extension changes it:
	/// *JAR (ZIP)*.
	static func title(for fileExtension: String) -> String
	/// Reads the file into the builder. Throws `Truncated` from a read past
	/// the end and `Malformed` when giving up; the registry turns both into a
	/// node saying so where the parser was.
	static func parse(_ file: StructureBuilder) throws
}

public extension BinaryFormat {
	static func title(for fileExtension: String) -> String { name }
}

/// How a number is shown in a node's value.
public enum ValueStyle: Sendable {
	case decimal, hex, both
}

/// The cursor and the tree a parser writes.
///
/// Reads advance the cursor and append a node; `group` nests. A read past the
/// end throws `Truncated`, which the registry catches and turns into a node in
/// the innermost open group — so a ZIP cut off in its third local header
/// yields two entries and *truncated at 0x… in local file header 3*, rather
/// than nothing. `repeating` caps a section at a written count with a node
/// saying how many were not listed, because a two-hundred-thousand-entry
/// archive is a fact about the archive and not a tree anybody reads.
public final class StructureBuilder {
	public let snapshot: ByteDocument.Snapshot
	public var offset: Int = 0
	public var count: Int { snapshot.count }
	public var remaining: Int { max(0, count - offset) }

	/// Open groups, innermost last. The root is the first.
	private var open: [(name: String, start: Int, meaning: String?, children: [StructureNode])]

	/// Past this many repeats of one section, the rest are counted.
	public static let repeatCap = 2000

	public init(snapshot: ByteDocument.Snapshot, root: String, meaning: String? = nil) {
		self.snapshot = snapshot
		open = [(root, 0, meaning, [])]
	}

	// MARK: - Reads

	public func peek(_ length: Int, at position: Int? = nil) -> Data? {
		let start = position ?? offset
		guard start >= 0, start + length <= count else { return nil }
		return snapshot.bytes(in: start..<(start + length))
	}

	private func take(_ length: Int, for field: String) throws -> Data {
		guard let data = peek(length) else { throw Truncated(offset: offset, field: field) }
		offset += length
		return data
	}

	private func number<T: FixedWidthInteger>(_ type: T.Type, _ data: Data, _ order: ByteOrder) -> T {
		var value: T = 0
		for byte in (order == .big ? Array(data) : Array(data).reversed()) {
			value = value << 8 | T(truncatingIfNeeded: byte)
		}
		return value
	}

	private func said<T: FixedWidthInteger>(_ value: T, _ style: ValueStyle) -> String {
		let width = MemoryLayout<T>.size * 2
		switch style {
		case .decimal: return String(value)
		case .hex: return String(format: "0x%0\(width)llX", UInt64(truncatingIfNeeded: value))
		case .both: return "\(value) (0x\(String(UInt64(truncatingIfNeeded: value), radix: 16, uppercase: true)))"
		}
	}

	@discardableResult
	public func u8(_ name: String, meaning: String? = nil, style: ValueStyle = .decimal) throws -> UInt8 {
		let start = offset
		let value = try take(1, for: name)[0]
		append(name, start..<offset, said(value, style), meaning)
		return value
	}

	@discardableResult
	public func u16(_ name: String, _ order: ByteOrder, meaning: String? = nil, style: ValueStyle = .decimal) throws -> UInt16 {
		let start = offset
		let value: UInt16 = number(UInt16.self, try take(2, for: name), order)
		append(name, start..<offset, said(value, style), meaning)
		return value
	}

	@discardableResult
	public func u32(_ name: String, _ order: ByteOrder, meaning: String? = nil, style: ValueStyle = .decimal) throws -> UInt32 {
		let start = offset
		let value: UInt32 = number(UInt32.self, try take(4, for: name), order)
		append(name, start..<offset, said(value, style), meaning)
		return value
	}

	@discardableResult
	public func u64(_ name: String, _ order: ByteOrder, meaning: String? = nil, style: ValueStyle = .decimal) throws -> UInt64 {
		let start = offset
		let value: UInt64 = number(UInt64.self, try take(8, for: name), order)
		append(name, start..<offset, said(value, style), meaning)
		return value
	}

	@discardableResult
	public func i32(_ name: String, _ order: ByteOrder, meaning: String? = nil) throws -> Int32 {
		let start = offset
		let value = Int32(bitPattern: number(UInt32.self, try take(4, for: name), order))
		append(name, start..<offset, String(value), meaning)
		return value
	}

	/// Raw bytes, shown as hex up to sixteen and counted beyond.
	@discardableResult
	public func bytes(_ name: String, _ length: Int, meaning: String? = nil) throws -> Data {
		let start = offset
		let data = try take(length, for: name)
		let shown = length <= 16
			? data.map { String(format: "%02X", $0) }.joined(separator: " ")
			: "\(length) bytes"
		append(name, start..<offset, shown, meaning)
		return data
	}

	/// A fixed-width string, NULs and trailing spaces trimmed.
	@discardableResult
	public func string(_ name: String, _ length: Int, encoding: String.Encoding = .ascii, meaning: String? = nil) throws -> String {
		let start = offset
		let data = try take(length, for: name)
		let cut = data.prefix { $0 != 0 }
		let text = (String(data: cut, encoding: encoding) ?? String(decoding: cut, as: UTF8.self))
			.trimmingCharacters(in: .whitespaces)
		append(name, start..<offset, "“\(text)”", meaning)
		return text
	}

	/// An unsigned LEB128, as WebAssembly writes every count.
	@discardableResult
	public func leb128(_ name: String, meaning: String? = nil) throws -> UInt64 {
		let start = offset
		guard let (value, length) = ByteValues.leb128(at: offset, in: snapshot) else {
			throw Truncated(offset: offset, field: name)
		}
		offset += length
		append(name, start..<offset, String(value), meaning)
		return value
	}

	/// Bytes stepped over and named, without being shown.
	public func skip(_ name: String, _ length: Int, meaning: String? = nil) throws {
		let start = offset
		guard length >= 0, offset + length <= count else { throw Truncated(offset: offset, field: name) }
		offset += length
		append(name, start..<offset, length == 1 ? "1 byte" : "\(length) bytes", meaning)
	}

	public func seek(to position: Int, for field: String) throws {
		guard position >= 0, position <= count else { throw Malformed(offset: offset, said: "\(field) points to 0x\(String(position, radix: 16, uppercase: true)), past the end") }
		offset = position
	}

	// MARK: - Structure

	private func append(_ name: String, _ range: Range<Int>, _ value: String?, _ meaning: String?) {
		open[open.count - 1].children.append(StructureNode(name: name, range: range, value: value, meaning: meaning))
	}

	/// A node with no bytes of its own: a fact the parser worked out.
	public func note(_ name: String, _ value: String? = nil, meaning: String? = nil) {
		append(name, offset..<offset, value, meaning)
	}

	/// The reads inside `body` become children of a node named `name`, whose
	/// range runs from `at` (the cursor by default) to where the cursor ends
	/// up, or `length` bytes when the format says how long the section is.
	public func group(
		_ name: String, at start: Int? = nil, length: Int? = nil, meaning: String? = nil,
		_ body: () throws -> Void
	) throws {
		let from = start ?? offset
		if let start { offset = start }
		open.append((name, from, meaning, []))
		// Not closed on the way out of a throw: the group stays open so the
		// node that says *truncated at 0x… in local file header 3* lands
		// inside local file header 3, and `finish` closes it afterwards.
		try body()
		if let length { offset = min(count, from + length) }
		let closed = open.removeLast()
		let end = length.map { min(count, from + $0) } ?? offset
		open[open.count - 1].children.append(
			StructureNode(name: closed.name, range: from..<max(from, end), meaning: closed.meaning, children: closed.children)
		)
	}

	/// The innermost group's value, for a group that sums up to one thing:
	/// a chunk's type, a section's name.
	public func describe(_ value: String, meaning: String? = nil) {
		// Written onto the group when it closes; kept here meanwhile.
		open[open.count - 1].children.append(StructureNode(name: "", range: offset..<offset, value: value, meaning: meaning))
	}

	/// `total` repeats of a section, the first `cap` of them read and the
	/// rest counted in a node. `each` receives the index from zero.
	public func repeating(
		_ total: Int, of what: String, cap: Int = repeatCap, _ each: (Int) throws -> Void
	) throws {
		for index in 0..<min(total, cap) { try each(index) }
		if total > cap {
			note("\(total - cap) more \(what) not listed", "\(total) in all")
		}
	}

	/// Repeats until `more` says no or the cap is reached, for a format that
	/// does not say how many there are up front.
	public func repeatingWhile(
		_ what: String, cap: Int = repeatCap, more: () -> Bool, _ each: (Int) throws -> Void
	) throws {
		var index = 0
		while more() {
			if index >= cap {
				note("more \(what) not listed", "the first \(cap) are")
				return
			}
			try each(index)
			index += 1
		}
	}

	/// What a read past the end, or a parser giving up, leaves behind.
	func problem(_ said: String, at position: Int) {
		open[open.count - 1].children.append(
			StructureNode(name: said, range: position..<position, source: .problem)
		)
	}

	/// Closes every open group and returns the root.
	public func finish() -> StructureNode {
		while open.count > 1 {
			let closed = open.removeLast()
			open[open.count - 1].children.append(
				StructureNode(name: closed.name, range: closed.start..<max(closed.start, offset), meaning: closed.meaning, children: closed.children)
			)
		}
		let root = open[0]
		return StructureNode(name: root.name, range: 0..<count, meaning: root.meaning, children: Self.lifted(root.children))
	}

	/// The `describe` placeholders become their group's value.
	private static func lifted(_ children: [StructureNode]) -> [StructureNode] {
		children.compactMap { child -> StructureNode? in
			guard !child.name.isEmpty else { return nil }
			var node = child
			if let described = child.children.first(where: { $0.name.isEmpty }) {
				node.value = described.value
				node.meaning = node.meaning ?? described.meaning
			}
			node.children = lifted(child.children)
			return node
		}
	}

	/// The innermost group's name, for the truncation sentence.
	var innermost: String { open.last?.name ?? "" }
}

/// The parsers this app ships, and the door to them.
public enum BinaryFormats {
	public static let all: [any BinaryFormat.Type] = [
		PNGFormat.self, JPEGFormat.self, GIFFormat.self, BMPFormat.self,
		ZIPFormat.self, GzipFormat.self, TarFormat.self,
		ELFFormat.self, MachOFormat.self, PEFormat.self,
		SQLiteFormat.self, RIFFFormat.self, JavaClassFormat.self, WebAssemblyFormat.self,
	]

	/// How much of the head a parser is shown to say whether the file is its.
	public static let headLength = 1024

	public static func recognise(_ snapshot: ByteDocument.Snapshot, extension fileExtension: String) -> (any BinaryFormat.Type)? {
		let head = snapshot.bytes(in: 0..<min(headLength, snapshot.count))
		return all.first { $0.recognises(head, extension: fileExtension.lowercased()) }
	}

	/// The tree, or nil when no parser recognises the file. A parser that
	/// runs off the end or gives up leaves the tree it had and a node that
	/// says where; nothing else it read is lost.
	public static func explain(_ snapshot: ByteDocument.Snapshot, extension fileExtension: String) -> StructureNode? {
		guard let format = recognise(snapshot, extension: fileExtension) else { return nil }
		let builder = StructureBuilder(snapshot: snapshot, root: format.title(for: fileExtension.lowercased()))
		do {
			try format.parse(builder)
		} catch let truncated as Truncated {
			let inside = builder.innermost.isEmpty || builder.innermost == builder.finishRootName
				? "" : " in \(builder.innermost)"
			builder.problem(
				"truncated at 0x\(String(truncated.offset, radix: 16, uppercase: true))\(inside): \(truncated.field) runs past the end",
				at: truncated.offset
			)
		} catch let malformed as Malformed {
			builder.problem(
				"stopped at 0x\(String(malformed.offset, radix: 16, uppercase: true)): \(malformed.said)",
				at: malformed.offset
			)
		} catch {
			builder.problem("stopped: \(error)", at: builder.offset)
		}
		return builder.finish()
	}
}

extension StructureBuilder {
	/// The root's name, so the truncation sentence does not say "in PNG".
	var finishRootName: String { open.first?.name ?? "" }
}

extension Data {
	/// Whether the data begins with these bytes.
	func starts(with bytes: [UInt8]) -> Bool {
		count >= bytes.count && Array(prefix(bytes.count)) == bytes
	}

	/// The bytes as the ASCII they are, for a tag.
	var asciiTag: String {
		String(decoding: map { ($0 >= 0x20 && $0 < 0x7F) ? $0 : 0x2E }, as: UTF8.self)
	}
}
