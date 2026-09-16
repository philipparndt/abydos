import Foundation

/// Whether a pane's first render has landed, and what is waiting for it.
///
/// A driven run asks a pane to do something "once it has rendered", and a
/// render that fails settles too — there is nothing more coming, and a driver
/// waiting for a sound that will never arrive is a run that times out saying
/// nothing. Its own type because it is two lines of state and every reader of
/// the pane has to skip past them otherwise.
@MainActor
final class SongSettled {
	private var landed = false
	private var waiting: [() -> Void] = []

	/// Nothing more is coming: whatever waited runs now.
	func settle() {
		landed = true
		let waited = waiting
		waiting = []
		waited.forEach { $0() }
	}

	/// The pane is starting again, on another song.
	func begin() {
		landed = false
	}

	func whenSettled(_ then: @escaping () -> Void) {
		if landed { then() } else { waiting.append(then) }
	}
}
