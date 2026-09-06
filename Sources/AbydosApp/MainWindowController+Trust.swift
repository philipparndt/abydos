import AppKit
import AbydosKit

/// Whether this window's project may run its own code, and how that is asked.
///
/// **Its own file because it is its own subject.** The layout file is where the
/// window's panes are put together; trust is a question about the project, with
/// a strip, a sheet and a settings page behind it — and `+Layout` had grown
/// past the line limit carrying both.
extension MainWindowController {

	// MARK: - Trust

	/// Puts the strip up or takes it down for whatever project this window has.
	func refreshTrustBanner() {
		let untrusted = project.map { !ProjectTrust.shared.isTrusted($0.root) } ?? false
		trustBanner.show(project: untrusted ? project?.root : nil)
		trustBannerHeight.constant = untrusted ? Theme.current.scaled(30) : 0
	}

	/// The sheet: the folder, the parent as the wider choice, and what trusting
	/// turns on said before it is granted.
	///
	/// **The only place trust is granted.** Everything else — the run control,
	/// the terminal, the language servers — refuses and points here, so there is
	/// one gesture to recognise and one sentence to have read.
	func askToTrustProject() {
		guard let root = project?.root else { return }
		let alert = NSAlert()
		alert.messageText = "Trust “\(root.lastPathComponent)”?"
		alert.informativeText = "Trusting it lets this project run on your machine: its run and "
			+ "debug configurations, its build and test commands, its devcontainer, the language "
			+ "servers its tree provides, the environment its files ask for, a terminal in its "
			+ "directory and its git hooks.\n\n"
			+ "Trust it only if you would run its code from a terminal yourself."

		// The host this clone says it came from, offered beside the folder: an
		// enterprise server is a hundred repositories from one place, and a
		// folder entry per clone is the dialog people learn to dismiss.
		var alsoHost: NSButton?
		var alsoParent: NSButton?
		if let parent = ProjectTrust.parent(of: root) {
			// The wider choice offered rather than assumed: one entry for a
			// folder of checkouts is the difference between a feature people use
			// and a dialog people learn to dismiss.
			let box = NSButton(
				checkboxWithTitle: "Trust everything in \(Project.abbreviate(parent))",
				target: nil, action: nil
			)
			// An explicit frame, for the reason `BranchDeletion` records: an
			// accessory at zero by zero is a dialog with an invisible control.
			box.frame = NSRect(origin: .zero, size: box.fittingSize)
			box.state = .off
			alsoParent = box
		}
		var alsoOwner: NSButton?
		if let remote = ProjectTrust.shared.remote(of: root) {
			// **Weaker than a folder, and said so where it is offered.** A
			// repository's remote is what its own `.git/config` claims, so a
			// folder that arrived with a `.git` somebody else wrote can name
			// any host it likes.
			let caution = "A repository's remote is what its own .git/config says, "
				+ "so this trusts every folder that claims to come from there."
			if let owner = remote.owner {
				// The owner first, and it is what somebody usually means:
				// `github.com` is the world, and one organisation on it is a
				// place.
				let box = NSButton(
					checkboxWithTitle: "Trust everything from \(remote.host)/\(owner)",
					target: nil, action: nil
				)
				box.frame = NSRect(origin: .zero, size: box.fittingSize)
				box.state = .off
				box.toolTip = caution
				alsoOwner = box
			}
			let box = NSButton(
				checkboxWithTitle: "Trust everything from \(remote.host)", target: nil, action: nil
			)
			box.frame = NSRect(origin: .zero, size: box.fittingSize)
			box.state = .off
			box.toolTip = remote.owner == nil
				? caution
				: caution + " The whole host, not only \(remote.owner ?? "")."
			alsoHost = box
		}
		alert.accessoryView = Self.trustAccessory(
			[alsoParent, alsoOwner, alsoHost].compactMap { $0 }
		)

		alert.addButton(withTitle: "Trust")
		alert.addButton(withTitle: "Cancel")

		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard let self, response == .alertFirstButtonReturn else { return }
			let coversChildren = alsoParent?.state == .on
			let folder = coversChildren ? (ProjectTrust.parent(of: root) ?? root) : root
			ProjectTrust.shared.trust(folder, coveringChildren: coversChildren)
			if let remote = ProjectTrust.shared.remote(of: root) {
				if alsoOwner?.state == .on, let owner = remote.owner {
					ProjectTrust.shared.trust(remoteHost: remote.host, owner: owner)
				}
				if alsoHost?.state == .on {
					ProjectTrust.shared.trust(remoteHost: remote.host)
				}
			}
			self.trustGranted()
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: act)
		} else {
			act(alert.runModal())
		}
	}

	/// The sheet's checkboxes, stacked — `NSAlert` takes one accessory view,
	/// and there may be a parent folder and a host to offer.
	private static func trustAccessory(_ boxes: [NSView]) -> NSView? {
		guard !boxes.isEmpty else { return nil }
		guard boxes.count > 1 else { return boxes[0] }
		let gap: CGFloat = 6
		let width = boxes.map(\.frame.width).max() ?? 0
		let height = boxes.map(\.frame.height).reduce(0, +) + gap * CGFloat(boxes.count - 1)
		let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
		var y = height
		for box in boxes {
			y -= box.frame.height
			box.frame = NSRect(x: 0, y: y, width: max(box.frame.width, width), height: box.frame.height)
			container.addSubview(box)
			y -= gap
		}
		return container
	}

	/// What is held back, listed rather than summarised: somebody deciding
	/// whether to trust a repository is owed the list.
	func sayWhatTrustHoldsBack() {
		Toast.post(
			"Not trusted",
			detail: "Held back: running, debugging and building; make, gradle and maven; "
				+ "devcontainers; language servers, formatters and linters; agents; a terminal "
				+ "in this directory; the environment its files ask for; and its git hooks. "
				+ "Reading it — the tree, the editor, search, history, diffs and blame — is "
				+ "unaffected.",
			kind: .information
		)
	}

	/// The window after trust is granted.
	///
	/// Nothing is started retroactively: a project that has just become trusted
	/// has not asked for anything yet, and a window that suddenly launched what
	/// it had refused would be doing something nobody pressed.
	func trustGranted() {
		refreshTrustBanner()
		Toast.post(
			"Trusted \(project?.root.lastPathComponent ?? "")",
			detail: "It can run, debug, open a terminal and start language servers.",
			kind: .information
		)
	}

	/// Grants trust from a driven run, through the same door the sheet's button
	/// goes through — the sheet itself stays undriven, `NSAlert` wanting a
	/// person.
	func trustProjectForTesting(coveringChildren: Bool = false) {
		guard let root = project?.root else { return }
		let folder = coveringChildren ? (ProjectTrust.parent(of: root) ?? root) : root
		ProjectTrust.shared.trust(folder, coveringChildren: coveringChildren)
		trustGranted()
	}

	/// Trusts where this clone says it came from, from a driven run — the same
	/// two doors the sheet's checkboxes go through.
	func trustRemoteForTesting(owner: Bool) {
		guard let root = project?.root, let remote = ProjectTrust.shared.remote(of: root) else {
			print("TRUST: no remote")
			fflush(stdout)
			return
		}
		ProjectTrust.shared.trust(
			remoteHost: remote.host, owner: owner ? remote.owner : nil
		)
		trustGranted()
	}

	/// What the strip says, for a driven run.
	func trustBannerReportForTesting() -> String { trustBanner.reportForTesting }
}
