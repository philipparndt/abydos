import AppKit
import AbydosKit

extension Notification.Name {
	/// A song's playback changed: it plays or it does not, a render replaced
	/// it, or a stem was switched. The object is the song's path.
	static let abydosSongPlaybackChanged = Notification.Name("abydos.songPlaybackChanged")
}

/// One sound per song, however many panes are showing it.
///
/// Asked for 2026-09-16: "when navigate through different files of one song the
/// song is now show, but all part should also have the same play status and the
/// same playhead". Since a file a song includes plays that song, two tabs can
/// be showing one song — and two `AudioPlayback`s of the same render meant two
/// playheads, two play buttons and, if both were started, the song twice.
///
/// So the playback belongs to the song and the panes borrow it: whoever renders
/// puts the new one in, everyone else attaches to it, and it goes when the last
/// pane showing that song does. What a person switches — which stems are heard
/// — belongs to the song here too, so both tabs show the same switches.
@MainActor
final class SongPlaybackHub {
	static let shared = SongPlaybackHub()

	private struct Song {
		var files: [URL]
		var playback: AudioPlayback
		var silenced: Set<String> = []
		var panes: Set<ObjectIdentifier> = []
	}

	private var songs: [String: Song] = [:]

	private func key(_ song: URL) -> String { FilePath.canonical(song) }

	/// The playback of this song's render, made once: the same one for every
	/// pane, and a new one only when the render is a different set of files.
	///
	/// A new one carries what the old one was doing — where it was, whether it
	/// was looping and over what — so a save under a playing song keeps it
	/// playing from the same bar.
	func playback(of song: URL, files: [URL], for pane: AnyObject) throws -> AudioPlayback {
		let id = ObjectIdentifier(pane)
		if var known = songs[key(song)] {
			if known.files == files {
				known.panes.insert(id)
				songs[key(song)] = known
				return known.playback
			}
			let made = try AudioPlayback(urls: files)
			let was = known.playback
			made.isLooping = was.isLooping
			made.loopRange = was.loopRange
			let position = was.currentSeconds
			let wasPlaying = was.isPlaying
			was.tearDown()
			made.seek(toSeconds: min(position, made.duration))
			known.files = files
			known.playback = made
			known.panes.insert(id)
			songs[key(song)] = known
			if wasPlaying { made.play() }
			said(song)
			return made
		}
		let made = try AudioPlayback(urls: files)
		songs[key(song)] = Song(files: files, playback: made, panes: [id])
		return made
	}

	/// The one a pane already has, without making one.
	func playing(of song: URL) -> AudioPlayback? {
		songs[key(song)]?.playback
	}

	/// A pane has stopped showing this song; the sound goes with the last of
	/// them.
	func release(_ song: URL, pane: AnyObject) {
		guard var known = songs[key(song)] else { return }
		known.panes.remove(ObjectIdentifier(pane))
		if known.panes.isEmpty {
			known.playback.tearDown()
			songs.removeValue(forKey: key(song))
		} else {
			songs[key(song)] = known
		}
	}

	/// The stems switched off, which is a fact about the song rather than about
	/// the tab it is switched from.
	func silenced(of song: URL) -> Set<String> {
		songs[key(song)]?.silenced ?? []
	}

	func setSilenced(_ stems: Set<String>, of song: URL) {
		guard var known = songs[key(song)] else { return }
		known.silenced = stems
		songs[key(song)] = known
		said(song)
	}

	/// Tells every pane of this song that something about its sound changed.
	func said(_ song: URL) {
		NotificationCenter.default.post(name: .abydosSongPlaybackChanged, object: key(song) as NSString)
	}
}
