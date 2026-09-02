import AppKit
import AbydosKit

/// A button in the app's own type, drawn rather than bezelled.
///
/// The reason it is not an `NSButton` with a bezel, which is what the
/// missing-server strip used to hold: a system bezel takes its size from
/// `controlSize`, never from the font put inside it. Measured on macOS 27, that
/// button is **20 points tall at `.small` and 28 at `.large`** whether its text
/// is 11 points or 22 — and `.large` is the largest artwork AppKit has. The
/// strip is `scaled(26)`, so at 2× it was 52 points tall with 22-point words
/// crammed into a 20-point pill, which is the fault that was reported: the bar
/// grows, the buttons do not, and picking a bigger `controlSize` only moves the
/// wall from 1× to about 1.4×.
///
/// Drawing it costs almost nothing and there is nothing to lose by it: these are
/// words and one glyph, with no system affordance — no chevron, no focus ring
/// somebody reads as meaning — that a bezel was carrying.
///
/// **This is the library's button**, and it is the fourth writing of one answer
/// rather than a new one. `PillButton` in the titlebar and `RowAction` in the
/// git tree draw themselves for the same reason and work for the same reason:
/// every dimension is read from `Theme.current` *where it is used*, so the next
/// repaint re-reads it and there is nothing stored to go stale. What is new here
/// is only that the answer is shared, and that `ScaledControls` sees the button
/// is asked again when the zoom moves under it.
final class DrawnButton: NSButton, ScaleFollowing {
	/// How much the button asks to be looked at.
	///
	/// The commit page has a blue `Push 1` beside a grey `Commit`, and that
	/// difference is meaning rather than decoration — one of them is what
	/// happens if you press ⏎. A bezel gave it for free through
	/// `keyEquivalent`; a drawn button has to be told.
	enum Prominence {
		/// The ordinary one: the app's surface, a hairline around it.
		case normal
		/// The one the ⏎ key would press.
		case prominent
		/// No edge and no fill: words or a glyph that sit on the surface.
		///
		/// For a control that helps with something rather than doing it — the
		/// commit page's chevron, its history clock and its Draft. Drawn with
		/// the same pill as Commit beside them, the row had five bordered
		/// objects on it and two of them mattered; a border is how the row
		/// says *this one changes the repository*, so the helpers give it up.
		case quiet
	}

	/// An SF Symbol instead of words, when the button is a glyph.
	///
	/// A `var` because a glyph can be the button's state: the commit page's
	/// chevron points right while the description is shut and down while it is
	/// open, and the same button carries both.
	private var symbol: String?

	/// The design-time size of the words. 11 is the strip's and the toasts';
	/// a pane's buttons sit beside 12-point rows and ask for 12.
	private let fontSize: CGFloat

	/// A number drawn as a tag after the words — `Push` with a `7` in a pill
	/// beside it rather than `Push 7`, so the word stays put as the number
	/// moves and the number reads as a count rather than as part of a verb.
	private var count: Int?

	/// Drawn as busy: a spinner at the trailing end, in the tag's place.
	///
	/// For a verb that takes a while and cannot say so — a push is a network
	/// round trip, and a button that only went grey looked like one that had
	/// refused. The words are the caller's ("Pushing"); the motion is this.
	var isWorking = false {
		didSet { applyTheme() }
	}
	private var spinner: NSProgressIndicator?

	var prominence: Prominence = .normal {
		didSet { applyTheme() }
	}

	/// Whether the pointer is over the button, for a quiet one to answer.
	///
	/// A normal button is a pill and a pill is an invitation; a quiet one is
	/// words on the surface, and words on a surface do not say they can be
	/// pressed. Under the pointer it takes the pill back — the same fill and
	/// hairline as its normal neighbours — so the answer to "is this a
	/// button?" arrives before the click rather than after it.
	private var isHovered = false {
		didSet { if prominence == .quiet { applyTheme() } }
	}
	private var trackingArea: NSTrackingArea?

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseEntered(with event: NSEvent) { isHovered = true }
	override func mouseExited(with event: NSEvent) { isHovered = false }

	/// A quiet button drawn as a normal one while the pointer is on it.
	private var isQuietAtRest: Bool { prominence == .quiet && !(isHovered && isEnabled) }

	/// Drawn as held down, for a button that is a switch rather than a verb.
	///
	/// `Check Out` on the review page is one: it says whether the branch is
	/// checked out and stays pressed while it is. A bezel gave that through
	/// `.pushOnPushOff`; a drawn button is told.
	var isLit: Bool = false {
		didSet { applyTheme() }
	}

	init(title: String, fontSize: CGFloat = 11, action: @escaping () -> Void) {
		symbol = nil
		self.fontSize = fontSize
		super.init(frame: .zero)
		self.title = title
		setUp(action)
	}

	init(symbol: String, description: String, action: @escaping () -> Void) {
		self.symbol = symbol
		fontSize = 11
		super.init(frame: .zero)
		imagePosition = .imageOnly
		setAccessibilityLabel(description)
		setUp(action)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func setUp(_ action: @escaping () -> Void) {
		isBordered = false
		wantsLayer = true
		setButtonType(.momentaryChange)
		onAction = action
		applyTheme()
		// In its own initialiser and not left to the caller: a control that has
		// to be registered by whoever makes it is a control somebody will make
		// without registering, which is the fault this library exists for.
		ScaledControls.register(self)
	}

	/// A new glyph, in the app's own colour and at the app's own size.
	///
	/// Setting `image` directly would work and would be wrong: the image would
	/// be the system's at the system's size, so the one button whose glyph
	/// changes would stop following the zoom while its neighbours carried on.
	func setSymbol(_ name: String, description: String) {
		symbol = name
		setAccessibilityLabel(description)
		applyTheme()
	}

	/// New words, in the app's own type.
	///
	/// Setting `title` on its own puts the cell's default font back — which is
	/// the system's, at the system's size — so the one button whose words are
	/// not known until a language is: "Ignore for JSON" came out in a different
	/// face from "How to install" beside it.
	func setLabel(_ text: String, count: Int? = nil) {
		title = text
		self.count = count
		applyTheme()
	}

	/// Re-reads the zoom and the palette. Without it a button built at 1× keeps
	/// a 1× pill around type that has already grown, which is the bug one layer
	/// down from the one this class fixes.
	func applyTheme() {
		if let symbol {
			image = Theme.symbol(
				symbol, size: 9 * Theme.current.scale,
				color: isEnabled ? textColour : textColour.withAlphaComponent(0.45)
			)
		} else {
			let font = Theme.current.uiFont(fontSize)
			let colour = isEnabled ? textColour : textColour.withAlphaComponent(0.45)
			let words = NSMutableAttributedString(string: title, attributes: [
				.font: font, .foregroundColor: colour,
			])
			if let count, !isWorking {
				words.append(NSAttributedString(string: " ", attributes: [.font: font]))
				words.append(Self.tag(count, after: font, colour: colour, size: fontSize))
			}
			attributedTitle = words
			showSpinner(isWorking, colour: colour)
		}
		layer?.cornerRadius = ControlMetrics.radius(scale: Theme.current.scale)
		// **Disabled has to reach the shape, not only the words.** Dimming the
		// title alone left a full-strength pill with faint text in it, which
		// reads as a button whose label happens to be light — reported as the
		// dimming not working. A bezel greyed the whole control and that is
		// what a drawn one has to do too.
		let dim: (NSColor) -> NSColor = { colour in
			self.isEnabled ? colour : colour.withAlphaComponent(colour.alphaComponent * 0.4)
		}
		layer?.backgroundColor = dim(fillColour).cgColor
		layer?.borderWidth = prominence == .normal || (prominence == .quiet && !isQuietAtRest) ? 1 : 0
		layer?.borderColor = dim(Theme.current.separator).cgColor
		invalidateIntrinsicContentSize()
	}

	/// Kept in step with the words: a disabled button that still draws its
	/// label at full strength is a button people press.
	override var isEnabled: Bool {
		didSet { applyTheme() }
	}

	private var textColour: NSColor {
		switch prominence {
		case .normal, .quiet: return Theme.current.sidebarHeaderText
		case .prominent: return Theme.current.editorBackground
		}
	}

	private var fillColour: NSColor {
		if isLit { return Theme.current.selection(.row, hasKeyboard: true) }
		switch prominence {
		case .normal: return Theme.current.editorBackground
		case .prominent: return Theme.current.caret
		case .quiet: return isQuietAtRest ? .clear : Theme.current.editorBackground
		}
	}

	/// The number as a pill, sized to the words it sits beside and centred
	/// on their middle rather than their baseline.
	private static func tag(
		_ count: Int, after font: NSFont, colour: NSColor, size: CGFloat
	) -> NSAttributedString {
		let scale = Theme.current.scale
		let number = NSAttributedString(string: "\(count)", attributes: [
			.font: Theme.current.uiFont(size - 1, weight: .semibold),
			.foregroundColor: colour,
		])
		let text = number.size()
		let pill = NSSize(width: ceil(text.width) + 8 * scale, height: ceil(text.height) + 1 * scale)
		let image = NSImage(size: pill, flipped: false) { rect in
			colour.withAlphaComponent(0.14).setFill()
			NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
			number.draw(at: NSPoint(
				x: ((rect.width - text.width) / 2).rounded(),
				y: ((rect.height - text.height) / 2).rounded()
			))
			return true
		}
		let attachment = NSTextAttachment()
		attachment.image = image
		let middle = (font.ascender + font.descender) / 2
		attachment.bounds = NSRect(
			x: 0, y: (middle - pill.height / 2).rounded(), width: pill.width, height: pill.height
		)
		return NSAttributedString(attachment: attachment)
	}

	/// The spinner's side, at the current zoom.
	private var spinnerSide: CGFloat { (12 * Theme.current.scale).rounded() }

	/// Puts the spinner up or takes it down. The cell is given an empty image
	/// of the spinner's size at the trailing end, so the words move over to
	/// make room the way they would for a glyph; the spinner itself is a view
	/// laid over that space in `layout()`.
	private func showSpinner(_ showing: Bool, colour: NSColor) {
		guard showing else {
			spinner?.stopAnimation(nil)
			spinner?.removeFromSuperview()
			spinner = nil
			image = nil
			imagePosition = .noImage
			return
		}
		if spinner == nil {
			let made = NSProgressIndicator()
			made.style = .spinning
			made.controlSize = .small
			made.isIndeterminate = true
			made.isDisplayedWhenStopped = false
			addSubview(made)
			made.startAnimation(nil)
			spinner = made
		}
		image = NSImage(size: NSSize(width: spinnerSide, height: spinnerSide))
		imagePosition = .imageTrailing
		needsLayout = true
	}

	override func layout() {
		super.layout()
		guard let spinner else { return }
		let side = spinnerSide
		spinner.frame = NSRect(
			x: bounds.width - ControlMetrics.horizontalPadding * Theme.current.scale - side,
			y: ((bounds.height - side) / 2).rounded(),
			width: side, height: side
		)
	}

	/// A field around whatever is in it, at whatever size that is.
	///
	/// **Derived, not chosen.** This used to answer `Theme.current.scaled(19)`
	/// — a constant that happened to match the system bezel at 1× and had
	/// nothing to do with the words inside it, so a button asked for a larger
	/// font came out the same height as one asked for a smaller. The height is
	/// what the line actually measures plus the padding, through the same
	/// arithmetic the tests check at all nine zoom steps.
	override var intrinsicContentSize: NSSize {
		let scale = Theme.current.scale
		guard symbol == nil else {
			let side = ControlMetrics.glyphSide(scale: scale)
			return NSSize(width: side, height: side)
		}
		let line = attributedTitle.size()
		// The spinner is not in the title, so its room is added here: the
		// side of it and the gap the cell leaves before a trailing image.
		let busy = isWorking ? spinnerSide + 4 * scale : 0
		return NSSize(
			width: ControlMetrics.width(textWidth: ceil(line.width) + busy, scale: scale),
			height: ControlMetrics.height(lineHeight: ceil(line.height), scale: scale)
		)
	}
}
