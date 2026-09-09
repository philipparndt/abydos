import AppKit
import AbydosKit

/// The two pills in the titlebar, and the terminal one of them opens.
///
/// Together because every one of these exists for the same reason: a pill is in
/// the titlebar, which a window rendering leaves out, and the reading that
/// matters is nearly always that the pill is *absent* — which a screenshot can
/// never prove, an empty toolbar looking exactly like one that has not finished
/// loading.
extension LaunchOptions {
	struct Pills {
		/// Open a terminal in the project's devcontainer and report what is in it.
		var terminal = false

		/// Which of them, when the project offers several: a number counting from
		/// one in the order the menu offers them, or "all" for one terminal in each,
		/// each after the last has answered. Nil is the one the View menu opens.
		var which: String?

		/// Print what the titlebar's devcontainer pill says, this many seconds in.
		///
		/// A pill in the titlebar cannot be read from a window rendering, which
		/// leaves out sheets and menus and is what the rest of these dumps exist
		/// for; and the thing worth checking is that it is *absent* for a project
		/// whose container was declined, which a screenshot can never prove — an
		/// empty toolbar looks the same as one that has not finished loading.
		/// Several times rather than one, because the pill has to be read before and
		/// after a project is switched away from and back to (0438).
		var devContainerAt: [Double] = []

		/// Print what the pill's menu offers, this many seconds in — which is where
		/// the way back out of a decline lives, and a menu cannot be photographed
		/// while it is open.
		var devContainerMenuAt: Double?

		/// Print what the titlebar's worktree pill says, at each of these many
		/// seconds in.
		///
		/// The two readings that matter are both invisible to a screenshot: a
		/// repository with one checkout has no pill, which looks like a toolbar that
		/// has not loaded; and on the primary the pill is an icon with no words, so
		/// there is nothing on screen saying which checkout it stands for. Several
		/// times rather than one, because the pill is filled in when git answers and
		/// again when the toolbar builds its items, and those arrive in either order.
		var worktreeAt: [Double] = []

		/// Print what the worktree pill's menu offers, this many seconds in — which
		/// on a repository with seventy-odd checkouts is the whole of what this is
		/// for, and a menu cannot be photographed while it is open.
		var worktreeMenuAt: Double?

		/// Press the pill menu's entry whose words are these: `<the words>@<seconds>`.
		/// Repeatable, because leaving a container and going back into it is one
		/// run and the second half is the interesting half (0438).
		var pressDevContainer: [String] = []
	}
}
