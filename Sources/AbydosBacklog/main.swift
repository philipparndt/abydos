import Foundation
import AbydosKit

// The backlog, from a terminal.
//
// Its own binary rather than a verb on the app: `abydos` opens a window, and
// the whole point of this one is that it runs where an agent runs — in a
// worktree, over ssh, from a `make` goal — none of which is a place a Mac
// application can be started. It links AbydosKit for the model and nothing
// else, so it is the same code the dashboard reads.
let status = await BacklogCommands.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(status)
