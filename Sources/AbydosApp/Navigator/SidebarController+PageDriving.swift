import AppKit
import AbydosKit

/// Driving the pages: what the estate, the commit page, the pull requests and
/// the log say, step by step.
extension SidebarController {
	/// What the estate page says, row by row.
	func estateForTesting(_ steps: String, waiting: Int = 8) {
		if estatePage == nil { showEstatePage() }
		guard let page = estatePage else {
			print("ESTATE: no page")
			return
		}
		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			if step.hasPrefix("settle") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.estateForTesting(rest, waiting: waiting)
				}
				return
			}
			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "rows":   print("ESTATE rows:\n\(page.rowsForTesting())")
			case "filter": page.filterForTesting(argument)
			case "take":
				// `svc-1:theirs`, or `svc-1:<commit>` for a third one.
				let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
				if parts.count == 2 { page.resolveForTesting(path: parts[0], to: parts[1]) }
			default:       print("ESTATE: unknown step \(step)")
			}
		}
	}

	/// What the commit page holds, and what a gesture over its diff does.
	///
	/// The steps are a comma-separated script, as everywhere else here. Beside
	/// `report`, `rows`, `diff`, `verbs`, `stage`, `stage-lines`, `who`, `keys`,
	/// `select`, `type`, `chevron`, `return` and `exit`, the diff's own:
	///
	/// - `text:12.4-14.9` — drag over the text, from row 12 offset 4 to row 14
	///   offset 9, against the rows on screen; `text-left:` for the old-file half
	///   of a side-by-side diff
	/// - `word:12.20` — double-click there; `row-text:12` — triple-click that
	///   row; `all` — ⌘A over the diff
	/// - `select-lines:12-14` — whole lines by number, as a drag down the numbers
	///   makes them
	/// - `press:12@60` / `drag:14@60` — the gesture itself, at a point: row 12 at
	///   x 60 is the number column, x 160 is the code, and the answer says which
	///   of the two selections the press made. `press:15@160+shift` holds shift,
	///   which extends from where the gesture began
	/// - `selected` — what is selected now, whichever of the two it is
	/// - `copied` — what ⌘C would put on the clipboard, without writing it
	/// - `copy` — press ⌘C for real, and say what it wrote
	/// - `diff-menu` — what the menu over the diff holds, in order
	/// - `regions:12` — what the diff says a point is over, either side of every
	///   boundary of that row
	/// - `diff-rows` — every row of the diff, numbered, as a `text:` step names
	///   them
	/// - `measured` — how many rows have been measured for a selection
	/// - `focus:diff` / `focus:list` — where the keyboard is, which is what
	///   decides the colour a selection is drawn in
	/// - `theme` — a theme change at the diff's door, which drops those rows
	/// - `copy-key` — ⌘C at the real menu bar, with the keyboard in the diff and
	///   then in the file list, and what the clipboard held each time
	/// - `sides:on` / `sides:off` — the arrangement, which rebuilds the rows
	/// - `chrome:on` / `chrome:off` — git's preamble, which is what puts a hunk
	///   header on screen
	/// - `timing` — what a drag down the whole diff costs beside a draw of it,
	///   with the load beside both numbers
	func commitPageForTesting(_ steps: String, waiting: Int = 8) {
		if commitPage == nil { showCommitPage(carrying: nil) }
		guard let page = commitPage else {
			print("COMMIT-PAGE: no page")
			return
		}

		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.commitPageForTesting(rest, waiting: waiting)
				}
				return
			}

			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "report": print("COMMIT-PAGE:\n\(page.pageReportForTesting())")
			case "rows":   print("COMMIT-PAGE rows:\n\(page.rowsForTesting())")
			case "diff":   print("COMMIT-PAGE diff: \(page.diffForTesting())")
			case "verbs":  print("COMMIT-PAGE verbs: \(page.diffVerbsForTesting())")
			// What a gesture over the diff selects, and what ⌘C would take from
			// it — see `DiffView` and the `--pull-requests` steps of the same
			// names, which this deliberately spells the same way.
			case "text", "text-left":
				// `12.4-14.9`: row and offset, to row and offset.
				let ends = argument.split(separator: "-").map { end -> (Int, Int) in
					let place = end.split(separator: ".").compactMap { Int($0) }
					return (place.first ?? 0, place.count > 1 ? place[1] : 0)
				}
				guard let first = ends.first, let last = ends.last else { break }
				print("COMMIT-PAGE text: " + page.selectDiffTextForTesting(
					fromRow: first.0, offset: first.1,
					toRow: last.0, offset: last.1,
					onLeft: step.hasPrefix("text-left")
				))
			case "word":
				let place = argument.split(separator: ".").compactMap { Int($0) }
				print("COMMIT-PAGE word: " + page.selectDiffWordForTesting(
					row: place.first ?? 0, offset: place.count > 1 ? place[1] : 0
				))
			case "row-text":
				print("COMMIT-PAGE row: "
					+ page.selectDiffRowTextForTesting(row: Int(argument) ?? 0))
			case "all":
				print("COMMIT-PAGE all: " + page.selectAllDiffTextForTesting())
			case "select-lines":
				let place = argument.split(separator: "-").compactMap { Int($0) }
				print("COMMIT-PAGE select-lines: " + page.selectDiffLinesForTesting(
					from: place.first ?? 0, to: place.last ?? place.first ?? 0
				))
			case "copied":
				print("COMMIT-PAGE copied:\n" + page.copiedDiffTextForTesting())
			case "copy":
				// The one step that writes the general pasteboard, because it is
				// the one that was asked for by name.
				print("COMMIT-PAGE copy:\n" + page.copyDiffTextForTesting())
			case "press", "drag":
				// `press:12@60` — row 12 at x 60, which is the number column;
				// `press:12@160` is the code. `drag:14@160` finishes it.
				// `+shift` on the end holds shift down, which is how a
				// selection is extended from where it began.
				let held = argument.hasSuffix("+shift")
				let place = argument
					.replacingOccurrences(of: "+shift", with: "")
					.split(separator: "@").map(String.init)
				let row = Int(place.first ?? "") ?? 0
				let x = place.count > 1 ? Int(place[1]) ?? 0 : 0
				let said = step.hasPrefix("press")
					? page.pressDiffForTesting(row: row, x: x, shift: held)
					: page.dragDiffForTesting(row: row, x: x)
				print("COMMIT-PAGE \(step.hasPrefix("press") ? "press" : "drag"): " + said)
			case "selected":
				print("COMMIT-PAGE selected: " + page.diffSelectionForTesting())
			case "timing":
				print("COMMIT-PAGE timing: " + page.diffTimingForTesting())
			case "chrome":
				// Git's preamble, from the same preference the View menu flips:
				// it is what puts a hunk header — the one bold row — on screen.
				Settings.shared.diffShowsChrome = argument == "on"
				print("COMMIT-PAGE chrome: \(argument == "on" ? "shown" : "hidden")")
			case "focus":
				print("COMMIT-PAGE focus: " + page.focusForTesting(argument))
			case "theme":
				print("COMMIT-PAGE theme: " + page.applyDiffThemeForTesting())
			case "copy-key":
				print("COMMIT-PAGE copy-key:\n" + page.copyKeyReportForTesting())
			case "diff-rows":
				print("COMMIT-PAGE diff rows:\n" + page.diffRowsForTesting())
			case "diff-menu":
				print("COMMIT-PAGE diff menu: " + page.diffMenuForTesting())
			case "regions":
				print("COMMIT-PAGE regions: "
					+ page.diffRegionsForTesting(row: Int(argument) ?? 0))
			case "measured":
				print("COMMIT-PAGE measured: " + page.diffMeasuredRowsForTesting())
			case "sides":
				// The arrangement, from the same preference the View menu
				// flips: every diff hears about it and rebuilds its rows.
				Settings.shared.diffIsSideBySide = argument == "on"
				print("COMMIT-PAGE sides: \(argument == "on" ? "side by side" : "unified")")
			case "stage-lines":
				let count = Int(argument) ?? 1
				print("COMMIT-PAGE stage-lines: \(page.stageLinesForTesting(count))")
			case "stage":  page.stageForTesting(paths: [argument], staged: false)
			case "who":    print("COMMIT-PAGE \(page.keyboardReportForTesting())")
			case "keys":   print("COMMIT-PAGE keys: " + page.keysForTesting(argument))
			case "select": page.selectChangeForTesting(argument)
			// Which way a changed picture is being looked at: 0 side by side,
			// 1 the slider, 2 the changed regions.
			case "picture-mode":
				print("COMMIT-PAGE picture: " + page.choosePictureModeForTesting(Int(argument) ?? 0))
			case "type":   page.carrySummaryForTesting(argument)
			// The draft, in the three moves a person has: press it, have an
			// answer arrive, and read what the button became.
			case "draft":  page.pressDraftForTesting()
			case "deliver":
				// `deliver:summary|description`, standing in for `claude`.
				let halves = argument.split(separator: "|", maxSplits: 1).map(String.init)
				page.deliverDraftForTesting(
					summary: halves.first ?? "feat: a drafted summary",
					description: halves.count > 1 ? halves[1] : "The why, drafted."
				)
			case "draft-report":
				print("COMMIT-PAGE draft: " + page.draftReportForTesting)
			case "chevron": page.toggleDescriptionForTesting()
			case "return":  page.pressReturnInSummaryForTesting()
			// The commit message history: `history` prints the menu's entries,
			// `use-history:<n>` fills the fields from one — both async, so
			// settle before reading.
			case "history":     page.messageHistoryForTesting()
			// Commits what is staged with this subject, through the button's
			// own door: whether the project's hooks ran is a claim that wants a
			// trace rather than an assertion.
			case "commit-now": page.commitForTesting(subject: argument)
			case "use-history": page.useHistoryEntryForTesting(Int(argument) ?? 0)
			// A script that says so ends the run. Without it the process is
			// killed by whatever is waiting on it, and a killed process never
			// flushes: the report was written and never reached the terminal.
			case "exit":   fflush(stdout); exit(0)
			default:       print("COMMIT-PAGE: unknown step \(step)")
			}
			fflush(stdout)
		}
	}

	/// What the pull request list says, row by row — see `PullRequestReview`.
	func pullRequestsForTesting(_ steps: String) { pullRequests.driveForTesting(steps) }

	/// What the log page holds, and what its menu over a commit offers.
	func logPageForTesting(_ steps: String, waiting: Int = 8) {
		if logPage == nil { showLogPage(scopedTo: nil) }
		// No page yet is the same waiting game as an empty one: the page needs
		// the project's git, which loads after the window, and a driver asking
		// at 2.5 seconds can be earlier than that. Reporting "no page" at the
		// first ask ended runs that were one loading step from working — and
		// ended them silently, because a run that then hangs is killed, and a
		// kill never flushes what `print` buffered. Hence the flushes on every
		// ending here, not only on `exit`.
		guard let page = logPage, page.hasRowsForTesting else {
			guard waiting > 0 else {
				print(logPage == nil ? "LOG-PAGE: no page" : "LOG-PAGE: the log is still empty")
				fflush(stdout)
				return
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.logPageForTesting(steps, waiting: waiting - 1)
			}
			return
		}
		// The steps are the pane's own — see `HistoryPane.driveForTesting`,
		// which is the shape `pullRequestsForTesting` already has: this
		// controller's part is only to have the page and to wait for it.
		page.driveForTesting(steps)
	}

	/// Where the lines were selected, so what happens next is shown back in the
	/// same place. A tab wants the diff re-opened as a tab; the commit page
	/// keeps its diff and only wants re-reading.
	enum DiffOrigin {
		case tab
		case page
	}
}
