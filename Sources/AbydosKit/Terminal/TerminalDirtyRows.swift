/// The rows a frame has to draw again, gathered between one frame and the next.
///
/// Two jobs, both of them small and both of them easy to get quietly wrong.
///
/// **The union.** `TerminalEngine.takeDirtyRange` answers once per batch of
/// output and clearing it is what taking it means, so whoever asks is the only
/// one holding the answer. Several batches are parsed between two frames — the
/// parser works to a budget and yields — so a frame that asked the engine
/// directly would see only the last batch and would draw a screen missing
/// everything the ones before it changed.
///
/// **The numbers.** A dirty range is in *absolute* rows: scrollback and the
/// active grid indexed as one buffer, which is what the view scrolls through.
/// Absolute rows move. A line falling out of history renumbers every one of
/// them, which is what `discardedLineCount` counts and what
/// `realignSelectionForDiscardedLines` moves a selection by. Anything that
/// *keeps* what it worked out about a row — the GPU renderer keeps the
/// instances it built, one array per row, and copies them forward into the next
/// frame — cannot key that by a number which shifts underneath it. So this
/// hands the range over as **line numbers**: counted from the first line the
/// terminal ever had, which nothing renumbers.
public struct TerminalDirtyRows: Sendable, Equatable {
	/// What has been reported and not yet drawn, in absolute rows.
	private var pending: ClosedRange<Int>?

	public init() {}

	/// Whether anything is waiting to be drawn.
	public var isEmpty: Bool { pending == nil }

	/// Adds what an engine has just reported, in absolute rows.
	///
	/// Ranges taken at different moments are unioned as absolute rows, and that
	/// is only sound because of one thing: a line leaving history dirties the
	/// whole document at the same moment it renumbers everything. So a union
	/// spanning that moment is a union with the document, and the shift cannot
	/// make the answer too small — only larger than it needed to be.
	/// `TerminalDirtyRangeTests.aDiscardedLineDirtiesEverything` is where that
	/// is asserted rather than assumed.
	public mutating func note(_ range: ClosedRange<Int>?) {
		guard let range else { return }
		guard let existing = pending else {
			pending = range
			return
		}
		let low = Swift.min(existing.lowerBound, range.lowerBound)
		let high = Swift.max(existing.upperBound, range.upperBound)
		pending = low...high
	}

	/// Hands over what changed as line numbers, and starts again.
	///
	/// `discardedLineCount` is read at this moment rather than at each `note`,
	/// which is the same reason the union is sound: the moment it changes is a
	/// moment the whole document was marked.
	public mutating func take(discardedLineCount: Int) -> ClosedRange<Int>? {
		defer { pending = nil }
		guard let pending else { return nil }
		return (pending.lowerBound + discardedLineCount)...(pending.upperBound + discardedLineCount)
	}

	/// Which line an absolute row is, counting from the first the terminal had.
	public static func lineNumber(ofAbsoluteRow row: Int, discardedLineCount: Int) -> Int {
		row + discardedLineCount
	}
}
