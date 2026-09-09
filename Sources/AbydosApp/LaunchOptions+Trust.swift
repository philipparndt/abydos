import AppKit
import AbydosKit

/// What a driven run says about project trust.
///
/// Together rather than seven flags side by side, because trust is one gate
/// with several ways through it, and a run that grants it usually then asks
/// what the strip says — which is the pair of flags nobody would guess were
/// related from the middle of an alphabetical list.
///
/// The sheet itself stays undriven: `NSAlert` wants a person.
extension LaunchOptions {
	struct Trust {
		/// `--trust` / `--trust-parent`: grant this project trust as the
		/// window's strip grants it, so a run can drive both sides of the gate.
		var project = false
		var parent = false
		/// `--trust-remote [owner]`: trust where this clone says it came from —
		/// the host, or the owner on it — as the sheet's own checkboxes do.
		var remoteHost = false
		var remoteOwner = false
		/// `--trust-report`: what the strip says, and whether the project is
		/// trusted, printed once the window is up.
		var report = false
		/// `--trust-held-back`: open the strip's list, for a photograph and for
		/// the words.
		var heldBack = false
		/// `--trust-dismiss`: put the strip away without trusting, as its ✕ does.
		var dismiss = false
	}
}
