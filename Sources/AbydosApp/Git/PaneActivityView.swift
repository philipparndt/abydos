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
/// Deliberately not a modal, and indeterminate by default: `git status` does
/// not say how far through the work tree it is, so for one repository the
/// honest shape is "still going".
///
/// **A queue of repositories is the case where there is a total.** An estate
/// sweep asks two hundred of them and knows the number before it starts, and
/// the answer somebody wants while a cold one takes a minute and a half is how
/// many are left. `count(_:of:)` turns the spinner into a bar and says so; a
/// pane that never calls it is the pane it always was.
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
	}

	/// **Centred on what can be seen, not on what the view is.**
	///
	/// Constraints could say "the middle of this view", and that is the wrong
	/// middle whenever the view is larger than the part of it on screen: a page
	/// inside a scroll view, or one whose frame the editor has made wider than
	/// the window. The spinner then sits somewhere off to one side of the empty
	/// space it is meant to be explaining — which is exactly what a pull request
	/// page did while it waited for GitHub.
	///
	/// `visibleRect` is the answer to that question and it changes as the pane
	/// is scrolled or resized, so this is laid out by hand rather than pinned.
	/// The rounded panel the spinner and its words sit on.
	///
	/// **Because the pane underneath is not empty.** The view covers the whole
	/// pane so that what is stale is hidden, and where the wait is short — a
	/// fetch on a small repository — what is under it is a list of branches
	/// that reads straight through the words. `Fetching…` over a branch name is
	/// two sentences in the same place.
	///
	/// A panel rather than a wash over everything: dimming the pane would say
	/// the whole list is unavailable, which is not what waiting for a fetch
	/// means. This says *here is the thing that is happening*, and leaves the
	/// list legible around it.
	private func drawPanel(around content: NSRect) {
		let padding = Theme.current.scaled(14)
		let panel = content.insetBy(dx: -padding, dy: -padding)
		let radius = Theme.current.scaled(10)
		let path = NSBezierPath(roundedRect: panel, xRadius: radius, yRadius: radius)
		// The pane's own surface at most of its strength, so it reads as
		// something laid over the list rather than a hole cut in it.
		Theme.current.sidebarBackground.withAlphaComponent(0.92).setFill()
		path.fill()
		Theme.current.separator.setStroke()
		path.lineWidth = 1
		path.stroke()
	}

	override func draw(_ dirtyRect: NSRect) {
		guard !panelFrame.isEmpty else { return }
		drawPanel(around: panelFrame)
	}

	/// What the panel is drawn around, worked out in `layout` where the two
	/// pieces are placed.
	private var panelFrame: NSRect = .zero

	override func layout() {
		super.layout()

		// An empty visible rect — a view not on screen yet — falls back to the
		// bounds, which is the same answer whenever the two agree.
		let area = visibleRect.isEmpty ? bounds : visibleRect
		// A determinate bar's `fittingSize` has no width in it, so the width
		// set when the bar was made is the one to lay out against.
		var wheelSize = wheel.fittingSize
		if !wheel.isIndeterminate {
			wheelSize.width = min(wheel.frame.width, max(0, area.width - Theme.current.scaled(24)))
		}
		let gap = Theme.current.scaled(8)
		let captionSize = caption.fittingSize
		let stack = wheelSize.height + gap + captionSize.height

		let top = area.midY - stack / 2
		wheel.frame = NSRect(
			x: area.midX - wheelSize.width / 2,
			y: top,
			width: wheelSize.width,
			height: wheelSize.height
		)
		// The caption gets the width of the area, so a long one wraps rather
		// than running out of the pane.
		let inset = Theme.current.scaled(12)
		caption.frame = NSRect(
			x: area.minX + inset,
			y: top + wheelSize.height + gap,
			width: max(0, area.width - inset * 2),
			height: captionSize.height
		)

		// Around the two of them, and no wider than the words actually take:
		// a panel the width of the pane would be the wash this is not.
		let width = max(wheelSize.width, min(captionSize.width, area.width - inset * 2))
		panelFrame = NSRect(
			x: (area.midX - width / 2).rounded(),
			y: top.rounded(),
			width: width.rounded(),
			height: stack.rounded()
		)
		needsDisplay = true
	}

	override var isFlipped: Bool { true }

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	/// Pins one over a pane and starts it turning.
	///
	/// The whole pane, not a corner of it: what is underneath is either empty or
	/// stale, and covering it is the point.
	static func install(over pane: NSView, message: String) -> PaneActivityView {
		let view = PaneActivityView(message: message)
		view.translatesAutoresizingMaskIntoConstraints = false
		// Above whatever is already there: a pane that has been built has its
		// own subviews, and a spinner behind them explains nothing.
		pane.addSubview(view, positioned: .above, relativeTo: nil)
		NSLayoutConstraint.activate([
			view.topAnchor.constraint(equalTo: pane.topAnchor),
			view.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
			view.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
		])
		view.wheel.startAnimation(nil)
		return view
	}

	/// How far through a queue of work this is.
	///
	/// The first call turns the spinner into a determinate bar; later ones move
	/// it. The numbers are the caller's own arithmetic, and so are the words:
	/// this view knows what a bar is and nothing about what is being counted,
	/// which is why `saying` is a finished sentence rather than a noun to be
	/// pasted into one here.
	///
	/// A total of one is left as a spinner: "1 of 1" is a bar that fills in one
	/// step and tells nobody anything.
	func count(_ done: Int, of total: Int, saying: String) {
		guard total > 1 else { return }
		if wheel.isIndeterminate {
			wheel.stopAnimation(nil)
			wheel.isIndeterminate = false
			wheel.style = .bar
			wheel.controlSize = .small
			wheel.minValue = 0
			wheel.maxValue = Double(total)
			// A bar has no width of its own to fit to, unlike a spinner.
			wheel.frame.size.width = Theme.current.scaled(160)
		}
		wheel.maxValue = Double(total)
		wheel.doubleValue = Double(min(done, total))
		caption.stringValue = saying
		needsLayout = true
	}

	/// The words and how far the bar has gone, for a driven run.
	var reportForTesting: String {
		let shape = wheel.isIndeterminate
			? "spinner"
			: "bar \(Int(wheel.doubleValue)) of \(Int(wheel.maxValue))"
		return "\(shape) · \(caption.stringValue)"
	}

	/// Takes it down. Stopping the animation first, because a `NSProgressIndicator`
	/// left animating keeps a timer alive after the view has gone.
	func finish() {
		wheel.stopAnimation(nil)
		removeFromSuperview()
	}
}
