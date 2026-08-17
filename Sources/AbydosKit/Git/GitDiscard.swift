import Foundation

/// What throwing away a row's changes would cost, and how to say it.
///
/// In the engine rather than in the pane because the arithmetic *is* the
/// substance of the question. Discard is the one thing the changes pane can do
/// that has no way back — a stash can be popped, staging can be unstaged, a
/// `.gitignore` line can be deleted — and for a file git has never seen there is
/// not even an object left afterwards: `clean -fd` takes it off the disk. A
/// confirmation that says "3 files" while a fourth is about to be deleted is the
/// kind of mistake that costs somebody work they cannot get back, so the counts
/// and the sentences are here, where they can be checked without a window.
///
/// Two losses, not one, and the second is the one that surprises people: a
/// tracked file goes back to the version in the index, and an untracked file
/// stops existing. Everything below exists to keep those apart in the wording.
public enum GitDiscard {
	/// The row the discard was asked for, for naming it.
	public enum Subject: Equatable, Sendable {
		/// One changed file.
		case file(String)
		/// One folder, with changes under it.
		case folder(String)
		/// Several rows chosen together, which no single name describes.
		case rows
	}

	/// The changes these paths cover.
	///
	/// A folder path covers everything beneath it, which is the same rule
	/// `git clean` and `git checkout` follow when they are handed a directory —
	/// so the number in the confirmation is the number of files git is about to
	/// act on, rather than the number of rows somebody clicked.
	public static func changes(_ changes: [GitChange], under paths: [String]) -> [GitChange] {
		changes.filter { change in
			paths.contains { change.path == $0 || change.path.hasPrefix($0 + "/") }
		}
	}

	/// Whether nothing here can be restored, only deleted.
	///
	/// The verb changes on it. "Discard Changes" over a file git has never seen
	/// is false — there are no changes, there is a file, and it is about to stop
	/// existing — and the menu entry is the last place that can say so before
	/// the confirmation has to.
	private static func isDeletionOnly(files: Int, untracked: Int) -> Bool {
		files > 0 && untracked == files
	}

	/// What the menu entry says.
	///
	/// A folder says how many files it is about to take, the way Stage and
	/// Unstage already do: the difference between one file and forty is the whole
	/// reason folder staging is worth being careful with, and discard needs it
	/// more rather than less. When some of them are untracked it says that too,
	/// because they are the ones that do not come back.
	public static func menuTitle(subject: Subject, files: Int, untracked: Int) -> String {
		let deleting = isDeletionOnly(files: files, untracked: untracked)
		let plural = files == 1 ? "" : "s"

		switch subject {
		case .file(let name):
			// The name is left out of the ordinary case for the same reason
			// Stage leaves it out: the row it was opened on is under the pointer.
			return deleting ? "Delete “\(name)”\u{2026}" : "Discard Changes\u{2026}"
		case .folder(let name):
			guard !deleting else { return "Delete “\(name)” (\(files) file\(plural))\u{2026}" }
			let alsoUntracked = untracked > 0 ? ", \(untracked) untracked" : ""
			return "Discard Changes in “\(name)” (\(files) file\(plural)\(alsoUntracked))\u{2026}"
		case .rows:
			guard !deleting else { return "Delete \(files) File\(plural)\u{2026}" }
			let alsoUntracked = untracked > 0 ? " (\(untracked) untracked)" : ""
			return "Discard Changes in \(files) File\(plural)\(alsoUntracked)\u{2026}"
		}
	}

	/// The confirmation's question.
	public static func question(subject: Subject, files: Int, untracked: Int) -> String {
		let deleting = isDeletionOnly(files: files, untracked: untracked)
		let plural = files == 1 ? "" : "s"

		switch subject {
		case .file(let name):
			return deleting ? "Delete “\(name)”?" : "Discard changes to “\(name)”?"
		case .folder(let name):
			return deleting
				? "Delete \(files) file\(plural) under “\(name)”?"
				: "Discard changes in \(files) file\(plural) under “\(name)”?"
		case .rows:
			return deleting ? "Delete \(files) files?" : "Discard changes in \(files) files?"
		}
	}

	/// The sentence under the question: what is lost, and what to do instead.
	///
	/// It names stash. The pane already has it, it is discard with a way back,
	/// and a confirmation that offers only "yes" and "no" leaves somebody who
	/// wanted neither to work it out under a sheet.
	public static func explanation(files: Int, untracked: Int) -> String {
		var sentences: [String] = []
		let them = files == 1 ? "it" : "them"

		if isDeletionOnly(files: files, untracked: untracked) {
			sentences.append(files == 1
				? "Git is not tracking this file, so there is no version to put back: "
					+ "it is deleted from the disk."
				: "Git is not tracking these files, so there is no version to put back: "
					+ "they are deleted from the disk.")
		} else if untracked > 0 {
			// The two losses, spelt out separately. A single sentence covering
			// both would have to call deleting a file "reverting" it.
			sentences.append("\(untracked) of them \(untracked == 1 ? "is" : "are") untracked and "
				+ "\(untracked == 1 ? "is" : "are") deleted from the disk — git has no version of "
				+ "\(untracked == 1 ? "it" : "them") to put back.")
			// "The other 1 go back" is what the plural form reads as on a folder
			// holding two files, one of them new, which is not a rare shape.
			let others = files - untracked
			sentences.append(others == 1
				? "The other one goes back to the version in the index: what was last staged "
					+ "for it, or last committed."
				: "The other \(others) go back to the version in the index: "
					+ "what was last staged for them, or last committed.")
		} else {
			sentences.append(files == 1
				? "The file goes back to the version in the index: what was last staged for it, "
					+ "or last committed."
				: "The files go back to the version in the index: what was last staged for them, "
					+ "or last committed.")
		}

		sentences.append("This cannot be undone. Stash \(them) instead to keep a way back.")
		return sentences.joined(separator: " ")
	}

	/// What the button that goes through with it says.
	public static func buttonTitle(files: Int, untracked: Int) -> String {
		isDeletionOnly(files: files, untracked: untracked) ? "Delete" : "Discard"
	}

	/// Which of `paths` git already has something tracked under, given the files
	/// it knows about.
	///
	/// Pure so that the rule can be checked without a repository: the paths are
	/// rows somebody clicked, `known` is what `git ls-files` answered for them,
	/// and a folder stays one argument rather than being expanded into the files
	/// beneath it.
	static func paths(_ paths: [String], coveringAnyOf known: [String]) -> [String] {
		paths.filter { path in
			// The work tree root is nothing's prefix and covers everything, so
			// it has to be said rather than derived. Nothing in the changes pane
			// hands it over — every row there is a real relative path — but the
			// working copy is a public API and "throw away the lot" is the first
			// thing anybody tries it with.
			guard path != ".", !path.isEmpty else { return !known.isEmpty }
			return known.contains { $0 == path || $0.hasPrefix(path + "/") }
		}
	}
}
