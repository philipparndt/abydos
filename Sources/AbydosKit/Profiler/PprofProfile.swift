import Compression
import Foundation

/// A profile as Go's runtime writes it.
///
/// The parts a profiler shows: what was measured, the samples, and enough of
/// the location tables to turn a stack of addresses back into function names.
/// Mappings, labels and line numbers within a function are read past — they
/// matter for symbolising a binary, which the Go runtime has already done by
/// the time this arrives.
public struct PprofProfile: Equatable, Sendable {
	/// One column of numbers, e.g. `samples/count` and `cpu/nanoseconds`.
	public struct ValueType: Equatable, Sendable {
		public let kind: String
		public let unit: String

		public init(kind: String, unit: String) {
			self.kind = kind
			self.unit = unit
		}
	}

	/// One stack, and what it measured.
	public struct Sample: Equatable, Sendable {
		/// Leaf first, as pprof stores it.
		public let locationIDs: [UInt64]
		public let values: [Int64]

		public init(locationIDs: [UInt64], values: [Int64]) {
			self.locationIDs = locationIDs
			self.values = values
		}
	}

	public struct Location: Equatable, Sendable {
		public let id: UInt64
		/// Innermost first: one location can hold several inlined frames.
		public let functionIDs: [UInt64]

		public init(id: UInt64, functionIDs: [UInt64]) {
			self.id = id
			self.functionIDs = functionIDs
		}
	}

	public struct Function: Equatable, Sendable {
		public let id: UInt64
		public let name: String
		public let fileName: String

		public init(id: UInt64, name: String, fileName: String) {
			self.id = id
			self.name = name
			self.fileName = fileName
		}
	}

	public let valueTypes: [ValueType]
	public let samples: [Sample]
	public let locations: [UInt64: Location]
	public let functions: [UInt64: Function]
	/// Sampling period, and what it counts. Zero for profiles without one.
	public let period: Int64
	public let periodType: ValueType?
	/// How long the profile covers, in nanoseconds. Zero for a heap profile,
	/// which is a snapshot rather than an interval.
	public let durationNanoseconds: Int64

	public init(
		valueTypes: [ValueType],
		samples: [Sample],
		locations: [UInt64: Location],
		functions: [UInt64: Function],
		period: Int64 = 0,
		periodType: ValueType? = nil,
		durationNanoseconds: Int64 = 0
	) {
		self.valueTypes = valueTypes
		self.samples = samples
		self.locations = locations
		self.functions = functions
		self.period = period
		self.periodType = periodType
		self.durationNanoseconds = durationNanoseconds
	}

	/// The name of every frame in a sample, outermost first.
	///
	/// The order a flame graph is built in: `main` at the bottom, the function
	/// actually running at the top.
	public func stack(of sample: Sample) -> [String] {
		var frames: [String] = []
		for locationID in sample.locationIDs.reversed() {
			guard let location = locations[locationID] else {
				frames.append("<unknown>")
				continue
			}
			// Inlined frames are stored innermost first, so the caller within
			// a location comes last.
			for functionID in location.functionIDs.reversed() {
				frames.append(functions[functionID]?.name ?? "<unknown>")
			}
		}
		return frames
	}

	/// Which column a flame graph should measure.
	///
	/// The last one, which is pprof's own convention: a CPU profile is
	/// `[samples/count, cpu/nanoseconds]` and a heap profile ends with
	/// `inuse_space`, and in both the useful number is the one on the right.
	public var defaultValueIndex: Int {
		max(0, valueTypes.count - 1)
	}
}

// MARK: - Decoding

public enum PprofDecoder {
	public enum Failure: Error, Equatable {
		case notGzipped
		case corrupt
	}

	/// Reads a profile as fetched from a `/debug/pprof/` endpoint.
	///
	/// Go always gzips these, including the ones written to a file by
	/// `pprof.StartCPUProfile`, but a profile that has been through a tool may
	/// arrive plain — so an ungzipped protobuf is read as it is rather than
	/// refused.
	public static func decode(_ data: Data) throws -> PprofProfile {
		let payload = isGzipped(data) ? try gunzip(data) : data
		return try decodeProtobuf(payload)
	}

	static func isGzipped(_ data: Data) -> Bool {
		data.count > 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
	}

	/// Inflates a gzip stream.
	///
	/// Apple's `COMPRESSION_ZLIB` is raw DEFLATE, not the zlib container and
	/// not gzip, so the header has to be stepped over by hand — including the
	/// optional filename and comment, which Go does not write but other
	/// producers do.
	static func gunzip(_ data: Data) throws -> Data {
		let bytes = [UInt8](data)
		guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else {
			throw Failure.notGzipped
		}

		let flags = bytes[3]
		var start = 10
		if flags & 0x04 != 0 {
			// An extra field, whose own length comes first.
			guard start + 2 <= bytes.count else { throw Failure.corrupt }
			let extra = Int(bytes[start]) | Int(bytes[start + 1]) << 8
			start += 2 + extra
		}
		for flag in [UInt8(0x08), UInt8(0x10)] where flags & flag != 0 {
			// A NUL-terminated name or comment.
			while start < bytes.count, bytes[start] != 0 { start += 1 }
			start += 1
		}
		if flags & 0x02 != 0 { start += 2 }
		guard start < bytes.count - 8 else { throw Failure.corrupt }

		// The last four bytes of a gzip stream are the uncompressed size, which
		// is exactly the buffer needed — with a floor, since it is taken modulo
		// 2^32 and a profile can in principle exceed that.
		let tail = bytes.count - 4
		let declared = Int(bytes[tail]) | Int(bytes[tail + 1]) << 8
			| Int(bytes[tail + 2]) << 16 | Int(bytes[tail + 3]) << 24
		let capacity = max(declared, (bytes.count - start) * 8, 64 * 1024)

		let compressed = [UInt8](bytes[start..<(bytes.count - 8)])
		var output = Data(count: capacity)
		let written = output.withUnsafeMutableBytes { destination -> Int in
			compressed.withUnsafeBufferPointer { source in
				compression_decode_buffer(
					destination.bindMemory(to: UInt8.self).baseAddress!,
					capacity,
					source.baseAddress!,
					compressed.count,
					nil,
					COMPRESSION_ZLIB
				)
			}
		}
		guard written > 0 else { throw Failure.corrupt }
		return output.prefix(written)
	}

	// Field numbers from profile.proto.
	private enum Field {
		static let sampleType = 1
		static let sample = 2
		static let location = 4
		static let function = 5
		static let stringTable = 6
		static let durationNanos = 9
		static let periodType = 11
		static let period = 12
	}

	static func decodeProtobuf(_ data: Data) throws -> PprofProfile {
		var reader = ProtobufReader(data)
		var strings: [String] = []
		var pendingValueTypes: [(Int, Int)] = []
		var pendingPeriodType: (Int, Int)?
		var samples: [PprofProfile.Sample] = []
		var locations: [UInt64: PprofProfile.Location] = [:]
		var functions: [UInt64: PprofProfile.Function] = [:]
		var period: Int64 = 0
		var duration: Int64 = 0

		while !reader.isAtEnd {
			let field = try reader.readField()
			switch (field.number, field.wireType) {
			case (Field.stringTable, .lengthDelimited):
				strings.append(try reader.readString())

			case (Field.sampleType, .lengthDelimited):
				pendingValueTypes.append(try readValueType(&reader))

			case (Field.periodType, .lengthDelimited):
				pendingPeriodType = try readValueType(&reader)

			case (Field.period, .varint):
				period = try reader.readInt64()

			case (Field.durationNanos, .varint):
				duration = try reader.readInt64()

			case (Field.sample, .lengthDelimited):
				samples.append(try readSample(&reader))

			case (Field.location, .lengthDelimited):
				let location = try readLocation(&reader)
				locations[location.id] = location

			case (Field.function, .lengthDelimited):
				let function = try readFunction(&reader, strings: strings)
				functions[function.id] = function

			default:
				try reader.skip(field.wireType)
			}
		}

		// Names are indices into the string table, which protobuf allows to
		// arrive after the messages that refer to it.
		func string(_ index: Int) -> String {
			strings.indices.contains(index) ? strings[index] : ""
		}
		let named = functions.mapValues { function in
			PprofProfile.Function(
				id: function.id,
				name: string(Int(function.name) ?? -1),
				fileName: string(Int(function.fileName) ?? -1)
			)
		}

		return PprofProfile(
			valueTypes: pendingValueTypes.map {
				PprofProfile.ValueType(kind: string($0.0), unit: string($0.1))
			},
			samples: samples,
			locations: locations,
			functions: named,
			period: period,
			periodType: pendingPeriodType.map {
				PprofProfile.ValueType(kind: string($0.0), unit: string($0.1))
			},
			durationNanoseconds: duration
		)
	}

	/// `ValueType { type = 1; unit = 2; }`, as indices into the string table.
	private static func readValueType(_ reader: inout ProtobufReader) throws -> (Int, Int) {
		let range = try reader.readLengthDelimited()
		var kind = 0
		var unit = 0
		try reader.forEachField(in: range) { inner, field in
			switch (field.number, field.wireType) {
			case (1, .varint): kind = Int(try inner.readVarint())
			case (2, .varint): unit = Int(try inner.readVarint())
			default: return false
			}
			return true
		}
		return (kind, unit)
	}

	/// `Sample { location_id = 1 [packed]; value = 2 [packed]; }`
	private static func readSample(_ reader: inout ProtobufReader) throws -> PprofProfile.Sample {
		let range = try reader.readLengthDelimited()
		var locationIDs: [UInt64] = []
		var values: [Int64] = []
		try reader.forEachField(in: range) { inner, field in
			switch field.number {
			case 1: locationIDs += try inner.readPackedVarints(field)
			case 2: values += try inner.readPackedVarints(field).map { Int64(bitPattern: $0) }
			default: return false
			}
			return true
		}
		return PprofProfile.Sample(locationIDs: locationIDs, values: values)
	}

	/// `Location { id = 1; line = 4 { function_id = 1 }; }`
	private static func readLocation(_ reader: inout ProtobufReader) throws -> PprofProfile.Location {
		let range = try reader.readLengthDelimited()
		var id: UInt64 = 0
		var functionIDs: [UInt64] = []

		try reader.forEachField(in: range) { inner, field in
			switch (field.number, field.wireType) {
			case (1, .varint):
				id = try inner.readVarint()
			case (4, .lengthDelimited):
				let line = try inner.readLengthDelimited()
				try inner.forEachField(in: line) { lineReader, lineField in
					guard lineField.number == 1, lineField.wireType == .varint else { return false }
					functionIDs.append(try lineReader.readVarint())
					return true
				}
			default:
				return false
			}
			return true
		}
		return PprofProfile.Location(id: id, functionIDs: functionIDs)
	}

	/// `Function { id = 1; name = 2; system_name = 3; filename = 4; }`, where
	/// the names are string-table indices. Carried as numbers until the table
	/// is complete.
	private static func readFunction(
		_ reader: inout ProtobufReader,
		strings: [String]
	) throws -> PprofProfile.Function {
		let range = try reader.readLengthDelimited()
		var id: UInt64 = 0
		var name = 0
		var file = 0

		try reader.forEachField(in: range) { inner, field in
			switch (field.number, field.wireType) {
			case (1, .varint): id = try inner.readVarint()
			case (2, .varint): name = Int(try inner.readVarint())
			case (4, .varint): file = Int(try inner.readVarint())
			default: return false
			}
			return true
		}
		return PprofProfile.Function(id: id, name: "\(name)", fileName: "\(file)")
	}
}
