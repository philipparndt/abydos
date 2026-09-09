import AppKit
import AbydosKit

/// Naming a file on the row it is on: making one, renaming one, and what has
/// to be true before either is allowed to happen.
extension ProjectNavigatorViewController {
	// MARK: - Naming on the row

	/// What the field standing on a row is for.
	///
	/// The two are one gesture from different starting points, so they share the
	/// field, its geometry, the rules that refuse a name, the hold on the
	/// watcher's rebuild and the reveal that follows the path afterwards. All
	/// that differs is whether there was a row before it began and what happens
	/// on Return.
	enum NameEdit {
		/// An existing row, being called something else.
		case rename(node: FileNode, original: String)
		/// A row that is not a file yet. **Nothing is on disk until Return** —
		/// which is the whole reason the order is this way round rather than
		/// create-then-rename: Escape has to leave nothing behind, and an empty
		/// file already written is something.
		case create(placeholder: FileNode, parent: FileNode, kind: EntryName.Kind, anchor: [String])

		var node: FileNode {
			switch self {
			case .rename(let node, _): return node
			case .create(let placeholder, _, _, _): return placeholder
			}
		}

		var kind: EntryName.Kind {
			switch self {
			case .rename(let node, _): return node.isDirectory ? .folder : .file
			case .create(_, _, let kind, _): return kind
			}
		}

		/// What a refusal is a refusal to do. Renaming with a name the rules do
		/// not allow has said "Cannot create that file" since the two paths were
		/// separate machines; sharing one is what makes it worth fixing.
		var verb: String {
			switch self {
			case .rename: return "rename"
			case .create: return "create"
			}
		}
	}



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
		      node !== rootNode, nameField == nil
		else { return }

		beginEditing(.rename(node: node, original: node.name), row: index, name: node.name)
	}

	/// Puts a row where the new entry is going to be and asks for its name
	/// there, which is the whole of 0439.
	///
	/// **At the end of its folder, and it stays there while the name is typed.**
	/// The alternative — re-sorting on every keystroke, so the row is always
	/// where the finished name would put it — moves the row out from under the
	/// cursor of the person reading it, which is reason enough. The mechanical
	/// reason is worse: the field is a subview of the outline view at absolute
	/// coordinates over one row, so a row that moved would leave the field
	/// behind on whatever is now at those coordinates, and re-placing it every
	/// keystroke means recomputing the geometry 0411 took four attempts to get
	/// right, mid-edit, under a caret. The row does jump once on Return —
	/// `pendingReveal` is what makes the jump end with it selected and scrolled
	/// to, rather than lost.
	///
	/// Nothing is written until Return. See `NameEdit.create`.
	func beginNew(kind: EntryName.Kind, named draft: String? = nil) {
		guard nameField == nil, let rootNode else { return }
		// Where a drop aimed at this row would land: inside the selected folder,
		// or beside the selected file, or the project root when nothing is
		// selected. One answer for both gestures, from one function.
		guard let folder = contextParentDirectory, let parent = rootNode.node(for: folder) else { return }

		let name = draft ?? EntryName.draftName(kind: kind)
		let node = FileNode(url: parent.url.appendingPathComponent(name), isDirectory: kind == .folder)
		// Whatever was highlighted before, so Escape can put it back: the
		// placeholder takes the selection while it is up, and the row it came
		// from is where somebody was.
		let anchor = selectedPaths()

		placeholder = (node, parent)
		// The whole tree, because the row structure has changed and the outline
		// view has to ask for the children again. Expansion is restored by path
		// the way every other rebuild here does it, and then the folder the row
		// is going into is opened whether it was before or not — a new child of
		// a collapsed folder is otherwise made and never seen.
		let expanded = expandedPaths()
		outlineView.reloadData()
		restore(expandedPaths: expanded)
		outlineView.expandItem(parent)

		let index = outlineView.row(forItem: node)
		guard index >= 0 else {
			placeholder = nil
			outlineView.reloadData()
			restore(expandedPaths: expanded)
			return
		}
		// Scrolled to before the field is measured: the frame is worked out from
		// the row's rectangle against the visible one, so a row still below the
		// fold would be given a field somewhere off screen.
		outlineView.scrollRowToVisible(index)
		let wasSilent = isSelectingSilently
		isSelectingSilently = true
		outlineView.selectRowIndexes([index], byExtendingSelection: false)
		isSelectingSilently = wasSilent

		beginEditing(
			.create(placeholder: node, parent: parent, kind: kind, anchor: anchor),
			row: index, name: name
		)
	}

	/// Puts the field on a row and hands it the keyboard.
	///
	/// One field for both gestures, which is the point: everything 0411 argued
	/// out about where the box sits, how big its text is and where it stops is
	/// paid for once and had by both.
	func beginEditing(_ edit: NameEdit, row index: Int, name: String) {
		// The rows have to exist before a field can be put on top of one.
		//
		// An outline view builds its row views at the next layout pass, not when
		// it is told to reload — so on a brand-new row the field went in first
		// and the row view was built over it a moment later, and the box was
		// simply not there. Seen on screen and nowhere else: the geometry the
		// harness prints was right the whole time, and the row correctly stopped
		// drawing its own name, so everything readable as a number agreed while
		// the pane showed an empty row. Renaming never met this, because its row
		// was already on screen before anybody asked.
		outlineView.layoutSubtreeIfNeeded()

		// Over the label, not the whole row: the icon stays, so the row still
		// says what kind of thing is being named.
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
		field.stringValue = name
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
		nameField = field
		editing = edit
		// Told, not reloaded. `reloadItem` would build a fresh row view and lay
		// it over the field, which is the fault the deferred rebuild above
		// exists for — the box vanishes while still taking the typing.
		showsName(at: index, false)

		outlineView.window?.makeFirstResponder(field)
		// The stem, the way the Finder does it: the extension is nearly never
		// what somebody meant to change, and having it selected is how a `.swift`
		// gets typed over by accident. The same rule for both gestures — it is
		// what makes `untitled.py` arrive with `untitled` selected, so typing
		// replaces the name and keeps the extension.
		if let editor = field.currentEditor() {
			editor.selectedRange = NSRange(
				location: 0, length: EntryName.stemLength(of: name, kind: edit.kind)
			)
		}
	}

	/// Renames the selected row, for the capture harness: the same three steps
	/// somebody takes, without a keyboard.
	func renameSelectionForTesting(_ name: String) {
		beginRename()
		nameField?.stringValue = name
		commitName()
	}

	/// The other gesture, whole: New, the name, Return. `kind` is `file`,
	/// `folder`, or an extension such as `swift`, which is the submenu's
	/// shortcut.
	///
	/// Typed into the selection rather than assigned to the field, which is the
	/// difference between asking what this does and asking what a harness does:
	/// the draft arrives with only its stem selected, so `new:py:script` has to
	/// come out `script.py`. Setting `stringValue` would replace the extension
	/// as well and prove nothing about the selection at all — and did: the first
	/// run of this made a file called `script`.
	func createSelectionForTesting(kind: String, name: String?) {
		beginNewForTesting(kind: kind)
		if let name { nameField?.currentEditor()?.insertText(name) }
		commitName()
	}

	/// New without the Return, so the row and the field it puts up can be
	/// photographed and measured — which is the half a committed name cannot
	/// show.
	func beginNewForTesting(kind: String) {
		switch kind {
		case "file": beginNew(kind: .file)
		case "folder": beginNew(kind: .folder)
		default:
			let suffix = NewFileKind(name: kind, count: 0, title: NewFileKinds.title(for: kind))
			beginNew(
				kind: .file,
				named: NewFileKinds.name(EntryName.draftName(kind: .file), endingIn: suffix)
			)
		}
	}

	/// Where the field is and what it is drawing with, for the harness.
	///
	/// The three things that were wrong with it were all geometry — the text's
	/// size, where it sat in the row, and where it stopped — so they are worth
	/// being able to read as numbers rather than only off a photograph.
	///
	/// `selected` since 0439: which part of the name the field opens with
	/// highlighted is a decision — the stem and not the extension — and a
	/// screenshot of a one-pixel-high highlight is not evidence of it.
	var renameFieldReportForTesting: String {
		guard let field = nameField else { return "no field" }
		let row = outlineView.rect(ofRow: outlineView.selectedRow)
		let range = field.currentEditor()?.selectedRange ?? NSRange(location: 0, length: 0)
		let text = field.stringValue as NSString
		let selected = NSMaxRange(range) <= text.length ? text.substring(with: range) : "?"
		return "frame=\(field.frame) row=\(row) visible=\(outlineView.visibleRect) "
			+ "font=\(field.font?.pointSize ?? 0) name=\(field.stringValue) selected=“\(selected)”"
	}


	/// True when a rebuild must not happen yet, and remembers that one is owed.
	func holdRebuildForRename() -> Bool {
		guard nameField != nil else { return false }
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

	/// Takes the field away, and with it the row when there was no row before.
	///
	/// **Escape leaves nothing**: no file, no folder, and no row where one was
	/// about to be. That is the whole of what `create` has to undo, and it is
	/// only that little because nothing was written on the way in.
	func endEditing() {
		// Forgotten before the field is taken away, not after: removing a field
		// that is being edited ends the editing then and there, and
		// `controlTextDidEndEditing` arrives while this is still half-done. It
		// would commit the very name Escape had just rejected — and did:
		// beginning a rename, changing the name and pressing Escape renamed the
		// file. Nothing left to find means nothing left to commit.
		let field = nameField
		let edit = editing
		nameField = nil
		editing = nil
		if case .rename(let node, _) = edit {
			showsName(at: outlineView.row(forItem: node), true)
		}
		field?.removeFromSuperview()

		if case .create(_, _, _, let anchor) = edit {
			// The placeholder goes before the tree is asked anything else, so
			// nothing can be handed a row that stands for no file.
			placeholder = nil
			let expanded = expandedPaths()
			outlineView.reloadData()
			restore(expandedPaths: expanded)
			// Whatever a successful Return left waiting, or the row the gesture
			// started from — which is where somebody was before they asked for a
			// new file, and where Escape should put them back.
			restoreSelectionOrReveal(paths: anchor)
		}

		outlineView.window?.makeFirstResponder(outlineView)
		// Whatever changed on disk while the field was up, caught up with now
		// rather than at the next event — which may be a long time coming.
		if deferredRebuild {
			deferredRebuild = false
			reloadTree()
		}
	}

	/// Return: renames the file, or writes the new one, or says why it cannot.
	///
	/// Validated before the field goes: a name that is refused leaves the field
	/// up with the name still in it, since taking it away would look like a
	/// rename that happened — and for a new file it would be worse, because
	/// there would be nothing left of what was typed at all.
	func commitName() {
		guard let field = nameField, let edit = editing else { return }
		let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

		switch edit {
		case .rename(let node, let original):
			// An empty field, or the name it already had, is a cancel rather than
			// an error: neither is somebody asking for anything.
			guard !name.isEmpty, name != original else {
				endEditing()
				return
			}
			let folder = node.url.deletingLastPathComponent()
			guard let destination = accepted(name, kind: edit.kind, in: folder) else { return }
			do {
				try FileManager.default.moveItem(at: node.url, to: destination)
			} catch {
				refuse(error.localizedDescription, kind: edit.kind)
				return
			}
			remember(FileUndo.renamed(from: node.url, to: destination))
			// The watcher rebuilds the tree, and the row is a different object
			// afterwards — so the selection follows the path rather than the node.
			pendingReveal = [destination]
			endEditing()

		case .create(_, let parent, let kind, _):
			// An empty field is a cancel, exactly as it is for a rename: nothing
			// was written on the way in, so there is nothing to undo.
			guard !name.isEmpty else {
				endEditing()
				return
			}
			guard let destination = accepted(name, kind: kind, in: parent.url) else { return }
			do {
				switch kind {
				case .folder:
					try FileManager.default.createDirectory(
						at: destination, withIntermediateDirectories: false
					)
				case .file:
					try Data().write(to: destination, options: .withoutOverwriting)
				}
			} catch {
				refuse(error.localizedDescription, kind: kind)
				return
			}
			// Undoing this moves it to the trash, and the date is read now so that
			// a ⌘Z arriving after somebody has written in the file refuses instead
			// — which is the case the change check exists for.
			remember(FileUndo.created(destination, isDirectory: kind == .folder) {
				Self.modificationDate(of: $0)
			})
			// The folder has just been written to, so its listing is stale by one
			// entry. Re-read here rather than waiting for the watcher: the row
			// the placeholder stood for has to be replaced by the real one in the
			// same breath, or the tree shows the file gone for as long as it
			// takes an event to arrive.
			parent.reloadPreservingIdentity()
			pendingReveal = [destination]
			endEditing()
			// Opened straight away, and only a file: a new file is made in order
			// to write in it. A folder is made to put things in, and there is
			// nothing to open.
			if kind == .file { onSelectFile?(destination, true) }
		}
	}

	/// The name checked before it reaches the disk, or nil with the field left
	/// standing.
	///
	/// Both halves refuse rather than overwrite, which is the rule everywhere
	/// else now, and both leave the field up with the keyboard in it so the name
	/// can be corrected rather than thrown away and retyped.
	private func accepted(_ name: String, kind: EntryName.Kind, in folder: URL) -> URL? {
		if let problem = EntryName.problem(
			name, kind: kind, showingHiddenFiles: Settings.shared.showHiddenFiles
		) {
			refuse(problem, kind: kind)
			return nil
		}
		let destination = folder.appendingPathComponent(name)
		guard !FileManager.default.fileExists(atPath: destination.path) else {
			refuse("“\(name)” already exists here.", kind: kind)
			return nil
		}
		return destination
	}

	/// Says why, and gives the keyboard back to the field that is still there.
	///
	/// **Only when the field has not got it already.** `makeFirstResponder` on
	/// the field that is already being edited is not a no-op: it tears the field
	/// editor down and builds another, `controlTextDidEndEditing` arrives, and
	/// the name is committed a second time — refused a second time, and reported
	/// a second time. Two identical toasts stacked up in the corner, which is
	/// how this was noticed; the same double report was there for a refused
	/// rename before the two paths shared this.
	private func refuse(_ problem: String, kind: EntryName.Kind) {
		Toast.post(
			"Cannot \(editing?.verb ?? "create") that \(kind == .file ? "file" : "folder")",
			detail: problem
		)
		guard let field = nameField, let window = outlineView.window else { return }
		let responder = window.firstResponder
		guard responder !== field, responder !== field.currentEditor() else { return }
		window.makeFirstResponder(field)
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
	@objc func contextExport(_ sender: NSMenuItem) {
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
	func statedLook(of node: FileNode?) -> String? {
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

	/// The submenu's two verbs without the menu, for driving them end to end;
	/// `menu` is the step that proves they are offered.
	func compareForTesting(history: Bool) {
		history ? contextCompareHistory() : contextCompareAgainstHead()
	}

	@objc func contextCompareAgainstHead() {
		guard let node = contextNode, !node.isDirectory else { return }
		onCompareFile?(node.url)
	}

	@objc func contextCompareWith() {
		guard let node = contextNode else { return }
		onCompareWith?(node.url)
	}

	@objc func contextCompareSelected() {
		let nodes = contextNodes
		guard nodes.count == 2 else { return }
		onCompareSelected?(nodes.map(\.url))
	}

	@objc func contextCompareHistory() {
		guard let node = contextNode, !node.isDirectory else { return }
		onShowFileHistory?(node.url)
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
			let children = (item.submenu?.items ?? [])
				.filter { !$0.isSeparatorItem && !$0.isHidden }.map {
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
			pendingReveal = [url]
		}
	}

	@objc func contextRename() {
		// The same gesture from the menu, so there is one way it works.
		let row = contextNode.map { outlineView.row(forItem: $0) } ?? -1
		guard row >= 0 else { return }
		outlineView.selectRowIndexes([row], byExtendingSelection: false)
		beginRename(row: row)
	}

	@objc func contextTrash() {
		trash(contextNodes)
	}

	/// ⌘⌫: whatever the tree has highlighted, and nothing to do with the pointer.
	///
	/// The selection rather than `contextNodes`, which starts from `clickedRow`:
	/// a row clicked earlier is still the clicked row long afterwards, and the
	/// keyboard should never trash something the keyboard cannot see it is about
	/// to trash.
	func trashSelection() {
		let doomed = outlineView.selectedRowIndexes
		// Worked out before anything goes, because afterwards there is no row to
		// count back from.
		let successor = rowSurviving(above: doomed)
		// Set *before* the trash rather than after, because the reload that takes
		// the rows away now happens inside it: `restoreSelectionOrReveal` reads
		// this, and a survivor named afterwards would be a row waiting for the
		// watcher's reload to arrive and put the selection somewhere.
		if let successor { pendingReveal = [successor] }
		trash(doomed.sorted().compactMap { outlineView.item(atRow: $0) as? FileNode })
	}

	/// Where the selection goes once these rows have gone. `TreeSelection` has
	/// the rule and the tests; this hands it the rows.
	private func rowSurviving(above doomed: IndexSet) -> URL? {
		TreeSelection.surviving(above: Set(doomed)) { row in
			(outlineView.item(atRow: row) as? FileNode)?.url.path
		}
		.map { URL(fileURLWithPath: $0) }
	}

	/// Moves rows to the trash.
	///
	/// All of them, and the project root is never one of them. This is the one
	/// place several rows makes the work smaller rather than larger: `recycle`
	/// already takes an array, and moving three files to the trash stops being
	/// three gestures.
	private func trash(_ nodes: [FileNode]) {
		let asked = nodes.filter { $0 !== rootNode }.map(\.url)
		guard !asked.isEmpty else { return }
		// A row whose file has already left is not sent to the trash.
		//
		// This is the error that was reported: the row stayed until the watcher
		// noticed, somebody pressed ⌘⌫ again, the dead URL went to `recycle`, and
		// the toast said *Could not move that to the trash* over a file that was
		// already in it. With the rows going at once it should not arise from
		// impatience any more, but a file deleted in a terminal is the same stale
		// row — and a refresh was always the honest reply to that key, never a
		// complaint.
		let urls = asked.filter { FileManager.default.fileExists(atPath: $0.path) }
		guard !urls.isEmpty else {
			reread(parentsOf: asked)
			return
		}

		// The rows go now, before the trash is asked.
		//
		// `recycle` is a cross-process round trip of hundreds of milliseconds,
		// and the row used to wait for the watcher to notice the file had left
		// its directory — which for a folder nobody had expanded never happened
		// at all. Marked here and cleared in the completion, so the tree is drawn
		// without them for exactly as long as the trash is working.
		doomedRows.mark(urls)
		redrawRows()

		let askedAt = Date()
		// Trash rather than delete: recoverable, and no confirmation needed.
		//
		// The dictionary `recycle` answers with is original URL to the place in
		// the trash each file went, and it is kept because there is nowhere else
		// to get it: the trash renames on collision, so two files called `main.py`
		// from different folders do not both keep the name in there, and no
		// amount of looking afterwards says which is which. It was discarded here
		// until 0442, and that — rather than anything unwritten — is what made ⌘Z
		// after a delete impossible.
		//
		// Whatever did arrive is recorded even when the call also reports an
		// error, because `recycle` can refuse one file out of four and the other
		// three are still undoable.
		NSWorkspace.shared.recycle(urls) { [weak self] moved, error in
			DispatchQueue.main.async {
				guard let self else { return }
				self.trashTimeForTesting = String(
					format: "%d file(s) in %.0f ms, %@",
					urls.count, Date().timeIntervalSince(askedAt) * 1000, LaunchClock.loadSaid
				)
				// Every row is un-marked, the moved and the refused alike. The set
				// says only "not drawn"; what became of each file is on the disk
				// by now, and the re-read below is what asks it. So a refused
				// file's row comes back beside the toast saying why, and a moved
				// one's does not come back because it is not in its folder any
				// more.
				self.doomedRows.clear(urls)
				// The parents rather than the watcher.
				//
				// A trashed folder arrives from FSEvents as a must-scan event on
				// the folder itself, and the handler re-reads only directories the
				// tree has listed — so a collapsed folder's row stayed until
				// something else changed its parent. Re-reading here does not
				// depend on the watcher noticing anything.
				self.reread(parentsOf: urls)
				if let error {
					Toast.post("Could not move that to the trash", detail: error.localizedDescription)
				}
				// From the trash's own answer, as it has been since 0442: the
				// dictionary is the only place the trash location of each file
				// exists. The row leaving early changes when it is *drawn*, not
				// when this is known.
				self.remember(FileUndo.trashed(moved))
			}
		}
	}

	/// Re-reads the folders these files were in and draws the tree again.
	private func reread(parentsOf urls: [URL]) {
		for folder in DoomedRows.parents(of: urls) {
			rootNode?.loadedNode(for: folder)?.reloadPreservingIdentity()
		}
		redrawRows()
	}

	/// Draws the tree again, keeping what was open and where the selection was —
	/// or landing it on a row somebody is waiting for.
	private func redrawRows() {
		let expanded = expandedPaths()
		let selected = selectedPaths()
		let place = rememberPlace()
		outlineView.reloadData()
		restore(expandedPaths: expanded)
		restoreSelectionOrReveal(paths: selected)
		restore(place: place)
	}
}
