import AppKit

/// Something in a tab that plays: a sound or a video.
@MainActor
protocol PlaysMedia: AnyObject {
	/// Another player has started; this one pauses where it is.
	func pauseForAnother()
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
		if let current, current !== player { current.pauseForAnother() }
		current = player
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
