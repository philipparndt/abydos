import AppKit
import AbydosKit

/// Zooming the window, and saying what happened to its frame.
///
/// **Three readings, because a springback is two frame changes.** The report is
/// that a double-click on the title bar zooms the window and it returns to the
/// size it was — so a run that reads the frame once after the gesture cannot
/// tell "it did not zoom" from "it zoomed and something put it back". Before,
/// immediately after, and a beat later; `isZoomed` beside each, because that is
/// AppKit's own opinion of the same question and the two can disagree.
///
/// In a file of its own: the two driving files are at the length aim, and this
/// is one instrument with one subject.
extension MainWindowController {
	/// `--zoom-gesture click` or `zoom`, optionally `@<seconds>`.
	///
	/// Both, because they are different claims. `zoom` calls what AppKit calls
	/// when the system setting says a double-click zooms, so it exercises the
	/// frame arithmetic and nothing else. `click` posts the double-click itself,
	/// which is the gesture that was reported — and can land on one of the
	/// title bar's own controls, so it says what was under it.
	func exerciseZoomForTesting(_ how: String) {
		guard let window else {
			print("ZOOM: no window")
			fflush(stdout)
			return
		}

		func say(_ when: String) {
			let frame = window.frame
			let visible = window.screen?.visibleFrame ?? .zero
			print(String(
				format: "ZOOM %@: frame=(%.0f,%.0f %.0f×%.0f) zoomed=%@ visible=(%.0f,%.0f %.0f×%.0f)",
				when, frame.minX, frame.minY, frame.width, frame.height,
				window.isZoomed ? "yes" : "no",
				visible.minX, visible.minY, visible.width, visible.height
			))
			fflush(stdout)
		}

		say("before")
		if how.hasPrefix("click") {
			print("ZOOM click: \(doubleClickTitleBar(of: window))")
			fflush(stdout)
		} else {
			window.zoom(nil)
		}
		say("after")
		// A beat, because the springback in the report is visible: the window
		// goes large and comes back, which is a second frame change on a later
		// turn of the run loop.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
			say("settled")
			// `click+back` or `zoom+back`: the same gesture again, which is a
			// toggle and has to give the window the size it had.
			guard how.hasSuffix("+back") else { return }
			if how.hasPrefix("click") {
				print("ZOOM click: \(self.doubleClickTitleBar(of: window))")
				fflush(stdout)
			} else {
				window.zoom(nil)
			}
			say("back")
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { say("back settled") }
		}
	}

	/// Posts a double-click in the title bar, through the window's own event
	/// queue rather than the system tap — see `TreeKeys.click` for what the tap
	/// costs a driven run.
	///
	/// The point is above the content the app draws and left of the run
	/// control: a click that lands on a control of ours is the instrument
	/// missing rather than the zoom failing, so what was under it is said.
	private func doubleClickTitleBar(of window: NSWindow) -> String {
		let point = NSPoint(x: window.frame.width * 0.42, y: window.frame.height - 14)
		let under = window.contentView?.hitTest(point).map { String(describing: type(of: $0)) } ?? "nothing"
		func event(_ type: NSEvent.EventType) -> NSEvent? {
			NSEvent.mouseEvent(
				with: type, location: point, modifierFlags: [],
				timestamp: ProcessInfo.processInfo.systemUptime,
				windowNumber: window.windowNumber, context: nil,
				eventNumber: 0, clickCount: 2, pressure: type == .leftMouseDown ? 1 : 0
			)
		}
		guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else {
			return "no event"
		}
		NSApp.activate(ignoringOtherApps: true)
		window.makeKeyAndOrderFront(nil)
		// **Down then up, in that order, and not the queued-release trick
		// `TreeKeys` needs.** A table's `mouseDown` runs a tracking loop that
		// asks the window for the release, so there the release is queued
		// first; a title bar runs no such loop. Queued here, the release
		// arrived on a later turn with no press in front of it, and AppKit read
		// an up carrying `clickCount: 2` as a double-click of its own — so
		// every gesture zoomed twice. That looked exactly like the springback
		// this change is about, and was this instrument.
		window.sendEvent(down)
		window.sendEvent(up)
		return "at (\(Int(point.x)),\(Int(point.y))) on \(under)"
	}
}
