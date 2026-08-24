import AppKit
import AbydosKit

/// Where a pull comes from, how it is reconciled, and what happens to the work
/// in hand.
///
/// **The one dialog worth having.** Pull is where everything meets: it brings
/// work down, it may rewrite yours, and it may refuse because the working copy
/// is in the way. None of it existed before this change, so there is no habit
/// to break — which makes it the right place to put the choice in front of
/// somebody once and then remember it.
///
/// Remote and branch are pickers rather than assumptions: a pull from
/// `upstream/main` into a fork is exactly the case that otherwise needs a
/// terminal. What it goes *into* is stated and not editable — a pull goes into
/// the branch the work tree is on, and saying which one is the difference
/// between a dialog that can be read and one that has to be trusted.
@MainActor
enum PullSheet {
	/// What somebody chose.
	struct Answer {
		let remote: String
		let branch: String
		let rebasing: Bool
		let stashing: Bool
	}

	/// Everything the sheet needs to describe the situation truthfully.
	struct Situation {
		var remotes: [String]
		var branches: [String]
		var into: String
		var coming: Int
		var going: Int
		var changedFiles: Int
		var preference: GitPull.Preference
		var stashes: Bool
	}

	/// Reads the repository for what the sheet should say.
	static func situation(in root: URL) async -> Situation? {
		let listed = await GitRepository.run(["remote"], in: root)
		let remotes = listed.stdout
			.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
		guard !remotes.isEmpty else { return nil }

		let state = await GitPush.state(in: root)
		guard let into = state?.branch else { return nil }

		let all = await GitBranches.list(in: root)
		// Branch names as the remote knows them, without the remote in front:
		// `origin/main` is a ref here and `main` is what `git pull origin …`
		// wants, and handing git the first is the mistake this saves.
		var offered = all.compactMap { branch -> String? in
			if case .remote = branch.kind { return branch.name }
			return nil
		}
		if offered.isEmpty { offered = [into] }

		let status = await GitWorkingCopy.status(in: root)
		let settings = Settings.shared

		return Situation(
			remotes: remotes,
			branches: Array(Set(offered)).sorted(),
			into: into,
			coming: state?.behind ?? 0,
			going: state?.ahead ?? 0,
			changedFiles: status.staged.count + status.unstaged.count,
			preference: await GitPull.preference(
				in: root, appDefault: settings.pullRebases ? .rebase : .merge
			),
			stashes: settings.pullStashes
		)
	}

	/// Puts the sheet up and answers with what was chosen.
	static func ask(
		_ situation: Situation,
		over window: NSWindow?,
		then act: @escaping (Answer) -> Void
	) {
		let alert = NSAlert()
		alert.messageText = "Pull"
		alert.informativeText = describe(situation)
		alert.addButton(withTitle: "Pull")
		alert.addButton(withTitle: "Cancel")

		let remote = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
		remote.addItems(withTitles: situation.remotes)

		let branch = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
		branch.addItems(withTitles: situation.branches)
		// The branch of the same name, which is what somebody nearly always
		// wants and is otherwise a scroll through everything the remote has.
		if situation.branches.contains(situation.into) {
			branch.selectItem(withTitle: situation.into)
		}

		let into = NSTextField(labelWithString: situation.into)
		into.font = Theme.current.uiFont(12)
		into.textColor = Theme.current.sidebarText

		let rebase = NSButton(checkboxWithTitle: "Rebase instead of merge", target: nil, action: nil)
		rebase.state = situation.preference.reconciliation == .rebase ? .on : .off
		// Said, not implied. A checkbox that came up ticked for a reason
		// somebody cannot see is a checkbox they will untick.
		rebase.toolTip = situation.preference.attribution
			?? "Your commits are replayed on top rather than merged."

		let stash = NSButton(
			checkboxWithTitle: "Stash and reapply local changes", target: nil, action: nil
		)
		stash.state = situation.stashes ? .on : .off
		stash.isEnabled = situation.changedFiles > 0
		stash.toolTip = situation.changedFiles > 0
			? "\(situation.changedFiles) changed file"
				+ (situation.changedFiles == 1 ? "" : "s")
				+ " would otherwise stop the pull."
			: "Nothing in the working copy to put aside."

		alert.accessoryView = layout(
			remote: remote, branch: branch, into: into, checkboxes: [rebase, stash],
			note: note(situation)
		)

		let answer: (NSApplication.ModalResponse) -> Void = { response in
			guard response == .alertFirstButtonReturn else { return }

			// Remembered as the app's default, not written into the
			// repository's config: a checkbox here that changed how `git pull`
			// behaves in somebody's terminal afterwards would be a surprise
			// nobody could trace back to it.
			Settings.shared.pullRebases = rebase.state == .on
			if stash.isEnabled { Settings.shared.pullStashes = stash.state == .on }

			act(Answer(
				remote: remote.titleOfSelectedItem ?? situation.remotes[0],
				branch: branch.titleOfSelectedItem ?? situation.into,
				rebasing: rebase.state == .on,
				stashing: stash.state == .on && stash.isEnabled
			))
		}

		if let window {
			alert.beginSheetModal(for: window, completionHandler: answer)
		} else {
			answer(alert.runModal())
		}
	}

	/// What is about to happen, in counts.
	private static func describe(_ situation: Situation) -> String {
		var said = "Bring down what is on the remote and put it into this branch."
		if situation.coming > 0 {
			said += "\n\(situation.coming) commit\(situation.coming == 1 ? "" : "s") to come"
			if situation.going > 0 {
				said += ", \(situation.going) of yours to send"
			}
			said += "."
		} else if situation.going > 0 {
			said += "\nNothing to come; \(situation.going) of yours to send."
		}
		return said
	}

	/// The line about the backup, which appears only when there will be one.
	private static func note(_ situation: Situation) -> String? {
		guard situation.preference.reconciliation == .rebase, situation.going > 0 else {
			return nil
		}
		return "Rebasing rewrites your commit\(situation.going == 1 ? "" : "s"), "
			+ "so \(situation.into) is kept on a backup branch first."
	}

	private static func layout(
		remote: NSView, branch: NSView, into: NSView,
		checkboxes: [NSView], note: String?
	) -> NSView {
		func label(_ text: String) -> NSTextField {
			let field = NSTextField(labelWithString: text)
			field.font = Theme.current.uiFont(12)
			field.textColor = Theme.current.gitIgnored
			field.alignment = .right
			field.setContentHuggingPriority(.required, for: .horizontal)
			return field
		}

		let grid = NSGridView(views: [
			[label("Remote:"), remote],
			[label("Branch:"), branch],
			[label("Into:"), into],
		])
		grid.rowSpacing = 8
		grid.columnSpacing = 8
		grid.column(at: 0).width = 64

		var rows: [NSView] = [grid]
		rows += checkboxes
		if let note {
			let said = NSTextField(wrappingLabelWithString: note)
			said.font = Theme.current.uiFont(11)
			said.textColor = Theme.current.gitAdded
			said.preferredMaxLayoutWidth = 320
			rows.append(said)
		}

		let stack = NSStackView(views: rows)
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 8
		stack.frame = NSRect(x: 0, y: 0, width: 340, height: note == nil ? 150 : 190)
		return stack
	}
}
