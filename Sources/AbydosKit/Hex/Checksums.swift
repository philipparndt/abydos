import CryptoKit
import Foundation

/// A digest of the file or of a selection, streamed, only when asked.
///
/// Nothing hashes on open: six passes over a large file before anybody has
/// asked a question is six passes wasted, and a SHA-256 of a gigabyte after
/// every keystroke is a second of work per nibble. Each is a button, each
/// walks the snapshot's runs — the mapping's pages, never a copy — and each
/// stops when its task is cancelled. CRC-32 and Adler-32 are written here
/// because they are a table and a loop; the rest are CryptoKit's.
public enum Checksum: String, CaseIterable, Sendable {
	case crc32, adler32, md5, sha1, sha256, sha512

	public var name: String {
		switch self {
		case .crc32: return "CRC-32"
		case .adler32: return "Adler-32"
		case .md5: return "MD5"
		case .sha1: return "SHA-1"
		case .sha256: return "SHA-256"
		case .sha512: return "SHA-512"
		}
	}
}

public enum Checksums {
	public struct Progress: Sendable, Equatable {
		public let done: Int
		public let total: Int
		/// The hex digest, on the last batch.
		public let result: String?

		public var fraction: Double { total == 0 ? 1 : Double(done) / Double(total) }
	}

	/// Progress is reported this often; a hash of a gigabyte then reports a
	/// few hundred times, enough for a bar and too few to cost anything.
	static let reportEvery = 4 * 1024 * 1024

	/// The digest, or nil when cancelled before the end.
	public static func compute(
		_ kind: Checksum,
		over snapshot: ByteDocument.Snapshot,
		range: Range<Int>? = nil,
		isCancelled: () -> Bool = { Task.isCancelled },
		progress: ((Int, Int) -> Void)? = nil
	) -> String? {
		let span = range ?? 0..<snapshot.count
		let total = max(0, span.upperBound - span.lowerBound)
		var done = 0
		var sinceReport = 0
		var stopped = false

		func feed(_ update: (Data) -> Void) {
			snapshot.forEachRun(in: span) { _, run in
				if isCancelled() {
					stopped = true
					return false
				}
				update(run)
				done += run.count
				sinceReport += run.count
				if sinceReport >= reportEvery {
					sinceReport = 0
					progress?(done, total)
				}
				return true
			}
		}

		let digest: String
		switch kind {
		case .crc32:
			var state: UInt32 = 0xFFFF_FFFF
			feed { run in run.withUnsafeBytes { crc32(&state, $0) } }
			digest = String(format: "%08x", state ^ 0xFFFF_FFFF)
		case .adler32:
			var a: UInt32 = 1, b: UInt32 = 0
			feed { run in run.withUnsafeBytes { adler32(&a, &b, $0) } }
			digest = String(format: "%08x", b << 16 | a)
		case .md5: digest = hashed(Insecure.MD5.self, feed)
		case .sha1: digest = hashed(Insecure.SHA1.self, feed)
		case .sha256: digest = hashed(SHA256.self, feed)
		case .sha512: digest = hashed(SHA512.self, feed)
		}
		guard !stopped else { return nil }
		progress?(total, total)
		return digest
	}

	/// The same as a stream of progress ending in the digest, on a task of
	/// its own that the stream's end cancels.
	public static func stream(
		_ kind: Checksum,
		over snapshot: ByteDocument.Snapshot,
		range: Range<Int>? = nil
	) -> AsyncStream<Progress> {
		AsyncStream { continuation in
			let task = Task.detached(priority: .userInitiated) {
				let result = compute(kind, over: snapshot, range: range, progress: { done, total in
					continuation.yield(Progress(done: done, total: total, result: nil))
				})
				if let result {
					let total = (range ?? 0..<snapshot.count).count
					continuation.yield(Progress(done: total, total: total, result: result))
				}
				continuation.finish()
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}

	private static func hashed<H: HashFunction>(_ type: H.Type, _ feed: ((Data) -> Void) -> Void) -> String {
		var hasher = H()
		feed { run in hasher.update(data: run) }
		return hasher.finalize().map { String(format: "%02x", $0) }.joined()
	}

	// MARK: - The two that are a table and a loop

	private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
		var value = UInt32(index)
		for _ in 0..<8 {
			value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
		}
		return value
	}

	static func crc32(_ state: inout UInt32, _ bytes: UnsafeRawBufferPointer) {
		var crc = state
		for byte in bytes {
			crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
		}
		state = crc
	}

	/// The largest prime under 2¹⁶, and the number of bytes the sums can
	/// take before they must be reduced to stay in 32 bits.
	private static let adlerModulus: UInt32 = 65521
	private static let adlerStride = 5552

	static func adler32(_ a: inout UInt32, _ b: inout UInt32, _ bytes: UnsafeRawBufferPointer) {
		var index = 0
		while index < bytes.count {
			let end = min(bytes.count, index + adlerStride)
			while index < end {
				a += UInt32(bytes[index])
				b += a
				index += 1
			}
			a %= adlerModulus
			b %= adlerModulus
		}
	}
}
