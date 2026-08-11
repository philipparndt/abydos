import Foundation

/// What applying a `WorkspaceEdit` comes to, worked out without touching
/// anything.
///
/// ## Why there is a plan at all
///
/// A workspace edit is the first thing this program asks a language server that
/// *changes* a file, and it changes many at once: a rename across five hundred
/// bundles is forty files, none of which is open. The failure that matters is
/// twenty of them written and the twenty-first refused, which leaves a project
/// that compiles nowhere and no record of how it got there.
///
/// So the answer is in three layers, and this type is the first and by far the
/// most important of them:
///
///  1. **Everything is read, applied and checked while nothing has been
///     written.** Almost every reason an edit fails is knowable here — a file
///     that is not there, a range the file does not have, two edits that
///     overlap, a rename onto a name something already holds. A plan with a
///     single refusal in it writes *nothing at all*: the person is told which
///     file and why, their project is exactly as it was, and they can fix that
///     one thing and ask again. Half a refactoring is not a lesser good than a
///     whole one, it is worse than none.
///  2. **A write that fails anyway is put back**, by `WorkspaceEditApplier`,
///     using the previous contents this plan already carries — which is the
///     same information the undo entry carries, so the rollback and ⌘Z are one
///     mechanism rather than two that can disagree.
///  3. **A rollback that cannot finish says precisely which files were written
///     and which were not**, by name. That is the floor, and reaching it takes
///     the file system refusing twice.
///
/// ## Why the whole thing is simulated
///
/// `documentChanges` is ordered and the order is load-bearing: jdtls renaming a
/// class sends the edits to `Foo.java` and then the move to `Bar.java`, and a
/// server may equally send the move first and the edits against the new name.
/// Both mean the same thing, and the only way to get both right is to keep a
/// picture of what each path holds as the changes are walked, rather than to
/// pattern-match the shapes that have been seen.
public struct WorkspaceEditPlan: Equatable, Sendable {
	/// One file's text, before and after.
	///
	/// At the path it will have **after** the moves, which is what makes the
	/// plan reversible in one pass: undoing writes `before` back to this same
	/// path and only then moves the file home.
	public struct Write: Equatable, Sendable {
		public let url: URL
		/// What is there now, and nil for a file this edit creates.
		public let before: String?
		public let after: String

		public init(url: URL, before: String?, after: String) {
			self.url = url
			self.before = before
			self.after = after
		}
	}

	public struct Move: Equatable, Sendable {
		public let from: URL
		public let to: URL

		public init(from: URL, to: URL) {
			self.from = from
			self.to = to
		}
	}

	/// A file the edit takes away, with what it held, so undo can put it back.
	public struct Deletion: Equatable, Sendable {
		public let url: URL
		public let contents: String?

		public init(url: URL, contents: String?) {
			self.url = url
			self.contents = contents
		}
	}

	/// Done first, so a write lands at the name the file will keep.
	public let moves: [Move]
	/// Then these, at their final names.
	public let writes: [Write]
	/// And these last, because a file that is going does not need writing to.
	public let deletions: [Deletion]
	/// Whole sentences for everything that cannot be done. **One of these and
	/// nothing happens** — see the note above.
	public let refusals: [String]

	public var isEmpty: Bool { moves.isEmpty && writes.isEmpty && deletions.isEmpty }

	/// Every file this plan touches, at the name it has now. What a summary
	/// counts and what the undo entry is named for.
	public var touched: [URL] {
		var seen: Set<URL> = []
		var order: [URL] = []
		for url in moves.map(\.from) + writes.map(\.url) + deletions.map(\.url) {
			guard seen.insert(url).inserted else { continue }
			order.append(url)
		}
		return order
	}

	/// Works out what the edit comes to.
	///
	/// - Parameters:
	///   - contents: what a file holds, or nil when it cannot be read. **This is
	///     where an open document differs from a closed one**: the caller answers
	///     from the rope for a file with an editor on it and from the disk for
	///     the rest, so that a plan is never computed against a buffer and
	///     written against a file that says something else.
	///   - exists: whether a path is on disk. Separate from `contents` because a
	///     directory exists and has no contents, and a rename onto one has to be
	///     refused rather than treated as a name nothing holds.
	public static func make(
		_ edit: WorkspaceEdit,
		contents: (URL) -> String?,
		exists: (URL) -> Bool
	) -> WorkspaceEditPlan {
		var refusals: [String] = []

		// The picture that is kept while the changes are walked: what each path
		// holds, which paths have been made to exist, and where each file
		// started out. `text` answers nil for a path that has been deleted, so
		// "not in the table" and "deleted" are told apart by `gone`.
		var text: [URL: String] = [:]
		var gone: Set<URL> = []
		var made: Set<URL> = []
		/// Where a file that has moved began, so the move can be recorded once
		/// however many times the file is renamed on the way.
		var origin: [URL: URL] = [:]
		var moveOrder: [URL] = []
		var deletedContents: [URL: String?] = [:]
		var deleteOrder: [URL] = []

		func here(_ url: URL) -> String? {
			if let held = text[url] { return held }
			if gone.contains(url) { return nil }
			return contents(url)
		}

		func present(_ url: URL) -> Bool {
			if text[url] != nil || made.contains(url) { return true }
			if gone.contains(url) { return false }
			return exists(url)
		}

		for change in edit.changes {
			switch change {
			case let .edits(uri, edits):
				guard let url = fileURL(uri) else {
					refusals.append(notAFile(uri))
					continue
				}
				guard let before = here(url) else {
					refusals.append("“\(url.lastPathComponent)” could not be read.")
					continue
				}
				guard let after = LSPTextEdit.applied(edits, to: before) else {
					// The one refusal that is not about the file system. A range
					// the file does not have, or two edits over one character:
					// the server is describing a document that is not the one on
					// disk, and writing its idea of the result would corrupt the
					// file rather than fail to change it.
					refusals.append(
						"The changes to “\(url.lastPathComponent)” did not fit the file. "
							+ "The language server and the file no longer agree about it."
					)
					continue
				}
				text[url] = after

			case let .create(uri, overwrite, ignoreIfExists):
				guard let url = fileURL(uri) else {
					refusals.append(notAFile(uri))
					continue
				}
				if present(url) {
					if ignoreIfExists { continue }
					guard overwrite else {
						refusals.append(
							"“\(url.lastPathComponent)” cannot be made: something is already there."
						)
						continue
					}
				}
				gone.remove(url)
				made.insert(url)
				text[url] = ""

			case let .rename(from, to, overwrite, ignoreIfExists):
				guard let source = fileURL(from) else {
					refusals.append(notAFile(from))
					continue
				}
				guard let destination = fileURL(to) else {
					refusals.append(notAFile(to))
					continue
				}
				guard present(source) else {
					refusals.append("“\(source.lastPathComponent)” is no longer there to rename.")
					continue
				}
				if present(destination), destination != source {
					if ignoreIfExists { continue }
					guard overwrite else {
						refusals.append(
							"“\(source.lastPathComponent)” cannot become "
								+ "“\(destination.lastPathComponent)”: something is already there."
						)
						continue
					}
				}

				let carried = here(source)
				let began = origin[source] ?? source
				text[source] = nil
				gone.insert(source)
				made.remove(source)
				origin[source] = nil

				gone.remove(destination)
				made.insert(destination)
				if let carried { text[destination] = carried }
				// Recorded against where the file *started*, so a file renamed
				// twice is one move rather than two — and a file renamed back to
				// its own name is no move at all.
				if began == destination {
					origin[destination] = nil
					moveOrder.removeAll { $0 == began }
				} else {
					origin[destination] = began
					if !moveOrder.contains(began) { moveOrder.append(began) }
				}

			case let .delete(uri, _, ignoreIfNotExists):
				guard let url = fileURL(uri) else {
					refusals.append(notAFile(uri))
					continue
				}
				guard present(url) else {
					if ignoreIfNotExists { continue }
					refusals.append("“\(url.lastPathComponent)” is no longer there to remove.")
					continue
				}
				if deletedContents[url] == nil { deleteOrder.append(url) }
				deletedContents[url] = here(url)
				text[url] = nil
				gone.insert(url)
				made.remove(url)
			}
		}

		// Where each file ended up, so a write is recorded at the name it will
		// have rather than at the one it had.
		var destination: [URL: URL] = [:]
		for (now, began) in origin { destination[began] = now }

		let moves = moveOrder.compactMap { began -> Move? in
			guard let now = destination[began] else { return nil }
			return Move(from: began, to: now)
		}

		// A file whose text is unchanged is not written. A rename that moves a
		// file and does not edit it is a move and no more, and a write that puts
		// back exactly what was there would still touch the modification date,
		// which is what a build watcher reads.
		let writes = text.keys
			.sorted { $0.path < $1.path }
			.compactMap { url -> Write? in
				guard let after = text[url] else { return nil }
				// What is at this path once the moves have happened: the file
				// that will have been moved here, or whatever was already here.
				//
				// Read from `contents` rather than from `made`, and the
				// difference is a file renamed away and back again: it is in
				// `made` because the walk put it there, and calling it a
				// creation would write it out as new and have undo trash
				// somebody's file. What decides is whether the path held
				// anything before any of this started, which is the one
				// question `contents` answers.
				let source = destination.first { $0.value == url }?.key
				let before = contents(source ?? url)
				guard before != after else { return nil }
				return Write(url: url, before: before, after: after)
			}

		let deletions = deleteOrder.map { Deletion(url: $0, contents: deletedContents[$0] ?? nil) }

		return WorkspaceEditPlan(
			moves: moves, writes: writes, deletions: deletions, refusals: refusals
		)
	}

	/// The file a URI names, and nil for a URI that names no file.
	///
	/// `jdt:` and `untitled:` and the rest are things a server can talk about
	/// and this program cannot write to, and a workspace edit that reaches one
	/// is refused by name rather than dropped.
	static func fileURL(_ uri: String) -> URL? {
		guard let url = URL(string: uri), url.isFileURL else { return nil }
		return URL(fileURLWithPath: url.path)
	}

	private static func notAFile(_ uri: String) -> String {
		"“\(uri)” is not a file this editor can change."
	}
}
