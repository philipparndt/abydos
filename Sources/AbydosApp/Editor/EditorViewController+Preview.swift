import AppKit
import CryptoKit
import QuickLookUI
import GoSTL
import AbydosKit
import SwiftUI

/// The Markdown preview beside the source, and what keeps the two in step.
extension EditorViewController {
	// MARK: - Markdown preview

	/// Swaps the active markdown tab between source and rendered preview.
	/// Cycles a markdown tab between source and preview, for the menu command.
	func toggleMarkdownPreview() {
		guard let tab = activeTab, tab.isMarkdown else { return }
		setPreviewMode(tab.previewMode == .source ? .preview : .source)
	}

	/// Shows a file's source, its rendered form, or both.
	func setPreviewMode(_ mode: PreviewMode) {
		guard let tab = activeTab, let index = activeIndex else { return }
		guard availableModes(for: tab).contains(mode) else { return }
		guard mode != tab.previewMode else { return }

		tab.previewMode = mode
		tab.contentView = makeContentView(for: tab, mode: mode)

		activeIndex = nil
		activate(index: index, focusEditor: mode == .source)
	}

	/// Which modes a tab's file can be shown in.
	///
	/// Asked of the *tab* rather than of the URL, because one file's answer is not in
	/// its name: a `.yaml` has a rendered form when it is a go3mf recipe, and the tab
	/// is where that was decided, once, when it opened.
	func availableModes(for tab: Tab) -> [PreviewMode] {
		FilePreview.availableModes(for: tab.url, facts: tab.previewFacts)
	}

	/// The view for a tab in a given mode, with the divider a session remembered
	/// or down the middle.
	func makeContentView(
		for tab: Tab, mode: PreviewMode, dividerFraction: Double? = nil
	) -> NSView {
		let source = tab.sourceView
		guard mode != .source else { return source ?? tab.contentView }

		let preview = makePreview(for: tab)
		guard mode.isSplit, let source else { return preview }

		// Source first: reading order, and the thing being edited stays where
		// it was whichever way the pane is divided.
		let split = PreviewSplitView()
		split.isVertical = mode.splitsSideBySide
		split.dividerStyle = .thin
		split.addArrangedSubview(source)
		split.addArrangedSubview(preview)

		// The split has no size yet — it is not in a window — so the fraction is
		// left with it and spent at its first real layout. This used to be a
		// half-and-half computed a runloop turn later, which found a size only
		// because the tab happened to be the one in front; the split built for a
		// tab behind it measured zero, gave up, and lived on whatever
		// `adjustSubviews` had left.
		//
		// Half for a model too, which 0483 tried to change and measured its way
		// back from. A mesh looks like it wants the larger half — it is being
		// turned around, where a line of OpenSCAD is narrow — and at 0.4 the file
		// that asked for this feature was clipped while the viewport around the
		// part had margins to spare. A 3D view zooms to fit, so it degrades
		// gracefully with less width; text stops at a hard edge. And the longest
		// line of the median `.scad` in the owner's own 493 of them is 93 columns,
		// which no fraction of a 970 pt pane fits — so the divider is not the
		// lever, and half is the answer for the same reason it is everywhere else.
		split.wantedFraction = dividerFraction.map { CGFloat($0) } ?? 0.5
		return split
	}

	/// The rendered form of a file, whichever kind it has.
	private func makePreview(for tab: Tab) -> NSView {
		switch FilePreview.kind(for: tab.url, facts: tab.previewFacts) {
		case .model:
			// A provisional tab waits before rendering; one somebody committed to
			// does not. `makeModelView` says why the wait exists at all.
			//
			// A go3mf recipe arrives here too, as the `.yaml` it is: GoSTL runs
			// `go3mf build` on it into a temporary directory of its own, watches the
			// recipe, and rebuilds when it changes. None of that is here, and since
			// 0.22.0 none of it writes into the project either.
			//
			// A Cadova model does not, and cannot: there is no file for the viewer
			// to open until a program has been built and run. Its pane does that
			// first and hosts the same viewer afterwards — see `CadovaPreviewView`.
			let waiting = tab.isPreview ? Self.provisionalRenderDelay : 0
			if let cadova = tab.cadova {
				let view = CadovaPreviewView(model: cadova)
				view.startAfter = waiting
				return view
			}
			return makeModelView(for: tab.url, startAfter: waiting)
		case .image:
			return ImageFileView(url: tab.url)
		case .plantuml:
			return makeDiagramView(for: tab)
		case .mermaid:
			return makeMermaidView(for: tab)
		case .drawio:
			return makeDrawioView(for: tab)
		case .pdf:
			return PdfFileView(url: tab.url)
		case .video:
			return VideoFileView(url: tab.url)
		case .markdown, .none:
			return makePreviewView(for: tab)
		}
	}

	private func makePreviewView(for tab: Tab) -> NSView {
		let textView = MarkdownPreviewTextView()
		// Which document this is, and where its text is — the pane's own `Export ▸`
		// writes the diagrams in it beside it, and draws the buffer rather than
		// what is on disk, exactly as the `.mmd` pane does.
		textView.fileURL = tab.url
		textView.markdownSource = { [weak tab] in tab?.document?.rope.string }
		textView.isEditable = false
		textView.isSelectable = true
		textView.drawsBackground = true
		textView.backgroundColor = Theme.current.editorBackground
		textView.textColor = Theme.current.editorText
		textView.linkTextAttributes = [
			.foregroundColor: Theme.current.gitModified,
			.underlineStyle: NSUnderlineStyle.single.rawValue,
			.cursor: NSCursor.pointingHand,
		]
		textView.textContainerInset = NSSize(width: 28, height: 24)
		textView.isRichText = true

		let scrollView = NSScrollView()
		scrollView.documentView = textView
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		scrollView.scrollerStyle = .overlay

		// Width-tracking so text reflows with the pane.
		textView.autoresizingMask = [.width]
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.textContainer?.widthTracksTextView = true

		renderPreview(into: textView, tab: tab)

		// Keep the preview current while the source is edited.
		tab.document?.onSyntaxUpdated = { [weak self, weak tab, weak textView] in
			guard let self, let tab, let textView, tab.isShowingMarkdownPreview else { return }
			self.schedulePreviewRefresh(textView: textView, tab: tab)
		}

		// A ```mermaid fence is drawn in a web view and arrives after the page it
		// belongs on has already been laid out. The document is rendered again
		// when it does — which finds the drawing in the cache this time and puts
		// it where the "drawing this diagram" line was. The refresh is the same
		// debounced one the typing uses, so a document of twenty fences settles in
		// a handful of renders rather than twenty, and the scroll position is kept
		// across each of them.
		textView.whenDiagramDrawn { [weak self, weak tab, weak textView] in
			guard let self, let tab, let textView, tab.isShowingMarkdownPreview else { return }
			self.schedulePreviewRefresh(textView: textView, tab: tab)
		}
		return scrollView
	}

	/// The diagram a PlantUML file describes, kept current while it is edited.
	private func makeDiagramView(for tab: Tab) -> NSView {
		let view = PlantUMLPreviewView(projectRoot: project?.root)
		// Which file this is a picture of: the pane's own menu writes the picture
		// beside it, and a pane that did not know would have nowhere to write.
		view.fileURL = tab.url
		if let document = tab.document {
			view.show(document.rope.string)

			// Every edit, not every reparse: PlantUML has no grammar here, so
			// there is no parser whose finishing could be waited for. Drawing
			// means starting a JVM, so the view debounces on top of this.
			document.onTextChanged = { [weak view, weak document] in
				guard let view, let document else { return }
				view.show(document.rope.string)
			}
		}
		return view
	}

	/// The diagram a Mermaid file describes, kept current while it is edited.
	///
	/// The same shape as the PlantUML one beside it. What is different is
	/// underneath: nothing is discovered, nothing is fetched, and the pane needs
	/// no project to find a tool in — Mermaid is in the app.
	private func makeMermaidView(for tab: Tab) -> NSView {
		let view = MermaidPreviewView()
		view.fileURL = tab.url
		if let document = tab.document {
			view.show(document.rope.string)
			document.onTextChanged = { [weak view, weak document] in
				guard let view, let document else { return }
				view.show(document.rope.string)
			}
		}
		return view
	}

	/// A `.drawio` open in draw.io's own editor.
	///
	/// The other two diagram panes are given the text and draw a picture of it.
	/// This one is given the text and *is* the editor, so the wiring runs both
	/// ways: the document goes in, and what somebody draws comes back out into
	/// the same `TextDocument` every other tab uses. Nothing else in this
	/// controller knows the difference — the dot, ⌘S, the close prompt and
	/// auto-save all read `document.isDirty` as they always did.
	private func makeDrawioView(for tab: Tab) -> NSView {
		let view = DrawioPreviewView()
		view.fileURL = tab.url
		view.document = tab.document
		if let document = tab.document {
			view.show(document.rope.string)
			// Somebody else wrote the file — a `git checkout` on a branch with a
			// different diagram. The editor is given the new document, and
			// whatever was in draw.io's undo stack goes with it, which is the
			// same trade the text editor makes when it reloads.
			document.onTextChanged = { [weak view, weak document] in
				guard let view, let document else { return }
				view.show(document.rope.string)
			}
		}
		view.onEdited = { [weak self] in self?.refreshTabBar() }
		view.onSaveRequested = { [weak self] in self?.save() }
		return view
	}

	/// The diagram pane the file in front is showing, when it is showing one.
	///
	/// Found rather than kept: the pane may be the tab's whole content or one
	/// half of a split, and which of those it is changes with the preview mode.
	/// Either kind of diagram, because everything asking this — the Export
	/// command, the menu it offers — wants the pane rather than the tool.
	var diagramPreview: DiagramPaneView? { activeTab.flatMap { Self.pane(in: $0.contentView) } }

	/// The Cadova pane the file in front is showing, when it is showing one.
	///
	/// Found the same way and for the same reason as `diagramPreview`: it is half
	/// of a split or the whole of a tab, depending on the preview mode.
	var cadovaPreview: CadovaPreviewView? { activeTab.flatMap { Self.pane(in: $0.contentView) } }

	/// The picture pane the file in front is showing, when it is showing one.
	///
	/// A PNG is a tab's whole content and an SVG is half a split — the same two
	/// shapes a diagram comes in, and the same reason this is a search rather
	/// than something kept.
	var imagePreview: ImageFileView? { activeTab.flatMap { Self.pane(in: $0.contentView) } }

	/// The player the file in front is showing, when it is showing one.
	var videoPreview: VideoFileView? { activeTab.flatMap { Self.pane(in: $0.contentView) } }

	/// The first pane of a kind anywhere under a view.
	///
	/// One walk rather than one per kind: the three above differ only in the type
	/// they are looking for, and a fourth copy of the same six lines is how the
	/// three of them come to disagree about what "under" means.
	static func pane<Found: NSView>(in view: NSView) -> Found? {
		if let pane = view as? Found { return pane }
		for subview in view.subviews {
			if let found: Found = pane(in: subview) { return found }
		}
		return nil
	}

	/// What the tab in front actually is, when something looking for a pane in it
	/// did not find one.
	///
	/// **A driver that can only say "not found" lies by omission**, and 0507 is
	/// what that costs: `--cadova-watch` said `no cadova pane in the tab in front`
	/// for a file that had one built for it, and the report was believed for long
	/// enough to be written into an item as evidence. It was true and useless —
	/// the tab in front was not the file at all. So the negative answer now comes
	/// with the tab it was asked about, the mode that tab is in, and the classes
	/// in its content view, which between them say *which* of the possible reasons
	/// it is.
	/// Opens Quick Look on a binary-file notice, and says whether the panel came
	/// up — which is the half that cannot be photographed, since the panel is a
	/// window of its own and the shot is of this one.
	func quickLookForTesting() -> String {
		guard let tab = activeTab else { return "no tab" }
		guard let notice: FileNoticeView = Self.pane(in: tab.contentView) else {
			return "no notice view in \(tab.url.lastPathComponent)"
		}
		notice.showQuickLook()
		// **Asked a moment later, not in this turn.** `makeKeyAndOrderFront`
		// starts the handshake — the panel becomes key, then walks the responder
		// chain asking who wants to control it — and none of that has happened
		// by the time this line runs. Read synchronously it says `dataSource=none`
		// about a panel that is about to be handed over perfectly well.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak notice] in
			let panel = QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil
			print("QUICKLOOK settled: panel=\(panel?.isVisible == true ? "open" : "not open") "
				+ "controlling=\(panel?.dataSource === notice ? "the notice" : "somebody else") "
				+ "showing=\((panel?.currentPreviewItem?.previewItemURL?.lastPathComponent) ?? "nothing")")
			fflush(stdout)
		}
		return "asked for \(notice.urlForTesting.lastPathComponent)"
	}

	func doubleClickTabForTesting(index: Int) -> String {
		tabBar.doubleClickForTesting(index: index)
	}

	var activeTabDescriptionForTesting: String {
		let open = "open=[" + tabs.map(\.url.lastPathComponent).joined(separator: " ") + "]"
		guard let tab = activeTab else {
			return "no active tab (\(tabs.count) tabs, group \(groupID.uuidString.prefix(4))) \(open)"
		}
		return "tab=\(tab.url.path) mode=\(tab.previewMode) "
			+ "cadova=\(tab.cadova?.product ?? "none") \(open) "
			+ "content=[\(Self.classes(in: tab.contentView).joined(separator: " "))]"
	}

	/// The class names in a view tree, outermost first, for a driver's report.
	private static func classes(in view: NSView, depth: Int = 0) -> [String] {
		// Two levels of subviews is enough to tell a split from a scroll view and
		// far short of the hundreds a code view holds.
		guard depth < 3 else { return [] }
		return [String(describing: type(of: view))]
			+ view.subviews.flatMap { classes(in: $0, depth: depth + 1) }
	}

	/// The rendered Markdown pane the file in front is showing, when it is
	/// showing one.
	///
	/// Found the same way and for the same reason as `diagramPreview`: a Markdown
	/// document full of ```` ```mermaid ```` fences has an `Export ▸` of its own,
	/// and the pane it hangs on is the tab's whole content or half of a split
	/// depending on the preview mode.
	var markdownPreview: MarkdownPreviewTextView? {
		activeTab.flatMap { Self.markdownPane(in: $0.contentView) }
	}

	private static func markdownPane(in view: NSView) -> MarkdownPreviewTextView? {
		if let pane = view as? MarkdownPreviewTextView { return pane }
		for subview in view.subviews {
			if let found = markdownPane(in: subview) { return found }
		}
		return nil
	}

	private func renderPreview(into textView: NSTextView, tab: Tab) {
		guard let document = tab.document else { return }
		let rendered = MarkdownRenderer.render(
			document.rope.string,
			// Relative links and images resolve against the file's directory.
			baseURL: tab.url.deletingLastPathComponent()
		)
		textView.textStorage?.setAttributedString(rendered)
	}


	/// Debounced: re-rendering the whole document on every keystroke would undo
	/// the point of the incremental editor.
	private func schedulePreviewRefresh(textView: NSTextView, tab: Tab) {
		previewRefreshWork?.cancel()
		let work = DispatchWorkItem { [weak textView, weak tab] in
			guard let textView, let tab else { return }
			let offset = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
			self.renderPreview(into: textView, tab: tab)
			// Preserve the scroll position across the re-render.
			textView.enclosingScrollView?.contentView.scroll(to: offset)
		}
		previewRefreshWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
	}

	/// True when the active tab is markdown, so the UI can offer the toggle.
	var canPreviewMarkdown: Bool { activeTab?.isMarkdown ?? false }
	var isShowingMarkdownPreview: Bool { activeTab?.isShowingMarkdownPreview ?? false }

	/// How long a provisional tab's model pane waits before it renders anything.
	///
	/// The same 0.4 s `PlantUMLPreviewView` debounces by, and for the same
	/// reason: arrowing down a directory gives each file a provisional tab that
	/// lives for as long as the next keypress takes, and a walk must not cost one
	/// render per row. 0470 measured that shape for usages and found the traffic
	/// was one `didOpen` per *file crossed* — which is the good answer there and
	/// the bad one here, because every row of a directory of models is a
	/// different file.
	private static let provisionalRenderDelay: TimeInterval = 0.4

	/// A tab showing a 3D model, hosted from GoSTL.
	///
	/// The viewer is a SwiftUI view from a package rather than a second
	/// application, so it lives in a tab beside the code like any other file.
	/// Hosts the 3D viewer on the editor's own background.
	///
	/// A SwiftUI view leaves its unpainted regions transparent, which against
	/// the window shows through as a different shade from the code beside it.
	/// The container settles that without GoSTL having to know about it.
	///
	/// The hosting view is built by the container rather than here, once the pane
	/// has actually been on screen for `startAfter`. Loading a model is not free
	/// and a `.scad` is the expensive end of it — GoSTL runs OpenSCAD, and it
	/// does so on the main actor, so however long the render takes is time this
	/// window is not drawing. Since 0483 that happens without being asked for,
	/// which is only affordable if it happens once for the file somebody stopped
	/// at rather than once for every file they went past.
	private func makeModelView(for fileURL: URL, startAfter: TimeInterval = 0) -> NSView {
		let container = ModelContainerView(color: Theme.current.editorBackground)
		container.startAfter = startAfter
		container.modelPath = fileURL.path
		container.makeViewer = { [weak container] in
			// The viewer sits in a pane rather than a window of its own: it takes
			// the editor's background so the split reads as one surface, and keeps
			// its menu panel folded away, since the panel is wider than the pane
			// often is.
			let hosting = NSHostingView(rootView: ContentView(
				fileURL: fileURL,
				embedding: ContentView.EmbeddingOptions(
					backgroundColor: Theme.current.editorBackground,
					showsMenuPanel: false,
					// Kept so a screenshot of this window can include the model.
					snapshotHandle: { [weak container] provider in container?.snapshot = provider }
				)
			))

			// Kept out of Auto Layout on purpose. NSHostingView publishes the
			// SwiftUI view's size as constraints and invalidates them from inside
			// the window's own constraint pass; splitting the editor re-parents the
			// view during exactly that pass, and AppKit raises rather than
			// re-entering it. The container sizes it directly instead, which is how
			// the rest of the editor lays out anyway.
			hosting.sizingOptions = []
			hosting.translatesAutoresizingMaskIntoConstraints = true
			return hosting
		}
		return container
	}

	/// Shows a view of the app's own in a tab, or brings back the one that is
	/// already open.
	///
	/// A page that wants to follow the zoom says so by being a `ScalingPage`;
	/// one that does not is left exactly as it is.
	///
	/// The URL is a name rather than a file: two pages must not collide, and a
	/// tab is found by it.
	@discardableResult
	func openPage(_ view: NSView, title: String, identifier: String, symbol: String = "square.grid.2x2") -> NSView {
		let url = URL(fileURLWithPath: "/ideai/page/" + identifier)
		if let index = tabs.firstIndex(where: { $0.pageTitle != nil && $0.url == url }) {
			activeIndex = nil
			activate(index: index, focusEditor: false)
			return tabs[index].contentView
		}

		let tab = Tab(url: url, document: nil, codeView: nil, contentView: view, isPreview: false)
		tab.pageTitle = title
		tab.pageSymbol = symbol
		tabs.append(tab)
		activeIndex = nil
		activate(index: tabs.count - 1, focusEditor: false)
		refreshTabBar()
		return view
	}

	/// Renames an open page and gives it a line under the name — a compare
	/// page whose sides moved, or whose counts arrived.
	func retitlePage(_ view: NSView, title: String, subtitle: String) {
		guard let index = tabs.firstIndex(where: { $0.contentView === view && $0.pageTitle != nil }) else { return }
		tabs[index].pageTitle = title
		tabs[index].pageSubtitle = subtitle
		refreshTabBar()
	}

	/// The page in front, if the active tab is one.
	var activePageView: NSView? {
		guard let tab = activeTab, tab.pageTitle != nil else { return nil }
		return tab.contentView
	}

	/// Whether the tab in front is a file as such: not a page, not a diff,
	/// not an entry of an archive.
	var activeTabIsPlainFile: Bool {
		guard let tab = activeTab else { return false }
		return tab.pageTitle == nil && !tab.isDiff && tab.archiveOrigin == nil
	}

	/// Whether a point of this group is over the document rather than the
	/// tab strip — the strip is where a file is dropped to be opened.
	func isOverDocument(_ point: NSPoint) -> Bool {
		guard let tabBar else { return true }
		return !tabBar.frame.contains(point)
	}

	/// The open page with this identifier, if it is open, whatever kind it is.
	func page(identifier: String) -> NSView? {
		let url = URL(fileURLWithPath: "/ideai/page/" + identifier)
		return tabs.first { $0.pageTitle != nil && $0.url == url }?.contentView
	}

	/// The identifiers of the pages open here, in tab order.
	///
	/// Off the same synthetic path `openPage` writes: the identifier is the last
	/// component, which is what makes a page reopenable at all — the *path* is
	/// nothing to reopen, and that is why pages are not in `captureSession`.
	func openPageIdentifiers() -> [String] {
		tabs.filter { $0.pageTitle != nil }.map { $0.url.lastPathComponent }
	}

	/// A tab showing a picture.
	///
	/// An SVG keeps its source: the control offers it and a split, since it is
	/// a drawing somebody may well have written by hand. A PNG has none, so the
	/// tab is the picture and nothing else.
	func makeImageTab(for fileURL: URL, preview: Bool) -> Tab {
		let tab = Tab(
			url: fileURL,
			document: nil,
			codeView: nil,
			contentView: ImageFileView(url: fileURL),
			isPreview: preview
		)
		tab.previewMode = .preview
		return tab
	}

	/// A tab that is the player, paused — see `VideoFileView` for why it never
	/// starts by itself.
	func makeVideoTab(for fileURL: URL, preview: Bool) -> Tab {
		let tab = Tab(
			url: fileURL,
			document: nil,
			codeView: nil,
			contentView: VideoFileView(url: fileURL),
			isPreview: preview
		)
		tab.previewMode = .preview
		return tab
	}

	/// A tab showing a PDF.
	///
	/// Like a picture's: the tab is the document and nothing else, since a PDF
	/// has no source half to offer and nothing here writes one.
	func makePdfTab(for fileURL: URL, preview: Bool) -> Tab {
		let tab = Tab(
			url: fileURL,
			document: nil,
			codeView: nil,
			contentView: PdfFileView(url: fileURL),
			isPreview: preview
		)
		tab.previewMode = .preview
		return tab
	}

	/// A tab that is nothing but the model — a mesh, which has no source half.
	///
	/// The wait applies here too. A `.stl` is parsed rather than rendered, so it
	/// is the cheap end of this, but a directory of them is walked the same way
	/// and each row still costs a Metal device and a spatial index.
	func makeModelTab(for fileURL: URL, preview: Bool) -> Tab {
		let tab = Tab(
			url: fileURL,
			document: nil,
			codeView: nil,
			contentView: makeModelView(
				for: fileURL, startAfter: preview ? Self.provisionalRenderDelay : 0
			),
			isPreview: preview
		)
		tab.previewMode = .preview
		return tab
	}

	/// A tab for a file that cannot be shown as text.
	func makeNoticeTab(for fileURL: URL, reason: String, preview: Bool) -> Tab {
		let notice = FileNoticeView(url: fileURL, reason: reason)
		let tab = Tab(url: fileURL, document: nil, codeView: nil, contentView: notice, isPreview: preview)

		notice.onOpenExternally = { NSWorkspace.shared.open(fileURL) }
		notice.onPreviewModel = { MainWindowController.previewModel(at: fileURL) }
		notice.onOpenHexEditor = { [weak self, weak tab] in
			guard let self, let tab else { return }
			self.showHexEditor(for: tab)
		}
		return tab
	}

	/// Swaps a tab's content for a hex editor over the same file.
	///
	/// The notice's button, *Open as Hex* on a text tab, and the driver all
	/// arrive here. A text tab with unsaved edits is refused rather than
	/// silently dropped: the bytes on disk are not the ones being looked at.
	func showHexEditor(for tab: Tab) {
		guard let index = tabs.firstIndex(where: { $0 === tab }), tab.hex == nil else { return }
		if tab.document?.isDirty == true {
			Toast.post("Save \(tab.url.lastPathComponent) first", detail: "The hex editor shows the file on disk, and this tab has edits that are not there yet.", kind: .warning)
			return
		}
		let hex: HexEditorController
		do {
			// Mapped rather than read: a 100 MB file costs no resident memory
			// until the visible rows are actually touched.
			hex = try HexEditorController(url: tab.url)
		} catch {
			Toast.post("Cannot open \(tab.url.lastPathComponent) as bytes", detail: error.localizedDescription, kind: .warning)
			return
		}
		tab.document = nil
		tab.codeView = nil
		tab.hex = hex
		tab.contentView = hex.view
		// Inspecting a file is a commitment to the tab, same as editing one.
		tab.isPreview = false
		hex.onDirtyChanged = { [weak self] in self?.refreshTabBar() }
		hex.onStatusChanged = { [weak self] in
			guard let self else { return }
			onStatusChanged?(self)
		}

		if activeIndex == index {
			activeIndex = nil
			activate(index: index, focusEditor: true)
		} else {
			refreshTabBar()
		}
		onStatusChanged?(self)
	}

	/// An entry inside an archive, from the file the cache holds it in: an
	/// ordinary tab in every way but two — it is read only, and its grey half
	/// names the archive rather than a directory.
	func openArchiveEntry(at url: URL, origin: ArchiveOrigin, focusEditor: Bool) {
		open(fileURL: url, focusEditor: focusEditor, preview: !focusEditor)
		guard let tab = tabs.first(where: { $0.url.path == url.path }) else { return }
		tab.archiveOrigin = origin
		tab.document?.isReadOnly = true
		refreshTabBar()
	}

	/// *Open as Hex* for the tab in front, whatever it holds.
	func openActiveAsHex() {
		guard let tab = activeTab else { return }
		showHexEditor(for: tab)
	}

	/// *Open as Text* for a hex tab over a file that is text: the tab is
	/// closed and the file opened the ordinary way, in the same place.
	func openActiveAsText() {
		guard let index = activeIndex, let tab = activeTab, tab.hex != nil else { return }
		if tab.isDirty, !confirmDiscard(for: tab) { return }
		let url = tab.url
		removeTab(at: index)
		open(fileURL: url, focusEditor: true)
	}

	var activeTabIsHex: Bool { activeTab?.hex != nil }

	/// Whether *Open as Text* is worth offering: a hex tab over a file the
	/// binary test passes. A binary would only land on the notice again.
	var activeTabCanOpenAsText: Bool {
		guard let tab = activeTab, tab.hex != nil else { return false }
		return !FileInspector.isProbablyBinary(url: tab.url)
	}

	/// ⌘L on a hex tab: the offset field.
	func goToOffset() {
		activeTab?.hex?.focusOffset()
	}

	/// What the status bar shows in place of line and column for a hex tab.
	var statusPositionText: String? { activeTab?.hex?.statusText }

	/// The driver: opens the front tab as hex when it is not, then performs
	/// the steps and returns the report.
	func hexStepsForTesting(_ steps: String) async -> String {
		guard let tab = activeTab else { return "HEX no tab" }
		if tab.hex == nil { showHexEditor(for: tab) }
		guard let hex = tab.hex else { return "HEX \(tab.url.lastPathComponent) could not be opened as bytes" }
		return await hex.performForTesting(steps)
	}

	var activeTab: Tab? {
		guard let activeIndex, tabs.indices.contains(activeIndex) else { return nil }
		return tabs[activeIndex]
	}
}
