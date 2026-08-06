import Foundation
import Testing
@testable import AbydosKit

/// Reading what Go's runtime writes.
struct PprofDecodingTests {
	private func fixture(_ name: String) throws -> Data {
		let url = try #require(Bundle.module.url(
			forResource: name, withExtension: "pprof", subdirectory: "Fixtures"
		))
		return try Data(contentsOf: url)
	}

	/// A CPU profile from a program that does nothing but recurse: the whole
	/// of its time belongs to one function, reached through a known stack.
	@Test func readsACPUProfile() throws {
		let profile = try PprofDecoder.decode(try fixture("cpu"))

		#expect(profile.valueTypes.map(\.kind) == ["samples", "cpu"])
		#expect(profile.valueTypes.map(\.unit) == ["count", "nanoseconds"])
		#expect(!profile.samples.isEmpty)
		#expect(profile.durationNanoseconds > 0)
		#expect(profile.period > 0)

		let names = Set(profile.functions.values.map(\.name))
		#expect(names.contains("main.fibonacci"))
		#expect(names.contains("main.spin"))
		#expect(names.contains("main.main"))
	}

	/// The stack reads outermost first, which is the order a flame graph is
	/// built in.
	@Test func readsStacksFromTheOutsideIn() throws {
		let profile = try PprofDecoder.decode(try fixture("cpu"))
		let deepest = try #require(profile.samples.max(by: { $0.locationIDs.count < $1.locationIDs.count }))
		let stack = profile.stack(of: deepest)

		#expect(stack.first?.hasPrefix("runtime.") == true)
		#expect(stack.last == "main.fibonacci")
		#expect(stack.contains("main.spin"))
	}

	/// The measurement worth showing is the last column: `cpu/nanoseconds`
	/// here, `inuse_space` in a heap profile.
	@Test func measuresTheLastColumnByDefault() throws {
		let profile = try PprofDecoder.decode(try fixture("cpu"))
		#expect(profile.defaultValueIndex == 1)
		#expect(profile.valueTypes[profile.defaultValueIndex].unit == "nanoseconds")

		let total = profile.samples.reduce(Int64(0)) { $0 + $1.values[1] }
		#expect(total > 0)
	}

	/// A profile that has been through a tool arrives without the gzip wrapper.
	@Test func readsAnUngzippedProfile() throws {
		let raw = try PprofDecoder.gunzip(try fixture("cpu"))
		let profile = try PprofDecoder.decode(raw)
		#expect(!profile.samples.isEmpty)
	}

	@Test func refusesSomethingThatIsNotAProfile() {
		#expect(throws: (any Error).self) {
			try PprofDecoder.decode(Data("not a profile at all".utf8))
		}
	}
}

/// The wire format itself.
struct ProtobufReaderTests {
	@Test func readsVarints() throws {
		var reader = ProtobufReader(Data([0x01, 0xAC, 0x02, 0x80, 0x80, 0x01]))
		#expect(try reader.readVarint() == 1)
		#expect(try reader.readVarint() == 300)
		#expect(try reader.readVarint() == 16384)
		#expect(reader.isAtEnd)
	}

	/// A negative int64 is ten bytes of varint, and reading it as unsigned
	/// gives the two's-complement pattern back.
	@Test func readsNegativeNumbers() throws {
		var reader = ProtobufReader(Data([
			0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01,
		]))
		#expect(try reader.readInt64() == -1)
	}

	@Test func stopsAtATruncatedValue() {
		var reader = ProtobufReader(Data([0x80, 0x80]))
		#expect(throws: ProtobufReader.Failure.truncated) { try reader.readVarint() }
	}

	/// Fields this decoder does not read must be stepped over, or a profile
	/// from a newer Go would stop being readable at the first new field.
	@Test func skipsFieldsItDoesNotKnow() throws {
		// field 1 varint = 7, field 2 length-delimited "hi", field 3 varint = 9
		var reader = ProtobufReader(Data([0x08, 0x07, 0x12, 0x02, 0x68, 0x69, 0x18, 0x09]))
		var seen: [Int: UInt64] = [:]
		while !reader.isAtEnd {
			let field = try reader.readField()
			if field.number == 3, field.wireType == .varint {
				seen[3] = try reader.readVarint()
			} else {
				try reader.skip(field.wireType)
			}
		}
		#expect(seen[3] == 9)
	}

	@Test func readsPackedAndUnpackedRepeatedFields() throws {
		var packed = ProtobufReader(Data([0x0A, 0x03, 0x01, 0x02, 0x03]))
		let packedField = try packed.readField()
		#expect(try packed.readPackedVarints(packedField) == [1, 2, 3])

		var single = ProtobufReader(Data([0x08, 0x05]))
		let singleField = try single.readField()
		#expect(try single.readPackedVarints(singleField) == [5])
	}
}
