import Foundation

/// Closing several tmux sessions in one go, from the session tag's menu.
///
/// **What the list of sessions turns into after a while.** Every project's
/// terminal starts in a session named after its folder, and a terminal that
/// was moved elsewhere left that session behind: one window, a shell nobody
/// typed in, and a name in `C-b s` for ever after. Twenty-five of them on one
/// server when this was written, and `tmux kill-session` twenty-four times is
/// not an answer anybody gives.
///
/// The decisions — what is offered, what may be closed, what is said — are here
/// so they can be checked without a server; the sheet that draws checkboxes is
/// the app's.
public enum TmuxSessionClosing {
	/// One session as the sheet offers it.
	public struct Offer: Equatable, Sendable {
		public let name: String
		public let windowCount: Int
		public let isAttached: Bool
		/// The session this window's tabs are showing. Listed, so the list is
		/// the whole list, but not closable from here: closing the session
		/// under the tabs is what closing its last window does, and doing it
		/// from a sheet about *other* sessions would take the terminal with
		/// it while somebody was tidying.
		public let isShowing: Bool

		public init(name: String, windowCount: Int, isAttached: Bool, isShowing: Bool) {
			self.name = name
			self.windowCount = windowCount
			self.isAttached = isAttached
			self.isShowing = isShowing
		}

		public var isClosable: Bool { !isShowing }

		/// What stands beside the name: how much would go, and whether anybody
		/// is looking at it.
		public var detail: String {
			var said = "\(windowCount) window\(windowCount == 1 ? "" : "s")"
			if isShowing {
				said += " · this window's tabs"
			} else if isAttached {
				said += " · attached"
			}
			return said
		}
	}

	/// The sessions as the sheet lists them: the order tmux cycles through
	/// them, which is the order the menu above the sheet just showed.
	public static func offers(
		_ sessions: [TmuxMirror.SessionSummary], showing: String?
	) -> [Offer] {
		sessions.map { summary in
			Offer(
				name: summary.name,
				windowCount: summary.windowCount,
				isAttached: summary.isAttached,
				isShowing: summary.name == showing
			)
		}
	}

	/// Whether the session tag's menu should carry *Close Sessions…* at all.
	///
	/// Only with something it could close. A server holding nothing but the
	/// session under the tabs would open a sheet whose every box is disabled,
	/// which is a menu item that cannot do anything and should not be there.
	public static func isWorthOffering(
		_ sessions: [TmuxMirror.SessionSummary], showing: String?
	) -> Bool {
		offers(sessions, showing: showing).contains(where: \.isClosable)
	}

	/// The names that may actually be closed, of those ticked.
	///
	/// A tick on the session being shown cannot be made in the sheet — its
	/// box is disabled — but a driven run can name anything, and the rule
	/// belongs here rather than in a control's enabled state.
	public static func closable(_ ticked: [String], among offers: [Offer]) -> [String] {
		let allowed = Set(offers.filter(\.isClosable).map(\.name))
		var seen = Set<String>()
		return ticked.filter { allowed.contains($0) && seen.insert($0).inserted }
	}

	/// What the toast says afterwards.
	public static func said(closed: Int, refused: Int) -> String {
		let sessions = { (count: Int) in "\(count) session\(count == 1 ? "" : "s")" }
		switch (closed, refused) {
		case (0, 0): return "Nothing to close"
		case (_, 0): return "Closed \(sessions(closed))"
		case (0, _): return "tmux would not close \(sessions(refused))"
		default: return "Closed \(sessions(closed)); tmux would not close \(refused)"
		}
	}
}
