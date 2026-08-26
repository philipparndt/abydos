import AppKit
import AbydosKit

/// One tab's display state.
struct EditorTabItem {
	let url: URL
	/// What the tab says. Usually the filename, but a scratch has no name of
	/// its own and is called by its number instead.
	var title: String
	var isDirty: Bool
	/// A preview tab is the single provisional slot: opened by a click in the
	/// tree, reused by the next click, and replaced rather than accumulated.
	/// Shown in italic, the convention for "this tab is not pinned yet".
	var isPreview: Bool
	/// Directory shown after the filename, relative to the project root.
	var subtitle: String
	/// The symbol a page is marked with, in place of a file icon.
	var pageSymbol: String?
	/// A file from outside the project.
	///
	/// Marked, because nothing else about the tab says so: a file opened from
	/// another checkout looks exactly like one from this one, and editing the
	/// wrong copy is a mistake that takes a while to notice.
	var isExternal = false
}

/// Horizontal strip of open-file tabs.
///
/// Hand-drawn rather than built from `NSButton`s so hover, dirty markers, the
/// preview italic and the close affordance all follow the same theme as the rest
/// of the window.
final class EditorTabBar: NSView {
	var onSelect: ((Int) -> Void)?
	var onClose: ((Int) -> Void)?
	/// Closing several at once, from the tab's own menu.
	var onCloseOthers: ((Int) -> Void)?
	var onCloseLeft: ((Int) -> Void)?
	var onCloseRight: ((Int) -> Void)?
	var onCloseAll: (() -> Void)?
	/// Asked to show a file in the Finder, or to copy its path.
	var onRevealInFinder: ((Int) -> Void)?
	var onCopyPath: ((Int) -> Void)?
	/// Double-click promotes a preview tab to a permanent one.
	var onPromote: ((Int) -> Void)?
	/// Double-clicking a tab that is already permanent: give the editor the
	/// whole window, or give it back.
	var onMaximize: (() -> Void)?
	/// The empty part of the strip was double-clicked: make a scratch.
	var onNewScratch: (() -> Void)?
	/// Asked for a scratch belonging to no project, from that strip's menu.
	var onNewGlobalScratch: (() -> Void)?
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

	/// Whether the cursor is in the pane this strip belongs to.
	///
	/// Asked of the group's own container rather than of a particular view, so
	/// anything the group holds — the code, the find bar, a preview — counts as
	/// the keyboard being here. In a split each group has its own container, so
	/// only one of them can answer yes.
	private var hasKeyboardFocus: Bool {
		// Whether the window is in front does not come into it: switching to
		// another app does not move the cursor, and a strip that drops the
		// accent when it goes behind says it did.
		guard let window,
		      let responder = window.firstResponder as? NSView,
		      let group = superview
		else { return false }
		return responder === self || responder.isDescendant(of: group)
	}

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
	/// Gives the editor the whole window, or gives it back.
	///
	/// Here rather than in the window's toolbar, where it started: it is about
	/// the editor, it sits with the other things that act on this strip, and up
	/// in the titlebar it read as a window control of macOS's own — beside the
	/// traffic lights, doing something none of them do.
	private var maximizeButtonFrame: NSRect = .zero
	private var isMaximizeHovered = false
	/// Which way the arrows point. The icon is the state: a button that looked
	/// the same either way leaves somebody in a maximised window with no way of
	/// knowing that the way out is the button they just pressed.
	private var isMaximized = false

	/// A square, like the chevron beside it.
	private static var maximizeWidth: CGFloat { Theme.current.scaled(26) }

	func setMaximized(_ maximized: Bool) {
		guard maximized != isMaximized else { return }
		isMaximized = maximized
		needsDisplay = true
	}

	/// The chevron offering the tabs there was no room for.
	private var overflowButtonFrame: NSRect = .zero
	private var visibleRun: Range<Int> = 0..<0
	private var hiddenTabs: [Int] = []
	/// Which tab the run starts at, and which that is by name.
	///
	/// Milder here than on the panel's strip — ⌘] and ⌘[ move between these
	/// tabs, so a hidden one was always reachable from the keyboard — but the
	/// same fault: an editor tab past the trailing edge cannot be clicked, and
	/// this bar caps a tab at 260 points and floors it at 90, so thirty open
	/// files overflow any window.
	private var runStart = 0
	private var runStartURL: URL?
	/// Wide enough for a chevron and a count of two digits.
	private static var overflowWidth: CGFloat { Theme.current.scaled(34) }

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

		// The line under the active tab says where the keyboard is, so it has to
		// be redrawn when the keyboard moves — including into another pane,
		// which this strip is told nothing about otherwise.
		NotificationCenter.default.addObserver(
			forName: .keyboardFocusChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.needsDisplay = true }
		}
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
		// By the file it starts at rather than by its number: closing a tab
		// before the run shifts every index after it, and the run would jump.
		runStart = runStartURL.flatMap { url in items.firstIndex { $0.url == url } } ?? 0
		recomputeFrames()
		showActiveTab()
		needsDisplay = true
	}

	// MARK: - Layout

	private func recomputeFrames() {
		frames.removeAll()

		// The trailing control first, because what it leaves is what the tabs
		// get. This used to be placed after them, from `bounds.width` backwards,
		// which is how tabs came to run underneath it — the comment there said
		// so and called it a trade. It was the right trade for the drawing and
		// the wrong one for reaching a tab, which is what the chevron below is.
		let controlHeight = Theme.current.scaled(20)
		// Outermost of the trailing controls, because it is the one about the
		// window rather than about what is in the strip.
		maximizeButtonFrame = NSRect(
			x: max(0, bounds.width - Self.maximizeWidth - Theme.current.scaled(8)),
			y: (bounds.height - controlHeight) / 2,
			width: Self.maximizeWidth,
			height: controlHeight
		)

		if previewModes.isEmpty {
			previewButtonFrame = .zero
		} else {
			let width = previewControlWidth()
			previewButtonFrame = NSRect(
				x: max(0, maximizeButtonFrame.minX - width - Theme.current.scaled(8)),
				y: (bounds.height - controlHeight) / 2,
				width: width,
				height: controlHeight
			)
		}

		let widths = items.map(measuredWidth(for:))
		let plain = TabOverflow.measure(
			widths: widths, start: runStart, available: tabRoom(overflowing: false)
		)
		let overflow = plain.isOverflowing
			? TabOverflow.measure(widths: widths, start: runStart, available: tabRoom(overflowing: true))
			: plain
		visibleRun = overflow.visible
		hiddenTabs = overflow.hidden
		overflowButtonFrame = overflow.isOverflowing
			? NSRect(
				x: tabRoom(overflowing: false) - Self.overflowWidth,
				y: 0,
				width: Self.overflowWidth,
				height: bounds.height
			)
			: .zero

		var x: CGFloat = 0
		for (index, width) in widths.enumerated() {
			// Hidden tabs keep their place and get no rectangle: everything that
			// finds a tab asks `frames` by index, and an empty rect contains no
			// point.
			guard visibleRun.contains(index) else {
				frames.append(.zero)
				continue
			}
			frames.append(NSRect(x: x, y: 0, width: width, height: bounds.height))
			x += width
		}
	}

	/// How much room the tabs have: up to the preview control, less the chevron
	/// where there is one.
	private func tabRoom(overflowing: Bool) -> CGFloat {
		var room = previewButtonFrame.width > 0
			? previewButtonFrame.minX - Theme.current.scaled(8)
			: maximizeButtonFrame.minX - Theme.current.scaled(8)
		if overflowing { room -= Self.overflowWidth }
		return max(0, room)
	}

	/// Moves the run, if it has to, so the active tab is one somebody can see.
	private func showActiveTab() {
		guard let active = activeIndex, items.indices.contains(active) else { return }
		let widths = items.map(measuredWidth(for:))
		let room = tabRoom(overflowing: true)
		// Forward if the active tab does not fit, then back into any room going
		// spare at the trailing end — see `TabOverflow.settled`. Without the
		// second half, tabs closed while the run was forward left the strip half
		// empty with the chevron still offering the ones before it.
		let moved = TabOverflow.settled(
			start: TabOverflow.start(showing: active, widths: widths, from: runStart, available: room),
			widths: widths,
			available: room
		)
		guard moved != runStart else { return }
		runStart = moved
		runStartURL = items[safe: moved]?.url
		recomputeFrames()
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
		let name = item.title
		let textWidth = (name as NSString).size(withAttributes: [.font: font(for: item)]).width
		let marker = item.isExternal ? Theme.current.scaled(14) : 0
		let raw = Self.horizontalPadding * 2 + Self.iconSize + Theme.current.scaled(6) + ceil(textWidth) + marker + Theme.current.scaled(8) + Self.closeSize
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
		updateHover(at: convert(event.locationInWindow, from: nil))
	}

	private func updateHover(at point: NSPoint) {
		let overPreview = !previewModes.isEmpty && previewButtonFrame.contains(point)
		if overPreview != isPreviewHovered {
			isPreviewHovered = overPreview
			needsDisplay = true
		}

		let overMaximize = maximizeButtonFrame.contains(point)
		if overMaximize != isMaximizeHovered {
			isMaximizeHovered = overMaximize
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
		clearHover()
	}

	private func clearHover() {
		hoveredIndex = nil
		hoveredClose = false
		isPreviewHovered = false
		isMaximizeHovered = false
		needsDisplay = true
	}

	/// Index the pointer went down on, so a drag knows what it is carrying.
	private var pressedIndex: Int?
	private var pressOrigin: NSPoint = .zero

	/// What a right-click on a tab offers.
	///
	/// The closes people reach for — this one, the others, the ones to either
	/// side — plus the two things anybody wants from a tab that names a file.
	override func rightMouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		NSMenu.popUpContextMenu(menu(at: point), with: event, for: self)
	}

	/// The menu for a point on the strip: the tab under it, or the strip itself.
	private func menu(at point: NSPoint) -> NSMenu {
		guard let index = frames.firstIndex(where: { $0.contains(point) }), index < items.count
		else { return emptyStripMenu() }

		let menu = NSMenu()
		func add(_ title: String, _ action: Selector, enabled: Bool = true) {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = self
			item.representedObject = index
			item.isEnabled = enabled
			menu.addItem(item)
		}

		add("Close", #selector(closeFromMenu(_:)))
		add("Close Others", #selector(closeOthersFromMenu(_:)), enabled: items.count > 1)
		add("Close to the Left", #selector(closeLeftFromMenu(_:)), enabled: index > 0)
		add(
			"Close to the Right", #selector(closeRightFromMenu(_:)),
			enabled: index < items.count - 1
		)
		add("Close All", #selector(closeAllFromMenu(_:)))
		menu.addItem(.separator())
		add("Copy Path", #selector(copyPathFromMenu(_:)))
		add("Reveal in Finder", #selector(revealFromMenu(_:)))
		return menu
	}

	/// The titles a right-click offers at a point, for checking that the empty
	/// part of the strip offers something rather than falling through.
	func contextMenuTitlesForTesting(overTab: Bool) -> [String] {
		let point = overTab && !frames.isEmpty
			? NSPoint(x: frames[0].midX, y: bounds.midY)
			: NSPoint(x: bounds.maxX - Theme.current.scaled(4), y: bounds.midY)
		return menu(at: point).items.map(\.title)
	}

	/// What a right-click on the empty part of the strip offers.
	///
	/// The same thing double-clicking there already does, plus the scratch that
	/// belongs to no project. Double-click is the shortcut for people who know
	/// it; a menu is how anybody else finds out either exists — and it is the
	/// only way to reach the global one without the Scratches pane.
	private func emptyStripMenu() -> NSMenu {
		let menu = NSMenu()
		for (title, action) in [
			("New Scratch File", #selector(newScratchFromMenu(_:))),
			("New Global Scratch File", #selector(newGlobalScratchFromMenu(_:))),
		] {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = self
			menu.addItem(item)
		}
		return menu
	}

	@objc private func newScratchFromMenu(_ sender: NSMenuItem) { onNewScratch?() }

	@objc private func newGlobalScratchFromMenu(_ sender: NSMenuItem) { onNewGlobalScratch?() }

	private func index(of sender: NSMenuItem) -> Int? { sender.representedObject as? Int }

	@objc private func closeFromMenu(_ sender: NSMenuItem) {
		if let index = index(of: sender) { onClose?(index) }
	}

	@objc private func closeOthersFromMenu(_ sender: NSMenuItem) {
		if let index = index(of: sender) { onCloseOthers?(index) }
	}

	@objc private func closeLeftFromMenu(_ sender: NSMenuItem) {
		if let index = index(of: sender) { onCloseLeft?(index) }
	}

	@objc private func closeRightFromMenu(_ sender: NSMenuItem) {
		if let index = index(of: sender) { onCloseRight?(index) }
	}

	@objc private func closeAllFromMenu(_ sender: NSMenuItem) { onCloseAll?() }

	@objc private func copyPathFromMenu(_ sender: NSMenuItem) {
		if let index = index(of: sender) { onCopyPath?(index) }
	}

	@objc private func revealFromMenu(_ sender: NSMenuItem) {
		if let index = index(of: sender) { onRevealInFinder?(index) }
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)

		// Checked before the tabs: the control sits over them when the strip is
		// full, and a click there means the control.
		if overflowButtonFrame.width > 0, overflowButtonFrame.contains(point) {
			showOverflowMenu()
			return
		}
		if !previewModes.isEmpty, previewButtonFrame.contains(point) {
			showPreviewMenu()
			return
		}
		if maximizeButtonFrame.contains(point) {
			onMaximize?()
			return
		}

		guard let index = index(at: point) else {
			// Double-clicking the empty part of the strip opens a scratch, the
			// way it does in the editors people arrive from.
			if event.clickCount == 2 { onNewScratch?() }
			return
		}

		if closeRect(for: frames[index]).contains(point) {
			onClose?(index)
			return
		}
		if event.clickCount >= 2 {
			// **A provisional tab is promoted; an already-permanent one gives the
			// editor the window.** One gesture, two meanings, and the tab says
			// which it will be: a preview tab is drawn in italic, so what a
			// double-click is about to do is on screen rather than remembered.
			//
			// Promoting first also means the tab survives what happens next: a
			// maximised editor with a provisional tab in it is one click from
			// being replaced by the next file somebody looks at.
			if items.indices.contains(index), items[index].isPreview {
				onPromote?(index)
			} else {
				onMaximize?()
			}
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
			// The key it already answers to, shown here rather than only in the
			// menu bar: this dropdown is where somebody is looking when they
			// wonder how to do it again without the mouse.
			let index = PreviewMode.allCases.firstIndex(of: mode).map { String($0 + 1) } ?? ""
			let item = NSMenuItem(
				title: mode.title, action: #selector(choosePreviewMode(_:)), keyEquivalent: index
			)
			item.keyEquivalentModifierMask = [.control, .command]
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

		// **A hidden tab has no rectangle, and must not be drawn into it.** An
		// empty frame is `.zero`, whose origin is the top-left corner of the
		// strip — so every tab scrolled out of the run painted its icon and the
		// first few pixels of its name there, one on top of another, behind the
		// first visible tab. That is the clutter above the first tab.
		for (index, item) in items.enumerated()
		where index < frames.count && !frames[index].isEmpty {
			draw(item: item, in: frames[index], isActive: index == activeIndex, index: index)
		}

		// Hairline under the whole strip, broken by the active tab so it reads as
		// continuous with the editor beneath it.
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
		if let activeIndex, activeIndex < frames.count, !frames[activeIndex].isEmpty {
			let rect = frames[activeIndex]
			Theme.current.editorBackground.setFill()
			NSRect(x: rect.minX, y: bounds.maxY - 1, width: rect.width, height: 1).fill()

			// The line under the tab that is showing, drawn after the hairline
			// rather than with the tab: filling the hairline back in over the
			// active tab painted out the bottom half of it, which is why it
			// came out thinner than the panel's. In the accent colour when the
			// cursor is in this pane and plain when it is not — otherwise a
			// split and a terminal show three tabs all claiming the keyboard.
			TabSelectionLine.color(focused: hasKeyboardFocus).setFill()
			TabSelectionLine.rect(in: rect, alongTop: false).fill()
		}

		drawOverflowControl()
		drawPreviewControl()
		drawMaximizeControl()
		drawDropCaret()
	}

	/// The tabs there was no room for.
	///
	/// The count comes with the chevron here too. The editor's case is milder
	/// than the panel's — ⌘] and ⌘[ reach a hidden tab from the keyboard — but
	/// two strips that answer the same question two ways is the thing this
	/// change exists to stop, and "how many am I not seeing" is worth the same
	/// four points in both.
	private func drawOverflowControl() {
		guard overflowButtonFrame.width > 0 else { return }

		Theme.current.sidebarBackground.setFill()
		overflowButtonFrame.fill()

		let colour = Theme.current.sidebarHeaderText
		let count = NSAttributedString(string: String(hiddenTabs.count), attributes: [
			.font: Theme.current.uiFont(10, weight: .medium),
			.foregroundColor: colour,
		])
		let size = count.size()
		let chevron = Theme.current.scaled(9)
		let content = size.width + Theme.current.scaled(3) + chevron
		let left = overflowButtonFrame.midX - content / 2

		count.draw(at: NSPoint(x: left, y: overflowButtonFrame.midY - size.height / 2))
		if let icon = Theme.symbol("chevron.down", size: 9 * Theme.current.scale, color: colour) {
			icon.drawFitted(in: NSRect(
				x: left + size.width + Theme.current.scaled(3),
				y: overflowButtonFrame.midY - chevron / 2,
				width: chevron,
				height: chevron
			))
		}
	}

	/// Only the hidden ones — a list of everything is a tab switcher, which is a
	/// different feature with a different gesture.
	private func showOverflowMenu() {
		guard !hiddenTabs.isEmpty else { return }
		let menu = NSMenu()
		for index in hiddenTabs {
			guard let item = items[safe: index] else { continue }
			// The subtitle is the directory, which is what tells two files of
			// the same name apart — and files of the same name are exactly what
			// fills a tab bar.
			let title = item.subtitle.isEmpty ? item.title : "\(item.title)  —  \(item.subtitle)"
			let entry = NSMenuItem(title: title, action: #selector(selectFromOverflow(_:)), keyEquivalent: "")
			entry.target = self
			entry.representedObject = index
			entry.state = index == activeIndex ? .on : .off
			menu.addItem(entry)
		}
		menu.popUp(
			positioning: nil,
			at: NSPoint(x: overflowButtonFrame.minX, y: overflowButtonFrame.maxY),
			in: self
		)
	}

	@objc private func selectFromOverflow(_ sender: NSMenuItem) {
		guard let index = sender.representedObject as? Int else { return }
		onSelect?(index)
	}

	/// The window-shape control at the trailing edge.
	private func drawMaximizeControl() {
		guard maximizeButtonFrame.width > 0 else { return }

		// Opaque, because tabs are allowed to scroll underneath it.
		Theme.current.sidebarBackground.setFill()
		maximizeButtonFrame
			.insetBy(dx: -Theme.current.scaled(6), dy: -Theme.current.scaled(6))
			.fill()

		if isMaximizeHovered {
			let path = NSBezierPath(
				roundedRect: maximizeButtonFrame,
				xRadius: Theme.current.scaled(5),
				yRadius: Theme.current.scaled(5)
			)
			NSColor.white.withAlphaComponent(0.14).setFill()
			path.fill()
		}

		let name = isMaximized
			? "arrow.down.right.and.arrow.up.left"
			: "arrow.up.left.and.arrow.down.right"
		guard let icon = Theme.symbol(
			name, size: 11 * Theme.current.scale,
			color: Theme.current.sidebarHeaderText, weight: .medium
		) else { return }
		let size = icon.size
		icon.draw(in: NSRect(
			x: maximizeButtonFrame.midX - size.width / 2,
			y: maximizeButtonFrame.midY - size.height / 2,
			width: size.width,
			height: size.height
		))
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
			icon.drawFitted(in: NSRect(x: x, y: previewButtonFrame.midY - size / 2, width: size, height: size))
			x += size + Self.previewGap
		}

		let label = previewLabel
		label.draw(at: NSPoint(x: x, y: previewButtonFrame.midY - label.size().height / 2))

		// A chevron, so it reads as a menu rather than a toggle.
		if let chevron = Theme.symbol("chevron.down", size: 7 * Theme.current.scale, color: colour) {
			let size = Self.previewChevronSize
			chevron.drawFitted(in: NSRect(
					x: previewButtonFrame.maxX - size - Self.previewPadding,
					y: previewButtonFrame.midY - size / 2,
					width: size,
					height: size
				))
		}
	}

	private func draw(item: EditorTabItem, in rect: NSRect, isActive: Bool, index: Int) {
		if isActive {
			Theme.current.editorBackground.setFill()
			rect.fill()
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

		let iconRect = NSRect(
			x: x, y: rect.midY - Self.iconSize / 2, width: Self.iconSize, height: Self.iconSize
		)
		if let symbol = item.pageSymbol {
			Theme.symbol(
				symbol,
				size: 12 * Theme.current.scale,
				color: Theme.current.sidebarText.withAlphaComponent(isActive ? 0.95 : 0.7)
			)?.drawFitted(in: iconRect)
		} else if let icon = FileIcon.image(for: FileNode(url: item.url, isDirectory: false), isExpanded: false) {
			icon.drawFitted(in: iconRect, fraction: isActive ? 1.0 : 0.75)
		}
		x += Self.iconSize + Theme.current.scaled(6)

		// Reserve room for the close button so the label never runs under it.
		let labelLimit = rect.maxX - Self.horizontalPadding - Self.closeSize - Theme.current.scaled(6) - x

		let color = isActive ? Theme.current.sidebarHeaderText : Theme.current.sidebarText.withAlphaComponent(0.75)
		let label = NSAttributedString(string: item.title, attributes: [
			.font: font(for: item),
			.foregroundColor: color,
		])
		let labelSize = label.size()
		let marker = item.isExternal ? Theme.current.scaled(14) : 0
		label.draw(in: NSRect(
			x: x,
			y: rect.midY - labelSize.height / 2,
			width: max(0, labelLimit - marker),
			height: labelSize.height
		))

		// The mark for a file that is not in this project, in the colour the
		// rest of the window uses for "look at this".
		if item.isExternal {
			let arrow = NSAttributedString(string: "↗", attributes: [
				.font: Theme.current.uiFont(11, weight: .semibold),
				.foregroundColor: Theme.current.gitModified.withAlphaComponent(isActive ? 0.95 : 0.7),
			])
			let size = arrow.size()
			arrow.draw(at: NSPoint(
				x: min(x + labelSize.width + Theme.current.scaled(4), rect.maxX - Self.horizontalPadding - Self.closeSize - marker),
				y: rect.midY - size.height / 2
			))
		}

		// The close control doubles as the unsaved marker: a dot until hovered.
		let close = closeRect(for: rect)
		if item.isDirty && !(hoveredIndex == index && hoveredClose) {
			let dot = NSBezierPath(ovalIn: NSRect(x: close.midX - 3.5, y: close.midY - 3.5, width: 7, height: 7))
			Theme.current.gitModified.setFill()
			dot.fill()
		} else if isActive || hoveredIndex == index {
			TabCloseButton.draw(
				in: close,
				hovered: hoveredClose && hoveredIndex == index,
				inset: 4,
				lineWidth: 1.3
			)
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

extension Array {
	subscript(safe index: Int) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}

extension EditorTabBar: TabCloseHovering {
	var tabCountForTesting: Int { items.count }

	@discardableResult
	/// Double-clicks a tab the way a pointer does, and says which branch it
	/// took.
	///
	/// Through `mouseDown` with a real event, because the branch *is* the
	/// behaviour: a provisional tab is promoted and a permanent one asks for the
	/// window, and a check that called either method directly could not be wrong
	/// about which.
	func doubleClickForTesting(index: Int) -> String {
		guard frames.indices.contains(index), items.indices.contains(index) else {
			return "no tab at \(index)"
		}
		let was = items[index].isPreview ? "preview" : "permanent"
		let centre = NSPoint(x: frames[index].midX, y: frames[index].midY)
		guard let event = NSEvent.mouseEvent(
			with: .leftMouseDown,
			location: convert(centre, to: nil),
			modifierFlags: [],
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: window?.windowNumber ?? 0,
			context: nil,
			eventNumber: 0,
			clickCount: 2,
			pressure: 1
		) else { return "no event" }
		mouseDown(with: event)
		return "double-clicked a \(was) tab"
	}

	func hoverCloseForTesting(_ index: Int?) -> String {
		// Through `updateHover` rather than by setting the two flags: what is
		// being checked is what the pointer does, and a harness that assigns the
		// state directly would pass with the hit test wired to nothing.
		if let frame = index.flatMap({ frames[safe: $0] }) {
			let close = closeRect(for: frame)
			updateHover(at: NSPoint(x: close.midX, y: close.midY))
		} else {
			clearHover()
		}
		// Every editor tab closes, so there is no `isClosable` to report — it is
		// printed as a constant so the two strips' lines read the same way.
		let title = index.flatMap { items[safe: $0] }?.title ?? "-"
		return "editor       \"\(title)\" closable=true"
			+ " -> tab=\(hoveredIndex.map(String.init) ?? "none") close=\(hoveredClose)"
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
