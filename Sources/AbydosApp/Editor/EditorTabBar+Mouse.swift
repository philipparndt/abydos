import AppKit
import AbydosKit

/// The pointer over the tabs: hovering, pressing, dragging one out, and the
/// menu behind a right-click.
extension EditorTabBar {
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

	func updateHover(at point: NSPoint) {
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

	func clearHover() {
		hoveredIndex = nil
		hoveredClose = false
		isPreviewHovered = false
		isMaximizeHovered = false
		needsDisplay = true
	}


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
		menu.addItem(.separator())
		add("Open as Hex", #selector(openAsHexFromMenu(_:)))
		add("Blame", #selector(blameFromMenu(_:)))
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

	@objc private func openAsHexFromMenu(_ sender: NSMenuItem) {
		if let index = index(of: sender) { onOpenAsHex?(index) }
	}

	@objc private func blameFromMenu(_ sender: NSMenuItem) {
		if let index = index(of: sender) { onBlame?(index) }
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
}
