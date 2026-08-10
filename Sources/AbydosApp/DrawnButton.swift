import AppKit

/// A small button in the app's own type, drawn rather than bezelled.
///
/// The reason it is not an `NSButton` with `.accessoryBarAction`, which is what
/// the missing-server strip used to hold: a system bezel takes its size from
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
/// somebody reads as meaning — that a bezel was carrying. It is the same answer
/// the titlebar's `PillButton` gives, for the same reason.
///
/// Shared by the strip above a file and by the toasts in the corner, because the
/// answers to a question in a toast are the same kind of thing as the ways out
/// of the strip, and two copies of a control would come to disagree about the
/// zoom the first time either was touched.
final class DrawnButton: NSButton {
	/// An SF Symbol instead of words, when the button is a glyph.
	private let symbol: String?

	init(title: String, action: @escaping () -> Void) {
		symbol = nil
		super.init(frame: .zero)
		self.title = title
		setUp(action)
	}

	init(symbol: String, description: String, action: @escaping () -> Void) {
		self.symbol = symbol
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
				symbol, size: 9 * Theme.current.scale, color: Theme.current.sidebarText
			)
		} else {
			attributedTitle = NSAttributedString(string: title, attributes: [
				.font: Theme.current.uiFont(11),
				.foregroundColor: Theme.current.sidebarHeaderText,
			])
		}
		layer?.cornerRadius = Theme.current.scaled(5)
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		layer?.borderWidth = 1
		layer?.borderColor = Theme.current.separator.cgColor
		invalidateIntrinsicContentSize()
	}

	/// A field around whatever is in it, at whatever size that is.
	///
	/// 19 points at 1×, which is where the system bezel was to within a point,
	/// so nothing visibly moves at the zoom almost everybody is at; 38 inside a
	/// 52-point strip at 2×, which is what the bezel could not do.
	override var intrinsicContentSize: NSSize {
		NSSize(
			width: symbol == nil
				? super.intrinsicContentSize.width + Theme.current.scaled(14)
				: Theme.current.scaled(20),
			height: Theme.current.scaled(19)
		)
	}
}
