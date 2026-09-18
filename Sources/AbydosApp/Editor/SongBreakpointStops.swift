import AppKit
import AbydosKit

/// Where a song stopped, and how it knows to stop there.
///
/// The song pane plays; the breakpoints are the gutter's, placed by the
/// timeline `mat lsp` sends, and the debugger over the song is told what
/// happened. What that needs remembering is small and entirely its own: where
/// the playhead was when it was last looked at, since a breakpoint is reached
/// by playing past the moment its line starts, and where it stopped.
///
/// Its own object rather than four more properties of the pane, which is long
/// enough that the sound is hard to find among them.
@MainActor
final class SongBreakpointStops {
	/// The first enabled breakpoint playing reaches between two moments; nil
	/// for none. The editor's, since the breakpoints and the timeline are.
	var ahead: ((_ from: Double, _ to: Double) -> (line: Int, seconds: Double, file: URL?)?)?
	/// The line a stop is on, and nil when the song plays on.
	var onStop: ((_ file: URL?, _ line: Int?) -> Void)?

	/// Where the playhead was when it was last looked at.
	private(set) var lastSeen: Double?
	/// The line it stopped on, 0-based, and the file that line is in.
	private(set) var line: Int?
	private(set) var file: URL?

	/// What a stop says to the debugger: the file and line, or nothing.
	var stopped: (file: URL?, line: Int?) { (line == nil ? nil : file, line) }

	/// Whether the song is standing on a breakpoint.
	var isStopped: Bool { line != nil }

	/// The playhead is here, and the song is or is not playing: the moment a
	/// breakpoint is reached, or nil.
	func reached(_ now: Double, playing: Bool) -> (line: Int, seconds: Double, file: URL?)? {
		let from = lastSeen
		lastSeen = now
		guard playing, let from, let hit = ahead?(from, now) else { return nil }
		lastSeen = hit.seconds
		set(line: hit.line, file: hit.file)
		return hit
	}

	/// Playing on, or a seek: nothing is stopped, and nothing between here and
	/// there was played past.
	func goOn(from seconds: Double?) {
		lastSeen = seconds
		set(line: nil, file: nil)
	}

	private func set(line: Int?, file: URL?) {
		guard line != self.line || file != self.file else { return }
		self.file = file
		self.line = line
		onStop?(line == nil ? nil : file, line)
	}
}
