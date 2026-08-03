import AppKit
import IdeaiKit

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
		outline.allowsMultipleSelection = false
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
			name: .ideaiRepositoryChanged,
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
		// Reported before the early return below: the staging view cares about
		// any edit, not only ones in a directory the tree happens to have
		// expanded.
		onFilesChanged?()

		guard let rootNode else { return }

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
		let selected = selectedPath()
		outlineView.reloadData()
		restore(expandedPaths: expanded)
		restoreSelection(path: selected)
		refreshGitStatus()
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
		let selected = selectedPath()
		rootNode.invalidate()
		outlineView.reloadData()
		outlineView.expandItem(rootNode)
		restore(expandedPaths: expanded)
		restoreSelection(path: selected)
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
		guard let rootNode else { return }
		let expanded = expandedPaths()
		let selected = selectedPath()
		rootNode.reloadPreservingIdentity()
		outlineView.reloadData()
		restore(expandedPaths: expanded)

		if let pending = pendingReveal, rootNode.node(for: pending) != nil {
			pendingReveal = nil
			selectWithoutOpening(url: pending)
		} else {
			restoreSelection(path: selected)
		}
		refreshGitStatus()
	}

	private func selectedPath() -> String? {
		let row = outlineView.selectedRow
		guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return nil }
		return node.url.path
	}

	/// Reselects by path, since reloadData replaces the row indices.
	private func restoreSelection(path: String?) {
		guard let path, let rootNode,
		      let node = rootNode.node(for: URL(fileURLWithPath: path))
		else { return }
		let row = outlineView.row(forItem: node)
		guard row >= 0 else { return }

		// Restoring must not be mistaken for somebody choosing the file, which
		// would reopen it in the editor.
		let wasSilent = isSelectingSilently
		isSelectingSilently = true
		outlineView.selectRowIndexes([row], byExtendingSelection: false)
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

		menu.addItem(item("New File…", #selector(contextNewFile)))
		menu.addItem(item("New Folder…", #selector(contextNewFolder)))
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
		menu.addItem(.separator())
		menu.addItem(item("Rename…", #selector(contextRename)))
		menu.addItem(item("Move to Trash", #selector(contextTrash)))
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

	/// The row the menu applies to: the right-clicked row, or the selection when
	/// the menu was opened from the keyboard.
	private var contextNode: FileNode? {
		let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
		guard row >= 0 else { return nil }
		return outlineView.item(atRow: row) as? FileNode
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

	@objc private func contextCopyPath() {
		guard let node = contextNode else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(node.url.path, forType: .string)
	}

	@objc private func contextCopyRelativePath() {
		guard let node = contextNode, let root = project?.root else { return }
		let path = node.url.path
		let relative = path.hasPrefix(root.path + "/")
			? String(path.dropFirst(root.path.count + 1))
			: path
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(relative, forType: .string)
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
	/// "new file here" means when the thing under the pointer is a file.
	private var contextParentDirectory: URL? {
		if let node = contextNode {
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
				NotificationCenter.default.post(name: .ideaiRepositoryChanged, object: root)
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

	@objc private func contextNewFile() {
		guard let parent = contextParentDirectory,
		      let name = askForName(kind: .file, in: parent)
		else { return }

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

		if let node = contextNode, node.isDirectory { outlineView.expandItem(node) }
		pendingReveal = destination
		// Opened straight away: a new file is made in order to write in it.
		onSelectFile?(destination, true)
	}

	@objc private func contextNewFolder() {
		let parent: URL
		if let node = contextNode {
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
		if let node = contextNode, node.isDirectory {
			outlineView.expandItem(node)
		}
		pendingReveal = destination
	}

	@objc private func contextRename() {
		guard let node = contextNode else { return }

		let alert = NSAlert()
		alert.messageText = "Rename \(node.name)"
		alert.addButton(withTitle: "Rename")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
		field.stringValue = node.name
		alert.accessoryView = field
		alert.window.initialFirstResponder = field

		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !newName.isEmpty, newName != node.name else { return }

		let destination = node.url.deletingLastPathComponent().appendingPathComponent(newName)
		do {
			try FileManager.default.moveItem(at: node.url, to: destination)
			// The filesystem watcher refreshes the tree on its own.
		} catch {
			Toast.post("Could not create the folder", detail: error.localizedDescription)
		}
	}

	@objc private func contextTrash() {
		guard let node = contextNode else { return }
		// Trash rather than delete: recoverable, and no confirmation needed.
		NSWorkspace.shared.recycle([node.url]) { _, error in
			guard let error else { return }
			DispatchQueue.main.async {
				Toast.post("Could not rename that", detail: error.localizedDescription)
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
		switch event.keyCode {
		case 36, 76: // Return, Keypad Enter
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
	func pressKeyForTesting(_ keyCode: UInt16) {
		view.window?.makeFirstResponder(outlineView)
		// The characters matter: `interpretKeyEvents` maps those, not the key
		// code, and an event with none does nothing at all.
		let characters: String
		switch keyCode {
		case 126: characters = String(UnicodeScalar(NSUpArrowFunctionKey)!)
		case 125: characters = String(UnicodeScalar(NSDownArrowFunctionKey)!)
		case 123: characters = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
		case 124: characters = String(UnicodeScalar(NSRightArrowFunctionKey)!)
		case 36: characters = "\r"
		case 49: characters = " "
		default: characters = ""
		}
		guard let event = NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: view.window?.windowNumber ?? 0, context: nil,
			characters: characters, charactersIgnoringModifiers: characters,
			isARepeat: false, keyCode: keyCode
		) else { return }
		outlineView.keyDown(with: event)
	}

	/// What the tree has highlighted, and how many rows it is showing.
	var selectionForTesting: (name: String, rows: Int) {
		let row = outlineView.selectedRow
		let node = row >= 0 ? outlineView.item(atRow: row) as? FileNode : nil
		return ("\(node?.name ?? "nothing")@\(row)", outlineView.numberOfRows)
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

extension ProjectNavigatorViewController: NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
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
			isSubproject: node.url.path == subprojectRoot?.path
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

	func menuNeedsUpdate(_ menu: NSMenu) {
		let node = contextNode
		let isRoot = node === rootNode

		for item in menu.items {
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
			case #selector(contextRename), #selector(contextTrash):
				item.isEnabled = node != nil && !isRoot
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

	override var acceptsFirstResponder: Bool { true }

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
		isSubproject: Bool = false
	) {
		self.node = node
		self.isRoot = isRoot
		self.subtitle = subtitle
		self.isExpanded = isExpanded
		self.isSubproject = isSubproject
		needsDisplay = true
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

		// On a selected row the VCS colour would fight the blue behind it, so the
		// label goes near-white — the treatment IDEA uses.
		let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
		// The subproject is written the way the project above it is — bold and
		// bright — because that is what it is here: the project everything is
		// pointed at. The blue folder says which of the two.
		let nameColor: NSColor = isSelected
			? .hex(0xE8EAED)
			: (isRoot || isSubproject
				? Theme.current.sidebarHeaderText
				: Theme.current.color(for: node.gitStatus))
		let nameFont = isRoot || isSubproject
			? Theme.current.uiFont(13, weight: .bold)
			: Theme.current.uiFont(13)

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
