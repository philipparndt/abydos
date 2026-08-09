import AbydosKit
import AppKit

extension Notification.Name {
	/// A diagram a Markdown preview asked for has finished being drawn.
	///
	/// The preview renders synchronously and Mermaid does not, so this is how a
	/// picture that arrived late gets onto the page: the pane re-renders, finds
	/// the drawing in the cache this time, and puts it where the placeholder was.
	static let abydosMarkdownDiagramDrawn = Notification.Name("abydos.markdown.diagram.drawn")
}

/// The pictures a Markdown preview shows for its ```` ```mermaid ```` blocks.
///
/// It exists because of one mismatch: `MarkdownRenderer.render` is a function
/// from a string to an attributed string and returns before it can have drawn
/// anything, while `mermaid.render` is a promise inside a web view. Something has
/// to remember pictures between those two facts, and this is it.
///
/// Three things follow from being a cache rather than a queue, and each is a
/// behaviour somebody would notice:
///
///  * **A re-render does not redraw.** The preview re-renders on every pause in
///    the typing, and a document whose fences have not changed gets its pictures
///    back from here synchronously — so a diagram does not blink out and back
///    while somebody edits the paragraph above it.
///  * **Drawing is one at a time.** There is one `WebRenderer` in the app and it
///    is one web view; twenty fences are twenty renders through it in turn, at
///    six to nineteen thousandths of a second each, rather than twenty calls
///    interleaved in one page. The queue is drained oldest first, so a document
///    fills in from the top.
///  * **A fault is remembered too.** A diagram that does not parse is asked once
///    and then answers from here, which is what stops a broken fence being
///    re-rendered on every keystroke while somebody types the rest of it.
@MainActor
final class MarkdownDiagrams {
	static let shared = MarkdownDiagrams()

	/// What a fence came to.
	enum Picture {
		/// The drawing, and the colour it was drawn on.
		case drawn(NSImage, paper: NSColor)
		/// The diagram's own fault, with the line it names still a number — the
		/// caller adds the fence's own position, so a complaint about line 3 of a
		/// block reads as the line of the file somebody is looking at.
		case fault(DiagramFault)
		/// Something that was not the diagram's doing.
		case trouble(String)
	}

	/// A drawing is of a source *and* of a look, so a theme change is a different
	/// question rather than a stale answer.
	private struct Key: Hashable {
		let source: String
		let theme: String
	}

	/// How many drawings are kept.
	///
	/// A README has two or three fences and the largest document in this
	/// repository has none. The cap is here so that scrolling through a folder of
	/// documents all afternoon does not accumulate bitmaps for ever; the oldest
	/// unused entry goes first.
	private static let capacity = 48

	private var drawn: [Key: Picture] = [:]
	/// Least-recently-asked-for first, which is the order they are dropped in.
	private var used: [Key] = []
	private var queue: [Key] = []
	private var queued: Set<Key> = []
	private var working = false

	private init() {}

	/// The picture for a fence, or nil while there is not one yet — in which case
	/// it has now been asked for.
	///
	/// - Parameter theme: which way round to draw it, or nil for a fence that
	///   states its own look. The rule is 0429's and is not repeated here: the
	///   caller asks `Mermaid.statedLook` and passes nil when the file has chosen.
	func picture(for source: String, theme: DiagramTheme?) -> Picture? {
		let key = Key(source: source, theme: theme?.rawValue ?? "")
		if let picture = drawn[key] {
			touch(key)
			return picture
		}
		guard !queued.contains(key) else { return nil }
		queued.insert(key)
		queue.append(key)
		startWorking()
		return nil
	}

	// MARK: - Drawing, one at a time

	private func startWorking() {
		guard !working else { return }
		working = true
		Task { [weak self] in
			await self?.work()
		}
	}

	private func work() async {
		defer { working = false }
		while !queue.isEmpty {
			let key = queue.removeFirst()
			queued.remove(key)
			let theme = DiagramTheme(rawValue: key.theme)
			let result = await MermaidRenderer.shared.draw(
				key.source, format: Mermaid.previewFormat, theme: theme
			)
			remember(key, result: result, theme: theme)
			// Said after every one rather than only when the queue drains. The
			// pane's own refresh is debounced, so a document of twenty fences
			// still re-renders a handful of times rather than twenty — and a
			// document of one does not wait on anything.
			NotificationCenter.default.post(name: .abydosMarkdownDiagramDrawn, object: nil)
		}
	}

	private func remember(
		_ key: Key, result: Result<Data, MermaidRenderer.Failure>, theme: DiagramTheme?
	) {
		switch result {
		case let .success(data):
			guard let image = NSImage(data: data), image.size.width > 0 else {
				drawn[key] = .trouble("Mermaid drew nothing.")
				break
			}
			drawn[key] = .drawn(image, paper: DiagramPaneView.paper(for: theme))
		case let .failure(.fault(fault)):
			drawn[key] = .fault(fault)
		case let .failure(.trouble(said)):
			drawn[key] = .trouble(said)
		}
		touch(key)
		while used.count > Self.capacity, let oldest = used.first {
			used.removeFirst()
			drawn[oldest] = nil
		}
	}

	private func touch(_ key: Key) {
		used.removeAll { $0 == key }
		used.append(key)
	}
}

/// The text view a rendered Markdown document is shown in.
///
/// It is an `NSTextView` and nothing more, except for two things it has to hold:
/// the subscription that brings a late picture to the page, and the `Export ▸`
/// its diagrams are written out from. A block observer is not removed by handing
/// the notification centre `self`, and a preview is made and thrown away with
/// every tab — so the token lives here and goes when the view does.
final class MarkdownPreviewTextView: NSTextView {
	private var watching: NSObjectProtocol?

	/// Which document this is a preview of, so the pictures have somewhere to go.
	var fileURL: URL?
	/// The text in front of somebody, which is what is drawn — unsaved edits and
	/// all, exactly as the `.mmd` pane's own export draws its buffer.
	var markdownSource: (() -> String?)?

	/// Runs something whenever a diagram anywhere has finished being drawn.
	///
	/// Every preview hears about every drawing rather than only its own, and that
	/// is deliberate: the cache is one cache, so a document that quotes the same
	/// diagram as the one beside it gets its picture from the render that has
	/// already happened.
	func whenDiagramDrawn(_ redraw: @escaping @MainActor () -> Void) {
		if let watching { NotificationCenter.default.removeObserver(watching) }
		watching = NotificationCenter.default.addObserver(
			forName: .abydosMarkdownDiagramDrawn, object: nil, queue: .main
		) { _ in
			MainActor.assumeIsolated { redraw() }
		}
	}

	// MARK: - Writing the pictures out

	/// The text view's own menu with `Export ▸` on the front of it.
	///
	/// **On the document rather than on the picture under the pointer**, which is
	/// the decision 0425 left open and `DiagramExport.export(markdown:)` records
	/// in full. The short of it: this same submenu has to work from the project
	/// tree, where there is no picture on screen to point at, so an export routed
	/// to the attachment beneath the click would be one act with two behaviours.
	///
	/// It appears only when there is something to write. Every other Markdown
	/// document in a repository gets the menu `NSTextView` has always given it.
	override func menu(for event: NSEvent) -> NSMenu? {
		let menu = super.menu(for: event)
		guard let menu, let url = fileURL, let source = markdownSource?(),
		      DiagramExport.holdsADiagram(url, source: source)
		else { return menu }

		let export = NSMenuItem(title: "Export", action: nil, keyEquivalent: "")
		let formats = NSMenu()
		formats.autoenablesItems = false
		DiagramExportMenu.fill(
			formats, theme: Theme.current.isLight ? .light : .dark,
			stated: DiagramExport.statedLook(of: url, source: source),
			target: self, action: #selector(exportDiagramsFromMenu(_:)), enabled: true
		)
		export.submenu = formats
		menu.insertItem(export, at: 0)
		menu.insertItem(.separator(), at: 1)
		return menu
	}

	@objc private func exportDiagramsFromMenu(_ sender: NSMenuItem) {
		guard let url = fileURL, let code = sender.representedObject as? String,
		      let choice = DiagramExportMenu.choice(for: code)
		else { return }
		DiagramExportCommand.run(
			url: url, source: markdownSource?(), format: choice.format, theme: choice.theme,
			projectRoot: nil
		)
	}

	/// What a right-click over the rendered document offers, for a test: a menu
	/// cannot be photographed while it is open.
	var exportMenuTitlesForTesting: [String] {
		guard let url = fileURL, let source = markdownSource?(),
		      DiagramExport.holdsADiagram(url, source: source)
		else { return [] }
		let formats = NSMenu()
		formats.autoenablesItems = false
		DiagramExportMenu.fill(
			formats, theme: Theme.current.isLight ? .light : .dark,
			stated: DiagramExport.statedLook(of: url, source: source),
			target: self, action: #selector(exportDiagramsFromMenu(_:)), enabled: true
		)
		return formats.items.map { "Export ▸ \($0.title)" }
	}

	deinit {
		if let watching { NotificationCenter.default.removeObserver(watching) }
	}
}

/// A drawing sitting in the flow of a rendered Markdown document.
///
/// A cell rather than an attachment with a fixed size, and that is the whole
/// reason it exists: a cell is asked how large it wants to be *for the line
/// fragment it is going into*, so a diagram wider than the pane shrinks to fit
/// and grows again when the divider is dragged, with no re-render and nothing
/// watching the frame.
final class DiagramAttachmentCell: NSTextAttachmentCell {
	/// The paper under the drawing.
	///
	/// Painted here for the same reason `DiagramPaneView` paints it: Mermaid emits
	/// no background of its own, so a light drawing dropped straight onto a dark
	/// preview is invisible. A themed drawing already carries a rectangle of this
	/// exact colour, so the two agree; a diagram that stated its own look gets the
	/// white the pane has always given one.
	private let paper: NSColor
	private let picture: NSImage

	/// The margin between the paper's edge and the drawing.
	private static let padding: CGFloat = 10

	init(picture: NSImage, paper: NSColor) {
		self.picture = picture
		self.paper = paper
		super.init()
		self.image = picture
	}

	required init(coder: NSCoder) { fatalError("not used") }

	/// The drawing's own size in points, which for an SVG is the only size it has.
	private var naturalSize: CGSize {
		picture.size.width > 0 && picture.size.height > 0
			? picture.size : CGSize(width: 200, height: 100)
	}

	/// The size this wants, given the width it is being offered.
	///
	/// Never larger than the drawing itself. A two-node flowchart blown up to the
	/// width of the window would be a picture of nothing much, and a document
	/// reads better with its diagrams at the size they were drawn — which is what
	/// every other renderer of a Mermaid fence does.
	private func fitted(into width: CGFloat) -> CGSize {
		let inner = max(40, width - 2 * Self.padding)
		let natural = naturalSize
		let scale = min(1, inner / natural.width)
		return CGSize(
			width: (natural.width * scale).rounded() + 2 * Self.padding,
			height: (natural.height * scale).rounded() + 2 * Self.padding
		)
	}

	override func cellSize() -> NSSize { fitted(into: naturalSize.width + 2 * Self.padding) }

	override func cellFrame(
		for textContainer: NSTextContainer,
		proposedLineFragment lineFrag: NSRect,
		glyphPosition position: NSPoint,
		characterIndex charIndex: Int
	) -> NSRect {
		// Measured against the fragment being offered rather than the container:
		// inside a table cell the two are very different, and the fragment is the
		// one that is true in both places.
		let available = lineFrag.width > 0 ? lineFrag.width : textContainer.size.width
		return NSRect(origin: .zero, size: fitted(into: available - position.x))
	}

	override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
		draw(withFrame: cellFrame, in: controlView, characterIndex: 0)
	}

	override func draw(
		withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int
	) {
		let sheet = cellFrame.insetBy(dx: 1, dy: 1)
		let rounded = NSBezierPath(roundedRect: sheet, xRadius: 4, yRadius: 4)
		paper.setFill()
		rounded.fill()
		Theme.current.separator.withAlphaComponent(0.5).setStroke()
		rounded.lineWidth = 1
		rounded.stroke()

		let box = cellFrame.insetBy(dx: Self.padding, dy: Self.padding)
		guard box.width > 0, box.height > 0 else { return }
		// `respectFlipped` rather than the shorter call beside it. A text view's
		// coordinates run downwards and an `NSImage` is drawn in its own, so the
		// short form put every diagram in the preview upside down and mirrored —
		// which was the first thing the first screenshot of this showed.
		picture.draw(
			in: box, from: .zero, operation: .sourceOver, fraction: 1,
			respectFlipped: true, hints: nil
		)
	}
}
