import Foundation

/// Where each line of a song is heard, as `mat lsp` says in `mat/timeline`.
///
/// Asked for on 2026-09-14: "the LSP should add markers for the times
/// (positions in the song) those shall be shown next to the line number as a
/// special bar". So the gutter draws, beside a line's number, a bar that is
/// the whole song, lit where that line is heard — a `play` step across its
/// repeats, a pattern's line wherever the pattern plays, a section across its
/// bars — and says the bars and times on hover.
///
/// Not a standard message: LSP has nothing for positions in time. A server
/// that sends it says so under `experimental.timeline`; one that does not is
/// never waited for, because nothing here waits.
public struct LineTimeline: Equatable, Sendable {
	public static let method = "mat/timeline"

	/// The end of the last thing heard, in seconds.
	public var seconds: Double
	public var barSeconds: Double
	/// 0-based lines, and the stretches of the song, in seconds, where each
	/// is heard; only lines heard somewhere.
	public var spans: [Int: [ClosedRange<Double>]]
	/// For the lines of patterns: where each pass starts and where each note
	/// is written, to light the note under the playhead. mat ecdd911 on.
	public var notes: [Int: LineNotes]

	/// A pattern line's passes and notes, as `mat/timeline` sends them.
	public struct LineNotes: Equatable, Sendable {
		/// Where each pass of the pattern starts, sorted, in seconds.
		public var passes: [Double]
		/// Sorted by start, in seconds from the start of a pass.
		public var notes: [Note]

		public init(passes: [Double], notes: [Note]) {
			self.passes = passes
			self.notes = notes
		}
	}

	public struct Note: Equatable, Sendable {
		public var start: Double
		public var end: Double
		/// 0-based UTF-16 columns on the line: the note's first, and past its last.
		public var columns: Range<Int>

		public init(start: Double, end: Double, columns: Range<Int>) {
			self.start = start
			self.end = end
			self.columns = columns
		}
	}

	public init(seconds: Double, barSeconds: Double, spans: [Int: [ClosedRange<Double>]], notes: [Int: LineNotes] = [:]) {
		self.seconds = seconds
		self.barSeconds = barSeconds
		self.spans = spans
		self.notes = notes
	}

	/// Reads a `mat/timeline` notification's parameters.
	public init?(params: [String: Any]) {
		guard let seconds = Self.number(params["seconds"]),
		      let lines = params["lines"] as? [[String: Any]]
		else { return nil }
		var spans: [Int: [ClosedRange<Double>]] = [:]
		var notes: [Int: LineNotes] = [:]
		for entry in lines {
			guard let line = (entry["line"] as? NSNumber)?.intValue,
			      let pairs = entry["spans"] as? [[Any]]
			else { continue }
			if let passes = (entry["passes"] as? [Any])?.compactMap(Self.number), !passes.isEmpty,
			   let written = entry["notes"] as? [[Any]] {
				let placed = written.compactMap { note -> Note? in
					guard note.count == 4, let start = Self.number(note[0]), let end = Self.number(note[1]),
					      let from = Self.number(note[2]), let to = Self.number(note[3]), to > from, end > start
					else { return nil }
					return Note(start: start, end: end, columns: Int(from)..<Int(to))
				}
				if !placed.isEmpty { notes[line] = LineNotes(passes: passes.sorted(), notes: placed) }
			}
			let ranges = pairs.compactMap { pair -> ClosedRange<Double>? in
				guard pair.count == 2, let start = Self.number(pair[0]), let end = Self.number(pair[1]), end >= start
				else { return nil }
				return start...end
			}
			if !ranges.isEmpty { spans[line] = ranges }
		}
		self.init(seconds: seconds, barSeconds: Self.number(params["barSeconds"]) ?? 0, spans: spans, notes: notes)
	}

	private static func number(_ value: Any?) -> Double? {
		(value as? NSNumber)?.doubleValue
	}

	/// A line's stretches as fractions of the song, for a bar the song's
	/// length wide. Empty for a line heard nowhere.
	public func fractions(line: Int) -> [ClosedRange<Double>] {
		guard seconds > 0, let ranges = spans[line] else { return [] }
		return ranges.map { max(0, min(1, $0.lowerBound / seconds))...max(0, min(1, $0.upperBound / seconds)) }
	}

	/// What a hover over a line's bar says: where, in bars and in time.
	///
	///     bars 9–16 · 0:14.545–0:29.090
	///     4 times: bars 1–2, 5–6, 9–10, 13–14 · first at 0:00.000
	public func summary(line: Int) -> String? {
		guard let ranges = spans[line], let first = ranges.first else { return nil }
		func bars(_ range: ClosedRange<Double>) -> String {
			guard barSeconds > 0 else { return "" }
			let from = Int((range.lowerBound / barSeconds + 1e-6).rounded(.down)) + 1
			let to = max(from, Int((range.upperBound / barSeconds - 1e-6).rounded(.up)))
			return from == to ? "\(from)" : "\(from)–\(to)"
		}
		if ranges.count == 1 {
			let where_ = barSeconds > 0 ? (bars(first).contains("–") ? "bars " : "bar ") + bars(first) + " · " : ""
			return where_ + Self.clock(first.lowerBound) + "–" + Self.clock(first.upperBound)
		}
		let shown = ranges.prefix(8).map(bars).joined(separator: ", ") + (ranges.count > 8 ? ", …" : "")
		return "\(ranges.count) times: bars \(shown) · first at \(Self.clock(first.lowerBound))"
	}

	/// Where a line is first heard, as the time-code column writes it.
	public func timeCode(line: Int) -> String? {
		spans[line]?.first.map { Self.clock($0.lowerBound) }
	}

	/// Where a click on a line's time code goes: the first stretch that starts
	/// after `seconds`, or the line's first when none does — so clicking the
	/// same code again walks a pattern's repeats in order.
	public func nextStart(line: Int, after seconds: Double) -> Double? {
		guard let ranges = spans[line], let first = ranges.first else { return nil }
		return ranges.first(where: { $0.lowerBound > seconds + 0.001 })?.lowerBound ?? first.lowerBound
	}

	/// How far a playhead may read before a moment and still be at it: a seek
	/// lands on a whole sample, so a song stopped on 7.2727 s reads 7.27270 and
	/// a little less.
	public static let slack = 0.002

	/// The lines heard at a moment: the debugger's markers while a song plays.
	///
	/// A stretch holds its start and not its end, so the line of one bar and
	/// the line of the next are never both marked on the boundary between.
	public func sounding(at seconds: Double) -> Set<Int> {
		let at = seconds + Self.slack
		var lines = Set<Int>()
		for (line, ranges) in spans where ranges.contains(where: { $0.lowerBound <= at && at < $0.upperBound }) {
			lines.insert(line)
		}
		return lines
	}

	/// The notes heard at a moment, by line: the columns to light while a song
	/// plays. A pass holds its start and not its end, as a stretch does.
	public func playing(at seconds: Double) -> [Int: [Range<Int>]] {
		let at = seconds + Self.slack
		var lit: [Int: [Range<Int>]] = [:]
		for (line, placed) in notes {
			// The last pass started by now, and the one before it, in case a
			// pass's last note rings past where the next begins.
			var low = 0, high = placed.passes.count
			while low < high {
				let mid = (low + high) / 2
				if placed.passes[mid] <= at { low = mid + 1 } else { high = mid }
			}
			var columns: [Range<Int>] = []
			for index in stride(from: low - 1, through: max(0, low - 2), by: -1) {
				let into = at - placed.passes[index]
				for note in placed.notes where note.start <= into && into < note.end && !columns.contains(note.columns) {
					columns.append(note.columns)
				}
			}
			if !columns.isEmpty { lit[line] = columns.sorted { $0.lowerBound < $1.lowerBound } }
		}
		return lit
	}

	/// The first breakpoint playing reaches between two moments: the earliest
	/// start of a stretch of one of `lines` after `from` and no later than
	/// `to`. A start at `from`, to within `slack`, is not reached, which is
	/// what lets a song stopped on a breakpoint play on from it. When `to` is
	/// well before `from` the song looped, and the stretch from the end back
	/// round to `to` counts; a reading a hair behind the last is not a loop.
	public func breakpoint(in lines: Set<Int>, from: Double, to: Double) -> (line: Int, seconds: Double)? {
		let looped = to < from - 0.25
		guard looped || to > from else { return nil }
		func reached(_ start: Double) -> Bool {
			looped
				? (start > from + Self.slack || start <= to + Self.slack)
				: (start > from + Self.slack && start <= to + Self.slack)
		}
		// Ordered by how far along from `from` playing reaches each, which is
		// the start itself unless the song wrapped past it.
		func distance(_ start: Double) -> Double {
			start > from ? start - from : start + (seconds - from)
		}
		var best: (line: Int, seconds: Double)?
		for line in lines.sorted() {
			for range in spans[line] ?? [] where reached(range.lowerBound) {
				if best.map({ distance(range.lowerBound) < distance($0.seconds) }) ?? true {
					best = (line, range.lowerBound)
				}
			}
		}
		return best
	}

	/// `0:31.123`, as the song pane's clock reads.
	static func clock(_ seconds: Double) -> String {
		let total = Int((max(0, seconds) * 1000).rounded(.down))
		return String(format: "%d:%02d.%03d", total / 60_000, total / 1000 % 60, total % 1000)
	}
}
