import Foundation

/// JPEG: segments marked FF xx to the start of scan, then entropy-coded data
/// to the end-of-image marker.
public enum JPEGFormat: BinaryFormat {
	public static let name = "JPEG"

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		head.starts(with: [0xFF, 0xD8, 0xFF])
	}

	static let markers: [UInt8: String] = [
		0xC0: "SOF0 baseline frame", 0xC1: "SOF1 extended sequential", 0xC2: "SOF2 progressive frame",
		0xC4: "DHT Huffman table", 0xD8: "SOI start of image", 0xD9: "EOI end of image",
		0xDA: "SOS start of scan", 0xDB: "DQT quantisation table", 0xDD: "DRI restart interval",
		0xE0: "APP0 JFIF", 0xE1: "APP1 Exif or XMP", 0xE2: "APP2 ICC profile", 0xED: "APP13 Photoshop",
		0xEE: "APP14 Adobe", 0xFE: "COM comment",
	]

	public static func parse(_ file: StructureBuilder) throws {
		try file.group("SOI") { try file.bytes("marker", 2, meaning: "start of image") }
		try file.repeatingWhile("segments", more: { file.remaining >= 2 }) { _ in
			guard let head = file.peek(2), head[0] == 0xFF else {
				throw Malformed(offset: file.offset, said: "expected a marker (FF xx)")
			}
			let code = head[1]
			let name = markers[code] ?? String(format: "marker FF%02X", code)
			if code == 0xD9 {
				try file.group("EOI") { try file.bytes("marker", 2, meaning: "end of image") }
				if file.remaining > 0 {
					file.note("\(file.remaining) bytes after EOI", meaning: "not part of the picture")
					try file.seek(to: file.count, for: "EOI")
				}
				return
			}
			try file.group(name) {
				try file.bytes("marker", 2)
				let length = Int(try file.u16("length", .big, meaning: "includes these two bytes"))
				guard length >= 2 else { throw Malformed(offset: file.offset, said: "a segment length under two") }
				switch code {
				case 0xC0, 0xC1, 0xC2:
					try file.group("frame", length: length - 2) {
						try file.u8("precision", meaning: "bits per sample")
						try file.u16("height", .big)
						try file.u16("width", .big)
						let components = try file.u8("components", meaning: "1 greyscale, 3 YCbCr, 4 CMYK")
						try file.repeating(Int(components), of: "components") { index in
							try file.group("component \(index + 1)") {
								try file.u8("id")
								try file.u8("sampling", meaning: "horizontal high nibble, vertical low", style: .hex)
								try file.u8("quantisation table")
							}
						}
					}
				case 0xE0:
					try file.group("JFIF", length: length - 2) {
						try file.string("identifier", 5)
						try file.u8("major version")
						try file.u8("minor version")
						try file.u8("density units", meaning: "0 none, 1 per inch, 2 per cm")
						try file.u16("x density", .big)
						try file.u16("y density", .big)
					}
				case 0xDA:
					try file.skip("scan header", length - 2)
					// Entropy-coded data runs to the next marker that is not a
					// stuffed FF00 or a restart; walking it byte by byte is the
					// only way, and it is the bulk of the file.
					let start = file.offset
					var position = start
					while position + 1 < file.count {
						if file.snapshot.byte(at: position) == 0xFF {
							let next = file.snapshot.byte(at: position + 1)
							if next != 0x00, !(0xD0...0xD7).contains(next) { break }
						}
						position += 1
					}
					try file.skip("entropy-coded data", position - start)
				default:
					try file.skip("data", length - 2)
				}
			}
		}
	}
}
