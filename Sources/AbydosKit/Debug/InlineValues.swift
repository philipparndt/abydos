import Foundation

/// One value, to be drawn at the end of the line that names it.
public struct InlineValueHint: Equatable, Sendable {
	public let name: String
	public let value: String
	/// Whether there is anything under it worth opening.
	///
	/// **The adapter's answer and nothing else** — `variablesReference > 0`,
	/// which is what `Variable.isExpandable` means. Not the length of the value,
	/// not a brace in the text: reading the string to guess would be the same
	/// mistake as reading a diagnostic's message to guess whether it is true.
	public let isOpenable: Bool
	/// What to ask the adapter for when it is opened. Zero when there is
	/// nothing under it.
	public let variablesReference: Int

	public init(name: String, value: String, isOpenable: Bool = false, variablesReference: Int = 0) {
		self.name = name
		self.value = value
		self.isOpenable = isOpenable
		self.variablesReference = variablesReference
	}

	/// What a card of this actually reads, in one place so the drawing and any
	/// report of it cannot word it differently.
	public var text: String { "\(name) = \(value)" }
}

/// What is drawn beside the code while a session is stopped, and where.
///
/// **Everything here is decided from what the adapter has already said.**
/// `DebugSession.selectFrame` asks for `scopes` and their `variables` on every
/// stop and every frame change; this matches those names against the text of a
/// line. Nothing is asked of the adapter to draw a hint — no `evaluate`, no
/// request per line — because evaluating runs the debuggee's own code in
/// several languages: a Java getter, a Python `__repr__`, a Go `String()`.
/// Drawing a hint must not be able to change the program being debugged.
///
/// In `AbydosKit` and over strings, so the part with the edge cases in it — a
/// name inside a longer one, a name twice on a line, a value the size of a page
/// — is a suite's to hold rather than a screenshot's.
public enum InlineValues {
	/// How much of a value fits beside code before it stops being a hint.
	public static let valueBudget = 40

	/// The variables of a frame, by name, innermost scope first.
	///
	/// First wins, which is what the ordering means: an adapter answers
	/// `scopes` from the inside out — locals, then arguments, then whatever is
	/// global — so a name that appears twice is the nearer one. Registers are
	/// already dropped by the session before this sees them.
	public static func byName(_ scopes: [Scope]) -> [String: Variable] {
		var values: [String: Variable] = [:]
		for scope in scopes {
			for variable in scope.variables where values[variable.name] == nil {
				values[variable.name] = variable
			}
		}
		return values
	}

	/// What to draw at the end of one line, in the order the names occur on it.
	///
	/// **Whole tokens only.** `count` is not found inside `counter`, `account`
	/// or `discount`: a hint that attaches a value to a name that is not the
	/// variable is worse than no hint, because it is read as fact.
	///
	/// **And not after a dot.** `self.count` and `shape.width` are members of
	/// something else, and the local of the same name is a different thing.
	/// This is the one rule beyond word boundaries, and it is here because the
	/// alternative is drawing somebody's local `count` beside an expression
	/// about a field that happens to share its name.
	///
	/// A name occurring twice on a line is one hint. Reading order is the only
	/// order that means anything at the end of a line.
	public static func hints(
		in line: String,
		from variables: [String: Variable],
		budget: Int = valueBudget
	) -> [InlineValueHint] {
		// The cheap way out, taken first: most lines of most files name nothing
		// in the frame, and this runs per visible row while somebody scrolls.
		guard !variables.isEmpty, !line.isEmpty else { return [] }

		var hints: [InlineValueHint] = []
		var seen: Set<String> = []
		var token = ""
		var precededByDot = false
		var previous: Character?

		func endToken() {
			defer { token = ""; precededByDot = false }
			guard !token.isEmpty, !precededByDot, !seen.contains(token) else { return }
			guard let variable = variables[token] else { return }
			seen.insert(token)
			hints.append(InlineValueHint(
				name: token,
				value: summary(of: variable.value, budget: budget),
				// A container is a door; a string is a piece of text. The
				// adapter is the only thing that knows which.
				isOpenable: variable.isExpandable,
				variablesReference: variable.variablesReference
			))
		}

		for character in line {
			if character.isLetter || character.isNumber || character == "_" {
				if token.isEmpty {
					// A token that begins right after a dot is a member of
					// whatever preceded it, and a number is not a name.
					precededByDot = previous == "."
					if character.isNumber { precededByDot = true }
				}
				token.append(character)
			} else {
				endToken()
			}
			previous = character
		}
		endToken()
		return hints
	}

	/// A value as one line, short enough to sit at the end of code.
	///
	/// A struct's value can be a page and a `[]byte` can be four kilobytes;
	/// neither is a hint. Whitespace runs — newlines among them — become single
	/// spaces so that nothing can push the drawing onto a second line, and what
	/// is left is cut to the budget. The whole value is still in the variables
	/// tree, which is a place that can hold one.
	public static func summary(of value: String, budget: Int = valueBudget) -> String {
		var flattened = ""
		var lastWasSpace = false
		for character in value {
			if character.isWhitespace || character.isNewline {
				if !lastWasSpace, !flattened.isEmpty { flattened.append(" ") }
				lastWasSpace = true
			} else {
				flattened.append(character)
				lastWasSpace = false
			}
		}
		let trimmed = flattened.hasSuffix(" ") ? String(flattened.dropLast()) : flattened
		guard trimmed.count > budget else { return trimmed }
		return String(trimmed.prefix(budget)) + "\u{2026}"
	}
}

/// The values a stopped session has to show, and where they belong.
///
/// **The file and the line are half the answer.** A variable is in scope in the
/// frame it belongs to, so its file gets values and every other tab gets none —
/// the same rule the execution marker follows. And nothing is drawn below the
/// line execution stopped at: a value there is either left over from a previous
/// pass or has not been assigned at all, and it would be drawn in the same grey
/// as one that is true.
public struct InlineValueSet: Equatable, Sendable {
	/// The frame's file, as the adapter gave it. Canonicalised where it is
	/// compared, the way the breakpoints and the marker are.
	public let file: String
	/// The frame's own line, counted from 1 as the adapter counts.
	public let line: Int
	public let values: [String: Variable]

	public init(file: String, line: Int, values: [String: Variable]) {
		self.file = file
		self.line = line
		self.values = values
	}

	public var isEmpty: Bool { values.isEmpty }
}
