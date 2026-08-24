import Foundation

/// Which files match what has been typed, and in what order.
///
/// **The order is the whole feature.** A plain "contains" over the path answers
/// `Git` with every file in a directory called `Git`, and the file actually
/// called `Git.swift` is somewhere in that list rather than at the top of it —
/// which is the behaviour that makes people stop using a file finder and go back
/// to the tree. It costs one comparison to avoid.
///
/// Substring rather than fuzzy, deliberately and for now. Fuzzy ranking changes
/// *what* matches as well as what order they come in, and shipping both at once
/// would make a bad result impossible to attribute to either.
public enum FileMatching {
	/// A path prepared for matching against many queries.
	///
	/// **This exists because of a measurement.** Matching was first written
	/// against `[String]`, lower-casing each path and taking its last component
	/// through `NSString` on every keystroke. Driven against a work tree of
	/// 24,691 files that cost **110–157 ms per character typed** — off the main
	/// thread, so nothing stuttered, but the list ran a whole keystroke behind
	/// the field, which is the same complaint from a different direction.
	///
	/// Everything that does not depend on the query is done once, here, when the
	/// index is built: lower-cased, as UTF-8 bytes, with the last component's
	/// offset already found. Searching bytes rather than `String.range(of:)` is
	/// the other half — UTF-8 is self-synchronising, so a byte-wise substring
	/// search over lower-cased UTF-8 finds exactly what a `String` search would.
	public struct Candidate: Sendable {
		/// The path as it will be shown and opened.
		public let path: String
		/// The same path, lower-cased, as UTF-8 bytes.
		let bytes: ContiguousArray<UInt8>
		/// Where the last path component starts in `bytes`.
		let nameAt: Int

		public init(_ path: String) {
			self.path = path
			let lowered = ContiguousArray(path.lowercased().utf8)
			self.bytes = lowered
			self.nameAt = lowered.lastIndex(of: UInt8(ascii: "/")).map { $0 + 1 } ?? 0
		}
	}

	/// How well a path answers a query. Lower sorts first.
	///
	/// Made public so the ranking can be tested as a claim about two paths
	/// rather than only through the order of a list.
	public struct Rank: Equatable, Comparable, Sendable {
		/// 0 when the file's own name matches, 1 when only a directory above it
		/// does. This is the rule that keeps `Sources/Model/Git.swift` above
		/// everything inside `Sources/Git/`.
		public let tier: Int
		/// How much longer the matched text is than the query: an exact name
		/// beats a longer one containing it, so `Repo` finds `Repo.swift` before
		/// `GitRepository.swift`.
		public let extra: Int
		/// Where the match starts, so a name beginning with the query beats one
		/// with it in the middle.
		public let offset: Int
		/// Shorter paths last, as a tie-break that is at least stable.
		public let length: Int

		public static func < (a: Rank, b: Rank) -> Bool {
			if a.tier != b.tier { return a.tier < b.tier }
			if a.extra != b.extra { return a.extra < b.extra }
			if a.offset != b.offset { return a.offset < b.offset }
			return a.length < b.length
		}
	}

	/// How a path scores against a query, or nil when it does not match.
	public static func rank(of path: String, for query: String) -> Rank? {
		let needle = ContiguousArray(query.lowercased().utf8)
		return needle.withUnsafeBufferPointer { rank(of: Candidate(path), for: $0) }
	}

	/// The same, against a path already prepared and a query already folded.
	static func rank(of candidate: Candidate, for needle: UnsafeBufferPointer<UInt8>) -> Rank? {
		guard !needle.isEmpty else { return nil }
		return candidate.bytes.withUnsafeBufferPointer { bytes -> Rank? in
			let total = bytes.count

			// The file's own name first, because that is the answer people mean.
			if let found = index(of: needle, in: bytes, from: candidate.nameAt) {
				return Rank(
					tier: 0,
					extra: (total - candidate.nameAt) - needle.count,
					offset: found - candidate.nameAt,
					length: total
				)
			}
			// Otherwise somewhere in a directory above it.
			guard let found = index(of: needle, in: bytes, from: 0) else { return nil }
			return Rank(tier: 1, extra: total - needle.count, offset: found, length: total)
		}
	}

	/// Where `needle` first occurs in `haystack` at or after `from`.
	///
	/// Written out rather than reached for through `String`, and over buffer
	/// pointers rather than arrays: this runs twenty-five thousand times per
	/// keystroke, and bounds checks and retain traffic on a `[UInt8]` are most
	/// of what it would otherwise cost. The first-byte check is what keeps the
	/// bytes that cannot match to a single comparison each.
	static func index(
		of needle: UnsafeBufferPointer<UInt8>,
		in haystack: UnsafeBufferPointer<UInt8>,
		from: Int
	) -> Int? {
		let n = needle.count
		let last = haystack.count - n
		guard n > 0, from <= last else { return nil }
		let first = needle[0]

		var start = from
		while start <= last {
			guard haystack[start] == first else {
				start += 1
				continue
			}
			var offset = 1
			while offset < n, haystack[start + offset] == needle[offset] { offset += 1 }
			if offset == n { return start }
			start += 1
		}
		return nil
	}

	/// The best matches, in order.
	///
	/// - `limit`: how many to return. The palette caps files the way it already
	///   caps projects, and for the reason its own comment gives: without a
	///   limit the sections underneath are pushed off. 25,564 candidates must
	///   not push branches and actions out of reach.
	public static func matches(for query: String, in paths: [String], limit: Int = 25) -> [String] {
		matches(for: query, in: paths.map(Candidate.init), limit: limit)
	}

	/// The same, against paths already prepared — what the index actually calls.
	public static func matches(
		for query: String, in candidates: [Candidate], limit: Int = 25
	) -> [String] {
		let trimmed = query.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty, limit > 0 else { return [] }
		let needle = ContiguousArray(trimmed.lowercased().utf8)

		// Ranked once and sorted, rather than sorted by a comparator that ranks
		// on every comparison. At tens of thousands of paths that is the
		// difference between one pass and n log n of them.
		var scored: [(path: String, rank: Rank)] = []
		scored.reserveCapacity(min(candidates.count, 512))
		needle.withUnsafeBufferPointer { needle in
			for candidate in candidates {
				guard let rank = rank(of: candidate, for: needle) else { continue }
				scored.append((candidate.path, rank))
			}
		}

		scored.sort { left, right in
			if left.rank != right.rank { return left.rank < right.rank }
			// Named order for the last tie, so the same query gives the same
			// list twice running — a list that reshuffled between two keystrokes
			// would be one nobody could click.
			return left.path.localizedStandardCompare(right.path) == .orderedAscending
		}
		return scored.prefix(limit).map(\.path)
	}
}
