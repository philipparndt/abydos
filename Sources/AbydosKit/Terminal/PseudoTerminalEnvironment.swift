import Foundation

/// What a shell started here is given to work with, and what it is not.
///
/// Built before the fork and kept apart from it, so that what this app puts
/// into a shell's environment — and what it refuses to pass on — can be
/// checked without starting a process.
extension PseudoTerminal {
	/// The environment a shell in this app is started with.
	///
	/// Built before the fork, and separated out so what it puts there can be
	/// checked without starting anything.
	static func mergedEnvironment(
		_ given: [String: String]?,
		bundled: String?,
		app: String? = BundledCommands.appBundle,
		inherited: [String: String] = ProcessInfo.processInfo.environment
	) -> [String: String] {
		// **What is given is added to the app's environment, not put in place
		// of it.** This was `given ?? inherited`, so the first caller ever to
		// pass a variable — the tab naming itself `ABYDOS_TERMINAL` — started
		// its shell with that one variable and the few below: no `PATH`, no
		// `HOME`, no `USER`, no `SSH_*`. A login shell rebuilds enough from the
		// profile that the pane still worked, which is why it took two
		// screenshots to see: a prompt drew a user segment nobody had asked for,
		// because the prompt's own rule for hiding it reads a variable that was
		// no longer there.
		//
		// Nobody ever wanted the other meaning. A pane is the app's environment
		// plus whatever this particular pane is; every caller passing a
		// dictionary is naming the second.
		var merged = inherited
		for (key, value) in given ?? [:] { merged[key] = value }
		// Claim a capable terminal so tools enable colour and full-screen UI.
		merged["TERM"] = merged["TERM"] ?? "xterm-256color"
		merged["COLORTERM"] = merged["COLORTERM"] ?? "truecolor"
		merged["LANG"] = merged["LANG"] ?? "en_US.UTF-8"
		// This terminal shows OSC 8 hyperlinks, said in the one word the
		// `supports-hyperlinks` convention reads. Claude Code writes a styled
		// link — its `#211` for a pull request — only for a terminal it
		// recognises by `TERM_PROGRAM`, or inside tmux 3.4 or newer, or when
		// this is set; a bare pane of ours is none of the first and was plain
		// text where Ghostty had a link (reported 2026-09-11). Defaulted, so a
		// `0` somebody exported to say no is theirs; and not `TERM_PROGRAM`
		// set to a terminal this is not, which is the lie the comment below is
		// about.
		merged["FORCE_HYPERLINK"] = merged["FORCE_HYPERLINK"] ?? "1"
		// **`PAGER` is deliberately not set.** It was `cat` here, to stop a
		// pager hanging a pane waiting for a keypress — true of a terminal that
		// could not run a full-screen program, and this one runs `vim`, `htop`,
		// `claude`'s own full-screen UI and tmux. A pager is that same class of
		// program.
		//
		// The `??` it was written with looked like deference and was not: this
		// dictionary starts from the *app's* environment, and a `PAGER` exported
		// from a profile is set by the shell that runs inside the pane, long
		// after the fork. So the app's value was what `git` saw, `git log`
		// printed everything and returned to the prompt, and it read as this
		// terminal being broken — which is how it was reported. Every tool the
		// pane started inherited it, not only `git log`.

		// Which terminal this is, by the name every other terminal uses for
		// itself. `abydos <file>` reads it to decide whether the escape that
		// opens a file in this window is worth writing at all, and any inherited
		// value is a lie here — the app launched from Ghostty inherits
		// `TERM_PROGRAM=ghostty`, and a pane of ours claiming to be Ghostty is
		// exactly the wrong answer. So it is set rather than defaulted.
		merged["TERM_PROGRAM"] = BundledCommands.termProgram
		// Which build to fall back to when the escape does not reach anybody.
		// Without it the command opens `/Applications/Abydos.app`, which is not
		// the app somebody running a checkout is looking at.
		if let app { merged["IDEAI_APP"] = app }

		// And a pane is not inside tmux until something in it starts tmux.
		//
		// The same lie as `TERM_PROGRAM`, and inherited the same way: an app
		// launched from a shell that is inside tmux — which is how anybody
		// running `make run` launches it — hands `TMUX` to every pane it opens,
		// naming a session none of them is in. `abydos <file>` believed it,
		// wrapped its question in a tmux passthrough nothing was there to
		// unwrap, heard no answer, and quietly opened the file through
		// LaunchServices instead of in the window it was typed in. It cost an
		// afternoon to see, because every part of it behaved correctly given
		// what it had been told.
		//
		// Removed rather than blanked: a shell that finds `TMUX` set to the
		// empty string is in no tmux either, but tmux itself sets the variable
		// when it starts, and something that has to be right for both wants the
		// absence rather than a second spelling of it. A pane that goes on to
		// run `tmux new -A` gets its own from tmux, which is the only thing
		// entitled to say so.
		merged["TMUX"] = nil
		merged["TMUX_PANE"] = nil

		// And one variable further along, for the same reason and with a louder
		// ending. `TMUX_TMPDIR` says where tmux keeps its sockets, it is
		// inherited exactly as `TMUX` was, and tmux appends `tmux-<uid>/default`
		// to it — so a directory that is merely long produces a socket path over
		// the length a unix socket can have. tmux says `File name too long` and
		// the pane is dead before it draws a prompt, naming a path nobody typed.
		//
		// Refused on what it produces rather than on being set at all: somebody
		// with a short, valid one means it, and taking it away would put their
		// panes on a different server from their other tools. `TmuxSocketPath`
		// has the arithmetic and the sentence the pane is given.
		merged = TmuxSocketPath.honouringWhatFits(merged)

		// The commands this app ships — `abydos-icat`, `abydos-bench` — on the
		// PATH of every shell it starts, without an install step. Appended
		// rather than prepended: a command somebody already has wins, since
		// shadowing what is on somebody's PATH is not this app's business.
		if let bundled {
			let path = merged["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
			if !path.split(separator: ":").contains(Substring(bundled)) {
				merged["PATH"] = path + ":" + bundled
			}
		}
		return merged
	}

	/// What the merge above threw away, ready to be written to a pane.
	///
	/// Separate from the merge because the two answers go to different places:
	/// one to `execve`, one to whoever is looking. Both are worked out from the
	/// same input, so a value refused is always a value explained.
	///
	/// It ends `\r\n` rather than `\n`: this goes to a terminal in raw mode,
	/// where a bare newline drops a line without returning to column one, and
	/// the shell's prompt would then start under the end of the sentence.
	static func refusals(
		_ given: [String: String]?,
		inherited: [String: String] = ProcessInfo.processInfo.environment
	) -> String? {
		let environment = given ?? inherited
		guard let refusal = TmuxSocketPath.refusal(for: environment["TMUX_TMPDIR"]) else {
			return nil
		}
		return refusal + "\r\n"
	}
}
