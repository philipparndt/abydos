import Foundation

/// SQLite: a hundred-byte header, then pages of the size it names.
public enum SQLiteFormat: BinaryFormat {
	public static let name = "SQLite database"

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		head.starts(with: Array("SQLite format 3\0".utf8))
	}

	public static func parse(_ file: StructureBuilder) throws {
		var pageSize = 0
		var pages = 0
		try file.group("header", length: 100) {
			try file.string("magic", 16)
			let size = Int(try file.u16("page size", .big, meaning: "1 means 65536"))
			pageSize = size == 1 ? 65536 : size
			try file.u8("write version", meaning: "1 legacy, 2 WAL")
			try file.u8("read version", meaning: "1 legacy, 2 WAL")
			try file.u8("reserved bytes per page")
			try file.u8("maximum payload fraction", meaning: "always 64")
			try file.u8("minimum payload fraction", meaning: "always 32")
			try file.u8("leaf payload fraction", meaning: "always 32")
			try file.u32("change counter", .big)
			pages = Int(try file.u32("pages", .big))
			try file.u32("first freelist page", .big)
			try file.u32("freelist pages", .big)
			try file.u32("schema cookie", .big)
			try file.u32("schema format", .big, meaning: "1 to 4")
			try file.u32("default cache size", .big)
			try file.u32("largest root page", .big, meaning: "non-zero with auto-vacuum")
			let encoding = try file.u32("text encoding", .big)
			file.note("text", [1: "UTF-8", 2: "UTF-16 LE", 3: "UTF-16 BE"][encoding] ?? "\(encoding)")
			try file.u32("user version", .big)
			try file.u32("incremental vacuum", .big)
			try file.u32("application id", .big, style: .hex)
			try file.skip("reserved", 20)
			try file.u32("version-valid-for", .big)
			try file.u32("SQLite version", .big, meaning: "as X*1000000 + Y*1000 + Z")
		}
		guard pageSize >= 512 else { throw Malformed(offset: 16, said: "page size \(pageSize) is not one SQLite writes") }
		file.note("layout", "\(pages) pages of \(pageSize) bytes")
		let types: [UInt8: String] = [2: "interior index b-tree", 5: "interior table b-tree", 10: "leaf index b-tree", 13: "leaf table b-tree"]
		try file.repeating(pages, of: "pages", cap: 256) { index in
			let start = index * pageSize
			guard start + pageSize <= file.count else { throw Truncated(offset: start, field: "page \(index + 1)") }
			try file.group("page \(index + 1)", at: start, length: pageSize) {
				if index == 0 { file.offset = 100 }
				let flag = try file.u8("type")
				file.describe(types[flag] ?? (flag == 0 ? "freelist or overflow" : "type \(flag)"))
				try file.u16("first freeblock", .big)
				try file.u16("cells", .big)
				try file.u16("cell content start", .big)
				try file.u8("fragmented free bytes")
				if flag == 2 || flag == 5 { try file.u32("right-most pointer", .big) }
			}
		}
	}
}
