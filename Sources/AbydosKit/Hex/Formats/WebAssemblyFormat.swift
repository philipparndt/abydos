import Foundation

/// WebAssembly: a magic, a version, then sections each with an id and a
/// LEB128 length.
public enum WebAssemblyFormat: BinaryFormat {
	public static let name = "WebAssembly"

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		head.starts(with: [0x00, 0x61, 0x73, 0x6D])
	}

	static let sections: [UInt8: String] = [
		0: "custom", 1: "type", 2: "import", 3: "function", 4: "table", 5: "memory", 6: "global",
		7: "export", 8: "start", 9: "element", 10: "code", 11: "data", 12: "data count", 13: "tag",
	]

	public static func parse(_ file: StructureBuilder) throws {
		try file.bytes("magic", 4, meaning: "\\0asm")
		try file.u32("version", .little)
		try file.repeatingWhile("sections", more: { file.remaining > 0 }) { _ in
			let id = file.peek(1)?[0] ?? 0
			try file.group("\(sections[id] ?? "section \(id)") section") {
				try file.u8("id")
				let size = Int(try file.leb128("size"))
				let start = file.offset
				switch id {
				case 0:
					let nameLength = Int(try file.leb128("name length"))
					file.describe(try file.string("name", nameLength, encoding: .utf8))
					try file.skip("contents", max(0, size - (file.offset - start)))
				case 7:
					let count = Int(try file.leb128("exports"))
					try file.repeating(count, of: "exports") { index in
						try file.group("export \(index)") {
							let nameLength = Int(try file.leb128("name length"))
							let name = try file.string("name", nameLength, encoding: .utf8)
							let kind = try file.u8("kind")
							file.describe(name, meaning: ["function", "table", "memory", "global", "tag"][safe: Int(kind)])
							try file.leb128("index")
						}
					}
					if file.offset < start + size { try file.skip("rest", start + size - file.offset) }
				case 1, 2, 3, 4, 5, 6, 9, 10, 11:
					let count = try file.leb128("count")
					file.describe("\(count)")
					try file.skip("entries", max(0, size - (file.offset - start)))
				default:
					try file.skip("contents", size)
				}
			}
		}
	}
}
