import Foundation
import Testing
@testable import IdeaiKit

/// Editing somebody's own ~/.tmux.conf.
struct TmuxConfigTests {
	/// A real one: the user's, with cmanager's window format in it.
	private let existing = """
	# prefix + a → the session picker
	bind a display-popup -E -w 80% -h 70% '$HOME/.local/bin/cmanager pick'

	set -g window-status-format '  #I:#W  '
	"""

	@Test func theBlockIsAppendedAndFound() {
		let updated = TmuxConfig.adding(to: existing)
		#expect(TmuxConfig.hidesStatus(in: updated))
		#expect(updated.contains("set -g status off"))
		#expect(updated.hasPrefix(existing), "what was there stays, and stays first")
	}

	/// The last word on an option is the one tmux takes, so the block goes at
	/// the end rather than being woven into somebody's careful ordering.
	@Test func nothingElseIsMoved() {
		let updated = TmuxConfig.adding(to: existing)
		#expect(updated.contains("bind a display-popup"))
		#expect(updated.contains("set -g window-status-format '  #I:#W  '"))
	}

	@Test func addingTwiceChangesNothing() {
		let once = TmuxConfig.adding(to: existing)
		#expect(TmuxConfig.adding(to: once) == once)
	}

	/// Pressing the button twice has to leave the file as it found it, or every
	/// switch back and forth grows somebody's config. Both ends normalise the
	/// blank lines at the end, so the round trip settles rather than drifts.
	@Test func removingPutsItBack() {
		let updated = TmuxConfig.adding(to: existing)
		let back = TmuxConfig.removing(from: updated)
		#expect(back == existing + "\n")
		// And again, and again: the same text every time.
		#expect(TmuxConfig.removing(from: TmuxConfig.adding(to: back)) == back)
		#expect(TmuxConfig.adding(to: back) == updated + "")
	}

	@Test func removingWhatIsNotThereIsHarmless() {
		#expect(TmuxConfig.removing(from: existing) == existing)
		#expect(TmuxConfig.removing(from: "") == "")
	}

	@Test func anEmptyConfigGetsJustTheBlock() {
		let updated = TmuxConfig.adding(to: "")
		#expect(updated.hasPrefix(TmuxConfig.openingMarker))
		#expect(TmuxConfig.hidesStatus(in: updated))
		#expect(TmuxConfig.removing(from: updated).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
	}

	/// Somebody may have written their own `status off` — that is not ours, and
	/// pressing restore must not take away a line we did not write.
	@Test func onlyOurOwnBlockIsRecognisedAndRemoved() {
		let theirs = "set -g status off\n"
		#expect(!TmuxConfig.hidesStatus(in: theirs))
		#expect(TmuxConfig.removing(from: theirs) == theirs)
	}

	@Test func writingKeepsACopy() throws {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("tmux-conf-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let file = directory.appendingPathComponent(".tmux.conf")

		#expect(try TmuxConfig.read(at: file).isEmpty, "no config yet is not an error")
		try existing.write(to: file, atomically: true, encoding: .utf8)

		let backup = try TmuxConfig.write(TmuxConfig.adding(to: try TmuxConfig.read(at: file)), to: file)
		#expect(TmuxConfig.hidesStatus(in: try TmuxConfig.read(at: file)))
		let saved = try #require(backup)
		#expect(try String(contentsOf: saved, encoding: .utf8) == existing, "the backup is what was there")
	}
}

/// Against the config that is actually on this machine, copied aside: the
/// round trip has to survive somebody's real file, not only a tidy fixture.
struct TmuxConfigRealFileTests {
	@Test func aRealConfigSurvivesTheRoundTrip() throws {
		let home = FileManager.default.homeDirectoryForCurrentUser
			.appendingPathComponent(".tmux.conf")
		try #require(FileManager.default.fileExists(atPath: home.path))

		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("tmux-real-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }

		let copy = directory.appendingPathComponent(".tmux.conf")
		try FileManager.default.copyItem(at: home, to: copy)
		let original = try TmuxConfig.read(at: copy)

		try TmuxConfig.write(TmuxConfig.adding(to: original), to: copy)
		let hidden = try TmuxConfig.read(at: copy)
		#expect(TmuxConfig.hidesStatus(in: hidden))
		#expect(hidden.contains("set -g status off"))
		// Everything that was there is still there, in order.
		#expect(hidden.hasPrefix(original.trimmingCharacters(in: .newlines)))

		try TmuxConfig.write(TmuxConfig.removing(from: hidden), to: copy)
		let restored = try TmuxConfig.read(at: copy)
		#expect(restored.trimmingCharacters(in: .newlines)
			== original.trimmingCharacters(in: .newlines))
	}
}
