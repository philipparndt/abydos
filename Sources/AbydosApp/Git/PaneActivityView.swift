import AppKit
import AbydosKit

/// A spinner and a line of text, over a pane that has nothing to show yet.
///
/// Every git pane asks git a question before it can draw anything, and on a
/// large repository some of those questions take a moment. What they used to do
/// in that moment was nothing at all: the sidebar kept the previous tool on
/// screen, or showed an empty pane, and there was no way to tell a slow answer
/// from a broken one. Somebody opening the changes view on a repository with a
/// hundred thousand untracked files saw an empty box and clicked again.
///
/// Deliberately not a modal or a progress bar. There is no total to count
/// against — `git status` does not say how far through the work tree it is — so
/// the honest shape is "still going", which is what an indeterminate spinner
/// says.
final class PaneActivityView: NSView {
	private let wheel = NSProgressIndicator()
	private let caption: NSTextField

	/// - Parameter message: what is being waited for, in a few words. Named
	///   after the question rather than the mechanism: "Reading branches…" is
	///   something to wait for, "Loading…" is not.
	init(message: String) {
		caption = NSTextField(labelWithString: message)
		super.init(frame: .zero)

		wheel.style = .spinning
		wheel.controlSize = .small
		wheel.isIndeterminate = true
		wheel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(wheel)

		caption.font = Theme.current.uiFont(11)
		caption.textColor = Theme.current.gitIgnored
		caption.alignment = .center
		caption.isSelectable = false
		caption.translatesAutoresizingMaskIntoConstraints = false
		addSubview(caption)

		NSLayoutConstraint.activate([
			wheel.centerXAnchor.constraint(equalTo: centerXAnchor),
			// Above the middle rather than in it: the caption sits under the
			// spinner and the pair should read as centred, not the spinner.
			wheel.centerYAnchor.constraint(
				equalTo: centerYAnchor, constant: -Theme.current.scaled(12)
			),
			caption.topAnchor.constraint(
				equalTo: wheel.bottomAnchor, constant: Theme.current.scaled(8)
			),
			caption.leadingAnchor.constraint(
				equalTo: leadingAnchor, constant: Theme.current.scaled(12)
			),
			caption.trailingAnchor.constraint(
				equalTo: trailingAnchor, constant: -Theme.current.scaled(12)
			),
		])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	/// Pins one over a pane and starts it turning.
	///
	/// The whole pane, not a corner of it: what is underneath is either empty or
	/// stale, and covering it is the point.
	static func install(over pane: NSView, message: String) -> PaneActivityView {
		let view = PaneActivityView(message: message)
		view.translatesAutoresizingMaskIntoConstraints = false
		pane.addSubview(view)
		NSLayoutConstraint.activate([
			view.topAnchor.constraint(equalTo: pane.topAnchor),
			view.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
			view.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
		])
		view.wheel.startAnimation(nil)
		return view
	}

	/// Takes it down. Stopping the animation first, because a `NSProgressIndicator`
	/// left animating keeps a timer alive after the view has gone.
	func finish() {
		wheel.stopAnimation(nil)
		removeFromSuperview()
	}
}
