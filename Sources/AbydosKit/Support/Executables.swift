import Foundation

/// Finding a command-line tool.
///
/// An app launched from the Finder inherits almost no `PATH`. Measured on the
/// running app rather than assumed: `ps eww` on Abydos started the ordinary way
/// says `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, and nothing anybody installs is
/// in those four. So a tool that works when the app is started from a terminal
/// is missing when it is started the way people actually start it, which reads
/// as a feature that "sometimes does not work".
///
/// There used to be two answers to that in this app and they did not agree. The
/// language server search asked the login shell — the only source that keeps up
/// with a version manager, since fnm, mise, asdf and pyenv all put their
/// binaries somewhere no fixed list would guess — and everything else made do
/// with four well-known directories. Two things came of that, both measured on
/// this machine with the `PATH` a Dock-launched app actually has:
///
/// - **A tool only the version manager knows about was invisible.** `cargo` is
///   `~/.cargo/bin/cargo`, and so is `rustc`; neither is in any of the four. So
///   the app could start `openscad-lsp` out of `~/.cargo/bin`, because that
///   went through the language server search, and could not find the `cargo`
///   beside it, because that went through this one. `DevPod` asks for `cargo`
///   and `zig` by name.
/// - **A tool in both places was a different program here and in the
///   terminal.** `docker` resolved to `/usr/local/bin/docker` — OrbStack's
///   client, 29.4.0 — while a terminal pane in the same app runs
///   `~/.rd/bin/docker`, Rancher Desktop's 29.1.4-rd, because `~/.rd/bin` is
///   first on the login shell's `PATH` and in none of the four. Here the two
///   turned out to be clients of one daemon and nothing was lost by it. That
///   was luck about how this machine happens to be set up, and 0427 — the entry
///   that led here — is this same shape one floor up: two copies of one tool,
///   and the app quietly picking the one the build is not using.
///
/// One search now, and it is this one. A tool this app runs and the same tool
/// typed into a terminal pane beside it have to be the same file.
public enum Executables {
	/// The directories searched for a tool, in order.
	///
	/// Three sources, and the order is the point. What this process was given
	/// first, so a `PATH` somebody set deliberately still chooses the tool; then
	/// the `PATH` their login shell has, which is where a version manager puts
	/// things and the only source that keeps up with them; then the well-known
	/// directories, as a floor for when the shell cannot be asked.
	public static var searchPaths: [String] {
		paths(given: ProcessInfo.processInfo.environment["PATH"], login: UserShell.loginPath)
	}

	/// Where tools live when `PATH` does not say.
	///
	/// A floor rather than an answer: no fixed list keeps up with fnm, mise,
	/// asdf or pyenv, which is what the login shell is asked for. These are the
	/// places a tool is still found when that ask fails.
	public static let toolDirectories: [String] = {
		let home = FileManager.default.homeDirectoryForCurrentUser.path
		return [
			"/opt/homebrew/bin",
			"/usr/local/bin",
			"/usr/bin",
			"/bin",
			"/usr/local/go/bin",
			"\(home)/go/bin",
			"\(home)/.cargo/bin",
			"\(home)/.local/bin",
			"\(home)/.bun/bin",
			"\(home)/.volta/bin",
		]
	}()

	/// The full path of a tool, or nil when it is not installed.
	public static func locate(_ name: String) -> String? {
		locate(name, path: ProcessInfo.processInfo.environment["PATH"])
	}

	/// - Parameters:
	///   - path: a `PATH` to search first, as the environment gives it.
	///     Separate so the search can be tested without one.
	///   - loginPath: what the person's own shell has. Separate for the same
	///     reason — the real one is a real shell on a real machine, and a test
	///     that asserted on it would be describing that machine.
	public static func locate(
		_ name: String,
		path: String?,
		loginPath: [String] = UserShell.loginPath
	) -> String? {
		let manager = FileManager.default
		// The list went from eight directories to forty-three, and the tmux
		// mirror asks this several times a second, so it was counted rather than
		// waved at. On this machine, with the `PATH` a Dock-launched app
		// actually has: finding `tmux` went from 0.016 ms to 0.042 ms, and the
		// worst case — a tool that is nowhere, so every directory is tried —
		// from 0.023 ms to 0.097 ms. The expensive part is not here at all: it
		// is the login shell behind `UserShell.loginPath`, worked out once per
		// process and warmed at launch before anything asks.
		for directory in paths(given: path, login: loginPath) {
			let candidate = directory + "/" + name
			if manager.isExecutableFile(atPath: candidate) { return candidate }
		}
		return nil
	}

	private static func paths(given path: String?, login: [String]) -> [String] {
		let all = (path?.split(separator: ":").map(String.init) ?? [])
			+ login
			+ toolDirectories

		var seen = Set<String>()
		return all.filter { !$0.isEmpty && seen.insert($0).inserted }
	}
}
