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
	}

	/// An SF Symbol instead of words, when the button is a glyph.
	private let symbol: String?

	/// The design-time size of the words. 11 is the strip's and the toasts';
	/// a pane's buttons sit beside 12-point rows and ask for 12.
	private let fontSize: CGFloat

	var prominence: Prominence = .normal {
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

	/// New words, in the app's own type.
	///
	/// Setting `title` on its own puts the cell's default font back — which is
	/// the system's, at the system's size — so the one button whose words are
	/// not known until a language is: "Ignore for JSON" came out in a different
	/// face from "How to install" beside it.
	func setLabel(_ text: String) {
		title = text
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
			attributedTitle = NSAttributedString(string: title, attributes: [
				.font: Theme.current.uiFont(fontSize),
				.foregroundColor: isEnabled ? textColour : textColour.withAlphaComponent(0.45),
			])
		}
		layer?.cornerRadius = ControlMetrics.radius(scale: Theme.current.scale)
		layer?.backgroundColor = fillColour.cgColor
		layer?.borderWidth = prominence == .prominent ? 0 : 1
		layer?.borderColor = Theme.current.separator.cgColor
		invalidateIntrinsicContentSize()
	}

	/// Kept in step with the words: a disabled button that still draws its
	/// label at full strength is a button people press.
	override var isEnabled: Bool {
		didSet { applyTheme() }
	}

	private var textColour: NSColor {
		switch prominence {
		case .normal: return Theme.current.sidebarHeaderText
		case .prominent: return Theme.current.editorBackground
		}
	}

	private var fillColour: NSColor {
		switch prominence {
		case .normal: return Theme.current.editorBackground
		case .prominent: return Theme.current.caret
		}
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
			width: ControlMetrics.width(textWidth: ceil(line.width), scale: scale),
			height: ControlMetrics.height(lineHeight: ceil(line.height), scale: scale)
		)
	}
}
