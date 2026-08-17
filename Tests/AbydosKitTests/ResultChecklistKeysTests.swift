import AppKit
import Testing
@testable import AbydosKit

/// The keys that tick a result off, and the one that must go on doing nothing.
///
/// The list itself is in `AbydosApp`, which the suite cannot reach, so its
/// evidence is the `--search-steps` and `--usages-steps` transcripts in items
/// 470 and 505. This is the part with an answer that can be wrong on its own,
/// and it is the part that matters: ⌘⌫ moves a file to the trash in the pane
/// next door, so what this rule lets through is the whole of the hazard.
struct ResultChecklistKeysTests {
	private func marksDone(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> Bool {
		ResultChecklistKeys.marksDone(keyCode: keyCode, modifiers: modifiers)
	}

	/// ␣ is what it has always been, and ⌫ now says the same thing — the key
	/// hands coming from IntelliJ press first.
	@Test func spaceAndBackspaceBothMarkDone() {
		#expect(marksDone(ResultChecklistKeys.space))
		#expect(marksDone(ResultChecklistKeys.backspace))
	}

	/// The one this rule exists for. ⌘⌫ trashes the selected file in the project
	/// tree, and the results list is the same list-shaped thing full of file
	/// names — so it is not marking, not unmarking, and not consumed here.
	@Test func commandBackspaceIsNotMarking() {
		#expect(!marksDone(ResultChecklistKeys.backspace, .command))
	}

	/// And the rest of the modifiers with it: only a bare press ticks, so
	/// anything else stays available to whoever wants it later.
	@Test func aModifiedPressIsNeverMarking() {
		for modifier: NSEvent.ModifierFlags in [.command, .option, .control] {
			#expect(!marksDone(ResultChecklistKeys.space, modifier))
			#expect(!marksDone(ResultChecklistKeys.backspace, modifier))
		}
		#expect(!marksDone(ResultChecklistKeys.backspace, [.command, .option]))
	}

	/// ⇧ is not one of the three. A shifted press comes from a selection being
	/// built with ⇧↓ and the thumb still down, and it means the same thing.
	@Test func shiftStillMarks() {
		#expect(marksDone(ResultChecklistKeys.space, .shift))
		#expect(marksDone(ResultChecklistKeys.backspace, .shift))
	}

	/// The keys the list answers itself — ⏎ and ⇥ — are not marking, and neither
	/// is anything else.
	@Test func otherKeysAreNotMarking() {
		for keyCode: UInt16 in [36, 48, 53, 117, 125, 126] {
			#expect(!marksDone(keyCode))
		}
	}
}

/// Which gesture hands the keyboard to the editor, which is item 510's whole
/// question.
///
/// It is the other half of the hazard `marksDone` exists for. ⌫ ticks a row
/// off, and that is only safe while the keyboard is provably still in the list:
/// a rule that lets one key too many hand the keyboard over is somebody
/// pressing ⌫ at a list that looks live and deleting a character of their
/// source, which is what was reported.
struct ResultChecklistOpeningTests {
	private func opening(
		_ keyCode: UInt16,
		_ modifiers: NSEvent.ModifierFlags = [],
		previewing: Bool = false
	) -> ResultIntent? {
		ResultChecklistKeys.opening(
			keyCode: keyCode, modifiers: modifiers, previewsOnSelectionChange: previewing
		)
	}

	/// The sentence the reporter wrote: the keyboard stays in the list unless Tab
	/// is pressed. So ⇥ commits in both lists, and nothing else commits at all.
	@Test func tabIsTheOnlyWayOut() {
		#expect(opening(ResultChecklistKeys.tab) == .commit)
		#expect(opening(ResultChecklistKeys.tab, previewing: true) == .commit)
		for keyCode: UInt16 in [
			ResultChecklistKeys.enter, ResultChecklistKeys.space,
			ResultChecklistKeys.backspace, 53, 125, 126,
		] {
			#expect(opening(keyCode) != .commit)
			#expect(opening(keyCode, previewing: true) != .commit)
		}
	}

	/// ⏎ shows the row and keeps the keyboard, which is the sentence in
	/// `spec/usages.md` that item 510 reversed. Which *tab* it lands in follows
	/// from whether the row is already on screen: a list that has not shown it
	/// shows it in the provisional tab, and a list that showed it as the
	/// selection moved settles it into one of its own. Since item 529 both lists
	/// are the second, so ⏎ over a search result opens a tab of its own — which
	/// is what `spec/search.md` has always promised a result gets.
	@Test func returnNeverMovesTheKeyboard() {
		#expect(opening(ResultChecklistKeys.enter) == .preview)
		#expect(opening(ResultChecklistKeys.enter, previewing: true) == .permanent)
	}

	/// A click is a decision about which file and not about where the keys go —
	/// and it still opens a tab of its own, which is what `spec/search.md` has
	/// always promised and is not what a preview does.
	@Test func aClickOpensPermanentlyAndKeepsTheKeyboard() {
		#expect(ResultChecklistKeys.click == .permanent)
	}

	/// ⇧⇥ is not the way out. It goes on walking the key view loop backwards,
	/// which in the search pane is the way back up to the query field — the one
	/// thing ⇥ used to do there.
	@Test func shiftTabIsNotAnswered() {
		#expect(opening(ResultChecklistKeys.tab, .shift) == nil)
		#expect(opening(ResultChecklistKeys.tab, .shift, previewing: true) == nil)
	}

	/// A modified press is nobody's here, exactly as with marking: ⌘⇥ is the
	/// system's application switcher and ⌃⇥ walks a tab bar, and a list that
	/// answered either would be taking a key out of a hand that meant something
	/// else by it.
	@Test func modifiedPressesFallThrough() {
		for modifier: NSEvent.ModifierFlags in [.command, .option, .control] {
			#expect(opening(ResultChecklistKeys.tab, modifier) == nil)
			#expect(opening(ResultChecklistKeys.enter, modifier) == nil)
			#expect(opening(ResultChecklistKeys.tab, modifier, previewing: true) == nil)
			#expect(opening(ResultChecklistKeys.enter, modifier, previewing: true) == nil)
		}
	}

	/// Everything else is the table's, the arrows included: moving the selection
	/// is not opening anything, and where a move does show a row it is driven
	/// from what the move did rather than from the key.
	@Test func nothingElseOpens() {
		for keyCode: UInt16 in [
			ResultChecklistKeys.space, ResultChecklistKeys.backspace, 53, 125, 126,
		] {
			#expect(opening(keyCode) == nil)
			#expect(opening(keyCode, previewing: true) == nil)
		}
	}
}

/// What a selection landing somewhere new does about showing it — item 529.
///
/// The rule was one line of guards inside the view until search started using
/// it, and search is the list whose rows *arrive while somebody is working it*.
/// A usages list is handed its whole answer at once, so "the selection moved"
/// and "somebody moved the selection" were never two different things there; a
/// batch of search results reloads the table under a selection nobody touched,
/// and a reveal fired from that would open a file the person is not looking at
/// and take their editor with it. That is the case worth a test, and it could
/// not have one while it lived in `AbydosApp`.
struct ResultRevealTests {
	private func revealing(
		previewing: Bool = true,
		restoring: Bool = false,
		isARepeat: Bool = false,
		selected: Int = 1,
		onAMatch: Bool = true
	) -> ResultReveal {
		ResultChecklistKeys.revealing(
			previewsOnSelectionChange: previewing,
			restoringSelection: restoring,
			isARepeat: isARepeat,
			selectedRowCount: selected,
			landsOnAMatch: onAMatch
		)
	}

	/// The feature, in one line: a press that lands on a match shows it, at once.
	@Test func amoveOntoAMatchShowsIt() {
		#expect(revealing() == .now)
	}

	/// A held key shows the row it stops on and not one file per row. Each
	/// repeat says `whenTheKeyStops`, and the view keeps only the last of them.
	@Test func aheldKeyWaitsUntilItStops() {
		#expect(revealing(isARepeat: true) == .whenTheKeyStops)
	}

	/// **The live-append case.** The list put the selection where it is —
	/// a batch of results reloading the table, a rebuild after a row was ticked,
	/// ↓ out of the query field landing on the first heading — so nothing is
	/// shown, whether the key was held or not.
	///
	/// `notThisList` and not `nothing`, and the difference is the reason there
	/// are four answers rather than three: a batch landing at the end of the rows
	/// leaves the row a held key stopped on exactly where it was, so a reveal
	/// already lined up for it is still the right one. "Nobody asked me anything"
	/// must not read as "forget what was asked".
	@Test func alistRestoringItsOwnSelectionRevealsNothingAndForgetsNothing() {
		#expect(revealing(restoring: true) == .notThisList)
		#expect(revealing(restoring: true, isARepeat: true) == .notThisList)
	}

	/// A list that shows a row only when asked answers nothing at all, and takes
	/// nothing back either.
	@Test func alistThatDoesNotPreviewIsNotAsked() {
		#expect(revealing(previewing: false) == .notThisList)
		#expect(revealing(previewing: false, isARepeat: true) == .notThisList)
		#expect(revealing(previewing: false, onAMatch: false) == .notThisList)
	}

	/// A file heading is not a place in a file. Nothing is shown — and anything
	/// a held key had scheduled *is* dropped, because the key has moved off the
	/// row it was going to show.
	@Test func amoveOntoAFileHeadingShowsNothingAndDropsWhatWasScheduled() {
		#expect(revealing(onAMatch: false) == .nothing)
		#expect(revealing(isARepeat: true, onAMatch: false) == .nothing)
	}

	/// ⇧↓ builds a selection, which is a gesture about ticking rows off rather
	/// than about looking at one of them.
	@Test func aselectionOfSeveralRowsShowsNothing() {
		#expect(revealing(selected: 2) == .nothing)
		#expect(revealing(selected: 0) == .nothing)
	}
}
