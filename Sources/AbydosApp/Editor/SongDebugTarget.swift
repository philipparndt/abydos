import AppKit
import AbydosKit

/// A song pane, and what a debugger over it needs from its tab: where the
/// song's lines are heard, and the lines themselves.
@MainActor
final class SongDebugTarget {
	weak var pane: SongPreviewView?
	let url: URL
	let timeline: () -> LineTimeline?
	/// A line of the buffer, 0-based.
	let lineText: (Int) -> String?

	init(pane: SongPreviewView, url: URL, timeline: @escaping () -> LineTimeline?, lineText: @escaping (Int) -> String?) {
		self.pane = pane
		self.url = url
		self.timeline = timeline
		self.lineText = lineText
	}
}

/// What a song pane's playing did, for the debugger over it.
enum SongPlaybackChange: Equatable {
	case playing
	/// Paused: on a breakpoint's line, 0-based, or wherever it was.
	case stopped(line: Int?)
	/// Ran to its end.
	case ended
	/// The playhead moved while playing.
	case tick
}
