import AppKit
import AbydosKit

/// Driving the backlog from a script: what a card's menu offers, what the tasks
/// under a card say, and the tip that opens over one.
extension BacklogPane {
	// MARK: - Driving it

	/// What a card's menu offers, as one line.
	///
	/// A menu is the part of this pane a screenshot cannot photograph without a
	/// click, and the pane is in the app target where the suite cannot reach it.
	/// So it is checked by opening the real window on a real backlog and asking
	/// the real menu what it says.
	/// Whether the board has anything on it yet, for a driver that must not ask
	/// before it does.
	///
	/// **The report used to be printed on a three-second timer**, and against
	/// the OpenSpec record three seconds is not enough: every change's fraction
	/// comes from the CLI, which is found through the login shell and started
	/// once per change. The board was empty, and what the driver printed was
	/// "no change called … on the board" — which reads exactly like a card that
	/// is missing.
	var hasCardsForTesting: Bool {
		columns.contains { !entries(in: $0).isEmpty }
	}

	func menuTitlesForTesting(number: Int) -> String {
		let found = BacklogState.board
			.compactMap { cards(in: $0).first { $0.number == number } }
			.first
		guard let card = found else { return "no item \(number) on the board" }
		return menu(for: card).items
			.map { $0.isSeparatorItem ? "\u{2014}" : $0.title }
			.joined(separator: " | ")
	}

	/// The same, for a change — which has a name where an item has a number.
	///
	/// Its own verb rather than a cleverness over the other one: the two records
	/// are addressed differently, and a driver that had to know `0540` means an
	/// item and `find-bands-follow-soft-wrap` means a change would be one that
	/// guesses.
	func menuTitlesForTesting(change name: String) -> String {
		let found = columns
			.flatMap { entries(in: $0) }
			.compactMap { entry -> OpenSpecCard? in
				guard case let .change(card) = entry, card.name == name else { return nil }
				return card
			}
			.first
		guard let card = found else { return "no change called \(name) on the board" }
		return "[\(card.state.rawValue)] " + menu(for: card).items
			.map { $0.isSeparatorItem ? "\u{2014}" : $0.title }
			.joined(separator: " | ")
	}

	// MARK: The task tip

	/// What the tip lists for a named card, for `--backlog-tasks`.
	///
	/// **Opened through the column's own hand-off**, so what is driven is what
	/// the pointer does: a harness that built a list of its own would pass with
	/// the hit test wired to nothing.
	func taskTipReportForTesting(change name: String) -> String {
		report(of: .change(name))
	}

	func taskTipReportForTesting(number: Int) -> String {
		report(of: .item(number))
	}

	/// Ticks the n-th open task through the tip's own click handler, and says
	/// what the fraction is afterwards.
	///
	/// One-based, because the report above numbers its rows from one and the
	/// two are read together.
	func tickOpenTaskForTesting(change name: String, index: Int) -> String {
		tick(.change(name), index: index)
	}

	func tickOpenTaskForTesting(number: Int, index: Int) -> String {
		tick(.item(number), index: index)
	}

	/// Draws the tip to a PNG, since a child window is invisible to a capture
	/// of the main one.
	func writeTaskTipImageForTesting(to path: String) -> String {
		guard TaskTip.shared.isShowing else { return "no tip is open" }
		return TaskTip.shared.writeImageForTesting(to: path) ? "wrote \(path)" : "could not write \(path)"
	}

	private func report(of identity: BoardEntry.Identity) -> String {
		guard let opened = openTheTip(on: identity) else { return missing(identity) }
		if case let .noTip(why) = opened { return why }
		return TaskTip.shared.reportForTesting
	}

	private func tick(_ identity: BoardEntry.Identity, index: Int) -> String {
		guard let opened = openTheTip(on: identity) else { return missing(identity) }
		if case let .noTip(why) = opened { return why }
		let said = TaskTip.shared.tickForTesting(row: index - 1)
		// After the write, from the file rather than from the card: the walk
		// this kicked off runs off the main thread and has not come back.
		let entry = self.entry(with: identity)
		let file = entry?.checklistFile
		let now = file.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
			.flatMap(BacklogItem.progress(in:))
		return "\(said) \u{2192} \(now?.summary ?? "no fraction")"
	}

	/// What happened when the tip was asked to open on a card, with the sentence
	/// to print where it did not.
	private enum Opening {
		case opened
		case noTip(String)
	}

	/// Finds the card, and hands it to the tip the way the column does.
	private func openTheTip(on identity: BoardEntry.Identity) -> Opening? {
		guard let entry = entry(with: identity) else { return nil }
		guard entry.isInProgress else {
			return .noTip("the card is in \(entry.column.title) and has no tip")
		}
		guard mode == .board else { return .noTip("the list is showing, and it has no tip") }
		guard let view = boardView.columnViewsForTesting.first(where: { $0.column == entry.column })
		else { return .noTip("no column on the board for \(entry.column.title)") }
		view.openTheTipForTesting(on: entry)
		return .opened
	}

	private func missing(_ identity: BoardEntry.Identity) -> String {
		switch identity {
		case let .item(number):  return "no item \(number) on the board"
		case let .change(name):  return "no change called \(name) on the board"
		}
	}

	/// Files an item the way the button does, and says where it landed.
	func newItemForTesting(titled title: String) -> String {
		guard hasBacklog else { return "no backlog" }
		guard let item = createItem(titled: title) else { return "nothing made" }
		let where_ = (item.folder ?? item.file).path
		let prefix = backlog.projectRoot.path + "/"
		return "\(String(format: "%04d", item.number))  \(item.state.directoryName)/  "
			+ (where_.hasPrefix(prefix) ? String(where_.dropFirst(prefix.count)) : where_)
	}

	/// Whether the pane is offering to make a backlog rather than showing one.
	var isOfferingToMakeOneForTesting: Bool { !hasBacklog }

	/// Makes a backlog the way the button does, and says what is there now.
	func makeBacklogForTesting() -> String {
		guard !hasBacklog else { return "there is one already" }
		makeBacklog(for: BacklogAssistant.allCases.filter(\.isInstalled))
		return hasBacklog ? "made, and the pane is showing it" : "not made"
	}

	/// The menu a card and a row both use.
	///
	/// Given the card rather than the item, because where an item is being
	/// worked on is not in the item: it is a run recorded beside the project,
	/// which the card already carries in order to draw the branch on it.
	func menu(for card: BacklogCard) -> NSMenu {
		let item = card.item
		let menu = NSMenu()

		let open = NSMenuItem(title: "Open", action: #selector(openFromMenu(_:)), keyEquivalent: "")
		open.target = self
		open.representedObject = item
		menu.addItem(open)

		if item.state == .ready {
			let start = NSMenuItem(
				title: "Start in a Worktree\u{2026}",
				action: #selector(startFromMenu(_:)),
				keyEquivalent: ""
			)
			start.target = self
			start.representedObject = item
			menu.addItem(start)
		}

		// Offered only where there is something to open.
		//
		// `isPresent` is the question, not whether a run was ever recorded: the
		// run file is this machine's note that a checkout was made, and a
		// checkout somebody removed with `rm -rf` leaves the note behind. An
		// entry that opened a window on a directory that is not there would
		// fail after the click rather than before it — and the card already
		// uses the same test to decide whether to draw the branch name, so the
		// menu and the card agree by construction.
		if let run = card.run, run.isPresent {
			let asProject = NSMenuItem(
				title: "Open Worktree as a Project",
				action: #selector(openWorktreeFromMenu(_:)),
				keyEquivalent: ""
			)
			asProject.target = self
			asProject.representedObject = run.worktree
			asProject.toolTip = run.worktreePath
			menu.addItem(asProject)

			let terminal = NSMenuItem(
				title: "Open Terminal in Worktree",
				action: #selector(openWorktreeTerminalFromMenu(_:)),
				keyEquivalent: ""
			)
			terminal.target = self
			terminal.representedObject = run.worktree
			terminal.toolTip = run.worktreePath
			menu.addItem(terminal)

			// The third thing to do with a worktree, and the one for when
			// somebody wants the files rather than the project or a shell —
			// a diff to drag somewhere, a screenshot the agent left in the
			// item's folder. Under the same guard as the other two, so all
			// three appear and disappear together with the checkout.
			let inFinder = NSMenuItem(
				title: "Reveal Worktree in Finder",
				action: #selector(revealWorktreeFromMenu(_:)),
				keyEquivalent: ""
			)
			inFinder.target = self
			inFinder.representedObject = run.worktree
			inFinder.toolTip = run.worktreePath
			menu.addItem(inFinder)
		}

		menu.addItem(.separator())
		for state in BacklogState.board where state != item.state {
			let move = NSMenuItem(
				title: "Move to \(state.title)",
				action: #selector(moveFromMenu(_:)),
				keyEquivalent: ""
			)
			move.target = self
			move.representedObject = MoveRequest(item: item, state: state)
			menu.addItem(move)
		}

		menu.addItem(.separator())
		let reveal = NSMenuItem(
			title: item.carriesFiles ? "Show Folder in Finder" : "Show in Finder",
			action: #selector(revealFromMenu(_:)),
			keyEquivalent: ""
		)
		reveal.target = self
		reveal.representedObject = item
		menu.addItem(reveal)
		return menu
	}

	/// A pair, because a menu item carries one object.
	private final class MoveRequest: NSObject {
		let item: BacklogItem
		let state: BacklogState
		init(item: BacklogItem, state: BacklogState) {
			self.item = item
			self.state = state
		}
	}

	@objc private func openFromMenu(_ sender: NSMenuItem) {
		guard let item = sender.representedObject as? BacklogItem else { return }
		open(item)
	}

	@objc private func startFromMenu(_ sender: NSMenuItem) {
		guard let item = sender.representedObject as? BacklogItem else { return }
		start(item)
	}

	@objc private func openWorktreeFromMenu(_ sender: NSMenuItem) {
		guard let worktree = sender.representedObject as? URL else { return }
		onOpenWorktree?(worktree)
	}

	@objc private func openWorktreeTerminalFromMenu(_ sender: NSMenuItem) {
		guard let worktree = sender.representedObject as? URL else { return }
		onOpenWorktreeTerminal?(worktree)
	}

	/// The worktree itself, selected in its parent — not opened as a window on
	/// its contents. A checkout of this project has forty entries at its root
	/// and none of them is what somebody asked to see; the directory is.
	@objc private func revealWorktreeFromMenu(_ sender: NSMenuItem) {
		guard let worktree = sender.representedObject as? URL else { return }
		NSWorkspace.shared.activateFileViewerSelecting([worktree])
	}

	@objc private func moveFromMenu(_ sender: NSMenuItem) {
		guard let request = sender.representedObject as? MoveRequest else { return }
		move(request.item, to: request.state)
	}

	@objc private func revealFromMenu(_ sender: NSMenuItem) {
		guard let item = sender.representedObject as? BacklogItem else { return }
		NSWorkspace.shared.activateFileViewerSelecting([item.folder ?? item.file])
	}
}
