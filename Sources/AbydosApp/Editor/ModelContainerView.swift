import AppKit
import GoSTL

/// A pane that does not pay for what is in it until somebody stops on it.
///
/// The guard 0483 needed and 0499 needs again, and it is not about 3D at all:
/// arrowing down a directory gives each file a provisional tab that lives for as
/// long as the next keypress takes, and a session restored with twenty model
/// tabs lays out only the one in front. Anything expensive keyed off a pane
/// being *made* is paid for all of them; keyed off a pane being *shown*, and
/// cancelled when it leaves, it is paid for the one somebody stopped at.
///
/// What it costs to be here rather than in `ModelContainerView`, where it was:
/// nothing. What it buys is that a Cadova pane starting a package build gets the
/// same rule as an OpenSCAD pane starting a render, from the same code, rather
/// than from a second copy of it that drifts.
class DelayedPaneView: ColoredView {
	/// How long this pane must have been on screen before `whenShown` runs.
	var startAfter: TimeInterval = 0

	/// Run once, `startAfter` seconds after this pane is first in a window, and
	/// not at all if it leaves before then.
	var whenShown: (() -> Void)?

	private var pending: DispatchWorkItem?

	/// Built on being *shown*, not on being made.
	///
	/// Which is the whole guard. A provisional tab is created, activated and then
	/// replaced in place by the next row of the tree, so a pane that leaves the
	/// window before its delay is up has its work cancelled and does nothing; and
	/// a session restored with twenty model tabs lays out only the one in front,
	/// so the other nineteen cost nothing at all until somebody clicks them.
	/// Keying off creation instead would have paid for all twenty at once, on the
	/// main actor, before the window was even up.
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		guard window != nil else {
			pending?.cancel()
			pending = nil
			return
		}
		guard whenShown != nil, pending == nil else { return }
		let work = DispatchWorkItem { [weak self] in
			guard let self, let run = self.whenShown else { return }
			// Cleared first: this happens once, and a pane may be shown and hidden
			// many times.
			self.whenShown = nil
			self.pending = nil
			run()
		}
		pending = work
		DispatchQueue.main.asyncAfter(deadline: .now() + startAfter, execute: work)
	}

	deinit { pending?.cancel() }
}

/// Holds the 3D preview, sized by hand.
///
/// The preview is a SwiftUI view, and letting it size itself through Auto
/// Layout puts it in the window's constraint pass — where re-parenting it, as
/// splitting the editor does, raises.
final class ModelContainerView: DelayedPaneView, SnapshotDrawable {
	/// GoSTL's way of rendering the current scene into an image.
	///
	/// The viewer draws through Metal, and a window capture walks the view
	/// tree — where a Metal layer's contents are not. Without this the model
	/// photographs as an empty rectangle.
	var snapshot: ContentView.EmbeddingOptions.SnapshotProvider?

	/// Builds the viewer, and is thrown away once it has.
	var makeViewer: (() -> NSView)? {
		didSet {
			guard makeViewer != nil else { return }
			whenShown = { [weak self] in
				guard let self, let make = self.makeViewer else { return }
				self.makeViewer = nil
				let viewer = make()
				viewer.frame = self.bounds
				self.addSubview(viewer)
			}
		}
	}

	override func layout() {
		super.layout()
		for subview in subviews { subview.frame = bounds }
	}

	func snapshotImage(size: CGSize) -> CGImage? { snapshot?(size) }
}
