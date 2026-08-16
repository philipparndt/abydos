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

	/// Whether this press marks the selection done.
	///
	/// Bare only. ⌘, ⌥ and ⌃ all fall through to the table, which is what keeps
	/// ⌘⌫ inert here and leaves ⌘⌥⌫ and the rest to whoever else wants them.
	public static func marksDone(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
		guard modifiers.intersection([.command, .option, .control]).isEmpty else { return false }
		return keyCode == space || keyCode == backspace
	}
}
