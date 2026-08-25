import AppKit

/// A titlebar control a menu can be anchored to, kept lit while that menu is up.
///
/// The pills and the capsule are drawn differently and share no code, but a
/// menu does not care which it was opened from — only that it can say when it
/// closed again.
protocol TitlebarMenuAnchor: AnyObject {
	var isMenuOpen: Bool { get set }
}

/// Base class for the titlebar pills: a rounded hit area that highlights on
/// hover and stays highlighted while its menu is open.
class PillButton: NSView, TitlebarMenuAnchor {
	var onClick: (() -> Void)?

	/// Kept lit while the popover is open so the pill reads as the menu's anchor.
	var isMenuOpen = false {
		didSet { needsDisplay = true }
	}

	private var isHovered = false {
		didSet { needsDisplay = true }
	}
	private var isPressed = false {
		didSet { needsDisplay = true }
	}

	private var trackingArea: NSTrackingArea?

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	// MARK: - Hover tracking

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseEnteredAndExited, .activeInActiveApp],
			owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseEntered(with event: NSEvent) { isHovered = true }
	override func mouseExited(with event: NSEvent) { isHovered = false }

	override func mouseDown(with event: NSEvent) {
		isPressed = true
	}

	override func mouseUp(with event: NSEvent) {
		isPressed = false
		// Only fire when released inside, matching standard button behaviour.
		if bounds.contains(convert(event.locationInWindow, from: nil)) {
			onClick?()
		}
	}

	// MARK: - Drawing

	/// How far the pill's own shape sits inside the space it is given.
	///
	/// The toolbar draws a rounded background of its own behind each item, and
	/// a highlight that runs to the very edge of it reads as two frames drawn
	/// on top of each other rather than as one pill being pointed at.
	static var inset: CGFloat { Theme.current.scaled(4) }

	override func draw(_ dirtyRect: NSRect) {
		let radius: CGFloat = 7
		let path = NSBezierPath(
			roundedRect: bounds.insetBy(dx: Self.inset, dy: Self.inset),
			xRadius: radius,
			yRadius: radius
		)

		// Darkening rather than lightening: the toolbar draws its items on a
		// pale background of its own, and white over white says nothing.
		if isMenuOpen || isPressed {
			NSColor.black.withAlphaComponent(0.16).setFill()
			path.fill()
			NSColor.black.withAlphaComponent(0.22).setStroke()
			path.lineWidth = 1
			path.stroke()
		} else if isHovered {
			NSColor.black.withAlphaComponent(0.08).setFill()
			path.fill()
		}

		drawContent(in: bounds)
	}

	/// Subclass hook for the pill's contents.
	func drawContent(in rect: NSRect) {}

	// MARK: - Shared drawing helpers

	static var labelFont: NSFont { Theme.current.uiFont(13, weight: .medium) }

	func drawChevron(at point: NSPoint, color: NSColor) {
		let path = NSBezierPath()
		path.move(to: NSPoint(x: point.x, y: point.y - 2))
		path.line(to: NSPoint(x: point.x + 3.5, y: point.y + 2))
		path.line(to: NSPoint(x: point.x + 7, y: point.y - 2))
		path.lineWidth = 1.3
		path.lineCapStyle = .round
		path.lineJoinStyle = .round
		color.setStroke()
		path.stroke()
	}
}

/// The part of the project being worked on.
///
/// Beside the project rather than instead of it: the project is what the tree
/// shows and what somebody came here for, and the subproject is which corner
/// of it the run button, git and the language server are pointed at. The cross
/// gives the whole project back.
final class SubprojectPillButton: PillButton {
	/// Asked to go back to the whole project.
	var onLeave: (() -> Void)?

	private var path: String?

	private static var iconSize: CGFloat { Theme.current.scaled(13) }
	private static var horizontalPadding: CGFloat { Theme.current.scaled(7) }
	private static var gap: CGFloat { Theme.current.scaled(6) }
	private static var crossSize: CGFloat { Theme.current.scaled(12) }

	var hasSubproject: Bool { path != nil }

	func setSubproject(_ path: String?) {
		self.path = path
		isHidden = (path == nil)
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	override var intrinsicContentSize: NSSize {
		// A toolbar measures a hidden view too, and warns about a zero
		// dimension: a sliver rather than nothing.
		guard let path else { return NSSize(width: 1, height: Theme.current.scaled(28)) }
		let textWidth = (path as NSString).size(withAttributes: [.font: PillButton.labelFont]).width
		return NSSize(
			width: PillButton.inset * 2 + Self.horizontalPadding * 2 + Self.iconSize
				+ Self.gap + ceil(textWidth) + Self.gap + Self.crossSize,
			height: Theme.current.scaled(30)
		)
	}

	/// Where the cross is, so a click there leaves rather than opens the menu.
	private var crossRect: NSRect {
		NSRect(
			x: bounds.maxX - PillButton.inset - Self.horizontalPadding - Self.crossSize,
			y: bounds.midY - Self.crossSize / 2,
			width: Self.crossSize,
			height: Self.crossSize
		)
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		guard !crossRect.insetBy(dx: -4, dy: -4).contains(point) else {
			onLeave?()
			return
		}
		super.mouseDown(with: event)
	}

	override func drawContent(in rect: NSRect) {
		guard let path else { return }
		var x = Self.horizontalPadding + PillButton.inset

		let tint = Theme.current.sidebarText
		if let icon = Theme.symbol(
			"square.split.bottomrightquarter", size: 11 * Theme.current.scale, color: tint
		) ?? Theme.symbol("square.on.square", size: 11 * Theme.current.scale, color: tint) {
			icon.drawFitted(in: NSRect(
				x: x, y: rect.midY - Self.iconSize / 2,
				width: Self.iconSize, height: Self.iconSize
			))
			x += Self.iconSize + Self.gap
		}

		let attributed = NSAttributedString(string: path, attributes: [
			.font: PillButton.labelFont,
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		let size = attributed.size()
		attributed.draw(at: NSPoint(x: x, y: rect.midY - size.height / 2))

		Theme.symbol("xmark", size: 8 * Theme.current.scale, color: tint.withAlphaComponent(0.75))?
			.drawFitted(in: crossRect.insetBy(dx: Theme.current.scaled(2), dy: Theme.current.scaled(2)))
	}
}

/// Which checkout of this repository the window is looking at.
///
/// **Not the capsule's chip made clickable, and 0490 is where that was weighed.**
/// The chip said which linked worktree the window was on and said *nothing at
/// all* on the primary — which is the whole of the report: `~/dev/abydos` showed
/// `abydos | main` and no way to reach any of the other checkouts. A control that
/// is invisible in the place it is most needed is not a control, and every chip
/// you could invent for the primary is worse than none: `abydos [abydos]` is the
/// name twice, `abydos [main]` puts the branch a divider away from the branch.
/// It would also have made a third hit target inside a capsule whose own comment
/// says it stays two.
///
/// So the chip is retired into this pill, and the doctrine it carried survives
/// untouched: **a worktree of ideai is still ideai**. The capsule goes on saying
/// the repository's name; this says which of its checkouts, in the place the
/// subproject pill qualifies which corner of it.
///
/// **It says only what the capsule beside it has not**, the way
/// `DevContainerPillButton` says only the mark and keeps the container's name
/// for its tool tip. On the primary that is nothing at all — the capsule has
/// just said `abydos`, and saying it again a few points to the right is noise.
/// On a worktree named after its branch it is *also* nothing, because the
/// capsule's right half is showing that branch a foot to the left; a pill
/// reading `backlog-0490-worktrees` beside a capsule reading
/// `backlog/0490-worktrees-chosen-from-the-titlebar` was a hundred and fifty
/// points spent on a word already on screen, and it was enough to push this pill
/// into the toolbar's overflow — leaving the one window that most needed the
/// control as the one window without it. `GitWorktrees.qualifier` is the rule.
///
/// What is left is a worktree somebody named themselves — `hotfix` on
/// `release/2.1` — where the directory is the only thing saying why that
/// checkout exists.
///
/// `house` and `folder` are the branches pane's own vocabulary for the primary
/// and a linked worktree, so a checkout marked one way in the sidebar is not
/// marked another way up here.
///
/// **Absent entirely for a repository with one checkout**, which is the rule the
/// branches pane keeps for its Worktrees section — *"a repository nobody has
/// added a worktree to should not carry a section explaining that it has one"*.
/// Nobody's titlebar gains furniture unless they use worktrees.
final class WorktreePillButton: PillButton {
	/// Which checkout, and whether it is the one the repository was cloned into.
	struct State: Equatable {
		/// The words to draw, or nil when the titlebar has already said them.
		let name: String?
		/// The directory this checkout really is, for the tool tip — which has
		/// room for it and is where somebody goes when the pill is wordless.
		let full: String
		let isPrimary: Bool
	}

	private var state: State?

	private static var iconSize: CGFloat { Theme.current.scaled(13) }
	private static var horizontalPadding: CGFloat { Theme.current.scaled(7) }
	private static var gap: CGFloat { Theme.current.scaled(6) }
	private static var chevronWidth: CGFloat { Theme.current.scaled(7) }

	var hasWorktrees: Bool { state != nil }

	/// Which checkout it stands for, which on the primary is not what it draws.
	var worktree: State? { state }

	/// - Parameters:
	///   - state: which checkout this is, or nil when there is only one and the
	///     pill has nothing to offer.
	///   - count: how many the repository has, for the tool tip. The menu is the
	///     only place the list itself belongs, but a pill that will open a list
	///     should say roughly how long it is before it is opened.
	func setWorktree(_ state: State?, count: Int = 0) {
		self.state = state
		isHidden = (state == nil)
		toolTip = state.map { current in
			let where_ = current.isPrimary
				? "Primary checkout — \(current.full)"
				: "Worktree \(current.full)"
			return count > 1 ? "\(where_)\n\(count) checkouts of this repository" : where_
		}
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	/// What is drawn beside the icon, which is often nothing.
	private var label: String? { state?.name }

	override var intrinsicContentSize: NSSize {
		// A toolbar measures a hidden view too, and warns about a zero dimension:
		// a sliver rather than nothing.
		guard state != nil else { return NSSize(width: 1, height: Theme.current.scaled(28)) }
		let textWidth = label.map {
			ceil(($0 as NSString).size(withAttributes: [.font: PillButton.labelFont]).width)
				+ Self.gap
		} ?? 0
		return NSSize(
			width: PillButton.inset * 2 + Self.horizontalPadding * 2 + Self.iconSize
				+ Self.gap + textWidth + Self.chevronWidth,
			height: Theme.current.scaled(30)
		)
	}

	override func drawContent(in rect: NSRect) {
		guard let state else { return }
		var x = Self.horizontalPadding + PillButton.inset

		let tint = Theme.current.sidebarText
		if let icon = Theme.symbol(
			state.isPrimary ? "house" : "folder",
			size: 11 * Theme.current.scale,
			color: tint
		) {
			icon.drawFitted(in: NSRect(
				x: x, y: rect.midY - Self.iconSize / 2,
				width: Self.iconSize, height: Self.iconSize
			))
			x += Self.iconSize + Self.gap
		}

		if let label {
			let attributed = NSAttributedString(string: label, attributes: [
				.font: PillButton.labelFont,
				.foregroundColor: Theme.current.sidebarHeaderText,
			])
			let size = attributed.size()
			attributed.draw(at: NSPoint(x: x, y: rect.midY - size.height / 2))
			x += ceil(size.width) + Self.gap
		}

		drawChevron(at: NSPoint(x: x, y: rect.midY), color: tint)
	}
}

/// The devcontainer this project is worked on inside, or the one it has and is
/// not using.
///
/// **Two states, and 0438's third fault is why there are two.** 0433 built this
/// to say *running*: a project whose container was declined had no pill at all,
/// which meant that the gesture most in need of undoing was the one that removed
/// its own undo — the way back lives in this menu. From the window it read as
/// gone for good, which is exactly how it was reported.
///
/// So a project that has a `devcontainer.json` and is not being worked on inside
/// it keeps its pill, dimmed, without the `⬢` the terminal tab wears. The
/// hexagon is the mark of being *in* the container and the pill must never wear
/// it while nothing of the project's is; the dimming is the whole of how loud
/// this is allowed to be, because somebody who chose to work on this machine
/// chose it and does not need reminding. What state is in force is in the tool
/// tip and at the top of the menu, for whoever goes looking.
///
/// A chevron rather than the subproject pill's cross, and the difference is on
/// purpose: the cross gives the whole project back and costs nothing, whereas
/// everything this pill offers changes which toolchain the code is checked
/// against. That is worth a menu somebody read rather than a small target
/// beside a name.
///
/// **It does not say the container's name, and 0444's part 3 is that decision
/// being reversed.** 0433 gave it `containerTabTitle` so that the pill, the tab
/// in the same container and the menu item that opens one could not drift apart,
/// and the naming argument was that "a window scoped to one subproject of ten
/// that each have a devcontainer cannot say which one it means by saying
/// 'container'". That argument is sound and it is about **the menu item that
/// opens one of several**, where the name is the only thing telling two entries
/// apart. It is much weaker here: this pill has exactly one answer at a time, the
/// window already says which project and which subproject it is showing, and a
/// devcontainer's `name` is a whole sentence — "Python, with its language server
/// in the container" beside a project, a branch and a subproject was most of the
/// titlebar, measured on the example project the whole feature was reported
/// against.
///
/// So what is left is the `⬢`: this window is working inside a container. The
/// name is in the tool tip, and in the menu, which lists every container the
/// project offers with the one in use marked — it has a home now, which is the
/// other half of why this is no longer a loss. The single source is untouched:
/// the name still comes from `MainWindowController.containerName`, and so does
/// the mark. What changed is what the pill shows, not where it learns it from.
final class DevContainerPillButton: PillButton {
	/// The very short thing it shows while the container is in use — the `⬢` the
	/// terminal tab wears — or nil when there is no container to show at all.
	private var mark: String?
	private var inUse = true
	/// Whether this project's language servers are answering yet.
	private var isLanguageReady = false

	private static var iconSize: CGFloat { Theme.current.scaled(13) }
	private static var horizontalPadding: CGFloat { Theme.current.scaled(7) }
	private static var gap: CGFloat { Theme.current.scaled(6) }
	private static var chevronWidth: CGFloat { Theme.current.scaled(7) }

	var hasContainer: Bool { mark != nil }
	/// Whether the container it stands for is the one this project's tools are in.
	var isInUse: Bool { inUse }

	/// Shows the pill for a container, or takes it away when given nil.
	///
	/// - Parameters:
	///   - mark: the two characters at most that it shows — the `⬢` the terminal
	///     tab wears, from `MainWindowController.containerMark`, so the pill and
	///     the tab in the same container cannot come to disagree about it.
	///   - inUse: whether this project's tools are in there. The mark is drawn
	///     only then: the hexagon means being *inside*, and a pill for a container
	///     that is merely available must not wear it (0438).
	func setContainer(_ mark: String?, inUse: Bool = true) {
		self.mark = mark
		self.inUse = inUse
		isHidden = (mark == nil)
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	/// Says whether this project's language servers are answering.
	///
	/// **Reported as a gap rather than a bug: nothing said when you could
	/// start.** A server in a container takes a minute or two — image, then
	/// handshake, then an index — and everything an editor does with one is
	/// quietly wrong before that: go-to-definition finds nothing and completion
	/// falls back to the words already in the file, both of which look like
	/// answers. The pill is where somebody is already looking to find out what
	/// their tools are doing.
	func setLanguageReady(_ ready: Bool) {
		guard ready != isLanguageReady else { return }
		isLanguageReady = ready
		needsDisplay = true
	}

	/// What is drawn beside the icon, which is the mark or nothing.
	private var label: String? { inUse ? mark : nil }

	override var intrinsicContentSize: NSSize {
		// A toolbar measures a hidden view too, and warns about a zero dimension:
		// a sliver rather than nothing.
		guard mark != nil else { return NSSize(width: 1, height: Theme.current.scaled(28)) }
		let textWidth = label.map {
			ceil(($0 as NSString).size(withAttributes: [.font: PillButton.labelFont]).width)
				+ Self.gap
		} ?? 0
		return NSSize(
			width: PillButton.inset * 2 + Self.horizontalPadding * 2 + Self.iconSize
				+ Self.gap + textWidth + Self.chevronWidth,
			height: Theme.current.scaled(30)
		)
	}

	override func drawContent(in rect: NSRect) {
		guard mark != nil else { return }
		var x = Self.horizontalPadding + PillButton.inset

		// Dimmed rather than coloured. A warning colour would be the app arguing
		// with a decision somebody made on purpose; the same grey the tree gives
		// an ignored file says "there, and not in play" without saying anything
		// about whether that was wise.
		let tint = inUse ? Theme.current.sidebarText : Theme.current.gitIgnored
		// **Green only when the servers are up, and only on the box.** The
		// theme's own added-file green rather than a colour of this file's
		// invention, so it means here what it means everywhere else in the
		// window: this is ready. The chevron stays neutral — it opens a menu,
		// which is as available before the servers are up as after.
		let boxTint = isLanguageReady && inUse ? Theme.current.gitAdded : tint
		if let icon = Theme.symbol("shippingbox", size: 11 * Theme.current.scale, color: boxTint) {
			icon.drawFitted(in: NSRect(
				x: x, y: rect.midY - Self.iconSize / 2,
				width: Self.iconSize, height: Self.iconSize
			))
			x += Self.iconSize + Self.gap
		}

		if let label {
			let attributed = NSAttributedString(string: label, attributes: [
				.font: PillButton.labelFont,
				.foregroundColor: Theme.current.sidebarHeaderText,
			])
			let size = attributed.size()
			attributed.draw(at: NSPoint(x: x, y: rect.midY - size.height / 2))
			x += ceil(size.width) + Self.gap
		}

		drawChevron(at: NSPoint(x: x, y: rect.midY), color: tint)
	}
}
