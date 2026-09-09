import AbydosKit
import AppKit

/// What the tree keeps for the archives somebody asked to see into.
///
/// One object on the navigator rather than five stored properties, because an
/// extension in another file cannot add stored state and the tree file is at
/// its recorded length.
final class ArchiveSupport {
	/// The shown archives, by the archive file's path.
	var roots: [String: ArchiveRoot] = [:]
	/// The items this extension owns in the tree's context menu.
	weak var showItem: NSMenuItem?
	weak var openItem: NSMenuItem?
	weak var openHexItem: NSMenuItem?
	weak var extractItem: NSMenuItem?
	weak var copyPathItem: NSMenuItem?
	/// The reads in flight, so a second *Show Contents* on the same archive
	/// while the first is reading does not read it twice.
	var reading: Set<String> = []
	/// Directories inside archives to open once their index arrives, from a
	/// session being restored.
	var pendingFolds: Set<String> = []
}

/// The archive rows: *Show Contents* on a zip, tar, tgz or gz, the entries
/// listed from the archive's own directory, an entry opened read only from
/// the cache, one entry extractable beside the archive, and the shown set
/// kept with the tree's folds.
extension ProjectNavigatorViewController {
	// MARK: - Which rows are archives

	/// The shown archive behind a file row, if it is one.
	func archiveRoot(for node: FileNode) -> ArchiveRoot? {
		archives.roots[node.url.path]
	}

	func isArchiveShown(_ node: FileNode) -> Bool {
		archiveRoot(for: node) != nil
	}

	/// Whether the row could be shown: a file whose name is an archive's.
	func isArchive(_ node: FileNode) -> Bool {
		!node.isDirectory && ArchiveKind.isOffered(forName: node.name)
	}

	// MARK: - The data source's arms

	/// How many rows an item has because it is, or is in, a shown archive —
	/// or nil when it is neither and the ordinary arms answer.
	func archiveChildCount(of item: Any) -> Int? {
		if let node = item as? FileNode, let root = archiveRoot(for: node) {
			return root.isReading ? 1 : root.children.count
		}
		if let node = item as? ArchiveNode { return node.children.count }
		return nil
	}

	func archiveChild(of item: Any, at index: Int) -> Any? {
		if let node = item as? FileNode, let root = archiveRoot(for: node) {
			if root.isReading { return ArchiveNode(note: "Reading \(node.name)…", root: root) }
			return root.children[index]
		}
		if let node = item as? ArchiveNode { return node.children[index] }
		return nil
	}

	func archiveIsExpandable(_ item: Any) -> Bool? {
		if let node = item as? FileNode, isArchiveShown(node) { return true }
		if let node = item as? ArchiveNode { return node.isExpandable }
		return nil
	}

	func archiveCell(for item: Any) -> NSView? {
		guard let node = item as? ArchiveNode else { return nil }
		let cell = ArchiveCellView()
		cell.configure(node)
		cell.toolTip = node.entry.map { "\(node.root.url.lastPathComponent)/\($0.path)" }
		return cell
	}

	// MARK: - Showing and hiding

	/// Reads the archive off the main thread and opens the row on what it
	/// finds; the row shows it is reading meanwhile.
	func showContents(of node: FileNode) {
		let path = node.url.path
		guard archives.roots[path] == nil else { return }
		let root = ArchiveRoot(url: node.url)
		archives.roots[path] = root
		archives.reading.insert(path)
		outlineView.reloadItem(node, reloadChildren: true)
		outlineView.expandItem(node)
		let url = node.url
		// Read on a detached task and applied on this actor once it is back,
		// so nothing hops threads with `self` in hand.
		Task { [weak self] in
			let outcome = await Task.detached(priority: .userInitiated) {
				Result { try ArchiveIndex.read(url) }
			}.value
			guard let self, archives.roots[path] === root else { return }
			archives.reading.remove(path)
			switch outcome {
			case .success(let index): root.set(index: index)
			case .failure(let failure):
				root.set(failure: (failure as? ArchiveIndex.Failure)?.said ?? failure.localizedDescription)
			}
			outlineView.reloadItem(node, reloadChildren: true)
			outlineView.expandItem(node)
			expandPendingArchiveFolds(in: root, archiveKey: archiveKey(for: node))
		}
	}

	func hideContents(of node: FileNode) {
		guard archives.roots[node.url.path] != nil else { return }
		outlineView.collapseItem(node)
		archives.roots[node.url.path] = nil
		outlineView.reloadItem(node, reloadChildren: true)
	}

	func toggleContents(of node: FileNode) {
		if isArchiveShown(node) { hideContents(of: node) } else { showContents(of: node) }
	}

	/// A replaced archive is a different key: read again on the next expand.
	func archiveWillExpand(_ node: FileNode) {
		guard let root = archiveRoot(for: node), let index = root.index,
			  let now = try? ArchiveIndex.Key.of(node.url), now != index.key else { return }
		archives.roots[node.url.path] = nil
		showContents(of: node)
	}

	/// Before a row opens: an archive replaced under an open row is read again.
	func outlineViewItemWillExpand(_ notification: Notification) {
		if let node = notification.userInfo?["NSObject"] as? FileNode, isArchiveShown(node) {
			archiveWillExpand(node)
		}
	}

	// MARK: - Opening and extracting

	/// Writes the entry to the cache off the main thread and hands the file
	/// to the editor with where it came from.
	func openArchiveEntry(_ node: ArchiveNode, pinned: Bool) {
		guard node.isOpenable, let entry = node.entry, let index = node.root.index, let origin = node.origin else { return }
		Task { [weak self] in
			let outcome = await Task.detached(priority: .userInitiated) {
				Result { try ArchiveCache.file(for: entry, in: index) }
			}.value
			guard let self else { return }
			switch outcome {
			case .success(let url):
				onOpenArchiveEntry?(url, origin, pinned)
			case .failure(let failure):
				Toast.post(
					"Cannot open \(entry.name)",
					detail: (failure as? ArchiveIndex.Failure)?.said ?? failure.localizedDescription,
					kind: .warning
				)
			}
		}
	}

	/// The entry beside the archive, asking before writing over anything.
	func extractArchiveEntry(_ node: ArchiveNode) {
		guard let entry = node.entry, let index = node.root.index else { return }
		let directory = node.root.url.deletingLastPathComponent()
		let target = directory.appendingPathComponent(entry.name)
		if FileManager.default.fileExists(atPath: target.path) {
			let alert = NSAlert()
			alert.messageText = "Replace \(entry.name)?"
			alert.informativeText = "There is already a \(entry.name) beside \(node.root.url.lastPathComponent). Extracting writes over it."
			alert.addButton(withTitle: "Replace")
			alert.addButton(withTitle: "Cancel")
			guard alert.runModal() == .alertFirstButtonReturn else { return }
		}
		do {
			let written = try ArchiveCache.extract(entry, from: index, into: directory, overwrite: true)
			reveal(url: written)
		} catch {
			Toast.post("Cannot extract \(entry.name)", detail: error.localizedDescription, kind: .warning)
		}
	}

	// MARK: - The menu

	/// The items, made once with the menu and shown by `updateArchiveMenu`.
	func installArchiveMenuItems(in menu: NSMenu) {
		func item(_ title: String, _ action: Selector) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = self
			item.isHidden = true
			return item
		}
		let show = item("Show Contents", #selector(contextToggleArchiveContents))
		let open = item("Open", #selector(contextOpenArchiveEntry))
		let hex = item("Open as Hex", #selector(contextOpenArchiveEntryAsHex))
		let extract = item("Extract…", #selector(contextExtractArchiveEntry))
		let copy = item("Copy Path", #selector(contextCopyArchivePath))
		// After *Open as Hex*, where the file's own opening verbs are.
		let anchor = menu.items.firstIndex { $0.title == "Open as Hex" }.map { $0 + 1 } ?? menu.items.count
		for (offset, entry) in [show, open, hex, extract, copy].enumerated() {
			menu.insertItem(entry, at: anchor + offset)
		}
		archives.showItem = show
		archives.openItem = open
		archives.openHexItem = hex
		archives.extractItem = extract
		archives.copyPathItem = copy
	}

	/// Tailors the menu to archive rows. Returns true when the click was on a
	/// row inside an archive, whose menu is these items and nothing else.
	func updateArchiveMenu(_ menu: NSMenu, fileNode: FileNode?) -> Bool {
		let inner = contextArchiveNode
		let own = [archives.showItem, archives.openItem, archives.openHexItem, archives.extractItem, archives.copyPathItem]
		if let inner {
			for item in menu.items { item.isHidden = !own.contains { $0 === item } }
			// Enabled by hand: the loop before this greyed everything that
			// wants a file row, and these want an archive row instead.
			for item in own { item?.isEnabled = true }
			archives.showItem?.isHidden = true
			archives.openItem?.isHidden = !inner.isOpenable
			archives.openHexItem?.isHidden = !inner.isOpenable
			archives.extractItem?.isHidden = inner.entry == nil
			archives.copyPathItem?.isHidden = inner.entry == nil
			return true
		}
		archives.showItem?.isEnabled = true
		for item in own.dropFirst() { item?.isHidden = true }
		if let fileNode, isArchive(fileNode) {
			archives.showItem?.isHidden = false
			archives.showItem?.title = isArchiveShown(fileNode) ? "Hide Contents" : "Show Contents"
		} else {
			archives.showItem?.isHidden = true
		}
		return false
	}

	/// The archive row the menu was opened on, when it was one.
	var contextArchiveNode: ArchiveNode? {
		let clicked = outlineView.clickedRow
		let row = clicked >= 0 ? clicked : outlineView.selectedRow
		return row >= 0 ? outlineView.item(atRow: row) as? ArchiveNode : nil
	}

	@objc private func contextToggleArchiveContents() {
		guard let node = contextFileNodeForArchive else { return }
		toggleContents(of: node)
	}

	@objc private func contextOpenArchiveEntry() {
		guard let node = contextArchiveNode else { return }
		openArchiveEntry(node, pinned: true)
	}

	@objc private func contextOpenArchiveEntryAsHex() {
		guard let node = contextArchiveNode, let entry = node.entry, let index = node.root.index else { return }
		Task { [weak self] in
			let outcome = await Task.detached(priority: .userInitiated) {
				Result { try ArchiveCache.file(for: entry, in: index) }
			}.value
			guard let self else { return }
			if case .success(let url) = outcome { onOpenAsHex?(url) }
		}
	}

	@objc private func contextExtractArchiveEntry() {
		guard let node = contextArchiveNode else { return }
		extractArchiveEntry(node)
	}

	@objc private func contextCopyArchivePath() {
		guard let node = contextArchiveNode, let entry = node.entry else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString("\(node.root.url.path)!/\(entry.path)", forType: .string)
	}

	/// The file row the menu was opened on, by the same rule the file items
	/// use, without reaching into the main file's private helpers.
	private var contextFileNodeForArchive: FileNode? {
		let clicked = outlineView.clickedRow
		let row = clicked >= 0 ? clicked : outlineView.selectedRow
		return row >= 0 ? outlineView.item(atRow: row) as? FileNode : nil
	}

	// MARK: - The session

	/// `archive:<path relative to the project>` for each shown archive, and
	/// `archive:<path>!<directory>` for each directory open inside one.
	func archiveFoldKeys() -> [String] {
		var keys: [String] = []
		for (path, root) in archives.roots {
			guard let node = fileNodeShown(atPath: path) else { continue }
			let key = archiveKey(for: node)
			keys.append(key)
			func walk(_ nodes: [ArchiveNode]) {
				for child in nodes where child.isDirectory && outlineView.isItemExpanded(child) {
					if let fold = child.foldKey(archiveKey: key) { keys.append(fold) }
					walk(child.children)
				}
			}
			walk(root.children)
		}
		return keys
	}

	func archiveKey(for node: FileNode) -> String {
		archiveKey(forArchivePath: node.url.path)
	}

	/// The same key from the path alone, for the rows *inside* an archive: an
	/// `ArchiveNode` knows the archive it came from and never the file row.
	func archiveKey(forArchivePath path: String) -> String {
		guard let root = project?.root.standardizedFileURL.path, path.hasPrefix(root + "/") else {
			return "archive:" + path
		}
		return "archive:" + String(path.dropFirst(root.count + 1))
	}

	/// What a selected archive row is remembered by across a rebuild.
	///
	/// See `ArchiveNode.selectionKey`, which is where the fault this answers
	/// is written down: the capture knew a file row and a session row, so the
	/// highlight on an entry went out on the next filesystem event.
	func archiveSelectionKey(for node: ArchiveNode) -> String? {
		node.selectionKey(archiveKey: archiveKey(forArchivePath: node.root.url.path))
	}

	/// The row a selection key names, or -1 where the key finds nothing.
	///
	/// -1 rather than nil because that is what `TreeSelection.rows` reads, and
	/// it is the honest answer for a key whose archive has since been hidden
	/// or whose entry is no longer in it: the selection is gone because the
	/// row is, which is not this fault.
	func archiveRow(forSelectionKey key: String) -> Int {
		guard let bang = key.firstIndex(of: "!") else { return -1 }
		let archive = String(key[..<bang])
		let inside = String(key[key.index(after: bang)...])
		guard let root = archives.roots.first(where: {
			archiveKey(forArchivePath: $0.key) == archive
		})?.value else { return -1 }
		guard let node = root.node(forPath: inside) else { return -1 }
		return outlineView.row(forItem: node)
	}

	// MARK: - Finding an entry from the file it was written to

	/// The archive row a cache file stands for, or nil when no archive this
	/// window is showing wrote it.
	///
	/// **The way back, because the way out is one-directional.** An entry that
	/// is opened is written into the cache under a folder keyed to a digest of
	/// the archive's path, size and modification time — so the file the editor
	/// holds is a path with nothing of the archive left in its name, and
	/// nothing anywhere maps it back. Every lookup the tree does is by path,
	/// and this path is outside the project, so revealing an open entry said
	/// the file was not in the tree while its row sat in the archive it came
	/// out of, two rows further down.
	///
	/// Asked of each shown archive rather than parsed out of the path: the
	/// digest is not reversible, but it is cheap to recompute, and an archive
	/// that can answer is one whose index is loaded and whose rows therefore
	/// exist. An archive that has since been hidden answers nothing, which is
	/// the honest result — the row really is gone.
	func archiveEntry(forCacheFile url: URL) -> ArchiveNode? {
		let path = FilePath.canonical(url)
		for root in archives.roots.values {
			guard let index = root.index else { continue }
			let directory = FilePath.canonical(ArchiveCache.directory(for: index)) + "/"
			guard path.hasPrefix(directory) else { continue }
			return root.node(forPath: String(path.dropFirst(directory.count)))
		}
		return nil
	}

	/// Whether a path is in the archive cache at all, whoever wrote it.
	///
	/// Separate from the lookup above so that "no archive claims this" and
	/// "this was never an archive entry" can be told apart, which is the
	/// difference between an archive that was hidden and a file that has
	/// nothing to do with any of this.
	func isArchiveCacheFile(_ url: URL) -> Bool {
		FilePath.canonical(url).hasPrefix(FilePath.canonical(ArchiveCache.root()) + "/")
	}

	/// What the tree says about an entry whose archive has since been hidden.
	///
	/// Its own sentence, because the three the tree ends with would each be
	/// true of this file and none of them useful: the file is real, it had a
	/// row when it was opened, and the way back to one is to show the archive
	/// again. Held here rather than written at the point of use so that the
	/// tree file, which is at its recorded length, does not carry it.
	static let archiveNoLongerShownSaid =
		"it was opened from inside an archive, and that archive is no longer "
		+ "shown in the tree."

	/// Opens every row above an entry: the folders holding the archive file,
	/// the archive's own row, then the directories inside it.
	///
	/// **Both halves, and in that order.** After a collapse-all the archive
	/// file has no row of its own, and `expandItem` on a row the outline has
	/// never been handed does nothing — silently, which is the failure
	/// `expandAncestors` is annotated for. So the first version of this found
	/// its entry and then selected nothing at all, which reads from outside
	/// exactly like the reveal that did nothing before any of this.
	///
	/// No row is asked for here, for the reason `expandAncestors` gives:
	/// expanding renumbers everything beneath it, so an index taken on the way
	/// down names the wrong row by the time the last folder is open.
	func expandForArchiveEntry(_ node: ArchiveNode) {
		if let rootNode, let file = rootNode.node(for: node.root.url) {
			let target = row(for: file)
			expandAncestors(of: target, under: rootNode)
			outlineView.expandItem(target)
		}
		expandArchiveAncestors(of: node)
	}

	/// The directories *inside* the archive, outermost first — the second half
	/// of `expandForArchiveEntry`, which is where the order is argued.
	private func expandArchiveAncestors(of node: ArchiveNode) {
		var ancestors: [ArchiveNode] = []
		var current = node.parent
		while let ancestor = current {
			ancestors.append(ancestor)
			current = ancestor.parent
		}
		for ancestor in ancestors.reversed() { outlineView.expandItem(ancestor) }
	}

	/// Shows the archives a session had open, and remembers which of their
	/// directories to open once each index arrives.
	func restoreArchives(matching keys: Set<String>) {
		let archiveKeys = keys.filter { $0.hasPrefix("archive:") }
		guard !archiveKeys.isEmpty, let root = project?.root.standardizedFileURL.path else { return }
		archives.pendingFolds.formUnion(archiveKeys.filter { $0.contains("!") })
		for key in archiveKeys where !key.contains("!") {
			let relative = String(key.dropFirst("archive:".count))
			let url = URL(fileURLWithPath: relative.hasPrefix("/") ? relative : root + "/" + relative)
			guard let node = fileNodeShown(atPath: url.path) ?? loadedFileNode(at: url) else { continue }
			if isArchiveShown(node) {
				outlineView.expandItem(node)
			} else {
				showContents(of: node)
			}
		}
	}

	private func expandPendingArchiveFolds(in root: ArchiveRoot, archiveKey: String) {
		let mine = archives.pendingFolds.filter { $0.hasPrefix(archiveKey + "!") }
		guard !mine.isEmpty else { return }
		archives.pendingFolds.subtract(mine)
		// Shallowest first, so a parent is open before its child is asked for.
		for key in mine.sorted(by: { $0.count < $1.count }) {
			let path = String(key.dropFirst(archiveKey.count + 1))
			if let node = root.node(forPath: path) { outlineView.expandItem(node) }
		}
	}

	/// A file row that is on screen, by path.
	private func fileNodeShown(atPath path: String) -> FileNode? {
		for row in 0..<outlineView.numberOfRows {
			if let node = outlineView.item(atRow: row) as? FileNode, node.url.path == path { return node }
		}
		return nil
	}

	/// A file node under the root, loading the directories on the way; nil
	/// when it is not there.
	private func loadedFileNode(at url: URL) -> FileNode? {
		guard let rootNode, url.path.hasPrefix(rootNode.url.path + "/") else { return nil }
		var node = rootNode
		let parts = url.path.dropFirst(rootNode.url.path.count + 1).split(separator: "/").map(String.init)
		for part in parts {
			guard let next = node.children.first(where: { $0.name == part }) else { return nil }
			node = next
		}
		return node
	}

	// MARK: - Driving

	func showContentsForTesting() -> String {
		guard let node = selectedFileNodeForArchive else { return "show-contents: no file row selected" }
		showContents(of: node)
		return "show-contents: \(node.name) reading"
	}

	func hideContentsForTesting() -> String {
		guard let node = selectedFileNodeForArchive else { return "hide-contents: no file row selected" }
		hideContents(of: node)
		return "hide-contents: \(node.name)"
	}

	func extractForTesting() -> String {
		guard let node = outlineView.item(atRow: outlineView.selectedRow) as? ArchiveNode, let entry = node.entry, let index = node.root.index else {
			return "extract: no entry selected"
		}
		let directory = node.root.url.deletingLastPathComponent()
		do {
			let written = try ArchiveCache.extract(entry, from: index, into: directory, overwrite: false)
			reveal(url: written)
			return "extract: wrote \(written.lastPathComponent) beside \(node.root.url.lastPathComponent)"
		} catch ArchiveCache.ExtractFailure.exists(let url) {
			return "extract: \(url.lastPathComponent) is already there; would ask"
		} catch {
			return "extract: failed: \(error)"
		}
	}

	/// The rows of every shown archive, as text, once its index has arrived.
	func archiveRowsForTesting() -> String {
		var lines: [String] = []
		for (path, root) in archives.roots.sorted(by: { $0.key < $1.key }) {
			let name = (path as NSString).lastPathComponent
			if root.isReading { lines.append("\(name): reading"); continue }
			if let failure = root.failure { lines.append("\(name): \(failure)"); continue }
			func walk(_ nodes: [ArchiveNode], _ depth: Int) {
				for node in nodes {
					lines.append(String(repeating: "  ", count: depth) + node.name + (node.subtitle.map { "  \($0)" } ?? "") + (outlineView.isItemExpanded(node) ? " ▾" : ""))
					if outlineView.isItemExpanded(node) { walk(node.children, depth + 1) }
				}
			}
			lines.append("\(name):")
			walk(root.children, 1)
		}
		return lines.joined(separator: "\n")
	}

	/// What a selected archive row is, for the `selected` report.
	func selectedArchivePathForTesting() -> String? {
		guard let node = outlineView.item(atRow: outlineView.selectedRow) as? ArchiveNode else { return nil }
		return "\(node.root.url.lastPathComponent)!/\(node.entry?.path ?? node.name)"
	}

	private var selectedFileNodeForArchive: FileNode? {
		outlineView.item(atRow: outlineView.selectedRow) as? FileNode
	}
}

/// A row inside an archive: an icon, the name, and the size in the grey half.
///
/// Its own cell rather than the file cell, which is private to the tree file
/// and is about a `FileNode`; this one is about an entry.
final class ArchiveCellView: NSTableCellView {
	private var node: ArchiveNode?

	func configure(_ node: ArchiveNode) {
		self.node = node
		needsDisplay = true
	}

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		guard let node else { return }
		let theme = Theme.current
		let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
		let ink: NSColor = isSelected
			? (theme.isLight ? theme.sidebarHeaderText : .hex(0xE8EAED))
			: theme.sidebarText
		let grey: NSColor = isSelected ? ink.withAlphaComponent(0.7) : theme.gitIgnored

		let symbol: String
		switch node.row {
		case .directory: symbol = "folder.fill"
		case .entry(let entry): symbol = entry.member == .regular ? "doc" : "link"
		case .note: symbol = "info.circle"
		}
		var x = theme.scaled(4)
		let iconSize = theme.scaled(16)
		if let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
			.withSymbolConfiguration(.init(pointSize: iconSize * 0.8, weight: .regular)) {
			let tinted = icon.tinted(with: node.isDirectory ? .hex(0xB58A2B) : grey)
			tinted.draw(in: NSRect(x: x, y: bounds.midY - iconSize / 2, width: iconSize, height: iconSize))
		}
		x += iconSize + theme.scaled(6)

		let font = theme.uiFont(13)
		let name = NSAttributedString(string: node.name, attributes: [.font: font, .foregroundColor: ink])
		let nameSize = name.size()
		name.draw(at: NSPoint(x: x, y: bounds.midY - nameSize.height / 2))
		x += nameSize.width + theme.scaled(8)

		if let subtitle = node.subtitle, x < bounds.width {
			let text = NSAttributedString(string: subtitle, attributes: [.font: theme.uiFont(11), .foregroundColor: grey])
			text.draw(at: NSPoint(x: x, y: bounds.midY - text.size().height / 2))
		}
	}
}

private extension NSImage {
	func tinted(with colour: NSColor) -> NSImage {
		let image = NSImage(size: size, flipped: false) { rect in
			self.draw(in: rect)
			colour.set()
			rect.fill(using: .sourceAtop)
			return true
		}
		image.isTemplate = false
		return image
	}
}
