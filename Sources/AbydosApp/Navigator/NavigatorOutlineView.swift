import AppKit
import QuickLookUI
import AbydosKit

/// Outline view that hands key events to the controller before acting on them.
final class NavigatorOutlineView: NSOutlineView {
	var onKeyDown: ((NSEvent) -> Bool)?
	/// The files Quick Look should show, in tree order — the whole selection,
	/// so the panel's arrow keys walk it the way they do in the Finder.
	var quickLookFiles: (() -> [URL])?
	/// The tree's file undo stack, asked for rather than held: the controller
	/// withholds it while a name is being edited on a row.
	/// Internal rather than `fileprivate` because this class now lives in a
	/// file of its own, and the controller sets it from that one. The house
	/// rule about splitting a class names this cost — every property the new
	/// file touches gets widened — and this is the whole of it here: one hook,
	/// set once, by the one object that owns this view.
	var fileUndoManager: (() -> UndoManager?)?
	/// What ⌘C should put on the pasteboard, in tree order.
	var copyFiles: (() -> [URL])?
	/// ⌘V, and ⌥⌘V, which is the same gesture the other way round.
	var onPaste: ((FileTransfer.Operation) -> Void)?
	/// Whether there is anything on the board to paste, so the Edit menu's
	/// Paste greys itself out over an empty one.
	var canPaste: (() -> Bool)?

	override var acceptsFirstResponder: Bool { true }

	/// ⌘C copies the selected files — as files, and as their paths.
	///
	/// Answered here rather than bound to a key, so it arrives the way copying
	/// arrives everywhere else: the Edit menu sends `copy:` down the responder
	/// chain, this is the responder when the tree has the keyboard, and the
	/// menu item greys itself out when there is nothing selected to copy.
	///
	/// `FilePasteboard` is what makes it both things at once. The text form is
	/// unchanged — one absolute path a line, in tree order — and the same ⌘C now
	/// pastes as a file in the Finder and in this tree.
	@objc func copy(_ sender: Any?) {
		let files = copyFiles?() ?? []
		guard !files.isEmpty else { return }
		FilePasteboard.write(files)
	}

	/// ⌘V. ⌥⌘V is the same thing as a move, and arrives through `keyDown`
	/// instead: AppKit only dispatches key equivalents it finds in the main
	/// menu, and the Edit menu's Paste is ⌘V alone.
	@objc func paste(_ sender: Any?) {
		onPaste?(.copy)
	}

	/// ⌘Z over the tree, which is files and never text.
	///
	/// Answered here rather than left to the window's undo manager, and that is
	/// the whole of how the two stacks stay apart. `undo:` is sent from the Edit
	/// menu with no target, so AppKit walks the responder chain from the first
	/// responder and stops at the first object answering to it: this one when the
	/// keyboard is in the tree, `CodeView` when it is in the editor. Neither pane
	/// is in the other's chain, so a ⌘Z aimed at a stray character can never put
	/// back a folder somebody meant to trash, and a ⌘Z after a delete never
	/// rewrites a file.
	///
	/// There is deliberately no `undoManager` override to go with this. Returning
	/// the file stack from that property would hand it to the *rename field*,
	/// whose editor sits inside this view and asks the chain for the manager to
	/// register its typing on — the two stacks would then be one, which is
	/// exactly what this is for. One door, and it is this method.
	///
	/// No `redo:` either. Taking a gesture back registers nothing in its place,
	/// so a redo here would be a menu item that is always empty; leaving the
	/// selector unanswered lets ⇧⌘Z carry on down the chain rather than being
	/// swallowed by something that could never do anything. Redoing a copy means
	/// keeping the source it came from, which is a larger promise than 0442 made.
	@objc func undo(_ sender: Any?) {
		fileUndoManager?()?.undo()
	}

	/// Transparent to `undo:` while a name is being edited on a row.
	///
	/// The rename field is a subview of this view, so its field editor's
	/// responder chain runs through here. Merely answering `undo:` with a no-op
	/// then would swallow the key — `tryToPerform` asks this, not the method's
	/// body — and typing in the field would have no undo at all. Saying no lets
	/// the chain reach the window's undo manager, which is the one the field
	/// editor registered its typing on.
	override func responds(to selector: Selector!) -> Bool {
		if selector == #selector(undo(_:)) { return fileUndoManager?() != nil }
		return super.responds(to: selector)
	}

	override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		if item.action == #selector(copy(_:)) { return !(copyFiles?().isEmpty ?? true) }
		if item.action == #selector(paste(_:)) { return canPaste?() ?? false }
		// Greyed out over an empty stack rather than swallowing the key: an Undo
		// that is enabled and does nothing is the same lie as one that undoes the
		// wrong thing, only quieter.
		if item.action == #selector(undo(_:)) { return fileUndoManager?()?.canUndo ?? false }
		return super.validateUserInterfaceItem(item)
	}

	override func keyDown(with event: NSEvent) {
		if onKeyDown?(event) == true { return }
		super.keyDown(with: event)
	}

	// MARK: - Quick Look

	/// Opens the system's preview panel on the selection.
	///
	/// **Here rather than on the controller**, because the panel asks the key
	/// window's responder chain who wants to control it and this is what has
	/// the keyboard when the tree does. The same handshake `FileNoticeView`
	/// does, and for the same measured reason: the documented route is the
	/// three `…PreviewPanelControl` methods, the panel only walks the chain
	/// when the application is active, and a panel opened while it is not is
	/// one controlled by nobody, showing nothing.
	func showQuickLook() {
		guard let panel = QLPreviewPanel.shared() else { return }
		// **A toggle, as everywhere else on this machine.** Space opens it and
		// Space closes it; without this the second press reloaded the panel it
		// had already opened and looked like a key that had stopped working.
		if panel.isVisible, panel.dataSource === self {
			panel.orderOut(nil)
			return
		}
		window?.makeFirstResponder(self)
		panel.dataSource = self
		panel.delegate = self
		panel.makeKeyAndOrderFront(nil)
		panel.reloadData()
	}

	override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

	override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
		panel.dataSource = self
		panel.delegate = self
	}

	override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
		// Only what this view put there. The panel outlives the tree's focus,
		// and clearing somebody else's source would leave their panel blank.
		guard panel.dataSource === self else { return }
		panel.dataSource = nil
		panel.delegate = nil
	}

	/// What the panel is showing, for a driven run.
	var quickLookReportForTesting: String {
		guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared()
		else { return "QUICKLOOK no panel" }
		let mine = panel.dataSource === self
		return "QUICKLOOK \(panel.isVisible ? "open" : "shut")"
			+ " controlled=\(mine ? "tree" : "somebody else")"
			+ " showing=\((panel.currentPreviewItem?.previewItemURL?.lastPathComponent) ?? "nothing")"
			+ " of=\(mine ? (quickLookFiles?().count ?? 0) : 0)"
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

extension NavigatorOutlineView: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
	func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
		quickLookFiles?().count ?? 0
	}

	func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
		let files = quickLookFiles?() ?? []
		guard index >= 0, index < files.count else { return nil }
		return files[index] as NSURL
	}

	/// Zooms out of the row it is previewing rather than appearing from
	/// nowhere, which is what the panel does everywhere else on this machine.
	func previewPanel(
		_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!
	) -> NSRect {
		guard let window, let url = item.previewItemURL as URL? else { return .zero }
		// **The row holding this file**, found by its path rather than by
		// counting. The two lists are not the same length — four rows selected
		// with two of them previewable is a panel of two — so the item's
		// position in the panel is not its position in the selection, and
		// indexing one by the other zooms out of somebody else's row.
		// `self.item(atRow:)` spelled out: the parameter of this delegate method
		// is also called `item`, and shadows the method.
		guard let row = selectedRowIndexes.first(where: {
			(self.item(atRow: $0) as? FileNode)?.url == url
		}) else { return .zero }
		return window.convertToScreen(convert(rect(ofRow: row), to: nil))
	}

	/// The panel takes the keys while it is up — except the ones that belong to
	/// the tree underneath it, so ↑ and ↓ still move the selection and the
	/// preview follows it, as in the Finder.
	func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
		guard event.type == .keyDown, event.keyCode == 125 || event.keyCode == 126 else {
			return false
		}
		keyDown(with: event)
		panel.reloadData()
		return true
	}
}
