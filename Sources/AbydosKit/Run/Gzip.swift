import Compression
import Foundation

/// Gzip, both ways.
///
/// Foundation has no gzip and the pod's supervisor speaks it because every
/// HTTP client does; a profile arrives gzipped and a Helm chart is a gzipped
/// tar. Apple's `COMPRESSION_ZLIB` is raw DEFLATE, so the header and the
/// trailer are written and stepped over here — ten bytes and eight, which is
/// less code than taking a dependency for them.
public enum Gzip {
	public enum Failure: Error, Equatable, Sendable {
		case notGzipped
		case corrupt
		/// The stream says it inflates past the cap the caller gave.
		case tooLarge(declared: Int, cap: Int)
	}

	/// Inflates a gzip stream, up to `cap` bytes out.
	///
	/// The header has to be stepped over by hand — including the optional
	/// filename and comment, which Go does not write but other producers do.
	/// The last four bytes are the uncompressed size modulo 2³², which is the
	/// buffer needed with a floor for the rare stream past that.
	public static func inflate(_ data: Data, cap: Int = Int.max) throws -> Data {
		let bytes = [UInt8](data)
		guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else {
			throw Failure.notGzipped
		}

		let flags = bytes[3]
		var start = 10
		if flags & 0x04 != 0 {
			// An extra field, whose own length comes first.
			guard start + 2 <= bytes.count else { throw Failure.corrupt }
			let extra = Int(bytes[start]) | Int(bytes[start + 1]) << 8
			start += 2 + extra
		}
		for flag in [UInt8(0x08), UInt8(0x10)] where flags & flag != 0 {
			// A NUL-terminated name or comment.
			while start < bytes.count, bytes[start] != 0 { start += 1 }
			start += 1
		}
		if flags & 0x02 != 0 { start += 2 }
		guard start < bytes.count - 8 else { throw Failure.corrupt }

		let tail = bytes.count - 4
		let declared = Int(bytes[tail]) | Int(bytes[tail + 1]) << 8
			| Int(bytes[tail + 2]) << 16 | Int(bytes[tail + 3]) << 24
		guard declared <= cap else { throw Failure.tooLarge(declared: declared, cap: cap) }
		let capacity = min(cap, max(declared, (bytes.count - start) * 8, 64 * 1024))

		let inflated = try Deflate.inflate(Data(bytes[start..<(bytes.count - 8)]), capacity: capacity)
		guard inflated.count == declared || declared == 0 else { throw Failure.corrupt }
		return inflated
	}

	/// The name a gzip stream carries in its header, when it carries one.
	public static func storedName(_ data: Data) -> String? {
		let bytes = [UInt8](data.prefix(1024))
		guard bytes.count > 10, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[3] & 0x08 != 0 else { return nil }
		var start = 10
		if bytes[3] & 0x04 != 0, start + 2 <= bytes.count {
			start += 2 + (Int(bytes[start]) | Int(bytes[start + 1]) << 8)
		}
		guard start < bytes.count, let end = bytes[start...].firstIndex(of: 0) else { return nil }
		return String(decoding: bytes[start..<end], as: UTF8.self)
	}

	public static func compress(_ data: Data) -> Data? {
		guard !data.isEmpty else { return nil }

		let capacity = data.count + 64 * 1024
		var deflated = Data(count: capacity)
		let written = deflated.withUnsafeMutableBytes { destination in
			data.withUnsafeBytes { source in
				compression_encode_buffer(
					destination.bindMemory(to: UInt8.self).baseAddress!,
					capacity,
					source.bindMemory(to: UInt8.self).baseAddress!,
					data.count,
					nil,
					COMPRESSION_ZLIB
				)
			}
		}
		guard written > 0 else { return nil }

		var output = Data([0x1F, 0x8B, 0x08, 0, 0, 0, 0, 0, 0, 0x03])
		output.append(deflated.prefix(written))

		var crc = crc32(data).littleEndian
		var size = UInt32(truncatingIfNeeded: data.count).littleEndian
		withUnsafeBytes(of: &crc) { output.append(contentsOf: $0) }
		withUnsafeBytes(of: &size) { output.append(contentsOf: $0) }
		return output
	}

	/// The table-less CRC-32 gzip requires. Slower than a table and run once
	/// per binary, which is nothing beside the compression itself.
	static func crc32(_ data: Data) -> UInt32 {
		var crc: UInt32 = 0xFFFF_FFFF
		for byte in data {
			crc ^= UInt32(byte)
			for _ in 0..<8 {
				crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1)))
			}
		}
		return crc ^ 0xFFFF_FFFF
	}
}

/// Raw DEFLATE, which is what a gzip body and a zip member both are.
public enum Deflate {
	public enum Failure: Error, Equatable, Sendable {
		case corrupt
	}

	/// Inflates into a buffer of `capacity`; a stream that needs more than
	/// that is refused as corrupt, since the caller knows the size it expects.
	public static func inflate(_ compressed: Data, capacity: Int) throws -> Data {
		guard capacity > 0 else { return Data() }
		var output = Data(count: capacity)
		let written = output.withUnsafeMutableBytes { destination -> Int in
			compressed.withUnsafeBytes { source -> Int in
				guard let from = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
				return compression_decode_buffer(
					destination.bindMemory(to: UInt8.self).baseAddress!,
					capacity,
					from,
					compressed.count,
					nil,
					COMPRESSION_ZLIB
				)
			}
		}
		guard written > 0 || compressed.isEmpty else { throw Failure.corrupt }
		return output.prefix(written)
	}
}
