import AppKit
import IdeaiKit

/// What a breakpoint should do besides stop: a condition, a hit count, a line
/// to log instead of stopping.
///
/// A sheet of this app's own rather than an `NSAlert` with three text fields
/// bolted underneath it. The alert put its title in bold at the top, its
/// buttons at the bottom, and everything that mattered in a grey box between —
/// which is what an alert does with an accessory view, and why it looked like
/// something unfinished rather than something built.
///
/// The fields hold code, and are drawn as code: monospaced, coloured by the
/// same grammar the file is. A condition is the one piece of code somebody
/// writes without the editor's help, and it is the one place a missing quote
/// was invisible.
final class BreakpointOptionsSheet: NSViewController {
	private let line: Int
	private let fileName: String
	private let languageId: String
	private let existing: Breakpoint
	private let onApply: (String, String, String) -> Void

	private var conditionField: CodeField!
	private var hitField: CodeField!
	private var logField: CodeField!

	init(
		line: Int,
		fileName: String,
		languageId: String,
		existing: Breakpoint,
		onApply: @escaping (_ condition: String, _ hitCondition: String, _ logMessage: String) -> Void
	) {
		self.line = line
		self.fileName = fileName
		self.languageId = languageId
		self.existing = existing
		self.onApply = onApply
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func loadView() {
		let container = NSView()
		container.wantsLayer = true
		container.layer?.backgroundColor = Theme.current.sidebarBackground.cgColor

		let title = NSTextField(labelWithString: "Breakpoint on line \(line)")
		title.font = Theme.current.uiFont(13, weight: .semibold)
		title.textColor = Theme.current.sidebarText

		// Which file, because a breakpoint is a place and the line number alone
		// is only half of one.
		let subtitle = NSTextField(labelWithString: fileName)
		subtitle.font = Theme.current.uiFont(11)
		subtitle.textColor = Theme.current.gitIgnored

		conditionField = CodeField(languageId: languageId, isCode: true)
		conditionField.stringValue = existing.condition ?? ""
		hitField = CodeField(languageId: languageId, isCode: true)
		hitField.stringValue = existing.hitCondition ?? ""
		// A log message is prose with code in the braces, so it is highlighted
		// by what is in them rather than parsed as a whole.
		logField = CodeField(languageId: languageId, isCode: false)
		logField.stringValue = existing.logMessage ?? ""

		let form = NSStackView(views: [
			title,
			subtitle,
			labelled("Stop only when this is true", "i > 5", conditionField),
			labelled("Stop after this many hits", "> 5", hitField),
			labelled("Log this and carry on, instead of stopping", "i is {i}", logField),
			buttons(),
		])
		form.orientation = .vertical
		form.alignment = .leading
		form.spacing = Theme.current.scaled(12)
		form.setCustomSpacing(Theme.current.scaled(2), after: title)
		form.setCustomSpacing(Theme.current.scaled(18), after: subtitle)
		form.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(form)

		// Every row as wide as the form. Left alone, a row is as wide as its
		// own heading, so the three fields came out three different widths —
		// each one sized to the label above it rather than to the sheet.
		for row in form.arrangedSubviews where !(row is NSTextField) {
			row.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
		}

		let margin = Theme.current.scaled(20)
		NSLayoutConstraint.activate([
			form.topAnchor.constraint(equalTo: container.topAnchor, constant: margin),
			form.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
			form.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin),
			form.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -margin),
			container.widthAnchor.constraint(equalToConstant: Theme.current.scaled(460)),
		])
		view = container
	}

	override func viewDidAppear() {
		super.viewDidAppear()
		view.window?.makeFirstResponder(conditionField)
	}

	/// A label, and an example under the field of what belongs in it.
	private func labelled(_ text: String, _ example: String, _ field: CodeField) -> NSView {
		let label = NSTextField(labelWithString: text)
		label.font = Theme.current.uiFont(11)
		label.textColor = Theme.current.sidebarText

		// The example beside the label rather than inside the field as a
		// placeholder: a placeholder disappears the moment somebody starts
		// typing, which is when they are still deciding what to write.
		let hint = NSTextField(labelWithString: "e.g. \(example)")
		hint.font = Theme.terminalFont(size: Theme.current.fontSize - 2)
		hint.textColor = Theme.current.gitIgnored

		let heading = NSStackView(views: [label, hint])
		heading.orientation = .horizontal
		heading.spacing = Theme.current.scaled(8)

		let stack = NSStackView(views: [heading, field])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = Theme.current.scaled(5)
		field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		return stack
	}

	private func buttons() -> NSView {
		let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
		cancel.bezelStyle = .rounded
		cancel.keyEquivalent = "\u{1b}"

		let apply = NSButton(title: "Apply", target: self, action: #selector(apply(_:)))
		apply.bezelStyle = .rounded
		apply.keyEquivalent = "\r"

		// A note about the empty field, where it is relevant: this is the only
		// way to take a condition off again, and nothing else says so.
		let note = NSTextField(labelWithString: "An empty field drops that part.")
		note.font = Theme.current.uiFont(10.5)
		note.textColor = Theme.current.gitIgnored

		let spacer = NSView()
		spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

		let row = NSStackView(views: [note, spacer, cancel, apply])
		row.orientation = .horizontal
		row.spacing = Theme.current.scaled(8)
		return row
	}

	@objc private func cancel(_ sender: Any?) {
		close()
	}

	@objc fileprivate func apply(_ sender: Any?) {
		onApply(conditionField.stringValue, hitField.stringValue, logField.stringValue)
		close()
	}

	/// Ends the sheet on the window that began it, which is what closes one.
	private func close() {
		guard let sheet = view.window else { return }
		if let parent = sheet.sheetParent {
			parent.endSheet(sheet)
		} else {
			sheet.close()
		}
	}
}

/// A one-line field holding code, coloured as code.
///
/// A text view rather than an `NSTextField`, because a field cannot show two
/// colours in one value. One line only: these are expressions, and a return
/// belongs to the sheet's Apply button.
final class CodeField: NSTextView {
	private var languageId = ""
	/// Whether the whole value is code, or prose with code in braces.
	private var isCode = true

	/// Built through `NSTextView`'s own initialiser rather than around it: a
	/// text view assembles a text storage, a layout manager and a container,
	/// and a subclass that calls `init(frame:)` without implementing
	/// `init(frame:textContainer:)` gets none of them and traps on the way up.
	convenience init(languageId: String, isCode: Bool) {
		self.init(frame: .zero)
		self.languageId = languageId
		self.isCode = isCode
		configure()
	}

	private func configure() {
		isRichText = false
		isAutomaticQuoteSubstitutionEnabled = false
		isAutomaticDashSubstitutionEnabled = false
		isAutomaticSpellingCorrectionEnabled = false
		isVerticallyResizable = false
		isHorizontallyResizable = false
		textContainer?.widthTracksTextView = true
		textContainer?.lineFragmentPadding = Theme.current.scaled(6)
		// Down the middle of the box. A text view lays its first line against
		// the top, so in a field one line tall the text sat on the upper edge
		// with the rest of the height empty under it.
		let lineHeight = Theme.terminalFont(size: Theme.current.fontSize).boundingRectForFont.height
		textContainerInset = NSSize(
			width: 0,
			height: max(0, (Theme.current.scaled(26) - lineHeight) / 2)
		)
		font = Theme.terminalFont(size: Theme.current.fontSize)
		textColor = Theme.current.sidebarText
		insertionPointColor = Theme.current.sidebarText
		backgroundColor = Theme.current.editorBackground
		drawsBackground = true
		wantsLayer = true
		layer?.cornerRadius = Theme.current.scaled(5)
		translatesAutoresizingMaskIntoConstraints = false
		heightAnchor.constraint(equalToConstant: Theme.current.scaled(26)).isActive = true
		delegate = self
	}

	var stringValue: String {
		get { string }
		set {
			string = newValue
			recolour()
		}
	}

	/// Return applies the sheet rather than adding a line this cannot show.
	override func insertNewline(_ sender: Any?) {
		window?.contentViewController?.tryToPerform(
			#selector(BreakpointOptionsSheet.apply(_:)), with: sender
		)
	}

	/// Colours the value.
	///
	/// Through the layout manager's temporary attributes rather than the text
	/// storage's own. A plain-text view — which this is, so that typing behaves
	/// like typing — applies its typing attributes over the storage, and the
	/// colours went on and were painted over: nine tokens found, none visible.
	/// Temporary attributes are what syntax highlighting is for.
	fileprivate func recolour() {
		guard let layout = layoutManager else { return }
		let whole = NSRange(location: 0, length: (string as NSString).length)
		layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)

		for (range, kind) in coloured() {
			let ns = NSRange(location: range.lowerBound, length: range.count)
			guard ns.location >= 0, NSMaxRange(ns) <= whole.length else { continue }
			layout.setTemporaryAttributes(
				[.foregroundColor: Theme.current.color(for: kind)], forCharacterRange: ns
			)
		}
	}

	/// What to colour: the whole value when it is code, and only what is in
	/// braces when it is a message that interpolates code.
	private func coloured() -> [(Range<Int>, HighlightKind)] {
		guard isCode else {
			return ExpressionHighlight.interpolations(in: string).flatMap { range -> [(Range<Int>, HighlightKind)] in
				let inner = string.utf16Slice(range.lowerBound + 1..<range.upperBound - 1)
				return ExpressionHighlight.tokens(in: inner, languageId: languageId)
					.map { ((range.lowerBound + 1 + $0.range.lowerBound)..<(range.lowerBound + 1 + $0.range.upperBound), $0.kind) }
					+ [(range.lowerBound..<(range.lowerBound + 1), .punctuation), ((range.upperBound - 1)..<range.upperBound, .punctuation)]
			}
		}
		return ExpressionHighlight.tokens(in: string, languageId: languageId).map { ($0.range, $0.kind) }
	}
}

extension CodeField: NSTextViewDelegate {
	func textDidChange(_ notification: Notification) {
		recolour()
	}
}

private extension String {
	/// The substring at a UTF-16 range, which is what the highlighter speaks.
	func utf16Slice(_ range: Range<Int>) -> String {
		let text = self as NSString
		let clamped = NSRange(
			location: max(0, min(range.lowerBound, text.length)),
			length: max(0, min(range.count, text.length - min(range.lowerBound, text.length)))
		)
		return text.substring(with: clamped)
	}
}
