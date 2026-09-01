import Foundation

/// A Conventional Commits v1.0.0 subject line, read.
///
/// **It reads and never writes.** Prepending a type to a summary that lacks one
/// is classifying somebody's change on their behalf, and a wrong classification
/// reads as deliberate and lands in a changelog under the wrong heading. So a
/// draft that comes back outside the format is left exactly as it came back, and
/// this type exists so tests — and one day a badge on screen — can say what a
/// summary *is* rather than a sentence about it.
///
/// <https://www.conventionalcommits.org/en/v1.0.0/>
public struct ConventionalCommit: Sendable, Equatable {
	/// `feat`, `fix`, and the eight the request named beside them.
	///
	/// The spec makes only `feat` and `fix` load-bearing — they are the two
	/// that move a semantic version — and allows the rest. Which "the rest"
	/// are is a convention, so the list is written down rather than guessed at
	/// per repository.
	public static let types = [
		"feat", "fix", "build", "chore", "ci", "docs", "style", "refactor", "perf", "test",
	]

	public let type: String
	/// The noun in parentheses, or nil where none was given.
	public let scope: String?
	/// Marked by `!` before the colon. A `BREAKING CHANGE:` footer says the
	/// same thing from the body, which is not this line's to read.
	public let isBreaking: Bool
	public let description: String

	/// Reads a subject line, or nil when it is not one.
	///
	/// Case is not significant except for `BREAKING CHANGE`, which the spec
	/// says must be uppercase and which lives in the body rather than here —
	/// so `Fix:` and `fix:` are the same type, lower-cased in what comes back.
	public static func read(_ summary: String) -> ConventionalCommit? {
		let line = summary.trimmingCharacters(in: .whitespaces)
		guard let colon = line.firstIndex(of: ":") else { return nil }
		var head = String(line[line.startIndex..<colon])
		let description = String(line[line.index(after: colon)...])
			.trimmingCharacters(in: .whitespaces)
		// The colon must be followed by a space and something: `fix:` alone is
		// a type with nothing said about the change, and `feat:x` is not the
		// form. The space is checked before it is trimmed away.
		guard description.isEmpty == false,
			line[line.index(after: colon)...].hasPrefix(" ") else { return nil }

		let breaking = head.hasSuffix("!")
		if breaking { head.removeLast() }

		var scope: String?
		if head.hasSuffix(")"), let open = head.firstIndex(of: "(") {
			scope = String(head[head.index(after: open)..<head.index(before: head.endIndex)])
			head = String(head[head.startIndex..<open])
			// `fix()` is punctuation, not a scope.
			guard let named = scope, !named.isEmpty else { return nil }
		}

		let type = head.lowercased()
		guard types.contains(type) else { return nil }
		return ConventionalCommit(
			type: type, scope: scope, isBreaking: breaking, description: description
		)
	}

	/// Whether a summary is in the format at all — the question a test asks
	/// most often.
	public static func isConventional(_ summary: String) -> Bool {
		read(summary) != nil
	}
}
