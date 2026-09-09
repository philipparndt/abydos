import AppKit
import AbydosKit

/// Driving the log from a script, which is how the pane is checked without a
/// person clicking through it.
///
/// The steps live here rather than on the controller that owns the page, the
/// way the pull request list drives itself: every one of them is a question
/// about this pane's own state.
extension HistoryPane {
	/// Runs a driver's comma-separated step script against this pane. The
	/// steps live here rather than on the controller that owns the page, the
	/// way the pull request list drives itself: every one of them is a
	/// question or a verb of this pane's, and the controller's part is only
	/// to have the page and wait for its first rows.
	func driveForTesting(_ steps: String) {
		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			// The diff of a file is read off the main queue like everything
			// else here, so a report taken in the same turn as the selection
			// sees the state before it.
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.driveForTesting(rest)
				}
				return
			}

			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "report": print("LOG-PAGE:\n\(pageReportForTesting())")
			// Folds or unfolds the merge on a row, so the graph after a fold is
			// something a run can read rather than something to look at.
			case "fold":   print("LOG-PAGE fold: \(toggleCollapseForTesting(row: Int(argument) ?? 0))")
			// Narrow to one ref, the way a branch row's "show log" does: the
			// scoped log is where the upstream's unpulled commits appear, and a
			// driver that can only open the everything-log could not ask about
			// them. Follow with `settle` — the reload is asynchronous.
			case "scope":  setRef(argument.isEmpty ? nil : argument)
			// Narrow to one file, the way Compare ▸ History… arrives.
			case "path":
				offerScope(path: argument.isEmpty ? nil : argument)
				setScope(path: argument.isEmpty ? nil : argument)
			case "verbs":  print("LOG-PAGE verbs: \(diffVerbsForTesting())")
			case "menu":   print("LOG-PAGE-MENU:\n\(commitMenuForTesting(row: Int(argument) ?? 0))")
			// `choose:<row>:<title>` fires that row's menu item by title, the
			// way a person picking Compare with Working Copy does.
			case "choose":
				let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
				if parts.count == 2, let row = Int(parts[0]) {
					print("LOG-PAGE choose: \(chooseCommitMenuItemForTesting(row: row, titled: parts[1]))")
				} else {
					print("LOG-PAGE choose: wants row:title, got \(argument)")
				}
			case "file":
				selectCommitForTesting(0)
				selectFileForTesting(Int(argument) ?? 0)
			// The changes view's own rows, which `report` does not carry: how a
			// commit's files are arranged is the question, and the flat
			// arrangement has to match what the page drew before it was an
			// outline at all.
			// The keyboard's own claims: a click gives the list focus, the
			// arrows move, and ← and → shut and open without losing the row.
			case "keys":
				print("LOG-PAGE keys: " + fileKeysForTesting(argument))
				fflush(stdout)
			case "files":
				print("LOG-PAGE files:\n  " + fileRowsForTesting().joined(separator: "\n  "))
			case "arrange": toggleFileArrangementForTesting()
			case "star":    pressStarForTesting()
			// The same diff steps the commit page has, spelled the same way —
			// a commit's diff is the read-only one, and it is where *Copy* has
			// to be offered over a diff nothing can be staged from.
			case "diff-rows":
				print("LOG-PAGE diff rows:\n" + diffRowsForTesting())
			case "text":
				let ends = argument.split(separator: "-").map { end -> (Int, Int) in
					let place = end.split(separator: ".").compactMap { Int($0) }
					return (place.first ?? 0, place.count > 1 ? place[1] : 0)
				}
				guard let first = ends.first, let last = ends.last else { break }
				print("LOG-PAGE text: " + selectDiffTextForTesting(
					fromRow: first.0, offset: first.1, toRow: last.0, offset: last.1
				))
			case "copied":
				print("LOG-PAGE copied:\n" + copiedDiffTextForTesting())
			case "copy":
				print("LOG-PAGE copy:\n" + copyDiffTextForTesting())
			case "diff-menu":
				print("LOG-PAGE diff menu: " + diffMenuForTesting())
			case "shut":    collapseEveryFolderForTesting()
			// A script that says so ends the run, as the commit page's does:
			// whatever is waiting on the process gets an exit rather than
			// having to kill it, and an exit is the one ending that flushes.
			case "exit":   fflush(stdout); exit(0)
			default:       print("LOG-PAGE: unknown step \(step)")
			}
		}
		fflush(stdout)
	}

	/// What the page is showing, on both sides of its split.
	///
	/// The claim is that a page holds what a column cannot: the graph with
	/// lanes and refs on one side, and the selected commit's files *and its
	/// diff* on the other rather than in a tab somewhere else.
	/// Lines drawn on a row that nothing above it hands down.
	///
	/// **The claim a folded merge is under.** A lane leaves a row through an
	/// edge and arrives at the next one; a line whose `from` lane is neither
	/// this row's own dot nor something the row above passed down is a line
	/// starting in nowhere — which is what folding used to leave behind, when
	/// the graph was laid out over every commit and the rows were filtered
	/// afterwards. Counted rather than drawn, so a run can assert zero.
	func danglingLanesForTesting() -> Int {
		var carried: Set<Int> = []
		var dangling = 0
		for row in visible {
			guard let graph = row.graph else { continue }
			for edge in graph.edges where edge.from != graph.lane && !carried.contains(edge.from) {
				dangling += 1
			}
			carried = Set(graph.edges.map(\.to))
		}
		return dangling
	}

	func pageReportForTesting() -> String {
		var said = ["layout=\(arrangement == .page ? "page" : "sidebar")"]
		// Which segment is lit, because Compare ▸ History…'s claim is that it
		// lands on "This File" — a state a screenshot of a segmented control
		// says less reliably than the control itself.
		let scope = scopeControl.selectedIndex == 1
			? (scopeControl.label(forSegment: 1) ?? "file") : "whole"
		said.append("scope=\(scope)")
		said.append("commits=\(visible.count)")
		said.append("dangling=\(danglingLanesForTesting())")
		said += visible.prefix(6).map { row in
			let lanes = row.graph.map { "lane \($0.lane)" } ?? "no graph"
			// Dimming is a drawing, and a driven run reads text: the marker is
			// how a test can say which rows are the unpulled ones.
			let side = remoteOnly.contains(row.commit.hash) ? " remote-only" : ""
			let refs = row.commit.refs.isEmpty
				? ""
				: " [" + row.commit.refs.joined(separator: ", ") + "]"
			return "  \(row.commit.shortHash) \(lanes)\(side) \(row.commit.authorName)\(refs) \(row.commit.subject)"
		}
		said.append("files=\(files.count)")
		said += files.prefix(6).map { "  \($0.path)" }
		said.append("diff=\(diffDocuments?.reportForTesting ?? diffView?.reportForTesting ?? "none")")
		return said.joined(separator: "\n")
	}

	/// Whether the log has anything in it yet.
	/// What the menu over the log page's diff offers — see
	/// `DiffView.verbsForTesting`. A commit has already happened, so the answer
	/// is that it offers nothing to stage or throw away.
	func diffVerbsForTesting() -> String {
		diffView?.verbsForTesting() ?? "no diff view"
	}

	/// Every row of the diff, numbered, as a `text:` step names them — and what
	/// a gesture over it selects and copies. A commit's diff is read-only, so
	/// this is the other half of the claim the commit page checks: *Copy* is
	/// offered over a diff nothing can be staged from either.
	func diffRowsForTesting() -> String {
		diffView?.rowTextsForTesting() ?? "no diff view"
	}

	func selectDiffTextForTesting(
		fromRow: Int, offset from: Int, toRow: Int, offset to: Int
	) -> String {
		diffView?.selectTextForTesting(
			fromRow: fromRow, offset: from, toRow: toRow, offset: to
		) ?? "no diff view"
	}

	func copiedDiffTextForTesting() -> String {
		diffView?.copiedTextForTesting() ?? "no diff view"
	}

	func copyDiffTextForTesting() -> String {
		diffView?.copyToPasteboardForTesting() ?? "no diff view"
	}

	func diffMenuForTesting() -> String {
		diffView?.menuTitlesForTesting() ?? "no diff view"
	}

	var hasRowsForTesting: Bool { !visible.isEmpty }

	/// What the menu over a commit offers, one item per line.
	///
	/// The list is the claim — that a commit has verbs at all, and that the one
	/// which can lose work is fenced off from the ones that cannot — and a list
	/// diffs where a photograph of an open menu does not.
	/// Fires one of the commit menu's items by title, through the same menu
	/// `menu:` reports, so the verb is proven to be *in* the menu rather than
	/// merely behind a method the driver knows.
	func chooseCommitMenuItemForTesting(row: Int, titled title: String) -> String {
		guard visible.indices.contains(row) else { return "no such row" }
		commitTable.selectRowIndexes([row], byExtendingSelection: false)
		let menu = NSMenu()
		menu.delegate = self
		menuNeedsUpdate(menu)
		guard let item = menu.items.first(where: { $0.title == title }) else {
			return "\(title) is not in the menu"
		}
		guard let action = item.action, let target = item.target else {
			return "\(title) has no action"
		}
		_ = NSApp.sendAction(action, to: target, from: item)
		return "fired \(title)"
	}

	func commitMenuForTesting(row: Int) -> String {
		guard visible.indices.contains(row) else { return "no such row" }
		commitTable.selectRowIndexes([row], byExtendingSelection: false)
		let menu = NSMenu()
		menu.delegate = self
		menuNeedsUpdate(menu)
		return menu.items
			.map { $0.isSeparatorItem ? "--" : $0.title }
			.joined(separator: "\n")
	}

	func setQueryForTesting(_ text: String) {
		searchField.stringValue = text
		query = text
		reload()
	}

	var commitSubjectsForTesting: [String] { commits.map(\.subject) }
	var fileNamesForTesting: [String] { files.map(\.path) }

	func selectCommitForTesting(_ index: Int) {
		guard commits.indices.contains(index) else { return }
		commitTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
	}

	func selectFileForTesting(_ index: Int) {
		fileList.select(index: index)
	}

	/// The rows as they are drawn, top to bottom, so a driven run can compare
	/// the two arrangements — and compare the flat one against what the page
	/// drew when its file list was a table.
	func fileRowsForTesting() -> [String] { fileList.rowsForTesting() }

	func fileArrangementChanged(to index: Int) {
		Settings.shared.commitFilesByFolder = index == 1
		fileList.arrangesByFolder = arrangesFilesByFolder
	}

	/// Draws the file list in whichever arrangement the preference now names.
	///
	/// The menu item flips the preference; this is the page catching up. Public
	/// because the window owns the menu and the page owns the rows.
	func applyFileArrangement() {
		arrangeControl?.selectedIndex = Settings.shared.commitFilesByFolder ? 1 : 0
		fileList.arrangesByFolder = arrangesFilesByFolder
	}

	/// Flips the arrangement, the way the menu item does.
	func toggleFileArrangementForTesting() {
		Settings.shared.commitFilesByFolder.toggle()
		applyFileArrangement()
	}

	func pressStarForTesting() { fileList.expandEveryFolder() }

	/// Works the commit's file list from the keyboard, and says what happened.
	func fileKeysForTesting(_ steps: String) -> String { fileList.keysForTesting(steps) }

	/// Shuts every folder, so `*` has something to do.
	func collapseEveryFolderForTesting() { fileList.collapseEveryFolder() }
}
