import Foundation

/// What a diagram is written out as, whichever tool drew it.
///
/// Two formats and no more, because they are the two a menu can offer without
/// becoming a dialogue: SVG for anything that will be looked at or scaled, PNG
/// for anything that has to be pasted into something that cannot read a
/// drawing.
///
/// One type across PlantUML and Mermaid rather than one each. The menus are the
/// same menu — `Export ▸ PNG`, `Export ▸ SVG`, in the preview and in the tree —
/// and two enumerations behind them would eventually be two menus.
public enum DiagramFormat: String, Sendable, CaseIterable {
	case png
	case svg
}

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
		progress: @escaping @Sendable (String) -> Void = { _ in }
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

	/// Draws every page of a `.drawio` and writes the pictures beside it.
	///
	/// **Every page, not the one on screen**, and that is the decision 0426 left
	/// open. Three `@startuml` blocks in a `.puml` are three diagrams somebody
	/// chose to keep together; three pages in a `.drawio` are one document, and
	/// the two arguments were "all three is probably wrong" against "only the one
	/// on screen, without saying so, is certainly wrong". All of them wins for
	/// three reasons: the naming already exists and already means this
	/// (`x.png`, then `x_001.png`), the export can be asked for from the tree
	/// where there is no page on screen to mean, and a folder that is missing two
	/// thirds of a document is the kind of quiet wrongness this app's export
	/// rules exist to avoid. What makes it honest rather than surprising is that
	/// the notice says how many were written, which `DiagramExportCommand`
	/// already does for a `.puml` with several diagrams in it.
	///
	/// Every picture also carries the whole `<mxfile>`, the way draw.io's own
	/// export does — so `architecture.png` is not only a picture of the diagram
	/// but the diagram, and opens again in draw.io with all its pages.
	public static func export(
		drawio data: Data, of url: URL, format: DiagramFormat, theme: DiagramTheme? = nil
	) async -> Result<[URL], Failure> {
		let name = url.lastPathComponent
		guard let document = Drawio.read(data), !document.pages.isEmpty else {
			return .failure(Failure("There is no diagram in \(name)."))
		}
		let imposed = imposed(theme, when: Drawio.statedLook(in: document))

		let destinations = destinations(
			for: url, format: format, diagrams: document.pages.count, theme: imposed
		)
		if let refused = refusal(toWrite: destinations) { return .failure(Failure(refused)) }

		// Everything drawn before anything is written, so a three-page file
		// gains three pictures or none.
		var pictures: [Data] = []
		for (index, page) in document.pages.enumerated() {
			let drawn = await DrawioRenderer.shared.draw(
				document.mxfile, page: index, format: format, theme: imposed
			)
			switch drawn {
			case let .success(picture):
				pictures.append(embedding(document.mxfile, in: picture, format: format))
			case let .failure(.fault(fault)):
				let where_ = document.pages.count == 1 ? name
					: "\(name) — \(page.title(number: index + 1))"
				return .failure(Failure(fault.sentence(for: where_)))
			case let .failure(.trouble(said)):
				return .failure(Failure(said))
			}
		}

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

	private static func embedding(
		_ mxfile: String, in picture: Data, format: DiagramFormat
	) -> Data {
		switch format {
		case .png:
			return DiagramStamp.embed(mxfile: mxfile, in: picture)
		case .svg:
			return Data(DiagramStamp.embed(
				mxfile: mxfile, in: String(decoding: picture, as: UTF8.self)
			).utf8)
		}
	}

	/// Draws a Mermaid file and writes the picture beside it.
	///
	/// The same rules as the PlantUML export above, deliberately: the same
	/// names, the same refusal to overwrite a picture nobody here drew, the same
	/// refusal to write a picture of a syntax error, and the format asked for
	/// rather than the format on screen.
	///
	/// Two things are simpler and both are facts about Mermaid rather than
	/// choices. A `.mmd` holds **one** diagram — there is no `@start` to count,
	/// and a file of several diagrams is a Markdown file full of fences, which
	/// is 0425's deferred half. And there is **nothing to find and nothing to
	/// fetch**: the renderer is in the app, so there is no tool to discover, no
	/// image to pull, and no sentence to say about what to install.
	public static func export(
		mermaid source: String, of url: URL, format: DiagramFormat, theme: DiagramTheme? = nil
	) async -> Result<[URL], Failure> {
		let name = url.lastPathComponent
		guard Mermaid.hasDiagram(source) else {
			return .failure(Failure("There is no diagram in \(name) yet."))
		}
		let imposed = imposed(theme, when: Mermaid.statedLook(in: source))

		let destinations = destinations(for: url, format: format, diagrams: 1, theme: imposed)
		if let refused = refusal(toWrite: destinations) { return .failure(Failure(refused)) }

		let drawn = await MermaidRenderer.shared.draw(source, format: format, theme: imposed)
		let picture: Data
		switch drawn {
		case let .success(data):
			picture = data
		case let .failure(.fault(fault)):
			return .failure(Failure(fault.sentence(for: name)))
		case let .failure(.trouble(said)):
			return .failure(Failure(said))
		}

		guard let destination = destinations.first else {
			return .failure(Failure("There is nowhere to write \(name)'s picture."))
		}
		do {
			try picture.write(to: destination, options: .atomic)
		} catch {
			return .failure(Failure(
				"Could not write \(destination.lastPathComponent): \(error.localizedDescription)"
			))
		}
		return .success([destination])
	}

	// MARK: - The diagrams inside a Markdown document

	/// One ```` ```mermaid ```` block, what its picture is called, and where it
	/// goes.
	public struct Fenced: Equatable, Sendable {
		/// The block, with the line of the file it opened on.
		public let fence: MarkdownFence.Drawn
		/// What goes between the document's own name and the extension, with no
		/// theme suffix on it yet: `checkout`, or `2`.
		public let name: String
		/// Which way round to draw it, or nil when this fence stated a look of its
		/// own — 0429's rule, applied a fence at a time because a look is stated a
		/// fence at a time.
		public let theme: DiagramTheme?
		/// The file to write.
		public let destination: URL

		public init(
			fence: MarkdownFence.Drawn, name: String, theme: DiagramTheme?, destination: URL
		) {
			self.fence = fence
			self.name = name
			self.theme = theme
			self.destination = destination
		}
	}

	/// The drawable blocks a Markdown document holds, in the order they appear.
	///
	/// A fence somebody has opened and not written in yet is not one of them, for
	/// the same reason the preview shows it as a code block rather than drawing
	/// it: there is no diagram there to draw, and asking Mermaid about it would
	/// produce an error and stop the export of every other block in the file.
	public static func fences(in markdown: String) -> [MarkdownFence.Drawn] {
		MarkdownFence.split(markdown).compactMap { piece in
			guard case let .drawn(fence) = piece, Mermaid.hasDiagram(fence.source) else { return nil }
			return fence
		}
	}

	/// What each block's picture is called, and where it goes.
	///
	/// **The naming decision, which 0425 left open and is settled here.**
	/// `DiagramExport` names PlantUML's blocks positionally — `diagram.png`, then
	/// `diagram_001.png` — because that is what PlantUML's own file output
	/// writes, so those names already mean something to a script that was written
	/// against them. **Markdown has no such convention to inherit**, so this is a
	/// choice rather than a copy, and it is made this way:
	///
	///     README.md   ```mermaid with `title: Checkout`   → README-checkout.png
	///                 ```mermaid with no title, 2nd block → README-2.png
	///
	/// **The diagram's own title first.** A fence's front matter `title:` is the
	/// one thing in a Markdown fence that *is* a name: it belongs to the diagram
	/// rather than to the prose around it, Mermaid draws it into the picture, and
	/// it does not move when the document is rewritten. `README-checkout.png` also
	/// says what it is a picture of, which no number does.
	///
	/// **The position when there is no title**, counting *every* drawable block in
	/// the file from 1 — so giving one block a title does not renumber the others.
	///
	/// Three things were rejected and it is worth saying why, because each is the
	/// obvious move from somewhere:
	///
	///  * **The preceding heading.** It is not part of the diagram. Four fences
	///    under one `## Architecture` all want the same name, and rewording a
	///    section for how it reads would rename a picture the README points at.
	///  * **The info string** (```` ```mermaid checkout.png ````). It would be a
	///    convention invented here, honoured by nothing else that reads Markdown,
	///    and it puts a build instruction in the middle of a document.
	///  * **Positions alone, PlantUML's rule copied.** It is the cheapest thing
	///    and its cost is real: inserting a block renumbers everything below it,
	///    so `README_002.png` silently becomes a picture of a different diagram
	///    and the last one is left behind as an orphan. That cost is still paid by
	///    an untitled block here, and the way out of it is written in the naming
	///    itself — give the diagram a title and its picture stops moving.
	///
	/// **There is never a bare `README.png`.** A Markdown document is not a
	/// diagram, so a picture named after the whole file would claim to be a
	/// picture of the document; and `README.md` and `README.puml` sit in one
	/// folder quite happily, where they would otherwise both export to
	/// `README.png`. Every fence's picture is suffixed, including the only one in
	/// a file with one.
	///
	/// **`-dark` goes on the end and composes with all of it**:
	/// `README-checkout-dark.png`, `README-2-dark.png`. A fence that states its
	/// own look is drawn that way and keeps the plain name, which is the same rule
	/// a whole `.mmd` file gets — so one export of a mixed document can write
	/// `README-1-dark.png` beside `README-2.png`, and `DiagramExportCommand` says
	/// so rather than leaving it to be discovered.
	///
	/// A name is not a stamp: `refusal` reads the *bytes* of whatever is already
	/// at these paths, so every one of these files is protected and replaceable by
	/// exactly the rules `diagram.png` is, with nothing new to recognise.
	public static func fenced(
		in markdown: String, of url: URL, format: DiagramFormat, theme: DiagramTheme? = nil
	) -> [Fenced] {
		let folder = url.deletingLastPathComponent()
		let base = url.deletingPathExtension().lastPathComponent
		var taken: Set<String> = []

		return fences(in: markdown).enumerated().map { index, fence in
			let imposed = imposed(theme, when: Mermaid.statedLook(in: fence.source))
			let suffix = imposed?.isDark == true ? "-dark" : ""
			let position = String(index + 1)
			// The first block to claim a name keeps it. A later one that would
			// collide falls back to its position, so a title typed today never
			// renames a picture written last week.
			var name = Mermaid.statedTitle(in: fence.source).flatMap(slug) ?? position
			if taken.contains("\(name)\(suffix)") { name = position }
			taken.insert("\(name)\(suffix)")
			return Fenced(
				fence: fence, name: name, theme: imposed,
				destination: folder.appendingPathComponent(
					"\(base)-\(name)\(suffix).\(format.rawValue)"
				)
			)
		}
	}

	/// A title as the middle of a file name, or nil when it cannot be one.
	///
	/// Letters and digits kept and lowercased, everything else — spaces,
	/// punctuation, and the `/` and `:` a file name may not hold at all —
	/// collapsed to one `-`. Capped at forty characters so a sentence used as a
	/// title does not become a file name nobody can read.
	///
	/// Two titles are refused rather than slugged, and both for one reason: the
	/// numbers belong to the positions. A title that comes out as `3`, or as
	/// `3-dark`, would be a name that says "the third block" about a block that is
	/// not it.
	static func slug(_ title: String) -> String? {
		var out = ""
		var pending = false
		for character in title.lowercased() {
			guard character.isLetter || character.isNumber else {
				pending = !out.isEmpty
				continue
			}
			if pending { out.append("-") }
			pending = false
			out.append(character)
		}
		if out.count > 40 { out = String(out.prefix(40)) }
		while out.hasSuffix("-") { out.removeLast() }
		guard !out.isEmpty, !isPositionShaped(out) else { return nil }
		return out
	}

	/// Whether a name is one the positional rule could have produced.
	private static func isPositionShaped(_ name: String) -> Bool {
		let digits = name.hasSuffix("-dark") ? String(name.dropLast(5)) : name
		return !digits.isEmpty && digits.allSatisfy(\.isNumber)
	}

	/// What a whole Markdown document states about its diagrams' look.
	///
	/// A document does not have a look; each fence does. So this answers with one
	/// only when *every* drawable fence has stated one — which is the only case
	/// where offering `PNG (Dark)` would be offering a difference that does not
	/// exist, and it is exactly the case `DiagramExportMenu` drops the themed
	/// items for. A document where two fences of four have chosen is still a
	/// document where two follow the app, so the themed items belong on its menu.
	public static func statedLook(inMarkdown markdown: String) -> String? {
		let blocks = fences(in: markdown)
		guard !blocks.isEmpty else { return nil }
		let stated = blocks.map { Mermaid.statedLook(in: $0.source) }
		guard let first = stated.first ?? nil, stated.allSatisfy({ $0 != nil }) else { return nil }
		return first
	}

	/// Whether there is anything in this file to export *now*.
	///
	/// `isDiagram` is a question about the name and this is a question about the
	/// contents; Markdown is why the two had to come apart. `README.md` is a thing
	/// to export only once somebody has written a ```` ```mermaid ```` block in
	/// it, and an `Export ▸` over every Markdown file in a repository — nearly all
	/// of which would answer "there is no diagram in it" — is a menu item that is
	/// wrong more often than it is right.
	///
	/// - Parameter source: the text in front of somebody, when there is an editor
	///   holding it. The tree has none and reads the file, which is one read of a
	///   text file while a menu is being filled in.
	public static func holdsADiagram(_ url: URL, source: String? = nil) -> Bool {
		guard FilePreview.kind(for: url) == .markdown else { return isDiagram(url) }
		guard let text = source ?? (try? String(contentsOf: url, encoding: .utf8)) else {
			return false
		}
		return !fences(in: text).isEmpty
	}

	/// Draws every ```` ```mermaid ```` block in a Markdown document and writes
	/// the pictures beside it.
	///
	/// **Every block, and that is the answer to 0425's other open question.** A
	/// `.mmd` pane *is* its diagram, so a right-click on it means the diagram it
	/// is. A Markdown preview is a document with four pictures in it, and three
	/// gestures were on the table:
	///
	///  * **A menu on the picture under the pointer.** It only exists where there
	///    is a picture on screen — so the project tree, which is the other place
	///    0429 says every export has to be reachable from, would need a different
	///    answer, and one act would have two behaviours. It also makes re-exporting
	///    a document four separate gestures with four separate answers.
	///  * **A submenu listing the blocks.** It needs each block to have a name
	///    before it can list them, which is the *other* open question; and a list
	///    of four items reading "the second one, the third one" is a choice
	///    between things nobody can tell apart.
	///  * **All of them, from the menu that already exists.** No new gesture at
	///    all: the same `Export ▸ PNG (Dark)` over the document, in the preview and
	///    in the tree, exactly as over a `.mmd`. It is what `mermaid-cli -i
	///    README.md` does, and it is the same decision the `.drawio` export already
	///    made about pages for the same reason — a folder holding one of a
	///    document's four pictures is the quiet wrongness these rules exist to
	///    avoid.
	///
	/// Everything else is 0424's export unchanged: the format asked for rather
	/// than the one on screen, nothing at all written for a document with a block
	/// that does not parse, and no picture overwritten that this app did not draw.
	/// The complaint names the line of the *file* rather than of the block, which
	/// is the number in the editor beside it — the same offset the preview puts
	/// under a broken fence.
	public static func export(
		markdown source: String, of url: URL, format: DiagramFormat, theme: DiagramTheme? = nil
	) async -> Result<[URL], Failure> {
		let name = url.lastPathComponent
		let blocks = fenced(in: source, of: url, format: format, theme: theme)
		guard !blocks.isEmpty else {
			return .failure(Failure(
				"There is no diagram in \(name) — a diagram lives in a ```mermaid block."
			))
		}

		let destinations = blocks.map(\.destination)
		if let refused = refusal(toWrite: destinations) { return .failure(Failure(refused)) }

		// Everything drawn before anything is written, so a document with four
		// fences gains four pictures or none — and the one that does not parse is
		// found before a single file has been touched.
		var pictures: [Data] = []
		for block in blocks {
			let drawn = await MermaidRenderer.shared.draw(
				block.fence.source, format: format, theme: block.theme
			)
			switch drawn {
			case let .success(data):
				pictures.append(data)
			case let .failure(.fault(fault)):
				return .failure(Failure(
					fault.sentence(for: name, offset: block.fence.openingLine)
				))
			case let .failure(.trouble(said)):
				return .failure(Failure(said))
			}
		}

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
		_ text: String, format: PlantUML.Format, tool: PlantUML.Tool, theme: DiagramTheme? = nil
	) async -> Result<Data, DrawFailure> {
		if case let .image(container, runtime) = tool,
		   let drawing = await PlantUMLServers.shared.draw(
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
