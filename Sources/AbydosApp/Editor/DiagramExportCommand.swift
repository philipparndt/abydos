import AbydosKit
import AppKit

extension Notification.Name {
	/// A picture has been written beside a diagram.
	///
	/// The tree finds the file by itself a moment later — the watcher sees it —
	/// but finding it is not the same as showing where it went, and "where did
	/// that go?" is the one question an export leaves. The window listens and
	/// selects it.
	static let abydosDiagramExported = Notification.Name("abydos.diagram.exported")
}

/// Exporting the diagram in a file as a picture beside it.
///
/// Every gesture reaches this — the preview's own menu and the file's in the
/// project tree, over a PlantUML file, a Mermaid one, a `.drawio`, and a
/// Markdown document full of fences — and they are all the same act: the same
/// rules about overwriting, the same refusal to write a picture of a syntax
/// error, the same sentence when it cannot be done. One place, so they cannot
/// drift apart.
///
/// The two tools part company at exactly one point and it is a fact about them
/// rather than a difference in the feature: a PlantUML file needs a PlantUML to
/// be found and may need an image fetched first, and a Mermaid file needs
/// neither because Mermaid is in the app. See 0425.
///
/// Nothing here is modal. An export is something somebody asked for by name, so
/// what it owes them is a line in the corner saying it happened, or one saying
/// why it did not.
enum DiagramExportCommand {
	/// Exports `source` — the text as it is now, unsaved edits and all, since
	/// the picture should be of the diagram in front of somebody rather than of
	/// whatever was last written to disk.
	/// - Parameter theme: which way round to draw it, as the menu item asked. The
	///   file overrules it when it states a look of its own, which is the rule
	///   0429 settled and the one thing this says out loud when it happens.
	/// - Parameter editable: write the picture that is also the document —
	///   `architecture.drawio.png` rather than `architecture.png`. draw.io only:
	///   nothing else here has a document to put inside a picture.
	static func run(
		url: URL,
		source: String? = nil,
		format: DiagramFormat,
		theme: DiagramTheme? = nil,
		editable: Bool = false,
		projectRoot: URL?,
		then: (@Sendable ([URL]) -> Void)? = nil
	) {
		// A `.drawio` is not text somebody typed, and the two picture forms are
		// not text at all — so it is read as bytes, and what is on screen wins
		// over what is on disk exactly as it does for the other two.
		if Drawio.isDiagram(url) {
			guard let data = source.map({ Data($0.utf8) })
				?? (try? Data(contentsOf: url, options: .mappedIfSafe))
			else {
				Toast.post("Could not read \(url.lastPathComponent)")
				return
			}
			let document = Drawio.read(data)
			let stated = document.flatMap(Drawio.statedLook)
			announceDrawing(url, format: format, theme: theme, stated: stated, editable: editable)
			// What this build cannot draw, said before the picture is written
			// rather than after somebody has committed it. The editor's own
			// scheme handler says the same thing for a diagram on screen; the
			// off-screen renderer has no scheme handler at all, so an export is
			// the one route where a gap would otherwise be silent.
			if let missing = document.flatMap(Drawio.notCarriedNotice) {
				Toast.post("Some of this diagram cannot be drawn", detail: missing)
			}
			if editable {
				Task {
					let outcome = await DiagramExport.export(
						editable: data, of: url, format: format, theme: theme
					)
					await MainActor.run {
						reportEditable(
							outcome, for: url, pages: document?.pages.count ?? 1,
							stated: stated, then: then
						)
					}
				}
				return
			}
			Task {
				let outcome = await DiagramExport.export(
					drawio: data, of: url, format: format, theme: theme
				)
				await MainActor.run { report(outcome, for: url, stated: stated, then: then) }
			}
			return
		}

		let text: String
		if let source {
			text = source
		} else if let onDisk = try? String(contentsOf: url, encoding: .utf8) {
			text = onDisk
		} else {
			Toast.post("Could not read \(url.lastPathComponent)")
			return
		}

		let stated = DiagramExport.statedLook(of: url, source: text)
		announceDrawing(url, format: format, theme: theme, stated: stated)

		// A Markdown document is several diagrams rather than one, and the whole
		// of it is written or none of it is. See `DiagramExport.export(markdown:)`
		// for why every block rather than the one under the pointer.
		if FilePreview.kind(for: url) == .markdown {
			let blocks = DiagramExport.fences(in: text)
			let chose = blocks.filter { Mermaid.statedLook(in: $0.source) != nil }.count
			Task {
				let outcome = await DiagramExport.export(
					markdown: text, of: url, format: format, theme: theme
				)
				await MainActor.run {
					report(outcome, for: url, stated: stated, then: then)
					// Said only when the document disagreed with itself. When every
					// fence stated a look `stated` is not nil and `report` has
					// already said it, in the sentence the other three tools use.
					guard stated == nil, chose > 0, case .success = outcome else { return }
					Toast.post(
						"Some of these diagrams chose",
						detail: DiagramLook.exportNotice(
							for: url.lastPathComponent, chose: chose, of: blocks.count
						),
						kind: .information
					)
				}
			}
			return
		}

		if Mermaid.isDiagram(url) {
			Task {
				let outcome = await DiagramExport.export(
					mermaid: text, of: url, format: format, theme: theme
				)
				await MainActor.run { report(outcome, for: url, stated: stated, then: then) }
			}
			return
		}

		guard let tool = discoverTool(projectRoot: projectRoot) else {
			Toast.post("Cannot export \(url.lastPathComponent)", detail: PlantUML.installHint)
			return
		}
		Task {
			let outcome = await DiagramExport.export(
				source: text, of: url, format: format, tool: tool, theme: theme,
				progress: { message in
					DispatchQueue.main.async { Toast.post(message, kind: .information) }
				}
			)
			await MainActor.run { report(outcome, for: url, stated: stated, then: then) }
		}
	}

	/// The line that says an export has started, naming what is being drawn.
	///
	/// The theme is in it, because the menu item said one and the file it writes
	/// is named after it: "Drawing flow.mmd as PNG (Dark)…" and then "Exported
	/// flow-dark.png" is a pair somebody can follow.
	private static func announceDrawing(
		_ url: URL, format: DiagramFormat, theme: DiagramTheme?, stated: String?,
		editable: Bool = false
	) {
		let what = (editable ? "an editable " : "") + format.rawValue.uppercased()
		let qualified = stated == nil ? theme.map { "\(what) (\($0.title))" } ?? what : what
		Toast.post("Drawing \(url.lastPathComponent) as \(qualified)…", kind: .information)
	}

	/// What one editable picture is, said in the one sentence that keeps it from
	/// being a surprise.
	///
	/// Two things somebody has to know and neither is visible in the file: the
	/// picture is of the **first page** while the file holds them all, and the
	/// `.drawio` beside it is still the one this app edits. A copy is a copy, and
	/// saying so is what stops two documents drifting apart in silence.
	@MainActor
	private static func reportEditable(
		_ outcome: Result<URL, DiagramExport.Failure>,
		for url: URL, pages: Int, stated: String?,
		then: (@Sendable ([URL]) -> Void)?
	) {
		switch outcome {
		case let .success(written):
			let inside = pages == 1
				? "It is the picture and the document at once: it reopens in draw.io."
				: "It shows page 1 and holds all \(pages): it reopens in draw.io with every page."
			Toast.post(
				"Saved \(written.lastPathComponent)",
				detail: inside + " Abydos still edits \(url.lastPathComponent).",
				kind: .information
			)
			if let stated {
				Toast.post(
					"The file chose",
					detail: DiagramLook.exportNotice(
						for: written.lastPathComponent, stated: stated
					),
					kind: .information
				)
			}
			NotificationCenter.default.post(
				name: .abydosDiagramExported, object: nil, userInfo: ["url": written]
			)
			then?([written])
		case let .failure(failure):
			Toast.post("Could not export \(url.lastPathComponent)", detail: failure.message)
		}
	}

	@MainActor
	private static func report(
		_ outcome: Result<[URL], DiagramExport.Failure>,
		for url: URL,
		stated: String? = nil,
		then: (@Sendable ([URL]) -> Void)?
	) {
		switch outcome {
		case let .success(written):
			announce(written)
			// And why it is not the picture the menu item promised, when it is
			// not. Without this, asking for Dark and finding a light
			// `diagram.png` — under the name with no `-dark` in it — is a bug
			// report waiting to happen rather than the rule working.
			if let stated {
				Toast.post(
					"The file chose",
					detail: DiagramLook.exportNotice(for: url.lastPathComponent, stated: stated),
					kind: .information
				)
			}
			then?(written)
		case let .failure(failure):
			// The register `ContainerImages.explain` set: one sentence, which
			// thing went wrong, and what to do about it. Nothing was written, and
			// saying so is half of what makes it honest.
			Toast.post("Could not export \(url.lastPathComponent)", detail: failure.message)
		}
	}

	/// Whichever PlantUML this project can reach, found the same way the preview
	/// finds it — including the image a project names in `.abydos/tools.json`,
	/// so a machine with nothing installed exports as happily as it previews.
	static func discoverTool(projectRoot: URL?) -> PlantUML.Tool? {
		let images = ToolImages.resolve(
			project: projectRoot.map { ToolImages.inProject($0) } ?? ToolImages(),
			settings: ToolImages(images: Settings.shared.toolImages)
		)
		return PlantUML.discover(
			image: images.image(for: "plantuml"),
			runtimePreference: ContainerRuntime.Preference(rawValue: Settings.shared.containerRuntime)
				?? .automatic
		)
	}

	@MainActor
	private static func announce(_ written: [URL]) {
		guard let first = written.first else { return }
		let title = written.count == 1
			? "Exported \(first.lastPathComponent)"
			// A file with several diagrams in it becomes several pictures, named
			// the way PlantUML's own file output names them for a `.puml`, and
			// after each fence's own title or place for a Markdown document.
			// Saying how many is what keeps that from being a surprise.
			: "Exported \(written.count) pictures, \(first.lastPathComponent) first"
		Toast.post(title, kind: .information)
		NotificationCenter.default.post(
			name: .abydosDiagramExported, object: nil, userInfo: ["url": first]
		)
	}
}
