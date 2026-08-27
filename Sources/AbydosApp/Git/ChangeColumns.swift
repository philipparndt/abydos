import AppKit
import AbydosKit

/// `+12 −3`, in the colours added and removed already have.
///
/// One place, because two views draw it and they would drift on the dash: a
/// hyphen-minus is narrower than the digits beside it and reads as a hyphen in a
/// filename, so this uses a real minus sign.
enum LineCountLabel {
	static var font: NSFont { Theme.current.uiFont(10.5) }

	/// The added half, `+12`, or nothing when nothing was added.
	static func added(_ lines: GitLineCount?) -> NSAttributedString? {
		guard let lines, lines.added > 0 else { return nil }
		return NSAttributedString(string: "+\(lines.added)", attributes: [
			.font: font, .foregroundColor: Theme.current.gitAdded,
		])
	}

	/// The removed half, `−3`.
	///
	/// A file git counted as nothing changed — a mode change it did count, a
	/// rename with no edit — has a count and it is zero. Saying `0` is clearer
	/// than an empty gap where every other row has numbers, and it goes in this
	/// column because this is the one nearest the tally.
	static func removed(_ lines: GitLineCount?) -> NSAttributedString? {
		guard let lines else { return nil }
		if lines.removed > 0 {
			return NSAttributedString(string: "\u{2212}\(lines.removed)", attributes: [
				.font: font, .foregroundColor: Theme.current.gitConflict,
			])
		}
		guard lines.added == 0 else { return nil }
		return NSAttributedString(string: "0", attributes: [
			.font: font, .foregroundColor: Theme.current.gitIgnored,
		])
	}
}

/// Where the numbers on the right of a changes row start.
///
/// **The counts were right-aligned and did not line up.** Each row put its own
/// text hard against the trailing inset, so a folder — which has a file tally
/// after its counts — pushed its `+69 −16` left by the width of that tally,
/// and the file under it did not. Reading down a nested tree, the plus signs
/// stepped in and out by a digit at every level.
///
/// So the three are columns, each as wide as the widest thing in that side of
/// the tree, and every row draws into the same ones. Measured once per reload
/// rather than once per row: `viewFor` is called for each visible row and
/// walking the whole side there would be the same walk many times over.
struct ChangeColumns {
	var added: CGFloat = 0
	var removed: CGFloat = 0
	var tally: CGFloat = 0

	static let gap: CGFloat = 6

	/// The widest of each over every node on one side.
	static func measure(_ roots: [GitChangeNode], tallies: (GitChangeNode) -> String?) -> Self {
		var columns = Self()
		var stack = roots
		while let node = stack.popLast() {
			stack.append(contentsOf: node.children)
			columns.added = max(columns.added, ceil(LineCountLabel.added(node.lines)?.size().width ?? 0))
			columns.removed = max(columns.removed, ceil(LineCountLabel.removed(node.lines)?.size().width ?? 0))
			if let tally = tallies(node) {
				columns.tally = max(columns.tally, ceil(NSAttributedString(
					string: tally,
					attributes: [.font: Theme.current.uiFont(10.5, weight: .semibold)]
				).size().width))
			}
		}
		return columns
	}

	/// Right edges of each column, and the x the name must stop before.
	func edges(in bounds: NSRect) -> (tally: CGFloat, removed: CGFloat, added: CGFloat, limit: CGFloat) {
		let gap = Theme.current.scaled(Self.gap)
		let right = bounds.maxX - RowMetrics.trailingInset
		let removedRight = tally > 0 ? right - tally - gap : right
		let addedRight = removed > 0 ? removedRight - removed - gap : removedRight
		let limit = added > 0 ? addedRight - added - gap : addedRight
		return (right, removedRight, addedRight, limit)
	}
}
