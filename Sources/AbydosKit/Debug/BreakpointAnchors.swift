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
	public struct Anchor: Equatable, Hashable, Sendable {
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
	/// The symbol first — narrowed to a line by the text inside it — then the
	/// text alone, then nothing: each is a weaker claim than the one before it,
	/// and a breakpoint moved by a weak claim to the wrong place is worse than
	/// one that admits it does not know.
	public static func resolve(
		_ anchor: Anchor,
		in symbols: [DocumentSymbol],
		lines: [String],
		lineOf: (DocumentSymbol) -> Range<Int>
	) -> Int? {
		if let line = resolveBySymbol(anchor, in: symbols, lines: lines, lineOf: lineOf) {
			return line
		}
		return rebound(line: anchor.offset, text: anchor.text, in: lines)
	}

	/// Where the anchor's symbol says it is, or nil when that symbol has gone.
	///
	/// The symbol says which function; inside it, the text says which line. Both
	/// together beat either alone — the offset on its own slips the moment a
	/// line is taken out above the breakpoint but inside the same function,
	/// which is most of what editing a function is, and the text on its own
	/// cannot tell one function's `start()` from the identical line in another.
	///
	/// Kept apart from the text fallback below because the two search from
	/// different places: this one from where the symbol now is, and that one
	/// from where the breakpoint was.
	public static func resolveBySymbol(
		_ anchor: Anchor,
		in symbols: [DocumentSymbol],
		lines: [String],
		lineOf: (DocumentSymbol) -> Range<Int>
	) -> Int? {
		guard !anchor.path.isEmpty, let symbol = find(path: anchor.path, in: symbols) else {
			return nil
		}
		let span = lineOf(symbol)
		// Inside the symbol it was in. A symbol that lost lines takes the
		// breakpoint no further than its own end.
		let counted = min(span.lowerBound + anchor.offset, max(span.lowerBound, span.upperBound - 1))

		// Never outside this symbol: a `start()` in the function below is a
		// different `start()`, and counting lines is the better guess than
		// moving the breakpoint into code the anchor never named.
		let wanted = anchor.text.trimmingCharacters(in: .whitespaces)
		guard !wanted.isEmpty else { return counted }

		func matches(_ line: Int) -> Bool {
			guard span.contains(line), line >= 1, line <= lines.count else { return false }
			return lines[line - 1].trimmingCharacters(in: .whitespaces) == wanted
		}

		if matches(counted) { return counted }
		for distance in 1..<max(2, span.count) {
			if matches(counted - distance) { return counted - distance }
			if matches(counted + distance) { return counted + distance }
		}
		return counted
	}

	/// Describes where a line is, against a file's whole outline.
	///
	/// The spans come from the outline's nesting rather than from the parser's
	/// declaration ranges, which several grammars hang on the enclosing type.
	public static func anchor(
		line: Int,
		text: String,
		in symbols: [DocumentSymbol],
		lineCount: Int
	) -> Anchor {
		let spans = SymbolOutline.lineSpans(of: symbols, lineCount: lineCount)
		return anchor(line: line, text: text, in: symbols) { spans[$0.id] ?? 0..<0 }
	}

	/// Where an anchor points in a file that has been rewritten.
	public static func resolve(
		_ anchor: Anchor,
		in symbols: [DocumentSymbol],
		lines: [String]
	) -> Int? {
		let spans = SymbolOutline.lineSpans(of: symbols, lineCount: lines.count)
		return resolve(anchor, in: symbols, lines: lines) { spans[$0.id] ?? 0..<0 }
	}

	/// Where a file's breakpoints belong after something else rewrote it.
	///
	/// One that is found moves, and is anchored again against the file as it is
	/// now: its symbol has moved, so the description of where it sits has to be
	/// taken afresh or the next rewrite is measured from somewhere that no
	/// longer exists.
	///
	/// One that is not found is left completely alone — line and anchor both.
	/// Not every reload is a finished file: writing without a temporary file
	/// truncates it first, so a save caught mid-flight reads as a file in which
	/// nothing can be found. Moving breakpoints to the top of that, and
	/// re-anchoring them to what is there, would throw away where they belong a
	/// fraction of a second before the real text arrives and could have been
	/// matched. Left as they were, they are still there to be found.
	///
	/// Two that land on the same line become one, which is all a line can hold.
	public static func resolve(
		breakpoints: [Breakpoint],
		in symbols: [DocumentSymbol],
		lines: [String]
	) -> [Breakpoint] {
		let spans = SymbolOutline.lineSpans(of: symbols, lineCount: lines.count)
		let lineOf: (DocumentSymbol) -> Range<Int> = { spans[$0.id] ?? 0..<0 }

		var taken = Set<Int>()
		var resolved: [Breakpoint] = []
		for breakpoint in breakpoints {
			// The text is searched for around where the breakpoint was, not
			// around the anchor's offset into a symbol that is no longer there.
			let found = breakpoint.anchor.flatMap { anchor in
				resolveBySymbol(anchor, in: symbols, lines: lines, lineOf: lineOf)
					?? rebound(line: breakpoint.line, text: anchor.text, in: lines)
			}
			let line = found ?? breakpoint.line
			guard taken.insert(line).inserted else { continue }

			guard let found, found <= lines.count else {
				resolved.append(breakpoint)
				continue
			}

			resolved.append(Breakpoint(
				file: breakpoint.file,
				line: found,
				isEnabled: breakpoint.isEnabled,
				// Where it is now is not where the adapter bound it; it is drawn
				// unbound until the adapter says otherwise.
				isVerified: found == breakpoint.line && breakpoint.isVerified,
				condition: breakpoint.condition,
				hitCondition: breakpoint.hitCondition,
				logMessage: breakpoint.logMessage,
				anchor: anchor(line: found, text: lines[found - 1], in: symbols, lineOf: lineOf)
			))
		}
		return resolved.sorted { $0.line < $1.line }
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
