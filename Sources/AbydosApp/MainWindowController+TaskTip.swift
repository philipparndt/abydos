import AppKit
import AbydosKit

/// Driving the task tip on a card: what it lists, and ticking through it.
///
/// **A file of its own rather than four more verbs in
/// `MainWindowController+Driving.swift`**, which was at 1,087 lines and went to
/// 1,116 with them — over the 1,100-line limit `Scripts/file-size.sh` keeps.
/// The split costs no encapsulation, which is the objection that file's own
/// header raises against splitting a class: everything below reads
/// `bottomPanel` and nothing else, and that is already reachable from any
/// extension.
///
/// Forwarding and nothing else. The verbs are declared on the pane, whose state
/// they read, as `screenshots` requires.
extension MainWindowController {
	/// What the task tip lists on a card, for `--backlog-tasks`.
	func backlogTasksForTesting(change: String) -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.taskTipReportForTesting(change: change)
	}

	/// The same for an item, which is numbered where a change is named.
	func backlogTasksForTesting(number: Int) -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.taskTipReportForTesting(number: number)
	}

	/// Ticks one of them through the tip's own handler, for `--backlog-tick`.
	///
	/// The card arrives as it was typed, and a number is an item exactly as
	/// `--backlog-menu` reads one: an item's name *is* its number, so there is
	/// nothing to collide.
	func backlogTickForTesting(card: String, index: Int) -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		if let number = Int(card) {
			return pane.tickOpenTaskForTesting(number: number, index: index)
		}
		return pane.tickOpenTaskForTesting(change: card, index: index)
	}

	/// Draws the tip to a PNG, for `--backlog-tasks-shot`, because a child
	/// window is invisible to a capture of the main one.
	func backlogTasksShotForTesting(to path: String) -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.writeTaskTipImageForTesting(to: path)
	}
}
