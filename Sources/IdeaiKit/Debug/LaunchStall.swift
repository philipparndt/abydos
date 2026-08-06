import Foundation

/// What to say when a launch produced no event and had to be given up on.
///
/// The old message named the one cause it knew — macOS holding a debuggee until
/// developer-tools authorization is answered — whatever had actually happened.
/// That is a good guess when the adapter said nothing at all, and a bad one the
/// rest of the time: a Go build that fails prints `cannot find main module` and
/// then this app reported a permissions problem, sending everybody to
/// `DevToolsSecurity` about a missing `go.mod`. The adapter usually says why.
/// Saying what it said costs nothing and is right more often than a guess.
public enum LaunchStall {
	/// How much of the adapter's output to keep. Enough for a compiler's
	/// complaint, which is several lines, and not so much that the reason is
	/// buried in the log that followed it.
	static let keptLines = 12

	/// Keeps the tail of what the adapter has said.
	public static func remember(_ text: String, after previous: String?) -> String {
		let combined = (previous ?? "") + text
		let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
		guard lines.count > keptLines else { return combined }
		return lines.suffix(keptLines).joined(separator: "\n")
	}

	/// The message to show, given what the adapter said before going quiet.
	public static func explain(lastOutput: String?) -> String {
		let said = (lastOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		guard !said.isEmpty else {
			// Nothing at all: no build, no error, no process. This is what the
			// authorization case looks like, since the debuggee is held before
			// it can say anything.
			return """
			The debugger started nothing, and said nothing about why.

			macOS asks for permission the first time a process is debugged and holds \
			the program until that is answered. If developer mode is off it asks every \
			time; enabling it once removes the prompt:

			    sudo DevToolsSecurity -enable
			"""
		}

		return """
		The debugger stopped without starting the program. The last thing it said was:

		\(said)
		"""
	}
}
