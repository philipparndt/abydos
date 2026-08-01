import Foundation

/// Adding things to `.gitignore`.
///
/// The pattern is offered rather than imposed. What somebody means by "ignore
/// this" varies — this exact file, everything with this name anywhere, this
/// whole directory, anything with this extension — and guessing wrong writes a
/// line into a tracked file that somebody else has to notice and undo.
public enum GitIgnore {
	/// A pattern worth offering for a path, and what it would cover.
	public struct Suggestion: Equatable, Sendable {
		public let pattern: String
		/// What it means, in a few words, so a choice can be made without
		/// knowing gitignore's syntax by heart.
		public let explanation: String

		public init(pattern: String, explanation: String) {
			self.pattern = pattern
			self.explanation = explanation
		}
	}

	/// Patterns worth offering for a path, best guess first.
	///
	/// - `relativePath`: the path as git names it, from the repository root.
	public static func suggestions(for relativePath: String, isDirectory: Bool) -> [Suggestion] {
		let name = (relativePath as NSString).lastPathComponent
		let extensionName = (name as NSString).pathExtension
		var suggestions: [Suggestion] = []

		if isDirectory {
			suggestions.append(Suggestion(
				pattern: "/\(relativePath)/",
				explanation: "This directory and everything in it."
			))
			suggestions.append(Suggestion(
				pattern: "\(name)/",
				explanation: "Any directory called “\(name)”, anywhere."
			))
			return suggestions
		}

		// This exact file first: it is what was right-clicked, and the only
		// suggestion that cannot possibly cover more than was meant.
		suggestions.append(Suggestion(
			pattern: "/\(relativePath)",
			explanation: "Only this file."
		))

		if name != relativePath {
			suggestions.append(Suggestion(
				pattern: name,
				explanation: "Any file called “\(name)”, anywhere."
			))
		}

		if !extensionName.isEmpty {
			suggestions.append(Suggestion(
				pattern: "*.\(extensionName)",
				explanation: "Every .\(extensionName) file."
			))
		}

		// Build artefacts are usually named for the thing that made them, and
		// the number on the end differs every time.
		if let stem = generatedStem(of: name) {
			suggestions.append(Suggestion(
				pattern: "\(stem)*",
				explanation: "Anything starting with “\(stem)”."
			))
		}

		let directory = (relativePath as NSString).deletingLastPathComponent
		if !directory.isEmpty {
			suggestions.append(Suggestion(
				pattern: "/\(directory)/",
				explanation: "Everything in \(directory)/."
			))
		}
		return suggestions
	}

	/// The fixed part of a name that ends in digits, for things like
	/// `__debug_bin374976163` where only the number changes.
	static func generatedStem(of name: String) -> String? {
		let trimmed = name.reversed().drop { $0.isNumber }
		let stem = String(trimmed.reversed())
		guard stem.count >= 3, stem.count < name.count else { return nil }
		return stem
	}

	/// Whether the file already ignores this pattern.
	///
	/// Compared line by line rather than by asking git, because the question is
	/// "is this line already here" — writing a duplicate is the actual mistake
	/// to avoid.
	public static func contains(_ pattern: String, in contents: String) -> Bool {
		contents
			.split(separator: "\n", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.contains(pattern.trimmingCharacters(in: .whitespaces))
	}

	/// Adds a pattern, returning the new contents of the file.
	///
    /// Appended under a heading of its own the first time, so what the editor
	/// added is distinguishable from what a person wrote.
	public static func adding(_ pattern: String, to contents: String) -> String {
		let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !pattern.isEmpty, !contains(pattern, in: contents) else { return contents }

		if contents.isEmpty { return pattern + "\n" }

		var result = contents
		if !result.hasSuffix("\n") { result += "\n" }
		if !result.hasSuffix("\n\n") { result += "\n" }
		return result + pattern + "\n"
	}

	/// Writes a pattern into a repository's `.gitignore`, making it if needed.
	@discardableResult
	public static func add(_ pattern: String, toRepositoryAt root: URL) throws -> URL {
		let file = root.appendingPathComponent(".gitignore")
		let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
		let updated = adding(pattern, to: existing)
		guard updated != existing else { return file }
		try updated.write(to: file, atomically: true, encoding: .utf8)
		return file
	}
}
