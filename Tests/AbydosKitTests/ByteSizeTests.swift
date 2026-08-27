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

	/// A directory is `du`, because a walk in Swift of a build directory is the
	/// thing this is used in front of — a dialog asking whether to delete a
	/// worktree, which wants to say what deleting it would free.
	@Test func aDirectoryIsMeasuredWhole() async throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-du-\(UUID().uuidString)")
		let nested = root.appendingPathComponent("a/b")
		try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		try Data(repeating: 0x41, count: 40_000).write(to: nested.appendingPathComponent("big"))

		let measured = try #require(await ByteSize.ofDirectory(at: root))
		// `du` counts blocks, so the answer is the file rounded up plus the
		// directories holding it — more than the file and not much more.
		#expect(measured >= 40_000, "\(measured)")
		#expect(measured < 200_000, "\(measured)")
	}

	@Test func aDirectoryThatIsNotThereMeasuresNothing() async {
		let missing = URL(fileURLWithPath: "/tmp/abydos-not-here-\(UUID())")
		#expect(await ByteSize.ofDirectory(at: missing) == nil)
	}

	/// **The deadline reaches the process, not just the task.** Cancelling a
	/// Swift task does not stop a `Process` — `waitUntilExit` waits either way
	/// — so a first version of this held the dialog open for as long as `du`
	/// felt like walking. Nothing measures the whole disk in a millisecond, so
	/// this comes back empty-handed, which is the contract: a sentence loses a
	/// clause and nothing else changes.
	@Test func aMeasurementThatWouldTakeTooLongIsGivenUpOn() async {
		let started = Date()
		let measured = await ByteSize.ofDirectory(
			at: URL(fileURLWithPath: "/"), within: .milliseconds(50)
		)
		// The answer is the claim, and it holds under any load: nothing
		// measures the whole disk in a millisecond, so it comes back
		// empty-handed and the sentence loses a clause.
		#expect(measured == nil)

		// **The clock is a separate claim, and it needs the load beside it.**
		// This asserted `< 5 s` flatly and went red at 6.3 s under load 28 —
		// which was not a walk of the disk but a detached task waiting for a
		// core on a machine running the whole suite. That is the failure mode
		// `Stopwatch` exists for.
		let took = Date().timeIntervalSince(started)
		guard Stopwatch.maySay("PERF du", "giving up on a measurement") else {
			print("PERF du: gave up after \(Int(took * 1000)) ms. \(MachineLoad.said)")
			return
		}
		#expect(took < 2, "gave up after \(Int(took * 1000)) ms. \(MachineLoad.said)")
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
