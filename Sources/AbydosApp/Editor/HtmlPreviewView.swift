import AbydosKit
import AppKit
import WebKit

/// The page an HTML document makes, beside the document.
///
/// The markdown pane with a layout engine behind it: the buffer is rendered,
/// the render follows the typing, and what somebody looks at is a picture of
/// what they are editing. Nothing comes back out of it — this is not draw.io's
/// pane, where the editor owns the document.
///
/// Three things it promises, and each is why a piece of this is here:
///
///  * **The buffer, not the disk.** The document is served out of `HtmlScheme`
///    from a string this pane hands it, so an unsaved edit is on screen. See
///    `HtmlPage.scheme` for the two arrangements that cannot do this.
///  * **Nothing is fetched until somebody asks for it.** A relative reference
///    reaches the scheme handler, which serves it from beside the file or
///    refuses it; an absolute one is blocked by a content rule list, and the
///    page is not loaded at all until that list is in the web view. A page built
///    on a CDN says so rather than rendering unstyled in silence, and offers to
///    load it — which takes the list off for that document and remembers the
///    answer in `AllowedPages`. A driven run fetches nothing whatever is
///    remembered, and says that is why.
///  * **Nothing of the project's runs until the project is trusted.** A page's
///    own `<script>` is the project's code, which is the line `project-trust`
///    draws. The previews this app renders itself are unaffected by trust; this
///    is the one that would run something the project wrote.
final class HtmlPreviewView: NSView, SnapshotDrawable {
	/// The file being shown, whose directory is everything the page may reach.
	private let file: URL
	/// Whether the page's own scripts may run, and what to say when they may not.
	private let trust: TrustDecision
	private let scheme: HtmlScheme
	private let web: WKWebView

	/// What there is instead of a page: loading, or why there is none.
	private let noticeLabel = NSTextField(labelWithString: "")
	/// What there is *beside* a page — the remote references it wanted and the
	/// trust that kept its scripts still. A line at the foot, for the same
	/// reason the diagram pane has one: a toast is gone by the time anybody
	/// wonders why the page looks wrong.
	private let captionLabel = NSTextField(labelWithString: "")
	/// The line is a row rather than a label since 2026-09-22: the sentence, and
	/// at its end the offer to load what was refused.
	private let captionRow = NSStackView()
	private let offerButton = NSButton(title: "", target: nil, action: nil)
	/// What the button would do if pressed, or nil when there is nothing on
	/// offer and the button is out of the row.
	private var offer: HtmlPage.PaneLine.Offer?

	/// The list of documents somebody has let reach the network. Held rather
	/// than asked for each time, so a test can give the pane a store of its own.
	let allowed: AllowedPages

	/// Opening a file the page links to. Set by whoever builds the pane; a pane
	/// that navigated itself would leave the tab bar naming one document while
	/// showing another.
	var onOpenFile: ((URL) -> Void)?

	/// The document as it stands, and what was last actually loaded.
	private var source = ""
	private var loaded: String?
	private var pending: DispatchWorkItem?
	/// Which load is the current one. An edit lands while the last reload is
	/// still reading the scroll position out of the page, and the older one must
	/// not finish on top of the newer.
	private var generation = 0
	/// Where the page was before the reload that is under way.
	private var keptScroll: CGPoint?
	/// Whether what this page may reach has been settled — the blocking list put
	/// on the web view, or deliberately left off for a document somebody allowed.
	/// Nothing is loaded before then: a preview that can neither promise the
	/// network is shut nor say it was asked to open it is not one this app
	/// offers.
	private var isSettled = false
	private var watchingSettings: Any?

	init(file: URL, trust: TrustDecision, allowed: AllowedPages) {
		self.file = file
		self.trust = trust
		self.allowed = allowed
		self.scheme = HtmlScheme(file: file)

		let configuration = WKWebViewConfiguration()
		configuration.setURLSchemeHandler(scheme, forURLScheme: HtmlPage.scheme)
		// The project's own code, which an untrusted project does not get to run.
		// Markup still lays out, so a page is still worth looking at — it is the
		// scripts that are held back, and the caption says so.
		configuration.defaultWebpagePreferences.allowsContentJavaScript = trust.isTrusted
		// Nothing persists. A page in a repository is not a site somebody has an
		// account on, and a preview that left cookies and local storage behind
		// would be keeping state for a file.
		configuration.websiteDataStore = .nonPersistent()
		web = WKWebView(frame: .zero, configuration: configuration)

		super.init(frame: .zero)

		web.translatesAutoresizingMaskIntoConstraints = false
		web.navigationDelegate = self
		web.allowsBackForwardNavigationGestures = false
		// Hidden until something has loaded: an empty white rectangle where a
		// page should be says nothing, and the sentence behind it says what is
		// happening.
		web.isHidden = true
		addSubview(web)

		noticeLabel.alignment = .center
		noticeLabel.maximumNumberOfLines = 0
		noticeLabel.lineBreakMode = .byWordWrapping
		noticeLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(noticeLabel)

		captionLabel.alignment = .center
		captionLabel.maximumNumberOfLines = 1
		// From the tail, not the middle. Photographed truncating in the middle in
		// a 580-point pane: "2 remote references were not loaded — the first
		// i…://cdn.jsdelivr.net/npm/water.css" — which ate the words that say
		// what the address *is* and kept the end of a URL nobody needs to read.
		// The count and the host are the two things worth having, and both are at
		// the front.
		captionLabel.lineBreakMode = .byTruncatingTail
		captionLabel.translatesAutoresizingMaskIntoConstraints = false

		// The offer, at the trailing end of the line it belongs to. Asked for
		// 2026-09-22 against a page that had lost its typeface one reference
		// short: "this is fine — but maybe it would be good to have a button to
		// allow it".
		offerButton.bezelStyle = .inline
		offerButton.controlSize = .small
		offerButton.target = self
		offerButton.action = #selector(offerPressed)
		offerButton.translatesAutoresizingMaskIntoConstraints = false
		// It keeps its title's width whatever the sentence beside it wants, and
		// the sentence takes what is left — which is why the label truncates and
		// the button never does.
		offerButton.setContentCompressionResistancePriority(.required, for: .horizontal)
		offerButton.setContentHuggingPriority(.required, for: .horizontal)

		captionRow.orientation = .horizontal
		captionRow.alignment = .centerY
		captionRow.spacing = 8
		captionRow.translatesAutoresizingMaskIntoConstraints = false
		captionRow.setViews([captionLabel, offerButton], in: .leading)
		addSubview(captionRow)

		NSLayoutConstraint.activate([
			web.leadingAnchor.constraint(equalTo: leadingAnchor),
			web.trailingAnchor.constraint(equalTo: trailingAnchor),
			web.topAnchor.constraint(equalTo: topAnchor),
			web.bottomAnchor.constraint(equalTo: captionRow.topAnchor),

			noticeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
			noticeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			noticeLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),

			captionRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
			captionRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
			captionRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
		])

		notice = "Rendering \(file.lastPathComponent)…"
		applyTheme()

		// The zoom and the palette, which this pane follows like every other. A
		// preview sits inside a split rather than being a tab's own view, so the
		// walk that visits a tab's page on ⌘+ does not reach one — it listens for
		// itself, exactly as `DiagramPaneView` does.
		watchingSettings = NotificationCenter.default.addObserver(
			forName: .abydosSettingsChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.applyTheme() }
		}

		// What this document may reach, settled before anything is loaded. A pane
		// built for a file somebody already allowed never puts the list on at
		// all, so an allowed page does not come up refused and correct itself a
		// moment later.
		Task { [weak self] in
			guard let self, await self.settleWhatThePageMayReach() else { return }
			self.render()
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit {
		pending?.cancel()
		if let watchingSettings {
			NotificationCenter.default.removeObserver(watchingSettings)
		}
	}

	// MARK: - The document

	/// A new state of the buffer. Debounced, because a document half way through
	/// being typed is not a document — the Mermaid pane's argument, and the same
	/// 0.3 s the markdown pane uses.
	func show(_ text: String) {
		source = text
		pending?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.render() }
		pending = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
	}

	/// Puts the blocking list on this pane's web view, or takes it off, to match
	/// what the document is allowed.
	///
	/// Removing the list rather than compiling a permissive one: the effect is
	/// the same and a second list is a second thing to keep right. The web view
	/// is this pane's own, so nothing here can reach another document.
	///
	/// - Returns: whether the page may be loaded at all. False is a build whose
	///   rule list would not compile, which is the one case where this app has
	///   no way to promise the network is shut — so it shows nothing rather than
	///   a page it cannot make that promise about.
	@discardableResult
	private func settleWhatThePageMayReach() async -> Bool {
		let controller = web.configuration.userContentController
		guard !allowed.isAllowed(file) else {
			controller.removeAllContentRuleLists()
			isSettled = true
			return true
		}
		guard let list = await HtmlBlocking.list() else {
			notice = "This build could not compile the rule that keeps a preview "
				+ "off the network, so the page was not shown."
			isSettled = false
			return false
		}
		controller.removeAllContentRuleLists()
		controller.add(list)
		isSettled = true
		return true
	}

	/// The offer was pressed: remember it, or forget it, and show the page again
	/// under the answer.
	@objc private func offerPressed() {
		switch offer {
		case .load:  allowed.allow(file)
		case .block: allowed.forget(file)
		case nil:    return
		}
		Task { [weak self] in
			guard let self, await self.settleWhatThePageMayReach() else { return }
			// The same text, under a different policy — so the guard that stops a
			// pointless reload has to be told this is not one.
			self.loaded = nil
			self.render()
		}
	}

	/// Loads what `source` holds, keeping the page where it was.
	private func render() {
		guard isSettled, source != loaded else { return }
		loaded = source
		scheme.document = source
		sayWhatThisPageReaches()

		generation += 1
		let mine = generation
		guard let address = HtmlPage.address(of: file) else { return }
		Task { [weak self] in
			guard let self else { return }
			// Where the reader was. Asked of the page rather than of the scroll
			// view, because the page is the thing that scrolls — and asked
			// *before* the load, since after it there is nothing left to ask.
			let scroll = await self.pageScroll()
			guard self.generation == mine else { return }
			self.keptScroll = scroll
			self.web.load(URLRequest(url: address))
		}
	}

	private func pageScroll() async -> CGPoint? {
		guard loadedOnce else { return nil }
		let answer = try? await web.evaluateJavaScript("[window.scrollX, window.scrollY]")
		guard let pair = answer as? [Double], pair.count == 2 else { return nil }
		return CGPoint(x: pair[0], y: pair[1])
	}

	private var loadedOnce = false

	// MARK: - What the pane says

	private var notice: String? {
		didSet {
			noticeLabel.stringValue = notice ?? ""
			noticeLabel.isHidden = notice?.isEmpty ?? true
			web.isHidden = !(notice?.isEmpty ?? true)
		}
	}

	/// The line at the foot: what this document reaches, and the trust that is
	/// keeping its scripts still.
	///
	/// Two rules about two different things, said side by side because that is
	/// the one place somebody sees the difference. Fetching a stylesheet does not
	/// run the project's code, so an allowed page in an untrusted project fetches
	/// its fonts and still runs no script.
	private func sayWhatThisPageReaches() {
		let line = HtmlPage.line(
			references: HtmlPage.remoteReferences(in: source),
			allowed: allowed.isRemembered(file),
			driven: allowed.isHeldBackByDrivenRun
		)
		var said: [String] = []
		if let reach = line.said { said.append(reach) }
		// The same sentence every other refusal in this window says, offering the
		// same one gesture. A second wording for the same rule teaches somebody
		// that they are two different rules.
		if let untrusted = trust.said { said.append(untrusted) }

		offer = line.offer
		offerButton.title = line.offer?.title ?? ""
		offerButton.isHidden = line.offer == nil
		caption = said.isEmpty ? nil : said.joined(separator: "  ")
	}

	private var caption: String? {
		didSet {
			guard caption != oldValue else { return }
			captionLabel.stringValue = caption ?? ""
			captionLabel.isHidden = caption == nil
			// A foot with nothing in it takes no room from the page, and the stack
			// is what decides that: `NSStackView` closes up around a *hidden*
			// arranged view, which is `DiagramPaneView`'s note in its own words.
			//
			// **Not a height constraint set from `fittingSize`.** That is what this
			// was, and it measured zero — the row is asked before it has laid out —
			// so the line was set, reported, and drawn nowhere. Photographed with
			// the page filling the pane and the sentence missing, and found by
			// putting the row's height into the pane's own report.
			needsLayout = true
		}
	}

	/// Presses the offer as somebody would, and says what it was.
	///
	/// The button's own action rather than a second path to the same effect: a
	/// driven check that took a shortcut would be checking a mechanism nobody
	/// uses.
	func pressOfferForTesting() -> String {
		guard let offer else { return "nothing — there is no offer on this page" }
		offerPressed()
		return offer.title
	}

	/// What the pane is showing, for a driven run to report.
	///
	/// Never a bare "not found": which state the line is in, what it says and
	/// what the button offers, so a run that photographs the wrong one says
	/// which one it got.
	var reportForTesting: String {
		// The row's height as well as its words. A line that is set and not shown
		// is the way this goes wrong — photographed exactly once, with the page
		// filling the pane and the sentence nowhere — and a report of the words
		// alone says everything is fine.
		"html \(file.lastPathComponent) allowed=\(allowed.isRemembered(file)) "
			+ "fetching=\(allowed.isAllowed(file)) offer=\(offer?.title ?? "none") "
			+ "line=\(Int(captionRow.frame.height))pt "
			+ "button=\(offerButton.isHidden ? "hidden" : Int(offerButton.frame.width).description) "
			+ "said=\(caption ?? "nothing")"
	}

	// MARK: - Being photographed

	/// A picture of the page, for a capture that cannot see one.
	///
	/// `cacheDisplay(in:to:)` walks the view tree and draws what is in it, and a
	/// web view's content is composited out of this process — so a driven
	/// screenshot of this pane came out as the pane's own background with the
	/// caption underneath it, and nothing said why. Photographed exactly that,
	/// four times, before `WindowCapture`'s protocol was remembered.
	///
	/// `DrawioPreviewView` does the same thing for the same reason, down to the
	/// run loop turned by hand: `takeSnapshot` answers on the main queue and the
	/// capture that asked cannot return until it has.
	func snapshotImage(size: CGSize) -> CGImage? {
		guard loadedOnce, !web.isHidden, size.width > 1, size.height > 1,
		      bounds.width > 1, bounds.height > 1,
		      let page = pagePicture()
		else { return nil }

		// A picture of the pane, not of the page: the capture draws what comes
		// back over the *view's* whole rectangle, and the page is only the part
		// of it above the caption. Painted into place on a clear ground, so the
		// line at the foot — which AppKit drew perfectly well — is still there
		// underneath.
		let scale = CGSize(width: size.width / bounds.width, height: size.height / bounds.height)
		let pageRect = CGRect(
			x: web.frame.minX * scale.width, y: web.frame.minY * scale.height,
			width: web.frame.width * scale.width, height: web.frame.height * scale.height
		)
		let canvas = NSImage(size: size)
		canvas.lockFocus()
		NSImage(cgImage: page, size: pageRect.size).draw(in: pageRect)
		canvas.unlockFocus()
		return canvas.cgImage(forProposedRect: nil, context: nil, hints: nil)
	}

	/// The page itself, waited for. `takeSnapshot` answers on the main queue and
	/// the capture that asked cannot return until it has, so the run loop is
	/// turned by hand — `DrawioPreviewView` does the same, for the same reason.
	private func pagePicture() -> CGImage? {
		let configuration = WKSnapshotConfiguration()
		configuration.rect = web.bounds
		configuration.snapshotWidth = NSNumber(value: Double(web.bounds.width))

		var made: CGImage?
		var answered = false
		web.takeSnapshot(with: configuration) { image, _ in
			made = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
			answered = true
		}
		let deadline = Date().addingTimeInterval(10)
		while !answered, Date() < deadline {
			RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
		}
		return made
	}

	// MARK: - The theme and the zoom

	/// Told, never rebuilt. Reloading the page to follow a palette would take
	/// the scroll position and whatever state the page's own script holds, which
	/// is 0423's lesson in `DrawioPreviewView`'s words.
	private func applyTheme() {
		let theme = Theme.current
		wantsLayer = true
		layer?.backgroundColor = theme.editorBackground.cgColor
		noticeLabel.font = theme.uiFont(12)
		noticeLabel.textColor = theme.sidebarText.withAlphaComponent(0.85)
		captionLabel.font = theme.uiFont(11)
		captionLabel.textColor = theme.sidebarText.withAlphaComponent(0.7)
		// The zoom, which is the app's own and not a second one of this pane's.
		web.pageZoom = theme.scale
		// A page that asks `prefers-color-scheme` gets the app's answer. This is
		// the appearance of the view, so it costs no reload and the page's own
		// colours, where it states them, are untouched.
		web.appearance = NSAppearance(named: theme.isLight ? .aqua : .darkAqua)
	}
}

// MARK: - Where a click goes

extension HtmlPreviewView: WKNavigationDelegate {
	/// The pane shows one document and never navigates.
	///
	/// A link off this machine goes to the browser, which is what a link in the
	/// markdown preview already does. A link to a file beside it opens that
	/// file, so that the tab bar never names one document while the pane shows
	/// another — `design.md` left that open and this is the answer, for the
	/// reason the tab bar gives.
	func webView(
		_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
		decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
	) {
		guard let url = action.request.url else {
			decisionHandler(.cancel)
			return
		}
		let clicked = action.navigationType == .linkActivated
		guard url.scheme == HtmlPage.scheme else {
			// Anything else is refused. Only a click is worth handing on: a page
			// that tried to *navigate* itself somewhere remote is doing something
			// nobody asked for, and opening a browser for it would make a preview
			// a way to be taken somewhere.
			if clicked { LinkOpener.open(url) }
			decisionHandler(.cancel)
			return
		}
		// The document itself, including an anchor into it.
		if HtmlPage.isDocument(path: url.path, of: file) || !clicked {
			decisionHandler(.allow)
			return
		}
		decisionHandler(.cancel)
		guard let neighbour = HtmlPage.file(
			at: url.path, under: file.deletingLastPathComponent()
		), FileManager.default.fileExists(atPath: neighbour.path) else { return }
		onOpenFile?(neighbour)
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		loadedOnce = true
		notice = nil
		guard let scroll = keptScroll else { return }
		keptScroll = nil
		// Where the reader was before the edit. A reload starts at the top, so a
		// word typed near the end of a long page would otherwise throw them back
		// to the beginning of it.
		web.evaluateJavaScript("window.scrollTo(\(scroll.x), \(scroll.y))")
	}

	func webView(
		_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
	) {
		notice = "This page could not be shown: \(error.localizedDescription)"
	}

	func webView(
		_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
		withError error: Error
	) {
		notice = "This page could not be shown: \(error.localizedDescription)"
	}
}
