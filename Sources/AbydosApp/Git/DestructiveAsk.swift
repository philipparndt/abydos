import AppKit
import AbydosKit

/// Asks before something that can lose work, keeps a ref, and says where it
/// went afterwards.
///
/// **One presenter for all eight**, so the promise cannot be kept in seven
/// places and forgotten in the eighth. What is *said* is `GitDestructive`'s and
/// is tested without a window; what is *done* about it is here: put the
/// question, make the backup before anything runs, and post the toast that
/// names the ref with an undo on it.
///
/// The order matters and is the whole of the guarantee: **the ref exists before
/// the operation starts**. A backup made afterwards is a backup of the wrong
/// thing, and one made concurrently is a race whose loser is somebody's
/// afternoon.
@MainActor
enum DestructiveAsk {
	/// What the caller does once the question has been answered.
	///
	/// It is given the backup that was made, so the toast it triggers can name
	/// it — and nil when the operation was one nothing here can insure, which
	/// is force-pushing and only force-pushing.
	///
	/// It answers with what went wrong, or nil when nothing did. A string
	/// rather than a `ProcessResult` because half the operations behind this
	/// are not one process — a reset that is really a capture, a ref and then a
	/// reset — and the only thing this needs from any of them is whether to say
	/// where the backup went or why there is not one.
	typealias Work = (_ chosen: Int, _ backup: String?) async -> String?

	/// Puts the question, keeps what it promised to keep, and runs the work.
	///
	/// The work is told which choice was taken, because the ones that offer two
	/// are offering two *different operations* — stash and switch, or switch and
	/// leave behind — and not two ways of confirming the same one. The safe
	/// choice is always index 0.
	static func run(
		_ operation: GitDestructive.Operation,
		in root: URL,
		over window: NSWindow?,
		at moment: Date = Date(),
		remembered: Bool = false,
		then work: @escaping Work
	) {
		let ask = GitDestructive.ask(before: operation, at: moment)

		// A remembered answer skips the question — and may only ever be the
		// choice that loses nothing, which `Choice.mayBeRemembered` is the one
		// place that decides. Asked of the ask rather than trusted from the
		// caller: a setting that had drifted would otherwise silently turn a
		// destructive answer into a habit.
		if remembered, let safe = ask.choices.first, safe.mayBeRemembered {
			perform(ask, index: 0, in: root, work: work)
			return
		}

		let alert = NSAlert()
		alert.messageText = ask.title
		alert.informativeText = detail(of: ask)
		for choice in ask.choices { alert.addButton(withTitle: choice.title) }
		alert.addButton(withTitle: "Cancel")

		// Only where the safe choice is the one being remembered. `Always
		// discard` is not a checkbox this app will ever draw.
		if ask.choices.first?.mayBeRemembered == true {
			alert.showsSuppressionButton = true
			alert.suppressionButton?.title = "Always \(ask.choices[0].title.lowercased())"
		}

		let answer: (NSApplication.ModalResponse) -> Void = { response in
			let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
			guard ask.choices.indices.contains(index) else { return }
			perform(ask, index: index, in: root, work: work)
		}

		if let window {
			alert.beginSheetModal(for: window, completionHandler: answer)
		} else {
			answer(alert.runModal())
		}
	}

	/// The question's detail, with what it will keep said last.
	///
	/// Every choice's own sentence is folded in, because an `NSAlert` button is
	/// two or three words and the difference between "stash and switch" and
	/// "switch and leave them behind" is the whole decision.
	private static func detail(of ask: GitDestructive.Ask) -> String {
		var lines = [ask.detail]
		lines += ask.choices
			.filter { !$0.detail.isEmpty }
			.map { "\($0.title): \($0.detail)" }
		return lines.filter { !$0.isEmpty }.joined(separator: "\n\n")
	}

	private static func perform(
		_ ask: GitDestructive.Ask,
		index: Int,
		in root: URL,
		work: @escaping Work
	) {
		let choice = ask.choices[index]

		Task { @MainActor in
			// Nothing is kept for the answer that loses nothing: a stash is its
			// own backup, and a ref per safe operation is the clutter that
			// makes the folder useless.
			var kept: String?
			if !choice.losesNothing, let name = ask.backup {
				kept = await make(name, in: root)
			}

			guard let wrong = await work(index, kept) else {
				guard let kept else { return }
				said(kept, in: root)
				return
			}

			// The backup stays even though the work did not happen: it costs a
			// ref and it is the only thing standing between a half-run
			// operation and somebody's afternoon.
			Toast.post("That did not work", detail: wrong, kind: .error)
			return
		}
	}

	/// Keeps the working copy on a backup branch and says where it went.
	///
	/// For a caller that already asks its own question. `ChangesPane`'s discard
	/// is the one: `GitDiscard` composes a sentence that names the folder and
	/// counts the untracked files inside it, which is better than anything a
	/// general dialog could say, so what it borrows is the *insurance* and not
	/// the wording.
	@discardableResult
	static func insureWorkingCopy(in root: URL, at moment: Date = Date()) async -> String? {
		let name = GitBackup.name(for: "wip", at: moment)
		guard let kept = await make(name, in: root) else { return nil }
		said(kept, in: root)
		return kept
	}

	/// Points a branch under `backup/` at what is about to be lost.
	///
	/// Committed work is kept by the ref the branch already has; uncommitted
	/// work has no ref, so it is captured first — which writes a commit and
	/// touches neither the working copy nor the stash list.
	private static func make(_ name: String, in root: URL) async -> String? {
		// Which of the two it is follows from the name the ask chose, and not
		// from a second decision that could disagree with the first.
		if name.hasSuffix("-wip") {
			guard let commit = await GitBackup.captureWorkingCopy(in: root) else { return nil }
			guard await GitBackup.keep(commit, as: name, in: root).exitCode == 0 else { return nil }
			return name
		}
		let head = await GitRepository.run(["rev-parse", "HEAD"], in: root)
		guard head.exitCode == 0 else { return nil }
		let commit = head.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !commit.isEmpty else { return nil }
		guard await GitBackup.keep(commit, as: name, in: root).exitCode == 0 else { return nil }
		return name
	}

	/// Says where it went, with a way back.
	///
	/// **Insurance nobody is told about is the same as none.** The undo is the
	/// reason this is a toast with a button rather than a line in a log: the ref
	/// is recoverable by hand for as long as it exists, and for the ten seconds
	/// after the mistake it should be recoverable by pressing something.
	private static func said(_ backup: String, in root: URL) {
		Toast.post(Toast(
			kind: .information,
			title: "Kept on \(backup)",
			detail: "Everything that was about to be lost is on that branch.",
			actionTitle: "Undo",
			action: {
				Task { @MainActor in
					let result = await GitRepository.run(
						["reset", "--hard", backup], in: root
					)
					if result.exitCode == 0 {
						NotificationCenter.default.post(
							name: .abydosRepositoryChanged, object: nil
						)
						Toast.post("Put back from \(backup)", kind: .information)
					} else {
						Toast.post("Could not undo", detail: result.stderr, kind: .error)
					}
				}
			}
		))
	}
}
