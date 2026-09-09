import AppKit
import CryptoKit
import QuickLookUI
import GoSTL
import AbydosKit
import SwiftUI

// MARK: - Status bar

final class EditorStatusView: NSView {
	/// A language was chosen by hand; nil means "no highlighting".
	var onLanguageChosen: ((String?) -> Void)?
	/// The lock was pressed: show or hide every secret in the file.
	var onSecretsToggled: (() -> Void)?

	private var positionText = ""
	private var languageText = ""
	private var languageRect = NSRect.zero
	private var isLanguageHovered = false
	private var trackingArea: NSTrackingArea?

	/// What the server chip says and what its tool tip says, already worked out.
	///
	/// Two strings and nothing else, which is the whole design: `setPosition` is
	/// called on every caret move and draws in this same view, so anything this
	/// bar has to *find out* would be found out beside every keystroke. The
	/// finding out happens in `LanguageService.footer(forLanguage:project:)`, is
	/// pushed here when a server starts, stops or is refused, and is a value by
	/// the time it arrives.
	private var serverText = ""
	private var serverDetail = ""
	private var serverRect = NSRect.zero
	private var isServerHovered = false
	/// Whether the front tab conceals at all, and whether it stands revealed —
	/// the lock's presence and which way it points.
	private var secretsConcealing = false
	private var secretsRevealed = false
	private var lockRect = NSRect.zero
	private var isLockHovered = false
	/// The SOPS chip's state, pushed by the area controller beside the lock's.
	private var sopsState: EditorViewController.SopsState = .none
	private var sopsRect = NSRect.zero
	private var isSopsHovered = false
	/// The passphrase field, made the first time it is asked for and laid
	/// over the chip's place while asking. A measured member of the scaled
	/// controls: AppKit's secure field, given its font from the theme.
	private var passphraseField: NSSecureTextField?
	private var passphraseAsk: (placeholder: String, tip: String)?
	/// Return in the field, with what was typed; the field is cleared.
	var onPassphraseEntered: ((String) -> Void)?
	/// Escape in the field: the chip comes back and nothing is tried.
	var onPassphraseCancelled: (() -> Void)?
	/// The chip was pressed: decrypt, encrypt and save, or encrypt a plaintext
	/// file the project's rules are for.
	var onSopsPressed: (() -> Void)?
	/// What git can see of a file whose values are covered, pushed by the area
	/// controller beside the lock's state. Nothing is drawn for a file git
	/// ignores, which is the ordinary case and the quiet one.
	private var exposure = SecretExposure.State.fine
	private var exposureRect = NSRect.zero
	private var isExposureHovered = false
	/// The notice was pressed and its one action chosen: write this file into
	/// `.gitignore`.
	var onIgnoreFile: (() -> Void)?
	/// How the front tab indents — the indent chip's words, pushed by the area
	/// controller beside the lock's and the SOPS chip's. Nil with no editor,
	/// and the chip is not drawn.
	private var indentStyle: IndentStyle?
	private var indentRect = NSRect.zero
	private var isIndentHovered = false
	/// A style was chosen from the menu: convert the file to it.
	var onIndentChosen: ((IndentStyle) -> Void)?
	/// The rectangle the tool tip is currently registered for, so it is put back
	/// only when it has moved rather than on every redraw. Nil asks for it to be
	/// registered again whatever the rectangle says.
	private var toolTipRect: NSRect?

	override var isFlipped: Bool { true }

	func setPosition(line: Int, column: Int) {
		positionText = "\(line):\(column)"
		needsDisplay = true
	}

	/// A hex tab's offset and selection, where a text tab has line and column.
	func setPosition(text: String) {
		positionText = text
		needsDisplay = true
	}

	func setLanguage(_ name: String?) {
		languageText = name ?? "Plain Text"
		needsDisplay = true
	}

	/// Which server is answering for the file, or nothing at all.
	///
	/// **Nothing at all is the common case and the deliberate one.** Most files
	/// in most projects have no server, and a chip saying so on every one of them
	/// would be a footer people learn to stop reading — which would cost the
	/// sentence it is here to say. The strip above the file is what talks about a
	/// server that is missing; this only names one that exists.
	func setSecrets(concealing: Bool, revealed: Bool) {
		guard concealing != secretsConcealing || revealed != secretsRevealed else { return }
		secretsConcealing = concealing
		secretsRevealed = revealed
		toolTipRect = nil
		needsDisplay = true
	}

	func setExposure(_ state: SecretExposure.State) {
		guard state != exposure else { return }
		exposure = state
		toolTipRect = nil
		needsDisplay = true
	}

	func setSops(_ state: EditorViewController.SopsState) {
		guard state != sopsState else { return }
		sopsState = state
		toolTipRect = nil
		needsDisplay = true
	}

	/// How the front tab indents, for the chip. Pushed on every status
	/// refresh beside the others, which is cheap here: a stored enum read,
	/// never a sample of the file.
	func setIndent(_ style: IndentStyle?) {
		guard style != indentStyle else { return }
		indentStyle = style
		toolTipRect = nil
		needsDisplay = true
	}

	func setServer(_ footer: LanguageServerFooter?) {
		let text = footer?.text(containerMark: MainWindowController.containerMark) ?? ""
		let detail = footer?.detail ?? ""
		guard text != serverText || detail != serverDetail else { return }
		serverText = text
		serverDetail = detail
		toolTipRect = nil
		needsDisplay = true
	}

	// MARK: - The language control

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		if let trackingArea { removeTrackingArea(trackingArea) }
		let area = NSTrackingArea(
			rect: bounds,
			options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
			owner: self
		)
		addTrackingArea(area)
		trackingArea = area
	}

	override func mouseMoved(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		let language = languageRect.contains(point)
		let server = !serverRect.isEmpty && serverRect.contains(point)
		let lock = !lockRect.isEmpty && lockRect.contains(point)
		let sops = !sopsRect.isEmpty && sopsRect.contains(point)
		let indent = !indentRect.isEmpty && indentRect.contains(point)
		let exposed = !exposureRect.isEmpty && exposureRect.contains(point)
		guard language != isLanguageHovered || server != isServerHovered
			|| lock != isLockHovered || sops != isSopsHovered || indent != isIndentHovered
			|| exposed != isExposureHovered else { return }
		isExposureHovered = exposed
		isLanguageHovered = language
		isServerHovered = server
		isLockHovered = lock
		isSopsHovered = sops
		isIndentHovered = indent
		needsDisplay = true
	}

	override func mouseExited(with event: NSEvent) {
		guard isLanguageHovered || isServerHovered || isLockHovered || isSopsHovered || isIndentHovered else { return }
		isLanguageHovered = false
		isServerHovered = false
		isLockHovered = false
		isSopsHovered = false
		isIndentHovered = false
		needsDisplay = true
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		if secretsConcealing, lockRect.contains(point) {
			onSecretsToggled?()
			return
		}
		if !sopsRect.isEmpty, sopsRect.contains(point) {
			onSopsPressed?()
			return
		}
		if !exposureRect.isEmpty, exposureRect.contains(point) {
			makeExposureMenu().popUp(
				positioning: nil, at: NSPoint(x: exposureRect.minX, y: exposureRect.maxY), in: self
			)
			return
		}
		if !indentRect.isEmpty, indentRect.contains(point) {
			showIndentMenu(at: NSPoint(x: indentRect.minX, y: indentRect.maxY))
			return
		}
		if languageRect.contains(point) {
			showLanguageMenu(at: NSPoint(x: languageRect.minX, y: languageRect.maxY))
			return
		}

		// **The list of what is running, and not the settings page.** Both were
		// candidates and they answer different questions. The chip states a fact
		// about *this project* — this server, from here, now — and the questions
		// that follow from reading it are whether it is really running, what it
		// is costing, which executable the system resolved and how to stop it;
		// that window answers all four and has the Stop. Settings is where the
		// answer is *changed*, but a settings page knows no project — the spec
		// says as much where it explains why a chosen server's row is in the list
		// and not in Settings — so a click landing there would answer a question
		// nobody had just asked.
		guard !serverRect.isEmpty, serverRect.contains(point) else { return }
		RunningToolsWindowController.shared.show()
	}

	override func resetCursorRects() {
		super.resetCursorRects()
		addCursorRect(languageRect, cursor: .pointingHand)
		if !serverRect.isEmpty { addCursorRect(serverRect, cursor: .pointingHand) }
		if !indentRect.isEmpty { addCursorRect(indentRect, cursor: .pointingHand) }
		if !exposureRect.isEmpty { addCursorRect(exposureRect, cursor: .pointingHand) }
	}

	private func showLanguageMenu(at point: NSPoint) {
		let menu = NSMenu()

		let plain = NSMenuItem(title: "Plain Text", action: #selector(chooseLanguage(_:)), keyEquivalent: "")
		plain.target = self
		plain.state = languageText == "Plain Text" ? .on : .off
		menu.addItem(plain)
		menu.addItem(.separator())

		for language in LanguageRegistry.shared.selectableLanguages {
			let item = NSMenuItem(title: language.name, action: #selector(chooseLanguage(_:)), keyEquivalent: "")
			item.target = self
			item.representedObject = language.id
			item.state = language.name == languageText ? .on : .off
			menu.addItem(item)
		}

		menu.popUp(positioning: nil, at: point, in: self)
	}

	@objc private func chooseLanguage(_ sender: NSMenuItem) {
		onLanguageChosen?(sender.representedObject as? String)
	}

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		// The editor's own background, not the sidebar's. This bar and the
		// panel's tab strip sat one on top of the other in the same shade with
		// the same hairline, so the pair read as a single band and the strip
		// took double-clicks meant for the bar — which maximises the panel.
		// Belonging to the editor is also what this bar is: it says where the
		// caret is.
		Theme.current.editorBackground.setFill()
		bounds.fill()

		// Along the top, between the text and this. The panel below draws its
		// own; two lines with nothing between them was the other half of the
		// problem.
		Theme.current.separator.setFill()
		NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()

		let attributes: [NSAttributedString.Key: Any] = [
			.font: Theme.current.uiFont(11),
			.foregroundColor: Theme.current.gitIgnored,
		]

		// Right-aligned: server, then position, then the indentation, then
		// language at the edge.
		//
		// **The order is about which one is allowed to lose.** The language,
		// the caret's position and the file's indentation are a handful of
		// characters and never more, so they are laid out first and keep
		// their place; the server is beside the language — the same fact one
		// layer down — and is the one that can be a name and an image tag
		// together, so it takes whatever room the others leave and truncates
		// at the tail. 0458 hit this on a card and settled it the same way:
		// say the important part first.
		let gap = Theme.current.scaled(16)
		var x = bounds.width - Theme.current.scaled(12)
		// The indent chip joins the right side as the language's neighbour —
		// both are menus, and two controls that open menus belong side by
		// side. Cleared first so a redraw with no style (no editor) takes
		// its hit area with it.
		indentRect = .zero
		let indentText = indentStyle?.words ?? ""
		for (index, text) in [languageText, indentText, positionText].enumerated() where !text.isEmpty {
			let attributed = NSAttributedString(string: text, attributes: attributes)
			let size = attributed.size()
			x -= size.width
			let origin = NSPoint(x: x, y: bounds.midY - size.height / 2)

			// The language and the indentation are controls, so each gets a
			// hit area and a hover background — otherwise nothing suggests
			// it can be clicked.
			if index == 0 {
				languageRect = chipRect(around: origin, size: size)
				if isLanguageHovered { highlight(languageRect) }
			} else if index == 1 {
				indentRect = chipRect(around: origin, size: size)
				if isIndentHovered { highlight(indentRect) }
			}

			attributed.draw(at: origin)
			x -= gap
		}

		// The file's facts first — SOPS, then the lock — each taking its
		// origin from the one before it, and none of them inside
		// `drawServer`, which returns early for the many files with no server.
		// Drawn before it so the server's room can begin after they end: these
		// two are about the file, not its tooling, and a narrow window owes
		// the server a name that starts after they finish rather than one
		// that overlaps them.
		drawSops()
		drawLock()
		drawExposure()
		drawServer(leftOf: x, after: leftChipsExtent(), attributes: attributes)
	}

	/// Where the left side's chips end, which is where the server's room
	/// begins. Zero when none is shown, so the room falls back to the left
	/// margin it always used.
	private func leftChipsExtent() -> CGFloat {
		max(
			chipsBeforeExposure(),
			exposureRect.isEmpty ? 0 : exposureRect.maxX
		)
	}

	/// How far the two chips the notice stands after reach.
	///
	/// **Separate from `leftChipsExtent` because the notice must not measure
	/// itself.** It did, for one build: its left edge came from an extent that
	/// counted `exposureRect`, so every redraw put it one gap further along
	/// than the last and the label walked to the right under the pointer —
	/// reported as "moving the mouse over the new secrets label makes it move".
	/// The server chip's room still counts all three, which is the question it
	/// is asking.
	private func chipsBeforeExposure() -> CGFloat {
		max(
			sopsRect.isEmpty ? 0 : sopsRect.maxX,
			lockRect.isEmpty ? 0 : lockRect.maxX
		)
	}

	/// The SOPS chip, first at the edge, before the lock: the chip is the
	/// button and the lock is a fact beside it, and a button that moves
	/// between its two states is a button nobody learns to reach for. It used
	/// to stand after the lock, and a decrypt brought the lock up beside it —
	/// so the chip jumped away the moment it was pressed. Pressing it
	/// decrypts, or encrypts and saves; ⌘S is the other way to the second.
	// MARK: - The passphrase field

	/// Puts a secure field where the chip is, named for the key or the file,
	/// with gpg's sentence as its tooltip, and the keyboard in it.
	func askPassphrase(placeholder: String, tip: String) {
		passphraseAsk = (placeholder, tip)
		let field = passphraseField ?? makePassphraseField()
		field.placeholderString = placeholder
		field.toolTip = tip
		field.stringValue = ""
		field.isHidden = false
		field.frame = passphraseRect()
		needsDisplay = true
		window?.makeFirstResponder(field)
	}

	/// The chip back, the field empty and gone.
	func endPassphraseAsk() {
		passphraseAsk = nil
		passphraseField?.stringValue = ""
		passphraseField?.isHidden = true
		needsDisplay = true
	}

	var isAskingPassphrase: Bool { passphraseAsk != nil }
	var passphraseAskForTesting: String? { passphraseAsk?.placeholder }

	private func makePassphraseField() -> NSSecureTextField {
		let field = NSSecureTextField()
		field.font = Theme.current.uiFont(11)
		field.focusRingType = .none
		field.delegate = self
		field.target = self
		field.action = #selector(passphraseEntered)
		addSubview(field)
		passphraseField = field
		return field
	}

	/// The chip's place, widened to hold a passphrase.
	private func passphraseRect() -> NSRect {
		let width = Theme.current.scaled(240)
		let height = Theme.current.scaled(19)
		return NSRect(x: Theme.current.scaled(8), y: (bounds.height - height) / 2, width: width, height: height)
	}

	override func layout() {
		super.layout()
		if isAskingPassphrase { passphraseField?.frame = passphraseRect() }
	}

	@objc private func passphraseEntered() {
		guard let field = passphraseField else { return }
		let typed = field.stringValue
		field.stringValue = ""
		onPassphraseEntered?(typed)
	}

	private func drawSops() {
		// While a passphrase is being asked for, the field stands where the
		// chip was and the chip is not drawn under it.
		if isAskingPassphrase {
			sopsRect = passphraseRect()
			return
		}
		guard sopsState != .none else {
			sopsRect = .zero
			return
		}
		let words: String
		let colour: NSColor
		let glyph: String
		switch sopsState {
		case .none: return
		case .unavailable:
			words = "sops not found"; colour = Theme.current.gitIgnored.withAlphaComponent(0.6); glyph = "lock.shield"
		case .encrypted:
			words = "SOPS · encrypted"; colour = Theme.current.gitIgnored; glyph = "lock.shield.fill"
		case .decrypted(let edited):
			words = edited ? "SOPS · encrypt and save" : "SOPS · decrypted"
			colour = Theme.current.gitModified; glyph = "shield.lefthalf.filled"
		case .offer:
			// An offer, so it says what pressing does rather than what the file
			// is: the file is plaintext, which is the state nobody needs a chip
			// to be told about.
			words = "SOPS · encrypt"; colour = Theme.current.gitAdded; glyph = "lock.shield"
		}
		let height = Theme.current.scaled(12)
		let symbol = Theme.symbol(glyph, size: 11 * Theme.current.scale, color: colour)
		let aspect = (symbol?.size.height ?? 0) > 0 ? symbol!.size.width / symbol!.size.height : 1
		let drawn = NSSize(width: height * aspect, height: height)
		// At the edge, always — the one place the chip keeps through every
		// state, so it is where the cursor already is when its state changes.
		let origin = NSPoint(x: Theme.current.scaled(12), y: bounds.midY - drawn.height / 2)
		let label = NSAttributedString(string: words, attributes: [
			.font: Theme.current.uiFont(11), .foregroundColor: colour,
		])
		let labelSize = label.size()
		let labelOrigin = NSPoint(
			x: origin.x + (symbol == nil ? 0 : drawn.width + Theme.current.scaled(5)),
			y: bounds.midY - labelSize.height / 2
		)
		sopsRect = chipRect(
			around: origin,
			size: NSSize(
				width: (symbol == nil ? 0 : drawn.width + Theme.current.scaled(5)) + labelSize.width,
				height: max(drawn.height, labelSize.height)
			)
		)
		if isSopsHovered { highlight(sopsRect) }
		symbol?.drawFitted(in: NSRect(origin: origin, size: drawn))
		label.draw(at: labelOrigin)
	}

	/// The server chip, in the room the position and the language left, which
	/// begins after the file-fact chips on the left rather than at the
	/// window's margin: with the indent chip always present, an overlap on a
	/// narrow window was a matter of time rather than of bad luck.
	private func drawServer(
		leftOf right: CGFloat, after leftExtent: CGFloat, attributes: [NSAttributedString.Key: Any]
	) {
		defer { refreshServerToolTip() }
		serverRect = .zero
		guard !serverText.isEmpty else { return }

		var truncating = attributes
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		truncating[.paragraphStyle] = paragraph
		let attributed = NSAttributedString(string: serverText, attributes: truncating)
		let size = attributed.size()

		// Whether there is room to say it, and how much of it is said, decided in
		// `LanguageServerFooter` — a rule the suite can reach rather than a
		// comparison written where the drawing is. 0467 is why: the rule used to
		// be here, it asked the wrong question, and nothing in the suite could
		// see it ask.
		let left = max(leftExtent, Theme.current.scaled(12))
		let room = right - left - Theme.current.scaled(10)
		guard let fits = LanguageServerFooter.chipWidth(
			text: Double(size.width),
			room: Double(room),
			legibleAt: Double(Theme.current.scaled(56))
		) else { return }
		let width = CGFloat(fits)

		let origin = NSPoint(x: right - Theme.current.scaled(12) - width, y: bounds.midY - size.height / 2)
		serverRect = chipRect(around: origin, size: NSSize(width: width, height: size.height))
		if isServerHovered { highlight(serverRect) }
		attributed.draw(in: NSRect(origin: origin, size: NSSize(width: width, height: size.height)))
	}

	/// The lock, after the SOPS chip when one is shown, alone at the edge when
	/// there is not: shut while the file's secrets are covered, open while they
	/// stand revealed, absent for a file that conceals nothing. Pressing it
	/// shows or hides every secret in the file — the same act as View ▸
	/// Reveal Secrets, one click closer to where the covers are.
	/// What git can see, after the lock: *Not in .gitignore*, or *Committed to
	/// git* for the case a `.gitignore` line can no longer fix.
	///
	/// **A statement, not a warning.** It is drawn where the lock already is,
	/// in the bar's own type, and nothing about it interrupts: a dialog at open
	/// is a dialog answered by reflex, and the file this is about is usually
	/// open before anybody thinks about committing it. Nothing is drawn at all
	/// for a file git ignores, which is what most of them are.
	private func drawExposure() {
		guard let words = SecretExposure.words(for: exposure) else {
			exposureRect = .zero
			return
		}
		let colour = Theme.current.gitModified
		let height = Theme.current.scaled(12)
		let symbol = Theme.symbol("eye.trianglebadge.exclamationmark", size: 11 * Theme.current.scale, color: colour)
		let aspect = (symbol?.size.height ?? 0) > 0 ? symbol!.size.width / symbol!.size.height : 1
		let drawn = NSSize(width: height * aspect, height: height)
		// After whichever of the chip and the lock is furthest along, so the
		// two facts about the file stay where they were and this joins them.
		let before = chipsBeforeExposure()
		let left = before > 0 ? before + Theme.current.scaled(10) : Theme.current.scaled(12)
		let origin = NSPoint(x: left, y: bounds.midY - drawn.height / 2)
		let label = NSAttributedString(string: words, attributes: [
			.font: Theme.current.uiFont(11), .foregroundColor: colour,
		])
		let labelSize = label.size()
		let gap = symbol == nil ? 0 : drawn.width + Theme.current.scaled(5)
		exposureRect = chipRect(
			around: origin,
			size: NSSize(width: gap + labelSize.width, height: max(drawn.height, labelSize.height))
		)
		if isExposureHovered { highlight(exposureRect) }
		symbol?.drawFitted(in: NSRect(origin: origin, size: drawn))
		label.draw(at: NSPoint(x: origin.x + gap, y: bounds.midY - labelSize.height / 2))
	}

	private func drawLock() {
		guard secretsConcealing else {
			lockRect = .zero
			return
		}
		let height = Theme.current.scaled(12)
		guard let symbol = Theme.symbol(
			secretsRevealed ? "lock.open.fill" : "lock.fill",
			size: 11 * Theme.current.scale,
			color: secretsRevealed ? Theme.current.gitModified : Theme.current.gitIgnored
		) else {
			lockRect = .zero
			return
		}
		// At the symbol's own aspect: the open lock is wider than tall, and a
		// square rect squeezed it out of shape.
		let aspect = symbol.size.height > 0 ? symbol.size.width / symbol.size.height : 1
		let drawn = NSSize(width: height * aspect, height: height)
		// After the chip when there is one, at the edge when there is not: the
		// chip is the control that gets pressed, and it keeps its place.
		let left = sopsRect.isEmpty ? Theme.current.scaled(12) : sopsRect.maxX + Theme.current.scaled(10)
		let origin = NSPoint(x: left, y: bounds.midY - drawn.height / 2)

		// The word beside the symbol, because a lock alone could be about
		// anything — the file, the git index, the window.
		let label = NSAttributedString(
			string: secretsRevealed ? "Secrets shown" : "Secrets hidden",
			attributes: [
				.font: Theme.current.uiFont(11),
				.foregroundColor: secretsRevealed
					? Theme.current.gitModified : Theme.current.gitIgnored,
			]
		)
		let labelSize = label.size()
		let labelOrigin = NSPoint(
			x: origin.x + drawn.width + Theme.current.scaled(5),
			y: bounds.midY - labelSize.height / 2
		)
		lockRect = chipRect(
			around: origin,
			size: NSSize(
				width: drawn.width + Theme.current.scaled(5) + labelSize.width,
				height: max(drawn.height, labelSize.height)
			)
		)
		if isLockHovered { highlight(lockRect) }
		symbol.drawFitted(in: NSRect(origin: origin, size: drawn))
		label.draw(at: labelOrigin)
	}

	/// The notice's menu: the one thing there is to do about a file git can
	/// see, and — for a file git already tracks — the reason that thing is not
	/// offered, said as a disabled line rather than as an item that would look
	/// like a fix.
	private func makeExposureMenu() -> NSMenu {
		let menu = NSMenu()
		switch exposure {
		case .fine:
			break
		case .notIgnored:
			let item = NSMenuItem(title: "Add this file to .gitignore", action: #selector(ignoreFile), keyEquivalent: "")
			item.target = self
			menu.addItem(item)
		case .tracked:
			let said = NSMenuItem(title: "Git already tracks this file", action: nil, keyEquivalent: "")
			said.isEnabled = false
			menu.addItem(said)
			let note = NSMenuItem(
				title: "Ignoring it now would not take its values out of the history",
				action: nil, keyEquivalent: ""
			)
			note.isEnabled = false
			menu.addItem(note)
		}
		return menu
	}

	@objc private func ignoreFile() { onIgnoreFile?() }

	/// The indent menu, popped at the chip on the right: the styles a file is
	/// switched among, the current one ticked. Choosing converts the file's
	/// indentation to the style and makes it the one inserted from here; the
	/// chip itself is drawn in the right-aligned row beside the language,
	/// where the two menu-openers stand together.
	private func showIndentMenu(at point: NSPoint) {
		makeIndentMenu().popUp(positioning: nil, at: point, in: self)
	}

	/// The menu's items, built from the one rule the driven report also
	/// reads: tabs, then the standing widths with the file's own beside them
	/// when it is not one of them.
	private func makeIndentMenu() -> NSMenu {
		let menu = NSMenu()
		let tabs = NSMenuItem(
			title: "Indent with Tabs", action: #selector(chooseIndent(_:)), keyEquivalent: ""
		)
		tabs.target = self
		tabs.tag = 0
		tabs.state = indentStyle == .tabs ? .on : .off
		menu.addItem(tabs)
		menu.addItem(.separator())

		var currentWidth: Int?
		if case .spaces(let width) = indentStyle { currentWidth = width }
		for width in IndentStyle.offeredWidths(currentWidth: currentWidth) {
			let item = NSMenuItem(
				title: "Indent with \(width) Spaces", action: #selector(chooseIndent(_:)), keyEquivalent: ""
			)
			item.target = self
			item.tag = width
			item.state = indentStyle == .spaces(width: width) ? .on : .off
			menu.addItem(item)
		}
		return menu
	}

	@objc private func chooseIndent(_ sender: NSMenuItem) {
		onIndentChosen?(sender.tag == 0 ? .tabs : .spaces(width: sender.tag))
	}

	/// The hit area and hover background of a chip, around the text it holds.
	private func chipRect(around origin: NSPoint, size: NSSize) -> NSRect {
		let padding = Theme.current.scaled(5)
		return NSRect(
			x: origin.x - padding,
			y: bounds.midY - size.height / 2 - padding / 2,
			width: size.width + padding * 2,
			height: size.height + padding
		)
	}

	private func highlight(_ rect: NSRect) {
		NSColor.white.withAlphaComponent(0.08).setFill()
		NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
	}

	/// Puts the tool tip back where the chip is now.
	///
	/// On the chip's rectangle rather than on the whole bar, because the bar is
	/// mostly empty and a tool tip over the empty part would be a sentence about
	/// a language server appearing under the mouse on its way somewhere else.
	/// Done here because here is where the rectangle is known — the caret's
	/// position changes width, so the chip beside it moves — and guarded so that
	/// a redraw for a caret that moved within the same line costs nothing.
	private var lockToolTipTag: NSView.ToolTipTag?
	private var sopsToolTipTag: NSView.ToolTipTag?
	private var indentToolTipTag: NSView.ToolTipTag?
	private var exposureToolTipTag: NSView.ToolTipTag?

	private func refreshServerToolTip() {
		guard serverRect != toolTipRect else { return }
		toolTipRect = serverRect
		removeAllToolTips()
		lockToolTipTag = nil
		sopsToolTipTag = nil
		indentToolTipTag = nil
		exposureToolTipTag = nil
		if !sopsRect.isEmpty {
			sopsToolTipTag = addToolTip(sopsRect, owner: self, userData: nil)
		}
		// **The view is the owner, because `addToolTip` retains nothing.** A
		// bridged NSString passed as owner is released as soon as this method
		// returns, and the tooltip timer then asks a freed pointer whether it
		// responds to stringForToolTip — which is a SIGSEGV in
		// NSToolTipManager, seen in a crash report the first day the lock had
		// a tooltip. The view outlives its own tooltips by construction, and
		// answers below with text computed when the tip is shown.
		if !lockRect.isEmpty {
			lockToolTipTag = addToolTip(lockRect, owner: self, userData: nil)
		}
		if !indentRect.isEmpty {
			indentToolTipTag = addToolTip(indentRect, owner: self, userData: nil)
		}
		if !exposureRect.isEmpty {
			exposureToolTipTag = addToolTip(exposureRect, owner: self, userData: nil)
		}
		guard !serverRect.isEmpty else { return }
		addToolTip(serverRect, owner: self, userData: nil)
	}

	@objc func view(
		_ view: NSView, stringForToolTip tag: NSView.ToolTipTag,
		point: NSPoint, userData data: UnsafeMutableRawPointer?
	) -> String {
		if tag == lockToolTipTag {
			return secretsRevealed
				? "Hide the file's secrets again"
				: "Reveal all secrets in this file"
		}
		if tag == sopsToolTipTag {
			switch sopsState {
			case .none: return ""
			case .unavailable:
				return "This file is SOPS-encrypted, and the sops command was not found on the PATH"
			case .encrypted:
				return "Decrypt with sops into the editor. Nothing decrypted is written to disk."
			case .decrypted(let edited):
				return edited
					? "Encrypt with sops and save over the file, as ⌘S does; the buffer shows the ciphertext again"
					: "Decrypted in the editor only. Press to put the ciphertext back; edit and ⌘S to encrypt and save."
			case .offer:
				return "This project's .sops.yaml has a rule for this path. Press to encrypt the file with sops."
			}
		}
		if tag == exposureToolTipTag {
			return SecretExposure.consequence(for: exposure) ?? ""
		}
		if tag == indentToolTipTag {
			switch indentStyle {
			case .none: return ""
			case .tabs:
				return "This file indents with tabs. Choosing an indentation converts the file to it, and what ⇥, ⇧⇥ and return insert follows."
			case .spaces(let width):
				return "This file indents with \(width) spaces. Choosing an indentation converts the file to it, and what ⇥, ⇧⇥ and return insert follows."
			}
		}
		return serverDetail
	}

	// MARK: - Testing

	/// What the bar is saying about the server, for a photograph to be checked
	/// against — the words and the rectangle they were measured into, since a
	/// card measured at one width and drawn at another is a fault this project
	/// has had twice.
	var serverReportForTesting: String {
		serverText.isEmpty
			? "no server"
			: "\(serverText) [\(Int(serverRect.width))×\(Int(serverRect.height))]"
	}
}


extension EditorStatusView: NSTextFieldDelegate {
	/// Escape in the passphrase field puts the chip back.
	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		guard control === passphraseField, selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
		onPassphraseCancelled?()
		return true
	}
}
