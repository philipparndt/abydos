import Foundation

/// gzip: a ten-byte header, optional fields the flags name, a deflate stream
/// that cannot be measured without inflating it, and an eight-byte trailer.
public enum GzipFormat: BinaryFormat {
	public static let name = "gzip"

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		head.starts(with: [0x1F, 0x8B])
	}

	public static func parse(_ file: StructureBuilder) throws {
		var flags: UInt8 = 0
		try file.group("header") {
			try file.bytes("magic", 2, meaning: "1F 8B")
			let method = try file.u8("method")
			file.note("compression", method == 8 ? "deflate" : "method \(method)")
			flags = try file.u8("flags", style: .hex)
			let time = try file.u32("modification time", .little)
			file.note("modified", time == 0 ? "not recorded" : ByteValues.unixTime(Int64(time)))
			try file.u8("extra flags", meaning: "2 slowest, 4 fastest")
			let os = try file.u8("operating system")
			file.note("made on", ["FAT", "Amiga", "VMS", "Unix", "VM/CMS", "Atari", "HPFS", "Macintosh", "Z-System", "CP/M", "TOPS-20", "NTFS", "QDOS", "RISCOS"][safe: Int(os)] ?? (os == 255 ? "unknown" : "\(os)"))
		}
		if flags & 0x04 != 0 {
			let length = Int(try file.u16("extra length", .little))
			try file.skip("extra", length)
		}
		if flags & 0x08 != 0 { try nulTerminated(file, "original name") }
		if flags & 0x10 != 0 { try nulTerminated(file, "comment") }
		if flags & 0x02 != 0 { try file.u16("header crc-16", .little, style: .hex) }
		guard file.remaining >= 8 else { throw Truncated(offset: file.offset, field: "deflate stream and trailer") }
		try file.skip("deflate stream", file.remaining - 8, meaning: "its length is only known by inflating it")
		try file.group("trailer") {
			try file.u32("crc-32", .little, meaning: "of the uncompressed data", style: .hex)
			try file.u32("uncompressed size", .little, meaning: "modulo 2³²")
		}
	}

	static func nulTerminated(_ file: StructureBuilder, _ name: String) throws {
		var length = 0
		while file.offset + length < file.count, file.snapshot.byte(at: file.offset + length) != 0 { length += 1 }
		guard file.offset + length < file.count else { throw Truncated(offset: file.offset, field: name) }
		try file.string(name, length + 1, encoding: .isoLatin1)
	}
}
