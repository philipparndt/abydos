import AppKit
import AbydosKit

/// A control that re-reads the theme when the theme changes.
///
/// **The whole library is this one method and the promise that it is called.**
/// Everything in this app that follows the zoom does so because it reads
/// `Theme.current` where it draws, and everything that does not follow the zoom
/// is something that read it once and kept the answer. A control that has to
/// keep an answer — a font on a cell, a height in a constraint — implements
/// this, and the registry sees that it is asked again.
protocol ScaleFollowing: AnyObject {
	/// Take the font, the metrics and the colours again.
	func applyTheme()
}

/// Every live control that follows the scale, and the one place they are told.
///
/// **Why a registry rather than an observer per control.** Seventy observers on
/// one notification is not expensive, but the order they fire in is
/// unspecified, and an observer outliving its control is a class of crash this
/// app has had. A registry of weak boxes cannot leak an observer, cannot fire
/// into a dead control, and can be *asked what it holds* — which is what makes
/// a driven run able to say "this pane has eleven controls and all of them
/// followed" instead of comparing two screenshots by eye.
///
/// **Why not each pane's `applySettings()`.** That is what the app did, and the
/// seven reports of 2026-09-01 are the panes that forgot. A mechanism whose
/// correctness depends on remembering is the thing being replaced, so the
/// library does not offer a way to opt out of it: registering happens in the
/// control's own initialiser and there is nothing for a caller to leave out.
enum ScaledControls {
	/// A weak hold, so a pane that goes away takes its controls with it and
	/// leaves nothing here but an empty box to be swept.
	private struct Box {
		weak var control: AnyObject?
	}

	private static var boxes: [Box] = []
	private static var isListening = false

	/// Adds a control, and starts listening the first time there is one to
	/// listen for.
	static func register(_ control: ScaleFollowing) {
		startListening()
		boxes.append(Box(control: control))
	}

	/// Tells every live control to take its metrics again, and forgets the
	/// dead ones.
	///
	/// Swept here rather than on a timer: this runs when somebody changes the
	/// zoom or the palette, which is exactly as often as the list needs
	/// tidying and never in the middle of anything.
	static func reapply() {
		var living: [Box] = []
		living.reserveCapacity(boxes.count)
		for box in boxes {
			guard let control = box.control else { continue }
			(control as? ScaleFollowing)?.applyTheme()
			living.append(box)
		}
		boxes = living
	}

	/// How many live controls are registered, for a driven run to report.
	static var countForTesting: Int {
		boxes.reduce(0) { $0 + (($1.control == nil) ? 0 : 1) }
	}

	private static func startListening() {
		guard !isListening else { return }
		isListening = true
		NotificationCenter.default.addObserver(
			forName: .abydosSettingsChanged, object: nil, queue: .main
		) { _ in
			// Already on the main queue by the queue argument, and every
			// control here is a view: nothing in this walk touches anything a
			// background thread can see.
			MainActor.assumeIsolated { reapply() }
		}
	}
}
