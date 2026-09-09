import AppKit
import AbydosKit

/// Zooming the window, and saying what happened to its frame.
///
/// **Three readings, because a springback is two frame changes.** The report is
/// that a double-click on the title bar zooms the window and it returns to the
/// size it was — so a run that reads the frame once after the gesture cannot
/// tell "it did not zoom" from "it zoomed and something put it back". Before,
/// once the zoom animation has had time to finish, and a beat later; `isZoomed`
/// beside each, because that is AppKit's own opinion of the same question and
/// the two can disagree.
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

		// **The largest frame the window passed through, beside where it is.**
		// Both toggles of a springback finish inside the first reading's wait —
		// each zoom animates for a fifth of a second and blocks the run loop
		// while it does — so a window zoomed and put back reads exactly like a
		// window nothing happened to. The resize notifications are the
		// difference: a springback passes through the visible frame and back,
		// and a gesture that did nothing passes through nothing.
		let largest = LargestFrame(window.frame)
		let watching = NotificationCenter.default.addObserver(
			forName: NSWindow.didResizeNotification, object: window, queue: nil
		) { [largest] note in
			guard let resized = note.object as? NSWindow else { return }
			largest.note(resized.frame)
		}

		func say(_ when: String) {
			let frame = window.frame
			let visible = window.screen?.visibleFrame ?? .zero
			print(String(
				format: "ZOOM %@: frame=(%.0f,%.0f %.0f×%.0f) zoomed=%@ largest=%.0f×%.0f visible=(%.0f,%.0f %.0f×%.0f)",
				when, frame.minX, frame.minY, frame.width, frame.height,
				window.isZoomed ? "yes" : "no",
				largest.frame.width, largest.frame.height,
				visible.minX, visible.minY, visible.width, visible.height
			))
			fflush(stdout)
		}

		func gesture() {
			if how.hasPrefix("click") {
				print("ZOOM click: \(doubleClickTitleBar(of: window))")
				fflush(stdout)
			} else {
				window.zoom(nil)
			}
		}

		// The zoom animates for about a fifth of a second, and a click is four
		// events the run loop delivers on its own turns — so the first reading
		// after the gesture waits for both, and the second is far enough behind
		// it that a window put back on a later turn has been put back.
		say("before")
		gesture()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { say("after") }
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
			say("settled")
			// `click+back` or `zoom+back`: the same gesture again, which is a
			// toggle and has to give the window the size it had.
			guard how.hasSuffix("+back") else {
				NotificationCenter.default.removeObserver(watching)
				return
			}
			gesture()
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { say("back") }
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				say("back settled")
				NotificationCenter.default.removeObserver(watching)
			}
		}
	}

	/// The biggest frame a window has had since the reading began: a resize
	/// notification arrives with the window already resized, so what it passed
	/// through is only known to somebody who was listening.
	private final class LargestFrame: @unchecked Sendable {
		private(set) var frame: NSRect
		init(_ frame: NSRect) { self.frame = frame }
		func note(_ candidate: NSRect) {
			if candidate.width * candidate.height > frame.width * frame.height { frame = candidate }
		}
	}

	/// Posts a double-click in the title bar, through the application's own
	/// event queue rather than the system tap — see `TreeKeys.click` for what
	/// the tap costs a driven run.
	///
	/// **All four events, in the order a mouse sends them.** A double-click is a
	/// press and release counted once, then a press and release counted twice,
	/// and the first pair is not decoration: forwarded by the strip as any view
	/// forwards a click, it reaches AppKit's own frame view and arms the
	/// title-bar handling that acts on the second release. An instrument that
	/// sent only the second pair — which this one did, and measured the zoom as
	/// correct with it — never armed that path, and so never saw the second
	/// toggle it produced while the strip still zoomed on the press. The
	/// reported springback was that toggle, reproduced only once the first
	/// click was sent too.
	///
	/// Posted rather than sent, so the run loop delivers them one turn at a time
	/// as it would a real click, and so a press that runs a tracking loop finds
	/// its release already in the queue.
	///
	/// The point is above the content the app draws and left of the run
	/// control: a click that lands on a control of ours is the instrument
	/// missing rather than the zoom failing, so what was under it is said.
	private func doubleClickTitleBar(of window: NSWindow) -> String {
		let point = NSPoint(x: window.frame.width * 0.42, y: window.frame.height - 14)
		let under = window.contentView?.hitTest(point).map { String(describing: type(of: $0)) } ?? "nothing"
		func event(_ type: NSEvent.EventType, count: Int) -> NSEvent? {
			NSEvent.mouseEvent(
				with: type, location: point, modifierFlags: [],
				timestamp: ProcessInfo.processInfo.systemUptime,
				windowNumber: window.windowNumber, context: nil,
				eventNumber: 0, clickCount: count, pressure: type == .leftMouseDown ? 1 : 0
			)
		}
		let sequence: [(NSEvent.EventType, Int)] = [
			(.leftMouseDown, 1), (.leftMouseUp, 1), (.leftMouseDown, 2), (.leftMouseUp, 2),
		]
		let events = sequence.compactMap { event($0.0, count: $0.1) }
		guard events.count == sequence.count else { return "no event" }
		NSApp.activate(ignoringOtherApps: true)
		window.makeKeyAndOrderFront(nil)
		for event in events { NSApp.postEvent(event, atStart: false) }
		return "at (\(Int(point.x)),\(Int(point.y))) on \(under)"
	}
}
