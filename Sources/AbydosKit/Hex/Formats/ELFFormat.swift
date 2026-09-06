import Foundation

/// ELF: the identification bytes say the class and the byte order, the rest
/// of the header says where the program and section headers are.
public enum ELFFormat: BinaryFormat {
	public static let name = "ELF"

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		head.starts(with: [0x7F, 0x45, 0x4C, 0x46])
	}

	static let types: [UInt16: String] = [0: "none", 1: "relocatable", 2: "executable", 3: "shared object", 4: "core"]
	static let machines: [UInt16: String] = [
		0x03: "x86", 0x08: "MIPS", 0x14: "PowerPC", 0x28: "ARM", 0x2A: "SuperH", 0x32: "IA-64",
		0x3E: "x86-64", 0xB7: "AArch64", 0xF3: "RISC-V", 0xF7: "BPF", 0x101: "LoongArch",
	]
	static let sectionTypes: [UInt32: String] = [
		0: "NULL", 1: "PROGBITS", 2: "SYMTAB", 3: "STRTAB", 4: "RELA", 5: "HASH", 6: "DYNAMIC", 7: "NOTE",
		8: "NOBITS", 9: "REL", 11: "DYNSYM", 14: "INIT_ARRAY", 15: "FINI_ARRAY", 0x6FFF_FFF6: "GNU_HASH",
		0x6FFF_FFFE: "GNU_verneed", 0x6FFF_FFFF: "GNU_versym",
	]
	static let segmentTypes: [UInt32: String] = [
		0: "NULL", 1: "LOAD", 2: "DYNAMIC", 3: "INTERP", 4: "NOTE", 6: "PHDR", 7: "TLS",
		0x6474_E550: "GNU_EH_FRAME", 0x6474_E551: "GNU_STACK", 0x6474_E552: "GNU_RELRO",
	]

	public static func parse(_ file: StructureBuilder) throws {
		var is64 = false
		var order = ByteOrder.little
		var sectionsAt = 0, sectionSize = 0, sectionCount = 0, namesIndex = 0
		var programAt = 0, programSize = 0, programCount = 0

		try file.group("header") {
			try file.group("identification") {
				try file.bytes("magic", 4, meaning: "\\x7FELF")
				let cls = try file.u8("class")
				is64 = cls == 2
				file.note("word size", cls == 2 ? "64-bit" : cls == 1 ? "32-bit" : "unknown")
				let data = try file.u8("data")
				order = data == 2 ? .big : .little
				file.note("byte order", order.said)
				try file.u8("version")
				let abi = try file.u8("OS ABI")
				file.note("ABI", [0: "System V", 3: "Linux", 9: "FreeBSD", 12: "OpenBSD"][abi] ?? "\(abi)")
				try file.u8("ABI version")
				try file.skip("padding", 7)
			}
			let type = try file.u16("type", order)
			file.note("kind", types[type] ?? "type \(type)")
			let machine = try file.u16("machine", order)
			file.note("architecture", machines[machine] ?? String(format: "machine 0x%X", machine))
			try file.u32("version", order)
			if is64 {
				try file.u64("entry point", order, style: .hex)
				programAt = Int(try file.u64("program header offset", order, style: .hex))
				sectionsAt = Int(try file.u64("section header offset", order, style: .hex))
			} else {
				try file.u32("entry point", order, style: .hex)
				programAt = Int(try file.u32("program header offset", order, style: .hex))
				sectionsAt = Int(try file.u32("section header offset", order, style: .hex))
			}
			try file.u32("flags", order, style: .hex)
			try file.u16("header size", order)
			programSize = Int(try file.u16("program header entry size", order))
			programCount = Int(try file.u16("program header count", order))
			sectionSize = Int(try file.u16("section header entry size", order))
			sectionCount = Int(try file.u16("section header count", order))
			namesIndex = Int(try file.u16("section name table index", order))
		}

		if programCount > 0, programAt > 0 {
			try file.group("program headers", at: programAt) {
				try file.repeating(programCount, of: "program headers") { index in
					try file.group("segment \(index)", at: programAt + index * programSize, length: programSize) {
						let type = try file.u32("type", order, style: .hex)
						file.describe(segmentTypes[type] ?? String(format: "0x%X", type))
						if is64 {
							try file.u32("flags", order, meaning: "1 execute, 2 write, 4 read", style: .hex)
							try file.u64("offset", order, style: .hex)
							try file.u64("virtual address", order, style: .hex)
							try file.u64("physical address", order, style: .hex)
							try file.u64("file size", order)
							try file.u64("memory size", order)
							try file.u64("alignment", order, style: .hex)
						} else {
							try file.u32("offset", order, style: .hex)
							try file.u32("virtual address", order, style: .hex)
							try file.u32("physical address", order, style: .hex)
							try file.u32("file size", order)
							try file.u32("memory size", order)
							try file.u32("flags", order, style: .hex)
							try file.u32("alignment", order, style: .hex)
						}
					}
				}
			}
		}

		guard sectionCount > 0, sectionsAt > 0 else { return }
		// Names come from the string table the header points at, read first
		// so each section is named rather than numbered.
		var names = Data()
		if namesIndex < sectionCount {
			let at = sectionsAt + namesIndex * sectionSize
			let offsetField = at + (is64 ? 24 : 16)
			if let offsetBytes = file.peek(is64 ? 8 : 4, at: offsetField),
			   let sizeBytes = file.peek(is64 ? 8 : 4, at: offsetField + (is64 ? 8 : 4)) {
				let tableAt = Int(integer(offsetBytes, order))
				let tableSize = Int(integer(sizeBytes, order))
				if let table = file.peek(min(tableSize, 1 << 20), at: tableAt) { names = table }
			}
		}
		try file.group("section headers", at: sectionsAt) {
			try file.repeating(sectionCount, of: "section headers") { index in
				try file.group("section \(index)", at: sectionsAt + index * sectionSize, length: sectionSize) {
					let nameAt = Int(try file.u32("name offset", order))
					let name = string(in: names, at: nameAt)
					let type = try file.u32("type", order, style: .hex)
					file.describe(name.isEmpty ? (sectionTypes[type] ?? "") : name, meaning: sectionTypes[type])
					if is64 {
						try file.u64("flags", order, style: .hex)
						try file.u64("address", order, style: .hex)
						try file.u64("offset", order, style: .hex)
						try file.u64("size", order)
					} else {
						try file.u32("flags", order, style: .hex)
						try file.u32("address", order, style: .hex)
						try file.u32("offset", order, style: .hex)
						try file.u32("size", order)
					}
					try file.u32("link", order)
					try file.u32("info", order)
					if is64 {
						try file.u64("alignment", order)
						try file.u64("entry size", order)
					} else {
						try file.u32("alignment", order)
						try file.u32("entry size", order)
					}
				}
			}
		}
	}

	static func integer(_ data: Data, _ order: ByteOrder) -> UInt64 {
		var value: UInt64 = 0
		for byte in (order == .big ? Array(data) : Array(data).reversed()) { value = value << 8 | UInt64(byte) }
		return value
	}

	static func string(in table: Data, at offset: Int) -> String {
		guard offset >= 0, offset < table.count else { return "" }
		let from = table.startIndex + offset
		let end = table[from...].firstIndex(of: 0) ?? table.endIndex
		return String(decoding: table[from..<end], as: UTF8.self)
	}
}
