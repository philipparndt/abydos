import AbydosKit
import AppKit

/// The half of the window a diagram is drawn in, whichever tool draws it.
///
/// PlantUML and Mermaid are two entirely different things to run — a JVM or a
/// container against a web view with a JavaScript bundle in it — and they are
/// the same *pane*: white paper, the drawing scaled to fit and following the
/// app's own ⌘+, a sentence in the middle when there is no picture to show, and
/// a right-click offering `Export ▸ PNG` and `Export ▸ SVG`.
///
/// So that is here, once. A subclass says how to get a picture and when there
/// is something worth exporting; everything somebody actually looks at is the
/// same, which is what "Mermaid the same way" was asked for.
class DiagramPaneView: NSView {
	/// The picture, or nil while there is none to show.
	var image: NSImage?
	/// Its own size in points, which for a drawing is the only size it has.
	var naturalSize: CGSize = .zero
	/// What to say instead of a picture: nothing drawn yet, or why not.
	var notice: String?

	let spinner = NSProgressIndicator()
	/// The zoom being watched, so the pane can stop watching when it goes.
	private var watchingSettings: NSObjectProtocol?
	private var exportMenu: NSMenu?

	/// The file being drawn, which is where an export writes and what it is
	/// named after. Nil until the pane is given one.
	var fileURL: URL?

	init() {
		super.init(frame: .zero)
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

		menu = makeExportMenu()

		// The zoom, which this pane follows like every other. A diagram sits
		// inside a split rather than being a tab's own view, so the walk that
		// visits a tab's page on ⌘+ does not reach one — it listens for itself
		// instead, and there is nothing to redo but the drawing.
		watchingSettings = NotificationCenter.default.addObserver(
			forName: .abydosSettingsChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.needsDisplay = true }
		}
	}

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

	/// Writes the picture beside the file, in the format asked for.
	func export(_ format: DiagramFormat, then: (@Sendable ([URL]) -> Void)? = nil) {}

	// MARK: - Exporting

	/// Right-clicking the picture offers to keep it.
	///
	/// A menu on the pane rather than a button in a corner: the pane is drawn
	/// entirely by hand and a button would sit over the diagram, and this is the
	/// gesture every picture on this machine already answers to. The format is
	/// asked for by name — the pane draws in SVG for sharpness, and "Export ▸
	/// PNG" has to mean a PNG rather than whatever happens to be on screen.
	private func makeExportMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		let export = NSMenuItem(title: "Export", action: nil, keyEquivalent: "")
		let formats = NSMenu()
		for format in DiagramFormat.allCases {
			let item = NSMenuItem(
				title: format.rawValue.uppercased(), action: #selector(exportFromMenu(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = format.rawValue
			formats.addItem(item)
		}
		export.submenu = formats
		menu.addItem(export)
		exportMenu = formats
		return menu
	}

	override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
		refreshExportMenu()
	}

	private func refreshExportMenu() {
		let ready = fileURL != nil && isReadyToExport
		for item in menu?.items ?? [] { item.isEnabled = ready }
		for item in exportMenu?.items ?? [] { item.isEnabled = ready }
	}

	@objc private func exportFromMenu(_ sender: NSMenuItem) {
		guard let raw = sender.representedObject as? String,
		      let format = DiagramFormat(rawValue: raw) else { return }
		export(format)
	}

	/// What a right-click on the diagram offers, for a test: a menu cannot be
	/// photographed while it is open.
	var menuTitlesForTesting: [String] {
		refreshExportMenu()
		return (menu?.items ?? []).flatMap { item -> [String] in
			let mark = item.isEnabled ? "" : " (disabled)"
			let children = (item.submenu?.items ?? []).map { "\(item.title) ▸ \($0.title)" }
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
		needsDisplay = true
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.fill()

		if let image {
			let pane = CGSize(width: max(0, bounds.width - 32), height: max(0, bounds.height - 32))
			// Following ⌘+ like the rest of the window, up to what the pane can
			// hold. A drawing can be asked for any size and still be sharp, which
			// is what makes this worth doing at all.
			let box = ImageFit.rect(
				image: naturalSize, in: pane,
				scale: ImageFit.fitScale(image: naturalSize, in: pane, zoom: Theme.current.scale)
			).offsetBy(dx: 16, dy: 16)
			guard box.width > 0, box.height > 0 else { return }
			// The paper the diagram is drawn on. Neither tool's default
			// background is painted — PlantUML's is a CSS property on the root
			// element and Mermaid's is nothing at all — so black lines on a dark
			// editor background would be all but invisible. A diagram that sets a
			// background of its own emits a rectangle for it and covers this.
			NSColor.white.setFill()
			box.fill()
			image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
			return
		}

		guard let notice else { return }
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
}
