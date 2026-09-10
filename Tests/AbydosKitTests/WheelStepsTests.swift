import Foundation
import Testing
@testable import AbydosKit

/// How many lines a wheel event is worth to a program.
///
/// Two devices, two shapes of event. A mouse wheel raises one event a notch; a
/// trackpad raises a hundred a second, each carrying the points moved since the
/// last. One formula served both, and it was tuned against the wheel: every
/// trackpad event was at least a line, however small. Reported 2026-09-10 by
/// somebody on a trackpad, and not by the maintainer on a mouse.
struct WheelStepsTests {
	let cell: CGFloat = 16

	@Test func aWheelNotchIsOneLineAsItWas() {
		var steps = WheelSteps()
		#expect(steps.take(delta: 10, precise: false, cellHeight: cell) == 1)
		#expect(steps.take(delta: -10, precise: false, cellHeight: cell) == -1)
	}

	@Test func aSpunWheelIsFiveLinesAtMost() {
		var steps = WheelSteps()
		#expect(steps.take(delta: 40, precise: false, cellHeight: cell) == 3)
		#expect(steps.take(delta: 200, precise: false, cellHeight: cell) == 5)
	}

	/// A wheel event with no vertical motion — a sideways one, or a phase
	/// marker — used to come out as one line down, because zero is not greater
	/// than zero and the floor was one.
	@Test func anEventWithNoVerticalMotionMovesNothing() {
		var steps = WheelSteps()
		#expect(steps.take(delta: 0, precise: false, cellHeight: cell) == 0)
		#expect(steps.take(delta: 0, precise: true, cellHeight: cell) == 0)
	}

	@Test func aTrackpadEventSmallerThanACellMovesNothingYet() {
		var steps = WheelSteps()
		#expect(steps.take(delta: -2, precise: true, cellHeight: cell) == 0)
		#expect(steps.carried == -2)
	}

	/// **The bug, as a claim.** A slow drag of one cell height arrives as ten
	/// events of two points. The old formula made that ten lines; it is the one
	/// line the finger moved, sent when the eighth event completes the cell.
	@Test func tenSmallTrackpadEventsAreTheOneLineTheFingerMoved() {
		var steps = WheelSteps()
		var sent: [Int] = []
		for _ in 0..<10 {
			sent.append(steps.take(delta: -2, precise: true, cellHeight: cell))
		}
		#expect(sent.reduce(0, +) == -1)
		#expect(sent == [0, 0, 0, 0, 0, 0, 0, -1, 0, 0])
		#expect(steps.carried == -4)

		var asAWheel = 0
		for _ in 0..<10 { asAWheel += WheelSteps.notchSteps(delta: -2, cellHeight: cell) }
		#expect(asAWheel == -10, "what the wheel formula made of the same drag")
	}

	@Test func aFlickIsAsManyLinesAsItsDistance() {
		var steps = WheelSteps()
		#expect(steps.take(delta: 100, precise: true, cellHeight: cell) == 6)
		#expect(steps.carried == 4)
	}

	/// Fourteen points carried down and two arriving up is two up, not twelve
	/// down: a finger that changes its mind is not charged the old remainder.
	@Test func reversingDirectionDropsTheCarry() {
		var steps = WheelSteps()
		#expect(steps.take(delta: -14, precise: true, cellHeight: cell) == 0)
		#expect(steps.take(delta: 2, precise: true, cellHeight: cell) == 0)
		#expect(steps.carried == 2)
	}

	@Test func aNewGestureStartsFromNothing() {
		var steps = WheelSteps()
		_ = steps.take(delta: 14, precise: true, cellHeight: cell)
		steps.reset()
		#expect(steps.carried == 0)
		#expect(steps.take(delta: 2, precise: true, cellHeight: cell) == 0)
		#expect(steps.carried == 2)
	}

	/// A wheel event between trackpad events leaves the carry alone: it is a
	/// different device, and its notch is whole on its own.
	@Test func aNotchDoesNotDisturbWhatATrackpadCarries() {
		var steps = WheelSteps()
		_ = steps.take(delta: 6, precise: true, cellHeight: cell)
		#expect(steps.take(delta: 10, precise: false, cellHeight: cell) == 1)
		#expect(steps.carried == 6)
	}
}
