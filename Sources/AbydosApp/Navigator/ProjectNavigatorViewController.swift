import AppKit
import AbydosKit

/// The project tree from image 1: a bold root row carrying the home-relative
/// path, then lazily-loaded directories with type icons and VCS colouring.
final class ProjectNavigatorViewController: NSViewController {
	/// `focusEditor` is true when the user committed to the file (Return or a
	/// double-click) rather than merely highlighting it.
	var onSelectFile: ((URL, _ focusEditor: Bool) -> Void)?
	/// Asked to open a terminal in the given directory.
	var onOpenTerminal: ((URL) -> Void)?
	/// Asked to work on part of the project, or on the whole of it again.
	var onOpenSubproject: ((URL) -> Void)?
	var onLeaveSubproject: (() -> Void)?
	/// Asked to show a 3D model in the external viewer.
	var onPreviewModel: ((URL) -> Void)?
	/// Something under the project root changed on disk.
	var onFilesChanged: (() -> Void)?
	/// How many files the working copy has changed, whenever that is read.
	///
	/// The tree reads `git status` already, on every watcher event; anything
	/// else that wants the number should hear it from here rather than run its
	/// own.
	var onChangeCount: ((Int) -> Void)?
	/// What the editor is showing, so the tree can be asked to find its way back
	/// to it after browsing somewhere else.
	var currentEditorFile: (() -> URL?)?

	/// True while the tree is moving its own selection — restoring it after a
	/// reload, or following the editor's tab — so it does not call back and
	/// reopen the file it was just told about.
	///
	/// Everything else opens: arrowing through the tree shows each file it lands
	/// on, provisionally, the way a click does. Moving the highlight without
	/// showing anything is what made the tree look broken.
	private var isSelectingSilently = false

	private var project: Project?
	private var rootNode: FileNode?
	/// The folder being worked on, marked in the tree so it is obvious which
	/// part of a repository the run button belongs to.
	private(set) var subprojectRoot: URL?
	private var watcher: FileSystemWatcher?
	private var outlineView: NSOutlineView!
	private var headerView: NavigatorHeaderView!
	private var headerTopConstraint: NSLayoutConstraint!
	private var headerHeightConstraint: NSLayoutConstraint!
	private var gitRoot: URL?

	/// The one column follows the view's width.
	///
	/// Left to itself an outline column stays as wide as the widest name it has
	/// been given, so a longer name truncates with an ellipsis while empty pane
	/// sits beside it — and anything measuring against the cell, such as the
	/// rename field, is cut to the same wrong width. Most visible at a large
	/// zoom, where the names grow and the column does not.
	override func viewDidLayout() {
		super.viewDidLayout()
		guard let column = outlineView?.tableColumns.first else { return }
		let width = outlineView.bounds.width
		guard width > 0, abs(column.width - width) > 0.5 else { return }
		column.width = width
	}

	/// Distance from the top of the window to the "Project" header.
	func setTopInset(_ inset: CGFloat) {
		headerTopConstraint.constant = inset + 4
	}

	// MARK: - View

	override func loadView() {
		let container = ColoredView(color: Theme.current.sidebarBackground)

		let header = NavigatorHeaderView()
		header.onCollapseAll = { [weak self] in self?.collapseAll() }
		header.onSelectOpenFile = { [weak self] in self?.selectFileInEditor() }
		headerView = header
		let outline = NavigatorOutlineView()
		outline.headerView = nil
		outline.backgroundColor = Theme.current.sidebarBackground
		// `.none` would suppress drawSelection(in:) entirely; `.regular` keeps the
		// callback so NavigatorRowView can draw the rounded highlight itself.
		outline.selectionHighlightStyle = .regular
		outline.rowSizeStyle = .custom
		outline.rowHeight = Theme.current.scaled(24)
		outline.intercellSpacing = NSSize(width: 0, height: 0)
		outline.indentationPerLevel = Theme.current.scaled(14)
		outline.autoresizesOutlineColumn = false
		outline.gridStyleMask = []
		outline.usesAutomaticRowHeights = false
		// ⇧-click a run of files, ⌘-click a handful of them, and ⌘A takes
		// everything the tree is showing — which is everything *visible*,
		// because an unexpanded folder's children are not rows and have not
		// been read off the disk. Trashing four files is one gesture now.
		outline.allowsMultipleSelection = true
		outline.focusRingType = .none

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
		column.resizingMask = .autoresizingMask
		outline.addTableColumn(column)
		outline.outlineTableColumn = column

		outline.dataSource = self
		outline.delegate = self
		// Files drag out as URLs: onto the terminal, or into another app. Copy
		// rather than move — dragging a file out of the tree should never be a
		// way to lose it from the project.
		outline.setDraggingSourceOperationMask(.copy, forLocal: true)
		outline.setDraggingSourceOperationMask(.copy, forLocal: false)
		outline.target = self
		outline.doubleAction = #selector(rowDoubleClicked)
		outline.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }
		// The absolute path, which is what "copy path" has always meant here and
		// what a terminal, a Finder window or another program can be given. The
		// menu still offers the relative one, which is the one a commit message
		// or an import wants.
		//
		// Several rows join with newlines, in the order they appear in the tree
		// rather than the order they were clicked: what is being copied is a
		// list of files, and the tree's order is the one that reads.
		outline.copyText = { [weak self] in
			guard let paths = self?.selectedPaths(), !paths.isEmpty else { return nil }
			return paths.joined(separator: "\n")
		}
		outline.menu = makeContextMenu()
		outlineView = outline

		let scrollView = NSScrollView()
		scrollView.documentView = outline
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = false
		scrollView.autohidesScrollers = true
		scrollView.automaticallyAdjustsContentInsets = false

		container.addSubview(header)
		container.addSubview(scrollView)
		header.translatesAutoresizingMaskIntoConstraints = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false

		// Set from the window's actual titlebar height rather than hardcoded.
		headerTopConstraint = header.topAnchor.constraint(equalTo: container.topAnchor, constant: 44)
		headerHeightConstraint = header.heightAnchor.constraint(equalToConstant: Theme.current.scaled(30))

		NSLayoutConstraint.activate([
			headerTopConstraint,
			header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			headerHeightConstraint,

			scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
			scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])

		view = container

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(repositoryChanged(_:)),
			name: .abydosRepositoryChanged,
			object: nil
		)
	}

	// MARK: - Loading

	/// Marks a folder as the one being worked on.
	func setSubproject(_ url: URL?) {
		guard url?.path != subprojectRoot?.path else { return }
		subprojectRoot = url
		outlineView.reloadData()
		if let url { reveal(url: url) }
	}

	func load(project: Project) {
		self.project = project
		let root = FileNode(url: project.root, isDirectory: true)
		rootNode = root

		outlineView.reloadData()
		outlineView.expandItem(root)

		startWatching(root: project.root)
	}

	func windowWillClose() {
		watcher?.stop()
		watcher = nil
		NotificationCenter.default.removeObserver(self)
	}

	// MARK: - Version control

	func refreshGitStatus() {
		guard let project, let git = project.git, let rootNode else { return }

		// One `git status` at a time, with at most one more queued behind it.
		// The tree asks for this on every watcher event, and a project being
		// built produces a great many of those.
		guard !isReadingGitStatus else {
			wantsAnotherGitStatus = true
			return
		}
		isReadingGitStatus = true

		Task { @MainActor in
			defer {
				isReadingGitStatus = false
				if wantsAnotherGitStatus {
					wantsAnotherGitStatus = false
					refreshGitStatus()
				}
			}

			// Re-read it: the cache was filled when the project opened, so a
			// file written since — a build's output, or the binary a debugger
			// leaves behind — had no status at all and was drawn as if it were
			// tracked and unmodified.
			await git.refresh()
			let repoRoot = await git.root
			gitRoot = repoRoot

			// Collect the lookups on the actor, then apply them synchronously so
			// the tree is never left half-updated between frames.
			var results: [String: GitFileStatus] = [:]
			var pending: [(String, Bool)] = []
			collectPaths(node: rootNode, gitRoot: repoRoot, into: &pending)

			for (path, isDirectory) in pending {
				results["\(isDirectory ? "d" : "f"):\(path)"] = await git.status(
					forRelativePath: path,
					isDirectory: isDirectory
				)
			}

			rootNode.applyGitStatus(gitRoot: repoRoot) { path, isDirectory in
				results["\(isDirectory ? "d" : "f"):\(path)"] ?? .unmodified
			}
			// Deliberately not reloadData(): the row structure has not changed,
			// only the colours, and a reload would clear the selection — which is
			// what made keyboard-expanding a folder lose your place.
			redrawVisibleRows()
			onChangeCount?(await git.changedFileCount())
		}
	}

	/// The submenu under "New", filled in as it is about to be shown.
	private var newMenu: NSMenu?
	/// The submenu under "Export", which is only ever shown over a diagram.
	private var exportMenu: NSMenu?
	/// The kinds this project is made of, counted once and kept.
	///
	/// Counted lazily and not at open: walking a project to fill in a menu
	/// nobody has asked for yet is work for nothing. Dropped when the tree
	/// changes, so the first file of a new kind shows up in the menu after it
	/// exists rather than after the project is reopened.
	private var fileKinds: [NewFileKind]?

	private var isReadingGitStatus = false
	private var wantsAnotherGitStatus = false
	private var hasScheduledGitStatusRefresh = false

	/// Repaints rows in place. Cells read `node.gitStatus` when they draw, so
	/// marking them dirty is enough to pick up new version-control state.
	private func redrawVisibleRows() {
		outlineView.enumerateAvailableRowViews { rowView, _ in
			rowView.needsDisplay = true
			for subview in rowView.subviews { subview.needsDisplay = true }
		}
	}

	/// Gathers relative paths for loaded nodes only; unloaded subtrees resolve
	/// their status when the user expands them.
	private func collectPaths(node: FileNode, gitRoot: URL, into result: inout [(String, Bool)]) {
		let base = gitRoot.path
		let path = node.url.path
		let relative: String
		if path == base {
			relative = ""
		} else if path.hasPrefix(base + "/") {
			relative = String(path.dropFirst(base.count + 1))
		} else {
			relative = ""
		}
		result.append((relative, node.isDirectory))

		guard node.hasLoadedChildren else { return }
		for child in node.children {
			collectPaths(node: child, gitRoot: gitRoot, into: &result)
		}
	}

	@objc private func repositoryChanged(_ notification: Notification) {
		guard let changedRoot = notification.object as? URL,
		      let gitRoot,
		      changedRoot.standardizedFileURL == gitRoot.standardizedFileURL
		else { return }
		reloadTree()
	}

	// MARK: - Filesystem watching

	private func startWatching(root: URL) {
		watcher?.stop()
		watcher = FileSystemWatcher(root: root) { [weak self] changedDirectories in
			self?.handleFilesystemChange(changedDirectories)
		}
		watcher?.start()
	}

	private func handleFilesystemChange(_ directories: [URL]) {
		StallWatch.mark("navigator watcher") { handleFilesystemChangeMarked(directories) }
	}

	/// Named for the stall log, because this runs on every filesystem event and
	/// an agent writing files makes that dozens a minute. A stall recorded as
	/// "idle" is one nobody can act on, and most of the log was idle.
	private func handleFilesystemChangeMarked(_ directories: [URL]) {
		// Reported before the early return below: the staging view cares about
		// any edit, not only ones in a directory the tree happens to have
		// expanded.
		onFilesChanged?()

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
		// And the first file of a new kind should be offered as one, without
		// the project being reopened. Counted again when a menu next asks.
		fileKinds = nil

		guard let rootNode else { return }
		guard !holdRebuildForRename() else { return }

		// Only re-read directories the user has actually expanded.
		var touched = false
		for directory in directories {
			guard let node = rootNode.node(for: directory), node.isDirectory, node.hasLoadedChildren else { continue }
			node.reloadPreservingIdentity()
			touched = true
		}
		guard touched else { return }

		// A reload drops the selection, so it is captured by path and restored.
		let expanded = expandedPaths()
		let selected = selectedPaths()
		outlineView.reloadData()
		restore(expandedPaths: expanded)
		// Or lands on the file somebody is waiting for. This is the path a
		// written file actually arrives by — the watcher re-reads the one
		// directory rather than the whole tree — and it used to put the old
		// selection back regardless, so `pendingReveal` was only honoured when
		// something else happened to reload everything.
		restoreSelectionOrReveal(paths: selected)
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
		headerView.restyle()
		guard let rootNode else { return }
		let expanded = expandedPaths()
		let selected = selectedPaths()
		rootNode.invalidate()
		outlineView.reloadData()
		outlineView.expandItem(rootNode)
		restore(expandedPaths: expanded)
		restoreSelection(paths: selected)
		refreshGitStatus()
	}

	/// A path to select once the tree has caught up with the file system.
	///
	/// Creating a folder does not refresh the tree directly — the watcher does,
	/// a moment later — so the selection has to wait for the node to exist.
	private var pendingReveal: URL?

	/// Re-reads every directory the tree has loaded.
	///
	/// Called when the window comes forward, since the watcher is not the only
	/// way the tree goes stale — the app may have been asleep, or the events
	/// may have been coalesced away.
	func refreshFromDisk() {
		reloadTree()
	}

	private func reloadTree() {
		StallWatch.mark("navigator reload") { reloadTreeMarked() }
	}

	private func reloadTreeMarked() {
		guard let rootNode else { return }
		guard !holdRebuildForRename() else { return }
		let expanded = expandedPaths()
		let selected = selectedPaths()
		rootNode.reloadPreservingIdentity()
		outlineView.reloadData()
		restore(expandedPaths: expanded)

		restoreSelectionOrReveal(paths: selected)
		refreshGitStatus()
	}

	/// Puts the selection back where it was — or on a file that has just been
	/// written, when the tree has caught up with it.
	private func restoreSelectionOrReveal(paths: [String]) {
		if let pending = pendingReveal, rootNode?.node(for: pending) != nil {
			pendingReveal = nil
			selectWithoutOpening(url: pending)
			return
		}
		restoreSelection(paths: paths)
	}

	/// Every selected path, in tree order.
	///
	/// All of them, not the first: the tree reloads on every filesystem event,
	/// and a build writing files reloads it dozens of times a minute. A capture
	/// that kept one path would shrink a selection of five to one while nobody
	/// was looking at it, which is the kind of fault nobody reports precisely.
	private func selectedPaths() -> [String] {
		TreeSelection.paths(rows: Array(outlineView.selectedRowIndexes)) { row in
			(outlineView.item(atRow: row) as? FileNode)?.url.path
		}
	}

	/// Reselects by path, since reloadData replaces the row indices.
	private func restoreSelection(paths: [String]) {
		guard !paths.isEmpty, let rootNode else { return }
		let rows = TreeSelection.rows(for: paths) { path in
			guard let node = rootNode.node(for: URL(fileURLWithPath: path)) else { return -1 }
			return outlineView.row(forItem: node)
		}
		guard !rows.isEmpty else { return }

		// Restoring must not be mistaken for somebody choosing the file, which
		// would reopen it in the editor.
		let wasSilent = isSelectingSilently
		isSelectingSilently = true
		outlineView.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
		isSelectingSilently = wasSilent
	}

	// MARK: - Expansion state

	private func expandedPaths() -> Set<String> {
		var paths = Set<String>()
		for row in 0..<outlineView.numberOfRows {
			guard let node = outlineView.item(atRow: row) as? FileNode,
			      outlineView.isItemExpanded(node) else { continue }
			paths.insert(node.url.path)
		}
		return paths
	}

	private func restoreExpansion() {
		guard let rootNode else { return }
		outlineView.expandItem(rootNode)
	}

	private func restore(expandedPaths paths: Set<String>) {
		guard let rootNode else { return }
		outlineView.expandItem(rootNode)
		expand(node: rootNode, matching: paths)
	}

	private func expand(node: FileNode, matching paths: Set<String>) {
		guard node.hasLoadedChildren else { return }
		for child in node.children where child.isDirectory && paths.contains(child.url.path) {
			outlineView.expandItem(child)
			expand(node: child, matching: paths)
		}
	}

	// MARK: - Selection

	@objc private func rowDoubleClicked() {
		guard let node = outlineView.item(atRow: outlineView.clickedRow) as? FileNode else { return }
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

	// MARK: - Context menu

	private func makeContextMenu() -> NSMenu {
		let menu = NSMenu()
		menu.delegate = self

		// `NSMenu` sends to the first responder chain; targeting self keeps the
		// actions here regardless of what currently has focus.
		func item(_ title: String, _ selector: Selector) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			item.target = self
			return item
		}

		// One "New", with what this project is made of under it. The two
		// original items are the first things in the submenu and behave exactly
		// as they did: the kinds below them are a shortcut past typing an
		// extension, not another way of creating things.
		let new = NSMenuItem(title: "New", action: nil, keyEquivalent: "")
		let kinds = NSMenu()
		kinds.addItem(item("File…", #selector(contextNewFile)))
		kinds.addItem(item("Folder…", #selector(contextNewFolder)))
		new.submenu = kinds
		newMenu = kinds
		menu.addItem(new)
		menu.addItem(.separator())
		menu.addItem(item("Open", #selector(contextOpen)))
		menu.addItem(item("Open Externally", #selector(contextOpenExternally)))
		// Built once and hidden per click: the menu exists long before anything
		// has been right-clicked, so it cannot be decided here.
		menu.addItem(item("Preview in GoSTL", #selector(contextPreviewModel)))
		menu.addItem(.separator())
		menu.addItem(item("Open as Subproject", #selector(contextOpenSubproject)))
		menu.addItem(item("Leave Subproject", #selector(contextLeaveSubproject)))
		menu.addItem(.separator())
		menu.addItem(item("Open Terminal Here", #selector(contextOpenTerminal)))
		menu.addItem(item("Reveal in Finder", #selector(contextRevealInFinder)))
		menu.addItem(.separator())
		menu.addItem(item("Copy Path", #selector(contextCopyPath)))
		menu.addItem(.separator())
		menu.addItem(item("Add to .gitignore\u{2026}", #selector(contextIgnore)))
		menu.addItem(item("Copy Relative Path", #selector(contextCopyRelativePath)))
		// Only ever shown over a diagram, so it costs nothing to be here for
		// every other file: `menuNeedsUpdate` hides it.
		let export = NSMenuItem(title: "Export", action: nil, keyEquivalent: "")
		// Filled in by `menuNeedsUpdate`, from the same list the preview pane's
		// own menu is built from: what it offers depends on the theme and on
		// whether the file has stated a look, and both change while a menu exists.
		let formats = NSMenu()
		formats.autoenablesItems = false
		export.submenu = formats
		exportMenu = formats
		menu.addItem(export)
		menu.addItem(.separator())
		// The two keys written down where somebody will find them. A contextual
		// menu is not in the menu bar, so nothing dispatches these — AppKit only
		// searches the main menu for key equivalents, and `handleKeyDown` is
		// what actually answers them. They are here to be read.
		let rename = item("Rename…", #selector(contextRename))
		// F2 rather than ⌥⏎, of the two keys that rename: an item carries one
		// equivalent, and F2 is the one somebody arrives already knowing. ⌥⏎ is
		// for the hands that spent a week with Return meaning rename.
		rename.keyEquivalent = String(UnicodeScalar(NSF2FunctionKey)!)
		rename.keyEquivalentModifierMask = []
		menu.addItem(rename)
		let trash = item("Move to Trash", #selector(contextTrash))
		trash.keyEquivalent = String(UnicodeScalar(NSBackspaceCharacter)!)
		trash.keyEquivalentModifierMask = [.command]
		menu.addItem(trash)
		menu.addItem(.separator())
		// The same two the header offers, for anybody who looks for them here.
		menu.addItem(item("Select Opened File", #selector(contextSelectOpenFile)))
		menu.addItem(item("Collapse All", #selector(contextCollapseAll)))
		return menu
	}

	@objc private func contextCollapseAll() { collapseAll() }
	@objc private func contextSelectOpenFile() { selectFileInEditor() }

	@objc private func contextOpenSubproject() {
		guard let node = contextNode, node.isDirectory else { return }
		onOpenSubproject?(node.url)
	}

	@objc private func contextLeaveSubproject() {
		onLeaveSubproject?()
	}

	/// Every row the menu applies to, in tree order.
	///
	/// Right-clicking inside the selection means all of it — the gesture every
	/// file manager has, and the reason ⇧-clicking four files and asking for the
	/// trash works. Right-clicking a row *outside* the selection means that row
	/// alone: the pointer is the more recent statement of what is meant.
	private var contextNodes: [FileNode] {
		let clicked = outlineView.clickedRow
		if clicked >= 0, !outlineView.selectedRowIndexes.contains(clicked) {
			return (outlineView.item(atRow: clicked) as? FileNode).map { [$0] } ?? []
		}
		if outlineView.selectedRowIndexes.isEmpty, clicked >= 0 {
			return (outlineView.item(atRow: clicked) as? FileNode).map { [$0] } ?? []
		}
		return outlineView.selectedRowIndexes.sorted().compactMap {
			outlineView.item(atRow: $0) as? FileNode
		}
	}

	/// The one row the menu applies to, or nil when it applies to several.
	///
	/// Rename, "open terminal here", "open as subproject" and "reveal" are all
	/// single-row gestures: there is no sensible answer for four, and doing it
	/// to whichever came first is worse than not offering it. `validateMenuItem`
	/// switches them off from the same answer.
	private var contextNode: FileNode? {
		let nodes = contextNodes
		return nodes.count == 1 ? nodes.first : nil
	}

	@objc private func contextOpen() {
		guard let node = contextNode else { return }
		if node.isDirectory {
			outlineView.isItemExpanded(node) ? outlineView.collapseItem(node) : outlineView.expandItem(node)
		} else {
			onSelectFile?(node.url, true)
		}
	}

	@objc private func contextPreviewModel() {
		guard let node = contextNode else { return }
		onPreviewModel?(node.url)
	}

	@objc private func contextOpenExternally() {
		guard let node = contextNode else { return }
		NSWorkspace.shared.open(node.url)
	}

	@objc private func contextOpenTerminal() {
		guard let node = contextNode else { return }
		// A file's directory is what you want to be in; the file itself is not a
		// place a shell can start.
		let directory = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
		onOpenTerminal?(directory)
	}

	@objc private func contextRevealInFinder() {
		guard let node = contextNode else { return }
		NSWorkspace.shared.activateFileViewerSelecting([node.url])
	}

	/// One path a line, in tree order — the shape a list of files is wanted in.
	@objc private func contextCopyPath() {
		let paths = contextNodes.map(\.url.path)
		guard !paths.isEmpty else { return }
		copyToPasteboard(paths)
	}

	@objc private func contextCopyRelativePath() {
		guard let root = project?.root else { return }
		let paths = contextNodes.map { node -> String in
			let path = node.url.path
			return path.hasPrefix(root.path + "/")
				? String(path.dropFirst(root.path.count + 1))
				: path
		}
		guard !paths.isEmpty else { return }
		copyToPasteboard(paths)
	}

	private func copyToPasteboard(_ paths: [String]) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
	}

	/// Creates a folder inside the clicked directory.
	///
	/// A file's parent rather than the file: right-clicking a file to make a
	/// folder beside it is the same gesture, and the alternative — refusing
	/// unless a directory was clicked — is a rule nobody would guess.
	/// Creates a folder without the prompt, for verifying the action end to end.
	func createFolderForTesting(named name: String) {
		guard let root = project?.root else { return }
		let destination = root.appendingPathComponent(name)
		try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
		pendingReveal = destination
	}

	func createFileForTesting(named name: String) {
		guard let root = project?.root else { return }
		let destination = root.appendingPathComponent(name)
		try? FileManager.default.createDirectory(
			at: destination.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try? Data().write(to: destination, options: .withoutOverwriting)
		pendingReveal = destination
		onSelectFile?(destination, true)
	}

	/// Where a new entry from the context menu goes.
	///
	/// Beside the file that was clicked, or inside the folder — which is what
	/// "new file here" means when the thing under the pointer is a file. The
	/// first of several, since a new file has one place to go and the topmost
	/// row is the one somebody would point at.
	private var contextParentDirectory: URL? {
		if let node = contextNodes.first {
			return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
		}
		return project?.root
	}

	/// Asks for a name, saying why one is refused rather than failing silently.
	private func askForName(kind: EntryName.Kind, in parent: URL) -> String? {
		let alert = NSAlert()
		alert.messageText = kind == .file ? "New File" : "New Folder"
		alert.informativeText = "Inside \(parent.lastPathComponent)."
		alert.addButton(withTitle: "Create")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
		field.placeholderString = kind == .file ? "File name" : "Folder name"
		alert.accessoryView = field
		alert.window.initialFirstResponder = field

		guard alert.runModal() == .alertFirstButtonReturn else { return nil }
		let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

		if let problem = EntryName.problem(
			name, kind: kind, showingHiddenFiles: Settings.shared.showHiddenFiles
		) {
			report(problem: problem, kind: kind)
			return nil
		}
		guard !FileManager.default.fileExists(atPath: parent.appendingPathComponent(name).path) else {
			report(problem: "“\(name)” already exists here.", kind: kind)
			return nil
		}
		return name
	}

	/// Offers a pattern for whatever was right-clicked, and writes it once it
	/// is agreed.
	@objc private func contextIgnore() {
		guard let node = contextNode, let project else { return }
		let root = gitRoot ?? project.root
		let path = node.url.path
		guard path.hasPrefix(root.path + "/") else {
			Toast.post("Not in this repository", detail: "\(node.name) is outside \(root.lastPathComponent).")
			return
		}
		let relative = String(path.dropFirst(root.path.count + 1))
		presentIgnoreDialog(relativePath: relative, isDirectory: node.isDirectory, root: root)
	}

	private func presentIgnoreDialog(relativePath: String, isDirectory: Bool, root: URL) {
		let suggestions = GitIgnore.suggestions(for: relativePath, isDirectory: isDirectory)

		let alert = NSAlert()
		alert.messageText = "Ignore \((relativePath as NSString).lastPathComponent)"
		alert.informativeText = "The pattern is written to .gitignore. Edit it if it is not quite right."
		alert.addButton(withTitle: "Ignore")
		alert.addButton(withTitle: "Cancel")

		let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 54))
		let popup = NSPopUpButton(frame: NSRect(x: 0, y: 30, width: 360, height: 24))
		popup.addItems(withTitles: suggestions.map { "\($0.pattern)   —   \($0.explanation)" })
		container.addSubview(popup)

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
		field.stringValue = suggestions.first?.pattern ?? relativePath
		field.font = Theme.terminalFont(size: 12)
		container.addSubview(field)

		ignoreSuggestions = suggestions
		ignoreField = field
		popup.target = self
		popup.action = #selector(ignorePatternChosen)
		alert.accessoryView = container

		let apply: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn else { return }
			let pattern = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !pattern.isEmpty else { return }
			do {
				try GitIgnore.add(pattern, toRepositoryAt: root)
				self?.refreshGitStatus()
				NotificationCenter.default.post(name: .abydosRepositoryChanged, object: root)
			} catch {
				Toast.post("Could not write .gitignore", detail: error.localizedDescription)
			}
		}
		if let window = view.window {
			alert.beginSheetModal(for: window, completionHandler: apply)
		} else {
			apply(alert.runModal())
		}
	}

	private var ignoreSuggestions: [GitIgnore.Suggestion] = []
	private weak var ignoreField: NSTextField?

	@objc private func ignorePatternChosen(_ sender: NSPopUpButton) {
		guard ignoreSuggestions.indices.contains(sender.indexOfSelectedItem) else { return }
		ignoreField?.stringValue = ignoreSuggestions[sender.indexOfSelectedItem].pattern
	}

	private func report(problem: String, kind: EntryName.Kind) {
		Toast.post("Cannot create that \(kind == .file ? "file" : "folder")", detail: problem)
	}

	/// Puts this project's own kinds under "New", below File… and Folder….
	///
	/// Rebuilt as the menu opens rather than kept in step with the tree: the
	/// count is cached, so this is a few string comparisons unless something
	/// has changed, and a menu that is right whenever it is looked at needs no
	/// invalidation rules of its own.
	private func refreshNewMenu() {
		guard let menu = newMenu, let root = project?.root else { return }
		while menu.numberOfItems > 2 { menu.removeItem(at: menu.numberOfItems - 1) }

		let kinds = fileKinds ?? NewFileKinds.inProject(root)
		fileKinds = kinds
		guard !kinds.isEmpty else { return }

		menu.addItem(.separator())
		for kind in kinds {
			let item = NSMenuItem(
				title: kind.title, action: #selector(contextNewFileOfKind(_:)), keyEquivalent: ""
			)
			item.target = self
			item.representedObject = kind.name
			menu.addItem(item)
		}
	}

	/// A new file whose extension is already decided.
	///
	/// Everything else is what File… does — the same prompt, the same
	/// validation, the same intermediate folders — because the shortcut is
	/// about the extension and nothing else.
	@objc private func contextNewFileOfKind(_ sender: NSMenuItem) {
		guard let suffix = sender.representedObject as? String else { return }
		let kind = NewFileKind(name: suffix, count: 0, title: sender.title)
		createFile(named: { NewFileKinds.name($0, endingIn: kind) })
	}

	@objc private func contextNewFile() {
		createFile(named: { $0 })
	}

	/// Asks for a name, makes the file, and opens it.
	///
	/// - Parameter named: what to call it, given what was typed. The plain item
	///   takes it as it comes; a kind adds its extension.
	private func createFile(named: (String) -> String) {
		guard let parent = contextParentDirectory,
		      let typed = askForName(kind: .file, in: parent)
		else { return }
		let name = named(typed)

		let destination = parent.appendingPathComponent(name)
		// Intermediate folders as well, so "src/new/thing.swift" works the way
		// anyone typing that would expect.
		let enclosing = destination.deletingLastPathComponent()
		do {
			if !FileManager.default.fileExists(atPath: enclosing.path) {
				try FileManager.default.createDirectory(at: enclosing, withIntermediateDirectories: true)
			}
			try Data().write(to: destination, options: .withoutOverwriting)
		} catch {
			Toast.post("Could not create the folder", detail: error.localizedDescription)
			return
		}

		if let node = contextNodes.first, node.isDirectory { outlineView.expandItem(node) }
		pendingReveal = destination
		// Opened straight away: a new file is made in order to write in it.
		onSelectFile?(destination, true)
	}

	@objc private func contextNewFolder() {
		let parent: URL
		if let node = contextNodes.first {
			parent = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
		} else if let root = project?.root {
			parent = root
		} else {
			return
		}

		let alert = NSAlert()
		alert.messageText = "New Folder"
		alert.informativeText = "Inside \(parent.lastPathComponent)."
		alert.addButton(withTitle: "Create")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
		field.placeholderString = "Folder name"
		alert.accessoryView = field
		alert.window.initialFirstResponder = field

		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

		// Checked here so the failure is a sentence rather than a POSIX error.
		if let problem = FolderName.problem(name, showingHiddenFiles: Settings.shared.showHiddenFiles) {
			Toast.post("Cannot create that folder", detail: problem)
			return
		}

		let destination = parent.appendingPathComponent(name)
		guard !FileManager.default.fileExists(atPath: destination.path) else {
			Toast.post("Cannot create that folder", detail: "“\(name)” already exists here.")
			return
		}

		do {
			try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
		} catch {
			Toast.post("Could not create the folder", detail: error.localizedDescription)
			return
		}

		// The watcher reloads the tree; the new folder is revealed once it has.
		if let node = contextNodes.first, node.isDirectory {
			outlineView.expandItem(node)
		}
		pendingReveal = destination
	}

	// MARK: - Renaming on the row

	/// The field standing in for a row's label while its name is being edited.
	private var renameField: NSTextField?
	/// What is being renamed, and what it was called.
	private var renaming: (node: FileNode, original: String)?

	/// Edits a name where the name is.
	///
	/// The Finder's gesture, and the reason it is the right one here: the file
	/// stays in its place in the tree while it is renamed, so what is being
	/// renamed is never in doubt and the files around it stay readable. A sheet
	/// in the middle of the window answers the same question with less of the
	/// answer on screen.
	func beginRename(row: Int? = nil) {
		// A row named explicitly, or the selection when it is one row. Renaming
		// is a single-row gesture: with several selected Return does nothing
		// rather than renaming whichever came first.
		if row == nil, outlineView.numberOfSelectedRows > 1 { return }
		let index = row ?? outlineView.selectedRow
		guard index >= 0, let node = outlineView.item(atRow: index) as? FileNode,
		      node !== rootNode, renameField == nil
		else { return }

		// Over the label, not the whole row: the icon stays, so the row still
		// says what kind of thing is being renamed.
		let cell = outlineView.frameOfCell(atColumn: 0, row: index)
		// Where `NavigatorCellView` puts the name: the icon's width and the two
		// gaps around it. Taken from the same numbers rather than guessed at, so
		// the name does not move sideways as the field appears over it.
		let inset = Theme.current.scaled(2) + Theme.current.scaled(16) + Theme.current.scaled(6)
		let trailing = Theme.current.scaled(8)

		let field = NSTextField(frame: .zero)
		// A cell that centres its text, for editing as well as drawing. A plain
		// one puts the text against the top of whatever height it is given, which
		// is what made the name jump up as the field appeared — and jump further
		// the taller the row, so it looked worst at a large zoom.
		let centred = CentredFieldCell(textCell: "")
		centred.isEditable = true
		centred.isSelectable = true
		centred.usesSingleLineMode = true
		centred.wraps = false
		// Scrolls inside itself rather than clipping, so a name longer than the
		// pane can still be read and edited to its end without the pane being
		// dragged wider first.
		centred.isScrollable = true
		field.cell = centred
		// The row's own font. At 12 against the label's 13 the name visibly
		// shrank the moment editing began.
		field.font = Theme.current.uiFont(13)
		// The row's height, less a hair so the border does not touch the rows
		// above and below. The text inside is centred by the cell.
		let height = max(1, cell.height - Theme.current.scaled(2))
		// Stops where the pane does, not where the widest name does: the outline
		// is as wide as its longest row, so measuring against that put the right
		// edge of the field beyond the edge of the view, and the pane had to be
		// dragged wider than the filename before the whole field could be seen.
		let rightEdge = min(outlineView.rect(ofRow: index).maxX, outlineView.visibleRect.maxX)
		field.frame = NSRect(
			x: cell.minX + inset,
			y: (cell.minY + (cell.height - height) / 2).rounded(),
			width: max(60, rightEdge - cell.minX - inset - trailing),
			height: height
		)
		field.stringValue = node.name
		// Not bezeled: a bezel in a dark appearance is translucent and draws its
		// own background, so `drawsBackground` is ignored and the row's label
		// shows through — the old name and the new one on top of each other.
		field.isBezeled = false
		field.isBordered = false
		field.focusRingType = .none
		field.wantsLayer = true
		field.layer?.cornerRadius = 3
		field.layer?.borderWidth = 1
		field.layer?.borderColor = Theme.current.caret.cgColor
		// Opaque, in the sidebar's own colours: the row keeps drawing its label
		// underneath, and a field that lets it through shows the old name and
		// the new one on top of each other.
		field.drawsBackground = true
		field.backgroundColor = Theme.current.editorBackground
		field.textColor = Theme.current.sidebarText
		field.delegate = self
		// Above the rows: they are subviews too, and a field merely added is
		// behind the label it is standing in for.
		outlineView.addSubview(field, positioned: .above, relativeTo: nil)
		renameField = field
		renaming = (node, node.name)
		// Told, not reloaded. `reloadItem` would build a fresh row view and lay
		// it over the field, which is the fault the deferred rebuild above
		// exists for — the box vanishes while still taking the typing.
		showsName(at: index, false)

		outlineView.window?.makeFirstResponder(field)
		// The stem, the way the Finder does it: the extension is nearly never
		// what somebody meant to change, and having it selected is how a `.swift`
		// gets typed over by accident.
		if let editor = field.currentEditor(), !node.isDirectory {
			let stem = (node.name as NSString).deletingPathExtension
			editor.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
		}
	}

	/// Renames the selected row, for the capture harness: the same three steps
	/// somebody takes, without a keyboard.
	func renameSelectionForTesting(_ name: String) {
		beginRename()
		renameField?.stringValue = name
		commitRename()
	}

	/// Takes the field away, whether the name was changed or not.
	/// Where the field is and what it is drawing with, for the harness.
	///
	/// The three things that were wrong with it were all geometry — the text's
	/// size, where it sat in the row, and where it stopped — so they are worth
	/// being able to read as numbers rather than only off a photograph.
	var renameFieldReportForTesting: String {
		guard let field = renameField else { return "no field" }
		let row = outlineView.rect(ofRow: outlineView.selectedRow)
		return "frame=\(field.frame) row=\(row) visible=\(outlineView.visibleRect) "
			+ "font=\(field.font?.pointSize ?? 0)"
	}

	/// A rebuild that arrived while a name was being edited.
	///
	/// The tree rebuilds on every filesystem event, and `reloadData()` lays
	/// fresh row views over the field standing on the row — which does not
	/// remove it, so the box vanished while still taking the keystrokes being
	/// typed into it. Worse than it sounds: the app writes `.abydos/session.json`
	/// itself, so renaming anything beside it raced against the app's own event
	/// and the field survived or disappeared depending on the timing.
	///
	/// Renaming is short and deliberate, so the rebuild waits for it. Rebuilding
	/// under an open field would move the row out from under it anyway.
	private var deferredRebuild = false

	/// True when a rebuild must not happen yet, and remembers that one is owed.
	private func holdRebuildForRename() -> Bool {
		guard renameField != nil else { return false }
		deferredRebuild = true
		return true
	}

	/// Whether a row draws its own name, for the row the field is standing on.
	private func showsName(at row: Int, _ shows: Bool) {
		guard row >= 0,
		      let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
		      	as? NavigatorCellView
		else { return }
		cell.isRenaming = !shows
	}

	private func endRename() {
		// Forgotten before the field is taken away, not after: removing a field
		// that is being edited ends the editing then and there, and
		// `controlTextDidEndEditing` arrives while this is still half-done. It
		// would commit the very name Escape had just rejected — and did:
		// beginning a rename, changing the name and pressing Escape renamed the
		// file. Nothing left to find means nothing left to commit.
		let field = renameField
		let node = renaming?.node
		renameField = nil
		renaming = nil
		if let node {
			showsName(at: outlineView.row(forItem: node), true)
		}
		field?.removeFromSuperview()
		outlineView.window?.makeFirstResponder(outlineView)
		// Whatever changed on disk while the field was up, caught up with now
		// rather than at the next event — which may be a long time coming.
		if deferredRebuild {
			deferredRebuild = false
			reloadTree()
		}
	}

	/// Renames the file, or says why it cannot be renamed.
	///
	/// Validated before the field goes: a name that is refused leaves the field
	/// up with the name still in it, since taking it away would look like a
	/// rename that happened.
	private func commitRename() {
		guard let field = renameField, let (node, original) = renaming else { return }
		let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

		// An empty field, or the name it already had, is a cancel rather than an
		// error: neither is somebody asking for anything.
		guard !name.isEmpty, name != original else {
			endRename()
			return
		}

		let kind: EntryName.Kind = node.isDirectory ? .folder : .file
		if let problem = EntryName.problem(
			name, kind: kind, showingHiddenFiles: Settings.shared.showHiddenFiles
		) {
			report(problem: problem, kind: kind)
			// The field stays, and takes the keyboard back: a refused name is
			// still there to be corrected rather than quietly thrown away.
			outlineView.window?.makeFirstResponder(field)
			return
		}

		let destination = node.url.deletingLastPathComponent().appendingPathComponent(name)
		guard !FileManager.default.fileExists(atPath: destination.path) else {
			report(problem: "“\(name)” already exists here.", kind: kind)
			outlineView.window?.makeFirstResponder(field)
			return
		}

		do {
			try FileManager.default.moveItem(at: node.url, to: destination)
		} catch {
			report(problem: error.localizedDescription, kind: kind)
			outlineView.window?.makeFirstResponder(field)
			return
		}
		// The watcher rebuilds the tree, and the row is a different object
		// afterwards — so the selection follows the path rather than the node.
		pendingReveal = destination
		endRename()
	}

	/// Writes the diagram out as a picture beside itself.
	///
	/// One file, like Rename and unlike Move to Trash. Four diagrams exported at
	/// once is four separate answers — this one overwrote a previous export,
	/// that one refused because something else already had the name, the third
	/// has a syntax error on line 12 — and there is nowhere to say four things
	/// that anybody would read. The menu greys itself over a multiple selection
	/// rather than doing three of the four and reporting the fourth.
	///
	/// From disk rather than from the editor's buffer, because the tree is about
	/// files: the pane's own Export is the one that draws unsaved edits, and it
	/// is the one that is looking at them.
	@objc private func contextExport(_ sender: NSMenuItem) {
		guard let node = contextNode, !node.isDirectory,
		      let code = sender.representedObject as? String,
		      let choice = DiagramExportMenu.choice(for: code)
		else { return }
		DiagramExportCommand.run(
			url: node.url, format: choice.format, theme: choice.theme,
			editable: choice.editable, projectRoot: project?.root
		)
	}

	/// What a file states about its own look, read from disk.
	///
	/// From disk rather than from an editor, for the same reason the export from
	/// here is: the tree is about files. It costs one read of a text file while a
	/// menu is being filled in, and only over a diagram.
	private func statedLook(of node: FileNode?) -> String? {
		guard let node, let text = try? String(contentsOf: node.url, encoding: .utf8) else {
			return nil
		}
		return DiagramExport.statedLook(of: node.url, source: text)
	}

	/// The same gesture without the menu, for verifying it end to end.
	func exportSelectionForTesting(
		_ format: DiagramFormat, theme: DiagramTheme? = nil, editable: Bool = false
	) {
		guard let node = contextNode, !node.isDirectory, DiagramExport.holdsADiagram(node.url) else {
			print("EXPORT: nothing to export")
			return
		}
		DiagramExportCommand.run(
			url: node.url, format: format, theme: theme ?? (Theme.current.isLight ? .light : .dark),
			editable: editable, projectRoot: project?.root
		) { written in
			print("EXPORT: \(written.map(\.lastPathComponent).joined(separator: ", "))")
		}
	}

	/// What a right-click offers over whatever is selected, with the submenus
	/// spelled out and the shortcuts each item shows: a menu cannot be
	/// photographed while it is open, and the keys it writes down are half of
	/// what the menu is for.
	func contextMenuTitlesForTesting() -> [String] {
		guard let menu = outlineView.menu else { return [] }
		menuNeedsUpdate(menu)
		return menu.items.flatMap { item -> [String] in
			guard !item.isHidden else { return [] }
			func mark(_ entry: NSMenuItem) -> String {
				(entry.isEnabled ? "" : " (disabled)") + Self.shortcutText(entry)
			}
			let children = (item.submenu?.items ?? []).filter { !$0.isSeparatorItem }.map {
				"\(item.title) ▸ \($0.title)\(mark($0))"
			}
			return ["\(item.title)\(mark(item))"] + children
		}
	}

	/// An item's key equivalent the way the menu draws it.
	private static func shortcutText(_ item: NSMenuItem) -> String {
		guard let key = item.keyEquivalent.unicodeScalars.first else { return "" }
		let flags = item.keyEquivalentModifierMask
		var text = " "
		if flags.contains(.control) { text += "⌃" }
		if flags.contains(.option) { text += "⌥" }
		if flags.contains(.shift) { text += "⇧" }
		if flags.contains(.command) { text += "⌘" }
		switch Int(key.value) {
		case NSF2FunctionKey: text += "F2"
		case NSBackspaceCharacter, NSDeleteCharacter: text += "⌫"
		case NSCarriageReturnCharacter: text += "⏎"
		default: text += item.keyEquivalent.uppercased()
		}
		return text
	}

	/// Selects a picture that has just been written, once the tree has it.
	///
	/// Selected and not opened: an export happens while somebody is working on
	/// the diagram, and a PNG tab taking the front of the editor would be the
	/// export stealing their place. The file being shown to have arrived, in the
	/// folder they expected, is the whole of what is wanted.
	func revealExported(_ url: URL) {
		if rootNode?.node(for: url) != nil {
			selectWithoutOpening(url: url)
		} else {
			pendingReveal = url
		}
	}

	@objc private func contextRename() {
		// The same gesture from the menu, so there is one way it works.
		let row = contextNode.map { outlineView.row(forItem: $0) } ?? -1
		guard row >= 0 else { return }
		outlineView.selectRowIndexes([row], byExtendingSelection: false)
		beginRename(row: row)
	}

	@objc private func contextTrash() {
		trash(contextNodes)
	}

	/// ⌘⌫: whatever the tree has highlighted, and nothing to do with the pointer.
	///
	/// The selection rather than `contextNodes`, which starts from `clickedRow`:
	/// a row clicked earlier is still the clicked row long afterwards, and the
	/// keyboard should never trash something the keyboard cannot see it is about
	/// to trash.
	private func trashSelection() {
		trash(outlineView.selectedRowIndexes.sorted().compactMap {
			outlineView.item(atRow: $0) as? FileNode
		})
	}

	/// Moves rows to the trash.
	///
	/// All of them, and the project root is never one of them. This is the one
	/// place several rows makes the work smaller rather than larger: `recycle`
	/// already takes an array, and moving three files to the trash stops being
	/// three gestures.
	private func trash(_ nodes: [FileNode]) {
		let urls = nodes.filter { $0 !== rootNode }.map(\.url)
		guard !urls.isEmpty else { return }
		// Trash rather than delete: recoverable, and no confirmation needed.
		NSWorkspace.shared.recycle(urls) { _, error in
			guard let error else { return }
			DispatchQueue.main.async {
				Toast.post("Could not move that to the trash", detail: error.localizedDescription)
			}
		}
	}

	// MARK: - Keyboard

	/// Returns true when the event was consumed.
	///
	/// Up/Down/Left/Right are left to `NSOutlineView`, which already moves the
	/// selection and expands or collapses rows correctly — and moving the
	/// selection is what shows the file, so there is nothing to add to them.
	private func handleKeyDown(_ event: NSEvent) -> Bool {
		// Nothing on this list while a name is being edited on a row. The field
		// has the keyboard then, so these events do not normally reach here at
		// all — but ⌘⌫ reaching here would move the file being renamed to the
		// trash, and that is not a mistake worth leaving one responder-chain
		// accident away. Return is the same story with a smaller cost: in the
		// field it commits the name, which `control(_:textView:doCommandBy:)`
		// does.
		guard renameField == nil else { return false }

		switch event.keyCode {
		case 36, 76: // Return, Keypad Enter
			// Return opens, which is what every editor does. It renamed for a
			// week, after the Finder, and the cost was that the one key everyone
			// presses to open a file no longer opened it.
			//
			// ⌥Return renames instead — one of the two rename keys, and the one
			// for hands that had learned Return meant rename.
			if event.modifierFlags.contains(.option) {
				beginRename()
			} else {
				openSelection(focusEditor: true)
			}
			return true
		case 120: // F2
			// The other rename key, and the one the menu writes down: F2 renames
			// in VS Code and in every file manager that is not the Finder.
			// Deliberately two keys for one gesture — there is nothing to
			// remember wrong, at the cost of a second binding to keep working.
			beginRename()
			return true
		case 51 where event.modifierFlags.contains(.command): // ⌘⌫
			// The Finder's key for it, reached for repeatedly before it did
			// anything. The whole selection, since `recycle` takes a list.
			trashSelection()
			return true
		case 125 where event.modifierFlags.contains(.command): // ⌘↓
			// Kept, though Return now does it: it costs nothing, and somebody's
			// hands may already know it from the week Return did not.
			openSelection(focusEditor: true)
			return true
		case 49: // Space — the same provisional open, for a row already selected
			openSelection(focusEditor: false)
			return true
		default:
			return false
		}
	}

	private func openSelection(focusEditor: Bool) {
		// One row, for the same reason a selection change opens only one: four
		// tabs from one keystroke, and the last one to arrive is whichever the
		// tree happened to order last.
		guard outlineView.numberOfSelectedRows == 1 else { return }
		let row = outlineView.selectedRow
		guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }

		if node.isDirectory {
			// Return on a directory toggles it, which is what IDEA does.
			if outlineView.isItemExpanded(node) {
				outlineView.collapseItem(node)
			} else {
				outlineView.expandItem(node)
			}
			return
		}
		onSelectFile?(node.url, focusEditor)
	}

	/// Gives the tree keyboard focus, so arrow keys work without a click first.
	func focusTree() {
		view.window?.makeFirstResponder(outlineView)
		if outlineView.selectedRow < 0, outlineView.numberOfRows > 0 {
			outlineView.selectRowIndexes([0], byExtendingSelection: false)
		}
	}

	/// Folds the whole tree away, leaving the root.
	///
	/// Not the root itself: collapsing that would leave one row and nothing to
	/// click, which is a worse place to start again from than the top level.
	func collapseAll() {
		guard let rootNode else { return }
		let selected = (outlineView.item(atRow: outlineView.selectedRow) as? FileNode)?.url

		// Backwards, because collapsing a row removes the rows under it and the
		// indices of everything after them.
		for row in stride(from: outlineView.numberOfRows - 1, through: 0, by: -1) {
			guard let node = outlineView.item(atRow: row) as? FileNode, node !== rootNode else { continue }
			outlineView.collapseItem(node)
		}
		outlineView.expandItem(rootNode)

		// Whatever was selected is probably inside something that just folded up,
		// so the selection moves to the folder it went into. Losing it entirely
		// would send the next arrow key back to the top of the tree.
		guard var url = selected else { return }
		while outlineView.row(forItem: rootNode.node(for: url)) < 0 {
			let parent = url.deletingLastPathComponent()
			guard parent.path != url.path, parent.path.hasPrefix(rootNode.url.path) else { return }
			url = parent
		}
		selectWithoutOpening(url: url)
	}

	/// Finds the file the editor is showing.
	///
	/// The tree already follows along when tabs change; this is for after
	/// somebody has browsed away from it and wants to know where they were.
	func selectFileInEditor() {
		guard let url = currentEditorFile?() else { return }
		selectWithoutOpening(url: url)
		view.window?.makeFirstResponder(outlineView)
	}

	/// Expands the root's immediate children, matching how IDEA shows a freshly
	/// opened project rather than a single collapsed row.
	func expandTopLevel() {
		guard let rootNode else { return }
		outlineView.expandItem(rootNode)
		for child in rootNode.children where child.isDirectory && !child.isExcluded {
			outlineView.expandItem(child)
		}
	}

	/// Selects a file without opening it.
	///
	/// Used when the editor switches tabs: the tree should follow along, but
	/// must not call back and reopen the file it was just told about.
	func selectWithoutOpening(url: URL) {
		let wasSilent = isSelectingSilently
		isSelectingSilently = true
		reveal(url: url)
		isSelectingSilently = wasSilent
	}

	// MARK: - Verification

	/// Sends a key to the tree as the keyboard would, so what arrowing through
	/// it actually does can be checked from outside.
	///
	/// The modifiers are part of the event, so ⇧↓ selects a run of rows and ⌥⏎,
	/// ⌘⌫ and ⌘↓ are askable at all — each of them is a different gesture from
	/// the key without them.
	func pressKeyForTesting(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
		// While a name is being edited the field has the keyboard, and taking it
		// back here would end the edit before the key ever arrived — which is
		// exactly what "⌘⌫ must not trash the file being renamed" has to be able
		// to ask about. So the key goes wherever the keyboard actually is.
		if renameField == nil { view.window?.makeFirstResponder(outlineView) }
		// The characters matter: `interpretKeyEvents` maps those, not the key
		// code, and an event with none does nothing at all.
		let characters: String
		switch keyCode {
		case 126: characters = String(UnicodeScalar(NSUpArrowFunctionKey)!)
		case 125: characters = String(UnicodeScalar(NSDownArrowFunctionKey)!)
		case 123: characters = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
		case 124: characters = String(UnicodeScalar(NSRightArrowFunctionKey)!)
		case 120: characters = String(UnicodeScalar(NSF2FunctionKey)!)
		case 36: characters = "\r"
		case 49: characters = " "
		case 51: characters = String(UnicodeScalar(NSDeleteCharacter)!)
		case 53: characters = "\u{1B}" // Escape
		default: characters = ""
		}
		guard let event = NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: modifiers,
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: view.window?.windowNumber ?? 0, context: nil,
			characters: characters, charactersIgnoringModifiers: characters,
			isARepeat: false, keyCode: keyCode
		) else { return }
		// The field editor when a name is being edited, so a key pressed during
		// a rename does to the field what it would really do to it.
		let target: NSResponder = renameField?.currentEditor() ?? outlineView
		target.keyDown(with: event)
	}

	/// The name in the field standing on a row, or nil when nothing is being
	/// renamed — the difference between Return opening a file and Return doing
	/// what it used to do.
	var renamingNameForTesting: String? { renameField?.stringValue }

	/// Rebuilds the tree the way a filesystem event does, so a selection can be
	/// checked to have survived one.
	func reloadForTesting() {
		reloadTree()
	}

	/// What ⌘C would put on the pasteboard — the same closure the Edit menu
	/// reaches, asked directly, so what several selected rows copy can be read
	/// without a key window to send an action through.
	func copyTextForTesting() -> String {
		(outlineView as? NavigatorOutlineView)?.copyText?() ?? "nothing"
	}

	/// What the tree has highlighted, and how many rows it is showing.
	///
	/// Every selected row, joined — one row reads exactly as it always did, so
	/// the harness's existing output is unchanged, and several are visible at
	/// all, which is what checking that a multi-row selection survives a reload
	/// needs.
	var selectionForTesting: (name: String, rows: Int) {
		let selected = outlineView.selectedRowIndexes.sorted()
		guard !selected.isEmpty else { return ("nothing@-1", outlineView.numberOfRows) }
		let names = selected.map { row -> String in
			let node = outlineView.item(atRow: row) as? FileNode
			return "\(node?.name ?? "nothing")@\(row)"
		}
		return (names.joined(separator: "+"), outlineView.numberOfRows)
	}

	/// Selects and scrolls to a file, expanding ancestors as needed.
	func reveal(url: URL) {
		guard let rootNode, let node = rootNode.node(for: url) else { return }

		var ancestors: [FileNode] = []
		var current: FileNode? = node
		while let parent = current?.parentNode(in: rootNode) {
			ancestors.append(parent)
			current = parent
		}
		for ancestor in ancestors.reversed() {
			outlineView.expandItem(ancestor)
		}

		let row = outlineView.row(forItem: node)
		guard row >= 0 else { return }
		outlineView.selectRowIndexes([row], byExtendingSelection: false)
		outlineView.scrollRowToVisible(row)
	}
}

private extension FileNode {
	/// Walks from a known root, since `parent` is weak and may be nil for nodes
	/// reached by path lookup.
	func parentNode(in root: FileNode) -> FileNode? {
		let parentURL = url.deletingLastPathComponent().standardizedFileURL
		guard parentURL.path != url.path, parentURL.path.hasPrefix(root.url.path) else { return nil }
		return root.node(for: parentURL)
	}
}

// MARK: - Outline data

/// The row's name field while it is being edited.
///
/// Return commits, Escape puts the name back, and clicking elsewhere commits —
/// which is what every other in-place rename on this machine does, and what
/// somebody who has typed a name and looked away expects to have happened.
extension ProjectNavigatorViewController: NSTextFieldDelegate {
	func control(
		_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
	) -> Bool {
		switch selector {
		case #selector(NSResponder.insertNewline(_:)):
			commitRename()
			return true
		case #selector(NSResponder.cancelOperation(_:)):
			endRename()
			return true
		default:
			return false
		}
	}

	func controlTextDidEndEditing(_ notification: Notification) {
		// Only when the field is going of its own accord — committing already
		// takes it away, and this would otherwise commit a name it just refused.
		guard renameField != nil, notification.object as? NSTextField === renameField else { return }
		commitRename()
	}
}

extension ProjectNavigatorViewController: NSOutlineViewDataSource, NSOutlineViewDelegate,
	NSMenuDelegate, NSMenuItemValidation {
	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		guard let item else { return rootNode == nil ? 0 : 1 }
		guard let node = item as? FileNode, node.isDirectory else { return 0 }

		// Children are read the first time the outline view asks for them,
		// which may be long after the last status refresh — and rows that
		// appeared since would be drawn as though everything about them were
		// unremarkable. Asking again is cheap; the refresh coalesces.
		let wasLoaded = node.hasLoadedChildren
		let count = node.children.count
		if !wasLoaded { scheduleGitStatusRefresh() }
		return count
	}

	/// Asks for a status refresh once the current run of layout is over.
	///
	/// Not immediately: this is called from inside the outline view's own data
	/// source, and reloading rows from there is how a table ends up drawing
	/// stale geometry.
	private func scheduleGitStatusRefresh() {
		guard !hasScheduledGitStatusRefresh else { return }
		hasScheduledGitStatusRefresh = true
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.hasScheduledGitStatusRefresh = false
			self.refreshGitStatus()
		}
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		guard let item else { return rootNode! }
		let node = item as! FileNode
		return node.children[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		guard let node = item as? FileNode else { return false }
		// Reporting expandable without reading the directory keeps opening a
		// project O(1) in the number of subdirectories.
		return node.isDirectory
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		guard let node = item as? FileNode else { return nil }
		let isRoot = (node === rootNode)
		let cell = NavigatorCellView()
		cell.configure(
			node: node,
			isRoot: isRoot,
			subtitle: isRoot ? project?.displayPath : nil,
			isExpanded: outlineView.isItemExpanded(node),
			isSubproject: node.url.path == subprojectRoot?.path,
			isRenaming: renaming?.node === node
		)
		return cell
	}

	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		let node = item as? FileNode
		let row = NavigatorRowView()
		row.isExcluded = node?.isExcluded ?? false
		return row
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		// Unless the tree is moving its own selection to follow something else.
		guard !isSelectingSilently else { return }

		// One row shows the file it landed on, which is what makes arrowing
		// through the tree feel like browsing. Several show nothing new: a
		// ⇧-click over four files that opened four tabs would be a surprise, and
		// the last one opened would not be the one under the pointer.
		guard outlineView.numberOfSelectedRows == 1 else { return }

		let row = outlineView.selectedRow
		guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode, !node.isDirectory else { return }
		// Provisionally, and without taking focus: a click or an arrow key shows
		// the file while the tree keeps the keyboard, so the next arrow works.
		// Return, or a double-click, is what pins the tab and moves focus.
		onSelectFile?(node.url, false)
	}

	/// Tailors the menu to the row it was opened on: directories cannot be
	/// "opened externally" in a meaningful way, and the project root should not
	/// offer to trash itself.
	/// Files can be dragged out — onto the terminal, or into another app.
	///
	/// The URL is the whole payload: every receiver already knows what to do
	/// with one, and the terminal turns it into a path.
	func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
		(item as? FileNode)?.url as NSURL?
	}

	/// Tailors each item to how many rows the menu was opened over.
	///
	/// `node` is the single row, and nil when there are several — so everything
	/// that only makes sense one at a time switches itself off without being
	/// told about the count. `nodes` is all of them, for the two that take a
	/// list.
	func menuNeedsUpdate(_ menu: NSMenu) {
		refreshNewMenu()
		let nodes = contextNodes
		let node = contextNode
		let isRoot = node === rootNode

		for item in menu.items {
			// The two items that are only a submenu, before anything looks at an
			// action — because an item with a submenu does not have the action it
			// was made with. AppKit replaces it with its own `submenuAction:` the
			// moment the submenu is attached, so `case nil where item.submenu ===`
			// never matched and "New" has been quietly following the rule meant
			// for everything else: greyed over four rows, though a new file has
			// one place to go however many are selected.
			if item.submenu === exportMenu {
				// Hidden unless a diagram was clicked — it means nothing over a
				// Swift file — and greyed when several rows were, for the same
				// reason Rename is: one file, one answer.
				// `holdsADiagram` rather than `isDiagram`, because a Markdown file
				// is one only when somebody has written a ```mermaid block in it —
				// and an Export over every `.md` in a repository would be wrong far
				// more often than right.
				item.isHidden = !nodes.contains { !$0.isDirectory && DiagramExport.holdsADiagram($0.url) }
				let single = node.map { !$0.isDirectory && DiagramExport.holdsADiagram($0.url) } ?? false
				item.isEnabled = single
				if let submenu = item.submenu {
					DiagramExportMenu.fill(
						submenu, theme: Theme.current.isLight ? .light : .dark,
						stated: single ? statedLook(of: node) : nil,
						target: self, action: #selector(contextExport(_:)), enabled: single,
						// The picture that is also the document, which only
						// draw.io has: `architecture.drawio.png` rather than
						// `architecture.png`.
						editable: single && (node.map { Drawio.isDiagram($0.url) } ?? false)
					)
				}
				continue
			}
			if item.submenu === newMenu {
				// A new file has one place to go whatever is selected: beside the
				// topmost row, or in the project root when nothing is.
				item.isEnabled = rootNode != nil
				continue
			}

			switch item.action {
			case #selector(contextOpenExternally):
				item.isHidden = node?.isDirectory ?? true
			case #selector(contextPreviewModel):
				item.isHidden = !(node.map { ModelPreview.canPreview($0.url) } ?? false)
					|| !ModelPreview.isAvailable
			case #selector(contextOpenSubproject):
				// Only a folder, and not the one already being worked on.
				let folder = node?.isDirectory == true && !isRoot
				item.isHidden = !folder || node?.url.path == subprojectRoot?.path
			case #selector(contextLeaveSubproject):
				item.isHidden = subprojectRoot == nil
			case #selector(contextRename):
				// One row. Renaming whichever came first is worse than not
				// offering it.
				item.isEnabled = node != nil && !isRoot
			case #selector(contextTrash):
				// All of them, less the project root, which never trashes itself.
				item.isEnabled = nodes.contains { $0 !== rootNode }
			case #selector(contextCopyPath), #selector(contextCopyRelativePath):
				item.isEnabled = !nodes.isEmpty
			case #selector(contextCollapseAll):
				// About the tree, not about a row: right-clicking empty space
				// still offers it.
				item.isEnabled = rootNode != nil
			case #selector(contextSelectOpenFile):
				item.isEnabled = currentEditorFile?() != nil
			default:
				item.isEnabled = node != nil
			}
		}
	}

	/// Keeps what `menuNeedsUpdate` decided.
	///
	/// Without this, AppKit's automatic enabling runs after the delegate and
	/// switches every item back on merely because this object answers to its
	/// action — which is exactly what "Rename… is off for four rows" is not
	/// about. The rule lives in one place; this stops the frame overruling it.
	func validateMenuItem(_ item: NSMenuItem) -> Bool { item.isEnabled }

	/// Lets the outline view's built-in type-select find rows. Without this the
	/// custom cells expose no string and typing does nothing.
	func outlineView(_ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any) -> String? {
		(item as? FileNode)?.name
	}

	func outlineViewItemDidExpand(_ notification: Notification) {
		// Newly-loaded children have no VCS state yet.
		refreshGitStatus()
	}
}

// MARK: - Header

/// The "Project ⌄" strip above the tree.
private final class NavigatorHeaderView: NSView {
	override var isFlipped: Bool { true }

	/// The two things a tree this size needs and cannot do by itself: fold
	/// everything away, and find its way back to whatever the editor is showing.
	var onCollapseAll: (() -> Void)?
	var onSelectOpenFile: (() -> Void)?

	private lazy var collapseButton = button(
		symbol: "arrow.down.right.and.arrow.up.left",
		tooltip: "Collapse all",
		action: #selector(collapseAll)
	)
	private lazy var locateButton = button(
		symbol: "scope",
		tooltip: "Select the file in the editor",
		action: #selector(selectOpenFile)
	)

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		for view in [locateButton, collapseButton] { addSubview(view) }
		layoutButtons()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("not from a nib") }

	private func button(symbol: String, tooltip: String, action: Selector) -> NSButton {
		let button = NSButton(image: NSImage(), target: self, action: action)
		button.image = Theme.symbol(
			symbol, size: Theme.current.scaled(11),
			color: Theme.current.sidebarHeaderText, weight: .medium
		)
		button.isBordered = false
		button.bezelStyle = .shadowlessSquare
		button.imagePosition = .imageOnly
		button.toolTip = tooltip
		// Nothing here should take focus from the tree, which is the point of
		// the buttons: the keyboard stays where it was.
		button.refusesFirstResponder = true
		return button
	}

	override func layout() {
		super.layout()
		layoutButtons()
	}

	private func layoutButtons() {
		let size = Theme.current.scaled(20)
		var x = bounds.maxX - Theme.current.scaled(8) - size
		// Rightmost first.
		for view in [locateButton, collapseButton] {
			view.frame = NSRect(x: x, y: (bounds.height - size) / 2, width: size, height: size)
			x -= size + Theme.current.scaled(2)
		}
	}

	/// Redrawn on a theme or zoom change, since the symbols carry their colour
	/// and their size in the image itself.
	func restyle() {
		collapseButton.image = Theme.symbol(
			"arrow.down.right.and.arrow.up.left", size: Theme.current.scaled(11),
			color: Theme.current.sidebarHeaderText, weight: .medium
		)
		locateButton.image = Theme.symbol(
			"scope", size: Theme.current.scaled(11),
			color: Theme.current.sidebarHeaderText, weight: .medium
		)
		layoutButtons()
		needsDisplay = true
	}

	@objc private func collapseAll() { onCollapseAll?() }
	@objc private func selectOpenFile() { onSelectOpenFile?() }

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()

		let attributed = NSAttributedString(string: "Project", attributes: [
			.font: Theme.current.uiFont(13, weight: .semibold),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		let size = attributed.size()
		attributed.draw(at: NSPoint(x: Theme.current.scaled(12), y: bounds.midY - size.height / 2))

		let path = NSBezierPath()
		let x = Theme.current.scaled(12) + size.width + Theme.current.scaled(8)
		path.move(to: NSPoint(x: x, y: bounds.midY - 2))
		path.line(to: NSPoint(x: x + 3.5, y: bounds.midY + 2))
		path.line(to: NSPoint(x: x + 7, y: bounds.midY - 2))
		path.lineWidth = 1.3
		path.lineCapStyle = .round
		path.lineJoinStyle = .round
		Theme.current.sidebarText.withAlphaComponent(0.8).setStroke()
		path.stroke()
	}
}

// MARK: - Rows

/// Outline view that hands key events to the controller before acting on them.
final class NavigatorOutlineView: NSOutlineView {
	var onKeyDown: ((NSEvent) -> Bool)?
	/// What ⌘C should put on the pasteboard, or nil when nothing is selected.
	var copyText: (() -> String?)?

	override var acceptsFirstResponder: Bool { true }

	/// ⌘C copies the selected file's path.
	///
	/// Answered here rather than bound to a key, so it arrives the way copying
	/// arrives everywhere else: the Edit menu sends `copy:` down the responder
	/// chain, this is the responder when the tree has the keyboard, and the
	/// menu item greys itself out when there is nothing selected to copy.
	@objc func copy(_ sender: Any?) {
		guard let text = copyText?() else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		if item.action == #selector(copy(_:)) { return copyText?() != nil }
		return super.validateUserInterfaceItem(item)
	}

	override func keyDown(with event: NSEvent) {
		if onKeyDown?(event) == true { return }
		super.keyDown(with: event)
	}

	/// Redraw selected rows when focus moves, so the highlight dims correctly.
	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		return super.resignFirstResponder()
	}
}

private final class NavigatorRowView: NSTableRowView {
	var isExcluded = false

	/// Cells draw their label colour from the selection state, so they have to
	/// repaint when it changes — NSTableRowView only invalidates itself.
	override var isSelected: Bool {
		didSet {
			guard isSelected != oldValue else { return }
			for subview in subviews { subview.needsDisplay = true }
		}
	}

	override func drawBackground(in dirtyRect: NSRect) {
		super.drawBackground(in: dirtyRect)
		// Excluded output directories get a warm tint, as in the reference.
		if isExcluded && !isSelected {
			Theme.current.excludedDirectoryTint.withAlphaComponent(0.35).setFill()
			bounds.fill()
		}
	}

	override func drawSelection(in dirtyRect: NSRect) {
		// A rounded, inset pill rather than a full-bleed band — the shape IDEA
		// uses. Focused selection is blue; unfocused grey, so the tree still
		// shows where you are while the editor has keyboard focus.
		let color = isTreeFocused ? Theme.current.selectionActive : Theme.current.selectionInactive
		let rect = bounds.insetBy(dx: Theme.current.scaled(5), dy: 1)
		let radius = Theme.current.scaled(6)
		let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
		color.setFill()
		path.fill()
	}

	/// True when the outline view containing this row holds keyboard focus.
	var isTreeFocused: Bool {
		guard let window, let responder = window.firstResponder as? NSView else { return false }
		return responder === superview || responder.isDescendant(of: superview ?? self)
	}
}

/// A text field cell whose text sits in the middle of its box.
///
/// `NSTextFieldCell` draws its text at the top of whatever height it is given
/// and offers no way to say otherwise, which is why every list that edits a
/// name in place ends up with one of these. The three overrides are the three
/// rects it uses: one to draw through, and two for the field editor, which is a
/// separate view laid into the cell and would otherwise stay at the top while
/// the drawn text moved.
private final class CentredFieldCell: NSTextFieldCell {
	private func centred(_ rect: NSRect) -> NSRect {
		let height = cellSize(forBounds: rect).height
		guard rect.height > height else { return rect }
		var centred = rect
		centred.origin.y += ((rect.height - height) / 2).rounded()
		centred.size.height = height
		return centred
	}

	override func drawingRect(forBounds rect: NSRect) -> NSRect {
		super.drawingRect(forBounds: centred(rect))
	}

	override func edit(
		withFrame rect: NSRect, in controlView: NSView,
		editor: NSText, delegate: Any?, event: NSEvent?
	) {
		super.edit(
			withFrame: centred(rect), in: controlView,
			editor: editor, delegate: delegate, event: event
		)
	}

	override func select(
		withFrame rect: NSRect, in controlView: NSView,
		editor: NSText, delegate: Any?, start: Int, length: Int
	) {
		super.select(
			withFrame: centred(rect), in: controlView,
			editor: editor, delegate: delegate, start: start, length: length
		)
	}
}

private final class NavigatorCellView: NSTableCellView {
	private var node: FileNode?
	private var isRoot = false
	private var subtitle: String?
	private var isExpanded = false

	func configure(
		node: FileNode,
		isRoot: Bool,
		subtitle: String?,
		isExpanded: Bool,
		isSubproject: Bool = false,
		isRenaming: Bool = false
	) {
		self.node = node
		self.isRoot = isRoot
		self.subtitle = subtitle
		self.isExpanded = isExpanded
		self.isSubproject = isSubproject
		self.isRenaming = isRenaming
		needsDisplay = true
	}

	/// Whether the field is standing on this row.
	///
	/// The name is then not drawn at all. Drawing it under the field and
	/// covering it up looks the same only while the field is as wide as the
	/// name it replaced — and it is not, since it stops at the edge of the
	/// pane, so the tail of the old name showed past the field's right border
	/// with the new one already typed in front of it.
	var isRenaming = false {
		didSet { if isRenaming != oldValue { needsDisplay = true } }
	}

	/// The folder the run button, git and the language server are pointed at.
	private var isSubproject = false

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		guard let node else { return }

		var x = Theme.current.scaled(2)
		let iconSize = Theme.current.scaled(16)

		// The folder being worked on is tinted rather than decorated: a mark
		// beside the name reads as a status — modified, added — and this is not
		// a status. It is which folder everything is pointed at.
		let icon = isSubproject
			? FileIcon.subprojectFolder()
			: FileIcon.image(for: node, isExpanded: isExpanded)
		if let icon {
			icon.drawFitted(
				in: NSRect(x: x, y: bounds.midY - iconSize / 2, width: iconSize, height: iconSize)
			)
		}
		x += iconSize + Theme.current.scaled(6)

		// On a selected row the VCS colour would fight the pill behind it, so the
		// label goes to whichever plain ink the palette reads with — the
		// treatment IDEA uses. Near-white was written for the dark theme's blue
		// and disappeared entirely on the light theme's pale one, which the
		// presentation mode ships by default.
		let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
		// The subproject is written the way the project above it is — bold and
		// bright — because that is what it is here: the project everything is
		// pointed at. The blue folder says which of the two.
		let nameColor: NSColor = isSelected
			? (Theme.current.isLight ? Theme.current.sidebarHeaderText : .hex(0xE8EAED))
			: (isRoot || isSubproject
				? Theme.current.sidebarHeaderText
				: Theme.current.color(for: node.gitStatus))
		let nameFont = isRoot || isSubproject
			? Theme.current.uiFont(13, weight: .bold)
			: Theme.current.uiFont(13)

		// The icon stays while the name is being edited — it says what kind of
		// thing this is, and the field does not cover it — but the name itself
		// belongs to the field now.
		if isRenaming { return }

		// Truncated rather than run past the edge: a long name would otherwise
		// draw straight over the row's rounded selection and out of the pane.
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let name = NSAttributedString(string: node.name, attributes: [
			.font: nameFont,
			.foregroundColor: nameColor,
			.paragraphStyle: paragraph,
		])
		let nameSize = name.size()
		let trailing = Theme.current.scaled(8)
		let available = max(0, bounds.width - x - trailing)
		let nameWidth = min(ceil(nameSize.width), available)
		name.draw(in: NSRect(
			x: x,
			y: bounds.midY - nameSize.height / 2,
			width: nameWidth,
			height: nameSize.height
		))
		x += nameWidth + trailing

		if let subtitle {
			let attributed = NSAttributedString(string: subtitle, attributes: [
				.font: Theme.current.uiFont(11),
				.foregroundColor: Theme.current.gitIgnored,
				.paragraphStyle: paragraph,
			])
			let size = attributed.size()
			attributed.draw(in: NSRect(
				x: x,
				y: bounds.midY - size.height / 2,
				width: max(0, bounds.width - x - trailing),
				height: size.height
			))
		}
	}

}
