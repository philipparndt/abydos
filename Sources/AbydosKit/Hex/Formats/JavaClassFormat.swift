import Foundation

/// A Java class file: magic, version, the constant pool, then the class's
/// flags, names, interfaces, fields, methods and attributes.
public enum JavaClassFormat: BinaryFormat {
	public static let name = "Java class"

	public static func recognises(_ head: Data, extension fileExtension: String) -> Bool {
		// CA FE BA BE is also a fat Mach-O; that parser runs first and takes
		// the file only when the next word is a small count, and a class file's
		// next word is a minor and major version — 0 and 45 or more.
		guard head.starts(with: [0xCA, 0xFE, 0xBA, 0xBE]), head.count >= 8 else { return false }
		let major = UInt16(head[6]) << 8 | UInt16(head[7])
		return major >= 45
	}

	static let tags: [UInt8: (String, Int)] = [
		1: ("Utf8", -1), 3: ("Integer", 4), 4: ("Float", 4), 5: ("Long", 8), 6: ("Double", 8),
		7: ("Class", 2), 8: ("String", 2), 9: ("Fieldref", 4), 10: ("Methodref", 4), 11: ("InterfaceMethodref", 4),
		12: ("NameAndType", 4), 15: ("MethodHandle", 3), 16: ("MethodType", 2), 17: ("Dynamic", 4),
		18: ("InvokeDynamic", 4), 19: ("Module", 2), 20: ("Package", 2),
	]

	public static func parse(_ file: StructureBuilder) throws {
		try file.bytes("magic", 4, meaning: "CA FE BA BE")
		try file.u16("minor version", .big)
		let major = try file.u16("major version", .big)
		file.note("Java", major >= 49 ? "\(major - 44)" : "1.\(major - 44)")
		var utf8: [Int: String] = [:]
		var classes: [Int: Int] = [:]
		let poolCount = Int(try file.u16("constant pool count", .big, meaning: "one more than the entries"))
		try file.group("constant pool") {
			var index = 1
			while index < poolCount {
				let tag = file.peek(1)?[0] ?? 0
				let (kind, width) = tags[tag] ?? ("tag \(tag)", 0)
				try file.group("#\(index) \(kind)") {
					try file.u8("tag")
					if tag == 1 {
						let length = Int(try file.u16("length", .big))
						let text = try file.string("bytes", length, encoding: .utf8)
						utf8[index] = text
						file.describe(text)
					} else if tag == 7 {
						classes[index] = Int(try file.u16("name index", .big))
					} else if width > 0 {
						try file.skip("info", width)
					} else if width == 0 {
						throw Malformed(offset: file.offset, said: "unknown constant pool tag \(tag)")
					}
				}
				index += (tag == 5 || tag == 6) ? 2 : 1
			}
		}
		try file.u16("access flags", .big, meaning: "0x1 public, 0x10 final, 0x200 interface, 0x400 abstract", style: .hex)
		let this = Int(try file.u16("this class", .big))
		if let name = classes[this].flatMap({ utf8[$0] }) { file.note("class", name) }
		let superIndex = Int(try file.u16("super class", .big))
		if let name = classes[superIndex].flatMap({ utf8[$0] }) { file.note("extends", name) }
		let interfaces = Int(try file.u16("interfaces count", .big))
		try file.repeating(interfaces, of: "interfaces") { index in
			let classIndex = Int(try file.u16("interface \(index)", .big))
			if let name = classes[classIndex].flatMap({ utf8[$0] }) { file.note("implements", name) }
		}
		for section in ["fields", "methods"] {
			let count = Int(try file.u16("\(section) count", .big))
			try file.group(section) {
				try file.repeating(count, of: section) { index in
					try file.group("\(section.dropLast()) \(index)") {
						try file.u16("access flags", .big, style: .hex)
						let nameIndex = Int(try file.u16("name index", .big))
						let descriptorIndex = Int(try file.u16("descriptor index", .big))
						if let name = utf8[nameIndex] { file.describe(name, meaning: utf8[descriptorIndex]) }
						try attributes(file, utf8)
					}
				}
			}
		}
		try attributes(file, utf8)
	}

	static func attributes(_ file: StructureBuilder, _ utf8: [Int: String]) throws {
		let count = Int(try file.u16("attributes count", .big))
		try file.repeating(count, of: "attributes") { index in
			let nameIndex = Int(file.peek(2).map { UInt16($0[0]) << 8 | UInt16($0[1]) } ?? 0)
			try file.group(utf8[nameIndex] ?? "attribute \(index)") {
				try file.u16("name index", .big)
				let length = Int(try file.u32("length", .big))
				try file.skip("info", length)
			}
		}
	}
}
