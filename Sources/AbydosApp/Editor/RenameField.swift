import AppKit
import AbydosKit

/// A field laid over something on screen, for typing a new name into.
///
/// ## Why this and not a dialog
///
/// The navigator renames a file in place on the row — 0439 — and a symbol
/// rename in the editor is the same gesture one layer in: the thing being
/// renamed is on screen, the new name goes where the old one is, and the rest
/// of the window carries on. A sheet would be the opposite of all three, and
/// `Toast.swift`'s rule about not interrupting is the same rule: this program
/// does not stop somebody to ask them a question they are already looking at
/// the answer to.
///
/// ## Why it is extracted rather than copied
///
/// There were three of these already — the navigator's row, the terminal's tab
/// strip, the changes pane — and each had its own copy of the same four rules,
/// which are all rules because the opposite happened to somebody:
///
///  * **Return commits, Escape drops, clicking away commits.** The third is the
///    one people forget, and leaving it out means a field that can never be got
///    rid of except by answering it.
///  * **A refusal keeps the field open**, with the text still in it and the
///    caret where it was. A name that is not allowed is a typo far more often
///    than it is a change of mind, and a field that closes makes the person
///    start again.
///  * **Never `makeFirstResponder` on the field that already has it.** It tears
///    down and rebuilds the field editor, which fires `controlTextDidEndEditing`
///    — so the name commits again, is refused again, and the person gets two
///    identical messages. The navigator pays for that sentence.
///  * **Clear the field before removing it from its superview.** Removing a
///    field that is being edited fires `controlTextDidEndEditing` synchronously,
///    which commits the name Escape had just rejected.
@MainActor final class RenameField: NSObject, NSTextFieldDelegate {
	/// A name was accepted. Answer `false` to refuse it and keep the field.
	var onCommit: ((String) -> Bool)?
	/// Escape, or a commit that was the same name.
	var onCancel: (() -> Void)?

	private var field: NSTextField?
	/// The name it opened with, so an unchanged one is a cancel rather than a
	/// rename of a symbol to itself — which is a real request to a server and a
	/// workspace edit that does nothing.
	private var original = ""

	var isOpen: Bool { field != nil }

	/// The text in the field, for a test to read back without a window.
	var textForTesting: String? { field?.stringValue }

	/// Opens the field over `rect` in `host`.
	///
	/// - Parameters:
	///   - rect: where the symbol is, in `host`'s coordinates. The field is laid
	///     over it and grows to the right as the name gets longer, because a
	///     field that stayed the width of the old name would hide what is being
	///     typed into it.
	///   - caveat: a sentence about what accepting this actually promises, shown
	///     under the field. Where it belongs: a warning that arrives *with the
	///     result* is a warning about something that has already happened.
	func begin(
		over rect: NSRect, in host: NSView, name: String,
		font: NSFont? = nil, caveat: String? = nil
	) {
		end()
		original = name

		let field = NSTextField(frame: rect.insetBy(dx: -2, dy: -1))
		field.stringValue = name
		// The editor's own font, so the name being typed sits exactly where the
		// old one was rather than jumping to the system font over the code.
		field.font = font ?? Theme.current.editorFont
		field.isBezeled = false
		field.drawsBackground = true
		field.backgroundColor = Theme.current.editorBackground
		field.textColor = Theme.current.editorText
		field.focusRingType = .none
		field.delegate = self
		field.wantsLayer = true
		field.layer?.borderWidth = 1
		field.layer?.borderColor = Theme.current.caret.cgColor
		field.layer?.cornerRadius = 2
		if let caveat { field.toolTip = caveat }

		host.addSubview(field, positioned: .above, relativeTo: nil)
		self.field = field
		host.window?.makeFirstResponder(field)
		field.currentEditor()?.selectedRange = NSRange(location: 0, length: (name as NSString).length)

		// The caveat under the field rather than in a toast: it is about the
		// thing being typed, so it belongs beside it and goes when it does.
		guard let caveat else { return }
		let note = RenameCaveatView(text: caveat)
		note.frame = NSRect(
			x: rect.minX, y: rect.maxY + 2,
			width: note.fittingSize.width, height: note.fittingSize.height
		)
		host.addSubview(note, positioned: .above, relativeTo: nil)
		self.caveat = note
	}

	private var caveat: NSView?

	/// Takes the field away. Safe to call when there is none.
	func end() {
		// Cleared first: removing a field that is being edited fires
		// `controlTextDidEndEditing` synchronously, and the delegate would then
		// commit a name that is on its way out.
		let going = field
		field = nil
		original = ""
		going?.removeFromSuperview()
		caveat?.removeFromSuperview()
		caveat = nil
	}

	/// Says why a name was not taken, and leaves the field standing so it can be
	/// corrected.
	func refuse(_ title: String, detail: String? = nil) {
		Toast.post(title, detail: detail)
		guard let field, let window = field.window else { return }
		// Never on the field that already has it — see the note at the top.
		let responder = window.firstResponder
		guard responder !== field, responder !== field.currentEditor() else { return }
		window.makeFirstResponder(field)
	}

	/// Types a name and presses Return, the way somebody would, for a test with
	/// no keyboard.
	@discardableResult
	func commitForTesting(_ name: String) -> Bool {
		guard let field else { return false }
		field.stringValue = name
		return commit()
	}

	// MARK: - Keys

	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		switch selector {
		case #selector(NSResponder.insertNewline(_:)):
			_ = commit()
			return true
		case #selector(NSResponder.cancelOperation(_:)):
			end()
			onCancel?()
			return true
		default:
			return false
		}
	}

	func controlTextDidEndEditing(_ notification: Notification) {
		// Clicking away commits, the way it does everywhere else here. Guarded
		// against the field that is already going: `end()` clears `field` before
		// it removes the view, so this sees nil and does nothing.
		guard let field, notification.object as? NSTextField === field else { return }
		_ = commit()
	}

	@discardableResult
	private func commit() -> Bool {
		guard let field else { return false }
		let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

		// Nothing typed, or the name it already had. Neither is a rename, and
		// asking a server to rename a symbol to itself is a workspace edit that
		// changes nothing and a second of somebody's time.
		guard !name.isEmpty, name != original else {
			end()
			onCancel?()
			return false
		}

		// The field goes only if the name was taken. A refusal leaves it
		// standing with the text still in it, which is what makes a typo one
		// keystroke to fix rather than the whole gesture again.
		guard onCommit?(name) ?? true else { return false }
		end()
		return true
	}
}

/// The sentence under the field about what a rename by this server means.
///
/// Drawn rather than a toast, because it is about the thing being typed and has
/// to go when the field does — and because a toast for something that has not
/// happened yet reads as a report of something that has.
private final class RenameCaveatView: NSView {
	private let label = NSTextField(labelWithString: "")

	init(text: String) {
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		layer?.borderWidth = 1
		layer?.borderColor = Theme.current.gitModified.withAlphaComponent(0.7).cgColor
		layer?.cornerRadius = 3

		label.stringValue = text
		label.font = .systemFont(ofSize: Theme.current.scaled(11))
		label.textColor = Theme.current.gitModified
		label.translatesAutoresizingMaskIntoConstraints = false
		addSubview(label)
		let inset = Theme.current.scaled(6)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
			label.topAnchor.constraint(equalTo: topAnchor, constant: inset / 2),
			label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset / 2),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override var isFlipped: Bool { true }
}
