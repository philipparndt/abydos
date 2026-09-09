import AppKit
import AbydosKit

// MARK: - Table

extension ChangesPane: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()

		func item(_ title: String, _ selector: Selector) -> NSMenuItem {
			let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			entry.target = self
			return entry
		}

		guard let clicked = clickedNode else {
			// Nothing under the pointer, so the only thing on offer is what
			// applies to the lot.
			if !status.staged.isEmpty || !status.unstaged.isEmpty {
				menu.addItem(item("Stash All Changes…", #selector(stashEverything)))
			}
			return
		}

		// A folder says how much it is about to take. "Stage" over a folder of
		// forty files is the same three words as over one file, and the
		// difference between them is the whole reason folder staging is worth
		// having and the whole reason it is worth being careful with.
		let verb = clicked.isStaged ? "Unstage" : "Stage"
		let title = clicked.node.isFolder
			? "\(verb) “\(clicked.node.name)” (\(clicked.node.count) file"
				+ "\(clicked.node.count == 1 ? "" : "s"))"
			: verb
		menu.addItem(item(title, clicked.isStaged ? #selector(unstageClicked) : #selector(stageClicked)))
		menu.addItem(.separator())
		// Only for something git is not already tracking: ignoring a tracked
		// file does nothing, which is a confusing thing to offer.
		//
		// The condition is `change?.kind`, so it covers an untracked *directory*
		// as well — which is right, and is what somebody who has just made a
		// folder of build output wants. The comment here used to say the
		// opposite: that `-uall` reports the files inside such a directory
		// individually and a folder row is therefore always one this pane
		// invented. That stopped being true when the listing became `-unormal`,
		// and it is doubly untrue now that such a row has children of its own.
		if clicked.node.change?.kind == .untracked {
			menu.addItem(item("Add to .gitignore\u{2026}", #selector(ignoreClicked)))
		}
		menu.addItem(.separator())
		// What is chosen, or what was clicked when nothing is.
		let chosen = stashable().files
		menu.addItem(item(
			chosen > 1 ? "Stash \(chosen) Files…" : "Stash This File…",
			#selector(stashSelected)
		))
		menu.addItem(item("Stash All Changes…", #selector(stashEverything)))
		// Under stash rather than beside stage, and fenced off on its own: the
		// recoverable version of the same wish is the line above it, which is
		// what the confirmation goes on to name.
		if let target = discardable() {
			let counts = discardCounts(target)
			menu.addItem(.separator())
			menu.addItem(item(
				GitDiscard.menuTitle(
					subject: target.subject, files: counts.files, untracked: counts.untracked
				),
				#selector(discardClicked)
			))
		}
		menu.addItem(.separator())
		menu.addItem(item("Reveal in Finder", #selector(revealClicked)))
		menu.addItem(item("Copy Path", #selector(copyClickedPath)))
	}
}

extension ChangesPane: NSOutlineViewDataSource, NSOutlineViewDelegate {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		guard let node = item as? GitChangeNode else { return side(for: outlineView).roots.count }
		return node.children.count
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		guard let node = item as? GitChangeNode else { return side(for: outlineView).roots[index] }
		return node.children[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		// `holdsFiles`, so an untracked directory gets a triangle. It has one
		// entry as far as git is concerned and a folder's worth of work inside,
		// and until now it was drawn as a file with nothing under it.
		(item as? GitChangeNode)?.holdsFiles ?? false
	}

	/// Fills an untracked directory the first time it is opened.
	///
	/// Nothing is asked for until this happens, which is the whole arrangement:
	/// the listing runs on every filesystem event and cannot afford `-uall`,
	/// while one directory's worth of it is what that directory holds.
	func outlineViewItemWillExpand(_ notification: Notification) {
		guard let node = notification.userInfo?["NSObject"] as? GitChangeNode,
		      let outline = notification.object as? ChangesOutlineView,
		      node.change?.isDirectory == true
		else { return }

		let staged = outline === stagedTable
		remember(opened: node.path, staged: staged)
		guard !node.isFilled else { return }

		// From what is already known, if this row has been opened before in this
		// session — so a rebuild does not blink.
		if let known = side(for: outline).untrackedContents[node.path] {
			node.fill(with: known)
			// `reloadItem` rather than `reloadData` keeps the selection by
			// itself — it is the one node's children being replaced, not the
			// row map — which is why the synchronous path was never the
			// reported one.
			outline.reloadItem(node, reloadChildren: true)
			return
		}
		fill(node, in: outline, staged: staged)
	}

	func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
		Theme.current.scaled(22)
	}

	/// **This tree had no row view, so AppKit drew its own selection band.** A
	/// selected file sat in the system's full-bleed blue inside a window that
	/// draws a rounded, inset pill everywhere else — reported on 2026-09-01 as
	/// the tree's selection not being themed, which is what it was.
	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		TreeRowView()
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? GitChangeNode else { return nil }
		guard let change = node.change else {
			return ChangeFolderRowView(node: node, isStaged: outlineView === stagedTable)
		}
		// A change that is a whole directory keeps its badge — it is untracked,
		// and that is what the badge says — and gains a folder beside it, rather
		// than becoming a folder row: a folder row says how much of it is on
		// this side, and this one is a single entry to git.
		return ChangeRowView(node: node, change: change)
	}

	func outlineView(_ outlineView: NSOutlineView, typeSelectStringFor column: NSTableColumn?, item: Any) -> String? {
		(item as? GitChangeNode)?.name
	}

	func outlineViewItemDidExpand(_ notification: Notification) {
		guard !isRestoring, let outline = notification.object as? NSOutlineView else { return }
		guard let node = notification.userInfo?["NSObject"] as? GitChangeNode else { return }
		// What is inside it comes back open too, unless it was shut on purpose.
		// The children are new objects since the last rebuild, so the outline
		// view has no memory of them and would otherwise hand back a folder
		// whose insides are shut while everything around it is open.
		isRestoring = true
		expand(node.children, in: outline, collapsed: side(for: outline).collapsed)
		stopRestoring()
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		// Not while the pane is putting its own selection back: a refresh runs
		// on every filesystem event, and reopening the diff each time would
		// throw away wherever somebody had scrolled to in it.
		guard !isRestoring else { return }
		guard let outline = notification.object as? NSOutlineView else { return }
		guard outline.numberOfSelectedRows > 0 else { return }

		// Selecting in one list clears the other, so the diff on screen always
		// belongs to the row that is highlighted.
		let other = outline === stagedTable ? unstagedTable : stagedTable
		if !(other?.selectedRowIndexes.isEmpty ?? true) {
			other?.deselectAll(nil)
		}

		// A folder has no diff of its own — it is not a thing git can be asked
		// about — so selecting one leaves up whatever was being read. Clearing
		// the pane on the way past a folder row would make arrowing down
		// through the tree flash it empty every second row.
		let changes = outline.selectedRowIndexes.sorted().compactMap {
			(outline.item(atRow: $0) as? GitChangeNode)?.change
		}
		guard let change = changes.first else { return }

		// A column hands the diff to the editor area; a page keeps it, which is
		// the whole difference between staging with a trip out to a tab per
		// file and staging in one place.
		//
		// **At once, not after the double-click interval.** This used to wait
		// out `NSEvent.doubleClickInterval` so that the first click of a
		// double-click would not start a render the second click's stage then
		// queued behind — which cost half a second on every click and every
		// arrow key. But a double-click is nearly always on the row that is
		// already selected, and that changes no selection and reaches nothing
		// here; and the render it guarded against no longer holds the main
		// thread, because `showDiff` parses and colours off it. What is left
		// to protect is nothing.
		guard arrangement == .page, diffView != nil else {
			onSelectChange?(change)
			return
		}
		showDiff(of: change)
	}

}

extension ChangesPane {
	/// Reads the diff of the row that is selected, again.
	///
	/// After part of a file has been staged from the page's own diff: the text
	/// on screen describes the state before that ran, and `refresh()` puts the
	/// lists back without going near it — it restores the selection with
	/// `isRestoring` set, precisely so that a filesystem event does not throw
	/// away wherever somebody had scrolled to.
	func rereadDiff() {
		guard arrangement == .page, diffView != nil else { return }
		for outline in [unstagedTable, stagedTable] {
			guard let outline, outline.numberOfSelectedRows > 0 else { continue }
			let changes = outline.selectedRowIndexes.sorted().compactMap {
				(outline.item(atRow: $0) as? GitChangeNode)?.change
			}
			guard let change = changes.first else { continue }
			showDiff(of: change)
			return
		}
	}

	private func showDiff(of change: GitChange) {
		guard let diffView else { return }
		// **The newest ask wins.** Two awaits sit between the selection and
		// the render — git, then the parse and colouring on a thread of its
		// own — and arrowing through the tree starts one of these per row.
		// A render that comes back to find the number has moved on belongs to
		// a row that is no longer selected and is dropped, so the diff on
		// screen is always the last row asked for and never the slowest one.
		diffGeneration += 1
		let generation = diffGeneration

		// A picture diffs as two pictures, not as "No textual changes."
		if PictureDiffLoader.isPicture(change.path, in: root), let documents = diffDocuments {
			Task { @MainActor [weak self] in
				guard let self else { return }
				let estate = self.submodules.estate
				let owner = estate.repositoryRoot(containing: change.path)
				let loaded = await PictureDiffLoader.load(
					change, path: estate.relativePath(of: change.path), in: owner
				)
				guard generation == self.diffGeneration else { return }
				documents.showPicture().show(old: loaded.old, new: loaded.new, outcome: loaded.outcome)
			}
			return
		}
		diffDocuments?.showText()

		Task { @MainActor [weak self] in
			guard let self else { return }
			// **In the repository that owns the path.** `git diff -- svc-2/…`
			// run in the superproject answers nothing at all: the superproject
			// does not track that file, so the pane went blank for every file
			// inside a submodule and looked like a file with no changes. The
			// path has to be relative to that repository too, for the reason
			// `Project.gitRoot` records.
			let estate = self.submodules.estate
			let owner = estate.repositoryRoot(containing: change.path)
			let text = await GitWorkingCopy.diff(
				for: estate.relativePath(of: change.path),
				staged: change.isStaged,
				in: owner
			)
			guard generation == self.diffGeneration else { return }
			let url = self.root.appendingPathComponent(change.path)
			let prepared = await DiffView.prepareOffMain(text, url: url)
			guard generation == self.diffGeneration else { return }
			diffView.setDiff(prepared, staged: change.isStaged)
			// **Re-bound on every selection, not once when the view was built.**
			// The verbs are about *this* change and *this* diff text, and the
			// one view shows every file in turn; a closure captured at build
			// time would stage the first file somebody ever looked at.
			diffView.onApplySelection = { [weak self] lines in
				self?.onApplyDiffSelection?(change, text, lines, owner)
			}
			diffView.onDiscardSelection = { [weak self] lines in
				self?.onDiscardDiffSelection?(change, text, lines, owner)
			}
			diffView.onStashSelection = self.onStashDiffSelection == nil ? nil : { [weak self] lines in
				self?.onStashDiffSelection?(change, text, lines, owner)
			}
		}
	}
}

extension ChangesPane: NSTextFieldDelegate {
	func controlTextDidChange(_ notification: Notification) {
		updateCommitButton()
	}

	/// Return in the summary opens the description rather than committing.
	///
	/// It is the reflex from every mail client — the subject is finished and
	/// there is more to say — and in a single-line field it did nothing at all.
	/// **⌘Return still commits**: that is the commit button's own key equivalent
	/// and is untouched, so the key that makes a commit is the key it was.
	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		guard control === subjectField, selector == #selector(NSResponder.insertNewline(_:)) else {
			return false
		}
		// Only the page has one. The sidebar's field is the one-line case and has
		// no description to open.
		guard descriptionChevron != nil else { return false }
		if !isDescriptionShowing { setDescription(showing: true) }
		window?.makeFirstResponder(bodyView)
		return true
	}
}
