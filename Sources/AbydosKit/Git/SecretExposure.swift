import Foundation

/// What git can see of a file whose values the editor conceals.
///
/// **Concealment is for the shared screen; this is for the repository.** The
/// covers go on a `.env` the moment it opens, and say nothing at all about the
/// far worse exposure — that the file is about to be committed, pushed and
/// read by everybody who clones it. The navigator has asked
/// `git status --ignored` for its tints since it was written and
/// `BacklogCommands` asks `git check-ignore` for the paths it writes; neither
/// answer ever reached the editor, which is where somebody is looking at the
/// file.
///
/// Two questions, one path each, because the two have different next steps: a
/// file git merely has not been told to ignore can be fixed with a line in
/// `.gitignore`; a file git already tracks cannot, the values being in the
/// history whatever the working tree does now.
public enum SecretExposure {
	/// What git makes of the file.
	public enum State: Equatable, Sendable {
		/// Ignored, or not a repository at all, or a file that conceals
		/// nothing: there is nothing to say, and the bar says nothing.
		case fine
		/// Neither ignored nor tracked — the case a line in `.gitignore` fixes.
		case notIgnored
		/// Already committed. Ignoring it now changes nothing about the
		/// history, and the wording must not pretend otherwise.
		case tracked
	}

	/// The chip's words, in the engine so the bar, the tooltip, the driven
	/// report and the spec's scenarios all read the same three.
	public static func words(for state: State) -> String? {
		switch state {
		case .fine: return nil
		case .notIgnored: return "Not in .gitignore"
		case .tracked: return "Committed to git"
		}
	}

	/// The consequence, said in a sentence, for the tooltip.
	public static func consequence(for state: State) -> String? {
		switch state {
		case .fine:
			return nil
		case .notIgnored:
			return "Git is not ignoring this file. Committing it commits the values under "
				+ "these covers. Right-click it in the project tree to add it to .gitignore."
		case .tracked:
			return "Git already tracks this file, so its values are in the history. "
				+ "Removing it now takes it out of the working tree and not out of the past."
		}
	}

	/// Asks git about one path: ignored (nothing to say), tracked, or neither.
	///
	/// `git check-ignore -q` exits 0 when a path is ignored and 1 when it is
	/// not; `git ls-files --error-unmatch` exits 0 when a path is tracked. Any
	/// other exit — no repository, git missing, a path outside the root — is
	/// `fine`, because a notice this cannot stand behind is worse than none.
	///
	/// Tracked is asked first and answers on its own: git ignores nothing it
	/// already tracks, so a `.gitignore` line matching a committed file is a
	/// line that does nothing, and "not ignored" would be the wrong sentence
	/// to put in front of somebody.
	public static func state(of file: URL, in root: URL, conceals: Bool) async -> State {
		guard conceals else { return .fine }
		let path = file.path
		let tracked = await GitRepository.run(["ls-files", "--error-unmatch", path], in: root)
		if tracked.exitCode == 0 { return .tracked }
		let ignored = await GitRepository.run(["check-ignore", "-q", path], in: root)
		switch ignored.exitCode {
		case 0: return .fine
		case 1: return .notIgnored
		// 128 and the rest: not a repository, or git could not answer. A
		// notice nobody can act on is not worth interrupting a file for.
		default: return .fine
		}
	}
}
