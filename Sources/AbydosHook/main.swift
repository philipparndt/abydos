import Foundation
import AbydosKit

// The Claude Code hook, as a binary of its own.
//
// Claude Code runs this on every event of every session — several times per
// tool call — so what it costs to *start* is most of what it costs. The app
// itself would do the same work, but it links AppKit and everything the editor
// needs, and paying a tenth of a second of dynamic linking for a line of JSON
// would be felt in every session on the machine.
let arguments = CommandLine.arguments.dropFirst()

switch arguments.first {
case "hook", "claude-hook", nil:
	ClaudeHookRunner.run()
case "install", "remove", "status":
	ClaudeHookCommands.runSetup(arguments.first ?? "status", hookBinary: CommandLine.arguments[0])
default:
	FileHandle.standardError.write(Data("""
	abydos-hook — tells ideai what Claude Code sessions are doing

	  abydos-hook            run as a hook (reads the event JSON on stdin)
	  abydos-hook install    wire it into ~/.claude/settings.json
	  abydos-hook remove     take it back out
	  abydos-hook status     say whether it is wired up

	""".utf8))
	exit(2)
}
