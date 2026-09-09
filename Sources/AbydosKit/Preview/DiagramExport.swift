import Foundation

/// Writing a diagram out as a picture, beside the file it came from.
///
/// `diagram.puml` becomes `diagram.png` or `diagram.svg` in the same folder —
/// the format asked for, which is not necessarily the one on screen: the
/// preview draws in SVG for sharpness, and asking for a PNG has to mean a PNG.
///
/// Three things this refuses to do, each of which would otherwise produce a
/// file somebody would find later and not be able to explain:
///
///  * **Overwrite a picture nobody here drew.** A `diagram.png` that PlantUML
///    made is a previous export of this diagram and is replaced, because
///    exporting twice is the ordinary way of working. Anything else — a
///    screenshot, an asset, a photograph — is somebody's own file with an
///    unlucky name, and it stops the export with a sentence instead. The same
///    principle as a rename onto an existing name, which also refuses rather
///    than destroying, and without the modal that a thing asked for by name
///    does not deserve.
///  * **Write a picture of an error.** See `DiagramFault`.
///  * **Write half of a file's diagrams.** Everything is drawn before anything
///    is written, so a file with three diagrams in it either gains three
///    pictures or none.
public enum DiagramExport {
	/// Why an export did not happen, in one sentence.
	public struct Failure: Error, Equatable, Sendable {
		public let message: String
		public init(_ message: String) { self.message = message }
	}

	/// One `@start…@end` block, and where it begins.
	public struct Diagram: Equatable, Sendable {
		public let text: String
		/// The line its `@start` is on, counting from one.
		public let firstLine: Int

		public init(text: String, firstLine: Int) {
			self.text = text
			self.firstLine = firstLine
		}
	}

	/// How long a single picture may take once whatever draws it is here.
	///
	/// The image has already been fetched by the time anything is drawn, so this
	/// covers a JVM starting and a genuinely large diagram, not a download.
	public static let deadline: TimeInterval = 60

	// MARK: - What is in the file

	/// The diagrams a file holds, in the order they are written.
	///
	/// A `.puml` may hold several, and PlantUML ignores everything outside a
	/// block — so a block is the unit, and each is drawn on its own. Both of the
	/// ways this app draws would otherwise be wrong about a file with two in it:
	/// `-pipe` returns both pictures glued into one stream, and the HTTP route
	/// merges them into a single picture with everybody's participants in it.
	/// Neither is what `plantuml diagram.puml` writes, which is one file per
	/// diagram.
	public static func diagrams(in source: String) -> [Diagram] {
		var found: [Diagram] = []
		var collecting: [Substring] = []
		var startedAt = 0

		for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if collecting.isEmpty {
				guard trimmed.hasPrefix("@start") else { continue }
				startedAt = index + 1
				collecting = [line]
				continue
			}
			collecting.append(line)
			guard trimmed.hasPrefix("@end") else { continue }
			found.append(Diagram(text: collecting.joined(separator: "\n"), firstLine: startedAt))
			collecting = []
		}
		// A block somebody is still typing, with no `@end` yet. PlantUML draws
		// one of those quite happily, so it counts.
		if !collecting.isEmpty {
			found.append(Diagram(text: collecting.joined(separator: "\n"), firstLine: startedAt))
		}
		return found
	}

	// MARK: - Where the pictures go

	/// The file a diagram is written to, beside its source.
	///
	/// The names PlantUML's own file output uses: `diagram.png` for the first,
	/// `diagram_001.png` for the second, and so on — so a project that already
	/// refers to those names by hand finds the same files here. The name after
	/// `@startuml`, which PlantUML would also honour, is deliberately not used:
	/// `diagram.puml` exporting to something other than `diagram.png` is a rule
	/// nobody would guess from the menu item they clicked.
	/// - Parameter theme: which way round the picture is drawn. A dark one is
	///   `diagram-dark.png` and every other case is the name it always was.
	///
	/// **`-dark` and nothing else, and the name says what is in the picture.**
	/// Three things decided that. `diagram.png` keeps meaning what it has always
	/// meant, so a README that already points at it does not quietly become a
	/// dark picture the day somebody switches theme — and re-exporting light
	/// still replaces the same file rather than accumulating. `-dark` is the
	/// suffix repositories already use for the second half of a pair, because it
	/// is the one GitHub's own `#gh-dark-mode-only` convention produced. And it
	/// composes with the existing numbering rather than fighting it: a file with
	/// three diagrams in it gives `diagram-dark.png`, `diagram_001-dark.png`,
	/// `diagram_002-dark.png`, in the same order and by the same rule.
	///
	/// **A second name is not a second thing to recognise**, which is the one
	/// worry 0429 raised about it. `refusal` reads the *bytes* of whatever is
	/// already there — PlantUML's own marker, `DiagramStamp`'s, or draw.io's
	/// `mxfile` chunk — and never the name. So `diagram-dark.png` is protected
	/// and replaceable by exactly the rules `diagram.png` is, with no new stamp,
	/// no new `DiagramStamp.Tool` case, and nothing to keep in step.
	public static func destinations(
		for source: URL, format: PlantUML.Format, diagrams: Int, theme: DiagramTheme? = nil
	) -> [URL] {
		let folder = source.deletingLastPathComponent()
		let base = source.deletingPathExtension().lastPathComponent
		let suffix = theme?.isDark == true ? "-dark" : ""
		guard diagrams > 1 else {
			return [folder.appendingPathComponent("\(base)\(suffix).\(format.rawValue)")]
		}
		return (0..<diagrams).map { index in
			let name = index == 0 ? base : String(format: "%@_%03d", base, index)
			return folder.appendingPathComponent("\(name)\(suffix).\(format.rawValue)")
		}
	}

	/// Whether a file already there is a picture PlantUML drew.
	///
	/// Both formats say so in their own bytes and say it early: a PNG carries a
	/// `tEXt` chunk reading "Generated by https://plantuml.com" and an `iTXt`
	/// chunk keyed `plantuml` holding the source; an SVG carries a
	/// `<?plantuml …?>` instruction. Neither is something a screenshot or an
	/// exported drawing from anywhere else has, which is the whole question
	/// being asked.
	public static func isDrawnByPlantUML(_ data: Data) -> Bool {
		let head = data.prefix(16 * 1024)
		for marker in ["plantuml", "PlantUML"] where head.range(of: Data(marker.utf8)) != nil {
			return true
		}
		return false
	}

	/// Whether a file already there is a picture *this app* drew.
	///
	/// Mermaid signs nothing — `mermaid.render` hands back an SVG with no
	/// provenance in it and a canvas hands back bare PNG pixels — so this side
	/// signs it, and `DiagramStamp` is where both halves of that live. Without a
	/// signature the refusal above would fire on this app's *own* previous
	/// export, and exporting the same diagram twice is the ordinary way of
	/// working rather than a mistake to catch.
	///
	/// The whole marker is looked for rather than the shared prefix, so that a
	/// file whose path happens to say "abydos-" is not mistaken for one of ours.
	public static func isDrawnHere(_ data: Data) -> Bool {
		let head = data.prefix(16 * 1024)
		return DiagramStamp.markers.contains { head.range(of: Data($0.utf8)) != nil }
	}

	/// Whether a file already there is a picture drawn from a *diagram* by
	/// anything at all, rather than a screenshot with an unlucky name.
	///
	/// draw.io answers this itself and better than a signature could: a picture
	/// it exported carries the whole `<mxfile>` in a `content` attribute or an
	/// `mxfile` chunk, and that chunk *is* the proof the file is a drawing
	/// somebody made rather than a photograph. So `architecture.png` beside
	/// `architecture.drawio`, written by draw.io on somebody else's machine, is
	/// replaced by an export here — which is right, because it is the same
	/// picture of the same document.
	public static func isDrawnFromADiagram(_ data: Data) -> Bool {
		Drawio.mxfile(in: data) != nil
	}

	/// Whether a file already there is one of ours at all, by any signature.
	public static func isOurs(_ data: Data) -> Bool {
		isDrawnByPlantUML(data) || isDrawnHere(data) || isDrawnFromADiagram(data)
	}

	/// Why one of these files must not be written over, or nil when they may be.
	///
	/// Every destination is checked before anything is drawn: finding out about
	/// the third one after two have been written is the half-done state this is
	/// meant not to have.
	public static func refusal(
		toWrite destinations: [URL],
		reading: (URL) -> Data? = { try? Data(contentsOf: $0, options: .mappedIfSafe) }
	) -> String? {
		for destination in destinations {
			guard let existing = reading(destination) else { continue }
			guard !isOurs(existing) else { continue }
			return "“\(destination.lastPathComponent)” is already here and was not drawn from a "
				+ "diagram, so nothing was written. Move it, or rename the diagram."
		}
		return nil
	}

	// MARK: - Doing it

	/// Draws a file's diagrams and writes them beside it.
	///
	/// - Parameters:
	///   - source: the text to draw, which is what is in the editor rather than
	///     what is on disk — the picture should be of the diagram somebody is
	///     looking at.
	///   - url: the `.puml` file, which is where the pictures go and what they
	///     are named after.
	///   - progress: for the one thing worth saying while this happens, which is
	///     that a container image is being fetched.
	///   - image: where getting that image is reported to somebody with a pane to
	///     put it in — what the runtime printed, and the moment that part settled.
	///     An export is a fetch and then several renders, and the one value this
	///     hands back cannot tell those apart: without the second, a pane opened
	///     to watch a fetch would end up with a syntax error in a `.puml` written
	///     into it in red. See `ImageWatch`.
	/// - Returns: the files written, in order.
	///   - theme: which way round to draw it. Ignored, along with the `-dark`
	///     naming, when the diagram states a look of its own — the file wins, so
	///     there is only one picture of it and it keeps the plain name.
	public static func export(
		source: String,
		of url: URL,
		format: PlantUML.Format,
		tool: PlantUML.Tool,
		theme: DiagramTheme? = nil,
		progress: @escaping @Sendable (String) -> Void = { _ in },
		image: ImageWatch = .none
	) async -> Result<[URL], Failure> {
		let name = url.lastPathComponent
		let blocks = diagrams(in: source)
		guard !blocks.isEmpty else {
			return .failure(Failure(
				"There is no diagram in \(name) — a diagram starts with @startuml."
			))
		}
		let imposed = imposed(theme, when: PlantUML.statedLook(in: source))

		let destinations = destinations(
			for: url, format: format, diagrams: blocks.count, theme: imposed
		)
		if let refused = refusal(toWrite: destinations) { return .failure(Failure(refused)) }

		// The image first, once, however many diagrams the file holds: a project
		// that names one and has never drawn anything has nothing to draw with
		// until this has run, and a two-minute fetch with nothing on screen is
		// indistinguishable from a hang.
		if case let .image(container, runtime) = tool {
			let outcome = await ContainerImageStore.shared.ensure(
				container.image, using: runtime,
				progress: { message in
					progress(message)
					image.step?(message)
				},
				output: image.output
			)
			if case let .failed(reason) = outcome {
				image.settled?(reason)
				return .failure(Failure(reason))
			}
			image.settled?(nil)
		}

		// One diagram means the whole file, exactly as the preview draws it —
		// the block is the same text, and anything around it PlantUML ignores.
		// Several means one render each, which is the only way both routes agree
		// about what the pictures are.
		let pieces: [(text: String, offset: Int)] = blocks.count == 1
			? [(source, 0)]
			: blocks.map { ($0.text, $0.firstLine - 1) }

		var pictures: [Data] = []
		for piece in pieces {
			switch await draw(piece.text, format: format, tool: tool, theme: imposed) {
			case let .success(data):
				pictures.append(data)
			case let .failure(.fault(fault)):
				return .failure(Failure(fault.sentence(for: name, offset: piece.offset)))
			case let .failure(.trouble(said)):
				return .failure(Failure(said))
			}
		}

		// Everything drawn, so everything is written or nothing is.
		for (picture, destination) in zip(pictures, destinations) {
			do {
				try picture.write(to: destination, options: .atomic)
			} catch {
				return .failure(Failure(
					"Could not write \(destination.lastPathComponent): \(error.localizedDescription)"
				))
			}
		}
		return .success(destinations)
	}

	/// Whether a file is a diagram this app draws at all, by either tool.
	///
	/// One question with one answer, because the tree's Export item, the
	/// preview's, and the pane that opens beside the text all have to agree
	/// about it — and two of them asking `PlantUML.isDiagram` was how a `.mmd`
	/// file came to have a preview and no way to export it.
	///
	/// This is the question about the *name*, and it is deliberately still only
	/// that: a Markdown file is a thing to export or not depending on what is
	/// written in it, which is `holdsADiagram`.
	public static func isDiagram(_ url: URL) -> Bool {
		PlantUML.isDiagram(url) || Mermaid.isDiagram(url) || Drawio.isDiagram(url)
	}

	/// What in a file states a look of its own, whichever language it is in.
	///
	/// The deciding is each renderer's — `PlantUML.statedLook`,
	/// `Mermaid.statedLook`, `Drawio.statedLook`, each about its own language and
	/// each with its own tests. This is only the one place that picks which to
	/// ask, for the same reason `isDiagram` is: the pane, the pane's menu, the
	/// tree's menu and the export itself all have to answer it the same way, and
	/// four copies of the question is how a `.mmd` came to have a preview and no
	/// way to export it.
	public static func statedLook(of url: URL, source: String) -> String? {
		if FilePreview.kind(for: url) == .markdown { return statedLook(inMarkdown: source) }
		if Drawio.isDiagram(url) {
			return Drawio.read(Data(source.utf8)).flatMap(Drawio.statedLook)
		}
		if Mermaid.isDiagram(url) { return Mermaid.statedLook(in: source) }
		return PlantUML.statedLook(in: source)
	}

	/// The theme to actually draw in: the one asked for, unless the file has
	/// stated a look — in which case nothing at all is imposed.
	static func imposed(_ theme: DiagramTheme?, when stated: String?) -> DiagramTheme? {
		stated == nil ? theme : nil
	}

	/// What went wrong with one picture: the diagram, or everything else.
	enum DrawFailure: Error {
		case fault(DiagramFault)
		case trouble(String)
	}

	/// One picture, from the kept-warm server when there is one and from
	/// `-pipe` when there is not.
	///
	/// The same two routes the preview has, in the same order and with the same
	/// fallback: the server answers in a twentieth of the time, and everything
	/// that can go wrong with it is a reason to draw the diagram the way this
	/// app always did.
	static func draw(
		_ text: String, format: PlantUML.Format, tool: PlantUML.Tool, theme: DiagramTheme? = nil
	) async -> Result<Data, DrawFailure> {
		if case let .image(container, runtime) = tool,
		   case let .success(drawing) = await PlantUMLServers.shared.draw(
		   	text, image: container.image, using: runtime, format: format, theme: theme
		   ) {
			if let fault = drawing.fault { return .failure(.fault(fault)) }
			return .success(drawing.data)
		}
		return await pipe(text, format: format, tool: tool, theme: theme)
	}

	/// The old route: the diagram on standard input, the picture on standard
	/// output, and the complaint on standard error.
	private static func pipe(
		_ text: String, format: PlantUML.Format, tool: PlantUML.Tool, theme: DiagramTheme?
	) async -> Result<Data, DrawFailure> {
		await withCheckedContinuation { continuation in
			// Off the cooperative pool: everything here waits on a subprocess, and
			// a thread held there is a thread every other task queues behind.
			DispatchQueue.global(qos: .userInitiated).async {
				continuation.resume(
					returning: runPipe(text, format: format, tool: tool, theme: theme)
				)
			}
		}
	}

	private static func runPipe(
		_ text: String, format: PlantUML.Format, tool: PlantUML.Tool, theme: DiagramTheme?
	) -> Result<Data, DrawFailure> {
		// A name for the container, when there is one: killing `docker run` does
		// not stop what it started, and a container with no name cannot be
		// removed again at all. See 0406.
		var containerName: String?
		if case let .image(_, runtime) = tool {
			let name = ToolContainers.mint("plantuml-export")
			ToolContainers.shared.register(name, runtime: runtime)
			containerName = name
		}
		defer { if let containerName { ToolContainers.shared.releaseInBackground(containerName) } }

		let run = PlantUML.invocation(
			for: tool, format: format, name: containerName, theme: theme
		)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: run.executable)
		process.arguments = run.arguments
		let input = Pipe(), output = Pipe(), errors = Pipe()
		process.standardInput = input
		process.standardOutput = output
		process.standardError = errors

		guard ToolProcesses.shared.adopt(
			process, as: "diagram export", fromImage: containerName != nil
		) else {
			return .failure(.trouble(ToolProcesses.shared.tooManyMessage))
		}

		// A deadline, because a runtime whose service is not up accepts the
		// command and then waits for a daemon that is never coming.
		let watchdog = DispatchWorkItem {
			guard process.isRunning else { return }
			process.terminate()
			DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
				if process.isRunning { kill(process.processIdentifier, SIGKILL) }
			}
			// Neither signal touches the container, which is the part that would
			// otherwise be left holding the runtime.
			if let containerName { ToolContainers.shared.releaseInBackground(containerName) }
		}
		DispatchQueue.global().asyncAfter(deadline: .now() + deadline, execute: watchdog)

		do {
			try process.run()
		} catch {
			ToolProcesses.shared.forget(process)
			watchdog.cancel()
			return .failure(.trouble(error.localizedDescription))
		}

		let captured = ProcessPipes.drain(
			process, out: output, err: errors, input: Data(text.utf8), stdin: input
		)
		watchdog.cancel()
		ToolProcesses.shared.forget(process)

		let complaint = String(decoding: captured.stderr, as: UTF8.self)
		// PlantUML exits 200 for a diagram it could not parse, having drawn a
		// picture of the complaint. The picture is not the export.
		if process.terminationStatus != 0, let fault = DiagramFault(standardError: complaint) {
			return .failure(.fault(fault))
		}
		guard PlantUML.isPicture(captured.stdout) else {
			let said = complaint.trimmingCharacters(in: .whitespacesAndNewlines)
			return .failure(.trouble(said.isEmpty
				? "\(tool.description) drew nothing. Graphviz may be missing."
				: said))
		}
		return .success(captured.stdout)
	}
}
