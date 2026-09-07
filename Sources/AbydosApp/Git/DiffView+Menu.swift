import AppKit
import AbydosKit

/// What a diff offers over what is selected.
///
/// **A file of its own, and the two menus kept together**: one for a diff
/// something can be staged from and one for a diff that has already happened,
/// and a single sentence binds them. *Copy* is the first item of both whenever
/// anything is selected — it answers the question somebody asked by selecting
/// something — and what a diff offered before it is unchanged, under it.
extension DiffView {
	/// The menu over a diff: *Copy* first whenever anything is selected, then
	/// whatever this diff itself offers.
	///
	/// **First because it answers the commonest question** — somebody who has
	/// just selected something wants it — and the diff's own menu is built
	/// before it, because that is what moves the line selection to where the
	/// pointer is aimed.
	override func menu(for event: NSEvent) -> NSMenu? {
		menu(atRow: row(at: convert(event.locationInWindow, from: nil)))
	}

	/// The row a right-click landed on, or none where the question is only
	/// "what does this diff offer over what is selected" — which is what a
	/// driven run asks.
	func menu(atRow row: Int?) -> NSMenu? {
		let offered = isReadOnly ? commentMenu(atRow: row) : stagingMenu(atRow: row)
		guard copiedText != nil else { return offered }

		let menu = offered ?? NSMenu()
		// Never AppKit's own enabling here: a context menu is built before this
		// view is the first responder, and `validateMenuItem` — which answers
		// for the Edit menu's *Copy* — would disable this one for saying so.
		menu.autoenablesItems = false
		let item = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
		item.target = self
		menu.insertItem(item, at: 0)
		if offered != nil { menu.insertItem(.separator(), at: 1) }
		return menu
	}

	private func stagingMenu(atRow row: Int?) -> NSMenu? {
		// A commit's diff has nothing to stage or throw away; it has already
		// happened, and offering to undo part of it here would be a lie. A pull
		// request's has nothing to stage either — it is somebody else's branch —
		// but it does have somewhere to leave a remark.
		// Right-clicking outside the selection moves it there first, so the
		// command acts on what was aimed at — unless what is selected is text,
		// which is the thing the menu is about to offer to copy.
		if !hasTextSelection, let row, rows.indices.contains(row) {
			if case let .hunkHeader(hunkIndex, _) = rows[row] {
				selectHunk(hunkIndex)
			} else if let index = lineIndex(atRow: row), !selection.contains(index) {
				setLineSelection([index])
				anchorRow = row
			}
		}
		guard hasSelection else { return nil }

		let menu = NSMenu()
		menu.autoenablesItems = false

		let count = selection.count
		let suffix = count == 1 ? "" : " (\(count))"
		// **Only what this view has somewhere to send.** These items used to be
		// added whatever the view had been told, and a diff whose owner had not
		// wired them up offered "Stage Selected Lines", enabled, over a closure
		// nobody had set — which is what the commit page did: fifteen lines
		// selected, the item pressed, and the working copy exactly as it was.
		// A missing item is a thing somebody can see; a dead one is not.
		if onApplySelection != nil {
			let apply = NSMenuItem(
				title: (isStaged ? "Unstage Selected Lines" : "Stage Selected Lines") + suffix,
				action: #selector(applySelection),
				keyEquivalent: ""
			)
			apply.target = self
			menu.addItem(apply)
		}

		if !isStaged, onStashSelection != nil {
			if !menu.items.isEmpty { menu.addItem(.separator()) }
			let stash = NSMenuItem(
				title: "Stash Selected Lines" + suffix,
				action: #selector(stashSelection),
				keyEquivalent: ""
			)
			stash.target = self
			menu.addItem(stash)
		}

		if !isStaged, onDiscardSelection != nil {
			if !menu.items.isEmpty { menu.addItem(.separator()) }
			let discard = NSMenuItem(
				title: "Discard Selected Lines" + suffix,
				action: #selector(discardSelection),
				keyEquivalent: ""
			)
			discard.target = self
			menu.addItem(discard)
		}
		return menu.items.isEmpty ? nil : menu
	}

	/// What a read-only diff offers: a remark on the lines under the pointer,
	/// and the verbs for a remark already written here.
	private func commentMenu(atRow row: Int?) -> NSMenu? {
		guard onCommentOnLines != nil else { return nil }

		if let row {
			guard rows.indices.contains(row) else { return nil }

			// Over a remark: the two things that can be done to one written
			// here. Somebody else's is theirs, and this offers nothing over it
			// rather than something that would fail.
			if !hasTextSelection, let (comment, block) = comment(atRow: row) {
				selectedComment = (comment, block)
				needsDisplay = true
				guard comment.isPending else { return nil }
				let menu = NSMenu()
				for (title, action) in [
					("Edit Comment…", #selector(editComment)),
					("Delete Comment", #selector(deleteComment)),
				] {
					let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
					item.target = self
					menu.addItem(item)
				}
				return menu
			}

			// Whichever arrangement is drawn: a row is commentable when it has a
			// line on the new side, which is the only side a forge can anchor
			// to.
			guard let index = lineIndex(atRow: row), newNumber(atRow: row) != nil else {
				return nil
			}

			// **Right-clicking outside the selection moves it there first**, so
			// the remark is about what was aimed at — the same rule the staging
			// menu keeps one function up.
			if !hasTextSelection, !selection.contains(index) {
				setLineSelection([index])
				anchorRow = row
				selectedComment = nil
			}
		}

		let lines = selectedNewLines
		guard let from = lines.min(), let to = lines.max() else { return nil }
		commentRange = (from, to)

		let menu = NSMenu()
		let item = NSMenuItem(
			title: from == to ? "Comment on Line \(from)…" : "Comment on Lines \(from)–\(to)…",
			action: #selector(commentOnLines),
			keyEquivalent: ""
		)
		item.target = self
		menu.addItem(item)
		return menu
	}

	@objc private func commentOnLines() {
		guard let commentRange else { return }
		onCommentOnLines?(commentRange.from, commentRange.to)
	}

	@objc private func editComment() {
		guard let comment = selectedComment?.comment else { return }
		onEditComment?(comment)
	}

	@objc private func deleteComment() {
		guard let comment = selectedComment?.comment else { return }
		onDeleteComment?(comment)
	}

	@objc private func applySelection() { onApplySelection?(selection) }
	@objc private func discardSelection() { onDiscardSelection?(selection) }
	@objc private func stashSelection() { onStashSelection?(selection) }
}
