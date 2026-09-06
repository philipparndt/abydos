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
		let root = project?.root
		let untrusted = root.map { !ProjectTrust.shared.isTrusted($0) } ?? false
		let hidden = root.map { hiddenTrustBanners.contains(ProjectTrust.resolvedForTesting($0)) } ?? false
		let shows = untrusted && !hidden
		trustBanner.show(project: shows ? root : nil)
		trustBannerHeight.constant = shows ? Theme.current.scaled(30) : 0
		// The panes under it take their inset from whether the strip is there:
		// with it up, the strip clears the titlebar and they must not clear it
		// again. See `updateTopInsets`.
		updateTopInsets()
	}

	/// The strip put away without anything being trusted.
	///
	/// **Per project and per window, and only until it is opened again.** A
	/// dismissal that outlived the session would be a decision about safety
	/// made by somebody trying to get a bar out of the way — and the one thing
	/// this strip must not become is a thing people learn to silence. Nothing
	/// about the project changes: it is still untrusted, everything still
	/// refuses, and File ▸ Trust This Project… is where the gesture lives.
	func hideTrustBanner() {
		guard let root = project?.root else { return }
		hiddenTrustBanners.insert(ProjectTrust.resolvedForTesting(root))
		refreshTrustBanner()
	}

	/// Whether this window's project could be trusted and is not — what the
	/// menu item asks before it offers itself.
	var couldBeTrusted: Bool {
		project.map { !ProjectTrust.shared.isTrusted($0.root) } ?? false
	}

	/// File ▸ Trust This Project…, which is the same sheet the strip's button
	/// opens — and the only way to it once the strip has been put away.
	@objc func trustThisProject(_ sender: Any?) {
		guard couldBeTrusted else {
			Toast.post(
				"Already trusted",
				detail: "\(project?.root.lastPathComponent ?? "This project") can run its own code.",
				kind: .information
			)
			return
		}
		askToTrustProject()
	}

	/// The scopes this project can be trusted at, and — once it is — the entry
	/// that trusts it, to take back.
	///
	/// **A menu rather than a sheet with checkboxes**, which is what this was
	/// first and what was reported: trusting is a choice of *scope*, and a
	/// scope is what a menu is for. Each item says exactly what it covers, so
	/// the press is the decision rather than a dialog to get through.
	///
	/// The same menu hangs off the strip's button and off the File menu, so
	/// there is one list to learn and one place it is built.
	func trustMenu() -> NSMenu {
		let menu = NSMenu()
		guard let root = project?.root else {
			let none = NSMenuItem(title: "No project in this window", action: nil, keyEquivalent: "")
			none.isEnabled = false
			menu.addItem(none)
			return menu
		}

		func add(_ title: String, _ scope: TrustScope, caution: String? = nil) {
			let item = NSMenuItem(title: title, action: #selector(trustScopeChosen(_:)), keyEquivalent: "")
			item.target = self
			item.representedObject = TrustScopeBox(scope: scope, caution: caution)
			menu.addItem(item)
		}

		if let entry = ProjectTrust.shared.entry(covering: root) {
			// Trusted by a folder: say which, since it may not be this one.
			let name = Project.abbreviate(URL(fileURLWithPath: entry.path))
			let said = entry.coversChildren ? "\(name) and everything in it" : name
			addHeading("Trusted by \(said)", to: menu)
			add(
				entry.coversChildren ? "Untrust \(name) and everything in it" : "Untrust \(name)",
				.withdrawFolder(entry.path),
				caution: entry.coversChildren
					? "Every project under \(name) stops being trusted, not only this one."
					: nil
			)
			return menu
		}
		if let remote = ProjectTrust.shared.remote(of: root),
		   let entry = ProjectTrust.shared.remotes.first(
			where: { $0.matches(host: remote.host, owner: remote.owner) }
		   ) {
			addHeading("Trusted by \(entry.said)", to: menu)
			add(
				"Untrust everything from \(entry.said)",
				.withdrawRemote(host: entry.host, owner: entry.owner),
				caution: "Every clone that says it came from \(entry.said) stops being trusted."
			)
			return menu
		}

		add("Trust “\(root.lastPathComponent)”", .folder(root, coversChildren: false))
		if let parent = ProjectTrust.parent(of: root) {
			// One entry for a folder of checkouts is the difference between a
			// feature people use and a dialog people learn to dismiss.
			add("Trust everything in \(Project.abbreviate(parent))", .folder(parent, coversChildren: true))
		}
		if let remote = ProjectTrust.shared.remote(of: root) {
			menu.addItem(.separator())
			// **Weaker than a folder, and it says so before it is granted.** A
			// repository's remote is what its own `.git/config` claims, so a
			// folder that arrived with a `.git` somebody else wrote can name
			// any host it likes — the one caveat a menu item's title cannot
			// carry, so these two ask first.
			let caution = "A repository's remote is what its own .git/config says, so this "
				+ "trusts every folder that claims to come from there — including one that "
				+ "arrived with a .git directory somebody else wrote."
			if let owner = remote.owner {
				add(
					"Trust everything from \(remote.host)/\(owner)",
					.remote(host: remote.host, owner: owner),
					caution: caution
				)
			}
			// **The whole host, but not a public forge.** `github.com` is every
			// repository anybody has ever pushed, and offering it beside "this
			// organisation" as though they were two sizes of the same thing is
			// how somebody picks the wrong one. An enterprise server is the
			// opposite — a place, whose every repository is a colleague's — and
			// that is the case the host scope exists for.
			if !TrustedRemote.isPublicForge(remote.host) {
				add(
					"Trust everything from \(remote.host)",
					.remote(host: remote.host, owner: nil),
					caution: remote.owner == nil ? caution : caution + " The whole host, not only "
						+ "\(remote.owner ?? "") on it."
				)
			}
		}
		return menu
	}

	private func addHeading(_ text: String, to menu: NSMenu) {
		let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
		item.isEnabled = false
		menu.addItem(item)
		menu.addItem(.separator())
	}

	/// One of the scopes, chosen.
	///
	/// The ones that reach beyond this project — a folder of checkouts, a
	/// remote anything can claim to come from — confirm first; trusting the
	/// project in front of somebody is the press itself, since that is what
	/// they are looking at.
	@objc private func trustScopeChosen(_ sender: NSMenuItem) {
		guard let box = sender.representedObject as? TrustScopeBox else { return }
		guard let caution = box.caution else {
			apply(box.scope)
			return
		}
		let alert = NSAlert()
		alert.messageText = sender.title
		alert.informativeText = caution
		alert.addButton(withTitle: sender.title.hasPrefix("Untrust") ? "Untrust" : "Trust")
		alert.addButton(withTitle: "Cancel")
		let act: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard let self, response == .alertFirstButtonReturn else { return }
			self.apply(box.scope)
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: act)
		} else {
			act(alert.runModal())
		}
	}

	private func apply(_ scope: TrustScope) {
		switch scope {
		case let .folder(url, coversChildren):
			ProjectTrust.shared.trust(url, coveringChildren: coversChildren)
			trustGranted()
		case let .remote(host, owner):
			ProjectTrust.shared.trust(remoteHost: host, owner: owner)
			trustGranted()
		case let .withdrawFolder(path):
			ProjectTrust.shared.withdraw(path: path)
			trustWithdrawn()
		case let .withdrawRemote(host, owner):
			ProjectTrust.shared.withdraw(remoteHost: host, owner: owner)
			trustWithdrawn()
		}
	}

	/// The palette's route to the same scopes: it lists menu items, and this is
	/// the one that opens the list rather than granting anything by itself.
	///
	/// The strip's button hangs its own menu off itself — a dropdown that
	/// appeared at the strip's leading edge read as a menu about something
	/// else — and File ▸ Project Trust is a submenu, built when it opens.
	func askToTrustProject() {
		trustMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
	}

	/// Every window says what it now is: trust is the app's, not one window's.
	private func trustWithdrawn() {
		for controller in NSApp.windows.compactMap({ $0.windowController as? MainWindowController }) {
			controller.refreshTrustBanner()
		}
		Toast.post(
			"Untrusted \(project?.root.lastPathComponent ?? "")",
			detail: "Nothing in it runs by itself again.",
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

	/// The scopes the menu offers, for a driven run — the words are the
	/// requirement, and which scopes are *absent* is half of it.
	func trustMenuForTesting() -> String {
		trustMenu().items
			.map { $0.isSeparatorItem ? "—" : $0.title + ($0.isEnabled ? "" : " (off)") }
			.joined(separator: " | ")
	}

	/// What the strip says, for a driven run.
	func trustBannerReportForTesting() -> String { trustBanner.reportForTesting }

	/// Opens *What is held back*, and says what it lists.
	func heldBackForTesting() {
		trustBanner.showHeldBackForTesting()
		print("HELDBACK: " + trustBanner.heldBackReportForTesting())
		fflush(stdout)
	}
}

/// What a trust menu item does.
enum TrustScope {
	case folder(URL, coversChildren: Bool)
	case remote(host: String, owner: String?)
	case withdrawFolder(String)
	case withdrawRemote(host: String, owner: String?)
}

/// A scope on a menu item, with the sentence that must be read first where
/// there is one. `representedObject` takes an object, and an enum is not one.
final class TrustScopeBox: NSObject {
	let scope: TrustScope
	let caution: String?

	init(scope: TrustScope, caution: String?) {
		self.scope = scope
		self.caution = caution
	}
}
