import AbydosKit
import AppKit
import PDFKit

/// A PDF, shown in a tab.
///
/// A repository keeps the paper beside the code — a datasheet, a protocol
/// specification, the standard an implementation is of — and clicking one used
/// to say "This looks like a binary file" and offer a hex dump, which is the
/// same wrong answer a picture used to get.
///
/// Drawn by `PDFKit`, which is what the owner's own scanner app uses for exactly
/// this job, and three of its decisions are taken straight from there:
///
///  * `autoScales = false`. PDFKit's auto-scaling fights every attempt to set a
///    scale, quietly resetting on the next layout pass — the note in
///    `DocumentPreview` says so, and it is the one thing that makes ⌘+ work here
///    at all. This app has a zoom of its own and it wins.
///  * The scale is recomputed in `layout()`, or fitting stops fitting the moment
///    a divider moves.
///  * The percent, and which page is on screen, are shown under the document
///    rather than left to be guessed at.
///
/// What is deliberately not taken is the rest of `DocumentPreview`: its page
/// strip, its rotate and delete buttons, and its Fit Page / Fit Width control.
/// Those edit a scan, and this is a viewer — and the two fit buttons would be a
/// second zoom sitting beside ⌘+, which is the bug the diagram panes had twice
/// this week.
final class PdfFileView: NSView, ScalingPage {
	private let url: URL
	private let pdfView = CapturablePDFView()
	private let caption = NSTextField(labelWithString: "")
	private let notice = NSTextField(labelWithString: "")
	private let spinner = NSProgressIndicator()

	/// The widest page, which is what a fit is measured against. Zero until the
	/// document has been read.
	private var pageWidth: CGFloat = 0
	/// Whether the document is still waiting to be put at the top of page one.
	private var needsFirstScroll = false
	private var watchingSettings: NSObjectProtocol?

	/// How tall the strip under the document is.
	private var captionHeight: CGFloat { Theme.current.scaled(22) }
	private var captionSpace: NSLayoutConstraint!

	init(url: URL) {
		self.url = url
		super.init(frame: .zero)

		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor

		// The pane's own background, not the document's. A PDF is usually white
		// paper on a window that is usually dark, and the paper stays white: the
		// document states its own look, and recolouring it would overrule the
		// person who wrote it — the same rule 0429 settled for diagrams. What the
		// palette gets to decide is everything around the page.
		pdfView.backgroundColor = Theme.current.editorBackground
		// Continuous, because a document in a pane is read by scrolling it. Single
		// page means pressing something to turn every page, and two-up halves a
		// pane that is already half a window.
		pdfView.displayMode = .singlePageContinuous
		pdfView.displaysPageBreaks = true
		pdfView.autoScales = false
		pdfView.translatesAutoresizingMaskIntoConstraints = false

		caption.font = Theme.current.uiFont(11)
		caption.textColor = Theme.current.sidebarText.withAlphaComponent(0.75)
		caption.alignment = .center
		caption.translatesAutoresizingMaskIntoConstraints = false

		notice.font = Theme.current.uiFont(12)
		notice.textColor = Theme.current.sidebarText.withAlphaComponent(0.85)
		notice.alignment = .center
		notice.maximumNumberOfLines = 0
		notice.lineBreakMode = .byWordWrapping
		notice.isHidden = true
		notice.translatesAutoresizingMaskIntoConstraints = false

		spinner.style = .spinning
		spinner.controlSize = .small
		spinner.isDisplayedWhenStopped = false
		spinner.translatesAutoresizingMaskIntoConstraints = false

		addSubview(pdfView)
		addSubview(caption)
		addSubview(notice)
		addSubview(spinner)

		captionSpace = caption.heightAnchor.constraint(equalToConstant: captionHeight)
		NSLayoutConstraint.activate([
			pdfView.topAnchor.constraint(equalTo: topAnchor),
			pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
			pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
			pdfView.bottomAnchor.constraint(equalTo: caption.topAnchor),

			caption.leadingAnchor.constraint(equalTo: leadingAnchor),
			caption.trailingAnchor.constraint(equalTo: trailingAnchor),
			caption.bottomAnchor.constraint(equalTo: bottomAnchor),
			captionSpace,

			notice.centerXAnchor.constraint(equalTo: centerXAnchor),
			notice.centerYAnchor.constraint(equalTo: centerYAnchor),
			notice.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -64),

			spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
			spinner.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18),
		])

		// Which page is on screen, so the count under the document means something
		// while it is being scrolled.
		NotificationCenter.default.addObserver(
			self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView
		)

		// The zoom, and the palette. A PDF may be a tab's whole content or half a
		// split, and only the first of those is walked on ⌘+ — so the pane
		// listens for itself as the diagram panes do, and `applySettings` below is
		// the other route into the same work.
		watchingSettings = NotificationCenter.default.addObserver(
			forName: .abydosSettingsChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.applySettings() }
		}

		load()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		if let watchingSettings { NotificationCenter.default.removeObserver(watchingSettings) }
		NotificationCenter.default.removeObserver(self, name: .PDFViewPageChanged, object: pdfView)
	}

	// MARK: - Reading the file

	/// Reads the document off the main thread.
	///
	/// `PDFDocument(url:)` parses the cross-reference table and the object graph
	/// before it answers, which for a few hundred pages is long enough to be felt
	/// as the window stopping. Nothing after this call is slow: PDFKit renders a
	/// page when it is scrolled to, so a thousand-page document costs the same
	/// first screen as a one-page one.
	private func load() {
		// Only if it takes long enough to be worth saying. A small PDF opens in
		// one frame and a spinner that appeared for that frame would be a flicker.
		let showSpinner = DispatchWorkItem { [weak self] in self?.spinner.startAnimation(nil) }
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: showSpinner)

		let url = self.url
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let opened = PdfPreview.open(url)
			DispatchQueue.main.async {
				showSpinner.cancel()
				guard let self else { return }
				self.spinner.stopAnimation(nil)
				self.finish(opened)
			}
		}
	}

	private func finish(_ opened: PdfPreview.Opened) {
		switch opened {
		case .document(let document):
			pdfView.document = document
			pageWidth = PdfPreview.widestPage(in: document)
			pdfView.isHidden = false
			notice.isHidden = true
			needsFirstScroll = true
			applyScale()
			updateCaption()
		case .trouble(let sentence):
			// One sentence in the middle, rather than an empty grey box that
			// leaves somebody wondering whether the app is still loading.
			pdfView.isHidden = true
			notice.stringValue = sentence
			notice.isHidden = false
			caption.stringValue = ""
		}
	}

	// MARK: - Scale

	override func layout() {
		super.layout()
		// A fit has to be recomputed as the pane changes width, or it stops
		// fitting the moment the divider moves.
		applyScale()
	}

	/// Re-reads the zoom and the palette, the way every pane of the window does.
	func applySettings() {
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		pdfView.backgroundColor = Theme.current.editorBackground
		caption.font = Theme.current.uiFont(11)
		caption.textColor = Theme.current.sidebarText.withAlphaComponent(0.75)
		notice.font = Theme.current.uiFont(12)
		notice.textColor = Theme.current.sidebarText.withAlphaComponent(0.85)
		captionSpace.constant = captionHeight
		applyScale()
		updateCaption()
	}

	private func applyScale() {
		guard pdfView.document != nil, pageWidth > 0 else { return }
		// Room for the scroller, so fitting does not itself produce one.
		let available = pdfView.bounds.width - 24
		guard available > 0 else { return }

		let wanted = PdfPreview.scale(
			pageWidth: pageWidth, paneWidth: available, zoom: Theme.current.scale
		)
		// Only when it actually moved: this runs from `layout()`, and assigning a
		// scale lays the view out again.
		if abs(pdfView.scaleFactor - wanted) > 0.001 {
			pdfView.scaleFactor = wanted
			updateCaption()
		}

		// A document opens at the top of its first page.
		//
		// `PDFView` keeps the middle of what is on screen where it is when the
		// scale changes, which is right while somebody is reading page seven and
		// presses ⌘+ — and wrong for the very first scale a document is ever
		// given, because there is no page seven yet. A window already zoomed to
		// 150% opened every PDF a third of the way down the title page.
		guard needsFirstScroll else { return }
		needsFirstScroll = false
		guard let first = pdfView.document?.page(at: 0) else { return }
		let bounds = first.bounds(for: pdfView.displayBox)
		pdfView.go(to: CGRect(x: 0, y: bounds.maxY - 1, width: 1, height: 1), on: first)
	}

	// MARK: - What it says underneath

	@objc private func pageChanged() { updateCaption() }

	private func updateCaption() {
		guard let document = pdfView.document, document.pageCount > 0 else {
			caption.stringValue = ""
			return
		}
		let percent = Int((pdfView.scaleFactor * 100).rounded())
		guard let page = pdfView.currentPage else {
			caption.stringValue = PdfPreview.caption(
				pages: document.pageCount, scale: pdfView.scaleFactor
			)
			return
		}
		let number = document.index(for: page) + 1
		caption.stringValue = document.pageCount == 1
			? "1 page · \(percent)%"
			: "Page \(number) of \(document.pageCount) · \(percent)%"
	}

	// MARK: - Find in file

	/// Text picked out with the pointer, for seeding the find bar.
	var selectedText: String? { pdfView.currentSelection?.string }

	/// Every place a string occurs, in reading order.
	///
	/// PDFKit's own search, which is the reason a PDF can be searched here at all
	/// — the app's `TextSearch` works on a rope and there is no rope, only pages.
	func find(_ query: String, caseSensitive: Bool) -> [PDFSelection] {
		guard let document = pdfView.document, !query.isEmpty else { return [] }
		var options: NSString.CompareOptions = []
		if !caseSensitive { options.insert(.caseInsensitive) }
		return document.findString(query, withOptions: options)
	}

	/// Paints every match and scrolls to the one being looked at.
	///
	/// The same two colours the code view paints matches in, so a find in a PDF
	/// and a find in a source file look like the same feature: the current match
	/// stronger than the rest, so it is findable at a glance among them.
	func showMatches(_ matches: [PDFSelection], current: Int?) {
		for match in matches { match.color = NSColor.hex(0x5A4A2A) }
		pdfView.highlightedSelections = matches.isEmpty ? nil : matches

		guard let current, matches.indices.contains(current) else {
			pdfView.setCurrentSelection(nil, animate: false)
			return
		}
		// A copy, so the one on screen can be a different colour from its twin in
		// the highlighted set underneath it.
		let selected = matches[current].copy() as? PDFSelection ?? matches[current]
		selected.color = NSColor.hex(0xC77B3B)
		pdfView.setCurrentSelection(selected, animate: false)
		pdfView.scrollSelectionToVisible(nil)
		updateCaption()
	}

	func clearFindSelection() {
		pdfView.highlightedSelections = nil
		pdfView.setCurrentSelection(nil, animate: false)
	}

	// MARK: - For a test that has no window

	/// How many pages are showing, and at what scale — the two things a
	/// screenshot is checked for, so a test can ask for them instead.
	var stateForTesting: (pages: Int, scale: CGFloat, notice: String?) {
		(pdfView.document?.pageCount ?? 0, pdfView.scaleFactor, notice.isHidden ? nil : notice.stringValue)
	}
}

/// A `PDFView` that can be photographed.
///
/// `--screenshot` exists so this app can be looked at without Screen Recording
/// permission, and it works by asking the view tree to draw itself into a
/// bitmap. A `PDFView` does not answer that: its pages go through a tiled layer
/// that renders on its own schedule, and a capture of one is a correctly sized,
/// correctly placed, entirely blank sheet of paper. Both routes were tried —
/// `cacheDisplay(in:to:)` and `CALayer.render(in:)` — and both gave the blank
/// sheet, which is exactly the failure `SnapshotDrawable` was added for when the
/// terminal started rendering through Metal.
///
/// So the capture is drawn here instead, and deliberately from what the view
/// itself says: every page rectangle comes from `convert(_:from:)`, so the
/// picture shows this view's own layout, scale and scroll position, with PDFKit
/// rasterising the same pages into them. Nothing in this is used on screen.
final class CapturablePDFView: PDFView, SnapshotDrawable {
	func snapshotImage(size: CGSize) -> CGImage? {
		guard let document, size.width > 1, size.height > 1 else { return nil }

		// Twice over, so the capture is as sharp as the screen it stands in for.
		let scale: CGFloat = 2
		guard let rep = NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
			colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
		) else { return nil }
		rep.size = NSSize(width: size.width, height: size.height)
		guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = context
		defer { NSGraphicsContext.restoreGraphicsState() }

		let visible = NSRect(origin: .zero, size: size)
		backgroundColor.setFill()
		visible.fill()

		for index in 0 ..< document.pageCount {
			guard let page = document.page(at: index) else { continue }
			let placed = convert(page.bounds(for: displayBox), from: page)
			// The bitmap counts upwards from the bottom whatever this view does.
			let box = isFlipped
				? NSRect(x: placed.minX, y: size.height - placed.maxY,
				         width: placed.width, height: placed.height)
				: placed
			guard box.intersects(visible), box.width > 1, box.height > 1 else { continue }

			NSColor.white.setFill()
			box.fill()
			let pixels = NSSize(width: box.width * scale, height: box.height * scale)
			page.thumbnail(of: pixels, for: displayBox).draw(in: box)
		}

		return rep.cgImage
	}
}
