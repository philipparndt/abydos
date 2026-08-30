import Foundation

/// Bringing work down, which this app has never been able to do.
///
/// It could push from the day it could talk to a remote at all, and there has
/// been no `fetch` and no `pull` anywhere in this folder — because a verb here
/// lives on the menu of the row that draws its object, and nothing drew *the
/// repository*. This is that verb, and the reading behind the dialog in front
/// of it.
///
/// Its own file beside `GitPush`, and for the reason that one gives: talking to
/// another machine is the one thing git does that can hang on a prompt nobody
/// can see, and whose failure is routinely somebody else's fault.
public enum GitPull {
	/// The environment every remote operation runs under.
	///
	/// Shared with `GitPush` in spirit and repeated rather than hoisted, so
	/// that a change to one is a decision about that one: an interactive git in
	/// an app with no terminal hangs with nothing on screen to say why.
	private static let unattended = [
		"GIT_TERMINAL_PROMPT": "0",
		"GIT_ASKPASS": "/usr/bin/false",
		"SSH_ASKPASS": "/usr/bin/false",
	]

	// MARK: - What the dialog opens on

	/// Whether a pull merges or rebases, and who decided.
	public enum Reconciliation: Sendable, Equatable {
		case merge
		case rebase
	}

	/// Where the answer came from.
	///
	/// **The repository outranks the app.** A project that has decided how it
	/// pulls should not be quietly overridden by somebody's preference in
	/// another program — so when `pull.rebase` is set here, that is what the
	/// dialog opens on, and it says so rather than looking like a coincidence.
	public enum Authority: Sendable, Equatable {
		/// `pull.rebase` is set in this repository or in the user's git config.
		case repository
		/// Nothing said, so the app's own default filled the gap.
		case app
	}

	public struct Preference: Sendable, Equatable {
		public let reconciliation: Reconciliation
		public let authority: Authority

		public init(reconciliation: Reconciliation, authority: Authority) {
			self.reconciliation = reconciliation
			self.authority = authority
		}

		/// What the dialog says beside the checkbox when it is not the app's
		/// choice, and nothing when it is.
		public var attribution: String? {
			guard authority == .repository else { return nil }
			return reconciliation == .rebase
				? "This repository is set to rebase when pulling"
				: "This repository is set to merge when pulling"
		}
	}

	/// What the dialog should open on.
	///
	/// - Parameter appDefault: what the app would choose if nothing else has.
	public static func preference(
		in root: URL,
		appDefault: Reconciliation
	) async -> Preference {
		let read = await GitRepository.run(["config", "--get", "pull.rebase"], in: root)
		let said = read.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

		// `--get` exits 1 when the key is not set at all, which is the common
		// case and not a failure. Anything git calls true — and `interactive`,
		// which is a rebase with a stop in it — is a rebase as far as the
		// checkbox is concerned.
		guard read.exitCode == 0, !said.isEmpty else {
			return Preference(reconciliation: appDefault, authority: .app)
		}
		let rebases = ["true", "yes", "on", "1", "interactive", "merges"].contains(said)
		return Preference(
			reconciliation: rebases ? .rebase : .merge, authority: .repository
		)
	}

	// MARK: - Doing it

	/// When the remote was last asked, or nil if it never has been here.
	///
	/// **Because every count this pane draws is only as true as the last
	/// fetch.** `1 ahead` is a statement about a tracking ref, and a tracking
	/// ref is a copy of what the remote said the last time somebody asked —
	/// which can be days ago, and nothing on screen said so. Git stamps
	/// `.git/FETCH_HEAD` on every fetch, so the answer is one `stat` and no
	/// subprocess.
	public static func lastFetch(in root: URL) async -> Date? {
		let said = await GitRepository.run(["rev-parse", "--git-path", "FETCH_HEAD"], in: root)
		let path = said.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard said.exitCode == 0, !path.isEmpty else { return nil }
		let file = path.hasPrefix("/")
			? URL(fileURLWithPath: path)
			: root.appendingPathComponent(path)
		return try? FileManager.default
			.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
	}

	/// Brings the remote's refs down without touching the working copy.
	public static func fetch(
		in root: URL,
		remote: String? = nil,
		pruning: Bool = false
	) async -> GitRepository.ProcessResult {
		var arguments = ["fetch"]
		if pruning { arguments.append("--prune") }
		if let remote { arguments.append(remote) }
		return await GitRepository.run(arguments, in: root, environment: unattended)
	}

	/// Brings work down and puts it into the branch that is checked out.
	///
	/// - Parameter rebasing: replay local commits on top rather than making a
	///   merge commit. It rewrites them, so the caller backs the branch up
	///   first — see `GitBackup`.
	/// - Parameter stashing: `--autostash`, so a dirty working copy does not
	///   stop the pull and is put back afterwards.
	public static func pull(
		in root: URL,
		remote: String? = nil,
		branch: String? = nil,
		rebasing: Bool,
		stashing: Bool
	) async -> GitRepository.ProcessResult {
		// Given as arguments and never written into the repository's config.
		// A checkbox in this app that quietly changed how `git pull` behaves in
		// somebody's terminal afterwards would be a surprise nobody could trace
		// back to it.
		var arguments = ["pull"]
		arguments.append(rebasing ? "--rebase" : "--no-rebase")
		if stashing { arguments.append("--autostash") }
		if let remote {
			arguments.append(remote)
			if let branch { arguments.append(branch) }
		}
		return await GitRepository.run(arguments, in: root, environment: unattended)
	}

	// MARK: - Why it did not work

	/// Why a fetch or a pull failed, when it is something worth saying.
	public enum Refusal: Sendable, Equatable {
		/// git wanted a credential and could not ask for one.
		case needsCredential
		/// There is no remote to talk to.
		case noRemote
		/// The working copy is in the way and autostash was not asked for.
		case workingCopyInTheWay
		/// It stopped in a conflict, which is not a failure.
		case conflicted([String])
		/// Something else, in git's own words.
		case other(String)
	}

	/// Reads a failed result for the reason worth putting on screen.
	///
	/// **A credential failure would otherwise be silence.** `GIT_TERMINAL_PROMPT=0`
	/// and an askpass of `/usr/bin/false` are right — nothing should hang on a
	/// prompt nobody can see — but they turn "this needs a password" into an
	/// exit code with very little beside it, and a pull that says nothing looks
	/// broken rather than unauthenticated.
	public static func refusal(
		from result: GitRepository.ProcessResult,
		conflicts: [String] = []
	) -> Refusal? {
		guard result.exitCode != 0 else { return nil }
		if !conflicts.isEmpty { return .conflicted(conflicts) }

		let said = (result.stderr + "\n" + result.stdout).lowercased()

		// Matched on several spellings because there are several: ssh, https
		// with a helper, https without one, and a host that refuses the key all
		// fail differently and all mean the same thing to somebody reading it.
		let credential = [
			"could not read username",
			"could not read password",
			"authentication failed",
			"permission denied (publickey",
			"terminal prompts disabled",
			"no askpass",
			"support for password authentication was removed",
		]
		if credential.contains(where: said.contains) { return .needsCredential }

		if said.contains("does not appear to be a git repository")
			|| said.contains("no such remote")
			|| said.contains("no remote repository specified") {
			return .noRemote
		}

		if said.contains("local changes")
			|| said.contains("would be overwritten")
			|| said.contains("cannot pull with rebase")
			|| said.contains("unstaged changes") {
			return .workingCopyInTheWay
		}

		let words = result.stderr.isEmpty ? result.stdout : result.stderr
		return .other(words.trimmingCharacters(in: .whitespacesAndNewlines))
	}
}
