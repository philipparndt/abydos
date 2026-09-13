import AbydosKit
import Foundation

/// The last render of each song, kept for the next pane on it.
///
/// **Reported the first evening: going to another file and back rendered the
/// whole song again**, which for a three-minute song is twenty seconds of
/// silence. A single click in the tree opens a provisional tab, and the next
/// click replaces it — so the pane for a song is torn down and made again
/// every time somebody looks at something else, and a pane that rendered on
/// being made rendered every time. The render is a function of the file's
/// bytes, so it is kept here by the file's fingerprint: a new pane on a song
/// that has not changed plays the last render at once, and its waves come
/// with it once they have been read.
///
/// One entry per song, the newest, so the temporary directory holds one
/// render per song this process has shown rather than one per look; the
/// directory of a replaced entry is deleted here. What a process that quits
/// leaves is swept by the next pane — see `SongRender.staleRenderDirectories`.
@MainActor
final class SongRenderCache {
	struct Entry {
		let fingerprint: String
		let directory: URL
		let manifest: SongRender.Manifest
		/// The mix first, then the stems in the manifest's order.
		let files: [URL]
		let info: String
		/// What has been read of them, in the same order, as it lands.
		var overviews: [AudioOverview?]
	}

	static let shared = SongRenderCache()

	private var entries: [String: Entry] = [:]

	private init() {}

	private func key(_ song: URL) -> String { song.standardizedFileURL.path }

	/// The last render of `song`, when the file is still what it was rendered
	/// from.
	func entry(for song: URL, fingerprint: String) -> Entry? {
		guard let entry = entries[key(song)], entry.fingerprint == fingerprint else { return nil }
		return entry
	}

	/// A new render takes the old one's place; the old directory goes, unless
	/// it is the same one.
	func store(_ entry: Entry, for song: URL) {
		if let old = entries[key(song)], old.directory != entry.directory {
			try? FileManager.default.removeItem(at: old.directory)
		}
		entries[key(song)] = entry
	}

	/// A reading of one of the entry's files landed.
	func read(_ overview: AudioOverview, at index: Int, of directory: URL, for song: URL) {
		guard var entry = entries[key(song)], entry.directory == directory,
		      entry.overviews.indices.contains(index) else { return }
		entry.overviews[index] = overview
		entries[key(song)] = entry
	}
}
