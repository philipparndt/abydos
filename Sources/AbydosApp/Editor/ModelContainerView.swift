import AppKit
import AbydosKit
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

	/// The model this pane is for, so a render that kills the app can be blamed
	/// on something in particular rather than on 3D in general.
	var modelPath: String?

	/// Builds the viewer, and is thrown away once it has.
	var makeViewer: (() -> NSView)? {
		didSet {
			guard makeViewer != nil else { return }
			whenShown = { [weak self] in
				guard let self, let make = self.makeViewer else { return }
				self.makeViewer = nil

				// The one model the last run did not survive is not rendered
				// again without being asked for. See `ViewerGuard`: a trap inside
				// the viewer is the end of the process, and a session that
				// restores the tab which caused it makes the app unstartable.
				let path = self.modelPath ?? ""
				if ViewerGuard.isBlamed(path) {
					self.refuse(path: path, make: make)
					return
				}

				ViewerGuard.begin(path)
				let viewer = make()
				viewer.frame = self.bounds
				self.addSubview(viewer)
				// Cleared only once the app is plainly still here. Clearing it as
				// soon as `make()` returned would clear it before the failure:
				// the abort happens in the first layout pass, which is after this.
				DispatchQueue.main.asyncAfter(deadline: .now() + ViewerGuard.settleDelay) {
					guard ViewerGuard.isBlamed(path) else { return }
					ViewerGuard.settled()
				}
			}
		}
	}

	/// Says why the model is not on screen, and offers to try it anyway.
	///
	/// An offer rather than a refusal: the app may have died for a reason that
	/// has since been fixed — a toolchain installed, a dependency updated — and
	/// the only way anybody finds that out is by asking again.
	private func refuse(path: String, make: @escaping () -> NSView) {
		let name = (path as NSString).lastPathComponent
		let label = NSTextField(wrappingLabelWithString:
			"Rendering \(name) ended the last session.\n"
			+ "It has not been opened again in case it does so twice.")
		label.font = Theme.current.uiFont(12)
		label.textColor = Theme.current.gitIgnored
		label.alignment = .center
		label.isSelectable = false

		let button = NSButton(title: "Show anyway", target: self, action: #selector(showAnyway))
		button.bezelStyle = .rounded
		blamedBuild = make
		blamedPath = path

		let stack = NSStackView(views: [label, button])
		stack.orientation = .vertical
		stack.alignment = .centerX
		stack.spacing = Theme.current.scaled(12)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
			stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
		])
		notice = stack
	}

	private var blamedBuild: (() -> NSView)?
	private var blamedPath: String?
	private weak var notice: NSView?

	@objc private func showAnyway() {
		guard let make = blamedBuild, let path = blamedPath else { return }
		blamedBuild = nil
		notice?.removeFromSuperview()
		// Forgiven before the attempt, not after: if it aborts again the note is
		// rewritten by `begin` below, and if it works there was nothing to
		// forgive. Leaving it would refuse a model that has just been shown.
		ViewerGuard.settled()
		ViewerGuard.begin(path)
		let viewer = make()
		viewer.frame = bounds
		addSubview(viewer)
		DispatchQueue.main.asyncAfter(deadline: .now() + ViewerGuard.settleDelay) {
			guard ViewerGuard.isBlamed(path) else { return }
			ViewerGuard.settled()
		}
	}

	override func layout() {
		super.layout()
		for subview in subviews { subview.frame = bounds }
	}

	func snapshotImage(size: CGSize) -> CGImage? { snapshot?(size) }
}
