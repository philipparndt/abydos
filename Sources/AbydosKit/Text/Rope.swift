import Foundation

/// An immutable, persistent rope over UTF-8 bytes.
///
/// Interior nodes sum three metrics — UTF-8 bytes, UTF-16 code units, and
/// newlines — so every conversion the editor needs (byte↔UTF-16↔line) is
/// O(log n) rather than a scan. That is what keeps a keystroke in a 200 MB file
/// as cheap as one in a 2 KB file.
///
/// Persistence matters as much as the balance: because nodes are shared and
/// never mutated, a `Rope` value is a free snapshot. The background syntax parse
/// holds one and reads from it at leisure while the user keeps typing into newer
/// versions, with no locking and no copying.
public struct Rope: Sendable {
	/// Chunk sizing. Leaves stay in this band so that tree depth remains shallow
	/// while a single-character edit never rewrites more than `maxChunk` bytes.
	static let minChunk = 512
	static let targetChunk = 1024
	static let maxChunk = 2048

	indirect enum Node: Sendable {
		case leaf(Leaf)
		case branch(Branch)

		struct Leaf: Sendable {
			var bytes: [UInt8]
			var utf16Count: Int
			var newlines: Int
		}

		struct Branch: Sendable {
			var left: Node
			var right: Node
			var byteCount: Int
			var utf16Count: Int
			var newlines: Int
			var height: Int
		}

		var byteCount: Int {
			switch self {
			case let .leaf(l): return l.bytes.count
			case let .branch(b): return b.byteCount
			}
		}

		var utf16Count: Int {
			switch self {
			case let .leaf(l): return l.utf16Count
			case let .branch(b): return b.utf16Count
			}
		}

		var newlines: Int {
			switch self {
			case let .leaf(l): return l.newlines
			case let .branch(b): return b.newlines
			}
		}

		var height: Int {
			switch self {
			case .leaf: return 0
			case let .branch(b): return b.height
			}
		}

		var isEmpty: Bool { byteCount == 0 }
	}

	var root: Node

	// MARK: - Construction

	public init() {
		root = .leaf(Node.Leaf(bytes: [], utf16Count: 0, newlines: 0))
	}

	public init(_ string: String) {
		self.init(bytes: Array(string.utf8))
	}

	public init(data: Data) {
		self.init(bytes: Array(data))
	}

	init(bytes: [UInt8]) {
		root = Rope.build(bytes: bytes, from: 0, to: bytes.count)
	}

	/// Builds a balanced tree bottom-up by bisecting the byte range, so a large
	/// file loads in one pass with no rebalancing work.
	private static func build(bytes: [UInt8], from lo: Int, to hi: Int) -> Node {
		let length = hi - lo
		if length <= maxChunk {
			return makeLeaf(Array(bytes[lo..<hi]))
		}
		// Bisect on a UTF-8 boundary so no chunk ever splits a codepoint.
		var mid = lo + length / 2
		while mid > lo && isContinuation(bytes[mid]) { mid -= 1 }
		return join(build(bytes: bytes, from: lo, to: mid),
		            build(bytes: bytes, from: mid, to: hi))
	}

	/// True for a UTF-8 continuation byte (`10xxxxxx`), i.e. a position that is
	/// not a character boundary.
	public static func isContinuation(_ byte: UInt8) -> Bool { byte & 0xC0 == 0x80 }

	static func makeLeaf(_ bytes: [UInt8]) -> Node {
		var utf16 = 0
		var newlines = 0
		for b in bytes {
			// Every non-continuation byte starts one codepoint; a 4-byte lead
			// (0xF0…0xF4) becomes a surrogate pair, so it counts twice in UTF-16.
			if !isContinuation(b) {
				utf16 += 1
				if b >= 0xF0 { utf16 += 1 }
			}
			if b == 0x0A { newlines += 1 }
		}
		return .leaf(Node.Leaf(bytes: bytes, utf16Count: utf16, newlines: newlines))
	}

	static func makeBranch(_ l: Node, _ r: Node) -> Node {
		.branch(Node.Branch(
			left: l,
			right: r,
			byteCount: l.byteCount + r.byteCount,
			utf16Count: l.utf16Count + r.utf16Count,
			newlines: l.newlines + r.newlines,
			height: max(l.height, r.height) + 1
		))
	}

	// MARK: - Metrics

	public var byteCount: Int { root.byteCount }
	public var utf16Count: Int { root.utf16Count }
	/// A trailing newline does not open a new line, matching editor convention.
	public var lineCount: Int { root.newlines + 1 }
	public var isEmpty: Bool { root.isEmpty }

	// MARK: - Balancing

	/// AVL join. Descends the taller side so concatenating a small edit onto a
	/// huge rope touches only O(log n) nodes.
	static func join(_ l: Node, _ r: Node) -> Node {
		if l.isEmpty { return r }
		if r.isEmpty { return l }

		// Coalesce small neighbours to stop edits from fragmenting the tree.
		if case let .leaf(a) = l, case let .leaf(b) = r, a.bytes.count + b.bytes.count <= maxChunk {
			return makeLeaf(a.bytes + b.bytes)
		}

		if l.height > r.height + 1 {
			guard case let .branch(b) = l else { return makeBranch(l, r) }
			return balance(makeBranch(b.left, join(b.right, r)))
		}

		if r.height > l.height + 1 {
			guard case let .branch(b) = r else { return makeBranch(l, r) }
			let merged = join(l, b.left)
			return balance(makeBranch(merged, b.right))
		}

		return makeBranch(l, r)
	}

	private static func balance(_ node: Node) -> Node {
		guard case let .branch(b) = node else { return node }
		let diff = b.left.height - b.right.height

		if diff > 1 {
			guard case let .branch(l) = b.left else { return node }
			if l.left.height >= l.right.height {
				// Single right rotation.
				return makeBranch(l.left, makeBranch(l.right, b.right))
			}
			// Left-right: split the inner node, then rotate.
			guard case let .branch(lr) = l.right else { return node }
			return makeBranch(makeBranch(l.left, lr.left), makeBranch(lr.right, b.right))
		}

		if diff < -1 {
			guard case let .branch(r) = b.right else { return node }
			if r.right.height >= r.left.height {
				// Single left rotation.
				return makeBranch(makeBranch(b.left, r.left), r.right)
			}
			// Right-left.
			guard case let .branch(rl) = r.left else { return node }
			return makeBranch(makeBranch(b.left, rl.left), makeBranch(rl.right, r.right))
		}

		return node
	}

	// MARK: - Split

	/// Splits at a byte offset, which must fall on a UTF-8 boundary.
	static func split(_ node: Node, at offset: Int) -> (Node, Node) {
		switch node {
		case let .leaf(l):
			if offset <= 0 { return (makeLeaf([]), node) }
			if offset >= l.bytes.count { return (node, makeLeaf([])) }
			return (makeLeaf(Array(l.bytes[0..<offset])), makeLeaf(Array(l.bytes[offset...])))
		case let .branch(b):
			let leftBytes = b.left.byteCount
			if offset < leftBytes {
				let (a, c) = split(b.left, at: offset)
				return (a, join(c, b.right))
			}
			if offset > leftBytes {
				let (a, c) = split(b.right, at: offset - leftBytes)
				return (join(b.left, a), c)
			}
			return (b.left, b.right)
		}
	}

	// MARK: - Editing

	/// Replaces a byte range with new bytes. Both ends must be UTF-8 boundaries.
	public mutating func replace(byteRange: Range<Int>, with bytes: [UInt8]) {
		let lo = max(0, min(byteRange.lowerBound, byteCount))
		let hi = max(lo, min(byteRange.upperBound, byteCount))

		let (head, rest) = Rope.split(root, at: lo)
		let (_, tail) = Rope.split(rest, at: hi - lo)

		var result = head
		if !bytes.isEmpty {
			result = Rope.join(result, Rope.build(bytes: bytes, from: 0, to: bytes.count))
		}
		root = Rope.join(result, tail)
	}

	public mutating func replace(byteRange: Range<Int>, with string: String) {
		replace(byteRange: byteRange, with: Array(string.utf8))
	}

	// MARK: - Reading

	/// Returns the leaf chunk containing `offset` plus that chunk's start offset.
	///
	/// This is the primitive tree-sitter's read callback wants: hand it a
	/// contiguous run of bytes at a position and it will ask again for the next.
	func chunk(containing offset: Int) -> (bytes: [UInt8], start: Int)? {
		guard offset >= 0 && offset < byteCount else { return nil }
		var node = root
		var base = 0
		while true {
			switch node {
			case let .leaf(l):
				return (l.bytes, base)
			case let .branch(b):
				let leftBytes = b.left.byteCount
				if offset - base < leftBytes {
					node = b.left
				} else {
					base += leftBytes
					node = b.right
				}
			}
		}
	}

	public func bytes(in range: Range<Int>) -> [UInt8] {
		let lo = max(0, min(range.lowerBound, byteCount))
		let hi = max(lo, min(range.upperBound, byteCount))
		guard hi > lo else { return [] }

		var out = [UInt8]()
		out.reserveCapacity(hi - lo)
		var offset = lo
		while offset < hi {
			guard let (chunkBytes, start) = chunk(containing: offset) else { break }
			let localLo = offset - start
			let localHi = min(chunkBytes.count, hi - start)
			out.append(contentsOf: chunkBytes[localLo..<localHi])
			offset = start + localHi
		}
		return out
	}

	public func string(in range: Range<Int>) -> String {
		String(decoding: bytes(in: range), as: UTF8.self)
	}

	public var string: String {
		string(in: 0..<byteCount)
	}

	// MARK: - Line lookup

	/// Byte offset where `line` starts (0-indexed).
	public func byteOffset(ofLine line: Int) -> Int {
		if line <= 0 { return 0 }
		if line > root.newlines { return byteCount }
		return byteOffsetAfterNewline(line - 1)
	}

	/// Byte offset just past the `k`-th newline (0-indexed).
	private func byteOffsetAfterNewline(_ k: Int) -> Int {
		var node = root
		var remaining = k
		var base = 0
		while true {
			switch node {
			case let .leaf(l):
				var seen = 0
				for (i, b) in l.bytes.enumerated() where b == 0x0A {
					if seen == remaining { return base + i + 1 }
					seen += 1
				}
				return base + l.bytes.count
			case let .branch(b):
				if remaining < b.left.newlines {
					node = b.left
				} else {
					remaining -= b.left.newlines
					base += b.left.byteCount
					node = b.right
				}
			}
		}
	}

	/// Line containing a byte offset.
	public func line(atByteOffset offset: Int) -> Int {
		let target = max(0, min(offset, byteCount))
		var node = root
		var remaining = target
		var lines = 0
		while true {
			switch node {
			case let .leaf(l):
				for i in 0..<min(remaining, l.bytes.count) where l.bytes[i] == 0x0A {
					lines += 1
				}
				return lines
			case let .branch(b):
				let leftBytes = b.left.byteCount
				if remaining <= leftBytes {
					node = b.left
				} else {
					lines += b.left.newlines
					remaining -= leftBytes
					node = b.right
				}
			}
		}
	}

	/// Byte range of `line`, excluding its terminating newline.
	public func lineByteRange(_ line: Int) -> Range<Int> {
		let start = byteOffset(ofLine: line)
		guard line < root.newlines else { return start..<byteCount }
		let nextStart = byteOffset(ofLine: line + 1)
		// Trim the line terminator, handling CRLF.
		var end = max(start, nextStart - 1)
		if end > start {
			let bs = bytes(in: (end - 1)..<end)
			if bs.first == 0x0D { end -= 1 }
		}
		return start..<end
	}

	public func lineText(_ line: Int) -> String {
		string(in: lineByteRange(line))
	}

	/// The whole lines a UTF-16 range touches, as a UTF-16 range.
	///
	/// Without the last line's own newline, so replacing what comes back rewrites
	/// those lines rather than joining them to the one after. This is what every
	/// line-wise gesture needs first — ⇥ and ⇧⇥ over a block, ⌘/ over a selection
	/// — and it lived privately inside the code view until there were two of them.
	///
	/// **A range ending exactly at a line's start stops at the line above.**
	/// Dragging the mouse to the beginning of the next line is not selecting that
	/// line, and an editor that thought otherwise indents or comments out one
	/// line too many every single time.
	public func lineSpan(touchingUTF16 range: Range<Int>) -> Range<Int> {
		let firstLine = line(atByteOffset: byteOffset(fromUTF16: range.lowerBound))
		let lastOffset = max(range.lowerBound, range.upperBound - (range.isEmpty ? 0 : 1))
		let lastLine = line(atByteOffset: byteOffset(fromUTF16: lastOffset))

		let start = utf16Offset(fromByte: byteOffset(ofLine: firstLine))
		let end = utf16Offset(fromByte: lineByteRange(lastLine).upperBound)
		return start..<max(start, end)
	}

	// MARK: - UTF-16 conversion

	/// UTF-16 offset ↔ byte offset, both O(log n). AppKit and CoreText speak
	/// UTF-16; tree-sitter and storage speak UTF-8.
	public func byteOffset(fromUTF16 utf16Offset: Int) -> Int {
		let target = max(0, min(utf16Offset, utf16Count))
		var node = root
		var remaining = target
		var bytesSoFar = 0
		while true {
			switch node {
			case let .leaf(l):
				var u = 0
				var i = 0
				while i < l.bytes.count && u < remaining {
					let b = l.bytes[i]
					var width = 1
					if b >= 0xF0 { width = 4 } else if b >= 0xE0 { width = 3 } else if b >= 0xC0 { width = 2 }
					u += (width == 4) ? 2 : 1
					i += width
				}
				return bytesSoFar + i
			case let .branch(b):
				if remaining <= b.left.utf16Count {
					node = b.left
				} else {
					remaining -= b.left.utf16Count
					bytesSoFar += b.left.byteCount
					node = b.right
				}
			}
		}
	}

	public func utf16Offset(fromByte byteOffset: Int) -> Int {
		let target = max(0, min(byteOffset, byteCount))
		var node = root
		var remaining = target
		var utf16SoFar = 0
		while true {
			switch node {
			case let .leaf(l):
				var i = 0
				while i < min(remaining, l.bytes.count) {
					let b = l.bytes[i]
					if !Rope.isContinuation(b) {
						utf16SoFar += 1
						if b >= 0xF0 { utf16SoFar += 1 }
					}
					i += 1
				}
				return utf16SoFar
			case let .branch(b):
				let leftBytes = b.left.byteCount
				if remaining <= leftBytes {
					node = b.left
				} else {
					utf16SoFar += b.left.utf16Count
					remaining -= leftBytes
					node = b.right
				}
			}
		}
	}

	/// Length in bytes of the longest line.
	///
	/// The view needs this to size its horizontal scroll range. It is one linear
	/// pass over the chunks with no per-line lookups, so even a very large file
	/// measures in a few milliseconds on a background queue.
	/// Width of the widest line in display columns.
	///
	/// Byte length is the wrong unit for sizing a scroll range: a tab is one
	/// byte and up to `tabWidth` columns, so a byte count leaves the document
	/// too narrow to scroll to the end of tab-indented code, and a multi-byte
	/// character makes it too wide. Continuation bytes are skipped so one
	/// character counts once.
	public func longestLineDisplayColumns(tabWidth: Int) -> Int {
		let tabWidth = max(1, tabWidth)
		var longest = 0
		var current = 0
		var offset = 0

		while offset < byteCount {
			guard let (chunkBytes, start) = chunk(containing: offset) else { break }
			for byte in chunkBytes[(offset - start)...] {
				switch byte {
				case 0x0A:
					longest = max(longest, current)
					current = 0
				case 0x09:
					current += tabWidth - (current % tabWidth)
				// UTF-8 continuation bytes belong to the character before them.
				case 0x80...0xBF:
					break
				default:
					current += 1
				}
			}
			offset = start + chunkBytes.count
		}
		return max(longest, current)
	}

	public func longestLineByteLength() -> Int {
		var longest = 0
		var current = 0
		var offset = 0
		while offset < byteCount {
			guard let (chunkBytes, start) = chunk(containing: offset) else { break }
			for byte in chunkBytes[(offset - start)...] {
				if byte == 0x0A {
					longest = max(longest, current)
					current = 0
				} else {
					current += 1
				}
			}
			offset = start + chunkBytes.count
		}
		return max(longest, current)
	}

	// MARK: - Boundaries

	/// Nudges an arbitrary byte offset back onto a UTF-8 boundary.
	public func alignToBoundary(_ offset: Int) -> Int {
		var o = max(0, min(offset, byteCount))
		while o > 0 && o < byteCount {
			let b = bytes(in: o..<(o + 1))
			guard let first = b.first, Rope.isContinuation(first) else { break }
			o -= 1
		}
		return o
	}
}

extension Rope: CustomStringConvertible {
	public var description: String { string }
}
