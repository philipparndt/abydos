import AppKit

/// A selected row, drawn in the theme's colour rather than the system's.
///
/// **Reported from use: the value popup's selection was blue** while the same
/// tree in the panel below it was the theme's orange — two views of the same
/// variables, disagreeing about what "selected" looks like. AppKit draws the
/// system accent unless a row view says otherwise, and the class that said
/// otherwise was private to the pane, so the popup could not have it.
///
/// It lives on its own for the same reason `VariableCell` does: the alternative
/// to sharing one row view is two, drifting apart the first time the theme's
/// selection colour is touched.
///
/// **Which of the two to use, since there are two.** This one is a full-bleed
/// band and is for a *list*: a dense run of records where the band is the row.
/// `TreeRowView` is a rounded, inset pill and is for a *tree*, where a
/// full-bleed band swallows the indentation that says what is inside what —
/// and it goes quiet when the keyboard is elsewhere, which a list of records
/// does not need to.
///
/// The four trees people use all day are on `TreeRowView`. The commit list, the
/// debugger's variables, the breakpoint list, the pull-request list and the
/// value popup are lists and stay here. That is a boundary rather than a
/// backlog: a band and a pill are both right, for different shapes.
final class ThemedRowView: NSTableRowView {
	override func drawSelection(in dirtyRect: NSRect) {
		Theme.current.selectionActive.setFill()
		bounds.fill()
	}
}
