import AbydosKit
import AppKit

/// The half of the window a diagram is drawn in, whichever tool draws it.
///
/// PlantUML and Mermaid are two entirely different things to run — a JVM or a
/// container against a web view with a JavaScript bundle in it — and they are
/// the same *pane*: paper in the theme's colour, the drawing fitted to the
/// width and following the app's own ⌘+, somewhere to scroll when it outgrows
/// that, a sentence in the middle when there is no picture to show, and a
/// right-click offering `Export ▸ PNG`, `Export ▸ SVG` and how large to draw.
///
/// So that is here, once. A subclass says how to get a picture and when there
/// is something worth exporting; everything somebody actually looks at is the
/// same, which is what "Mermaid the same way" was asked for.
class DiagramPaneView: NSView {
	/// How large the drawing is laid out, before the app's zoom is applied.
	///
	/// Two states and not a number, because a number would be a second zoom: the
	/// app has one, it is ⌘+ / ⌘- / ⌘0, and a diagram that kept its own would be
	/// a pane where those keys did something different from everywhere else.
	/// What is left over is the question a zoom cannot answer — *what does 1×
	/// mean here* — and there are exactly two honest answers for a drawing.
	enum Fit {
		/// As wide as the pane, or its own size when that is smaller. The
		/// default, and what a diagram is opened to be read at.
		case width
		/// The drawing's own size. What "100%" means for something that states
		/// its size in points, and what `Actual Size` puts it at.
		case actual
	}

	/// The picture, or nil while there is none to show.
	var image: NSImage?
	/// Its own size in points, which for a drawing is the only size it has.
	var naturalSize: CGSize = .zero
	/// What to say instead of a picture: nothing drawn yet, or why not.
	var notice: String?
	/// What to say *beside* a picture, which is a different thing: the notice
	/// replaces the drawing and this sits under it.
	///
	/// One line, at the foot of the pane, for the one thing somebody has to be
	/// able to see while looking at the diagram — that their own file asked for
	/// the colours it has. 0429 is explicit that a diagram staying light in a
	/// dark window has to explain itself or the bug gets reported again, and a
	/// toast cannot do that: it is gone by the time anybody wonders.
	var caption: String?

	/// The colour behind the drawing.
	///
	/// Neither PlantUML's light output nor Mermaid's states a background a
	/// renderer that is not a browser can see, so the pane paints one. It follows
	/// the theme now rather than being white: black lines on a dark editor were
	/// the reason for the white, and light lines on white are the same fault the
	/// other way up.
	var paper: NSColor = .white

	let spinner = NSProgressIndicator()
	/// The zoom being watched, so the pane can stop watching when it goes.
	private var watchingSettings: NSObjectProtocol?
	/// Which palette the picture on screen was drawn for, so a settings change
	/// that was not a theme change does not redraw a diagram.
	private var drawnForTheme = Theme.current.name
	private var exportItem: NSMenuItem?
	private var exportMenu: NSMenu?

	/// Where the picture is, and what makes it pannable once it is larger than
	/// the pane.
	///
	/// A diagram used to be shrunk until it fitted in both directions, which is
	/// what a pane that cannot scroll has to do — and it meant ⌘+ had no effect
	/// at all on any diagram bigger than the pane, since the fit was also the
	/// ceiling. Somewhere to scroll is what makes zooming in mean anything.
	private let scrollView = NSScrollView()
	private let canvas = DiagramCanvas()
	/// What 1× means here. Reset with every pane, and deliberately not
	/// remembered per file — see `setFit`.
	private(set) var fit: Fit = .width
	/// What the drawing is being shown at, for the readout in the corner.
	private var shownScale: CGFloat = 1
	/// Whether the next layout should put the top of the drawing on screen.
	///
	/// True for a new picture and for every change of zoom or fit, and false for
	/// a window somebody resized — the top is where a diagram is read from, and
	/// taking somebody back there because they widened the window is not.
	private var wantsTopOfPicture = true

	/// The file being drawn, which is where an export writes and what it is
	/// named after. Nil until the pane is given one.
	var fileURL: URL?

	init() {
		super.init(frame: .zero)

		// First, so everything else is over it — the spinner, the sentence in the
		// middle, and draw.io's own editor, which a subclass adds on top of this
		// and which is not a picture at all.
		scrollView.drawsBackground = false
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.scrollerStyle = .overlay
		scrollView.documentView = canvas
		scrollView.isHidden = true
		canvas.pane = self
		addSubview(scrollView)

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

		menu = makeContextMenu()

		// The zoom, which this pane follows like every other. A diagram sits
		// inside a split rather than being a tab's own view, so the walk that
		// visits a tab's page on ⌘+ does not reach one — it listens for itself
		// instead, and there is nothing to redo but the drawing.
		watchingSettings = NotificationCenter.default.addObserver(
			forName: .abydosSettingsChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.settingsChanged() }
		}
	}

	/// A settings change: always a repaint, and a *redraw* when it was the
	/// palette.
	///
	/// The zoom needs nothing but a repaint — a drawing is scaled at draw time.
	/// A theme is not like that: the picture itself is a different picture, and
	/// it has to be asked for again. This is 0423's `ScalingPage` lesson in its
	/// own terms, and it is the same mistake the settings page made — a pane that
	/// followed the change only when it was reopened.
	private func settingsChanged() {
		needsDisplay = true
		// ⌘+ arrives here. The drawing is laid out again at the new zoom and the
		// top of it is put back on screen, because a zoom that leaves somebody
		// looking at the middle of a diagram they were reading from the top is
		// the fault the PDF pane had to fix for the same reason.
		wantsTopOfPicture = true
		needsLayout = true
		guard Theme.current.name != drawnForTheme else { return }
		drawnForTheme = Theme.current.name
		themeChanged()
	}

	/// The palette changed while this diagram was open. A subclass draws it
	/// again; the base pane has nothing to draw.
	func themeChanged() {}

	/// Which way round this pane draws, unless the file has stated its own look.
	var appTheme: DiagramTheme { Theme.current.isLight ? .light : .dark }

	/// The paper for a theme, as the colour AppKit fills with.
	///
	/// Read from `DiagramTheme.paper` rather than written out again here: the
	/// pane, the rasterised PNG and the rectangle put into an exported SVG all
	/// have to be the same colour, and three copies of a hex code is how they
	/// stop being. Nil is a file that stated its own look, which gets the white
	/// this pane has always painted.
	static func paper(for theme: DiagramTheme?) -> NSColor {
		guard let hex = theme?.paper.dropFirst(),
		      let value = UInt32(hex, radix: 16)
		else { return .white }
		return .hex(value)
	}

	/// Redraws the pane as if the theme had changed, for a test: a notification
	/// posted from a test would reach every window on the machine.
	func themeChangedForTesting() { settingsChanged() }

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		// A block observer is not removed by handing the centre `self`, and a
		// pane is made and thrown away with every tab — so the token is kept.
		if let watchingSettings { NotificationCenter.default.removeObserver(watchingSettings) }
	}

	// MARK: - What a subclass says

	/// Whether there is a diagram here worth exporting. A menu item that would
	/// write nothing is worse than one that is greyed.
	var isReadyToExport: Bool { false }

	/// What in the open file states a look of its own, or nil when it says
	/// nothing. A subclass answers about its own language.
	var statedLook: String? { nil }

	/// Writes the picture beside the file, in the format asked for.
	///
	/// - Parameters:
	///   - theme: which way round, or nil for whatever is on screen.
	///   - editable: write `x.drawio.png` — the picture that is also the document
	///     — rather than `x.png`. Only draw.io has one to write.
	func export(
		_ format: DiagramFormat, theme: DiagramTheme? = nil, editable: Bool = false,
		then: (@Sendable ([URL]) -> Void)? = nil
	) {}

	/// Whether this file has an editable-picture form, which is draw.io and
	/// nothing else: a `.puml` has no document to put inside a PNG.
	var offersEditablePicture: Bool { fileURL.map(Drawio.isDiagram) ?? false }

	// MARK: - Exporting, and how large

	/// Right-clicking the picture offers to keep it, and to change how large it
	/// is.
	///
	/// A menu on the pane rather than a button in a corner: the pane is drawn
	/// entirely by hand and a button would sit over the diagram, and this is the
	/// gesture every picture on this machine already answers to. The format is
	/// asked for by name — the pane draws in SVG for sharpness, and "Export ▸
	/// PNG" has to mean a PNG rather than whatever happens to be on screen.
	///
	/// The four zoom items under it are the window's own commands, written out
	/// where the diagram is. `Zoom In` and `Zoom Out` are ⌘+ and ⌘- and do
	/// exactly what they do everywhere else; the last two are the pair only a
	/// drawing has a use for, and they are here because ⌘+ over a picture is
	/// something people look for a menu to confirm.
	private func makeContextMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		let export = NSMenuItem(title: "Export", action: nil, keyEquivalent: "")
		let formats = NSMenu()
		formats.autoenablesItems = false
		export.submenu = formats
		menu.addItem(export)
		exportItem = export
		exportMenu = formats

		menu.addItem(.separator())
		for (title, action) in [
			("Zoom In", #selector(zoomDiagramIn(_:))),
			("Zoom Out", #selector(zoomDiagramOut(_:))),
			("Actual Size", #selector(showDiagramActualSize(_:))),
			("Fit to Width", #selector(fitDiagramToWidth(_:))),
		] {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = self
			menu.addItem(item)
		}
		return menu
	}

	override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
		refreshExportMenu()
	}

	private func refreshExportMenu() {
		let ready = fileURL != nil && isReadyToExport
		// Only the export half is greyed by there being nothing drawn yet. The
		// zoom items stay live: they are about the pane rather than about the
		// diagram, and a diagram redraws on every pause in the typing — items
		// that greyed for the second the render took would flicker all day, and
		// a fit chosen while one was under way is honoured by the picture that
		// arrives.
		exportItem?.isEnabled = ready
		if let mark = menu?.items.first(where: { $0.title == "Fit to Width" }) {
			mark.state = fit == .width ? .on : .off
		}
		if let mark = menu?.items.first(where: { $0.title == "Actual Size" }) {
			mark.state = fit == .actual ? .on : .off
		}
		guard let exportMenu else { return }
		DiagramExportMenu.fill(
			exportMenu, theme: appTheme, stated: statedLook,
			target: self, action: #selector(exportFromMenu(_:)), enabled: ready,
			editable: offersEditablePicture
		)
	}

	// MARK: - How large

	/// ⌘+ and ⌘-, said out loud over the diagram. The window's zoom, because
	/// the window has one and a pane with a second would make the same key mean
	/// two things.
	@objc private func zoomDiagramIn(_ sender: Any?) { Settings.shared.zoomIn() }

	@objc private func zoomDiagramOut(_ sender: Any?) { Settings.shared.zoomOut() }

	/// The diagram at exactly 100%, which takes both halves.
	///
	/// The basis alone would be the drawing's own size *times* whatever the
	/// window is zoomed to, which is not 100% and would be a menu item that lied
	/// about the number in its own name. So it puts the window's zoom back to 1×
	/// as well — the same thing `Actual Size` in the View menu does, since this
	/// app has one zoom and that is the item it belongs to.
	@objc private func showDiagramActualSize(_ sender: Any?) {
		Settings.shared.resetZoom()
		setFit(.actual)
	}

	@objc private func fitDiagramToWidth(_ sender: Any?) { setFit(.width) }

	/// Changes what 1× means here, and does not write it down anywhere.
	///
	/// **Not remembered per file, on purpose.** The zoom itself already is —
	/// `Settings.activeScale` is one number for the app and it survives a
	/// relaunch — and that is the part somebody sets once because of their
	/// eyesight or their screen. This is the other part: a way of looking at
	/// *this* diagram for a moment, to read the small print and then go back.
	/// Keyed by path it would need a store, would have to be forgotten when a
	/// file is renamed or deleted, and would open a diagram at a size chosen a
	/// week ago in a differently shaped window. Fit to width costs nothing to
	/// recompute and is right in every window it is asked in, which is the
	/// whole argument for it being the default.
	func setFit(_ wanted: Fit) {
		guard fit != wanted else { return }
		fit = wanted
		wantsTopOfPicture = true
		needsLayout = true
		needsDisplay = true
	}

	@objc private func exportFromMenu(_ sender: NSMenuItem) {
		guard let code = sender.representedObject as? String,
		      let choice = DiagramExportMenu.choice(for: code) else { return }
		export(choice.format, theme: choice.theme, editable: choice.editable)
	}

	/// What a right-click on the diagram offers, for a test: a menu cannot be
	/// photographed while it is open.
	var menuTitlesForTesting: [String] {
		refreshExportMenu()
		// Separators are not offers, and one listed as a disabled empty title is
		// a line of noise in the middle of what the menu says.
		return (menu?.items ?? []).filter { !$0.isSeparatorItem }.flatMap { item -> [String] in
			let mark = item.isEnabled ? "" : " (disabled)"
			let children = (item.submenu?.items ?? [])
				.filter { !$0.isSeparatorItem }
				.map { "\(item.title) ▸ \($0.title)" }
			return ["\(item.title)\(mark)"] + children
		}
	}

	// MARK: - Showing a picture

	/// Takes whatever was drawn as the picture to show, or says why it is not
	/// one.
	func show(picture data: Data, otherwise complaint: String) {
		if !data.isEmpty, let picture = NSImage(data: data) {
			image = picture
			// A bitmap knows how many pixels it has; a drawing has none, and its
			// size in points is the only size it has. Asking the wrong one of the
			// two for pixels gives zero, and a picture drawn in a box of nothing
			// is a pane that stays empty.
			naturalSize = picture.representations.first(where: { $0.pixelsWide > 0 }).map {
				CGSize(width: $0.pixelsWide, height: $0.pixelsHigh)
			} ?? picture.size
			notice = nil
		} else {
			image = nil
			notice = complaint
		}
		// A new picture starts at the top of itself, whatever somebody had
		// scrolled the last one to: it is a different drawing, and its middle is
		// not where the old one's middle was.
		wantsTopOfPicture = true
		needsLayout = true
		needsDisplay = true
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		needsLayout = true
		needsDisplay = true
	}

	/// Puts the scroll view where it goes and lays the drawing out inside it.
	override func layout() {
		super.layout()
		// The foot of the pane is left to the caption and the readout, so the
		// scrolling picture cannot cover either of them.
		scrollView.frame = NSRect(
			x: 0, y: footHeight, width: bounds.width, height: max(0, bounds.height - footHeight)
		)
		layoutPicture()
	}

	/// How much of the foot of the pane belongs to the writing under the picture.
	///
	/// Measured from the font rather than fixed, because that font follows ⌘+
	/// like everything else in the window: a constant here was right at 1× and
	/// left the readout half behind the picture at 2×.
	private var footHeight: CGFloat {
		let font = Theme.current.uiFont(10)
		return (font.ascender - font.descender).rounded(.up) + 6
	}

	/// How large the drawing is, and how much room it needs to be scrolled in.
	///
	/// The document view is the drawing plus a margin, or the pane — whichever is
	/// larger in each direction — so a small diagram is centred in the pane and a
	/// large one is pannable in exactly the direction it overflows.
	private func layoutPicture() {
		guard image != nil, naturalSize.width > 0, naturalSize.height > 0 else {
			scrollView.isHidden = true
			return
		}
		scrollView.isHidden = false
		let visible = scrollView.contentSize
		guard visible.width > 0, visible.height > 0 else { return }

		let margin: CGFloat = 16
		let zoom = Theme.current.scale
		let factor: CGFloat
		switch fit {
		case .width:
			factor = ImageFit.widthScale(
				width: naturalSize.width, paneWidth: max(1, visible.width - margin * 2), zoom: zoom
			)
		// The drawing's own size, still following the window's zoom — so ⌘+ from
		// 100% is 110% rather than nothing, which is what a ceiling here would
		// have made it.
		case .actual:
			factor = ImageFit.clamp(zoom)
		}
		shownScale = factor

		let picture = CGSize(
			width: (naturalSize.width * factor).rounded(),
			height: (naturalSize.height * factor).rounded()
		)
		let document = CGSize(
			width: max(visible.width, picture.width + margin * 2),
			height: max(visible.height, picture.height + margin * 2)
		)
		if canvas.frame.size != document { canvas.setFrameSize(document) }
		canvas.picture = CGRect(
			x: ((document.width - picture.width) / 2).rounded(),
			y: ((document.height - picture.height) / 2).rounded(),
			width: picture.width, height: picture.height
		)
		canvas.image = image
		canvas.paper = paper
		canvas.needsDisplay = true

		guard wantsTopOfPicture else { return }
		wantsTopOfPicture = false
		// Unflipped, so the top of the document is its largest y.
		canvas.scroll(NSPoint(x: 0, y: max(0, document.height - visible.height)))
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.fill()
		drawCaption()
		drawScaleReadout()

		guard image == nil, let notice else { return }
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
		// sits in the same spot either way, so it does not jump when the drawing
		// finishes.
		let top = (bounds.height - height) / 2 + 12
		text.draw(with: NSRect(x: 32, y: top, width: width, height: height),
		          options: [.usesLineFragmentOrigin])
	}

	/// The one line at the foot of the pane, under whatever is above it.
	///
	/// Drawn before the picture rather than over it, so a large diagram scaled to
	/// fill the pane cannot land on top of it — the picture is inset 16 points
	/// and this sits inside that margin.
	private func drawCaption() {
		guard let caption, !caption.isEmpty else { return }
		let text = NSAttributedString(string: caption, attributes: [
			.font: Theme.current.uiFont(10),
			.foregroundColor: Theme.current.sidebarText.withAlphaComponent(0.6),
		])
		let width = max(40, bounds.width - 24)
		let box = text.boundingRect(
			with: NSSize(width: width, height: .greatestFiniteMagnitude),
			options: [.usesLineFragmentOrigin]
		)
		text.draw(with: NSRect(x: 12, y: 2, width: width, height: box.height),
		          options: [.usesLineFragmentOrigin])
	}

	/// How large the drawing is, in the other corner from the caption.
	///
	/// A zoom with no number is a zoom somebody cannot get back from — the pane
	/// has two ways of arriving at a size and a diagram at 62% looks much like
	/// one at 58%. `Fit` is said as well as the percentage, because "100%" while
	/// fitted and "100%" at the drawing's own size are the same number arrived at
	/// two different ways, and only one of them stays 100% when the pane is made
	/// narrower.
	private func drawScaleReadout() {
		guard image != nil, naturalSize.width > 0 else { return }
		let percent = Int((shownScale * 100).rounded())
		let said = fit == .width ? "Fit · \(percent)%" : "\(percent)%"
		let text = NSAttributedString(string: said, attributes: [
			.font: Theme.current.uiFont(10),
			.foregroundColor: Theme.current.sidebarText.withAlphaComponent(0.6),
		])
		let size = text.size()
		text.draw(at: NSPoint(x: max(12, bounds.width - size.width - 12), y: 2))
	}

	/// What the pane says beside the picture, for a test — a caption too small to
	/// read in a screenshot is still worth being certain of.
	var captionForTesting: String? { caption }

	/// What the corner says the drawing is at, for a test, since the point of a
	/// zoom is the number it lands on.
	var scaleReadoutForTesting: String {
		layoutSubtreeIfNeeded()
		layoutPicture()
		let percent = Int((shownScale * 100).rounded())
		return fit == .width ? "Fit · \(percent)%" : "\(percent)%"
	}

	/// Swaps between fitting the pane's width and the drawing's own size — the
	/// double-click the canvas forwards, and what a test presses.
	func toggleFit() { setFit(fit == .width ? .actual : .width) }
}

/// The drawing itself, inside the pane's scroll view.
///
/// A view of its own because a scroll view needs a document to scroll, and the
/// document has to be exactly as large as the picture is being shown at — which
/// is the one thing the pane cannot be, since the pane is also the sentence in
/// the middle, the caption at the foot and the menu.
///
/// It owns no state worth the name: the pane works out where the picture goes
/// and this paints it there.
private final class DiagramCanvas: NSView {
	/// The pane above, for the two gestures that belong to it rather than here.
	weak var pane: DiagramPaneView?
	var image: NSImage?
	var paper: NSColor = .white
	/// Where the drawing goes in this view's own coordinates.
	var picture: NSRect = .zero

	override func draw(_ dirtyRect: NSRect) {
		guard let image, picture.width > 0, picture.height > 0 else { return }
		// The paper the diagram is drawn on. Neither tool's default background is
		// painted — PlantUML's is a CSS property on the root element and Mermaid's
		// is nothing at all — so black lines on a dark editor background would be
		// all but invisible. A diagram that sets a background of its own emits a
		// rectangle for it and covers this.
		paper.setFill()
		picture.fill()
		image.draw(in: picture, from: .zero, operation: .sourceOver, fraction: 1)
	}

	/// Double-click swaps between fitting the width and the drawing's own size.
	///
	/// The same gesture `ImageFileView` gives a picture, for the same question —
	/// "is that as big as it gets?" — and reaching for the menu is the slower
	/// answer to it.
	override func mouseDown(with event: NSEvent) {
		guard event.clickCount == 2, image != nil else { return super.mouseDown(with: event) }
		pane?.toggleFit()
	}

	// The right-click menu belongs to the pane, and this view is over all of it.
	// Both halves are forwarded: the menu itself, and the moment before it opens
	// — which is when the pane fills in what may be exported and at what size.
	override func menu(for event: NSEvent) -> NSMenu? { pane?.menu }

	override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
		pane?.willOpenMenu(menu, with: event)
	}
}
