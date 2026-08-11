import Foundation

/// The files a workspace edit acts on, as five things that can be done to them.
///
/// A seam rather than `FileManager` directly, for two reasons that are both the
/// point of this item. The first is that **an open document is not its file**:
/// a document with an editor on it has to change through its rope or the buffer
/// and the disk disagree, and that is a substitution here rather than a special
/// case threaded through the applier. The second is that a rollback is only
/// worth having if it has been driven, and a write that refuses is not
/// something a test can arrange on a real disk without making the machine
/// strange.
public struct WorkspaceEditFiles {
	/// What a file holds, or nil when it cannot be read.
	public var contents: (URL) -> String?
	public var exists: (URL) -> Bool
	public var write: (URL, String) throws -> Void
	public var move: (URL, URL) throws -> Void
	/// To the trash, never deleted outright — the rule `FileUndo` settled. A ⌘Z
	/// that cannot put a file back should at least leave it somewhere the Finder
	/// can.
	public var trash: (URL) throws -> Void

	public init(
		contents: @escaping (URL) -> String?,
		exists: @escaping (URL) -> Bool,
		write: @escaping (URL, String) throws -> Void,
		move: @escaping (URL, URL) throws -> Void,
		trash: @escaping (URL) throws -> Void
	) {
		self.contents = contents
		self.exists = exists
		self.write = write
		self.move = move
		self.trash = trash
	}

	/// The plain answer: the files as they are on disk.
	public static var disk: WorkspaceEditFiles { WorkspaceEditFiles(
		contents: { try? String(contentsOf: $0, encoding: .utf8) },
		exists: { FileManager.default.fileExists(atPath: $0.path) },
		write: { url, text in
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try Data(text.utf8).write(to: url, options: .atomic)
		},
		move: { from, to in
			try FileManager.default.createDirectory(
				at: to.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try FileManager.default.moveItem(at: from, to: to)
		},
		trash: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
	) }
}

/// Carrying out a `WorkspaceEditPlan`, and putting it back when that is what
/// has to happen.
///
/// The three layers of the partial-failure answer are all here, and the whole
/// argument for them is at the top of `WorkspaceEditPlan`. In one sentence:
/// **nothing is written until everything has been checked, a write that fails
/// anyway is put back, and a putting-back that fails names every file on both
/// sides.**
public enum WorkspaceEditApplier {
	/// What happened, which is one of four things and never a `Bool`.
	public enum Outcome: Equatable, Sendable {
		/// Nothing was touched. The sentences say why, and the project is
		/// exactly as it was.
		case refused([String])
		/// All of it happened. The plan is carried so that one ⌘Z can run it
		/// backwards.
		case applied(WorkspaceEditPlan)
		/// Something refused partway and everything already done was put back.
		/// The project is as it was, and this says which file stopped it.
		case putBack(failure: String)
		/// Something refused partway, and putting it back refused as well.
		/// **This is the state the whole design exists to make rare**, and when
		/// it happens the only thing worth doing is being exact.
		case halfDone(failure: String, changed: [URL], unchanged: [URL])

		/// Whether the project is as it was.
		public var isUntouched: Bool {
			switch self {
			case .refused, .putBack: return true
			case .applied, .halfDone: return false
			}
		}
	}

	/// One recorded step, so that undoing is the same walk as failing.
	fileprivate enum Done {
		case moved(from: URL, to: URL)
		case wrote(url: URL, before: String?)
		case trashed(url: URL, contents: String?)
	}

	/// Carries the plan out.
	///
	/// Moves first, so a write lands at the name the file will keep; then the
	/// writes; then the deletions, because a file that is going does not need
	/// writing to first.
	public static func apply(
		_ plan: WorkspaceEditPlan, to files: WorkspaceEditFiles
	) -> Outcome {
		guard plan.refusals.isEmpty else { return .refused(plan.refusals) }
		guard !plan.isEmpty else { return .applied(plan) }

		var done: [Done] = []

		func fail(_ url: URL, _ error: Error, _ verb: String) -> Outcome {
			let failure = "“\(url.lastPathComponent)” could not be \(verb): "
				+ error.localizedDescription
			return undo(done, with: files, after: failure)
		}

		for move in plan.moves {
			do {
				try files.move(move.from, move.to)
				done.append(.moved(from: move.from, to: move.to))
			} catch {
				return fail(move.from, error, "renamed")
			}
		}

		for write in plan.writes {
			do {
				try files.write(write.url, write.after)
				done.append(.wrote(url: write.url, before: write.before))
			} catch {
				return fail(write.url, error, "written")
			}
		}

		for deletion in plan.deletions {
			do {
				try files.trash(deletion.url)
				done.append(.trashed(url: deletion.url, contents: deletion.contents))
			} catch {
				return fail(deletion.url, error, "removed")
			}
		}

		return .applied(plan)
	}

	/// Takes back everything in `done`, newest first.
	///
	/// Newest first because the steps are ordered and the later ones stand on
	/// the earlier ones: a file that was moved and then written has to be
	/// written back before it is moved home, or the write goes to a path the
	/// move has already emptied.
	private static func undo(
		_ done: [Done], with files: WorkspaceEditFiles, after failure: String
	) -> Outcome {
		var stuck: [URL] = []
		var restored: [URL] = []

		for step in done.reversed() {
			do {
				switch step {
				case let .moved(from, to):
					try files.move(to, from)
					restored.append(from)
				case let .wrote(url, before):
					// A file that did not exist before goes to the trash rather
					// than being left empty, which is what an undo of a creation
					// does everywhere else in this program.
					if let before {
						try files.write(url, before)
					} else {
						try files.trash(url)
					}
					restored.append(url)
				case let .trashed(url, contents):
					// Written back rather than fished out of the trash. The trash
					// renames on collision and only `NSWorkspace.recycle` says
					// where a file went; the contents are already in hand, which
					// is a shorter road to the same file.
					try files.write(url, contents ?? "")
					restored.append(url)
				}
			} catch {
				stuck.append(step.url)
			}
		}

		guard stuck.isEmpty else {
			// Exact, by name, on both sides. Somebody whose project is half
			// changed needs to know which half, and a count is not that.
			return .halfDone(
				failure: failure,
				changed: stuck.reversed(),
				unchanged: restored.reversed()
			)
		}
		return .putBack(failure: failure)
	}

	/// Runs an applied plan backwards. One ⌘Z, however many files it was.
	///
	/// The same walk `undo` above does, over the whole plan rather than over the
	/// part of it that happened — which is what makes the rollback and the undo
	/// one mechanism rather than two that can come to disagree.
	public static func reverse(
		_ plan: WorkspaceEditPlan, in files: WorkspaceEditFiles
	) -> Outcome {
		var done: [Done] = plan.moves.map { .moved(from: $0.from, to: $0.to) }
		done += plan.writes.map { .wrote(url: $0.url, before: $0.before) }
		done += plan.deletions.map { .trashed(url: $0.url, contents: $0.contents) }
		return undo(done, with: files, after: "")
	}
}

fileprivate extension WorkspaceEditApplier.Done {
	/// The file a step is about, at the name it has once the step has happened.
	var url: URL {
		switch self {
		case let .moved(_, to): return to
		case let .wrote(url, _): return url
		case let .trashed(url, _): return url
		}
	}
}

// MARK: - Saying what happened

public extension WorkspaceEditApplier.Outcome {
	/// The one message this gets, or nil when there is nothing to say.
	///
	/// One message however many files, the way `FileUndo.Reversal.summary` is
	/// one however many it put back: a rename is one gesture, and forty toasts
	/// arriving after it would make it forty.
	///
	/// Silence on success is deliberate and the same rule as everywhere else
	/// here — the files have changed on screen, which is the whole of what was
	/// asked for.
	var summary: (title: String, detail: String)? {
		switch self {
		case .applied:
			return nil
		case let .refused(reasons):
			return (
				title: "Nothing was renamed",
				detail: (reasons + ["Nothing has been changed."]).joined(separator: " ")
			)
		case let .putBack(failure):
			return (
				title: "Nothing was renamed",
				detail: "\(failure) Everything that had been changed was put back."
			)
		case let .halfDone(failure, changed, unchanged):
			var sentences = [failure]
			sentences.append(
				"These files were changed and could not be put back: "
					+ changed.map { "“\($0.lastPathComponent)”" }.joined(separator: ", ") + "."
			)
			if unchanged.isEmpty {
				sentences.append("Nothing else was changed.")
			} else {
				sentences.append(
					"Everything else was put back: "
						+ unchanged.map { "“\($0.lastPathComponent)”" }.joined(separator: ", ") + "."
				)
			}
			return (title: "The rename did not finish", detail: sentences.joined(separator: " "))
		}
	}
}
