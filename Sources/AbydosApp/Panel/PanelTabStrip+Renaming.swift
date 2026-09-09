import AppKit
import AbydosKit

/// Renaming a tab in place, and dragging one — within the strip, and out of
/// it into a window of its own.
extension PanelTabStrip {
	// MARK: - Renaming in place


	func beginRenaming(_ index: Int) {
		guard frames.indices.contains(index) else { return }
		endRenaming(commit: true)

		let field = CenteredTextField(string: items[index].title)
		field.font = font
		field.textColor = Theme.current.sidebarHeaderText
		field.backgroundColor = Theme.current.editorBackground
		field.drawsBackground = true
		field.isBordered = false
		field.isBezeled = false
		field.focusRingType = .none
		field.delegate = self
		// The height a line of this font actually needs, centred in the tab: a
		// field the height of the tab puts its text against the top.
		let height = ceil(font.ascender - font.descender + font.leading) + Theme.current.scaled(6)
		let tab = frames[index]
		field.frame = NSRect(
			x: tab.minX + Theme.current.scaled(4),
			y: tab.midY - height / 2,
			width: tab.width - Theme.current.scaled(8),
			height: height
		)
		field.wantsLayer = true
		field.layer?.cornerRadius = 3

		addSubview(field)
		renameField = field
		renamingIndex = index
		window?.makeFirstResponder(field)
		field.currentEditor()?.selectAll(nil)
	}

	func endRenaming(commit: Bool) {
		guard let field = renameField, let index = renamingIndex else { return }
		renameField = nil
		renamingIndex = nil

		let name = field.stringValue
		field.removeFromSuperview()
		if commit { onRename?(index, name) }
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp], owner: self)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseMoved(with event: NSEvent) {
		updateHover(at: convert(event.locationInWindow, from: nil))
	}

	func updateHover(at point: NSPoint) {
		let index = frames.firstIndex { $0.contains(point) }

		// The same question the click asks, and asked the same way: a tmux
		// window has no ✕ to be over, so the pointer never lights one up there.
		let overClose = index.map { index in
			(items[safe: index]?.isClosable ?? true) && closeRect(for: frames[index]).contains(point)
		} ?? false

		let movedControl = tips.update(at: point, in: self)
		if index != hoveredIndex || overClose != hoveredClose || movedControl {
			hoveredIndex = index
			hoveredClose = overClose
			needsDisplay = true
		}
	}

	override func mouseExited(with event: NSEvent) {
		clearHover()
	}

	func clearHover() {
		hoveredIndex = nil
		hoveredClose = false
		tips.clear()
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		pressedIndex = nil
		// Anything pressed puts the tip away: it explains a control somebody
		// has stopped reading about and started using.
		StyledTip.shared.hide()

		switch addControl(at: point) {
		case .plus?: onAdd?(); return
		case .chevron?: onAddMenu?(NSPoint(x: addButtonFrame.minX, y: bounds.maxY)); return
		case nil: break
		}
		if overflowButtonFrame.width > 0, overflowButtonFrame.contains(point) {
			showOverflowMenu()
			return
		}
		if hideButtonFrame.contains(point) { onHide?(); return }
		if maximizeButtonFrame.contains(point) { onToggleMaximize?(); return }
		if sessionsPillFrame.width > 0, sessionsPillFrame.contains(point) {
			onSessionsPillClicked?(sessionsPillFrame)
			return
		}
		if mirroredSession != nil, mirrorTagFrame.contains(point) {
			onMirrorTagClicked?(mirrorTagFrame)
			return
		}
		if followButtonFrame.contains(point) { onToggleFollowProject?(); return }

		// Double-clicking the empty part of the strip does what the arrow does,
		// the way double-clicking a window's title bar zooms it.
		if event.clickCount == 2, !frames.contains(where: { $0.contains(point) }) {
			onToggleMaximize?()
			return
		}

		guard let index = frames.firstIndex(where: { $0.contains(point) }) else { return }
		let closable = items.indices.contains(index) ? items[index].isClosable : true

		// **The cross is asked about before the click count is.** Closing four
		// terminals means four clicks in the same corner of the screen, and the
		// tabs shuffle left under the pointer as they go — so the second, third
		// and fourth arrive inside the double-click interval and AppKit reports
		// them as a double click. Renaming came first here, so the second press
		// on a close button opened a rename field on whichever tab had just slid
		// into that place, and the terminal somebody meant to close was still
		// there with its name selected.
		//
		// A press on a cross is a close whatever the click count. Nobody has
		// ever meant to rename a tab by hitting the one control on it that is
		// not its name.
		if closable, closeRect(for: frames[index]).contains(point) {
			onClose?(index)
			return
		}

		// Double-clicking a tab renames it, in place: the name is a label on a
		// tab, and typing it anywhere else means finding the tab again after.
		if event.clickCount == 2, items.indices.contains(index), items[index].isTerminal {
			beginRenaming(index)
			return
		}

		onSelect?(index)
		// Remembered rather than acted on: a press becomes a drag only if
		// the pointer travels, so selecting a tab stays a click.
		pressedIndex = index
		pressOrigin = point
	}

	override func rightMouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		guard let index = frames.firstIndex(where: { $0.contains(point) }),
		      items.indices.contains(index)
		else { return super.rightMouseDown(with: event) }

		let menu = NSMenu()
		func add(_ title: String, _ action: Selector) {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = self
			item.representedObject = index
			menu.addItem(item)
		}

		if isMirroringTmux {
			// A tmux window is not one of the panel's panes: it cannot be put
			// beside anything here or torn into a window of its own, and the
			// only two things that make sense are its name and its life.
			add("Rename\u{2026}", #selector(renameFromMenu(_:)))
			menu.addItem(.separator())
			add("Kill Window", #selector(closeFromMenu(_:)))
			NSMenu.popUpContextMenu(menu, with: event, for: self)
			return
		}

		if items[index].isTerminal { add("Rename\u{2026}", #selector(renameFromMenu(_:))) }
		add("Put Beside, Left", #selector(splitLeftFromMenu(_:)))
		add("Put Beside, Right", #selector(splitRightFromMenu(_:)))
		if isSplit?() == true { add("Show One Only", #selector(unsplitFromMenu(_:))) }
		menu.addItem(.separator())
		// A window of its own is a terminal thing: a debugger belongs to the
		// window whose program it is stopped in.
		if items[index].isTerminal { add("Move to a Window", #selector(tearOffFromMenu(_:))) }
		add("Close", #selector(closeFromMenu(_:)))

		NSMenu.popUpContextMenu(menu, with: event, for: self)
	}

	@objc private func renameFromMenu(_ sender: NSMenuItem) {
		guard let index = sender.representedObject as? Int else { return }
		beginRenaming(index)
	}

	@objc private func splitLeftFromMenu(_ sender: NSMenuItem) {
		guard let index = sender.representedObject as? Int else { return }
		onSplit?(index, .left)
	}

	@objc private func splitRightFromMenu(_ sender: NSMenuItem) {
		guard let index = sender.representedObject as? Int else { return }
		onSplit?(index, .right)
	}

	@objc private func unsplitFromMenu(_ sender: NSMenuItem) { onUnsplit?() }

	@objc private func tearOffFromMenu(_ sender: NSMenuItem) {
		guard let index = sender.representedObject as? Int else { return }
		let point = window?.frame.origin ?? .zero
		onTearOff?(index, NSPoint(x: point.x - 60, y: point.y + (window?.frame.height ?? 0) - 80))
	}

	@objc private func closeFromMenu(_ sender: NSMenuItem) {
		guard let index = sender.representedObject as? Int else { return }
		onClose?(index)
	}

	override func mouseDragged(with event: NSEvent) {
		guard let index = pressedIndex, index < frames.count else { return }
		let point = convert(event.locationInWindow, from: nil)
		guard hypot(point.x - pressOrigin.x, point.y - pressOrigin.y) > 6 else { return }
		guard canDrag?(index) ?? false else { return }

		pressedIndex = nil
		beginDrag(index: index, event: event)
	}

	private func beginDrag(index: Int, event: NSEvent) {
		guard let item = TerminalTabDrag.item(panelID: panelID, column: column, index: index)
		else { return }

		let dragItem = NSDraggingItem(pasteboardWriter: item)
		dragItem.setDraggingFrame(frames[index], contents: snapshot(of: index))

		draggedIndex = index
		onDragStarted?()
		let session = beginDraggingSession(with: [dragItem], event: event, source: self)
		// A terminal let go outside the window becomes a window, so sliding it
		// back to where it started would contradict what happens next.
		session.animatesToStartingPositionsOnCancelOrFail = false
	}

	private func snapshot(of index: Int) -> NSImage? {
		guard index < frames.count, index < items.count else { return nil }
		let rect = frames[index]
		guard rect.width > 1, rect.height > 1 else { return nil }

		let image = NSImage(size: rect.size)
		image.lockFocus()
		if let context = NSGraphicsContext.current {
			context.cgContext.translateBy(x: -rect.minX, y: 0)
			draw(item: items[index], in: rect, isActive: true, isHovered: false)
		}
		image.unlockFocus()
		return image
	}

	/// Where a dropped tab would land, as an index between tabs.
	func insertionIndex(at point: NSPoint) -> Int {
		for (index, frame) in frames.enumerated() where point.x < frame.midX {
			return index
		}
		return frames.count
	}

	override func draw(_ dirtyRect: NSRect) {
		// tmux's strip is green from end to end, not a green tab here and
		// there on the app's own background: the bar across the foot of the
		// screen is the thing everybody recognises. Dimmed, though — the shape
		// is what is recognised, and full green over that width was the
		// loudest thing in the window.
		(isMirroringTmux ? Self.tmuxGreenBar : Theme.current.sidebarBackground).setFill()
		bounds.fill()
		if !isMirroringTmux {
			Theme.current.separator.setFill()
			NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
		}

		// Where a dragged tab would go, drawn where the gap will be.
		if let caret = dropCaret {
			let x = caret < frames.count
				? frames[caret].minX - Theme.current.scaled(1)
				: (frames.last?.maxX ?? Theme.current.scaled(8)) + Theme.current.scaled(1)
			Theme.current.gitModified.setFill()
			NSRect(
				x: x - 1, y: Theme.current.scaled(4),
				width: 2, height: bounds.height - Theme.current.scaled(8)
			).fill()
		}

		// **A hidden tab has no rectangle, and must not be drawn into it.** An
		// empty frame is `.zero`, whose origin is the top-left corner of the
		// strip — so every tab scrolled out of the run painted its icon there,
		// stacked behind the first visible one. That is the clutter reported at
		// the start of the strip.
		for (index, item) in items.enumerated()
		where index < frames.count && !frames[index].isEmpty {
			draw(item: item, in: frames[index], isActive: index == activeIndex, isHovered: index == hoveredIndex)
		}

		if showsAddButton {
			drawGlyph(in: addButtonFrame, symbol: "plus", tint: isMirroringTmux ? Self.onTmuxGreen : nil)
		}
		if offersAddMenu {
			// Smaller and dimmer than the +, the way the chevron beside the
			// ladybird is: it is part of that button, not another one.
			drawGlyph(
				in: addMenuFrame, symbol: "chevron.down", points: 9, tint: Theme.current.gitIgnored
			)
		}
		// **Opaque, because tabs are allowed to run underneath.** The frames are
		// laid out left to right at whatever width each name needs and nothing
		// stops them reaching the trailing edge, while these controls are placed
		// backwards from it — so with a dozen terminals open the session tag and
		// the three buttons were drawn over tab names with both still legible
		// through each other. The editor's tab bar settled this for itself
		// (`drawPreviewControl`) and the answer is the same one: a tab's last few
		// characters matter less than the controls staying readable and
		// reachable.
		if showsPanelControls { drawControlsBackground() }
		// Under the control the pointer is on, and under the pill and the tag
		// rather than over them: both draw grounds of their own, and a tint on
		// top would change what their colours mean.
		drawTrailingHover()
		// After the ground and before the panel's own controls, on every strip.
		// Its own room is already reserved by `tabRoom`, so no tab reaches it
		// and it needs no ground of its own.
		drawOverflowButton()
		guard showsPanelControls else { return }
		drawTrailingPanelControls()
	}

	/// A soft ground under whichever trailing control the pointer is on.
	///
	/// The tabs have had this since they were drawn; the controls beside them
	/// never did, so half the strip answered the pointer and half sat there
	/// looking like a picture. Same shape as a tab's own hover — a rounded
	/// rect in the faintest ink the theme has — because they are the same
	/// gesture on the same strip.
	private func drawTrailingHover() {
		guard let hoveredControl else { return }
		// **Twice as much for the two that have grounds of their own.** The
		// pill and the tag are drawn on a tint already, so the faint band that
		// reads clearly behind a bare glyph disappeared behind them entirely —
		// checked against the pixels rather than assumed, after a chevron that
		// was computed and never drawn earlier the same day. `HoverGround`
		// keeps both weights, and the shape the rest of the chrome now draws.
		// The + and its chevron overlap by a few points so they read as one
		// control, and the +'s hover ground drawn over its whole frame covered
		// the chevron's left half. Each is lit to where the other begins.
		var ground = frame(of: hoveredControl)
		if offersAddMenu {
			switch hoveredControl {
			case .add: ground.size.width = max(0, addMenuFrame.minX - ground.minX)
			case .addMenu:
				let start = addButtonFrame.maxX
				ground = NSRect(x: start, y: ground.minY, width: max(0, ground.maxX - start), height: ground.height)
			default: break
			}
		}
		HoverGround.draw(
			around: ground,
			ink: isMirroringTmux ? Self.onTmuxGreen : Theme.current.sidebarText,
			overTint: hoveredControl == .sessions || hoveredControl == .mirrorTag
		)
	}

	/// The hide, maximise, follow and tag controls: the panel's own, and only
	/// where there is a panel. Split out so that the overflow chevron above
	/// them is drawn on every strip — it was inside this guard, so tmux's
	/// windows and a torn-off terminal's tabs were counted, hidden and
	/// clickable with nothing drawn to say so.
	private func drawTrailingPanelControls() {
		drawGlyph(in: hideButtonFrame, symbol: "chevron.down")
		drawGlyph(
			in: maximizeButtonFrame,
			symbol: isMaximized
				? "arrow.down.right.and.arrow.up.left"
				: "arrow.up.left.and.arrow.down.right"
		)
		// Filled while it is on, so it is obvious at a glance that the window is
		// no longer staying where it was put.
		drawGlyph(
			in: followButtonFrame,
			symbol: isFollowingProject ? "link.circle.fill" : "link.circle",
			tint: isFollowingProject ? Theme.current.gitAdded : nil
		)

		drawMirrorTag()
		drawSessionsPill()
	}

	/// What the strip is showing and what it is holding back.
	///
	/// The entries are the menu's own titles, built the same way, so a driven
	/// run asserts on what somebody would read rather than on a picture of it.
	var overflowReportForTesting: String {
		let shown = visibleRun.count
		guard !hiddenTabs.isEmpty else { return "\(items.count) tabs, all \(shown) shown" }
		let entries = hiddenTabs.compactMap { index in
			items[safe: index].map { overflowTitle(for: $0, at: index) }
		}
		return "\(items.count) tabs, \(shown) shown, \(hiddenTabs.count) hidden: "
			+ entries.joined(separator: " | ")
	}

	/// Chooses a hidden tab the way its menu entry would, so what happens next
	/// — the run moving to show it — can be looked at.
	func selectHiddenForTesting(_ position: Int) -> String {
		guard hiddenTabs.indices.contains(position) else { return "no hidden tab \(position)" }
		let index = hiddenTabs[position]
		onSelect?(index)
		return "chose tab \(index)"
	}

	/// Chooses a hidden tab and makes it the active one, which on a mirroring
	/// strip is two halves: the click asks tmux, and the strip only learns the
	/// answer when the mirror re-reads the window list and hands the items back
	/// with a new active index. A seeded strip has no tmux to ask, so the
	/// second half is done here — otherwise the run has no reason to move and
	/// the instrument would report a fault that is its own.
	func selectHiddenAndActivateForTesting(_ position: Int) -> String {
		guard hiddenTabs.indices.contains(position) else { return "no hidden tab \(position)" }
		let index = hiddenTabs[position]
		let said = selectHiddenForTesting(position)
		setItems(items, activeIndex: index)
		return said
	}

	/// The tabs there was no room for, offered as a menu.
	///
	/// Only the hidden ones. A list of everything is a tab switcher, which is a
	/// different feature with a different gesture — and it would put the tab
	/// somebody is already looking at into a menu of things they cannot see.
	private func showOverflowMenu() {
		guard !hiddenTabs.isEmpty else { return }
		let menu = NSMenu()
		for index in hiddenTabs {
			guard let item = items[safe: index] else { continue }
			let entry = NSMenuItem(
				title: overflowTitle(for: item, at: index),
				action: #selector(selectFromOverflow(_:)),
				keyEquivalent: ""
			)
			entry.target = self
			entry.representedObject = index
			entry.state = index == activeIndex ? .on : .off
			menu.addItem(entry)
		}
		menu.popUp(
			positioning: nil,
			at: NSPoint(x: overflowButtonFrame.minX, y: bounds.maxY),
			in: self
		)
	}

	/// What a hidden tab is called in the menu.
	///
	/// **Not just its name**, and this is the part of the change that answers
	/// the report rather than the fault: sixteen terminals are sixteen tabs
	/// called `Local`, and a menu of sixteen identical lines is no more use than
	/// no menu. tmux's own number where there is one, and the position otherwise
	/// — which is what `C-b 2` selects and what somebody counting along the
	/// strip already has.
	private func overflowTitle(for item: PanelTabItem, at index: Int) -> String {
		let number = item.tmuxIndex ?? index + 1
		return "\(number)  \(item.title)"
	}

	@objc private func selectFromOverflow(_ sender: NSMenuItem) {
		guard let index = sender.representedObject as? Int else { return }
		onSelect?(index)
	}

	/// The chevron that offers the tabs there was no room for, with how many.
	///
	/// **The count is not decoration.** Three hidden and eleven hidden are
	/// different situations, and the number is the only thing that says which
	/// without opening the menu — it is also what makes this discoverable at
	/// all, since a bare chevron beside four other glyphs is one more glyph.
	private func drawOverflowButton() {
		guard overflowButtonFrame.width > 0 else { return }

		let colour = isMirroringTmux ? Self.onTmuxGreen : Theme.current.sidebarHeaderText
		let count = NSAttributedString(string: String(hiddenTabs.count), attributes: [
			.font: Theme.current.uiFont(10, weight: .medium),
			.foregroundColor: colour,
		])
		let size = count.size()
		let chevron = Theme.current.scaled(9)
		let content = size.width + Theme.current.scaled(3) + chevron
		let left = overflowButtonFrame.midX - content / 2

		count.draw(at: NSPoint(x: left, y: overflowButtonFrame.midY - size.height / 2))
		drawGlyph(
			in: NSRect(
				x: left + size.width + Theme.current.scaled(3),
				y: 0,
				width: chevron,
				height: overflowButtonFrame.height
			),
			symbol: "chevron.down",
			points: 9,
			tint: colour
		)
	}

	/// The ground the trailing controls are drawn on.
	///
	/// One rectangle covering the tag and all three buttons, from a little way
	/// in front of the leftmost of them to the edge — the strip's own colour, so
	/// a tab that has run this far simply stops being drawn there rather than
	/// showing through. Faded in over its first few points, or the tab it cuts
	/// off ends against a hard vertical edge that reads as a tab of its own.
	private func drawControlsBackground() {
		let leftmost = [sessionsPillFrame, mirrorTagFrame, followButtonFrame, maximizeButtonFrame, hideButtonFrame]
			.filter { $0.width > 0 }
			.map(\.minX)
			.min()
		guard let leftmost else { return }

		let colour = isMirroringTmux ? Self.tmuxGreenBar : Theme.current.sidebarBackground
		let fade = Theme.current.scaled(16)
		// One point short of the bar's bottom: the hairline is drawn before
		// this backdrop, and a full-height fill painted it out — the line
		// under the strip stopped dead where the controls begin, with a
		// sixteen-point fade-out in front of them. The mirroring strip draws
		// no hairline, so there the fill keeps the whole height.
		let height = bounds.height - (isMirroringTmux ? 0 : 1)
		let solid = NSRect(
			x: leftmost - Theme.current.scaled(6),
			y: 0,
			width: bounds.maxX - leftmost + Theme.current.scaled(6),
			height: height
		)
		colour.setFill()
		solid.fill()

		let gradient = NSGradient(
			starting: colour.withAlphaComponent(0),
			ending: colour
		)
		gradient?.draw(
			in: NSRect(x: solid.minX - fade, y: 0, width: fade, height: height),
			angle: 0
		)
	}

	/// Room for the chevron and the gap in front of it.
	var mirrorChevronWidth: CGFloat { Theme.current.scaled(11) }

	private func drawMirrorTag() {
		guard let session = mirroredSession, mirrorTagFrame.width > 0 else { return }

		let pill = NSBezierPath(
			roundedRect: mirrorTagFrame,
			xRadius: mirrorTagFrame.height / 2,
			yRadius: mirrorTagFrame.height / 2
		)
		Theme.current.gitModified.withAlphaComponent(0.14).setFill()
		pill.fill()

		// The text and the chevron are laid out together, so the pair sits in
		// the middle of the pill rather than the text alone.
		let label = mirrorTagText(for: session)
		let size = label.size()
		let content = size.width + mirrorChevronWidth
		let left = mirrorTagFrame.midX - content / 2

		label.draw(at: NSPoint(x: left, y: mirrorTagFrame.midY - size.height / 2))

		// Drawn rather than typed: a `⌄` is a character with a baseline of its
		// own and sits low beside anything else.
		let centre = NSPoint(
			x: left + size.width + mirrorChevronWidth / 2,
			y: mirrorTagFrame.midY + Theme.current.scaled(0.5)
		)
		let arm = Theme.current.scaled(2.6)
		let chevron = NSBezierPath()
		chevron.move(to: NSPoint(x: centre.x - arm, y: centre.y - arm / 2))
		chevron.line(to: NSPoint(x: centre.x, y: centre.y + arm / 2))
		chevron.line(to: NSPoint(x: centre.x + arm, y: centre.y - arm / 2))
		chevron.lineWidth = Theme.current.scaled(1.2)
		chevron.lineCapStyle = .round
		chevron.lineJoinStyle = .round
		Theme.current.gitModified.setStroke()
		chevron.stroke()
	}

	private func drawSessionsPill() {
		guard let counts = runningCounts, sessionsPillFrame.width > 0 else { return }
		SessionsPill.draw(counts, in: sessionsPillFrame, showsDigits: sessionsPillShowsDigits)
	}

	private func draw(item: PanelTabItem, in rect: NSRect, isActive: Bool, isHovered: Bool) {
		drawEditorStyle(item: item, in: rect, isActive: isActive, isHovered: isHovered)
	}

	/// Drawn the way an editor tab is drawn.
	///
	/// The same shape, the same icon-then-name, the same accent under the one
	/// in front: a terminal is a tab like any other and there is no reason for
	/// the panel to have a style of its own.
	private func drawEditorStyle(
		item: PanelTabItem,
		in rect: NSRect,
		isActive: Bool,
		isHovered: Bool
	) {
		if isMirroringTmux, !isActive, isHovered {
			// The strip is already green; hovering only lifts the one under the
			// pointer out of it.
			Self.onTmuxGreen.withAlphaComponent(0.10).setFill()
			rect.fill()
		}

		if isActive {
			// On tmux's strip the active tab is a hole cut in the green, and
			// what shows through it has to be the terminal that is sitting
			// directly above — the editor's background is a different dark, and
			// the step between the two read as a gap under the green line.
			(isMirroringTmux ? TerminalPalette.background : Theme.current.editorBackground).setFill()
			rect.fill()
			// In colour only when the keyboard is down here: the editor's strip
			// marks its own tab the same way, and two coloured lines at once say
			// the cursor is in both places.
			TabSelectionLine.color(
				focused: hasKeyboardFocus,
				accent: isMirroringTmux ? Self.tmuxGreen : nil
			).setFill()
			// On tmux's strip the line goes along the top, since the strip is
			// under what it belongs to rather than over it.
			TabSelectionLine.rect(in: rect, alongTop: isMirroringTmux).fill()
		} else if item.isShowing {
			// The other half of a split: on screen, but not the one the
			// keyboard is in.
			NSColor.white.withAlphaComponent(0.06).setFill()
			rect.fill()
		} else if isHovered {
			NSColor.white.withAlphaComponent(0.05).setFill()
			rect.fill()
		}

		// A run in progress: the tab wears the titlebar's green so the two say
		// the same thing, and the one in the corner of the eye is the tab.
		// After the backgrounds, or the active tab's own fill covers it.
		if item.isRunning {
			Self.runningGreen.withAlphaComponent(isActive ? 0.38 : 0.24).setFill()
			rect.fill()
		}

		if !isActive {
			// On tmux's strip the divider is green and full height, the way
			// tmux separates the entries in its own window list.
			if isMirroringTmux {
				Self.onTmuxGreen.withAlphaComponent(0.18).setFill()
				NSRect(x: rect.maxX - 1, y: 0, width: 1, height: rect.height).fill()
			} else {
				Theme.current.separator.withAlphaComponent(0.6).setFill()
				NSRect(
					x: rect.maxX - 1, y: Theme.current.scaled(6),
					width: 1, height: rect.height - Theme.current.scaled(12)
				).fill()
			}
		}

		var x = rect.minX + padding
		let iconSize = Theme.current.scaled(14)
		let tint = item.hasExited
			? Theme.current.gitIgnored
			: Theme.current.sidebarText.withAlphaComponent(isActive ? 0.95 : 0.7)

		if let number = item.tmuxIndex {
			// tmux's number: the label somebody already uses for this window
			// when they type `C-b 2`. Green on dark for the window you are in,
			// dark on green for the rest — which is tmux's own status bar,
			// the other way up.
			let text = NSAttributedString(string: "\(number)", attributes: [
				.font: Theme.current.uiFont(11, weight: .semibold),
				.foregroundColor: isActive ? Self.tmuxGreen : Self.onTmuxGreen,
			])
			let size = text.size()
			text.draw(at: NSPoint(
				x: x + (iconSize - size.width) / 2, y: rect.midY - size.height / 2
			))
		} else {
			let symbolColour: NSColor
			if item.isTmuxAttached {
				symbolColour = Self.tmuxGreen
			} else if item.isRunning {
				symbolColour = Theme.current.gitAdded
			} else {
				symbolColour = tint
			}
			Theme.symbol(
				item.symbol,
				size: 11 * Theme.current.scale,
				color: symbolColour
			)?.drawFitted(in: NSRect(
				x: x, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize
			))
		}
		x += iconSize + Theme.current.scaled(6)

		let color: NSColor
		if isMirroringTmux, !isActive {
			color = Self.onTmuxGreen
		} else if item.hasExited {
			color = Theme.current.gitIgnored
		} else {
			color = isActive
				? Theme.current.sidebarHeaderText
				: Theme.current.sidebarText.withAlphaComponent(0.8)
		}
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let label = NSAttributedString(string: item.title, attributes: [
			.font: font,
			.foregroundColor: color,
			.paragraphStyle: paragraph,
		])
		let size = label.size()
		let badge = isMirroringTmux || item.aiStatus != nil
			? statusSize + Theme.current.scaled(5)
			: 0
		let reserved = (item.isClosable ? closeSize + Theme.current.scaled(6) : 0) + badge
		let limit = max(0, rect.maxX - padding - reserved - x)
		label.draw(in: NSRect(x: x, y: rect.midY - size.height / 2, width: limit, height: size.height))

		// The Claude session's state, where the ✕ would be — a tmux tab has
		// none, and the two never appear together.
		if let status = item.aiStatus {
			let badge = badgeRect(in: rect)
			let onGreen = isMirroringTmux && !isActive
			if status == .working {
				drawSpinner(in: badge, colour: onGreen ? Self.onTmuxGreen : nil)
			} else {
				// On a green tab the badge is drawn in the ink the rest of the
				// tab uses: amber on green is a smudge, and the mark itself —
				// ⟳, !, ✓ — already says which of the three it is.
				Theme.symbol(
					Self.symbol(for: status),
					size: 11 * Theme.current.scale,
					color: onGreen ? Self.onTmuxGreen : Self.colour(for: status),
					weight: .semibold
				)?.drawFitted(in: badge)
			}
		}

		if item.isClosable, isActive || isHovered {
			// `isHovered` is this tab being the hovered one and `hoveredClose` is
			// the pointer being on a cross, so the two together name this cross
			// without the drawing needing to know its own index.
			TabCloseButton.draw(
				in: closeRect(for: rect),
				hovered: isHovered && hoveredClose,
				inset: Theme.current.scaled(3),
				lineWidth: 1.2
			)
		}
	}

	/// An arc chasing its own tail, a twelfth of a turn at a time.
	///
	/// Drawn rather than an `NSProgressIndicator`: the strip is one view that
	/// draws all its tabs, and a control per tab would have to be created,
	/// placed and torn down every time tmux's window list changes — which is
	/// twice a second.
	private func drawSpinner(in rect: NSRect, colour: NSColor? = nil) {
		Spinner.draw(in: rect, phase: spinnerPhase, colour: colour ?? Self.colour(for: .working))
	}

	/// cmanager's three states, in this app's alphabet.
	///
	/// The same meanings it writes on tmux's own status line — working, needs
	/// you, finished — drawn as symbols rather than as `…` `⚠` `✓`, so they sit
	/// on the baseline of a tab beside an icon rather than wherever a glyph's
	/// own metrics put them.
	///
	/// Bare marks, not the ringed or filled ones: at the size a tab badge can
	/// be, a `.circle.fill` symbol is a dot and nothing else, and telling
	/// "needs you" from "finished" would come down to colour alone.
	static func symbol(for status: TmuxMirror.AIStatus) -> String {
		switch status {
		case .working:    return "ellipsis"
		case .needsInput: return "exclamationmark"
		case .done:       return "checkmark"
		}
	}

	/// Amber for the one that wants something: it is the only one worth
	/// crossing the room for, and the other two should not compete with it.
	static func colour(for status: TmuxMirror.AIStatus) -> NSColor {
		switch status {
		case .working:    return Theme.current.sidebarText.withAlphaComponent(0.55)
		case .needsInput: return .hex(0xD6A05E)
		case .done:       return Theme.current.gitAdded
		}
	}

	private func drawPillStyle(item: PanelTabItem, in rect: NSRect, isActive: Bool, isHovered: Bool) {
		// Beside the focused one when the pane is split: both are on screen,
		// and a strip that marks only one of them makes the other look like it
		// belongs to some other tab.
		if item.isShowing, !isActive {
			let path = NSBezierPath(
				roundedRect: rect.insetBy(dx: 0, dy: Theme.current.scaled(4)),
				xRadius: Theme.current.scaled(5),
				yRadius: Theme.current.scaled(5)
			)
			NSColor.white.withAlphaComponent(0.05).setFill()
			path.fill()
		}

		if isActive {
			let path = NSBezierPath(
				roundedRect: rect.insetBy(dx: 0, dy: Theme.current.scaled(4)),
				xRadius: Theme.current.scaled(5),
				yRadius: Theme.current.scaled(5)
			)
			NSColor.white.withAlphaComponent(0.10).setFill()
			path.fill()
		} else if isHovered {
			let path = NSBezierPath(
				roundedRect: rect.insetBy(dx: 0, dy: Theme.current.scaled(4)),
				xRadius: Theme.current.scaled(5),
				yRadius: Theme.current.scaled(5)
			)
			NSColor.white.withAlphaComponent(0.05).setFill()
			path.fill()
		}

		// An exited session is dimmed rather than removed, so output stays
		// readable after the process finishes.
		let color = item.hasExited
			? Theme.current.gitIgnored
			: (isActive ? Theme.current.sidebarHeaderText : Theme.current.sidebarText)

		let label = NSAttributedString(string: item.title, attributes: [
			.font: font,
			.foregroundColor: color,
		])
		let size = label.size()
		label.draw(at: NSPoint(x: rect.minX + padding, y: rect.midY - size.height / 2))

		if isActive || isHovered {
			TabCloseButton.draw(
				in: closeRect(for: rect),
				hovered: isHovered && hoveredClose,
				inset: Theme.current.scaled(3),
				lineWidth: 1.2
			)
		}
	}

	/// - Parameter points: how big the glyph is, before the theme's scale. The
	///   default is what every control on this strip is; the + 's chevron is
	///   smaller, because it is part of that button rather than another one.
	private func drawGlyph(
		in rect: NSRect, symbol: String, points: CGFloat = 12, tint: NSColor? = nil
	) {
		guard let image = Theme.symbol(
			symbol,
			size: (points - 1) * Theme.current.scale,
			color: tint ?? Theme.current.sidebarText
		) else {
			return
		}
		let size = Theme.current.scaled(points)
		image.drawFitted(in: NSRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size))
	}
}
