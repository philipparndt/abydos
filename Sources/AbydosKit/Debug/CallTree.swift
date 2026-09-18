import Foundation

/// The threads and their stacks as one tree, for the debug pane's Stack.
///
/// Asked for on 2026-09-15, of a song being debugged: "the debugger should be a
/// tree", then "a tree for the root threads". A list of one thread's frames
/// behind a picker showed a song's tracks one at a time, and two notes
/// sounding side by side in a pattern as though one ran inside the other. So
/// the roots are the threads — under a group when an adapter gives several
/// the same one — and under each thread its frames: as the list they always
/// were, or nested by `parentID` when the adapter says what is inside what.
public enum CallTree {
	public enum Kind: Equatable, Sendable {
		case group(String)
		case thread(DebugThread)
		case frame(StackFrame, thread: Int)
	}

	/// A class, so an outline view can keep a row's identity — its expansion,
	/// its selection — across rebuilds by reusing the node with the same key.
	public final class Node {
		public let key: String
		public var kind: Kind
		public var children: [Node]

		public init(key: String, kind: Kind, children: [Node] = []) {
			self.key = key
			self.kind = kind
			self.children = children
		}
	}

	public static func nodes(threads: [DebugThread], stacks: [Int: [StackFrame]]) -> [Node] {
		var roots: [Node] = []
		var groups: [String: Node] = [:]
		let counts = Dictionary(threads.compactMap(\.group).map { ($0, 1) }, uniquingKeysWith: +)
		for thread in threads {
			let node = Node(
				key: "t:\(thread.id)", kind: .thread(thread),
				children: frames(stacks[thread.id] ?? [], thread: thread.id)
			)
			// A group of one is just its thread.
			guard let group = thread.group, counts[group, default: 0] > 1 else {
				roots.append(node)
				continue
			}
			if let existing = groups[group] {
				existing.children.append(node)
			} else {
				let made = Node(key: "g:\(group)", kind: .group(group), children: [node])
				groups[group] = made
				roots.append(made)
			}
		}
		return roots
	}

	/// A thread's frames: in the adapter's order when none names a parent; a
	/// tree otherwise, outermost at the top, and siblings in the order of
	/// their lines — a stack puts what is sounding first, and a row that moved
	/// up and down with the music would be a row nobody could keep an eye on.
	static func frames(_ list: [StackFrame], thread: Int) -> [Node] {
		func leaf(_ frame: StackFrame) -> Node {
			Node(key: "f:\(thread):\(frame.id)", kind: .frame(frame, thread: thread))
		}
		guard list.contains(where: { $0.parentID != nil }) else { return list.map(leaf) }
		let ids = Set(list.map(\.id))
		var inside: [Int: [StackFrame]] = [:]
		var roots: [StackFrame] = []
		for frame in list {
			if let parent = frame.parentID, ids.contains(parent), parent != frame.id {
				inside[parent, default: []].append(frame)
			} else {
				roots.append(frame)
			}
		}
		var seen = Set<Int>()
		func build(_ frame: StackFrame) -> Node {
			let node = leaf(frame)
			guard seen.insert(frame.id).inserted else { return node }
			node.children = (inside[frame.id] ?? [])
				.sorted { ($0.file ?? "", $0.line) < ($1.file ?? "", $1.line) }
				.map(build)
			return node
		}
		return roots.map(build)
	}

	/// The tree as indented lines, for a test or a driven run to read.
	public static func describe(_ nodes: [Node], depth: Int = 0) -> [String] {
		nodes.flatMap { node -> [String] in
			let pad = String(repeating: "  ", count: depth)
			let said: String
			switch node.kind {
			case let .group(name): said = "[\(name)]"
			case let .thread(thread): said = thread.name + (thread.isQuiet == true ? " (quiet)" : "")
			case let .frame(frame, _): said = "\(frame.name)@\(frame.line)" + (frame.isSubtle ? " (subtle)" : "")
			}
			return [pad + said] + describe(node.children, depth: depth + 1)
		}
	}
}
