import AbydosKit
import AppKit

/// The whole file in one strip.
///
/// Each row of pixels is a block from the statistics pass, coloured by what
/// its bytes are — zero, printable, control, high — or by its entropy on a
/// switch; the viewport is a rectangle, matches and edits are ticks, and a
/// click or a drag moves the editor. Drawn from a cached picture that is
/// remade only when the pass delivers or the strip is resized, never per
/// scroll: a scroll changes the rectangle and nothing under it.
final class HexMinimap: NSView, ScaleFollowing {
	enum Mode { case classes, entropy }
	private var widthConstraint: NSLayoutConstraint?

	var onScrollTo: ((Int) -> Void)?

	var statistics: ByteStatistics? {
		didSet { picture = nil; needsDisplay = true }
	}
	var mode: Mode = .classes {
		didSet { picture = nil; needsDisplay = true }
	}
	var count = 0 {
		didSet { picture = nil; needsDisplay = true }
	}
	var visibleRange: Range<Int> = 0..<0 {
		didSet { needsDisplay = true }
	}
	var matches: [Int] = [] {
		didSet { needsDisplay = true }
	}
	var editedRanges: [Range<Int>] = [] {
		didSet { needsDisplay = true }
	}

	private var picture: NSImage?
	private var pictureSize = NSSize.zero

	static var width: CGFloat { Theme.current.scaled(16) }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		let width = widthAnchor.constraint(equalToConstant: Self.width)
		width.isActive = true
		widthConstraint = width
		ScaledControls.register(self)
	}

	func applyTheme() {
		widthConstraint?.constant = Self.width
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		picture = nil
		needsDisplay = true
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		if newSize != pictureSize { picture = nil }
	}

	private func y(of offset: Int) -> CGFloat {
		guard count > 0 else { return 0 }
		return (CGFloat(offset) / CGFloat(count) * bounds.height).rounded(.down)
	}

	private func offset(atY y: CGFloat) -> Int {
		guard count > 0, bounds.height > 0 else { return 0 }
		return max(0, min(count - 1, Int(y / bounds.height * CGFloat(count))))
	}

	override func draw(_ dirtyRect: NSRect) {
		let theme = Theme.current
		theme.editorBackground.setFill()
		bounds.fill()
		guard count > 0 else { return }

		if picture == nil { picture = makePicture() }
		picture?.draw(in: bounds)

		theme.gitModified.setFill()
		for range in editedRanges {
			NSRect(x: 0, y: y(of: range.lowerBound), width: bounds.width * 0.3, height: max(2, y(of: range.upperBound) - y(of: range.lowerBound))).fill()
		}
		theme.searchMatchCurrentBackground.setFill()
		// Ticks at most once per pixel row: a hundred thousand matches are a
		// few hundred rects.
		var lastY: CGFloat = -1
		for match in matches {
			let at = y(of: match)
			if at == lastY { continue }
			lastY = at
			NSRect(x: bounds.width * 0.7, y: at, width: bounds.width * 0.3, height: 2).fill()
		}

		let top = y(of: visibleRange.lowerBound)
		let bottom = max(top + 3, y(of: visibleRange.upperBound))
		theme.selection(.text, hasKeyboard: true).withAlphaComponent(0.35).setFill()
		NSRect(x: 0, y: top, width: bounds.width, height: bottom - top).fill()
		theme.editorText.withAlphaComponent(0.5).setStroke()
		NSBezierPath(rect: NSRect(x: 0.5, y: top + 0.5, width: bounds.width - 1, height: bottom - top - 1)).stroke()
	}

	/// One colour a pixel row, from the blocks that row covers.
	private func makePicture() -> NSImage? {
		let size = bounds.size
		guard size.height >= 1, size.width >= 1 else { return nil }
		pictureSize = size
		let theme = Theme.current
		let image = NSImage(size: size, flipped: true) { [weak self] rect in
			guard let self, let statistics = self.statistics, !statistics.blocks.isEmpty else { return true }
			let rows = Int(rect.height)
			let blocks = statistics.blocks
			for row in 0..<rows {
				let first = row * blocks.count / rows
				let last = max(first + 1, (row + 1) * blocks.count / rows)
				var zero = 0, printable = 0, control = 0, high = 0, total = 0
				var entropy = 0.0, measured = 0
				for index in first..<min(blocks.count, last) {
					guard let block = blocks[index] else { continue }
					zero += block.zero; printable += block.printable; control += block.control; high += block.high
					total += block.length
					entropy += statistics.curve(at: index) ?? block.entropy; measured += 1
				}
				guard total > 0 else { continue }
				let colour: NSColor
				switch self.mode {
				case .classes:
					// A blend by share: mostly zeros stays the background, text
					// reads green, code and data read as the modified colour,
					// control bytes as grey.
					let weight = CGFloat(total)
					colour = theme.editorBackground.blended(withFraction: CGFloat(printable) / weight * 0.9, of: theme.gitAdded)?
						.blended(withFraction: CGFloat(high) / weight * 0.9, of: theme.gitModified)?
						.blended(withFraction: CGFloat(control) / weight * 0.7, of: theme.gutterText)
						?? theme.editorBackground
				case .entropy:
					let fraction = CGFloat(entropy / Double(max(1, measured)) / 8)
					colour = theme.editorBackground.blended(withFraction: fraction, of: theme.gitConflict) ?? theme.editorBackground
				}
				colour.setFill()
				NSRect(x: 0, y: CGFloat(row), width: rect.width, height: 1).fill()
			}
			return true
		}
		return image
	}

	override func mouseDown(with event: NSEvent) {
		scroll(to: event)
	}

	override func mouseDragged(with event: NSEvent) {
		scroll(to: event)
	}

	private func scroll(to event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		onScrollTo?(offset(atY: point.y))
	}
}
