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
	/// Take the one thing offered — see `ServerNotice.Offer`. Nothing to install
	/// and nothing to ignore: a decision somebody made, taken back.
	var onOffer: (() -> Void)?

	private var label: NSTextField!
	private var offerButton: DrawnButton!
	private var ignoreButton: DrawnButton!
	private var detailsButton: DrawnButton!
	private var closeButton: DrawnButton!
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

		// The title is set again from every notice — see `ServerNotice.detailsTitle`
		// — and this is only what it says before there is one to read.
		detailsButton = DrawnButton(title: "How to install") { [weak self] in self?.onDetails?() }
		offerButton = DrawnButton(title: "") { [weak self] in self?.onOffer?() }
		ignoreButton = DrawnButton(title: "Ignore") { [weak self] in self?.onIgnore?() }
		closeButton = DrawnButton(symbol: "xmark", description: "Dismiss") { [weak self] in
			self?.onDismiss?()
		}
		closeButton.toolTip = "Not now"

		// The offer nearest the sentence it answers, because it is the one button
		// here that does the thing rather than explaining it.
		stack = NSStackView(views: [icon, label, offerButton, detailsButton, ignoreButton, closeButton])
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
		detailsButton.setLabel(notice.detailsTitle)
		offerButton.isHidden = notice.offer == nil
		if let offer = notice.offer { offerButton.setLabel(offer.title) }
		ignoreButton.isHidden = !notice.isIgnorable
		ignoreButton.setLabel("Ignore for \(notice.languageName)")
		ignoreButton.toolTip = "Never offer a \(notice.languageName) server again"
		// A lightbulb is an idea somebody could act on; a wait is not one. The
		// states of this strip look different from across the room, which is the
		// distance most of them are read from. An offer is an idea too — the
		// devcontainer somebody turned down, offered back — so it lights as
		// well. **A server that started and is not answering for this project is
		// none of those**: it is a report, and it wears the sign that means read
		// this rather than the one that means here is a thought. 0461.
		symbolName = notice.problem
			? "exclamationmark.triangle"
			: notice.manual == nil && notice.offer == nil ? "hourglass" : "lightbulb"
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
		for button in [offerButton, detailsButton, ignoreButton, closeButton] { button?.applyTheme() }
		needsDisplay = true
	}

	/// How tall the strip is when it is showing.
	static var height: CGFloat { Theme.current.scaled(26) }

	// MARK: - Testing

	var textForTesting: String { label.stringValue }
	/// What the strip is offering to do about it, if anything — the words on the
	/// button, which is what somebody reads before pressing it.
	var offerForTesting: String { offerButton.isHidden ? "" : offerButton.title }
	func pressIgnoreForTesting() { onIgnore?() }
	func pressDetailsForTesting() { onDetails?() }
	func pressDismissForTesting() { onDismiss?() }
	func pressOfferForTesting() { onOffer?() }

	/// The sizes the strip actually gave itself, so a zoom can be measured
	/// rather than squinted at.
	var sizesForTesting: String {
		"scale=\(Theme.current.scale)"
			+ " strip=\(Int(bounds.height))"
			+ " button=\(Int(detailsButton.frame.height))"
			+ " text=\(Int(Theme.current.uiFont(11).pointSize))"
	}
}
