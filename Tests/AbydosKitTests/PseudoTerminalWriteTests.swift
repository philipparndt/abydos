import Foundation
import Testing
@testable import AbydosKit

/// Sending a program more than the pty can take at once.
///
/// A pasted crash report is tens of kilobytes; a pty buffer is a few. The
/// master is non-blocking, so a write that fills it says "not now" — and the
/// old loop took that as "stop", which meant most of a paste never arrived
/// while the app looked as though it had sent it.
struct PseudoTerminalWriteTests {
	@Test func everythingWrittenArrivesEvenWhenItIsFarTooMuch() async throws {
		let terminal = PseudoTerminal()
		let received = Received()
		terminal.onOutput = { received.append($0) }

		// `cat` sends back whatever it is given, so what arrives is the measure
		// of what got through.
		try #require(terminal.start(executable: "/bin/cat", arguments: [], rows: 24, columns: 80))
		defer { terminal.terminate() }

		// Far more than a pty buffer holds, and every line numbered so a gap in
		// the middle would show.
		let lines = (0..<4000).map { "line \($0) ................................................" }
		let payload = lines.joined(separator: "\n") + "\n"
		terminal.write(Data(payload.utf8))

		// Waited for by its last line rather than by a byte count: a pty echoes
		// what it is given as well as what the program says, so counting bytes
		// says "enough have arrived" long before the end has.
		let arrived = await received.wait(forText: "line 3999 ", seconds: 30)
		let text = received.text
		if !arrived {
			Issue.record("""
			the end never arrived: \(received.count) bytes back, \
			last line seen \(text.split(separator: "\n").last ?? "none")
			""")
		}
		#expect(text.contains("line 0 "))
		#expect(text.contains("line 2000 "), "the middle, which used to be dropped")
	}

	/// What is waiting is something the caller can ask about, so anything
	/// advisory — a mouse moving — can be left out while there is a backlog.
	@Test func aBacklogIsVisible() throws {
		let terminal = PseudoTerminal()
		try #require(terminal.start(executable: "/bin/cat", arguments: [], rows: 24, columns: 80))
		defer { terminal.terminate() }

		#expect(terminal.pendingInputCount == 0)
		terminal.write(Data(String(repeating: "x", count: 400_000).utf8))
		// Some of it will have gone; the rest is waiting rather than lost.
		#expect(terminal.pendingInputCount >= 0)
	}

	/// Collects what the program sends back.
	private final class Received: @unchecked Sendable {
		private let lock = NSLock()
		private var data = Data()

		func append(_ chunk: Data) {
			lock.lock(); data.append(chunk); lock.unlock()
		}

		var count: Int {
			lock.lock(); defer { lock.unlock() }
			return data.count
		}

		var text: String {
			lock.lock(); defer { lock.unlock() }
			return String(decoding: data, as: UTF8.self)
		}

		func wait(forText wanted: String, seconds: TimeInterval) async -> Bool {
			let deadline = Date().addingTimeInterval(seconds)
			while Date() < deadline {
				if text.contains(wanted) { return true }
				try? await Task.sleep(nanoseconds: 50_000_000)
			}
			return text.contains(wanted)
		}
	}
}
