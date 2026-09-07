import Foundation

/// What an archive is, decided from its first bytes.
///
/// The name decides only whether *Show Contents* is offered; the bytes decide
/// what is read, so a text file called `x.zip` says it is not an archive
/// rather than showing nothing.
public enum ArchiveKind: String, Sendable, Equatable {
	case zip, tar, tarGzip, gzip

	/// The suffixes the tree offers *Show Contents* on: zips under every name
	/// the hex editor knows, tars, gzipped tars, and a lone gzip.
	public static let offeredSuffixes: [String] = ["zip", "tar", "tgz", "tar.gz", "gz"]
		+ ZIPFormat.knownAs.keys.sorted()

	public static func isOffered(forName name: String) -> Bool {
		let lower = name.lowercased()
		return offeredSuffixes.contains { lower.hasSuffix("." + $0) }
	}

	/// The kind from the first bytes, or nil for something that is not one.
	/// A gzip is a gzipped tar when its name says so; a `.gz` whose name does
	/// not is decided again after inflating, by what came out.
	public static func detect(_ head: Data, name: String) -> ArchiveKind? {
		let bytes = [UInt8](head.prefix(512))
		if bytes.count >= 4, bytes[0] == 0x50, bytes[1] == 0x4B, (bytes[2] == 0x03 && bytes[3] == 0x04) || (bytes[2] == 0x05 && bytes[3] == 0x06) {
			return .zip
		}
		if bytes.count >= 2, bytes[0] == 0x1F, bytes[1] == 0x8B {
			let lower = name.lowercased()
			return lower.hasSuffix(".tgz") || lower.hasSuffix(".tar.gz") ? .tarGzip : .gzip
		}
		if looksLikeTar(head) { return .tar }
		return nil
	}

	/// `ustar` at 257, or a header whose checksum adds up for a tar older
	/// than the magic.
	static func looksLikeTar(_ data: Data) -> Bool {
		guard data.count >= 512 else { return false }
		let bytes = [UInt8](data.prefix(512))
		if Array(bytes[257..<262]) == Array("ustar".utf8) { return true }
		// The checksum field holds the sum of the header with itself as spaces.
		let stored = Int(String(decoding: bytes[148..<156], as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: " \0")), radix: 8) ?? -1
		guard stored >= 0 else { return false }
		var sum = 0
		for (index, byte) in bytes.enumerated() { sum += (148..<156).contains(index) ? 32 : Int(byte) }
		return sum == stored
	}
}
