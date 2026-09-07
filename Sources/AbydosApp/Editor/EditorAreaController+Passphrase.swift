import AbydosKit
import AppKit

/// The passphrase field's owner: the area holds the status bar, so the ask
/// a group raises and the answer the field gives meet here.
extension EditorAreaController {
	/// A group may ask for a passphrase; the bar shows the field and the
	/// answer goes back to whichever decrypt asked. One ask at a time: a
	/// second one replaces the first, whose caller is told nothing came.
	func wirePassphrase(_ group: EditorViewController) {
		group.onPassphraseNeeded = { [weak self, weak group] placeholder, tip, answer in
			guard let self else { return }
			pendingPassphrase?(nil)
			pendingPassphrase = answer
			group?.passphraseAskForTesting = placeholder
			group?.passphraseAnswerForTesting = { [weak self] text in self?.answerPassphrase(text) }
			statusBar.askPassphrase(placeholder: placeholder, tip: tip)
		}
	}

	/// The answer to the field, or its dismissal, handed to whichever decrypt
	/// asked; the field goes away either way and the keyboard returns to the
	/// editor.
	func answerPassphrase(_ text: String?) {
		let waiting = pendingPassphrase
		pendingPassphrase = nil
		statusBar.endPassphraseAsk()
		for group in groups {
			group.passphraseAskForTesting = nil
			group.passphraseAnswerForTesting = nil
		}
		if let codeView = activeGroup?.activeCodeView { view.window?.makeFirstResponder(codeView) }
		waiting?(text)
	}
}
