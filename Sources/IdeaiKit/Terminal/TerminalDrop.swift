import Foundation

/// Turning dropped files into text a shell will accept.
public enum TerminalDrop {
	/// Characters that would be read as syntax rather than as part of a name.
	private static let needsQuoting = CharacterSet(charactersIn: " \t\n'\"\\$`&|;<>()[]{}*?!#~")

	/// One path, quoted only if it has to be.
	///
	/// Quoting everything would be safe but unreadable: most paths are ordinary
	/// and a shell prompt full of quotes is harder to edit afterwards, which is
	/// usually what happens next to a dropped path.
	public static func quoted(_ path: String) -> String {
		guard path.rangeOfCharacter(from: needsQuoting) != nil else { return path }
		// Single quotes, with the one escape a single-quoted string allows.
		return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}

	/// What to type when files are dropped on a terminal.
	///
	/// Space-separated and with a trailing space, so a second drop — or the
	/// rest of the command — does not run into the last path.
	public static func text(for urls: [URL]) -> String {
		let paths = urls.map { quoted($0.path) }
		guard !paths.isEmpty else { return "" }
		return paths.joined(separator: " ") + " "
	}
}
