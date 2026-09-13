import AbydosKit
import AppKit
import AVFoundation

/// A sound file, shown in a tab: a player, its wave and its spectrogram.
///
/// Asked for on 2026-09-13, beside the video tab: a `.wav` or an `.mp3` in a
/// repository opened as the binary notice, while a screen recording beside it
/// played in a tab.
///
/// **It opens paused at the start**, for the video tab's reason: an editor tab
/// is often opened mid-meeting, and a preview that starts making sound is a jump
/// scare. **Unlike the video, it keeps playing when another tab is brought to
/// the front** — asked for the same day: a loop is something to listen to while
/// working in the file it is for — and it stops when its own tab or window
/// closes. While it plays, its tab shows a speaker.
///
/// **The transport is ours, not `AVPlayerView`'s.** Its scrubber would be a
/// second timeline under a wave that is already one, and its controls take
/// their size from `controlSize`, which does not follow the zoom. What plays the
/// sound is `AudioPlayback`, which exists for the seamless loop.
///
/// The file is analysed off the main thread when the tab is first shown — see
/// `DelayedPaneView` — and play works before the drawing arrives.
final class AudioFileView: DelayedPaneView, ScaleFollowing, PlaysMedia {
	private let url: URL
	private let playback: AudioPlayback?
	private let canvas = AudioCanvas()
	private let heights = ScaledHeights()

	private var playButton: DrawnButton!
	private var loopButton: DrawnButton!
	private var fitButton: DrawnButton!
	private var timeLabel: ScaledLabel!
	private var infoLabel: ScaledLabel!
	private var modeChoice: DrawnChoice!
	private var strip: NSStackView!
	private let failureLabel = ScaledLabel(size: 12) { Theme.current.gitIgnored }

	private var activity: PaneActivityView?
	/// Moves the playhead while playing, and only then.
	private var ticker: Timer?
	/// Set when the tab goes, so a read still out stops at its next chunk.
	private let cancelled = CancelFlag()
	/// The detail read for the window on screen, replaced by every newer one.
	private var detailRead: (flag: CancelFlag, task: Task<Void, Never>)?
	private var detailSettle: DispatchWorkItem?

	/// Told whenever playing starts or stops, so the tab can show a speaker.
	var onPlayingChanged: ((Bool) -> Void)?

	/// What the analysis found, or why there is none.
	private(set) var failure: String?
	private var isSettled = false
	private var whenSettled: [() -> Void] = []

	init(url: URL) {
		self.url = url
		playback = try? AudioPlayback(url: url)
		super.init(color: Theme.current.editorBackground)
		colourSource = { Theme.current.editorBackground }
		build()
		whenShown = { [weak self] in self?.analyse() }
		ScaledControls.register(self)
		playback?.onStopped = { [weak self] in self?.playingChanged() }
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		cancelled.set()
		detailRead?.flag.set()
		ticker?.invalidate()
	}

	/// Stops for good. The tab is closing — see `EditorViewController.teardown`
	/// — or its window is.
	func tearDown() {
		cancelled.set()
		detailRead?.flag.set()
		ticker?.invalidate()
		ticker = nil
		let wasPlaying = playback?.isPlaying == true
		playback?.tearDown()
		if wasPlaying { onPlayingChanged?(false) }
	}

	// MARK: - Building

	private func build() {
		playButton = DrawnButton(symbol: "play.fill", description: "Play") { [weak self] in
			self?.togglePlayback()
		}
		playButton.tip = StyledTip.Tip(title: "Play", detail: "Space plays and pauses.")
		loopButton = DrawnButton(symbol: "repeat", description: "Loop") { [weak self] in
			self?.toggleLoop()
		}
		loopButton.tip = StyledTip.Tip(
			title: "Loop", detail: "Plays the file round and round, with no gap at the seam."
		)
		timeLabel = ScaledLabel("0:00 / 0:00", size: 11.5)
		infoLabel = ScaledLabel("", size: 11) { Theme.current.gitIgnored }
		fitButton = DrawnButton(title: "Fit") { [weak self] in self?.canvas.fit() }
		fitButton.tip = StyledTip.Tip(
			title: "Show the whole file", detail: "Pinch or ⌥-scroll to zoom; scroll to move along."
		)
		fitButton.isEnabled = false
		modeChoice = DrawnChoice(
			segments: [.words("Wave"), .words("Spectrum"), .words("Both")],
			selectedIndex: AudioCanvas.Mode.both.rawValue
		) { [weak self] index in
			self?.canvas.mode = AudioCanvas.Mode(rawValue: index) ?? .both
		}

		let spacer = NSView()
		spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
		strip = NSStackView(views: [playButton, loopButton, timeLabel, infoLabel, spacer, fitButton, modeChoice])
		strip.orientation = .horizontal
		strip.alignment = .centerY
		strip.setCustomSpacing(Theme.current.scaled(4), after: playButton)
		applyStripMetrics()

		canvas.onSeek = { [weak self] seconds in self?.seek(to: seconds) }
		canvas.onWindowChanged = { [weak self] in self?.windowChanged() }

		failureLabel.alignment = .center
		failureLabel.lineBreakMode = .byWordWrapping
		failureLabel.maximumNumberOfLines = 0
		failureLabel.isHidden = true

		for view in [strip, canvas, failureLabel] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		NSLayoutConstraint.activate([
			strip.topAnchor.constraint(equalTo: topAnchor),
			strip.leadingAnchor.constraint(equalTo: leadingAnchor),
			strip.trailingAnchor.constraint(equalTo: trailingAnchor),
			heights.height(strip, design: 40),

			canvas.topAnchor.constraint(equalTo: strip.bottomAnchor),
			canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
			canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
			canvas.bottomAnchor.constraint(equalTo: bottomAnchor),

			failureLabel.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
			failureLabel.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
			failureLabel.widthAnchor.constraint(lessThanOrEqualTo: canvas.widthAnchor, constant: -64),
		])
	}

	private func applyStripMetrics() {
		strip.spacing = Theme.current.scaled(10)
		strip.setCustomSpacing(Theme.current.scaled(4), after: playButton)
		strip.edgeInsets = NSEdgeInsets(
			top: 0, left: Theme.current.scaled(10), bottom: 0, right: Theme.current.scaled(10)
		)
	}

	func applyTheme() {
		applyStripMetrics()
		canvas.applyTheme()
	}

	// MARK: - Reading

	/// Decodes and analyses the file off the main thread, under the waiting
	/// strip at the tab's top edge.
	private func analyse() {
		activity = PaneActivityView.install(over: self, message: "Reading \(url.lastPathComponent)…")
		let url = self.url
		let cancelled = self.cancelled
		Task { @MainActor [weak self] in
			// The read captures nothing of the view: only the file and the flag
			// that says the tab has gone.
			let result = await Task.detached(priority: .userInitiated) { () -> Result<AudioOverview, Error> in
				do {
					return .success(try AudioAnalysis.read(url) { cancelled.isSet })
				} catch {
					return .failure(error)
				}
			}.value
			self?.settle(result)
		}
	}

	private func settle(_ result: Result<AudioOverview, Error>) {
		activity?.finish()
		activity = nil
		switch result {
		case .success(let overview):
			canvas.overview = overview
			canvas.fit()
			let rate = overview.sampleRate >= 1000
				? String(format: "%g kHz", (overview.sampleRate / 100).rounded() / 10)
				: "\(Int(overview.sampleRate)) Hz"
			let channels: String
			switch overview.channelCount {
			case 1: channels = "mono"
			case 2: channels = "stereo"
			default: channels = "\(overview.channelCount) channels, mixed"
			}
			infoLabel.stringValue = "\(rate) · \(channels)"
		case .failure(let error):
			guard (error as? AudioAnalysis.Failure) != .cancelled else { return }
			failure = error.localizedDescription
			failureLabel.stringValue = "\(url.lastPathComponent) could not be decoded.\n\(error.localizedDescription)"
			failureLabel.isHidden = false
			playButton.isEnabled = false
			loopButton.isEnabled = false
		}
		followPlayback()
		isSettled = true
		let waiting = whenSettled
		whenSettled = []
		waiting.forEach { $0() }
	}

	/// The window moved: stretch the overview now, and read the window at the
	/// width's detail once it has stopped moving.
	private func windowChanged() {
		fitButton.isEnabled = canvas.isZoomed
		detailSettle?.cancel()
		guard canvas.isZoomed, let overview = canvas.overview else {
			detailRead?.flag.set()
			detailRead = nil
			canvas.detail = nil
			return
		}
		// Already covered by the detail in hand: nothing to read.
		if canvas.detailInUse != nil { return }
		let work = DispatchWorkItem { [weak self] in self?.readDetail(of: overview) }
		detailSettle = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
	}

	/// Reads the window on screen, and half a window either side, at the detail
	/// the width allows: a peak per pixel and a spectrogram column per pixel.
	private func readDetail(of overview: AudioOverview) {
		let rate = overview.sampleRate
		let span = canvas.windowSpan
		let pixels = max(1, Int(canvas.bounds.width * (window?.backingScaleFactor ?? 2)))
		let from = max(0, Int((canvas.windowStart - span / 2) * rate))
		let to = min(overview.frameCount, Int((canvas.windowStart + span * 1.5) * rate))
		guard to > from else { return }
		// Twice the window on screen, so twice the pixels, and never finer
		// than a frame per peak.
		let framesPerPeak = max(1, Int(Double(to - from) / Double(pixels * 2)))
		// Worth a read only where the overview is coarser than the screen: its
		// peaks are wider than a pixel, or its spectrogram has fewer columns in
		// the window than the window has pixels.
		let overviewColumns = Double(overview.spectrogram.columns) * span / max(1e-9, overview.duration)
		guard framesPerPeak < overview.lanes.first?.framesPerPeak ?? 256
		        || overviewColumns < Double(pixels) / 2 else { return }

		detailRead?.flag.set()
		let flag = CancelFlag()
		let url = self.url
		let columns = min(8192, pixels * 2)
		let task = Task { @MainActor [weak self] in
			let reading = await Task.detached(priority: .userInitiated) { () -> AudioOverview? in
				// A column per pixel of what is read, down to 64 frames apart:
				// the window stays 2,048 frames, so the columns overlap and the
				// time axis is smooth rather than blocky.
				try? AudioAnalysis.read(
					url, range: from..<to, framesPerPeak: framesPerPeak, maximumColumns: columns,
					minimumHop: 64
				) { flag.isSet }
			}.value
			guard let self, !flag.isSet, let reading else { return }
			self.canvas.detail = reading
		}
		detailRead = (flag, task)
	}

	// MARK: - Playing

	private var duration: Double {
		if let seconds = canvas.overview?.duration, seconds > 0 { return seconds }
		return playback?.duration ?? 0
	}

	private var isPlaying: Bool { playback?.isPlaying == true }

	func togglePlayback() {
		guard failure == nil, let playback else { return }
		if playback.isPlaying {
			playback.pause()
		} else {
			playback.play()
			if playback.isPlaying { OnePlayer.started(self) }
		}
		playingChanged()
	}

	/// Another tab started playing: pause here, keeping the position.
	func pauseForAnother() {
		guard let playback, playback.isPlaying else { return }
		playback.pause()
		playingChanged()
	}

	private func toggleLoop() {
		guard let playback else { return }
		playback.isLooping.toggle()
		loopButton.isLit = playback.isLooping
		followPlayback()
	}

	private func seek(to seconds: Double) {
		playback?.seek(toSeconds: seconds)
		followPlayback()
	}

	/// Playing started or stopped: the button, the ticker and the tab.
	private func playingChanged() {
		ticker?.invalidate()
		ticker = nil
		if isPlaying {
			let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
				MainActor.assumeIsolated { self?.followPlayback() }
			}
			RunLoop.main.add(timer, forMode: .common)
			ticker = timer
		}
		followPlayback()
		onPlayingChanged?(isPlaying)
	}

	/// The playhead, the clock and the button, from where the sound is.
	private func followPlayback() {
		let now = playback?.currentSeconds ?? 0
		// Out of sight the clock is not worth drawing; the tab's speaker is
		// what says it is playing.
		guard window != nil || !isPlaying else { return }
		canvas.playhead = now
		if isPlaying { canvas.follow(now) }
		timeLabel.stringValue = "\(Self.clock(now)) / \(Self.clock(duration))"
		playButton.setSymbol(isPlaying ? "pause.fill" : "play.fill", description: isPlaying ? "Pause" : "Play")
	}

	static func clock(_ seconds: Double) -> String {
		let whole = Int(seconds.isFinite ? seconds : 0)
		return whole >= 3600
			? String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
			: String(format: "%d:%02d", whole / 60, whole % 60)
	}

	// MARK: - Keyboard and window

	override var acceptsFirstResponder: Bool { true }

	override func keyDown(with event: NSEvent) {
		let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
		// Space, as over the video.
		if event.keyCode == 49, modifiers.isEmpty {
			togglePlayback()
			return
		}
		// ← and →: five seconds, and one with ⇧. Five rather than ten, the web
		// players' step, because many files here are loops of a few seconds,
		// where ten would only ever land on an end.
		if event.keyCode == 123 || event.keyCode == 124, modifiers.isEmpty || modifiers == .shift {
			let step = modifiers == .shift ? Self.fineStep : Self.step
			jump(by: event.keyCode == 123 ? -step : step)
			return
		}
		super.keyDown(with: event)
	}

	static let step = 5.0
	static let fineStep = 1.0

	/// Moves the playhead by `seconds`, wrapping round while looping and
	/// stopping at the ends otherwise; a zoomed view follows it.
	func jump(by seconds: Double) {
		guard failure == nil, duration > 0 else { return }
		var target = (playback?.currentSeconds ?? canvas.playhead) + seconds
		if playback?.isLooping == true {
			target = target.truncatingRemainder(dividingBy: duration)
			if target < 0 { target += duration }
		} else {
			target = min(duration, max(0, target))
		}
		canvas.playhead = target
		canvas.follow(target)
		seek(to: target)
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		super.mouseDown(with: event)
	}

	/// Coming back into sight after playing out of it: the clock and the
	/// playhead catch up at once rather than at the next tick.
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if window != nil { followPlayback() }
	}

	// MARK: - Driving

	/// Runs `then` once the analysis has landed or failed.
	func whenAnalysed(_ then: @escaping () -> Void) {
		if isSettled { then() } else { whenSettled.append(then) }
	}

	func seekForTesting(seconds: Double) {
		canvas.playhead = seconds
		seek(to: seconds)
	}

	func showForTesting(_ name: String) {
		guard let mode = AudioCanvas.Mode.allCases.first(where: { $0.name == name }) else { return }
		modeChoice.selectedIndex = mode.rawValue
		canvas.mode = mode
	}

	func zoomForTesting(from start: Double, to end: Double) {
		canvas.setWindow(start: start, span: end - start)
	}

	func playForTesting() { if !isPlaying { togglePlayback() } }

	func loopForTesting() { if playback?.isLooping == false { toggleLoop() } }

	/// What a driven run reads instead of listening.
	var reportForTesting: String {
		let overview = canvas.overview
		let now = playback?.currentSeconds ?? 0
		return "\(url.lastPathComponent) \(isPlaying ? "playing" : "paused")"
			+ String(format: " duration=%.2f", overview?.duration ?? duration)
			+ " rate=\(Int(overview?.sampleRate ?? 0)) channels=\(overview?.channelCount ?? 0)"
			+ " lanes=\(overview?.lanes.count ?? 0) peaks=\(overview?.lanes.first?.count ?? 0)"
			+ " columns=\(overview?.spectrogram.columns ?? 0)"
			+ String(format: " playhead=%.2f", now)
			+ " view=\(canvas.mode.name) loop=\(playback?.isLooping == true ? "on" : "off")"
			+ String(format: " window=%.3f+%.3fs", canvas.windowStart, canvas.windowSpan)
			+ " detail=\(canvas.detailInUse.map { "\($0) frames per peak" } ?? "none")"
			+ " info=\"\(infoLabel.stringValue)\""
			+ " error=\(failure.map { "\"\($0)\"" } ?? "none")"
	}
}

/// A flag a background read can ask without touching the view.
final class CancelFlag: @unchecked Sendable {
	private let lock = NSLock()
	private var value = false

	var isSet: Bool { lock.withLock { value } }
	func set() { lock.withLock { value = true } }
}
