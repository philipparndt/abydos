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
		/// A launch that is being arranged rather than one that is running:
		/// waiting on a language server for a classpath, on a port, on an import.
		///
		/// **The one state that moves**, and the exception is narrow on purpose.
		/// The note below still holds for a run: a bar that crawls for as long as
		/// a build takes is motion in the corner of the eye that says nothing. A
		/// wait on something that has not answered yet is different — it is
		/// bounded by a deadline, it is the case where the alternative reading is
		/// "this has hung", and it is the one somebody asked to be able to tell
		/// apart from a run.
		case preparing
		case running
		/// Held until the next run starts: a failure scrolled past is still a
		/// failure.
		case failed
	}

	private(set) var state: State = .idle

	/// Thick enough to be seen from the other side of the room, which is the
	/// whole point of putting it across the window rather than in the strip.
	static var height: CGFloat { Theme.current.scaled(4) }

	override var isFlipped: Bool { true }

	func set(_ state: State) {
		guard state != self.state else { return }
		self.state = state
		if state == .preparing { startSweep() } else { stopSweep() }
		needsDisplay = true
	}

	override func layout() {
		super.layout()
		sweep?.frame = bounds
	}

	/// The moving highlight, as a layer animation.
	///
	/// On the layer rather than on a timer that calls `needsDisplay`: a titlebar
	/// redrawing itself twenty times a second for the length of an import is the
	/// cost this view was written to avoid, and the compositor does this one for
	/// free.
	private var sweep: CAGradientLayer?

	private func startSweep() {
		// Somebody who has asked the system for less motion has asked for this
		// too. The colour still changes, so the state is still legible.
		guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
		guard sweep == nil, let layer else { return }

		// **Green travelling along the background, not a highlight over green.**
		// The first attempt was green with a lighter green moving over it, and at
		// four points high against a bright colour the difference was invisible —
		// the state read as "running" with something faintly happening. Inverted,
		// the moving part is the only coloured thing in the strip, so the motion
		// is the signal rather than a modulation of it.
		let track = Theme.current.sidebarBackground
		let pulse = Theme.current.gitAdded
		let gradient = CAGradientLayer()
		gradient.frame = bounds
		gradient.colors = [
			track.cgColor, pulse.cgColor, pulse.cgColor, track.cgColor,
		]
		gradient.startPoint = CGPoint(x: 0, y: 0.5)
		gradient.endPoint = CGPoint(x: 1, y: 0.5)
		// A band with a flat middle rather than a spike, so it reads as an object
		// moving rather than as a flicker.
		gradient.locations = [0, 0.10, 0.22, 0.32]

		let move = CABasicAnimation(keyPath: "locations")
		move.fromValue = [-0.32, -0.22, -0.10, 0]
		move.toValue = [1, 1.10, 1.22, 1.32]
		move.duration = 1.8
		move.repeatCount = .infinity
		gradient.add(move, forKey: "sweep")

		layer.addSublayer(gradient)
		sweep = gradient
	}

	private func stopSweep() {
		sweep?.removeFromSuperlayer()
		sweep = nil
	}

	override func draw(_ dirtyRect: NSRect) {
		// The track: the boundary between the titlebar and what is under it,
		// which this window needs drawn whatever is running.
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

		// Held still. A bar that crawls says a percentage nothing here knows,
		// and a titlebar is the wrong place for something that moves in the
		// corner of the eye for as long as a build takes.
		switch state {
		case .idle:
			return
		case .preparing:
			// Under the sweep: the track. With motion reduced there is no sweep, so
			// the strip is green instead — the state still has to be legible when
			// nothing moves.
			let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
			(reduced ? Theme.current.gitAdded : Theme.current.sidebarBackground).setFill()
			bounds.fill()
		case .running:
			Theme.current.gitAdded.setFill()
			bounds.fill()
		case .failed:
			Theme.current.gitConflict.setFill()
			bounds.fill()
		}
	}
}
