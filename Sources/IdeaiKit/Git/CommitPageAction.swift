import Foundation

/// Which of the commit page's two buttons is the one to press.
///
/// Commit and push sit side by side, and only one of them can be the primary —
/// the accented button that Return also triggers. Which one is not a matter of
/// taste: with files staged the page is there to make a commit, and with
/// nothing staged the only thing left to do is send what is already committed.
public enum CommitPageAction: Equatable, Sendable {
	case commit
	case push
	/// Neither: a clean working copy that is level with its remote.
	case none

	/// Decides from the state of the page.
	///
	/// Amending counts as something to commit even with an empty index —
	/// rewording the last commit is a normal thing to be here for.
	public static func primary(
		staged: Int,
		isAmending: Bool,
		canPush: Bool
	) -> CommitPageAction {
		if staged > 0 || isAmending { return .commit }
		return canPush ? .push : .none
	}
}
