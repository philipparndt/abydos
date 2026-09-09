import AppKit
import AbydosKit

/// Putting the pane together: the tree, the filter strip above it, and the
/// banner that appears while an operation is running.
extension BranchesPane {
	// MARK: - Layout

	func build() {
		// **The repository, as a control**, which is what the button above this
		// tree used to be: fetch when level, pull when behind, push when ahead.
		// Its own comment gave the reason it was a button — *a verb here hangs
		// off the row that draws its object, and nothing drew the repository*.
		// Something does now, so the verb is on it and the button is gone.
		repositoryRow = RepositoryRowView()
		repositoryRow.translatesAutoresizingMaskIntoConstraints = false
		repositoryRow.onAction = { [weak self] in self?.trafficPressed() }
		// **Fetch, in the word, always.** The row's own verb is chosen from the
		// state — Pull when behind, Push when ahead — so Fetch was the one verb
		// that disappeared exactly when somebody wanted it: a branch one commit
		// ahead offered Push and no way at all to ask whether anybody else had
		// pushed.
		//
		// The glyph that used to be here already fetched. It said so in a
		// tooltip, and a tooltip is not a label, so it was reported as a
		// missing button while it was on the row being pressed for something
		// else. Nothing about what it does has changed; it says what it does.
		repositoryRow.onSecondaryAction = { [weak self] in self?.fetchPressed() }
		repositoryRow.buildMenu = { [weak self] in self?.remoteMenu() }
		repositoryRow.onDownArrow = { [weak self] in self?.moveKeyboardIntoTree() }

		tableView = BranchesOutlineView()
		tableView.headerView = nil
		tableView.backgroundColor = Theme.current.sidebarBackground
		tableView.selectionHighlightStyle = .regular
		// So that several stashes can be dropped in one go. Branches ignore it:
		// nothing here acts on more than one of those.
		tableView.allowsMultipleSelection = true
		tableView.rowSizeStyle = .custom
		tableView.intercellSpacing = .zero
		tableView.gridStyleMask = []
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("branch"))
		tableView.addTableColumn(column)
		// The column the disclosure triangles sit in, which an outline view
		// will not draw one without.
		tableView.outlineTableColumn = column
		tableView.indentationPerLevel = Theme.current.scaled(14)
		tableView.autoresizesOutlineColumn = false
		tableView.delegate = self
		tableView.dataSource = self
		tableView.menu = makeMenu()
		tableView.onActivate = { [weak self] in self?.checkoutSelected() }
		tableView.onRowAction = { [weak self] in self?.fireSelectedRowAction() }
		// Tags only, deliberately: a branch delete asks about worktrees and
		// about commits nothing else has, and giving that a bare key would be
		// answering a bigger question with a smaller gesture. `deleteTag` is a
		// no-op unless every selected row is a tag.
		tableView.onDeleteKey = { [weak self] in self?.deleteTag() }
		tableView.onLeaveTop = { [weak self] in self?.moveKeyboardToRepositoryRow() }

		conflictBanner = OperationBanner()
		conflictBanner.onOpenFiles = { [weak self] in
			guard let self else { return }
			self.onOpenFiles?(self.conflictPaths)
		}
		// One file, which is how somebody actually works through a conflict:
		// open it, read the two halves, write a third, come back and say so.
		conflictBanner.onOpenFile = { [weak self] path in
			self?.onOpenFiles?([path])
		}
		conflictBanner.onTake = { [weak self] side, path in
			self?.resolveConflict(path, by: { root in
				await GitConflicts.take(side, of: path, in: root)
			})
		}
		conflictBanner.onMarkResolved = { [weak self] path in
			self?.resolveConflict(path, by: { root in
				await GitConflicts.markResolved(path, in: root)
			})
		}
		conflictBanner.onOpenInFork = { [weak self] in
			guard let self, let fork = ForkIntegration.applicationURL() else { return }
			NSWorkspace.shared.open(
				[self.root], withApplicationAt: fork,
				configuration: NSWorkspace.OpenConfiguration()
			)
		}
		conflictBanner.onCopyPrompt = { [weak self] in
			guard let self else { return }
			let root = self.root
			Task { @MainActor in
				guard let prompt = await GitConflicts.prompt(in: root) else { return }
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(prompt, forType: .string)
				Toast.post(
					"The conflict is on the clipboard",
					detail: "Paste it into a session in the terminal below.",
					kind: .information
				)
			}
		}

		conflictBanner.onCarryOn = { [weak self] in self?.step(.carryOn) }
		conflictBanner.onSkip = { [weak self] in self?.step(.skip) }
		conflictBanner.onAbort = { [weak self] in self?.askAboutAborting() }

		let scrollView = NSScrollView()
		scrollView.documentView = tableView
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.sidebarBackground
		scrollView.scrollerStyle = NSScroller.preferredScrollerStyle

		for view in [conflictBanner, repositoryRow, scrollView] as [NSView] {
			addSubview(view)
			view.translatesAutoresizingMaskIntoConstraints = false
		}

		// Shut to nothing unless there is a conflict, so a clean repository
		// pays nothing for it.
		conflictHeight = conflictBanner.heightAnchor.constraint(equalToConstant: 0)
		conflictHeight.isActive = true

		NSLayoutConstraint.activate([
			conflictBanner.topAnchor.constraint(equalTo: topAnchor),
			conflictBanner.leadingAnchor.constraint(equalTo: leadingAnchor),
			conflictBanner.trailingAnchor.constraint(equalTo: trailingAnchor),

			// **Nothing between the conflict banner and the repository row.**
			// The filter field and the New Branch button were 58 points of
			// chrome above a list; the filter is on ⌘F and the new branch is a
			// verb on the LOCAL row it belongs to.
			repositoryRow.topAnchor.constraint(equalTo: conflictBanner.bottomAnchor),
			repositoryRow.leadingAnchor.constraint(equalTo: leadingAnchor),
			repositoryRow.trailingAnchor.constraint(equalTo: trailingAnchor),
			repositoryRow.heightAnchor.constraint(equalToConstant: Theme.current.scaled(24)),

			scrollView.topAnchor.constraint(equalTo: repositoryRow.bottomAnchor),
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}
}
