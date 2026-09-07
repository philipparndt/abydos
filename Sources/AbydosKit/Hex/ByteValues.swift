import Foundation

/// Which end of a number comes first.
public enum ByteOrder: String, CaseIterable, Sendable {
	case little, big

	public var said: String { self == .little ? "little-endian" : "big-endian" }
}

/// How the text column reads its bytes.
public enum ByteEncoding: String, CaseIterable, Sendable {
	case ascii, latin1, utf8, utf16LittleEndian, utf16BigEndian

	public var said: String {
		switch self {
		case .ascii: return "ASCII"
		case .latin1: return "Latin-1"
		case .utf8: return "UTF-8"
		case .utf16LittleEndian: return "UTF-16 LE"
		case .utf16BigEndian: return "UTF-16 BE"
		}
	}

	public var stringEncoding: String.Encoding {
		switch self {
		case .ascii: return .ascii
		case .latin1: return .isoLatin1
		case .utf8: return .utf8
		case .utf16LittleEndian: return .utf16LittleEndian
		case .utf16BigEndian: return .utf16BigEndian
		}
	}

	/// Whether a single byte is a character somebody can read on its own.
	public func isPrintable(_ byte: UInt8) -> Bool {
		switch self {
		case .latin1: return (byte >= 0x20 && byte < 0x7F) || byte >= 0xA0
		default: return byte >= 0x20 && byte < 0x7F
		}
	}

	/// How loudly a byte's *hex* is drawn — the hex column's three shades.
	///
	/// Here rather than beside the drawing because it is a question about a
	/// byte and an encoding and not about a font, which makes it a claim
	/// somebody can check without a window. `HexEditorView.drawHex` turns each
	/// case into a colour and does nothing else with it.
	///
	/// **The same predicate the text column uses**, so the two columns cannot
	/// disagree: a byte drawn as a dot over there is a quiet pair of digits
	/// over here, and changing `isPrintable` moves both at once. That is the
	/// whole reason this is one function rather than a second rule written out
	/// beside the hex.
	public func shade(of byte: UInt8) -> HexShade {
		if byte == 0 { return .empty }
		return isPrintable(byte) ? .text : .quiet
	}

	/// The character that begins at `offset`, and how many bytes it took —
	/// or nil where the bytes there are not one. For the text column, which
	/// draws a dot in that case, and for the inspector, which says so.
	public func character(at offset: Int, in snapshot: ByteDocument.Snapshot) -> (String, Int)? {
		guard offset >= 0, offset < snapshot.count else { return nil }
		switch self {
		case .ascii, .latin1:
			let byte = snapshot.byte(at: offset)
			guard isPrintable(byte), let text = String(data: Data([byte]), encoding: stringEncoding) else {
				return nil
			}
			return (text, 1)
		case .utf8:
			let lead = snapshot.byte(at: offset)
			let length: Int
			switch lead {
			case 0x20..<0x7F: return (String(UnicodeScalar(lead)), 1)
			case 0xC2...0xDF: length = 2
			case 0xE0...0xEF: length = 3
			case 0xF0...0xF4: length = 4
			default: return nil
			}
			guard offset + length <= snapshot.count else { return nil }
			let bytes = snapshot.bytes(in: offset..<(offset + length))
			guard let text = String(data: bytes, encoding: .utf8), text.unicodeScalars.count == 1,
				  let scalar = text.unicodeScalars.first, scalar.properties.isGraphemeBase || scalar.properties.isEmoji
			else { return nil }
			return (text, length)
		case .utf16LittleEndian, .utf16BigEndian:
			guard offset + 2 <= snapshot.count else { return nil }
			let pair = snapshot.bytes(in: offset..<(offset + 2))
			let unit = self == .utf16LittleEndian
				? UInt16(pair[pair.startIndex]) | UInt16(pair[pair.startIndex + 1]) << 8
				: UInt16(pair[pair.startIndex]) << 8 | UInt16(pair[pair.startIndex + 1])
			guard unit >= 0x20, unit != 0x7F, let scalar = UnicodeScalar(unit) else { return nil }
			return (String(scalar), 2)
		}
	}
}

/// Which of three shades a byte's hex digits are drawn in.
///
/// Three rather than two because zero was already dimmed before there was any
/// notion of "printable", and for a good reason: a run of zeros is padding or
/// a hole, and seeing it as one block is most of what reading a binary is. A
/// zero is also unprintable, so without a case of its own it would have been
/// promoted to the middle shade and that structure would have flattened.
public enum HexShade: Equatable, Sendable {
	/// A byte that is a character in this encoding.
	case text
	/// A byte that is not — a control byte, or one that no character starts
	/// at in this encoding.
	case quiet
	/// Zero, quieter than either.
	case empty
}

/// What the bytes at the caret are, read every way the inspector shows.
///
/// Pure functions over a snapshot, so the pane draws what these say and a test
/// asks them without a pane. Every reading is `nil` where fewer bytes remain
/// than it needs: the last byte of a file has an 8-bit value and no 16-bit
/// one, and a reading that quietly used zeros past the end would say `256`
/// about a file that ends in `00 01`.
public enum ByteValues {
	/// One row of the inspector.
	public enum Field: String, CaseIterable, Sendable {
		case int8, uint8, int16, uint16, int32, uint32, int64, uint64
		case float32, float64
		case character
		case unixTime32, unixTime64
		case leb128
		case binary

		public var name: String {
			switch self {
			case .int8: return "Int8"
			case .uint8: return "UInt8"
			case .int16: return "Int16"
			case .uint16: return "UInt16"
			case .int32: return "Int32"
			case .uint32: return "UInt32"
			case .int64: return "Int64"
			case .uint64: return "UInt64"
			case .float32: return "Float32"
			case .float64: return "Float64"
			case .character: return "Character"
			case .unixTime32: return "Unix time (32-bit)"
			case .unixTime64: return "Unix time (64-bit)"
			case .leb128: return "LEB128"
			case .binary: return "Binary"
			}
		}

		/// Which band of the inspector's list this belongs in.
		///
		/// The cases are declared `int8, uint8, int16, uint16 …`, which is the
		/// order somebody *writing* them thinks in and not the order somebody
		/// reading the pane does: signed and unsigned alternate, so finding
		/// UInt32 means reading every label on the way down. Neither the names
		/// nor the numbers give the eye anything to skip by. Four bands do.
		public enum Group: String, CaseIterable, Sendable {
			case signed, unsigned, floating, interpreted

			public var name: String {
				switch self {
				case .signed: return "Signed"
				case .unsigned: return "Unsigned"
				case .floating: return "Floating point"
				case .interpreted: return "Interpreted"
				}
			}
		}

		public var group: Group {
			switch self {
			case .int8, .int16, .int32, .int64: return .signed
			case .uint8, .uint16, .uint32, .uint64: return .unsigned
			case .float32, .float64: return .floating
			case .character, .unixTime32, .unixTime64, .leb128, .binary: return .interpreted
			}
		}

		/// The fields by band, each keeping the order they are declared in —
		/// which inside a band is narrowest first.
		public static var grouped: [(group: Group, fields: [Field])] {
			Group.allCases.compactMap { group in
				let fields = allCases.filter { $0.group == group }
				return fields.isEmpty ? nil : (group, fields)
			}
		}

		/// Bytes the reading needs, or nil where it depends on the bytes.
		public var width: Int? {
			switch self {
			case .int8, .uint8, .binary: return 1
			case .int16, .uint16: return 2
			case .int32, .uint32, .float32, .unixTime32: return 4
			case .int64, .uint64, .float64, .unixTime64: return 8
			case .character, .leb128: return nil
			}
		}

		/// Whether a value typed into the row can be written back as bytes.
		public var isEditable: Bool {
			switch self {
			case .character, .leb128, .binary, .unixTime32, .unixTime64: return false
			default: return true
			}
		}
	}

	/// A field's reading at an offset.
	public struct Reading: Sendable, Equatable {
		public let field: Field
		/// The value, or nil when the bytes there do not make one.
		public let text: String?
		/// How many bytes it covers, so the field's bytes can be highlighted.
		public let length: Int

		/// What the row says in place of a value.
		public var unavailable: String {
			if let width = field.width { return "needs \(width) bytes" }
			return "not one here"
		}
	}

	public static func readings(
		at offset: Int,
		in snapshot: ByteDocument.Snapshot,
		order: ByteOrder,
		encoding: ByteEncoding
	) -> [Reading] {
		Field.allCases.map { reading($0, at: offset, in: snapshot, order: order, encoding: encoding) }
	}

	public static func reading(
		_ field: Field,
		at offset: Int,
		in snapshot: ByteDocument.Snapshot,
		order: ByteOrder,
		encoding: ByteEncoding
	) -> Reading {
		func made(_ text: String?, _ length: Int) -> Reading {
			Reading(field: field, text: text, length: text == nil ? 0 : length)
		}
		switch field {
		case .int8: return made(integer(Int8.self, at: offset, in: snapshot, order: order).map(String.init), 1)
		case .uint8: return made(integer(UInt8.self, at: offset, in: snapshot, order: order).map(String.init), 1)
		case .int16: return made(integer(Int16.self, at: offset, in: snapshot, order: order).map(String.init), 2)
		case .uint16: return made(integer(UInt16.self, at: offset, in: snapshot, order: order).map(String.init), 2)
		case .int32: return made(integer(Int32.self, at: offset, in: snapshot, order: order).map(String.init), 4)
		case .uint32: return made(integer(UInt32.self, at: offset, in: snapshot, order: order).map(String.init), 4)
		case .int64: return made(integer(Int64.self, at: offset, in: snapshot, order: order).map(String.init), 8)
		case .uint64: return made(integer(UInt64.self, at: offset, in: snapshot, order: order).map(String.init), 8)
		case .float32:
			return made(integer(UInt32.self, at: offset, in: snapshot, order: order)
				.map { said(Float(bitPattern: $0)) }, 4)
		case .float64:
			return made(integer(UInt64.self, at: offset, in: snapshot, order: order)
				.map { said(Double(bitPattern: $0)) }, 8)
		case .character:
			guard let (text, length) = encoding.character(at: offset, in: snapshot) else { return made(nil, 0) }
			return made(text, length)
		case .unixTime32:
			return made(integer(Int32.self, at: offset, in: snapshot, order: order)
				.map { unixTime(Int64($0)) }, 4)
		case .unixTime64:
			return made(integer(Int64.self, at: offset, in: snapshot, order: order).map(unixTime), 8)
		case .leb128:
			guard let (value, length) = leb128(at: offset, in: snapshot) else { return made(nil, 0) }
			return made(String(value), length)
		case .binary:
			guard offset >= 0, offset < snapshot.count else { return made(nil, 0) }
			let byte = snapshot.byte(at: offset)
			let bits = String(byte, radix: 2)
			return made(String(repeating: "0", count: 8 - bits.count) + bits, 1)
		}
	}

	// MARK: - The readings themselves

	public static func integer<T: FixedWidthInteger>(
		_ type: T.Type, at offset: Int, in snapshot: ByteDocument.Snapshot, order: ByteOrder
	) -> T? {
		let width = MemoryLayout<T>.size
		guard offset >= 0, offset + width <= snapshot.count else { return nil }
		let bytes = snapshot.bytes(in: offset..<(offset + width))
		var value: T = 0
		for byte in (order == .big ? Array(bytes) : Array(bytes).reversed()) {
			value = value << 8 | T(truncatingIfNeeded: byte)
		}
		return value
	}

	/// An unsigned LEB128 that ends within ten bytes, as WebAssembly and DWARF
	/// write them, and how long it was.
	public static func leb128(at offset: Int, in snapshot: ByteDocument.Snapshot) -> (UInt64, Int)? {
		guard offset >= 0, offset < snapshot.count else { return nil }
		var value: UInt64 = 0
		var shift: UInt64 = 0
		var length = 0
		while offset + length < snapshot.count, length < 10 {
			let byte = snapshot.byte(at: offset + length)
			length += 1
			value |= UInt64(byte & 0x7F) << shift
			if byte & 0x80 == 0 { return (value, length) }
			shift += 7
		}
		return nil
	}

	/// A time in UTC, or a sentence for a number that is not one.
	public static func unixTime(_ seconds: Int64) -> String {
		// Between the years 1 and 9999; outside that a date formatter answers
		// with something that is not a date and looks like one.
		guard seconds > -62_135_596_800, seconds < 253_402_300_800 else { return "not a time" }
		let date = Date(timeIntervalSince1970: TimeInterval(seconds))
		return timeFormatter.string(from: date)
	}

	private static let timeFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(identifier: "UTC")
		formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
		return formatter
	}()

	/// Shortest text that reads back as the same number, which is what
	/// `description` gives. Not through `Double`: a `Float` 0.1 widened is
	/// 0.10000000149011612, and `%f` would print it as 0.100000.
	static func said<T: BinaryFloatingPoint & CustomStringConvertible>(_ value: T) -> String {
		if value.isNaN { return "NaN" }
		if value.isInfinite { return value < 0 ? "-∞" : "∞" }
		return value.description
	}

	// MARK: - Writing back

	/// The bytes a value typed into a field becomes, or nil with a sentence
	/// when the text is not one the field can hold.
	public static func encode(
		_ text: String, as field: Field, order: ByteOrder
	) -> Result<Data, EncodeProblem> {
		let trimmed = text.trimmingCharacters(in: .whitespaces)
		switch field {
		case .int8: return integerBytes(Int8.self, trimmed, order)
		case .uint8: return integerBytes(UInt8.self, trimmed, order)
		case .int16: return integerBytes(Int16.self, trimmed, order)
		case .uint16: return integerBytes(UInt16.self, trimmed, order)
		case .int32: return integerBytes(Int32.self, trimmed, order)
		case .uint32: return integerBytes(UInt32.self, trimmed, order)
		case .int64: return integerBytes(Int64.self, trimmed, order)
		case .uint64: return integerBytes(UInt64.self, trimmed, order)
		case .float32:
			guard let value = Float(trimmed) else { return .failure(.notANumber(trimmed)) }
			return .success(bytes(of: value.bitPattern, order: order))
		case .float64:
			guard let value = Double(trimmed) else { return .failure(.notANumber(trimmed)) }
			return .success(bytes(of: value.bitPattern, order: order))
		default:
			return .failure(.notEditable(field))
		}
	}

	public enum EncodeProblem: Error, Equatable, Sendable {
		case notANumber(String)
		case doesNotFit(String, Field)
		case notEditable(Field)

		public var said: String {
			switch self {
			case .notANumber(let text): return "“\(text)” is not a number"
			case .doesNotFit(let text, let field): return "\(text) does not fit in \(field.name)"
			case .notEditable(let field): return "\(field.name) is read from the bytes and not typed"
			}
		}
	}

	private static func integerBytes<T: FixedWidthInteger>(
		_ type: T.Type, _ text: String, _ order: ByteOrder
	) -> Result<Data, EncodeProblem> {
		let parsed: T?
		if text.hasPrefix("0x") || text.hasPrefix("0X") {
			parsed = T(text.dropFirst(2), radix: 16)
		} else if text.hasPrefix("-0x") {
			parsed = T(text.dropFirst(3), radix: 16).flatMap { 0 - $0 }
		} else {
			parsed = T(text)
		}
		guard let value = parsed else {
			// Told apart so "300 does not fit in UInt8" is said rather than
			// "300 is not a number", which it plainly is.
			if Int64(text) != nil || UInt64(text) != nil {
				return .failure(.doesNotFit(text, fieldName(for: type)))
			}
			return .failure(.notANumber(text))
		}
		return .success(bytes(of: value, order: order))
	}

	private static func fieldName<T: FixedWidthInteger>(for type: T.Type) -> Field {
		switch (MemoryLayout<T>.size, T.isSigned) {
		case (1, true): return .int8
		case (1, false): return .uint8
		case (2, true): return .int16
		case (2, false): return .uint16
		case (4, true): return .int32
		case (4, false): return .uint32
		case (8, true): return .int64
		default: return .uint64
		}
	}

	public static func bytes<T: FixedWidthInteger>(of value: T, order: ByteOrder) -> Data {
		let width = MemoryLayout<T>.size
		var out = Data(count: width)
		var remaining = value
		for index in 0..<width {
			let byte = UInt8(truncatingIfNeeded: remaining)
			out[order == .little ? index : width - 1 - index] = byte
			remaining = remaining >> 8
		}
		return out
	}
}
