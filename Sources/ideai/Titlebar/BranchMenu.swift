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

			// Fork is a common companion for anything git can't do well inline,
			// so offer a handoff when it is actually installed.
			if let fork = ForkIntegration.applicationURL() {
				let item = NSMenuItem(
					title: "Open in Fork",
					action: #selector(BranchMenuTarget.openInFork(_:)),
					keyEquivalent: ""
				)
				item.target = BranchMenuTarget.shared
				item.representedObject = ForkRequest(application: fork, repository: root)
				item.image = ForkIntegration.icon()
				menu.addItem(item)
				menu.addItem(.separator())
			}

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

private struct ForkRequest {
	let application: URL
	let repository: URL
}

/// Detects Fork, the git client.
enum ForkIntegration {
	/// The installed Fork, if there is one.
	///
	/// Checked by bundle identifier first so a copy outside /Applications is
	/// still found, with the conventional path as a fallback.
	static func applicationURL() -> URL? {
		if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.DanPristupov.Fork") {
			return url
		}
		let conventional = URL(fileURLWithPath: "/Applications/Fork.app")
		return FileManager.default.fileExists(atPath: conventional.path) ? conventional : nil
	}

	static var isInstalled: Bool { applicationURL() != nil }

	/// Fork's own icon, so the menu item reads as a handoff to that app.
	static func icon() -> NSImage? {
		guard let url = applicationURL() else { return nil }
		let image = NSWorkspace.shared.icon(forFile: url.path)
		image.size = NSSize(width: 14, height: 14)
		return image
	}

	/// Opens a repository in Fork.
	static func open(repository: URL, application: URL) {
		let configuration = NSWorkspace.OpenConfiguration()
		configuration.activates = true
		NSWorkspace.shared.open(
			[repository],
			withApplicationAt: application,
			configuration: configuration
		) { _, error in
			guard let error else { return }
			DispatchQueue.main.async {
				let alert = NSAlert()
				alert.messageText = "Could not open Fork"
				alert.informativeText = error.localizedDescription
				alert.runModal()
			}
		}
	}
}

private final class BranchMenuTarget: NSObject {
	static let shared = BranchMenuTarget()

	@objc func openInFork(_ sender: NSMenuItem) {
		guard let request = sender.representedObject as? ForkRequest else { return }
		ForkIntegration.open(repository: request.repository, application: request.application)
	}

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
