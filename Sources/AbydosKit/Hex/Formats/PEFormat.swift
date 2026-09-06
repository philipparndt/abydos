import Foundation

/// PE: a DOS header pointing at the PE signature, then the COFF header, the
/// optional header and the section table.
public enum PEFormat: BinaryFormat {
	public static let name = "PE"

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		guard head.starts(with: [0x4D, 0x5A]), head.count >= 0x40 else { return false }
		let at = Int(head[0x3C]) | Int(head[0x3D]) << 8 | Int(head[0x3E]) << 16 | Int(head[0x3F]) << 24
		guard at + 4 <= head.count else { return at < 1 << 20 }
		return Array(head[at..<(at + 4)]) == [0x50, 0x45, 0x00, 0x00]
	}

	static let machines: [UInt16: String] = [0x14C: "x86", 0x8664: "x86-64", 0x1C0: "ARM", 0xAA64: "ARM64", 0x200: "IA-64"]
	static let subsystems: [UInt16: String] = [1: "native", 2: "Windows GUI", 3: "Windows console", 9: "Windows CE", 10: "EFI application", 11: "EFI boot driver", 12: "EFI runtime driver", 13: "EFI ROM", 14: "Xbox"]

	public static func parse(_ file: StructureBuilder) throws {
		var peAt = 0
		try file.group("DOS header") {
			try file.string("signature", 2, meaning: "MZ")
			try file.skip("DOS fields", 0x3A)
			peAt = Int(try file.u32("PE header offset", .little, style: .hex))
		}
		if peAt > 0x40 { try file.skip("DOS stub", peAt - 0x40, meaning: "usually 'This program cannot be run in DOS mode'") }
		var sections = 0
		var optionalSize = 0
		try file.group("COFF header", at: peAt) {
			try file.bytes("signature", 4, meaning: "PE\\0\\0")
			let machine = try file.u16("machine", .little, style: .hex)
			file.note("architecture", machines[machine] ?? String(format: "machine 0x%X", machine))
			sections = Int(try file.u16("sections", .little))
			let stamp = try file.u32("timestamp", .little)
			file.note("linked", ByteValues.unixTime(Int64(stamp)))
			try file.u32("symbol table offset", .little, style: .hex)
			try file.u32("symbols", .little)
			optionalSize = Int(try file.u16("optional header size", .little))
			try file.u16("characteristics", .little, meaning: "0x2 executable, 0x2000 DLL", style: .hex)
		}
		if optionalSize > 0 {
			try file.group("optional header", length: optionalSize) {
				let magic = try file.u16("magic", .little, style: .hex)
				let plus = magic == 0x20B
				file.note("format", plus ? "PE32+ (64-bit)" : magic == 0x10B ? "PE32" : "unknown")
				try file.u8("linker major")
				try file.u8("linker minor")
				try file.u32("code size", .little)
				try file.u32("initialised data size", .little)
				try file.u32("uninitialised data size", .little)
				try file.u32("entry point", .little, style: .hex)
				try file.u32("code base", .little, style: .hex)
				if !plus { try file.u32("data base", .little, style: .hex) }
				if plus { try file.u64("image base", .little, style: .hex) } else { try file.u32("image base", .little, style: .hex) }
				try file.u32("section alignment", .little, style: .hex)
				try file.u32("file alignment", .little, style: .hex)
				try file.u16("OS major", .little)
				try file.u16("OS minor", .little)
				try file.u16("image major", .little)
				try file.u16("image minor", .little)
				try file.u16("subsystem major", .little)
				try file.u16("subsystem minor", .little)
				try file.u32("Win32 version", .little)
				try file.u32("image size", .little)
				try file.u32("headers size", .little)
				try file.u32("checksum", .little, style: .hex)
				let subsystem = try file.u16("subsystem", .little)
				file.note("subsystem", subsystems[subsystem] ?? "\(subsystem)")
				try file.u16("DLL characteristics", .little, style: .hex)
				for name in ["stack reserve", "stack commit", "heap reserve", "heap commit"] {
					if plus { try file.u64(name, .little) } else { try file.u32(name, .little) }
				}
				try file.u32("loader flags", .little)
				let directories = Int(try file.u32("data directories", .little))
				let names = ["export", "import", "resource", "exception", "certificate", "base relocation", "debug", "architecture", "global pointer", "TLS", "load config", "bound import", "IAT", "delay import", "CLR runtime", "reserved"]
				try file.repeating(min(directories, 16), of: "data directories") { index in
					try file.group(names[safe: index] ?? "directory \(index)") {
						try file.u32("address", .little, style: .hex)
						try file.u32("size", .little)
					}
				}
			}
		}
		try file.group("section table") {
			try file.repeating(sections, of: "sections") { index in
				guard let nameBytes = file.peek(8) else { throw Truncated(offset: file.offset, field: "section \(index)") }
				try file.group(nameBytes.prefix { $0 != 0 }.asciiTag, length: 40) {
					try file.string("name", 8)
					try file.u32("virtual size", .little)
					try file.u32("virtual address", .little, style: .hex)
					try file.u32("raw size", .little)
					try file.u32("raw offset", .little, style: .hex)
					try file.u32("relocations offset", .little, style: .hex)
					try file.u32("line numbers offset", .little, style: .hex)
					try file.u16("relocations", .little)
					try file.u16("line numbers", .little)
					try file.u32("characteristics", .little, meaning: "0x20 code, 0x40 data, 0x20000000 execute, 0x80000000 write", style: .hex)
				}
			}
		}
	}
}
