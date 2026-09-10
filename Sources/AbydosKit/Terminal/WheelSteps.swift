import Foundation

/// How many lines a wheel event is worth to a program, by the device it came from.
///
/// Two devices raise two shapes of event. A mouse wheel raises one per notch,
/// with a delta near ten points and a larger one when spun. A trackpad raises
/// one every eight to sixteen milliseconds while the fingers move, each carrying
/// the points covered since the last, and then a momentum phase of the same shape
/// after they lift. One formula served both — `Int(|Δy| / cellHeight) + 1`, five
/// at most — and it was tuned against the wheel: the `+ 1` that makes a notch
/// under a cell height still a line made every two-point trackpad event a line
/// too, at a hundred events a second. A slow drag of one cell moved ten lines
/// and a flick moved hundreds. Reported 2026-09-10 by somebody on a trackpad,
/// and not by the maintainer on a mouse, which is what pointed at the device.
///
/// So the precise device is added up: one step per whole cell the gesture has
/// covered, the fraction carried into the next event. The wheel keeps its
/// formula to the byte, because nobody on a wheel had a complaint.
///
/// Kept out of the view so the arithmetic is a test and not a feeling.
public struct WheelSteps: Sendable {
	/// Points from a precise device not yet turned into a step. Signed: the
	/// event's sign, positive for up.
	public private(set) var carried: CGFloat = 0

	public init() {}

	/// A gesture began: what an earlier one left over is not owed to this one.
	public mutating func reset() {
		carried = 0
	}

	/// The steps this event is worth, signed as the event is — positive for up.
	///
	/// `precise` is `hasPreciseScrollingDeltas`: true for a trackpad or a Magic
	/// Mouse, false for a wheel with notches.
	public mutating func take(delta: CGFloat, precise: Bool, cellHeight: CGFloat) -> Int {
		guard delta != 0 else { return 0 }
		guard precise else { return Self.notchSteps(delta: delta, cellHeight: cellHeight) }

		// A finger changing its mind is not charged the old remainder before the
		// new direction registers: fourteen down and two up is two up.
		if (carried > 0) != (delta > 0) { carried = 0 }
		carried += delta
		let cell = max(1, cellHeight)
		let steps = Int((carried / cell).rounded(.towardZero))
		carried -= CGFloat(steps) * cell
		return steps
	}

	/// The formula a notch has had since mouse reporting was added: one line
	/// for a notch, more for a spun wheel, five at most.
	///
	/// A zero delta is zero, where it used to be one line *down* — a sideways
	/// event, or a phase marker, compared `0 > 0` and took the floor.
	public static func notchSteps(delta: CGFloat, cellHeight: CGFloat) -> Int {
		guard delta != 0 else { return 0 }
		let magnitude = max(1, min(5, Int(abs(delta) / max(1, cellHeight)) + 1))
		return delta > 0 ? magnitude : -magnitude
	}
}
