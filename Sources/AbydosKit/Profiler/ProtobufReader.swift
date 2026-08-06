import Foundation

/// Just enough protobuf to read a pprof profile.
///
/// A generated decoder would mean vendoring swift-protobuf and a code
/// generator into a build that currently has neither, for one message type
/// whose wire format has been stable for a decade. The wire format itself is
/// four rules, and they are all here.
struct ProtobufReader {
	enum WireType: UInt8 {
		case varint = 0
		case fixed64 = 1
		case lengthDelimited = 2
		case startGroup = 3
		case endGroup = 4
		case fixed32 = 5
	}

	struct Field {
		let number: Int
		let wireType: WireType
	}

	enum Failure: Error, Equatable {
		/// The bytes ran out mid-value, or a field claimed a length past the end.
		case truncated
		/// A wire type protobuf does not define, which means this is not a
		/// protobuf message at all.
		case unknownWireType(UInt8)
	}

	private let bytes: [UInt8]
	private(set) var offset: Int

	init(_ data: Data) {
		bytes = [UInt8](data)
		offset = 0
	}

	init(_ bytes: [UInt8], from start: Int = 0) {
		self.bytes = bytes
		offset = start
	}

	var isAtEnd: Bool { offset >= bytes.count }

	mutating func readField() throws -> Field {
		let key = try readVarint()
		guard let wireType = WireType(rawValue: UInt8(key & 0b111)) else {
			throw Failure.unknownWireType(UInt8(key & 0b111))
		}
		return Field(number: Int(key >> 3), wireType: wireType)
	}

	mutating func readVarint() throws -> UInt64 {
		var value: UInt64 = 0
		var shift: UInt64 = 0
		while true {
			guard offset < bytes.count else { throw Failure.truncated }
			let byte = bytes[offset]
			offset += 1
			value |= UInt64(byte & 0x7F) << shift
			if byte & 0x80 == 0 { return value }
			shift += 7
			// Ten groups of seven bits is the most a 64-bit value can occupy;
			// more than that is a corrupt stream, not a very large number.
			guard shift < 70 else { throw Failure.truncated }
		}
	}

	/// A signed field. pprof stores negative values — a heap profile's
	/// `inuse_objects` after a free — as ordinary two's-complement varints.
	mutating func readInt64() throws -> Int64 {
		Int64(bitPattern: try readVarint())
	}

	mutating func readLengthDelimited() throws -> Range<Int> {
		let length = Int(try readVarint())
		guard length >= 0, offset + length <= bytes.count else { throw Failure.truncated }
		let range = offset..<(offset + length)
		offset += length
		return range
	}

	mutating func readString() throws -> String {
		let range = try readLengthDelimited()
		return String(decoding: bytes[range], as: UTF8.self)
	}

	/// Skips a field whose number is not one we read.
	///
	/// Required rather than optional: a profile written by a newer Go carries
	/// fields this does not know, and stopping at the first of them would mean
	/// reading nothing at all.
	mutating func skip(_ wireType: WireType) throws {
		switch wireType {
		case .varint:
			_ = try readVarint()
		case .fixed64:
			guard offset + 8 <= bytes.count else { throw Failure.truncated }
			offset += 8
		case .fixed32:
			guard offset + 4 <= bytes.count else { throw Failure.truncated }
			offset += 4
		case .lengthDelimited:
			_ = try readLengthDelimited()
		case .startGroup, .endGroup:
			// Groups were removed from the language before pprof existed.
			throw Failure.unknownWireType(wireType.rawValue)
		}
	}

	/// Reads a message's fields, handing each to `body`, which must consume
	/// exactly the field it is given or say it did not.
	mutating func forEachField(
		in range: Range<Int>,
		_ body: (inout ProtobufReader, Field) throws -> Bool
	) throws {
		var inner = ProtobufReader(bytes, from: range.lowerBound)
		while inner.offset < range.upperBound {
			let field = try inner.readField()
			if try !body(&inner, field) {
				try inner.skip(field.wireType)
			}
		}
		offset = max(offset, range.upperBound)
	}

	/// A repeated numeric field, which protobuf may write either packed into
	/// one length-delimited run or as separate varints.
	mutating func readPackedVarints(_ field: Field) throws -> [UInt64] {
		guard field.wireType == .lengthDelimited else { return [try readVarint()] }

		let range = try readLengthDelimited()
		var inner = ProtobufReader(bytes, from: range.lowerBound)
		var values: [UInt64] = []
		while inner.offset < range.upperBound {
			values.append(try inner.readVarint())
		}
		return values
	}
}
