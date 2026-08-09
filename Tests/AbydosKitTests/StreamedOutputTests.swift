import Foundation
import Testing
@testable import AbydosKit

/// A command's output as it is printed rather than when it is over.
///
/// The reason this exists at all: a devcontainer's first minutes are a pull, a
/// build and a `postCreateCommand`, each of which prints as it goes, and each of
/// which used to arrive in the app as one lump at the end. A pane that shows
/// nothing for four minutes and then everything is indistinguishable from one
/// that has hung, which is the whole of 0424's complaint about the lifecycle
/// commands.
struct StreamedOutputTests {
	/// One collector, written from the two reading threads.
	private final class Collected: @unchecked Sendable {
		private let lock = NSLock()
		private var text = ""
		private var stamps: [Date] = []

		func add(_ piece: String) {
			lock.lock()
			text += piece
			stamps.append(Date())
			lock.unlock()
		}

		var all: String {
			lock.lock()
			defer { lock.unlock() }
			return text
		}

		var first: Date? {
			lock.lock()
			defer { lock.unlock() }
			return stamps.first
		}

		var pieces: Int {
			lock.lock()
			defer { lock.unlock() }
			return stamps.count
		}
	}

	/// Everything the command printed arrives through the callback as well as in
	/// the result, and both streams are in it.
	@Test func whatIsStreamedIsWhatIsCollected() {
		let collected = Collected()
		let result = RuntimeCommand.run(
			("/bin/sh", ["-c", "echo out; echo err >&2"]),
			deadline: 30,
			onOutput: { collected.add($0) }
		)

		#expect(result.succeeded)
		#expect(collected.all.contains("out"))
		#expect(collected.all.contains("err"))
		// The result keeps both apart and together, which is what the failure
		// sentence for a lifecycle command is built from.
		#expect(result.errorOutput.contains("err"))
		#expect(result.output.contains("out"))
	}

	/// The first line arrives long before the command ends, which is the point.
	///
	/// A second of margin either side: the command prints at once and then sits
	/// for two, so a callback that only fired at the end could not land in the
	/// first half however slow the machine is.
	@Test func theFirstLineArrivesBeforeTheCommandEnds() throws {
		let collected = Collected()
		let started = Date()
		let result = RuntimeCommand.run(
			("/bin/sh", ["-c", "echo first; sleep 2; echo last"]),
			deadline: 30,
			onOutput: { collected.add($0) }
		)
		let took = Date().timeIntervalSince(started)

		#expect(result.succeeded)
		#expect(took >= 2)
		let firstAt = try #require(collected.first)
		#expect(firstAt.timeIntervalSince(started) < 1)
		// And it did not all come at once at the end.
		#expect(collected.pieces >= 2)
		#expect(collected.all.contains("first"))
		#expect(collected.all.contains("last"))
	}

	/// Nothing is asked for and nothing breaks, which is every other caller.
	@Test func aCommandWithNobodyWatchingIsUnchanged() {
		let result = RuntimeCommand.run(("/bin/echo", ["quiet"]), deadline: 30)
		#expect(result.succeeded)
		#expect(result.output.contains("quiet"))
	}
}
