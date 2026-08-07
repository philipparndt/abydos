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

	/// Thick enough to be seen from the other side of the room, which is the
	/// whole point of putting it across the window rather than in the strip.
	static var height: CGFloat { Theme.current.scaled(4) }

	override var isFlipped: Bool { true }

	func set(_ state: State) {
		guard state != self.state else { return }
		self.state = state
		needsDisplay = true
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
		case .running:
			Theme.current.gitAdded.setFill()
			bounds.fill()
		case .failed:
			Theme.current.gitConflict.setFill()
			bounds.fill()
		}
	}
}
