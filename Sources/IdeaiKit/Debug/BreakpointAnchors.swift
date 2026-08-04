import Foundation

/// Keeping breakpoints on the code they were put on.
///
/// A breakpoint stored as a line number stops meaning anything the moment
/// somebody types above it: the number stays where it was and the code moves
/// out from under it. Every editor that has solved this anchors the breakpoint
/// to a place in the text and reads the line off it — insert three lines above
/// and it moves down three; delete the line it sits on and it goes with it.
///
/// This is that rule, in one place and testable: a line, an edit, and where the
/// line ends up.
public enum BreakpointAnchors {
	/// Where a 1-based line ends up after an edit, or `nil` when the edit
	/// deleted it.
	///
	/// - Parameters:
	///   - line: the line the breakpoint is on, counting from 1.
	///   - firstLine: the first line the edit touched, counting from 0.
	///   - removed: how many line breaks the edit took out.
	///   - inserted: how many it put in.
	public static func moved(
		line: Int,
		editedFrom firstLine: Int,
		removed: Int,
		inserted: Int
	) -> Int? {
		let edited = firstLine + 1          // the same line, counting from 1
		let lastRemoved = edited + removed

		// Above the edit, or on the line it started in: an edit inside a line
		// leaves the breakpoint on that line, which is where its code still is.
		if line <= edited { return line }

		// Inside what was taken out: the code it was on is gone, and so is it.
		// A breakpoint left behind would sit on whatever moved up into its
		// place, which is not what anybody put it on.
		if line <= lastRemoved { return nil }

		return line + inserted - removed
	}

	/// Where a breakpoint belongs in a file that changed while nobody was
	/// looking.
	///
	/// An agent rewriting a file, a `git checkout`, a formatter: none of them
	/// send edits, so there are no lines to shift by — the file is simply
	/// different when it is read again. What is left to go on is the line
	/// itself. If the text that was on it is still nearby, the breakpoint
	/// belongs there; if it has gone, the breakpoint stays where it was and is
	/// no longer claimed to be bound.
	///
	/// Searched outward from where it was, so the nearest match wins: a line
	/// like `}` occurs everywhere, and the one three lines down is far more
	/// likely to be the same `}` than the one four hundred lines up.
	///
	/// - Parameters:
	///   - line: where the breakpoint was, counting from 1.
	///   - text: what was on that line when it was put there.
	///   - lines: the file as it is now.
	///   - radius: how far to look.
	public static func rebound(
		line: Int,
		text: String,
		in lines: [String],
		radius: Int = 40
	) -> Int? {
		let wanted = text.trimmingCharacters(in: .whitespaces)
		// Nothing to match on: a blank line is anywhere and nowhere.
		guard !wanted.isEmpty else { return min(max(1, line), max(1, lines.count)) }

		func matches(_ candidate: Int) -> Bool {
			guard candidate >= 1, candidate <= lines.count else { return false }
			return lines[candidate - 1].trimmingCharacters(in: .whitespaces) == wanted
		}

		if matches(line) { return line }
		for distance in 1...max(1, radius) {
			if matches(line - distance) { return line - distance }
			if matches(line + distance) { return line + distance }
		}
		return nil
	}

	/// Where a breakpoint sat, described by the code around it rather than by a
	/// number.
	///
	/// A line number says nothing once a file has been rewritten. "Third line
	/// of `TmuxConfig.setStatusHidden`" survives the function moving four
	/// hundred lines, which is what an agent editing a file does all the time
	/// and what the text search — deliberately near-sighted, so a stray `}`
	/// four hundred lines off is not mistaken for the same one — cannot follow.
	public struct Anchor: Equatable, Sendable {
		/// The symbols the line sits inside, outermost first.
		public let path: [String]
		/// How far into that symbol the line was.
		public let offset: Int
		/// What was written on the line, for when the symbol has gone too.
		public let text: String

		public init(path: [String], offset: Int, text: String) {
			self.path = path
			self.offset = offset
			self.text = text
		}
	}

	/// Describes where a line is, in terms of the symbols around it.
	///
	/// The innermost symbol that contains the line wins: a breakpoint in a
	/// method belongs to the method, not to the type it is in.
	///
	/// `lineOf` gives a symbol's lines as a half-open range — first up to but
	/// not including one past the last.
	public static func anchor(
		line: Int,
		text: String,
		in symbols: [DocumentSymbol],
		lineOf: (DocumentSymbol) -> Range<Int>
	) -> Anchor {
		var path: [String] = []
		var offset = line
		var candidates = symbols

		while true {
			let containing = candidates.first { symbol in
				lineOf(symbol).contains(line)
			}
			guard let containing else { break }
			path.append(containing.name)
			offset = line - lineOf(containing).lowerBound
			candidates = containing.children
		}
		return Anchor(path: path, offset: offset, text: text)
	}

	/// Where an anchor points now, in a file that has been rewritten.
	///
	/// The symbol first, then the text, then nothing: each is a weaker claim
	/// than the one before it, and a breakpoint moved by a weak claim to the
	/// wrong place is worse than one that admits it does not know.
	public static func resolve(
		_ anchor: Anchor,
		in symbols: [DocumentSymbol],
		lines: [String],
		lineOf: (DocumentSymbol) -> Range<Int>
	) -> Int? {
		if !anchor.path.isEmpty, let symbol = find(path: anchor.path, in: symbols) {
			let span = lineOf(symbol)
			let line = span.lowerBound + anchor.offset
			// Inside the symbol it was in. A symbol that lost lines takes the
			// breakpoint no further than its own end.
			return min(line, max(span.lowerBound, span.upperBound - 1))
		}
		return rebound(line: anchor.offset, text: anchor.text, in: lines)
	}

	/// Walks a path of names down a tree of symbols.
	private static func find(path: [String], in symbols: [DocumentSymbol]) -> DocumentSymbol? {
		var candidates = symbols
		var found: DocumentSymbol?
		for name in path {
			guard let match = candidates.first(where: { $0.name == name }) else { return nil }
			found = match
			candidates = match.children
		}
		return found
	}

	/// The same, for a set of breakpoints keyed by line.
	public static func moved<Value>(
		lines: [Int: Value],
		editedFrom firstLine: Int,
		removed: Int,
		inserted: Int
	) -> [Int: Value] {
		var moved: [Int: Value] = [:]
		for (line, value) in lines {
			guard let now = self.moved(
				line: line, editedFrom: firstLine, removed: removed, inserted: inserted
			) else { continue }
			moved[now] = value
		}
		return moved
	}
}
