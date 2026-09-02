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
		/// Whether anything has been committed on the branch. False in a
		/// repository that has been `git init`ed and not committed to yet: the
		/// branch is real and it is named, and there is no commit to send.
		public let hasCommits: Bool
		/// The branch tracks an upstream that no longer exists — the usual
		/// cause being a remote branch deleted after it was merged.
		///
		/// Distinguished from level on purpose. `%(upstream:track)` says
		/// `[gone]` where it would otherwise say the counts, so a gone upstream
		/// parses as nought behind and nought ahead and reads as *level with
		/// the remote* — which is a sentence about a ref that is not there.
		public let upstreamIsGone: Bool

		public init(
			branch: String,
			upstream: String? = nil,
			ahead: Int = 0,
			behind: Int = 0,
			hasRemote: Bool = true,
			hasCommits: Bool = true,
			upstreamIsGone: Bool = false
		) {
			self.branch = branch
			self.upstream = upstream
			self.ahead = ahead
			self.behind = behind
			self.hasRemote = hasRemote
			self.hasCommits = hasCommits
			self.upstreamIsGone = upstreamIsGone
		}

		/// Pushing would do something.
		public var canPush: Bool {
			guard hasCommits, hasRemote else { return false }
			return upstream == nil || ahead > 0
		}

		/// What a button offering the push should say.
		public var buttonTitle: String {
			guard hasRemote, hasCommits else { return "Push" }
			if upstream == nil { return "Publish Branch" }
			return ahead > 0 ? "Push \(ahead)" : "Push"
		}

		/// How many commits the push would send, for a button that shows the
		/// number as a tag beside the word rather than inside it — so the
		/// word keeps its width from one refresh to the next. Nil when the
		/// title carries no number.
		public var buttonCount: Int? {
			guard hasRemote, hasCommits, upstream != nil, ahead > 0 else { return nil }
			return ahead
		}

		/// `buttonTitle` without the number, for a button that shows the
		/// number as `buttonCount`.
		public var buttonWord: String { buttonCount == nil ? buttonTitle : "Push" }

		/// Why the button is the way it is, for the tooltip on it.
		///
		/// Here rather than in the pane so that every reason is written in one
		/// place and can be checked without a window: the unborn branch is the
		/// case that used to reach the pane as `nil` and read "Push this
		/// branch", which is the one thing this repository cannot do.
		public var explanation: String {
			guard hasCommits else { return "“\(branch)” has no commits yet" }
			guard hasRemote else { return "This repository has no remote" }
			guard let upstream else { return "Push “\(branch)” to origin and track it" }
			if ahead == 0 { return "Nothing to push to \(upstream)" }
			return "Push \(ahead) commit\(ahead == 1 ? "" : "s") to \(upstream)"
		}
	}

	public static func state(in root: URL) async -> State? {
		async let headRead = GitRepository.head(in: root)
		async let remotesResult = GitRepository.run(["remote"], in: root)

		let head = await headRead
		// Detached, or not a work tree at all: there is no branch to push, and
		// nothing true to say about one either.
		guard let branch = head.name else { return nil }

		let hasRemote = await !remotesResult.stdout
			.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

		// An unborn branch used to come back nil here too — the comment said
		// "or a repository with no commits" and meant it — and the page then
		// offered a disabled Push whose tooltip said "Push this branch". The
		// push itself is still impossible: `git push -u origin main` from here
		// has no ref to send and fails. What changed is that the state can now
		// say *which* branch has nothing on it, which is the difference between
		// a refusal and silence.
		guard !head.isUnborn else {
			return State(branch: branch, hasRemote: hasRemote, hasCommits: false)
		}

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
		let track = fields.count > 2 ? fields[2] : ""
		let counts = GitBranches.parseTracking(track)
		let isGone = upstream != nil && track.contains("gone")

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
			hasRemote: hasRemote,
			upstreamIsGone: isGone
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
