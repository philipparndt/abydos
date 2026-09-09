import AppKit
import AbydosKit


// MARK: - Tables

extension HistoryPane: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int {
		// The changes view is an outline and asks its own questions; this is the
		// commit list alone now.
		visible.count
	}

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		(tableView as? HistoryTableView)?.rowHeightOverride ?? Theme.current.scaled(22)
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		if tableView === commitTable {
			guard commits.indices.contains(row) else { return nil }
			let commit = visible[row].commit
			let view = CommitRowView(
				commit: commit,
				isUnpushed: unpushed.contains(commit.hash),
				isRemoteOnly: remoteOnly.contains(commit.hash),
				fadedLanes: fadedLanesByRow.indices.contains(row) ? fadedLanesByRow[row] : [],
				graph: visible[row].graph,
				isCollapsed: collapsedMerges.contains(commit.hash),
				// Who and when, which a 300 pt column has no room for and a
				// page does. They are the two questions a log is asked that the
				// subject cannot answer.
				showsAuthor: arrangement == .page
			)
			// **By hash, and selecting first.** The row index captured here is
			// the one the view was made at, and folding moves every row below
			// it — so a reused view folded whatever had since arrived at that
			// index. And a click on the button is not a click on the row, so
			// nothing was selected for `keepingSelection` to put back: the
			// keyboard path kept its selection because pressing ← requires
			// having one.
			view.onFold = { [weak self] in
				guard let self,
				      let now = self.visible.firstIndex(where: { $0.commit.hash == commit.hash })
				else { return }
				self.commitTable.selectRowIndexes(
					IndexSet(integer: now), byExtendingSelection: false
				)
				self.toggleCollapse(at: now)
			}
			return view
		}
		return nil
	}

	/// The theme's selection colour rather than the system's blue, in both of
	/// the log's tables — the same reason `ThemedRowView` was written.
	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		ThemedRowView()
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		(notification.object as? HistoryTableView)?.onSelectionChange?()
	}
}

extension HistoryPane: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()
		guard clickedCommit != nil else { return }

		func item(_ title: String, _ selector: Selector) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			item.target = self
			return item
		}
		// Where you can stand, and what you can make from here.
		menu.addItem(item("Checkout", #selector(checkoutCommit)))
		// Only on a file-scoped log: on the whole log "the working copy
		// against then" spans every file, which is not a diff tab, and the
		// item would lie about what it opens.
		if scopedPath != nil {
			menu.addItem(item(
				"Compare with Working Copy", #selector(compareCommitWithWorkingCopy)
			))
		}
		menu.addItem(item("Branch from Here\u{2026}", #selector(branchFromHere)))
		menu.addItem(item("Tag Here\u{2026}", #selector(tagHere)))
		menu.addItem(.separator())

		// What this commit's change can do to the branch you are on. Revert and
		// cherry-pick add a commit; reset takes them away, which is why it is
		// fenced off below and is the only one here that asks first.
		menu.addItem(item("Revert\u{2026}", #selector(revertCommit)))
		menu.addItem(item("Cherry-pick", #selector(cherryPickCommit)))
		menu.addItem(.separator())
		menu.addItem(item("Reset to Here\u{2026}", #selector(resetToCommit)))
		menu.addItem(.separator())

		menu.addItem(item("Copy Commit Hash", #selector(copyHash)))
		menu.addItem(item("Copy Subject", #selector(copySubject)))
	}
}

extension HistoryPane: NSSplitViewDelegate {
	/// How small a pane may be dragged.
	///
	/// **Through the delegate rather than through constraints.** A height
	/// constraint on a pane is a second opinion about where the divider is, and
	/// two opinions is what made the page argue with the panel below it once
	/// per frame.
	func splitView(
		_ splitView: NSSplitView,
		constrainMinCoordinate minimum: CGFloat,
		ofSubviewAt divider: Int
	) -> CGFloat {
		// Two rows of files, or a third of the graph: below either there is
		// nothing to read, and a pane dragged to nothing cannot be found again.
		guard splitView === pageSplit else { return minimum + Theme.current.scaled(48) }
		return minimum + Theme.current.scaled(320)
	}

	func splitView(
		_ splitView: NSSplitView,
		constrainMaxCoordinate maximum: CGFloat,
		ofSubviewAt divider: Int
	) -> CGFloat {
		guard splitView === pageSplit else { return maximum - Theme.current.scaled(80) }
		return maximum - Theme.current.scaled(300)
	}
}

extension HistoryPane: NSSearchFieldDelegate {
	func controlTextDidChange(_ notification: Notification) {
		query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
		reload()
	}
}
