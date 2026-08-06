import Foundation

/// Sending commits to a remote.
///
/// Its own file rather than a method on the working copy, because pushing is
/// the one git operation that talks to another machine: it can hang on a
/// password prompt nobody can see, and it is the only one whose failure is
/// routinely somebody else's fault.
public enum GitPush {
	/// What the current branch is, and where it goes when pushed.
	public struct State: Equatable, Sendable {
		public let branch: String
		/// Nil when the branch has never been pushed.
		public let upstream: String?
		public let ahead: Int
		public let behind: Int
		/// Whether the repository has any remote at all.
		public let hasRemote: Bool

		public init(
			branch: String,
			upstream: String? = nil,
			ahead: Int = 0,
			behind: Int = 0,
			hasRemote: Bool = true
		) {
			self.branch = branch
			self.upstream = upstream
			self.ahead = ahead
			self.behind = behind
			self.hasRemote = hasRemote
		}

		/// Pushing would do something.
		public var canPush: Bool {
			guard hasRemote else { return false }
			return upstream == nil || ahead > 0
		}

		/// What a button offering the push should say.
		public var buttonTitle: String {
			guard hasRemote else { return "Push" }
			if upstream == nil { return "Publish Branch" }
			return ahead > 0 ? "Push \(ahead)" : "Push"
		}
	}

	public static func state(in root: URL) async -> State? {
		async let branchResult = GitRepository.run(["rev-parse", "--abbrev-ref", "HEAD"], in: root)
		async let remotesResult = GitRepository.run(["remote"], in: root)

		let branch = await branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		// Detached, or a repository with no commits: there is no branch to push.
		guard await branchResult.exitCode == 0, !branch.isEmpty, branch != "HEAD" else { return nil }

		let hasRemote = await !remotesResult.stdout
			.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

		let format = ["%(refname:short)", "%(upstream:short)", "%(upstream:track)"]
			.joined(separator: "\u{1F}")
		let details = await GitRepository.run(
			["for-each-ref", "--format=\(format)", "refs/heads/\(branch)"],
			in: root
		)
		let fields = details.stdout
			.trimmingCharacters(in: .newlines)
			.components(separatedBy: "\u{1F}")

		let upstream = fields.count > 1 && !fields[1].isEmpty ? fields[1] : nil
		let counts = GitBranches.parseTracking(fields.count > 2 ? fields[2] : "")

		// A branch that was never pushed reports no counts, and every commit on
		// it is one the remote has not seen.
		let ahead = upstream == nil
			? await GitHistory.unpushed(in: root).count
			: counts.ahead

		return State(
			branch: branch,
			upstream: upstream,
			ahead: ahead,
			behind: counts.behind,
			hasRemote: hasRemote
		)
	}

	/// Pushes the current branch, setting its upstream the first time.
	///
	/// Never interactively: a git that asks for a password does it on a
	/// terminal this app does not have, and the push would hang forever with
	/// nothing on screen to say why. Refusing to prompt turns that into an
	/// error message, which can at least be read.
	/// - Parameter branch: which branch to send, or nil for the one checked
	///   out. Naming one is what makes a branch pushable from a list without
	///   checking it out first.
	public static func push(
		in root: URL,
		setUpstream: Bool,
		branch: String? = nil
	) async -> GitRepository.ProcessResult {
		var arguments = ["push"]
		if setUpstream { arguments.append("--set-upstream") }
		arguments.append("origin")
		arguments.append(branch ?? "HEAD")

		return await GitRepository.run(
			arguments,
			in: root,
			environment: [
				"GIT_TERMINAL_PROMPT": "0",
				"GIT_ASKPASS": "/usr/bin/false",
				"SSH_ASKPASS": "/usr/bin/false",
			]
		)
	}
}
