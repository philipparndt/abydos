import Foundation

/// PNG: an eight-byte signature, then chunks to IEND.
public enum PNGFormat: BinaryFormat {
	public static let name = "PNG"

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		head.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
	}

	static let colourTypes: [UInt8: String] = [
		0: "greyscale", 2: "RGB", 3: "indexed", 4: "greyscale with alpha", 6: "RGBA",
	]

	public static func parse(_ file: StructureBuilder) throws {
		try file.bytes("signature", 8, meaning: "\\x89PNG\\r\\n\\x1A\\n")
		try file.repeatingWhile("chunks", more: { file.remaining > 0 }) { _ in
			guard let type = file.peek(4, at: file.offset + 4)?.asciiTag else {
				throw Truncated(offset: file.offset, field: "chunk type")
			}
			try file.group(type) {
				let length = Int(try file.u32("length", .big))
				try file.bytes("type", 4)
				switch type {
				case "IHDR":
					// Straight under the chunk, so the caret's label reads
					// *IHDR › width* and not *IHDR › data › width*.
					try file.u32("width", .big)
					try file.u32("height", .big)
					try file.u8("bit depth")
					let colour = try file.u8("colour type")
					file.note("colour", colourTypes[colour] ?? "unknown colour type \(colour)")
					try file.u8("compression", meaning: "0 is deflate")
					try file.u8("filter")
					try file.u8("interlace", meaning: "0 none, 1 Adam7")
				case "tEXt":
					try file.group("data", length: length) {
						if let text = file.peek(length), let split = text.firstIndex(of: 0) {
							try file.string("keyword", split - text.startIndex + 1)
							try file.string("text", length - (split - text.startIndex + 1), encoding: .isoLatin1)
						}
					}
				case "pHYs":
					try file.group("data", length: length) {
						try file.u32("pixels per unit, x", .big)
						try file.u32("pixels per unit, y", .big)
						try file.u8("unit", meaning: "1 is the metre")
					}
				default:
					try file.skip("data", length)
				}
				try file.u32("crc", .big, style: .hex)
			}
			if type == "IEND", file.remaining > 0 {
				file.note("\(file.remaining) bytes after IEND", meaning: "a PNG ends at IEND; what follows is not the picture")
				try file.seek(to: file.count, for: "IEND")
			}
		}
	}
}
