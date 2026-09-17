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
	/// `--zoom-gesture click`, `click-status` or `zoom`, optionally `@<seconds>`.
	///
	/// All three, because they are different claims. `zoom` calls what AppKit
	/// calls when the system setting says a double-click zooms, so it exercises
	/// the frame arithmetic and nothing else. `click` posts the double-click
	/// itself, which is the gesture that was reported — and can land on one of
	/// the title bar's own controls, so it says what was under it.
	/// `click-status` aims the same four events at the run control's status
	/// area, where the gesture was reported to do nothing on 2026-09-16, and
	/// `click-clear` a single click at the cross that clears the status.
	///
	/// **What a posted click can and cannot show.** Under macOS 26.7 the zoom
	/// is decided in `NSWindow.mouseDown` from the real mouse's state, and a
	/// posted `NSEvent` does not carry it: a posted double-click zooms nothing,
	/// not even on the backdrop where a mouse zooms every time. So the reading
	/// worth having from `click` is where the press went — the view under the
	/// point and the responder chain above it, which this prints — and the
	/// frame readings are for `zoom`, and for the day posted events act again.
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
				let place: TitleBarPlace = how.hasPrefix("click-status") ? .runControlStatus
					: how.hasPrefix("click-clear") ? .runControlClear
					: how.hasPrefix("click-x") ? .x(Double(how.dropFirst(7).prefix { $0.isNumber }) ?? 0)
					: .leftOfRunControl
				print("ZOOM click: \(doubleClickTitleBar(of: window, at: place))")
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
	/// Where in the title bar a posted double-click lands.
	private enum TitleBarPlace {
		/// Above the content the app draws and left of the run control, where
		/// nothing of ours claims the press: a click that lands on a control
		/// here is the instrument missing rather than the zoom failing, so
		/// what was under it is said.
		case leftOfRunControl
		/// The middle of the status message on the title bar, left of the run
		/// control — or, with no message showing, the room where one would be.
		/// The reading wanted is the backdrop under the point: the status view
		/// declines the hit, so the click is the title bar's.
		case runControlStatus
		/// The cross that clears the status — a single click, not a double,
		/// because the claim is that the cross still does its own job and
		/// the window stays where it was.
		case runControlClear
		/// `click-x<n>`: a point at that x, just under the top edge. A
		/// diagnostic for finding out what a spot in the strip belongs to.
		case x(CGFloat)
	}

	private func doubleClickTitleBar(of window: NSWindow, at place: TitleBarPlace) -> String {
		let point: NSPoint
		var detail = ""
		switch place {
		case .leftOfRunControl:
			point = NSPoint(x: window.frame.width * 0.42, y: window.frame.height - 14)
		case .x(let x):
			point = NSPoint(x: x, y: window.frame.height - 14)
		case .runControlStatus, .runControlClear:
			guard let control = run.runControl, control.window === window else { return "no run control" }
			let controlFrame = control.convert(control.bounds, to: nil)
			let status = titlebar.statusForTesting
			let shown = status.map { !$0.isHidden && $0.hasMessage } ?? false
			if case .runControlClear = place {
				guard let status, shown else { return "no status showing" }
				let cross = status.convert(status.clearRect, to: nil)
				point = NSPoint(x: cross.midX, y: cross.midY)
			} else if let status, shown {
				let area = status.convert(status.bounds, to: nil)
				point = NSPoint(x: area.midX, y: area.midY)
			} else {
				// No message: the room where it would be, left of the buttons.
				point = NSPoint(x: controlFrame.minX - Theme.current.scaled(60), y: controlFrame.midY)
			}
			detail = String(
				format: " control=(%.0f,%.0f %.0f×%.0f) status=%@", controlFrame.minX, controlFrame.minY,
				controlFrame.width, controlFrame.height, shown ? "shown" : "none"
			)
		}
		// Asked of the frame view, not the content view: the toolbar's views
		// hang off the window's frame, so a content-view hit test answers
		// "the backdrop" for a point that a real click would give to a pill.
		let frameView = window.contentView?.superview ?? window.contentView
		let hit = frameView?.hitTest(point)
		let under = hit.map { String(describing: type(of: $0)) } ?? "nothing"
		// The chain the press climbs, so a forwarded event can be followed to
		// whoever keeps it.
		var chain: [String] = []
		var responder: NSResponder? = hit?.nextResponder
		while let next = responder, chain.count < 12 {
			chain.append(String(describing: type(of: next)))
			responder = next.nextResponder
		}
		detail += " chain=" + chain.joined(separator: ">")
		func event(_ type: NSEvent.EventType, count: Int) -> NSEvent? {
			NSEvent.mouseEvent(
				with: type, location: point, modifierFlags: [],
				timestamp: ProcessInfo.processInfo.systemUptime,
				windowNumber: window.windowNumber, context: nil,
				eventNumber: 0, clickCount: count, pressure: type == .leftMouseDown ? 1 : 0
			)
		}
		var sequence: [(NSEvent.EventType, Int)] = [(.leftMouseDown, 1), (.leftMouseUp, 1)]
		if case .runControlClear = place {} else {
			sequence += [(.leftMouseDown, 2), (.leftMouseUp, 2)]
		}
		let events = sequence.compactMap { event($0.0, count: $0.1) }
		guard events.count == sequence.count else { return "no event" }
		NSApp.activate(ignoringOtherApps: true)
		window.makeKeyAndOrderFront(nil)
		for event in events { NSApp.postEvent(event, atStart: false) }
		return "at (\(Int(point.x)),\(Int(point.y))) on \(under)\(detail)"
	}
}
