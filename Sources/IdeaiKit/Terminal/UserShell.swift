import Foundation

/// Running a command line the way the person at the keyboard would.
///
/// A run console used `/bin/sh -lc`, which reads `/etc/profile` and
/// `~/.profile` and nothing else. Almost nobody's tools are there any more:
/// fnm, nvm, mise, asdf, pyenv, rbenv and pnpm all install themselves into
/// `~/.zshrc`, and several of them — fnm most sharply — put their binaries in a
/// directory belonging to one shell session, created when that shell starts and
/// deleted when it exits.
///
/// So `pnpm` was found or not found depending on how the app happened to be
/// launched, and a PATH inherited from a terminal went stale the moment that
/// terminal was closed. The same `make run` worked in the morning and failed in
/// the afternoon with nothing changed, and the error came from make rather than
/// from here: `pnpm: command not found`.
///
/// The shell a terminal pane runs is the user's own, logged in and interactive,
/// which is why typing the command there has always worked. A run console now
/// runs the same shell the same way, so pressing Run and typing it out reach
/// the same tools.
public enum UserShell {
	/// The login shell, as the system reports it.
	public static var path: String {
		let shell = ProcessInfo.processInfo.environment["SHELL"] ?? ""
		return shell.isEmpty ? "/bin/zsh" : shell
	}

	/// How to hand this shell one command line to run.
	///
	/// Interactive as well as login, because the file the tools write to —
	/// `.zshrc`, `.bashrc` — is only read by an interactive shell. This runs on
	/// a pty, so interactive is what it actually is; the prompt is never drawn
	/// because the shell has a command to run and exits after it.
	///
	/// `sh` is the exception: it has no interactive-only startup file, and
	/// `sh -i` merely turns on job-control noise for nothing.
	public static func invocation(
		for line: String,
		shell: String = UserShell.path
	) -> (executable: String, arguments: [String]) {
		let name = (shell as NSString).lastPathComponent
		switch name {
		case "sh", "dash":
			return (shell, ["-lc", line])
		default:
			// zsh, bash and fish all take these three together, and anything
			// else that calls itself a shell is expected to as well — a shell
			// that does not would not be able to run `-lc` either.
			return (shell, ["-lic", line])
		}
	}
}
