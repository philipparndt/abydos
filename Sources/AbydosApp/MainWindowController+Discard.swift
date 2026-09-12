import AppKit
import AbydosKit

/// Throwing work away, from wherever it was asked.
///
/// The changes pane's *Discard* and the project tree's *Discard Changes* both
/// end here. The pane had the verb to itself, and a file in the tree — the
/// same file, one tab over — had no way to ask: somebody reading a diff they
/// had decided against had to find the file again in another pane to throw
/// the diff away. The verb is the window's now because the window is what the
/// two have in common, and because the estate it runs across is the window's
/// — the pane may not be open, and a tree that showed the pane to borrow a
/// method would have changed the window to do a thing asked of a row.
extension MainWindowController {
	/// Insures every repository the paths fall in, discards across them, and
	/// says where the refs went.
	///
	/// **The most-used destructive verb in the app, insured.** The question
	/// is asked before this and is `GitDiscard`'s — it names the folder and
	/// counts what git has never seen, which no general dialog could — so what
	/// is borrowed from the safety net is the ref, made before anything is
	/// restored, and the toast that says where it went.
	///
	/// **The safety net is asked once for the whole operation and every
	/// repository is insured before any file is discarded.** Insuring and
	/// discarding repository by repository has no way back from a failure
	/// part way through — the ones before it have moved and only some were
	/// recorded. Two hundred questions is also no question at all: a dialogue
	/// repeated per repository is answered by holding Return, and two hundred
	/// toasts afterwards are read by nobody.
	///
	/// - Parameter paths: relative to the estate's root, which is what a
	///   `GitChange` carries and what `Project.place(of:)` answers for a URL.
	@discardableResult
	func discard(paths: [String]) async -> [GitEstateOutcome] {
		guard let project, !paths.isEmpty else { return [] }
		let estate = project.estate
		let insured = await DestructiveAsk.insureEstate(estate.grouped(paths))
		let outcomes = await GitEstateOperation.discard(paths: paths, in: estate)
		DestructiveAsk.sayWhatHappened("discarded", outcomes, insured: insured)
		return outcomes
	}

	/// The tree's confirmation button: the verb, and then what the pane's
	/// own path does for itself afterwards.
	///
	/// The watcher would get to all three — the file was rewritten on disk —
	/// but a quarter of a second after the button with the old colour and
	/// the old text still up is long enough to press it twice. The pane's
	/// `runAcrossOwners` refreshes on the command's own word for the same
	/// reason.
	func discardFromTree(_ target: GitDiscard.Target) async {
		await discard(paths: target.paths)
		navigator.refreshGitStatus()
		editor.reloadExternallyChangedFiles()
		sidebar.changesPane?.refresh()
	}
}
