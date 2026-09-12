import AppKit
import AbydosKit

/// A hairline under a pane's header, sweeping while the pane waits.
///
/// Every pane asks something before it can draw — git for its rows, GitHub
/// for its list, a compiler for a model — and on a large repository or a cold
/// build that takes a moment. What the panes used to show in that moment was
/// a rounded panel in the middle with the system spinner in it, which said
/// the pane was empty by covering the pane, and covered the rows of a pane
/// that was not empty: a refresh of the pull-request list hid the very list
/// being refreshed. Reported 2026-09-11; five treatments were mocked and the
/// maintainer chose this one, *"as this works best when there is already text
/// in the panel."*
///
/// So: a two-point strip across the pane at the seam under its header, with a
/// run of colour a third of the width long sweeping left to right. Nothing is
/// dimmed and nothing framed; rows already on screen stay on screen. A pane
/// with nothing beneath the strip says what it is waiting for, small and
/// centred, and past five seconds adds that it is still waiting. A pane with
/// rows beneath says nothing but the sweep — there is nowhere to say it that
/// is not over the rows.
///
/// **One view for every pane**, as it was: the git panes, the pull-request
/// list and page, the sidebar's tool switch, the project tree, the Backlog
/// pane and the previews all install this and nothing else, so what waiting
/// looks like is decided once. The estate sweep, which knows how many
/// repositories it has to read, gets the same strip filling from the left.
///
/// Clicks go through it. The old panel took them, which was right for a view
/// that covered stale rows and is wrong for a strip over live ones.
final class PaneActivityView: NSView {
	/// The header the strip sits under, when the pane has one. Its bottom edge
	/// is re-read at every layout, so a header that grows with the zoom moves
	/// the strip with it.
	private weak var header: NSView?
	/// What is being waited for, or nil for a strip that says nothing.
	private var message: String?
	/// Whether there is room for the sentence: nothing beneath the strip.
	private let paneIsEmpty: Bool

	private let caption = NSTextField(labelWithString: "")
	/// Where the run is along the strip, 0…1 and past either end so it enters
	/// and leaves rather than appearing.
	private var phase: CGFloat = 0
	/// A determinate fill instead of the sweep, once `count` has been called.
	private var filled: (done: Int, total: Int)?
	private var sweep: Timer?
	private var stillWaiting: DispatchWorkItem?
	private var stripFrame: NSRect = .zero

	/// How long a wait is before the sentence says so.
	static let longWait: TimeInterval = 5

	/// `--hold-activity`: `finish()` leaves every strip up so a wait of a tenth
	/// of a second can be captured and reported.
	static var holdsForTesting = false
	/// Every strip alive, for `reportAllForTesting`.
	private static let live = NSHashTable<PaneActivityView>.weakObjects()

	private init(message: String?, header: NSView?, paneIsEmpty: Bool) {
		self.message = message
		self.header = header
		self.paneIsEmpty = paneIsEmpty
		super.init(frame: .zero)

		caption.font = Theme.current.uiFont(11)
		caption.textColor = Theme.current.gitIgnored
		caption.alignment = .center
		caption.isSelectable = false
		caption.translatesAutoresizingMaskIntoConstraints = false
		caption.isHidden = !(paneIsEmpty && message != nil)
		caption.stringValue = message ?? ""
		addSubview(caption)
		Self.live.add(self)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	deinit { sweep?.invalidate() }

	override var isFlipped: Bool { true }

	/// The strip is over the pane and must not be in its way.
	override func hitTest(_ point: NSPoint) -> NSView? { nil }

	/// Pins one over a pane and starts the sweep.
	///
	/// - Parameters:
	///   - message: what is being waited for, in a few words — "Reading
	///     branches…" is something to wait for, "Loading…" is not. Nil for a
	///     pane that says it in a sentence of its own, as the previews do.
	///   - header: the view the strip sits under; nil puts it at the pane's top
	///     edge, which is right for a page and a preview that have no header.
	///   - paneIsEmpty: whether there is nothing beneath the strip, and so room
	///     for the sentence. False for a refresh with rows on screen.
	@discardableResult
	static func install(
		over pane: NSView, message: String? = nil, below header: NSView? = nil, paneIsEmpty: Bool = true
	) -> PaneActivityView {
		// A held strip from an earlier wait would otherwise stack under this
		// one and be reported twice: the Backlog pane reloads twice on opening.
		if holdsForTesting {
			for old in pane.subviews.compactMap({ $0 as? PaneActivityView }) { old.removeFromSuperview() }
		}
		let view = PaneActivityView(message: message, header: header, paneIsEmpty: paneIsEmpty)
		view.translatesAutoresizingMaskIntoConstraints = false
		// Above whatever is already there: a strip behind the rows is no strip.
		pane.addSubview(view, positioned: .above, relativeTo: nil)
		NSLayoutConstraint.activate([
			view.topAnchor.constraint(equalTo: pane.topAnchor),
			view.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
			view.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
		])
		view.startSweeping()
		view.armStillWaiting()
		return view
	}

	/// A change of sentence, for a wait with more than one step in it — the
	/// pull-request list looks for `gh` and then asks it.
	func say(_ sentence: String) {
		message = sentence
		stillWaiting?.cancel()
		caption.stringValue = sentence
		armStillWaiting()
		needsLayout = true
	}

	/// How far through a queue of work this is.
	///
	/// The first call stops the sweep and fills the strip from the left; later
	/// ones move the fill. The numbers are the caller's own arithmetic, and so
	/// are the words: this view knows what a strip is and nothing about what is
	/// being counted, which is why `saying` is a finished sentence.
	///
	/// A total of one is left sweeping: "1 of 1" fills in one step and tells
	/// nobody anything.
	func count(_ done: Int, of total: Int, saying: String) {
		guard total > 1 else { return }
		filled = (min(done, total), total)
		sweep?.invalidate()
		sweep = nil
		message = saying
		caption.stringValue = saying
		needsDisplay = true
	}

	/// Takes it down, unless a run has asked for it to stay.
	func finish() {
		stillWaiting?.cancel()
		guard !Self.holdsForTesting else { return }
		sweep?.invalidate()
		sweep = nil
		removeFromSuperview()
	}

	// MARK: - Drawing

	private func startSweeping() {
		phase = -0.4
		let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
			// On the main run loop by construction; every view here is main's.
			MainActor.assumeIsolated { self?.advanceSweep() }
		}
		RunLoop.main.add(timer, forMode: .common)
		sweep = timer
	}

	/// One frame of the run: 1.4 s from off the left edge to off the right.
	private func advanceSweep() {
		guard filled == nil else { return }
		phase += 1.45 / (1.4 * 30)
		if phase > 1.05 { phase = -0.4 }
		// The old strip and the new: the seam can have moved since the last
		// frame — see `seam()`.
		setNeedsDisplay(stripFrame.union(seam()).insetBy(dx: -2, dy: -2))
	}

	/// Where the strip is, asked afresh every time it matters.
	///
	/// **Not kept from `layout()`.** The project tree installs its strip as the
	/// project loads, before its header has been given a height, and nothing
	/// lays this view out again when the header is: the first tree captures
	/// reported the strip at the header's *top*, which is where a
	/// zero-height header's bottom was. So the seam is read at every draw and
	/// every frame of the sweep, which is one rectangle conversion.
	private func seam() -> NSRect {
		let bottom = header.map { convert($0.bounds, from: $0).maxY } ?? 0
		let height = max(1, Theme.current.scaled(2).rounded())
		return NSRect(x: 0, y: bottom.rounded(), width: bounds.width, height: height)
	}

	private func armStillWaiting() {
		guard paneIsEmpty, message != nil else { return }
		let work = DispatchWorkItem { [weak self] in
			guard let self, let message = self.message else { return }
			self.caption.stringValue = message + " · still waiting"
			self.needsLayout = true
		}
		stillWaiting = work
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.longWait, execute: work)
	}

	override func layout() {
		super.layout()
		stripFrame = seam()

		// The sentence centred in what can be seen beneath the strip — the
		// visible rect, not the bounds, for a page inside a scroll view.
		let area = visibleRect.isEmpty ? bounds : visibleRect
		let inset = Theme.current.scaled(12)
		let size = caption.fittingSize
		caption.frame = NSRect(
			x: area.minX + inset,
			y: (max(area.minY, stripFrame.maxY) + area.maxY) / 2 - size.height / 2,
			width: max(0, area.width - inset * 2),
			height: size.height
		)
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {
		let current = seam()
		if current != stripFrame {
			stripFrame = current
			// The sentence is placed against the strip, so it moves too.
			needsLayout = true
		}
		guard !stripFrame.isEmpty else { return }
		Theme.current.separator.setFill()
		stripFrame.fill()

		let ink = Theme.current.selectionActive
		let run: NSRect
		if let filled {
			let fraction = CGFloat(filled.done) / CGFloat(filled.total)
			run = NSRect(x: 0, y: stripFrame.minY, width: (stripFrame.width * fraction).rounded(), height: stripFrame.height)
		} else {
			let width = (stripFrame.width / 3).rounded()
			run = NSRect(x: (stripFrame.width * phase).rounded(), y: stripFrame.minY, width: width, height: stripFrame.height)
		}
		ink.setFill()
		NSBezierPath(roundedRect: run.intersection(stripFrame), xRadius: 1, yRadius: 1).fill()
	}

	// MARK: - Driving

	/// Where the strip is and what it says, for a driven run: the seam can be
	/// checked against the header's bottom in numbers rather than by eye.
	var reportForTesting: String {
		superview?.layoutSubtreeIfNeeded()
		stripFrame = seam()
		let shape = filled.map { "filled \($0.done) of \($0.total)" } ?? "sweeping"
		let seam = header.map { String(describing: type(of: $0)) } ?? "top"
		let pane = superview.map { String(describing: type(of: $0)) } ?? "nowhere"
		return "\(pane): strip y=\(Int(stripFrame.minY)) height=\(Int(stripFrame.height)) "
			+ "width=\(Int(stripFrame.width)) under=\(seam) \(shape) "
			+ "saying=\(caption.isHidden ? "nothing" : caption.stringValue)"
	}

	/// Every strip alive, one line each.
	static func reportAllForTesting() -> String {
		let strips = live.allObjects.filter { $0.superview != nil }
		guard !strips.isEmpty else { return "ACTIVITY: none" }
		return "ACTIVITY:\n" + strips.map { "  " + $0.reportForTesting }.joined(separator: "\n")
	}
}
