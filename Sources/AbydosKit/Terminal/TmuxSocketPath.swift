import Darwin
import Foundation

/// The socket tmux would open, and whether it is a path that can exist.
///
/// A unix socket is bound by copying its path into `sockaddr_un.sun_path`,
/// which is a fixed array — so the path has a hard length, and a path over it
/// is not slow or unusual but impossible. tmux copies with `strlcpy` and checks
/// the overflow, so what somebody sees is tmux's own sentence, `File name too
/// long`, naming a path they never typed.
///
/// This exists because that happened: `TMUX_TMPDIR` was set in the shell the
/// app was launched from, every pane inherited it, and tmux appended its own
/// two components to a directory that was already 116 bytes. The pane died
/// before it drew a prompt, with a path in it that had nothing to do with the
/// project somebody had opened.
public enum TmuxSocketPath {
	/// The longest a unix socket path may be: the field, less its terminator.
	///
	/// Measured rather than written down, because 104 is a fact about this
	/// platform's headers and not one this app is entitled to assume. It comes
	/// to 103 on macOS 26, and both ends of that were checked by hand: a socket
	/// bound at 103 bytes, and one at 104 refused with `ENAMETOOLONG`.
	///
	/// The terminator is subtracted because tmux is the thing being predicted
	/// here, and tmux writes the path with `strlcpy` — which always terminates,
	/// so 104 bytes of path is one byte too many for it even though the kernel
	/// would take the field filled to its end.
	public static let limit = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

	/// What tmux calls the socket when nobody has said otherwise.
	///
	/// `-L <name>` chooses another, and a pane is free to do that — so this is a
	/// prediction rather than a certainty. It is the right one to make: it is
	/// what every pane gets that does not opt out, and a wrong guess here is a
	/// refusal that was slightly too eager rather than a pane that dies.
	public static let defaultLabel = "default"

	/// The socket tmux opens for a directory: `<directory>/tmux-<uid>/<label>`.
	///
	/// Resolved first, and that is the part worth knowing rather than a
	/// tidy-up: tmux calls `realpath` before it measures, so
	/// `TMUX_TMPDIR=/tmp/…` is measured as `/private/tmp/…` — eight bytes
	/// longer than it looks. A 79-byte value under `/tmp` is refused by tmux
	/// while the arithmetic on what was typed says it fits with room to spare,
	/// which was checked against tmux 3.7b rather than reasoned about.
	public static func path(
		under directory: String,
		uid: uid_t = getuid(),
		label: String = defaultLabel
	) -> String {
		"\(resolved(directory))/tmux-\(uid)/\(label)"
	}

	/// The directory as tmux will see it.
	///
	/// `realpath(3)`, and deliberately not Foundation's
	/// `resolvingSymlinksInPath`, which is not the same function: asked about
	/// `/private/tmp/x` it answers `/tmp/x`, because it strips a leading
	/// `/private` whenever the shorter form also exists — which under `/tmp` it
	/// always does. That is eight bytes shorter than tmux measures, and short
	/// in the one direction that matters, since it would pass a directory tmux
	/// then refuses.
	///
	/// A path that is not there yet resolves as far as it goes and keeps the
	/// rest: tmux creates only `<directory>/tmux-<uid>`, so the directory
	/// itself is normally already there — but resolving nothing at all would
	/// again answer short for anything written under `/tmp`.
	static func resolved(_ directory: String) -> String {
		var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
		if let existing = realpath(directory, &buffer) { return String(cString: existing) }

		var missing: [String] = []
		var url = URL(fileURLWithPath: directory).standardizedFileURL
		while url.path != "/", !url.path.isEmpty {
			missing.append(url.lastPathComponent)
			url = url.deletingLastPathComponent()
			guard let existing = realpath(url.path, &buffer) else { continue }
			let base = String(cString: existing)
			let rest = missing.reversed().joined(separator: "/")
			return base == "/" ? "/" + rest : base + "/" + rest
		}
		return directory
	}

	/// Whether tmux could open a socket under this directory.
	public static func fits(
		_ directory: String,
		uid: uid_t = getuid(),
		label: String = defaultLabel
	) -> Bool {
		path(under: directory, uid: uid, label: label).utf8.count <= limit
	}

	/// What to say when a `TMUX_TMPDIR` has to be refused, or nothing when
	/// there is nothing to refuse.
	///
	/// A sentence rather than a flag, because the only place this can be said
	/// is a terminal pane and the person reading it has just watched one fail.
	/// It names the variable, the number, and what happens instead — the three
	/// things tmux's own message left them to guess.
	public static func refusal(
		for directory: String?,
		uid: uid_t = getuid(),
		label: String = defaultLabel
	) -> String? {
		guard let directory, !directory.isEmpty else { return nil }
		let socket = path(under: directory, uid: uid, label: label)
		let length = socket.utf8.count
		guard length > limit else { return nil }
		return """
		Abydos: leaving TMUX_TMPDIR out of this shell. It was inherited from \
		wherever the app was launched, and the socket tmux would open under it \
		— \(socket) — is \(length) bytes, where a unix socket path can be at \
		most \(limit). tmux would have exited with "File name too long" before \
		this pane drew a prompt. tmux started here uses its own directory \
		instead.
		"""
	}

	/// An environment safe to hand to anything that may talk to tmux.
	///
	/// The variable is removed rather than corrected. Where it should point
	/// instead is not this app's guess to make — tmux has a default, it is the
	/// one every other tool on the machine falls back to, and putting a
	/// directory of our own choosing there would move somebody's panes onto a
	/// server their other tools cannot see. Absence is the only answer that
	/// leaves tmux deciding.
	///
	/// And only when it does not fit. Somebody who has set a short, valid
	/// `TMUX_TMPDIR` means it: their panes belong on the same server as their
	/// other tools, and taking it away would be the same class of mistake as
	/// ignoring their `PATH`.
	/// What to give a `Process` that is about to run tmux.
	///
	/// A pane is not the only thing in this app that talks to tmux: the tab
	/// strip asks the server for its windows, following a terminal asks which
	/// directory its pane is in, hiding the status line sets an option, and the
	/// Claude hook writes a badge. None of those sets an environment, so all of
	/// them inherited the same doomed `TMUX_TMPDIR` — and all of them send
	/// tmux's stderr to the null device and turn a failure into `nil`, `false`
	/// or an empty list. So while a pane at least died loudly, the strip simply
	/// showed nothing and no message was written anywhere.
	///
	/// `$TMUX` does not rescue them, which was worth checking rather than
	/// assuming: tmux works its socket path out from `TMUX_TMPDIR` whether or
	/// not it is already inside a session, so a client with both set still goes
	/// looking for the path that cannot exist.
	public static var environment: [String: String] {
		honouringWhatFits(ProcessInfo.processInfo.environment)
	}

	public static func honouringWhatFits(
		_ environment: [String: String],
		uid: uid_t = getuid(),
		label: String = defaultLabel
	) -> [String: String] {
		guard let directory = environment["TMUX_TMPDIR"], !directory.isEmpty,
		      !fits(directory, uid: uid, label: label)
		else { return environment }
		var refused = environment
		refused["TMUX_TMPDIR"] = nil
		return refused
	}
}
