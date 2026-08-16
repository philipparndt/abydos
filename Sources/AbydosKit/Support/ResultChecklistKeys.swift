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
	/// - `previewsOnSelectionChange` is what tells the two lists apart: the
	///   usages list shows each row as the selection moves, search does not.
	///   ⏎ does the thing the selection has not already done, so in search it
	///   shows the row in the provisional tab and in usages it settles the tab
	///   that is already showing. **Neither of them moves the keyboard.**
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

	/// What a click on a row does: shows it in a tab of its own and leaves the
	/// keyboard where the hand is, which is the list.
	///
	/// A permanent tab rather than the provisional one, which is the part of
	/// *"somebody who clicked a line of code means to be in it"* that survives
	/// item 510: a click is a decision about which file, and only ⇥ is a
	/// decision about where the keys go.
	public static let click: ResultIntent = .permanent
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
