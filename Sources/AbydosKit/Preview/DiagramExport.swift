import Foundation

/// What PlantUML says is wrong with a diagram.
///
/// It never fails on one: a diagram it cannot parse comes back as a *picture of
/// the complaint*, in the format that was asked for, with the ordinary exit
/// status on the HTTP route and a 400 on the other. That is exactly right for a
/// preview — the picture names the line — and exactly wrong for an export,
/// which would write `diagram.png`, report success, and leave somebody with a
/// picture of an error message in their repository.
///
/// So both routes are asked for the complaint rather than only for the picture,
/// and both have one: the server puts it in headers of its own, and `-pipe`
/// prints it on standard error and exits 200.
public struct DiagramFault: Equatable, Sendable {
	/// PlantUML's own sentence: "Syntax Error? (Assumed diagram type: sequence)".
	public let message: String
	/// Which line it is about, counting from one, when PlantUML said.
	public let line: Int?

	public init(message: String, line: Int?) {
		self.message = message
		self.line = line
	}

	/// From the server's headers, which are the same two on both formats.
	///
	/// The line is one-based there — measured against the image, not assumed.
	public init?(errorHeader: String?, lineHeader: String?) {
		guard let errorHeader, !errorHeader.isEmpty else { return nil }
		self.message = errorHeader
		self.line = lineHeader.flatMap(Int.init)
	}

	/// From what `-pipe` printed on standard error.
	///
	/// Three lines, after whatever the JVM had to say for itself first:
	///
	///     ERROR
	///     4
	///     Syntax Error? (Assumed diagram type: sequence)
	///
	/// The number is the offending line counted from *zero*, which the server's
	/// header for the same diagram reports as five. Measured on two diagrams
	/// rather than assumed, and it is added to here so that one export reports
	/// one line number whichever route drew it.
	public init?(standardError: String) {
		let lines = standardError
			.split(separator: "\n", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespaces) }
		guard let marker = lines.firstIndex(of: "ERROR") else { return nil }
		let rest = lines[(marker + 1)...].filter { !$0.isEmpty }
		guard !rest.isEmpty else { return nil }
		if let counted = Int(rest[rest.startIndex]) {
			self.line = counted + 1
			let said = rest.dropFirst().joined(separator: " ")
			self.message = said.isEmpty ? "PlantUML could not parse the diagram." : said
		} else {
			self.line = nil
			self.message = rest.joined(separator: " ")
		}
	}

	/// The one sentence somebody needs: which file, which line, what is wrong.
	///
	/// - Parameter offset: how many lines above this diagram's `@start` the file
	///   begins — nothing for a file with one diagram in it, and the block's
	///   place in the file when there are several, since PlantUML counts from
	///   the start of what it was given.
	public func sentence(for name: String, offset: Int = 0) -> String {
		guard let line else {
			return "\(name) could not be drawn: \(message)"
		}
		return "\(name) line \(line + offset): \(message)"
	}
}

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
	public static func destinations(
		for source: URL, format: PlantUML.Format, diagrams: Int
	) -> [URL] {
		let folder = source.deletingLastPathComponent()
		let base = source.deletingPathExtension().lastPathComponent
		guard diagrams > 1 else {
			return [folder.appendingPathComponent("\(base).\(format.rawValue)")]
		}
		return (0..<diagrams).map { index in
			let name = index == 0 ? base : String(format: "%@_%03d", base, index)
			return folder.appendingPathComponent("\(name).\(format.rawValue)")
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
			guard !isDrawnByPlantUML(existing) else { continue }
			return "“\(destination.lastPathComponent)” is already here and was not drawn by "
				+ "PlantUML, so nothing was written. Move it, or rename the diagram."
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
	/// - Returns: the files written, in order.
	public static func export(
		source: String,
		of url: URL,
		format: PlantUML.Format,
		tool: PlantUML.Tool,
		progress: @escaping @Sendable (String) -> Void = { _ in }
	) async -> Result<[URL], Failure> {
		let name = url.lastPathComponent
		let blocks = diagrams(in: source)
		guard !blocks.isEmpty else {
			return .failure(Failure(
				"There is no diagram in \(name) — a diagram starts with @startuml."
			))
		}

		let destinations = destinations(for: url, format: format, diagrams: blocks.count)
		if let refused = refusal(toWrite: destinations) { return .failure(Failure(refused)) }

		// The image first, once, however many diagrams the file holds: a project
		// that names one and has never drawn anything has nothing to draw with
		// until this has run, and a two-minute fetch with nothing on screen is
		// indistinguishable from a hang.
		if case let .image(container, runtime) = tool {
			let outcome = await ContainerImageStore.shared.ensure(
				container.image, using: runtime, progress: progress
			)
			if case let .failed(reason) = outcome { return .failure(Failure(reason)) }
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
			switch await draw(piece.text, format: format, tool: tool) {
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
		_ text: String, format: PlantUML.Format, tool: PlantUML.Tool
	) async -> Result<Data, DrawFailure> {
		if case let .image(container, runtime) = tool,
		   let drawing = await PlantUMLServers.shared.draw(
		   	text, image: container.image, using: runtime, format: format
		   ) {
			if let fault = drawing.fault { return .failure(.fault(fault)) }
			return .success(drawing.data)
		}
		return await pipe(text, format: format, tool: tool)
	}

	/// The old route: the diagram on standard input, the picture on standard
	/// output, and the complaint on standard error.
	private static func pipe(
		_ text: String, format: PlantUML.Format, tool: PlantUML.Tool
	) async -> Result<Data, DrawFailure> {
		await withCheckedContinuation { continuation in
			// Off the cooperative pool: everything here waits on a subprocess, and
			// a thread held there is a thread every other task queues behind.
			DispatchQueue.global(qos: .userInitiated).async {
				continuation.resume(returning: runPipe(text, format: format, tool: tool))
			}
		}
	}

	private static func runPipe(
		_ text: String, format: PlantUML.Format, tool: PlantUML.Tool
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

		let run = PlantUML.invocation(for: tool, format: format, name: containerName)
		let process = Process()
		process.executableURL = URL(fileURLWithPath: run.executable)
		process.arguments = run.arguments
		let input = Pipe(), output = Pipe(), errors = Pipe()
		process.standardInput = input
		process.standardOutput = output
		process.standardError = errors

		guard ToolProcesses.shared.adopt(process) else {
			return .failure(.trouble(ToolProcesses.tooManyMessage))
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
