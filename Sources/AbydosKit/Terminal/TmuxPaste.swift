import Foundation

/// What a paste puts on the wire, decided without a window so the rule is a
/// test and not a race.
///
/// A paste into a tmux pane is handed to tmux, which knows the inner program's
/// bracketed-paste mode and wraps the text or does not. Only when tmux cannot
/// be reached does the terminal write the text itself — and there is the trap
/// this type exists to close.
///
/// **Through tmux, the terminal's own bracketed-paste flag is the wrong mode.**
/// It is tmux's forwarded mode, the outer client's; the program that will read
/// the bytes is the inner shell, which toggles its own mode as it runs commands
/// and edits lines. When the two disagree for an instant, markers written on the
/// outer mode reach the shell literally — `ESC[200~` loses its `ESC` to the
/// line editor and leaves `[200~` in the command line, `ESC[201~` a trailing
/// `~`. Reported 2026-09-10, a string pasted twice, one clean and one broken.
///
/// So the rule: markers are written only where nothing knows the mode better
/// than we do, which through tmux is never. A tmux paste that failed is written
/// raw. A multi-line paste that runs line by line is annoying; a marker in the
/// command line is a bug.
public enum TmuxPaste {
	/// What to do with the text.
	public enum Plan: Equatable, Sendable {
		/// tmux took it; nothing goes on the wire directly.
		case tmuxTook
		/// Write exactly this to the program.
		case write(String)
	}

	/// - Parameters:
	///   - throughTmux: whether the pane is a tmux client.
	///   - tmuxAccepted: whether the tmux paste succeeded (after its retries).
	///     Meaningless when `throughTmux` is false.
	///   - bracketedPaste: the emulator's own mode, which is the authority only
	///     when there is no tmux between the terminal and the program.
	public static func plan(
		text: String, throughTmux: Bool, tmuxAccepted: Bool, bracketedPaste: Bool
	) -> Plan {
		if throughTmux {
			// tmux took it, or it did not and we write the text plainly — never
			// the markers, because the inner mode is tmux's to know and tmux is
			// the thing that just failed.
			return tmuxAccepted ? .tmuxTook : .write(text)
		}
		// No tmux: the emulator's mode is the real one, so the markers mean what
		// they say. This is the path a bare pane has always taken.
		return .write(bracketedPaste ? "\u{1B}[200~" + text + "\u{1B}[201~" : text)
	}
}
