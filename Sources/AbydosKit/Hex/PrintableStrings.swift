import Foundation

/// Runs of readable text in a binary, the way `strings` lists them.
///
/// Built off the main thread over a snapshot, and capped: a gigabyte of
/// mostly-text yields millions of runs, and a list of millions is not a list
/// anybody reads. The cap is said in the result so the pane can say how many
/// more there were rather than end quietly.
public enum PrintableStrings {
	public struct Found: Sendable, Equatable {
		public let offset: Int
		public let length: Int
		public let text: String
	}

	public struct Listing: Sendable, Equatable {
		public let strings: [Found]
		/// How many runs were there beyond the cap.
		public let unlisted: Int

		public init(strings: [Found], unlisted: Int) {
			self.strings = strings
			self.unlisted = unlisted
		}
	}

	/// Four is `strings`' default and the shortest run that is more often a
	/// word than a coincidence.
	public static let minimumLength = 4
	public static let maximumListed = 20_000

	public static func list(
		in snapshot: ByteDocument.Snapshot,
		encoding: ByteEncoding = .ascii,
		minimum: Int = minimumLength,
		cap: Int = maximumListed,
		isCancelled: () -> Bool = { Task.isCancelled }
	) -> Listing {
		switch encoding {
		case .utf16LittleEndian, .utf16BigEndian:
			return wide(in: snapshot, encoding: encoding, minimum: minimum, cap: cap, isCancelled: isCancelled)
		default:
			return narrow(in: snapshot, encoding: encoding, minimum: minimum, cap: cap, isCancelled: isCancelled)
		}
	}

	/// One byte per character: ASCII, Latin-1, and UTF-8 where a run may also
	/// hold well-formed multi-byte sequences.
	private static func narrow(
		in snapshot: ByteDocument.Snapshot,
		encoding: ByteEncoding,
		minimum: Int,
		cap: Int,
		isCancelled: () -> Bool
	) -> Listing {
		var strings: [Found] = []
		var unlisted = 0
		var runStart = -1
		var runBytes = Data()
		var runCharacters = 0

		func close(at offset: Int) {
			defer {
				runStart = -1
				runBytes.removeAll(keepingCapacity: true)
				runCharacters = 0
			}
			guard runStart >= 0, runCharacters >= minimum else { return }
			if strings.count >= cap {
				unlisted += 1
				return
			}
			guard let text = String(data: runBytes, encoding: encoding.stringEncoding) else { return }
			strings.append(Found(offset: runStart, length: offset - runStart, text: text))
		}

		var offset = 0
		let total = snapshot.count
		while offset < total {
			if offset & 0xFFFFF == 0, isCancelled() { break }
			let byte = snapshot.byte(at: offset)
			if encoding.isPrintable(byte) {
				if runStart < 0 { runStart = offset }
				runBytes.append(byte)
				runCharacters += 1
				offset += 1
				continue
			}
			if encoding == .utf8, byte >= 0xC2, let length = utf8Length(lead: byte),
			   offset + length <= total,
			   let scalar = String(data: snapshot.bytes(in: offset..<(offset + length)), encoding: .utf8),
			   scalar.unicodeScalars.count == 1 {
				if runStart < 0 { runStart = offset }
				runBytes.append(snapshot.bytes(in: offset..<(offset + length)))
				runCharacters += 1
				offset += length
				continue
			}
			close(at: offset)
			offset += 1
		}
		close(at: offset)
		return Listing(strings: strings, unlisted: unlisted)
	}

	private static func utf8Length(lead: UInt8) -> Int? {
		switch lead {
		case 0xC2...0xDF: return 2
		case 0xE0...0xEF: return 3
		case 0xF0...0xF4: return 4
		default: return nil
		}
	}

	/// Two bytes per character, the way Windows binaries and .NET write their
	/// text: a printable ASCII unit with a zero high byte, which is `strings
	/// -el`. Anything wider is left to a proper decoder.
	private static func wide(
		in snapshot: ByteDocument.Snapshot,
		encoding: ByteEncoding,
		minimum: Int,
		cap: Int,
		isCancelled: () -> Bool
	) -> Listing {
		var strings: [Found] = []
		var unlisted = 0
		let total = snapshot.count
		let little = encoding == .utf16LittleEndian
		// Both alignments, since a UTF-16 string may begin on an odd byte.
		for phase in 0..<2 {
			var runStart = -1
			var text = ""
			func close(at offset: Int) {
				defer { runStart = -1; text = "" }
				guard runStart >= 0, text.count >= minimum else { return }
				if strings.count >= cap { unlisted += 1; return }
				strings.append(Found(offset: runStart, length: offset - runStart, text: text))
			}
			var offset = phase
			while offset + 1 < total {
				if offset & 0xFFFFF == 0, isCancelled() { break }
				let first = snapshot.byte(at: offset), second = snapshot.byte(at: offset + 1)
				let (low, high) = little ? (first, second) : (second, first)
				if high == 0, low >= 0x20, low < 0x7F {
					if runStart < 0 { runStart = offset }
					text.append(Character(UnicodeScalar(low)))
					offset += 2
					continue
				}
				close(at: offset)
				offset += 2
			}
			close(at: offset)
		}
		strings.sort { $0.offset < $1.offset }
		return Listing(strings: strings, unlisted: unlisted)
	}
}
