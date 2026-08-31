import AppKit
import AbydosKit

/// A commit: what it did, who did it, and when.
final class CommitRowView: NSView {
	private let commit: GitCommit
	private let isUnpushed: Bool
	/// The upstream has this commit and the scoped ref does not: on the page
	/// before a pull, not of the branch yet.
	private let isRemoteOnly: Bool
	/// Lanes whose segment at this row belongs to an unpulled commit's line to
	/// its parent, so the line fades whole rather than only inside the rows
	/// whose commits are unpulled.
	private let fadedLanes: Set<Int>
	/// Where this commit sits in the drawing, and what runs past it.
	private let graph: GitGraph.Row?
	/// Whether the branch this merge brought in is folded away.
	private let isCollapsed: Bool
	/// Whether there is room for who made it and when.
	private let showsAuthor: Bool
	override var isFlipped: Bool { true }

	/// Pressed to fold the branch this merge brought in.
	var onFold: (() -> Void)?

	init(
		commit: GitCommit,
		isUnpushed: Bool = false,
		isRemoteOnly: Bool = false,
		fadedLanes: Set<Int> = [],
		graph: GitGraph.Row? = nil,
		isCollapsed: Bool = false,
		showsAuthor: Bool = false
	) {
		self.commit = commit
		self.isUnpushed = isUnpushed
		self.isRemoteOnly = isRemoteOnly
		self.fadedLanes = fadedLanes
		self.graph = graph
		self.isCollapsed = isCollapsed
		self.showsAuthor = showsAuthor
		super.init(frame: .zero)
		var lines = [commit.shortHash, commit.subject, commit.body]
		if isUnpushed { lines.append("Not pushed yet") }
		if isRemoteOnly { lines.append("Not pulled yet") }
		toolTip = lines
			.filter { !$0.isEmpty }
			.joined(separator: "\n\n")

		addFoldButton()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Puts a real button where the fold marker is drawn.
	///
	/// **Three attempts at hit-testing the drawing were three attempts too
	/// many.** The box was measured in one place and clicked in another, then
	/// in one place with slack, then with more slack, and it was reported dead
	/// every time. A button cannot be three points out and cannot be argued
	/// with: AppKit routes the click, and the drawing is only a drawing.
	private func addFoldButton() {
		guard let graph, graph.collapsible > 0 else { return }

		let button = NSButton(frame: .zero)
		button.isBordered = false
		button.bezelStyle = .inline
		button.title = ""
		button.target = self
		button.action = #selector(foldPressed)
		button.translatesAutoresizingMaskIntoConstraints = false
		button.toolTip = isCollapsed
			? "Show the \(graph.collapsible) commits this merge brought in"
			: "Fold away the \(graph.collapsible) commits this merge brought in"
		addSubview(button)

		// Bigger than the drawing, because a nine-point square is a hard thing
		// to hit; centred on it, so it still looks like what it is.
		let box = GraphMetrics.foldBox(lane: graph.lane, isMerge: commit.isMerge, centreY: 0)
		let size = Theme.current.scaled(18)
		NSLayoutConstraint.activate([
			button.centerXAnchor.constraint(equalTo: leadingAnchor, constant: box.midX),
			button.centerYAnchor.constraint(equalTo: centerYAnchor),
			button.widthAnchor.constraint(equalToConstant: size),
			button.heightAnchor.constraint(equalToConstant: size),
		])
	}

	@objc private func foldPressed() { onFold?() }

	/// How wide one lane is, and how far the text starts from the graph.
	private var laneWidth: CGFloat { GraphMetrics.laneWidth }

	/// A remote-only commit is faded, not greyed — the refs tree's rule for a
	/// merged branch, for the refs tree's reason: a fixed dim colour would be
	/// one more meaning for a row's colour, and an alpha keeps whatever the
	/// row already said and says it quietly. The ref pills are exempt: the
	/// `origin/…` chip is why the row is on the page at all.
	private func faded(_ colour: NSColor, when dim: Bool) -> NSColor {
		dim ? colour.withAlphaComponent(0.45) : colour
	}

	private func faded(_ colour: NSColor) -> NSColor {
		faded(colour, when: isRemoteOnly)
	}

	/// The colours lines of descent are drawn in, in order.
	///
	/// Chosen to be told apart at a glance rather than to be pretty: a graph is
	/// read by following one line down past the others.
	private static let laneColours: [NSColor] = [
		.hex(0x6E97F0), .hex(0x71B382), .hex(0xE5BE72), .hex(0xC983C5),
		.hex(0x62B4F0), .hex(0xD8926B), .hex(0x46BDB6), .hex(0xD6706E),
	]

	static func colour(forBranch branch: Int) -> NSColor {
		laneColours[abs(branch) % laneColours.count]
	}

	/// The graph column's width for this row, or nothing when there is no
	/// graph — a filtered log has no shape worth drawing.
	private var graphWidth: CGFloat {
		guard let graph else { return 0 }
		return CGFloat(max(1, graph.width)) * laneWidth + Theme.current.scaled(6)
	}

	override func draw(_ dirtyRect: NSRect) {
		drawGraph()

		let left = Theme.current.scaled(10) + graphWidth
		let top = Theme.current.scaled(5)

		var x = left
		// Where a branch or tag points, said before the subject: it is how a
		// commit is found by eye when scrolling.
		// Four rather than two: a commit at the tip of a branch that is also
		// tagged, pushed and stashed on top of is exactly the commit somebody
		// is looking for, and it is the one whose labels were being dropped.
		for ref in commit.refs.prefix(4) {
			let name = ref.replacingOccurrences(of: "tag: ", with: "")
			// A tag is one thing, a stash another, a branch a third: the colour
			// is what tells them apart while scrolling.
			let tint: NSColor
			if ref.hasPrefix("tag: ") {
				tint = Theme.current.gitModified
			} else if name.hasPrefix("refs/stash") || name.hasPrefix("stash@") {
				tint = Theme.current.gitUnversioned
			} else if name.contains("/") && !name.hasPrefix("feature/") && name.split(separator: "/").count == 2
				&& !name.hasPrefix("fix/") && !name.hasPrefix("chore/") && !name.hasPrefix("release/") {
				// `origin/main` and friends: where it is, not where it is being
				// worked on.
				tint = Theme.current.gitIgnored
			} else {
				tint = Theme.current.gitAdded
			}

			let label = NSAttributedString(string: name, attributes: [
				.font: NSFont.systemFont(ofSize: Theme.current.scaled(9.5), weight: .semibold),
				.foregroundColor: tint,
			])
			let size = label.size()
			let pill = NSRect(x: x, y: top, width: size.width + 8, height: size.height + 2)
			// A row is drawn to its own bounds and nothing clips it, so a
			// commit at the tip of four refs used to draw its last pill over
			// whatever was beside the list. Stop instead: the subject is worth
			// more than a fifth label, and the tooltip has them all.
			guard pill.maxX < bounds.maxX - Theme.current.scaled(60) else { break }
			tint.withAlphaComponent(0.18).setFill()
			NSBezierPath(roundedRect: pill, xRadius: 3, yRadius: 3).fill()
			label.draw(at: NSPoint(x: x + 4, y: top + 1))
			x += pill.width + Theme.current.scaled(5)
		}

		// A commit only on this machine is the one worth spotting: it is the
		// one a lost laptop takes with it.
		if isUnpushed, let arrow = Theme.symbol(
			"arrow.up", size: 9 * Theme.current.scale, color: Theme.current.gitModified
		) {
			let size = Theme.current.scaled(10)
			arrow.drawFitted(in: NSRect(
				x: x, y: top + Theme.current.scaled(2), width: size, height: size
			))
			x += size + Theme.current.scaled(4)
		}

		// **On a page, who and when are columns.** In a column they have to be a
		// second line under the subject, which is the only place they fit; with
		// room they belong at the right-hand edge, aligned down the list, where
		// the eye can run past them rather than through them.
		var subjectLimit = max(0, bounds.width - x - Theme.current.scaled(10))
		if showsAuthor {
			let columns = NSAttributedString(
				string: "\(commit.authorName)   \(Self.age(of: commit.date))",
				attributes: [
					.font: Theme.current.uiFont(10.5),
					.foregroundColor: faded(Theme.current.gitIgnored),
				]
			)
			let width = columns.size().width
			let right = bounds.maxX - Theme.current.scaled(12) - width
			columns.draw(at: NSPoint(x: right, y: top + Theme.current.scaled(1)))
			subjectLimit = max(0, right - x - Theme.current.scaled(12))
		}

		let subject = NSAttributedString(string: commit.subject, attributes: [
			.font: Theme.current.uiFont(12),
			.foregroundColor: faded(Theme.current.sidebarText),
		])
		subject.draw(in: NSRect(
			x: x, y: top,
			width: subjectLimit,
			height: subject.size().height
		))

		// Merges are worth telling apart at a glance: their diff is against the
		// first parent and reads differently from an ordinary commit's.
		var meta = showsAuthor
			? commit.shortHash
			: "\(commit.shortHash)  ·  \(commit.authorName)  ·  \(Self.age(of: commit.date))"
		if commit.isMerge { meta = "merge  ·  " + meta }

		let detail = NSAttributedString(string: meta, attributes: [
			.font: Theme.current.uiFont(10),
			.foregroundColor: faded(Theme.current.gitIgnored),
		])
		detail.draw(in: NSRect(
			x: left,
			y: top + subject.size().height + Theme.current.scaled(2),
			width: max(0, bounds.width - left - Theme.current.scaled(10)),
			height: detail.size().height
		))
	}

	/// Draws the lanes, the lines between them, and this commit's dot.
	///
	/// A row is drawn as: everything that passes through it going straight
	/// down, then the lines that bend into or out of this commit, then the dot
	/// on top so nothing crosses it.
	private func drawGraph() {
		guard let graph else { return }
		let centreY = bounds.midY
		func centre(_ lane: Int) -> CGFloat { GraphMetrics.laneCentre(lane) }

		// The strokes stop at the dot's edge rather than running under it. A
		// dot is not always opaque — a remote-only row's is faded — and a line
		// crossing behind a translucent dot reads as a line through it. Hiding
		// the overlap by painting background first would paint the wrong
		// colour on a selected row, so the lines simply end where the dot
		// begins.
		let radius = Theme.current.scaled(commit.isMerge ? 4 : 3.5)
		let width = Theme.current.scaled(1.6)
		for edge in graph.edges {
			let path = NSBezierPath()
			let from = centre(edge.from)
			let to = centre(edge.to)
			// A stroke below this row's own dot belongs to this commit's link
			// to its parent and fades with the commit; anything else fades
			// when its lane is inside an unpulled commit's link from above.
			let dim: Bool
			if edge.from == edge.to {
				dim = edge.from == graph.lane
					? isRemoteOnly
					: fadedLanes.contains(edge.from)
			} else if edge.to == graph.lane {
				dim = fadedLanes.contains(edge.from)
			} else {
				dim = isRemoteOnly
			}
			if from == to {
				// A lane carrying on: the line runs the height of the row, and
				// only from the dot downwards when it starts here.
				let top = (edge.from == graph.lane) ? centreY + radius : bounds.minY
				path.move(to: NSPoint(x: from, y: top))
				path.line(to: NSPoint(x: from, y: bounds.maxY))
			} else if edge.to == graph.lane {
				// A line arriving: it came down its own lane from the row
				// above and bends into this commit. Drawn upwards, which is
				// where it comes from — drawing it downwards left every merged
				// branch ending in mid-air.
				path.move(to: NSPoint(x: from, y: bounds.minY))
				path.curve(
					to: NSPoint(x: to, y: centreY - radius),
					controlPoint1: NSPoint(x: from, y: centreY - (bounds.height / 3)),
					controlPoint2: NSPoint(x: to, y: bounds.minY + (bounds.height / 3))
				)
			} else {
				// A line leaving: from this commit down into another lane.
				path.move(to: NSPoint(x: from, y: centreY + radius))
				path.curve(
					to: NSPoint(x: to, y: bounds.maxY),
					controlPoint1: NSPoint(x: from, y: bounds.maxY - (bounds.height / 3)),
					controlPoint2: NSPoint(x: to, y: centreY + (bounds.height / 3))
				)
			}
			path.lineWidth = width
			faded(Self.colour(forBranch: edge.branch).withAlphaComponent(0.9), when: dim).setStroke()
			path.stroke()
		}

		// Lines coming from above into this commit's lane: the row above drew
		// them to its own edge, and this one meets them.
		//
		// Unless there is nothing above. The newest commit of a line has
		// nothing continuing into it, and drawing this anyway gave every
		// branch tip a stub of line above the dot, arriving from a history
		// that is not there.
		let own = centre(graph.lane)
		if !graph.isTip {
			let up = NSBezierPath()
			up.move(to: NSPoint(x: own, y: bounds.minY))
			up.line(to: NSPoint(x: own, y: centreY))
			up.lineWidth = width
			// The stub arrives from the row above: it is the tail of whatever
			// link is coming down this lane, not part of this commit's own.
			faded(
				Self.colour(forBranch: graph.branch).withAlphaComponent(0.9),
				when: fadedLanes.contains(graph.lane)
			).setStroke()
			up.stroke()
		}

		let dot = NSRect(
			x: own - radius, y: centreY - radius, width: radius * 2, height: radius * 2
		)
		let colour = faded(Self.colour(forBranch: graph.branch))
		if commit.isMerge {
			// A merge is drawn hollow, the way a junction is: the two lines
			// meeting are what matters, not the point itself.
			Theme.current.editorBackground.setFill()
			NSBezierPath(ovalIn: dot).fill()
			colour.setStroke()
			let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.8, dy: 0.8))
			ring.lineWidth = Theme.current.scaled(1.8)
			ring.stroke()
		} else {
			colour.setFill()
			NSBezierPath(ovalIn: dot).fill()
		}

		// A merge that brought a branch in can fold it away. The marker sits
		// beside the dot rather than under it, where the lines leaving the row
		// are: a plus for a branch that is folded, a minus for one that is not,
		// which is how a tree says the same thing everywhere else.
		guard graph.collapsible > 0 else { return }
		// **In the colour of what it folds, not of the row it sits on.** The
		// row is the branch being merged *into*, so a blue mainline offered a
		// blue button that hides a red branch — and the one thing a fold marker
		// has to say is which line it is about. Reported against exactly that
		// pair of colours.
		let folding = Self.colour(forBranch: graph.collapsedBranch ?? graph.branch)
		// Through the same measurements the click is tested against, so the two
		// cannot drift apart again.
		let box = GraphMetrics.foldBox(
			lane: graph.lane, isMerge: commit.isMerge, centreY: centreY
		)
		folding.withAlphaComponent(0.18).setFill()
		NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()

		let marker = NSBezierPath()
		let arm = Theme.current.scaled(2.4)
		marker.move(to: NSPoint(x: box.midX - arm, y: box.midY))
		marker.line(to: NSPoint(x: box.midX + arm, y: box.midY))
		if isCollapsed {
			marker.move(to: NSPoint(x: box.midX, y: box.midY - arm))
			marker.line(to: NSPoint(x: box.midX, y: box.midY + arm))
		}
		marker.lineWidth = Theme.current.scaled(1.3)
		marker.lineCapStyle = .round
		folding.setStroke()
		marker.stroke()
	}

	/// Coarse: which week it was is what anybody remembers.
	static func age(of date: Date) -> String {
		let seconds = -date.timeIntervalSinceNow
		switch seconds {
		case ..<60: return "just now"
		case ..<3600: return "\(Int(seconds / 60))m ago"
		case ..<86_400: return "\(Int(seconds / 3600))h ago"
		case ..<(86_400 * 7): return "\(Int(seconds / 86_400))d ago"
		case ..<(86_400 * 365): return "\(Int(seconds / (86_400 * 7)))w ago"
		default: return "\(Int(seconds / (86_400 * 365)))y ago"
		}
	}
}

/// Where the graph puts things.
///
/// **One set of numbers for drawing and for hit-testing.** They were written
/// out twice and disagreed by three points, which is how a fold marker came to
/// be drawn where a click on it did nothing.
enum GraphMetrics {
	static var laneWidth: CGFloat { Theme.current.scaled(13) }

	static func laneCentre(_ lane: Int) -> CGFloat {
		Theme.current.scaled(8) + CGFloat(lane) * laneWidth
	}

	static func dotRadius(isMerge: Bool) -> CGFloat {
		Theme.current.scaled(isMerge ? 4 : 3.5)
	}

	/// The box holding the plus or minus, beside the dot.
	static func foldBox(lane: Int, isMerge: Bool, centreY: CGFloat) -> NSRect {
		NSRect(
			x: laneCentre(lane) + dotRadius(isMerge: isMerge) + Theme.current.scaled(3),
			y: centreY - Theme.current.scaled(4.5),
			width: Theme.current.scaled(9),
			height: Theme.current.scaled(9)
		)
	}
}
