import AppKit
import AbydosKit

extension FileNode {
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
/// Return commits, Escape abandons, and clicking elsewhere commits — which is
/// what every other in-place rename on this machine does, and what somebody who
/// has typed a name and looked away expects to have happened. Abandoning is the
/// one thing the two gestures differ on: a rename keeps the old name, and a new
/// row goes away entirely, having never been written.
extension ProjectNavigatorViewController: NSTextFieldDelegate {
	func control(
		_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
	) -> Bool {
		switch selector {
		case #selector(NSResponder.insertNewline(_:)):
			commitName()
			return true
		case #selector(NSResponder.cancelOperation(_:)):
			endEditing()
			return true
		default:
			return false
		}
	}

	func controlTextDidEndEditing(_ notification: Notification) {
		// Only when the field is going of its own accord — committing already
		// takes it away, and this would otherwise commit a name it just refused.
		//
		// A new row commits here too, the way the Finder's does: clicking away
		// from a folder called `untitled folder` leaves you with a folder called
		// `untitled folder`, not with nothing. Escape is the way to mean nothing.
		guard nameField != nil, notification.object as? NSTextField === nameField else { return }
		commitName()
	}
}

extension ProjectNavigatorViewController: NSOutlineViewDataSource, NSOutlineViewDelegate,
	NSMenuDelegate, NSMenuItemValidation {
	/// Whether a chain of directories each holding one directory is drawn as one
	/// row. Off by default; the header's third button turns it on.
	var compactsPackages: Bool { Settings.shared.compactsPackages }

	/// The rows under a directory — its children, or the folded ones.
	///
	/// Every walk in this file goes through here rather than through `children`
	/// directly, which is what stops the outline and the four hand-written walks
	/// disagreeing about which rows exist.
	func rows(under node: FileNode) -> [FileNode] {
		let rows = compactsPackages ? node.compactedChildren : node.children
		// A row sent to the trash is not drawn while the trash is working. Here
		// rather than at each of the walks, which is the whole reason this
		// function exists — and free when nothing is doomed, which is almost
		// always.
		guard !doomedRows.isEmpty else { return rows }
		return rows.filter { !doomedRows.hides($0.url) }
	}

	/// What a row is called: its own name, or the whole chain folded into it.
	func title(for node: FileNode) -> String {
		compactsPackages ? node.compactedName : node.name
	}

	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		// Two roots when there is a Dependencies section: the project's own
		// directory, and everything that is not it. IntelliJ's *External
		// Libraries* sits in the same place, below the tree rather than inside
		// it, because a dependency is not in the project — that is what it means.
		guard let item else {
			guard rootNode != nil else { return 0 }
			// Up to three, and each is there only when it holds something.
			return 1 + (dependencies == nil ? 0 : 1) + (sessions == nil ? 0 : 1)
		}
		if let count = archiveChildCount(of: item) { return count }
		if let node = item as? SessionNode {
			// A session row *is* a directory, the same as a package row: from
			// here down the rows are ordinary files.
			if let fileRoot = node.fileRoot { return rows(under: fileRoot).count }
			return node.childNodes.count
		}
		if let node = item as? DependencyNode {
			// A package row *is* a directory: from here down the rows are
			// ordinary files and everything the tree does works on them.
			if let fileRoot = node.fileRoot { return rows(under: fileRoot).count }
			return node.childNodes.count
		}
		guard let node = item as? FileNode, node.isDirectory else { return 0 }

		// Children are read the first time the outline view asks for them,
		// which may be long after the last status refresh — and rows that
		// appeared since would be drawn as though everything about them were
		// unremarkable. Asking again is cheap; the refresh coalesces.
		let wasLoaded = node.hasLoadedChildren
		let count = rows(under: node).count
		if !wasLoaded { scheduleGitStatusRefresh() }
		// And the one row that is not a file. It is last, so it changes nothing
		// about the rows above it and cannot move while a name is being typed
		// into it — see `beginNew`.
		return count + (placeholder?.parent === node ? 1 : 0)
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
		guard let item else {
			// The project, then Dependencies, then Claude Sessions — the order
			// the reveal claims a file in, so the tree reads the same way it
			// resolves.
			guard index > 0 else { return rootNode! }
			if let dependencies { return index == 1 ? dependencies.root : sessions! }
			return sessions!
		}
		if let child = archiveChild(of: item, at: index) { return child }
		if let node = item as? SessionNode {
			if let fileRoot = node.fileRoot { return rows(under: fileRoot)[index] }
			return node.childNodes[index]
		}
		if let node = item as? DependencyNode {
			if let fileRoot = node.fileRoot { return rows(under: fileRoot)[index] }
			return node.childNodes[index]
		}
		let node = item as! FileNode
		let children = rows(under: node)
		if index == children.count, let placeholder, placeholder.parent === node {
			return placeholder.node
		}
		return children[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		if let expandable = archiveIsExpandable(item) { return expandable }
		if let node = item as? SessionNode { return node.isExpandable }
		if let node = item as? DependencyNode { return node.isExpandable }
		guard let node = item as? FileNode else { return false }
		// A new folder has nothing in it and does not exist yet, so it gets no
		// disclosure triangle: opening it would list a directory that is not
		// there.
		guard node !== placeholder?.node else { return false }
		// Reporting expandable without reading the directory keeps opening a
		// project O(1) in the number of subdirectories.
		return node.isDirectory
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		if let cell = archiveCell(for: item) { return cell }
		if let node = item as? SessionNode {
			let cell = NavigatorCellView()
			cell.configure(session: node)
			// The transcript's path lives here and nowhere else: worth having
			// for pointing another tool at it, not worth opening as a file.
			cell.toolTip = node.detail
			return cell
		}
		if let node = item as? DependencyNode {
			let cell = NavigatorCellView()
			cell.configure(dependency: node)
			// The whole origin, which the row itself has to cut down to fit. A
			// package's tooltip is the URL, the version and where the sources
			// are — the three things somebody following a symbol out of their
			// own code wants and cannot otherwise find out.
			cell.toolTip = node.detail
			return cell
		}
		guard let node = item as? FileNode else { return nil }
		let isRoot = (node === rootNode)
		let cell = NavigatorCellView()
		// The whole path, which a folded row is the reason for: `com.example.myapp`
		// says which package and not where it is, and the row is too narrow for
		// both. Every file row has it, so a folded one is not a special case.
		cell.toolTip = node.url.path
		cell.configure(
			node: node,
			title: title(for: node),
			isRoot: isRoot,
			subtitle: isRoot ? project?.displayPath : nil,
			isExpanded: outlineView.isItemExpanded(node),
			isSubproject: node.url.path == subprojectRoot?.path,
			isRenaming: editing?.node === node
		)
		return cell
	}

	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		let node = item as? FileNode
		let row = TreeRowView()
		// The one thing this tree draws that the others do not: excluded output
		// directories get a warm wash, as in the reference.
		row.tint = (node?.isExcluded ?? false)
			? Theme.current.excludedDirectoryTint.withAlphaComponent(0.35)
			: nil
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
		if row >= 0, let archiveNode = outlineView.item(atRow: row) as? ArchiveNode {
			// An entry shows provisionally, as a file does.
			openArchiveEntry(archiveNode, pinned: false)
			return
		}
		guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode, !node.isDirectory else { return }
		// The row for a file that does not exist yet opens nothing: it is a name
		// being typed, not a file to show.
		guard node !== placeholder?.node else { return }
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

	/// Whether the drop under the pointer would do anything, and which of the
	/// two things it would do.
	///
	/// The row it highlights is retargeted to the folder the files will really
	/// land in — a file's parent, or the folder a line between two rows sits
	/// inside — so what is about to happen is visible before the mouse comes up
	/// rather than explained after.
	///
	/// The whole plan is worked out here and thrown away, which is what makes a
	/// drag onto a folder that could only refuse show the "no" cursor instead of
	/// accepting and then posting a toast. It is a few string comparisons and a
	/// `fileExists` per dragged file, per mouse move over a row.
	func outlineView(
		_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
		proposedItem item: Any?, proposedChildIndex index: Int
	) -> NSDragOperation {
		guard let folder = destinationFolder(for: item as? FileNode) else { return [] }
		let target = rootNode?.node(for: folder)
		outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)

		let sources = FilePasteboard.files(on: info.draggingPasteboard)
		guard !sources.isEmpty else { return [] }

		let operation = operation(for: info)
		let wanted: NSDragOperation = operation == .move ? .move : .copy
		// Some applications offer only `.generic`; a file URL is a file URL
		// either way, so that counts as permission to copy.
		guard info.draggingSourceOperationMask.contains(wanted)
			|| info.draggingSourceOperationMask.contains(.generic)
		else { return [] }

		let plan = FileTransfer.plan(
			sources, into: folder, operation: operation, projectRoot: project?.root,
			exists: { FileManager.default.fileExists(atPath: $0.path) }
		)
		return plan.hasWork ? wanted : []
	}

	/// The mouse came up. Everything that decides anything is in `transfer`, so
	/// a drop and a ⌘V are the same act arriving by two routes.
	func outlineView(
		_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
		item: Any?, childIndex index: Int
	) -> Bool {
		guard let folder = destinationFolder(for: item as? FileNode) else { return false }
		let sources = FilePasteboard.files(on: info.draggingPasteboard)
		guard !sources.isEmpty else { return false }
		let arrived = transfer(sources, into: folder, operation: operation(for: info))
		// The one gesture in the family that does not already leave the keyboard
		// in the tree. Every other route — the menu, ⌘⌫, ⌥⌘V — starts from a click
		// or a keystroke in the tree and ends with it still focused, but a drag
		// from the Finder can land here while the caret is in the editor, and then
		// ⌘Z would mean the editor's undo rather than this drop's. Undo lives
		// where the gesture happened, so the gesture takes the keyboard.
		if arrived, nameField == nil { view.window?.makeFirstResponder(outlineView) }
		return arrived
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
		// **A session row is not a file, so nothing else in this menu belongs
		// over it.** Driven, and the first version offered every file item on a
		// session's row — New, Rename, Open Externally, and *Move to Trash*,
		// which reads as an offer to delete somebody's session. They do nothing,
		// because each guards on a file being clicked, but a menu of seventeen
		// items that do nothing is not a menu. One item, which is the only one
		// that means anything there.
		// Reported again after the first attempt: right-clicking **the root** —
		// which is the row anybody would try — still offered the whole file
		// menu, because only a *session* row was being told apart. The root is
		// not a file either.
		// **And not over a session that is already running.** `claude --resume`
		// on a live session is not a thing anybody wants pasted into a terminal:
		// the conversation it names is open in a window somewhere, and what the
		// command does with one is not this app's to promise.
		resumeItem?.isHidden = contextSession.map(\.isLive) ?? true
		revealSessionItem?.isHidden = contextSessionDirectory == nil
		if contextSessionRow != nil {
			for item in menu.items where item !== resumeItem && item !== revealSessionItem {
				item.isHidden = true
			}
			return
		}
		for item in menu.items where item !== resumeItem && item !== revealSessionItem {
			// Put back whatever a session row hid on the way past.
			item.isHidden = false
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
			if item === compareSelectedItem {
				// Two rows, both files or both folders: anything else has no
				// two sides to put beside each other.
				let nodes = contextNodes
				let two = nodes.count == 2 && nodes[0].isDirectory == nodes[1].isDirectory
					&& !nodes.contains { $0 === rootNode }
				item.isHidden = !two
				item.isEnabled = two
				continue
			}
			if item.submenu === compareMenu {
				// A file's question and only a file's: folders and the root
				// have no one file's working copy to compare. An untracked or
				// ignored file offers Against Last Commit disabled — there is
				// no last commit of it — and no History…, git holding none.
				// With… is any row's: a folder is compared with a folder.
				let file = node.map { !$0.isDirectory } ?? false
				item.isHidden = node == nil || isRoot
				item.isEnabled = node != nil
				compareAgainstItem?.isHidden = !file
				compareHistoryItem?.isHidden = !file
				compareWithItem?.isHidden = false
				if let node, file {
					let outside = node.gitStatus == .unversioned || node.gitStatus == .ignored
					compareAgainstItem?.isEnabled = !outside
					compareHistoryItem?.isHidden = outside
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
			case #selector(contextOpenExternally), #selector(contextOpenAsHex):
				item.isHidden = node?.isDirectory ?? true
			case #selector(contextBlame):
				// A file's question, and only in a repository.
				item.isHidden = (node?.isDirectory ?? true) || project?.git == nil
			case #selector(contextQuickLook):
				// Only where the system would actually render something. A
				// menu item that opens a panel showing a large grey icon is an
				// offer to do nothing, which is the argument `offersQuickLook`
				// was written for.
				item.isHidden = !(node.map {
					!$0.isDirectory && FileNotice.offersQuickLook(forExtension: $0.url.pathExtension)
				} ?? false)
			case #selector(contextPreviewModel):
				// `holdsAModel` rather than `canPreview`, for the same reason Export
				// above uses `holdsADiagram`: a go3mf recipe is a `.yaml`, and the
				// name of a `.yaml` says nothing at all. This reads the head of the
				// one file that was right-clicked, and only when it is named like a
				// recipe could be — the row, never the tree. See 0482.
				item.isHidden = !(node.map { !$0.isDirectory && ModelPreview.holdsAModel($0.url) } ?? false)
					|| !ModelPreview.isAvailable
			case #selector(contextDiscard):
				// Only where git has something to put back or remove, asked of
				// the same status the colours come from — a folder counts the
				// files under it, a file whose only change is staged is refused
				// as the changes pane refuses it — and never over a conflict.
				// Absent rather than greyed, the way Blame is absent off a
				// repository: an offer to do nothing is not an offer.
				let target = discardTarget
				item.isHidden = target == nil
				item.isEnabled = target != nil
				item.title = target?.menuTitle ?? "Discard Changes\u{2026}"
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
			case #selector(contextPaste):
				// About the board and the folder, not about how many rows are
				// highlighted: pasting four files into a folder is one act, and
				// right-clicking empty space still has somewhere to put them.
				// Files, or a picture: a screenshot pastes as a PNG.
				item.isEnabled = rootNode != nil
					&& (!FilePasteboard.files().isEmpty || FilePasteboard.hasPicture())
			case #selector(contextPasteAsMove):
				// Files only. Pixels have nowhere to be moved from, and a move that
				// copied would be a lie in the menu.
				item.isEnabled = rootNode != nil && !FilePasteboard.files().isEmpty
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
		// Last, after the loop above has put every item back: the archive rows'
		// own items, and *Show Contents* on an archive file. Inside an archive
		// the menu is those items and nothing else.
		_ = updateArchiveMenu(menu, fileNode: node)
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
		(item as? FileNode).map { title(for: $0) }
	}

	func outlineViewItemDidExpand(_ notification: Notification) {
		// Newly-loaded children have no VCS state yet.
		refreshGitStatus()
	}
}
