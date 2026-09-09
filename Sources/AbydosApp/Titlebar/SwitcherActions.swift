import AppKit
import AbydosKit

/// What a row does when it is chosen, and the keys that choose one without the
/// pointer ever leaving the filter field.
extension SwitcherViewController {
	// MARK: - Actions

	@objc func rowClicked() {
		activateRow(at: tableView.clickedRow)
	}

	func activateRow(at index: Int) {
		guard rows.indices.contains(index) else { return }
		switch rows[index] {
		case let .action(_, _, _, _, handler):
			handler()
		case .header:
			break
		case let .project(entry, _):
			onDismiss?()
			(NSApp.delegate as? AppDelegate)?.open(projectAt: entry.url, from: owner)
		case let .branch(branch, isCurrent):
			onDismiss?()
			// Checking out the branch already on is a slow way of doing nothing.
			guard !isCurrent, let root = currentProject?.root else { return }
			BranchMenu.checkout(branch, in: root)
		case let .file(path):
			onDismiss?()
			open(file: path)
		case let .run(configuration, _, _, _):
			onDismiss?()
			runs?.choose(configuration)
		case let .goal(goal):
			// **Opens, whichever way it was activated.** It used to run at the
			// reactor root on Return and open only on →, and that is one row
			// doing two different things depending on how you touched it: a
			// mouse has no →, so clicking a goal ran something instead of
			// showing the places, and the popover shut. Running at the root is
			// the first row inside instead, which costs one keystroke and is the
			// same for everybody.
			open(goal: goal)
		}
	}

	/// Opens a file from the list, or says why it could not be.
	///
	/// The index is mended by filesystem events and is briefly behind them, so
	/// a row can name a file that has since gone. Said rather than opened: an
	/// editor onto a deleted file is an empty window with a title, which reads
	/// as "the file is empty" and is a different and wrong answer.
	func open(file path: String) {
		guard let root = currentProject?.root else { return }
		let url = root.appendingPathComponent(path)
		guard FileManager.default.fileExists(atPath: url.path) else {
			Toast.post("That file is gone", detail: path)
			// The list said otherwise, so it is behind. It will be right the
			// next time the palette is opened.
			if let files = currentProject?.files {
				Task { await files.noticed(changed: [url]) }
			}
			return
		}
		// After the popover has gone, for the reason the menu actions give: a
		// window that takes the keyboard cannot do it while a popover holds it.
		DispatchQueue.main.async { [weak self] in
			self?.owner?.openFile(at: url)
		}
	}

	func newProject() {
		let panel = NSSavePanel()
		panel.title = "New Project"
		panel.prompt = "Create"
		panel.nameFieldLabel = "Project name:"
		panel.canCreateDirectories = true

		guard panel.runModal() == .OK, let url = panel.url else { return }
		do {
			try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			(NSApp.delegate as? AppDelegate)?.open(projectAt: url, from: owner)
		} catch {
			Toast.post("Could not open that folder", detail: error.localizedDescription)
		}
	}

	func cloneRepository() {
		let alert = NSAlert()
		alert.messageText = "Clone Repository"
		alert.informativeText = "Enter a repository URL. It will be cloned into a directory you choose."
		alert.addButton(withTitle: "Choose Location…")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
		field.placeholderString = "https://github.com/owner/repo.git"
		alert.accessoryView = field
		alert.window.initialFirstResponder = field

		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let remote = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !remote.isEmpty else { return }

		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.prompt = "Clone Here"
		guard panel.runModal() == .OK, let parent = panel.url else { return }

		// Derive the destination the way `git clone` would.
		let name = URL(fileURLWithPath: remote).deletingPathExtension().lastPathComponent
		let destination = parent.appendingPathComponent(name)

		Task {
			let result = await GitRepository.run(["clone", remote, destination.path], in: parent)
			await MainActor.run {
				if result.exitCode == 0 {
					(NSApp.delegate as? AppDelegate)?.open(projectAt: destination, from: owner)
				} else {
					Toast.post(
						"Clone failed",
						detail: result.stderr.isEmpty
							? "git exited with code \(result.exitCode)."
							: result.stderr
					)
				}
			}
		}
	}

	// MARK: - Keyboard

	/// Sends the field editor's command, and reports the row it left selected.
	func openGoalForTesting(_ name: String) -> [String] {
		guard let goal = runs?.arrangement.goals.first(where: { $0.name == name }) else {
			return ["no goal called \(name)"]
		}
		open(goal: goal)
		return rowsForTesting()
	}

	func rowsForTesting() -> [String] {
		rows.map { row in
			switch row {
			case let .header(title):            return "── \(title)"
			case let .branch(name, isCurrent):  return isCurrent ? "* \(name)" : "  \(name)"
			case let .project(entry, _):        return "project \(entry.name)"
			case let .action(title, _, _, _, _): return "action \(title)"
			case let .file(path):               return "file \(path)"
			case let .goal(goal):               return "goal \(goal.name) (\(goal.places))"
			case let .run(_, title, place, current):
				let where_ = place.map { "  [\($0)]" } ?? ""
				return "\(current ? "* " : "  ")\(title)\(where_)"
			}
		}
	}

	func pressForTesting(_ selector: Selector) -> String {
		let handled = control(filterField, textView: NSTextView(), doCommandBy: selector)
		let row = tableView.selectedRow
		let what = rows.indices.contains(row) ? describeForTesting(rows[row]) : "none"
		return "handled=\(handled) row=\(row) of \(rows.count): \(what)"
	}

	func describeForTesting(_ row: Row) -> String {
		switch row {
		case let .action(title, _, _, _, _): return "action \(title)"
		case let .header(title):             return "header \(title)"
		case let .project(project, _):       return "project \(project.path)"
		case let .branch(name, _):           return "branch \(name)"
		case let .file(path):                return "file \(path)"
		case let .goal(goal):                return "goal \(goal.name)"
		case let .run(run, _, place, _):     return "run \(run.name)\(place.map { " in \($0)" } ?? "")"
		}
	}

	/// Opens the modules of the goal under the selection. False when there is
	/// no goal there, so the key falls through to the field editor and the
	/// caret still moves through what has been typed.
	func openSelectedGoal() -> Bool {
		guard filterText.isEmpty, rows.indices.contains(tableView.selectedRow),
		      case let .goal(goal) = rows[tableView.selectedRow]
		else { return false }
		open(goal: goal)
		return true
	}

	/// Shows a goal's places, and puts the selection on the first of them
	/// rather than on the row that goes back.
	func open(goal: RunPicker.Goal) {
		openGoal = goal
		buildRows()
		tableView.reloadData()
		updatePreferredSize()
		let first = rows.firstIndex {
			if case .run = $0 { return true }
			return false
		}
		if let first {
			tableView.selectRowIndexes([first], byExtendingSelection: false)
			tableView.scrollRowToVisible(first)
		} else {
			selectFirstSelectableRow()
		}
	}

	func closeOpenGoal() -> Bool {
		guard openGoal != nil else { return false }
		let leaving = openGoal?.name
		openGoal = nil
		buildRows()
		tableView.reloadData()
		updatePreferredSize()
		// Back onto the goal that was left, rather than the top of the list.
		if let leaving, let index = rows.firstIndex(where: {
			if case let .goal(goal) = $0 { return goal.name == leaving }
			return false
		}) {
			tableView.selectRowIndexes([index], byExtendingSelection: false)
			tableView.scrollRowToVisible(index)
		} else {
			selectFirstSelectableRow()
		}
		return true
	}

	func selectFirstSelectableRow() {
		if let index = rows.firstIndex(where: { $0.isSelectable }) {
			tableView.selectRowIndexes([index], byExtendingSelection: false)
		}
	}

	/// Returns true when the event was consumed.
	func handleKeyDown(_ event: NSEvent) -> Bool {
		switch event.keyCode {
		case 36, 76: // Return, Keypad Enter
			activateRow(at: tableView.selectedRow)
			return true
		case 53: // Escape
			onDismiss?()
			return true
		case 125: // Down
			moveSelection(by: 1)
			return true
		case 126: // Up
			moveSelection(by: -1)
			return true
		case 124: // Right — open a goal's modules
			return openSelectedGoal()
		case 123: // Left — back out of one
			return closeOpenGoal()
		default:
			// Everything else belongs to the filter field.
			return false
		}
	}

	/// Moves the selection by that many *selectable* rows — headers are stepped
	/// over rather than landed on.
	func moveSelection(by delta: Int) {
		guard let index = ListSelection.move(
			from: tableView.selectedRow,
			by: delta,
			count: rows.count,
			isSelectable: { rows[$0].isSelectable }
		) else { return }

		tableView.selectRowIndexes([index], byExtendingSelection: false)
		tableView.scrollRowToVisible(index)
	}

	/// How far a page moves: what fits in the list, less one row of overlap so
	/// the place somebody was reading is still on screen afterwards.
	var pageSize: Int {
		ListSelection.pageSize(
			viewportHeight: tableView.enclosingScrollView?.contentSize.height ?? tableView.bounds.height,
			rowHeight: rows.first?.height ?? Theme.current.scaled(26)
		)
	}
}
