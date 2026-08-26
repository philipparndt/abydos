import AppKit
import AbydosKit

/// Reviewing a pull request: the list in the sidebar, the page it opens, and
/// the run that drives them.
///
/// **A collaborator of `SidebarController` rather than more of it.** That class
/// was at a thousand lines before any of this, which is where the file-size
/// check says a file stops being read and starts being appended to. What a
/// review needs is not a `case` in `makeToolView`: it is a page, a set of ticks,
/// a checkout, a pending review and a driven script, all of which have state of
/// their own. So they live here, and the sidebar is asked for the two things
/// only it knows — which pane is on screen, and how to put one there.
@MainActor
final class PullRequestReview {
	/// The list in the sidebar, while one is there.
	var pane: () -> PullRequestsPane? = { nil }
	/// Put the list on screen, for a driven run that has not opened it.
	var showList: () -> Void = {}
	/// What the rail says, which a driven run asks for to prove the way in.
	var rail: () -> String = { "" }

	/// What the pull request list says, row by row.
	///
	/// The steps are a comma-separated script, as everywhere else here:
	///
	/// - `report` — the `gh` version, the scope, and one line per row
	/// - `scope:me` / `scope:meOrMyTeams` — the "waiting on me" question
	/// - `refresh` — ask GitHub again
	/// - `open:123` — open one as a page
	/// - `settle` / `settle:2` — wait, because a network call is in flight
	///
	/// It waits for the first answer rather than reporting an empty list: `gh`
	/// is a process and a round trip, and a report taken before it lands says
	/// the repository has no pull requests — which is exactly the sentence this
	/// whole capability exists not to say by accident.
	func driveForTesting(_ steps: String, waiting: Int = 20) {
		if pane() == nil { showList() }
		guard let pane = pane() else {
			print("PULL-REQUESTS: no pane")
			return
		}
		guard pane.hasAnsweredForTesting else {
			guard waiting > 0 else {
				print("PULL-REQUESTS: GitHub has not answered")
				return
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
				self?.driveForTesting(steps, waiting: waiting - 1)
			}
			return
		}

		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.driveForTesting(rest)
				}
				return
			}

			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "report": print("PULL-REQUESTS:\n\(pane.reportForTesting())")
			case "refresh": pane.reload()
			case "scope":
				guard let scope = ReviewRequestScope(rawValue: argument) else {
					print("PULL-REQUESTS: no such scope \(argument)")
					break
				}
				pane.setScopeForTesting(scope)
			case "open":
				let number = Int(argument) ?? 0
				print("PULL-REQUESTS: open #\(number) \(pane.openForTesting(number: number) ? "opened" : "no such row")")
			case "rail": print("PULL-REQUESTS rail: \(rail())")
			default: print("PULL-REQUESTS: unknown step \(step)")
			}
		}
	}
}
