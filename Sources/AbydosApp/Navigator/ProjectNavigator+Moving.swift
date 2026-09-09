import AppKit
import AbydosKit

/// Moving and copying files, and undoing it.
///
/// Every one of these touches somebody's disk, which is why the undo is here
/// beside them rather than anywhere else: what was moved is what has to move
/// back, and only this code knows it.
extension ProjectNavigatorViewController {
	// MARK: - Moving and copying

	/// Where a drop or a paste aimed at a row actually lands.
	///
	/// A folder is itself. A *file* is the folder holding it, which is what
	/// pointing at a file in a list of files means — and a drop between two rows
	/// is the same answer, because the tree is the file system's order rather
	/// than a list: there is nothing to insert between two names. Nothing at all
	/// under the pointer is the project root.
	func destinationFolder(for node: FileNode?) -> URL? {
		guard let node else { return project?.root }
		return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
	}

	/// Which way round a drag goes.
	///
	/// **A drag that starts in the tree moves, wherever it lands; ⌥ copies. A
	/// drag that arrives from another application always copies.**
	///
	/// The Finder moves within a volume and copies across one, and following
	/// that was the obvious answer — but the Finder's window names the volume
	/// every file is on and this one does not. A folder inside a project can be
	/// a mount point or a symlink onto another disk with nothing in the tree
	/// saying so, and a gesture that silently changes meaning on information the
	/// window never shows is a gesture nobody can predict. Inside one project
	/// the tree is one thing, so the drag means one thing.
	///
	/// Nothing in the implementation wanted the distinction either:
	/// `FileManager.moveItem` already does copy-then-remove when the two ends
	/// are on different volumes. Not proved here against a real pair of volumes.
	///
	/// Arriving from outside is the other way round, and there the Finder's rule
	/// is plainly right: an import that emptied the USB stick it came from would
	/// be a way to lose files, and the tree cannot even show what it took them
	/// from. So an external drop copies, full stop — ⌘ does not turn it into a
	/// move.
	func operation(for info: NSDraggingInfo) -> FileTransfer.Operation {
		let isOurOwn = (info.draggingSource as? NSOutlineView) === outlineView
		guard isOurOwn else { return .copy }
		// The live modifier state rather than `draggingSourceOperationMask`.
		// AppKit is documented to narrow that mask by the modifier keys, but the
		// question here — is ⌥ down *now* — is one `NSEvent` answers without
		// depending on that narrowing being what it is thought to be.
		return NSEvent.modifierFlags.contains(.option) ? .copy : .move
	}

	/// Moves or copies files into a folder, and says once what did not happen.
	///
	/// Returns whether anything arrived, which is what `acceptDrop` answers with.
	@discardableResult
	func transfer(
		_ sources: [URL], into folder: URL, operation: FileTransfer.Operation
	) -> Bool {
		let plan = FileTransfer.plan(
			sources, into: folder, operation: operation, projectRoot: project?.root,
			exists: { FileManager.default.fileExists(atPath: $0.path) }
		)

		// The ones that actually happened rather than the ones that were planned,
		// so nothing on the undo stack claims work the file system refused.
		var done: [FileTransfer.Transfer] = []
		var failures: [String] = []
		for transfer in plan.transfers {
			do {
				switch operation {
				case .move: try FileManager.default.moveItem(at: transfer.source, to: transfer.destination)
				case .copy: try FileManager.default.copyItem(at: transfer.source, to: transfer.destination)
				}
				done.append(transfer)
			} catch {
				failures.append("“\(transfer.source.lastPathComponent)”: \(error.localizedDescription)")
			}
		}
		let arrived = done.map(\.destination)
		// A move goes home again; a copy goes to the trash. Recorded before the
		// message, so a drop that half worked is still half undoable.
		remember(FileUndo.transferred(done, operation: operation) { Self.modificationDate(of: $0) })

		// One message for the whole drop, however many files it was. Skipping
		// rather than prompting is what keeps the gesture a gesture, and three
		// dialogs arriving afterwards instead of during would undo that.
		if let said = plan.summary(operation: operation, done: arrived.count, failures: failures) {
			Toast.post(said.title, detail: said.detail)
		}

		guard !arrived.isEmpty else { return false }
		// Opened, so there is somewhere for the files to appear.
		if let node = rootNode?.node(for: folder), node !== rootNode {
			outlineView.expandItem(node)
		}
		// The watcher rebuilds the tree a moment from now and every row is a
		// different object afterwards, so the selection follows the paths rather
		// than the nodes — the same problem rename has, and the same answer.
		pendingReveal = arrived
		return true
	}

	/// ⌘V, and ⌥⌘V which moves instead — the Finder's two keys.
	///
	/// Whatever is on the pasteboard as files, so it works with a copy made in
	/// the Finder as readily as with one made here.
	private func paste(
		_ operation: FileTransfer.Operation, into folder: URL?, from board: NSPasteboard = .general
	) {
		guard let folder else { return }
		let files = FilePasteboard.files(on: board)
		if !files.isEmpty {
			transfer(files, into: folder, operation: operation)
			return
		}
		// Pixels and no file: a screenshot, or a picture copied out of a browser
		// or Preview. Files first, above, because copying an image file in the
		// Finder can put pixels beside the URL and the file is what was meant.
		// A copy only: pixels have nowhere to be moved from, so ⌥⌘V over them
		// does nothing rather than quietly copying.
		guard operation == .copy, FilePasteboard.hasPicture(on: board) else { return }
		pastePicture(from: board, into: folder)
	}

	/// Writes the board's picture as a PNG into the folder and offers it a name.
	///
	/// Written the moment ⌘V arrives, under the first free `picture-<n>.png`,
	/// and then the row opens for renaming with the stem selected — typing
	/// replaces the name and Escape keeps it. Not the New File order, where
	/// nothing is on disk until Return: that is right there because an empty
	/// file Escape left behind is something. Here the picture is the thing, and
	/// a paste that could still be cancelled after the key went down would be
	/// the only paste in the app that is not done when it is pressed. ⌘Z is the
	/// answer for a change of mind.
	///
	/// Revealed and not opened, on `revealExported`'s reasoning: a picture is
	/// pasted into a project to be referred to from something being written,
	/// and an image tab taking the front of the editor would be the paste
	/// stealing that place — and the name field needs the keyboard the editor
	/// would take. Return on the row opens it, as any picture row's does.
	///
	/// Returns where it went, for the driven run's report.
	@discardableResult
	private func pastePicture(from board: NSPasteboard, into folder: URL) -> URL? {
		guard let png = FilePasteboard.picture(on: board) else {
			// Said rather than nothing: the board declared a picture and ⌘V was
			// heard, so silence would read as a key that does not work.
			Toast.post("Cannot paste that picture", detail: "The clipboard's picture could not be read.")
			return nil
		}
		let destination = FileTransfer.freeName(stem: "picture", extension: "png", in: folder) {
			FileManager.default.fileExists(atPath: $0.path)
		}
		do {
			try png.write(to: destination, options: .withoutOverwriting)
		} catch {
			Toast.post("Cannot paste that picture", detail: error.localizedDescription)
			return nil
		}
		// The same record a new file makes, with the same guard: a ⌘Z arriving
		// after something has written to the file refuses instead.
		remember(FileUndo.pasted(destination) { Self.modificationDate(of: $0) })

		// The folder has just gained an entry, so its listing is stale by one.
		// Re-read here rather than waiting for the watcher, as New File does:
		// the row has to exist before a field can be put on it.
		guard let parent = rootNode?.node(for: folder) else {
			pendingReveal = [destination]
			return destination
		}
		parent.reloadPreservingIdentity()
		let expanded = expandedPaths()
		outlineView.reloadData()
		restore(expandedPaths: expanded)
		// Opened whether it was or not: a picture pasted into a collapsed folder
		// is otherwise made and never seen.
		outlineView.expandItem(parent)
		guard let node = rootNode?.node(for: destination) else {
			pendingReveal = [destination]
			return destination
		}
		let index = outlineView.row(forItem: node)
		guard index >= 0 else {
			pendingReveal = [destination]
			return destination
		}
		outlineView.scrollRowToVisible(index)
		let wasSilent = isSelectingSilently
		isSelectingSilently = true
		outlineView.selectRowIndexes([index], byExtendingSelection: false)
		isSelectingSilently = wasSilent
		beginEditing(.rename(node: node, original: node.name), row: index, name: node.name)
		return destination
	}

	/// The keyboard's paste: into the selected folder, or the folder holding the
	/// selected file, or the project root when nothing is selected.
	///
	/// From the selection rather than from `contextNodes`, which starts at
	/// `clickedRow`: a row clicked ten minutes ago is still the clicked row, and
	/// the keyboard must never put files somewhere the keyboard cannot see.
	func pasteIntoSelection(_ operation: FileTransfer.Operation) {
		paste(operation, into: destinationFolder(for: selectedNodes().first))
	}

	@objc func contextPaste() { paste(.copy, into: contextParentDirectory) }
	@objc func contextPasteAsMove() { paste(.move, into: contextParentDirectory) }

	/// The same two gestures without a pasteboard or a mouse, for verifying them
	/// end to end: the files named, dropped into the folder named.
	func dropForTesting(_ sources: [URL], into folder: URL, move: Bool) {
		let arrived = transfer(sources, into: folder, operation: move ? .move : .copy)
		print("TREE drop: \(move ? "move" : "copy") \(sources.count) → \(folder.lastPathComponent) "
			+ "arrived=\(arrived)")
	}

	/// ⌘C then ⌘V, driven through the real pasteboard so what ⌘C writes is what
	/// ⌘V reads.
	func pasteForTesting(move: Bool) {
		pasteIntoSelection(move ? .move : .copy)
	}

	/// ⌘V over a picture, from a board of the run's own.
	///
	/// A named board rather than the general one, unlike `copy-files` above: a
	/// driven run changes nothing that belongs to whoever is at the keyboard,
	/// and their clipboard is theirs. Released afterwards, since a named board
	/// lives in the pasteboard server until somebody says otherwise.
	func pastePictureForTesting(_ picture: URL) {
		let board = NSPasteboard(name: NSPasteboard.Name("abydos.driven.paste-picture.\(UUID().uuidString)"))
		defer { board.releaseGlobally() }
		board.clearContents()
		// A `.tiff` goes on as TIFF, which is the path that decodes and encodes;
		// anything else goes on as PNG, which is written as it is.
		board.setData(
			(try? Data(contentsOf: picture)) ?? Data(),
			forType: picture.pathExtension.lowercased() == "tiff" ? .tiff : .png
		)
		guard let folder = destinationFolder(for: selectedNodes().first) else {
			print("TREE paste-picture: nowhere to paste")
			return
		}
		let started = Date()
		guard let written = pastePicture(from: board, into: folder) else {
			print("TREE paste-picture: nothing written")
			return
		}
		let took = Date().timeIntervalSince(started)
		let size = (try? Data(contentsOf: written)).flatMap(NSBitmapImageRep.init(data:))
		let relative = project.map { written.path.replacingOccurrences(of: $0.root.path + "/", with: "") }
			?? written.path
		print("TREE paste-picture: \(relative) \(size?.pixelsWide ?? 0)×\(size?.pixelsHigh ?? 0)"
			+ String(format: " in %.3f s", took) + " \(renameFieldReportForTesting)")
	}

	// MARK: - Undo


	/// The manager, or nil while a name is being edited on a row.
	///
	/// Nil then because the rename field is a *subview of the outline view*, so
	/// the field editor's responder chain runs straight through it: without this
	/// the tree would answer the ⌘Z meant to take back a mistyped letter, and
	/// undo a delete instead. Answering nil makes `NavigatorOutlineView`
	/// transparent to `undo:` — see its `responds(to:)` — so the chain carries on
	/// past the tree to the window's undo manager, which is where the field
	/// editor's text undo lives.
	var fileUndoManager: UndoManager? { nameField == nil ? fileUndo : nil }

	/// Puts one gesture on the stack, under the name the Edit menu will show.
	///
	/// A gesture that did nothing is not recorded: a ⌘Z that pops an entry and
	/// has nothing to do would silently eat the one before it, which is the same
	/// "cannot be trusted" this was written to avoid.
	func remember(_ action: FileUndo.Action) {
		guard !action.isEmpty else { return }
		fileUndo.registerUndo(withTarget: undoTarget) { target in
			target.navigator?.takeBack(action)
		}
		fileUndo.setActionName(action.gesture.title)
	}

	/// Puts one entry on this stack for a whole workspace edit.
	///
	/// **On the tree's stack, and this is the only place it can be.** A rename
	/// through a language server changes forty files, most of which nothing in
	/// this window has open; a `TextDocument`'s own `UndoTree` is that document's
	/// history and knows nothing of the other thirty-nine, and a rename that
	/// also moved `Foo.java` to `Bar.java` is not a text edit at all. This stack
	/// already holds the gestures that act on files rather than on text, which is
	/// exactly what a workspace edit is, and it is already the stack somebody's
	/// ⌘Z reaches from the tree.
	///
	/// One entry, however many files — the rule `remember` above settled, for the
	/// same reason: forty presses that each take back one file's worth of a
	/// refactoring which only makes sense whole is not an undo.
	func rememberWorkspaceEdit(
		_ plan: WorkspaceEditPlan, title: String, undo: @escaping (WorkspaceEditPlan) -> Void
	) {
		guard !plan.isEmpty else { return }
		fileUndo.registerUndo(withTarget: undoTarget) { _ in undo(plan) }
		fileUndo.setActionName(title)
	}

	/// When a file was last written, for the check that stops an undo throwing
	/// away work somebody did after the gesture.
	static func modificationDate(of url: URL) -> Date? {
		(try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
	}

	/// Takes one gesture back, or says in a sentence why it cannot.
	///
	/// Silent when it works, because the tree showing the file where it belongs
	/// is the whole of what was asked for. Never silent when it does not: an
	/// emptied trash, a name taken since, a folder that has itself gone are all
	/// ordinary, and each gets said.
	///
	/// Nothing is registered back on the stack, so there is no redo — see
	/// `NavigatorOutlineView`, which does not answer `redo:` for that reason.
	fileprivate func takeBack(_ action: FileUndo.Action) {
		let reversal = FileUndo.reverse(
			action,
			exists: { FileManager.default.fileExists(atPath: $0.path) },
			modified: { Self.modificationDate(of: $0) }
		)

		var restored: [URL] = []
		var failures: [String] = []
		for restore in reversal.restores {
			do {
				try FileManager.default.moveItem(at: restore.from, to: restore.to)
				restored.append(restore.to)
			} catch {
				failures.append("“\(restore.to.lastPathComponent)”: \(error.localizedDescription)")
			}
		}

		guard !reversal.discards.isEmpty else {
			finish(action, reversal, restored: restored, discarded: 0, failures: failures)
			return
		}
		// The other half of the family, and the only undo in the app that takes
		// something away: it goes to the trash rather than being unlinked, so
		// undo is not the one operation here that deletes outright.
		//
		// The message waits for this rather than counting the files as gone the
		// moment they are handed over — `recycle` is asynchronous and can refuse,
		// and a summary written before the answer arrives would be a guess.
		NSWorkspace.shared.recycle(reversal.discards) { [weak self] moved, error in
			DispatchQueue.main.async {
				var failures = failures
				if let error { failures.append(error.localizedDescription) }
				self?.finish(
					action, reversal, restored: restored, discarded: moved.count,
					failures: failures
				)
			}
		}
	}

	/// The one message the whole undo gets, and the selection put where the
	/// files went back to.
	private func finish(
		_ action: FileUndo.Action, _ reversal: FileUndo.Reversal,
		restored: [URL], discarded: Int, failures: [String]
	) {
		// One message for the whole gesture, however many files it was — the same
		// rule a drop keeps, and for the same reason: ⌘Z is one gesture.
		if let said = reversal.summary(
			gesture: action.gesture, done: restored.count + discarded, failures: failures
		) {
			Toast.post(said.title, detail: said.detail)
		}

		guard !restored.isEmpty else { return }
		// Opened, so there is somewhere for the files to come back to — the
		// folder they were in may well have been folded away since.
		for url in restored {
			let folder = url.deletingLastPathComponent()
			if let node = rootNode?.node(for: folder), node !== rootNode {
				outlineView.expandItem(node)
			}
		}
		// The watcher rebuilds a moment from now and every row is a different
		// object afterwards, so the selection follows the paths.
		pendingReveal = restored
	}

	/// ⌘Z sent straight at the tree, for scripts that want the file half without
	/// asking the responder chain anything. Naming what is on the stack is the
	/// only way to tell "⌘Z did the right thing" from "⌘Z did nothing".
	func undoForTesting() {
		print("TREE undo: can=\(fileUndo.canUndo) action=\(fileUndo.undoActionName)")
		outlineView.undo(nil)
	}
}
