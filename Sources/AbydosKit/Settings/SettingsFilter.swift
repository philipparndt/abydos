import Foundation

/// What a settings filter matches.
///
/// The settings page is a sidebar of sections and one section's rows at a
/// time, and finding a row means knowing which page it is on — which is the
/// thing a filter field exists to make unnecessary. The words are decided here,
/// in the kit, because the rows live in the window layer where nothing can be
/// tested, and the part with decisions in it is the part a test has to reach.
///
/// Every word, anywhere, in the title *or* the help, case-insensitively. The
/// help because that is where the words people search with actually are — the
/// row called "Engine" is found by "ghostty" only through its sentence. Every
/// word because "tmux status" should find the row about tmux's status bar
/// whether the title has "status" and the help "tmux" or the other way round.
/// Substring rather than prefix, so "engine" finds "Terminal engine". Not fuzzy:
/// over a few dozen rows a fuzzy match finds rows nobody meant and cannot be
/// explained in a sentence.
public enum SettingsFilter {
	/// The query as the words it is matched by: split on whitespace, empties
	/// dropped. An empty list is an empty query, which matches everything.
	public static func words(in query: String) -> [String] {
		query.split(whereSeparator: \.isWhitespace).map(String.init)
	}

	/// Whether a row with this title and help contains every word.
	public static func matches(title: String, help: String?, words: [String]) -> Bool {
		guard !words.isEmpty else { return true }
		let haystack = help.map { "\(title)\n\($0)" } ?? title
		return words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
	}
}
