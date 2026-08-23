import Foundation
import Testing
@testable import AbydosKit

/// Which keystroke is ⌃C.
///
/// The predicate rather than the plumbing, because the plumbing is view code
/// with no suite to hold it — and this is the half where being wrong is
/// expensive in both directions: too eager and a console stops somebody's
/// program on a copy, too strict and the key nobody can find an alternative to
/// does nothing.
struct TerminalInterruptTests {
	private func interrupt(
		_ characters: String?, control: Bool = true, command: Bool = false, option: Bool = false
	) -> Bool {
		TerminalKeys.isInterrupt(
			charactersIgnoringModifiers: characters,
			control: control, command: command, option: option
		)
	}

	@Test func controlCIsTheInterrupt() {
		#expect(interrupt("c"))
	}

	/// Asked of `charactersIgnoringModifiers` on purpose: with control held,
	/// `characters` is the control code itself and there is nothing to compare.
	@Test func theShiftedOneCountsToo() {
		#expect(interrupt("C"))
	}

	@Test func withoutControlItIsJustTheLetter() {
		#expect(interrupt("c", control: false) == false)
	}

	/// **⌘C is Copy**, which somebody over a console has every reason to press.
	/// A console that stopped the program on a copy would be a trap.
	@Test func commandCIsNotIt() {
		#expect(interrupt("c", command: true) == false)
	}

	@Test func optionMakesItADifferentKeystroke() {
		#expect(interrupt("c", option: true) == false)
	}

	@Test func nothingElseIsTheInterrupt() {
		#expect(interrupt("d") == false)
		#expect(interrupt("") == false)
		#expect(interrupt(nil) == false)
	}
}
