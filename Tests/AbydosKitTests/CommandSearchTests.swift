import Foundation
import Testing
@testable import AbydosKit

/// Finding a command among everything the app can do.
///
/// The palette used to hold a hand-written list of eight actions; it now holds
/// every menu item there is, which is only useful if what somebody types brings
/// the right one to the top.
struct CommandSearchTests {
	private let commands = [
		CommandDescriptor(title: "Open…", path: ["File"], shortcut: "⌘O"),
		CommandDescriptor(title: "Open Recent", path: ["File"]),
		CommandDescriptor(title: "Split Right", path: ["Editor"], shortcut: "⌥⌘→"),
		CommandDescriptor(title: "Close Tab", path: ["File"], shortcut: "⌘W"),
		CommandDescriptor(title: "Clear", path: ["Terminal"], shortcut: "⌘K"),
	]

	/// An exact name beats a name that merely contains the letters, or "open"
	/// buries "Open…" under everything with the word in it.
	@Test func putsTheExactNameFirst() {
		let found = CommandSearch.match(commands, query: "open")
		#expect(found.first?.title == "Open…")
		#expect(found.map(\.title).contains("Open Recent"))
	}

	/// A word anywhere in the name counts, so "right" finds "Split Right".
	@Test func matchesAWordInTheMiddle() {
		#expect(CommandSearch.match(commands, query: "right").first?.title == "Split Right")
	}

	/// The menu it lives under is searched too: "terminal" lists what the
	/// Terminal menu holds even where the items never say the word.
	@Test func findsByTheMenuItLivesIn() {
		#expect(CommandSearch.match(commands, query: "terminal").map(\.title) == ["Clear"])
	}

	/// Letters in order, which is how anybody who knows what they want types it.
	@Test func matchesInitialsInOrder() {
		#expect(CommandSearch.match(commands, query: "spr").map(\.title) == ["Split Right"])
		#expect(CommandSearch.isSubsequence("sr", of: "split right"))
		#expect(!CommandSearch.isSubsequence("rs", of: "split right"))
	}

	/// Nothing typed lists everything, in the menus' own order — which is
	/// meaningful, and resorting it alphabetically would scatter the items of a
	/// menu somebody is looking down.
	@Test func keepsTheMenusOrderWhenNothingIsTyped() {
		#expect(CommandSearch.match(commands, query: "") == commands)
		#expect(CommandSearch.match(commands, query: "   ") == commands)
	}

	@Test func findsNothingForNonsense() {
		#expect(CommandSearch.match(commands, query: "zzzz").isEmpty)
	}

	/// The name a command is shown under says where it came from, so two
	/// commands called the same thing can be told apart.
	@Test func saysWhereACommandLives() {
		#expect(commands[2].qualifiedTitle == "Editor › Split Right")
		#expect(CommandDescriptor(title: "Alone").qualifiedTitle == "Alone")
	}
}

/// Writing a key equivalent the way a menu writes it.
struct ShortcutTextTests {
	/// The order is fixed by convention, and getting it wrong looks like a typo
	/// in somebody's muscle memory.
	@Test func writesModifiersInTheUsualOrder() {
		#expect(ShortcutText.describe(key: "p", shift: true, command: true) == "⇧⌘P")
		#expect(ShortcutText.describe(key: "k", command: true) == "⌘K")
		#expect(ShortcutText.describe(
			key: "a", control: true, option: true, shift: true, command: true
		) == "⌃⌥⇧⌘A")
	}

	/// A letter is written as it is printed on the key. The shift, where there
	/// is one, is already a symbol in front of it.
	@Test func writesLettersAsTheyAreOnTheKeyboard() {
		#expect(ShortcutText.describe(key: "w", command: true) == "⌘W")
	}

	/// The keys that are not letters have names of their own.
	@Test func namesTheKeysThatAreNotLetters() {
		#expect(ShortcutText.describe(key: "\r", command: true) == "⌘↩")
		#expect(ShortcutText.describe(key: "\u{8}", command: true) == "⌘⌫")
		#expect(ShortcutText.describe(key: "\t", control: true) == "⌃⇥")
		#expect(ShortcutText.describe(key: "\u{1B}") == "⎋")
		#expect(ShortcutText.describe(key: " ", command: true) == "⌘Space")
		#expect(ShortcutText.describe(key: "\u{F702}", option: true, command: true) == "⌥⌘←")
	}

	/// An item with no key equivalent has no shortcut to show, rather than an
	/// empty box where one would be.
	@Test func saysNothingWhenThereIsNoKey() {
		#expect(ShortcutText.describe(key: "", command: true) == nil)
		#expect(ShortcutText.describe(key: "") == nil)
	}
}
