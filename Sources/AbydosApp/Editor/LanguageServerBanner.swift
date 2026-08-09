import AppKit
import AbydosKit

/// The strip above the editor saying that this file could have a language
/// server, and does not.
///
/// The gap it fills: an editor with no server for the language in front of you
/// behaves exactly like one whose server is broken. Nothing is underlined,
/// nothing completes, go-to-declaration finds nothing — and the only place that
/// ever said why was the empty state of a palette somebody had to think to
/// open. This says it where the file is, once it is opened, in a sentence with
/// the command in it.
///
/// A strip rather than a dialog, for the reason the find bar is one: it never
/// covers the code, it can be read at a glance and ignored, and it costs a
/// click to be rid of rather than a click to continue. Three ways out, which is
/// the point — "not now" (✕), "not for this language, ever" (Ignore), and the
/// one that solves it (How to install).
final class LanguageServerBanner: NSView {
	/// Read the manual: what to install, where it has to end up, how to check.
	var onDetails: (() -> Void)?
	/// Never for this language again.
	var onIgnore: (() -> Void)?
	/// Not now. Comes back for the next file of this language.
	var onDismiss: (() -> Void)?

	private var label: NSTextField!
	private var ignoreButton: BannerButton!
	private var detailsButton: BannerButton!
	private var closeButton: BannerButton!
	private var icon: NSImageView!
	private var iconWidth: NSLayoutConstraint!
	private var stack: NSStackView!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		build()
		applyTheme()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	/// A hairline under it, so the strip reads as chrome above the file rather
	/// than as the file's first line.
	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.editorBackground.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
	}

	private func build() {
		icon = NSImageView()
		icon.translatesAutoresizingMaskIntoConstraints = false
		iconWidth = icon.widthAnchor.constraint(equalToConstant: 0)
		iconWidth.isActive = true

		label = NSTextField(labelWithString: "")
		label.textColor = Theme.current.sidebarHeaderText
		label.lineBreakMode = .byTruncatingTail

		detailsButton = BannerButton(title: "How to install") { [weak self] in self?.onDetails?() }
		ignoreButton = BannerButton(title: "Ignore") { [weak self] in self?.onIgnore?() }
		closeButton = BannerButton(symbol: "xmark", description: "Dismiss") { [weak self] in
			self?.onDismiss?()
		}
		closeButton.toolTip = "Not now"

		stack = NSStackView(views: [icon, label, detailsButton, ignoreButton, closeButton])
		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		// The sentence gives way first: on a narrow window the buttons are what
		// the strip is for.
		label.setContentHuggingPriority(.defaultLow, for: .horizontal)
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	// MARK: - Contents

	private(set) var notice: LanguageService.ServerNotice?

	/// What is being said, and which of the three ways out apply to it.
	///
	/// Not every notice has all three. A server that is on its way has nothing
	/// to install and nothing worth switching off for ever — the wait ends by
	/// itself — so it gets the sentence and the ✕ and no more. Offering "How to
	/// install" beside a server that is already being fetched would be an offer
	/// to solve something that is solving itself.
	func show(_ notice: LanguageService.ServerNotice) {
		self.notice = notice
		// The command is in the sentence: it is the searchable part, the thing
		// somebody types, and the name they will recognise if they already know
		// the language's tooling.
		label.stringValue = notice.text
		label.toolTip = notice.manual
		detailsButton.isHidden = notice.manual == nil
		ignoreButton.isHidden = !notice.isIgnorable
		ignoreButton.setLabel("Ignore for \(notice.languageName)")
		ignoreButton.toolTip = "Never offer a \(notice.languageName) server again"
		// A lightbulb is an idea somebody could act on; a wait is not one. The
		// two states of this strip look different from across the room, which is
		// the distance most of them are read from.
		symbolName = notice.manual == nil ? "hourglass" : "lightbulb"
		applyTheme()
	}

	/// Which glyph the sentence is wearing, so `applyTheme` can put it back at a
	/// new zoom without being told again what the strip is saying.
	private var symbolName = "lightbulb"

	func applyTheme() {
		label?.font = Theme.current.uiFont(11.5)
		label?.textColor = Theme.current.sidebarHeaderText

		// Drawn at the zoom rather than tinted at whatever size AppKit picked:
		// an `NSImageView` scales an image down to fit and never up, so a symbol
		// asked for by name alone stayed the size it was made at while the strip
		// around it doubled.
		icon?.image = Theme.symbol(
			symbolName, size: 11 * Theme.current.scale, color: Theme.current.gitModified
		)
		iconWidth?.constant = Theme.current.scaled(14)

		stack?.spacing = Theme.current.scaled(6)
		stack?.edgeInsets = NSEdgeInsets(
			top: 0, left: Theme.current.scaled(10), bottom: 0, right: Theme.current.scaled(10)
		)
		for button in [detailsButton, ignoreButton, closeButton] { button?.applyTheme() }
		needsDisplay = true
	}

	/// How tall the strip is when it is showing.
	static var height: CGFloat { Theme.current.scaled(26) }

	// MARK: - Testing

	var textForTesting: String { label.stringValue }
	func pressIgnoreForTesting() { onIgnore?() }
	func pressDetailsForTesting() { onDetails?() }
	func pressDismissForTesting() { onDismiss?() }

	/// The sizes the strip actually gave itself, so a zoom can be measured
	/// rather than squinted at.
	var sizesForTesting: String {
		"scale=\(Theme.current.scale)"
			+ " strip=\(Int(bounds.height))"
			+ " button=\(Int(detailsButton.frame.height))"
			+ " text=\(Int(Theme.current.uiFont(11).pointSize))"
	}
}

/// A button in the strip, drawn rather than bezelled.
///
/// The reason it is not an `NSButton` with `.accessoryBarAction` any more, which
/// is what it was: a system bezel takes its size from `controlSize`, never from
/// the font put inside it. Measured on macOS 27, that button is **20 points tall
/// at `.small` and 28 at `.large`** whether its text is 11 points or 22 — and
/// `.large` is the largest artwork AppKit has. The strip is `scaled(26)`, so at
/// 2× it is 52 points tall with 22-point words crammed into a 20-point pill,
/// which is the fault reported: the bar grows, the buttons do not, and picking a
/// bigger `controlSize` only moves the wall from 1× to about 1.4×.
///
/// Drawing it costs almost nothing here and there is nothing to lose by it:
/// these are words and one glyph, with no system affordance — no chevron, no
/// focus ring somebody reads as meaning — that a bezel was carrying. It is the
/// same answer the titlebar's `PillButton` gives, for the same reason, and it
/// makes the strip one drawn thing rather than the app's colours with the
/// system's buttons standing in them.
private final class BannerButton: NSButton {
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
