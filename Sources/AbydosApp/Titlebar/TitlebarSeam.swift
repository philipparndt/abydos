import AppKit

/// The line under the titlebar.
///
/// It carries one thing: whether something is running. It used to be tempting
/// to give it the project's colour as well, but the badge palette contains a
/// green and a red, so one project would have sat there looking permanently
/// built and another permanently broken. A line that means two things means
/// neither.
///
/// Having only the one meaning is what lets it be loud about it: the coloured
/// part is absent when nothing is happening, so its appearance alone is the
/// signal, and it can be red without that reading as somebody's project colour.
final class TitlebarSeam: NSView {
	enum State: Equatable {
		case idle
		case running
		/// Held until the next run starts: a failure scrolled past is still a
		/// failure.
		case failed
	}

	private(set) var state: State = .idle
	/// How far along the sweep is, 0...1, for a run whose progress is unknown —
	/// which is every run, until something starts reporting one.
	private var phase: CGFloat = 0
	private var timer: Timer?

	/// Tall enough for the run line; the track sits inside it.
	static var height: CGFloat { Theme.current.scaled(2) }

	override var isFlipped: Bool { true }

	deinit { timer?.invalidate() }

	func set(_ state: State) {
		guard state != self.state else { return }
		self.state = state
		needsDisplay = true

		if state == .running {
			startSweeping()
		} else {
			timer?.invalidate()
			timer = nil
			phase = 0
		}
	}

	/// A moving segment rather than a filled bar: nothing here knows how far
	/// along a build is, and a bar that fills at a made-up rate is a lie told
	/// slowly.
	private func startSweeping() {
		guard timer == nil else { return }
		// Somebody who has asked for less movement gets a plain line instead.
		guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

		let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
			guard let self else { return }
			phase += 0.012
			if phase > 1 { phase -= 1 }
			needsDisplay = true
		}
		// .common so it keeps moving while a menu is down or the window is being
		// dragged, which is exactly when somebody is waiting for a build.
		RunLoop.main.add(timer, forMode: .common)
		self.timer = timer
	}

	override func draw(_ dirtyRect: NSRect) {
		// The track: the boundary between the titlebar and what is under it,
		// which this window needs drawn whatever is running.
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

		switch state {
		case .idle:
			return
		case .failed:
			Theme.current.gitConflict.setFill()
			bounds.fill()
		case .running:
			Theme.current.gitAdded.setFill()
			guard timer != nil else {
				// Reduced motion: the whole width, held still.
				bounds.fill()
				return
			}
			// The segment runs off one end and back on at the other, so the
			// wrap is a movement rather than a jump.
			let width = max(bounds.width * 0.22, Theme.current.scaled(60))
			let x = phase * (bounds.width + width) - width
			NSRect(x: x, y: 0, width: width, height: bounds.height).fill()
		}
	}
}
