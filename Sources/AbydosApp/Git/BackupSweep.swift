import AppKit
import AbydosKit

/// Deleting the backup refs past a chosen age.
///
/// **The verb the `backup/` folder is kept for.** `git-refs-tree` has said the
/// folder carries it since the specification was written and `GitBackup.sweep`
/// has done it for as long; nothing offered it, and until `PathTree` learnt to
/// keep the folder there was often no row to offer it on.
///
/// Its own type because it needs three things from the pane — where the
/// repository is, a window to put a sheet over, and something to call when the
/// refs change — and none of them is the pane's private state.
enum BackupSweep {
	/// The ages offered, shortest-lived first.
	///
	/// Named rather than typed into a field: the question is *how far back do I
	/// still care*, which has three real answers, and a field would ask for a
	/// number of days to answer it with.
	static let ages: [(title: String, seconds: TimeInterval)] = [
		("Older Than a Week", 7 * 24 * 3600),
		("Older Than a Month", 30 * 24 * 3600),
		("Older Than Three Months", 90 * 24 * 3600),
	]

	/// What the sheet answers in a driven run. A driven run that opens a sheet
	/// is a driven run that stops.
	static var answerForTesting: Int?

	/// Asks which age, having said what each one would take, and then takes it.
	///
	/// **The count comes before the choice, not after it.** A backup ref is the
	/// only copy of what it holds — that is what it is for — so *delete
	/// everything older than a month* is a sentence nobody can weigh without
	/// being told it means four refs or forty.
	@MainActor
	static func run(in root: URL, over window: NSWindow?, then changed: @escaping () -> Void) {
		Task { @MainActor in
			let entries = await GitBackup.list(in: root)
			guard !entries.isEmpty else {
				Toast.post("There are no backups to delete")
				return
			}
			let now = Date()
            let counted = ages.map { age in
				(age, entries.filter { now.timeIntervalSince($0.made) > age.seconds }.count)
			}

			let alert = NSAlert()
			alert.messageText = "Delete backups older than…"
			alert.informativeText = counted
				.map { "\($0.0.title): \($0.1) of \(entries.count)" }
				.joined(separator: "\n")
			for (age, count) in counted {
				// Nothing to take is a button that would do nothing.
				alert.addButton(withTitle: age.title).isEnabled = count > 0
			}
			alert.addButton(withTitle: "Cancel")

			let chosen = await ask(alert, over: window)
			let index = chosen - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
			guard counted.indices.contains(index) else { return }

			let taken = await GitBackup.sweep(
				olderThan: counted[index].0.seconds, now: now, in: root
			)
			Toast.post(taken.isEmpty
				? "No backups were old enough"
				: "Deleted \(taken.count) backup\(taken.count == 1 ? "" : "s")")
			changed()
		}
	}

	@MainActor
	private static func ask(_ alert: NSAlert, over window: NSWindow?) async -> Int {
		if let canned = answerForTesting { return canned }
		guard let window else { return NSApplication.ModalResponse.cancel.rawValue }
		return await withCheckedContinuation { continuation in
			alert.beginSheetModal(for: window) { continuation.resume(returning: $0.rawValue) }
		}
	}
}
