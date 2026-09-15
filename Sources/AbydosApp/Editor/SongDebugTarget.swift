import AppKit
import AbydosKit

/// A song pane, and what a debugger over it needs from its tab: where the
/// song's lines are heard, and the lines themselves.
@MainActor
final class SongDebugTarget {
	weak var pane: SongPreviewView?
	let url: URL
	/// The song's files as paths, the song first; the song alone before
	/// includes.
	let files: () -> [String]
	/// Where the lines of one of `files` are heard.
	let timeline: (Int) -> LineTimeline?
	/// A line of one of `files`, both 0-based.
	let lineText: (Int, Int) -> String?

	init(
		pane: SongPreviewView, url: URL, files: @escaping () -> [String],
		timeline: @escaping (Int) -> LineTimeline?, lineText: @escaping (Int, Int) -> String?
	) {
		self.pane = pane
		self.url = url
		self.files = files
		self.timeline = timeline
		self.lineText = lineText
	}
}

/// The lines of files on disk, read again only when a file changes: a frame's
/// name is the note's text, asked for several times a second while a song
/// plays, and an included file has no buffer here unless it is open.
@MainActor
final class SongLineCache {
	private var read: [String: (stamp: Date, lines: [String])] = [:]

	func line(_ line: Int, of path: String) -> String? {
		let stamp = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]))?
			.contentModificationDate ?? .distantPast
		if read[path]?.stamp != stamp {
			let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
			read[path] = (stamp, text.components(separatedBy: "\n"))
		}
		guard let lines = read[path]?.lines, lines.indices.contains(line) else { return nil }
		return lines[line]
	}
}

/// What a song pane's playing did, for the debugger over it.
enum SongPlaybackChange: Equatable {
	case playing
	/// Paused: on a breakpoint's line, 0-based, or wherever it was.
	case stopped(file: URL?, line: Int?)
	/// Ran to its end.
	case ended
	/// The playhead moved while playing.
	case tick
}
