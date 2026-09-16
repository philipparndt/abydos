import AbydosKit
import AppKit

/// A song's sound, beside the text that makes it.
///
/// A [musik-as-text](https://github.com/rnd7/musik-as-text) `.song` is the
/// `.scad` case with sound for a shape: text written to be heard, rendered by
/// a program somebody has installed. `mat render` writes the whole mix and one
/// stem per layer, and this pane plays them and draws them — the mix as one
/// wave and spectrum, or the stems one above the other, each with a switch —
/// and lights the stem the caret is in.
///
/// Three things follow from what a song is that the `.scad` pane does not need:
///
///  1. **The render is played, not looked at**, so it is kept playing across
///     edits. A save that does not parse — which is most saves, mid-line — must
///     not stop the loop somebody is writing against: the last good render
///     stays and keeps playing, and the error is a strip over it that reveals
///     the line when clicked. Cadova's pane replaces the model with the
///     compiler, and the argument there was that a stale shape is a lie with a
///     caption; a stale sound is what a musician expects until the next bar.
///  2. **A new render carries the place over.** The playhead and whether it
///     was playing move to the new files, so a change to the chorus is heard
///     in the chorus, not from the top.
///  3. **The song file is rendered where it is**, since its samples and audio
///     tracks are paths relative to it, and the output goes to a directory of
///     the pane's own under the temporary directory, never into the project.
///
/// Like every preview, nothing runs until the pane has been looked at.
final class SongPreviewView: DelayedPaneView, ScaleFollowing, PlaysMedia {
	enum View: Int {
		case mix, stems

		var name: String { self == .mix ? "mix" : "stems" }
	}

	/// The song this pane plays. The tab's own file, until a timeline says the
	/// file is included in another song — then that one, since a file of a song
	/// has no sound of its own. See `showSong(at:)`.
	private(set) var url: URL
	/// The tab's file, whatever is being played for it.
	let file: URL
	let executable: String?
	/// The text as it is in the buffer, for the block under the caret.
	private let sourceText: () -> String?
	/// The source should show a line: a lane's name was clicked, or the
	/// error strip.
	var onRevealLine: ((Int, Int) -> Void)?
	/// Where the playhead is, as it moves, for the source's timeline bars; nil
	/// when there is nothing to play.
	var onPlayhead: ((_ seconds: Double?, _ marking: Bool) -> Void)?
	/// The first enabled breakpoint playing reaches between two moments, from
	/// the source's timeline; nil for none.
	var breakpointAhead: ((_ from: Double, _ to: Double) -> (line: Int, seconds: Double, file: URL?)?)?
	/// The line a breakpoint stopped the song on, and nil when it plays on.
	var onBreakpointStop: ((_ file: URL?, _ line: Int?) -> Void)?
	/// Playing, pausing, stopping on a breakpoint, running out, and the
	/// playhead moving: what a debugger over the song is told.
	var onPlaybackChange: ((SongPlaybackChange) -> Void)?
	/// Where the playhead was when last followed: a breakpoint is reached
	/// when playing carries the playhead past its start.
	private var lastFollowed: Double?
	/// The line a breakpoint stopped playing on, until play or a seek.
	private var stoppedLine: Int? {
		didSet { if stoppedLine != oldValue { onBreakpointStop?(stoppedFile, stoppedLine) } }
	}
	/// The included file the stop's line is in; nil for the song's own.
	private var stoppedFile: URL?
	/// Told whenever playing starts or stops, so the tab can show a speaker.
	var onPlayingChanged: ((Bool) -> Void)?

	private let canvas = SongCanvas()
	private let heights = ScaledHeights()
	private var playButton: DrawnButton!
	private var loopButton: DrawnButton!
	private var fitButton: DrawnButton!
	/// Export ▸ — see `SongPreviewView+Export`.
	var exportButton: DrawnButton!
	var isExporting = false
	private var timeLabel: ScaledLabel!
	private var infoLabel: ScaledLabel!
	private var viewChoice: DrawnChoice!
	private var modeChoice: DrawnChoice!
	private var strip: NSStackView!
	/// The last render's complaint, over the sound that is still playing.
	private let errorStrip = ErrorStripView()
	/// Why there is nothing at all: no tool, or no render that ever worked.
	private let failureText = NSTextView()
	private let failureScroll = NSScrollView()
	private let noticeLabel = ScaledLabel("", size: 12) { Theme.current.sidebarText.withAlphaComponent(0.85) }
	private var activity: PaneActivityView?

	// MARK: The render

	/// What one render produced and what plays it.
	private struct Rendered {
		let directory: URL
		let manifest: SongRender.Manifest
		/// The mix first, then a stem per layer, in the manifest's order —
		/// the same order as the playback's voices.
		let files: [URL]
		let playback: AudioPlayback
	}

	private var rendered: Rendered?
	private var running: Process?
	private var pending: DispatchWorkItem?
	/// The files the song is made of, and the watch on them.
	private lazy var sources = SongSources { [weak self] in self?.fileChanged() }
	private var fingerprint: String?
	private var runs = 0
	private var analysis: (flag: CancelFlag, task: Task<Void, Never>)?
	private let cancelled = CancelFlag()
	/// The pane's own directory under the temporary one, holding one
	/// subdirectory per render.
	private var outputRoot: URL

	// MARK: What is shown

	private(set) var view: View = .mix
	/// Stems switched off from the pane, by layer, kept across renders.
	/// The stems switched off, kept with the song so every pane of it shows
	/// the same switches.
	private var silenced: Set<String> {
		get { SongPlaybackHub.shared.silenced(of: url) }
		set { SongPlaybackHub.shared.setSilenced(newValue, of: url) }
	}
	/// The layers the caret lights, kept so a new render lights the same.
	private var lit: Set<String> = []
	private var ticker: Timer?
	private var lastError: String?
	/// The errors behind `lastError`, for the strip's click.
	private var lastDiagnostics: [SongRender.Diagnostic] = []
	private var isSettled = false
	private var whenSettled: [() -> Void] = []

	private static let deadline: TimeInterval = 300
	private static let debounce: TimeInterval = 0.4

	init(url: URL, sourceText: @escaping () -> String?) {
		self.url = url
		self.file = url
		self.sourceText = sourceText
		executable = SongRender.executable()
		outputRoot = SongRender.outputRoot(for: url)
		// What a process that is gone left behind: see `SongRender.outputRoot`.
		for stale in SongRender.staleRenderDirectories() {
			try? FileManager.default.removeItem(at: stale)
		}
		super.init(color: Theme.current.editorBackground)
		colourSource = { Theme.current.editorBackground }
		NotificationCenter.default.addObserver(
			self, selector: #selector(songPlaybackChanged(_:)),
			name: .abydosSongPlaybackChanged, object: nil
		)
		build()
		ScaledControls.register(self)

		if executable == nil {
			show(failure: SongRender.missingMessage)
			lastError = SongRender.missingMessage
			// Nothing is coming, and a driver waiting for it should be told so.
			settle()
		} else {
			show(notice: "Waiting to render \(url.lastPathComponent)…")
			whenShown = { [weak self] in self?.start() }
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Renders what the pane is showing, or reads back the render it kept.
	private func start() {
		// The files it was read from last time, so the fingerprint asks about
		// all of them.
		sources.begin(song: url, files: (SongRenderCache.shared.manifest(for: url)?.sources ?? []).map {
			URL(fileURLWithPath: $0)
		})
		// The last render of this song, when nothing it is made of has changed
		// since: the pane before this one was torn down with its tab, and
		// rendering again would be twenty seconds for nothing.
		let now = sources.fingerprint(of: url)
		if let kept = SongRenderCache.shared.entry(for: url, fingerprint: now) {
			fingerprint = now
			infoLabel.stringValue = info(kept.info)
			load(directory: kept.directory, manifest: kept.manifest, mix: kept.files[0], kept: kept)
		} else {
			render()
		}
	}

	/// Plays another song in this pane: the song that includes the tab's file.
	///
	/// Asked for 2026-09-16 — "the main song is no longer shown when navigating
	/// to an include file" — since a kit or a set of patterns has no tracks and
	/// renders to silence on its own. The tab keeps its text and its gutter;
	/// what it plays is the song it belongs to.
	func showSong(at song: URL) {
		guard executable != nil, FilePath.canonical(song) != FilePath.canonical(url) else { return }
		SongPlaybackHub.shared.release(url, pane: self)
		pending?.cancel()
		analysis?.flag.set()
		stopRendering()
		let wasPlaying = rendered?.playback.isPlaying == true
		rendered = nil
		if wasPlaying { onPlayingChanged?(false) }
		onPlayhead?(nil, false)
		url = song
		outputRoot = SongRender.outputRoot(for: song)
		sources.begin(song: song, files: [])
		fingerprint = nil
		isSettled = false
		show(notice: "Waiting to render \(song.lastPathComponent)…")
		if window != nil { start() } else { whenShown = { [weak self] in self?.start() } }
	}

	/// What the header says, with the song's name when it is not the tab's.
	private func info(_ said: String) -> String {
		FilePath.canonical(url) == FilePath.canonical(file) ? said : "\(url.lastPathComponent) · \(said)"
	}

	deinit {
		pending?.cancel()
		cancelled.set()
		analysis?.flag.set()
		ticker?.invalidate()
		if let running, running.isRunning { running.terminate() }
		// The playback and its engine: a pane that went with its split, or with
		// the tab switching to source, must not keep sounding — unless another
		// pane of the same song still is, which the hub knows. The render itself
		// stays, in `SongRenderCache`, for the next pane on this file.
		MainActor.assumeIsolated { SongPlaybackHub.shared.release(url, pane: self) }
	}

	/// Stops for good: the tab is closing, or its window is.
	func tearDown() {
		cancelled.set()
		analysis?.flag.set()
		pending?.cancel()
		ticker?.invalidate()
		ticker = nil
		stopRendering()
		let wasPlaying = rendered?.playback.isPlaying == true
		// The sound belongs to the song, and another pane may still be showing
		// it; it goes with the last of them.
		SongPlaybackHub.shared.release(url, pane: self)
		if wasPlaying { onPlayingChanged?(false) }
		stoppedLine = nil
		onPlayhead?(nil, false)
	}

	// MARK: - Building

	private func build() {
		playButton = DrawnButton(symbol: "play.fill", description: "Play") { [weak self] in self?.togglePlayback() }
		playButton.tip = StyledTip.Tip(title: "Play", detail: "Space plays and pauses.")
		loopButton = DrawnButton(symbol: "repeat", description: "Loop") { [weak self] in self?.toggleLoop() }
		loopButton.tip = StyledTip.Tip(title: "Loop", detail: "Plays the song round and round.")
		timeLabel = ScaledLabel("0:00.000 / 0:00", size: 11.5, fixedDigits: true)
		infoLabel = ScaledLabel("", size: 11) { Theme.current.gitIgnored }
		// The one thing in the strip that may give way: in a narrow pane the
		// switches are worth more than the peak level, and a label that would
		// not compress pushed *Both* off the right edge in the first capture.
		infoLabel.lineBreakMode = .byTruncatingTail
		infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		fitButton = DrawnButton(title: "Fit") { [weak self] in self?.canvas.fit() }
		exportButton = DrawnButton(symbol: "square.and.arrow.up", description: "Export") { [weak self] in
			self?.showExportMenu()
		}
		exportButton.tip = StyledTip.Tip(
			title: "Export", detail: "The mix, or the mix and its stems, as WAV, FLAC or M4A, beside the song."
		)
		fitButton.tip = StyledTip.Tip(title: "Show the whole song", detail: "Pinch or ⌥-scroll to zoom; scroll to move along.")
		fitButton.isEnabled = false
		viewChoice = DrawnChoice(segments: [.words("Mix"), .words("Stems")], selectedIndex: 0) { [weak self] index in
			self?.show(View(rawValue: index) ?? .mix)
		}
		modeChoice = DrawnChoice(
			segments: [.words("Wave"), .words("Spectrum"), .words("Both")],
			selectedIndex: AudioCanvas.Mode.both.rawValue
		) { [weak self] index in
			self?.canvas.mode = AudioCanvas.Mode(rawValue: index) ?? .both
		}
		playButton.isEnabled = false
		loopButton.isEnabled = false

		let spacer = NSView()
		spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
		strip = NSStackView(views: [playButton, loopButton, timeLabel, infoLabel, spacer, exportButton, viewChoice, fitButton, modeChoice])
		strip.orientation = .horizontal
		strip.alignment = .centerY
		applyStripMetrics()

		canvas.onSeek = { [weak self] seconds in self?.seek(to: seconds) }
		canvas.onWindowChanged = { [weak self] in
			guard let self else { return }
			self.fitButton.isEnabled = self.canvas.isZoomed
		}
		canvas.onToggleLane = { [weak self] index in self?.toggleLane(at: index) }
		canvas.onRevealLane = { [weak self] index in self?.revealLane(at: index) }

		errorStrip.isHidden = true
		errorStrip.onClick = { [weak self] in
			guard let self, let place = self.lastDiagnostics.first(where: { $0.line != nil }),
			      let line = place.line else { return }
			self.onRevealLine?(line, place.column ?? 1)
		}

		failureText.isEditable = false
		failureText.isSelectable = true
		failureText.drawsBackground = false
		failureText.textContainerInset = NSSize(width: 14, height: 12)
		failureText.autoresizingMask = [.width]
		failureText.isVerticallyResizable = true
		failureText.isHorizontallyResizable = false
		failureText.textContainer?.widthTracksTextView = true
		failureScroll.documentView = failureText
		failureScroll.drawsBackground = false
		failureScroll.hasVerticalScroller = true
		failureScroll.scrollerStyle = .overlay
		failureScroll.isHidden = true

		noticeLabel.alignment = .center
		noticeLabel.lineBreakMode = .byTruncatingMiddle
		noticeLabel.maximumNumberOfLines = 1

		for view in [strip, canvas, errorStrip, failureScroll, noticeLabel] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		NSLayoutConstraint.activate([
			strip.topAnchor.constraint(equalTo: topAnchor),
			strip.leadingAnchor.constraint(equalTo: leadingAnchor),
			strip.trailingAnchor.constraint(equalTo: trailingAnchor),
			heights.height(strip, design: 40),

			errorStrip.topAnchor.constraint(equalTo: strip.bottomAnchor),
			errorStrip.leadingAnchor.constraint(equalTo: leadingAnchor),
			errorStrip.trailingAnchor.constraint(equalTo: trailingAnchor),

			canvas.topAnchor.constraint(equalTo: errorStrip.bottomAnchor),
			canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
			canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
			canvas.bottomAnchor.constraint(equalTo: bottomAnchor),

			failureScroll.topAnchor.constraint(equalTo: canvas.topAnchor),
			failureScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
			failureScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
			failureScroll.bottomAnchor.constraint(equalTo: bottomAnchor),

			noticeLabel.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
			noticeLabel.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
			noticeLabel.widthAnchor.constraint(lessThanOrEqualTo: canvas.widthAnchor, constant: -64),
		])
	}

	private func applyStripMetrics() {
		strip.spacing = Theme.current.scaled(10)
		strip.setCustomSpacing(Theme.current.scaled(4), after: playButton)
		strip.setCustomSpacing(Theme.current.scaled(6), after: viewChoice)
		strip.edgeInsets = NSEdgeInsets(top: 0, left: Theme.current.scaled(10), bottom: 0, right: Theme.current.scaled(10))
	}

	func applyTheme() {
		applyStripMetrics()
		canvas.applyTheme()
		errorStrip.applyTheme()
	}

	// MARK: - Watching the files

	private func fileChanged() {
		pending?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.renderIfChanged() }
		pending = work
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: work)
	}

	private func renderIfChanged() {
		guard sources.fingerprint(of: url) != fingerprint else { return }
		render()
	}

	// MARK: - Rendering

	/// Stops the render that is going, if one is.
	///
	/// **Asked whether it is running.** `Process.terminate()` on a process that
	/// has not been launched raises an Objective-C exception — "task not
	/// launched" — which nothing here catches, and the app goes with `SIGABRT`.
	/// The render is started on another queue a moment after `running` is set,
	/// so anything that stopped it inside that moment killed the app: reported
	/// 2026-09-16, "it seems to crash (without any report) as soon as I play /
	/// navigate through the song files", and the crash's last Foundation frame
	/// is `_signalRunningTask`. Navigating to an included file made it likely,
	/// since the pane then starts again on another song at once.
	private func stopRendering() {
		if let running, running.isRunning { running.terminate() }
		running = nil
	}

	/// Runs `mat` on the file. A run still going is stopped first: a render is
	/// a computation with no state to corrupt, unlike a package build, so the
	/// newest text wins at once.
	private func render() {
		guard let executable else { return }
		stopRendering()
		fingerprint = sources.fingerprint(of: url)
		runs += 1
		// Named at random rather than by count: two panes on one song in one
		// process share the root, and would otherwise both write `run-1`.
		let directory = outputRoot.appendingPathComponent(
			"run-" + UUID().uuidString.prefix(8), isDirectory: true
		)
		do {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		} catch {
			show(failure: "Nowhere to render into: \(error.localizedDescription)")
			return
		}

		let line = SongRender.command(
			executable: executable, song: url, output: directory, cache: SongRender.cacheDirectory(for: url)
		)
		let invocation = UserShell.invocation(for: line)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: invocation.executable)
		process.arguments = invocation.arguments
		process.currentDirectoryURL = url.deletingLastPathComponent()
		let output = Pipe()
		let errors = Pipe()
		process.standardOutput = output
		process.standardError = errors
		process.standardInput = FileHandle.nullDevice

		guard ToolProcesses.shared.adopt(process, as: "Song render") else {
			show(failure: ToolProcesses.shared.tooManyMessage)
			return
		}
		running = process
		spin(true)
		if rendered == nil { show(notice: "Rendering \(url.lastPathComponent)…") }

		let watchdog = DispatchWorkItem { [weak self] in
			guard process.isRunning else { return }
			process.terminate()
			DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
				if process.isRunning { kill(process.processIdentifier, SIGKILL) }
			}
			guard let self, self.running === process else { return }
			self.running = nil
			self.spin(false)
			self.finish(output: "mat did not finish within \(Int(Self.deadline)) seconds.", status: -1, directory: directory)
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.deadline, execute: watchdog)

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			var said = ""
			do {
				try process.run()
				let captured = ProcessPipes.drainText(process, out: output, err: errors)
				said = captured.stdout + "\n" + captured.stderr
			} catch {
				said = error.localizedDescription
			}
			ToolProcesses.shared.forget(process)
			let status = process.terminationStatus
			let report = said
			DispatchQueue.main.async {
				watchdog.cancel()
				guard let self else { return }
				guard self.running === process else {
					// Replaced by a newer render: what this one wrote is not wanted.
					try? FileManager.default.removeItem(at: directory)
					return
				}
				self.running = nil
				self.spin(false)
				self.finish(output: report, status: status, directory: directory)
			}
		}
	}

	private func finish(output: String, status: Int32, directory: URL) {
		let manifestURL = directory.appendingPathComponent(SongRender.stemsDirectory).appendingPathComponent(SongRender.manifestName)
		let mixURL = directory.appendingPathComponent(SongRender.mixName)
		guard status == 0,
		      let data = try? Data(contentsOf: manifestURL),
		      let manifest = try? SongRender.manifest(from: data),
		      FileManager.default.fileExists(atPath: mixURL.path)
		else {
			try? FileManager.default.removeItem(at: directory)
			failed(with: SongRender.complaint(in: output), diagnostics: SongRender.diagnostics(in: output))
			return
		}
		lastError = nil
		lastDiagnostics = []
		errorStrip.isHidden = true
		infoLabel.stringValue = info(Self.info(of: manifest, rendered: SongRender.renderedLine(in: output)))
		// A render that found more files than were being fingerprinted: this
		// render is of them, and it is not a change to render again for.
		if sources.adopt(manifest.sources, of: url) { fingerprint = sources.fingerprint(of: url) }
		load(directory: directory, manifest: manifest, mix: mixURL, kept: nil)
	}

	/// The sound stays; the error goes over it. Unless there was never a
	/// sound, in which case the error is all there is to show.
	private func failed(with complaint: String, diagnostics: [SongRender.Diagnostic] = []) {
		lastError = complaint
		lastDiagnostics = diagnostics
		if rendered == nil {
			show(failure: complaint)
			settle()
			return
		}
		errorStrip.show(complaint.split(whereSeparator: \.isNewline).first.map(String.init) ?? complaint)
		errorStrip.isHidden = false
		settle()
	}

	private static func info(of manifest: SongRender.Manifest, rendered: String?) -> String {
		var parts = ["\(Int(manifest.tempo.rounded())) bpm"]
		if manifest.meter.count == 2 { parts.append("\(manifest.meter[0])/\(manifest.meter[1])") }
		parts.append("\(manifest.layers.count) stem\(manifest.layers.count == 1 ? "" : "s")")
		// `peak -1.0 dBFS`, out of the render's own summary line.
		if let rendered, let peak = rendered.range(of: "peak ") {
			let rest = rendered[peak.upperBound...]
			if let end = rest.range(of: ",") { parts.append("peak " + rest[..<end.lowerBound]) }
		}
		return parts.joined(separator: " · ")
	}

	/// Puts a render on: the new playback takes the old one's place and
	/// state, the old files go, and the stems are read for the drawing.
	///
	/// - Parameter kept: the cache's entry when this render is the last one
	///   rather than a new one, with whatever of it has been read already.
	private func load(directory: URL, manifest: SongRender.Manifest, mix: URL, kept: SongRenderCache.Entry?) {
		let stems = manifest.layers.map {
			directory.appendingPathComponent(SongRender.stemsDirectory).appendingPathComponent($0.file)
		}
		let files = [mix] + stems
		let playback: AudioPlayback
		do {
			// One playback per song, borrowed: see `SongPlaybackHub`.
			playback = try SongPlaybackHub.shared.playback(of: url, files: files, for: self)
		} catch {
			try? FileManager.default.removeItem(at: directory)
			failed(with: "The render could not be opened: \(error.localizedDescription)")
			return
		}
		if kept == nil {
			SongRenderCache.shared.store(SongRenderCache.Entry(
				fingerprint: fingerprint ?? sources.fingerprint(of: url), directory: directory, manifest: manifest,
				files: files, info: infoLabel.stringValue, overviews: Array(repeating: nil, count: files.count)
			), for: url)
		}

		let previous = rendered
		// The hub carried what the old playback was doing into the new one —
		// where it was, and its loop — so nothing here moves the playhead.
		playback.onStopped = { [weak self] in
			guard let self else { return }
			self.playingChanged()
			SongPlaybackHub.shared.said(self.url)
		}

		rendered = Rendered(directory: directory, manifest: manifest, files: files, playback: playback)
		applyVolumes()
		// The previous render's directory is the cache's to delete, which it
		// did when the new one was stored.

		canvas.duration = playback.duration
		canvas.barSeconds = manifest.barSeconds
		canvas.sections = manifest.sections
		if previous == nil { canvas.fit() }
		playButton.isEnabled = true
		loopButton.isEnabled = true
		show(notice: nil)
		failureScroll.isHidden = true
		playingChanged()
		// The lanes at once, named and empty, so ten stems of neon.song are ten
		// headers with switches while their waves are still being read, rather
		// than a blank pane for the seconds that takes.
		// What is already drawn: the last render's readings when this is that
		// render, and otherwise the drawing of every stem whose layer key did
		// not change — the mix is always new.
		overviews = kept?.overviews ?? ([nil] + manifest.layers.map {
			SongRenderCache.shared.overview(ofStem: $0.key, of: url)
		})
		rebuildLanes()
		analyse(files: files, manifest: manifest, directory: directory)
		// Settled at the render, not at the drawing: the sound is what the pane
		// is for, and a driver reading the lanes before they are read sees
		// them marked unread rather than waiting on a dozen stems of neon.song.
		settle()
	}

	/// Reads the mix and every stem not yet read off the main thread, and
	/// draws them as they land — the mix first, since it is what the pane
	/// opens on. Each reading goes to the cache too, for the next pane.
	private func analyse(files: [URL], manifest: SongRender.Manifest, directory: URL) {
		analysis?.flag.set()
		let flag = CancelFlag()
		var overviews = self.overviews
		let task = Task { @MainActor [weak self] in
			for (index, file) in files.enumerated() where overviews[index] == nil {
				let reading = await Task.detached(priority: .userInitiated) { () -> AudioOverview? in
					try? AudioAnalysis.read(file) { flag.isSet }
				}.value
				guard let self, !flag.isSet else { return }
				overviews[index] = reading
				if let reading {
					SongRenderCache.shared.read(reading, at: index, of: directory, for: self.url)
					if index > 0, manifest.layers.indices.contains(index - 1) {
						SongRenderCache.shared.remember(reading, ofStem: manifest.layers[index - 1].key, of: self.url)
					}
				}
				self.showLanes(overviews, manifest: manifest)
			}
		}
		analysis = (flag, task)
	}

	private var overviews: [AudioOverview?] = []
	private var manifest: SongRender.Manifest? { rendered?.manifest }

	private func showLanes(_ overviews: [AudioOverview?], manifest: SongRender.Manifest) {
		self.overviews = overviews
		rebuildLanes()
	}

	private func rebuildLanes() {
		guard let manifest else { return }
		switch view {
		case .mix:
			canvas.showsHeaders = false
			canvas.setLanes([SongCanvas.Lane(name: "mix", tracks: [], overview: overviews.first ?? nil)])
		case .stems:
			canvas.showsHeaders = true
			canvas.setLanes(manifest.layers.enumerated().map { index, layer in
				SongCanvas.Lane(
					name: layer.name, tracks: layer.tracks,
					overview: overviews.indices.contains(index + 1) ? overviews[index + 1] : nil,
					isEnabled: !silenced.contains(layer.name),
					isLit: lit.contains(layer.name)
				)
			})
		}
	}

	// MARK: - The view and the switches

	func show(_ new: View) {
		guard new != view else { return }
		view = new
		viewChoice.selectedIndex = new.rawValue
		applyVolumes()
		rebuildLanes()
	}

	/// The mix is heard in the mix view and the stems in the stems view, each
	/// stem at its share or at nothing; every file plays throughout, so a
	/// switch of view or of stem is instant and keeps the place.
	///
	/// The share is `Manifest.stemGain`: the stems sum to the mix before its
	/// limiter, which peaks above the ceiling on any loud song, and the sum
	/// of them at full would clip in the engine. Turned down to the ceiling,
	/// the stems view is the song at the level the limiter would have left
	/// it, short of the limiter's own squeeze.
	private func applyVolumes() {
		guard let rendered else { return }
		rendered.playback.setVolume(view == .mix ? 1 : 0, ofVoice: 0)
		let share = Float(rendered.manifest.stemGain)
		for (index, layer) in rendered.manifest.layers.enumerated() {
			let heard = view == .stems && !silenced.contains(layer.name)
			rendered.playback.setVolume(heard ? share : 0, ofVoice: index + 1)
		}
	}

	private func toggleLane(at index: Int) {
		guard let manifest, manifest.layers.indices.contains(index) else { return }
		let name = manifest.layers[index].name
		if silenced.contains(name) { silenced.remove(name) } else { silenced.insert(name) }
		applyVolumes()
		canvas.setEnabled(!silenced.contains(name), at: index)
	}

	/// `wobble:<layer>`: a press on the layer's switch that drags a pixel.
	func wobbleSwitchForTesting(layer name: String) {
		guard let manifest, let index = manifest.layers.firstIndex(where: { $0.name == name }) else { return }
		canvas.wobbleSwitchForTesting(lane: index)
	}

	func setLane(_ name: String, enabled: Bool) {
		guard let manifest, let index = manifest.layers.firstIndex(where: { $0.name == name }) else { return }
		if enabled != !silenced.contains(name) { toggleLane(at: index) }
	}

	/// The first track of the layer, in the source.
	private func revealLane(at index: Int) {
		guard let manifest, manifest.layers.indices.contains(index), let text = sourceText() else { return }
		let source = SongSource.parse(text)
		let layer = manifest.layers[index]
		guard let track = source.tracks.first(where: { layer.tracks.contains($0.name) })
			?? source.tracks(inLayer: layer.name).first else { return }
		onRevealLine?(track.lines.lowerBound, 1)
	}

	// MARK: - The caret

	/// The caret moved to `line`: the stems the block it is in makes light up.
	///
	/// A parse of the buffer per caret move, which is a line scan of a file of
	/// a few hundred lines — measured in the tests' fixture at well under a
	/// millisecond — and it runs on the caret, not the keystroke's redraw.
	func caretMoved(toLine line: Int) {
		guard let text = sourceText() else { return }
		let layers = SongSource.parse(text).layers(litByCaretAt: line)
		guard layers != lit else { return }
		lit = layers
		canvas.setLit(layers)
	}

	// MARK: - Playing

	private var playback: AudioPlayback? { rendered?.playback }
	private var isPlaying: Bool { playback?.isPlaying == true }
	private var duration: Double { playback?.duration ?? 0 }

	func togglePlayback() {
		guard let playback else { return }
		if playback.isPlaying {
			playback.pause()
		} else {
			// Playing on from a breakpoint: from where it stopped, which is not
			// reached again, so the same breakpoint does not stop it twice.
			stoppedLine = nil
			lastFollowed = playback.currentSeconds
			playback.play()
			if playback.isPlaying { OnePlayer.started(self) }
		}
		playingChanged()
	}

	/// Another pane of the same song, sharing its playback.
	func makesTheSameSound(as other: PlaysMedia) -> Bool {
		guard let playback, let song = other as? SongPreviewView else { return false }
		return song.playbackForTesting === playback
	}

	func pauseForAnother() {
		guard let playback, playback.isPlaying else { return }
		playback.pause()
		playingChanged()
	}

	private func toggleLoop() {
		guard let playback else { return }
		playback.isLooping.toggle()
		// Off means the whole song again: a loop over a few bars is the thing
		// being turned off, not a hidden setting kept for the next press.
		if !playback.isLooping { setLoop(nil) }
		loopButton.isLit = playback.isLooping
		followPlayback()
	}

	/// The stretch the loop plays, in seconds, or nil for the whole song. The
	/// playback's, so every pane of the song draws the same band.
	var loopRange: ClosedRange<Double>? { playback?.loopRange }

	/// Loops a stretch of the song and plays it: a section, or the bars where
	/// one line is heard.
	///
	/// Asked for 2026-09-16, to change a sound and hear it at once: "play one
	/// section in a loop and while playing make the changes to the sounds". A
	/// render landing under it keeps the loop, since the loop is seconds of the
	/// song rather than anything the render owns.
	func setLoop(_ range: ClosedRange<Double>?) {
		canvas.loopRange = range
		guard let playback else { return }
		playback.loopRange = range
		SongPlaybackHub.shared.said(url)
		if let range {
			playback.isLooping = true
			if playback.currentSeconds < range.lowerBound || playback.currentSeconds >= range.upperBound {
				playback.seek(toSeconds: range.lowerBound)
			}
			if !playback.isPlaying {
				playback.play()
				if playback.isPlaying { OnePlayer.started(self) }
			}
			playingChanged()
		}
		loopButton.isLit = playback.isLooping
		followPlayback()
	}

	/// A line's bar, option-clicked in the source: loop where that line is
	/// heard. The same line again turns the loop off.
	func loopFromSource(_ range: ClosedRange<Double>) {
		if let loopRange, abs(loopRange.lowerBound - range.lowerBound) < 0.01, abs(loopRange.upperBound - range.upperBound) < 0.01 {
			playback?.isLooping = false
			setLoop(nil)
			return
		}
		setLoop(range)
	}

	/// A click on a timeline bar in the source: the playhead goes there, and a
	/// zoomed canvas follows it.
	func seekFromSource(_ seconds: Double) {
		let target = min(duration, max(0, seconds))
		canvas.playhead = target
		canvas.follow(target)
		seek(to: target)
	}

	private func seek(to seconds: Double) {
		// A seek is not playing past anything between here and there.
		lastFollowed = seconds
		stoppedLine = nil
		playback?.seek(toSeconds: seconds)
		followPlayback()
	}

	/// A tick while the song plays, whoever started it.
	private func refreshTicker() {
		ticker?.invalidate()
		ticker = nil
		guard isPlaying else { return }
		let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.followPlayback() }
		}
		RunLoop.main.add(timer, forMode: .common)
		ticker = timer
	}

	/// Another pane of this song did something to it: the same sound, so the
	/// same playhead, the same switches, the same loop, the same button.
	@objc private func songPlaybackChanged(_ notification: Notification) {
		guard (notification.object as? NSString) as String? == FilePath.canonical(url) else { return }
		canvas.loopRange = playback?.loopRange
		loopButton.isLit = playback?.isLooping ?? false
		rebuildLanes()
		refreshTicker()
		followPlayback()
		onPlayingChanged?(isPlaying)
	}

	private func playingChanged() {
		SongPlaybackHub.shared.said(url)
		refreshTicker()
		followPlayback()
		onPlayingChanged?(isPlaying)
		if isPlaying {
			onPlaybackChange?(.playing)
		} else if let playback, playback.duration > 0, !playback.isLooping, playback.currentSeconds >= playback.duration - 0.05 {
			onPlaybackChange?(.ended)
		} else if playback != nil {
			onPlaybackChange?(.stopped(file: stoppedLine == nil ? nil : stoppedFile, line: stoppedLine))
		}
	}

	private func followPlayback() {
		let now = playback?.currentSeconds ?? 0
		let from = lastFollowed
		lastFollowed = now
		// Stopped exactly on the breakpoint's moment, whatever of the frame
		// since the last tick was already heard past it.
		if isPlaying, let playback, let from, let stop = breakpointAhead?(from, now) {
			playback.pause()
			playback.seek(toSeconds: stop.seconds)
			lastFollowed = stop.seconds
			stoppedFile = stop.file
			stoppedLine = stop.line
			playingChanged()
			return
		}
		onPlayhead?(playback == nil ? nil : now, isPlaying || stoppedLine != nil)
		if isPlaying { onPlaybackChange?(.tick) }
		// The pane's own drawing only while it is shown; the source's marks and
		// breakpoints above go on, since an included file's tab can be in front.
		guard window != nil || !isPlaying else { return }
		canvas.playhead = now
		if isPlaying { canvas.follow(now) }
		var clock = "\(AudioFileView.clock(now, milliseconds: true)) / \(AudioFileView.clock(duration))"
		if let manifest, manifest.barSeconds > 0 {
			let place = manifest.bar(at: now)
			clock += " · bar \(place.bar)"
		}
		if let loopRange, let manifest, manifest.barSeconds > 0 {
			let from = manifest.bar(at: loopRange.lowerBound).bar
			let to = manifest.bar(at: max(loopRange.lowerBound, loopRange.upperBound - 0.001)).bar
			clock += from == to ? " · loop bar \(from)" : " · loop bars \(from)–\(to)"
		}
		timeLabel.stringValue = clock
		playButton.setSymbol(isPlaying ? "pause.fill" : "play.fill", description: isPlaying ? "Pause" : "Play")
	}

	// MARK: - Keyboard and window

	/// Right-click anywhere on the pane: the Export menu.
	override func menu(for event: NSEvent) -> NSMenu? {
		executable == nil ? nil : exportMenu()
	}

	override var acceptsFirstResponder: Bool { true }

	override func keyDown(with event: NSEvent) {
		let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
		if event.keyCode == 49, modifiers.isEmpty {
			togglePlayback()
			return
		}
		if event.keyCode == 123 || event.keyCode == 124, modifiers.isEmpty || modifiers == .shift {
			let step = modifiers == .shift ? AudioFileView.fineStep : AudioFileView.step
			jump(by: event.keyCode == 123 ? -step : step)
			return
		}
		super.keyDown(with: event)
	}

	func jump(by seconds: Double) {
		guard duration > 0 else { return }
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

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		if window != nil { followPlayback() }
	}

	// MARK: - What the pane says

	private func show(notice: String?) {
		noticeLabel.stringValue = notice ?? ""
		noticeLabel.isHidden = notice == nil || rendered != nil
	}

	private func show(failure said: String) {
		show(notice: nil)
		failureText.textStorage?.setAttributedString(NSAttributedString(
			string: said,
			attributes: [
				.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
				.foregroundColor: Theme.current.editorText,
			]
		))
		failureScroll.isHidden = false
	}

	private func spin(_ turning: Bool) {
		if turning {
			guard activity == nil else { return }
			activity = PaneActivityView.install(over: self, paneIsEmpty: rendered == nil)
		} else {
			activity?.finish()
			activity = nil
		}
	}

	// MARK: - Driving

	private func settle() {
		isSettled = true
		let waiting = whenSettled
		whenSettled = []
		waiting.forEach { $0() }
	}

	/// Runs `then` once a render has landed and been read, or failed.
	func whenRendered(_ then: @escaping () -> Void) {
		if isSettled { then() } else { whenSettled.append(then) }
	}

	/// Whether this pane is the one whose sound is being heard, which is the one
	/// that says where the playhead is for every tab of its song.
	var isTheOneSounding: Bool {
		OnePlayer.isCurrent(self) || (playback?.isPlaying == true)
	}

	/// The sound this pane is playing, to tell two panes of one song apart from
	/// two songs.
	var playbackForTesting: AudioPlayback? { playback }

	/// What the loop is playing, for a driven run.
	var loopRangeForTesting: String {
		loopRange.map { String(format: "%.2f-%.2f", $0.lowerBound, $0.upperBound) } ?? "whole"
	}

	/// Where the song is, for the debugger.
	var currentSecondsForDebugger: Double { playback?.currentSeconds ?? canvas.playhead }

	/// The debugger's continue.
	func playForDebugger() {
		if !isPlaying { togglePlayback() }
	}

	/// The line a breakpoint stopped the song on, for a driven run.
	var stoppedLineForTesting: Int? { stoppedLine }

	func seekForTesting(seconds: Double) {
		canvas.playhead = seconds
		seek(to: seconds)
	}

	func playForTesting() { if !isPlaying { togglePlayback() } }
	func loopForTesting() { if playback?.isLooping == false { toggleLoop() } }

	func showForTesting(mode name: String) {
		guard let mode = AudioCanvas.Mode.allCases.first(where: { $0.name == name }) else { return }
		modeChoice.selectedIndex = mode.rawValue
		canvas.mode = mode
	}

	var runsForTesting: Int { runs }

	/// What a driven run reads instead of listening.
	var reportForTesting: String {
		let state: String
		if running != nil {
			state = rendered == nil ? "rendering" : "rerendering"
		} else if rendered != nil {
			state = "rendered"
		} else if !failureScroll.isHidden {
			state = "failed"
		} else {
			state = "waiting"
		}
		let lanes = canvas.lanes.map { lane in
			"\(lane.name):\(lane.isEnabled ? "on" : "off")\(lane.isLit ? "*" : "")"
				+ (lane.overview == nil ? "(unread)" : "")
		}
		let error = lastError.map { "\"\($0.split(whereSeparator: \.isNewline).first ?? "")\"" } ?? "none"
		return "SONG: \(url.lastPathComponent) state=\(state) runs=\(runs) view=\(view.name) "
			+ "mode=\(canvas.mode.name) \(isPlaying ? "playing" : "paused")"
			+ String(format: " playhead=%.2f duration=%.2f", playback?.currentSeconds ?? 0, duration)
			+ " tempo=\(Int(manifest?.tempo ?? 0)) stems=\(manifest?.layers.count ?? 0)"
			+ " lanes=[\(lanes.joined(separator: " "))] lit=[\(lit.sorted().joined(separator: " "))]"
			+ " loop=\(playback?.isLooping == true ? "on" : "off")"
			+ String(format: " window=%.3f+%.3fs", canvas.windowStart, canvas.windowSpan)
			+ " clock=\"\(timeLabel.stringValue)\""
			// Which stems `mat` read back instead of rendering, and how many of
			// the pane's drawings were reused rather than read again — the two
			// halves of what makes a save quick.
			+ " cached=[\((manifest?.layers.filter(\.cached).map(\.name) ?? []).joined(separator: " "))]"
			+ " drawn=\(overviews.compactMap { $0 }.count)/\(overviews.count)"
			+ " info=\"\(infoLabel.stringValue)\" error=\(error)"
	}
}

/// One line of complaint over a pane, clickable.
///
/// Drawn rather than an `NSButton`, so it takes the theme's colours and the
/// zoom the way everything else in the strip does.
final class ErrorStripView: NSView {
	private let label = ScaledLabel("", size: 11) { Theme.current.editorText }
	private var height: NSLayoutConstraint!
	var onClick: (() -> Void)?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		label.lineBreakMode = .byTruncatingTail
		label.maximumNumberOfLines = 1
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)
		height = heightAnchor.constraint(equalToConstant: Theme.current.scaled(22))
		NSLayoutConstraint.activate([
			height,
			label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(10)),
			label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Theme.current.scaled(10)),
			label.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		applyTheme()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func show(_ text: String) {
		label.stringValue = "⚠︎ " + text
		label.toolTip = text
	}

	func applyTheme() {
		height.constant = Theme.current.scaled(22)
		layer?.backgroundColor = Theme.current.gitConflict.withAlphaComponent(0.18).cgColor
	}

	override var isHidden: Bool {
		didSet { height.constant = isHidden ? 0 : Theme.current.scaled(22) }
	}

	override func mouseDown(with event: NSEvent) { onClick?() }

	override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
