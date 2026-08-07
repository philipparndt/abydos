import Foundation

/// Turns repeated tails of a log into the part that has not been seen.
///
/// A pod's supervisor answers "the last N lines", which is the right thing for
/// it to answer and the wrong thing to append: ask twice in a second and the
/// same two hundred lines arrive twice. Replacing the whole view with each
/// answer works for a pane that shows nothing else — and is exactly wrong for a
/// debug console, where the program's output is interleaved with the
/// debugger's and rewriting it would take the debugger's half with it.
///
/// So each answer is compared with the last: the overlap is what was already
/// shown, and what follows it is new. Line by line, because a tail is cut at
/// whatever byte the window started at and half a line matches nothing.
public struct LogTail: Sendable {
	/// The lines already handed out, most recent last.
	private var seen: [String] = []

	/// How much history to keep for matching. Longer than any tail worth
	/// asking for, and short enough that a program printing all day does not
	/// turn this into the log.
	private let memory: Int

	public init(memory: Int = 500) {
		self.memory = memory
	}

	/// The lines in this tail that have not been returned before.
	///
	/// The first tail is all new. After that the longest run of lines that ends
	/// what was seen and begins what arrived is the overlap; anything after it
	/// is new. A tail identical to the last one is entirely overlap and yields
	/// nothing, which is the common case while a program sits idle.
	public mutating func newLines(in tail: String) -> [String] {
		var lines = tail.components(separatedBy: "\n")
		// A log ends with a newline, which splits into a last empty piece that
		// is not a line.
		if lines.last?.isEmpty == true { lines.removeLast() }
		guard !lines.isEmpty else { return [] }

		var overlap = 0
		for length in stride(from: min(seen.count, lines.count), through: 1, by: -1)
		where Array(seen.suffix(length)) == Array(lines.prefix(length)) {
			overlap = length
			break
		}

		let fresh = Array(lines.dropFirst(overlap))
		seen.append(contentsOf: fresh)
		if seen.count > memory { seen.removeFirst(seen.count - memory) }
		return fresh
	}

	/// The same, as text ready to append — empty when there is nothing new, so
	/// a caller can skip the append entirely.
	public mutating func newText(in tail: String) -> String {
		let fresh = newLines(in: tail)
		return fresh.isEmpty ? "" : fresh.joined(separator: "\n") + "\n"
	}
}
