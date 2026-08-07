import Foundation
import Testing
@testable import AbydosKit

/// Writing to a pipe nobody is reading.
///
/// The default is that it kills the process outright — no crash report, nothing
/// on standard error, exit status 141. That is what "Abydos exited again and
/// there is no crash report" was, all day, and nothing on this side could see
/// it because there was nothing left to see it with.
struct BrokenPipesTests {
	@Test func theSignalIsIgnoredOnceItIsAskedFor() {
		BrokenPipes.ignore()
		#expect(BrokenPipes.isIgnored)
	}

	/// Asking twice is asking once.
	@Test func askingAgainChangesNothing() {
		BrokenPipes.ignore()
		BrokenPipes.ignore()
		#expect(BrokenPipes.isIgnored)
	}

	/// The end of it: a write to a pty whose program has gone comes back as a
	/// failure rather than as the end of this process.
	///
	/// If this regresses the whole suite dies with it, which is the loudest
	/// failure available and the right one — that is exactly what it did in the
	/// app.
	@Test func writingToAShellThatHasGoneIsSurvivable() async throws {
		BrokenPipes.ignore()

		let pty = PseudoTerminal()
		pty.callbackQueue = DispatchQueue(label: "broken-pipes")
		#expect(pty.start(
			executable: "/bin/cat", arguments: [], rows: 24, columns: 80
		))
		try await Task.sleep(nanoseconds: 300_000_000)

		pty.terminate()
		try await Task.sleep(nanoseconds: 300_000_000)

		// Enough to fill anything still buffered, so the write reaches the
		// descriptor rather than sitting in a queue.
		for _ in 0..<50 {
			pty.write(String(repeating: "x", count: 4096))
		}
		try await Task.sleep(nanoseconds: 300_000_000)

		// Still here.
		#expect(BrokenPipes.isIgnored)
	}
}
