import AppKit
import IdeaiKit

/// A profile, drawn as a flame graph.
///
/// One row per level of the stack, each frame as wide as the time spent in it.
/// The shape is the point: a wide bar near the top is a function doing the
/// work itself, and a tall narrow spike is a deep call chain that costs
/// nothing. Neither is visible in a table of numbers.
final class FlameGraphView: NSView {
	/// Told which frame was clicked, so the pane can say more about it.
	var onSelect: ((String) -> Void)?
	/// Told when the view zooms, so the pane can offer a way back.
	var onFocusChanged: ((String?) -> Void)?

	private var graph: FlameGraph?
	/// The node the graph is zoomed into; the root when it is not.
	private var focus: FlameGraph.Node?
	private var hovered: FlameGraph.Node?
	/// Where each node was drawn, for hit testing.
	private var frames: [(node: FlameGraph.Node, rect: NSRect)] = []
	private var trackingArea: NSTrackingArea?

	private static var rowHeight: CGFloat { Theme.current.scaled(18) }

	override var isFlipped: Bool { true }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func show(_ graph: FlameGraph?) {
		self.graph = graph
		focus = graph?.root
		hovered = nil
		onFocusChanged?(nil)
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	/// Back to the whole profile.
	func resetFocus() {
		guard let graph else { return }
		focus = graph.root
		onFocusChanged?(nil)
		needsDisplay = true
	}

	override var intrinsicContentSize: NSSize {
		let depth = focus?.depth ?? 1
		return NSSize(width: NSView.noIntrinsicMetric, height: CGFloat(depth) * Self.rowHeight)
	}

	// MARK: - Interaction

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseMoved(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		let found = frames.first { $0.rect.contains(point) }?.node
		guard found !== hovered else { return }
		hovered = found
		toolTip = found.map { node in
			let share = ProfileValue.percentage(node.value, of: graph?.total ?? 0)
			let unit = graph?.unit ?? ""
			return """
			\(node.name)
			\(ProfileValue.format(node.value, unit: unit)) (\(share)) \
			· \(ProfileValue.format(node.selfValue, unit: unit)) in itself
			"""
		}
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent) {
		hovered = nil
		toolTip = nil
		needsDisplay = true
	}

	/// A click zooms into a frame: its callers stay, everything beside it goes,
	/// and the frame fills the width. The way any flame graph is read once the
	/// interesting part is narrower than a pixel.
	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		guard let hit = frames.first(where: { $0.rect.contains(point) })?.node else { return }

		onSelect?(hit.name)
		guard !hit.children.isEmpty else { return }
		focus = hit
		onFocusChanged?(hit === graph?.root ? nil : hit.name)
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	override func keyDown(with event: NSEvent) {
		// Escape zooms back out, as it closes anything else here.
		if event.keyCode == 53 { resetFocus() } else { super.keyDown(with: event) }
	}

	override var acceptsFirstResponder: Bool { true }

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		bounds.fill()
		frames = []

		guard let focus, focus.value > 0 else {
			let message = NSAttributedString(string: "No samples.", attributes: [
				.font: Theme.current.uiFont(12),
				.foregroundColor: Theme.current.gitIgnored,
			])
			message.draw(at: NSPoint(x: Theme.current.scaled(12), y: Theme.current.scaled(10)))
			return
		}

		draw(node: focus, x: 0, width: bounds.width, row: 0)
	}

	private func draw(node: FlameGraph.Node, x: CGFloat, width: CGFloat, row: Int) {
		let rect = NSRect(
			x: x,
			y: CGFloat(row) * Self.rowHeight,
			width: width,
			height: Self.rowHeight - 1
		)
		guard rect.maxY <= bounds.height + Self.rowHeight, width >= 0.5 else { return }
		frames.append((node, rect))

		let colour = Self.colour(for: node.name, hovered: node === hovered)
		colour.setFill()
		NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0), xRadius: 2, yRadius: 2).fill()

		// A label only where one fits; a two-pixel frame with a clipped glyph
		// in it is noise.
		if width > Theme.current.scaled(28) {
			let label = NSAttributedString(string: node.name, attributes: [
				.font: Theme.terminalFont(size: Theme.current.fontSize - 2),
				.foregroundColor: NSColor.black.withAlphaComponent(0.82),
			])
			let inset = Theme.current.scaled(4)
			label.draw(in: NSRect(
				x: rect.minX + inset,
				y: rect.midY - label.size().height / 2,
				width: rect.width - inset * 2,
				height: label.size().height
			))
		}

		guard !node.children.isEmpty else { return }
		var childX = x
		for child in node.children {
			let share = CGFloat(child.value) / CGFloat(node.value)
			let childWidth = width * share
			draw(node: child, x: childX, width: childWidth, row: row + 1)
			childX += childWidth
		}
	}

	/// A frame's colour comes from its name, so the same function is the same
	/// colour everywhere in the graph and a package reads as a band.
	///
	/// Warm hues, as every flame graph since the first one: the point is to
	/// tell frames apart, not to encode anything in the hue.
	static func colour(for name: String, hovered: Bool) -> NSColor {
		var hash: UInt64 = 5381
		for byte in name.utf8 { hash = hash &* 33 &+ UInt64(byte) }

		let hue = 0.02 + Double(hash % 1000) / 1000 * 0.11
		let saturation = 0.55 + Double((hash / 1000) % 100) / 100 * 0.2
		return NSColor(
			hue: hue,
			saturation: saturation,
			brightness: hovered ? 1.0 : 0.86,
			alpha: 1
		)
	}

	// MARK: - Testing

	var frameCountForTesting: Int { frames.count }

	func focusForTesting(_ name: String) {
		guard let match = frames.first(where: { $0.node.name == name })?.node else { return }
		focus = match
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}
}
