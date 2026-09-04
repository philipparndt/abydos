import AppKit
import AbydosKit

/// A tooltip this app draws itself.
///
/// **Because AppKit's takes a `String`.** Everything on the terminal's strip is
/// drawn — the tabs, the sessions pill, the buttons — and the one thing
/// explaining them was a yellow system box of one size, one weight and one
/// colour, belonging to no theme here. The pill's tooltip has three things to
/// say: what its two counts are, what each colour means, and which key opens
/// the list. As a single string those are three sentences with nothing to tell
/// them apart.
///
/// The shape is `ParameterHintStrip`'s, which is the app's existing floating
/// panel with a drawn view in it: borderless, non-activating, transparent,
/// `.popUpMenu` level, ignoring the mouse, and a child of the window it hangs
/// off so that it goes when that window does.
@MainActor
final class StyledTip {
	/// What a tip says: what the thing *is*, what it *does*, and the key.
	///
	/// Three fields rather than one string, so the drawing decides the
	/// hierarchy instead of the caller deciding it with punctuation. A caller
	/// with one short thing to say passes a title and gets one line.
	struct Tip: Equatable {
		var title: String
		var detail: String?
		var shortcut: String?

		init(title: String, detail: String? = nil, shortcut: String? = nil) {
			self.title = title
			self.detail = detail
			self.shortcut = shortcut
		}

		/// What a driven run reads, so the words are checkable without a
		/// screenshot.
		var reportForTesting: String {
			var said = "title=[\(title)]"
			said += " detail=[\(detail ?? "")]"
			said += " key=[\(shortcut ?? "")]"
			return said
		}
	}

	/// One tip at a time, everywhere.
	///
	/// A tooltip is only ever one on screen; one panel per control would be
	/// eight of them on a strip that redraws twice a second while a tmux
	/// session is watched. It is added as a child of whichever window asks, so
	/// sharing it across windows costs nothing.
	static let shared = StyledTip()

	/// How long the pointer rests before it appears.
	///
	/// The app's own, because `NSView.toolTip`'s delay is the system's and
	/// cannot be read. Half a second is what that one measures at, and the
	/// timer is dropped the moment the pointer moves to another control — so
	/// crossing a strip does not leave a trail of tips.
	static let delay: TimeInterval = 0.5

	private var window: NSPanel?
	private var view: TipView?
	private var timer: Timer?
	private var showing: Tip?

	private init() {}

	/// What is on screen, for whoever needs to know whether to hide it.
	var isShowing: Bool { window?.isVisible == true }

	/// Rests a tip under a rectangle in a view's own coordinates.
	///
	/// The same tip over the same control asks for nothing: a strip redrawing
	/// under a still pointer must not restart the wait.
	func show(_ tip: Tip, from rect: NSRect, of host: NSView) {
		guard tip != showing || !isShowing else { return }
		timer?.invalidate()
		showing = tip
		timer = Timer.scheduledTimer(withTimeInterval: Self.delay, repeats: false) { _ in
			MainActor.assumeIsolated { self.put(tip, from: rect, of: host) }
		}
	}

	func hide() {
		timer?.invalidate()
		timer = nil
		showing = nil
		guard let window, window.isVisible else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
	}

	private func put(_ tip: Tip, from rect: NSRect, of host: NSView) {
		guard let parent = host.window else { return }
		let window = self.window ?? makeWindow()
		self.window = window

		view?.tip = tip
		let size = view?.wantedSize ?? .zero

		// Under the control, aligned with its leading edge, and kept inside the
		// window it belongs to — which is where the control is, so a strip
		// control never wants for room above.
		let onScreen = parent.convertToScreen(host.convert(rect, to: nil))
		let visible = parent.screen?.visibleFrame ?? parent.frame
		let gap = Theme.current.scaled(6)
		let x = min(max(visible.minX + gap, onScreen.minX), visible.maxX - size.width - gap)
		var y = onScreen.minY - size.height - gap
		// Above it instead, where there is no room below — the panel is at the
		// bottom of the window in a torn-off terminal.
		if y < visible.minY + gap { y = onScreen.maxY + gap }

		window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
		if window.parent == nil { parent.addChildWindow(window, ordered: .above) }
		window.orderFront(nil)
	}

	private func makeWindow() -> NSPanel {
		let view = TipView()
		self.view = view

		let window = NSPanel(
			contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: true
		)
		window.hasShadow = true
		window.isOpaque = false
		window.backgroundColor = .clear
		window.level = .popUpMenu
		window.contentView = view
		// **Nothing to hover and nothing to click.** A tip that answered the
		// pointer would keep itself alive after the pointer had left the
		// control it is about, which is how a tooltip becomes something to
		// dismiss.
		window.ignoresMouseEvents = true
		return window
	}
}

/// The tip itself: a title, a body under it, and the key as a cap.
private final class TipView: NSView {
	var tip: StyledTip.Tip? {
		didSet {
			guard tip != oldValue else { return }
			needsDisplay = true
		}
	}

	override var isFlipped: Bool { true }

	private var inset: CGFloat { Theme.current.scaled(10) }
	private var widest: CGFloat { Theme.current.scaled(320) }

	private var titleFont: NSFont { Theme.current.uiFont(12, weight: .semibold) }
	private var detailFont: NSFont { Theme.current.uiFont(11) }
	private var keyFont: NSFont { Theme.current.uiFont(10, weight: .medium) }

	private func title(_ tip: StyledTip.Tip) -> NSAttributedString {
		NSAttributedString(string: tip.title, attributes: [
			.font: titleFont, .foregroundColor: Theme.current.sidebarText,
		])
	}

	private func detail(_ text: String) -> NSAttributedString {
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byWordWrapping
		// A line and a half of leading: three lines of dimmed text set solid is
		// a paragraph nobody reads off a floating panel.
		paragraph.lineSpacing = Theme.current.scaled(2)
		return NSAttributedString(string: text, attributes: [
			.font: detailFont,
			// The dimmed ink, not the header one: in this theme the header ink
			// is the brighter of the two, and a body brighter than its title
			// reads as the thing to look at.
			.foregroundColor: Theme.current.sidebarText.withAlphaComponent(0.62),
			.paragraphStyle: paragraph,
		])
	}

	private func key(_ text: String) -> NSAttributedString {
		NSAttributedString(string: text, attributes: [
			.font: keyFont, .foregroundColor: Theme.current.sidebarText.withAlphaComponent(0.75),
		])
	}

	/// The size the words want, bounded, with the key on the title's line where
	/// it fits and on its own where it does not.
	var wantedSize: NSSize {
		guard let tip else { return .zero }
		let room = widest - inset * 2
		let titled = title(tip)
		var width = ceil(titled.size().width)
		var height = ceil(titled.size().height)

		if let shortcut = tip.shortcut {
			// The cap, beside the title: a key is a thing rather than a word,
			// and inside the sentence it reads as punctuation.
			width += Theme.current.scaled(10) + capSize(for: shortcut).width
		}

		if let text = tip.detail, !text.isEmpty {
			let bounds = detail(text).boundingRect(
				with: NSSize(width: room, height: .greatestFiniteMagnitude),
				options: [.usesLineFragmentOrigin, .usesFontLeading]
			)
			width = max(width, ceil(bounds.width))
			height += Theme.current.scaled(5) + ceil(bounds.height)
		}

		return NSSize(
			width: min(widest, width + inset * 2),
			height: height + inset * 2
		)
	}

	private func capSize(for text: String) -> NSSize {
		let size = key(text).size()
		return NSSize(
			width: ceil(size.width) + Theme.current.scaled(10),
			height: ceil(size.height) + Theme.current.scaled(4)
		)
	}

	override func draw(_ dirtyRect: NSRect) {
		guard let tip else { return }

		// The ground and its edge: the sidebar's own background, so a tip over
		// the terminal reads as part of this app rather than as the system's
		// yellow note.
		let shape = NSBezierPath(
			roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
			xRadius: Theme.current.scaled(6), yRadius: Theme.current.scaled(6)
		)
		Theme.current.sidebarBackground.setFill()
		shape.fill()
		Theme.current.separator.setStroke()
		shape.lineWidth = 1
		shape.stroke()

		let titled = title(tip)
		let titleSize = titled.size()
		titled.draw(at: NSPoint(x: inset, y: inset))

		if let shortcut = tip.shortcut {
			let size = capSize(for: shortcut)
			let cap = NSRect(
				x: bounds.maxX - inset - size.width,
				y: inset + (titleSize.height - size.height) / 2,
				width: size.width, height: size.height
			)
			let capShape = NSBezierPath(
				roundedRect: cap,
				xRadius: Theme.current.scaled(4), yRadius: Theme.current.scaled(4)
			)
			Theme.current.sidebarText.withAlphaComponent(0.10).setFill()
			capShape.fill()
			Theme.current.separator.setStroke()
			capShape.lineWidth = 1
			capShape.stroke()

			let word = key(shortcut)
			let wordSize = word.size()
			word.draw(at: NSPoint(
				x: cap.midX - wordSize.width / 2, y: cap.midY - wordSize.height / 2
			))
		}

		guard let text = tip.detail, !text.isEmpty else { return }
		let body = detail(text)
		body.draw(with: NSRect(
			x: inset,
			y: inset + titleSize.height + Theme.current.scaled(5),
			width: bounds.width - inset * 2,
			height: bounds.height - inset * 2 - titleSize.height
		), options: [.usesLineFragmentOrigin, .usesFontLeading])
	}
}
