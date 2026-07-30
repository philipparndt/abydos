import AppKit
import IdeaiKit

/// One tab's display state.
struct EditorTabItem {
	let url: URL
	var isDirty: Bool
	/// A preview tab is the single provisional slot: opened by a click in the
	/// tree, reused by the next click, and replaced rather than accumulated.
	/// Shown in italic, the convention for "this tab is not pinned yet".
	var isPreview: Bool
	/// Directory shown after the filename, relative to the project root.
	var subtitle: String
}

/// Horizontal strip of open-file tabs.
///
/// Hand-drawn rather than built from `NSButton`s so hover, dirty markers, the
/// preview italic and the close affordance all follow the same theme as the rest
/// of the window.
final class EditorTabBar: NSView {
	var onSelect: ((Int) -> Void)?
	var onClose: ((Int) -> Void)?
	/// Double-click promotes a preview tab to a permanent one.
	var onPromote: ((Int) -> Void)?

	private(set) var items: [EditorTabItem] = []
	private var activeIndex: Int?

	private var hoveredIndex: Int?
	private var hoveredClose: Bool = false
	private var trackingArea: NSTrackingArea?

	/// Cached layout, recomputed whenever the tabs or bounds change.
	private var frames: [NSRect] = []

	// Design-time dimensions; every use goes through Theme.scaled so the strip
	// zooms with the rest of the window.
	static var height: CGFloat { Theme.current.scaled(34) }
	private static var horizontalPadding: CGFloat { Theme.current.scaled(10) }
	private static var iconSize: CGFloat { Theme.current.scaled(15) }
	private static var closeSize: CGFloat { Theme.current.scaled(14) }
	private static var maxTabWidth: CGFloat { Theme.current.scaled(260) }
	private static var minTabWidth: CGFloat { Theme.current.scaled(90) }

	override var isFlipped: Bool { true }

	override var intrinsicContentSize: NSSize {
		NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
	}

	/// Re-measures after a zoom change.
	func applyThemeChange() {
		recomputeFrames()
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	// MARK: - Model

	func setItems(_ items: [EditorTabItem], activeIndex: Int?) {
		self.items = items
		self.activeIndex = activeIndex
		recomputeFrames()
		needsDisplay = true
	}

	// MARK: - Layout

	private func recomputeFrames() {
		frames.removeAll()
		var x: CGFloat = 0
		for item in items {
			let width = measuredWidth(for: item)
			frames.append(NSRect(x: x, y: 0, width: width, height: bounds.height))
			x += width
		}
	}

	private func measuredWidth(for item: EditorTabItem) -> CGFloat {
		let name = item.url.lastPathComponent
		let textWidth = (name as NSString).size(withAttributes: [.font: font(for: item)]).width
		let raw = Self.horizontalPadding * 2 + Self.iconSize + Theme.current.scaled(6) + ceil(textWidth) + Theme.current.scaled(8) + Self.closeSize
		return min(Self.maxTabWidth, max(Self.minTabWidth, raw))
	}

	private func font(for item: EditorTabItem) -> NSFont {
		// Italic marks the provisional tab.
		let base = Theme.current.uiFont(12.5)
		guard item.isPreview else { return base }
		let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
		return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		recomputeFrames()
	}

	// MARK: - Hit testing

	private func index(at point: NSPoint) -> Int? {
		frames.firstIndex { $0.contains(point) }
	}

	private func closeRect(for tabRect: NSRect) -> NSRect {
		NSRect(
			x: tabRect.maxX - Self.horizontalPadding - Self.closeSize,
			y: tabRect.midY - Self.closeSize / 2,
			width: Self.closeSize,
			height: Self.closeSize
		)
	}

	// MARK: - Mouse

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp],
			owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseMoved(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		let index = index(at: point)
		let overClose = index.map { closeRect(for: frames[$0]).contains(point) } ?? false

		if index != hoveredIndex || overClose != hoveredClose {
			hoveredIndex = index
			hoveredClose = overClose
			needsDisplay = true
		}
	}

	override func mouseExited(with event: NSEvent) {
		hoveredIndex = nil
		hoveredClose = false
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		guard let index = index(at: point) else { return }

		if closeRect(for: frames[index]).contains(point) {
			onClose?(index)
			return
		}
		if event.clickCount >= 2 {
			onPromote?(index)
			return
		}
		onSelect?(index)
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()

		for (index, item) in items.enumerated() where index < frames.count {
			draw(item: item, in: frames[index], isActive: index == activeIndex, index: index)
		}

		// Hairline under the whole strip, broken by the active tab so it reads as
		// continuous with the editor beneath it.
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
		if let activeIndex, activeIndex < frames.count {
			let rect = frames[activeIndex]
			Theme.current.editorBackground.setFill()
			NSRect(x: rect.minX, y: bounds.maxY - 1, width: rect.width, height: 1).fill()
		}
	}

	private func draw(item: EditorTabItem, in rect: NSRect, isActive: Bool, index: Int) {
		if isActive {
			Theme.current.editorBackground.setFill()
			rect.fill()
			// Accent along the bottom of the active tab.
			Theme.current.gitModified.setFill()
			NSRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 2).fill()
		} else if hoveredIndex == index {
			NSColor.white.withAlphaComponent(0.05).setFill()
			rect.fill()
		}

		// Divider between inactive tabs.
		if !isActive {
			Theme.current.separator.withAlphaComponent(0.6).setFill()
			NSRect(x: rect.maxX - 1, y: Theme.current.scaled(6), width: 1, height: rect.height - Theme.current.scaled(12)).fill()
		}

		var x = rect.minX + Self.horizontalPadding

		let node = FileNode(url: item.url, isDirectory: false)
		if let icon = FileIcon.image(for: node, isExpanded: false) {
			icon.draw(
				in: NSRect(x: x, y: rect.midY - Self.iconSize / 2, width: Self.iconSize, height: Self.iconSize),
				from: .zero,
				operation: .sourceOver,
				fraction: isActive ? 1.0 : 0.75,
				respectFlipped: true,
				hints: nil
			)
		}
		x += Self.iconSize + Theme.current.scaled(6)

		// Reserve room for the close button so the label never runs under it.
		let labelLimit = rect.maxX - Self.horizontalPadding - Self.closeSize - Theme.current.scaled(6) - x

		let color = isActive ? Theme.current.sidebarHeaderText : Theme.current.sidebarText.withAlphaComponent(0.75)
		let label = NSAttributedString(string: item.url.lastPathComponent, attributes: [
			.font: font(for: item),
			.foregroundColor: color,
		])
		let labelSize = label.size()
		label.draw(in: NSRect(
			x: x,
			y: rect.midY - labelSize.height / 2,
			width: max(0, labelLimit),
			height: labelSize.height
		))

		// The close control doubles as the unsaved marker: a dot until hovered.
		let close = closeRect(for: rect)
		if item.isDirty && !(hoveredIndex == index && hoveredClose) {
			let dot = NSBezierPath(ovalIn: NSRect(x: close.midX - 3.5, y: close.midY - 3.5, width: 7, height: 7))
			Theme.current.gitModified.setFill()
			dot.fill()
		} else if isActive || hoveredIndex == index {
			if hoveredClose && hoveredIndex == index {
				let path = NSBezierPath(roundedRect: close.insetBy(dx: -1, dy: -1), xRadius: 4, yRadius: 4)
				NSColor.white.withAlphaComponent(0.12).setFill()
				path.fill()
			}
			let cross = NSBezierPath()
			let inset: CGFloat = 4
			cross.move(to: NSPoint(x: close.minX + inset, y: close.minY + inset))
			cross.line(to: NSPoint(x: close.maxX - inset, y: close.maxY - inset))
			cross.move(to: NSPoint(x: close.maxX - inset, y: close.minY + inset))
			cross.line(to: NSPoint(x: close.minX + inset, y: close.maxY - inset))
			cross.lineWidth = 1.3
			cross.lineCapStyle = .round
			Theme.current.sidebarText.setStroke()
			cross.stroke()
		}
	}
}
