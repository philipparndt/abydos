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

	private let url: URL
	private let executable: String?
	/// The text as it is in the buffer, for the block under the caret.
	private let sourceText: () -> String?
	/// The source should show a line: a lane's name was clicked, or the
	/// error strip.
	var onRevealLine: ((Int, Int) -> Void)?
	/// Told whenever playing starts or stops, so the tab can show a speaker.
	var onPlayingChanged: ((Bool) -> Void)?

	private let canvas = SongCanvas()
	private let heights = ScaledHeights()
	private var playButton: DrawnButton!
	private var loopButton: DrawnButton!
	private var fitButton: DrawnButton!
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
	private var watcher: FileSystemWatcher?
	private var fingerprint: String?
	private var runs = 0
	private var analysis: (flag: CancelFlag, task: Task<Void, Never>)?
	private let cancelled = CancelFlag()
	/// The pane's own directory under the temporary one, holding one
	/// subdirectory per render.
	private let outputRoot: URL

	// MARK: What is shown

	private(set) var view: View = .mix
	/// Stems switched off from the pane, by layer, kept across renders.
	private var silenced: Set<String> = []
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
		self.sourceText = sourceText
		executable = SongRender.executable()
		outputRoot = SongRender.outputRoot(for: url)
		// What a process that is gone left behind: see `SongRender.outputRoot`.
		for stale in SongRender.staleRenderDirectories() {
			try? FileManager.default.removeItem(at: stale)
		}
		super.init(color: Theme.current.editorBackground)
		colourSource = { Theme.current.editorBackground }
		build()
		ScaledControls.register(self)

		if executable == nil {
			show(failure: SongRender.missingMessage)
			lastError = SongRender.missingMessage
			// Nothing is coming, and a driver waiting for it should be told so.
			settle()
		} else {
			show(notice: "Waiting to render \(url.lastPathComponent)…")
			whenShown = { [weak self] in
				guard let self else { return }
				self.watch()
				// The last render of this file, when the file has not changed
				// since: the pane before this one was torn down with its tab, and
				// rendering again would be twenty seconds for nothing.
				let now = self.currentFingerprint()
				if let kept = SongRenderCache.shared.entry(for: self.url, fingerprint: now) {
					self.fingerprint = now
					self.infoLabel.stringValue = kept.info
					self.load(directory: kept.directory, manifest: kept.manifest, mix: kept.files[0], kept: kept)
				} else {
					self.render()
				}
			}
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		pending?.cancel()
		cancelled.set()
		analysis?.flag.set()
		ticker?.invalidate()
		running?.terminate()
		// The playback and its engine: a pane that went with its split, or
		// with the tab switching to source, must not keep sounding. The render
		// itself stays, in `SongRenderCache`, for the next pane on this file.
		MainActor.assumeIsolated { rendered?.playback.tearDown() }
	}

	/// Stops for good: the tab is closing, or its window is.
	func tearDown() {
		cancelled.set()
		analysis?.flag.set()
		pending?.cancel()
		ticker?.invalidate()
		ticker = nil
		running?.terminate()
		running = nil
		let wasPlaying = rendered?.playback.isPlaying == true
		rendered?.playback.tearDown()
		if wasPlaying { onPlayingChanged?(false) }
	}

	// MARK: - Building

	private func build() {
		playButton = DrawnButton(symbol: "play.fill", description: "Play") { [weak self] in self?.togglePlayback() }
		playButton.tip = StyledTip.Tip(title: "Play", detail: "Space plays and pauses.")
		loopButton = DrawnButton(symbol: "repeat", description: "Loop") { [weak self] in self?.toggleLoop() }
		loopButton.tip = StyledTip.Tip(title: "Loop", detail: "Plays the song round and round.")
		timeLabel = ScaledLabel("0:00 / 0:00", size: 11.5)
		infoLabel = ScaledLabel("", size: 11) { Theme.current.gitIgnored }
		// The one thing in the strip that may give way: in a narrow pane the
		// switches are worth more than the peak level, and a label that would
		// not compress pushed *Both* off the right edge in the first capture.
		infoLabel.lineBreakMode = .byTruncatingTail
		infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		fitButton = DrawnButton(title: "Fit") { [weak self] in self?.canvas.fit() }
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
		strip = NSStackView(views: [playButton, loopButton, timeLabel, infoLabel, spacer, viewChoice, fitButton, modeChoice])
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

	// MARK: - Watching the file

	/// The song's directory, since FSEvents watches directories; whether the
	/// song itself changed is the fingerprint's question, asked after the
	/// debounce. The samples beside it are read by the render too, and a
	/// change to one of them is a change to the sound, but the file somebody
	/// edits is the song — and a render on every write to the directory would
	/// render when the project's own tools write beside it.
	private func watch() {
		let watcher = FileSystemWatcher(root: url.deletingLastPathComponent()) { [weak self] _ in
			DispatchQueue.main.async { self?.fileChanged() }
		}
		watcher.start()
		self.watcher = watcher
	}

	private func fileChanged() {
		pending?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.renderIfChanged() }
		pending = work
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: work)
	}

	/// Size and date rather than the event: an event says something in the
	/// directory happened, and most of what happens is not the song.
	private func currentFingerprint() -> String {
		let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
		return "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values?.fileSize ?? 0)"
	}

	private func renderIfChanged() {
		guard currentFingerprint() != fingerprint else { return }
		render()
	}

	// MARK: - Rendering

	/// Runs `mat` on the file. A run still going is stopped first: a render is
	/// a computation with no state to corrupt, unlike a package build, so the
	/// newest text wins at once.
	private func render() {
		guard let executable else { return }
		if let running {
			running.terminate()
			self.running = nil
		}
		fingerprint = currentFingerprint()
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

		let line = SongRender.command(executable: executable, song: url, output: directory)
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
		infoLabel.stringValue = Self.info(of: manifest, rendered: SongRender.renderedLine(in: output))
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
			playback = try AudioPlayback(urls: files)
		} catch {
			try? FileManager.default.removeItem(at: directory)
			failed(with: "The render could not be opened: \(error.localizedDescription)")
			return
		}
		if kept == nil {
			SongRenderCache.shared.store(SongRenderCache.Entry(
				fingerprint: fingerprint ?? currentFingerprint(), directory: directory, manifest: manifest,
				files: files, info: infoLabel.stringValue, overviews: Array(repeating: nil, count: files.count)
			), for: url)
		}

		let previous = rendered
		let wasPlaying = previous?.playback.isPlaying == true
		let position = previous?.playback.currentSeconds ?? 0
		playback.isLooping = previous?.playback.isLooping ?? false
		playback.onStopped = { [weak self] in self?.playingChanged() }
		previous?.playback.tearDown()

		rendered = Rendered(directory: directory, manifest: manifest, files: files, playback: playback)
		applyVolumes()
		playback.seek(toSeconds: min(position, playback.duration))
		if wasPlaying {
			playback.play()
			if playback.isPlaying { OnePlayer.started(self) }
		}
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
		overviews = kept?.overviews ?? Array(repeating: nil, count: files.count)
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
				if let reading { SongRenderCache.shared.read(reading, at: index, of: directory, for: self.url) }
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
	/// stem at full or at nothing; every file plays throughout, so a switch of
	/// view or of stem is instant and keeps the place.
	private func applyVolumes() {
		guard let rendered else { return }
		rendered.playback.setVolume(view == .mix ? 1 : 0, ofVoice: 0)
		for (index, layer) in rendered.manifest.layers.enumerated() {
			let heard = view == .stems && !silenced.contains(layer.name)
			rendered.playback.setVolume(heard ? 1 : 0, ofVoice: index + 1)
		}
	}

	private func toggleLane(at index: Int) {
		guard let manifest, manifest.layers.indices.contains(index) else { return }
		let name = manifest.layers[index].name
		if silenced.contains(name) { silenced.remove(name) } else { silenced.insert(name) }
		applyVolumes()
		canvas.setEnabled(!silenced.contains(name), at: index)
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
			playback.play()
			if playback.isPlaying { OnePlayer.started(self) }
		}
		playingChanged()
	}

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

	private func followPlayback() {
		let now = playback?.currentSeconds ?? 0
		guard window != nil || !isPlaying else { return }
		canvas.playhead = now
		if isPlaying { canvas.follow(now) }
		var clock = "\(AudioFileView.clock(now)) / \(AudioFileView.clock(duration))"
		if let manifest, manifest.barSeconds > 0 {
			let place = manifest.bar(at: now)
			clock += " · bar \(place.bar)"
		}
		timeLabel.stringValue = clock
		playButton.setSymbol(isPlaying ? "pause.fill" : "play.fill", description: isPlaying ? "Pause" : "Play")
	}

	// MARK: - Keyboard and window

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
