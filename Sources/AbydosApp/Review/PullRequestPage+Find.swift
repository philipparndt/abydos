import AppKit
import AbydosKit

/// ⌘F over the diff, and the switch between one column and two.
///
/// **The editor's own find bar**, find-only: the same field, the same three
/// switches, the same `n of m`. Two bars that look alike and differ in their keys
/// or their wording are the thing this avoids. What it searches, and how a
/// search survives the rows under it being rebuilt, is `DiffView+Search`.
///
/// A file of its own because the page was 874 lines of 1,100 before it had a
/// bar, and the wiring here is nothing the rest of the page needs to read.
extension PullRequestPage {
	/// The diff's half of the split: the bar, when it is up, over the scroll
	/// view. A plain view holding both, because a split view's child should have
	/// no intrinsic height and the bar has one.
	func makeDiffSide() -> NSView {
		findBar = FindBar()
		findBar.isHidden = true
		findBar.onQueryChanged = { [weak self] query, options in
			self?.diffView.search(for: query, options: options)
		}
		findBar.onNext = { [weak self] in self?.diffView.stepMatch(by: 1) }
		findBar.onPrevious = { [weak self] in self?.diffView.stepMatch(by: -1) }
		findBar.onClose = { [weak self] in self?.closeFind() }
		diffView.onMatchesChanged = { [weak self] in self?.sayMatches() }

		let side = NSView()
		for view in [findBar, diffScroll] as [NSView] {
			side.addSubview(view)
			view.translatesAutoresizingMaskIntoConstraints = false
		}
		findBarHeight = findBar.heightAnchor.constraint(equalToConstant: 0)
		NSLayoutConstraint.activate([
			findBar.topAnchor.constraint(equalTo: side.topAnchor),
			findBar.leadingAnchor.constraint(equalTo: side.leadingAnchor),
			findBar.trailingAnchor.constraint(equalTo: side.trailingAnchor),
			findBarHeight,
			diffScroll.topAnchor.constraint(equalTo: findBar.bottomAnchor),
			diffScroll.leadingAnchor.constraint(equalTo: side.leadingAnchor),
			diffScroll.trailingAnchor.constraint(equalTo: side.trailingAnchor),
			diffScroll.bottomAnchor.constraint(equalTo: side.bottomAnchor),
		])
		return side
	}

	var findIsShowing: Bool { !findBar.isHidden }

	// MARK: - The responder chain

	/// ⌘F, from anywhere on the page — the file list as much as the diff.
	///
	/// **Answered here, inside the responder chain**, as the settings page and
	/// the branches pane answer it. Left to fall through, it reached the window
	/// controller, which asked the editor for a code view the page does not
	/// have, and the key did nothing at all.
	@objc func findInFile(_ sender: Any?) {
		showFind()
	}

	@objc func findNext(_ sender: Any?) {
		guard findIsShowing else { return showFind() }
		diffView.stepMatch(by: 1)
	}

	@objc func findPrevious(_ sender: Any?) {
		guard findIsShowing else { return showFind() }
		diffView.stepMatch(by: -1)
	}

	/// ⎋ with the keyboard in the diff or the list rather than in the field,
	/// which the bar answers itself.
	override func cancelOperation(_ sender: Any?) {
		guard findIsShowing else { return super.cancelOperation(sender) }
		closeFind()
	}

	// MARK: - The bar

	func showFind() {
		findBar.setReplacing(false)
		findBar.isHidden = false
		findBarHeight.constant = findBar.wantedHeight
		// Seeded from the diff's selection, as the editor's is from the
		// caret's: the word a reviewer just double-clicked is the word they
		// mean. Not a selection over several lines, which is not a query.
		if let selected = diffView.copiedText, !selected.isEmpty, !selected.contains("\n") {
			findBar.setQuery(selected)
		} else {
			diffView.search(for: findBar.query, options: findBar.options)
		}
		findBar.focusField()
	}

	func closeFind() {
		findBar.isHidden = true
		findBarHeight.constant = 0
		diffView.endSearch()
		window?.makeFirstResponder(diffView)
	}

	private func sayMatches() {
		guard findIsShowing else { return }
		findBar.setStatus(matchCount: diffView.matches.count, currentIndex: diffView.currentMatch)
	}

	// MARK: - Side by side

	/// The switch, which is the View menu's preference and not one of its own:
	/// two answers to whether a diff is side by side leave the changes pane and
	/// the review disagreeing about what a diff looks like.
	func makeSideBySideSwitch() -> DrawnCheckbox {
		let made = DrawnCheckbox(title: "Side by side") { [weak self] in
			guard let self else { return }
			Settings.shared.diffIsSideBySide = self.sideBySideSwitch.state == .on
		}
		made.state = Settings.shared.diffIsSideBySide ? .on : .off
		made.toolTip = "The old file on the left and the new on the right, rather than one column"
		// Followed rather than only set: the View menu flips the same
		// preference, and a switch that does not move with it lies about what
		// the diff beside it is showing.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(sideBySideMoved),
			name: .abydosSettingsChanged,
			object: nil
		)
		return made
	}

	@objc private func sideBySideMoved() {
		let state: NSControl.StateValue = Settings.shared.diffIsSideBySide ? .on : .off
		guard sideBySideSwitch.state != state else { return }
		sideBySideSwitch.state = state
	}

	// MARK: - Driving

	/// `find:<query>` — ⌘F, then the query typed.
	func findForTesting(_ query: String) -> String {
		showFind()
		findBar.setQuery(query)
		return findReportForTesting()
	}

	/// What the bar says and what the diff says is current.
	func findReportForTesting() -> String {
		guard findIsShowing else { return "bar hidden; \(diffView.searchReportForTesting)" }
		return "\(findBar.statusReportForTesting); \(diffView.searchReportForTesting)"
	}

	/// ⌘F as the menu sends it: down the responder chain from whatever has the
	/// keyboard — the file list, or the diff — rather than by calling
	/// `showFind`, which would prove only that the method exists. Then ⎋ the
	/// same way, from the field the bar put the keyboard in.
	func pressFindForTesting(fromDiff: Bool) -> String {
		guard let window else { return "no window" }
		if fromDiff {
			window.makeFirstResponder(diffView)
		} else {
			window.makeFirstResponder(self)
			focusList()
		}
		let from = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nothing"
		let handled = window.firstResponder?.tryToPerform(
			#selector(MainWindowController.findInFile(_:)), with: nil
		) ?? false
		let focused = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nothing"
		return "from=\(from) handled=\(handled) keyboard=\(focused) \(findReportForTesting())"
	}

	func stepFindForTesting(by delta: Int) -> String {
		if delta > 0 { findNext(nil) } else { findPrevious(nil) }
		return findReportForTesting()
	}

	func closeFindForTesting() -> String {
		closeFind()
		return findReportForTesting()
	}

	/// `side-by-side:on` — press the page's switch if it does not already say so.
	func setSideBySideForTesting(_ on: Bool) -> String {
		if (sideBySideSwitch.state == .on) != on { sideBySideSwitch.performClick(nil) }
		return "switch=\(sideBySideSwitch.state == .on ? "on" : "off")"
			+ " setting=\(Settings.shared.diffIsSideBySide ? "on" : "off")"
			+ " top=\(diffView.topPlace().map { ($0.isOld ? "old " : "new ") + "\($0.number)" } ?? "-")"
	}

	/// View ▸ Diff ▸ Side by Side Diff, the real item out of the main menu:
	/// validated as the menu would be before it opens, and chosen when asked —
	/// so the tick is read the way somebody would see it, not off the setting.
	func sideBySideMenuForTesting(choosing: Bool) -> String {
		let action = #selector(MainWindowController.toggleSideBySideDiff(_:))
		func find(in menu: NSMenu?) -> NSMenuItem? {
			for item in menu?.items ?? [] {
				if item.action == action { return item }
				if let found = find(in: item.submenu) { return found }
			}
			return nil
		}
		guard let item = find(in: NSApp.mainMenu),
		      let controller = window?.windowController as? MainWindowController
		else { return "no menu item or no window" }
		if choosing { controller.toggleSideBySideDiff(item) }
		_ = controller.validateMenuItem(item)
		return "menu=\(item.state == .on ? "ticked" : "unticked")"
			+ " switch=\(sideBySideSwitch.state == .on ? "on" : "off")"
	}

	// MARK: - Sideways, for driving

	/// `sideways:right=200`, `sideways:left=end`, `sideways:only=0` — a column
	/// put at an offset as its scroller would put it.
	func sidewaysForTesting(_ argument: String) -> String {
		let parts = argument.split(separator: "=").map(String.init)
		guard parts.count == 2, let column = Self.column(named: parts[0]) else { return "say left=200" }
		let value = parts[1] == "end" ? diffView.maxSidewaysOffset(of: column) : CGFloat(Double(parts[1]) ?? 0)
		diffView.setSidewaysOffset(value, of: column)
		return diffView.sidewaysReportForTesting
	}

	/// `swipe:left=-120` — a real horizontal scroll event, built from a
	/// `CGEvent` and delivered to the diff at the middle of that column, so what
	/// is checked is the wheel path and not the setter behind it.
	func swipeForTesting(_ argument: String) -> String {
		let parts = argument.split(separator: "=").map(String.init)
		guard parts.count == 2, let column = Self.column(named: parts[0]),
		      let window, let points = Int32(parts[1])
		else { return "say left=-120" }
		let area = diffView.textArea(of: column)
		let inView = NSPoint(x: (area.lowerBound + area.upperBound) / 2, y: diffView.visibleRect.midY)
		let onScreen = window.convertPoint(toScreen: diffView.convert(inView, to: nil))
		let screenHeight = NSScreen.screens.first?.frame.height ?? 0
		guard let made = CGEvent(
			scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: points, wheel3: 0
		) else { return "no event" }
		made.location = CGPoint(x: onScreen.x, y: screenHeight - onScreen.y)
		guard let event = NSEvent(cgEvent: made) else { return "no event" }
		diffView.scrollWheel(with: event)
		return diffView.sidewaysReportForTesting
	}

	func sidewaysLinkForTesting() -> String {
		diffView.sidewaysBar?.pressLinkForTesting()
		return diffView.sidewaysReportForTesting
	}

	func sidewaysStatusForTesting() -> String { diffView.sidewaysReportForTesting }

	func sidewaysTimingForTesting() -> String { diffView.measureTimingForTesting() }

	/// `edge-click:right.1` — double-click two characters in from the visible
	/// left edge of that column's text on that row.
	func edgeClickForTesting(_ argument: String) -> String {
		let parts = argument.split(separator: ".").map(String.init)
		guard parts.count == 2, let column = Self.column(named: parts[0]), let row = Int(parts[1]) else {
			return "say right.1"
		}
		return diffView.doubleClickAtLeftEdgeForTesting(row: row, column: column)
	}

	private static func column(named name: String) -> DiffTextRun.Column? {
		switch name {
		case "left":  return .left
		case "right": return .right
		case "only":  return .only
		default:      return nil
		}
	}

	/// Scrolls the diff so that row is at the top, for a run that needs to be
	/// half-way down a file before it switches.
	func scrollDiffForTesting(toRow row: Int) -> String {
		diffView.scroll(NSPoint(x: 0, y: diffView.rowsTop + CGFloat(row) * diffView.lineHeight))
		return "top=\(diffView.topPlace().map { ($0.isOld ? "old " : "new ") + "\($0.number)" } ?? "-")"
	}
}
