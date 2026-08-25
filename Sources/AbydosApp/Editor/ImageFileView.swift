import AbydosKit
import AppKit

/// A picture, shown in a tab.
///
/// Documentation lives next to the diagrams and screenshots it talks about, and
/// clicking one used to say "This looks like a binary file" and offer a hex
/// dump. It opens fitted to the pane and never blown up past its own size, on a
/// checkerboard so a transparent background reads as transparent rather than as
/// whatever colour happens to be behind it — which is exactly the question
/// anybody opening an icon has.
///
/// Fitted is where it *starts*. ⌘+ and ⌘- make it larger and smaller, a pinch
/// does the same continuously, a double-click swaps between the fit and the
/// picture's own size, and anything larger than the pane is scrolled to its
/// edges rather than cropped at them. Item 0532 is the three ways that was not
/// true before: the document view was resized to the pane on every frame change
/// so the scrollers had nothing to scroll, "1:1" therefore cropped a screenshot
/// instead of letting it be panned, and the only sizes reachable at all were the
/// fit and 1:1.
///
/// The pane is built like the diagram pane, which worked all of this out first:
/// the picture is in a scroll view whose document is exactly as large as the
/// picture is being drawn, and the caption sits at the foot *outside* that scroll
/// view — it used to be a subview of the document, so it would have scrolled
/// away with the picture.
///
/// **The one place it now differs from the diagram pane is the zoom, and item
/// 0537 is why.** 0532 gave this pane no scale of its own, on the diagram pane's
/// argument that the app has one zoom; everything between the fit and the
/// picture's own size therefore came from `Settings.activeScale`, so looking
/// closely at a screenshot enlarged the editor's font and the sidebar's rows
/// along with it. That was reported as the thing it is. A picture is not
/// furniture around the content — it *is* the content, and enlarging it is the
/// same act as the editor's own text zoom rather than a different one. So the
/// picture keeps its own scale, ⌘+ / ⌘- / ⌘0 drive it **while this pane has the
/// keyboard**, and the interface's zoom is left to the rest of the window.
final class ImageFileView: NSView, ScalingPage {
	/// How large the picture is drawn, which is the one question a zoom cannot
	/// answer on its own.
	///
	/// Either the pane decides — the whole picture, as large as the pane can show
	/// it — or somebody has named a scale, and `.actual` is the one they name
	/// most: the size the file says it is, which is `.scale(1)` under a name
	/// worth having.
	///
	/// **A named scale is the scale actually drawn, and is not multiplied by the
	/// interface's zoom.** That is what makes `Actual Size` mean 100% rather than
	/// 100% of whatever the window is at — which is the fault 0532 papered over by
	/// having `Actual Size` reset the window's zoom as well.
	enum Fit: Equatable {
		/// The whole picture, as large as the pane can show it, or its own size
		/// when that is smaller. What a picture opens at, and the one state that
		/// follows the interface's zoom the way every other pane's contents do.
		case pane
		/// A size somebody asked for, as a factor of the size the file says it
		/// is. Left exactly where it was put by a window resize or by ⌘+
		/// elsewhere in the window.
		case scale(CGFloat)

		/// The picture's own size. What `Actual Size` puts it at, and what a
		/// double-click asks for.
		static let actual = Fit.scale(1)
	}

	private let url: URL
	private var image: NSImage?
	/// The size in pixels, which is what the file *holds*: `NSImage.size` is in
	/// points, so a picture from a Retina screenshot claims to be half of what it
	/// holds. Said in the caption, and what the interpolation is decided against.
	private var pixelSize: CGSize = .zero
	/// The size in points, which is what the file says it *is* — and therefore
	/// what 100% means.
	///
	/// **The two are not interchangeable and this is the half that gets drawn.**
	/// Drawing `pixelSize` at scale 1 puts one image pixel on one *point*, so a
	/// 144-dpi screenshot came out at twice the size of the thing it was a
	/// screenshot of, blurred by the interpolation that doubling needs, under a
	/// caption that said 100%. Drawing the stated size instead makes 100% mean
	/// what Preview means by it and what `PdfPreview` already meant by it, and on
	/// a Retina screen it puts one pixel of that screenshot on one pixel of the
	/// display — which is the sharpest a picture can be shown.
	private var naturalSize: CGSize = .zero
	/// Whether the file is pixels rather than instructions, which decides whether
	/// magnifying it should interpolate. See `interpolation`.
	private var isBitmap = false

	private(set) var fit: Fit = .pane
	/// What the picture is being drawn at, for the caption.
	private var shownScale: CGFloat = 1
	/// Which point of the picture to keep in the middle of the pane when the
	/// picture changes size — as a fraction of it, in each direction.
	///
	/// A zoom that puts somebody back at the top left of a picture they were
	/// looking at the middle of is a zoom they have to undo by scrolling. Read
	/// from where the pane is looking, so it costs nothing to keep up to date and
	/// cannot drift from where the picture actually is.
	private var anchor = CGPoint(x: 0.5, y: 0.5)

	private let scrollView = NSScrollView()
	private let canvas = ImageCanvas()
	private let caption = NSTextField(labelWithString: "")
	private var watchingSettings: NSObjectProtocol?

	/// How much room the picture leaves around itself inside the document, so a
	/// picture panned to its edge is not flush against the side of the window.
	private static let margin: CGFloat = 16

	init(url: URL) {
		self.url = url
		super.init(frame: .zero)
		load()

		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.scrollerStyle = .overlay
		scrollView.documentView = canvas
		canvas.pane = self
		addSubview(scrollView)

		caption.font = Theme.current.uiFont(11)
		caption.textColor = Theme.current.sidebarText.withAlphaComponent(0.75)
		caption.translatesAutoresizingMaskIntoConstraints = false
		addSubview(caption)
		NSLayoutConstraint.activate([
			caption.centerXAnchor.constraint(equalTo: centerXAnchor),
			caption.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
		])

		menu = makeContextMenu()

		// The zoom, and the palette. A PNG is a tab's whole content and an SVG is
		// half a split, and only the first of those is walked on ⌘+ — so the pane
		// listens for itself, exactly as the PDF and diagram panes do, and
		// `applySettings` is the other route into the same work.
		watchingSettings = NotificationCenter.default.addObserver(
			forName: .abydosSettingsChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.applySettings() }
		}

		updateCaption()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		if let watchingSettings { NotificationCenter.default.removeObserver(watchingSettings) }
	}

	private func load() {
		guard let loaded = NSImage(contentsOf: url) else { return }
		image = loaded

		// A bitmap knows how many pixels it has; anything drawn from
		// instructions — an SVG — has no pixel count of its own, so its size in
		// points is the honest answer.
		if let bitmap = loaded.representations.first(where: { $0.pixelsWide > 0 }) {
			pixelSize = CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
			isBitmap = true
		} else {
			pixelSize = loaded.size
		}
		// A picture whose stated size is nothing — which a badly written SVG can
		// be — is drawn at its pixel count rather than not at all.
		naturalSize = loaded.size.width > 0 && loaded.size.height > 0 ? loaded.size : pixelSize
	}

	// MARK: - How large

	/// Changes how large the picture is drawn, and does not write it down
	/// anywhere.
	///
	/// **Not remembered per file, on purpose**, for the reasons the diagram pane
	/// sets out and one this pane adds. A picture opens fitted, which is the
	/// answer to "what is in this file"; a scale is a way of looking at *this*
	/// picture for a moment, so it lives for as long as the tab does and no
	/// longer. Remembering it would need a store, would have to be forgotten on
	/// a rename and a delete, and would open a picture at a size chosen last week
	/// in a differently shaped window. The interface's zoom is the part that *is*
	/// remembered, because that is the part somebody sets once for their eyesight
	/// or their screen — and item 0537 is the whole argument that these are two
	/// different things.
	func setFit(_ wanted: Fit) {
		guard fit != wanted else { return }
		fit = wanted
		// The middle of the pane is the least surprising place to grow from and
		// shrink towards, whichever direction the swap goes in.
		anchor = CGPoint(x: 0.5, y: 0.5)
		needsLayout = true
	}

	/// Swaps between the fit and the picture's own size — what a double-click on
	/// the picture does, and what a test presses.
	func toggleFit() { setFit(fit == .pane ? .actual : .pane) }

	/// Where the next ⌘+ or the next pinch counts from.
	///
	/// The scale being *drawn*, so a zoom out of a fitted picture is a step down
	/// from the fit rather than a step down from some remembered number nobody
	/// can see. `shownScale` is what the caption says, which makes this the only
	/// reading that agrees with what is on screen.
	private var scaleToZoomFrom: CGFloat {
		if case .scale(let asked) = fit { return ImageFit.clamp(asked) }
		return shownScale
	}

	/// ⌘+ and ⌘- over the picture: **the picture's own scale, not the window's.**
	///
	/// These are the View menu's own `Zoom In` and `Zoom Out` arriving down the
	/// responder chain, which is what `acceptsFirstResponder` below is for: while
	/// this pane has the keyboard the keys mean the picture, and everywhere else
	/// in the window they still mean the window. The context menu names the same
	/// two selectors so the menu and the keys cannot drift apart.
	@objc func zoomIn(_ sender: Any?) {
		setFit(.scale(ImageFit.zoomIn(from: scaleToZoomFrom)))
	}

	@objc func zoomOut(_ sender: Any?) {
		setFit(.scale(ImageFit.zoomOut(from: scaleToZoomFrom)))
	}

	/// ⌘0 and `Actual Size`: the picture at exactly 100%, and **the window's zoom
	/// left alone**.
	///
	/// It used to call `Settings.shared.resetZoom()` as well, and that was
	/// correct only while the picture's size and the interface's were the same
	/// number: with no scale of its own, "the picture's own size" could only be
	/// reached by putting the window back to 1×. Now that a named scale is the
	/// scale drawn, 100% is 100% at any interface zoom, and resetting the window
	/// would be this pane reaching out and resizing the rest of the editor —
	/// which is the whole of what was complained about.
	@objc func resetZoom(_ sender: Any?) { setFit(.actual) }

	@objc private func fitImageToPane(_ sender: Any?) { setFit(.pane) }

	/// Pinch, which item 0532 ruled out and this item puts back.
	///
	/// **The objection was true and it is gone.** 0532's reason was not taste: a
	/// pinch would have had to drive `Settings.activeScale`, and "a two-finger
	/// pinch over a picture that resized the editor's font and the sidebar's rows
	/// would be a bug report by lunchtime". With a scale of its own there is
	/// nothing for a pinch to reach except the picture, and pinch is the gesture
	/// people already make at a picture — a trackpad has had it since before this
	/// program existed. `NSEvent.magnification` still appears nowhere else in
	/// `Sources/AbydosApp`, and that stays true: this is the pane where a picture
	/// *is* the content, which is the same reason it is the pane that got a scale.
	///
	/// Continuous rather than stepped, because that is what a pinch is; ⌘+ from
	/// wherever it stops takes the next rung above, which is `scaleToZoomFrom`.
	/// A gesture goes to the view under the pointer, so this works whether or not
	/// the pane has the keyboard — which is right, since nothing about it is
	/// ambiguous the way a key is.
	///
	/// Anchored on the middle of the pane, like every other size change here,
	/// rather than on the fingers. Zooming towards the pointer is nicer and it is
	/// a second anchoring rule: ⌘+ and a pinch would then leave the picture in
	/// two different places, and `rememberAnchor` is read from where the pane is
	/// looking precisely so there is only one answer.
	func magnify(by amount: CGFloat) {
		guard image != nil, amount != 0 else { return }
		setFit(.scale(ImageFit.clamp(scaleToZoomFrom * (1 + amount))))
	}

	/// The pane takes the keyboard, so that ⌘+ over a picture is the picture.
	///
	/// Nothing else here needs a key, and this is not a claim that it does: it is
	/// how the responder chain is asked the question "which pane is being looked
	/// at". Without it, activating a picture tab left the keyboard wherever it
	/// was — often a code view for a file no longer on screen — and the View
	/// menu's zoom went to the window controller as it does everywhere else.
	override var acceptsFirstResponder: Bool { image != nil }

	/// Right-clicking the picture offers the four sizes.
	///
	/// The same four the diagram pane offers, and deliberately the same words for
	/// the three that mean the same thing — `Zoom In`, `Zoom Out` and `Actual
	/// Size` are the View menu's own items, and over a picture they are the
	/// picture. The fourth is `Fit to Window` rather than `Fit to Width`, and the
	/// different word is the whole difference between the two panes: a diagram is
	/// read down its length, and a picture is looked at whole.
	///
	/// The three that are also keys point at **the same selectors the keys
	/// arrive on**, rather than at wrappers of their own. That is the part worth
	/// keeping: a right-click item and a key equivalent that did the same thing
	/// by two routes is how the two come to disagree.
	///
	/// A menu rather than buttons in a corner, because the pane is drawn by hand
	/// and a button would sit over the picture — and because ⌘+ over a picture is
	/// something people look for a menu to confirm.
	private func makeContextMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		for (title, action) in [
			("Zoom In", #selector(zoomIn(_:))),
			("Zoom Out", #selector(zoomOut(_:))),
			("Actual Size", #selector(resetZoom(_:))),
			("Fit to Window", #selector(fitImageToPane(_:))),
		] {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = self
			menu.addItem(item)
		}
		return menu
	}

	override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
		menu.items.first { $0.title == "Fit to Window" }?.state = fit == .pane ? .on : .off
		menu.items.first { $0.title == "Actual Size" }?.state = fit == .actual ? .on : .off
	}

	// MARK: - Laying it out

	/// Re-reads the zoom and the palette, the way every pane of the window does.
	func applySettings() {
		scrollView.backgroundColor = Theme.current.editorBackground
		caption.font = Theme.current.uiFont(11)
		caption.textColor = Theme.current.sidebarText.withAlphaComponent(0.75)
		needsLayout = true
		needsDisplay = true
	}

	/// How much of the foot of the pane belongs to the caption.
	///
	/// Measured from the font rather than fixed, because that font follows ⌘+ like
	/// everything else in the window — the same trap the diagram pane records,
	/// where a constant was right at 1× and left the readout half behind the
	/// picture at 2×.
	private var footHeight: CGFloat {
		let font = Theme.current.uiFont(11)
		return (font.ascender - font.descender).rounded(.up) + 20
	}

	override func layout() {
		super.layout()
		let foot = footHeight
		scrollView.frame = NSRect(
			x: 0, y: foot, width: bounds.width, height: max(0, bounds.height - foot)
		)
		layoutPicture()
	}

	/// How large the picture is drawn, how large a document it needs to be
	/// scrolled in, and where in that document it goes.
	private func layoutPicture() {
		guard image != nil, naturalSize.width > 0, naturalSize.height > 0 else {
			scrollView.isHidden = true
			return
		}
		scrollView.isHidden = false
		let visible = scrollView.contentSize
		guard visible.width > 0, visible.height > 0 else { return }

		// Where the pane is looking now, before anything moves under it.
		rememberAnchor()

		let margin = Self.margin
		let factor: CGFloat
		switch fit {
		case .pane:
			// The room inside the margin, so a fitted picture is not flush against
			// the sides of the pane and so fitting cannot itself produce a scroller.
			//
			// **Times the interface's zoom, which is the half of 0532 that stays.**
			// A fitted picture is this pane's contents at rest, and every other
			// pane's contents grow with ⌘+ elsewhere in the window; a picture that
			// alone ignored it would be a picture that shrank, relatively, every
			// time somebody made the editor larger.
			factor = ImageFit.paneScale(
				image: naturalSize,
				in: CGSize(width: max(1, visible.width - margin * 2),
				           height: max(1, visible.height - margin * 2)),
				zoom: Theme.current.scale
			)
		// A size somebody asked for is that size. **Not times the interface's
		// zoom**: `Actual Size` at a 1.5× interface would otherwise draw 150% and
		// say so, which is a menu item lying about the number in its own name —
		// and 0532's answer to that was to reset the interface's zoom, which is
		// exactly what item 0537 is about.
		case .scale(let asked):
			factor = ImageFit.clamp(asked)
		}
		shownScale = factor

		let picture = CGSize(
			width: (naturalSize.width * factor).rounded(),
			height: (naturalSize.height * factor).rounded()
		)
		let document = ImageFit.documentSize(picture: picture, visible: visible, margin: margin)
		if canvas.frame.size != document { canvas.setFrameSize(document) }
		canvas.picture = ImageFit.rect(image: picture, in: document, scale: 1)
		canvas.image = image
		canvas.interpolation = interpolation(drawnAt: picture)
		canvas.needsDisplay = true

		restoreAnchor(in: document, visible: visible)
		updateCaption()
	}

	/// Which point of the picture the pane is looking at the middle of.
	private func rememberAnchor() {
		let box = canvas.picture
		guard box.width > 0, box.height > 0 else { return }
		let seen = scrollView.documentVisibleRect
		guard seen.width > 0, seen.height > 0 else { return }
		anchor = CGPoint(
			x: min(max((seen.midX - box.minX) / box.width, 0), 1),
			y: min(max((seen.midY - box.minY) / box.height, 0), 1)
		)
	}

	/// Puts that point back in the middle of the pane, as far as the document
	/// allows — which for a picture smaller than the pane is not at all, and is
	/// why this clamps rather than asserting.
	///
	/// **Only when it actually moves.** This is called from `layout()`, and
	/// scrolling a clip view invalidates layout, so scrolling unconditionally is a
	/// pass that asks for another pass for ever. Found while hunting something
	/// else — it was not the cause of that, and it is a fault on its own.
	private func restoreAnchor(in document: CGSize, visible: CGSize) {
		let box = canvas.picture
		guard box.width > 0, box.height > 0 else { return }
		let wanted = NSPoint(
			x: min(max(box.minX + anchor.x * box.width - visible.width / 2, 0),
			       max(0, document.width - visible.width)).rounded(),
			y: min(max(box.minY + anchor.y * box.height - visible.height / 2, 0),
			       max(0, document.height - visible.height)).rounded()
		)
		let now = scrollView.documentVisibleRect.origin
		guard abs(wanted.x - now.x) > 0.5 || abs(wanted.y - now.y) > 0.5 else { return }
		canvas.scroll(wanted)
	}

	/// Whether to smooth the picture or show its pixels as pixels.
	///
	/// **Decided against the pixels rather than against the percentage**, because
	/// that is the question being asked. A picture being *shrunk* has to be
	/// interpolated — nearest-neighbour drops rows and columns, and a screenshot
	/// with every other line of text missing is unreadable. A picture being blown
	/// up past its own pixels is the opposite case: the reason anybody zooms a
	/// screenshot to 400% is to see the pixels, and smoothing hides exactly what
	/// they are looking for. `ImageFit`'s own comment used to argue from the blur
	/// that this was a reason not to zoom a bitmap at all; the request overrules
	/// that, and `NSImageInterpolation.none` is what stops the blur being the
	/// answer.
	///
	/// A Retina screen makes this a question at 100% too, not only above it: a
	/// 72-dpi picture at its own size covers each of its pixels with a 2 × 2
	/// square of screen pixels, and that square is either honest or a smudge.
	/// Judged by eye at 110%, 200% and 400% — see the pictures on the item.
	///
	/// Never for a drawing: an SVG is instructions, `NSImage` renders it afresh at
	/// whatever size it is asked for, and there is no pixel there to preserve.
	private func interpolation(drawnAt picture: CGSize) -> NSImageInterpolation {
		guard isBitmap, pixelSize.width > 0 else { return .high }
		let onScreen = picture.width * (window?.backingScaleFactor
			?? NSScreen.main?.backingScaleFactor ?? 1)
		return onScreen > pixelSize.width * 1.01 ? .none : .high
	}

	/// **Only when it changed.** This is called from `layout()`, and assigning
	/// `stringValue` invalidates a label's intrinsic size, which asks for another
	/// layout pass: the same fault `restoreAnchor` guards against, one line further
	/// on, and found the same way.
	private func updateCaption() {
		let said = ImageFit.caption(image: pixelSize, scale: shownScale, fitted: fit == .pane)
		guard caption.stringValue != said else { return }
		caption.stringValue = said
	}

	override func draw(_ dirtyRect: NSRect) {
		// **The intersection with `bounds`, not the dirty rectangle.** A dirty
		// rectangle is not promised to be inside the view it is handed to, and the
		// capture path hands over one covering the whole window: `dirtyRect.fill()`
		// painted a band of editor background straight over the *tab strip above
		// this pane*, which showed up as a picture tab whose tab was missing while
		// every report insisted the strip was visible, on top, and holding an item
		// at a sensible rectangle. It cost an hour, and `NSColor.red` in place of
		// the theme's colour would have cost a minute. This pane is a tab's own
		// content view now rather than a document inside a clip view, and the clip
		// view was what used to make the difference harmless.
		Theme.current.editorBackground.setFill()
		dirtyRect.intersection(bounds).fill()

		guard image == nil else { return }
		let message = NSAttributedString(string: "This picture cannot be read.", attributes: [
			.font: Theme.current.uiFont(12),
			.foregroundColor: Theme.current.sidebarText,
		])
		let size = message.size()
		message.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.midY))
	}

	// MARK: - Driven from outside

	/// Scrolls to a point of the picture given as fractions of it, `0,0` being
	/// its top left corner — for `--image-pan`.
	func panForTesting(_ fraction: CGPoint) {
		layoutSubtreeIfNeeded()
		// Read the way somebody reads a picture, so `1,1` is the bottom right
		// corner. This view is unflipped, where `y = 0` is the *bottom*.
		anchor = CGPoint(x: min(max(fraction.x, 0), 1), y: 1 - min(max(fraction.y, 0), 1))
		restoreAnchor(in: canvas.frame.size, visible: scrollView.contentSize)
		scrollView.reflectScrolledClipView(scrollView.contentView)
	}

	/// The picture, the document it sits in and the part of it on screen, in one
	/// line — see `EditorAreaController.setImageFitForTesting`.
	///
	/// **The three sizes and not one.** What 0532 was about is the document being
	/// the same size as the hole it is seen through, and no capture of a picture
	/// can show whether the thing under it is larger than the pane. These numbers
	/// can, and they are the views' own rather than a second sum that agrees with
	/// the drawing by hand.
	///
	/// The interface's zoom is on the line too, for item 0537: what that item
	/// asks for is that one of these two numbers moves and the other does not,
	/// and a claim about two numbers wants both of them printed together.
	var reportForTesting: String {
		layoutSubtreeIfNeeded()
		let document = canvas.frame.size
		let visible = scrollView.contentSize
		let seen = scrollView.documentVisibleRect.origin
		let smoothing = canvas.interpolation == NSImageInterpolation.none ? "none" : "high"
		return "said=\(caption.stringValue) scale=\(Int((shownScale * 100).rounded()))% "
			+ "ui=\(Int((Settings.shared.activeScale * 100).rounded()))% "
			+ "picture=\(Int(canvas.picture.width))x\(Int(canvas.picture.height)) "
			+ "document=\(Int(document.width))x\(Int(document.height)) "
			+ "visible=\(Int(visible.width))x\(Int(visible.height)) "
			+ "at=\(Int(seen.x)),\(Int(seen.y)) smoothing=\(smoothing)"
	}
}

/// The picture itself, inside the pane's scroll view.
///
/// A view of its own because a scroll view needs a document to scroll and the
/// document has to be exactly as large as the picture is being shown at — which
/// is the one thing the pane cannot be, since the pane is also the caption at
/// the foot, the sentence for a file that will not open, and the menu. The pane
/// having been the document is precisely how 0532 happened.
///
/// It owns no state worth the name: the pane works out where the picture goes
/// and this paints it there.
private final class ImageCanvas: NSView {
	/// The pane above, for the two gestures that belong to it rather than here.
	weak var pane: ImageFileView?
	var image: NSImage?
	/// Where the picture goes in this view's own coordinates.
	var picture: NSRect = .zero
	var interpolation: NSImageInterpolation = .high

	override func draw(_ dirtyRect: NSRect) {
		guard let image, picture.width > 0, picture.height > 0 else { return }
		drawCheckerboard(in: picture)
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current?.imageInterpolation = interpolation
		image.draw(in: picture, from: .zero, operation: .sourceOver, fraction: 1)
		NSGraphicsContext.restoreGraphicsState()
	}

	/// The grey squares under the picture, so a transparent background is
	/// visibly transparent rather than looking like part of the picture.
	private func drawCheckerboard(in box: NSRect) {
		let square: CGFloat = 8
		let dark = Theme.current.editorBackground.blended(withFraction: 0.06, of: .white)
			?? Theme.current.editorBackground
		let light = Theme.current.editorBackground.blended(withFraction: 0.12, of: .white)
			?? Theme.current.editorBackground

		NSGraphicsContext.saveGraphicsState()
		NSBezierPath(rect: box).addClip()
		dark.setFill()
		box.fill()
		light.setFill()
		var row = 0
		var y = box.minY
		while y < box.maxY {
			var x = box.minX + (row.isMultiple(of: 2) ? 0 : square)
			while x < box.maxX {
				NSRect(x: x, y: y, width: square, height: square).fill()
				x += square * 2
			}
			y += square
			row += 1
		}
		NSGraphicsContext.restoreGraphicsState()
	}

	/// Double-click swaps between fitting the pane and the picture's own size,
	/// which is the question a scaled-down screenshot always raises.
	///
	/// Kept from before 0532, and it means something different now: the picture's
	/// own size used to be a crop of it, and is now the whole of it with somewhere
	/// to scroll.
	///
	/// A click of any count also hands the keyboard to the pane, which is what
	/// makes ⌘+ afterwards mean the picture. AppKit does that by itself only for
	/// the view it hits, and the view it hits is this one — which deliberately
	/// takes no keys at all: the pane owns the state, so the pane takes the
	/// keyboard. It matters most for an SVG, where the pane is half a split and
	/// the other half is a code view that took the keyboard when the tab opened.
	override func mouseDown(with event: NSEvent) {
		if let pane, pane.acceptsFirstResponder { window?.makeFirstResponder(pane) }
		guard event.clickCount == 2, image != nil else { return super.mouseDown(with: event) }
		pane?.toggleFit()
	}

	/// Pinch over the picture. See `ImageFileView.magnify(by:)` for why there is
	/// one at all now, and why there was not one before.
	override func magnify(with event: NSEvent) {
		guard let pane else { return super.magnify(with: event) }
		pane.magnify(by: event.magnification)
	}

	// The menu belongs to the pane, and this view is over all of it. Both halves
	// are forwarded: the menu itself, and the moment before it opens, which is
	// when the pane marks which size the picture is at.
	override func menu(for event: NSEvent) -> NSMenu? { pane?.menu }

	override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
		pane?.willOpenMenu(menu, with: event)
	}
}
