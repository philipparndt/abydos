import Foundation
import SwiftTreeSitter

/// One open file: text storage, undo history, syntax tree, and fold regions.
///
/// Threading is the whole design here. The rope lives on the main thread and is
/// authoritative for *text*, so a keystroke costs microseconds and the glyphs on
/// screen are never wrong. The parser lives behind a serial queue and is
/// authoritative for *colour*, which is allowed to arrive a frame or two late.
///
/// That split exists because tree-sitter's reparse, while genuinely incremental
/// in what it re-reads, still rebuilds the root node's child list — O(siblings),
/// which for a multi-megabyte file measures in tens of milliseconds. Doing that
/// inline would drop frames on every keypress. Doing it behind a queue costs
/// nothing visible: text is already correct, and highlights repaint on arrival.
public final class TextDocument {
	public let url: URL
	public private(set) var rope: Rope
	public private(set) var languageId: String?
	public private(set) var isDirty = false

	/// Fold regions for the whole document. Recomputed after each parse settles.
	public private(set) var folds: [FoldRange] = []

	/// Fired when new highlights or folds are available and the view should redraw.
	public var onSyntaxUpdated: (() -> Void)?
	/// The text changed, whether or not anything can parse it.
	public var onTextChanged: (() -> Void)?

	/// Fired after an automatic save, so the tab can drop its dirty marker.
	public var onAutoSaved: (() -> Void)?

	/// Injected rather than reaching for the singleton, so auto-save behaviour
	/// can be tested against isolated preferences.
	public var settings: Settings = .shared

	private var autoSaveWork: DispatchWorkItem?

	// MARK: Syntax state

	/// Owned by `engineQueue`; never touched from the main thread.
	private var engine: SyntaxEngine?
	private let engineQueue = DispatchQueue(label: "abydos.syntax", qos: .userInteractive)

	/// Bumped on every edit. A background result carrying an older generation
	/// describes text that no longer exists and is dropped.
	private var generation = 0

	/// Most recent highlights, with the byte range and generation they describe.
	private var cachedTokens: [HighlightToken] = []
	private var cachedByteRange: Range<Int> = 0..<0
	private var cachedGeneration = -1

	private var highlightRequestInFlight = false
	private var desiredByteRange: Range<Int>?

	/// Extra lines fetched around the viewport so ordinary scrolling hits cache
	/// instead of round-tripping to the parser.
	private static let highlightMarginLines = 150

	private var pendingFoldWork: DispatchWorkItem?

	// MARK: Undo

	/// Every state this document has been in.
	///
	/// A tree rather than two stacks: typing after an undo used to throw away
	/// what had been undone, which is the one place editing destroys work
	/// without saying so.
	public private(set) var history = UndoTree()
	private var lastEditTime: Date = .distantPast
	private var lastEditEnd: Int = -1

	// MARK: - Loading

	public init(url: URL) throws {
		self.url = url
		// Raw bytes rather than String: the rope stores UTF-8 directly, so a file
		// with invalid sequences still round-trips byte-for-byte on save.
		let data = try Data(contentsOf: url, options: .mappedIfSafe)
		self.rope = Rope(data: data)
		self.languageId = LanguageRegistry.shared.languageId(for: url)
		self.engine = languageId.flatMap { SyntaxEngine(languageId: $0) }

		startInitialParse()
		recordDiskState()
	}

	public var displayLanguageName: String? {
		languageId.map { LanguageRegistry.shared.displayName(for: $0) }
	}

	/// The file's declarations, for the structure view.
	///
	/// Asynchronous because the tree belongs to the parser's queue, and running
	/// the query over a whole large file is not something to do on the main
	/// thread. The result is delivered there.
	public func symbols(completion: @escaping ([DocumentSymbol]) -> Void) {
		guard let engine else {
			completion([])
			return
		}

		let snapshot = rope
		let currentGeneration = generation
		engineQueue.async { [weak self] in
			let symbols = engine.symbols(rope: snapshot)
			DispatchQueue.main.async {
				// A newer edit has landed; its own request will follow.
				guard let self, self.generation == currentGeneration else { return }
				completion(symbols)
			}
		}
	}

	/// Overrides the detected language, re-parsing from scratch.
	///
	/// Detection is a guess, and the file that defeats it is exactly the one
	/// worth reading with colour, so the guess has to be correctable. Passing
	/// nil turns highlighting off.
	public func setLanguage(_ newLanguageId: String?) {
		guard newLanguageId != languageId else { return }
		languageId = newLanguageId

		// The old tree describes a different grammar, so nothing carries over:
		// the generation bump abandons any parse still in flight.
		generation &+= 1
		folds = []
		engine = newLanguageId.flatMap { SyntaxEngine(languageId: $0) }

		startInitialParse()
		onSyntaxUpdated?()
	}

	private func startInitialParse() {
		guard let engine else { return }
		let snapshot = rope
		let currentGeneration = generation

		// Even the first parse is off-thread: opening a large file should show
		// text immediately and colour in a moment later, never block.
		engineQueue.async { [weak self] in
			engine.parse(rope: snapshot)
			let computed = engine.foldRanges(rope: snapshot)
			DispatchQueue.main.async {
				guard let self, self.generation == currentGeneration else { return }
				self.folds = computed
				self.onSyntaxUpdated?()
			}
		}
	}

	// MARK: - Reading

	public var lineCount: Int { rope.lineCount }

	/// Whether there is nothing in this document at all.
	public var isEmptyText: Bool { rope.byteCount == 0 }

	public func lineText(_ line: Int) -> String { rope.lineText(line) }

	/// Highlights for a line range.
	///
	/// Returns immediately, always. If the cache is current it is exact; if the
	/// viewport moved or the text changed, the previous tokens are returned while
	/// a refresh runs, and `onSyntaxUpdated` fires when the new ones land. The
	/// view therefore never blocks on the parser.
	public func highlights(forLineRange lines: Range<Int>) -> [HighlightToken] {
		guard engine != nil else { return [] }

		let paddedLower = max(0, lines.lowerBound - Self.highlightMarginLines)
		let paddedUpper = min(rope.lineCount, lines.upperBound + Self.highlightMarginLines)
		let startByte = rope.byteOffset(ofLine: paddedLower)
		let endByte = paddedUpper >= rope.lineCount
			? rope.byteCount
			: rope.byteOffset(ofLine: paddedUpper)

		let isFresh = cachedGeneration == generation
			&& cachedByteRange.lowerBound <= startByte
			&& cachedByteRange.upperBound >= endByte

		if !isFresh {
			requestHighlights(byteRange: startByte..<endByte)
		}
		return cachedTokens
	}

	private func requestHighlights(byteRange: Range<Int>) {
		desiredByteRange = byteRange
		guard !highlightRequestInFlight, let engine else { return }

		highlightRequestInFlight = true
		let snapshot = rope
		let requestedGeneration = generation
		let requested = byteRange

		engineQueue.async { [weak self] in
			let tokens = engine.highlights(rope: snapshot, byteRange: requested)
			DispatchQueue.main.async {
				guard let self else { return }
				self.highlightRequestInFlight = false

				// Only publish if the text has not moved on since the request.
				if self.generation == requestedGeneration {
					self.cachedTokens = tokens
					self.cachedByteRange = requested
					self.cachedGeneration = requestedGeneration
					self.onSyntaxUpdated?()
				}

				// The viewport or text may have changed while this was running.
				if let desired = self.desiredByteRange,
				   self.cachedGeneration != self.generation
					|| desired.lowerBound < self.cachedByteRange.lowerBound
					|| desired.upperBound > self.cachedByteRange.upperBound {
					self.requestHighlights(byteRange: desired)
				}
			}
		}
	}

	// MARK: - Editing

	/// Replaces a UTF-16 range with `text`, the unit the view works in.
	@discardableResult
	public func replace(utf16Range: Range<Int>, with text: String, caretBefore: Int) -> Int {
		let startByte = rope.byteOffset(fromUTF16: utf16Range.lowerBound)
		let endByte = rope.byteOffset(fromUTF16: utf16Range.upperBound)
		let replaced = rope.bytes(in: startByte..<endByte)
		let inserted = Array(text.utf8)

		applyEdit(byteRange: startByte..<endByte, newBytes: inserted)

		// Undo entries coalesce while the user types a run of characters, so one
		// ⌘Z removes a word rather than a single keystroke.
		let now = Date()
		let isContiguousTyping = replaced.isEmpty
			&& inserted.count <= 2
			&& startByte == lastEditEnd
			&& now.timeIntervalSince(lastEditTime) < 0.6

		if isContiguousTyping, let existing = history.currentNode.edit {
			// Summarised from the whole run rather than from the character that
			// started it: a state described as “Typed ⏎” because the run began
			// with a newline says nothing about the line that followed it.
			history.extendCurrent(
				inserted: inserted,
				summary: Self.summary(
					removed: existing.removed,
					inserted: existing.inserted + inserted,
					extending: nil
				),
				time: now
			)
		} else {
			history.record(
				UndoTree.Edit(
					byteRange: startByte..<endByte,
					removed: replaced,
					inserted: inserted,
					caretBefore: rope.byteOffset(fromUTF16: caretBefore)
				),
				summary: Self.summary(removed: replaced, inserted: inserted, extending: nil),
				time: now
			)
		}
		lastEditTime = now
		lastEditEnd = startByte + inserted.count

		isDirty = true
		scheduleAutoSave()

		return rope.utf16Offset(fromByte: startByte + inserted.count)
	}

	// MARK: - Auto save

	/// Writes the file after a pause in typing.
	///
	/// Debounced rather than written per keystroke: a save is a full serialise
	/// plus an atomic file replace, which has no business running inside the edit
	/// path of a multi-megabyte file.
	/// A document whose text must not reach the disk by itself: a decrypted
	/// SOPS buffer. Its only saves are the ones somebody asks for, and those go
	/// through `sops` rather than through `save()`.
	public var declinesAutoSave = false

	private func scheduleAutoSave() {
		autoSaveWork?.cancel()
		guard settings.autoSaveEnabled, !declinesAutoSave else { return }

		let work = DispatchWorkItem { [weak self] in
			self?.autoSave()
		}
		autoSaveWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + settings.autoSaveDelay, execute: work)
	}

	private func autoSave() {
		guard isDirty, settings.autoSaveEnabled, !declinesAutoSave else { return }
		// A failed automatic save must stay silent — the user did not ask for
		// this write, so interrupting them with an alert would be wrong. The tab
		// simply stays dirty and an explicit ⌘S will surface the error.
		guard (try? save()) != nil else { return }
		onAutoSaved?()
	}

	/// Writes immediately if there are unsaved changes and auto save is on.
	/// Used when the app loses focus or a tab is closed.
	@discardableResult
	public func autoSaveIfNeeded() -> Bool {
		guard settings.autoSaveEnabled, isDirty, !declinesAutoSave else { return false }
		autoSaveWork?.cancel()
		guard (try? save()) != nil else { return false }
		onAutoSaved?()
		return true
	}

	/// Applies an edit to the rope, then hands the reparse to the syntax queue.
	/// An edit happened: where it started, how many lines it took out, and how
	/// many it put in.
	///
	/// For anything anchored to a place in the file rather than to a line
	/// number — a breakpoint above all. Rows are 0-based, as the parser counts
	/// them.
	public var onLinesChanged: ((_ firstLine: Int, _ removed: Int, _ inserted: Int) -> Void)?

	/// The same edit in the unit the view edits in: which UTF-16 range went,
	/// and how much text came in its place.
	///
	/// `onLinesChanged` is this for whole lines, which suits a breakpoint. A
	/// snippet's tab stops are spans within a line, and lines cannot tell them
	/// where they went. Said for undo and redo as well, which are edits like
	/// any other to anything holding a place in the text.
	///
	/// The offsets cost three lookups into the rope, so they are worked out
	/// only when somebody is listening.
	public var onTextReplaced: ((_ utf16Range: Range<Int>, _ insertedUTF16Count: Int) -> Void)?

	private func applyEdit(byteRange: Range<Int>, newBytes: [UInt8]) {
		// Positions must be captured against the *old* text — tree-sitter needs
		// both the old and new end to map the tree forward.
		let startPoint = point(forByte: byteRange.lowerBound)
		let oldEndPoint = point(forByte: byteRange.upperBound)
		let replacedUTF16: Range<Int>? = onTextReplaced.map { _ in
			let lower = rope.utf16Offset(fromByte: byteRange.lowerBound)
			return lower..<rope.utf16Offset(fromByte: byteRange.upperBound)
		}

		rope.replace(byteRange: byteRange, with: newBytes)
		generation += 1

		let newEndByte = byteRange.lowerBound + newBytes.count
		let newEndPoint = point(forByte: newEndByte)

		if let replacedUTF16 {
			onTextReplaced?(
				replacedUTF16,
				rope.utf16Offset(fromByte: newEndByte) - replacedUTF16.lowerBound
			)
		}

		// The same three numbers tree-sitter is about to be given, in lines.
		if startPoint.row != oldEndPoint.row || startPoint.row != newEndPoint.row {
			onLinesChanged?(
				Int(startPoint.row),
				Int(oldEndPoint.row) - Int(startPoint.row),
				Int(newEndPoint.row) - Int(startPoint.row)
			)
		}

		let edit = InputEdit(
			startByte: byteRange.lowerBound,
			oldEndByte: byteRange.upperBound,
			newEndByte: newEndByte,
			startPoint: startPoint,
			oldEndPoint: oldEndPoint,
			newEndPoint: newEndPoint
		)

		// Said for every edit, grammar or no grammar. `onSyntaxUpdated` cannot
		// carry this: it is fired by the parser finishing, and a language with
		// no grammar of its own — PlantUML, whose preview is the point of
		// editing it — has no parser to finish.
		onTextChanged?()

		guard let engine else { return }
		let snapshot = rope
		// Serial queue, so edits reparse in the order they were made and each
		// sees the rope exactly as it looked after that edit.
		engineQueue.async {
			engine.applyEdit(edit, newRope: snapshot)
		}
		scheduleFoldRecompute()
	}

	/// tree-sitter points are (row, byte column within the row).
	private func point(forByte offset: Int) -> Point {
		let line = rope.line(atByteOffset: offset)
		let lineStart = rope.byteOffset(ofLine: line)
		return Point(row: line, column: offset - lineStart)
	}

	/// Folds are recomputed after typing settles rather than on every keystroke:
	/// the whole file is scanned for them, and nobody folds mid-word.
	private func scheduleFoldRecompute() {
		pendingFoldWork?.cancel()
		let work = DispatchWorkItem { [weak self] in
			self?.recomputeFolds()
		}
		pendingFoldWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
	}

	private func recomputeFolds() {
		guard let engine else { return }
		let snapshot = rope
		let currentGeneration = generation

		engineQueue.async { [weak self] in
			let computed = engine.foldRanges(rope: snapshot)
			DispatchQueue.main.async {
				guard let self, self.generation == currentGeneration else { return }
				self.folds = computed
				self.onSyntaxUpdated?()
			}
		}
	}

	// MARK: - Undo

	public var canUndo: Bool { history.canUndo }
	public var canRedo: Bool { history.canRedo }

	/// Returns the caret position to restore, or nil if there was nothing to undo.
	@discardableResult
	public func undo() -> Int? {
		guard let target = history.undoTarget else { return nil }
		return travel(to: target)
	}

	@discardableResult
	public func redo() -> Int? {
		guard let target = history.redoTarget else { return nil }
		return travel(to: target)
	}

	/// Goes to any state the document has been in.
	///
	/// The same machinery undo and redo use: they are only this with the target
	/// worked out for you.
	@discardableResult
	public func travel(to state: Int) -> Int? {
		let route = history.route(to: state)
		guard !route.undo.isEmpty || !route.apply.isEmpty else { return nil }

		for edit in route.undo {
			applyEdit(byteRange: edit.appliedRange, newBytes: edit.removed)
		}
		for edit in route.apply {
			applyEdit(byteRange: edit.byteRange, newBytes: edit.inserted)
		}
		history.moveTo(state)

		// A run of typing must not coalesce onto whatever state was landed on.
		lastEditEnd = -1
		lastEditTime = .distantPast

		isDirty = true
		scheduleAutoSave()
		return route.caret.map { rope.utf16Offset(fromByte: min($0, rope.byteCount)) }
	}

	/// A few words about what an edit did, for a list of states.
	///
	/// The text is trimmed and its newlines shown, since a summary is read in a
	/// list one line high and most edits begin or end with one.
	static func summary(removed: [UInt8], inserted: [UInt8], extending: String? = nil) -> String {
		let insertedText = String(decoding: inserted.prefix(32), as: UTF8.self)
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.replacingOccurrences(of: "\n", with: "⏎")
		let removedText = String(decoding: removed.prefix(32), as: UTF8.self)
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.replacingOccurrences(of: "\n", with: "⏎")

		switch (removed.isEmpty, inserted.isEmpty) {
		case (true, false):
			return insertedText.isEmpty ? "Typed a new line" : "Typed “\(insertedText)”"
		case (false, true):
			return removedText.isEmpty ? "Deleted a new line" : "Deleted “\(removedText)”"
		case (false, false): return "Replaced “\(removedText)” with “\(insertedText)”"
		case (true, true): return "No change"
		}
	}

	// MARK: - Saving

	/// Marked rather than moved. Everything else in this file is on
	/// `engineQueue`; this one piece serialises the whole rope and does an
	/// atomic write — a temporary file, a write, a rename — on whichever thread
	/// asked, which after a typing pause is the main one. Moving it is a change
	/// to what `throws` means to every caller, so for now the log gets to say
	/// how much of a session's stalling this actually is.
	public func save() throws {
		try StallWatch.mark("document save") {
			let bytes = rope.bytes(in: 0..<rope.byteCount)
			try Data(bytes).write(to: url, options: .atomic)
			isDirty = false
			recordDiskState()
		}
	}

	/// Writes something *other* than the buffer over the file — the ciphertext
	/// `sops` made of it — and counts the buffer as saved. The same atomic
	/// write `save()` does, with the disk state recorded so the reload on
	/// focus does not take the ciphertext for a change somebody else made.
	public func replaceOnDisk(with data: Data) throws {
		try data.write(to: url, options: .atomic)
		isDirty = false
		recordDiskState()
	}

	/// Counts the buffer as saved without writing: a parked decrypted buffer
	/// that was never edited is put back into a tab by an edit, and that edit
	/// is not somebody's.
	public func markClean() {
		isDirty = false
	}

	/// Replaces the whole document with what another editor made of it.
	///
	/// For a `.drawio`, which is edited by draw.io in a web view rather than by
	/// this app's own `CodeView`. The change arrives as a whole document rather
	/// than as an edit, because that is what draw.io has to give — and it must
	/// **not** go through `replace`, for two reasons that both matter:
	///
	///  * **The undo stack is not this app's.** ⌘Z in a draw.io pane belongs to
	///    mxGraph's undo manager. Pushing an entry here as well would give the
	///    file two histories that disagree, and the app's Edit menu no way to
	///    know which one it is talking to.
	///  * **`onTextChanged` would come straight back.** The view that sent this
	///    listens to that notification for *external* changes, and a loop
	///    between an editor and the document it is editing is the shape of bug
	///    that loses somebody's drawing.
	///
	/// Everything else about the document is unchanged, which is the point:
	/// `isDirty` marks the tab, `save()` writes and records the disk state so
	/// the watcher does not mistake it for somebody else's write, and the
	/// close-without-saving prompt asks what it always asks.
	public func setContents(_ text: String, markingDirty: Bool = true) {
		guard text != rope.string else { return }
		rope = Rope(data: Data(text.utf8))
		isDirty = markingDirty
		generation &+= 1
		folds = []
		if markingDirty { scheduleAutoSave() }
	}

	// MARK: - External changes

	/// What the file looked like when this document last agreed with it.
	///
	/// Size as well as date: an agent that rewrites a file twice in the same
	/// second — which happens — would otherwise look unchanged.
	private var diskModified: Date?
	private var diskSize: Int?

	private func recordDiskState() {
		let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
		diskModified = attributes?[.modificationDate] as? Date
		diskSize = attributes?[.size] as? Int
	}

	/// Whether the file on disk no longer matches what was last read or written.
	public var hasChangedOnDisk: Bool {
		guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
			// Deleted or unreadable: not a change to reload, and treating it as
			// one would replace the buffer with nothing.
			return false
		}
		let modified = attributes[.modificationDate] as? Date
		let size = attributes[.size] as? Int
		return modified != diskModified || size != diskSize
	}

	/// Re-reads the file, replacing the buffer.
	///
	/// Returns false when there was nothing to do. The caller is responsible for
	/// putting the caret back: offsets into the old text mean nothing in the new
	/// one, and only the view knows where the user was looking.
	@discardableResult
	public func reloadFromDisk() throws -> Bool {
		guard hasChangedOnDisk else { return false }

		let data = try Data(contentsOf: url, options: .mappedIfSafe)
		rope = Rope(data: data)
		isDirty = false
		recordDiskState()

		// The tree describes text that no longer exists, so it is abandoned
		// rather than edited: an incremental reparse needs to be told what
		// changed, and an external writer does not say.
		generation &+= 1
		folds = []
		startInitialParse()
		onSyntaxUpdated?()
		// Somebody else wrote the file: that is a change to the text like any
		// other, and a preview drawn from it has to follow.
		onTextChanged?()
		return true
	}
}
