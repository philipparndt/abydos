import AppKit

/// Something in a tab that plays: a sound or a video.
@MainActor
protocol PlaysMedia: AnyObject {
	/// Another player has started; this one pauses where it is.
	func pauseForAnother()
	/// Whether the two are making the same sound, which since a song can be
	/// shown in several tabs at once they may be: pausing for *that* would be
	/// pausing the sound the other has just started. See `SongPlaybackHub`.
	func makesTheSameSound(as other: PlaysMedia) -> Bool
}

extension PlaysMedia {
	func makesTheSameSound(as other: PlaysMedia) -> Bool { false }
}

/// One sound at a time, across every tab and every window.
///
/// Asked for on 2026-09-13, once a sound kept playing behind other tabs: start
/// a second and the first went on underneath it. Whichever player starts takes
/// the claim, and the one that had it pauses — keeping its position, so going
/// back and pressing play carries on.
@MainActor
enum OnePlayer {
	private static weak var current: PlaysMedia?

	/// `player` has just started playing.
	static func started(_ player: PlaysMedia) {
		if let current, current !== player, !current.makesTheSameSound(as: player) {
			current.pauseForAnother()
		}
		current = player
	}

	/// Every sound in the app, in every window, paused where it is: what the
	/// run control's stop means.
	///
	/// Reported 2026-09-19: "it can happen that a song keeps running even wen
	/// the red stop button is pressed. This shall sotp everything running
	/// globally". The button stopped the first thing it found running — a
	/// program, then the debug session — and a song was stopped only through
	/// its own song session, which a running program kept it from reaching.
	/// And `current` is weak: a song keeps playing when the pane that started
	/// it goes, since the playback belongs to the song (`SongPlaybackHub`), and
	/// nothing held it any more. So the hub is asked too.
	static func stopAll() {
		current?.pauseForAnother()
		SongPlaybackHub.shared.pauseAll()
	}

	/// Whether this is the one that last played.
	///
	/// Two panes can show one song since includes — the song's own tab and a
	/// tab of a file it includes — and both would otherwise say where the
	/// playhead is, the paused one over the playing one.
	static func isCurrent(_ player: PlaysMedia) -> Bool {
		current === player
	}
}
