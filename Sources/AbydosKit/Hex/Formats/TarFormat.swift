import Foundation

/// tar: 512-byte headers, each followed by the file's data rounded up to a
/// block, ending in two zero blocks.
public enum TarFormat: BinaryFormat {
	public static let name = "tar"

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		guard head.count >= 512 else { return false }
		let magic = head[257..<262]
		return Array(magic) == Array("ustar".utf8)
	}

	static let kinds: [UInt8: String] = [
		0x30: "regular file", 0x00: "regular file", 0x31: "hard link", 0x32: "symbolic link",
		0x33: "character device", 0x34: "block device", 0x35: "directory", 0x36: "FIFO",
		0x4C: "GNU long name", 0x78: "pax extended header", 0x67: "pax global header",
	]

	public static func parse(_ file: StructureBuilder) throws {
		var entry = 0
		try file.repeatingWhile("entries", more: {
			guard let block = file.peek(512) else { return false }
			return block.contains { $0 != 0 }
		}) { _ in
			entry += 1
			var size = 0
			var name = ""
			try file.group("entry \(entry)") {
				try file.group("header", length: 512) {
					name = try file.string("name", 100)
					try file.string("mode", 8, meaning: "octal")
					try file.string("owner id", 8, meaning: "octal")
					try file.string("group id", 8, meaning: "octal")
					let sizeText = try file.string("size", 12, meaning: "octal")
					size = Int(sizeText.trimmingCharacters(in: .whitespacesAndNewlines), radix: 8) ?? 0
					let time = try file.string("modification time", 12, meaning: "octal seconds since 1970")
					if let seconds = Int64(time.trimmingCharacters(in: .whitespacesAndNewlines), radix: 8) {
						file.note("modified", ByteValues.unixTime(seconds))
					}
					try file.string("checksum", 8)
					let kind = try file.u8("type flag")
					file.note("kind", kinds[kind] ?? "type '\(Character(UnicodeScalar(kind)))'")
					try file.string("link name", 100)
					try file.string("magic", 6)
					try file.string("version", 2)
					try file.string("owner", 32)
					try file.string("group", 32)
					try file.string("device major", 8)
					try file.string("device minor", 8)
					let prefix = try file.string("prefix", 155)
					if !prefix.isEmpty { name = prefix + "/" + name }
				}
				file.describe(name, meaning: "\(size) bytes")
				let padded = (size + 511) / 512 * 512
				if padded > 0 { try file.skip("data", padded, meaning: "\(size) bytes, padded to a block") }
			}
		}
		if file.remaining > 0 {
			try file.skip("end of archive", file.remaining, meaning: "zero blocks")
		}
	}
}
