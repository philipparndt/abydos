import Foundation

/// What a drop, or a paste, of several files into one folder comes to.
///
/// Kept out of the view for the reason `EntryName` is: the rules are worth
/// testing without a window, and a drop has more of them than a rename does —
/// a folder must not be dropped inside itself, the project root must not go
/// anywhere, and twelve files dropped where three of them collide has to have
/// one answer rather than twelve.
///
/// ## Twelve files, three collisions
///
/// **The ones that can go, go; the ones that collide stay where they are; and
/// the whole drop says so once.** Nothing is ever overwritten.
///
/// The alternatives were a prompt per file — a wall of dialogs, and the same
/// "there is nowhere to say four things" `exportDiagram` already states — or
/// refusing the whole drop, which throws away the nine that were fine because
/// three were not. Replacing was never on the table: `commitRename` already
/// answers a collision by refusing rather than overwriting, and skipping keeps
/// that rule the same everywhere instead of "a collision never overwrites,
/// except when dragged".
///
/// One of the supports has since moved. 0436 also argued that there was no undo,
/// so an overwrite would be unrecoverable; 0442 gave the tree one. It does not
/// carry an overwrite, though — undoing one means having kept the overwritten
/// file somewhere, which is a much larger promise than moving a file back to
/// where it came from, and `FileUndo` refuses onto an occupied name for exactly
/// that reason. **The skip rule stands on the supports it has left**, until
/// somebody argues it down on its own merits.
///
/// Renaming the newcomer the way the Finder's "Keep Both" does was considered
/// and left out *for a collision between two different files*: it produces a
/// file nobody asked for under a name nobody chose, and after a twelve-file drop
/// there is no telling which of the two is which.
///
/// ## Copying a file into the folder it is already in
///
/// That one is different, and it does get a new name. A collision between two
/// different files may be an accident — the wrong folder, a stale pasteboard —
/// and refusing is the safe answer. Copying a file onto its own folder cannot
/// be an accident: there is no other thing it could have meant. So it duplicates,
/// as `main.py` → `main-1.py`, and the next one is `main-2.py`.
///
/// The number goes before the extension, so the copy is still a Python file, and
/// it is the first free one rather than a count — duplicate `main-1.py` itself
/// and the answer is `main-1-1.py`, not `main-2.py`. Incrementing the number
/// that is already there would quietly take the next name in somebody's series:
/// a second copy of `chapter-1.md` is not `chapter-2.md`.
public enum FileTransfer {
	public enum Operation: Sendable {
		case move, copy

		/// "moved" / "copied", for saying what did and did not happen.
		public var past: String {
			switch self {
			case .move: return "moved"
			case .copy: return "copied"
			}
		}
	}

	public struct Transfer: Equatable, Sendable {
		public let source: URL
		public let destination: URL

		public init(source: URL, destination: URL) {
			self.source = source
			self.destination = destination
		}
	}

	/// Everything a drop was asked to do, split by what became of it.
	public struct Plan: Sendable {
		/// The ones that will happen, in the order they were given.
		public let transfers: [Transfer]
		/// Names already taken in the destination. Left where they were.
		public let collisions: [URL]
		/// Whole sentences: the project root, a folder inside itself, a source
		/// that is no longer on disk.
		public let refusals: [String]
		/// A move onto the folder the file is already in. Nothing to do, and
		/// nothing worth saying about it either — it is what dropping a row two
		/// pixels from where it started does, and a message for that would be a
		/// message for a slip of the hand.
		public let unchanged: [URL]

		/// Whether the drop is worth taking at all. `validateDrop` answers with
		/// this, so a drag that could only refuse shows the "no" cursor rather
		/// than accepting and then explaining.
		public var hasWork: Bool { !transfers.isEmpty }
	}

	/// Works out what happens, without touching anything.
	///
	/// - Parameter exists: whether a path is on disk. Injected rather than read,
	///   so the rules can be exercised without a temporary directory — and it
	///   answers for the sources as well as for the destination names, since a
	///   pasteboard written five minutes ago may name a file that has since
	///   gone.
	public static func plan(
		_ sources: [URL],
		into destination: URL,
		operation: Operation,
		projectRoot: URL?,
		exists: (URL) -> Bool
	) -> Plan {
		let folder = destination.standardizedFileURL
		let root = projectRoot?.standardizedFileURL

		var transfers: [Transfer] = []
		var collisions: [URL] = []
		var refusals: [String] = []
		var unchanged: [URL] = []
		// Names this plan has already spoken for. Nothing is on disk yet, so
		// `exists` cannot know about them, and two duplicates in one drop would
		// otherwise both be offered the same free number.
		var claimed: Set<String> = []

		for raw in sources {
			let source = raw.standardizedFileURL
			let name = source.lastPathComponent

			// The project root first: it is the most specific answer, and
			// "cannot go inside itself" would be a confusing way to say it.
			if let root, source.path == root.path {
				refusals.append("“\(name)” is the project root.")
				continue
			}
			// A folder into itself, or into anything under it — which is how a
			// tree eats itself. `+ "/"` rather than a bare prefix, so `/a/b`
			// does not look like an ancestor of `/a/bc`.
			if folder.path == source.path || folder.path.hasPrefix(source.path + "/") {
				refusals.append("“\(name)” cannot go inside itself.")
				continue
			}
			guard exists(source) else {
				refusals.append("“\(name)” is no longer there.")
				continue
			}

			let target = folder.appendingPathComponent(name)
			// Already where it is being put. A move has nothing to do; a copy is
			// somebody asking for a second one, which is the only thing it could
			// be, so it gets the next free name rather than an apology.
			if target.path == source.path {
				if operation == .move {
					unchanged.append(source)
					continue
				}
				let duplicate = Self.duplicateName(for: source, in: folder) {
					exists($0) || claimed.contains($0.path)
				}
				claimed.insert(duplicate.path)
				transfers.append(Transfer(source: source, destination: duplicate))
				continue
			}
			guard !exists(target), !claimed.contains(target.path) else {
				collisions.append(source)
				continue
			}
			claimed.insert(target.path)
			transfers.append(Transfer(source: source, destination: target))
		}

		return Plan(
			transfers: transfers, collisions: collisions,
			refusals: refusals, unchanged: unchanged
		)
	}
}

public extension FileTransfer.Plan {
	/// The one message the whole drop gets, or nil when there is nothing to say.
	///
	/// One message however many files were dropped: the point of skipping rather
	/// than prompting is that the gesture stays a gesture, and it would be
	/// undone by three dialogs arriving afterwards instead of during.
	///
	/// - Parameters:
	///   - done: how many actually arrived, which is not `transfers.count` when
	///     the file system refused one of them.
	///   - failures: whole sentences for the ones it refused.
	func summary(
		operation: FileTransfer.Operation, done: Int, failures: [String] = []
	) -> (title: String, detail: String)? {
		guard !collisions.isEmpty || !refusals.isEmpty || !failures.isEmpty else { return nil }

		var sentences = refusals + failures
		if !collisions.isEmpty {
			let names = collisions.map { "“\($0.lastPathComponent)”" }
			sentences.append(
				FileTransfer.list(names)
					+ (collisions.count == 1 ? " already exists here." : " already exist here.")
			)
		}
		if done == 1 {
			sentences.append("The other one was \(operation.past).")
		} else if done > 1 {
			sentences.append("The other \(done) were \(operation.past).")
		}

		return (
			title: done == 0
				? "Nothing was \(operation.past)"
				: "Not everything was \(operation.past)",
			detail: sentences.joined(separator: " ")
		)
	}
}

extension FileTransfer {
	/// `main.py` → `main-1.py`, then `main-2.py`, then the first one free.
	///
	/// The extension is kept because it is what the file *is*: `main-1.py` is
	/// still Python and `main.py-1` is nothing. Foundation's `pathExtension` takes
	/// the last one only, so `archive.tar.gz` duplicates as `archive.tar-1.gz` —
	/// the same simplification every other extension-aware thing in this app
	/// makes, and the file still opens. A name that is all extension and no stem,
	/// `.gitignore`, has no extension by that reckoning and becomes
	/// `.gitignore-1`, which is right.
	static func duplicateName(
		for source: URL, in folder: URL, isTaken: (URL) -> Bool
	) -> URL {
		let name = source.lastPathComponent
		let ext = source.pathExtension
		let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
		return freeName(stem: stem, extension: ext, in: folder, isTaken: isTaken)
	}

	/// `picture-1.png`, then `picture-2.png`, then the first one free: a name
	/// for a file that arrives without one, which is what a picture pasted from
	/// the clipboard is.
	///
	/// The first number free rather than the next count, the rule the duplicate
	/// above follows: a gap left by a deletion is a name that is free, and a
	/// folder holding `picture-1` and `picture-3` gets `picture-2`.
	public static func freeName(
		stem: String, extension ext: String, in folder: URL, isTaken: (URL) -> Bool
	) -> URL {
		var number = 1
		while true {
			let candidate = folder.appendingPathComponent(
				ext.isEmpty ? "\(stem)-\(number)" : "\(stem)-\(number).\(ext)"
			)
			if !isTaken(candidate) { return candidate }
			number += 1
		}
	}

	/// "a", "a and b", "a, b and c", and past four "a, b, c, d and 8 more" —
	/// because a toast naming twelve files is a toast nobody finishes reading.
	static func list(_ names: [String]) -> String {
		guard names.count > 1 else { return names.first ?? "" }
		guard names.count <= 4 else {
			return names.prefix(4).joined(separator: ", ") + " and \(names.count - 4) more"
		}
		return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
	}
}
