import Foundation

/// Writing a `.drawio` out: every page as a picture, and the one picture that
/// is also the document.
///
/// The rules are `DiagramExport`'s own — the same names, the same refusal to
/// overwrite a picture nobody here drew, the same theme imposed only on a file
/// that has not stated one. What is particular to draw.io is here: a document
/// has pages where a `.puml` has diagrams, and every picture carries the whole
/// `<mxfile>` inside it.
extension DiagramExport {

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

	// MARK: - The picture that is also the document

	/// Where an editable picture goes: `architecture.drawio.png`.
	///
	/// **One file, and the name is the whole of what is new.** The bytes are the
	/// bytes the ordinary export already writes — draw.io's own `<mxfile>` in a
	/// `content` attribute or an `mxfile` chunk, which is what makes any picture
	/// this app exports reopen in draw.io. What `architecture.png` does not do is
	/// *say* that: it is a name every screenshot in the world could have, and
	/// nobody looking at a repository can tell that this one is also a document.
	/// `architecture.drawio.png` is the name draw.io's own desktop app writes and
	/// the name people commit, and it is the difference between a picture beside
	/// a document and a picture that **is** the document.
	///
	/// `.dio` normalises to `.drawio.png` rather than `.dio.png`: the suffix is a
	/// convention that readers recognise, and there is no `.dio.png` convention to
	/// join.
	///
	/// The `-dark` rule composes exactly as it does above, and has to: without it
	/// a light and a dark editable picture would be the same file.
	public static func editableDestination(
		for source: URL, format: DiagramFormat, theme: DiagramTheme? = nil
	) -> URL {
		let folder = source.deletingLastPathComponent()
		let base = source.deletingPathExtension().lastPathComponent
		let suffix = theme?.isDark == true ? "-dark" : ""
		return folder.appendingPathComponent("\(base)\(suffix).drawio.\(format.rawValue)")
	}

	/// Writes one editable picture of a `.drawio`, beside it.
	///
	/// **One file however many pages there are, and that is the difference from
	/// the export above.** Three pages exported as pictures are three pictures,
	/// because a picture shows one page and a folder missing two thirds of a
	/// document is the quiet wrongness the export rules exist to avoid. An
	/// editable picture is not in that position: the whole `<mxfile>` is inside
	/// it, so `architecture.drawio.png` is the *entire* three-page document and
	/// reopens as all three. What it shows is the first page, which is the same
	/// choice draw.io's own "Save as PNG" makes, and the caller says so.
	///
	/// Everything else is the ordinary export's rules, deliberately: the same
	/// refusal to overwrite a file nobody here drew, the same theme imposed only
	/// when the file has not chosen one, the same atomic write.
	public static func export(
		editable data: Data, of url: URL, format: DiagramFormat, theme: DiagramTheme? = nil
	) async -> Result<URL, Failure> {
		let name = url.lastPathComponent
		guard let document = Drawio.read(data), !document.pages.isEmpty else {
			return .failure(Failure("There is no diagram in \(name)."))
		}
		let imposed = imposed(theme, when: Drawio.statedLook(in: document))
		let destination = editableDestination(for: url, format: format, theme: imposed)
		if let refused = refusal(toWrite: [destination]) { return .failure(Failure(refused)) }

		let drawn = await DrawioRenderer.shared.draw(
			document.mxfile, page: 0, format: format, theme: imposed
		)
		let picture: Data
		switch drawn {
		case let .success(made):
			picture = embedding(document.mxfile, in: made, format: format)
		case let .failure(.fault(fault)):
			return .failure(Failure(fault.sentence(for: name)))
		case let .failure(.trouble(said)):
			return .failure(Failure(said))
		}

		// Written only after it has been read back the way draw.io's own reader
		// would. An editable picture whose document cannot be got out again is a
		// picture, and it would be one under a name promising otherwise — which is
		// worse than not offering the gesture at all.
		guard let back = Drawio.read(picture), back.pages.count == document.pages.count else {
			return .failure(Failure(
				"\(destination.lastPathComponent) would not have opened again as a diagram, "
					+ "so nothing was written."
			))
		}
		do {
			try picture.write(to: destination, options: .atomic)
		} catch {
			return .failure(Failure(
				"Could not write \(destination.lastPathComponent): \(error.localizedDescription)"
			))
		}
		return .success(destination)
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
}
