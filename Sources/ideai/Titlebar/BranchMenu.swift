import AppKit
import IdeaiKit

/// Dropdown for the branch pill: lists local branches and checks one out.
enum BranchMenu {
	static func show(relativeTo pill: PillButton, project: Project) {
		pill.isMenuOpen = true

		Task { @MainActor in
			guard let git = project.git else {
				pill.isMenuOpen = false
				return
			}
			let root = await git.root
			let current = await git.currentBranch()

			// `git branch` sorted by most recent commit puts the branches the user
			// actually moves between at the top.
			let result = await GitRepository.run(
				["branch", "--sort=-committerdate", "--format=%(refname:short)"],
				in: root
			)
			let branches = result.stdout
				.split(separator: "\n")
				.map { $0.trimmingCharacters(in: .whitespaces) }
				.filter { !$0.isEmpty }

			guard !branches.isEmpty else {
				pill.isMenuOpen = false
				return
			}

			let menu = NSMenu()
			menu.autoenablesItems = false
			for branch in branches {
				let item = NSMenuItem(
					title: branch,
					action: #selector(BranchMenuTarget.checkout(_:)),
					keyEquivalent: ""
				)
				item.target = BranchMenuTarget.shared
				item.representedObject = BranchCheckout(root: root, branch: branch)
				item.state = (branch == current) ? .on : .off
				menu.addItem(item)
			}

			menu.popUp(
				positioning: nil,
				at: NSPoint(x: 0, y: pill.bounds.maxY + 4),
				in: pill
			)
			pill.isMenuOpen = false
		}
	}
}

private struct BranchCheckout {
	let root: URL
	let branch: String
}

private final class BranchMenuTarget: NSObject {
	static let shared = BranchMenuTarget()

	@objc func checkout(_ sender: NSMenuItem) {
		guard let request = sender.representedObject as? BranchCheckout else { return }

		Task { @MainActor in
			let result = await GitRepository.run(["checkout", request.branch], in: request.root)
			if result.exitCode != 0 {
				// Most often a dirty work tree; git's own message is the clearest
				// explanation we could show.
				let alert = NSAlert()
				alert.alertStyle = .warning
				alert.messageText = "Could not switch to \(request.branch)"
				alert.informativeText = result.stderr.isEmpty
					? "git exited with code \(result.exitCode)."
					: result.stderr
				alert.runModal()
				return
			}
			// The working tree changed underneath every open window on this repo.
			NotificationCenter.default.post(name: .ideaiRepositoryChanged, object: request.root)
		}
	}
}

extension Notification.Name {
	static let ideaiRepositoryChanged = Notification.Name("ideai.repositoryChanged")
}
