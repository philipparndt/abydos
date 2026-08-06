import Foundation

/// What pressing return should actually insert.
///
/// Not just a newline. Nobody wants the caret at column zero after a line that
/// was indented four levels, and everybody expects the body of a block to be
/// one level in from its opening. Getting this wrong is felt on every line of
/// every file, which is why editors that do nothing here feel broken however
/// fast they are.
public enum ReturnIndent {
	/// What to type in place of a newline, and where the caret ends up.
	public struct Result: Equatable, Sendable {
		/// The text to insert at the caret.
		public var text: String
		/// How far into that text the caret goes, in UTF-16 units. Usually the
		/// end; on a split pair it is the end of the *first* line, leaving the
		/// closing brace below.
		public var caretOffset: Int

		public init(text: String, caretOffset: Int) {
			self.text = text
			self.caretOffset = caretOffset
		}
	}

	/// One level of indent, in whatever the file is written in.
	static func unit(usesTabs: Bool, width: Int) -> String {
		usesTabs ? "\t" : String(repeating: " ", count: max(1, width))
	}

	/// The whitespace a line begins with.
	public static func leadingWhitespace(of line: String) -> String {
		String(line.prefix { $0 == " " || $0 == "\t" })
	}

	/// Whether a line's last non-space character opens a block.
	static func opensBlock(_ line: String) -> Bool {
		guard let last = line.reversed().first(where: { !$0.isWhitespace }) else { return false }
		return last == "{" || last == "(" || last == "[" || last == ":"
	}

	/// Whether what follows the caret closes the block just opened.
	static func closesBlock(_ text: String) -> Bool {
		guard let first = text.first(where: { !$0.isWhitespace }) else { return false }
		return first == "}" || first == ")" || first == "]"
	}

	/// Works out what return should do.
	///
	/// - `before`: the text on the line to the left of the caret.
	/// - `after`: the text on the line to its right.
	public static func result(
		before: String,
		after: String,
		usesTabs: Bool,
		indentWidth: Int
	) -> Result {
		let indent = leadingWhitespace(of: before)
		let step = unit(usesTabs: usesTabs, width: indentWidth)

		// Between a pair — `{|}` — the closing half goes to its own line at the
		// original indent, and the caret waits on a blank line between them.
		if opensBlock(before), closesBlock(after) {
			let opening = "\n" + indent + step
			let closing = "\n" + indent
			return Result(text: opening + closing, caretOffset: opening.utf16.count)
		}

		// After an opening: one level in.
		if opensBlock(before) {
			return newline(indent + step)
		}

		// A line that is only a closing brace has already been dedented by the
		// editor, so the next line follows it rather than its contents.
		return newline(indent)
	}

	private static func newline(_ indent: String) -> Result {
		let text = "\n" + indent
		return Result(text: text, caretOffset: text.utf16.count)
	}

	/// Whether typing `character` should pull the current line back a level.
	///
	/// Typing the `}` that closes a block should move it out to line up with
	/// whatever opened it, and it should only do so when it is the first thing
	/// on the line — otherwise `x[i]` would reindent as you type it.
	public static func shouldDedent(afterTyping character: Character, lineBefore: String) -> Bool {
		guard character == "}" || character == ")" || character == "]" else { return false }
		return lineBefore.allSatisfy { $0 == " " || $0 == "\t" }
	}

	/// The indent a closing brace should have, given the line that opened it.
	public static func dedented(_ indent: String, usesTabs: Bool, indentWidth: Int) -> String {
		let step = unit(usesTabs: usesTabs, width: indentWidth)
		guard indent.hasSuffix(step) else {
			// Mixed or partial indentation: take off what is there rather than
			// insisting on a whole level that may not exist.
			return usesTabs ? String(indent.dropLast()) : String(indent.dropLast(min(indentWidth, indent.count)))
		}
		return String(indent.dropLast(step.count))
	}

	/// Whether a file indents with tabs, judged by what it already does.
	///
	/// The file's own habit beats the setting: joining a tab-indented file and
	/// filling it with spaces is worse than either convention on its own.
	public static func usesTabs(in text: String, default fallback: Bool) -> Bool {
		var tabs = 0
		var spaces = 0
		for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(200) {
			guard let first = line.first else { continue }
			if first == "\t" { tabs += 1 }
			if first == " " { spaces += 1 }
		}
		if tabs == 0, spaces == 0 { return fallback }
		return tabs >= spaces
	}
}
