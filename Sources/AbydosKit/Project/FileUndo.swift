import Foundation

/// What a gesture in the tree did to the files, and what taking it back means.
///
/// Kept out of the view for the reason `FileTransfer` is: the rules are worth
/// testing without a window, and there are more of them than there look to be.
/// The app target has no tests at all, so anything left in the view controller
/// is anything nobody can check.
///
/// ## Two reversals, five gestures
///
/// Everything the tree can do to a file comes back to one of two acts:
///
/// | gesture | undo |
/// |---|---|
/// | move to trash | move it back out of the trash |
/// | rename | move it back to its old name |
/// | move (drag, ⌥⌘V) | move it back to the folder it came from |
/// | copy, paste, duplicate | move the copy to the trash |
/// | new file or folder | move it to the trash |
///
/// So an `Action` is a list of `Restore`s — put what is now here back there —
/// and a list of `Discard`s, which go to the trash. A gesture only ever makes
/// one kind, but both live in the one type because undoing either is the same
/// walk with the same refusals.
///
/// ## Why a copy is trashed rather than deleted
///
/// Undoing a copy is the one undo in the family that destroys something, and
/// the app has no other operation that removes a file outright. It would be a
/// poor place to start: ⌘Z is pressed by reflex, often twice, and the second
/// press is not a decision. So the copy goes where a deliberate delete goes,
/// and the Finder can still put it back.
///
/// ## Why an undo can refuse
///
/// A file operation is not undoable for ever, and the ways it stops being
/// undoable are ordinary rather than exotic: the trash gets emptied, the name
/// gets taken by something else, the folder a file came from is itself trashed
/// a minute later, a build rewrites the copy. Each of those is a sentence
/// rather than a silent no-op or a guess — the standard `FileTransfer`'s own
/// refusals meet, and the reason `reverse` answers with words instead of a
/// `Bool`.
///
/// The change check is on discards only, and it is the one that earns its keep:
/// somebody makes a new file, writes in it, comes back to the tree and presses
/// ⌘Z. Trashing what they just wrote because a stale entry says the file was
/// theirs to remove is exactly the behaviour that teaches people not to trust
/// undo. A restore does not need the check — moving a changed file home is
/// still putting it where it belongs.
public enum FileUndo {
	/// Which gesture is being taken back.
	///
	/// Carried through so the menu can say what ⌘Z will do, and so a refusal can
	/// be worded for what actually happened: "no longer in the trash" is only
	/// true of one of the five.
	public enum Gesture: Equatable, Sendable {
		case trash, rename, move, copy, newFile, newFolder

		/// What `NSUndoManager.setActionName` is given, which the Edit menu turns
		/// into "Undo Move to Trash".
		public var title: String {
			switch self {
			case .trash: return "Move to Trash"
			case .rename: return "Rename"
			case .move: return "Move"
			case .copy: return "Copy"
			case .newFile: return "New File"
			case .newFolder: return "New Folder"
			}
		}

		/// "copied" / "made", for saying that a file has changed since.
		var past: String {
			switch self {
			case .copy: return "copied"
			default: return "made"
			}
		}

		/// What undoing this gesture does, for the one message afterwards.
		var undone: String {
			switch self {
			case .trash, .rename, .move: return "put back"
			case .copy, .newFile, .newFolder: return "moved to the trash"
			}
		}
	}

	/// One file to put back: what is at `from` now belongs at `to`.
	///
	/// Both ends are absolute, and for a trash `from` is the path the trash
	/// answered with rather than one worked out from the name — the trash renames
	/// on collision, so two files called `main.py` from different folders do not
	/// both keep the name, and there is nowhere else to learn which is which.
	public struct Restore: Equatable, Sendable {
		public let from: URL
		public let to: URL

		public init(from: URL, to: URL) {
			self.from = from
			self.to = to
		}
	}

	/// One file to take away, and when it was last written at the moment it
	/// arrived.
	///
	/// `made` is nil when the date could not be read, and the change check is
	/// then skipped rather than guessed at: refusing to undo because a `stat`
	/// failed would be a refusal about the wrong thing.
	public struct Discard: Equatable, Sendable {
		public let url: URL
		public let made: Date?

		public init(url: URL, made: Date?) {
			self.url = url
			self.made = made
		}
	}

	/// What one gesture left behind, and how to take it back.
	public struct Action: Equatable, Sendable {
		public let gesture: Gesture
		public let restores: [Restore]
		public let discards: [Discard]

		public init(gesture: Gesture, restores: [Restore] = [], discards: [Discard] = []) {
			self.gesture = gesture
			self.restores = restores
			self.discards = discards
		}

		/// Nothing to take back, so nothing worth putting on the stack. A ⌘Z that
		/// pops an entry and does nothing is a ⌘Z that has eaten the one before it.
		public var isEmpty: Bool { restores.isEmpty && discards.isEmpty }
	}

	/// What an undo will actually do, worked out without touching anything.
	public struct Reversal: Equatable, Sendable {
		/// The ones that can happen, in the order they were recorded.
		public let restores: [Restore]
		/// The ones to move to the trash.
		public let discards: [URL]
		/// Whole sentences for the ones that cannot.
		public let refusals: [String]

		public var hasWork: Bool { !restores.isEmpty || !discards.isEmpty }
	}

	/// Works out what taking the gesture back comes to, without touching
	/// anything.
	///
	/// - Parameters:
	///   - exists: whether a path is on disk. Injected rather than read, the way
	///     `FileTransfer.plan` takes it, so every refusal can be exercised
	///     without staging a trash folder.
	///   - modified: when a file was last written, for the change check on the
	///     ones that would be thrown away.
	public static func reverse(
		_ action: Action,
		exists: (URL) -> Bool,
		modified: (URL) -> Date?
	) -> Reversal {
		var restores: [Restore] = []
		var discards: [URL] = []
		var refusals: [String] = []

		for restore in action.restores {
			// The name to say it with. For a trash that is the *original* name:
			// what sits in the trash may have been renamed on the way in, and
			// "“main 3.py” is no longer in the trash" names a file nobody ever
			// made. For a rename or a move it is the name the file has now.
			let spoken = action.gesture == .trash
				? restore.to.lastPathComponent
				: restore.from.lastPathComponent
			let arriving = restore.to.lastPathComponent
			guard exists(restore.from) else {
				refusals.append(
					action.gesture == .trash
						? "“\(spoken)” is no longer in the trash."
						: "“\(spoken)” is no longer there."
				)
				continue
			}
			// The folder it came from can have been trashed since — which is an
			// ordinary thing to do a minute after trashing a file inside it, and
			// would otherwise arrive as whatever `moveItem` says about ENOENT.
			let folder = restore.to.deletingLastPathComponent()
			guard exists(folder) else {
				refusals.append(
					"“\(arriving)” cannot go back: the folder “\(folder.lastPathComponent)” "
						+ "is no longer there."
				)
				continue
			}
			// Nothing is ever overwritten, here least of all: an undo that wrote
			// over a file would need an undo of its own.
			guard !exists(restore.to) else {
				refusals.append("“\(arriving)” cannot go back: something else is there now.")
				continue
			}
			restores.append(restore)
		}

		for discard in action.discards {
			let name = discard.url.lastPathComponent
			guard exists(discard.url) else {
				refusals.append("“\(name)” is no longer there.")
				continue
			}
			if let made = discard.made, let now = modified(discard.url), now != made {
				refusals.append("“\(name)” has changed since it was \(action.gesture.past).")
				continue
			}
			discards.append(discard.url)
		}

		return Reversal(restores: restores, discards: discards, refusals: refusals)
	}
}

// MARK: - What each gesture leaves behind

public extension FileUndo {
	/// What `NSWorkspace.recycle` answered with, kept.
	///
	/// The dictionary is original URL to where in the trash it went, and it is
	/// the whole reason a trash is undoable: the trash renames on collision, so
	/// the name in there is not derivable from the name that went in. Sorted by
	/// the original path, because a dictionary has no order and a stack entry
	/// should not change shape between two runs.
	static func trashed(_ locations: [URL: URL]) -> Action {
		let restores = locations
			.sorted { $0.key.path < $1.key.path }
			.map { Restore(from: $0.value, to: $0.key) }
		return Action(gesture: .trash, restores: restores)
	}

	/// A rename: the file is at `to` now and belongs at `from`.
	static func renamed(from: URL, to: URL) -> Action {
		Action(gesture: .rename, restores: [Restore(from: to, to: from)])
	}

	/// A drop or a paste, from whichever of its transfers actually happened.
	///
	/// A move goes home; a copy goes to the trash. The ones the file system
	/// refused are not in the list, so nothing on the stack claims work that was
	/// never done.
	static func transferred(
		_ transfers: [FileTransfer.Transfer],
		operation: FileTransfer.Operation,
		modified: (URL) -> Date?
	) -> Action {
		switch operation {
		case .move:
			return Action(
				gesture: .move,
				restores: transfers.map { Restore(from: $0.destination, to: $0.source) }
			)
		case .copy:
			return Action(
				gesture: .copy,
				discards: transfers.map { Discard(url: $0.destination, made: modified($0.destination)) }
			)
		}
	}

	/// A new file or folder, which undo takes away again.
	static func created(_ url: URL, isDirectory: Bool, modified: (URL) -> Date?) -> Action {
		Action(
			gesture: isDirectory ? .newFolder : .newFile,
			discards: [Discard(url: url, made: modified(url))]
		)
	}
}

// MARK: - Saying what did not happen

public extension FileUndo.Reversal {
	/// The one message the whole undo gets, or nil when it all went back.
	///
	/// One message however many files, and the same shape as
	/// `FileTransfer.Plan.summary` for the same reason: ⌘Z is one gesture, and
	/// three dialogs arriving after it would make it three.
	///
	/// Silence on success is deliberate. The tree shows the file back where it
	/// was, which is the whole of what was asked for, and a toast saying so
	/// would be an app congratulating itself.
	///
	/// - Parameters:
	///   - done: how many actually happened, which is not `restores.count` when
	///     the file system refused one of them.
	///   - failures: whole sentences for the ones it refused.
	func summary(
		gesture: FileUndo.Gesture, done: Int, failures: [String] = []
	) -> (title: String, detail: String)? {
		guard !refusals.isEmpty || !failures.isEmpty else { return nil }

		var sentences = refusals + failures
		if done == 1 {
			sentences.append("The other one was \(gesture.undone).")
		} else if done > 1 {
			sentences.append("The other \(done) were \(gesture.undone).")
		}

		return (
			title: done == 0
				? "Nothing was \(gesture.undone)"
				: "Not everything was \(gesture.undone)",
			detail: sentences.joined(separator: " ")
		)
	}
}
