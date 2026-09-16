import AppKit
import AbydosKit

/// Running `mat` over a song, and picking up what it writes.
///
/// One run at a time: a newer one stops the one going, since a render is a
/// computation with no state to corrupt and the newest text wins. What it
/// writes arrives in two goes — the mix, as soon as `mat` has finished writing
/// it and gone on to the stems, and then everything with the manifest — so the
/// song can be heard while the stems are still being written.
///
/// Its own object because it is the pane's other half: a process, a debounce,
/// a watchdog and a fingerprint, none of which is about drawing a song.
@MainActor
final class SongRenderRun {
	/// How long `mat` gets before the run is given up on.
	static let deadline: TimeInterval = 300
	/// How long a change waits, so a save mid-keystroke renders once.
	static let debounce: TimeInterval = 0.4

	/// How many renders have been started, for a driven run.
	private(set) var runs = 0
	private var running: Process?
	private var pending: DispatchWorkItem?
	/// The sources as they were when the last render started.
	private var fingerprint: String?
	/// This pane's own directory under the temporary one, one subdirectory per
	/// render.
	var outputRoot: URL

	/// The mix, written and no longer growing, while the stems still are.
	var onMix: (_ mix: URL, _ directory: URL) -> Void = { _, _ in }
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
	func render(song: URL, executable: String, fingerprint: String) {
		stop()
		self.fingerprint = fingerprint
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
			executable: executable, song: song, output: directory, cache: SongRender.cacheDirectory(for: song)
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

		let watchdog = DispatchWorkItem { [weak self] in
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
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.deadline, execute: watchdog)
		watchForTheMix(in: directory, of: process)

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
				self.onBusy(false)
				self.onFinished(report, status, directory)
			}
		}
	}

	/// The mix, while the stems are still being written.
	///
	/// Asked for 2026-09-16: "it seems that we always need the complete
	/// rendering till something is shown", and "ideally we can start early
	/// before the render is even complete". `mat` writes the mix, then a stem
	/// per layer, then the manifest — which is what the pane waited for, so a
	/// song of ten stems was silent for the whole of it. The mix alone is the
	/// song, so it is handed over as soon as it has stopped growing.
	private func watchForTheMix(in directory: URL, of process: Process) {
		let mix = directory.appendingPathComponent(SongRender.mixName)
		var lastSize: Int64 = -1
		func look() {
			guard running === process, showing() != directory else { return }
			let size = (try? mix.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? -1
			// Written, and no longer growing: `mat` has gone on to the stems.
			if size > 0, size == lastSize {
				onMix(mix, directory)
				return
			}
			lastSize = size
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { look() }
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { look() }
	}
}
