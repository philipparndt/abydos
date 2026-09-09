import AppKit
import AbydosKit

/// One changed file: git's status letter, then the name.
///
/// No directory after the name any more. The row sits under the folders it is
/// in, so repeating them on every row would be the flat list drawn inside the
/// tree — and it was only ever there because there was nowhere else to say
/// which of three `GitBlame.swift` was which.
final class ChangeRowView: NSView {
	private let node: GitChangeNode
	private let change: GitChange

	override var isFlipped: Bool { true }

	init(node: GitChangeNode, change: GitChange) {
		self.node = node
		self.change = change
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x = Theme.current.scaled(8)
		let badgeSize = Theme.current.scaled(13)

		// The status letter in its colour, as git prints it — the same letter
		// people already read in `git status`.
		let badge = NSRect(x: x, y: bounds.midY - badgeSize / 2, width: badgeSize, height: badgeSize)
		color(for: change.kind).setFill()
		NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3).fill()

		let letter = NSAttributedString(string: letter(for: change.kind), attributes: [
			.font: NSFont.systemFont(ofSize: Theme.current.scaled(9), weight: .bold),
			.foregroundColor: NSColor.black.withAlphaComponent(0.85),
		])
		letter.draw(at: NSPoint(
			x: badge.midX - letter.size().width / 2,
			y: badge.midY - letter.size().height / 2
		))
		x = badge.maxX + Theme.current.scaled(6)

		// A whole untracked directory keeps the badge — it is untracked, and
		// that is what the badge says — and gains a folder beside it. Both,
		// because neither alone is the truth: `.abydos` and `PI-12` were drawn
		// with the badge and nothing else, and read as files.
		if change.isDirectory,
		   let folder = Theme.symbol(
		   	"folder", size: badgeSize, color: Theme.current.gitUnversioned
		   ) {
			folder.drawFitted(in: NSRect(
				x: x, y: bounds.midY - badgeSize / 2, width: badgeSize, height: badgeSize
			))
			x += badgeSize + Theme.current.scaled(5)
		}

		// **The whole row is the name.** It used to end in `+1234 −567`,
		// right-aligned in columns measured across the side — three numbers
		// per row, and the deepest paths cut to make room for them. In a pane
		// that is read to find *which* file changed, that was width spent on
		// an answer nobody was looking for; how much changed is one click away
		// in the diff, and the folder rows say it in their tool tip.
		RowMetrics.draw(
			change.name,
			font: Theme.current.uiFont(12),
			colour: Theme.current.sidebarText,
			at: x, in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset - Theme.current.scaled(2)
		)
	}

	private func letter(for kind: GitChange.Kind) -> String {
		switch kind {
		case .added:      return "A"
		case .modified:   return "M"
		case .deleted:    return "D"
		case .renamed:    return "R"
		case .copied:     return "C"
		case .untracked:  return "U"
		case .conflicted: return "!"
		}
	}

	private func color(for kind: GitChange.Kind) -> NSColor {
		switch kind {
		case .added, .copied:  return Theme.current.gitAdded
		case .modified, .renamed: return Theme.current.gitModified
		case .deleted:         return Theme.current.gitUnversioned
		case .untracked:       return Theme.current.gitUnversioned
		case .conflicted:      return Theme.current.gitUnversioned
		}
	}
}


/// A folder with changes under it: the navigator's folder glyph, the name, and
/// how much of what changed under it is on this side of the index.
///
/// **Half staged is a state git does not have.** A folder is not something it
/// tracks, so nothing in `git status` can be asked whether a directory is
/// wholly in the index; the pane works it out by counting, and then has to say
/// so, because two lists make a folder sitting under "Staged" look finished and
/// somebody who reads it that way commits half of it.
///
/// It says so as a number rather than a new symbol to learn: `6` when
/// everything that changed under the folder is on this side, and `4 of 6` — in
/// the colour a modified file is drawn in, so it reads as something to look at
/// — when it is not. There is no checkbox to give a mixed state to and there
/// was never going to be one: the pane is deliberately two lists rather than
/// one with ticks, which is what lets it show a file that is in both.
final class ChangeFolderRowView: NSView {
	private let node: GitChangeNode

	override var isFlipped: Bool { true }

	init(node: GitChangeNode, isStaged: Bool) {
		self.node = node
		super.init(frame: .zero)

		// The count is small and the arithmetic behind it is not obvious, so
		// the sentence is on the row rather than in a release note.
		let side = isStaged ? "staged" : "not staged"
		let counts = node.isPartial
			? "\(node.count) of the \(node.total) changes under \(node.path) are \(side). "
				+ "\(isStaged ? "Unstaging" : "Staging") the folder takes all of them."
			: "\(node.count) change\(node.count == 1 ? "" : "s") under \(node.path), all \(side)."
		// **Which repository, when it is not this one.** Said in words as well
		// as in the glyph, because "is this my project or a submodule" is the
		// question the row was answering wrongly and a box is only a hint.
		toolTip = node.isRepository
			? "\(node.path) is a submodule — its own repository. \(counts) "
				+ "They are committed in \(node.name), and the superproject records where it now points."
			: counts
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x = Theme.current.scaled(8)
		let glyph = Theme.current.scaled(13)

		// In the slot the status letter occupies on a file row, and fitted
		// rather than stretched to fill it: `folder.fill` is half again as wide
		// as it is tall, and squeezed into a square it stops looking like a
		// folder at all — a rounded box with a notch, next to a tree of real
		// folders in the same window.
		//
		// **Unless the row is a repository**, which is a different thing and
		// now looks like one. See `BranchesPaneChangeRow` for the report: a
		// change inside a submodule read as a change to the project that is
		// open, because the submodule was drawn as one more folder in its path.
		if node.isRepository,
		   let box = Theme.symbol(
		   	"shippingbox", size: glyph, color: Theme.current.gitModified
		   ) {
			box.drawFitted(
				in: NSRect(x: x, y: bounds.midY - glyph / 2, width: glyph, height: glyph)
			)
		} else {
			FileIcon.folder()?.drawFitted(
				in: NSRect(x: x, y: bounds.midY - glyph / 2, width: glyph, height: glyph)
			)
		}
		x += glyph + Theme.current.scaled(6)

		// **The name and nothing else**, as on the file rows under it. The
		// tally and the `+69 −16` beside it are gone; what remains of them is
		// the tool tip set above, which says how many of how many are on this
		// side and what staging the folder would take.
		RowMetrics.draw(
			node.name,
			font: Theme.current.uiFont(12, weight: .medium),
			colour: Theme.current.sidebarText,
			at: x, in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset - Theme.current.scaled(2)
		)
	}
}
