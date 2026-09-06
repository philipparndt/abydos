import Foundation

/// A file looked at as bytes, with its edits kept as pieces over the mapping.
///
/// **Pieces, not a copy.** The one thing the old read-only view got right was
/// never copying the file: it was mapped and only the visible rows were
/// touched, which is why a 114 MB STL opened at once. An editor that read the
/// file into a `Data` on the first keystroke would give that up for a
/// gigabyte-sized allocation. So the original stays mapped, bytes that are
/// typed or pasted go into one append-only buffer, and the document is a list
/// of runs — *these bytes from the original, then these from the buffer* —
/// that is exactly as large as its edits. Overwrite, insert and delete are all
/// splits of that list; undo is the list before the edit.
///
/// **Readers take a snapshot.** The statistics pass, a search and a checksum
/// all read while the person types. A `Snapshot` is a value — the piece list
/// and the two sources — so a background reader sees one consistent document
/// and an edit on the main thread never moves the bytes under it.
public final class ByteDocument {
	/// Where a run's bytes come from.
	enum Source: Sendable { case original, added }

	/// One run of the document: `length` bytes from `start` in `source`.
	struct Piece: Sendable, Equatable {
		var source: Source
		var start: Int
		var length: Int
		var end: Int { start + length }
	}

	/// The document as it was at one moment, readable from any thread.
	public struct Snapshot: Sendable {
		let original: Data
		let added: Data
		let pieces: [Piece]
		/// Where each piece begins in the document, for the binary search.
		let starts: [Int]
		public let count: Int

		init(original: Data, added: Data, pieces: [Piece]) {
			self.original = original
			self.added = added
			self.pieces = pieces
			var starts: [Int] = []
			starts.reserveCapacity(pieces.count)
			var total = 0
			for piece in pieces {
				starts.append(total)
				total += piece.length
			}
			self.starts = starts
			count = total
		}

		/// Which piece holds `offset`, or nil past the end.
		func pieceIndex(at offset: Int) -> Int? {
			guard offset >= 0, offset < count, !pieces.isEmpty else { return nil }
			var low = 0, high = pieces.count - 1
			while low < high {
				let mid = (low + high + 1) / 2
				if starts[mid] <= offset { low = mid } else { high = mid - 1 }
			}
			return low
		}

		func storage(of source: Source) -> Data {
			source == .original ? original : added
		}

		public func byte(at offset: Int) -> UInt8 {
			guard let index = pieceIndex(at: offset) else { return 0 }
			let piece = pieces[index]
			let data = storage(of: piece.source)
			return data[data.startIndex + piece.start + (offset - starts[index])]
		}

		/// The longest contiguous run starting at `offset`, without a copy: a
		/// slice of whichever source holds it. Empty past the end.
		///
		/// This is what every whole-file reader loops over, so a gigabyte's
		/// checksum touches the mapping page by page and allocates nothing.
		public func run(at offset: Int) -> Data {
			guard let index = pieceIndex(at: offset) else { return Data() }
			let piece = pieces[index]
			let data = storage(of: piece.source)
			let from = data.startIndex + piece.start + (offset - starts[index])
			return data[from..<(data.startIndex + piece.end)]
		}

		/// Contiguous runs covering `range`, in order, each with its offset.
		/// The body returns false to stop.
		public func forEachRun(
			in range: Range<Int>, _ body: (Int, Data) throws -> Bool
		) rethrows {
			var offset = max(0, range.lowerBound)
			let end = min(count, range.upperBound)
			while offset < end {
				var run = run(at: offset)
				if run.isEmpty { return }
				if offset + run.count > end { run = run.prefix(end - offset) }
				guard try body(offset, run) else { return }
				offset += run.count
			}
		}

		/// `range` gathered into one `Data`. A copy, so it is for the small
		/// reads — a row, the inspector's eight bytes — not for the whole file.
		public func bytes(in range: Range<Int>) -> Data {
			let clamped = max(0, range.lowerBound)..<min(count, max(0, range.upperBound))
			guard !clamped.isEmpty else { return Data() }
			var out = Data(capacity: clamped.count)
			forEachRun(in: clamped) { _, run in
				out.append(run)
				return true
			}
			return out
		}

		/// The document ranges whose bytes came from typing or pasting, merged
		/// where they touch. What the view marks, until a save makes them the
		/// original.
		public var editedRanges: [Range<Int>] {
			var ranges: [Range<Int>] = []
			for (index, piece) in pieces.enumerated() where piece.source == .added {
				let range = starts[index]..<(starts[index] + piece.length)
				if let last = ranges.last, last.upperBound == range.lowerBound {
					ranges[ranges.count - 1] = last.lowerBound..<range.upperBound
				} else {
					ranges.append(range)
				}
			}
			return ranges
		}
	}

	/// The file this is, or nil for bytes that came from nowhere.
	public private(set) var url: URL?

	private var original: Data
	private var added = Data()
	private var pieces: [Piece]
	private var cached: Snapshot?

	/// Counts edits. Dirty is a generation the disk has not seen.
	private var generation = 0
	private var savedGeneration = 0

	/// The window's, when there is one, so ⌘Z reaches these edits.
	public weak var undoManager: UndoManager?

	/// Told after every edit and after a save, with what happened, so the view
	/// redraws the rows it must and the statistics pass invalidates the blocks
	/// it must. The range is in document offsets after the edit; `delta` is
	/// how much the document grew or shrank at it.
	public var onChange: ((_ range: Range<Int>, _ delta: Int) -> Void)?

	/// Maps the file. Nothing is read until a row is drawn.
	public init(url: URL) throws {
		self.url = url
		original = try Data(contentsOf: url, options: .mappedIfSafe)
		pieces = original.isEmpty ? [] : [Piece(source: .original, start: 0, length: original.count)]
	}

	/// Bytes with no file behind them, for a test and for a scratch.
	public init(bytes: Data) {
		original = bytes
		pieces = bytes.isEmpty ? [] : [Piece(source: .original, start: 0, length: bytes.count)]
	}

	// MARK: - Reading

	public func snapshot() -> Snapshot {
		if let cached { return cached }
		let made = Snapshot(original: original, added: added, pieces: pieces)
		cached = made
		return made
	}

	public var count: Int { snapshot().count }
	public func byte(at offset: Int) -> UInt8 { snapshot().byte(at: offset) }
	public func bytes(in range: Range<Int>) -> Data { snapshot().bytes(in: range) }
	public func run(at offset: Int) -> Data { snapshot().run(at: offset) }
	public var editedRanges: [Range<Int>] { snapshot().editedRanges }

	public var isDirty: Bool { generation != savedGeneration }

	/// How many runs the document is in. A test's way of saying an edit cost
	/// a piece and not a copy.
	var pieceCountForTesting: Int { pieces.count }

	// MARK: - Editing

	/// The one primitive: `range` becomes `data`. Overwrite is a range and
	/// data of the same length; insert is an empty range; delete is empty
	/// data. Anything past the end is appended rather than refused, because
	/// typing at the last byte of a file is how a byte is added to it.
	public func replace(_ range: Range<Int>, with data: Data) {
		let before = pieces
		let total = snapshot().count
		let lower = max(0, min(range.lowerBound, total))
		let upper = max(lower, min(range.upperBound, total))

		var next: [Piece] = []
		next.reserveCapacity(pieces.count + 2)
		var position = 0
		for piece in pieces {
			let pieceRange = position..<(position + piece.length)
			position += piece.length
			// Entirely before or after the hole: kept whole.
			if pieceRange.upperBound <= lower || pieceRange.lowerBound >= upper {
				next.append(piece)
				continue
			}
			// The part before the hole.
			if pieceRange.lowerBound < lower {
				next.append(Piece(source: piece.source, start: piece.start, length: lower - pieceRange.lowerBound))
			}
			// The part after it.
			if pieceRange.upperBound > upper {
				let skipped = upper - pieceRange.lowerBound
				next.append(Piece(source: piece.source, start: piece.start + skipped, length: piece.length - skipped))
			}
		}

		if !data.isEmpty {
			let start = added.count
			added.append(data)
			let inserted = Piece(source: .added, start: start, length: data.count)
			// In front of the first piece that begins at or after the hole.
			var at = 0
			var seen = 0
			while at < next.count, seen < lower {
				seen += next[at].length
				at += 1
			}
			next.insert(inserted, at: at)
		}

		pieces = Self.coalesced(next)
		cached = nil
		generation += 1

		undoManager?.registerUndo(withTarget: self) { document in
			document.restore(before, undoing: true)
		}
		undoManager?.setActionName("Edit Bytes")
		onChange?(lower..<(lower + data.count), data.count - (upper - lower))
	}

	public func overwrite(_ data: Data, at offset: Int) {
		replace(offset..<(offset + data.count), with: data)
	}

	public func insert(_ data: Data, at offset: Int) {
		replace(offset..<offset, with: data)
	}

	public func delete(_ range: Range<Int>) {
		replace(range, with: Data())
	}

	/// Undo and redo are the piece list from before, and registering the
	/// other direction is what makes ⇧⌘Z work.
	private func restore(_ list: [Piece], undoing: Bool) {
		let current = pieces
		pieces = list
		cached = nil
		generation += 1
		undoManager?.registerUndo(withTarget: self) { document in
			document.restore(current, undoing: !undoing)
		}
		onChange?(0..<snapshot().count, 0)
	}

	/// Neighbouring runs of the same source with touching bytes become one.
	/// Typing a byte is two nibbles, and a byte typed after the last is a run
	/// that touches it in both the document and the buffer; without this a
	/// hundred typed bytes would be two hundred pieces.
	static func coalesced(_ list: [Piece]) -> [Piece] {
		var out: [Piece] = []
		out.reserveCapacity(list.count)
		for piece in list where piece.length > 0 {
			if let last = out.last, last.source == piece.source, last.end == piece.start {
				out[out.count - 1].length += piece.length
			} else {
				out.append(piece)
			}
		}
		return out
	}

	// MARK: - Saving

	/// A byte document is never saved on its own.
	///
	/// `TextDocument` has the same method and answers from the setting. This
	/// one answers no by construction: the auto-save fires between two nibbles
	/// as readily as after them, and half a typed byte written into a Mach-O is
	/// a corrupted binary rather than a draft.
	public func autoSaveIfNeeded() -> Bool { false }

	/// Writes the document over its file, through a temporary and a rename.
	///
	/// Through a temporary because the original is mapped by this very
	/// process: writing over a mapping you are reading from produces a file
	/// that is half the old bytes and half the new, and then reads them back.
	/// The rename is atomic and the old inode stays alive for anybody who has
	/// it open, which is what every editor's atomic save does.
	///
	/// Undo does not cross a save: afterwards the pieces point into a new
	/// mapping, and a piece list from before it would name bytes of a buffer
	/// that has been folded into the file.
	public func save() throws {
		guard let url else { throw SaveFailure.noFile }
		try write(to: url)
		original = try Data(contentsOf: url, options: .mappedIfSafe)
		added = Data()
		pieces = original.isEmpty ? [] : [Piece(source: .original, start: 0, length: original.count)]
		cached = nil
		savedGeneration = generation
		undoManager?.removeAllActions(withTarget: self)
		onChange?(0..<original.count, 0)
	}

	/// Streams the pieces to `destination`, which may be this document's own
	/// file. Nothing is gathered: a gigabyte goes through in runs the size of
	/// the pieces, the largest of which is the mapping itself.
	public func write(to destination: URL) throws {
		let snapshot = snapshot()
		let directory = destination.deletingLastPathComponent()
		let temporary = directory.appendingPathComponent(
			".\(destination.lastPathComponent).abydos-\(UUID().uuidString.prefix(8))"
		)
		FileManager.default.createFile(atPath: temporary.path, contents: nil)
		let handle = try FileHandle(forWritingTo: temporary)
		do {
			try snapshot.forEachRun(in: 0..<snapshot.count) { _, run in
				try handle.write(contentsOf: run)
				return true
			}
			try handle.close()
		} catch {
			try? handle.close()
			try? FileManager.default.removeItem(at: temporary)
			throw error
		}
		if FileManager.default.fileExists(atPath: destination.path) {
			_ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
		} else {
			try FileManager.default.moveItem(at: temporary, to: destination)
		}
	}

	public enum SaveFailure: Error, Sendable {
		/// Bytes that came from nowhere have nowhere to go.
		case noFile
	}
}
