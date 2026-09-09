import AppKit
import AbydosKit

/// Driving the sidebar's panes from a script: the branch rows, the changes
/// steps, the commit menu, and the two synthetic events a driver needs.
///
/// Every one of these is a question about a pane this controller owns, asked
/// without a person clicking. They are here rather than beside the panes
/// because the answer nearly always needs the tool to be shown first, which is
/// this controller's business and not the pane's.
extension SidebarController {
	/// What the menu over a commit in the log offers.
	///
	/// The same shape as `--branch-rows` and for the same reason: the claim is
	/// that a commit has verbs, and that the one which can lose work is fenced
	/// off from the ones that cannot. A list of titles diffs; a photograph of an
	/// open menu does not, and an `NSMenu` popped up for real blocks the run
	/// loop so the screenshot never fires at all.
	func commitMenuForTesting(row: Int, waiting: Int = 6) {
		if historyPane == nil { showSidebarTool(.history) }
		guard let pane = historyPane else {
			print("COMMIT-MENU: no history pane")
			return
		}

		// The log is read off the main queue and answers on it, so a pane built
		// a moment ago has no rows yet. Waited for rather than assumed: a fixed
		// delay long enough for a cold repository is a delay every run pays,
		// and one short enough not to be is a flake.
		guard pane.hasRowsForTesting else {
			guard waiting > 0 else {
				print("COMMIT-MENU: the log is still empty")
				return
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.commitMenuForTesting(row: row, waiting: waiting - 1)
			}
			return
		}
		print("COMMIT-MENU:\n\(pane.commitMenuForTesting(row: row))")
	}

	/// Drives the refs tree from the command line: `report`, `shut:<key>`,
	/// `open:<key>`, `filter:<text>`, `stash:<n>`, `tag-sources:<tag>`,
	/// `refresh`, `settle[:seconds]`.
	///
	/// The same arrangement `--changes-tree` uses and for the same reason: the
	/// questions this pane turns on are about *this view* — did the prefix
	/// fold, did the one branch under `hotfix/` stay flat, did filtering
	/// flatten the lot — and a screenshot is one frame of that rather than the
	/// sequence.
	/// A key-down for ⎋, for a driven run that wants the key rather than the
	/// method it ends up in.
	static func escapeEvent() -> NSEvent {
		NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
			windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil,
			characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
			isARepeat: false, keyCode: 53
		)!
	}

	/// Whether the editor's find bar is up — the other half of "who got ⌘F".
	private var editorFindBarIsShowing: Bool { editor.findBarIsShowingForTesting }

	/// ⌘⏎, the key a row's own verb is on.
	static func commandReturnEvent() -> NSEvent {
		NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
			windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil,
			characters: "\r", charactersIgnoringModifiers: "\r",
			isARepeat: false, keyCode: 36
		)!
	}

	/// Walks the window's responder chain for Find and names who takes it.
	///
	/// **The chain, not the key, and the window's chain rather than the
	/// application's.** Three ways were tried before this one. A hand-made
	/// `NSEvent` through `performKeyEquivalent` is ignored; a `CGEvent` at the
	/// window server needs an Accessibility grant the built app does not have;
	/// and `NSApp.sendAction(to: nil)` goes through the *key window*, which a
	/// driven run does not have — these runs are not activated, and the report
	/// said `app active false` rather than lying about the outcome.
	///
	/// What is left is the thing actually in question. The ⌘F binding is
	/// untouched by this change — the item is `keyEquivalent: "f"` and was
	/// before — and what the change adds is a second implementor of the action
	/// further down the chain. So: start at the window's first responder, walk
	/// up, and say who answers.
	static func sendFind(in window: NSWindow?) -> String {
		let selector = #selector(MainWindowController.findInFile(_:))
		var responder = window?.firstResponder
		while let here = responder {
			if here.responds(to: selector) {
				_ = here.perform(selector, with: nil)
				return String(describing: type(of: here))
			}
			responder = here.nextResponder
		}
		return "nobody"
	}

	func branchRowsForTesting(_ steps: String) {
		if branchesPane == nil { showSidebarTool(.branches) }
		guard let pane = branchesPane else {
			print("BRANCHES: no branches pane")
			return
		}

		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			// Everything after a `settle` goes back to the run loop: git answers
			// on the main queue, so a nested wait here would never see the list
			// it is waiting for.
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.branchRowsForTesting(rest)
				}
				return
			}

			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "report":  print("BRANCHES:\n\(pane.rowsForTesting())")
			case "stash":
				pane.openStashForTesting(Int(argument) ?? 0)
			case "recreate": pane.recreateTagForTesting()
			// The tag delete with the sheet's answer given — `delete-tag` for
			// the local half alone, `delete-tag:remote` for both. The sheet
			// itself stays undriven: `NSAlert` wants a person, and reaching in
			// to press it would be testing `NSAlert`.
			case "delete-tag": pane.deleteTagForTesting(alsoOnRemote: argument == "remote")
			// Opening a stash as a page, and what that page then says.
			case "review-stash":
				print("BRANCHES review-stash: " + pane.reviewStashForTesting(argument))
			case "stash-page":
				print(stashPage?.reportForTesting() ?? "STASH-PAGE none")
			case "stash-page-select":
				print("STASH-PAGE select: "
					+ (stashPage?.selectForTesting(argument) ?? "no page"))
			case "stash-page-press":
				print("STASH-PAGE press: "
					+ (stashPage?.pressForTesting(argument) ?? "no page"))
			case "tag-sources":
				print("TAG-SOURCES:\n\(pane.tagSourcesForTesting(excluding: argument))")
			case "shut":    pane.setFolderForTesting(argument, collapsed: true)
			case "open":    pane.setFolderForTesting(argument, collapsed: false)
			case "filter":  pane.filterForTesting(argument)
			case "find":    pane.showFilter()
			// A real ⎋ through the responder chain, not a call to what ⎋ calls:
			// the question here is whether the key reaches the strip at all.
			case "escape":  pane.window?.sendEvent(SidebarController.escapeEvent())
			// ⌘F through the menu bar, which is how the press actually
			// arrives — the responder chain decides who gets it, and the
			// question in 4.4 is whether it decides the way it should.
			case "cmdf":
				print("BRANCHES find taken by: \(SidebarController.sendFind(in: pane.window))")
			case "focus-tree": pane.window?.makeFirstResponder(pane.tableViewForTesting)
			// Clicks and arrows, with the selection read after each — the
			// tree-behaviour claim, asked of this tree as of the other three.
			case "keys": print("BRANCHES keys: " + pane.keysForTesting(argument))
			// Several branches at once, and what the menu would then offer and
			// copy. `+` between the names, as the other multi-row steps use.
			// A row index selects that row; names select those branches. One
			// verb rather than two because they are the same step asked in two
			// ways — and because two `case "select"` in one switch is a warning
			// saying the second is dead, which it was.
			case "select":
				if let row = Int(argument) {
					pane.selectRowForTesting(row)
				} else {
					print("BRANCHES select: " + pane.selectBranchesForTesting(
						argument.split(separator: "+").map(String.init)
					))
				}
			case "menu":
				if let row = Int(argument) {
					print("BRANCHES menu \(argument): " + pane.menuTitlesForTesting(row: row))
				} else {
					print("BRANCHES menu: "
						+ pane.branchMenuTitlesForTesting().joined(separator: " | "))
				}
			// `choose:<row>:<title>` fires that row's menu item by title, the
			// way a person picking a sort order would.
			case "choose":
				let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
				if parts.count == 2, let row = Int(parts[0]) {
					print("BRANCHES choose: "
						+ pane.chooseMenuItemForTesting(row: row, titled: parts[1]))
				} else {
					print("BRANCHES choose: wants row:title, got \(argument)")
				}
			case "delete-wording":
				Task { @MainActor in
					print("BRANCHES delete-wording: \(await pane.deleteWordingForTesting())")
					fflush(stdout)
				}
			// The delete itself, with the dialog's checkbox as the argument —
			// `delete:worktrees` ticks it, `delete` leaves it. This skips the
			// dialog; `sheet-press` below is the step that answers one.
			case "delete":
				Task { @MainActor in
					await pane.deleteForTesting(removingWorktrees: argument == "worktrees")
				}
			// The dialog itself, on screen, for a screenshot of it.
			case "ask-delete": pane.askAboutDeletingForTesting()
			case "sheet":      print(pane.deleteSheetForTesting())
			// The working copy's own verb, and answering the dialog it opens.
			// Not `stash`, which is taken above for opening a stash row — a
			// second one is dead code the compiler does not always mention.
			case "stash-changes": pane.stashWorkingCopyForTesting()
			case "stash-answer":
				let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
				print("BRANCHES stash-answer: " + pane.answerStashForTesting(
					parts.first ?? "", untracked: (parts.count > 1 ? parts[1] : "yes") != "no"
				))
			// Publishing with no remote, which is the case that used to fail in
			// git's words instead of asking for one.
			case "publish":    pane.pushSelectedForTesting()
			case "remote":     pane.setRemoteForTesting()
			case "type-remote": pane.typeRemoteForTesting(argument)
			// Answering it — the step the two above skip between them. Not
			// `press`, which the banner below has: a second one is a dead case.
			case "sheet-press": print("BRANCHES "
				+ BranchDeletion.pressSheetButtonForTesting(argument, in: pane.window))
			case "copy-name":
				print("BRANCHES copy-name would copy:\n"
					+ pane.copyNameTextForTesting().split(separator: "\n")
						.map { "  " + $0 }.joined(separator: "\n"))
			case "unfind":  pane.hideFilter()
			case "fstate":  print("BRANCHES filter: \(pane.filterStateForTesting())"
				+ " · editor find \(editorFindBarIsShowing ? "open" : "shut")"
				+ " · responder \(type(of: pane.window?.firstResponder ?? NSNull()))")
			case "refresh": pane.refresh()
			// What each row offers, and firing the selected one's verb — the
			// two halves of "a row's action can be reached from the keyboard".
			case "actions": print("BRANCHES actions:\n  "
				+ pane.rowActionsForTesting().joined(separator: "\n  "))
			case "fire":    pane.fireSelectedRowActionForTesting()
			case "repo":    print("BRANCHES repo: \(pane.repositoryRowForTesting())")
			case "repo-fire": pane.fireRepositoryRowForTesting()
			// The pinned row's whole claim is that scrolling does not take it
			// away, and only a scrolled tree can say whether that is true.
			// The strip above the tree while git is mid-operation, and its
			// verbs: `banner`, `press:continue`, `press:skip`, `press:abort`.
			case "banner":  print(pane.operationBannerForTesting())
			case "press":   pane.pressBannerForTesting(argument)
			// What the `⋯` menu holds, and what one conflicted file's row
			// offers — neither of which a shot of a closed menu can show.
			// Every remote verb the repository row offers, and when it last
			// fetched — the row draws one verb and there are four.
			// Which refs the pane calls finished, by ref rather than by name:
			// `origin/x` and `x` are two questions.
			case "merged":
				print("BRANCHES merged: " + pane.mergedMarkForTesting())
			case "delete-remote":
				pane.deleteRemoteForTesting()
			case "remote-menu":
				print("REPOSITORY menu: " + pane.remoteMenuForTesting())
			case "fetch":
				pane.pressFetchForTesting()
			// What the editor is showing, so "a click on a row opens the file"
			// is a claim a driven run can check rather than a screenshot.
			case "tabs":
				print("TABS: " + (editor.activeGroup?.tabTitlesForTesting.joined(separator: ", ")
					?? "no group"))
			case "banner-menu":
				print("BANNER menu \(argument.isEmpty ? "more" : argument): "
					+ pane.bannerMenuForTesting(argument))
			// Resolving one file the way the row's menu does:
			// `resolve:<path>:<ours|theirs|mark|open>`.
			case "resolve":
				let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)
				print("BANNER resolve: " + pane.resolveConflictForTesting(
					parts.first ?? "", how: parts.count > 1 ? parts[1] : "mark"
				))
			case "scroll":  pane.scrollTreeForTesting(toBottom: argument != "top")
			default:        print("BRANCHES: unknown step \(step)")
			}
			// Every step, because a driven run is killed rather than ended:
			// stdout is a pipe, the buffer is never drained by the exit, and a
			// report written after the last flushing step is simply lost. It
			// cost half an hour of "the tree prints nothing" that was a report
			// sitting in a buffer.
			fflush(stdout)
		}
	}

	/// Drives the changes tree from the command line: `report`, `stage:<path>`,
	/// `unstage:<path>`, `shut:<path>`, `open:<path>`, `offer:<path>`,
	/// `offer-staged:<path>`, `discard:<path>`, `refresh`, `settle[:seconds]`.
	///
	/// The pane lives in the app target, where the suite cannot reach it, and
	/// the questions this pane turns on — does staging a folder take everything
	/// under it, does the tree stay open across a refresh, where does the
	/// selection land once what was selected has been staged away — are about
	/// *this view* rather than about the tree it is drawn from. A screenshot is
	/// one frame of that and not the sequence, so the sequence is scripted, the
	/// way `--tree` scripts the navigator.
	func changesStepsForTesting(_ steps: String) {
		if changesPane == nil { showSidebarTool(.changes) }
		guard let pane = changesPane else {
			print("CHANGES: no changes pane")
			return
		}

		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			// Everything after a `settle` goes back to the run loop: git runs
			// off the main queue and answers on it, so a nested wait here would
			// never see the tree it is waiting for.
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.changesStepsForTesting(rest)
				}
				return
			}

			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "report":
				print("CHANGES:\n\(pane.changesTreeForTesting())")
			// The sweep's own progress strip, put up on demand: a warm estate
			// answers before anything could be photographed, and the whole
			// point of the strip is what a *cold* one looks like. `43/170`.
			case "progress":
				let parts = argument.split(separator: "/").compactMap { Int($0) }
				guard parts.count == 2 else { break }
				print("CHANGES progress: " + pane.showProgressForTesting(done: parts[0], of: parts[1]))
			// Selects the row the way a first click does, deferred diff and
			// all, so the double-click shape can be driven: select, then stage.
			case "select":
				pane.selectForTesting(path: argument, staged: false)
			case "stage":
				pane.stageForTesting(paths: argument.split(separator: "+").map(String.init), staged: false)
			case "unstage":
				pane.stageForTesting(paths: argument.split(separator: "+").map(String.init), staged: true)
			case "shut":
				pane.setExpandedForTesting(path: argument, expanded: false, staged: false)
			case "open":
				pane.setExpandedForTesting(path: argument, expanded: true, staged: false)
			// What the context menu offers over a row, and what it would ask
			// before throwing the work away. `offer-staged` is how the other
			// half of that decision is checked: a staged row offers nothing.
			case "offer":
				print(pane.discardWordingForTesting(path: argument, staged: false))
			case "offer-staged":
				print(pane.discardWordingForTesting(path: argument, staged: true))
			case "discard":
				pane.discardForTesting(path: argument)
			// What a file being written does to the pane, on demand: what is
			// still open and still selected afterwards is the whole question.
			case "refresh":
				pane.refresh()
			// The commit message history: `history` prints the menu's entries,
			// `use-history:<n>` fills the fields from one — both async (the
			// log is read when the menu opens), so settle before reading.
			case "history":
				pane.messageHistoryForTesting()
			// What the Draft button would ask for. `draft-ask:plain` asks with
			// the setting off, so the two shapes can be read in one run.
			case "draft-ask":
				if argument == "plain" { Settings.shared.conventionalCommitDrafts = false }
				pane.draftAskForTesting()
			// Both halves of a message, and what is left of them: the two steps
			// a switch-and-return proof needs. `compose:<summary>|<body>`.
			case "compose":
				let parts = argument.split(separator: "|", maxSplits: 1).map(String.init)
				pane.composeForTesting(
					summary: parts.first ?? "", body: parts.count > 1 ? parts[1] : ""
				)
			case "message":
				print("CHANGES message: " + pane.messageReportForTesting())
			// Commits what is staged with this subject, through the button's
			// own door: whether the project's hooks ran is a claim that wants a
			// trace rather than an assertion.
			case "commit-now": pane.commitForTesting(subject: argument)
			case "use-history":
				pane.useHistoryEntryForTesting(Int(argument) ?? 0)
			// Ends the run, and is the one ending that flushes: a script with
			// no exit is killed by whatever waits on it, and a kill loses what
			// `print` buffered — reports were written and never seen.
			case "exit":
				fflush(stdout)
				exit(0)
			default:
				print("CHANGES: no such step \(step)")
			}
		}
		fflush(stdout)
	}

	/// Clicks into the commit details field and types there.
	///
	/// Opens the pane first: it is only built once the repository has been
	/// read, so asking too early finds nothing and says so.
	func typeInCommitBodyForTesting(_ text: String) -> String {
		if changesPane == nil { showSidebarTool(.changes) }
		guard let pane = changesPane else { return "no changes pane" }
		hostWindow()?.layoutIfNeeded()
		return pane.typeInCommitBodyForTesting(text)
	}

	/// Pushes a branch from the branches view, for looking at what it does
	/// while it is happening.
	func pushBranchForTesting(_ name: String) {
		showSidebarTool(.branches)
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
			self?.branchesPane?.pushForTesting(branch: name)
		}
	}

	/// Folds a merge in the history, for checking the graph.
	func collapseHistoryRowForTesting(_ row: Int) {
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
			guard let pane = self?.historyPane else {
				print("FOLD no history pane")
				return
			}
			print("FOLD " + pane.toggleCollapseForTesting(row: row))
		}
	}

	/// Opens the branches view's own menu on a row, so what it offers for a
	/// branch or a stash can be looked at rather than assumed.
	func branchMenuForTesting(row: Int) {
		showSidebarTool(.branches)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
			self?.branchesPane?.showMenuForTesting(row: row)
		}
	}
}
