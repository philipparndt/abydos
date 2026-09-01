import AppKit
import AbydosKit

/// One of a few, drawn as a row of pills.
///
/// What `NSSegmentedControl` was doing in four places: `Whole Repository` /
/// `This File` on the log page, `Only me` / `My teams too` on the pull-request
/// list, the two view-mode glyphs on the review page. All of them at
/// `controlSize = .small`, which is 20 points of artwork whatever the words
/// inside it are, and all of them reported on 2026-09-01 as not following the
/// zoom.
///
/// **The keyboard is the reason this is a control and not a pair of buttons.**
/// A segmented control moves between its segments with ← and →, and people who
/// use it use that. Two `DrawnButton`s in a stack view would have looked
/// identical and lost it silently, which is the worst way to lose a behaviour.
/// So the arrows are answered here, and the design's fallback — keep
/// `NSSegmentedControl` as a *measured* member — is not needed.
final class DrawnChoice: NSControl, ScaleFollowing {
	/// The words, or the glyphs, in order.
	enum Segment {
		case words(String)
		case symbol(String, description: String)
	}

	private let segments: [Segment]
	private var frames: [NSRect] = []

	/// Which one is chosen. Setting it does not call `onChange`: that is for
	/// the person pressing, not for the code putting the control back.
	var selectedIndex: Int {
		didSet { needsDisplay = true }
	}

	var onChange: ((Int) -> Void)?

	init(segments: [Segment], selectedIndex: Int = 0, onChange: @escaping (Int) -> Void) {
		self.segments = segments
		self.selectedIndex = selectedIndex
		self.onChange = onChange
		super.init(frame: .zero)
		wantsLayer = true
		applyTheme()
		ScaledControls.register(self)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func applyTheme() {
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	override var isFlipped: Bool { true }
	override var acceptsFirstResponder: Bool { true }

	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		return super.resignFirstResponder()
	}

	// MARK: - Measuring

	private func words(_ text: String, chosen: Bool) -> NSAttributedString {
		NSAttributedString(string: text, attributes: [
			.font: Theme.current.uiFont(11, weight: chosen ? .medium : .regular),
			.foregroundColor: chosen
				? Theme.current.sidebarText
				: Theme.current.sidebarHeaderText,
		])
	}

	private func width(of segment: Segment) -> CGFloat {
		switch segment {
		case let .words(text):
			return ControlMetrics.width(
				textWidth: ceil(words(text, chosen: true).size().width),
				scale: Theme.current.scale
			)
		case .symbol:
			return ControlMetrics.glyphSide(scale: Theme.current.scale)
		}
	}

	private var height: CGFloat {
		ControlMetrics.height(
			lineHeight: ceil(words("Hg", chosen: true).size().height),
			scale: Theme.current.scale
		)
	}

	override var intrinsicContentSize: NSSize {
		NSSize(width: segments.reduce(0) { $0 + width(of: $1) }, height: height)
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		let radius = ControlMetrics.radius(scale: Theme.current.scale)
		let outline = NSBezierPath(
			roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius
		)
		Theme.current.editorBackground.setFill()
		outline.fill()

		frames = []
		var x: CGFloat = 0
		for (index, segment) in segments.enumerated() {
			let box = NSRect(x: x, y: 0, width: width(of: segment), height: bounds.height)
			frames.append(box)
			x += box.width

			if index == selectedIndex {
				// Inset by a point, so the chosen pill sits *inside* the
				// outline rather than covering it — the shape that says "one
				// of these" instead of "a button that happens to be next to
				// another button".
				let chosen = box.insetBy(dx: 1, dy: 1)
				Theme.current.selection(.row, hasKeyboard: window?.firstResponder === self)
					.setFill()
				NSBezierPath(
					roundedRect: chosen, xRadius: max(1, radius - 1), yRadius: max(1, radius - 1)
				).fill()
			}

			switch segment {
			case let .words(text):
				let drawn = words(text, chosen: index == selectedIndex)
				let size = drawn.size()
				drawn.draw(at: NSPoint(
					x: (box.midX - size.width / 2).rounded(),
					y: (box.midY - size.height / 2).rounded()
				))
			case let .symbol(name, _):
				if let image = Theme.symbol(
					name, size: 11 * Theme.current.scale,
					color: index == selectedIndex
						? Theme.current.sidebarText
						: Theme.current.sidebarHeaderText
				) {
					let side = ControlMetrics.glyphSide(scale: Theme.current.scale) * 0.6
					image.drawFitted(in: NSRect(
						x: (box.midX - side / 2).rounded(),
						y: (box.midY - side / 2).rounded(),
						width: side, height: side
					))
				}
			}
		}

		Theme.current.separator.setStroke()
		outline.lineWidth = 1
		outline.stroke()
	}

	// MARK: - Pressing

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		guard let index = frames.firstIndex(where: { $0.contains(point) }) else { return }
		window?.makeFirstResponder(self)
		choose(index)
	}

	/// ← and →, which is what a segmented control answers and what would have
	/// been lost by drawing two buttons instead.
	override func keyDown(with event: NSEvent) {
		switch event.keyCode {
		case 123: choose(max(0, selectedIndex - 1))
		case 124: choose(min(segments.count - 1, selectedIndex + 1))
		default: super.keyDown(with: event)
		}
	}

	private func choose(_ index: Int) {
		guard index != selectedIndex, segments.indices.contains(index) else { return }
		selectedIndex = index
		onChange?(index)
	}

	// MARK: - Testing

	/// What a driven run reads instead of a screenshot: the words, and which is
	/// chosen.
	func segmentsForTesting() -> [String] {
		segments.enumerated().map { index, segment in
			let name: String
			switch segment {
			case let .words(text): name = text
			case let .symbol(_, description): name = description
			}
			return index == selectedIndex ? "[\(name)]" : name
		}
	}
}
