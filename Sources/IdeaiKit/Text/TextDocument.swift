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

	/// Fired after an automatic save, so the tab can drop its dirty marker.
	public var onAutoSaved: (() -> Void)?

	/// Injected rather than reaching for the singleton, so auto-save behaviour
	/// can be tested against isolated preferences.
	public var settings: Settings = .shared

	private var autoSaveWork: DispatchWorkItem?

	// MARK: Syntax state

	/// Owned by `engineQueue`; never touched from the main thread.
	private let engine: SyntaxEngine?
	private let engineQueue = DispatchQueue(label: "ideai.syntax", qos: .userInteractive)

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

	private var undoStack: [EditRecord] = []
	private var redoStack: [EditRecord] = []
	private var lastEditTime: Date = .distantPast
	private var lastEditEnd: Int = -1

	/// The inverse of an applied edit, for undo.
	private struct EditRecord {
		var byteRange: Range<Int>      // range in the *new* text
		var replacedBytes: [UInt8]     // what used to be there
		var utf16CaretBefore: Int
	}

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
	}

	public var displayLanguageName: String? {
		languageId.map { LanguageRegistry.shared.displayName(for: $0) }
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

		if isContiguousTyping, var last = undoStack.last {
			last.byteRange = last.byteRange.lowerBound..<(last.byteRange.upperBound + inserted.count)
			undoStack[undoStack.count - 1] = last
		} else {
			undoStack.append(EditRecord(
				byteRange: startByte..<(startByte + inserted.count),
				replacedBytes: replaced,
				utf16CaretBefore: caretBefore
			))
		}
		lastEditTime = now
		lastEditEnd = startByte + inserted.count

		redoStack.removeAll()
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
	private func scheduleAutoSave() {
		autoSaveWork?.cancel()
		guard settings.autoSaveEnabled else { return }

		let work = DispatchWorkItem { [weak self] in
			self?.autoSave()
		}
		autoSaveWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + settings.autoSaveDelay, execute: work)
	}

	private func autoSave() {
		guard isDirty, settings.autoSaveEnabled else { return }
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
		guard settings.autoSaveEnabled, isDirty else { return false }
		autoSaveWork?.cancel()
		guard (try? save()) != nil else { return false }
		onAutoSaved?()
		return true
	}

	/// Applies an edit to the rope, then hands the reparse to the syntax queue.
	private func applyEdit(byteRange: Range<Int>, newBytes: [UInt8]) {
		// Positions must be captured against the *old* text — tree-sitter needs
		// both the old and new end to map the tree forward.
		let startPoint = point(forByte: byteRange.lowerBound)
		let oldEndPoint = point(forByte: byteRange.upperBound)

		rope.replace(byteRange: byteRange, with: newBytes)
		generation += 1

		let newEndByte = byteRange.lowerBound + newBytes.count
		let newEndPoint = point(forByte: newEndByte)

		let edit = InputEdit(
			startByte: byteRange.lowerBound,
			oldEndByte: byteRange.upperBound,
			newEndByte: newEndByte,
			startPoint: startPoint,
			oldEndPoint: oldEndPoint,
			newEndPoint: newEndPoint
		)

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

	// MARK: - Undo

	public var canUndo: Bool { !undoStack.isEmpty }
	public var canRedo: Bool { !redoStack.isEmpty }

	/// Returns the caret position to restore, or nil if there was nothing to undo.
	@discardableResult
	public func undo() -> Int? {
		guard let record = undoStack.popLast() else { return nil }

		let current = rope.bytes(in: record.byteRange)
		applyEdit(byteRange: record.byteRange, newBytes: record.replacedBytes)

		redoStack.append(EditRecord(
			byteRange: record.byteRange.lowerBound..<(record.byteRange.lowerBound + record.replacedBytes.count),
			replacedBytes: current,
			utf16CaretBefore: record.utf16CaretBefore
		))

		isDirty = true
		// Break the coalescing run so the next keystroke starts a fresh entry.
		lastEditEnd = -1
		return record.utf16CaretBefore
	}

	@discardableResult
	public func redo() -> Int? {
		guard let record = redoStack.popLast() else { return nil }

		let current = rope.bytes(in: record.byteRange)
		applyEdit(byteRange: record.byteRange, newBytes: record.replacedBytes)

		undoStack.append(EditRecord(
			byteRange: record.byteRange.lowerBound..<(record.byteRange.lowerBound + record.replacedBytes.count),
			replacedBytes: current,
			utf16CaretBefore: record.utf16CaretBefore
		))

		isDirty = true
		lastEditEnd = -1
		return rope.utf16Offset(fromByte: record.byteRange.lowerBound + record.replacedBytes.count)
	}

	// MARK: - Folding

	/// Folds cover the whole document, so they are debounced and computed off the
	/// main thread — a burst of keystrokes recomputes them once, after a pause.
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

	// MARK: - Saving

	public func save() throws {
		let bytes = rope.bytes(in: 0..<rope.byteCount)
		try Data(bytes).write(to: url, options: .atomic)
		isDirty = false
	}
}
