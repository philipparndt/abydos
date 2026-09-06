import Foundation

/// Mach-O: a header and its load commands; or a fat header naming the
/// architectures and where each thin Mach-O begins.
public enum MachOFormat: BinaryFormat {
	public static let name = "Mach-O"

	static let thin: [[UInt8]] = [[0xFE, 0xED, 0xFA, 0xCE], [0xCE, 0xFA, 0xED, 0xFE], [0xFE, 0xED, 0xFA, 0xCF], [0xCF, 0xFA, 0xED, 0xFE]]
	static let fat: [[UInt8]] = [[0xCA, 0xFE, 0xBA, 0xBE], [0xCA, 0xFE, 0xBA, 0xBF]]

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		// CA FE BA BE is also a Java class file; the class parser comes later
		// in the list, and a fat header's second word is a count of
		// architectures where a class file's is a version — 45 or more since
		// JDK 1.1. No fat binary has thirty architectures.
		if fat.contains(where: head.starts(with:)) {
			guard head.count >= 8 else { return false }
			let count = UInt32(head[4]) << 24 | UInt32(head[5]) << 16 | UInt32(head[6]) << 8 | UInt32(head[7])
			return count > 0 && count < 30
		}
		return thin.contains(where: head.starts(with:))
	}

	static let cpuTypes: [UInt32: String] = [
		7: "x86", 0x0100_0007: "x86-64", 12: "ARM", 0x0100_000C: "arm64", 0x0200_000C: "arm64_32", 18: "PowerPC", 0x0100_0012: "PowerPC 64",
	]
	static let fileTypes: [UInt32: String] = [
		1: "object", 2: "executable", 3: "fixed VM library", 4: "core", 5: "preloaded executable", 6: "dynamic library",
		7: "dynamic linker", 8: "bundle", 9: "dynamic library stub", 10: "dSYM", 11: "kext bundle",
	]
	static let commands: [UInt32: String] = [
		0x1: "LC_SEGMENT", 0x2: "LC_SYMTAB", 0xB: "LC_DYSYMTAB", 0xC: "LC_LOAD_DYLIB", 0xD: "LC_ID_DYLIB", 0xE: "LC_LOAD_DYLINKER",
		0x19: "LC_SEGMENT_64", 0x1B: "LC_UUID", 0x1D: "LC_CODE_SIGNATURE", 0x24: "LC_VERSION_MIN_MACOSX", 0x26: "LC_FUNCTION_STARTS",
		0x29: "LC_DATA_IN_CODE", 0x2A: "LC_SOURCE_VERSION", 0x32: "LC_BUILD_VERSION", 0x8000_0022: "LC_DYLD_INFO_ONLY", 0x8000_0028: "LC_MAIN",
		0x8000_001C: "LC_RPATH", 0x8000_0033: "LC_DYLD_EXPORTS_TRIE", 0x8000_0034: "LC_DYLD_CHAINED_FIXUPS", 0x8000_0018: "LC_LOAD_WEAK_DYLIB",
	]

	public static func parse(_ file: StructureBuilder) throws {
		guard let magic = file.peek(4) else { throw Truncated(offset: 0, field: "magic") }
		if fat.contains(where: magic.starts(with:)) {
			try parseFat(file, wide: magic[3] == 0xBF)
		} else {
			try parseThin(file, at: 0)
		}
	}

	static func parseFat(_ file: StructureBuilder, wide: Bool) throws {
		var slices: [(offset: Int, name: String)] = []
		try file.group("fat header") {
			try file.bytes("magic", 4, meaning: wide ? "CA FE BA BF, 64-bit offsets" : "CA FE BA BE")
			let count = Int(try file.u32("architectures", .big))
			try file.repeating(count, of: "architectures") { index in
				try file.group("architecture \(index)") {
					let cpu = try file.u32("cpu type", .big, style: .hex)
					let arch = cpuTypes[cpu] ?? String(format: "cpu 0x%X", cpu)
					file.describe(arch)
					try file.u32("cpu subtype", .big, style: .hex)
					let offset = wide ? Int(try file.u64("offset", .big, style: .hex)) : Int(try file.u32("offset", .big, style: .hex))
					if wide { try file.u64("size", .big) } else { try file.u32("size", .big) }
					try file.u32("alignment", .big, meaning: "as a power of two")
					if wide { try file.u32("reserved", .big) }
					slices.append((offset, arch))
				}
			}
		}
		for slice in slices {
			try file.group("\(slice.name) slice", at: slice.offset) {
				try parseThin(file, at: slice.offset)
			}
		}
	}

	static func parseThin(_ file: StructureBuilder, at base: Int) throws {
		guard let magic = file.peek(4, at: base) else { throw Truncated(offset: base, field: "magic") }
		let is64 = magic[0] == 0xCF || magic[3] == 0xCF
		let order: ByteOrder = magic[0] == 0xFE || magic[0] == 0xCA ? .big : .little
		var commandCount = 0
		var commandsSize = 0
		try file.group("header", at: base) {
			try file.bytes("magic", 4, meaning: "\(is64 ? "64" : "32")-bit, \(order.said)")
			let cpu = try file.u32("cpu type", order, style: .hex)
			file.note("architecture", cpuTypes[cpu] ?? String(format: "cpu 0x%X", cpu))
			try file.u32("cpu subtype", order, style: .hex)
			let type = try file.u32("file type", order)
			file.note("kind", fileTypes[type] ?? "type \(type)")
			commandCount = Int(try file.u32("load commands", order))
			commandsSize = Int(try file.u32("load commands size", order))
			try file.u32("flags", order, style: .hex)
			if is64 { try file.u32("reserved", order) }
		}
		try file.group("load commands", length: commandsSize) {
			try file.repeating(commandCount, of: "load commands") { index in
				let start = file.offset
				guard let head = file.peek(8) else { throw Truncated(offset: file.offset, field: "load command \(index)") }
				let code = ELFFormat.integer(head[head.startIndex..<(head.startIndex + 4)], order)
				let size = Int(ELFFormat.integer(head[(head.startIndex + 4)..<(head.startIndex + 8)], order))
				let name = commands[UInt32(code)] ?? String(format: "command 0x%X", code)
				try file.group(name, length: size) {
					try file.u32("command", order, style: .hex)
					try file.u32("size", order)
					switch code {
					case 0x1, 0x19:
						let segment = try file.string("segment name", 16)
						file.describe(segment)
						if is64 {
							try file.u64("vm address", order, style: .hex)
							try file.u64("vm size", order)
							try file.u64("file offset", order, style: .hex)
							try file.u64("file size", order)
						} else {
							try file.u32("vm address", order, style: .hex)
							try file.u32("vm size", order)
							try file.u32("file offset", order, style: .hex)
							try file.u32("file size", order)
						}
						try file.u32("maximum protection", order, style: .hex)
						try file.u32("initial protection", order, style: .hex)
						let sections = Int(try file.u32("sections", order))
						try file.u32("flags", order, style: .hex)
						try file.repeating(sections, of: "sections") { _ in
							let sectionSize = is64 ? 80 : 68
							guard let nameBytes = file.peek(16) else { throw Truncated(offset: file.offset, field: "section") }
							try file.group("section", length: sectionSize) {
								file.describe(nameBytes.prefix { $0 != 0 }.asciiTag)
								try file.string("section name", 16)
								try file.string("segment name", 16)
								if is64 {
									try file.u64("address", order, style: .hex)
									try file.u64("size", order)
								} else {
									try file.u32("address", order, style: .hex)
									try file.u32("size", order)
								}
								try file.u32("offset", order, style: .hex)
								try file.u32("alignment", order, meaning: "as a power of two")
								try file.u32("relocations offset", order, style: .hex)
								try file.u32("relocations", order)
								try file.u32("flags", order, style: .hex)
							}
						}
					case 0xC, 0xD, 0x8000_0018:
						let nameOffset = Int(try file.u32("name offset", order))
						try file.u32("timestamp", order)
						try file.u32("current version", order, style: .hex)
						try file.u32("compatibility version", order, style: .hex)
						if nameOffset >= 24, size > nameOffset {
							file.describe(try file.string("path", size - nameOffset, encoding: .utf8))
						}
					case 0x1B:
						let uuid = try file.bytes("uuid", 16)
						file.describe(uuid.map { String(format: "%02X", $0) }.joined())
					case 0x8000_0028:
						try file.u64("entry offset", order, style: .hex)
						try file.u64("stack size", order)
					case 0x32:
						let platform = try file.u32("platform", order)
						file.describe([1: "macOS", 2: "iOS", 3: "tvOS", 4: "watchOS", 6: "Mac Catalyst", 7: "iOS simulator", 11: "visionOS"][platform] ?? "platform \(platform)")
						let minimum = try file.u32("minimum OS", order, style: .hex)
						file.note("minimum OS", "\(minimum >> 16).\((minimum >> 8) & 0xFF).\(minimum & 0xFF)")
						try file.u32("SDK", order, style: .hex)
						try file.u32("tools", order)
					default:
						if size > 8 { try file.skip("payload", size - 8) }
					}
				}
				if file.offset != start + size { file.offset = start + size }
			}
		}
	}
}
