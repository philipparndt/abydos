import CoreGraphics

/// Whether the terminal panel should be rounded down to whole rows, and where
/// the divider goes if it should.
///
/// The grid is `floor(height / rowHeight)`, so whatever is left over is drawn
/// as a strip of a row against the top of the viewport. Giving it back is a
/// question about the window's whole state, not about the arithmetic — the
/// panel may have been put away, or given the window, since the resize that
/// asked. It lives here so that the answer can be asked for twice, and tested
/// without a window.
public enum PanelRowSnap {
	/// What the window looks like at the moment the question is asked.
	public struct State: Equatable, Sendable {
		/// Whether the panel is on screen at all.
		public var isVisible: Bool
		/// Whether the panel has the whole window. Then it is not the split's
		/// to divide and its height is not its own to round.
		public var isMaximized: Bool
		/// The height the split has to share out.
		public var total: CGFloat
		/// What the panel has of it now.
		public var panelHeight: CGFloat
		/// How much of the terminal's height is not a whole row. Nil when the
		/// pane in front is not a terminal, and so has no grid and no opinion.
		public var remainder: CGFloat?
		/// How thick the divider between them is.
		///
		/// **Not a detail.** `setPosition` leaves the second subview
		/// `total - position - thickness` tall, so a position computed without
		/// it hands the panel one point less than was asked for — and one point
		/// less than whole rows is a remainder of nearly a whole row, which
		/// this function then takes off again on the next pass. That is how
		/// widening a window came to shorten the terminal: dozens of resize
		/// notifications, a row lost to each.
		///
		/// Given rather than assumed: the app's split view decides its own
		/// thickness and could stop being thin.
		public var dividerThickness: CGFloat

		public init(
			isVisible: Bool,
			isMaximized: Bool,
			total: CGFloat,
			panelHeight: CGFloat,
			remainder: CGFloat?,
			dividerThickness: CGFloat = 0
		) {
			self.isVisible = isVisible
			self.isMaximized = isMaximized
			self.total = total
			self.panelHeight = panelHeight
			self.remainder = remainder
			self.dividerThickness = dividerThickness
		}
	}

	/// The floor a panel is allowed to be: a terminal four rows tall is the
	/// floor everywhere else, and shaving a row off to make the arithmetic
	/// tidy would be tidying the wrong thing.
	public static let minimumPanelHeight: CGFloat = 160
	/// Below this the window has not been laid out yet and there is nothing
	/// meaningful to divide.
	public static let minimumSplitHeight: CGFloat = 200
	/// Less than this much of a row left over is not worth moving anything for,
	/// and rounding noise should not start a layout pass.
	public static let smallestRemainder: CGFloat = 0.5

	/// Where the divider belongs, or nil when nothing should move.
	public static func dividerPosition(for state: State) -> CGFloat? {
		guard state.isVisible, !state.isMaximized else { return nil }
		guard let remainder = state.remainder, remainder > smallestRemainder else { return nil }

		let wanted = state.panelHeight - remainder
		guard state.total > minimumSplitHeight, wanted >= minimumPanelHeight else { return nil }
		// The thickness, so that the panel is `wanted` tall rather than a point
		// short of it: a point short is what made this run again, and again.
		return state.total - wanted - state.dividerThickness
	}
}
