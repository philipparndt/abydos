import AppKit
import AbydosKit

/// Dropdown for the branch pill: lists local branches and checks one out.
enum BranchMenu {
	/// - Parameter anchorRect: where the menu should hang from, for a control
	///   that is bigger than the part being pointed at. Its whole bounds when
	///   nothing is given.
	static func show(
		relativeTo pill: some NSView & TitlebarMenuAnchor,
		anchorRect: NSRect? = nil,
		project: Project
	) {
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
			let branches = await Self.branches(in: root)

			guard !branches.isEmpty else {
				pill.isMenuOpen = false
				return
			}

			let menu = NSMenu()
			menu.autoenablesItems = false

			// The handoffs: places this repository also exists, offered only when
			// they are really there. Fork when it is installed, the remote's own
			// site when the remote is one — a repository with no remote, or one
			// that is a path on this disk, has nowhere to be opened.
			var handedOff = false

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
				handedOff = true
			}

			if let repository = await GitForge.repository(in: root) {
				// Named after the host rather than after a vendor: an Enterprise
				// install is `git.example.com` and calling it GitHub would be a
				// guess, while the address is a fact and the thing you would
				// recognise anyway.
				let item = NSMenuItem(
					title: "Open on \(repository.displayName)",
					action: nil,
					keyEquivalent: ""
				)
				item.submenu = hostMenu(for: repository, branch: current)
				item.image = NSImage(
					systemSymbolName: "globe",
					accessibilityDescription: nil
				)
				menu.addItem(item)
				handedOff = true
			}

			if handedOff { menu.addItem(.separator()) }

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

			let from = anchorRect ?? pill.bounds
			menu.popUp(
				positioning: nil,
				at: NSPoint(x: from.minX, y: from.maxY + 4),
				in: pill
			)
			pill.isMenuOpen = false
		}
	}

	/// Moves the work tree onto another branch.
	///
	/// Shared with the switcher, which lists branches beside projects: a branch
	/// chosen by typing its name has to end up in exactly the same place as one
	/// chosen from this menu.
	static func checkout(_ branch: String, in root: URL) {
		Task { @MainActor in
			let result = await GitRepository.run(["checkout", branch], in: root)
			if result.exitCode != 0 {
				// Most often a dirty work tree; git's own message is the clearest
				// explanation we could show.
				Toast.post(
					"Could not switch to \(branch)",
					detail: result.stderr.isEmpty
						? "git exited with code \(result.exitCode)."
						: result.stderr
				)
				return
			}
			// The working tree changed underneath every open window on this repo.
			NotificationCenter.default.post(name: .abydosRepositoryChanged, object: root)
		}
	}

	/// Which branch the work tree is on.
	///
	/// Asked of git rather than of `GitRepository.currentBranch()`, which
	/// answers from a cache that only a loaded repository has filled — a fresh
	/// one says nil however checked out it is.
	static func currentBranch(in root: URL) async -> String? {
		let result = await GitRepository.run(["rev-parse", "--abbrev-ref", "HEAD"], in: root)
		guard result.exitCode == 0 else { return nil }
		let name = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		// `HEAD` is git's way of saying it is detached, which is not a branch.
		return (name.isEmpty || name == "HEAD") ? nil : name
	}

	/// The branches this repository has, most recently committed to first.
	static func branches(in root: URL) async -> [String] {
		let result = await GitRepository.run(
			["branch", "--sort=-committerdate", "--format=%(refname:short)"],
			in: root
		)
		return result.stdout
			.split(separator: "\n")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
	}

	/// What there is to look at on the host.
	///
	/// Every entry is drawn twice: the plain one, and an alternate that copies
	/// the address instead of opening it. Half the time the link is wanted for a
	/// message rather than for a browser tab, and ⌥ is where a Mac user already
	/// looks for the variant of a command.
	private static func hostMenu(for repository: GitForge.Repository, branch: String?) -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false

		var entries: [(String, URL?)] = []
		if let branch {
			entries.append(("This Branch", repository.url(forBranch: branch)))
			entries.append(("Commits", repository.url(forCommitsOn: branch)))
		}
		entries.append(("Pull Requests", repository.pullRequestsURL))
		entries.append(("Repository Home", repository.webURL))

		for (title, url) in entries {
			guard let url else { continue }

			let open = NSMenuItem(
				title: title,
				action: #selector(BranchMenuTarget.openLink(_:)),
				keyEquivalent: ""
			)
			open.target = BranchMenuTarget.shared
			open.representedObject = url
			menu.addItem(open)

			let copy = NSMenuItem(
				title: "Copy Link to \(title)",
				action: #selector(BranchMenuTarget.copyLink(_:)),
				keyEquivalent: ""
			)
			copy.target = BranchMenuTarget.shared
			copy.representedObject = url
			copy.keyEquivalentModifierMask = .option
			copy.isAlternate = true
			menu.addItem(copy)
		}
		return menu
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
				Toast.post("Could not open Fork", detail: error.localizedDescription)
			}
		}
	}
}

private final class BranchMenuTarget: NSObject {
	static let shared = BranchMenuTarget()

	@objc func openLink(_ sender: NSMenuItem) {
		guard let url = sender.representedObject as? URL else { return }
		NSWorkspace.shared.open(url)
	}

	@objc func copyLink(_ sender: NSMenuItem) {
		guard let url = sender.representedObject as? URL else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(url.absoluteString, forType: .string)
		// Copying leaves nothing on screen to show for itself, so say so.
		Toast.post("Copied link", detail: url.absoluteString)
	}

	@objc func openInFork(_ sender: NSMenuItem) {
		guard let request = sender.representedObject as? ForkRequest else { return }
		ForkIntegration.open(repository: request.repository, application: request.application)
	}

	@objc func checkout(_ sender: NSMenuItem) {
		guard let request = sender.representedObject as? BranchCheckout else { return }
		BranchMenu.checkout(request.branch, in: request.root)
	}
}

extension Notification.Name {
	static let abydosRepositoryChanged = Notification.Name("abydos.repositoryChanged")
}
