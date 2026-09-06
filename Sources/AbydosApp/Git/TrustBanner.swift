import AppKit
import AbydosKit

/// The strip that says a project is not trusted, and the one gesture that
/// changes it.
///
/// **A strip and not a modal.** A window that cannot be looked at until a
/// security question is answered is a security question answered by reflex —
/// and the whole point of an untrusted project is that it is fully readable:
/// the tree, the editor, search, the git history and the diffs all work while
/// this is up. So it sits above the editor, says what is held back, and waits.
///
/// The shape is `LanguageServerBanner`'s, which is this app's answer to "a
/// sentence and a button, above the file": same ground, same hairline, same
/// drawn buttons, so a second strip does not read as a different kind of thing.
final class TrustBanner: NSView {
	/// The scopes this project can be trusted at, asked for when the button is
	/// pressed — the menu is the window's, and where it hangs is this strip's.
	var trustScopes: (() -> NSMenu)?
	/// Put the strip away without trusting anything.
	var onDismiss: (() -> Void)?

	private var label: NSTextField!
	private var trustButton: DrawnButton!
	private var detailsButton: DrawnButton!
	private var closeButton: DrawnButton!
	private var icon: NSImageView!

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		build()
		applyTheme()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

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
		icon.widthAnchor.constraint(equalToConstant: Theme.current.scaled(16)).isActive = true

		label = NSTextField(labelWithString: "")
		label.lineBreakMode = .byTruncatingTail

		// **A dropdown, because trusting is a choice of scope.** This project,
		// the folder of checkouts it sits in, or everywhere a clone says it
		// came from — one press, then the scope, rather than a sheet of
		// checkboxes to work through. The chevron is drawn into the title the
		// way the capsule's own menus draw theirs.
		trustButton = DrawnButton(title: "Trust This Project") { [weak self] in self?.popTrustMenu() }
		trustButton.prominence = .prominent
		// The chevron as a drawn glyph on the capitals' middle, not a `⌄` in
		// the title sitting on the baseline — which hung low, and was reported.
		trustButton.trailingSymbol = "chevron.down"
		trustButton.tip = StyledTip.Tip(
			title: "Trust this project",
			detail: "Choose how far it reaches: this project, the folder it is in, "
				+ "or everywhere a clone says it came from."
		)
		detailsButton = DrawnButton(title: "What is held back") { [weak self] in self?.showHeldBack() }
		detailsButton.prominence = .quiet

		// **Dismissable, and dismissing grants nothing.** A strip that can only
		// be got rid of by trusting the project is a strip that gets the
		// project trusted — which is the opposite of what it is for. The
		// project stays untrusted, the refusals stay, and File ▸ Trust This
		// Project… is where the gesture lives once the strip is away.
		closeButton = DrawnButton(symbol: "xmark", description: "Hide this") { [weak self] in
			self?.onDismiss?()
		}
		closeButton.prominence = .quiet
		closeButton.tip = StyledTip.Tip(
			title: "Hide this",
			detail: "The project stays untrusted and nothing in it runs. "
				+ "File ▸ Trust This Project… when you want it."
		)

		let stack = NSStackView(views: [icon, label, trustButton, detailsButton, closeButton])
		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		// The sentence gives way first: on a narrow window the button is what
		// the strip is for.
		label.setContentHuggingPriority(.defaultLow, for: .horizontal)
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(12)),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(12)),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
		stack.spacing = Theme.current.scaled(8)
	}

	/// The project this is about, or nil to hide the strip.
	func show(project: URL?) {
		guard let project else {
			isHidden = true
			return
		}
		isHidden = false
		label.stringValue = "\(project.lastPathComponent) is not trusted — "
			+ "nothing in it runs by itself, and its environment reaches nothing."
		applyTheme()
		needsDisplay = true
	}

	func applyTheme() {
		label.font = Theme.current.uiFont(11.5)
		label.textColor = Theme.current.sidebarHeaderText
		icon.image = Theme.symbol(
			"hand.raised.fill", size: 12 * Theme.current.scale, color: Theme.current.gitModified
		)
		trustButton.applyTheme()
		detailsButton.applyTheme()
		closeButton.applyTheme()
		needsDisplay = true
	}

	/// Under the button, which is where a dropdown belongs: it opened at the
	/// strip's leading edge to begin with — a menu that appears somewhere other
	/// than the control that opened it reads as a menu about something else.
	private func popTrustMenu() {
		guard let menu = trustScopes?() else { return }
		menu.popUp(
			positioning: nil,
			at: NSPoint(x: 0, y: trustButton.bounds.height),
			in: trustButton
		)
	}

	// MARK: - What is held back

	/// The two lists, in a popover from the button that asked for them.
	///
	/// **Not a toast, which was the first cut and wrong.** A toast goes on a
	/// timer and cannot be read twice: this is a list somebody is reading
	/// *while they decide*, and half of it — what still works — is the half
	/// that makes the decision easy. A popover stays until it is dismissed,
	/// appears where the press was, and can be opened again.
	private func showHeldBack() {
		let popover = NSPopover()
		popover.behavior = .transient
		popover.appearance = NSAppearance(named: Theme.current.isLight ? .aqua : .darkAqua)
		popover.contentViewController = HeldBackViewController()
		heldBack = popover
		popover.show(relativeTo: detailsButton.bounds, of: detailsButton, preferredEdge: .maxY)
	}

	private var heldBack: NSPopover?

	/// Opens the list from a driven run, so it can be photographed: a popover
	/// is a window of its own and a capture takes it with the rest.
	func showHeldBackForTesting() { showHeldBack() }

	/// What the popover lists, for a driven run — the words are the
	/// requirement, and a photograph cannot be grepped.
	func heldBackReportForTesting() -> String {
		"held back: " + HeldBackViewController.heldBack.joined(separator: ", ")
			+ " || still yours: " + HeldBackViewController.stillWorks.joined(separator: ", ")
	}

	/// What the strip says, for a driven run: the words are the requirement.
	var reportForTesting: String {
		isHidden ? "no banner" : label.stringValue
	}
}

/// The list behind *What is held back*.
///
/// **Two lists, not two paragraphs.** The first cut said the same things in
/// prose — semicolons between eight items — and prose is what somebody reads
/// last when they are trying to answer "can I look at this repository". A list
/// is scanned; a paragraph is skipped. Reported as exactly that.
///
/// Both halves are here because the second is what makes the decision easy:
/// what waits, and what does not.
@MainActor
private final class HeldBackViewController: NSViewController {
	static let heldBack = [
		"Running, debugging and building",
		"make, gradle and maven",
		"Devcontainers",
		"Language servers, formatters, linters",
		"Agents",
		"The environment its files ask for",
		"Its git hooks",
	]
	static let stillWorks = [
		"The tree, the editor, syntax, folding",
		"Search",
		"The git panes, history, diffs, blame",
		"Previews",
		"A terminal — your own shell",
	]

	/// The one thing about the terminal worth a sentence: it is not gated, and
	/// the project's own `.envrc` still does not run in it.
	static let footnote = "direnv is switched off there, so the project's files do not run "
		+ "behind you. What you type is your own choosing."

	override func loadView() {
		let width = Theme.current.scaled(300)
		let container = NSView()

		let stack = NSStackView(views: [
			Self.heading("While this project is not trusted", size: 12, weight: .semibold),
			// The palette's own red for the half that is refused: `gitModified`
			// is blue in every scheme here and read as "changed" rather than as
			// "not now", which is the wrong half of a security list to be
			// ambiguous about.
			Self.section("Held back", items: Self.heldBack, mark: "xmark",
			             ink: Theme.current.gitConflict, width: width),
			Self.section("Still yours", items: Self.stillWorks, mark: "checkmark",
			             ink: Theme.current.gitAdded, width: width),
			Self.note(Self.footnote, width: width),
		])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = Theme.current.scaled(10)
		stack.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(stack)

		let inset = Theme.current.scaled(14)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
			stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
			stack.topAnchor.constraint(equalTo: container.topAnchor, constant: inset),
			stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -inset),
			stack.widthAnchor.constraint(equalToConstant: width),
		])
		view = container
	}

	/// A heading and its rows: one mark per row, in the colour that says which
	/// half it is, so the two lists are told apart without being read.
	private static func section(
		_ title: String, items: [String], mark: String, ink: NSColor, width: CGFloat
	) -> NSView {
		var rows: [NSView] = [heading(title, size: 11, weight: .semibold)]
		rows += items.map { item in
			let symbol = NSImageView()
			symbol.image = Theme.symbol(mark, size: 9 * Theme.current.scale, color: ink)
			symbol.translatesAutoresizingMaskIntoConstraints = false
			symbol.widthAnchor.constraint(equalToConstant: Theme.current.scaled(12)).isActive = true

			let label = NSTextField(labelWithString: item)
			label.font = Theme.current.uiFont(11.5)
			label.textColor = Theme.current.sidebarText
			label.lineBreakMode = .byTruncatingTail

			let row = NSStackView(views: [symbol, label])
			row.orientation = .horizontal
			row.alignment = .firstBaseline
			row.spacing = Theme.current.scaled(6)
			return row
		}
		let stack = NSStackView(views: rows)
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = Theme.current.scaled(3)
		return stack
	}

	private static func heading(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
		let field = NSTextField(labelWithString: text)
		field.font = Theme.current.uiFont(size, weight: weight)
		field.textColor = Theme.current.sidebarHeaderText
		return field
	}

	private static func note(_ text: String, width: CGFloat) -> NSTextField {
		let field = NSTextField(wrappingLabelWithString: text)
		field.font = Theme.current.uiFont(10.5)
		field.textColor = Theme.current.gitIgnored
		field.preferredMaxLayoutWidth = width
		return field
	}
}
