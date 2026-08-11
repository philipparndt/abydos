import Foundation

/// One row of a changes tree: a changed file, or a folder with changes under it.
///
/// A class rather than a struct because `NSOutlineView` keeps its items and
/// asks about them by identity; the tree is rebuilt from scratch on every
/// refresh and the view puts expansion and selection back by *path*, which is
/// the only thing that survives that. Same arrangement as the project tree, and
/// for the same reason.
public final class GitChangeNode {
	/// Path relative to the work tree root.
	///
	/// A folder's path is a path `git add` and `git restore` already accept, so
	/// staging a folder is one argument rather than one per file under it.
	public let path: String

	/// The change this row is, for a file. Nil for a folder.
	///
	/// Git has no such thing as a changed directory — a folder is not something
	/// it tracks — so a folder row is entirely ours, and everything it says
	/// about itself is computed here.
	public let change: GitChange?

	public private(set) var children: [GitChangeNode] = []

	/// Changes under this row on the side of the index it is showing. One for a
	/// file, the number of files beneath for a folder.
	public private(set) var count: Int = 0

	/// Changes under this row on *both* sides of the index.
	///
	/// Counted per entry rather than per path, so a file that is staged and then
	/// edited again counts twice — once on each side. That is what makes the
	/// arithmetic below work without a special case: such a file leaves its
	/// folder saying "1 of 2" in both lists, which is true. Counting distinct
	/// paths would have said "1 of 1" and called a folder whole when a commit
	/// would have left half of it behind.
	public private(set) var total: Int = 0

	public var name: String { (path as NSString).lastPathComponent }
	public var isFolder: Bool { change == nil }

	/// Whether only some of what has changed under this folder is on this side.
	///
	/// The one thing a folder row has to say and a file row does not: two lists
	/// make a folder in "Staged" look finished, and somebody who reads it that
	/// way commits half of it.
	public var isPartial: Bool { isFolder && count < total }

	init(path: String, change: GitChange?) {
		self.path = path
		self.change = change
	}

	fileprivate func add(_ child: GitChangeNode) { children.append(child) }

	fileprivate func sortChildren() {
		// Directories first, then case-insensitive name order — the arrangement
		// `FileNode.order` gives the project tree. Two trees in one window that
		// sort differently is a difference nobody can explain.
		children.sort { a, b in
			if a.isFolder != b.isFolder { return a.isFolder }
			return a.name.localizedStandardCompare(b.name) == .orderedAscending
		}
		for child in children { child.sortChildren() }
	}

	@discardableResult
	fileprivate func tally() -> (count: Int, total: Int) {
		guard isFolder else {
			count = 1
			total = 1
			return (1, 1)
		}
		var counted = 0
		var totalled = 0
		for child in children {
			let sums = child.tally()
			counted += sums.count
			totalled += sums.total
		}
		count = counted
		total = totalled + otherSide
		return (count, total)
	}

	/// Entries under this folder that are on the *other* side of the index.
	fileprivate var otherSide = 0
}

/// The changes on one side of the index, as the folders they are in.
///
/// Only folders with a change under them exist. The whole project would put a
/// commit of three files at the bottom of the same tree the navigator already
/// shows, which is the column of near-identical paths this replaces with extra
/// steps — and it would make the pane's cost the project's size rather than the
/// change's. The price is that the tree changes shape as things are staged: a
/// folder emptied by staging goes away, and where the selection lands next is
/// the view's problem, not this one's.
///
/// Nothing is collapsed: `Sources/AbydosKit/Git` with one change under it is
/// three rows. Folding a chain of single-child folders into one row would make
/// a row that is not a folder, in a window whose other tree does not do it, and
/// would take away the row that stages `Sources/AbydosKit` on its own.
public enum GitChangeTree {
	/// The roots of the tree for `changes`, told what is on the other side so
	/// each folder can say whether it is whole.
	public static func build(_ changes: [GitChange], against other: [GitChange] = []) -> [GitChangeNode] {
		let root = GitChangeNode(path: "", change: nil)
		var folders: [String: GitChangeNode] = ["": root]

		for change in changes {
			let parent = folder(for: (change.path as NSString).deletingLastPathComponent,
			                    in: &folders, under: root)
			parent.add(GitChangeNode(path: change.path, change: change))
		}

		// The other side is counted into the deepest folder this tree happens to
		// have, and only that one: `tally` carries a child's total up into its
		// parent, so counting the same entry at every level above it would say
		// a folder three deep held three changes it does not have.
		//
		// A folder with nothing at all on this side is not made here. It
		// belongs to the other list, and an empty row for it would be a row
		// that stages nothing.
		for change in other {
			var path = (change.path as NSString).deletingLastPathComponent
			while !path.isEmpty {
				if let folder = folders[path] {
					folder.otherSide += 1
					break
				}
				path = (path as NSString).deletingLastPathComponent
			}
		}

		root.sortChildren()
		root.tally()
		return root.children
	}

	/// Every node in the tree, by path, for putting selection and expansion back
	/// after a rebuild.
	public static func index(_ roots: [GitChangeNode]) -> [String: GitChangeNode] {
		var found: [String: GitChangeNode] = [:]
		var stack = roots
		while let node = stack.popLast() {
			found[node.path] = node
			stack.append(contentsOf: node.children)
		}
		return found
	}

	/// The paths to hand git, with anything already covered by a selected
	/// folder dropped.
	///
	/// `git add -A -- Sources Sources/Git/Blame.swift` would do the right thing
	/// anyway, so this is not correctness — it is that a selection of a folder
	/// and forty files under it should be the one argument the folder already
	/// is, and that the command an error is reported from should be readable.
	public static func reduce(_ paths: [String]) -> [String] {
		let selected = Set(paths)
		var seen = Set<String>()
		return paths.filter { path in
			guard seen.insert(path).inserted else { return false }
			var parent = (path as NSString).deletingLastPathComponent
			while !parent.isEmpty {
				if selected.contains(parent) { return false }
				parent = (parent as NSString).deletingLastPathComponent
			}
			return true
		}
	}

	/// The folder node for a relative path, making every folder above it that
	/// does not exist yet.
	private static func folder(
		for path: String,
		in folders: inout [String: GitChangeNode],
		under root: GitChangeNode
	) -> GitChangeNode {
		if let found = folders[path] { return found }
		let node = GitChangeNode(path: path, change: nil)
		folders[path] = node
		let parent = folder(for: (path as NSString).deletingLastPathComponent, in: &folders, under: root)
		parent.add(node)
		return node
	}
}
