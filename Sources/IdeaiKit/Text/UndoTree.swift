import Foundation

/// Every state a document has been in, and how to get between them.
///
/// A plain undo stack throws away the future the moment you type after
/// undoing: the text you backed out of is gone, and no amount of redo brings
/// it back. That is the one moment in editing where the machine destroys work
/// silently, and it happens constantly — undo a few lines, try something else,
/// and the first attempt has never existed.
///
/// A tree keeps both. Typing after an undo adds a branch beside the old one
/// rather than deleting it, so every state the document has been in stays
/// reachable. What it costs is that "redo" becomes a question — which future?
/// — which is why a node remembers when it was made and which of its children
/// came last.
public struct UndoTree {
	/// One edit, in both directions.
	///
	/// Enough to apply and to undo, because moving around a tree does both:
	/// getting from one branch to another walks up to a shared ancestor undoing
	/// as it goes, then back down applying.
	public struct Edit: Equatable, Sendable {
		/// Where it happened, in the text as it was *before* the edit.
		public var byteRange: Range<Int>
		public var removed: [UInt8]
		public var inserted: [UInt8]
		/// Where the caret was before this was typed, so undo puts it back.
		public var caretBefore: Int

		public init(byteRange: Range<Int>, removed: [UInt8], inserted: [UInt8], caretBefore: Int) {
			self.byteRange = byteRange
			self.removed = removed
			self.inserted = inserted
			self.caretBefore = caretBefore
		}

		/// The range this edit occupies in the text *after* it was applied.
		public var appliedRange: Range<Int> {
			byteRange.lowerBound..<(byteRange.lowerBound + inserted.count)
		}
	}

	public struct Node: Equatable, Sendable {
		public let id: Int
		public var parent: Int?
		public var children: [Int]
		/// What was done to the parent to arrive here. The root has none: it is
		/// the document as it was opened.
		public var edit: Edit?
		public var time: Date
		/// A short description of what changed, for a list of states.
		public var summary: String
	}

	public private(set) var nodes: [Node]
	/// Which state the document is in now.
	public private(set) var current: Int

	public static let rootID = 0

	public init(time: Date = Date()) {
		nodes = [Node(id: Self.rootID, parent: nil, children: [], edit: nil, time: time, summary: "Opened")]
		current = Self.rootID
	}

	public var root: Node { nodes[Self.rootID] }
	public var currentNode: Node { nodes[current] }
	public var count: Int { nodes.count }

	public var canUndo: Bool { currentNode.parent != nil }
	public var canRedo: Bool { !currentNode.children.isEmpty }

	/// Whether there is more than one way forward from here.
	public var hasAlternativeFutures: Bool { currentNode.children.count > 1 }

	// MARK: - Recording

	/// Adds a state reached by making an edit, and moves to it.
	@discardableResult
	public mutating func record(_ edit: Edit, summary: String, time: Date = Date()) -> Int {
		let id = nodes.count
		nodes.append(Node(
			id: id, parent: current, children: [], edit: edit, time: time, summary: summary
		))
		// Newest last: redo without being asked takes the most recent future,
		// which is the one somebody was working on.
		nodes[current].children.append(id)
		current = id
		return id
	}

	/// Extends the edit that led to the current state.
	///
	/// Typing a word is one thing that happened, not seven, and undo should
	/// take back the word. Only ever the node just arrived at — anything else
	/// would rewrite a state something else may have branched from.
	public mutating func extendCurrent(inserted: [UInt8], summary: String, time: Date) {
		guard current != Self.rootID, nodes[current].edit != nil else { return }
		nodes[current].edit?.inserted += inserted
		nodes[current].time = time
		nodes[current].summary = summary
	}

	// MARK: - Moving

	/// The edits to undo and then to apply, to get from here to `target`.
	///
	/// Undoing walks up to the nearest shared ancestor, applying walks back
	/// down. For plain undo and redo one of the two lists is always empty; for
	/// a jump across branches neither is.
	public func route(to target: Int) -> (undo: [Edit], apply: [Edit], caret: Int?) {
		guard nodes.indices.contains(target), target != current else { return ([], [], nil) }

		let fromRoot = pathFromRoot(to: current)
		let toRoot = pathFromRoot(to: target)

		// Where the two paths stop agreeing is the shared ancestor.
		var shared = 0
		while shared < fromRoot.count, shared < toRoot.count, fromRoot[shared] == toRoot[shared] {
			shared += 1
		}

		let undo = fromRoot[shared...].reversed().compactMap { nodes[$0].edit }
		let apply = toRoot[shared...].compactMap { nodes[$0].edit }

		// The caret belongs where the last thing that moved it left it: after
		// undoing, where the undone edit began; after applying, after it.
		let caret = apply.last.map { $0.byteRange.lowerBound + $0.inserted.count }
			?? undo.last?.caretBefore
		return (undo, apply, caret)
	}

	/// Marks a move as done. The caller applies the edits `route` handed back.
	public mutating func moveTo(_ target: Int) {
		guard nodes.indices.contains(target) else { return }
		current = target
	}

	/// The state one step back, or nil at the beginning.
	public var undoTarget: Int? { currentNode.parent }

	/// The state one step forward, taking the most recent branch.
	public var redoTarget: Int? { currentNode.children.last }

	/// Every way forward from here, newest first.
	public var futures: [Node] {
		currentNode.children.reversed().map { nodes[$0] }
	}

	/// Every state, oldest first — what a list of the history shows.
	public var timeline: [Node] {
		nodes.sorted { $0.time < $1.time }
	}

	/// Whether `node` is on the way from the root to the current state.
	public func isOnCurrentPath(_ node: Int) -> Bool {
		pathFromRoot(to: current).contains(node) || node == Self.rootID
	}

	private func pathFromRoot(to node: Int) -> [Int] {
		var path: [Int] = []
		var cursor: Int? = node
		while let id = cursor {
			path.append(id)
			cursor = nodes[id].parent
		}
		return path.reversed()
	}
}
