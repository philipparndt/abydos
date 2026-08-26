import Foundation
import Testing
@testable import AbydosKit

/// What a number of bytes looks like in this app.
///
/// Three places say it now — the sessions section, a binary file's notice and
/// the tool window's memory column — and they say it through one function for a
/// reason that has already bitten once: a notice read `405,7 MB` in its sentence
/// and `387 MiB` beside it, because one came from `ByteCountFormatter`'s `.file`
/// style (dividing by 1000) and the other from this arithmetic. The same number
/// in two conventions reads as a mistake, because it is one.
struct ByteSizeTests {
	@Test func bytesBelowAKilobyteAreCountedInBytes() {
		#expect(ByteSize.said(0) == "0 B")
		#expect(ByteSize.said(1) == "1 B")
		#expect(ByteSize.said(1023) == "1023 B")
	}

	/// 1024 and not 1000. The unit says `MiB`, so the arithmetic has to match
	/// it — that is the whole of what went wrong before.
	@Test func aKibibyteIsTenTwentyFourBytes() {
		#expect(ByteSize.said(1024) == "1.0 KiB")
		#expect(ByteSize.said(1_048_576) == "1.0 MiB")
		#expect(ByteSize.said(1_073_741_824) == "1.0 GiB")
	}

	/// Below ten it keeps a decimal, at ten and above it rounds — a column of
	/// sizes reads better without a trailing `.0` on every large one, and a
	/// `1.5 KiB` would be a bare `1` without the decimal on the small ones.
	@Test func tenIsWhereTheDecimalStops() {
		#expect(ByteSize.said(1536) == "1.5 KiB")
		#expect(ByteSize.said(9 * 1024 + 512) == "9.5 KiB")
		#expect(ByteSize.said(10 * 1024) == "10 KiB")
		#expect(ByteSize.said(25_400_000) == "24 MiB")
	}

	/// Gibibytes are the last unit: a terabyte says four figures of them rather
	/// than inventing a `TiB` nothing in this app has ever needed.
	@Test func gibibytesAreTheLargestUnit() {
		#expect(ByteSize.said(1_099_511_627_776) == "1024 GiB")
	}

	/// The rounding is on the boundary, so this is the case a second
	/// implementation would get wrong: 10.0 exactly rounds, 9.99 does not.
	@Test func theBoundaryItselfRounds() {
		#expect(ByteSize.said(10 * 1_048_576) == "10 MiB")
		#expect(ByteSize.said(10 * 1_048_576 - 1) == "10.0 MiB")
	}

	@Test func aFileThatIsNotThereHasNoSize() {
		#expect(ByteSize.ofFile(at: URL(fileURLWithPath: "/tmp/nothing-here-\(UUID())")) == nil)
	}

	@Test func aFileThatIsThereIsMeasured() throws {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-bytesize-\(UUID().uuidString)")
		try Data(repeating: 0x41, count: 2048).write(to: url)
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(ByteSize.ofFile(at: url) == 2048)
		#expect(ByteSize.ofFile(at: url).map(ByteSize.said) == "2.0 KiB")
	}
}
