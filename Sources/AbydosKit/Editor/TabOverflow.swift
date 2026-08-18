import Foundation

/// Which of a strip's tabs can actually be clicked, and how far the run has to
/// move to bring one into view.
///
/// **Arithmetic, so it lives here and not in a view.** Two strips ask it — the
/// editor's tab bar and the panel's — and they measure tabs differently on
/// purpose: an editor tab is `min(260, max(90, …))`, a panel tab is `max(96, …)`
/// with no ceiling and room reserved for a badge whether or not there is one.
/// What does not differ is the part that decides whether a tab is reachable, and
/// two copies of that would be two behaviours within a month.
///
/// The fault this answers: both strips lay tabs out from the leading edge with
/// no bound and neither takes a `scrollWheel`, so with a dozen terminals open the
/// tabs past the edge could be reached by widening the window or by closing the
/// ones in front of them, and that was the whole list. The panel's strip has no
/// keyboard route either — ⌘] and ⌘[ are `editor.selectNextTab`.
public struct TabOverflow: Equatable, Sendable {
	/// The tabs wholly in front of whatever is drawn over the trailing end,
	/// as indices into the frames given.
	public let visible: Range<Int>
	/// Hidden because the run starts after them.
	public let hiddenBefore: [Int]
	/// Hidden because they are past the trailing edge, or under it.
	public let hiddenAfter: [Int]

	public init(visible: Range<Int>, hiddenBefore: [Int], hiddenAfter: [Int]) {
		self.visible = visible
		self.hiddenBefore = hiddenBefore
		self.hiddenAfter = hiddenAfter
	}

	public var hiddenCount: Int { hiddenBefore.count + hiddenAfter.count }
	public var isOverflowing: Bool { hiddenCount > 0 }

	/// Every hidden tab, in tab order, the ones behind the run first.
	///
	/// One list rather than two, because that is what a menu shows: the order a
	/// person knows their tabs by is the order they are in, and splitting the
	/// menu into "before" and "after" would be showing them the strip's
	/// bookkeeping.
	public var hidden: [Int] { hiddenBefore + hiddenAfter }

	/// Works out what is reachable.
	///
	/// - Parameters:
	///   - widths: each tab's width, in the order they are laid out.
	///   - start: the first tab of the run — what the strip is scrolled to,
	///     though nothing scrolls it but the active tab needing to be seen.
	///   - available: how much room there is from the leading edge to the point
	///     where the trailing controls' own ground begins.
	///   - spacing: what sits between two tabs, which is nothing on the tmux
	///     strip and two points elsewhere.
	///
	/// **A tab is visible only if the whole of it fits.** Half a tab under the
	/// session tag is not a target — it is a tab somebody clicks and misses —
	/// and counting it as visible is how a menu comes to leave out the very tab
	/// that could not be reached.
	public static func measure(
		widths: [CGFloat],
		start: Int = 0,
		available: CGFloat,
		spacing: CGFloat = 0
	) -> TabOverflow {
		guard !widths.isEmpty else { return TabOverflow(visible: 0..<0, hiddenBefore: [], hiddenAfter: []) }
		let first = max(0, min(start, widths.count - 1))

		var x: CGFloat = 0
		var last = first
		for index in first..<widths.count {
			let next = x + widths[index]
			// The strip cannot show less than one tab, so the first of the run
			// counts as visible even where there is no room for it at all —
			// otherwise a very narrow window reports everything hidden and the
			// menu becomes the only way to use the app.
			if next > available, index > first { break }
			x = next + spacing
			last = index
		}

		return TabOverflow(
			visible: first..<(last + 1),
			hiddenBefore: Array(0..<first),
			hiddenAfter: Array((last + 1)..<widths.count)
		)
	}

	/// Where the run must start so that no room is wasted at the trailing end.
	///
	/// **Reported: tabs are closed and the strip does not lay out again.** Eight
	/// tabs left, room for all of them, half the strip empty — and the chevron
	/// still offering five. `start(showing:)` moves the run *forward* when the
	/// active tab does not fit and there was nothing to move it back, so space
	/// that appeared later went unused and the tabs before the run stayed
	/// hidden. Closing a tab, closing several, widening the window: all the same
	/// fault.
	///
	/// **It only ever fills trailing space**, and that is what keeps it from
	/// being a second thing that moves tabs about. A run with tabs still hidden
	/// after it has no space to fill, so this leaves it exactly where it is —
	/// which is every moment somebody is working in the middle of a long strip.
	/// It pulls back only while the last tab stays visible, so the run cannot
	/// slide off the end it was showing.
	public static func settled(
		start: Int,
		widths: [CGFloat],
		available: CGFloat,
		spacing: CGFloat = 0
	) -> Int {
		var candidate = max(0, min(start, max(0, widths.count - 1)))
		while candidate > 0 {
			let earlier = measure(
				widths: widths, start: candidate - 1, available: available, spacing: spacing
			)
			guard earlier.hiddenAfter.isEmpty else { break }
			candidate -= 1
		}
		return candidate
	}

	/// Where the run must start for one tab to be wholly visible, moving as
	/// little as possible.
	///
	/// Nothing where it already is: a strip that re-lays itself out on every
	/// selection is a strip whose tabs move under the pointer for no reason.
	///
	/// Forwards, the run starts at the first tab that leaves room for the wanted
	/// one; backwards, it starts at the wanted tab itself. Both are the least
	/// move — going further forwards would hide a tab that was visible, and
	/// going further back is simply further.
	public static func start(
		showing index: Int,
		widths: [CGFloat],
		from start: Int,
		available: CGFloat,
		spacing: CGFloat = 0
	) -> Int {
		guard widths.indices.contains(index) else { return start }
		let current = measure(widths: widths, start: start, available: available, spacing: spacing)
		if current.visible.contains(index) { return start }
		if index < current.visible.lowerBound { return index }

		// Walk the run forwards until the wanted tab is the last that fits. The
		// loop is bounded by the tab itself: starting there always shows it,
		// because the first of a run is always counted visible.
		var candidate = start
		while candidate < index {
			candidate += 1
			let moved = measure(widths: widths, start: candidate, available: available, spacing: spacing)
			if moved.visible.contains(index) { return candidate }
		}
		return index
	}
}
