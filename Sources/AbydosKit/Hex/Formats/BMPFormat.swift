import Foundation

/// BMP: a file header, a DIB header of one of several sizes, then pixels
/// where the file header says.
public enum BMPFormat: BinaryFormat {
	public static let name = "BMP"

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		head.starts(with: [0x42, 0x4D]) && head.count >= 14
	}

	public static func parse(_ file: StructureBuilder) throws {
		var pixelsAt = 0
		try file.group("file header") {
			try file.string("signature", 2)
			try file.u32("file size", .little)
			try file.u16("reserved", .little)
			try file.u16("reserved", .little)
			pixelsAt = Int(try file.u32("pixel data offset", .little))
		}
		let headerSize = Int(file.peek(4).map { UInt32($0[0]) | UInt32($0[1]) << 8 | UInt32($0[2]) << 16 | UInt32($0[3]) << 24 } ?? 0)
		let kind: String
		switch headerSize {
		case 12: kind = "BITMAPCOREHEADER"
		case 40: kind = "BITMAPINFOHEADER"
		case 52: kind = "BITMAPV2INFOHEADER"
		case 56: kind = "BITMAPV3INFOHEADER"
		case 108: kind = "BITMAPV4HEADER"
		case 124: kind = "BITMAPV5HEADER"
		default: kind = "DIB header"
		}
		try file.group(kind, length: headerSize) {
			try file.u32("header size", .little)
			if headerSize == 12 {
				try file.u16("width", .little)
				try file.u16("height", .little)
				try file.u16("planes", .little)
				try file.u16("bits per pixel", .little)
			} else {
				try file.i32("width", .little)
				try file.i32("height", .little, meaning: "negative is top-down")
				try file.u16("planes", .little)
				try file.u16("bits per pixel", .little)
				let compression = try file.u32("compression", .little)
				file.note("compression", ["BI_RGB", "BI_RLE8", "BI_RLE4", "BI_BITFIELDS", "BI_JPEG", "BI_PNG"][safe: Int(compression)] ?? "\(compression)")
				try file.u32("image size", .little)
				try file.i32("x pixels per metre", .little)
				try file.i32("y pixels per metre", .little)
				try file.u32("colours used", .little)
				try file.u32("important colours", .little)
			}
		}
		if pixelsAt > file.offset {
			try file.skip("colour table and gap", pixelsAt - file.offset)
		}
		if pixelsAt >= file.offset, pixelsAt <= file.count {
			file.offset = pixelsAt
			try file.skip("pixel data", file.remaining)
		} else {
			throw Malformed(offset: 10, said: "pixel data offset 0x\(String(pixelsAt, radix: 16, uppercase: true)) is outside the file")
		}
	}
}

extension Array {
	subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
