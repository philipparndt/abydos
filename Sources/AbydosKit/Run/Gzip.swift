import Compression
import Foundation

/// Gzip, for the one place that needs it.
///
/// Foundation has no gzip and the pod's supervisor speaks it because every
/// HTTP client does. Apple's `COMPRESSION_ZLIB` is raw DEFLATE, so the header
/// and the trailer are written here — ten bytes and eight, which is less code
/// than taking a dependency for them.
public enum Gzip {
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
