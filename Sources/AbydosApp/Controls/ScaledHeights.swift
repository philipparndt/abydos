import AppKit
import AbydosKit

/// The heights a pane took out of the theme, so they can be taken again.
///
/// **A constraint constant is the same fault as a bezel, by a different road.**
/// `heightAnchor.constraint(equalToConstant: Theme.current.scaled(150))` reads
/// the scale once and keeps the answer, so leaving presentation mode put the
/// type in the commit page's description box back to 1.0× and left the box
/// itself at the height 1.5× had asked for. That is the report — "the detail
/// area of the commit remains large" — and it is not a divider problem, which
/// is what it looked like: `PanelRowSnap` was read before this was written and
/// has nothing to say about it.
///
/// A table's row height is the same thing again: it is computed from the theme
/// on demand, but AppKit does not ask again unless it is told to.
///
/// So a pane keeps one of these, hands it every height it takes, and forgets
/// about it. It registers itself, so nothing has to remember it either — which
/// is the whole rule of this library.
final class ScaledHeights: ScaleFollowing {
	private var constraints: [(NSLayoutConstraint, CGFloat)] = []
	private var tables: [() -> NSTableView?] = []

	init() {
		ScaledControls.register(self)
	}

	/// A height constraint at the current scale, remembered.
	func height(_ view: NSView, design: CGFloat) -> NSLayoutConstraint {
		let constraint = view.heightAnchor.constraint(
			equalToConstant: Theme.current.scaled(design)
		)
		constraints.append((constraint, design))
		return constraint
	}

	/// A table whose rows should be re-measured when the scale moves.
	///
	/// Weakly, through a closure, because a pane hands these over while it is
	/// being built and the table may not outlive it.
	func follow(_ table: @autoclosure @escaping () -> NSTableView?) {
		tables.append(table)
	}

	func applyTheme() {
		for (constraint, design) in constraints {
			constraint.constant = Theme.current.scaled(design)
		}
		for table in tables.compactMap({ $0() }) {
			table.noteHeightOfRows(withIndexesChanged: IndexSet(0..<table.numberOfRows))
		}
	}
}
