import Foundation

/// Writing Mermaid out: a `.mmd`, which holds one diagram, and a Markdown
/// document, which holds as many as it has fences.
///
/// Nothing here is fetched and nothing is discovered — the renderer is in the
/// app — so what this half is about is naming: which fence becomes which file,
/// and how a document that gains a diagram in the middle does not rename the
/// pictures of the ones after it.
extension DiagramExport {

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
}
