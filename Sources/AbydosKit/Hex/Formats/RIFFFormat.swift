import Foundation

/// RIFF: `RIFF`, a size, a form type, then chunks — WAV, AVI and WebP among
/// them. A WAV's `fmt ` chunk is read into its fields.
public enum RIFFFormat: BinaryFormat {
	public static let name = "RIFF"

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		head.starts(with: Array("RIFF".utf8)) && head.count >= 12
	}

	public static func title(for fileExtension: String) -> String { name }

	static let formats: [UInt16: String] = [1: "PCM", 3: "IEEE float", 6: "A-law", 7: "µ-law", 0xFFFE: "extensible"]

	public static func parse(_ file: StructureBuilder) throws {
		var form = ""
		try file.group("RIFF header") {
			try file.string("id", 4)
			try file.u32("size", .little, meaning: "of everything after this field")
			form = try file.string("form", 4)
			file.describe(form)
		}
		try file.repeatingWhile("chunks", more: { file.remaining >= 8 }) { _ in
			guard let id = file.peek(4)?.asciiTag else { return }
			try file.group(id) {
				try file.string("id", 4)
				let size = Int(try file.u32("size", .little))
				switch (form, id) {
				case ("WAVE", "fmt "):
					try file.group("format", length: size) {
						let format = try file.u16("format", .little)
						file.note("encoding", formats[format] ?? "format \(format)")
						try file.u16("channels", .little)
						try file.u32("sample rate", .little)
						try file.u32("byte rate", .little)
						try file.u16("block align", .little)
						try file.u16("bits per sample", .little)
					}
				case ("WAVE", "data"):
					try file.skip("samples", min(size, file.remaining))
				case (_, "LIST"):
					try file.group("list", length: size) {
						file.describe(try file.string("type", 4))
					}
				default:
					try file.skip("data", min(size, file.remaining))
				}
				// Chunks are word aligned; an odd size is followed by a pad byte.
				if size % 2 == 1, file.remaining > 0 { try file.skip("pad", 1) }
			}
		}
	}
}
