import AppKit
import AbydosKit

/// Keeping the tree true to the disk: the filesystem watcher, which folds are
/// open, and where the selection is.
extension ProjectNavigatorViewController {
	// MARK: - Filesystem watching

	func startWatching(root: URL) {
		watcher?.stop()
		watcher = FileSystemWatcher(root: root) { [weak self] change in
			self?.handleFilesystemChange(change)
		}
		watcher?.start()
	}

	/// What the watcher has delivered and what the tree did about it, since the
	/// window opened.
	///
	/// 0428 asks for "filesystem events per build, and what the tree does with
	/// them", and those are three different numbers: how many batches FSEvents
	/// coalesced the build into, how many directories those batches named, and
	/// how many of them the tree was actually open on. The third is the one
	/// `loadedNode(for:)` was written to keep small, and it can only be counted
	/// from here — `FileNode.directoryReadsForTesting` counts listings anywhere,
	/// including the ones somebody's clicking causes.
	struct WatcherTally {
		var batches = 0
		var directories = 0
		var reloaded = 0
	}
	nonisolated(unsafe) static var watcherTallyForTesting = WatcherTally()

	/// What the tree costs right now, for `--report-open`.
	func scaleReportForTesting() -> [String] {
		let tally = Self.watcherTallyForTesting
		return [
			String(format: "OPEN %-24s %8d", ("tree rows" as NSString).utf8String!, outlineView.numberOfRows),
			String(format: "OPEN %-24s %8d", ("tree nodes held" as NSString).utf8String!, rootNode?.loadedNodeCount ?? 0),
			String(format: "OPEN %-24s %8d", ("directories listed" as NSString).utf8String!, FileNode.directoryReadsForTesting),
			String(format: "OPEN %-24s %8d batches, %d paths, %d reloaded",
				("watcher" as NSString).utf8String!, tally.batches, tally.directories, tally.reloaded),
		]
	}

	private func handleFilesystemChange(_ change: FileSystemChange) {
		Self.watcherTallyForTesting.batches += 1
		Self.watcherTallyForTesting.directories += change.directories.count
		StallWatch.mark("navigator watcher") { handleFilesystemChangeMarked(change) }
	}

	/// Named for the stall log, because this runs on every filesystem event and
	/// an agent writing files makes that dozens a minute. A stall recorded as
	/// "idle" is one nobody can act on, and most of the log was idle.
	private func handleFilesystemChangeMarked(_ change: FileSystemChange) {
		let directories = change.directories
		// Reported before the early return below: the staging view cares about
		// any edit, not only ones in a directory the tree happens to have
		// expanded.
		onFilesChanged?(change)

		// And so does the colouring, for a reason that is easy to miss: an edit
		// to an ignore file changes the status of files that did not themselves
		// change. Saving `.abydos/.gitignore` with `!backlog/` in it makes two
		// folders elsewhere in the tree stop being ignored, and nothing about
		// those folders was written. This used to be asked only when a directory
		// somebody had expanded was re-read, so the answer depended on which
		// parts of the tree happened to be open. The refresh coalesces — one
		// `git status` at a time with at most one queued — which is what makes
		// asking on every event affordable.
		refreshGitStatus()
		// And the first file of a new kind should be offered as one, without the
		// project being reopened. Marked rather than cleared: see
		// `fileKindsAreStale`.
		fileKindsAreStale = true
		// The palette's file list, which is why this is here rather than in the
		// palette: the palette is shut when the file somebody is about to look
		// for is saved, and the watcher is the only thing awake to see it.
		updateFileIndex(with: change)

		// A lock file being written is the one event that changes the
		// Dependencies section, and it is exactly what `swift package resolve`
		// and `go get` produce. Before the early return below, because the
		// section is not a directory anybody has expanded and would otherwise
		// only be re-read when something else in the tree happened to move.
		if changeTouchesDependencies(change) { refreshDependencies() }

		guard let rootNode else { return }
		guard !holdRebuildForRename() else { return }

		// Only re-read directories the user has actually expanded — and only ask
		// the question through directories that are already open. `node(for:)`
		// lists a directory to look inside it, so asking it about a path under
		// `.build` read `.build` and everything down to the event's parent, on
		// this queue, to find out that none of it was open. `loadedNode(for:)`
		// stops at the first closed door, which is where the answer already is.
		var touched = false
		for directory in directories {
			guard let node = rootNode.loadedNode(for: directory), node.isDirectory, node.hasLoadedChildren
			else { continue }
			node.reloadPreservingIdentity()
			Self.watcherTallyForTesting.reloaded += 1
			touched = true
		}
		guard touched else { return }

		// A reload drops the selection, so it is captured by path and restored.
		let expanded = expandedPaths()
		let selected = selectedPaths()
		let place = rememberPlace()
		outlineView.reloadData()
		restore(expandedPaths: expanded)
		// Or lands on the file somebody is waiting for. This is the path a
		// written file actually arrives by — the watcher re-reads the one
		// directory rather than the whole tree — and it used to put the old
		// selection back regardless, so `pendingReveal` was only honoured when
		// something else happened to reload everything.
		restoreSelectionOrReveal(paths: selected)
		restore(place: place)
		// The status was already asked for above, for every change rather than
		// only the ones that landed here; rows that have just appeared are
		// covered by the same read.
	}

	/// Re-reads the tree after a settings change.
	///
	/// Hiding or showing dotfiles changes which nodes exist, so cached children
	/// have to be discarded rather than merely repainted.
	func applySettings() {
		outlineView.rowHeight = Theme.current.scaled(24)
		outlineView.indentationPerLevel = Theme.current.scaled(14)
		headerHeightConstraint.constant = Theme.current.scaled(30)
		// **The colours, beside the metrics that were already re-taken here.**
		// Both were copied out of the theme in `loadView()`, and only the
		// metrics were ever copied again — so the tree kept its dark background
		// in a light window while the header directly above it, which fills
		// with `sidebarBackground` as it draws, followed. One pane, half light
		// and half dark, which is the screenshot that was reported.
		outlineView.backgroundColor = Theme.current.sidebarBackground
		(view as? ColoredView)?.refreshColour()
		outlineView.enclosingScrollView?.backgroundColor = Theme.current.sidebarBackground
		headerView.isCompactingPackages = Settings.shared.compactsPackages
		headerView.restyle()
		guard let rootNode else { return }
		let expanded = expandedPaths()
		let selected = selectedPaths()
		let place = rememberPlace()
		rootNode.invalidate()
		outlineView.reloadData()
		outlineView.expandItem(rootNode)
		restore(expandedPaths: expanded)
		restoreSelection(paths: selected)
		restore(place: place)
		refreshGitStatus()
	}




	/// Re-reads every directory the tree has loaded.
	///
	/// Called when the window comes forward, since the watcher is not the only
	/// way the tree goes stale — the app may have been asleep, or the events
	/// may have been coalesced away.
	func refreshFromDisk() {
		reloadTree()
		// **And the sessions, which the tree reload does not touch.** They are
		// not read from a directory the tree has loaded, so nothing else here
		// would notice a session that started while the app was asleep — or one
		// whose hooks are not installed, which is the only way such a session is
		// ever seen at all.
		refreshSessions()
	}

	/// Redraws the tree from the file system.
	///
	/// Internal rather than private since 0453: a workspace edit from a language
	/// server changes files nobody in this window went near, and the tree that
	/// is showing them is not otherwise told.
	func reloadTree() {
		StallWatch.mark("navigator reload") { reloadTreeMarked() }
	}

	private func reloadTreeMarked() {
		guard let rootNode else { return }
		guard !holdRebuildForRename() else { return }
		let expanded = expandedPaths()
		let selected = selectedPaths()
		let place = rememberPlace()
		rootNode.reloadPreservingIdentity()
		outlineView.reloadData()
		restore(expandedPaths: expanded)

		restoreSelectionOrReveal(paths: selected)
		restore(place: place)
		refreshGitStatus()
	}

	/// Puts the selection back where it was — or on a file that has just been
	/// written, when the tree has caught up with it.
	/// Whichever of the pending paths the tree can find, or the old selection.
	///
	/// Any rather than all: a drop is one `FileManager` loop that finishes before
	/// the watcher fires, so in practice they arrive together — but a file that
	/// never arrives at all, a dotfile with hidden files switched off, would
	/// otherwise hold the reveal open for ever and the selection would sit on
	/// whatever was highlighted before the drop. What has arrived is selected;
	/// what has not is given up on. Not proved against a partial arrival, since
	/// nothing here can make one happen on purpose.
	func restoreSelectionOrReveal(paths: [String]) {
		if !pendingReveal.isEmpty {
			let arrived = pendingReveal.filter { rootNode?.node(for: $0) != nil }
			if !arrived.isEmpty {
				pendingReveal = []
				selectWithoutOpening(urls: arrived)
				return
			}
		}
		restoreSelection(paths: paths)
	}

	/// Every selected path, in tree order.
	///
	/// All of them, not the first: the tree reloads on every filesystem event,
	/// and a build writing files reloads it dozens of times a minute. A capture
	/// that kept one path would shrink a selection of five to one while nobody
	/// was looking at it, which is the kind of fault nobody reports precisely.
	func selectedPaths() -> [String] {
		TreeSelection.paths(rows: Array(outlineView.selectedRowIndexes)) { row in
			let item = outlineView.item(atRow: row)
			if let node = item as? FileNode { return node.url.path }
			// A session's own row is a selection too, and it is not a file. Held
			// the way its expansion is, so the one set carries both.
			if let node = item as? SessionNode { return "session:" + node.identity }
			// A row inside a shown archive is not a file either, and it was
			// the third kind to be missing from here — see
			// `ArchiveNode.selectionKey`. Held under the same `archive:` key
			// its fold is, so the one set carries both.
			if let node = item as? ArchiveNode { return archiveSelectionKey(for: node) }
			return nil
		}
	}

	/// Every selected row as a node, in tree order.
	///
	/// The selection rather than `contextNodes`, which starts from `clickedRow`:
	/// this is what the keyboard's gestures act on, and a row clicked ten minutes
	/// ago is still the clicked row.
	func selectedNodes() -> [FileNode] {
		outlineView.selectedRowIndexes.sorted().compactMap {
			outlineView.item(atRow: $0) as? FileNode
		}
	}

	/// Reselects by path, since reloadData replaces the row indices.
	func restoreSelection(paths: [String]) {
		guard !paths.isEmpty, let rootNode else { return }
		// Through open directories only. A path that was selected was on screen,
		// so everything above it is expanded and therefore loaded; a path that
		// cannot be reached that way has no row to select either, and reading a
		// directory to prove it has no row is work for nothing on the queue the
		// watcher runs this from.
		let rows = TreeSelection.rows(for: paths) { path in
			// **Whichever root holds it.** This asked `rootNode` alone, so a
			// selected file under a Claude session — which lives outside the
			// project, in `/tmp/claude-…` — was looked for in the project tree,
			// not found, and dropped. Every rebuild of that section therefore
			// lost the selection entirely, and the section rebuilds on every
			// file an agent writes.
			if path.hasPrefix("session:") {
				guard let node = self.sessionNode(withIdentity: String(path.dropFirst(8))) else {
					return -1
				}
				return outlineView.row(forItem: node)
			}
			// An entry inside a shown archive, by the path it has in there.
			if path.hasPrefix("archive:") { return archiveRow(forSelectionKey: path) }
			let url = URL(fileURLWithPath: path)
			if let node = rootNode.loadedNode(for: url) { return outlineView.row(forItem: node) }
			if let located = dependencies?.locate(url) {
				return outlineView.row(forItem: located.node)
			}
			// Through open directories only, as above: `loadedNode` gives up
			// rather than reading a directory to prove a row does not exist.
			if let session = sessions?.session(containing: url),
			   let fileRoot = session.fileRoot,
			   let node = fileRoot.loadedNode(for: url) {
				return outlineView.row(forItem: node)
			}
			return -1
		}
		guard !rows.isEmpty else { return }

		// Restoring must not be mistaken for somebody choosing the file, which
		// would reopen it in the editor.
		let wasSilent = isSelectingSilently
		isSelectingSilently = true
		outlineView.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
		isSelectingSilently = wasSilent
	}

	/// A session row by the name its selection was held under.
	private func sessionNode(withIdentity identity: String) -> SessionNode? {
		func find(_ node: SessionNode) -> SessionNode? {
			if node.identity == identity { return node }
			for child in node.childNodes {
				if let found = find(child) { return found }
			}
			return nil
		}
		guard let sessions else { return nil }
		return find(sessions)
	}

	// MARK: - Expansion state

	/// What is open, by name rather than by object, so it survives a reload.
	///
	/// Two kinds of name in one set: an absolute path for a file row, and
	/// `dep:` plus an identity for one of the Dependencies section's own rows.
	/// One set and not two, because every caller captures this before a reload
	/// and puts it back afterwards, and a second set would be one more thing for
	/// the next call site to forget — there are six of them already.
	func expandedPaths() -> Set<String> {
		var paths = Set<String>()
		for row in 0..<outlineView.numberOfRows {
			let item = outlineView.item(atRow: row)
			if let node = item as? FileNode, outlineView.isItemExpanded(node) {
				paths.insert(node.url.path)
			} else if let node = item as? DependencyNode, outlineView.isItemExpanded(node) {
				paths.insert("dep:" + node.identity)
			} else if let node = item as? SessionNode, outlineView.isItemExpanded(node) {
				// **The third root was missing from here, and that is item 0540.**
				// A session's row rebuilds whenever the session's size changes —
				// which, while an agent is working in it, is every file it
				// writes — and nothing recorded that the row had been open. So
				// the section folded shut under whoever was reading it, dozens of
				// times a minute.
				paths.insert("session:" + node.identity)
			}
		}
		// And the archives somebody opened up, with the directories open
		// inside them — see `+Archives`.
		paths.formUnion(archiveFoldKeys())
		return paths
	}

	private func restoreExpansion() {
		guard let rootNode else { return }
		outlineView.expandItem(rootNode)
	}

	/// What is unfolded here, for the project's session.
	///
	/// **Positive, and relative to the project.** A tree arrives with the root
	/// alone open, so what is worth writing down is what somebody unrolled. The
	/// file paths go relative to the project root, because the session file
	/// sits inside the project: a checkout that is moved, or the same checkout
	/// opened through a worktree, is the same tree with the same folders. The
	/// `dep:` and `session:` identities are not paths and travel as they are.
	///
	/// The root itself is not written: it is expanded by `restoreExpansion`
	/// whatever the session says, and a key for it would be a line in every
	/// file saying what always happens.
	var folds: ProjectSession.TreeFolds {
		get {
			guard let root = project?.root.standardizedFileURL.path else {
				return ProjectSession.TreeFolds()
			}
			let opened = expandedPaths().compactMap { path -> String? in
				guard path.hasPrefix("/") else { return path }
				guard path != root else { return nil }
				guard path.hasPrefix(root + "/") else { return nil }
				return String(path.dropFirst(root.count + 1))
			}
			return ProjectSession.TreeFolds(opened: opened.sorted())
		}
		set {
			guard let root = project?.root.standardizedFileURL.path else { return }
			restore(expandedPaths: Set(newValue.opened.map { key in
				key.hasPrefix("dep:") || key.hasPrefix("session:") || key.hasPrefix("archive:")
					? key
					: root + "/" + key
			}))
		}
	}

	func restore(expandedPaths paths: Set<String>) {
		let paths = FilePath.withAncestors(of: paths)
		if let rootNode {
			outlineView.expandItem(rootNode)
			expand(node: rootNode, matching: paths)
		}
		// **Each root, and no early return between them.** This used to `guard
		// let dependencies else { return }`, so a project without a Dependencies
		// section never reached the sessions below it — and one with a section
		// never reached them either, because nothing here walked them at all.
		if let dependencies { expand(dependency: dependencies.root, matching: paths) }
		if let sessions { expand(session: sessions, matching: paths) }
		restoreArchives(matching: paths)
	}

	/// The same for the Claude Sessions root and its own rows, and then on into
	/// the session's directory, where the rows are files again and
	/// `expand(node:matching:)` takes over.
	private func expand(session node: SessionNode, matching paths: Set<String>) {
		guard paths.contains("session:" + node.identity) else { return }
		outlineView.expandItem(node)
		for child in node.childNodes { expand(session: child, matching: paths) }
		if let fileRoot = node.fileRoot { expand(node: fileRoot, matching: paths) }
	}

	private func expand(node: FileNode, matching paths: Set<String>) {
		guard node.hasLoadedChildren else { return }
		// The rows, not the children: with compaction on, half the directories
		// under this one have no row to open, and the one that has is several
		// levels down. Its path is in `paths` either way, which is what makes
		// the saved set survive the toggle.
		for child in rows(under: node) where child.isDirectory && paths.contains(child.url.path) {
			outlineView.expandItem(child)
			expand(node: child, matching: paths)
		}
	}

	/// The same for the section's own rows, which are not files and have no
	/// paths — and then on into the package's directory, where they are files
	/// again and the rule above takes over.
	private func expand(dependency node: DependencyNode, matching paths: Set<String>) {
		guard paths.contains("dep:" + node.identity) else { return }
		outlineView.expandItem(node)
		for child in node.childNodes { expand(dependency: child, matching: paths) }
		if let fileRoot = node.fileRoot { expand(node: fileRoot, matching: paths) }
	}

	// MARK: - Selection

	/// Opens a row, or closes it. The one gesture the Dependencies section's own
	/// rows have — a package is not a file, so there is nothing to show for it
	/// but what is inside it.
	func toggle(_ item: Any) {
		if outlineView.isItemExpanded(item) {
			outlineView.collapseItem(item)
		} else {
			outlineView.expandItem(item)
		}
	}

	@objc func rowDoubleClicked() {
		let clicked = outlineView.item(atRow: outlineView.clickedRow)
		if let archiveNode = clicked as? ArchiveNode {
			if archiveNode.isExpandable { toggle(archiveNode) } else { openArchiveEntry(archiveNode, pinned: true) }
			return
		}
		if let dependency = clicked as? DependencyNode {
			toggle(dependency)
			return
		}
		guard let node = clicked as? FileNode else { return }
		if node.isDirectory {
			if outlineView.isItemExpanded(node) {
				outlineView.collapseItem(node)
			} else {
				outlineView.expandItem(node)
			}
		} else {
			// Committing to a file hands keyboard focus to the editor.
			onSelectFile?(node.url, true)
		}
	}
}
