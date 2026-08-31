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

	/// The directories on the PATH the person at the keyboard actually has.
	///
	/// The same problem the run console had, in the place that looks for a
	/// language server: a list of well-known directories cannot keep up with
	/// where version managers put things. `npm install -g
	/// typescript-language-server` under fnm lands in
	/// `~/.local/share/fnm/node-versions/v24.15.0/installation/bin`, which no
	/// fixed list would have guessed, and nvm, mise, asdf, pyenv and rbenv each
	/// have a layout of their own. Asking the shell is the only answer that
	/// stays right.
	///
	/// Symlinks are resolved, and that is the point rather than tidiness. fnm
	/// puts a directory belonging to *one shell session* on the PATH —
	/// `~/.local/state/fnm_multishells/53245_1785944432859/bin` — which is
	/// created when that shell starts and is not ours to rely on afterwards.
	/// Resolved, it becomes the version directory it points at, which stays put.
	///
	/// Worked out once. Starting an interactive shell means running somebody's
	/// whole `.zshrc`, which is not free and does not change while the app is
	/// open.
	public static let loginPath: [String] = readLoginPath()

	/// Works the PATH out before anything needs it.
	///
	/// Whoever asks first pays for it, and the first asker is the editor opening
	/// a file — on the main thread, where a third of a second spent running
	/// somebody's `.zshrc` is a visible stall on the very first file of the
	/// session. Called at launch, the answer is already there.
	public static func warmLoginPath() {
		DispatchQueue.global(qos: .utility).async { _ = loginPath }
	}

	/// Long enough for a slow `.zshrc`, short enough not to be a hang.
	///
	/// A startup file can block — waiting on a network mount, on a version
	/// manager fetching something, on a prompt nobody will answer — and the
	/// alternative to a timeout is an editor that never opens a file.
	private static let longestWait: TimeInterval = 5

	private static func readLoginPath() -> [String] {
		// Marked where the work is rather than at a call site, because there is
		// no call site to mark: this is the initialiser of a `static let`, and it
		// runs on whichever thread asks for the value first. `warmLoginPath`
		// means that is usually a background queue and the mark is silent; when
		// it is not — somebody opened a file before the warm-up finished, and
		// then waited up to five seconds for a `.zshrc` — the log says so by name
		// instead of adding to "idle".
		StallWatch.mark("login shell path") { readLoginPathNow() }
	}

	private static func readLoginPathNow() -> [String] {
		// Fenced, because a startup file is entitled to print things and several
		// of them do. Without the markers a login banner ends up being treated
		// as a list of directories.
		let marker = "__ABYDOS_PATH__"
		let invocation = self.invocation(for: "printf '%s%s%s' '\(marker)' \"$PATH\" '\(marker)'")

		let process = Process()
		process.executableURL = URL(fileURLWithPath: invocation.executable)
		process.arguments = invocation.arguments
		let output = Pipe()
		process.standardOutput = output
		process.standardError = Pipe()
		// No terminal to read from: a startup file that asks a question gets an
		// immediate end of input rather than waiting for somebody who is not
		// there.
		process.standardInput = FileHandle.nullDevice

		guard (try? process.run()) != nil else { return [] }

		// Read on another thread: a shell that writes more than the pipe holds
		// blocks until somebody drains it, and waiting first would deadlock.
		var data = Data()
		let reading = DispatchSemaphore(value: 0)
		DispatchQueue.global(qos: .userInitiated).async {
			data = output.fileHandleForReading.readDataToEndOfFile()
			reading.signal()
		}

		if reading.wait(timeout: .now() + longestWait) == .timedOut {
			process.terminate()
			// Give the read a moment to finish once the pipe closes; if it does
			// not, there is nothing worth having.
			guard reading.wait(timeout: .now() + 1) == .success else { return [] }
		}
		process.waitUntilExit()

		let text = String(decoding: data, as: UTF8.self)
		let parts = text.components(separatedBy: marker)
		guard parts.count >= 3 else { return [] }

		var seen = Set<String>()
		var directories: [String] = []
		for entry in parts[1].split(separator: ":").map(String.init) where !entry.isEmpty {
			// A dotfile that single-quotes its export leaves `~/.dotnet/tools`
			// in the PATH with the tilde still in it — the shell searches that
			// entry literally and finds nothing, but what the person meant was
			// their home, and this app can do the expanding the quoting
			// prevented. What is still relative after that (`.` is legal in a
			// PATH) means "wherever the shell happens to stand", which for an
			// app is nowhere in particular, and is dropped.
			let stated = NSString(string: entry).expandingTildeInPath
			guard stated.hasPrefix("/") else { continue }
			// Both forms: the one the shell gave, and the one it points at. The
			// first is what the user's tools expect to see; the second is what is
			// still there tomorrow.
			for candidate in [stated, URL(fileURLWithPath: stated).resolvingSymlinksInPath().path]
			where seen.insert(candidate).inserted {
				directories.append(candidate)
			}
		}
		return directories
	}
}
