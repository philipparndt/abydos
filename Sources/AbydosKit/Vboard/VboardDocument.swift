import Foundation

/// A `.vboard` file open as a board on a server: which board, its key, and
/// whether the board has changed since the file last agreed with it.
///
/// Not a `TextDocument`. The file is one line of JSON with every picture on the
/// board in it as base64, hundreds of megabytes for a recorded workshop, and
/// nothing in this app edits it as text: the board is edited in vboard's own
/// page, by whoever is on it, and the file is what a save brings back. So this
/// is `ByteDocument`'s shape instead — a dirty state, a save through a
/// temporary and a rename, and never an auto-save.
///
/// Dirty is a count, not a flag. Every change message the page's socket
/// delivers counts one, whoever made the change; a save remembers the count it
/// started at and is only allowed to clear the dot to that. With colleagues on
/// the board a save takes a moment and the board keeps moving, and a flag
/// cleared at the end would claim a change the file does not have.
public final class VboardDocument {
	public let url: URL
	public let client: VboardClient
	/// The board this file is on. A new one when the file has to be opened
	/// again.
	public private(set) var boardID: String
	/// The board's link key when it is encrypted; nil for a session board the
	/// AI can work on, which is what a tab opens. An encrypted board shuts the
	/// AI out — vboard will not let it read one — and that was the worse half
	/// of the trade ("local boards are handled like normal encrypted boards
	/// with no AI access", 2026-10-23).
	public private(set) var key: VboardKey?

	/// How long a lease runs, and who it says holds the session. Renewed by the
	/// tab well before it runs out (`renewLease`).
	public static let leaseSeconds = 900
	public static let leaseHost = "Abydos"

	private var changes = 0
	private var savedChanges = 0
	public var isDirty: Bool { changes != savedChanges }
	public var onDirtyChanged: (() -> Void)?

	public init(url: URL, client: VboardClient, encrypted: Bool = false) {
		self.url = url
		self.client = client
		boardID = VboardBoardID.make()
		key = encrypted ? VboardKey.make() : nil
	}

	/// The board's link, for colleagues and for the web view.
	public var link: URL { VboardLink.board(server: client.server, id: boardID, key: key) }

	// MARK: Changes

	/// Something on the board changed: items, a widget's entries, its name.
	public func noteChange() {
		let wasDirty = isDirty
		changes += 1
		if !wasDirty { onDirtyChanged?() }
	}

	/// The same answer as a byte document: no, by construction. A save is a
	/// round trip to a server that may be slow or gone, and auto-save fires on
	/// losing focus.
	public func autoSaveIfNeeded() -> Bool { false }

	/// Throws the board's changes away as far as this document is concerned:
	/// the file is about to be put back on the board, or the tab is closing
	/// after somebody chose Discard.
	public func forgetChanges() {
		let wasDirty = isDirty
		savedChanges = changes
		if wasDirty { onDirtyChanged?() }
	}

	// MARK: Putting the file on a board

	public enum Opened: Equatable {
		/// On the board, under `boardID`, with `key`.
		case onBoard
		/// The file is not something the server should be given.
		case refusedFile(VboardFile)
		/// The server said why not.
		case failed(VboardClient.Outcome)
	}

	/// Puts the file on a new private temporary board.
	///
	/// An empty file is created rather than imported: there is nothing to
	/// import, and it is how somebody starts a board. A board id that turns out
	/// to be taken is tried once more with another; eight random bytes colliding
	/// twice is not something to retry forever.
	public func open(progress: ((Double) -> Void)? = nil) async -> Opened {
		let kind = VboardFile.inspect(url)
		switch kind {
		case .board, .empty:
			for attempt in 0..<2 {
				if attempt > 0 { boardID = VboardBoardID.make() }
				let outcome = kind == .empty
					? await client.create(id: boardID, name: url.deletingPathExtension().lastPathComponent, key: key)
					: await client.importBoard(file: url, id: boardID, key: key, progress: progress)
				switch outcome {
				case .created:
					recordDiskState()
					await settle()
					return .onBoard
				case .refused:
					continue
				default:
					return .failed(outcome)
				}
			}
			return .failed(.refused)
		case .encrypted, .notABoard, .tooLarge:
			return .refusedFile(kind)
		}
	}

	public enum Reloaded: Equatable {
		/// The same board now shows the file. Everybody's pages reload.
		case replaced
		/// The file is on a new board with a new key. The old link opens nothing.
		case reopened
		case failed(Opened)
	}

	/// Puts the file, changed by somebody else, back on the board.
	///
	/// In place when vboard allows it: same id, same key, and the link people
	/// have still works. It allows it only when the file's content marker is
	/// newer than the board's, which a `git checkout` of an older version or a
	/// hand-edited file will not be — so then the board is ended and the file
	/// opened again, and the tab has to say the link changed.
	public func reload() async -> Reloaded {
		if VboardFile.inspect(url) == .board,
		   await client.replace(file: url, id: boardID, key: key) == .replaced {
			recordDiskState()
			forgetChanges()
			return .replaced
		}
		_ = await client.delete(id: boardID, key: key)
		boardID = VboardBoardID.make()
		if key != nil { key = VboardKey.make() }
		let opened = await open()
		guard opened == .onBoard else { return .failed(opened) }
		forgetChanges()
		return .reopened
	}

	/// Makes a new board a session board and lets colleagues with the link in.
	///
	/// Both are asked for and neither is required: a server from before session
	/// boards answers 404 to the lease and the board is then an ordinary
	/// temporary one, and a server without a login has nobody to let in.
	private func settle() async {
		_ = await client.lease(id: boardID, seconds: Self.leaseSeconds, host: Self.leaseHost)
		_ = await client.shareByLink(id: boardID)
	}

	/// Renews the lease, for as long as the tab is open.
	@discardableResult
	public func renewLease() async -> VboardClient.Outcome {
		await client.lease(id: boardID, seconds: Self.leaseSeconds, host: Self.leaseHost)
	}

	/// Ends the board for everybody on it.
	@discardableResult
	public func end() async -> VboardClient.Outcome {
		await client.delete(id: boardID, key: key)
	}

	// MARK: Saving

	public enum SaveFailure: Error, Equatable {
		case server(VboardClient.Outcome)
		case disk(String)
	}

	/// Writes the board into the file: the server's export, through a
	/// temporary beside the file and a rename over it.
	///
	/// Beside the file so the rename never crosses a volume and is atomic, and
	/// so a save that dies halfway leaves the old file whole. The bytes are the
	/// server's own; this app does not own the format and does not rearrange it.
	public func save() async throws {
		let startedAt = changes
		let export: VboardClient.Export
		switch await client.export(id: boardID, key: key, into: url.deletingLastPathComponent()) {
		case .success(let made): export = made
		case .failure(let failure): throw SaveFailure.server(failure.outcome)
		}
		do {
			if FileManager.default.fileExists(atPath: url.path) {
				_ = try FileManager.default.replaceItemAt(url, withItemAt: export.file)
			} else {
				try FileManager.default.moveItem(at: export.file, to: url)
			}
		} catch {
			try? FileManager.default.removeItem(at: export.file)
			throw SaveFailure.disk(error.localizedDescription)
		}
		recordDiskState()
		let wasDirty = isDirty
		savedChanges = startedAt
		if wasDirty != isDirty { onDirtyChanged?() }
	}

	// MARK: The file on disk

	/// What the file looked like when this document last agreed with it. Size
	/// as well as date, as `TextDocument` does: two writes in one second are
	/// otherwise the same write.
	private var diskModified: Date?
	private var diskSize: Int?

	private func recordDiskState() {
		let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
		diskModified = attributes?[.modificationDate] as? Date
		diskSize = attributes?[.size] as? Int
	}

	/// Whether somebody other than this document has written the file.
	public var hasChangedOnDisk: Bool {
		guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
			// Deleted or unreadable: not a change to put on the board, and
			// treating it as one would end the board for a missing file.
			return false
		}
		return attributes[.modificationDate] as? Date != diskModified || attributes[.size] as? Int != diskSize
	}
}
