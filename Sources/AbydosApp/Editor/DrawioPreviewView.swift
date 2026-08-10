import AbydosKit
import AppKit
import WebKit

/// A `.drawio` open in draw.io's own editor, editing this app's own document.
///
/// The other two diagram panes draw a picture of text somebody typed. This one
/// is not a picture at all — it is the editor, and what somebody does in it is
/// an edit to the file the tab is showing. See 0426, level 2.
///
/// The wiring is deliberately small, and small is the whole claim:
///
///  * draw.io reports every change, and the change goes into the tab's
///    `TextDocument`. That is what makes the edited dot appear, what makes ⌘S
///    write, what makes the close prompt ask, and what makes auto-save work —
///    all of it code that already existed and none of it changed.
///  * Somebody else writing the file reaches here as `onTextChanged`, and the
///    document is put back into the editor. The one thing that must not happen
///    is a document arriving back that this pane itself sent, so what was last
///    given to the editor is remembered and compared.
///  * The pane's own `Export ▸ PNG` / `SVG` draws through the editor, so it is
///    a picture of what is on screen including unsaved work.
///
/// It subclasses the diagram pane for the export menu and for the sentence in
/// the middle: the pane says something while the editor loads, and says why if
/// it will not.
final class DrawioPreviewView: DiagramPaneView {
	private var editor: DrawioEditor?
	/// The document this pane edits, held weakly — the tab owns it.
	weak var document: TextDocument?
	/// What was last handed to draw.io, so a change coming back out of it is not
	/// mistaken for somebody else writing the file.
	private var lastGiven: String?
	private var isLoaded = false

	override init() {
		super.init()
		notice = "Opening draw.io…"

		guard let made = DrawioEditor.make() else {
			notice = Drawio.missingBundleHint
			return
		}
		editor = made

		let web = made.webView
		web.translatesAutoresizingMaskIntoConstraints = false
		// Hidden until the editor says it is ready: an empty white rectangle
		// where a diagram should be says nothing, and the sentence behind it
		// says what is happening.
		web.isHidden = true
		addSubview(web)
		NSLayoutConstraint.activate([
			web.leadingAnchor.constraint(equalTo: leadingAnchor),
			web.trailingAnchor.constraint(equalTo: trailingAnchor),
			web.topAnchor.constraint(equalTo: topAnchor),
			web.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		made.onReady = { [weak self] in self?.editorIsReady() }
		made.onChanged = { [weak self] xml in self?.editorChanged(xml) }
		made.onSaveRequested = { [weak self] xml in self?.editorAskedToSave(xml) }
		made.onTrouble = { [weak self] said in
			guard let self, !self.isLoaded else { return }
			self.notice = said
			self.needsDisplay = true
		}
		made.start()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: - The document, both ways

	/// Puts a document in the editor. Called when the tab opens and again
	/// whenever something outside the app writes the file.
	func show(_ xml: String) {
		guard xml != lastGiven else { return }
		lastGiven = xml
		let document = Drawio.read(Data(xml.utf8))
		stated = document.flatMap(Drawio.statedLook)
		caption = stated.map(DiagramLook.notice(stated:))
		applyTheme()
		editor?.load(xml, compressed: document?.isCompressed ?? false)
	}

	/// What in the document states a look of its own — a page background — or
	/// nil when it says nothing.
	private var stated: String?

	override var statedLook: String? { stated }

	/// The palette changed under an open diagram.
	///
	/// The editor is *told* rather than rebuilt: reloading the page would take
	/// draw.io's undo stack and anything unsaved with it, and the theme can
	/// change with a diagram half drawn. This is 0423's lesson — a pane that has
	/// to be told — with a document open in it that must survive the telling.
	override func themeChanged() {
		applyTheme()
	}

	private func applyTheme() {
		// The chrome follows the app whatever the file says; the shape colours
		// follow it only when the document has stated no background of its own.
		editor?.setDark(chrome: appTheme.isDark, colours: appTheme.isDark && stated == nil)
	}

	private func editorIsReady() {
		isLoaded = true
		editor?.webView.isHidden = false
		notice = nil
		needsDisplay = true
		sayWhatIsMissing()
	}

	/// A change in draw.io is a change to the file, said once and immediately —
	/// unless it is draw.io writing the same drawing back in its own hand.
	///
	/// The editor re-serialises the document as it loads it and reports that as a
	/// change, and the text it reports is never the text that went in: the
	/// indentation is its own, and `<mxGraphModel dx dy>` is the size of the
	/// window the diagram is being looked at in. Taken at face value that marks
	/// **every** `.drawio` edited the instant it is opened — the dot on the tab,
	/// the close prompt, and auto-save rewriting a file nobody touched. Seen, on
	/// three fixtures, none of them touched.
	///
	/// So a change that is the same *drawing* is remembered and not reported.
	/// `Drawio.isSameDrawing` can only be wrong in the safe direction: nothing
	/// anybody did to a diagram survives its normalisation.
	private func editorChanged(_ xml: String) {
		guard let document, xml != lastGiven else { return }
		if let given = lastGiven, Drawio.isSameDrawing(xml, as: given) {
			// Remembered, so ⌘S does not write it either: the app's copy is the
			// file as it stands, and the file as it stands is this drawing.
			lastGiven = xml
			return
		}
		lastGiven = xml
		document.setContents(xml)
		onEdited?()
	}

	/// draw.io's own Save button, which does exactly what ⌘S does.
	private func editorAskedToSave(_ xml: String) {
		editorChanged(xml)
		onSaveRequested?()
	}

	/// The tab was edited, so the bar can put the dot on.
	var onEdited: (() -> Void)?
	/// Somebody pressed Save inside draw.io.
	var onSaveRequested: (() -> Void)?

	/// Reads the editor and puts what it says into the document, before a save.
	///
	/// The change listener means this is almost always a no-op — but "almost
	/// always" is not what ⌘S may be, and the round trip costs milliseconds.
	///
	/// It asks the same question the change listener does, and for the same
	/// reason: ⌘S a second after opening a file, before draw.io has reported its
	/// own re-serialisation, would otherwise write the diagram back in draw.io's
	/// hand — a diff over a file nobody touched, and pressing ⌘S is exactly what
	/// somebody does out of habit on a tab they have only just opened.
	func flush() async {
		guard let document, let current = await editor?.currentDocument() else { return }
		guard current != lastGiven else { return }
		if let given = lastGiven, Drawio.isSameDrawing(current, as: given) {
			lastGiven = current
			return
		}
		lastGiven = current
		document.setContents(current)
	}

	// MARK: - Exporting

	override var isReadyToExport: Bool { isLoaded }

	override func export(
		_ format: DiagramFormat, theme: DiagramTheme? = nil,
		then: (@Sendable ([URL]) -> Void)? = nil
	) {
		guard let fileURL else { return }
		let wanted = theme ?? appTheme
		Task { @MainActor in
			await flush()
			DiagramExportCommand.run(
				url: fileURL, source: document?.rope.string, format: format, theme: wanted,
				projectRoot: nil, then: then
			)
		}
	}

	// MARK: - What this build does not carry

	/// draw.io's clipart is the one asset deliberately left out, and a picture
	/// that silently does not draw is exactly the failure 0426 warned about for
	/// the stencils. The editor asks for it by path, the scheme handler answers
	/// 404 and writes the path down, and this says so once.
	private func sayWhatIsMissing() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
			guard let self, let editor = self.editor else { return }
			let clipart = editor.missingAssets.filter { $0.hasPrefix("img/lib/") }
			guard !clipart.isEmpty else { return }
			Toast.post(
				"Some shapes could not be drawn",
				detail: "\(clipart.count) of them are draw.io clipart, which this build of "
					+ "Abydos does not carry."
			)
		}
	}
}
