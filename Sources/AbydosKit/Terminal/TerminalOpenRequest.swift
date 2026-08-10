import Foundation

/// A file a command running in one of this app's panes asked to have opened.
///
/// ## Why an escape sequence at all
///
/// `abydos ~/notes.md` used to end in `open -a Abydos ~/notes.md`, and what
/// arrives at the far end of LaunchServices is "a file was opened". There is no
/// window in that, no terminal in it, and therefore no reason to move the
/// keyboard anywhere — it cannot even tell being typed in this app's terminal
/// from being typed in Ghostty, which is the whole distinction the behaviour
/// turns on.
///
/// The pty can say it, because the pane a command runs in *is* the window that
/// should answer. Nothing has to be invented for that: no socket, no port, no
/// lock file that outlives the window it names. It is the same channel OSC 52
/// already uses to put something on the clipboard on a program's say-so, with a
/// different verb.
///
/// ## The wire
///
///     ESC ] 440 ; ?                       ST     is anybody there?
///     ESC ] 440 ; abydos                  ST     the answer, from this app
///     ESC ] 440 ; open ; <base64 path>    ST     open this
///     ESC ] 440 ; open ; <base64> ; 12    ST     …and put the cursor on line 12
///
/// The path is base64 because a path is arbitrary bytes: a semicolon in a file
/// name would end the field, and a newline or an ESC would end the sequence
/// itself. OSC 52 carries its payload the same way for the same reason, and the
/// decoding is already here.
///
/// 440 is the number of the backlog entry that asked for this. It is not a
/// registered code — nothing standard claims it, and neither xterm, kitty,
/// iTerm2 nor tmux uses it — but it is a private extension, and a program that
/// emits it for some other purpose in some other terminal would be understood
/// here as asking for a file. That is the same bet OSC 52 makes about the
/// clipboard, taken knowingly.
public struct TerminalOpenRequest: Equatable, Sendable {
	/// The file, absolute. The command makes it absolute before sending it,
	/// because it is relative to the *shell's* directory and this app's is
	/// somewhere else entirely.
	public let path: String
	/// Where to put the cursor, when the command was given one.
	public let line: Int?

	public init(path: String, line: Int? = nil) {
		self.path = path
		self.line = line
	}

	/// The OSC code this travels under.
	public static let osc = 440

	/// What this app answers `ESC ] 440 ; ? ST` with.
	///
	/// Terminated with ST rather than BEL: BEL inside a tmux passthrough is the
	/// one byte that reads as a bell to whatever is in between.
	public static let reply = "\u{1B}]\(osc);abydos\u{1B}\\"

	/// The word a command looks for in the answer.
	public static let replyMarker = "\(osc);abydos"

	/// Reads the body of an `OSC 440` — everything after the code.
	///
	/// Nil for anything not understood, which is deliberately most things: this
	/// acts on a file path arriving from a program, so a body that is not
	/// exactly what was meant is one to drop rather than to guess at.
	public init?(body: String) {
		let fields = body.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
		guard fields.count >= 2, fields[0] == "open" else { return nil }

		guard let data = Data(base64Encoded: fields[1], options: .ignoreUnknownCharacters) else {
			return nil
		}
		let decoded = String(decoding: data, as: UTF8.self)
		// Absolute, because the app's working directory is not the shell's and
		// resolving a relative path here would resolve it against the wrong one.
		guard decoded.hasPrefix("/") else { return nil }
		path = decoded

		if fields.count >= 3, let number = Int(fields[2]), number > 0 {
			line = number
		} else {
			line = nil
		}
	}

	/// The sequence a command writes to ask for this file, plain and wrapped for
	/// tmux. Only the tests use it; the command builds its own, in shell.
	public var sequence: String {
		let payload = Data(path.utf8).base64EncodedString()
		let suffix = line.map { ";\($0)" } ?? ""
		return "\u{1B}]\(Self.osc);open;\(payload)\(suffix)\u{1B}\\"
	}
}
