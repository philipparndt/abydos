import AbydosKit
import AppKit
import GoSTL
import SwiftUI

/// The shape a Cadova model makes, beside the code that describes it.
///
/// **Every other preview in this app is given a file and draws it. This one has
/// no file until it has built and run a program.** Cadova is a Swift library, so
/// a model is an executable target in a package; `swift run <product>` in the
/// package root writes a `.3mf` beside the package, and *that* is what the
/// viewer opens. So the pane is two things in sequence: a run, and then the same
/// `ModelContainerView` a `.scad` gets.
///
/// The three decisions 0499 asked for, in the order they arise:
///
///  1. **Which tabs get one.** Not "a `.swift` file" — nearly every `.swift` ever
///     written is not a model. The sources of an *executable target that depends
///     on Cadova*, which is what `CadovaModel` answers and what the manifest is
///     the only honest source of. All of that target's sources and not only the
///     one with `Model(…)` in it, because running the target is what makes the
///     shape and a helper file changes it exactly as much.
///  2. **Where the `.3mf` is.** Read out of what the run said —
///     `Wrote model to /…/hexholder.3mf`. Cadova names the file after the model
///     *inside the code*, so the path cannot be known in advance, and the two
///     candidates were parsing the output and watching the directory. Parsing
///     wins on an argument the item did not have: the failure requirement means
///     the output is captured *anyway*, so reading a line of it is free, and it
///     names the file exactly where a watch would have to filter everything
///     `swift build` writes. `CadovaRun.newestModel(in:since:)` is the fallback
///     for a Cadova that words the line differently — one directory listing after
///     a run that has already ended, which is not a watcher.
///  3. **How often.** When a file in the target's source directory *changes on
///     disk*, coalesced by FSEvents and debounced by another 0.4 s, with any run
///     still going terminated first. On disk rather than on a keystroke because
///     the compiler reads the disk: building an unsaved buffer would show the
///     shape of the last save while claiming to show this one. On the directory
///     rather than on this tab's document because the target has other files in
///     it, and a `git checkout` is a change too.
///
/// **What it costs somebody else.** Not frames: `swift run` is a subprocess, so
/// even the 46 s cold build measured for 0499 is 46 s in which this window draws
/// normally — which is the argument 0483 could not make for a `.scad`, where
/// OpenSCAD renders on the main actor. What it costs instead is SwiftPM's
/// exclusive lock on `.build`: a preview build makes the user's own
/// `swift build` in a terminal wait for it, and the other way round. A warm run
/// is about two seconds, and two builds of one package contending is the same
/// wait two terminals would have, so it is a cost worth naming rather than one
/// worth designing around.
final class CadovaPreviewView: DelayedPaneView {
	private let model: CadovaModel

	/// The run in flight.
	private var running: Process?
	/// A change that arrived while a run was going, to be honoured when it ends.
	/// See `sourcesChanged()` for why this is a queue rather than a kill.
	private var wantsRerun = false
	/// The debounce between a file changing and a run starting.
	private var pending: DispatchWorkItem?
	/// Watching the target's sources. Empty until the pane has been shown, so a
	/// tab nobody stopped at starts no stream.
	private var watchers: [FileSystemWatcher] = []
	/// What the sources were when the last run started, so an event that is not
	/// an edit does not start another. See `CadovaModel.sourceFingerprint()`.
	private var fingerprint: String?

	/// The model on screen, so a rerun writing the same path can leave the viewer
	/// alone and let GoSTL's own file watcher reload it.
	private var showing: URL?
	/// Where the viewer lives once there is something to show.
	private var viewer: ModelContainerView?

	/// One line, in the middle, with the spinner over it.
	private var notice: String?
	/// Why there is no model, when there is a reason worth reading. Shown in the
	/// text view rather than as a notice: a compiler says four lines, not four
	/// words.
	private let failureText = NSTextView()
	private let failureScroll = NSScrollView()
	private let spinner = NSProgressIndicator()

	/// How many runs have finished, for the driver that watches this.
	private(set) var runsForTesting = 0

	/// How long a run may take before it is stopped.
	///
	/// Generous, and it has to be: the cold build for 0499's spike was 46 s idle
	/// and 53 s with four agents building beside it, and the very first run of a
	/// package resolves its dependencies over the network first. A deadline is
	/// here at all for the same reason PlantUML's is — a process that never
	/// answers leaves a pane spinning for ever and a `swift-frontend` running
	/// after the tab has gone.
	private static let deadline: TimeInterval = 300

	/// Long enough that saving three files in a row is one run, short enough that
	/// a save reads as "it is building". The same 0.4 s everything else in this
	/// editor debounces by, on top of FSEvents' own 0.25 s of coalescing.
	private static let debounce: TimeInterval = 0.4

	init(model: CadovaModel) {
		self.model = model
		super.init(color: Theme.current.editorBackground)

		spinner.style = .spinning
		spinner.controlSize = .small
		spinner.isDisplayedWhenStopped = false
		spinner.translatesAutoresizingMaskIntoConstraints = false
		addSubview(spinner)
		NSLayoutConstraint.activate([
			spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
			spinner.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18),
		])

		failureText.isEditable = false
		// Selectable, which is the point of showing the compiler rather than
		// summarising it: the line somebody wants is one they will paste.
		failureText.isSelectable = true
		failureText.drawsBackground = false
		failureText.textContainerInset = NSSize(width: 14, height: 12)
		failureScroll.documentView = failureText
		failureScroll.drawsBackground = false
		failureScroll.hasVerticalScroller = true
		failureScroll.scrollerStyle = .overlay
		failureScroll.isHidden = true
		addSubview(failureScroll)

		notice = "Waiting to build \(model.product)…"

		// The lazy guard, inherited: nothing starts until this pane has been on
		// screen for `startAfter`, and nothing starts at all if it leaves first.
		whenShown = { [weak self] in
			self?.watchSources()
			self?.run()
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		pending?.cancel()
		// The one place a build *is* killed, and it is killed knowing what that
		// costs: a half-stopped `swift build` leaves `.build` inconsistent and the
		// next build of that package is cold. The alternative is worse — a build
		// nobody is waiting for, holding SwiftPM's lock and a dozen
		// `swift-frontend` processes, started by a tab that has been closed. That
		// is the fault PlantUML's watchdog records, one process size larger.
		running?.terminate()
	}

	// MARK: - Starting

	/// FSEvents over the target's sources, and nothing else.
	///
	/// Not the package: `swift build` writes thousands of files into `.build`
	/// under it, and a watch there would rebuild because it had just built. The
	/// target's own directory holds nothing but somebody's code.
	private func watchSources() {
		for directory in model.sources {
			let watcher = FileSystemWatcher(root: directory) { [weak self] _ in
				DispatchQueue.main.async { self?.sourcesChanged() }
			}
			watcher.start()
			watchers.append(watcher)
		}
	}

	/// Something under the target's sources happened. Whether it was an edit is a
	/// separate question, asked after the debounce.
	private func sourcesChanged() {
		pending?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.runIfSourcesChanged() }
		pending = work
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: work)
	}

	private func runIfSourcesChanged() {
		// **The event is not the question.** FSEvents reports a file's inode
		// metadata changing, and compiling a file changes its access time — so
		// this fires while the build that is running reads the very sources it is
		// building. Watched in the app: the pane rebuilt itself in a loop, and the
		// two builds then broke `.build` between them.
		guard model.sourceFingerprint() != fingerprint else { return }

		// **A run in flight is left alone.** The obvious thing — kill it, start the
		// newer one — is what produced
		// `module file 'std_errno_h-….pcm' not found: module file not found`
		// in the app, twice: terminating the shell does not stop `swift-build` and
		// its frontends, so the killed build carried on writing `.build` while its
		// replacement wrote it too, and the *next* five builds after that were cold
		// while SwiftPM rebuilt what had been half-written. A package build is not
		// a render: it has a build directory to keep consistent, and there is no
		// signal that makes stopping one safe. So a change during a build is
		// remembered and honoured when it ends, which coalesces a burst of saves
		// into exactly one extra run — the same outcome cancelling was for, by a
		// means that does not corrupt anything.
		guard running == nil else {
			wantsRerun = true
			return
		}
		run()
	}

	// MARK: - The run

	private func run() {
		wantsRerun = false
		// Taken before the build starts, not after: everything the build touches
		// from here on is the build's own doing.
		fingerprint = model.sourceFingerprint()

		let invocation = UserShell.invocation(for: model.command)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: invocation.executable)
		process.arguments = invocation.arguments
		// 0498 made this a promise rather than an accident, with a requirement and
		// a test behind it: `swift run` runs in the package root, so the `.3mf`
		// lands beside the package and this is the directory to look in.
		process.currentDirectoryURL = model.packageDirectory

		let output = Pipe()
		let errors = Pipe()
		process.standardOutput = output
		process.standardError = errors
		// Nothing is going to answer a question a startup file asks.
		process.standardInput = FileHandle.nullDevice

		guard ToolProcesses.shared.adopt(process) else {
			show(failure: ToolProcesses.tooManyMessage)
			return
		}
		running = process

		spinner.startAnimation(nil)
		show(notice: "Building \(model.product)…")

		let started = Date()
		let watchdog = DispatchWorkItem { [weak self] in
			guard process.isRunning else { return }
			process.terminate()
			DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
				if process.isRunning { kill(process.processIdentifier, SIGKILL) }
			}
			guard let self, self.running === process else { return }
			self.spinner.stopAnimation(nil)
			self.running = nil
			self.show(failure: "\(self.model.command) did not finish within "
				+ "\(Int(Self.deadline)) seconds.")
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.deadline, execute: watchdog)

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			var said = ""
			do {
				try process.run()
				// Both pipes at once. In sequence this deadlocks: a build says more
				// than a pipe holds, on both streams — the model's path comes out of
				// stdout and every one of six hundred progress lines out of stderr.
				let captured = ProcessPipes.drainText(
					process, out: output, err: errors,
					onOutput: { piece in
						// The last line of a build, while it builds. A cold one is
						// most of a minute, and a pane that says only "Building…"
						// for that long is indistinguishable from a pane that has
						// hung.
						guard let line = CadovaRun.lastLine(of: piece) else { return }
						DispatchQueue.main.async {
							guard let self, self.running === process else { return }
							self.show(notice: line)
						}
					}
				)
				said = captured.stdout + "\n" + captured.stderr
			} catch {
				said = error.localizedDescription
			}

			ToolProcesses.shared.forget(process)
			let status = process.terminationStatus
			let report = said
			DispatchQueue.main.async {
				watchdog.cancel()
				guard let self, self.running === process else { return }
				self.running = nil
				self.spinner.stopAnimation(nil)
				self.finish(output: report, status: status, started: started)
			}
		}
	}

	private func finish(output: String, status: Int32, started: Date) {
		runsForTesting += 1

		// A save that arrived while this was building. Honoured now rather than
		// dropped: what is on screen after this is the shape of code that has
		// since changed, and nothing else is going to notice.
		defer {
			if wantsRerun {
				wantsRerun = false
				// Through the fingerprint check again rather than straight into
				// `run()`: what the watcher saw during a build is usually the build.
				runIfSourcesChanged()
			}
		}

		guard let written = CadovaRun.wroteModel(in: output)
			?? CadovaRun.newestModel(in: model.packageDirectory, since: started),
			FileManager.default.fileExists(atPath: written.path)
		else {
			// **A failure must arrive as a failure.** 0484 is the item about what
			// happens when it does not, and its whole complaint is a shape on screen
			// that nobody's code describes and no message anywhere. That pane is
			// GoSTL's and cannot be fixed from here; this one is ours, so the model
			// goes and the compiler takes its place. Keeping the last good shape
			// under a banner was the alternative, and it is the same lie with a
			// caption: what somebody is looking at is still not their file.
			show(failure: CadovaRun.complaint(in: output))
			return
		}

		// The same file again, which is the ordinary case: GoSTL watches the model
		// it has open and reloads it, so there is nothing to rebuild here. Tearing
		// the viewer down and putting a new one up would throw away the camera, and
		// turning the part round to look at the change is the whole of the work.
		if showing == written, viewer != nil, status == 0 {
			show(notice: nil)
			return
		}

		showing = written
		show(notice: nil)
		mountViewer(for: written)
	}

	/// Puts the 3D viewer in, on the file the run wrote.
	private func mountViewer(for fileURL: URL) {
		viewer?.removeFromSuperview()
		let container = ModelContainerView(color: Theme.current.editorBackground)
		// Nothing to wait for: this pane has already been on screen for its own
		// delay and has just spent seconds building. The lazy guard was about a
		// pane nobody stopped at, and somebody stopped at this one.
		container.startAfter = 0
		container.makeViewer = { [weak container] in
			let hosting = NSHostingView(rootView: ContentView(
				fileURL: fileURL,
				embedding: ContentView.EmbeddingOptions(
					backgroundColor: Theme.current.editorBackground,
					showsMenuPanel: false,
					snapshotHandle: { [weak container] provider in container?.snapshot = provider }
				)
			))
			// Out of Auto Layout, for the reason `makeModelView` gives: NSHostingView
			// publishes constraints from inside the window's own constraint pass, and
			// splitting the editor re-parents it during exactly that pass.
			hosting.sizingOptions = []
			hosting.translatesAutoresizingMaskIntoConstraints = true
			return hosting
		}
		container.frame = bounds
		// Under the spinner, and therefore under the failure text as well, since
		// both were added before it: a rerun spins over the model that is still on
		// screen from the last one.
		addSubview(container, positioned: .below, relativeTo: spinner)
		viewer = container
		needsLayout = true
	}

	// MARK: - What the pane says

	private func show(notice said: String?) {
		notice = said
		if said != nil { failureScroll.isHidden = true }
		needsDisplay = true
	}

	private func show(failure said: String) {
		notice = nil
		spinner.stopAnimation(nil)
		// The model goes with it. See `finish`.
		viewer?.removeFromSuperview()
		viewer = nil
		showing = nil
		failureText.textStorage?.setAttributedString(NSAttributedString(
			string: said,
			attributes: [
				.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
				.foregroundColor: Theme.current.editorText,
			]
		))
		failureScroll.isHidden = false
		needsDisplay = true
	}

	override func layout() {
		super.layout()
		viewer?.frame = bounds
		failureScroll.frame = bounds
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.fill()

		guard viewer == nil, let notice else { return }
		let text = NSAttributedString(string: notice, attributes: [
			.font: Theme.current.uiFont(12),
			.foregroundColor: Theme.current.sidebarText.withAlphaComponent(0.85),
			.paragraphStyle: {
				let style = NSMutableParagraphStyle()
				style.alignment = .center
				style.lineBreakMode = .byTruncatingMiddle
				return style
			}(),
		])
		let width = max(80, bounds.width - 64)
		let height = text.boundingRect(
			with: NSSize(width: width, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin]
		).height
		let top = (bounds.height - height) / 2 + 12
		text.draw(with: NSRect(x: 32, y: top, width: width, height: height),
		          options: [.usesLineFragmentOrigin])
	}

	// MARK: - Watched from outside

	/// What this pane is doing, in one line, for the driver.
	///
	/// A pane cannot be photographed mid-build and a model cannot be read off a
	/// screenshot, so the thing to watch is this: which of the three states it is
	/// in, which file the viewer has, and how many runs have finished.
	var reportForTesting: String {
		let state: String
		if viewer != nil {
			state = "model"
		} else if !failureScroll.isHidden {
			state = "failed"
		} else {
			state = "building"
		}
		let said = failureScroll.isHidden
			? (notice ?? "")
			: (failureText.string.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
		return "CADOVA: state=\(state) runs=\(runsForTesting) "
			+ "product=\(model.product) model=\(showing?.lastPathComponent ?? "none") "
			+ "said=\(said)"
	}
}
