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

	/// The message to show when the adapter *refused* — which is a different
	/// event from going quiet, and used not to be told apart from it.
	///
	/// **Measured on the reported project**: `dlv dap` answered `Building …`,
	/// then `Build Error: …` with the compiler's own words, then a `launch`
	/// response with `success: false` and a message — all inside one second. The
	/// app read none of it and reported the watchdog's guess twenty-five seconds
	/// later, quoting `Building …`, which is the adapter clearing its throat.
	///
	/// The adapter's own sentence leads, because it is one line written for a
	/// person. What it printed follows, because that is where the compiler's
	/// words are — and it is *not* the same text: a message saying "check the
	/// debug console for details" is useless on its own.
	///
	/// The console is named when the adapter points at it. A dialog that repeats
	/// "check the console" without saying the console is a pane away is a dialog
	/// in the way of its own advice.
	public static func explainRefusal(
		_ command: String, message: String?, lastOutput: String?
	) -> String {
		let said = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		let printed = (lastOutput ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
		let verb = command == "attach" ? "attach to the program" : "start the program"

		var lines: [String] = []
		lines.append(said.isEmpty
			? "The debugger would not \(verb), and said nothing about why."
			: "The debugger would not \(verb): \(said)")

		if !printed.isEmpty {
			lines.append("")
			lines.append("What it said on the way:")
			lines.append("")
			lines.append(printed)
		}
		// Only when the adapter itself pointed there, and only once — repeating
		// its own sentence back at somebody is not advice.
		if said.lowercased().contains("console"), !printed.isEmpty {
			lines.append("")
			lines.append("The debug console has the whole of it.")
		}
		return lines.joined(separator: "\n")
	}
}
