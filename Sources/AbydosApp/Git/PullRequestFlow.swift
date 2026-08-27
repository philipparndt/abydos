import AppKit
import AbydosKit

/// Getting from a branch to the page where a pull request is written.
///
/// **The two halves are one verb each, and this is why.** Making a pull request
/// from a branch nobody else can see takes two steps — push, then find the
/// compare page — and having to know that is what makes this the part of the
/// job people leave the app to do. A branch with no upstream is offered
/// *publish and open*; one that has been published is offered *open*.
///
/// Its own type rather than more of `BranchesPane`, because it needs four
/// things from that pane — where the repository is, which forge, which branch
/// everything merges into, and something to call afterwards — and none of them
/// is that class's private state.
enum PullRequestFlow {
	/// Opens the compare page for a branch the host already knows about.
	@MainActor
	static func open(_ branch: String, on forge: GitForge.Repository, into base: String?) {
		guard let url = forge.url(forPullRequestFrom: branch, into: base) else {
			Toast.post("There is no pull request page for \(branch)")
			return
		}
        NSWorkspace.shared.open(url)
	}

	/// Publishes the branch, and opens the page only if that worked.
	///
	/// **The page is not opened on a failed push.** A compare page for a branch
	/// the host has never heard of is a 404, and a browser tab explaining that
	/// a branch does not exist is a worse answer than the toast saying why it
	/// could not be sent.
	@MainActor
	static func publishThenOpen(
		_ branch: GitBranch,
		on forge: GitForge.Repository,
		into base: String?,
		in root: URL,
		then finished: @escaping () -> Void
	) {
		Task { @MainActor in
			defer { finished() }
			let result = await GitPush.push(
				in: root,
				setUpstream: true,
				// HEAD for the current branch: pushing it by name would work
				// too, but naming HEAD is what git does and what the log says.
				branch: branch.isCurrent ? nil : branch.name
			)
			let output = (result.stderr.isEmpty ? result.stdout : result.stderr)
				.trimmingCharacters(in: .whitespacesAndNewlines)
			guard result.exitCode == 0 else {
				Toast.post("Could not publish \(branch.name)", detail: output, kind: .error)
				return
			}
			NotificationCenter.default.post(name: .abydosRepositoryChanged, object: root)
			open(branch.name, on: forge, into: base)
		}
	}
}
