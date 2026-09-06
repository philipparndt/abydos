import Foundation

/// What is looked for: bytes, and which of them are fixed.
///
/// A hex pattern with `??`, text in an encoding and a number in a width and
/// byte order all lower to this, so the scan knows one shape.
public struct BytePattern: Sendable, Equatable {
	public let bytes: [UInt8]
	/// True where the byte must match; false for a wildcard.
	public let fixed: [Bool]

	public init(bytes: [UInt8], fixed: [Bool]) {
		self.bytes = bytes
		self.fixed = fixed
	}

	public init(_ bytes: [UInt8]) {
		self.init(bytes: bytes, fixed: Array(repeating: true, count: bytes.count))
	}

	public var count: Int { bytes.count }

	/// The first fixed byte, which is what `memchr` runs on.
	var anchor: Int? { fixed.firstIndex(of: true) }

	/// What the person typed, said back, for the bar's placeholder and the
	/// report.
	public var said: String {
		zip(bytes, fixed).map { $1 ? String(format: "%02X", $0) : "??" }.joined(separator: " ")
	}

	/// Why a query could not become a pattern.
	public enum Problem: Error, Equatable, Sendable {
		case empty
		/// A hex string whose digits do not pair up.
		case halfByte(String)
		case notHex(String)
		case notANumber(String)
		case doesNotFit(String, width: Int)
		case notEncodable(String, ByteEncoding)

		public var said: String {
			switch self {
			case .empty: return "Nothing to look for"
			case .halfByte(let text): return "“\(text)” is not whole bytes"
			case .notHex(let text): return "“\(text)” is not hex"
			case .notANumber(let text): return "“\(text)” is not a number"
			case .doesNotFit(let text, let width): return "\(text) does not fit in \(width) bits"
			case .notEncodable(let text, let encoding): return "“\(text)” cannot be written in \(encoding.said)"
			}
		}
	}

	/// `50 4B ?? 04`, with or without spaces, `0x` prefixes or commas.
	public static func hex(_ text: String) -> Result<BytePattern, Problem> {
		var cleaned = text.lowercased()
		for noise in [",", "0x", "\\x"] { cleaned = cleaned.replacingOccurrences(of: noise, with: " ") }
		let digits = cleaned.filter { !$0.isWhitespace }
		guard !digits.isEmpty else { return .failure(.empty) }
		guard digits.count % 2 == 0 else { return .failure(.halfByte(text.trimmingCharacters(in: .whitespaces))) }

		var bytes: [UInt8] = []
		var fixed: [Bool] = []
		var index = digits.startIndex
		while index < digits.endIndex {
			let next = digits.index(index, offsetBy: 2)
			let pair = digits[index..<next]
			if pair == "??" {
				bytes.append(0)
				fixed.append(false)
			} else if let value = UInt8(pair, radix: 16) {
				bytes.append(value)
				fixed.append(true)
			} else {
				return .failure(.notHex(String(pair)))
			}
			index = next
		}
		return .success(BytePattern(bytes: bytes, fixed: fixed))
	}

	public static func text(_ text: String, encoding: ByteEncoding) -> Result<BytePattern, Problem> {
		guard !text.isEmpty else { return .failure(.empty) }
		// Without a byte-order mark: `String.data(using: .utf16LittleEndian)`
		// writes none, and a mark in a search pattern would match nothing.
		guard let data = text.data(using: encoding.stringEncoding), !data.isEmpty else {
			return .failure(.notEncodable(text, encoding))
		}
		return .success(BytePattern(Array(data)))
	}

	/// A number in 8, 16, 32 or 64 bits; hex with `0x`, negative with `-`.
	public static func number(_ text: String, width: Int, order: ByteOrder) -> Result<BytePattern, Problem> {
		let trimmed = text.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return .failure(.empty) }
		let value: Int64?
		if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
			value = Int64(trimmed.dropFirst(2), radix: 16)
		} else {
			value = Int64(trimmed)
		}
		guard var number = value else {
			// A number too large for Int64 is still a number: try it unsigned
			// before saying otherwise.
			if let unsigned = UInt64(trimmed), width == 64 {
				return .success(BytePattern(Array(ByteValues.bytes(of: unsigned, order: order))))
			}
			return .failure(.notANumber(trimmed))
		}
		let bytes: Data
		switch width {
		case 8:
			guard number >= Int64(Int8.min), number <= Int64(UInt8.max) else { return .failure(.doesNotFit(trimmed, width: 8)) }
			bytes = ByteValues.bytes(of: UInt8(truncatingIfNeeded: number), order: order)
		case 16:
			guard number >= Int64(Int16.min), number <= Int64(UInt16.max) else { return .failure(.doesNotFit(trimmed, width: 16)) }
			bytes = ByteValues.bytes(of: UInt16(truncatingIfNeeded: number), order: order)
		case 32:
			guard number >= Int64(Int32.min), number <= Int64(UInt32.max) else { return .failure(.doesNotFit(trimmed, width: 32)) }
			bytes = ByteValues.bytes(of: UInt32(truncatingIfNeeded: number), order: order)
		default:
			if number < 0 { number = Int64(bitPattern: UInt64(bitPattern: number)) }
			bytes = ByteValues.bytes(of: UInt64(bitPattern: number), order: order)
		}
		return .success(BytePattern(Array(bytes)))
	}
}

/// Finding a pattern in a document, in chunks, off the main thread.
///
/// A hex search is asked precisely to find what is *not* on screen, so it is
/// the whole file every time, and the whole file may be a gigabyte. The scan
/// walks the snapshot's runs — slices of the mapping, no copy — and within a
/// run uses `memchr` on the first fixed byte, which is what every fast grep
/// does and is within a small factor of the clever algorithms on real
/// binaries at a tenth of the code. A match that straddles two runs, or two
/// chunks of one, is found by a small window copied across the seam.
///
/// Matches are delivered as they are found, so the count climbs and the
/// minimap fills, and the stream ends when its task is cancelled — by the next
/// keystroke, or the bar closing.
public enum ByteSearch {
	/// A batch of what has been found so far.
	public struct Progress: Sendable, Equatable {
		/// Offsets found since the last batch.
		public let found: [Int]
		/// How far the scan has got, and how far it goes.
		public let scanned: Int
		public let total: Int
		/// True on the last batch.
		public let finished: Bool
		/// True when the scan stopped at `maximumMatches` with more to find.
		public let capped: Bool

		public var fraction: Double { total == 0 ? 1 : Double(scanned) / Double(total) }
	}

	/// Past this the scan stops and says so: a pattern of `??` matches every
	/// offset of a gigabyte, and a list of a billion offsets is not a result.
	public static let maximumMatches = 100_000

	/// How much is scanned between two batches. Four megabytes is a few
	/// milliseconds of `memchr` and a count that visibly climbs.
	public static let chunk = 4 * 1024 * 1024

	/// Every match, synchronously. For tests and for a small file.
	public static func matches(
		of pattern: BytePattern,
		in snapshot: ByteDocument.Snapshot,
		range: Range<Int>? = nil,
		chunk: Int = chunk,
		limit: Int = maximumMatches
	) -> [Int] {
		var out: [Int] = []
		scan(pattern, in: snapshot, range: range ?? 0..<snapshot.count, chunk: chunk, limit: limit) { batch in
			out.append(contentsOf: batch.found)
			return true
		}
		return out
	}

	/// The search as a stream of batches, on a task of its own, cancelled with
	/// the stream.
	public static func search(
		for pattern: BytePattern,
		in snapshot: ByteDocument.Snapshot,
		range: Range<Int>? = nil,
		chunk: Int = chunk
	) -> AsyncStream<Progress> {
		AsyncStream { continuation in
			let task = Task.detached(priority: .userInitiated) {
				scan(pattern, in: snapshot, range: range ?? 0..<snapshot.count, chunk: chunk, limit: maximumMatches) { batch in
					continuation.yield(batch)
					return !Task.isCancelled
				}
				continuation.finish()
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}

	/// The walk. `deliver` returns false to stop.
	static func scan(
		_ pattern: BytePattern,
		in snapshot: ByteDocument.Snapshot,
		range: Range<Int>,
		chunk: Int,
		limit: Int,
		deliver: (Progress) -> Bool
	) {
		let start = max(0, range.lowerBound)
		let end = min(snapshot.count, range.upperBound)
		let total = max(0, end - start)
		guard pattern.count > 0, total >= pattern.count else {
			_ = deliver(Progress(found: [], scanned: total, total: total, finished: true, capped: false))
			return
		}

		var position = start
		var delivered = 0
		var capped = false
		while position < end {
			var run = snapshot.run(at: position)
			if run.isEmpty { break }
			if run.count > chunk { run = run.prefix(chunk) }
			if position + run.count > end { run = run.prefix(end - position) }

			var found: [Int] = []
			run.withUnsafeBytes { buffer in
				find(pattern, in: buffer, base: position, into: &found, limit: limit - delivered)
			}

			// Across the seam: a window of pattern-1 bytes either side, and
			// only matches that begin inside this run count, so nothing is
			// reported twice.
			let seam = position + run.count
			let overlap = pattern.count - 1
			if overlap > 0, seam < end, found.count + delivered < limit {
				let window = snapshot.bytes(in: max(start, seam - overlap)..<min(end, seam + overlap))
				let windowBase = max(start, seam - overlap)
				var across: [Int] = []
				window.withUnsafeBytes { buffer in
					find(pattern, in: buffer, base: windowBase, into: &across, limit: limit)
				}
				// Beginning in *this* run: a match that straddles two seams — an
				// edited byte in its middle — would otherwise be reported at both.
				found.append(contentsOf: across.filter { $0 >= position && $0 < seam && $0 + pattern.count > seam })
			}

			delivered += found.count
			position = seam
			if delivered >= limit {
				capped = true
				_ = deliver(Progress(found: found, scanned: position - start, total: total, finished: true, capped: true))
				return
			}
			guard deliver(Progress(found: found, scanned: position - start, total: total, finished: position >= end, capped: false)) else {
				return
			}
		}
		if position >= end, !capped {
			// The loop delivered `finished` on its last batch; nothing more to say.
			return
		}
	}

	/// Matches within one contiguous buffer.
	static func find(
		_ pattern: BytePattern,
		in buffer: UnsafeRawBufferPointer,
		base: Int,
		into found: inout [Int],
		limit: Int
	) {
		let length = pattern.count
		guard buffer.count >= length, limit > 0, let baseAddress = buffer.baseAddress else { return }
		let bytes = pattern.bytes
		let fixed = pattern.fixed

		guard let anchor = pattern.anchor else {
			// All wildcards: every offset matches, up to the cap.
			for offset in 0...(buffer.count - length) where found.count < limit {
				found.append(base + offset)
			}
			return
		}

		let anchorByte = Int32(bytes[anchor])
		var cursor = anchor
		let last = buffer.count - length + anchor
		while cursor <= last, found.count < limit {
			let remaining = last - cursor + 1
			guard let hit = memchr(baseAddress + cursor, anchorByte, remaining) else { return }
			let at = baseAddress.distance(to: UnsafeRawPointer(hit)) - anchor
			var matched = true
			for index in 0..<length where fixed[index] {
				if buffer[at + index] != bytes[index] {
					matched = false
					break
				}
			}
			if matched { found.append(base + at) }
			cursor = at + anchor + 1
		}
	}
}
