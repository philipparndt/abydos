import Foundation

/// A "do not ask me again" answer, and the repository it was given for.
///
/// **The key is the point.** An estate turns "always stash" into a decision
/// about two or three hundred repositories, taken while looking at one of them.
/// Nobody consented to that scope: the answer was about `svc-3`, given while
/// `svc-3` was on screen, and applying it to `svc-47` a minute later is the
/// safety net deciding something on somebody's behalf.
///
/// So an answer is filed under the repository it was given for as well as the
/// operation it was about, and a repository that has never been answered for is
/// asked.
///
/// It is also why this exists at all: the suppression checkbox has been drawn on
/// the safety net's alert since it was written and its state was never read
/// back, so nothing was ever remembered and the box did nothing. Making it work
/// and making it per repository are the same change, and doing the first without
/// the second is what this file exists to prevent.
public enum RememberedChoice {
	/// Where an answer is filed.
	///
	/// The repository's path rather than its name: two submodules called
	/// `common` in different parts of an estate are different repositories, and
	/// a key that could not tell them apart would carry an answer from one to
	/// the other — the exact failure this is keyed to avoid.
	public static func key(operation: String, in root: URL) -> String {
		"safety.\(operation).\(root.standardizedFileURL.path)"
	}

	/// Whether the safe answer has been remembered for this repository.
	public static func isRemembered(
		operation: String, in root: URL, reading defaults: UserDefaults = DrivenRun.defaults
	) -> Bool {
		defaults.bool(forKey: key(operation: operation, in: root))
	}

	/// Records that the safe answer may be taken without asking, here.
	///
	/// Only ever the answer that loses nothing — which `GitDestructive.Choice`
	/// `.mayBeRemembered` decides and this does not second-guess. `Always
	/// discard` is not a thing this program will ever store.
	public static func remember(
		operation: String, in root: URL, writing defaults: UserDefaults = DrivenRun.defaults
	) {
		defaults.set(true, forKey: key(operation: operation, in: root))
	}

	public static func forget(
		operation: String, in root: URL, writing defaults: UserDefaults = DrivenRun.defaults
	) {
		defaults.removeObject(forKey: key(operation: operation, in: root))
	}
}
