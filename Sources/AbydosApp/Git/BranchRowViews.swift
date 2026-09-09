import AppKit
import AbydosKit

/// The rows the branches tree is drawn with: a section heading, a branch, the
/// working copy and what is changed in it, a stash and its files, a detached
/// head, a folder, a submodule and a worktree.
/// answer for three controls without asking which one it came from, and that
/// question has a wrong answer.
@MainActor
final class TagSourceWatcher: NSObject, NSComboBoxDelegate {
	private let field: NSComboBox
	private let label: NSTextField
	let root: URL

	init(field: NSComboBox, label: NSTextField, root: URL) {
		self.field = field
		self.label = label
		self.root = root
		super.init()
		field.delegate = self
	}

	func controlTextDidChange(_ notification: Notification) { refresh() }
	func comboBoxSelectionDidChange(_ notification: Notification) {
		// The field still holds the old text at this moment; the selection is
		// what was just picked.
		let index = field.indexOfSelectedItem
		guard index >= 0, let value = field.itemObjectValue(at: index) as? String else { return }
		describe(value)
	}

	func refresh() { describe(field.stringValue) }

	private func describe(_ source: String) {
		let asked = source.trimmingCharacters(in: .whitespaces)
		guard !asked.isEmpty else {
			label.stringValue = " "
			return
		}
		Task { @MainActor [weak self] in
			guard let self else { return }
			guard let found = await GitTags.describe(asked, in: self.root) else {
				// Said plainly rather than left blank: an empty line under a
				// name somebody has mistyped looks exactly like one under a
				// name that is fine.
				self.label.textColor = Theme.current.gitConflict
				self.label.stringValue = "git does not know “\(asked)”"
				return
			}
			self.label.textColor = Theme.current.gitAdded
			self.label.stringValue = "→ \(found)"
		}
	}
}

/// The tree, drawn by AppKit rather than by hand.
///
/// **What is left here is only what an outline view does not already do.**
/// Indentation, disclosure triangles and the clicks on them, ← and →, and
/// keeping the keyboard through an expansion are all AppKit's — and each one of
/// them was written out by hand here first, and each was reported broken.
final class BranchesOutlineView: NSOutlineView {
	var onActivate: (() -> Void)?
	/// `⌘⏎` — the selected row's own verb, whatever that row is.
	var onRowAction: (() -> Void)?
	/// `↑` from the first row, which leaves for the row pinned above the tree.
	var onLeaveTop: (() -> Void)?
	/// ⌘⌫ on the selection, which is this app's delete gesture: the project
	/// tree has trashed a file with it since it had a tree.
	var onDeleteKey: (() -> Void)?

	/// A click from an inactive window lands on the row rather than being spent
	/// activating the app, which is what the project tree has always done.
	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	/// Redraw when focus moves, so the highlight dims with it.
	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		return super.resignFirstResponder()
	}

	override func keyDown(with event: NSEvent) {
		// **⌘⏎ before ⏎.** A row's verb needs a key of its own, or it is a
		// mouse-only feature — which these panes were fixed not to be. ⏎ is
		// taken: on a branch it checks it out, and one key meaning two things on
		// two rows is the overload this avoids.
		if event.keyCode == 36 || event.keyCode == 76 {
			if event.modifierFlags.contains(.command) {
				onRowAction?()
			} else {
				onActivate?()
			}
			return
		}

		// ⌘⌫, the delete gesture this app already has in the project tree — so
		// a tag's own verb is not the one thing in this tree that needs a
		// pointer. It acts on the selection or on nothing, which is what a key
		// that means "delete what is highlighted" has to do.
		if event.keyCode == 51, event.modifierFlags.contains(.command) {
			onDeleteKey?()
			return
		}

		// Home, End, Page Up and Page Down. An outline view interprets the
		// arrows and leaves these four to the scroll view, which moves the
		// paper and not the selection — so the list scrolled and the highlight
		// stayed where it was, which is not what any of them means in a list.
		// ↑ off the top goes to the row pinned above, which is the repository.
		if event.keyCode == 126, selectedRow == 0 {
			onLeaveTop?()
			return
		}

		let last = numberOfRows - 1
		guard last >= 0 else { return super.keyDown(with: event) }
		let page = max(1, Int(visibleRect.height / max(1, rowHeight)) - 1)
		let here = selectedRow < 0 ? 0 : selectedRow

		switch event.keyCode {
		case 115: select(row: 0)
		case 119: select(row: last)
		case 116: select(row: max(0, here - page))
		case 121: select(row: min(last, here + page))
		default:  super.keyDown(with: event)
		}
	}

	private func select(row: Int) {
		let found = min(max(0, row), numberOfRows - 1)
		guard found >= 0 else { return }
		selectRowIndexes([found], byExtendingSelection: false)
		scrollRowToVisible(found)
	}

	override func mouseDown(with event: NSEvent) {
		super.mouseDown(with: event)
		if event.clickCount == 2 { onActivate?() }
	}
}

/// A merge that has stopped, and the three things somebody does next.
///
/// **Three, and deliberately not four.** Opening the files is the work; Fork is
/// where this change has already said a three-way merge editor belongs, so the
/// handoff has a home rather than being a dead end; and a prompt on the
/// clipboard hands the conflict to an agent in this app's own terminal, which
/// is the thing this app is for. Aborting is not here — the banner is about
/// resolving, and abandoning belongs on the operation that started the merge,
/// where what would be lost can be counted.
final class BranchSectionView: ActionableRowView {
	private let title: String

	init(title: String) {
		self.title = title
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// What kind of thing a section holds.
	///
	/// **Icons at the root too.** Without one the indentation under a section
	/// reads as text that has been pushed sideways for no reason: every row
	/// below has a glyph, and the row above it had a gap where one should be.
	private var symbol: String {
		switch title {
		case "Local":     return "arrow.trianglehead.branch"
		case "Tags":      return "tag"
		case "Stashes":   return "tray.full"
		case "Worktrees": return "folder.badge.gearshape"
		// Anything else is a remote, named after the remote.
		default:          return "cloud"
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		// **No triangle of its own.** The outline view draws one, and a second
		// drawn here put two side by side on every section.
		RowMetrics.glyph(symbol, colour: Theme.current.gitIgnored, in: bounds)

		let label = NSAttributedString(string: title.uppercased(), attributes: [
			.font: Theme.current.uiFont(10, weight: .semibold),
			.foregroundColor: Theme.current.gitIgnored,
		])
		label.draw(at: NSPoint(
			x: RowMetrics.textInset,
			y: bounds.midY - label.size().height / 2
		))

		drawAction()
	}
}

final class BranchRowView: NSView {
	private let branch: GitBranch
	/// What the row says, which under a folder is one component of the name
	/// rather than all of it.
	private let display: String
	private let depth: Int
	/// What this row is waiting on — the sentence it says while it waits, or
	/// nil when it is not waiting on anything.
	private let busy: String?
	/// Its work is already in the default branch: nothing on it that is not
	/// somewhere else. Drawn faded, and never for the branch you are on.
	private let isMerged: Bool
	/// What an unpublished branch's count is measured against, for the tooltip.
	private let base: String?
	private var spinner: NSProgressIndicator?
	override var isFlipped: Bool { true }

	init(
		branch: GitBranch,
		display: String? = nil,
		depth: Int = 0,
		busy: String? = nil,
		isMerged: Bool = false,
		base: String? = nil
	) {
		self.branch = branch
		self.display = display ?? branch.name
		self.depth = depth
		self.busy = busy
		self.base = base
		// **The branch you are standing on never dims, whatever the reading
		// says.** The default branch is trivially merged into itself and any
		// branch you have just merged and not left is finished by the same
		// test — and a faded row for the branch the window is on reads as
		// something being wrong rather than as something being done.
		self.isMerged = isMerged && !branch.isCurrent
		super.init(frame: .zero)
		if let busy {
			toolTip = busy
			// A real spinner rather than something drawn by hand: it has to
			// keep turning while git works, and that is what this control is
			// for.
			//
			// **It sat below a `return` for as long as it existed.** One guard
			// left on a row that was waiting and a second one turned the
			// spinner back on further down, so the branch being pushed showed
			// a tooltip and nothing else — the thing the spinner was added to
			// answer. One `if` for both halves now, and no way back into that.
			let wheel = NSProgressIndicator()
			wheel.style = .spinning
			wheel.controlSize = .small
			wheel.isIndeterminate = true
			wheel.translatesAutoresizingMaskIntoConstraints = false
			addSubview(wheel)
			NSLayoutConstraint.activate([
				wheel.centerYAnchor.constraint(equalTo: centerYAnchor),
				wheel.trailingAnchor.constraint(
					equalTo: trailingAnchor, constant: -Theme.current.scaled(10)
				),
				wheel.widthAnchor.constraint(equalToConstant: Theme.current.scaled(12)),
				wheel.heightAnchor.constraint(equalToConstant: Theme.current.scaled(12)),
			])
			wheel.startAnimation(nil)
			spinner = wheel
			return
		}
		// **The words the symbols replaced live here.** A symbol on a row is a
		// note somebody has to be able to look up, and the row already had a
		// tooltip to put it in.
		var notes: [String] = [branch.checkoutName]
		if !branch.subject.isEmpty { notes.append(branch.subject) }
		if self.isMerged { notes.append("already merged") }
		if branch.upstreamIsGone { notes.append("its upstream has been deleted") }
		else if branch.isUnpublished {
			let ahead = branch.aheadOfDefault ?? 0
			notes.append(ahead > 0
				? "never published — \(ahead) commit\(ahead == 1 ? "" : "s") of its own"
				: "never published")
			// The half the row does not draw, said here in words rather than
			// in an arrow that would be read as remote traffic.
			if let behind = branch.behindDefault, behind > 0 {
				notes.append("\(base ?? "the default branch")"
					+ " has moved on by \(behind) commit\(behind == 1 ? "" : "s")")
			}
		}
		toolTip = notes.joined(separator: " — ")
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		// **One text column for every kind of row.** The outline view has
		// already indented this view by its depth; anything added here is an
		// offset of its own, and five row kinds each adding a different one is
		// what made the tree look ragged.
		//
		// A constant now the trailing mark is right-aligned: nothing after the
		// name needs to know where the name ended.
		let x = RowMetrics.textInset

		// **What kind of thing this row is, said by a glyph.** A folded prefix
		// and a branch are both a name at a depth, and with only indentation to
		// tell them apart somebody has to count. The current branch keeps its
		// tick — that is how git itself marks it, and it outranks saying what
		// kind of ref it is, which is obvious for the one you are standing on.
		let mark: (name: String, colour: NSColor) = {
			if branch.isCurrent { return ("checkmark", Theme.current.gitAdded) }
			if case .tag = branch.kind { return ("tag", Theme.current.gitModified) }
			return ("arrow.trianglehead.branch", Theme.current.gitIgnored)
		}()
		// **A merged branch is faded, not greyed.** A fixed dim colour would be
		// a fourth meaning for a row's colour, next to current, tag and plain;
		// an alpha keeps whatever the row already said and says it quietly.
		let fade: (NSColor) -> NSColor = { [isMerged] colour in
			isMerged ? colour.withAlphaComponent(0.45) : colour
		}
		RowMetrics.glyph(mark.name, colour: fade(mark.colour), in: bounds)

		let colour = fade(branch.isCurrent ? Theme.current.gitAdded : Theme.current.sidebarText)
		// **Bold, and green.** Semibold beside regular is a difference somebody
		// has to look for, and the branch you are standing on is the one row in
		// the list you should never have to look for. Through `uiFont` like
		// every other weight in this pane, rather than `NSFont.systemFont`,
		// which was this one row disagreeing about where a font comes from.
		let font = branch.isCurrent
			? Theme.current.uiFont(12, weight: .bold)
			: Theme.current.uiFont(12)

		// **The trailing end of the row is a column**, right-aligned, so a list
		// of these reads down rather than along a ragged edge made of whatever
		// each name happened to leave. The changes tree's counts had the same
		// fault and it is fixed the same way.
		//
		// What sits in it is either news or a standing fact, and they are said
		// differently. Ahead and behind are news — somebody moved — and they
		// are numbers because the number is the point. Merged, never published,
		// and an upstream that has been deleted are facts about the branch that
		// do not change while you look at them, and they are symbols: two words
		// of English on every row of a list is a paragraph nobody reads.
		//
		// **Merged outranks the other two.** A branch whose pull request was
		// merged and whose remote branch went with it is both merged and
		// upstream-gone, and of the two only one of them is what you wanted to
		// know: the work is in, and this row can go. `not published` on a
		// branch that is already merged is a note about how it got there.
		//
		// The other two are `icloud` symbols because both are about the copy on
		// the other machine — one that was never made, one that has gone. The
		// counts could never have said either: nought ahead and nought behind
		// is what a branch level with its remote reads.
		let standing: (symbol: String, said: String)? = {
			if isMerged { return ("checkmark", "already merged") }
			if branch.upstreamIsGone { return ("xmark.icloud", "upstream gone") }
			if branch.isUnpublished { return ("icloud.and.arrow.up", "not published") }
			return nil
		}()

		// **A branch that has never been pushed still has a count worth
		// showing** — against the default branch, there being no upstream to
		// count from. The cloud stays beside it: *never published* and *three
		// commits of your own* are both true and neither implies the other.
		//
		// **Only the ahead half, and that is the whole care taken here.** `↑`
		// and `↓` are this pane's remote vocabulary — what is waiting to go up
		// and what is waiting to come down — and `↓1557` against the default
		// branch borrows the second of those to say something else entirely:
		// not *there are commits to pull* but *main has moved on, and you may
		// want to rebase*. It was read as the first, which is the only way it
		// could be read on a row where every other arrow means that.
		//
		// `↑` survives because it does not change meaning: commits this branch
		// has that the other side has not, which is both the work on it and
		// exactly what publishing would send. The number that could not be said
		// without misleading is not said — it is in the tooltip, in words,
		// where there is room to name what it is measured against.
		var counts = ""
		if branch.isUnpublished {
			let own = branch.aheadOfDefault ?? 0
			if own > 0 { counts = "↑\(own)" }
		} else if standing == nil {
			if branch.ahead > 0 { counts += "↑\(branch.ahead)" }
			if branch.behind > 0 { counts += (counts.isEmpty ? "" : " ") + "↓\(branch.behind)" }
		}

		let countsFont = Theme.current.uiFont(10.5)
		let countsWidth = counts.isEmpty ? 0 : ceil(NSAttributedString(
			string: counts, attributes: [.font: countsFont]
		).size().width)
		let symbolWidth = standing == nil ? 0 : RowMetrics.trailingGlyphSize
		let inner = countsWidth > 0 && symbolWidth > 0 ? Theme.current.scaled(5) : 0
		let trailingWidth = countsWidth + inner + symbolWidth

		// While it is waiting on something, the spinner has the right-hand end
		// of the row.
		let right = bounds.maxX - RowMetrics.trailingInset
			- (busy == nil ? 0 : Theme.current.scaled(18))
		let gap = Theme.current.scaled(6)

		RowMetrics.draw(
			display, font: font, colour: colour,
			at: x, in: bounds,
			limit: trailingWidth == 0 ? right : right - trailingWidth - gap
		)

		// The symbol takes the edge and the counts sit inside it, so the marks
		// of a kind line up with each other down the pane.
		if let standing {
			// **The tick is not faded, though everything beside it is.** It is
			// the reason the row is dim, and dimming the answer along with the
			// question leaves somebody looking at a grey row with nothing on it
			// saying why.
			RowMetrics.trailingGlyph(
				standing.symbol,
				colour: isMerged ? Theme.current.gitIgnored : fade(Theme.current.gitIgnored),
				in: bounds, rightAt: right
			)
		}
		guard !counts.isEmpty else { return }
		RowMetrics.drawTrailing(
			counts, font: countsFont,
			colour: fade(Theme.current.gitModified), in: bounds,
			rightAt: right - symbolWidth - inner
		)
	}
}

/// One file inside an opened stash.
/// The working copy: what you are doing, and how much of it there is.
final class WorkingCopyRowView: ActionableRowView {
	private let changed: Int

	init(changed: Int) {
		self.changed = changed
		super.init(frame: .zero)
		toolTip = changed == 0
			? "Nothing has changed"
			: "\(changed) changed file\(changed == 1 ? "" : "s")"
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let colour = changed > 0 ? Theme.current.gitModified : Theme.current.gitIgnored
		RowMetrics.glyph(
			changed > 0 ? "pencil.circle" : "checkmark.circle", colour: colour, in: bounds
		)
		// Measured first: the row's own text has to be laid out inside what the
		// action leaves, or the two are drawn over each other.
		let taken = actionWidth
		// **One line, so the two share a baseline.** Drawn separately they were
		// each centred in the row, and a ten-and-a-half-point label beside a
		// twelve-point name floats a fraction above where it belongs.
		//
		// **And `no changes` rather than `clean`.** One word in the place a
		// verb would go reads as one: the row's own action sits at the other
		// end of it and says `Review 3 changes…`, so a lone `clean` beside the
		// name looked like the button that would make it so. Reported as
		// exactly that. Two words that can only be a state cost four
		// characters and cannot be misread.
		RowMetrics.draw(
			"Working copy",
			font: Theme.current.uiFont(12, weight: .semibold),
			colour: colour,
			label: changed == 0 ? "no changes" : "\(changed)",
			labelFont: Theme.current.uiFont(10.5),
			labelColour: Theme.current.gitIgnored,
			gap: Theme.current.scaled(8),
			at: RowMetrics.textInset, in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset - taken
		)
		drawAction()
	}
}

/// One changed file, or a folder of them, under the working copy.
///
/// Its own name rather than `ChangeRowView`, which `ChangesPane` already has:
/// two files each holding a private class of one name is legal and is a trap
/// for whoever reads a stack trace next.
final class WorkingCopyChangeRowView: NSView {
	private let node: GitChangeNode
	private let staged: Bool
	override var isFlipped: Bool { true }

	init(node: GitChangeNode, staged: Bool) {
		self.node = node
		self.staged = staged
		super.init(frame: .zero)
		toolTip = node.path
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private var letter: String {
		guard let kind = node.change?.kind else { return "" }
		switch kind {
		case .added:      return "A"
		case .deleted:    return "D"
		case .renamed:    return "R"
		case .copied:     return "C"
		case .untracked:  return "?"
		case .conflicted: return "U"
		default:          return "M"
		}
	}

	private var colour: NSColor {
		guard let kind = node.change?.kind else { return Theme.current.gitIgnored }
		switch kind {
		case .added:      return Theme.current.gitAdded
		case .untracked:  return Theme.current.gitUnversioned
		case .deleted:    return Theme.current.gitConflict
		case .conflicted: return Theme.current.gitConflict
		default:          return Theme.current.gitModified
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		var x = RowMetrics.textInset

		// A folder of changes gets a folder, like a folder of branches; a file
		// gets the letter for what happened to it, in the same column.
		//
		// `holdsFiles`, so a wholly untracked directory gets one too — in the
		// colour its own kind is drawn in, which is what tells it apart from a
		// folder this tree invented. There is one column and it cannot hold both
		// a folder and a letter, so the tint carries the `?`.
		//
		// **A repository is not a folder**, and this row is where that was
		// invisible. The tree is built from superproject-relative paths, so a
		// submodule arrives as an ordinary folder — `repos` then `vehub-api`
		// then the file — and a change inside one read as a change to the
		// repository somebody has open. It was reported that way: the same
		// file, in Working copy and again under Submodules, with nothing
		// saying the first was a submodule's. `isRepository` knew all along
		// and only the driven report ever said it. The box is the glyph the
		// Submodules section already uses for the same thing.
		if node.holdsFiles {
			RowMetrics.glyph(
				node.isRepository ? "shippingbox" : "folder",
				colour: node.isFolder ? Theme.current.gitIgnored : colour,
				in: bounds
			)
		} else if !letter.isEmpty {
			RowMetrics.draw(
				letter, font: Theme.current.uiFont(11, weight: .semibold), colour: colour,
				at: RowMetrics.glyphInset + Theme.current.scaled(4), in: bounds,
				limit: bounds.maxX - RowMetrics.trailingInset
			)
		}

		x = RowMetrics.draw(
			node.name,
			font: Theme.current.uiFont(12),
			colour: node.isFolder ? Theme.current.sidebarText : colour,
			at: x, in: bounds, limit: bounds.maxX - RowMetrics.trailingInset
		)

		// A folder says how much of it is on this side, which is the one thing
		// a folder row has to say that a file row does not: two lists make a
		// folder in Staged look finished, and somebody reads it that way and
		// commits half of it.
		guard node.isFolder else { return }
		RowMetrics.draw(
			node.isPartial ? "\(node.count) of \(node.total)" : "\(node.count)",
			font: Theme.current.uiFont(10.5),
			colour: node.isPartial ? Theme.current.gitModified : Theme.current.gitIgnored,
			at: x + Theme.current.scaled(6), in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset
		)
	}
}

final class StashFileRowView: NSView {
	private let file: GitCommitFile
	override var isFlipped: Bool { true }

	init(file: GitCommitFile) {
		self.file = file
		super.init(frame: .zero)
		toolTip = file.path
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private var letter: String {
		switch file.kind {
		case .added:      return "A"
		case .deleted:    return "D"
		case .renamed:    return "R"
		case .copied:     return "C"
		case .untracked:  return "?"
		case .conflicted: return "U"
		default:          return "M"
		}
	}

	private var colour: NSColor {
		switch file.kind {
		case .added, .untracked: return Theme.current.gitAdded
		case .deleted:           return Theme.current.gitConflict
		case .conflicted:        return Theme.current.gitConflict
		default:                 return Theme.current.gitModified
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		RowMetrics.draw(
			letter, font: Theme.current.uiFont(10.5), colour: colour,
			at: RowMetrics.glyphInset, in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset
		)
		var x = RowMetrics.textInset
		// The name, with the folder it is in behind it — a stash of four files
		// three directories apart is unreadable as bare basenames.
		x = RowMetrics.draw(
			file.name, font: Theme.current.uiFont(12), colour: Theme.current.sidebarText,
			at: x, in: bounds, limit: bounds.maxX - RowMetrics.trailingInset
		)
		guard !file.directory.isEmpty else { return }
		RowMetrics.draw(
			file.directory, font: Theme.current.uiFont(10.5),
			colour: Theme.current.gitIgnored,
			at: x + Theme.current.scaled(6), in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset
		)
	}
}

/// A prefix several branches share, and how many are under it.
/// Where the head is when it is on no branch, and what git has stopped in the
/// middle of.
///
/// It sits where the ticked branch would be, and takes the tick's place in the
/// conflict colour rather than the added one: this is a place to be, but not a
/// place to commit onto — a commit made here belongs to no branch until one is
/// put on it, which is the thing this row exists to keep somebody from
/// discovering afterwards.
final class DetachedHeadRowView: NSView {
	private let notice: String
	override var isFlipped: Bool { true }

	init(notice: String) {
		self.notice = notice
		super.init(frame: .zero)
		toolTip = "Not on a branch — \(notice). A commit here belongs to no branch "
			+ "until one is put on it."
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		RowMetrics.glyph(
			"exclamationmark.triangle", colour: Theme.current.gitConflict, in: bounds
		)
		RowMetrics.draw(
			notice,
			font: Theme.current.uiFont(12, weight: .medium),
			colour: Theme.current.gitConflict,
			at: RowMetrics.textInset, in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset
		)
	}
}

final class BranchFolderRowView: NSView {
	private let display: String
	private let count: Int
	override var isFlipped: Bool { true }

	init(display: String, count: Int) {
		self.display = display
		self.count = count
		super.init(frame: .zero)
		toolTip = "\(count) branch\(count == 1 ? "" : "es") under \(display)/"
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		// No twisty and no indent: an outline view draws both, and drawing a
		// second set beside them is what made this look like several trees.
		//
		// A folder does get a folder, which is the whole of what tells it from
		// a branch of the same name at the same depth.
		RowMetrics.glyph("folder", colour: Theme.current.gitIgnored, in: bounds)
		let x = RowMetrics.textInset
		// **No trailing slash.** It was there to say "a prefix, not a branch
		// called `feature`" back when this was a flat list with nothing else to
		// say it. The disclosure triangle says it now — and the same row draws
		// `Staged` and `Unstaged`, which are not prefixes at all and read as
		// nonsense with one.
		RowMetrics.draw(
			display,
			font: Theme.current.uiFont(12),
			colour: Theme.current.sidebarText,
			at: x, in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset - Theme.current.scaled(24)
		)
		// **On the trailing edge, not after the name.** Drawn where the name
		// happened to end, the counts landed at a different x on every row —
		// `feature 1` and `renovate 2` two characters apart — so a column of
		// numbers could not be read as a column. Everything else on this row's
		// right-hand end is trailing-aligned already: the ahead and behind
		// counts on a branch, the cloud on an unpublished one.
		RowMetrics.drawTrailing(
			"\(count)",
			font: Theme.current.uiFont(10.5),
			colour: Theme.current.gitIgnored,
			in: bounds,
			rightAt: bounds.maxX - RowMetrics.trailingInset
		)
	}
}

/// A stash: what it was called, and how long it has been waiting.
final class StashRowView: NSView {
	private let entry: GitStash.Entry
	private let isOpen: Bool
	/// Whether it would still go back, once that has been asked. Nil until the
	/// row has been opened, because asking costs a three-way merge.
	private let applies: GitStash.Applicability?
	override var isFlipped: Bool { true }

	init(entry: GitStash.Entry, isOpen: Bool = false, applies: GitStash.Applicability? = nil) {
		self.entry = entry
		self.isOpen = isOpen
		self.applies = applies
		super.init(frame: .zero)

		var said = [entry.reference, entry.branch.isEmpty ? nil : "on \(entry.branch)", entry.age]
			.compactMap { $0 }
		switch applies {
		case .clean:                 said.append("applies cleanly")
		case let .conflicts(paths):  said.append("would conflict in \(paths.joined(separator: ", "))")
		case .unknown, .none:        break
		}
		toolTip = said.joined(separator: " — ")
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x = RowMetrics.textInset

		RowMetrics.glyph(
			isOpen ? "tray.full.fill" : "tray.full",
			colour: Theme.current.sidebarText, in: bounds
		)

		// How long it has been sitting there decides whether it is still
		// wanted, so it keeps its room and the message gives way first.
		let ageFont = Theme.current.uiFont(10.5)
		let ageWidth = entry.age.isEmpty ? 0 : NSAttributedString(
			string: entry.age, attributes: [.font: ageFont]
		).size().width + Theme.current.scaled(8)

		// Whether it would still go back, in the colour that already means
		// "this is fine" and "this is not" everywhere else in this window.
		var mark = ""
		var markColour = Theme.current.gitAdded
		switch applies {
		case .clean:
			mark = "✓"
		case let .conflicts(paths):
			mark = "⚠\(paths.count)"
			markColour = Theme.current.gitModified
		case .unknown, .none:
			break
		}
		let markFont = Theme.current.uiFont(10.5)
		let markWidth = mark.isEmpty ? 0 : NSAttributedString(
			string: mark, attributes: [.font: markFont]
		).size().width + Theme.current.scaled(8)

		let limit = bounds.maxX - RowMetrics.trailingInset
		x = RowMetrics.draw(
			entry.message, font: Theme.current.uiFont(12), colour: Theme.current.sidebarText,
			at: x, in: bounds, limit: limit - ageWidth - markWidth
		)

		if !entry.age.isEmpty {
			x = RowMetrics.draw(
				entry.age, font: ageFont,
				colour: Theme.current.sidebarText.withAlphaComponent(0.55),
				at: x + Theme.current.scaled(8), in: bounds, limit: limit - markWidth
			)
		}
		guard !mark.isEmpty else { return }
		RowMetrics.draw(
			mark, font: markFont, colour: markColour,
			at: x + Theme.current.scaled(8), in: bounds, limit: limit
		)
	}
}

/// A worktree: where it is, what is checked out there, and whether it is still
/// on disk.
/// One submodule: what it is called, and the one thing about it that needs
/// somebody.
///
/// **Not a branch row wearing a different hat.** A branch row says ahead and
/// behind against a remote; this says whichever of four different things is
/// currently true — its merge is unresolved, it has uncommitted work, it has
/// commits to push, or the superproject records it somewhere else. Which of
/// them it is, is the whole reason the row is in this section rather than
/// counted into the clean ones.
/// Internal rather than private only so the driven row report can borrow
/// `said`: what a row draws and what a report claims it draws must be the one
/// sentence, or the report cannot catch the row being wrong.
final class SubmoduleRowView: NSView {
	let row: GitEstateRow
	override var isFlipped: Bool { true }

	init(row: GitEstateRow) {
		self.row = row
		super.init(frame: .zero)
		toolTip = "\(row.path) — \(Self.said(row))"
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// What the row says about itself, in the same words the overview uses.
	static func said(_ row: GitEstateRow) -> String {
		switch row.state {
		case .conflicted:         return row.conflict != nil ? "gitlink conflict" : "conflicted"
		case .changed(let count): return "\(count) changed"
		case .ahead(let count):   return "\(count) to push"
		case .moved:              return "moved"
		case .clean:              return "clean"
		case .unread:             return "reading\u{2026}"
		case .absent:             return "not checked out"
		}
	}

	private var tint: NSColor {
		switch row.state {
		case .conflicted:    return Theme.current.gitConflict
		case .changed:       return Theme.current.gitModified
		case .ahead, .moved: return Theme.current.gitAdded
		default:             return Theme.current.gitIgnored
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		RowMetrics.glyph("shippingbox", colour: tint, in: bounds)
		let after = RowMetrics.draw(
			row.path,
			font: Theme.current.uiFont(12),
			colour: Theme.current.sidebarText,
			at: RowMetrics.textInset, in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset - Theme.current.scaled(90)
		)
		RowMetrics.draw(
			Self.said(row),
			font: Theme.current.uiFont(10.5),
			colour: tint,
			at: after + Theme.current.scaled(6), in: bounds,
			limit: bounds.maxX - RowMetrics.trailingInset
		)
	}
}

final class WorktreeRowView: NSView {
	private let worktree: GitWorktree
	override var isFlipped: Bool { true }

	init(worktree: GitWorktree) {
		self.worktree = worktree
		super.init(frame: .zero)
		toolTip = worktree.path.path
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x = Theme.current.scaled(18)

		// The one the repository was cloned into is marked, since it is the one
		// that cannot be removed.
		let symbol = worktree.isPrimary ? "house" : (worktree.isMissing ? "questionmark.circle" : "folder")
		let tint = worktree.isMissing ? Theme.current.gitUnversioned : Theme.current.gitIgnored
		if let icon = Theme.symbol(symbol, size: 10 * Theme.current.scale, color: tint) {
			let size = Theme.current.scaled(11)
			icon.drawFitted(in: NSRect(
				x: Theme.current.scaled(4), y: bounds.midY - size / 2, width: size, height: size
			))
		}

		let limit = bounds.maxX - RowMetrics.trailingInset
		x = RowMetrics.draw(
			worktree.name,
			font: Theme.current.uiFont(12),
			colour: worktree.isMissing ? Theme.current.gitIgnored : Theme.current.sidebarText,
			at: x, in: bounds, limit: limit
		)

		var note = worktree.branch ?? "detached"
		// **Which ones this program made to read somebody else's work.** A
		// checkout made for a review is temporary and belongs to a pull request
		// rather than to a piece of work; saying so is what makes them
		// collectable, and a reviewer who opens three a day would otherwise grow
		// three checkouts a day named after strangers' branches.
		if let number = ReviewCheckouts.shared.number(of: worktree.path) {
			note += " · PR #\(number)"
		}
		if worktree.isMissing { note += " · missing" }
		if worktree.isLocked { note += " · locked" }

		RowMetrics.draw(
			note,
			font: Theme.current.uiFont(10),
			colour: worktree.isMissing ? Theme.current.gitUnversioned : Theme.current.gitIgnored,
			at: x + Theme.current.scaled(6), in: bounds, limit: limit
		)
	}
}
