import Foundation

/// GIF: header, logical screen, an optional global colour table, then blocks
/// introduced by `,` for an image, `!` for an extension and `;` for the end.
public enum GIFFormat: BinaryFormat {
	public static let name = "GIF"

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		head.starts(with: Array("GIF87a".utf8)) || head.starts(with: Array("GIF89a".utf8))
	}

	public static func parse(_ file: StructureBuilder) throws {
		try file.group("header") {
			try file.string("signature", 3)
			try file.string("version", 3)
		}
		var globalTable = 0
		try file.group("logical screen") {
			try file.u16("width", .little)
			try file.u16("height", .little)
			let packed = try file.u8("packed", style: .hex)
			if packed & 0x80 != 0 {
				globalTable = 3 * (1 << (Int(packed & 0x07) + 1))
				file.note("global colour table", "\(globalTable / 3) colours")
			}
			try file.u8("background colour index")
			try file.u8("pixel aspect ratio")
		}
		if globalTable > 0 { try file.skip("global colour table", globalTable) }

		try file.repeatingWhile("blocks", more: { file.remaining > 0 }) { _ in
			guard let introducer = file.peek(1)?[0] else { return }
			switch introducer {
			case 0x2C:
				try file.group("image") {
					try file.u8("introducer", meaning: "','")
					try file.u16("left", .little)
					try file.u16("top", .little)
					try file.u16("width", .little)
					try file.u16("height", .little)
					let packed = try file.u8("packed", style: .hex)
					if packed & 0x80 != 0 {
						try file.skip("local colour table", 3 * (1 << (Int(packed & 0x07) + 1)))
					}
					try file.u8("LZW minimum code size")
					try subBlocks(file, "image data")
				}
			case 0x21:
				guard let label = file.peek(1, at: file.offset + 1)?[0] else {
					throw Truncated(offset: file.offset, field: "extension label")
				}
				let name: String
				switch label {
				case 0xF9: name = "graphic control extension"
				case 0xFE: name = "comment extension"
				case 0x01: name = "plain text extension"
				case 0xFF: name = "application extension"
				default: name = String(format: "extension 0x%02X", label)
				}
				try file.group(name) {
					try file.u8("introducer", meaning: "'!'")
					try file.u8("label", style: .hex)
					if label == 0xF9 {
						try file.u8("block size")
						let packed = try file.u8("packed", style: .hex)
						file.note("disposal", "\((packed >> 2) & 0x07)", meaning: "0 none, 1 keep, 2 restore background, 3 restore previous")
						try file.u16("delay", .little, meaning: "hundredths of a second")
						try file.u8("transparent colour index")
						try file.u8("terminator")
					} else {
						try subBlocks(file, "data")
					}
				}
			case 0x3B:
				try file.group("trailer") { try file.u8("introducer", meaning: "';'") }
				if file.remaining > 0 {
					file.note("\(file.remaining) bytes after the trailer")
					try file.seek(to: file.count, for: "trailer")
				}
			default:
				throw Malformed(offset: file.offset, said: String(format: "unknown block introducer 0x%02X", introducer))
			}
		}
	}

	/// Length-prefixed sub-blocks to a zero-length one.
	private static func subBlocks(_ file: StructureBuilder, _ name: String) throws {
		let start = file.offset
		var blocks = 0
		while true {
			guard let size = file.peek(1)?[0] else { throw Truncated(offset: file.offset, field: name) }
			guard file.offset + 1 + Int(size) <= file.count else { throw Truncated(offset: file.offset, field: name) }
			file.offset += 1 + Int(size)
			blocks += 1
			if size == 0 { break }
		}
		let end = file.offset
		file.offset = start
		try file.skip(name, end - start, meaning: "\(blocks) sub-blocks")
	}
}
