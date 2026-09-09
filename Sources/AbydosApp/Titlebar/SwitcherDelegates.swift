import AppKit
import AbydosKit

// MARK: - Table data

extension SwitcherViewController: NSSearchFieldDelegate {
	func controlTextDidChange(_ obj: Notification) {
		applyFilter(filterField.stringValue)
	}

	/// Arrows and Return work while the field has focus, so filtering and
	/// choosing are one continuous gesture.
	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		switch selector {
		case #selector(NSResponder.moveDown(_:)):
			moveSelection(by: 1)
			return true
		case #selector(NSResponder.moveUp(_:)):
			moveSelection(by: -1)
			return true
		// Both spellings: which one a key sends depends on the field it is sent
		// to, and a list that answers only one of them works in some places and
		// not others.
		case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)):
			moveSelection(by: pageSize)
			return true
		case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)):
			moveSelection(by: -pageSize)
			return true
		// ⌘↑ and ⌘↓ — the ends of the list, which is what somebody reaches for
		// after paging twice.
		case #selector(NSResponder.moveToBeginningOfDocument(_:)),
		     #selector(NSResponder.scrollToBeginningOfDocument(_:)):
			moveSelection(by: -rows.count)
			return true
		case #selector(NSResponder.moveToEndOfDocument(_:)),
		     #selector(NSResponder.scrollToEndOfDocument(_:)):
			moveSelection(by: rows.count)
			return true
		case #selector(NSResponder.insertNewline(_:)):
			activateRow(at: tableView.selectedRow)
			return true
		case #selector(NSResponder.moveRight(_:)):
			return openSelectedGoal()
		case #selector(NSResponder.moveLeft(_:)):
			return closeOpenGoal()
		case #selector(NSResponder.cancelOperation(_:)):
			// Escape leaves an opened goal first, then clears the filter, then
			// closes — undoing one thing per press, in the order they were done.
			if closeOpenGoal() { return true }
			if filterText.isEmpty {
				onDismiss?()
			} else {
				filterField.stringValue = ""
				applyFilter("")
			}
			return true
		default:
			return false
		}
	}
}

extension SwitcherViewController: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		rows[row].height
	}

	func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
		rows[row].isSelectable
	}

	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		SwitcherRowView()
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		switch rows[row] {
		case let .action(title, symbol, shortcut, detail, _):
			return SwitcherActionCell(title: title, symbol: symbol, shortcut: shortcut, detail: detail)
		case let .header(title):
			return SwitcherHeaderCell(title: title)
		case let .project(entry, isOpen):
			return SwitcherProjectCell(entry: entry, isOpen: isOpen, filter: filterText)
		case let .branch(name, isCurrent):
			return SwitcherBranchCell(name: name, isCurrent: isCurrent, filter: filterText)
		case let .file(path):
			return SwitcherFileCell(path: path, filter: filterText)
		case let .run(configuration, title, place, isCurrent):
			return SwitcherRunCell(
				title: title, place: place, chip: isCurrent ? "current" : nil,
				symbol: Self.symbol(for: configuration.source), filter: filterText
			)
		case let .goal(goal):
			return SwitcherRunCell(
				title: goal.name, place: nil, chip: "\(goal.places) places  \u{203A}",
				symbol: Self.symbol(for: goal.whenChosen?.source ?? .make), filter: filterText
			)
		}
	}
}
