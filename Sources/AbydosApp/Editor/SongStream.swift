import AppKit
import AbydosKit

/// The render that is still being written, while it is.
///
/// `mat render --stream` writes the mix a stretch at a time, so a pane can play
/// a song before it is rendered. What has to be remembered across those
/// stretches is small — which render is growing — and one rule has to be
/// decided on each of them: whether this render may take over from whatever is
/// playing now.
///
/// Its own object because the pane is at its size limit, and because the rule
/// is worth reading on its own.
@MainActor
final class SongStream {
	/// The render whose mix is still being written; nil when nothing is.
	private(set) var directory: URL?

	/// How far past the playhead a render has to reach before it is taken over
	/// to. A sound that is playing is never cut short for one: what was
	/// rendered before goes on until the new render has passed the playhead, so
	/// a save under a playing song is heard from the same bar rather than from
	/// wherever the first stretch happens to end.
	static let lead: Double = 0.5

	func isGrowing(_ candidate: URL) -> Bool { directory == candidate }

	func began(_ directory: URL) { self.directory = directory }

	/// Nothing more is coming — the run ended, or a new one took its place.
	/// Says whether there was something growing to stop.
	func ended() -> Bool {
		guard directory != nil else { return false }
		directory = nil
		return true
	}

	/// Whether a render that has `written` seconds of the song in it may become
	/// what the pane plays.
	///
	/// - Parameter playingAt: where the sound the pane has is, or nil when it
	///   has none — the first render of a song, which is taken at once.
	func mayTakeOver(from playingAt: Double?, written: Double, finished: Bool) -> Bool {
		guard let playingAt, !finished else { return true }
		return written >= playingAt + Self.lead
	}
}
