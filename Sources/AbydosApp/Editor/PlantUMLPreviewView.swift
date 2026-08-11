import AbydosKit
import AppKit

/// The diagram a PlantUML file describes.
///
/// PlantUML is not bundled and never installed on anybody's behalf — it is a
/// Java program that draws with Graphviz, and the copy already on the machine
/// is the one the diagrams were written against. When there is none, the pane
/// says so and says what to install, which is the one thing somebody needs at
/// that moment.
///
/// Rendering runs off the main thread and is debounced, because it means
/// starting a JVM: a diagram redrawn on every keystroke would start one every
/// keystroke, and the editor would be typing through treacle.
///
/// What comes back is a drawing rather than a picture — `PlantUML.previewFormat`
/// — and that is what makes it sharp: a PNG is sized in points, so on a Retina
/// screen every pixel of it is stretched over two.
final class PlantUMLPreviewView: DiagramPaneView {
	private var running: Process?
	private var pending: DispatchWorkItem?
	/// What was last drawn, so an unchanged document is not drawn again.
	private var lastSource: String?

	/// How long to wait for a picture before saying so. Long, because the first
	/// run of a container image fetches it.
	private static let deadline: TimeInterval = 30

	/// Whether the runtime's caveat has been said in this run of the app. Once
	/// is the right number: it is the same sentence for every pane.
	private static var saidCaveat = false

	/// Whichever PlantUML this project can reach, looked up once per view: the
	/// answer does not change while a window is open, and looking it up per
	/// keystroke means walking the PATH per keystroke.
	private let tool: PlantUML.Tool?

	/// The project the diagram belongs to, for finding the same PlantUML again
	/// when the picture is exported.
	private let projectRoot: URL?

	/// Which way round the render under way is drawing, or nil when the file
	/// stated its own look. Kept because the two routes below both need it and
	/// the second is started from inside a `Task`.
	private var theme: DiagramTheme?

	/// - Parameter projectRoot: whose `.abydos/tools.json` may name an image to
	///   draw with, so a machine with no PlantUML on it still shows diagrams.
	init(projectRoot: URL?) {
		self.projectRoot = projectRoot
		let images = ToolImages.resolve(
			project: projectRoot.map { ToolImages.inProject($0) } ?? ToolImages(),
			settings: ToolImages(images: Settings.shared.toolImages)
		)
		tool = PlantUML.discover(
			image: images.image(for: "plantuml"),
			runtimePreference: ContainerRuntime.Preference(rawValue: Settings.shared.containerRuntime)
				?? .automatic
		)
		super.init()
		if tool == nil { notice = PlantUML.installHint }
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		pending?.cancel()
		running?.terminate()
	}

	// MARK: - Exporting

	/// Nothing to export before there is a diagram in the file.
	override var isReadyToExport: Bool {
		lastSource.map { PlantUML.hasDiagram($0) } ?? false
	}

	override var statedLook: String? {
		lastSource.flatMap { PlantUML.statedLook(in: $0) }
	}

	/// Writes the picture beside the file, in the format asked for.
	override func export(
		_ format: DiagramFormat, theme: DiagramTheme? = nil, editable: Bool = false,
		then: (@Sendable ([URL]) -> Void)? = nil
	) {
		guard let fileURL else { return }
		DiagramExportCommand.run(
			url: fileURL, source: lastSource, format: format, theme: theme ?? appTheme,
			projectRoot: projectRoot, then: then
		)
	}

	/// The palette changed under an open diagram. PlantUML draws dark or light
	/// when it is *run*, so this is a whole render again rather than a repaint.
	override func themeChanged() {
		guard let source = lastSource else { return }
		lastSource = nil
		show(source)
	}

	/// Draws this diagram, after a pause in the typing.
	func show(_ source: String) {
		guard tool != nil else { return }
		guard source != lastSource else { return }

		pending?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.render(source) }
		pending = work
		// Long enough that a burst of typing renders once, short enough that a
		// pause reads as "it is drawing" rather than "it is stuck".
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
	}

	private func render(_ source: String) {
		guard let tool else { return }
		lastSource = source

		// Nothing written yet is not an error to draw: PlantUML refuses text
		// with no `@start`, and a file somebody has just opened is exactly that.
		guard PlantUML.hasDiagram(source) else {
			image = nil
			notice = "Nothing to draw yet — a diagram starts with @startuml."
			needsDisplay = true
			return
		}

		// Once, and out loud, when the runtime is the one whose cleanup is not
		// proven: a container that may be left behind is worth knowing about
		// before eleven of them wedge the runtime, and it is not something the
		// pane itself can say — a notice here is replaced by the picture a second
		// later.
		if case let .image(_, runtime) = tool, let caveat = runtime.caveat, !Self.saidCaveat {
			Self.saidCaveat = true
			Toast.post("Diagrams are being drawn by Apple's container", detail: caveat, kind: .warning)
		}

		// The file wins. A diagram that says `!theme` or sets its own background
		// colour is drawn exactly as it asks, and the caption says so — a picture
		// that stays light in a dark window has to be able to explain itself.
		let stated = PlantUML.statedLook(in: source)
		let theme: DiagramTheme? = stated == nil ? appTheme : nil
		self.theme = theme
		paper = Self.paper(for: theme)
		caption = stated.map(DiagramLook.notice(stated:))

		// Only one at a time: a diagram that takes a second to draw would
		// otherwise leave a JVM running for every keystroke that started one.
		running?.terminate()
		spinner.startAnimation(nil)
		notice = "Drawing with \(tool.description)…"
		image = nil
		needsDisplay = true

		// An image that is not on the machine yet is fetched first, once,
		// however many panes ask. This is the ordinary case the first time
		// anybody opens a project that names one — and a pull with nothing on
		// screen is indistinguishable from a tool that has hung, so it says
		// what it is doing while it happens.
		if case let .image(container, runtime) = tool {
			// The notice in this pane says *what* is happening and has room for one
			// sentence; the terminal tab holds what the runtime is saying while it
			// does it. Both, because they answer different questions — and the tab
			// is there at all because nothing says a diagram tool must be a pull:
			// a recipe can be written for anything, and then this is minutes. 0459.
			let arrival = ImageArrival(
				image: container.image, tool: "PlantUML", project: projectRoot
			)
			// Taken here rather than inside the task: the task is not on the main
			// actor and `arrival` is, so the sinks have to be lifted out of it
			// while this still is.
			let watch = arrival.watch
			Task { [weak self] in
				let outcome = await ContainerImageStore.shared.ensure(
					container.image,
					using: runtime,
					progress: { message in
						watch.step?(message)
						DispatchQueue.main.async {
							guard let self, self.tool == tool else { return }
							self.notice = message
							self.needsDisplay = true
						}
					},
					output: watch.output
				)
				if case let .failed(reason) = outcome {
					await MainActor.run {
						arrival.failed(reason)
						guard let self else { return }
						self.spinner.stopAnimation(nil)
						self.running = nil
						self.notice = reason
						self.needsDisplay = true
					}
					return
				}
				await MainActor.run { arrival.arrived() }

				// One PlantUML kept warm, asked over HTTP: a container and a JVM
				// per diagram is two seconds, and the same picture from a server
				// that is already up is a twentieth of that. Nil means it could
				// not be — no server, a runtime whose containers cannot be
				// removed again, a diagram too large for a request line — and the
				// answer to all of those is the render this app has always done,
				// which works and is only slow.
				if let drawn = await PlantUMLServers.shared.render(
					source, image: container.image, using: runtime,
					format: PlantUML.previewFormat, theme: theme
				) {
					await MainActor.run {
						guard let self, self.lastSource == source else { return }
						self.spinner.stopAnimation(nil)
						self.running = nil
						self.finish(drawn: drawn, complaint: "")
					}
					return
				}

				await MainActor.run {
					guard let self, self.lastSource == source else { return }
					self.draw(source, with: tool)
				}
			}
			return
		}
		draw(source, with: tool)
	}

	/// Runs the tool over the diagram. The image it needs is already here.
	private func draw(_ source: String, with tool: PlantUML.Tool) {
		// A name for the container, when there is a container. Killing the `run`
		// process does not stop what it started — `--rm` only fires for a
		// container that ends of its own accord — so the render has to be able to
		// name the thing it wants removed. Registered before it is started and
		// removed on every way out of here, including the deadline's.
		var containerName: String?
		if case let .image(_, runtime) = tool {
			let name = ToolContainers.mint("plantuml")
			ToolContainers.shared.register(name, runtime: runtime)
			containerName = name
		}
		// The same format the warm server is asked for. Two ways of drawing the
		// same diagram that disagreed about it would make sharpness depend on
		// which one answered, which is the kind of fault that reads as
		// intermittent.
		let run = PlantUML.invocation(
			for: tool, format: PlantUML.previewFormat, name: containerName, theme: theme
		)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: run.executable)
		process.arguments = run.arguments

		let input = Pipe()
		let output = Pipe()
		let errors = Pipe()
		process.standardInput = input
		process.standardOutput = output
		process.standardError = errors
		running = process

		// Registered before it is started, so it is ended with the app however
		// the app ends — including the way that runs no `deinit` at all. The
		// refusal is worth showing: a dozen tools running and none finishing is
		// a runtime that has stopped answering, not a diagram that is hard.
		guard ToolProcesses.shared.adopt(process) else {
			running = nil
			if let containerName { ToolContainers.shared.releaseInBackground(containerName) }
			spinner.stopAnimation(nil)
			notice = ToolProcesses.tooManyMessage
			needsDisplay = true
			return
		}

		// A deadline, because the thing being run may never answer: a container
		// runtime whose service is not up accepts the command and then waits
		// for a daemon that is never coming, and a preview that spins for ever
		// tells somebody nothing about why. Generous, since the first run of an
		// image has to fetch it first.
		// The process is stopped whether or not this view is still here to be
		// told about it. It used to be the first thing the deadline checked —
		// `guard let self` — so a pane closed while its render hung left the
		// render running, and a container that hangs hangs for ever: eleven of
		// them were found on this machine, the oldest a day old, and enough of
		// them wedge the runtime's service so that every later render hangs too.
		// That is the shape of "it spawned endless containers".
		let watchdog = DispatchWorkItem { [weak self] in
			guard process.isRunning else { return }
			process.terminate()
			// And then for certain. A runtime waiting on a service that is not
			// coming does not always answer a polite ask, and what is left
			// behind is exactly what this deadline exists to prevent.
			DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
				if process.isRunning { kill(process.processIdentifier, SIGKILL) }
			}
			// Neither signal touches the container, which was the whole of why
			// this deadline never actually stopped anything: the process goes and
			// the container carries on holding the runtime. It is removed by name
			// instead, and that is the part that works.
			if let containerName { ToolContainers.shared.releaseInBackground(containerName) }
			guard let self, self.running === process else { return }
			self.spinner.stopAnimation(nil)
			self.running = nil
			self.image = nil
			self.notice = "\(tool.description) did not answer within \(Int(Self.deadline)) seconds."
			self.needsDisplay = true
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.deadline, execute: watchdog)

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			var drawn = Data()
			var complaint = ""
			do {
				try process.run()
				// The diagram goes in and both pipes come out at the same time.
				// Anything in sequence here deadlocks — a diagram larger than
				// the pipe leaves PlantUML waiting to be given the rest, and a
				// complaint longer than the pipe leaves it waiting to finish
				// saying it while this waits for the picture.
				let captured = ProcessPipes.drain(
					process, out: output, err: errors,
					input: Data(source.utf8), stdin: input
				)
				drawn = captured.stdout
				complaint = String(decoding: captured.stderr, as: UTF8.self)
			} catch {
				complaint = error.localizedDescription
			}

			ToolProcesses.shared.forget(process)
			// `--rm` has usually taken it already, this being a container that
			// ended by itself; the removal then fails with "no such container",
			// which is the right state arriving by another route. What it costs
			// is one command, off this thread, after the picture is in hand.
			if let containerName { ToolContainers.shared.releaseInBackground(containerName) }
			DispatchQueue.main.async {
				guard let self else { return }
				watchdog.cancel()
				self.spinner.stopAnimation(nil)
				self.running = nil
				self.finish(drawn: drawn, complaint: complaint)
			}
		}
	}

	private func finish(drawn: Data, complaint: String) {
		let tool = self.tool
		// An error picture is still a picture, and it names the line that is
		// wrong — which is more useful in the pane than any message here.
		let said = complaint.trimmingCharacters(in: .whitespacesAndNewlines)
		let otherwise: String
		if !said.isEmpty {
			// Nothing came back at all, which is what a PlantUML without
			// Graphviz looks like. Whatever it said on the way out is the only
			// clue there is.
			otherwise = said
		} else if case .image = tool {
			// Naming the command is the whole message: a container runtime that
			// is installed but not running fails silently, and "drew nothing"
			// gives nobody anywhere to look.
			otherwise = "\(tool?.description ?? "The image") produced no picture. "
				+ "Is the container runtime running?"
		} else {
			otherwise = "PlantUML drew nothing. Graphviz may be missing."
		}
		show(picture: drawn, otherwise: otherwise)
	}
}
