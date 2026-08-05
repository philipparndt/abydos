import Foundation
import Testing
@testable import IdeaiKit

/// What happens to the readers when a child process goes away.
///
/// The bug this exists for cost two cores and was invisible: a
/// `readabilityHandler` is not removed when the far end of the pipe closes, and
/// one left on a closed descriptor is called again the instant it returns. Each
/// language server that exited, and each debug session that ended, left a
/// thread spinning on empty reads for the rest of the session — in an app that
/// looked idle, because nothing was on screen.
///
/// Counted rather than timed. The obvious test measures CPU, and CPU is the one
/// thing a test running beside a thousand others cannot measure: `getrusage`
/// reports the whole process, so the first version of this file passed alone
/// and failed in the suite. How often the reader runs is the same fact, stated
/// where it belongs.
struct PipeDrainTests {
	/// A reader in the shape both clients now use: on end of file it takes
	/// itself off.
	@Test func aHandlerThatSeesEndOfFileRemovesItself() async throws {
		let pipe = Pipe()
		let calls = Counter()

		pipe.fileHandleForReading.readabilityHandler = { handle in
			let data = handle.availableData
			calls.increment()
			guard !data.isEmpty else {
				handle.readabilityHandler = nil
				return
			}
		}

		try pipe.fileHandleForWriting.write(contentsOf: Data("hello".utf8))
		try pipe.fileHandleForWriting.close()

		// Long enough that a handler which does not remove itself would be
		// into the hundreds of thousands of calls.
		try await Task.sleep(nanoseconds: 300_000_000)

		// One read for the data, one for the end of file, and then silence.
		#expect(calls.value <= 3, "the handler kept firing after end of file: \(calls.value) calls")
		#expect(calls.value >= 1)
	}

	/// A language server that exits leaves nothing spinning behind it.
	@Test func aServerThatExitsStopsWakingItsReaders() async throws {
		let client = LSPClient()
		defer { client.stop() }

		// The smallest program that starts and is immediately gone, which is
		// what a server with a bad command line does.
		try client.start(executable: "/usr/bin/true", arguments: [], workingDirectory: nil)
		try await Task.sleep(nanoseconds: 250_000_000)

		let settled = client.readerWakeups
		try await Task.sleep(nanoseconds: 250_000_000)

		// Two ends closing is two wakeups. Anything beyond a handful means a
		// handler is being called back on a descriptor that will never have
		// anything on it again.
		#expect(client.readerWakeups == settled,
		        "the readers are still being woken: \(settled) → \(client.readerWakeups)")
		#expect(settled <= 4)
	}

	/// The same for a debug adapter, which is where the spinning threads were
	/// actually found: `stop()` cleared stdout and left stderr behind.
	@Test func anAdapterThatIsStoppedStopsWakingItsReaders() async throws {
		let client = DAPClient()
		// `cat` holds its end open until it is told to go, so this is about
		// `stop()` rather than about end of file.
		try client.start(executable: "/bin/cat", arguments: [], workingDirectory: nil)
		client.stop()
		#expect(!client.isRunning)

		try await Task.sleep(nanoseconds: 250_000_000)
		let settled = client.readerWakeups
		try await Task.sleep(nanoseconds: 250_000_000)

		#expect(client.readerWakeups == settled,
		        "the readers are still being woken after stop(): \(settled) → \(client.readerWakeups)")
	}

	private final class Counter: @unchecked Sendable {
		private let lock = NSLock()
		private var count = 0

		var value: Int { lock.withLock { count } }
		func increment() { lock.withLock { count += 1 } }
	}
}
