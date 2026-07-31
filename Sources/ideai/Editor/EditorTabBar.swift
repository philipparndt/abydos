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
	/// Identifies the group this strip belongs to, carried on the pasteboard so
	/// a drop knows where the tab came from.
	var groupID: UUID = UUID()
	/// A tab was released clear of every window: the index, and where it landed
	/// in screen coordinates.
	var onTearOff: ((Int, NSPoint) -> Void)?
	/// Which tab the running drag picked up, so the session can say what to do
	/// with it if it ends nowhere.
	private var draggedIndex: Int?
	/// Asked for the URL of a tab about to be dragged, for the drag image.
	var urlForIndex: ((Int) -> URL?)?
	/// A tab was dropped on this strip, to land at the given position.
	var onTabDropped: ((EditorTabDrag.Payload, Int) -> Void)?
	/// A preview mode was chosen for the active tab.
	var onPreviewModeChange: ((PreviewMode) -> Void)?

	private(set) var items: [EditorTabItem] = []
	private var activeIndex: Int?

	private var hoveredIndex: Int?
	private var hoveredClose: Bool = false
	private var trackingArea: NSTrackingArea?

	/// Cached layout, recomputed whenever the tabs or bounds change.
	private var frames: [NSRect] = []

	/// Slot a dragged tab would land in, drawn as a caret while dragging.
	private var dropIndex: Int?

	/// The preview control at the trailing edge, when the active tab has one.
	private var previewModes: [PreviewMode] = []
	private var previewMode: PreviewMode = .source
	private var previewButtonFrame: NSRect = .zero
	private var isPreviewHovered = false

	// Design-time dimensions; every use goes through Theme.scaled so the strip
	// zooms with the rest of the window.
	static var height: CGFloat { Theme.current.scaled(34) }
	private static var horizontalPadding: CGFloat { Theme.current.scaled(10) }
	private static var iconSize: CGFloat { Theme.current.scaled(15) }
	private static var closeSize: CGFloat { Theme.current.scaled(14) }
	private static var maxTabWidth: CGFloat { Theme.current.scaled(260) }
	private static var minTabWidth: CGFloat { Theme.current.scaled(90) }

	override var isFlipped: Bool { true }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		// The strip is its own drop target, so dropping onto it reorders or moves
		// a tab into this group rather than falling through to the pane beneath,
		// which would read the tab bar as the pane's top edge and split.
		registerForDraggedTypes([EditorTabDrag.pasteboardType])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

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

	/// Offers a preview control for the active tab. An empty list hides it.
	func setPreview(modes: [PreviewMode], current: PreviewMode) {
		guard modes != previewModes || current != previewMode else { return }
		previewModes = modes
		previewMode = current
		recomputeFrames()
		needsDisplay = true
	}

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

		guard !previewModes.isEmpty else {
			previewButtonFrame = .zero
			return
		}
		// Pinned to the trailing edge. Tabs are free to run underneath when
		// there are too many of them; the control stays on top and reachable,
		// which matters more than a tab's last few characters.
		let width = previewControlWidth()
		let height = Theme.current.scaled(20)
		previewButtonFrame = NSRect(
			x: max(0, bounds.width - width - Theme.current.scaled(8)),
			y: (bounds.height - height) / 2,
			width: width,
			height: height
		)
	}

	// Metrics for the preview control, shared by its measurement and its
	// drawing. A fixed width fits "Source" and clips "Split Right".
	private static var previewPadding: CGFloat { Theme.current.scaled(7) }
	private static var previewIconSize: CGFloat { Theme.current.scaled(11) }
	private static var previewChevronSize: CGFloat { Theme.current.scaled(8) }
	private static var previewGap: CGFloat { Theme.current.scaled(5) }

	private var previewLabel: NSAttributedString {
		NSAttributedString(string: previewMode.title, attributes: [
			.font: Theme.current.uiFont(11),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
	}

	/// Wide enough for whichever mode is showing.
	private func previewControlWidth() -> CGFloat {
		Self.previewPadding
			+ Self.previewIconSize + Self.previewGap
			+ ceil(previewLabel.size().width) + Self.previewGap
			+ Self.previewChevronSize + Self.previewPadding
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

		let overPreview = !previewModes.isEmpty && previewButtonFrame.contains(point)
		if overPreview != isPreviewHovered {
			isPreviewHovered = overPreview
			needsDisplay = true
		}

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
		isPreviewHovered = false
		needsDisplay = true
	}

	/// Index the pointer went down on, so a drag knows what it is carrying.
	private var pressedIndex: Int?
	private var pressOrigin: NSPoint = .zero

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)

		// Checked before the tabs: the control sits over them when the strip is
		// full, and a click there means the control.
		if !previewModes.isEmpty, previewButtonFrame.contains(point) {
			showPreviewMenu()
			return
		}

		guard let index = index(at: point) else { return }

		if closeRect(for: frames[index]).contains(point) {
			onClose?(index)
			return
		}
		if event.clickCount >= 2 {
			onPromote?(index)
			return
		}
		pressedIndex = index
		pressOrigin = point
		onSelect?(index)
	}

	override func mouseUp(with event: NSEvent) {
		pressedIndex = nil
	}

	private func showPreviewMenu() {
		let menu = NSMenu()
		menu.autoenablesItems = false

		for mode in previewModes {
			let item = NSMenuItem(title: mode.title, action: #selector(choosePreviewMode(_:)), keyEquivalent: "")
			item.target = self
			item.representedObject = mode.rawValue
			item.state = mode == previewMode ? .on : .off
			item.image = Theme.symbol(
				mode.symbolName,
				size: 11 * Theme.current.scale,
				color: Theme.current.sidebarText
			)
			menu.addItem(item)
		}

		menu.popUp(
			positioning: nil,
			at: NSPoint(x: previewButtonFrame.minX, y: previewButtonFrame.maxY),
			in: self
		)
	}

	@objc private func choosePreviewMode(_ sender: NSMenuItem) {
		guard let raw = sender.representedObject as? String,
		      let mode = PreviewMode(rawValue: raw)
		else { return }
		onPreviewModeChange?(mode)
	}

	override func mouseDragged(with event: NSEvent) {
		guard let index = pressedIndex, index < frames.count else { return }
		let point = convert(event.locationInWindow, from: nil)

		// A small threshold, so an imprecise click is not read as a drag.
		guard hypot(point.x - pressOrigin.x, point.y - pressOrigin.y) > 6 else { return }
		pressedIndex = nil
		beginDrag(index: index, event: event)
	}

	private func beginDrag(index: Int, event: NSEvent) {
		let item = NSPasteboardItem()
		let payload: [String: Any] = [
			"group": groupID.uuidString,
			"index": index,
			"path": urlForIndex?(index)?.path ?? "",
		]
		guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
		item.setData(data, forType: EditorTabDrag.pasteboardType)

		let dragItem = NSDraggingItem(pasteboardWriter: item)
		let rect = frames[index]
		dragItem.setDraggingFrame(rect, contents: snapshot(of: index))

		draggedIndex = index
		let session = beginDraggingSession(with: [dragItem], event: event, source: self)
		// A tab released outside the window becomes a window of its own, so
		// sliding it back to where it started would contradict what happens.
		session.animatesToStartingPositionsOnCancelOrFail = false
	}

	/// Renders the tab as the drag image, so what you picked up is what you see.
	private func snapshot(of index: Int) -> NSImage? {
		guard index < frames.count, index < items.count else { return nil }
		let rect = frames[index]
		guard rect.width > 1, rect.height > 1 else { return nil }

		let image = NSImage(size: rect.size)
		image.lockFocus()
		if let context = NSGraphicsContext.current {
			context.cgContext.translateBy(x: -rect.minX, y: 0)
			draw(item: items[index], in: rect, isActive: true, index: index)
		}
		image.unlockFocus()
		return image
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

		drawPreviewControl()
		drawDropCaret()
	}

	/// The mode control at the trailing edge.
	private func drawPreviewControl() {
		guard !previewModes.isEmpty, previewButtonFrame.width > 0 else { return }

		// Opaque, because tabs are allowed to scroll underneath it.
		Theme.current.sidebarBackground.setFill()
		previewButtonFrame.insetBy(dx: -Theme.current.scaled(6), dy: -Theme.current.scaled(6)).fill()

		let path = NSBezierPath(
			roundedRect: previewButtonFrame,
			xRadius: Theme.current.scaled(5),
			yRadius: Theme.current.scaled(5)
		)
		NSColor.white.withAlphaComponent(isPreviewHovered ? 0.14 : 0.07).setFill()
		path.fill()

		var x = previewButtonFrame.minX + Self.previewPadding
		let colour = Theme.current.sidebarHeaderText

		if let icon = Theme.symbol(previewMode.symbolName, size: 10 * Theme.current.scale, color: colour) {
			let size = Self.previewIconSize
			icon.draw(
				in: NSRect(x: x, y: previewButtonFrame.midY - size / 2, width: size, height: size),
				from: .zero,
				operation: .sourceOver,
				fraction: 1.0,
				respectFlipped: true,
				hints: nil
			)
			x += size + Self.previewGap
		}

		let label = previewLabel
		label.draw(at: NSPoint(x: x, y: previewButtonFrame.midY - label.size().height / 2))

		// A chevron, so it reads as a menu rather than a toggle.
		if let chevron = Theme.symbol("chevron.down", size: 7 * Theme.current.scale, color: colour) {
			let size = Self.previewChevronSize
			chevron.draw(
				in: NSRect(
					x: previewButtonFrame.maxX - size - Self.previewPadding,
					y: previewButtonFrame.midY - size / 2,
					width: size,
					height: size
				),
				from: .zero,
				operation: .sourceOver,
				fraction: 1.0,
				respectFlipped: true,
				hints: nil
			)
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


// MARK: - Drop destination

extension EditorTabBar {
	/// Slot index the pointer sits in: the gap the tab would be inserted into.
	private func insertionIndex(for point: NSPoint) -> Int {
		for (index, frame) in frames.enumerated() where point.x < frame.midX {
			return index
		}
		return items.count
	}

	/// Left edge of a slot, for drawing the caret.
	private func insertionX(for index: Int) -> CGFloat {
		if let frame = frames[safe: index] { return frame.minX }
		return frames.last.map(\.maxX) ?? 0
	}

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		updateDropIndex(sender)
		return .move
	}

	override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
		updateDropIndex(sender)
		return .move
	}

	override func draggingExited(_ sender: NSDraggingInfo?) {
		clearDropIndex()
	}

	override func draggingEnded(_ sender: NSDraggingInfo) {
		clearDropIndex()
	}

	private func updateDropIndex(_ sender: NSDraggingInfo) {
		guard EditorTabDrag.payload(from: sender.draggingPasteboard) != nil else { return }
		let index = insertionIndex(for: convert(sender.draggingLocation, from: nil))
		guard index != dropIndex else { return }
		dropIndex = index
		needsDisplay = true
	}

	private func clearDropIndex() {
		guard dropIndex != nil else { return }
		dropIndex = nil
		needsDisplay = true
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		let index = dropIndex ?? insertionIndex(for: convert(sender.draggingLocation, from: nil))
		clearDropIndex()
		guard let payload = EditorTabDrag.payload(from: sender.draggingPasteboard) else { return false }
		onTabDropped?(payload, index)
		return true
	}

	/// The caret marking where the tab lands.
	func drawDropCaret() {
		guard let dropIndex else { return }
		let width = Theme.current.scaled(2)
		let inset = Theme.current.scaled(4)
		Theme.current.gitModified.setFill()
		NSRect(
			x: insertionX(for: dropIndex) - width / 2,
			y: inset,
			width: width,
			height: bounds.height - inset * 2
		).fill()
	}
}

private extension Array {
	subscript(safe index: Int) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}

extension EditorTabBar: NSDraggingSource {
	func draggingSession(
		_ session: NSDraggingSession,
		sourceOperationMaskFor context: NSDraggingContext
	) -> NSDragOperation {
		// Within the app only: a tab has no meaning dropped elsewhere.
		context == .withinApplication ? .move : []
	}

	/// A tab let go where nothing wanted it becomes a window of its own.
	func draggingSession(
		_ session: NSDraggingSession,
		endedAt screenPoint: NSPoint,
		operation: NSDragOperation
	) {
		let index = draggedIndex
		draggedIndex = nil

		// Something accepted it — another group, this strip, an edge to split.
		guard operation == [], let index, let frame = window?.frame else { return }
		guard TearOff.tearsOff(dropPoint: screenPoint, sourceWindowFrame: frame) else { return }
		onTearOff?(index, screenPoint)
	}
}
