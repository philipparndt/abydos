import AppKit
import AbydosKit

/// Running `mat` over a song, and picking up what it writes.
///
/// One run at a time: a newer one stops the one going, since a render is a
/// computation with no state to corrupt and the newest text wins.
///
/// What it writes arrives while it is being written. `mat render --stream`
/// writes the mix a stretch at a time and says how much of it can be read in
/// `mix.stream.json`, which this polls: the first stretch is a fraction of a
/// second in, and the rest of the song and its stems land behind it.
///
/// Its own object because it is the pane's other half: a process, a debounce,
/// a watchdog and a fingerprint, none of which is about drawing a song.
@MainActor
final class SongRenderRun {
	/// How long `mat` gets before the run is given up on.
	nonisolated static let deadline: TimeInterval = 300
	/// How long a change waits, so a save mid-keystroke renders once.
	nonisolated static let debounce: TimeInterval = 0.4
	/// How often the mix is asked how much of it has been written. Short
	/// because the first stretch is what the wait for a sound now is.
	nonisolated static let streamPoll: TimeInterval = 0.1

	/// How many renders have been started, for a driven run.
	private(set) var runs = 0
	private var running: Process?
	private var pending: DispatchWorkItem?
	/// The watchdog of the run that is going, cancelled when it ends: kept here
	/// rather than captured by the closure that waits for `mat`, which is a
	/// `@Sendable` one and a work item is not.
	private var watchdog: DispatchWorkItem?
	/// The sources as they were when the last render started.
	private var fingerprint: String?
	/// When the last render started: what it read is what was on disk then.
	private(set) var startedAt = Date.distantPast
	/// This pane's own directory under the temporary one, one subdirectory per
	/// render.
	var outputRoot: URL

	/// More of the mix has been written, and how much: the pane plays it while
	/// the rest of the song renders.
	var onStream: (_ mix: URL, _ directory: URL, _ stream: SongRender.Stream) -> Void = { _, _, _ in }
	/// The run ended: what it said, how it ended, and where it wrote.
	var onFinished: (_ output: String, _ status: Int32, _ directory: URL) -> Void = { _, _, _ in }
	/// Nothing could be run: nowhere to write, or too many tools already.
	var onRefused: (String) -> Void = { _ in }
	/// A render started or ended, for the spinner.
	var onBusy: (Bool) -> Void = { _ in }
	/// Whether anything is showing yet, which decides the notice.
	var isShowingSomething: () -> Bool = { false }
	/// The directory whatever is showing was rendered into.
	var showing: () -> URL? = { nil }
	var onNotice: (String) -> Void = { _ in }

	init(outputRoot: URL) {
		self.outputRoot = outputRoot
	}

	/// Whether `mat` is running now.
	var isRendering: Bool { running != nil }

	/// Whether this fingerprint is the one the last render was of.
	func isRendered(_ fingerprint: String) -> Bool {
		self.fingerprint == fingerprint
	}

	func note(fingerprint: String?) {
		self.fingerprint = fingerprint
	}

	/// A file changed: render once the writing has settled.
	func changed(after debounce: TimeInterval = SongRenderRun.debounce, then render: @escaping () -> Void) {
		pending?.cancel()
		let work = DispatchWorkItem(block: render)
		pending = work
		DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
	}

	/// Stops the render that is going, if one is.
	///
	/// **Asked whether it is running.** `Process.terminate()` on a process that
	/// has not been launched raises an Objective-C exception — "task not
	/// launched" — which nothing catches, and the app goes with `SIGABRT`. The
	/// render is started on another queue a moment after `running` is set, so
	/// anything that stopped it inside that moment killed the app: reported
	/// 2026-09-16, "it seems to crash (without any report) as soon as I play /
	/// navigate through the song files", with `_signalRunningTask` as the last
	/// Foundation frame. Navigating to an included file made it likely, since
	/// the pane then starts again on another song at once.
	func stop() {
		if let running, running.isRunning { running.terminate() }
		running = nil
	}

	func cancelPending() {
		pending?.cancel()
	}

	/// Runs `mat` on `song`, with `fingerprint` as what this render is of.
	///
	/// - Parameter streaming: whether this `mat` writes the mix as it renders,
	///   which is what the pane plays before the render is done. A `mat` from
	///   before a5f7d05 refuses the flag, so the pane asks first.
	func render(song: URL, executable: String, fingerprint: String, streaming: Bool) {
		stop()
		self.fingerprint = fingerprint
		startedAt = Date()
		runs += 1
		// Named at random rather than by count: two panes on one song in one
		// process share the root, and would otherwise both write `run-1`.
		let directory = outputRoot.appendingPathComponent(
			"run-" + UUID().uuidString.prefix(8), isDirectory: true
		)
		do {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		} catch {
			onRefused("Nowhere to render into: \(error.localizedDescription)")
			return
		}

		let line = SongRender.command(
			executable: executable, song: song, output: directory,
			cache: SongRender.cacheDirectory(for: song), streaming: streaming
		)
		let invocation = UserShell.invocation(for: line)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: invocation.executable)
		process.arguments = invocation.arguments
		process.currentDirectoryURL = song.deletingLastPathComponent()
		let output = Pipe()
		let errors = Pipe()
		process.standardOutput = output
		process.standardError = errors
		process.standardInput = FileHandle.nullDevice

		guard ToolProcesses.shared.adopt(process, as: "Song render") else {
			onRefused(ToolProcesses.shared.tooManyMessage)
			return
		}
		running = process
		onBusy(true)
		if !isShowingSomething() { onNotice("Rendering \(song.lastPathComponent)…") }

		let watching = DispatchWorkItem { [weak self] in
			guard process.isRunning else { return }
			process.terminate()
			DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
				if process.isRunning { kill(process.processIdentifier, SIGKILL) }
			}
			guard let self, self.running === process else { return }
			self.running = nil
			self.onBusy(false)
			self.onFinished("mat did not finish within \(Int(Self.deadline)) seconds.", -1, directory)
		}
		watchdog = watching
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.deadline, execute: watching)
		if streaming { watchTheStream(in: directory, of: process) }

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
				guard let self else { return }
				self.watchdog?.cancel()
				guard self.running === process else {
					// Replaced by a newer render: what this one wrote is not wanted.
					try? FileManager.default.removeItem(at: directory)
					return
				}
				self.running = nil
				self.onBusy(false)
				self.onFinished(report, status, directory)
			}
		}
	}

	/// The mix while it is being written.
	///
	/// Asked for 2026-09-16: "it seems that we always need the complete
	/// rendering till something is shown", "ideally we can start early before
	/// the render is even complete", and "it takes way too long till a song can
	/// be started and also seems to render twice". `mat` a5f7d05 renders in
	/// order of time and keeps `mix.stream.json` beside the mix saying how many
	/// frames of it are there; this reads it while the run goes, and every
	/// reading that says more than the last one is handed over.
	///
	/// The reading is always behind the file, never ahead: `mat` writes the
	/// samples, then the JSON, under a temporary name and renamed.
	private func watchTheStream(in directory: URL, of process: Process) {
		let mix = directory.appendingPathComponent(SongRender.mixName)
		let status = SongRender.streamStatus(beside: mix)
		var last: SongRender.Stream?
		func look() {
			guard running === process else { return }
			if let data = try? Data(contentsOf: status), let stream = SongRender.stream(from: data),
			   stream != last, stream.frames > 0 {
				last = stream
				onStream(mix, directory, stream)
				// The whole song: what follows is the stems and the manifest,
				// and `onFinished` puts those on.
				if stream.finished { return }
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + Self.streamPoll) { look() }
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.streamPoll) { look() }
	}
}
