import AppKit
import CryptoKit
import QuickLookUI
import GoSTL
import AbydosKit
import SwiftUI

/// Find in file: the bar, what it matches, and moving between matches.
extension EditorViewController {
	// MARK: - Find in file

	/// The PDF the tab in front is showing, when it is showing one.
	///
	/// A PDF tab is the document and nothing else — there is no split to look
	/// inside, unlike a diagram — so this is the whole search.
	var pdfPreview: PdfFileView? { activeTab?.contentView as? PdfFileView }

	/// Opens the find bar, seeded with the selection when there is one.
	/// Whether the find bar is up, for a driven run asking who got ⌘F.
	var findBarIsShowingForTesting: Bool { !findBar.isHidden }

	func showFind() {
		if let hex = activeTab?.hex {
			hex.focusFind()
			return
		}
		guard let tab = activeTab, tab.codeView != nil || pdfPreview != nil else { return }
		tab.find.isShowing = true
		// The tab's mode, which ⌘F reports rather than changes: somebody who
		// pressed it to re-read their query has not asked for the replacement
		// they typed to go away.
		findBar.setReplacing(tab.find.isReplacing)
		showFindBar(true)

		if let selected = selectedTextForSearch() {
			findBar.setQuery(selected)
		}
		findBar.focusField()
		runFind(query: findBar.query, options: findBar.options)
	}

	/// Opens the bar in replace mode, or switches an open one to it.
	///
	/// Only where there is something to edit. A PDF is searched through PDFKit
	/// and has no text to change, so ⌘R leaves its bar alone rather than putting
	/// up two buttons that cannot fire.
	func showReplace() {
		guard let tab = activeTab, tab.codeView != nil, tab.document != nil else { return }

		// A bar already up keeps what it was searching for: ⌘R is a switch, and
		// re-seeding from the selection would take away the query somebody is
		// part-way through replacing.
		let wasShowing = tab.find.isShowing
		tab.find.isShowing = true
		tab.find.isReplacing = true
		findBar.setReplacing(true)
		showFindBar(true)

		// **Only when the bar was closed.** A search that is already showing has
		// its answer in hand, and running it again is not free of consequence:
		// `runFind` starts from the caret and `setSearchMatches` leaves the caret
		// at the end of whichever match it made current — so asking twice walks
		// the current match forward one. Driving this caught it: ⌘R over a bar
		// showing `1 of 4` replaced the *third* match.
		if !wasShowing {
			if let selected = selectedTextForSearch() { findBar.setQuery(selected) }
			runFind(query: findBar.query, options: findBar.options)
		}
		findBar.focusReplaceField()
	}

	/// Replaces the match the bar calls current, and shows the one after it.
	///
	/// The step is only about *showing*: the edit itself takes this match out of
	/// the list and leaves the next one current, through the same
	/// `onTextReplaced` every other edit goes through. Showing it is the part
	/// that matters — pressing Replace again edits whatever is current, and
	/// something off the bottom of the pane is not something to edit unseen.
	func replaceCurrent(steppingBy delta: Int) {
		guard let tab = activeTab, let document = tab.document, let codeView = tab.codeView else { return }
		guard findBar.isPatternValid, findBar.isTemplateValid else { return }
		guard let current = tab.find.current, tab.find.matches.indices.contains(current) else { return }

		let match = tab.find.matches[current]
		// Asked of the text as it is now. A match found before an edit is a range
		// and not a promise, and `replacement` answers nil rather than replacing
		// something else that happens to be there.
		guard let text = TextSearch.replacement(
			forMatchAt: match.utf16Range,
			in: document.rope.string,
			query: tab.find.query,
			options: tab.find.options,
			template: findBar.replacement
		) else { return }

		codeView.replace(utf16Range: match.utf16Range, with: text)
		stepMatch(by: delta > 0 ? 0 : -1)
	}

	/// Replaces every match, as one edit.
	///
	/// One `document.replace` over the span from the first match to the last, so
	/// the undo history gets one entry and the parser one edit — not one of each
	/// per match. What lies between the matches and did not match is carried
	/// through untouched.
	func replaceAll() {
		guard let tab = activeTab, let document = tab.document, let codeView = tab.codeView else { return }
		guard findBar.isPatternValid, findBar.isTemplateValid else { return }
		guard let edit = TextSearch.replaceAll(
			in: document.rope.string,
			query: tab.find.query,
			options: tab.find.options,
			template: findBar.replacement
		) else { return }

		codeView.replace(utf16Range: edit.utf16Range, with: edit.text)
	}

	/// Drives a replace the way the buttons do, and says what it did.
	///
	/// Every step is the one a person takes — the bar is opened, the query and
	/// the replacement are typed into it, and the button's own verb is called —
	/// so what this proves is the path and not a private shortcut through it.
	/// Selects the first place a string appears and says what lit up because of
	/// it, once the scan has settled.
	func selectTextForTesting(_ text: String) -> Bool {
		guard let codeView = activeTab?.codeView else { return false }
		return codeView.selectTextForTesting(text)
	}

	var occurrenceReportForTesting: String {
		activeTab?.codeView?.occurrenceReportForTesting ?? "no code view"
	}

	func replaceForTesting(query: String, replacement: String, all: Bool, regex: Bool) -> String {
		// The same refusal `--type` is held to, and for the same reason: this
		// verb edits whatever is in front, `--open` is a request rather than a
		// guarantee, and a run that rewrote a stranger's file would be the third
		// incident of that shape rather than the first.
		guard codeViewToDrive("--replace") != nil else { return "refused" }
		showReplace()
		findBar.setReplacement(replacement)
		// Only a query this run has not already typed, and for the same reason
		// `showReplace` will not re-run one: asking again moves the match the
		// buttons are about.
		if findBar.query != query || regex != findBar.options.isRegex {
			// The switches as this run named them, rather than as the last run
			// left them: a driven run says what it wants and inherits nothing.
			findBar.setQueryWithoutSearching(query, options: SearchOptions(isRegex: regex))
			// The bar debounces; a run nobody is watching cannot wait for it.
			runFind(query: findBar.query, options: findBar.options)
		}

		let before = activeTab?.find.matches.count ?? 0
		if all { replaceAll() } else { replaceCurrent(steppingBy: 1) }
		return "all=\(all) matched=\(before)\n\(findReportForTesting)"
	}

	func setFindQuery(_ query: String) {
		showFind()
		findBar.setQuery(query)
	}

	func closeFind() {
		// This tab's, and only this tab's. Closing find in one file used to
		// close it in every file in the group, because there was one flag for
		// all of them.
		if let tab = activeTab {
			tab.find = Tab.FindState()
			tab.codeView?.clearSearchMatches()
		}
		showFindBar(false)
		findBar.setReplacing(false)
		findBar.setReplacement("")
		pdfPreview?.clearFind()
		focusActiveEditor()
	}

	/// The one bar, shown or hidden. Which tab it is *about* is the tab's.
	private func showFindBar(_ showing: Bool) {
		findBar.isHidden = !showing
		findBarHeight.constant = showing ? findBar.wantedHeight : 0
	}

	/// Puts the arriving tab's find state into the bar.
	///
	/// Called from `activate(index:)` and from nowhere else. Touches nothing
	/// about responders: where the keyboard goes after a tab switch is settled
	/// there, twice, with the measurements in the comments.
	func restoreFind(for tab: Tab) {
		// The mode before the height, which is worked out from it.
		findBar.setReplacing(tab.find.isReplacing)
		findBar.setReplacement(tab.find.replacement)
		showFindBar(tab.find.isShowing)
		guard tab.find.isShowing else {
			// **Emptied, not just hidden.** Driving this caught the bar still
			// holding `widget` and `1 of 199` after the tab that searched for it
			// was closed — invisible, because the bar was hidden, and waiting to
			// be shown over a file it knows nothing about. A hidden control
			// holding another tab's answer is the same class of fault as the
			// matches were.
			findBar.setQueryWithoutSearching("", options: SearchOptions())
			findBar.setReplacing(false)
			findBar.setReplacement("")
			findBar.setStatus(matchCount: 0, currentIndex: nil)
			return
		}
		findBar.setQueryWithoutSearching(tab.find.query, options: tab.find.options)
		// The matches belong to this tab's document, so they can be handed to
		// this tab's view — which is the whole point of their living here.
		tab.codeView?.setSearchMatches(tab.find.matches, current: tab.find.current)
		findBar.setStatus(matchCount: tab.find.matches.count, currentIndex: tab.find.current)
	}

	var isFindVisible: Bool { activeTab?.find.isShowing ?? false }

	/// Debounced so a search does not run on every keystroke of a long query.
	func scheduleFind(query: String, options: SearchOptions, movingCaret: Bool = true) {
		findDebounce?.cancel()
		let work = DispatchWorkItem { [weak self] in
			self?.runFind(query: query, options: options, movingCaret: movingCaret)
		}
		findDebounce = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
	}

	/// - Parameter movingCaret: whether the current match should be selected and
	///   scrolled to. True for a search somebody asked for by typing a query;
	///   false for the one an edit triggers, where the caret is where they are
	///   typing and taking it to the nearest match would make the file
	///   impossible to type in with find open.
	private func runFind(query: String, options: SearchOptions, movingCaret: Bool = true) {
		// A PDF has no rope to search, so PDFKit searches it and the bar is told
		// the same two numbers it is told for a source file. Whole-word and regex
		// are not offered by `PDFDocument.findString`, so those switches do
		// nothing here — the bar keeps showing them because they still apply to
		// the next file, and a search that quietly ignored them would find more
		// than it said rather than less.
		// Remembered whatever kind of tab this is, so coming back to it shows
		// what was being looked for.
		activeTab?.find.query = query
		activeTab?.find.options = options

		// **A pattern that will not compile is not searched for.** It used to
		// be: the search ran, got nothing out of a regex that never compiled,
		// and the bar reported `No results` — an answer to a question nobody
		// asked. Not searching also keeps the last valid query's matches on
		// screen, rather than clearing them on the keystroke that was only half
		// of a bracket.
		guard TextSearch.isValid(query: query, options: options) else {
			findBar.setStatus(matchCount: 0, currentIndex: nil)
			return
		}

		if let pdf = pdfPreview {
			// A PDF has its matches inside PDFKit rather than as offsets, so the
			// tab keeps the question and `PdfFileView` keeps the answer.
			let count = pdf.find(query, caseSensitive: options.caseSensitive)
			findBar.setStatus(matchCount: count, currentIndex: pdf.currentMatchIndex)
			return
		}

		guard let tab = activeTab, let document = tab.document, let codeView = tab.codeView else { return }

		guard !query.isEmpty else {
			tab.find.matches = []
			tab.find.current = nil
			codeView.clearSearchMatches()
			findBar.setStatus(matchCount: 0, currentIndex: nil)
			return
		}

		let matches = TextSearch.matches(in: document.rope, query: query, options: options)
		// Start from the match nearest the caret rather than the top of the file.
		let caret = codeView.caretOffset
		let nearestToCaret = matches.firstIndex { $0.utf16Range.lowerBound >= caret }
			?? (matches.isEmpty ? nil : 0)

		// **A search an edit asked for keeps the match the edit left current.**
		// The caret rule alone moves on one every time: an edit — a replacement
		// above all — leaves the caret at the end of what it put in, and the
		// first match at or after that is the *next* one. Driving it showed the
		// wobble plainly: Replace lit `1 of 3`, and a tenth of a second later the
		// same three matches were `2 of 3` with nothing having happened.
		let current: Int?
		if movingCaret {
			current = nearestToCaret
		} else {
			let wanted = tab.find.current.flatMap {
				tab.find.matches.indices.contains($0) ? tab.find.matches[$0].utf16Range : nil
			}
			current = wanted.flatMap { range in matches.firstIndex { $0.utf16Range == range } }
				?? nearestToCaret
		}
		tab.find.matches = matches
		tab.find.current = current

		if movingCaret {
			codeView.setSearchMatches(matches, current: current)
		} else {
			codeView.updateSearchMatches(matches, current: current)
		}
		findBar.setStatus(matchCount: matches.count, currentIndex: current)
	}

	/// The text moved under a tab's matches.
	///
	/// **Nothing used to ask.** `runFind` was called from the find field, from a
	/// tab coming to the front and from ⌘G, and from no edit anywhere — so the
	/// matches were offsets into the text as it had been when the search ran. A
	/// file searched for a path and then edited to take that path off eight of
	/// its ten lines drew eight bands of the old length at the old offsets, over
	/// words holding nothing of the sort. They are not only drawn, either: the
	/// current one sets a caret.
	///
	/// Two halves, and each is wrong alone. The matches are moved now, so nothing
	/// false is ever on screen; the search is asked again on the debounce it
	/// already runs on, because an edit can make a match as easily as destroy
	/// one and only searching knows.
	func textReplaced(in tab: Tab, replacing range: Range<Int>, insertedLength: Int) {
		// A file nobody is searching pays nothing for this.
		guard tab.find.isShowing else { return }

		let adjusted = MatchesAfterEdit.adjusted(
			tab.find.matches,
			current: tab.find.current,
			replacing: range,
			insertedLength: insertedLength
		)
		tab.find.matches = adjusted.matches
		tab.find.current = adjusted.current

		// The bar and the bands are the active tab's. A background tab keeps its
		// adjusted matches and is drawn from them when it comes forward.
		guard tab === activeTab else { return }
		tab.codeView?.updateSearchMatches(adjusted.matches, current: adjusted.current)
		findBar.setStatus(matchCount: adjusted.matches.count, currentIndex: adjusted.current)
		scheduleFind(query: tab.find.query, options: tab.find.options, movingCaret: false)
	}

	func stepMatch(by delta: Int) {
		if let pdf = pdfPreview {
			pdf.stepMatch(by: delta)
			findBar.setStatus(matchCount: pdf.matchCount, currentIndex: pdf.currentMatchIndex)
			return
		}

		// **This tab's matches.** They used to be the group's, so stepping after
		// a tab switch handed one file's offsets to another file's view — and
		// `setSearchMatches` sets a caret from them, against a document that
		// never produced that range.
		guard let tab = activeTab else { return }
		let matches = tab.find.matches
		guard !matches.isEmpty else { return }
		let current = tab.find.current ?? -1
		// Wraps, which is what every find bar does at the ends.
		let next = ((current + delta) % matches.count + matches.count) % matches.count
		tab.find.current = next
		tab.codeView?.setSearchMatches(matches, current: next)
		findBar.setStatus(matchCount: matches.count, currentIndex: next)
	}

	func findNext() { stepMatch(by: 1) }
	func findPrevious() { stepMatch(by: -1) }

	/// ⌘G with the keyboard in the text rather than in the find field.
	///
	/// Every verb that opens the find bar leaves the keyboard in it, so a capture
	/// taken after one can only ever show an *unfocused* selection over the
	/// current match. The other state is real and is reached by the ordinary
	/// gesture — the bar is open, the keyboard is back in the code, ⌘G steps on —
	/// and 0536 had to be looked at in both, because the selection that lands on
	/// the current match is a different colour in each.
	func findNextFromEditor(_ times: Int) {
		focusActiveEditor()
		for _ in 0..<max(1, times) { findNext() }
	}

	/// Opens a file and jumps to a line — the target of review findings and
	/// search results.
	///
	/// `focusEditor` and `preview` are what tell "take me to this one" from "show
	/// me this one": a checklist being walked with ↓ asks for the provisional tab
	/// and leaves the keyboard in the list, so 263 usages cost one tab rather than
	/// 263, and the next ↓ still reaches the next row. Both keep the defaults the
	/// call has always had, so a click and a review finding are unchanged.
	///
	/// The column is where a search match starts on its line and the length is how
	/// wide it is, and they are here because a line is not a place: a match two
	/// hundred characters along a long line is off the side of the pane, and a
	/// forty-character one starting a column inside the edge is mostly off it. The
	/// editor can know neither from the line alone. Column one and length nothing
	/// are the start of the line, which is what a review finding and a `file:150`
	/// mean.
	///
	/// The reveal happens **now**, not on the next turn of the main loop. It used
	/// to be a `DispatchQueue.main.async`, whose comment had the diagnosis right —
	/// a freshly opened document has not laid out, so scrolling would measure
	/// against a zero-height view — and answered it with a bet: one turn is not
	/// "layout has finished", it is one turn. Where the sizing took two, or was
	/// itself scheduled, the reveal ran against a pane that was still wrong and
	/// scrolled somewhere that was not the line. `CodeView.reveal` now forces the
	/// layout pass it depends on and, where there is still nothing to measure,
	/// waits for the pane to be given a size rather than for time to pass — so
	/// this is a plain call, on the tab this call opened, and `abydos deep.txt:150
	/// main.go` cannot reveal line 150 on the wrong file because there is no
	/// interval in which the active tab can change.
	func open(
		fileURL: URL,
		atLine line: Int,
		column: Int = 1,
		length: Int = 0,
		focusEditor: Bool = true,
		preview: Bool = false
	) {
		let departure = currentPlace
		isReportingSuppressed += 1
		open(fileURL: fileURL, focusEditor: focusEditor, preview: preview)
		isReportingSuppressed -= 1
		reportNavigation(
			from: departure,
			to: (fileURL, line)
		)
		activeTab?.codeView?.reveal(line: line, column: column, length: length)
	}

	/// Puts the caret on a 1-based line of the file being edited.
	///
	/// Nothing happens when no file is open: `:` in the palette is a question
	/// about a document, and there is no document to ask it of.
	/// ⌃Space: offer completions at the caret, whatever is being typed.
	func completeAtCaret() {
		guard let tab = activeTab, let codeView = tab.codeView else { return }
		codeView.requestCompletionsNow()
	}

	func goTo(line: Int) {
		activeTab?.codeView?.reveal(line: line)
		activeTab?.codeView?.window?.makeFirstResponder(activeTab?.codeView)
	}
}
