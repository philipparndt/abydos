import AVKit
import AppKit

/// A video, shown in a tab.
///
/// Screen recordings and test captures live in repositories beside what they
/// show, and clicking one used to say "This looks like a binary file" and
/// offer a hex dump or a Quick Look panel — a floating window that belongs to
/// no tab and closes on a keypress. The notice's own comment conceded the
/// point: the obvious thing to do with a video is watch it.
///
/// The player is AVKit's, with its inline controls: scrubbing, volume,
/// full screen and space-to-play are what every user's muscle memory expects,
/// and rebuilding transport controls would be a project rather than a tab.
///
/// **It opens paused on its first frame, and switching away pauses it.**
/// An editor tab is often opened mid-meeting — the dotenv covers exist
/// because screens get shared — and a preview that starts talking is a jump
/// scare. Leaving the tab pauses for the same reason the open does not play:
/// a hidden tab with a voice in it is a haunted window. Neither the open nor
/// the return presses play; only somebody watching does.
final class VideoFileView: NSView {
	private let playerView = AVPlayerView()
	private let url: URL

	init(url: URL) {
		self.url = url
		super.init(frame: .zero)

		playerView.player = AVPlayer(url: url)
		playerView.controlsStyle = .inline
		playerView.showsFullScreenToggleButton = true
		// An editor tab is not the machine's media session: a paused clip in
		// a tab must not sit on the Now Playing centre or the media keys.
		playerView.updatesNowPlayingInfoCenter = false
		playerView.translatesAutoresizingMaskIntoConstraints = false
		addSubview(playerView)
		NSLayoutConstraint.activate([
			playerView.topAnchor.constraint(equalTo: topAnchor),
			playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
			playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
			playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Pauses without losing the position, for the tab leaving the front.
	func pause() {
		playerView.player?.pause()
	}

	/// The window watches nothing when the view leaves it, and a view leaving
	/// the window is every way a tab stops being seen — closed, replaced, or
	/// its window gone.
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if window == nil { pause() }
	}

	/// What a driven run reads instead of pixels.
	var reportForTesting: String {
		let player = playerView.player
		let playing = (player?.rate ?? 0) != 0
		let seconds = player?.currentItem?.duration.seconds ?? .nan
		let duration = seconds.isFinite ? String(format: "%.1fs", seconds) : "unknown"
		return "video \(url.lastPathComponent) \(playing ? "playing" : "paused") duration=\(duration)"
	}
}
