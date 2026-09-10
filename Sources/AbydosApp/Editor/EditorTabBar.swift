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
	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// Index the pointer went down on, so a drag knows what it is carrying.
	var pressedIndex: Int?
	var pressOrigin: NSPoint = .zero

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
	/// The tab should show its file as bytes.
	var onOpenAsHex: ((Int) -> Void)?
	/// The tab's file should show who last touched each line.
	var onBlame: ((Int) -> Void)?
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
	var draggedIndex: Int?
	/// Asked for the URL of a tab about to be dragged, for the drag image.
	var urlForIndex: ((Int) -> URL?)?
	/// A tab was dropped on this strip, to land at the given position.
	var onTabDropped: ((EditorTabDrag.Payload, Int) -> Void)?
	/// A preview mode was chosen for the active tab.
	var onPreviewModeChange: ((PreviewMode) -> Void)?

	private(set) var items: [EditorTabItem] = []
	var activeIndex: Int?

	/// Whether the cursor is in the pane this strip belongs to.
	///
	/// Asked of the group's own container rather than of a particular view, so
	/// anything the group holds — the code, the find bar, a preview — counts as
	/// the keyboard being here. In a split each group has its own container, so
	/// only one of them can answer yes.
	var hasKeyboardFocus: Bool {
		// Whether the window is in front does not come into it: switching to
		// another app does not move the cursor, and a strip that drops the
		// accent when it goes behind says it did.
		guard let window,
		      let responder = window.firstResponder as? NSView,
		      let group = superview
		else { return false }
		return responder === self || responder.isDescendant(of: group)
	}

	var hoveredIndex: Int?
	var hoveredClose: Bool = false
	var trackingArea: NSTrackingArea?

	/// Cached layout, recomputed whenever the tabs or bounds change.
	var frames: [NSRect] = []

	/// Slot a dragged tab would land in, drawn as a caret while dragging.
	private var dropIndex: Int?

	/// The preview control at the trailing edge, when the active tab has one.
	var previewModes: [PreviewMode] = []
	var previewMode: PreviewMode = .source
	var previewButtonFrame: NSRect = .zero
	var isPreviewHovered = false
	/// Gives the editor the whole window, or gives it back.
	///
	/// Here rather than in the window's toolbar, where it started: it is about
	/// the editor, it sits with the other things that act on this strip, and up
	/// in the titlebar it read as a window control of macOS's own — beside the
	/// traffic lights, doing something none of them do.
	var maximizeButtonFrame: NSRect = .zero
	var isMaximizeHovered = false
	/// Which way the arrows point. The icon is the state: a button that looked
	/// the same either way leaves somebody in a maximised window with no way of
	/// knowing that the way out is the button they just pressed.
	var isMaximized = false

	/// A square, like the chevron beside it.
	private static var maximizeWidth: CGFloat { Theme.current.scaled(26) }

	func setMaximized(_ maximized: Bool) {
		guard maximized != isMaximized else { return }
		isMaximized = maximized
		needsDisplay = true
	}

	/// The chevron offering the tabs there was no room for.
	var overflowButtonFrame: NSRect = .zero
	private var visibleRun: Range<Int> = 0..<0
	var hiddenTabs: [Int] = []
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
	static var horizontalPadding: CGFloat { Theme.current.scaled(10) }
	static var iconSize: CGFloat { Theme.current.scaled(15) }
	static var closeSize: CGFloat { Theme.current.scaled(14) }
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
	static var previewPadding: CGFloat { Theme.current.scaled(7) }
	static var previewIconSize: CGFloat { Theme.current.scaled(11) }
	static var previewChevronSize: CGFloat { Theme.current.scaled(8) }
	static var previewGap: CGFloat { Theme.current.scaled(5) }

	var previewLabel: NSAttributedString {
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

	func font(for item: EditorTabItem) -> NSFont {
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

	func index(at point: NSPoint) -> Int? {
		frames.firstIndex { $0.contains(point) }
	}

	func closeRect(for tabRect: NSRect) -> NSRect {
		NSRect(
			x: tabRect.maxX - Self.horizontalPadding - Self.closeSize,
			y: tabRect.midY - Self.closeSize / 2,
			width: Self.closeSize,
			height: Self.closeSize
		)
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
		// A negative index is the strip's empty part — `--tab-double empty` —
		// which is where the setting decides what a double-click does. Just
		// past the last tab, or the middle of an empty strip; short of the
		// buttons at the trailing edge.
		let centre: NSPoint
		let was: String
		if index < 0 {
			let afterTabs = (frames.last?.maxX ?? 0) + Theme.current.scaled(30)
			centre = NSPoint(x: min(afterTabs, bounds.midX), y: bounds.midY)
			was = "the empty part of the strip (\(Settings.shared.tabStripDoubleClick.rawValue))"
		} else {
			guard frames.indices.contains(index), items.indices.contains(index) else {
				return "no tab at \(index)"
			}
			was = items[index].isPreview ? "preview" : "permanent"
			centre = NSPoint(x: frames[index].midX, y: frames[index].midY)
		}
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
		return index < 0 ? "double-clicked \(was)" : "double-clicked a \(was) tab"
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
