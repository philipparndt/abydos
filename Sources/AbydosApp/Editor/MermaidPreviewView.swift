import AbydosKit
import AppKit

/// The diagram a Mermaid file describes.
///
/// The same pane as PlantUML's — white paper, the drawing scaled to the window
/// and following ⌘+, `Export ▸ PNG` / `Export ▸ SVG` on a right-click — and
/// underneath it the one tool in this app that needs nothing installed. There
/// is no discovery, no install hint, no container to fetch and no runtime to be
/// running: the renderer is a `WKWebView` with a 3.6 MB bundle in it. See 0425
/// for why, and for the 2.16 GB that the obvious alternative weighed.
///
/// Rendering is debounced like PlantUML's, though for a different reason.
/// Drawing costs about fifteen thousandths of a second rather than two seconds,
/// so this is not about the cost of the render — it is that a diagram half way
/// through being typed does not parse, and redrawing on every keystroke would
/// flash a syntax error into the pane between every two characters.
final class MermaidPreviewView: DiagramPaneView {
	/// What was last drawn, so an unchanged document is not drawn again.
	private var lastSource: String?
	private var pending: DispatchWorkItem?
	/// Which render is the current one. A render started before the last
	/// keystroke must not overwrite the picture of the text as it is now, and
	/// with an async renderer there is no process to terminate to prevent that.
	private var generation = 0

	override init() {
		super.init()
		notice = "Nothing to draw yet."
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		pending?.cancel()
	}

	// MARK: - Exporting

	override var isReadyToExport: Bool {
		lastSource.map { Mermaid.hasDiagram($0) } ?? false
	}

	override var statedLook: String? {
		lastSource.flatMap { Mermaid.statedLook(in: $0) }
	}

	override func export(
		_ format: DiagramFormat, theme: DiagramTheme? = nil,
		then: (@Sendable ([URL]) -> Void)? = nil
	) {
		guard let fileURL else { return }
		DiagramExportCommand.run(
			url: fileURL, source: lastSource, format: format, theme: theme ?? appTheme,
			projectRoot: nil, then: then
		)
	}

	// MARK: - Drawing

	/// The palette changed under an open diagram, so it is drawn again — Mermaid
	/// is themed at render time, so there is no repainting this into place.
	override func themeChanged() {
		guard let source = lastSource else { return }
		lastSource = nil
		show(source)
	}

	/// Draws this diagram, after a pause in the typing.
	func show(_ source: String) {
		guard source != lastSource else { return }
		pending?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.render(source) }
		pending = work
		// The same pause the PlantUML pane uses, so the two panes feel the same
		// under the hand even though what is behind them costs a hundredfold
		// different.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
	}

	private func render(_ source: String) {
		lastSource = source

		// An empty file, or one that is nothing but `%%` comments, is the
		// ordinary state of a document somebody has just made — not something to
		// draw an error for.
		guard Mermaid.hasDiagram(source) else {
			image = nil
			notice = "Nothing to draw yet."
			needsDisplay = true
			return
		}

		// The file wins. A diagram naming a theme of its own — in front matter or
		// in an `%%{init}%%` — is drawn in it, on white paper as it always was,
		// and the caption says whose decision that was.
		let stated = Mermaid.statedLook(in: source)
		let theme: DiagramTheme? = stated == nil ? appTheme : nil
		paper = Self.paper(for: theme)
		caption = stated.map(DiagramLook.notice(stated:))

		generation += 1
		let mine = generation
		spinner.startAnimation(nil)

		Task { [weak self] in
			let drawn = await MermaidRenderer.shared.draw(
				source, format: Mermaid.previewFormat, theme: theme
			)
			guard let self, self.generation == mine else { return }
			self.spinner.stopAnimation(nil)
			switch drawn {
			case let .success(data):
				self.show(picture: data, otherwise: "Mermaid drew nothing.")
			case let .failure(.fault(fault)):
				// The line and the complaint, in the pane where the diagram
				// would be — which is what PlantUML's picture of its own error
				// gives, arriving here as a sentence instead because
				// `mermaid.render` throws rather than drawing one.
				self.image = nil
				self.notice = fault.sentence(
					for: self.fileURL?.lastPathComponent ?? "This diagram"
				)
				self.needsDisplay = true
			case let .failure(.trouble(said)):
				self.image = nil
				self.notice = said
				self.needsDisplay = true
			}
		}
	}
}
