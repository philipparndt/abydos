import AppKit
import AbydosKit

/// The spinner on a tab whose session is working, and the drawing the strip
/// does around it.
extension PanelTabStrip {
	// MARK: - The spinner on a working tab

	/// Turning while at least one session is working, and stopped otherwise.
	///
	/// A still `⋯` says "something is happening here" no more convincingly than
	/// a full stop does; a turning one says it at a glance from across the
	/// room. The timer exists only while there is something to turn, so an
	/// idle app is an idle app.
	func syncSpinner() {
		let wanted = items.contains { $0.aiStatus == .working }
		if wanted, spinnerTimer == nil {
			spinnerTimer = Timer.scheduledTimer(withTimeInterval: Spinner.interval, repeats: true) { [weak self] _ in
				guard let self else { return }
				self.spinnerPhase += 1
				// Only the badges: redrawing a whole strip twelve times a
				// second to turn three little marks would be silly.
				for (index, item) in self.items.enumerated()
				where item.aiStatus == .working && index < self.frames.count {
					self.setNeedsDisplay(self.badgeRect(in: self.frames[index]))
				}
			}
			// Turning has to carry on while a menu is open or a divider is
			// being dragged, which is exactly what the tracking mode is for.
			RunLoop.main.add(spinnerTimer!, forMode: .common)
		} else if !wanted {
			spinnerTimer?.invalidate()
			spinnerTimer = nil
		}
	}

	/// Where a tab's ✕ goes.
	///
	/// A method rather than a local inside `mouseDown`, which is where it used
	/// to be: the click knew where the cross was and nothing else did, so the
	/// pointer could not tell it was over one and the strip drew no hover.
	/// Three callers now — the click, the hover and the drawing — and one
	/// answer between them.
	func closeRect(for tabRect: NSRect) -> NSRect {
		NSRect(
			x: tabRect.maxX - padding - closeSize,
			y: tabRect.midY - closeSize / 2,
			width: closeSize,
			height: closeSize
		)
	}

	/// Where a tab's status badge goes: where the ✕ would be, which a tmux tab
	/// does not have.
	func badgeRect(in rect: NSRect) -> NSRect {
		NSRect(
			x: rect.maxX - padding - statusSize,
			y: rect.midY - statusSize / 2,
			width: statusSize,
			height: statusSize
		)
	}

	func applyThemeChange() {
		recomputeLayout()
		needsDisplay = true
	}

	var font: NSFont { Theme.current.uiFont(11.5) }
	var closeSize: CGFloat { Theme.current.scaled(12) }
	/// The Claude badge, the size of the ✕ it sits where.
	var statusSize: CGFloat { Theme.current.scaled(12) }
	var padding: CGFloat { Theme.current.scaled(10) }

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		recomputeLayout()
	}

	func recomputeLayout() {
		frames.removeAll()

		// **The trailing controls are placed before the tabs now, not after.**
		// They used to be laid out from `bounds.width` backwards once the tabs
		// had already been given every point they asked for, which is how the
		// two came to be drawn through each other. What they leave is what the
		// tabs get, and a tab that does not fit in it is one the overflow
		// chevron offers rather than one nobody can reach.
		layoutTrailingControls()

		let widths = items.map(width(for:))
		let gap = isMirroringTmux ? 0 : Theme.current.scaled(2)

		// Measured twice, deliberately. Whether the chevron is there at all
		// depends on whether anything is hidden, and the chevron itself takes
		// room that can hide one more — so the first pass asks without it and
		// the second asks again with its width taken off. It cannot oscillate:
		// reserving room can only ever hide more, never fewer.
		let plain = TabOverflow.measure(
			widths: widths, start: runStart, available: tabRoom(overflowing: false), spacing: gap
		)
		let overflow = plain.isOverflowing
			? TabOverflow.measure(
				widths: widths, start: runStart, available: tabRoom(overflowing: true), spacing: gap
			)
			: plain
		visibleRun = overflow.visible
		hiddenTabs = overflow.hidden
		overflowButtonFrame = overflow.isOverflowing
			? NSRect(
				x: trailingControlsLeadingEdge - overflowButtonWidth,
				y: 0,
				width: overflowButtonWidth,
				height: bounds.height
			)
			: .zero

		// Hard against the left, as tmux's strip already was — there for a
		// reason of its own, since the active tab is a hole cut in the green
		// and green down its outer edge frames that one tab. The rest of the
		// panel starts at the edge too: the terminal below has no margin, and a
		// strip that begins eight points in sits on nothing.
		var x: CGFloat = 0
		for index in items.indices {
			// **A hidden tab keeps its place in `frames` and gets no rectangle.**
			// Everything that finds a tab — the click, the hover, the drop
			// caret, the rename field — asks `frames` by index, so shortening it
			// would renumber every tab after the first hidden one. An empty rect
			// contains no point, so those all say "not this one" without being
			// told about the run.
			guard visibleRun.contains(index) else {
				frames.append(.zero)
				continue
			}
			let width = widths[index]
			frames.append(NSRect(x: x, y: 0, width: width, height: bounds.height))
			// Tabs meet on tmux's strip. Anywhere else the gap between them is
			// the panel's background and reads as a gap; there it is the green
			// bar, and a sliver of it down the side of the tab you are in looks
			// like a frame around it.
			x += width + gap
		}
		addButtonFrame = showsAddButton
			? NSRect(x: x + Theme.current.scaled(4), y: 0, width: Theme.current.scaled(24), height: bounds.height)
			: .zero
		// Hard against the +, the width of the debug button's chevron, so the two
		// read as one control rather than as two buttons.
		addMenuFrame = offersAddMenu
			? NSRect(
				x: addButtonFrame.maxX - Theme.current.scaled(4),
				y: 0,
				width: Theme.current.scaled(14),
				height: bounds.height
			)
			: .zero

		refreshToolTipsIfMoved()
	}

	/// Re-registers the tooltip rects, but only when something has moved.
	///
	/// **Not on every layout.** This strip re-lays out whenever tmux's windows
	/// are re-read, which is twice a second while a session is watched, and
	/// tearing a tooltip down while somebody is reading it is how a tip that
	/// flickers is made. Not never, either: the pill widens as its counts pass
	/// nine, the tag drops the session's name on a narrow strip, and a rect
	/// left where a control used to be is a tip that answers over empty space.
	private func refreshToolTipsIfMoved() {
		let shape = [
			sessionsPillFrame, mirrorTagFrame, followButtonFrame, maximizeButtonFrame,
			hideButtonFrame, overflowButtonFrame, addButtonFrame, addMenuFrame,
		] + frames
		guard shape != toolTipShape else { return }
		toolTipShape = shape
		refreshEngineTips()
	}

	/// What one tab wants to be, which is the same question wherever it is asked.
	func width(for item: PanelTabItem) -> CGFloat {
		// The editor's own measurement: room for the icon, the name, and
		// the cross, and never so narrow that a name is all ellipsis.
		let text = (item.title as NSString).size(withAttributes: [.font: font]).width
		// Room for the badge whether or not there is one to draw, on the
		// strip where badges come and go: a tab that widens the moment its
		// session starts working shoves every tab after it sideways, and
		// the one somebody was aiming at moves out from under the pointer.
		let badge = isMirroringTmux || item.aiStatus != nil
			? statusSize + Theme.current.scaled(5)
			: 0
		return ceil(max(
			Theme.current.scaled(96),
			padding * 2 + Theme.current.scaled(14) + Theme.current.scaled(6)
				+ ceil(text) + Theme.current.scaled(8) + closeSize + badge
		))
	}

	/// How much room the tabs have: everything up to the controls, less the +
	/// that follows them and the chevron that offers what does not fit.
	func tabRoom(overflowing: Bool) -> CGFloat {
		var room = trailingControlsLeadingEdge
		if showsAddButton { room -= Theme.current.scaled(28) }
		if offersAddMenu { room -= Theme.current.scaled(14) }
		if overflowing { room -= overflowButtonWidth }
		return max(0, room)
	}

	/// Where the panel's own controls begin, which is where the tabs must stop.
	private var trailingControlsLeadingEdge: CGFloat {
		let leading = [sessionsPillFrame, mirrorTagFrame, followButtonFrame, maximizeButtonFrame, hideButtonFrame]
			.filter { $0.width > 0 }
			.map(\.minX)
			.min()
		return (leading ?? bounds.width) - Theme.current.scaled(8)
	}

	/// Wide enough for a chevron and a count of two digits.
	private var overflowButtonWidth: CGFloat { Theme.current.scaled(34) }

	private func layoutTrailingControls() {
		guard showsPanelControls else {
			hideButtonFrame = .zero
			maximizeButtonFrame = .zero
			followButtonFrame = .zero
			mirrorTagFrame = .zero
			sessionsPillFrame = .zero
			return
		}

		hideButtonFrame = NSRect(
			x: bounds.width - Theme.current.scaled(30),
			y: 0,
			width: Theme.current.scaled(24),
			height: bounds.height
		)
		// Beside the one that puts it away, since they are the same kind of
		// thing: how much room the panel gets.
		maximizeButtonFrame = NSRect(
			x: hideButtonFrame.minX - Theme.current.scaled(26),
			y: 0,
			width: Theme.current.scaled(24),
			height: bounds.height
		)
		followButtonFrame = NSRect(
			x: maximizeButtonFrame.minX - Theme.current.scaled(26),
			y: 0,
			width: Theme.current.scaled(24),
			height: bounds.height
		)

		let height = Theme.current.scaled(16)
		if let session = mirroredSession {
			let label = mirrorTagText(for: session)
			let width = label.size().width + Theme.current.scaled(12) + mirrorChevronWidth
			mirrorTagFrame = NSRect(
				x: followButtonFrame.minX - Theme.current.scaled(8) - width,
				y: (bounds.height - height) / 2,
				width: width,
				height: height
			)
		} else {
			mirrorTagFrame = .zero
		}

		// The pill is the leftmost control, so it is the first thing the tabs
		// meet — and when there is nothing running it is not there at all, and
		// the tabs have what it would have taken.
		guard let counts = runningCounts else {
			sessionsPillFrame = .zero
			return
		}
		let anchor = mirrorTagFrame.width > 0 ? mirrorTagFrame.minX : followButtonFrame.minX
		let width = SessionsPill.width(for: counts, showsDigits: sessionsPillShowsDigits)
		sessionsPillFrame = NSRect(
			x: anchor - Theme.current.scaled(8) - width,
			y: (bounds.height - height) / 2,
			width: width,
			height: height
		)
	}

	var sessionsPillShowsDigits: Bool { SessionsPill.showsDigits(inStripOfWidth: bounds.width) }

	/// `tmux · session`, or just `tmux` when the name would crowd the strip.
	func mirrorTagText(for session: String) -> NSAttributedString {
		let text = bounds.width > Theme.current.scaled(420) ? "tmux · \(session)" : "tmux"
		return NSAttributedString(string: text, attributes: [
			.font: Theme.current.uiFont(10, weight: .medium),
			.foregroundColor: Theme.current.gitModified,
		])
	}
}
