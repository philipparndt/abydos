import Foundation
import Testing
@testable import AbydosKit

/// Which mouse button means what.
///
/// Stated once because two places read it: the terminal, which forwards only the
/// middle one to the program, and the window, which navigates on the other two.
/// Two answers to "is this the middle button" is how a side button came to be
/// pasted into a shell.
struct MouseButtonTests {
	@Test func theMiddleButtonIsTwoAndTheSideButtonsAreThreeAndFour() {
		#expect(MouseButtons.purpose(of: 2) == .middleClick)
		#expect(MouseButtons.purpose(of: 3) == .navigateBack)
		#expect(MouseButtons.purpose(of: 4) == .navigateForward)
	}

	/// **The bug, as a claim.** Every one of these was forwarded as the middle
	/// button, which is button 1 on the wire and paste in many terminals.
	@Test func onlyTheMiddleButtonIsTheMiddleButton() {
		for number in 0...8 where number != MouseButtons.middle {
			#expect(MouseButtons.purpose(of: number) != .middleClick, "button \(number)")
		}
	}

	/// Anything past the two side buttons travels up unclaimed, which is what an
	/// unhandled event does everywhere else.
	@Test func aButtonNobodyWantsIsUnclaimed() {
		#expect(MouseButtons.purpose(of: 5) == .unclaimed)
		#expect(MouseButtons.purpose(of: 9) == .unclaimed)
		// Left and right never arrive here — they have their own overrides —
		// but a number is a number and this must not claim them.
		#expect(MouseButtons.purpose(of: 0) == .unclaimed)
		#expect(MouseButtons.purpose(of: 1) == .unclaimed)
	}
}
