import Testing
@testable import AbydosKit

/// What typing into the settings filter finds.
struct SettingsFilterTests {
	@Test func aWordInTheTitleFindsTheRow() {
		#expect(SettingsFilter.matches(title: "Terminal engine", help: nil, words: ["engine"]))
	}

	/// The sentence under a control is where the words people search with are.
	@Test func aWordOnlyInTheHelpFindsTheRowToo() {
		#expect(SettingsFilter.matches(
			title: "Engine", help: "Ghostty's terminal, or this app's own.", words: ["ghostty"]
		))
	}

	@Test func everyWordHasToBeSomewhereInTitleOrHelp() {
		let title = "Hide the status bar"
		let help = "tmux's own line at the bottom of the pane."
		#expect(SettingsFilter.matches(title: title, help: help, words: ["tmux", "status"]))
		#expect(!SettingsFilter.matches(title: title, help: help, words: ["tmux", "colour"]))
	}

	@Test func caseDoesNotMatterAndNeitherDoesWordPosition() {
		#expect(SettingsFilter.matches(title: "Font ligatures", help: nil, words: ["LIGA"]))
	}

	@Test func anEmptyQueryMatchesEverything() {
		#expect(SettingsFilter.words(in: "   ").isEmpty)
		#expect(SettingsFilter.matches(title: "Anything", help: nil, words: []))
	}

	@Test func aWordNothingHasMatchesNothing() {
		#expect(!SettingsFilter.matches(title: "Font ligatures", help: "Joined glyphs.", words: ["zebra"]))
	}

	@Test func theQueryIsSplitOnWhitespace() {
		#expect(SettingsFilter.words(in: " tmux   status\tbar ") == ["tmux", "status", "bar"])
	}
}
