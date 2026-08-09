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

/// Exporting the diagram in a `.puml` file as a picture beside it.
///
/// Two gestures reach this — the preview's own menu and the file's in the
/// project tree — and they are the same act: the same rules about overwriting,
/// the same refusal to write a picture of a syntax error, the same sentence
/// when it cannot be done. One place, so they cannot drift apart.
///
/// Nothing here is modal. An export is something somebody asked for by name, so
/// what it owes them is a line in the corner saying it happened, or one saying
/// why it did not.
enum DiagramExportCommand {
	/// Exports `source` — the text as it is now, unsaved edits and all, since
	/// the picture should be of the diagram in front of somebody rather than of
	/// whatever was last written to disk.
	static func run(
		url: URL,
		source: String? = nil,
		format: PlantUML.Format,
		projectRoot: URL?,
		then: (@Sendable ([URL]) -> Void)? = nil
	) {
		let text: String
		if let source {
			text = source
		} else if let onDisk = try? String(contentsOf: url, encoding: .utf8) {
			text = onDisk
		} else {
			Toast.post("Could not read \(url.lastPathComponent)")
			return
		}

		guard let tool = discoverTool(projectRoot: projectRoot) else {
			Toast.post("Cannot export \(url.lastPathComponent)", detail: PlantUML.installHint)
			return
		}

		Toast.post(
			"Drawing \(url.lastPathComponent) as \(format.rawValue.uppercased())…",
			kind: .information
		)
		Task {
			let outcome = await DiagramExport.export(
				source: text, of: url, format: format, tool: tool,
				progress: { message in
					DispatchQueue.main.async { Toast.post(message, kind: .information) }
				}
			)
			await MainActor.run {
				switch outcome {
				case let .success(written):
					announce(written)
					then?(written)
				case let .failure(failure):
					// The register `ContainerImages.explain` set: one sentence, which
					// thing went wrong, and what to do about it. Nothing was written,
					// and saying so is half of what makes it honest.
					Toast.post("Could not export \(url.lastPathComponent)", detail: failure.message)
				}
			}
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
			// the way PlantUML's own file output names them. Saying how many is
			// what keeps that from being a surprise.
			: "Exported \(written.count) pictures, \(first.lastPathComponent) first"
		Toast.post(title, kind: .information)
		NotificationCenter.default.post(
			name: .abydosDiagramExported, object: nil, userInfo: ["url": first]
		)
	}
}
