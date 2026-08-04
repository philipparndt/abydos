import Foundation

/// The shape of a history: which lane each commit sits in, and what runs past
/// it.
///
/// A list of commits with their parents is a graph, and drawing it is a matter
/// of assigning every line of descent a lane and remembering, for each row,
/// which lanes pass through it and which of them bend. This does that and
/// nothing else — no colours, no geometry, no view — so it can be tested
/// against histories that would be miserable to make by hand in a repository.
public enum GitGraph {
	/// A line leaving a row, from one lane to another.
	public struct Edge: Equatable, Sendable {
		/// The lane the line is in as it leaves the top of the row.
		public let from: Int
		/// The lane it is in when it reaches the next row.
		public let to: Int
		/// Which line of descent it belongs to, for colouring.
		public let branch: Int

		public init(from: Int, to: Int, branch: Int) {
			self.from = from
			self.to = to
			self.branch = branch
		}
	}

	/// One row of the drawing.
	public struct Row: Equatable, Sendable {
		public let hash: String
		/// The lane the commit's own dot sits in.
		public let lane: Int
		/// Which line of descent the dot belongs to, for its colour.
		public let branch: Int
		/// Lines carrying on downwards from this row, including the commit's
		/// own if it has a parent.
		public let edges: [Edge]
		/// How many lanes are in use here, which is how wide the column has to
		/// be for this row.
		public let width: Int
		/// A merge whose second parent's own commits can be folded away, and
		/// how many rows that would hide.
		public let collapsible: Int

		public init(
			hash: String,
			lane: Int,
			branch: Int,
			edges: [Edge],
			width: Int,
			collapsible: Int = 0
		) {
			self.hash = hash
			self.lane = lane
			self.branch = branch
			self.edges = edges
			self.width = width
			self.collapsible = collapsible
		}
	}

	/// What a commit needs to be placed: its hash and its parents.
	public struct Node: Equatable, Sendable {
		public let hash: String
		public let parents: [String]

		public init(hash: String, parents: [String]) {
			self.hash = hash
			self.parents = parents
		}
	}

	/// Lays out a list of commits, in the order they are given.
	///
	/// The order is git's — `log` hands them back newest first — and the lanes
	/// follow from it: a lane is opened when a commit is first expected by
	/// something below it, and closed when it is reached.
	public static func lay(out nodes: [Node]) -> [Row] {
		/// What each lane is waiting for, and which line of descent it is.
		var lanes: [(expects: String, branch: Int)?] = []
		var nextBranch = 0
		var rows: [Row] = []

		let positions = Dictionary(
			nodes.enumerated().map { ($0.element.hash, $0.offset) },
			uniquingKeysWith: { first, _ in first }
		)

		for node in nodes {
			// The lane already waiting for this commit, or a new one on the
			// right. The leftmost wins, so a long-lived line — main — keeps the
			// lane it started in.
			var lane = lanes.firstIndex { $0?.expects == node.hash } ?? -1
			if lane < 0 {
				lane = lanes.firstIndex { $0 == nil } ?? lanes.count
				if lane == lanes.count { lanes.append(nil) }
				lanes[lane] = (expects: node.hash, branch: nextBranch)
				nextBranch += 1
			}
			let branch = lanes[lane]?.branch ?? 0

			// Anything else waiting for the same commit merges into this lane
			// and lets its own go. Its branch is taken now, before the lane is
			// let go: the line arriving here is the last of *that* line of
			// descent, and drawing it in this commit's colour would change a
			// branch's colour halfway down for no reason the history gives.
			var joining: [(lane: Int, branch: Int)] = []
			for (index, entry) in lanes.enumerated() where index != lane && entry?.expects == node.hash {
				joining.append((lane: index, branch: entry?.branch ?? 0))
				lanes[index] = nil
			}

			// The first parent carries this lane on; the others take a lane of
			// their own unless something is already waiting for them.
			if let first = node.parents.first {
				lanes[lane] = (expects: first, branch: branch)
			} else {
				lanes[lane] = nil
			}

			var edges: [Edge] = []
			for (index, entry) in lanes.enumerated() where entry != nil {
				// A lane that is still waiting for something carries straight
				// down, except this one, which bends from the dot.
				edges.append(Edge(from: index, to: index, branch: entry?.branch ?? 0))
			}
			// Lines that ended here came from their own lane into this one, in
			// their own colour.
			for join in joining {
				edges.append(Edge(from: join.lane, to: lane, branch: join.branch))
			}

			for parent in node.parents.dropFirst() {
				if let existing = lanes.firstIndex(where: { $0?.expects == parent }) {
					edges.append(Edge(from: lane, to: existing, branch: lanes[existing]?.branch ?? 0))
					continue
				}
				var slot = lanes.firstIndex { $0 == nil } ?? lanes.count
				if slot == lanes.count { lanes.append(nil) }
				lanes[slot] = (expects: parent, branch: nextBranch)
				edges.append(Edge(from: lane, to: slot, branch: nextBranch))
				nextBranch += 1
				slot += 0
			}

			rows.append(Row(
				hash: node.hash,
				lane: lane,
				branch: branch,
				edges: edges,
				width: lanes.count,
				collapsible: mergedRowCount(of: node, nodes: nodes, positions: positions)
			))
		}
		return rows
	}

	/// How many rows a merge brought in on its second parent.
	///
	/// Everything reachable from the second parent that is not also reachable
	/// from the first — the commits somebody would call "the branch that was
	/// merged" — counted only as far as the list goes. Zero for anything that
	/// is not a merge, and zero when the two sides meet immediately.
	static func mergedRowCount(
		of node: Node,
		nodes: [Node],
		positions: [String: Int]
	) -> Int {
		mergedHashes(of: node, nodes: nodes).count { positions[$0] != nil }
	}

	/// The commits a merge brought in on its second parent.
	///
	/// Everything reachable from it that is not also reachable from the first —
	/// what somebody would call "the branch that was merged". Empty for
	/// anything that is not a merge, and for a merge whose sides meet at once.
	public static func mergedHashes(of node: Node, nodes: [Node]) -> Set<String> {
		guard node.parents.count > 1 else { return [] }
		let byHash = Dictionary(nodes.map { ($0.hash, $0) }, uniquingKeysWith: { first, _ in first })

		// Everything the first parent can reach, which is where the side
		// branch stops belonging to itself.
		var mainline = Set<String>()
		var queue = [node.parents[0]]
		while let hash = queue.popLast() {
			guard mainline.insert(hash).inserted, let commit = byHash[hash] else { continue }
			queue += commit.parents
		}

		var side = Set<String>()
		queue = Array(node.parents.dropFirst())
		while let hash = queue.popLast() {
			guard !mainline.contains(hash) else { continue }
			guard side.insert(hash).inserted, let commit = byHash[hash] else { continue }
			queue += commit.parents
		}
		return side
	}
}
