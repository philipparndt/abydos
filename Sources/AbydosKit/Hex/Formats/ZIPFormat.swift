import Foundation

/// ZIP: local file headers with their data, then a central directory, then
/// its end record — which is where a reader that wants the truth starts, and
/// which this walks second so the tree reads in file order.
///
/// A JAR, a 3MF, a DOCX and an APK are ZIPs under other names; the magic says
/// ZIP and the extension says which.
public enum ZIPFormat: BinaryFormat {
	public static let name = "ZIP"

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		head.starts(with: [0x50, 0x4B, 0x03, 0x04]) || head.starts(with: [0x50, 0x4B, 0x05, 0x06])
	}

	static let knownAs: [String: String] = [
		"jar": "JAR", "war": "WAR", "ear": "EAR", "aar": "AAR", "apk": "APK", "ipa": "IPA",
		"3mf": "3MF", "docx": "DOCX", "xlsx": "XLSX", "pptx": "PPTX", "odt": "ODT", "ods": "ODS",
		"epub": "EPUB", "whl": "Python wheel", "nupkg": "NuGet package", "vsix": "VSIX", "xpi": "XPI",
		"kmz": "KMZ", "sketch": "Sketch", "pages": "Pages", "numbers": "Numbers", "key": "Keynote",
	]

	public static func title(for fileExtension: String) -> String {
		knownAs[fileExtension].map { "\($0) (ZIP)" } ?? name
	}

	static let methods: [UInt16: String] = [
		0: "stored", 8: "deflate", 9: "deflate64", 12: "bzip2", 14: "LZMA", 93: "zstd", 95: "xz", 99: "AES",
	]

	public static func parse(_ file: StructureBuilder) throws {
		var entry = 0
		try file.repeatingWhile("entries", more: { file.peek(4)?.starts(with: [0x50, 0x4B, 0x03, 0x04]) == true }) { _ in
			entry += 1
			try file.group("local file header \(entry)") {
				try file.bytes("signature", 4, meaning: "PK\\x03\\x04")
				try file.u16("version needed", .little)
				let flags = try file.u16("flags", .little, style: .hex)
				let method = try file.u16("method", .little)
				file.note("compression", methods[method] ?? "method \(method)")
				try file.u16("modification time", .little, meaning: "MS-DOS time", style: .hex)
				try file.u16("modification date", .little, meaning: "MS-DOS date", style: .hex)
				try file.u32("crc-32", .little, style: .hex)
				let compressed = Int(try file.u32("compressed size", .little))
				try file.u32("uncompressed size", .little)
				let nameLength = Int(try file.u16("name length", .little))
				let extraLength = Int(try file.u16("extra length", .little))
				let name = try file.string("name", nameLength, encoding: .utf8)
				file.describe(name)
				if extraLength > 0 { try file.skip("extra", extraLength) }
				if flags & 0x08 != 0, compressed == 0 {
					// Sizes are in a descriptor after the data, which cannot be
					// found without inflating. The central directory knows.
					file.note("data", "length in the data descriptor after it")
					throw Malformed(offset: file.offset, said: "entry \(entry) uses a data descriptor; the rest is read from the central directory")
				}
				try file.skip("data", compressed)
			}
		}
		try centralDirectory(file)
	}

	static func centralDirectory(_ file: StructureBuilder) throws {
		var index = 0
		try file.repeatingWhile("central directory entries", more: { file.peek(4)?.starts(with: [0x50, 0x4B, 0x01, 0x02]) == true }) { _ in
			index += 1
			try file.group("central directory entry \(index)") {
				try file.bytes("signature", 4, meaning: "PK\\x01\\x02")
				try file.u16("version made by", .little)
				try file.u16("version needed", .little)
				try file.u16("flags", .little, style: .hex)
				let method = try file.u16("method", .little)
				file.note("compression", methods[method] ?? "method \(method)")
				try file.u16("modification time", .little, style: .hex)
				try file.u16("modification date", .little, style: .hex)
				try file.u32("crc-32", .little, style: .hex)
				try file.u32("compressed size", .little)
				try file.u32("uncompressed size", .little)
				let nameLength = Int(try file.u16("name length", .little))
				let extraLength = Int(try file.u16("extra length", .little))
				let commentLength = Int(try file.u16("comment length", .little))
				try file.u16("disk number start", .little)
				try file.u16("internal attributes", .little, style: .hex)
				try file.u32("external attributes", .little, style: .hex)
				try file.u32("local header offset", .little, style: .hex)
				file.describe(try file.string("name", nameLength, encoding: .utf8))
				if extraLength > 0 { try file.skip("extra", extraLength) }
				if commentLength > 0 { try file.string("comment", commentLength, encoding: .utf8) }
			}
		}
		if file.peek(4)?.starts(with: [0x50, 0x4B, 0x05, 0x06]) == true {
			try file.group("end of central directory") {
				try file.bytes("signature", 4, meaning: "PK\\x05\\x06")
				try file.u16("this disk", .little)
				try file.u16("directory disk", .little)
				try file.u16("entries on this disk", .little)
				try file.u16("entries", .little)
				try file.u32("directory size", .little)
				try file.u32("directory offset", .little, style: .hex)
				let commentLength = Int(try file.u16("comment length", .little))
				if commentLength > 0 { try file.string("comment", commentLength, encoding: .utf8) }
			}
		}
		if file.remaining > 0 {
			file.note("\(file.remaining) bytes not part of the archive", meaning: "a ZIP may be preceded or followed by anything; only the directory is authoritative")
		}
	}
}
