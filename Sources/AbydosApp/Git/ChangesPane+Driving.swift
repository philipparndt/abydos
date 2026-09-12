import AppKit
import AbydosKit

/// Driving the changes pane from a script: what it shows, what the diff beside
/// it says, and what pressing each of its verbs does.
extension ChangesPane {
	func pushForTesting() { push() }

	/// Selects the first unstaged change, so the screenshot harness can verify
	/// the diff without a click.
	///
	/// The first *file*: row 0 is a folder as soon as anything has changed
	/// below the root, and a folder has no diff to show.
	func selectFirstChangeForTesting() {
		for row in 0..<unstagedTable.numberOfRows {
			guard (unstagedTable.item(atRow: row) as? GitChangeNode)?.change != nil else { continue }
			unstagedTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
			return
		}
	}

	/// What the two trees are showing, as lines, for driving the pane from the
	/// command line. Indented by depth, with a folder's tally after its name.
	/// Puts a summary in, as `…` does when it carries one across.
	/// Presses the draft button, whatever state it is in.
	///
	/// The one gesture, so that a run pressing it while an answer is held is
	/// pressing what somebody would press: the button *is* the offer.
	func pressDraftForTesting() {
		draftMessage()
	}

	/// Hands this pane a draft as though `claude` had just answered — the same
	/// door the real answer comes through.
	///
	/// **Because `claude` cannot be relied on inside a run.** It may not be
	/// installed, it costs money and time, and what is under test here is where
	/// the answer *goes* rather than what it says. The inbox and the pane's own
	/// root decide that, and both are exercised exactly as they are in earnest.
	func deliverDraftForTesting(summary: String, description: String) {
		onDraft?(root, ClaudeDraft.Draft(summary: summary, description: description))
		applyHeldDraft()
	}

	/// What the draft button is, and what the fields hold, in one line.
	var draftReportForTesting: String {
		let state: String
		switch draftState {
		case .idle:     state = "idle"
		case .drafting: state = "drafting"
		case .offering: state = "offering"
		}
		return "draft=\(state) label=\(draftButton?.title ?? "absent")"
			+ " tint=\(draftButton?.tint == nil ? "none" : "red")"
			+ " summary=[\(subjectField.stringValue)]"
			+ " body=[\(bodyView.string.replacingOccurrences(of: "\n", with: "⏎"))]"
			+ " held=\(heldDraft?(root) == nil ? "nothing" : "a draft")"
	}

	func carrySummaryForTesting(_ text: String) {
		subjectField.stringValue = text
		updateCommitButton()
	}

	/// Types both halves of a message, as somebody composing one does.
	///
	/// Both, because `carrySummaryForTesting` is the summary alone and the
	/// description is the half that is expensive to lose — a proof that only
	/// carried a subject would pass over the bug it is about.
	func composeForTesting(summary: String, body: String) {
		fill(subject: summary, body: body)
		if !body.isEmpty { setDescription(showing: true) }
	}

	/// What the fields hold, in one line, for a report either side of a switch.
	/// Commits what is staged, through the button's own door — so a driven run
	/// can show whether the project's hooks ran.
	func commitForTesting(subject: String) {
		composeForTesting(summary: subject, body: "")
		commit()
	}

	func messageReportForTesting() -> String {
		"summary=[\(subjectField.stringValue)] body=[\(bodyView.string)]"
	}

	/// Selects a change by path, in whichever list holds it.
	/// Puts the selection on the row for this path, in whichever list has it.
	///
	/// Named for the driver because that is what asked for it first, and used by
	/// the estate overview too: opening a submodule from there means landing on
	/// its row here rather than in a page that looks the same as before.
	func select(path: String) { selectChangeForTesting(path) }

	/// Switches the picture diff's mode, as the choice control does.
	func choosePictureModeForTesting(_ index: Int) -> String {
		guard let documents = diffDocuments, documents.showsPicture else { return "no picture showing" }
		documents.picture.chooseForTesting(index)
		return documents.picture.reportForTesting
	}

	func selectChangeForTesting(_ path: String) {
		for table in [unstagedTable, stagedTable].compactMap({ $0 }) {
			for row in 0..<table.numberOfRows {
				guard let node = table.item(atRow: row) as? GitChangeNode,
				      node.path == path else { continue }
				table.selectRowIndexes([row], byExtendingSelection: false)
				return
			}
		}
	}

	/// What the page is showing on both sides, and in its message.
	func pageReportForTesting() -> String {
		var said = ["layout=\(arrangement == .page ? "page" : "sidebar")"]
		said.append("unstaged=\(status.unstaged.count) staged=\(status.staged.count)")
		said.append("summary=\(subjectField.stringValue)")
		said.append("body=\(bodyView.string.isEmpty ? "empty" : "\(bodyView.string.count) characters")")
		if let draft = draftButton {
			// The state by name, and the label beside it: "offered" used to
			// mean "the button is enabled", which is true of a button that is
			// holding a draft and of one that has never been pressed.
			let state: String
			switch draftState {
			case .idle:     state = draft.isEnabled ? "idle" : "unavailable"
			case .drafting: state = "drafting"
			case .offering: state = "offering"
			}
			said.append("draft=\(state) label=\(draft.title)")
		} else {
			said.append("draft=absent")
		}
		said.append("history=\(historyButton?.isHidden == false ? "shown" : "hidden")")
		said.append("diff=\(diffDocuments?.reportForTesting ?? diffView?.reportForTesting ?? "none")")
		said.append(layoutReportForTesting())
		return said.joined(separator: "\n")
	}

	/// Where the message ended up and how much height the diff kept.
	///
	/// The numbers are the claim. "The diff has the height the box would have
	/// taken" is not something a photograph can be compared against, and "the
	/// message is under the diff only" is a question about two x positions.
	private func layoutReportForTesting() -> String {
		guard arrangement == .page, let messageStack, let diffScroll = diffView?.enclosingScrollView else {
			return "geometry=none"
		}
		let message = convert(messageStack.bounds, from: messageStack)
		let diff = convert(diffScroll.bounds, from: diffScroll)
		func round(_ value: CGFloat) -> Int { Int(value.rounded()) }
		return "description=\(isDescriptionShowing ? "showing" : "collapsed")"
			+ " message=(x \(round(message.minX)) w \(round(message.width)) h \(round(message.height)))"
			+ " diff=(x \(round(diff.minX)) w \(round(diff.width)) h \(round(diff.height)))"
			+ " pane=(w \(round(bounds.width)) h \(round(bounds.height)))"
	}

	/// Presses the chevron, the way somebody would.
	func toggleDescriptionForTesting() {
		toggleDescription()
	}

	/// Return at the end of the summary, through the delegate a key would reach.
	func pressReturnInSummaryForTesting() {
		guard let textView = subjectField.currentEditor() as? NSTextView else {
			window?.makeFirstResponder(subjectField)
			guard let editor = subjectField.currentEditor() as? NSTextView else { return }
			_ = control(subjectField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
			return
		}
		_ = control(subjectField, textView: textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
	}

	/// Every row of both trees, with what each one is.
	///
	/// A repository row is marked `[repo]` and a moved gitlink `[moved]`, which
	/// is the whole of what an estate adds to this pane and therefore the whole
	/// of what a driven run has to be able to see. Indented by depth, because
	/// the claim being checked is that a submodule sits *above* its folders.
	/// The diff the page is showing, for the row named — which is the claim a
	/// screenshot of an empty pane cannot be asked about.
	func diffForTesting() -> String {
		guard let diffView else { return "no diff view" }
		let text = diffView.reportForTesting
		return text.isEmpty ? "empty" : text
	}

	/// What the menu over the page's diff offers, and whether it is wired to
	/// anything — see `DiffView.verbsForTesting`.
	func diffVerbsForTesting() -> String {
		diffView?.verbsForTesting() ?? "no diff view"
	}

	/// Selects a run of the diff's text the way a drag does: row and offset to
	/// row and offset — see `DiffView.selectTextForTesting`.
	func selectDiffTextForTesting(
		fromRow: Int, offset from: Int, toRow: Int, offset to: Int, onLeft: Bool = false
	) -> String {
		diffView?.selectTextForTesting(
			fromRow: fromRow, offset: from, toRow: toRow, offset: to, onLeft: onLeft
		) ?? "no diff view"
	}

	/// A press at a point in the diff, and the drag that follows it — the
	/// gesture as the pointer makes it, x in points from the view's left edge.
	func pressDiffForTesting(row: Int, x: Int, clicks: Int = 1, shift: Bool = false) -> String {
		diffView?.pressAtForTesting(row: row, x: x, clicks: clicks, shift: shift) ?? "no diff view"
	}

	func dragDiffForTesting(row: Int, x: Int) -> String {
		diffView?.dragToForTesting(row: row, x: x) ?? "no diff view"
	}

	/// What is selected in the diff, whichever of the two selections it is.
	func diffSelectionForTesting() -> String {
		diffView?.selectionForTesting() ?? "no diff view"
	}

	/// A double-click and a triple-click over the diff.
	func selectDiffWordForTesting(row: Int, offset: Int) -> String {
		diffView?.selectWordForTesting(row: row, offset: offset) ?? "no diff view"
	}

	func selectDiffRowTextForTesting(row: Int) -> String {
		diffView?.selectRowTextForTesting(row: row) ?? "no diff view"
	}

	/// ⌘A over the diff.
	func selectAllDiffTextForTesting() -> String {
		diffView?.selectAllTextForTesting() ?? "no diff view"
	}

	/// Selects whole lines by number, the way a drag down the numbers does.
	func selectDiffLinesForTesting(from: Int, to: Int) -> String {
		guard let diffView else { return "no diff view" }
		diffView.selectLinesForTesting(from: from, to: to)
		return "\(diffView.selectedLines.count) lines"
	}

	/// What ⌘C would copy, and — only where a step asks for it by name — what
	/// pressing it puts on the clipboard.
	func copiedDiffTextForTesting() -> String {
		diffView?.copiedTextForTesting() ?? "no diff view"
	}

	func copyDiffTextForTesting() -> String {
		diffView?.copyToPasteboardForTesting() ?? "no diff view"
	}

	/// What a drag down the whole diff costs beside a draw of it.
	func diffTimingForTesting() -> String {
		diffView?.timingForTesting() ?? "no diff view"
	}

	/// Moves the keyboard between the diff and the file list beside it, so a run
	/// can photograph a selection with the keys somewhere else — which is the
	/// grey a selection is drawn in when it is not where the next key goes.
	func focusForTesting(_ what: String) -> String {
		guard let diffView else { return "no diff view" }
		window?.makeFirstResponder(what == "diff" ? diffView : unstagedTable)
		return keyboardReportForTesting()
	}

	/// A theme change at the diff's own door, which is where the rows it has
	/// measured are dropped.
	func applyDiffThemeForTesting() -> String {
		guard let diffView else { return "no diff view" }
		diffView.applyThemeChange()
		return "\(diffView.measuredRowsForTesting) rows measured"
	}

	/// ⌘C at the real menu bar, with the keyboard in the diff and then in the
	/// file list beside it.
	///
	/// **The whole path rather than the view's own `copy(_:)`.** The Edit menu's
	/// *Copy* has no target, so it is the responder chain that has to reach the
	/// diff and `validateMenuItem` that has to enable it; a run that called the
	/// method would prove neither. The press itself is the one AppKit says
	/// reaches that item on this keyboard layout — see `MenuKeyReport`, and
	/// 0479, which is why it is measured rather than assumed.
	///
	/// The clipboard is put back as it was found: it belongs to whoever is using
	/// this machine, and a report is not a reason to take away what they had
	/// copied.
	func copyKeyReportForTesting() -> String {
		guard let diffView else { return "no diff view" }
		let selector = #selector(NSText.copy(_:))
		let items = (NSApp.mainMenu?.items ?? [])
			.compactMap(\.submenu)
			.flatMap(\.items)
			.filter { $0.action == selector }
		guard let item = items.first else { return "no Copy in the menu bar" }

		let theirs = NSPasteboard.general.string(forType: .string)
		defer {
			NSPasteboard.general.clearContents()
			if let theirs { NSPasteboard.general.setString(theirs, forType: .string) }
		}

		func enabled() -> Bool {
			guard let target = NSApp.target(forAction: selector, to: nil, from: item) else {
				return false
			}
			guard let validator = target as? NSMenuItemValidation else { return true }
			return validator.validateMenuItem(item)
		}

		var said: [String] = []
		let places: [(String, NSResponder)] = [("the diff", diffView), ("the file list", unstagedTable)]
		for (who, responder) in places {
			window?.makeFirstResponder(responder)
			NSPasteboard.general.clearContents()
			var answered = false
			for (_, event) in MenuKeyReport.presses(reaching: item) {
				answered = NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
				if answered { break }
			}
			let written = NSPasteboard.general.string(forType: .string) ?? ""
			let first = written.split(separator: "\n", omittingEmptySubsequences: false).first ?? ""
			said.append("keyboard in \(who): Copy \(enabled() ? "enabled" : "disabled")"
				+ ", ⌘C \(answered ? "answered" : "reached nothing")"
				+ ", clipboard \(written.isEmpty ? "empty" : "holds |\(first)|")")
		}
		return said.joined(separator: "\n")
	}

	/// Every row of the diff, numbered, as a `text:` step names them.
	func diffRowsForTesting() -> String {
		diffView?.rowTextsForTesting() ?? "no diff view"
	}

	/// What the menu over the diff holds, in order.
	func diffMenuForTesting() -> String {
		diffView?.menuTitlesForTesting() ?? "no diff view"
	}

	/// What the diff says a point is over, either side of every boundary.
	func diffRegionsForTesting(row: Int) -> String {
		diffView?.regionsForTesting(row: row) ?? "no diff view"
	}

	/// How many of the diff's rows have been measured for a selection.
	func diffMeasuredRowsForTesting() -> String {
		guard let diffView else { return "no diff view" }
		return "\(diffView.measuredRowsForTesting) rows measured"
	}

	/// Stages the first `count` changed lines of the diff on screen.
	func stageLinesForTesting(_ count: Int) -> String {
		diffView?.applyFirstLinesForTesting(count) ?? "no diff view"
	}

	func rowsForTesting() -> String {
		func lines(_ nodes: [GitChangeNode], depth: Int) -> [String] {
			nodes.flatMap { node -> [String] in
				var marks: [String] = []
				if node.isRepository { marks.append("[repo]") }
				if node.gitlink != nil { marks.append("[moved]") }
				// A folder's tally is the pane's own arithmetic and still
				// reads. A file's `+n/-n` does not: nothing asks git for it
				// any more, so it would be nil on every row.
				let tally = node.isFolder
					? (node.isPartial ? " \(node.count) of \(node.total)" : " \(node.count)")
					: ""
				let line = String(repeating: "  ", count: depth)
					+ node.name + tally
					+ (marks.isEmpty ? "" : " " + marks.joined(separator: " "))
				return [line] + lines(node.children, depth: depth + 1)
			}
		}
		return (["unstaged:"] + lines(unstagedSide.roots, depth: 1)
			+ ["staged:"] + lines(stagedSide.roots, depth: 1)).joined(separator: "\n")
	}

	/// **What is on screen, so it says only what is drawn.** The rows carried
	/// `+3/-1` here while they still carried it on screen; the counters are
	/// gone from the pane, and a report that kept them would pass over the
	/// change it exists to catch. `rowsForTesting` is the other report and
	/// still says them, because that one is about the tree this pane built
	/// rather than about the pane.
	func changesTreeForTesting() -> String {
		var lines: [String] = []
		for (title, outline) in [("Unstaged", unstagedTable!), ("Staged", stagedTable!)] {
			lines.append("\(title) (\(outline.numberOfRows) rows)")
			for row in 0..<outline.numberOfRows {
				guard let node = outline.item(atRow: row) as? GitChangeNode else { continue }
				let indent = String(repeating: "  ", count: outline.level(forRow: row) + 1)
				let selected = outline.selectedRowIndexes.contains(row) ? " <-" : ""
				if node.holdsFiles {
					// A folder this pane invented says how much of it is on this
					// side. A wholly untracked directory says what it is instead:
					// git reports it as one entry, so a count would be a 1 that
					// means something different from every other 1 in this tree.
					let tally = node.isFolder
						? (node.isPartial ? "\(node.count) of \(node.total)" : "\(node.count)")
						: (node.isFilled ? "untracked folder" : "untracked folder, not opened")
					let shut = outline.isItemExpanded(node) ? "" : " [shut]"
					// The tally is the pane's own arithmetic and still reads
					// here: it is what the folder's tool tip says, and a driven
					// run is the only way to ask for it.
					lines.append("\(indent)\(node.name)/  \(tally)\(shut)\(selected)")
				} else {
					lines.append("\(indent)\(node.name)\(selected)")
				}
			}
		}
		return lines.joined(separator: "\n")
	}

	/// The history menu's entries, printed the way the menu would show them,
	/// and asynchronously — the log is read when the menu opens, so the driver
	/// settles before reading the answer.
	/// What the draft would ask for, without a `claude` on the machine and
	/// without sending anything: the format is the claim, and the prompt is
	/// where it is either stated or not.
	func draftAskForTesting() {
		let conventional = Settings.shared.conventionalCommitDrafts
		Task { @MainActor in
			guard let ask = await ClaudeDraft.ask(in: self.root, conventional: conventional) else {
				print("CHANGES draft-ask: nothing staged")
				fflush(stdout)
				return
			}
			// The diff is not printed: it is the half that is somebody's code,
			// and the claim is about the words around it.
			let words = ask.prompt.components(separatedBy: "The staged diff:").first ?? ""
			print("CHANGES draft-ask conventional=\(conventional):\n"
				+ words.split(separator: "\n", omittingEmptySubsequences: false)
					.map { "  " + $0 }.joined(separator: "\n"))
			fflush(stdout)
		}
	}

	func messageHistoryForTesting() {
		Task { @MainActor in
			let commits = await GitHistory.log(in: self.root, limit: 20)
			print("CHANGES history:\n"
				+ commits.map { "  " + Self.historyTitle(for: $0) }.joined(separator: "\n"))
			fflush(stdout)
		}
	}

	/// Fills from the numbered entry as choosing it would, and prints what the
	/// fields hold afterwards — the fill is the claim.
	func useHistoryEntryForTesting(_ index: Int) {
		Task { @MainActor in
			let commits = await GitHistory.log(in: self.root, limit: 20)
			guard commits.indices.contains(index) else {
				print("CHANGES history: no entry \(index)")
				fflush(stdout)
				return
			}
			self.fill(subject: commits[index].subject, body: commits[index].body)
			print("CHANGES history used: subject=\(self.subjectField.stringValue.debugDescription)"
				+ " body=\(self.bodyView.string.debugDescription)")
			fflush(stdout)
		}
	}

	/// Selects one row the way a first click does — the deferred diff render
	/// included — so the double-click shape can be driven from outside.
	func selectForTesting(path: String, staged: Bool) {
		let outline = staged ? stagedTable! : unstagedTable!
		// **By row and not only by `byPath`.** The children of an untracked
		// directory are put under their row when the listing comes back and are
		// never added to `byPath`, which is built from what git reported — so
		// the one shape the selection reports were about could not be driven at
		// all. Walking the rows finds what is on screen, which is what a person
		// clicking has.
		let row = side(for: outline).byPath[path].map { outline.row(forItem: $0) }
			?? (0..<outline.numberOfRows).first {
				(outline.item(atRow: $0) as? GitChangeNode)?.path == path
			} ?? -1
		guard row >= 0 else {
			print("CHANGES select: no row at \(path)")
			return
		}
		outline.selectRowIndexes([row], byExtendingSelection: false)
	}

	/// Selects the rows whose paths these are, in the named list, and stages or
	/// unstages them — the keyboard's gesture, driven from outside.
	func stageForTesting(paths: [String], staged: Bool) {
		let outline = staged ? stagedTable! : unstagedTable!
		let side = self.side(for: outline)
		let rows = TreeSelection.rows(for: paths) { path in
			// The same reach as `selectForTesting`: an untracked directory's
			// children are rows and are not in `byPath`.
			side.byPath[path].map { outline.row(forItem: $0) }
				?? (0..<outline.numberOfRows).first {
					(outline.item(atRow: $0) as? GitChangeNode)?.path == path
				} ?? -1
		}
		guard !rows.isEmpty else { return }
		outline.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
		// What git is actually given, which is the claim worth printing: a
		// screenshot of the tree afterwards cannot show whether the folder went
		// as one argument or as forty.
		print("CHANGES \(staged ? "unstage" : "stage"): "
			+ GitChangeTree.reduce(selectedPaths(in: outline)).joined(separator: " "))
		if staged { unstageSelected() } else { stageSelected() }
	}

	/// What the menu would offer over a row and what the confirmation would say,
	/// as lines.
	///
	/// The whole of what this entry had to decide is wording and counting, and a
	/// screenshot of a menu cannot be asked whether the number in it is right. A
	/// staged row answers "not offered", which is the claim that is hardest of
	/// all to see in a picture.
	func discardWordingForTesting(path: String, staged: Bool) -> String {
		let side = staged ? stagedSide : unstagedSide
		guard let node = side.byPath[path] else { return "DISCARD \(path): no such row" }
		guard !staged, let target = discardable(node: node) else {
			return "DISCARD \(path): not offered"
		}
		return [
			"DISCARD \(path)",
			"  menu: " + target.menuTitle,
			"  asks: " + target.question,
			"  says: " + target.explanation,
			"  button: " + target.buttonTitle,
			"  git: " + target.paths.joined(separator: " "),
		].joined(separator: "\n")
	}

	/// Goes through with a discard over a row, as pressing the confirmation's
	/// button does. The sheet is what is skipped, and nothing else.
	func discardForTesting(path: String) {
		guard let node = unstagedSide.byPath[path], let target = discardable(node: node) else {
			print("DISCARD \(path): not offered")
			return
		}
		print("DISCARD \(path): " + target.paths.joined(separator: " "))
		performDiscard(target)
	}

	/// Folds a folder shut or open, so a refresh can be asked what it did with
	/// it — and so that reopening one by hand can be asked whether what is
	/// inside it came back open too.
	func setExpandedForTesting(path: String, expanded: Bool, staged: Bool) {
		let outline = staged ? stagedTable! : unstagedTable!
		guard let node = side(for: outline).byPath[path] else { return }
		if expanded { outline.expandItem(node) } else { outline.collapseItem(node) }
	}

	/// **This existed and nothing called it.** Written to re-take the pane's
	/// type on a theme change, and never wired to anything — so the commit page
	/// followed a zoom only where the sidebar rebuilt it, and the page in a tab
	/// did not follow at all. It is on the library's one path now, which is the
	/// point of there being one.
	func applyTheme() {
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		subjectField.font = Theme.current.uiFont(12, weight: .medium)
		bodyView.font = Theme.current.uiFont(12)
		// **The placeholder keeps the font it was set with.** `NSTextField`
		// renders it from the font in force at the moment it was assigned, so
		// a field whose font has just grown draws "Summary" at the old size —
		// the one part of the commit page that did not follow, and reported as
		// exactly that. Setting it again is the whole fix.
		let placeholder = subjectField.placeholderString
		subjectField.placeholderString = nil
		subjectField.placeholderString = placeholder
		// A zoom changes the indent as well as the type, and through `reload`
		// so that the trees come back open where they were open.
		unstagedTable.indentationPerLevel = Theme.current.scaled(14)
		stagedTable.indentationPerLevel = Theme.current.scaled(14)
		reload()
	}
}
