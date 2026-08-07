import AppKit

/// The line that marks the tab being shown.
///
/// Two strips draw it — the editor's and the panel's — and they have to agree,
/// or the same mark in two places reads as two different marks. One thickness,
/// and one rule about the colour: the accent belongs to the pane the cursor is
/// in, and every other strip shows the line without it. Otherwise a window with
/// a split and a terminal has three tabs all claiming the keyboard.
enum TabSelectionLine {
	/// How thick the line is, wherever it is drawn.
	static let thickness: CGFloat = 2

	/// Where it goes on a tab. Along the top for a strip that sits under what it
	/// belongs to, which is how tmux's own strip reads.
	static func rect(in tab: NSRect, alongTop: Bool) -> NSRect {
		NSRect(
			x: tab.minX,
			y: alongTop ? tab.minY : tab.maxY - thickness,
			width: tab.width,
			height: thickness
		)
	}

	/// The accent where the keyboard is, and a quiet grey everywhere else.
	@MainActor static func color(focused: Bool, accent: NSColor? = nil) -> NSColor {
		guard focused else { return Theme.current.sidebarText.withAlphaComponent(0.35) }
		return accent ?? Theme.current.gitModified
	}
}
