import Foundation

/// Which files hold secrets by shape, and where in a line the secret is —
/// the model behind the editor's redaction covers.
///
/// Name shapes, not content sniffing: entropy heuristics are false positives
/// waiting to interrupt somebody's JSON, and the files that put keys in front
/// of a shared screen announce themselves by name. `.env` and its variants
/// are the dotenv convention; `*.dec` is the file a SOPS-style decrypt leaves
/// beside its encrypted original, which is the most secret-laden file a
/// screen can show.
public enum DotenvSecrets {
	/// Whether a file of this name conceals its values.
	public static func conceals(fileNamed name: String) -> Bool {
		let lowered = name.lowercased()
		if lowered == ".env" || lowered.hasPrefix(".env.") { return true }
		if lowered.hasSuffix(".env") { return true }
		if lowered.hasSuffix(".dec") { return true }
		return false
	}

	/// The range of the value in one line — what a cover hides.
	///
	/// After the first separator: `=` for the dotenv shape, and `:` too for
	/// the YAML shape a `.dec` file usually has. `export ` prefixes do not
	/// hide a key's name, quotes are covered with the value they quote, and a
	/// comment, a blank line or a line with no separator has no value to
	/// cover. The separator itself stays readable — `API_KEY=` is the half
	/// somebody shares a screen to talk about.
	public static func valueRange(inLine line: String) -> Range<String.Index>? {
		let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
		guard let first = trimmed.first, first != "#" else { return nil }

		guard let separator = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else {
			return nil
		}
		var start = line.index(after: separator)
		// The space after a YAML `:`, kept readable with the separator.
		while start < line.endIndex, line[start] == " " || line[start] == "\t" {
			start = line.index(after: start)
		}
		guard start < line.endIndex else { return nil }
		return start..<line.endIndex
	}
}
