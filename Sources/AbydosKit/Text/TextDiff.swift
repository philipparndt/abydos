import Foundation

/// Two texts, aligned line by line, with the characters that differ inside a
/// changed pair marked.
///
/// `GitPatch` parses a diff git wrote. Between two files on disk — or a file and
/// a blob, or two drafts of a paragraph — there is no git, and shelling out to
/// `git diff --no-index` for every pair a folder diff opens, or every click on
/// the history rail, is a process per look at something already in memory. So
/// the diff is computed here: Myers over lines, in linear space, and Myers
/// again over the characters of each changed pair where the pair is similar
/// enough for the marks to mean anything.
///
/// Lines are compared as integers — each distinct line interned once — so the
/// inner loop is an array read and not a string comparison, and the algorithm
/// is iterative with a work stack rather than recursive: the recursion depth
/// of a divide-and-conquer diff is the number of edits, and a hundred-thousand-
/// line rewrite is a stack nobody has.
public struct TextDiff: Sendable, Equatable {
	/// What one row of the aligned view holds.
	public enum Kind: Sendable, Equatable {
		/// The same line on both sides.
		case equal
		/// A line on each side, and they differ.
		case changed
		/// A line on the left with nothing opposite it.
		case leftOnly
		/// A line on the right with nothing opposite it.
		case rightOnly
	}

	/// One row: a line index on each side, or on one, and the marks inside a
	/// changed pair.
	///
	/// Marks are UTF-16 ranges within that side's own line, which is what an
	/// attributed string is indexed by and what a view draws from. Nil marks on a
	/// changed row mean the pair is coloured whole: either the two lines share
	/// too little for character marks to say anything, or a line was too long
	/// for the pass to be worth its cost.
	public struct Row: Sendable, Equatable {
		public let kind: Kind
		public let left: Int?
		public let right: Int?
		public let leftMarks: [Range<Int>]?
		public let rightMarks: [Range<Int>]?

		public init(
			kind: Kind, left: Int?, right: Int?,
			leftMarks: [Range<Int>]? = nil, rightMarks: [Range<Int>]? = nil
		) {
			self.kind = kind
			self.left = left
			self.right = right
			self.leftMarks = leftMarks
			self.rightMarks = rightMarks
		}
	}

	/// One maximal run of rows that are not equal: the unit the reader walks,
	/// and the unit a curve is drawn for.
	public struct Change: Sendable, Equatable {
		public enum Kind: Sendable, Equatable {
			case added, removed, changed
		}

		public let rows: Range<Int>
		public let kind: Kind

		/// The lines on each side, for the curve: empty on a side the change
		/// touches nothing of, in which case the curve pinches to the point
		/// between the neighbours.
		public let leftLines: Range<Int>
		public let rightLines: Range<Int>
	}

	/// What the title says.
	public struct Counts: Sendable, Equatable {
		/// Lines only on the right.
		public let additions: Int
		/// Lines only on the left.
		public let deletions: Int
		/// Pairs that differ.
		public let changes: Int

		public var said: String {
			"\(additions) Addition\(additions == 1 ? "" : "s"), "
				+ "\(deletions) Deletion\(deletions == 1 ? "" : "s"), "
				+ "\(changes) Change\(changes == 1 ? "" : "s")"
		}
	}

	public let leftLines: [String]
	public let rightLines: [String]
	public let rows: [Row]
	public let changes: [Change]
	public let counts: Counts

	/// Past this many UTF-16 units a line is coloured whole: the character pass
	/// over a minified bundle is O(N·D) for an N and a D that are both the
	/// whole line.
	public static let intralineLimit = 3_000

	/// How many edits the line pass will look for exactly before it splits a
	/// region at the furthest point it has reached and carries on either side
	/// of that. Myers is O((N+M)·D), so two unrelated files of a hundred
	/// thousand lines would otherwise cost the square of that — 21 seconds for
	/// twenty thousand lines a side, measured in debug — and a region that
	/// different is not one anybody reads line by line anyway. Bounded the way
	/// git's own xdiff bounds it, near the square root of the region, which
	/// keeps a real diff exact and a rewrite fast.
	public static let editLimit = 20_000

	public init(_ left: String, _ right: String) {
		self.init(leftLines: Self.lines(of: left), rightLines: Self.lines(of: right))
	}

	public init(leftLines: [String], rightLines: [String]) {
		self.leftLines = leftLines
		self.rightLines = rightLines

		// Intern: each distinct line becomes a number, so the diff compares
		// integers.
		var ids: [String: Int] = [:]
		func intern(_ lines: [String]) -> [Int] {
			lines.map { line in
				if let id = ids[line] { return id }
				let id = ids.count
				ids[line] = id
				return id
			}
		}
		let a = intern(leftLines)
		let b = intern(rightLines)

		let matches = Myers.matches(a, b, editLimit: Self.editLimit)
		var rows: [Row] = []
		rows.reserveCapacity(max(a.count, b.count))
		var i = 0, j = 0
		func flush(removed: Range<Int>, added: Range<Int>) {
			// A run of removals is paired with the run of additions after it,
			// position by position, the way `DiffView` pairs a hunk: the old
			// line and the one that replaced it on one row.
			let pairs = min(removed.count, added.count)
			for position in 0..<pairs {
				let left = removed.lowerBound + position
				let right = added.lowerBound + position
				let marks = Self.intraline(leftLines[left], rightLines[right])
				rows.append(Row(
					kind: .changed, left: left, right: right,
					leftMarks: marks?.left, rightMarks: marks?.right
				))
			}
			for left in (removed.lowerBound + pairs)..<removed.upperBound {
				rows.append(Row(kind: .leftOnly, left: left, right: nil))
			}
			for right in (added.lowerBound + pairs)..<added.upperBound {
				rows.append(Row(kind: .rightOnly, left: nil, right: right))
			}
		}
		for (x, y) in matches {
			if x > i || y > j { flush(removed: i..<x, added: j..<y) }
			rows.append(Row(kind: .equal, left: x, right: y))
			i = x + 1
			j = y + 1
		}
		if i < a.count || j < b.count { flush(removed: i..<a.count, added: j..<b.count) }
		self.rows = rows

		// The changes: maximal runs of rows that are not equal.
		var changes: [Change] = []
		var additions = 0, deletions = 0, changed = 0
		var start: Int?
		func close(at end: Int) {
			guard let from = start else { return }
			let run = rows[from..<end]
			let kinds = Set(run.map(\.kind))
			let kind: Change.Kind = kinds == [.rightOnly] ? .added : kinds == [.leftOnly] ? .removed : .changed
			let lefts = run.compactMap(\.left)
			let rights = run.compactMap(\.right)
			// A side the change touches nothing of is a point between its
			// neighbours: the line after the last equal one before the run.
			let leftAnchor = rows[..<from].last(where: { $0.left != nil })?.left.map { $0 + 1 } ?? 0
			let rightAnchor = rows[..<from].last(where: { $0.right != nil })?.right.map { $0 + 1 } ?? 0
			changes.append(Change(
				rows: from..<end,
				kind: kind,
				leftLines: lefts.isEmpty ? leftAnchor..<leftAnchor : lefts[0]..<(lefts[lefts.count - 1] + 1),
				rightLines: rights.isEmpty ? rightAnchor..<rightAnchor : rights[0]..<(rights[rights.count - 1] + 1)
			))
			start = nil
		}
		for (index, row) in rows.enumerated() {
			switch row.kind {
			case .equal:
				close(at: index)
			case .changed:
				changed += 1
				if start == nil { start = index }
			case .leftOnly:
				deletions += 1
				if start == nil { start = index }
			case .rightOnly:
				additions += 1
				if start == nil { start = index }
			}
		}
		close(at: rows.count)
		self.changes = changes
		self.counts = Counts(additions: additions, deletions: deletions, changes: changed)
	}

	/// The lines of a text, without their terminators. A text ending in a
	/// newline has no extra empty line after it — that is how every editor
	/// counts, and how git does.
	public static func lines(of text: String) -> [String] {
		guard !text.isEmpty else { return [] }
		var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
		if lines.last == "" { lines.removeLast() }
		return lines
	}

	// MARK: - Inside a changed pair

	/// The characters that differ between two lines, or nil where marking them
	/// would say nothing.
	///
	/// Nil when the pair shares less than half of the shorter line — a line
	/// replaced wholesale is coloured wholesale rather than as confetti — and
	/// nil past `intralineLimit`. Ranges are UTF-16 units, merged so that
	/// adjacent differences are one mark.
	static func intraline(_ left: String, _ right: String) -> (left: [Range<Int>], right: [Range<Int>])? {
		let a = Array(left.utf16).map(Int.init)
		let b = Array(right.utf16).map(Int.init)
		guard a.count <= intralineLimit, b.count <= intralineLimit else { return nil }
		let shorter = min(a.count, b.count)
		guard shorter > 0 else { return nil }

		let matches = Myers.matches(a, b, editLimit: intralineLimit)
		// More than half the shorter line has to survive for the marks to be
		// marks and not noise.
		guard matches.count * 2 > shorter else { return nil }

		func gaps(_ count: Int, matched: [Int]) -> [Range<Int>] {
			var ranges: [Range<Int>] = []
			var next = 0
			for index in matched {
				if index > next { ranges.append(next..<index) }
				next = index + 1
			}
			if next < count { ranges.append(next..<count) }
			return ranges
		}
		return (gaps(a.count, matched: matches.map(\.0)), gaps(b.count, matched: matches.map(\.1)))
	}

	// MARK: - Folding

	/// A row of the aligned view as it is shown: one of the rows, or a fold
	/// standing for a run of equal ones.
	public enum Shown: Sendable, Equatable {
		case row(Int)
		/// The rows hidden, identified by the first of them.
		case fold(rows: Range<Int>)
	}

	/// The rows with the long unchanged runs folded away.
	///
	/// A diff of two large files should start on the first change, not on the
	/// first line. A run of equal rows longer than `minimum` is folded, keeping
	/// `context` rows beside each change it borders — none at the edges of the
	/// file, where there is no change to border. Two identical files fold
	/// nothing: there is no change to start on, and a page of "everything is
	/// hidden" is not a diff of anything.
	public func shown(opened: Set<Int>, context: Int = 3, minimum: Int = 10) -> [Shown] {
		guard !changes.isEmpty else { return rows.indices.map(Shown.row) }
		var result: [Shown] = []
		result.reserveCapacity(rows.count)
		var index = 0
		while index < rows.count {
			guard rows[index].kind == .equal else {
				result.append(.row(index))
				index += 1
				continue
			}
			var end = index
			while end < rows.count, rows[end].kind == .equal { end += 1 }
			// Keep context beside a change, and none against the file's edges.
			let keepBefore = index == 0 ? 0 : context
			let keepAfter = end == rows.count ? 0 : context
			let hidden = (index + keepBefore)..<max(index + keepBefore, end - keepAfter)
			if hidden.count >= minimum, !opened.contains(hidden.lowerBound) {
				for row in index..<hidden.lowerBound { result.append(.row(row)) }
				result.append(.fold(rows: hidden))
				for row in hidden.upperBound..<end { result.append(.row(row)) }
			} else {
				for row in index..<end { result.append(.row(row)) }
			}
			index = end
		}
		return result
	}
}

/// Myers' algorithm over integer sequences, in linear space.
///
/// The matches — pairs of indices that are equal and in order — rather than an
/// edit script, because both callers build their own rows from them and a
/// script would be taken apart again.
enum Myers {
	/// The matched pairs, in order.
	///
	/// `editLimit` bounds the search for a middle snake: past that many edits a
	/// region is taken as wholly replaced, with no matches inside it, so the
	/// cost of two unrelated inputs is the limit times their length and not the
	/// square of their length.
	///
	/// Iterative, with a work stack of regions. The matches of a region are
	/// its common prefix, its common suffix, the body of its middle snake, and
	/// whatever its two halves match; none of that depends on the order the
	/// regions are visited in, because a match is a pair of absolute indices
	/// and the set of them is monotone. So they are collected as found and
	/// sorted once at the end, which is what lets the recursion go.
	static func matches(_ a: [Int], _ b: [Int], editLimit: Int) -> [(Int, Int)] {
		var matched: [(Int, Int)] = []
		var work: [(Range<Int>, Range<Int>)] = [(0..<a.count, 0..<b.count)]
		// Diagonals run from -(n+m) to n+m around an offset, and the search
		// reads one past either end.
		let size = 2 * (a.count + b.count) + 4
		var vf = [Int](repeating: 0, count: size)
		var vb = [Int](repeating: 0, count: size)

		while let (ra, rb) = work.popLast() {
			var a0 = ra.lowerBound, a1 = ra.upperBound
			var b0 = rb.lowerBound, b1 = rb.upperBound
			// Common prefix and suffix first: it is most of most diffs and it
			// costs nothing.
			while a0 < a1, b0 < b1, a[a0] == b[b0] {
				matched.append((a0, b0))
				a0 += 1
				b0 += 1
			}
			while a0 < a1, b0 < b1, a[a1 - 1] == b[b1 - 1] {
				a1 -= 1
				b1 -= 1
				matched.append((a1, b1))
			}
			guard a0 < a1, b0 < b1 else { continue }

			// Too different to be worth the search: nothing matches here.
			guard let snake = middleSnake(
				a, b, a0..<a1, b0..<b1, vf: &vf, vb: &vb, editLimit: editLimit
			) else { continue }
			for step in 0..<(snake.endX - snake.startX) {
				matched.append((snake.startX + step, snake.startY + step))
			}
			// After the prefix and suffix are gone the difference is at least
			// two edits, so the snake splits the region into two strictly
			// smaller ones.
			work.append((snake.endX..<a1, snake.endY..<b1))
			work.append((a0..<snake.startX, b0..<snake.startY))
		}
		return matched.sorted { $0.0 < $1.0 }
	}

	struct Snake {
		let startX: Int, startY: Int, endX: Int, endY: Int
	}

	/// The middle snake of the shortest edit path through a region — or, past
	/// the cost limit, an empty snake at the furthest point the forward search
	/// reached, which splits the region into two smaller ones that are each
	/// searched again. Nil only for a region with nothing to split.
	///
	/// The limit is `editLimit` or four times the square root of the region,
	/// whichever is smaller: the same shape as xdiff's, so that a diff with a
	/// few hundred edits is exact and a wholesale rewrite costs O((N+M)·√(N+M))
	/// rather than the square.
	private static func middleSnake(
		_ a: [Int], _ b: [Int], _ ra: Range<Int>, _ rb: Range<Int>,
		vf: inout [Int], vb: inout [Int], editLimit: Int
	) -> Snake? {
		let n = ra.count, m = rb.count
		let a0 = ra.lowerBound, b0 = rb.lowerBound
		let delta = n - m
		let odd = delta & 1 == 1
		let offset = n + m + 1
		let furthest = (n + m + 1) / 2
		let costLimit = min(editLimit, max(256, Int(Double(n + m).squareRoot()) * 4))
		vf[offset + 1] = 0
		vb[offset + 1] = 0
		// The furthest point reached so far, for the split when the search is
		// cut short. In bounds and strictly inside the region at any d ≥ 1,
		// which is what makes the two halves smaller than the whole.
		var best: (x: Int, y: Int)?
		var d = 0
		while d <= furthest {
			if d > costLimit, let best {
				return Snake(startX: a0 + best.x, startY: b0 + best.y, endX: a0 + best.x, endY: b0 + best.y)
			}
			// Forward, from the top left.
			var k = -d
			while k <= d {
				var x: Int
				if k == -d || (k != d && vf[offset + k - 1] < vf[offset + k + 1]) {
					x = vf[offset + k + 1]
				} else {
					x = vf[offset + k - 1] + 1
				}
				var y = x - k
				let startX = x, startY = y
				while x < n, y < m, a[a0 + x] == b[b0 + y] { x += 1; y += 1 }
				vf[offset + k] = x
				if x <= n, y <= m, x + y > (best.map { $0.x + $0.y } ?? 0), x + y < n + m {
					best = (x, y)
				}
				if odd, d > 0, k >= delta - (d - 1), k <= delta + (d - 1) {
					let kb = delta - k
					if vf[offset + k] + vb[offset + kb] >= n {
						return Snake(startX: a0 + startX, startY: b0 + startY, endX: a0 + x, endY: b0 + y)
					}
				}
				k += 2
			}
			// Backward, from the bottom right, in reversed coordinates.
			k = -d
			while k <= d {
				var x: Int
				if k == -d || (k != d && vb[offset + k - 1] < vb[offset + k + 1]) {
					x = vb[offset + k + 1]
				} else {
					x = vb[offset + k - 1] + 1
				}
				var y = x - k
				let startX = x, startY = y
				while x < n, y < m, a[a0 + n - 1 - x] == b[b0 + m - 1 - y] { x += 1; y += 1 }
				vb[offset + k] = x
				if !odd, k >= delta - d, k <= delta + d {
					let kf = delta - k
					if vb[offset + k] + vf[offset + kf] >= n {
						return Snake(
							startX: a0 + n - x, startY: b0 + m - y,
							endX: a0 + n - startX, endY: b0 + m - startY
						)
					}
				}
				k += 2
			}
			d += 1
		}
		return nil
	}
}
