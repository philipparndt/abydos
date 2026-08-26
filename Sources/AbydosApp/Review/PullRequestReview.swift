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
	/// Where git is run, which is the repository a pull request belongs to.
	var repositoryRoot: () -> URL? = { nil }
	/// A page already open under this identifier, if there is one.
	var existingPage: (String) -> NSView? = { _ in nil }
	/// Put a page in the editor area and give the editor the window.
	var openPage: (NSView, String, String, String) -> Void = { _, _, _, _ in }
	/// Write what the project has open, so a tick outlives the window.
	var rememberSession: () -> Void = {}

	/// Which files of which pull request have been read, this window's copy.
	///
	/// Kept here rather than in the page because a page is a tab somebody may
	/// close and open again in the same afternoon, and closing a tab is not
	/// unreading a file.
	private var ticks: [Int: Checklist<String>] = [:]

	/// What to write beside the project: every pull request this window knows
	/// about, over whatever the session file already held.
	///
    /// **Merged rather than written over.** A window that has opened one pull
	/// request today knows nothing about the four somebody read yesterday, and
	/// writing only what it knows would forget them.
	func ticksToRemember() -> [String: [String: String]] {
		guard let root = repositoryRoot() else { return [:] }
		var remembered = SessionStore.read(in: root)?.reviewTicks ?? [:]
		for (number, list) in ticks {
			let recorded = list.recordedTokens.filter { list.isDone($0.key) }
			if recorded.isEmpty {
				remembered.removeValue(forKey: "\(number)")
			} else {
				remembered["\(number)"] = recorded
			}
		}
		return remembered
	}

	/// What the project remembered about one pull request.
	private func remembered(_ number: Int) -> Checklist<String> {
		if let held = ticks[number] { return held }
		guard let root = repositoryRoot(),
		      let stored = SessionStore.read(in: root)?.reviewTicks["\(number)"]
		else { return Checklist<String>() }
		return Checklist(done: Set(stored.keys), tokens: stored)
	}

	/// The pages open, by pull request number.
	///
	/// **Weak, because the editor owns them.** Closing the tab should let the
	/// page go; a strong reference here would keep every pull request somebody
	/// looked at today alive with its diffs in it.
	private var pages: [Int: WeakPage] = [:]

	private struct WeakPage {
		weak var page: PullRequestPage?
	}

	/// The last pull request a driven run opened, which its page steps address.
	private var lastOpened: Int?

	private var openedPage: PullRequestPage? { lastOpened.flatMap { page(of: $0) } }

	/// The page for one pull request, opening it if it is not open.
	///
	/// Two pull requests at once is what a blocked morning looks like, so the
	/// identifier carries the number: `openPage` reuses a tab by identifier, and
	/// one called "pull-request" would make the second review replace the first.
	@discardableResult
	func open(_ request: PullRequest) -> PullRequestPage? {
		guard let root = repositoryRoot() else { return nil }
		let identifier = "pull-request-\(request.number)"
		let page = (existingPage(identifier) as? PullRequestPage)
			?? PullRequestPage(root: root, request: request)
		// Before the files arrive, so the revalidation that follows them has
		// something to check.
		page.restore(ticks: remembered(request.number))
		page.onTicksChanged = { [weak self] number, list in
			guard let self else { return }
			self.ticks[number] = list
			self.rememberSession()
		}
		pages[request.number] = WeakPage(page: page)
		openPage(page, "PR #\(request.number)", identifier, "arrow.trianglehead.pull")
		// Opened to be read, and read with the arrows.
		DispatchQueue.main.async { [weak page] in page?.focusList() }
		return page
	}

	/// The page for a pull request, while one is open.
	func page(of number: Int) -> PullRequestPage? { pages[number]?.page }

	/// What the pull request list says, row by row, and what the page it opens
	/// holds.
	///
	/// The steps are a comma-separated script, as everywhere else here:
	///
	/// - `report` — the `gh` version, the scope, and one line per row
	/// - `scope:me` / `scope:meOrMyTeams` — the "waiting on me" question
	/// - `refresh` — ask GitHub again
	/// - `open:123` — open one as a page
	/// - `page` — what the open page holds: files, rows, diff
	/// - `whole:on` / `whole:off` — the whole-file view of the diff
	/// - `pick:2` — select the file at that index
	/// - `read` — tick the selected file off, as ␣ does
	/// - `next` — go to the next file nobody has read, as ⌥↓ does
	/// - `hide:on` / `hide:off` — leave only what is still to read
	/// - `push:<path>` — pretend the author pushed a change to that file, which
	///   fakes the token and nothing else; `push:` alone revalidates against the
	///   tokens as they are, which is a rebase that changed nothing
	/// - `keys:down+down` — walk the file list, as `--log-page` does
	/// - `diff` — the first lines of the diff on screen
	/// - `settle` / `settle:2` — wait, because a network call is in flight
	///
	/// Every step that addresses the page waits for it to have answered, for
	/// the same reason the list does.
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
				let opened = pane.openForTesting(number: number)
				lastOpened = opened ? number : nil
				print("PULL-REQUESTS: open #\(number) \(opened ? "opened" : "no such row")")
			case "rail": print("PULL-REQUESTS rail: \(rail())")
			case "page", "whole", "pick", "keys", "diff", "read", "next", "hide", "push":
				// The page is a second round of network calls, so a step that
				// addresses it waits — and takes the rest of the script with it
				// rather than running the tail against a page that is not there.
				guard let page = openedPage else {
					print("PULL-REQUESTS: no page open")
					return
				}
				guard page.hasAnsweredForTesting else {
					guard waiting > 0 else {
						print("PULL-REQUESTS: the page has not answered")
						return
					}
					let rest = script[index...].joined(separator: ",")
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
						self?.driveForTesting(rest, waiting: waiting - 1)
					}
					return
				}
				switch step.prefix(while: { $0 != ":" }) {
				case "push":  print("PULL-REQUEST PAGE: " + page.pretendPushForTesting(argument))
				case "read":  page.toggleReadForTesting()
				case "next":  print("PULL-REQUEST PAGE: next unread \(page.nextUnreadForTesting())")
				case "hide":  page.setHideReadForTesting(argument == "on")
				case "page":  print("PULL-REQUEST PAGE:\n\(page.reportForTesting())")
				case "whole": page.setWholeFileForTesting(argument == "on")
				case "pick":  page.selectFileForTesting(Int(argument) ?? 0)
				case "keys":  print("PULL-REQUEST PAGE keys: " + page.fileKeysForTesting(argument))
				default:      print("PULL-REQUEST PAGE diff:\n\(page.diffTextForTesting())")
				}
			default: print("PULL-REQUESTS: unknown step \(step)")
			}
		}
	}
}
