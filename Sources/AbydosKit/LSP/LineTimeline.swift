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

	public init(seconds: Double, barSeconds: Double, spans: [Int: [ClosedRange<Double>]]) {
		self.seconds = seconds
		self.barSeconds = barSeconds
		self.spans = spans
	}

	/// Reads a `mat/timeline` notification's parameters.
	public init?(params: [String: Any]) {
		guard let seconds = Self.number(params["seconds"]),
		      let lines = params["lines"] as? [[String: Any]]
		else { return nil }
		var spans: [Int: [ClosedRange<Double>]] = [:]
		for entry in lines {
			guard let line = (entry["line"] as? NSNumber)?.intValue,
			      let pairs = entry["spans"] as? [[Any]]
			else { continue }
			let ranges = pairs.compactMap { pair -> ClosedRange<Double>? in
				guard pair.count == 2, let start = Self.number(pair[0]), let end = Self.number(pair[1]), end >= start
				else { return nil }
				return start...end
			}
			if !ranges.isEmpty { spans[line] = ranges }
		}
		self.init(seconds: seconds, barSeconds: Self.number(params["barSeconds"]) ?? 0, spans: spans)
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

	/// `0:31.123`, as the song pane's clock reads.
	static func clock(_ seconds: Double) -> String {
		let total = Int((max(0, seconds) * 1000).rounded(.down))
		return String(format: "%d:%02d.%03d", total / 60_000, total / 1000 % 60, total % 1000)
	}
}
