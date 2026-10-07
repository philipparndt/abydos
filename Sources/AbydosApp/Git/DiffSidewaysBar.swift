import AppKit
import AbydosKit

/// The strip along the bottom of a diff: a horizontal scroller per text column
/// and, side by side, the link between them.
///
/// **In the scroll view, not in the diff.** The diff is the scroll view's
/// document view, so anything inside it scrolls up and down with the rows; a
/// sibling of the clip view stays at the bottom of what is visible. The diff puts
/// it there itself, so every host — the changes pane, the log and commit pages,
/// the stash, a pull request — has it without laying anything out.
///
/// **Always drawn while there is something to scroll.** In the overlay style a
/// scroller is invisible until it is used, and a reader who cannot see one has
/// no way to know the line goes on — which is the whole complaint this answers.
final class DiffSidewaysBar: NSView {
	private weak var diff: DiffView?
	private var scrollers: [DiffTextRun.Column: NSScroller] = [:]
	private let link = NSButton()

	init(diff: DiffView) {
		self.diff = diff
		super.init(frame: .zero)
		wantsLayer = true
		for column in [DiffTextRun.Column.only, .left, .right] {
			// **Born wide.** A scroller decides whether it is horizontal from the
			// frame it is made with, and one made at zero size drew itself as a
			// vertical stub at the end of its track whatever it was later given.
			let scroller = NSScroller(frame: NSRect(x: 0, y: 0, width: 200, height: 15))
			scroller.scrollerStyle = .legacy
			scroller.controlSize = .regular
			scroller.isEnabled = true
			scroller.target = self
			scroller.action = #selector(scrolled(_:))
			scroller.isHidden = true
			addSubview(scroller)
			scrollers[column] = scroller
		}
		link.isBordered = false
		link.bezelStyle = .accessoryBarAction
		link.imagePosition = .imageOnly
		link.target = self
		link.action = #selector(linkPressed)
		addSubview(link)
		// The link is a preference every diff shares; a bar that did not hear
		// another diff flip it would draw the wrong state until it was touched.
		NotificationCenter.default.addObserver(
			self, selector: #selector(settingsChanged), name: .abydosSettingsChanged, object: nil
		)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit { NotificationCenter.default.removeObserver(self) }

	private var thickness: CGFloat {
		NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
	}

	@objc private func settingsChanged() { update() }

	// MARK: - Layout

	/// Shows what can scroll, sizes the knobs to the columns, and sits along the
	/// bottom of the scroll view's visible area.
	func update() {
		guard let diff, let scroll = superview as? NSScrollView else { return }
		let wasHidden = isHidden
		let columns = diff.scrollingColumns
		let scrollable = columns.filter { diff.maxSidewaysOffset(of: $0) > 0 }
		isHidden = scrollable.isEmpty

		let clip = scroll.contentView.frame
		let height = thickness
		// Pinned to the bottom edge as the scroll view grows, so a taller window
		// does not leave the bar floating where the bottom used to be.
		autoresizingMask = scroll.isFlipped ? [.width, .minYMargin] : [.width, .maxYMargin]
		frame = NSRect(
			x: clip.minX,
			y: scroll.isFlipped ? clip.maxY - height : clip.minY,
			width: clip.width,
			height: height
		)

		let linkWidth = diff.isSideBySide ? height + Theme.current.scaled(6) : 0
		let middle = diff.pairMiddle
		for (column, scroller) in scrollers {
			guard scrollable.contains(column) else {
				scroller.isHidden = true
				continue
			}
			scroller.isHidden = false
			switch column {
			case .only:
				let minX = diff.textArea(of: .only).lowerBound
				scroller.frame = NSRect(x: minX, y: 0, width: bounds.width - minX, height: height)
			case .left:
				scroller.frame = NSRect(x: 0, y: 0, width: middle - linkWidth / 2, height: height)
			case .right:
				let minX = middle + linkWidth / 2
				scroller.frame = NSRect(x: minX, y: 0, width: bounds.width - minX, height: height)
			}
			let visible = diff.visibleTextWidth(of: column)
			let total = visible + diff.maxSidewaysOffset(of: column)
			scroller.knobProportion = total > 0 ? visible / total : 1
			let maximum = diff.maxSidewaysOffset(of: column)
			scroller.doubleValue = maximum > 0 ? Double(diff.sidewaysOffset(of: column) / maximum) : 0
		}

		link.isHidden = !diff.isSideBySide || scrollable.isEmpty
		link.frame = NSRect(x: middle - linkWidth / 2, y: 0, width: linkWidth, height: height)
		let linked = diff.halvesScrollTogether
		link.image = linked ? Self.linkedImage : Self.unlinkedImage
		link.contentTintColor = linked ? Theme.current.gitModified : Theme.current.gitIgnored
		link.toolTip = linked
			? "The halves scroll sideways together — click to scroll each on its own"
			: "Each half scrolls sideways on its own — click to link them"
		link.setAccessibilityLabel(linked ? "Halves linked" : "Halves not linked")

		if wasHidden != isHidden { diff.invalidateIntrinsicContentSize() }
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: isFlipped ? 0 : bounds.maxY - 1, width: bounds.width, height: 1).fill()
	}

	// MARK: - Gestures

	@objc private func scrolled(_ sender: NSScroller) {
		guard let diff, let column = scrollers.first(where: { $0.value === sender })?.key else { return }
		let maximum = diff.maxSidewaysOffset(of: column)
		let offset = diff.sidewaysOffset(of: column)
		let page = diff.visibleTextWidth(of: column) * 0.9
		switch sender.hitPart {
		case .decrementPage: diff.setSidewaysOffset(offset - page, of: column)
		case .incrementPage: diff.setSidewaysOffset(offset + page, of: column)
		case .decrementLine: diff.setSidewaysOffset(offset - diff.characterWidth * 4, of: column)
		case .incrementLine: diff.setSidewaysOffset(offset + diff.characterWidth * 4, of: column)
		default:             diff.setSidewaysOffset(CGFloat(sender.doubleValue) * maximum, of: column)
		}
	}

	@objc private func linkPressed() {
		guard let diff else { return }
		diff.setHalvesLinked(!diff.halvesScrollTogether)
	}

	// MARK: - Symbols

	/// SF Symbols has a link and no broken one — `link.slash` does not exist, and
	/// this was checked rather than assumed — so the unlinked state is the same
	/// link with a slash drawn through it, which reads as "not" the way every
	/// other slashed symbol does.
	private static let linkedImage: NSImage? = NSImage(
		systemSymbolName: "link", accessibilityDescription: "Linked"
	)

	private static let unlinkedImage: NSImage? = {
		guard let link = NSImage(systemSymbolName: "link", accessibilityDescription: "Not linked") else {
			return nil
		}
		let size = link.size
		let made = NSImage(size: size, flipped: false) { rect in
			link.draw(in: rect)
			let slash = NSBezierPath()
			slash.move(to: NSPoint(x: rect.minX + 1, y: rect.minY + 1))
			slash.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 1))
			slash.lineWidth = max(1.2, size.width / 10)
			NSColor.black.setStroke()
			slash.stroke()
			return true
		}
		made.isTemplate = true
		return made
	}()

	// MARK: - Driving

	var reportForTesting: String {
		guard !isHidden else { return "bar=hidden" }
		let shown = scrollers.filter { !$0.value.isHidden }.keys
			.map { $0 == .only ? "only" : ($0 == .left ? "left" : "right") }.sorted()
		return "bar=shown scrollers=\(shown.joined(separator: "+"))"
			+ " link=\(link.isHidden ? "hidden" : (diff?.halvesScrollTogether == true ? "linked" : "unlinked"))"
			+ " frame=\(Int(frame.minY)),\(Int(frame.height))"
			+ " scroll=\((superview as? NSScrollView).map { "\(Int($0.bounds.height)) flipped=\($0.isFlipped)" } ?? "-")"
			+ " index=\(superview?.subviews.firstIndex(of: self) ?? -1)/\(superview?.subviews.count ?? 0)"
			+ scrollers.filter { !$0.value.isHidden }.map { column, scroller in
				" \(column == .only ? "only" : (column == .left ? "left" : "right"))"
					+ "=\(String(format: "%.2f", scroller.doubleValue))"
					+ "@\(String(format: "%.2f", scroller.knobProportion))"
					+ " x\(Int(scroller.frame.minX))w\(Int(scroller.frame.width))"
			}.sorted().joined()
	}

	/// Presses the link as a click would.
	func pressLinkForTesting() { link.performClick(nil) }
}
