import Foundation

/// What a mouse button number means, said once.
///
/// macOS raises `otherMouseDown` for everything past left and right, and
/// `buttonNumber` says which. Reading it is the whole of the terminal's
/// middle-click bug: all of them were forwarded to the program as the middle
/// button, which is button 1 on the wire, and middle click in a terminal is
/// commonly paste — so a side button over the terminal could put the selection
/// into the shell.
///
/// A number rather than a name because that is what the system reports. Drivers
/// renumber and remap; this says what to do with what arrives, not what anybody's
/// hardware sends.
public enum MouseButtons {
	/// The middle button, and the only one a terminal program hears about.
	public static let middle = 2
	/// The two side buttons, which browsers use for back and forward.
	public static let back = 3
	public static let forward = 4

	/// What a button number is for.
	public enum Purpose: Equatable, Sendable {
		/// The terminal's, when a program is tracking the mouse.
		case middleClick
		case navigateBack
		case navigateForward
		/// Anything else, which travels up the responder chain unclaimed —
		/// which is what an unhandled event does everywhere else.
		case unclaimed
	}

	public static func purpose(of buttonNumber: Int) -> Purpose {
		switch buttonNumber {
		case middle: return .middleClick
		case back: return .navigateBack
		case forward: return .navigateForward
		default: return .unclaimed
		}
	}
}
