import AppKit

/// Which keys tick a row off in a results list.
///
/// The search results and the usages list are one widget, so this is one rule
/// rather than two. ␣ is the key the system already uses for a checkbox. ⌫ is
/// the key IntelliJ uses to take a usage off the list, and fingers arriving
/// from there press it first.
///
/// It is a rule of its own, out here, because of the key it must *not* answer.
/// One pane over — the project tree — ⌘⌫ moves a file to the trash, and the two
/// panes are the same list-shaped thing full of file names. So a ⌘⌫ over a
/// result has to go on doing nothing at all, and that is a claim worth a test:
/// nothing in the window layer has one, and the whole of the hazard is in which
/// modifiers are let through.
///
/// Bare ⌫ trashes nothing anywhere in this program — the navigator's case is
/// `51 where event.modifierFlags.contains(.command)`, and its menu item's key
/// equivalent carries `.command` too — so the key is free to mean something
/// here without meaning two things one pane apart.
public enum ResultChecklistKeys {
	/// Space.
	public static let space: UInt16 = 49
	/// Delete, which on a Mac keyboard is the key over Return: ⌫.
	public static let backspace: UInt16 = 51
	/// Return.
	public static let enter: UInt16 = 36
	/// Tab: the one key in this program that takes the keyboard out of a
	/// results list.
	public static let tab: UInt16 = 48

	/// Whether this press marks the selection done.
	///
	/// Bare only. ⌘, ⌥ and ⌃ all fall through to the table, which is what keeps
	/// ⌘⌫ inert here and leaves ⌘⌥⌫ and the rest to whoever else wants them.
	public static func marksDone(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
		guard modifiers.intersection([.command, .option, .control]).isEmpty else { return false }
		return keyCode == space || keyCode == backspace
	}

	/// What a press in the list does about showing a row, or nil when the list
	/// does not answer that key at all.
	///
	/// Out here with `marksDone` and for the same reason: it is the rule item
	/// 510 is about, and the list it belongs to is in `AbydosApp`, which the
	/// suite cannot reach. The hazard is the same shape too — a rule that lets
	/// one key too many hand the keyboard over is a person pressing ⌫ at what
	/// looks like a list and deleting a character of their source.
	///
	/// - `previewsOnSelectionChange` says whether the row is already on screen.
	///   ⏎ does the thing the selection has not already done: where the list
	///   previews, the row is showing and ⏎ settles it into a tab of its own;
	///   where it does not, ⏎ is the showing. **Neither of them moves the
	///   keyboard.** Both lists pass true since item 529, which is what makes ⏎
	///   mean the same thing in search as it does in usages; the false case is
	///   the rule, not a list nobody has.
	/// - ⇥ is the one that does, in both lists. ⇧⇥ is deliberately not it:
	///   it goes on walking the key view loop backwards, which in the search
	///   pane is the way back up to the query field.
	public static func opening(
		keyCode: UInt16,
		modifiers: NSEvent.ModifierFlags,
		previewsOnSelectionChange: Bool
	) -> ResultIntent? {
		guard modifiers.intersection([.command, .option, .control]).isEmpty else { return nil }
		switch keyCode {
		case enter where !modifiers.contains(.shift):
			return previewsOnSelectionChange ? .permanent : .preview
		case tab where !modifiers.contains(.shift):
			return .commit
		default:
			return nil
		}
	}

	/// What a selection landing somewhere new does about showing it.
	///
	/// Out here for the reason `opening` is out here, and for one more: item 529
	/// turned this on for search, where results *arrive while the list is live*.
	/// A usages list is handed its whole answer at once, so "the selection moved"
	/// and "somebody moved the selection" were the same sentence; a streaming
	/// list rebuilds its table under a selection that nobody touched, and the
	/// difference between the two is the whole of what must not fire a reveal.
	/// It is a rule with four answers and it can be wrong on its own, so it has
	/// a test rather than a transcript.
	///
	/// - `previewsOnSelectionChange` — off for a list that shows a row only when
	///   asked. Nothing is scheduled and nothing is cancelled.
	/// - `restoringSelection` — the list put the selection there itself: a batch
	///   of results reloading the table, a rebuild after a row was ticked, ↓ out
	///   of the query field landing on the first heading. Not somebody moving it,
	///   so not a reveal — and not a reason to drop a reveal already scheduled
	///   either, since the row the key stopped on is still the row it stopped on.
	/// - `selectedRowCount` and `landsOnAMatch` — a move onto a file heading, or
	///   one that built a selection of several rows, shows nothing. It *does*
	///   drop anything scheduled: the key has moved on from the row it was going
	///   to show.
	/// - `isARepeat` — a held key. See `ResultReveal.whenTheKeyStops`.
	public static func revealing(
		previewsOnSelectionChange: Bool,
		restoringSelection: Bool,
		isARepeat: Bool,
		selectedRowCount: Int,
		landsOnAMatch: Bool
	) -> ResultReveal {
		guard previewsOnSelectionChange, !restoringSelection else { return .notThisList }
		guard selectedRowCount == 1, landsOnAMatch else { return .nothing }
		return isARepeat ? .whenTheKeyStops : .now
	}

	/// What a click on a row does: shows it in a tab of its own and leaves the
	/// keyboard where the hand is, which is the list.
	///
	/// A permanent tab rather than the provisional one, which is the part of
	/// *"somebody who clicked a line of code means to be in it"* that survives
	/// item 510: a click is a decision about which file, and only ⇥ is a
	/// decision about where the keys go.
	public static let click: ResultIntent = .permanent
}

/// What a selection change asks of the editor.
///
/// Four answers and not two, because "show nothing" splits: a list that does not
/// preview at all has nothing to take back, while a move onto a file heading has
/// to cancel a reveal that a held key had already lined up.
public enum ResultReveal: Sendable, Equatable {
	/// Not this list's business. Either it does not show rows as the selection
	/// moves, or the list moved the selection itself and nobody asked for
	/// anything — a batch of search results reloading the table under a
	/// selection that has not moved is this one, and it is the answer item 529
	/// turned on for search to get right.
	case notThisList
	/// Somebody moved the selection, and it landed on nothing worth showing: a
	/// file heading, or several rows at once. Anything already scheduled is
	/// dropped, because the key has left the row it was going to show.
	case nothing
	/// Show it at once. A single press: a preview that arrived 120ms late would
	/// feel broken.
	case now
	/// Schedule it, cancelling whatever was scheduled before. A key held down
	/// through 263 rows sends 263 of these, and only the last of them survives —
	/// so a held ↓ opens the row it stops on and not one file per row.
	case whenTheKeyStops
}

/// What showing a row costs — the tab it lands in, and who has the keyboard
/// afterwards.
///
/// Three cases and not two, which is the correction item 510 made to item 470's
/// pair. The old `.commit` meant both "a permanent tab" and "the keyboard goes
/// with it", and once a click keeps the keyboard while still opening a
/// permanent tab, those are two different questions with three answers between
/// them.
public enum ResultIntent: Sendable {
	/// The provisional tab, and the keyboard stays in the list. Walking a list
	/// with ↓, where 263 usages cost one tab.
	case preview
	/// A tab of its own, and the keyboard still stays in the list. A click, a
	/// double click, and ⏎ over a row already being previewed: *this* is the
	/// one, and I am still working the list.
	case permanent
	/// A tab of its own, and the keyboard goes with it. ⇥, and nothing else.
	case commit
}
