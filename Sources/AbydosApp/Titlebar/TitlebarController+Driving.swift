import AppKit
import AbydosKit

/// What the titlebar says, asked from a script.
///
/// A menu cannot be photographed while it is open, and the absence of a pill
/// cannot be told from a window that has not finished loading — so each of
/// these prints the state instead.
extension TitlebarController {
	/// What the pill says, for the harness — a menu cannot be photographed while
	/// it is open, and neither can the absence of a pill be told from a window
	/// that has not finished loading.
	func devContainerPillForTesting() -> String {
		// The scope beside it, because "no pill" has two causes that look
		// identical from outside — this project has no devcontainer, or the window
		// is not pointed at the part of it that has one — and telling them apart
		// is most of what a switched-back window has to be checked for.
		let where_ = " [scope=\(scopeRoot()?.lastPathComponent ?? "-")"
			+ " container=\(devContainerRoot()?.lastPathComponent ?? "-")]"
		guard let pill = devContainerPill, pill.hasContainer else { return "PILL: (none)\(where_)" }
		// **What it shows and what it means, separately**, since 0444 made them
		// two different things: the pill is the mark alone, and the name it stands
		// for is only in the tool tip and the menu. A dump that printed the name as
		// though it were on the pill would be recording the thing that was
		// deliberately taken off it.
		return "PILL: shows=\(pill.isInUse ? containerMark : "(icon only)")"
			+ " name=\(devContainerPillTitleForTesting)"
			+ " tip=\(pill.toolTip ?? "-")"
			+ where_
	}

	private var devContainerPillTitleForTesting: String {
		containerName(pilledContainer, devContainerRoot() ?? URL(fileURLWithPath: "/"))
	}

	/// What the pill's menu offers, for the harness: a menu cannot be
	/// photographed while it is open, and the way back out of a decline is the
	/// whole of 0438's third fault.
	func devContainerMenuForTesting() -> String {
		guard devContainerPill?.hasContainer == true else { return "PILLMENU: (no pill)" }
		let menu = devContainerPillMenu()
		return "PILLMENU: " + menu.items.map { item in
			guard !item.isSeparatorItem else { return "—" }
			// The tick as well as the words: with several containers listed, which
			// one is marked is the whole of what the list says.
			return (item.state == .on ? "✓" : "")
				+ item.title
				+ (item.isEnabled ? "" : " (disabled)")
		}.joined(separator: " | ")
	}

	/// What the worktree pill says, for the harness.
	///
	/// Absence is the interesting reading and the one a screenshot cannot give:
	/// a repository with one checkout should have no pill at all, and an empty
	/// stretch of toolbar looks exactly like one that has not finished loading.
	/// On the primary the pill is deliberately wordless, so what it *shows* and
	/// what it *is* are printed separately — a dump that read the name off the
	/// drawing would record nothing on the very window the report was about.
	func worktreePillForTesting() -> String {
		guard let pill = worktreePill, pill.hasWorktrees else {
			return "WORKTREE: (none) [listed=\(worktrees.count)]"
		}
		let state = pill.worktree
		return "WORKTREE: shows=\(state?.name ?? "(icon only)")"
			+ " of=\(state?.full ?? "-")"
			+ " at=\(state.map { $0.isPrimary ? "primary" : "linked" } ?? "-")"
			+ " listed=\(worktrees.count)"
			+ " tip=\((pill.toolTip ?? "-").replacingOccurrences(of: "\n", with: " / "))"
	}

	/// What the worktree menu offers, for the harness — including how much of it
	/// went behind `More…`, which is the whole claim on a repository with
	/// seventy-four checkouts.
	func worktreeMenuForTesting() -> String {
		guard worktreePill?.hasWorktrees == true else { return "WORKTREEMENU: (no pill)" }
		func describe(_ items: [NSMenuItem]) -> String {
			items.map { item in
				guard !item.isSeparatorItem else { return "—" }
				let submenu = item.submenu.map { " { \(describe($0.items)) }" } ?? ""
				return (item.state == .on ? "✓" : "") + item.title + submenu
			}.joined(separator: " | ")
		}
		return "WORKTREEMENU: " + describe(worktreeMenu().items)
	}

	/// What the toolbar is showing, and what it has put away.
	func reportToolbarForTesting() {
		guard let toolbar = window?.toolbar else { return }
		let visible = Set((toolbar.visibleItems ?? []).map(\.itemIdentifier.rawValue))
		let all = toolbar.items.map(\.itemIdentifier.rawValue)
		let hidden = all.filter { !visible.contains($0) && !$0.hasPrefix("NSToolbar") }
		print("TOOLBAR visible=\(visible.filter { !$0.hasPrefix("NSToolbar") }.sorted()) hidden=\(hidden)")

		for item in toolbar.items where !visible.contains(item.itemIdentifier.rawValue) {
			let menu = item.menuFormRepresentation
			print("  put away: \(item.itemIdentifier.rawValue) menu=\(menu?.title ?? "none") "
				+ "submenu=\(menu?.submenu?.items.map(\.title).prefix(4) ?? [])")
		}

		if let capsule {
			print("  capsule height=\(capsule.frame.height) in row=\(capsule.superview?.frame.height ?? 0)")
		}
	}

	func branchPillForTesting() -> String {
		capsule?.branchPillForTesting() ?? "BRANCHPILL none"
	}

	func highlightPillsForTesting() {
		capsule?.isMenuOpen = true
	}

	/// Next to the traffic lights, where a window says what it is.
	///
}
