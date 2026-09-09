import AppKit
import AbydosKit

/// The keys the tree answers to, and the checks a driven run makes against it.
extension ProjectNavigatorViewController {
	// MARK: - Keyboard

	/// Returns true when the event was consumed.
	///
	/// Up/Down/Left/Right are left to `NSOutlineView`, which already moves the
	/// selection and expands or collapses rows correctly — and moving the
	/// selection is what shows the file, so there is nothing to add to them.
	func handleKeyDown(_ event: NSEvent) -> Bool {
		// Nothing on this list while a name is being edited on a row. The field
		// has the keyboard then, so these events do not normally reach here at
		// all — but ⌘⌫ reaching here would move the file being renamed to the
		// trash, and that is not a mistake worth leaving one responder-chain
		// accident away. Return is the same story with a smaller cost: in the
		// field it commits the name, which `control(_:textView:doCommandBy:)`
		// does.
		guard nameField == nil else { return false }

		// ⌥⌘V, the Finder's "Move Item Here". It arrives here rather than through
		// the responder chain because AppKit only dispatches key equivalents it
		// finds in the *main* menu, and the Edit menu's Paste is ⌘V alone —
		// which is the one that does reach `NavigatorOutlineView.paste`.
		//
		// Matched by its character and not by a key code, unlike everything in
		// the switch below: a key code is a position on an ANSI keyboard, and
		// this is the only binding here that is a letter rather than a position.
		// `charactersIgnoringModifiers` drops everything but Shift, so ⌥ does not
		// turn the "v" into a "√".
		if event.modifierFlags.intersection([.command, .option, .control, .shift])
			== [.command, .option],
			event.charactersIgnoringModifiers?.lowercased() == "v"
		{
			pasteIntoSelection(.move)
			return true
		}

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
		case 49: // Space
			// **Quick Look for what Quick Look is for.** An image, a video, a
			// PDF: the provisional open this used to do put a notice in the
			// editor with a Quick Look button on it, which is two presses to
			// reach the thing Space reaches everywhere else on this machine.
			//
			// Everything else keeps the provisional open, which is what Space
			// is for in a tree of source files — and `offersQuickLook` is the
			// same list the notice uses, so the two cannot disagree about what
			// the system will actually render.
			if !quickLookSelection().isEmpty {
				outlineView.showQuickLook()
			} else {
				openSelection(focusEditor: false)
			}
			return true
		default:
			return false
		}
	}

	/// What the preview panel is showing, and whether the tree is driving it.
	var quickLookReportForTesting: String { outlineView.quickLookReportForTesting }

	/// The selected files Quick Look would show something for, in tree order.
	///
	/// Empty when there is nothing worth previewing, which is what decides
	/// whether Space previews or opens. A directory is never previewable here:
	/// Quick Look draws one as a large folder icon, and Space on a folder in
	/// this tree has always folded it.
	func quickLookSelection() -> [URL] {
		outlineView.selectedRowIndexes.sorted().compactMap { row in
			guard let node = outlineView.item(atRow: row) as? FileNode, !node.isDirectory
			else { return nil }
			guard FileNotice.offersQuickLook(forExtension: node.url.pathExtension) else {
				return nil
			}
			return node.url
		}
	}

	/// Opens the panel from the menu, on the row that was clicked.
	@objc func contextQuickLook() {
		guard let node = contextNode else { return }
		// The clicked row, and the selection only when the click was inside it:
		// right-clicking one file with three selected previews that one, as it
		// does in the Finder.
		let selected = quickLookSelection()
		if !selected.contains(node.url) {
			outlineView.selectRowIndexes(
				IndexSet(integer: outlineView.row(forItem: node)), byExtendingSelection: false
			)
		}
		outlineView.showQuickLook()
	}

	private func openSelection(focusEditor: Bool) {
		// One row, for the same reason a selection change opens only one: four
		// tabs from one keystroke, and the last one to arrive is whichever the
		// tree happened to order last.
		guard outlineView.numberOfSelectedRows == 1 else { return }
		let row = outlineView.selectedRow
		guard row >= 0 else { return }
		if let dependency = outlineView.item(atRow: row) as? DependencyNode {
			toggle(dependency)
			return
		}
		if let archiveNode = outlineView.item(atRow: row) as? ArchiveNode {
			// Return opens an entry and pins it, as it does a file; on a
			// directory inside the archive it opens the row.
			if archiveNode.isExpandable { toggle(archiveNode) } else { openArchiveEntry(archiveNode, pinned: focusEditor) }
			return
		}
		guard let node = outlineView.item(atRow: row) as? FileNode else { return }

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
			let item = outlineView.item(atRow: row)
			// The other two roots fold away with everything else, their own rows
			// included: "collapse all" means all.
			if let dependency = item as? DependencyNode {
				outlineView.collapseItem(dependency)
				continue
			}
			if let session = item as? SessionNode {
				outlineView.collapseItem(session)
				continue
			}
			guard let node = item as? FileNode, node !== rootNode else { continue }
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

	/// Folds chains of single-directory folders into one row, or unfolds them.
	///
	/// The rebuild is deliberately not done here. Setting the preference posts
	/// `.abydosSettingsChanged`, and every window's `applySettings` puts its own
	/// tree back — the same route Show Hidden Files takes, and the reason a
	/// second window does not sit there in the old shape.
	func toggleCompactPackages() {
		Settings.shared.compactsPackages.toggle()
	}

	/// Finds the file the editor is showing.
	///
	/// The tree already follows along when tabs change; this is for after
	/// somebody has browsed away from it and wants to know where they were.
	func selectFileInEditor() {
		guard let url = currentEditorFile?() else { return }
		selectWithoutOpening(url: url)
		// **Asked, and unanswerable — so it says so.** This gesture used to do
		// nothing at all for a file the tree has no row for: the selection
		// stayed where it was, and the only way to tell a reveal that landed
		// somewhere from one that could not was to look at the pane and notice
		// nothing had moved. That is the failure item 539 was actually reported
		// as. Only on this gesture, and never on a tab switch, which calls the
		// same reveal a hundred times an hour and must stay silent.
		if let reason = placementProblem(for: url) {
			Toast.post(
				"\(url.lastPathComponent) is not in the tree",
				detail: reason + "\n" + url.path,
				kind: .information
			)
		}
		view.window?.makeFirstResponder(outlineView)
	}

	/// Why a file has no row, or nil when it has one.
	///
	/// The sentence names what is true of *this* file rather than a fixed
	/// apology — the same rule the section's own notes follow. A file inside no
	/// project and no package is a different situation from one whose project
	/// is a different window's.
	func placementProblem(for url: URL) -> String? {
		if dependencies?.locate(url) != nil { return nil }
		if sessions?.session(containing: url) != nil { return nil }
		if rootNode?.node(for: url) != nil { return nil }
		if archiveEntry(forCacheFile: url) != nil { return nil }
		if isArchiveCacheFile(url) { return Self.archiveNoLongerShownSaid }
		guard let project else { return "no project is open in this window." }
		let path = FilePath.canonical(url)
		guard !path.hasPrefix(FilePath.canonical(project.root) + "/") else {
			// Inside the project and still unfound: a filter is hiding it, or
			// the folder above it has not been listed. Worth telling apart from
			// the case below, because the answer is different — one is a
			// setting, the other is nothing anybody can do.
			return "it is inside the project but hidden by a filter."
		}
		return "it is outside the project, no package or toolchain in Dependencies "
			+ "holds it, and no session left it behind."
	}

	/// Expands the root's immediate children, matching how IDEA shows a freshly
	/// opened project rather than a single collapsed row.
	func expandTopLevel() {
		guard let rootNode else { return }
		outlineView.expandItem(rootNode)
		for child in rows(under: rootNode) where child.isDirectory && !child.isExcluded {
			outlineView.expandItem(child)
		}
	}

	/// Selects a file without opening it.
	///
	/// Used when the editor switches tabs: the tree should follow along, but
	/// must not call back and reopen the file it was just told about.
	func selectWithoutOpening(url: URL) {
		selectWithoutOpening(urls: [url])
	}

	/// The same for several files, which is what a drop or a paste lands.
	func selectWithoutOpening(urls: [URL]) {
		let wasSilent = isSelectingSilently
		isSelectingSilently = true
		reveal(urls: urls)
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
		if nameField == nil { view.window?.makeFirstResponder(outlineView) }
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
		// The one letter the tree binds, and the reason `handleKeyDown` matches
		// ⌥⌘V on its character: the code is where "v" sits on an ANSI keyboard.
		case 9: characters = "v"
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
		let target: NSResponder = nameField?.currentEditor() ?? outlineView
		target.keyDown(with: event)
	}

	/// The name in the field standing on a row, or nil when nothing is being
	/// renamed — the difference between Return opening a file and Return doing
	/// what it used to do.
	var renamingNameForTesting: String? { nameField?.stringValue }

	/// Rebuilds the tree the way a filesystem event does, so a selection can be
	/// checked to have survived one.
	func reloadForTesting() {
		reloadTree()
	}

	/// What ⌘C would put on the pasteboard — the same closure the Edit menu
	/// reaches, asked directly, so what several selected rows copy can be read
	/// without a key window to send an action through.
	///
	/// The text form of it, which `FilePasteboardTests` proves is what AppKit
	/// joins the per-item strings into: the harness's output is unchanged by ⌘C
	/// having become a file copy as well.
	func copyTextForTesting() -> String {
		let files = outlineView.copyFiles?() ?? []
		guard !files.isEmpty else { return "nothing" }
		return files.map(\.path).joined(separator: "\n")
	}

	/// ⌘C for real, onto the general pasteboard, so a ⌘V after it has something
	/// to read.
	func copyToPasteboardForTesting() {
		FilePasteboard.write(selectedNodes().map(\.url))
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
			let item = outlineView.item(atRow: row)
			// A dependency row is named too, since 508: the selection landing on
			// a package or on the section is a thing a script has to be able to
			// tell from the selection landing on nothing at all.
			if let node = item as? FileNode { return "\(node.name)@\(row)" }
			if let node = item as? DependencyNode { return "\(node.title)@\(row)" }
			if let node = item as? SessionNode { return "\(node.title)@\(row)" }
			// And an archive row, for the same reason: a highlight that stayed
			// on an entry read as `nothing@2`, which is what a highlight that
			// went out reads as.
			if let node = item as? ArchiveNode { return "\(node.name)@\(row)" }
			return "nothing@\(row)"
		}
		return (names.joined(separator: "+"), outlineView.numberOfRows)
	}

	/// Every row the tree is showing, with its depth.
	///
	/// The Dependencies section cannot be checked any other way: it is not on
	/// disk, so `ls:` says nothing about it, and a screenshot proves it is drawn
	/// without saying what it says. Each row is `depth·name — subtitle`, which
	/// is exactly what somebody reads off the pane.
	/// A real click on a row, through the window server, and who then has the
	/// keyboard — the half of the tree-behaviour claim `pressKeyForTesting`
	/// cannot ask, since it puts the keyboard in the tree itself first.
	func clickRowForTesting(_ row: Int) -> String {
		TreeKeys.click(row: row, in: outlineView)
			+ " keyboard=\(TreeKeys.keyboardHolder(in: view.window))"
			+ " selected=\(selectedPathsForTesting().joined(separator: "+"))"
	}

	/// The selection by the project-relative paths it is remembered by.
	///
	/// The `archive:` keys are dropped and the archive line appended instead,
	/// so an entry reads as `bundle.zip!/a.txt` here rather than twice in two
	/// spellings — the report's own shape, unchanged by the capture having
	/// learnt about archive rows.
	func selectedPathsForTesting() -> [String] {
		let files = selectedPaths().filter { !$0.hasPrefix("archive:") }.map { path -> String in
			guard let root = project?.root.path, path.hasPrefix(root) else { return path }
			return String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		}
		return files + (selectedArchivePathForTesting().map { [$0] } ?? [])
	}

	func rowsForTesting() -> [String] {
		(0..<outlineView.numberOfRows).map { row in
			let item = outlineView.item(atRow: row)
			let indent = String(repeating: "  ", count: outlineView.level(forRow: row))
			// Which row is selected, because "the selection survived a rebuild"
			// is the claim and a list of names cannot make it.
			let mark = outlineView.selectedRowIndexes.contains(row) ? "  <-" : ""
			if let node = item as? DependencyNode {
				return indent + node.title + (node.subtitle.map { " — " + $0 } ?? "") + mark
			}
			if let node = item as? SessionNode {
				return indent + node.title + (node.subtitle.map { " — " + $0 } ?? "") + mark
			}
			// A row inside a shown archive, which this said `?` about — so the
			// one report that can show *which* row keeps the highlight could
			// not name the rows the highlight is about.
			if let node = item as? ArchiveNode {
				return indent + node.name + (node.subtitle.map { "  " + $0 } ?? "") + mark
			}
			guard let node = item as? FileNode else { return indent + "?" }
			// **And the colour it is drawn in.** A report that says which rows
			// exist cannot catch a row that exists in the wrong colour, which is
			// the whole of what a git tint is — `.gitignore` rules going
			// unnoticed looks exactly like a tree that is working.
			let tint: String
			switch node.gitStatus {
			case .unmodified:  tint = ""
			case .ignored:     tint = "  ignored"
			case .unversioned: tint = "  untracked"
			case .added:       tint = "  added"
			case .modified:    tint = "  modified"
			case .deleted:     tint = "  deleted"
			case .conflicted:  tint = "  conflicted"
			}
			return indent + title(for: node) + tint + mark
		}
	}

	/// The section as the model has it, whether or not anything is expanded —
	/// the half `rowsForTesting` cannot answer, since a folded row has no rows
	/// under it to print.
	func dependencyReportForTesting() -> [String] {
		dependencies?.report() ?? ["no dependencies section"]
	}

	/// Opens the Dependencies section and scrolls to it.
	///
	/// The section sits below the whole project tree, which on a repository of
	/// eight subprojects is several screens down — so a script that wants to
	/// photograph it has to be able to ask for it rather than arrow there.
	func openDependenciesForTesting(groups: Bool) {
		guard let dependencies else { return }
		outlineView.expandItem(dependencies.root)
		if groups {
			for child in dependencies.root.childNodes { outlineView.expandItem(child) }
		}
		let row = outlineView.row(forItem: dependencies.root)
		guard row >= 0 else { return }
		// The last row first, so the section ends up at the top of the pane
		// rather than at its bottom edge: `scrollRowToVisible` does the least it
		// can, and a row already on screen moves nothing.
		outlineView.scrollRowToVisible(outlineView.numberOfRows - 1)
		outlineView.scrollRowToVisible(row)
		outlineView.selectRowIndexes([row], byExtendingSelection: false)
	}

	/// What a **real right-click** offers over each row of the sessions root.
	///
	/// Through `NSView.menu(for:)` with a synthetic right-click at the row's own
	/// rectangle, which is the gesture rather than the delegate: the previous
	/// check called `menuNeedsUpdate` directly with a row *selected*, and a
	/// selected row and a clicked row are not the same thing.
	func sessionRightClicksForTesting() -> String {
		guard let sessions else { return "no sessions" }
		outlineView.expandItem(sessions)

		var said: [String] = []
		for row in 0..<outlineView.numberOfRows {
			guard let node = outlineView.item(atRow: row) as? SessionNode else { continue }
			let rect = outlineView.rect(ofRow: row)
			let inView = NSPoint(x: rect.midX, y: rect.midY)
			guard let event = NSEvent.mouseEvent(
				with: .rightMouseDown,
				location: outlineView.convert(inView, to: nil),
				modifierFlags: [], timestamp: 0,
				windowNumber: outlineView.window?.windowNumber ?? 0,
				context: nil, eventNumber: 0, clickCount: 1, pressure: 1
			) else { continue }

			let menu = outlineView.menu(for: event)
			// **`update()` is not the delegate.** `NSMenu.update()` on a menu
			// that is not on screen validates items and does not necessarily ask
			// a delegate to rebuild — so the state read here is whatever was set
			// last. The delegate is called directly beside it, which is what
			// AppKit does before showing the menu.
			menu?.update()
			let beforeDelegate = (menu?.items ?? []).filter { !$0.isHidden }.map(\.title)
			if let menu { menuNeedsUpdate(menu) }
			let offered = (menu?.items ?? []).filter { !$0.isHidden }.map(\.title)
			_ = beforeDelegate
			let kind: String
			switch node.row {
			case .section: kind = "root"
			case .session: kind = "session"
			}
			said.append("\(kind)@\(row) clicked=\(outlineView.clickedRow) "
				+ "session=\(contextSession?.id.prefix(8) ?? "nil") "
				+ "offers=[\(offered.joined(separator: ", "))]")
		}
		return said.joined(separator: "\n    ")
	}

	/// What the context menu offers over a session's row, and what its one item
	/// copies — for `session-menu`.
	func sessionMenuForTesting() -> String {
		guard let sessions, let first = sessions.childNodes.first else { return "no sessions" }
		outlineView.expandItem(sessions)
		let row = outlineView.row(forItem: first)
		guard row >= 0 else { return "no row for the first session" }
		outlineView.selectRowIndexes([row], byExtendingSelection: false)

		// **The same reader the `menu` step uses**, and that is the point: the
		// first version of this called `menu.update()` and read the items itself,
		// which reported all seventeen file items as offered while the menu on
		// screen showed one. `contextMenuTitlesForTesting` calls the delegate
		// directly, so what it prints is what a right-click gets.
		let offered = contextMenuTitlesForTesting()
		contextCopyResumeCommand()
		return "offers=[\(offered.joined(separator: ", "))] "
			+ "copied=\(NSPasteboard.general.string(forType: .string) ?? "nothing")"
	}

	/// Opens the Claude Sessions root and brings it into view, which on a
	/// repository of this size is several screens down.
	func openSessionsForTesting(files: Bool) {
		guard let sessions else { return }
		outlineView.expandItem(sessions)
		if files {
			for child in sessions.childNodes { outlineView.expandItem(child) }
		}
		let row = outlineView.row(forItem: sessions)
		guard row >= 0 else { return }
		// The last row first, so the root ends up at the top of the pane rather
		// than at its bottom edge — the same reason `deps-open` does it.
		outlineView.scrollRowToVisible(outlineView.numberOfRows - 1)
		outlineView.scrollRowToVisible(row)
		outlineView.selectRowIndexes([row], byExtendingSelection: false)
	}

	/// What roots the tree has and what is under the third of them, for
	/// `--tree-roots`.
	func rootsForTesting() -> String {
		var said = ["project=\(rootNode?.name ?? "none")"]
		said.append("dependencies=\(dependencies == nil ? "absent" : "present")")
		guard let sessions else {
			said.append("sessions=absent")
			return said.joined(separator: " ")
		}
		said.append("sessions=\(sessions.childNodes.count)")
		for node in sessions.childNodes.prefix(4) {
			said.append("\n    \(node.title) [\(node.subtitle ?? "")]")
		}
		return said.joined(separator: " ")
	}

	/// Opens the section down to a file and selects it, the way activating a tab
	/// on a file outside the project does.
	/// Rebuilds the Claude Sessions root from the sessions it already holds, so
	/// what a rebuild costs can be asked for on purpose.
	///
	/// **New node objects, which is the whole point.** `refreshSessions` returns
	/// early unless a session's size or liveness has moved, and what breaks when
	/// it does *not* return early is that `reloadData` throws away every row's
	/// identity. This is that moment, without having to make an agent write a
	/// file to get it.
	func rebuildSessionsForTesting() {
		guard let sessions else {
			print("TREE sessions-rebuild: no sessions")
			return
		}
		show(SessionNode.build(sessions.sessions))
	}

	func revealForTesting(_ path: String) {
		let url = URL(fileURLWithPath: path)
		selectWithoutOpening(url: url)
		let package = dependency(containing: url)
		// Which root claimed it, because three can and only one did.
		let claimed = dependencies?.locate(url) != nil
			? "dependencies"
			: (sessions?.session(containing: url) != nil ? "sessions" : "tree")
		print("TREE reveal: \(url.lastPathComponent) "
			+ "claimed-by=\(claimed) "
			+ "package=\(package?.name ?? "none") "
			+ "origin=\(package?.origin ?? "none") "
			+ "selection=\(selectionForTesting.name) "
			+ "unplaceable=\(placementProblem(for: url) ?? "no")")
	}

	/// Selects and scrolls to a file, expanding ancestors as needed.
	func reveal(url: URL) {
		reveal(urls: [url])
	}

	/// The same for several files at once.
	///
	/// Every ancestor is expanded first and the selection set once at the end,
	/// rather than a row at a time: expanding renumbers the rows under it, so
	/// indices collected as they went would name the wrong files by the time the
	/// last folder opened. The topmost is what gets scrolled to.
	func reveal(urls: [URL]) {
		guard !urls.isEmpty else { return }

		// Held back while the dependency walk is out, and done again when it
		// lands. Without this a reveal during those milliseconds answers from
		// `.build` rather than from the Dependencies section — see
		// `deferredReveals` for why that is the wrong row.
		if isReadingDependencies {
			deferredReveals.append(contentsOf: urls)
			return
		}

		// Before anything is looked up: a file from a toolchain has no row yet,
		// and this is the moment its path is in hand. Gives the section a row
		// for the toolchain if one of these came out of it, so the lookup below
		// finds it like any other.
		noteToolchains(for: urls)

		var found: [FileNode] = []
		var foundEntries: [ArchiveNode] = []
		for url in urls {
			// **The Dependencies section wins.** A file under
			// `.build/checkouts/Cadova` is reachable both ways — the section, and
			// the `.build` folder in the ordinary tree — and only one of the two
			// can say which package it is and where that package came from. That
			// is the whole of what item 508 was filed for, so a reveal that
			// landed in `.build` would answer the question with the one row that
			// does not.
			if let located = dependencies?.locate(url) {
				for node in located.chain { outlineView.expandItem(node) }
				let target = row(for: located.node)
				if let package = located.chain.last, let fileRoot = package.fileRoot {
					expandAncestors(of: target, under: fileRoot)
				}
				found.append(target)
				continue
			}
			// **Then Claude Sessions**, which is the third and last claimant.
			// The order never has to be argued about, because nothing lives in
			// two of them: a package's sources are not under `/tmp/claude-*`,
			// and a session's scratch directory is not inside the project.
			if let sessions, let session = sessions.session(containing: url),
			   let fileRoot = session.fileRoot, let node = fileRoot.node(for: url) {
				outlineView.expandItem(sessions)
				outlineView.expandItem(session)
				let target = row(for: node)
				expandAncestors(of: target, under: fileRoot)
				found.append(target)
				continue
			}
			// **And archives, a fourth claimant.** See `expandForArchiveEntry`,
			// which is where what this one takes is written down.
			if let entry = archiveEntry(forCacheFile: url) {
				expandForArchiveEntry(entry)
				foundEntries.append(entry)
				continue
			}
			guard let rootNode, let node = rootNode.node(for: url) else { continue }
			let target = row(for: node)
			expandAncestors(of: target, under: rootNode)
			found.append(target)
		}
		guard !found.isEmpty || !foundEntries.isEmpty else { return }

		let rows = (found.map { outlineView.row(forItem: $0) }
			+ foundEntries.map { outlineView.row(forItem: $0) })
			.filter { $0 >= 0 }.sorted()
		guard let first = rows.first else { return }
		outlineView.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
		outlineView.scrollRowToVisible(first)
	}

	/// Opens every folder between a node and the root it was found under.
	///
	/// Outermost first, and the rows are asked for only once everything is open
	/// — expanding renumbers the rows beneath it, so an index collected on the
	/// way would name the wrong file by the time the last folder opened.
	func expandAncestors(of node: FileNode, under root: FileNode) {
		var ancestors: [FileNode] = []
		var current: FileNode? = node
		while let parent = current?.parentNode(in: root) {
			ancestors.append(parent)
			current = parent
		}
		// A directory folded into the row below it has no row of its own, and
		// `expandItem` on something the outline has never been handed does
		// nothing — silently, which is the failure that would be hard to see.
		// The row that stands for it is further down and is opened in its turn.
		for ancestor in ancestors.reversed() where !(compactsPackages && ancestor.isCompactedAway) {
			outlineView.expandItem(ancestor)
		}
	}

	/// The row a node is drawn on: itself, unless compaction has folded it into
	/// the row below it.
	///
	/// A file is always its own row, so this only ever moves a *directory* — the
	/// reveal of a folder inside a chain, which would otherwise select nothing.
	func row(for node: FileNode) -> FileNode {
		compactsPackages ? node.compactedRow : node
	}

	/// Which package a file belongs to, for anything outside the tree that wants
	/// to say where it came from.
	func dependency(containing url: URL) -> ExternalDependency? {
		dependencies?.package(containing: url)
	}
}
