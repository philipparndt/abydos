import Foundation
import Testing
@testable import AbydosKit

/// What a paste puts on the wire, as a claim rather than a race.
///
/// The leak of 2026-09-10 was a fallback that wrote bracketed-paste markers from
/// the outer terminal's mode when the paste went through tmux — where the inner
/// shell's mode is the one that matters and only tmux knows it. The rule that
/// closes it is here, testable without a window.
struct TmuxPasteDecisionTests {
	@Test func aTmuxClientTmuxTookIsWrittenNothing() {
		#expect(TmuxPaste.plan(
			text: "hello", throughTmux: true, tmuxAccepted: true, bracketedPaste: true
		) == .tmuxTook)
	}

	/// **The fix.** tmux was asked and could not; the terminal writes the text
	/// and not the markers, whatever the outer mode says, because through tmux
	/// the outer mode is not the program's.
	@Test func aTmuxClientTmuxRefusedIsWrittenRawTextWithNoMarker() {
		for outer in [true, false] {
			let plan = TmuxPaste.plan(
				text: "a\nb", throughTmux: true, tmuxAccepted: false, bracketedPaste: outer
			)
			#expect(plan == .write("a\nb"), "outer mode \(outer)")
			if case let .write(bytes) = plan {
				#expect(!bytes.contains("\u{1B}[200~"))
				#expect(!bytes.contains("[200~"))
			}
		}
	}

	@Test func aPlainPaneWithBracketedPasteOnGetsTheMarkers() {
		#expect(TmuxPaste.plan(
			text: "x", throughTmux: false, tmuxAccepted: false, bracketedPaste: true
		) == .write("\u{1B}[200~x\u{1B}[201~"))
	}

	@Test func aPlainPaneWithoutItGetsTheRawText() {
		#expect(TmuxPaste.plan(
			text: "x", throughTmux: false, tmuxAccepted: false, bracketedPaste: false
		) == .write("x"))
	}
}
