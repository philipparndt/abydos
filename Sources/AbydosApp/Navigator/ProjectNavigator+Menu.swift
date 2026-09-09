import AppKit
import AbydosKit

/// What a right-click on a row offers, and what each item does.
extension ProjectNavigatorViewController {
	// MARK: - Context menu

	func makeContextMenu() -> NSMenu {
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
		//
		// No ellipsis on either since 0439. It said a dialog was about to ask
		// for the name, and nothing asks any more — the row appears in the tree
		// with the name selected on it, which is what the Finder's "New Folder"
		// does and why the Finder does not write an ellipsis on it either.
		// A session's row, and only that: the id is unreadable and is exactly
		// what `claude --resume` takes, so the row hands it over as a command.
		// First in the menu, because for a session row it is the only item in it
		// that means anything.
		let resume = item("Copy Resume Command", #selector(contextCopyResumeCommand))
		resumeItem = resume
		menu.addItem(resume)
		// **And a way into the directory itself**, for both rows of that root.
		// Reported: right-clicking `Claude Sessions` offered the whole file menu
		// — New, Rename, *Move to Trash* — and nothing that applies to it. Its
		// own two items are these, and the file menu is not one of them.
		let revealSession = item("Reveal in Finder", #selector(contextRevealSessionInFinder))
		revealSessionItem = revealSession
		menu.addItem(revealSession)

		let new = NSMenuItem(title: "New", action: nil, keyEquivalent: "")
		let kinds = NSMenu()
		kinds.addItem(item("File", #selector(contextNewFile)))
		kinds.addItem(item("Folder", #selector(contextNewFolder)))
		new.submenu = kinds
		newMenu = kinds
		menu.addItem(new)
		menu.addItem(.separator())
		menu.addItem(item("Open", #selector(contextOpen)))
		menu.addItem(item("Open Externally", #selector(contextOpenExternally)))
		menu.addItem(item("Blame", #selector(contextBlame)))
		menu.addItem(item("Open as Hex", #selector(contextOpenAsHex)))
		// Space does this too. Written down here because a key with nothing
		// naming it is a key nobody finds — and hidden per click, like the
		// model preview below, because whether it is worth offering depends on
		// what was clicked.
		let look = item("Quick Look", #selector(contextQuickLook))
		look.keyEquivalent = " "
		look.keyEquivalentModifierMask = []
		menu.addItem(look)
		// Built once and hidden per click: the menu exists long before anything
		// has been right-clicked, so it cannot be decided here.
		menu.addItem(item("Preview in GoSTL", #selector(contextPreviewModel)))
		// Comparing the file with its git past. Both destinations exist — the
		// diff tab and the file-scoped log — and neither was reachable from
		// the file it is about.
		// Two rows of one kind selected: the page that puts them side by side.
		let selected = item("Compare Selected", #selector(contextCompareSelected))
		compareSelectedItem = selected
		menu.addItem(selected)
		let compare = NSMenuItem(title: "Compare", action: nil, keyEquivalent: "")
		let comparing = NSMenu()
		let against = item("Against Last Commit", #selector(contextCompareAgainstHead))
		let history = item("History\u{2026}", #selector(contextCompareHistory))
		let with = item("With\u{2026}", #selector(contextCompareWith))
		comparing.addItem(against)
		comparing.addItem(history)
		comparing.addItem(.separator())
		comparing.addItem(with)
		compare.submenu = comparing
		compareMenu = comparing
		compareAgainstItem = against
		compareHistoryItem = history
		compareWithItem = with
		menu.addItem(compare)
		menu.addItem(.separator())
		menu.addItem(item("Open as Subproject", #selector(contextOpenSubproject)))
		menu.addItem(item("Leave Subproject", #selector(contextLeaveSubproject)))
		menu.addItem(.separator())
		menu.addItem(item("Open Terminal Here", #selector(contextOpenTerminal)))
		menu.addItem(item("Reveal in Finder", #selector(contextRevealInFinder)))
		menu.addItem(.separator())
		// ⌘C, written down at last: it has always copied the absolute paths, and
		// since 0436 it copies the files themselves alongside them.
		let copyPath = item("Copy Path", #selector(contextCopyPath))
		copyPath.keyEquivalent = "c"
		copyPath.keyEquivalentModifierMask = [.command]
		menu.addItem(copyPath)
		// The Finder's two words for the two pastes. Like Rename… and Move to
		// Trash below, nothing dispatches these — a contextual menu is not the
		// main menu — but this is the only place ⌥⌘V is written down at all.
		let pasteItem = item("Paste Item", #selector(contextPaste))
		pasteItem.keyEquivalent = "v"
		pasteItem.keyEquivalentModifierMask = [.command]
		menu.addItem(pasteItem)
		let moveItem = item("Move Item Here", #selector(contextPasteAsMove))
		moveItem.keyEquivalent = "v"
		moveItem.keyEquivalentModifierMask = [.command, .option]
		menu.addItem(moveItem)
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
		//
		// Ellipsis-free for the same reason New is: renaming has edited the row
		// in place since 0411, so the promise of a dialog was already stale.
		let rename = item("Rename", #selector(contextRename))
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
		installArchiveMenuItems(in: menu)
		return menu
	}

	@objc func contextCollapseAll() { collapseAll() }
	@objc func contextSelectOpenFile() { selectFileInEditor() }

	@objc func contextOpenSubproject() {
		guard let node = contextNode, node.isDirectory else { return }
		onOpenSubproject?(node.url)
	}

	@objc func contextLeaveSubproject() {
		onLeaveSubproject?()
	}

	/// Every row the menu applies to, in tree order.
	///
	/// Right-clicking inside the selection means all of it — the gesture every
	/// file manager has, and the reason ⇧-clicking four files and asking for the
	/// trash works. Right-clicking a row *outside* the selection means that row
	/// alone: the pointer is the more recent statement of what is meant.
	var contextNodes: [FileNode] {
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
	var contextNode: FileNode? {
		let nodes = contextNodes
		return nodes.count == 1 ? nodes.first : nil
	}



	/// The row of the sessions root the menu was opened on — the root itself, or
	/// one session — if it was opened on either.
	var contextSessionRow: SessionNode? {
		let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
		guard row >= 0 else { return nil }
		return outlineView.item(atRow: row) as? SessionNode
	}

	/// The session row the menu was opened on, if it was opened on one. The
	/// root is not one: it has no id, and no session to resume.
	var contextSession: AgentSession? { contextSessionRow?.session }

	/// The directory a row of that root stands for: a session's own, or the one
	/// every session of this project sits in.
	var contextSessionDirectory: URL? {
		guard let row = contextSessionRow else { return nil }
		if let session = row.session { return session.directory }
		// The root: taken from one of its sessions rather than rebuilt from a
		// slug nobody should have to spell twice.
		return row.childNodes.first?.session?.directory.deletingLastPathComponent()
	}

	@objc private func contextRevealSessionInFinder() {
		guard let directory = contextSessionDirectory else { return }
		NSWorkspace.shared.activateFileViewerSelecting([directory])
	}

	/// Copies what somebody would type to carry that session on.
	///
	/// **What a session id is for.** It is unreadable and unmemorable, and it is
	/// exactly what `claude --resume` wants — so the row that could not be named
	/// by its id hands the id over as a command instead.
	@objc func contextCopyResumeCommand() {
		// Not for one that is already running, which the menu also hides — but
		// hiding an item is a thing a menu does, not a thing the action knows,
		// and the driven report reads the two separately: `offers=[…] copied=…`
		// said in one line that nothing was offered and something was copied.
		guard let session = contextSession, !session.isLive else { return }
		let command = AgentSessions.resumeCommand(for: session)
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(command, forType: .string)
		Toast.post("Copied", detail: command, kind: .information)
	}

	@objc private func contextOpen() {
		guard let node = contextNode else { return }
		if node.isDirectory {
			outlineView.isItemExpanded(node) ? outlineView.collapseItem(node) : outlineView.expandItem(node)
		} else {
			onSelectFile?(node.url, true)
		}
	}

	@objc func contextPreviewModel() {
		guard let node = contextNode else { return }
		onPreviewModel?(node.url)
	}

	@objc func contextOpenExternally() {
		guard let node = contextNode else { return }
		NSWorkspace.shared.open(node.url)
	}

	@objc func contextBlame() {
		guard let node = contextNode, !node.isDirectory else { return }
		onBlame?(node.url)
	}

	/// *Blame* on the selected file row, for the driver.
	func blameSelectedForTesting() -> String {
		guard let node = outlineView.item(atRow: outlineView.selectedRow) as? FileNode, !node.isDirectory else {
			return "blame: no file row selected"
		}
		onBlame?(node.url)
		return "blame: \(node.name)"
	}

	@objc func contextOpenAsHex() {
		guard let node = contextNode, !node.isDirectory else { return }
		onOpenAsHex?(node.url)
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

	/// One path a line, in tree order — the shape a list of files is wanted in —
	/// and the files themselves alongside, which is what ⌘C is.
	@objc func contextCopyPath() {
		let urls = contextNodes.map(\.url)
		guard !urls.isEmpty else { return }
		FilePasteboard.write(urls)
	}

	@objc func contextCopyRelativePath() {
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

	/// Text and nothing else, which is right for the one caller left: a relative
	/// path names no file the rest of the machine could find.
	private func copyToPasteboard(_ paths: [String]) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
	}

	/// Writes a folder straight to disk, without the row or the field, for the
	/// harness's older scripts: this is the file system doing it, not the
	/// gesture. `beginNewForTesting` is the gesture.
	func createFolderForTesting(named name: String) {
		guard let root = project?.root else { return }
		let destination = root.appendingPathComponent(name)
		try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
		pendingReveal = [destination]
	}

	func createFileForTesting(named name: String) {
		guard let root = project?.root else { return }
		let destination = root.appendingPathComponent(name)
		try? FileManager.default.createDirectory(
			at: destination.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try? Data().write(to: destination, options: .withoutOverwriting)
		pendingReveal = [destination]
		onSelectFile?(destination, true)
	}

	/// Where a new entry from the context menu goes.
	///
	/// The same answer a drop gets, from the same function: inside the folder
	/// that was clicked, or beside the file that was clicked. The first of
	/// several, since a new file has one place to go and the topmost row is the
	/// one somebody would point at.
	var contextParentDirectory: URL? {
		destinationFolder(for: contextNodes.first)
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


	@objc private func ignorePatternChosen(_ sender: NSPopUpButton) {
		guard ignoreSuggestions.indices.contains(sender.indexOfSelectedItem) else { return }
		ignoreField?.stringValue = ignoreSuggestions[sender.indexOfSelectedItem].pattern
	}

	/// Puts this project's own kinds under "New", below File and Folder.
	///
	/// Rebuilt as the menu opens rather than kept in step with the tree: the
	/// count is cached, so this is a few string comparisons unless something
	/// has changed, and a menu that is right whenever it is looked at needs no
	/// invalidation rules of its own.
	/// Counts the kinds of file the project holds, from the palette's index.
	///
	/// The index is built by one `git ls-files` and mended as files come and go,
	/// so this costs a map over a list that is already in memory — against the
	/// walk it replaces, which `FileIndex` itself documents as 3.05 s where the
	/// index took 0.03 s.
	///
	/// One at a time: a `git checkout` names thousands of files in a few batches
	/// and every batch marks the count stale, and there is no sense in a second
	/// recount of a list the first one is already reading.
	private func recountFileKinds() {
		guard fileKindsTask == nil, let files = project?.files else { return }
		// Cleared before the work rather than after it, so a change arriving
		// during the recount is not forgotten — it marks the flag again and the
		// next menu asks for another.
		fileKindsAreStale = false
		fileKindsTask = Task { [weak self] in
			let paths = await files.indexedPaths()
			let kinds = NewFileKinds.choose(from: paths)
			await MainActor.run {
				guard let self else { return }
				self.fileKindsTask = nil
				// An index that has not finished its first build answers with
				// nothing, and nothing is not an answer — it would empty a submenu
				// that had perfectly good entries in it. Left alone, and asked
				// again next time.
				guard !kinds.isEmpty else {
					self.fileKindsAreStale = true
					return
				}
				guard kinds != self.fileKinds else { return }
				self.fileKinds = kinds
				self.refreshNewMenu()
			}
		}
	}

	func refreshNewMenu() {
		guard let menu = newMenu else { return }
		while menu.numberOfItems > 2 { menu.removeItem(at: menu.numberOfItems - 1) }

		// **Never a walk of the project from here.** This runs inside
		// `menuNeedsUpdate`, which AppKit calls while the menu is opening, on the
		// main thread, with the menu on screen waiting for it to return. It used
		// to call `NewFileKinds.inProject`, which collects every file in the
		// project — and because the watcher cleared the cache on any change, that
		// walk was paid again on the next right-click after every save. On a
		// repository of 43,600 entries a right-click took seconds, for a submenu
		// of five items.
		//
		// What is shown is whatever was last counted; a recount is asked for here
		// and arrives later.
		if fileKindsAreStale { recountFileKinds() }
		guard let kinds = fileKinds, !kinds.isEmpty else { return }

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
	/// Everything else is what New ▸ File does — the same row, the same field,
	/// the same validation — because the shortcut is about the extension and
	/// nothing else. What it changes is the two things the field starts with:
	/// the name has the extension on it already, and only the stem is selected.
	@objc private func contextNewFileOfKind(_ sender: NSMenuItem) {
		guard let suffix = sender.representedObject as? String else { return }
		let kind = NewFileKind(name: suffix, count: 0, title: sender.title)
		beginNew(kind: .file, named: NewFileKinds.name(EntryName.draftName(kind: .file), endingIn: kind))
	}

	/// The same gesture as the context menu's New ▸ File, asked for from the
	/// menu bar.
	///
	/// Muscle memory goes to the File menu first, and for as long as the tree
	/// has been able to make files there was nothing there — the gesture
	/// existed only under a right-click, which is a place you have to already
	/// know to look. Nothing is decided differently here: the row lands in the
	/// selected folder, or beside the selected file, or in the project root
	/// when nothing is selected, which is the answer `beginNew` already gives a
	/// right-click on empty space.
	func beginNewEntry(kind: EntryName.Kind) {
		beginNew(kind: kind)
	}

	@objc private func contextNewFile() {
		beginNew(kind: .file)
	}

	@objc private func contextNewFolder() {
		beginNew(kind: .folder)
	}
}
