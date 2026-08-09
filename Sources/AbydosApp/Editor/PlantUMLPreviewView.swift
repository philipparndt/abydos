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
final class PlantUMLPreviewView: NSView {
	/// The picture, or nil while there is none to show.
	private var image: NSImage?
	private var pixelSize: CGSize = .zero
	/// What to say instead of a picture: no PlantUML, or nothing drawn yet.
	private var notice: String?

	private let spinner = NSProgressIndicator()
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

	/// - Parameter projectRoot: whose `.abydos/tools.json` may name an image to
	///   draw with, so a machine with no PlantUML on it still shows diagrams.
	init(projectRoot: URL?) {
		let images = ToolImages.resolve(
			project: projectRoot.map { ToolImages.inProject($0) } ?? ToolImages(),
			settings: ToolImages(images: Settings.shared.toolImages)
		)
		tool = PlantUML.discover(
			image: images.image(for: "plantuml"),
			runtimePreference: ContainerRuntime.Preference(rawValue: Settings.shared.containerRuntime)
				?? .automatic
		)
		super.init(frame: .zero)
		spinner.style = .spinning
		spinner.controlSize = .small
		spinner.isDisplayedWhenStopped = false
		spinner.translatesAutoresizingMaskIntoConstraints = false
		addSubview(spinner)
		NSLayoutConstraint.activate([
			spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
			// Above the message rather than behind it: both are shown while a
			// diagram is being drawn, and centred on the same point the text
			// runs straight through the spinner.
			spinner.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18),
		])

		if tool == nil { notice = PlantUML.installHint }
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		pending?.cancel()
		running?.terminate()
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
			Task { [weak self] in
				let outcome = await ContainerImageStore.shared.ensure(
					container.image,
					using: runtime,
					progress: { message in
						DispatchQueue.main.async {
							guard let self, self.tool == tool else { return }
							self.notice = message
							self.needsDisplay = true
						}
					}
				)
				if case let .failed(reason) = outcome {
					await MainActor.run {
						guard let self else { return }
						self.spinner.stopAnimation(nil)
						self.running = nil
						self.notice = reason
						self.needsDisplay = true
					}
					return
				}

				// One PlantUML kept warm, asked over HTTP: a container and a JVM
				// per diagram is two seconds, and the same picture from a server
				// that is already up is a twentieth of that. Nil means it could
				// not be — no server, a runtime whose containers cannot be
				// removed again, a diagram too large for a request line — and the
				// answer to all of those is the render this app has always done,
				// which works and is only slow.
				if let drawn = await PlantUMLServers.shared.render(
					source, image: container.image, using: runtime
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
		let run = PlantUML.invocation(for: tool, name: containerName)
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
		if PlantUML.isPicture(drawn), let picture = NSImage(data: drawn) {
			image = picture
			pixelSize = picture.representations.first.map {
				CGSize(width: $0.pixelsWide, height: $0.pixelsHigh)
			} ?? picture.size
			notice = nil
		} else {
			image = nil
			// Nothing came back at all, which is what a PlantUML without
			// Graphviz looks like. Whatever it said on the way out is the only
			// clue there is.
			let said = complaint.trimmingCharacters(in: .whitespacesAndNewlines)
			if !said.isEmpty {
				notice = said
			} else if case .image = tool {
				// Naming the command is the whole message: a container runtime
				// that is installed but not running fails silently, and "drew
				// nothing" gives nobody anywhere to look.
				notice = "\(tool?.description ?? "The image") produced no picture. "
					+ "Is the container runtime running?"
			} else {
				notice = "PlantUML drew nothing. Graphviz may be missing."
			}
		}
		needsDisplay = true
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.fill()

		if let image {
			let box = ImageFit.rect(
				image: pixelSize,
				in: CGSize(width: max(0, bounds.width - 32), height: max(0, bounds.height - 32))
			).offsetBy(dx: 16, dy: 16)
			guard box.width > 0, box.height > 0 else { return }
			image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
			return
		}

		guard let notice else { return }
		let text = NSAttributedString(string: notice, attributes: [
			.font: Theme.current.uiFont(12),
			.foregroundColor: Theme.current.sidebarText.withAlphaComponent(0.85),
			.paragraphStyle: {
				let style = NSMutableParagraphStyle()
				style.alignment = .center
				return style
			}(),
		])
		let width = max(80, bounds.width - 64)
		let height = text.boundingRect(
			with: NSSize(width: width, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin]
		).height
		// Below the spinner's place, whether or not one is turning: the message
		// sits in the same spot either way, so it does not jump when the
		// drawing finishes.
		let top = (bounds.height - height) / 2 + 12
		text.draw(with: NSRect(x: 32, y: top, width: width, height: height),
		          options: [.usesLineFragmentOrigin])
	}
}
