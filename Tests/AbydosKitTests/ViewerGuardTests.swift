import Testing
import Foundation
@testable import AbydosKit

/// The note that stops a model which killed the app from being rendered twice.
///
/// A 3D viewer is somebody else's code reached through SwiftUI, and it can fail
/// in a way nothing here can catch — a Swift precondition ends the process. That
/// happened. What made it serious was not the crash but that the session
/// restored the tab which caused it, so the app died a second into every launch
/// and could not be started at all until a file was edited by hand.
struct ViewerGuardTests {
	private func directory() throws -> URL {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-viewer-guard-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	@Test func nothingIsBlamedWhenThereIsNoNote() throws {
		let store = try directory()
		defer { try? FileManager.default.removeItem(at: store) }

		#expect(ViewerGuard.blamed(in: store) == nil)
		#expect(!ViewerGuard.isBlamed("/models/bracket.scad", in: store))
	}

	/// A render that started and never finished leaves the note behind, which is
	/// exactly the state a process that stopped existing leaves.
	@Test func aRenderThatNeverSettledIsBlamed() throws {
		let store = try directory()
		defer { try? FileManager.default.removeItem(at: store) }

		ViewerGuard.begin("/models/bracket.scad", in: store)
		#expect(ViewerGuard.blamed(in: store) == "/models/bracket.scad")
		#expect(ViewerGuard.isBlamed("/models/bracket.scad", in: store))
	}

	/// And one that finished does not.
	@Test func aRenderThatSettledIsNotBlamed() throws {
		let store = try directory()
		defer { try? FileManager.default.removeItem(at: store) }

		ViewerGuard.begin("/models/bracket.scad", in: store)
		ViewerGuard.settled(in: store)

		#expect(ViewerGuard.blamed(in: store) == nil)
		#expect(!ViewerGuard.isBlamed("/models/bracket.scad", in: store))
	}

	/// Only the model that did it is refused. Everything else still opens, which
	/// is the difference between this and switching the viewer off.
	@Test func onlyTheModelThatDidItIsBlamed() throws {
		let store = try directory()
		defer { try? FileManager.default.removeItem(at: store) }

		ViewerGuard.begin("/models/bracket.scad", in: store)

		#expect(ViewerGuard.isBlamed("/models/bracket.scad", in: store))
		#expect(!ViewerGuard.isBlamed("/models/dollhouse.scad", in: store))
	}

	/// One note, not a list: the question is what the *last* run died on, and a
	/// second render replacing the first is the honest answer to it.
	@Test func aSecondRenderReplacesTheNote() throws {
		let store = try directory()
		defer { try? FileManager.default.removeItem(at: store) }

		ViewerGuard.begin("/models/first.scad", in: store)
		ViewerGuard.begin("/models/second.scad", in: store)

		#expect(ViewerGuard.blamed(in: store) == "/models/second.scad")
		#expect(!ViewerGuard.isBlamed("/models/first.scad", in: store))
	}

	/// "Show anyway" clears the note before trying again, so a model that then
	/// renders is not refused next time either.
	@Test func forgivingThenSucceedingLeavesNothingBehind() throws {
		let store = try directory()
		defer { try? FileManager.default.removeItem(at: store) }

		ViewerGuard.begin("/models/bracket.scad", in: store)
		// What `showAnyway` does: clear, re-mark, and settle when it survives.
		ViewerGuard.settled(in: store)
		ViewerGuard.begin("/models/bracket.scad", in: store)
		ViewerGuard.settled(in: store)

		#expect(ViewerGuard.blamed(in: store) == nil)
	}

	/// An empty path is not a model and must never be written: a note naming
	/// nothing would be a note that blames everything.
	@Test func anEmptyPathIsNeverWritten() throws {
		let store = try directory()
		defer { try? FileManager.default.removeItem(at: store) }

		ViewerGuard.begin("", in: store)

		#expect(ViewerGuard.blamed(in: store) == nil)
		#expect(!ViewerGuard.isBlamed("", in: store))
	}

	/// The note has to survive a process that stops without warning, so it is on
	/// the disk by the time `begin` returns rather than in a buffer.
	@Test func theNoteIsOnDiskBeforeTheRenderStarts() throws {
		let store = try directory()
		defer { try? FileManager.default.removeItem(at: store) }

		ViewerGuard.begin("/models/bracket.scad", in: store)

		let onDisk = try String(contentsOf: ViewerGuard.noteURL(in: store), encoding: .utf8)
		#expect(onDisk.trimmingCharacters(in: .whitespacesAndNewlines) == "/models/bracket.scad")
	}

	/// Paths with spaces and non-ASCII in them are ordinary, and a note that
	/// mangled one would refuse the wrong file or none at all.
	@Test func awkwardPathsSurviveTheRoundTrip() throws {
		let store = try directory()
		defer { try? FileManager.default.removeItem(at: store) }

		let path = "/Users/x/Modelle/kühlschrank-türe/abdeckung 2.3mf"
		ViewerGuard.begin(path, in: store)

		#expect(ViewerGuard.isBlamed(path, in: store))
	}

	/// The delay covers the failure it is for — an abort in the first layout pass
	/// — without being so long that quitting after opening a model leaves a note
	/// that refuses it next time.
	@Test func theSettleDelayIsSecondsRatherThanMinutes() {
		#expect(ViewerGuard.settleDelay >= 2)
		#expect(ViewerGuard.settleDelay <= 15)
	}

	/// A note left by a *previous* version, or hand-written, should not throw.
	@Test func aNoteWithSurroundingWhitespaceStillNamesTheModel() throws {
		let store = try directory()
		defer { try? FileManager.default.removeItem(at: store) }

		try "  /models/bracket.scad \n".write(
			to: ViewerGuard.noteURL(in: store), atomically: true, encoding: .utf8
		)

		#expect(ViewerGuard.blamed(in: store) == "/models/bracket.scad")
	}
}
