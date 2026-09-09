import AppKit
import AbydosKit

/// Drawing the strip: a tab, its close button, the line under the one in front,
/// and what is shown when there is no room for them all.
extension EditorTabBar {
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

		drawOverflowControl()
		drawPreviewControl()
		drawMaximizeControl()

		// Hairline under the whole strip, broken by the active tab so it reads as
		// continuous with the editor beneath it. After the trailing controls,
		// not before: their backdrops are opaque fills the full height of the
		// bar, and painted over the hairline they took it with them — the line
		// stopped dead under the overflow chevron, and under the other two at
		// the zoom steps where their backdrop's inset rounds onto the last row.
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
	func showOverflowMenu() {
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

	func draw(item: EditorTabItem, in rect: NSRect, isActive: Bool, index: Int) {
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
