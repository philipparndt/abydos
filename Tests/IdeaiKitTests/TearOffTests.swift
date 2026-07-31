import CoreGraphics
import Testing
@testable import IdeaiKit

/// Dragging a tab out of the window makes a window of its own.
struct TearOffTests {
	private let window = CGRect(x: 100, y: 100, width: 1200, height: 800)

	@Test func releasingInsideTheWindowDoesNotTearOff() {
		#expect(!TearOff.tearsOff(dropPoint: CGPoint(x: 700, y: 500), sourceWindowFrame: window))
		// On the very edge still counts as inside.
		#expect(!TearOff.tearsOff(dropPoint: CGPoint(x: 100, y: 100), sourceWindowFrame: window))
	}

	@Test func releasingOutsideTearsOff() {
		#expect(TearOff.tearsOff(dropPoint: CGPoint(x: 50, y: 500), sourceWindowFrame: window))
		#expect(TearOff.tearsOff(dropPoint: CGPoint(x: 700, y: 2000), sourceWindowFrame: window))
		// A second display, off to the right.
		#expect(TearOff.tearsOff(dropPoint: CGPoint(x: 3000, y: 500), sourceWindowFrame: window))
	}

	// MARK: - Placement

	private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
	private let size = CGSize(width: 900, height: 600)

	@Test func theWindowHangsBelowThePointer() {
		let frame = TearOff.windowFrame(
			droppedAt: CGPoint(x: 960, y: 800), size: size, visibleFrame: screen
		)
		#expect(frame.midX == 960)
		#expect(frame.maxY == 800 + TearOff.grabInset)
	}

	/// Wherever it is dropped, the whole window has to be reachable.
	@Test func itLandsFullyOnScreen() {
		let corners = [
			CGPoint(x: 0, y: 0), CGPoint(x: 1920, y: 0),
			CGPoint(x: 0, y: 1080), CGPoint(x: 1920, y: 1080),
			CGPoint(x: 5, y: 1075),
		]
		for corner in corners {
			let frame = TearOff.windowFrame(droppedAt: corner, size: size, visibleFrame: screen)
			#expect(screen.contains(frame), "dropped at \(corner) gave \(frame)")
		}
	}

	/// The screen it was dropped on, not the one it came from.
	@Test func itLandsOnASecondDisplay() {
		let second = CGRect(x: 1920, y: 200, width: 2560, height: 1440)
		let frame = TearOff.windowFrame(
			droppedAt: CGPoint(x: 3200, y: 1000), size: size, visibleFrame: second
		)
		#expect(second.contains(frame))
		#expect(frame.midX == 3200)
	}

	@Test func aWindowTooBigForTheScreenIsShrunkToFit() {
		let small = CGRect(x: 0, y: 0, width: 800, height: 500)
		let frame = TearOff.windowFrame(
			droppedAt: CGPoint(x: 400, y: 250), size: CGSize(width: 2000, height: 1500),
			visibleFrame: small
		)
		#expect(frame == small)
	}

	/// The pointer should still be on the window it just made, so the drag can
	/// be continued by the title bar.
	@Test func thePointerEndsOnTheNewWindow() {
		for point in [CGPoint(x: 960, y: 540), CGPoint(x: 20, y: 1070), CGPoint(x: 1900, y: 30)] {
			let frame = TearOff.windowFrame(droppedAt: point, size: size, visibleFrame: screen)
			#expect(frame.contains(point), "dropped at \(point) gave \(frame)")
		}
	}
}
