import AppKit
import AbydosKit

/// The strip above the refs tree while git is in the middle of something.
///
/// **It used to be about conflicted files, and that was half the state.** It
/// appeared when `git status` reported unmerged paths and went away when the
/// last one was resolved — which is the moment a rebase most needs saying
/// something, because resolving the files is not finishing the rebase. There
/// was nothing anywhere in this app that ran `git rebase --continue`, so the
/// flow ended in the middle: resolve, stage, and then go and find a terminal.
///
/// So it is about the operation now. It shows for as long as one is in
/// progress, says which stage it is at, and carries the verbs that end it.
///
/// **Then it said the wrong sentence about it.** Three faults, all of them
/// visible in one screenshot of a stopped merge:
///
/// - The headline named a commit. `GitConflicts.describe` answers a merge with
///   `"Merging " + git log -1 --format='%h %s' MERGE_HEAD` — a short hash and
///   the whole subject of somebody else's commit, sixty characters and a
///   truncation, with the one thing you want — which branch is coming in — not
///   in it. It says `Merging side into main` now, and `sides(of:in:)` is where
///   the names come from.
/// - The one actionable fact was a number, and the quietest thing in the strip.
///   `3 files conflicted`, with a `Files` button that opened all of them at
///   once and a `Continue` that was grey for a reason kept in a tooltip.
///   The files are rows now; they tick off as they resolve; `Continue` lights
///   when the last one turns, and the list is the explanation.
/// - Six controls in two rows, with `Abort` — the one that throws work away —
///   full size and directly under the primary verb that was not. One verb at
///   full width now, `Skip` beside it where the operation has one, and
///   everything else behind `⋯`.
///
/// And it is a card inset from the pane rather than a full-bleed wash with hard
/// edges. Nothing has failed here: git is waiting.
final class OperationBanner: NSView {
	/// Opens every conflicted file at once — still offered, behind `⋯`, for a
	/// stop with more files in it than the list will draw.
	var onOpenFiles: (() -> Void)?
	var onOpenInFork: (() -> Void)?
	var onCopyPrompt: (() -> Void)?
	/// `--continue`, `--skip` and `--abort`.
	var onCarryOn: (() -> Void)?
	var onSkip: (() -> Void)?
	var onAbort: (() -> Void)?

	/// One file: open it in the editor, take one whole side of it, or stage it
	/// as it stands because somebody has already written the answer into it.
	var onOpenFile: ((String) -> Void)?
	var onTake: ((GitConflicts.Side, String) -> Void)?
	var onMarkResolved: ((String) -> Void)?

	/// How many rows the list draws before it says how many more there are.
	///
	/// A merge of forty files would otherwise take the pane, and the branches
	/// under it are the thing the pane is for. `Open All Files` in the `⋯` menu
	/// is what the rest is reached by.
	private static let rowsShown = 6

	private let card = NSView()
	private let rule = NSView()
	private let label = NSTextField(labelWithString: "")
	private let position = NSTextField(labelWithString: "")
	private let state = NSTextField(labelWithString: "")
	private let why = NSTextField(labelWithString: "")
	private let bar = NSProgressIndicator()
	private var files: NSStackView!
	private var buttons: NSStackView!
	private var stack: NSStackView!

	private let carryOnButton: NSButton
	private let skipButton: NSButton
	private let moreButton: NSButton

	/// The names for the two halves of this conflict, in the words of this
	/// operation — never "ours" and "theirs", which swap meaning between a
	/// merge and a rebase. See `GitConflicts.Side`.
	private var sides: (ours: String, theirs: String) = ("", "")

	/// What the label last said, for a driven run to read.
	private(set) var said = ""
	private var waiting: [GitConflicts.Waiting] = []
	private var overflow = 0

	override init(frame frameRect: NSRect) {
		func button(_ title: String) -> NSButton {
			let made = NSButton(title: title, target: nil, action: nil)
			made.bezelStyle = .rounded
			made.controlSize = .small
			made.font = Theme.current.uiFont(10.5)
			return made
		}
		carryOnButton = button("Continue")
		skipButton = button("Skip")
		moreButton = button("⋯")
		moreButton.toolTip = "Everything else this operation can do"
		moreButton.setAccessibilityLabel("More")

		super.init(frame: frameRect)
		let theme = Theme.current

		// **A card, not a banner.** A full-bleed wash with hard edges top and
		// bottom, running out under the sidebar rail, reads as something having
		// gone wrong. Nothing has: git stopped and is waiting for an answer.
		// Inset and rounded, with the conflict colour as a rule down the left,
		// says the window is in a mode — which is what is true.
		card.wantsLayer = true
		card.layer?.cornerRadius = theme.scaled(7)
		card.layer?.backgroundColor = theme.gitConflict.withAlphaComponent(0.13).cgColor
		rule.wantsLayer = true
		rule.layer?.backgroundColor = theme.gitConflict.cgColor
		isHidden = true

		label.font = theme.uiFont(11.5, weight: .semibold)
		label.textColor = theme.gitConflict
		// **It wraps rather than truncating.** The headline is two branch names
		// now, and a name is the half a truncation eats. Two lines in a strip
		// that is already the tallest thing in the pane costs nothing.
		label.lineBreakMode = .byWordWrapping
		label.maximumNumberOfLines = 3
		label.cell?.usesSingleLineMode = false

		position.font = theme.uiFont(10.5)
		position.textColor = theme.sidebarText
		position.lineBreakMode = .byTruncatingTail
		state.font = theme.uiFont(10.5, weight: .medium)
		state.textColor = theme.sidebarHeaderText
		state.lineBreakMode = .byTruncatingTail
		why.font = theme.uiFont(9.5)
		why.textColor = theme.sidebarText.withAlphaComponent(0.6)
		why.lineBreakMode = .byWordWrapping
		why.maximumNumberOfLines = 2
		why.cell?.usesSingleLineMode = false

		bar.style = .bar
		bar.isIndeterminate = false
		bar.controlSize = .small
		bar.minValue = 0

		for (made, action) in [
			(carryOnButton, #selector(carryOn)),
			(skipButton, #selector(skip)),
			(moreButton, #selector(showMore)),
		] as [(NSButton, Selector)] {
			made.target = self
			made.action = action
		}
		// The default button: ⏎ on this pane finishes what git started.
		carryOnButton.keyEquivalent = "\r"
		// **The primary verb takes the width it can get.** It is the reason the
		// strip is here. The other two size to their titles.
		carryOnButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
		for made in [skipButton, moreButton] {
			made.setContentCompressionResistancePriority(.required, for: .horizontal)
			made.setContentHuggingPriority(.required, for: .horizontal)
		}

		files = NSStackView(views: [])
		files.orientation = .vertical
		files.alignment = .leading
		files.spacing = 0

		buttons = NSStackView(views: [carryOnButton, skipButton, moreButton])
		buttons.orientation = .horizontal
		buttons.spacing = theme.scaled(6)
		buttons.alignment = .centerY
		buttons.distribution = .fill

		// **One stack, because hidden views must take no room.** The rows were
		// pinned to each other, and a plain `isHidden` leaves the constraints
		// standing: a merge — which has no `1 of n` to draw, so no bar and no
		// position line — left a hole where they would have been and pushed the
		// buttons out through the bottom of the strip and over the repository
		// row. A stack view excludes what is hidden, which is the behaviour
		// this needed all along.
		let rows = NSStackView(views: [label, bar, position, state, files, buttons, why])
		rows.orientation = .vertical
		rows.alignment = .leading
		rows.spacing = theme.scaled(3)
		rows.setCustomSpacing(theme.scaled(6), after: state)
		rows.setCustomSpacing(theme.scaled(6), after: files)
		rows.setHuggingPriority(.required, for: .vertical)
		stack = rows

		addSubview(card)
		card.addSubview(rule)
		card.addSubview(rows)
		for view in [card, rule, rows] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
		}
		let outer = theme.scaled(8)
		let inner = theme.scaled(9)
		NSLayoutConstraint.activate([
			card.topAnchor.constraint(equalTo: topAnchor, constant: outer / 2),
			card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -outer / 2),
			card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: outer),
			card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -outer),

			rule.leadingAnchor.constraint(equalTo: card.leadingAnchor),
			rule.topAnchor.constraint(equalTo: card.topAnchor),
			rule.bottomAnchor.constraint(equalTo: card.bottomAnchor),
			rule.widthAnchor.constraint(equalToConstant: theme.scaled(2)),

			rows.topAnchor.constraint(equalTo: card.topAnchor, constant: theme.scaled(7)),
			rows.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -theme.scaled(7)),
			rows.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inner),
			rows.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inner),

			// The bar and the buttons span the card; everything else sizes to
			// its text.
			bar.widthAnchor.constraint(equalTo: rows.widthAnchor),
			buttons.widthAnchor.constraint(equalTo: rows.widthAnchor),
			files.widthAnchor.constraint(equalTo: rows.widthAnchor),
			label.widthAnchor.constraint(equalTo: rows.widthAnchor),
			why.widthAnchor.constraint(equalTo: rows.widthAnchor),
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: - What it says

	/// - Parameter operation: what git is in the middle of, which decides which
	///   verbs are offered at all — a merge has no `--skip`.
	/// - Parameter waiting: every file this stop is waiting on, resolved ones
	///   included and ticked. See `GitConflicts.waiting(in:alsoShowing:)`.
	/// - Parameter staged: whether anything is staged, which is the difference
	///   between "resolved, ready to go on" and "nothing here to commit".
	/// - Parameter sides: what to call the two halves, in branch names.
	///
	/// **The label says the stage, not the state.** `Rebasing — 2 files
	/// conflicted` and `Rebasing — resolved, ready to continue` are the two
	/// halves of the thing this pane got wrong: the second one used to be no
	/// banner at all, which read as the rebase being over.
	func show(
		operation: GitConflicts.Operation,
		waiting: [GitConflicts.Waiting],
		staged: Bool,
		what: String?,
		sides: (ours: String, theirs: String),
		progress: GitConflicts.Progress?
	) {
		self.waiting = waiting
		self.sides = sides

		// **Both branches, named.** `Merging side into main` — the sentence
		// somebody would say out loud about what the window is in the middle
		// of. `describe` is kept as the fallback for a stop with no names to
		// hand: a merge of a bare commit, a cherry-pick, a revert.
		switch operation {
		case .merge where !sides.ours.isEmpty && !sides.theirs.isEmpty:
			label.stringValue = "Merging \(sides.theirs) into \(sides.ours)"
		case .rebase:
			if let progress, let branch = progress.branch {
				label.stringValue = progress.onto.map {
					"Rebasing \(branch) onto \(sides.ours.isEmpty ? $0 : sides.ours)"
				} ?? "Rebasing \(branch)"
			} else {
				label.stringValue = what ?? operation.titled
			}
		default:
			label.stringValue = what ?? operation.titled
		}

		if let progress, progress.total > 0 {
			bar.isHidden = false
			bar.maxValue = Double(progress.total)
			// **Half a step for the one in hand.** The commit being applied is
			// neither done nor untouched, and counting only the finished ones
			// draws an empty bar at `commit 1 of 3` — which reads as a rebase
			// that has not started, at the moment it is waiting on you.
			bar.doubleValue = Double(progress.position) - 0.5
			position.isHidden = false
			position.stringValue = "commit \(progress.position) of \(progress.total)"
				+ (progress.subject.map { " · \($0)" } ?? "")
		} else {
			bar.isHidden = true
			position.isHidden = true
			position.stringValue = ""
		}

		let title = label.stringValue
		// Truncation is the price of a narrow sidebar; losing the words is
		// not. Whatever the strip cannot show, it says under the pointer.
		label.toolTip = title
		position.toolTip = position.stringValue

		let left = waiting.filter { !$0.isResolved }.count
		let done = waiting.count - left
		if left > 0 {
			said = "\(title) — \(left) file\(left == 1 ? "" : "s") conflicted"
			// `2 of 3 resolved` once anything has been, because that is the
			// half that is moving. `3 files still have conflict markers` at the
			// start, which says what to do about them without a second line.
			state.stringValue = done > 0
				? "\(done) of \(waiting.count) resolved"
				: left == 1
					? "1 file still has conflict markers"
					: "\(left) files still have conflict markers"
			why.stringValue = "Click a file to open it. Right-click for the two sides."
			why.isHidden = false
		} else if staged {
			said = "\(title) — resolved, ready to continue"
			state.stringValue = waiting.isEmpty
				? "Resolved — ready to continue"
				: "All \(waiting.count) resolved — ready to continue"
			why.isHidden = true
		} else {
			// Nothing conflicted and nothing staged: the commit in hand has
			// become empty, which is what `--skip` is for. Said plainly,
			// because `git` will otherwise say it as an error after the press.
			said = operation.canSkip
				? "\(title) — nothing left to apply, skip this commit"
				: "\(title) — nothing staged"
			state.stringValue = operation.canSkip
				? "Nothing left to apply — Skip it"
				: "Nothing staged"
			why.isHidden = true
		}

		drawFiles()

		// Only the verbs that mean something here. A merge cannot skip.
		skipButton.isHidden = !operation.canSkip
		carryOnButton.isEnabled = left == 0
		carryOnButton.toolTip = left == 0
			? nil
			: "Resolve the conflicted files first — git will not carry on over markers."
	}

	/// The list, rebuilt. Cheap: at most `rowsShown` small views, and the strip
	/// is redrawn on the same events that redraw the tree beneath it.
	private func drawFiles() {
		for view in files.arrangedSubviews {
			files.removeArrangedSubview(view)
			view.removeFromSuperview()
		}
		overflow = max(0, waiting.count - Self.rowsShown)
		files.isHidden = waiting.isEmpty
		guard !waiting.isEmpty else { return }

		for file in waiting.prefix(Self.rowsShown) {
			let row = ConflictFileRow(waiting: file)
			row.onOpen = { [weak self] in self?.onOpenFile?(file.path) }
			row.buildMenu = { [weak self] in self?.menu(for: file) }
			files.addArrangedSubview(row)
			row.translatesAutoresizingMaskIntoConstraints = false
			row.widthAnchor.constraint(equalTo: files.widthAnchor).isActive = true
		}

		// **What was cut is named, not dropped.** A list that silently stops at
		// six reads as a merge of six files.
		if overflow > 0 {
			let more = NSTextField(labelWithString: "and \(overflow) more…")
			more.font = Theme.current.uiFont(9.5)
			more.textColor = Theme.current.sidebarText.withAlphaComponent(0.55)
			more.toolTip = "Open All Files, under ⋯, opens every one of them."
			files.addArrangedSubview(more)
		}
	}

	/// What one file offers.
	///
	/// **Named by branch, never "ours" and "theirs".** Stage 2 is `--ours` in
	/// both a merge and a rebase and they are opposite halves: rebasing replays
	/// your commits onto somebody else's, so the branch you are on arrives as
	/// `--theirs`. A menu item saying "Use Ours" during a rebase is one that
	/// throws away the wrong half, and nobody would be able to tell from the
	/// wording that it had.
	private func menu(for file: GitConflicts.Waiting) -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false

		let open = NSMenuItem(title: "Open", action: #selector(openOne(_:)), keyEquivalent: "")
		open.target = self
		open.representedObject = file.path
		menu.addItem(open)

		guard !file.isResolved else {
			// Resolved and staged. The stages are gone from the index, so the
			// conflict cannot be put back — `git checkout -m` needs them — and
			// an item that would fail is not offered.
			let done = NSMenuItem(title: "Resolved — staged", action: nil, keyEquivalent: "")
			done.isEnabled = false
			menu.addItem(.separator())
			menu.addItem(done)
			return menu
		}

		menu.addItem(.separator())
		for (side, name) in [
			(GitConflicts.Side.ours, sides.ours), (GitConflicts.Side.theirs, sides.theirs),
		] where !name.isEmpty {
			let item = NSMenuItem(
				title: "Use \(name)",
				action: side == .ours ? #selector(takeOurs(_:)) : #selector(takeTheirs(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = file.path
			item.toolTip = "Replace the whole file with \(name)'s version and stage it"
			menu.addItem(item)
		}

		menu.addItem(.separator())
		// **The manual path, which is the usual one.** Open the file, edit the
		// markers away, come back and say so. It is offered whether or not the
		// markers have gone — a file can legitimately contain the characters,
		// and `Waiting.markers` is a count to warn on, not a rule to enforce.
		let mark = NSMenuItem(
			title: "Mark Resolved", action: #selector(markResolved(_:)), keyEquivalent: ""
		)
		mark.target = self
		mark.representedObject = file.path
		mark.toolTip = file.markers > 0
			? "\(file.markers) conflict marker\(file.markers == 1 ? "" : "s") still in it — "
				+ "it will be staged as it stands"
			: "Stage it as it stands"
		menu.addItem(mark)
		return menu
	}

	/// Everything the row of buttons no longer has room for.
	private func moreMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false

		let open = NSMenuItem(
			title: "Open All Files", action: #selector(openFiles), keyEquivalent: ""
		)
		open.target = self
		open.isEnabled = waiting.contains { !$0.isResolved }
		menu.addItem(open)

		let prompt = NSMenuItem(
			title: "Copy Prompt", action: #selector(copyPrompt), keyEquivalent: ""
		)
		prompt.target = self
		prompt.toolTip = "Copy a description of the conflict, to paste into a session"
		menu.addItem(prompt)

		if onOpenInFork != nil {
			let fork = NSMenuItem(
				title: "Open in Fork", action: #selector(openInFork), keyEquivalent: ""
			)
			fork.target = self
			menu.addItem(fork)
		}

		// **Furthest from the one they came to press**, which the two-row
		// layout claimed and did not manage: last on the second row is beside
		// first on the first. Behind a menu it is a deliberate second gesture.
		menu.addItem(.separator())
		let abort = NSMenuItem(title: "Abort", action: #selector(abort), keyEquivalent: "")
		abort.target = self
		menu.addItem(abort)
		return menu
	}

	/// How tall the strip wants to be — asked of what is in it rather than
	/// counted in points.
	///
	/// **Measured, because the guess was wrong.** It was `66 or 100, plus 24
	/// for the helpers`: three numbers standing in for what the strip is
	/// actually showing, which is how a merge — no bar, no position line, two
	/// rows of buttons — came out short and drew its second row over the
	/// repository row beneath it. Nothing needs to know the line count now.
	var wantedHeight: CGFloat {
		// The stack knows: it has excluded whatever is hidden and laid out the
		// rest at the width it has been given.
		layoutSubtreeIfNeeded()
		return ceil(stack.fittingSize.height) + Theme.current.scaled(22)
	}

	/// What a driven run reads off the banner: the sentence, which verbs are
	/// pressable, and every row of the list with its state.
	var reportForTesting: String {
		let offered = [
			("continue", carryOnButton), ("skip", skipButton), ("more", moreButton),
		].compactMap { name, made -> String? in
			guard !made.isHidden, !(made.superview?.isHidden ?? false) else { return nil }
			return made.isEnabled ? name : "\(name)(off)"
		}
		let counted = bar.isHidden
			? ""
			: " {\(bar.doubleValue)/\(Int(bar.maxValue)) \(position.stringValue)}"
		let listed = waiting.isEmpty
			? ""
			: " files=" + waiting.prefix(Self.rowsShown).map {
				($0.isResolved ? "✓" : "◆") + $0.path
					+ ($0.isResolved || $0.markers == 0 ? "" : "(\($0.markers))")
			}.joined(separator: ",")
			+ (overflow > 0 ? ",+\(overflow)" : "")
		// The two heights, because the strip getting them wrong is what a
		// screenshot of the sidebar cannot show: a banner shorter than its
		// content draws its buttons over the row below.
		let sizes = "fits=\(Int(stack.fittingSize.height)) tall=\(Int(frame.height))"
		return "BANNER \(isHidden ? "hidden" : "shown"): \(said)\(counted)"
			+ " state=\"\(state.stringValue)\""
			+ " [\(offered.joined(separator: " "))]\(listed) \(sizes)"
	}

	/// What the `⋯` menu holds, and what one file's menu holds — neither of
	/// which a screenshot of a closed menu can be asked about.
	func menuForTesting(_ which: String) -> String {
		let menu: NSMenu
		if which.isEmpty || which == "more" {
			menu = moreMenu()
		} else if let file = waiting.first(where: { $0.path == which || $0.name == which }) {
			menu = self.menu(for: file)
		} else {
			return "no file called \(which)"
		}
		return menu.items.map {
			$0.isSeparatorItem ? "—" : ($0.isEnabled ? $0.title : "\($0.title)(off)")
		}.joined(separator: " | ")
	}

	/// Presses a row's menu item, the way a right-click and a choice would.
	func resolveForTesting(_ path: String, _ how: String) -> String {
		guard waiting.contains(where: { $0.path == path }) else { return "not waiting on \(path)" }
		switch how {
		case "ours":   onTake?(.ours, path)
		case "theirs": onTake?(.theirs, path)
		case "mark":   onMarkResolved?(path)
		case "open":   onOpenFile?(path)
		default:       return "no such resolution \(how)"
		}
		return "\(how) \(path)"
	}

	func pressForTesting(_ name: String) {
		switch name {
		case "continue": if carryOnButton.isEnabled { carryOn() }
		case "skip":     skip()
		case "abort":    abort()
		case "prompt":   copyPrompt()
		case "open":     openFiles()
		default:         print("BANNER: no button called \(name)")
		}
	}

	@objc private func showMore() {
		let menu = moreMenu()
		menu.popUp(
			positioning: nil,
			at: NSPoint(x: 0, y: moreButton.bounds.height + Theme.current.scaled(2)),
			in: moreButton
		)
	}

	@objc private func openOne(_ sender: NSMenuItem) {
		guard let path = sender.representedObject as? String else { return }
		onOpenFile?(path)
	}

	@objc private func takeOurs(_ sender: NSMenuItem) {
		guard let path = sender.representedObject as? String else { return }
		onTake?(.ours, path)
	}

	@objc private func takeTheirs(_ sender: NSMenuItem) {
		guard let path = sender.representedObject as? String else { return }
		onTake?(.theirs, path)
	}

	@objc private func markResolved(_ sender: NSMenuItem) {
		guard let path = sender.representedObject as? String else { return }
		onMarkResolved?(path)
	}

	@objc private func openFiles() { onOpenFiles?() }
	@objc private func openInFork() { onOpenInFork?() }
	@objc private func copyPrompt() { onCopyPrompt?() }
	@objc private func carryOn() { onCarryOn?() }
	@objc private func skip() { onSkip?() }
	@objc private func abort() { onAbort?() }
}
