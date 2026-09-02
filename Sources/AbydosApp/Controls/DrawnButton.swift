import AppKit
import CoreText
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
	/// The tag drawn after the words, made in `applyTheme` for `draw`.
	private var badge: NSImage?

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
			// **The words and the tag are drawn by `draw`, not by the cell.**
			// The cell was handed the tag as a text attachment and centred
			// the pair by its own measure, which put the tag a space and a
			// half from the word and closer to the edge than the word was to
			// its side — reported as the content not being centred. Drawing
			// them here makes the gap a number and the centring arithmetic.
			attributedTitle = NSAttributedString(string: title, attributes: [
				.font: font, .foregroundColor: colour,
			])
			badge = (count != nil && !isWorking) ? Self.tag(count!, colour: colour, size: fontSize) : nil
			showSpinner(isWorking, colour: colour)
			needsDisplay = true
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

	/// The number as a pill, sized to the words it sits beside.
	private static func tag(_ count: Int, colour: NSColor, size: CGFloat) -> NSImage {
		let scale = Theme.current.scale
		let number = NSAttributedString(string: "\(count)", attributes: [
			.font: Theme.current.uiFont(size - 1, weight: .semibold),
			.foregroundColor: colour,
		])
		let font = Theme.current.uiFont(size - 1, weight: .semibold)
		let text = number.size()
		// **Sized and placed by the capitals, not the line.** Digits have no
		// descenders, and a line box has room for one under them: centring
		// the box put the digits high in the pill, and a pill as tall as the
		// box stood a point over the word's capitals and a point under its
		// baseline. The pill is the digits plus an even margin, and the
		// baseline is set so the digits' middle is the pill's.
		let margin = 3 * scale
		let pill = NSSize(width: ceil(text.width) + 8 * scale, height: ceil(font.capHeight + margin * 2))
		return NSImage(size: pill, flipped: false) { rect in
			colour.withAlphaComponent(0.14).setFill()
			NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
			drawLine(number, baselineAt: NSPoint(
				x: ((rect.width - text.width) / 2).rounded(),
				y: ((rect.height - font.capHeight) / 2).rounded()
			), flipped: false)
			return true
		}
	}

	/// Draws text with its baseline exactly where it is asked to.
	///
	/// `NSAttributedString.draw(at:)` places a line box and puts the baseline
	/// where the typesetter rounds it, which came out a point above where the
	/// font's descender said it would be — enough for a tag centred on the
	/// arithmetic to sit visibly high. Core Text takes the baseline as given.
	///
	/// `flipped` says which way up the context is. A button is a flipped view,
	/// and Core Text draws glyphs through the context's transform as it finds
	/// it: on one machine the text matrix arrived already turned over and the
	/// words came out upright, on another it arrived as the identity and every
	/// word on the commit row drew mirrored. Set here, not assumed.
	private static func drawLine(
		_ text: NSAttributedString, baselineAt origin: NSPoint, flipped: Bool
	) {
		guard let context = NSGraphicsContext.current?.cgContext else { return }
		context.saveGState()
		context.textMatrix = flipped ? CGAffineTransform(scaleX: 1, y: -1) : .identity
		context.textPosition = origin
		CTLineDraw(CTLineCreateWithAttributedString(text), context)
		context.restoreGState()
	}

	/// Between the words and the tag, and between the words and the spinner.
	private var gap: CGFloat { (5 * Theme.current.scale).rounded() }

	/// What the words, the tag and the spinner's room add up to across.
	private var contentWidth: CGFloat {
		var width = ceil(attributedTitle.size().width)
		if let badge { width += gap + badge.size.width }
		if isWorking { width += gap + spinnerSide }
		return width
	}

	override func draw(_ dirtyRect: NSRect) {
		// A glyph is the cell's to draw; the words and the tag are this
		// view's, centred as one group.
		guard symbol == nil else { super.draw(dirtyRect); return }
		let words = attributedTitle
		let text = words.size()
		var x = ((bounds.width - contentWidth) / 2).rounded()
		// **The capitals centred, not the line box.** The box has the
		// descender under it, so centring it puts a word with no descenders
		// high; the baseline is set so the capitals' middle is the pill's,
		// and the tag is centred on the same line.
		let font = Theme.current.uiFont(fontSize)
		let baseline = ((bounds.height - font.capHeight) / 2).rounded()
		// Core Text takes the baseline in the context's own coordinates, and
		// a button is a flipped view: from the top, where `draw(in:)` below
		// is told which way up it is.
		Self.drawLine(
			words, baselineAt: NSPoint(x: x, y: isFlipped ? bounds.height - baseline : baseline),
			flipped: isFlipped
		)
		x += ceil(text.width)
		if let badge {
			let middle = baseline + font.capHeight / 2
			x += gap
			badge.draw(in: NSRect(
				x: x, y: (middle - badge.size.height / 2).rounded(),
				width: badge.size.width, height: badge.size.height
			))
		}
	}

	/// The spinner's side, at the current zoom.
	private var spinnerSide: CGFloat { (12 * Theme.current.scale).rounded() }

	/// Puts the spinner up or takes it down. `draw` leaves its room at the
	/// trailing end of the content, and `layout()` puts the view there.
	private func showSpinner(_ showing: Bool, colour: NSColor) {
		guard showing else {
			spinner?.stopAnimation(nil)
			spinner?.removeFromSuperview()
			spinner = nil
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
		needsLayout = true
	}

	override func layout() {
		super.layout()
		guard let spinner else { return }
		let side = spinnerSide
		spinner.frame = NSRect(
			x: ((bounds.width - contentWidth) / 2).rounded() + contentWidth - side,
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
		return NSSize(
			width: ControlMetrics.width(textWidth: contentWidth, scale: scale),
			height: ControlMetrics.height(lineHeight: ceil(line.height), scale: scale)
		)
	}
}
