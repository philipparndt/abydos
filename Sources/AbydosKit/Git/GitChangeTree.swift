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

	/// The submodule this row *is*, when the row is a repository rather than a
	/// folder somebody's paths happened to invent.
	///
	/// In an estate the tree is built from paths relative to the superproject —
	/// `svc-47/src/Main.java` — so a submodule already arrives as a folder row
	/// without anything being added. What it does not arrive as is a
	/// *repository*, and the difference decides three things: which git the row
	/// is staged in, that `src/main/java` under `svc-3` and under `svc-47` are
	/// different folders rather than one, and that the row has a branch and a
	/// gitlink to say something about.
	public private(set) var submodule: GitSubmodule?

	public var isRepository: Bool { submodule != nil }

	/// The superproject's own entry for this submodule, when its recorded commit
	/// has moved.
	///
	/// Held on the repository row rather than drawn as a row of its own, because
	/// there is one submodule and it should be one row. "This submodule points
	/// somewhere new" and "this submodule has uncommitted work in it" are two
	/// facts about the same thing, and a refactoring produces them in that
	/// order.
	public private(set) var gitlink: GitChange?

	/// How far the gitlink moved, once somebody has asked. A row draws commits
	/// here where a file row draws lines — see `GitGitlinkMovement`.
	public var movement: GitGitlinkMovement?

	fileprivate func mark(as submodule: GitSubmodule, gitlink: GitChange?) {
		self.submodule = submodule
		self.gitlink = gitlink
	}

	/// Whether this row has files under it — a folder this tree invented, *or* a
	/// directory git reported as a single entry because everything inside it is
	/// untracked.
	///
	/// **The question the icon and the disclosure triangle ask, and deliberately
	/// not `isFolder`.** An untracked directory has a change, so it is not a
	/// folder in the sense the rest of this file means: `isPartial` is
	/// `isFolder && count < total`, the context menu says "folder" for rows this
	/// pane invented, and `tally` gives anything that is not a folder a count of
	/// one — which is exactly right here, because git reports the whole
	/// directory as one entry and one thing to stage. Widening `isFolder` to
	/// cover it would have made a wholly unstaged directory read "1 of 12" and
	/// offer to stage what was already staged.
	///
	/// What was wrong was only ever the drawing: `.abydos` and `PI-12` are
	/// directories with work inside them and they were two rows with a `?`
	/// beside them and nothing underneath.
	public var holdsFiles: Bool { isFolder || change?.isDirectory == true }

	/// Whether only some of what has changed under this folder is on this side.
	///
	/// The one thing a folder row has to say and a file row does not: two lists
	/// make a folder in "Staged" look finished, and somebody who reads it that
	/// way commits half of it.
	public var isPartial: Bool { isFolder && count < total }

	/// Public so a view can make the flat arrangement — one childless node per
	/// file, in the order git gave them — without going through `build`, which
	/// sorts and groups and is the *other* arrangement.
	public init(path: String, change: GitChange?) {
		self.path = path
		self.change = change
	}

	fileprivate func add(_ child: GitChangeNode) { children.append(child) }

	/// Puts what was found inside an untracked directory under it, once
	/// somebody has opened the row.
	///
	/// **`count` and `total` are deliberately left alone.** Git reports the
	/// whole directory as one entry — one thing to stage, whether it holds two
	/// files or ten thousand — and `tally` has already given this row a count of
	/// one, which is true. Counting what turned up inside would make a row that
	/// is wholly unstaged read "1 of 12" and offer to stage the rest of
	/// something already staged in full.
	///
	/// Replaces rather than appends, so a refresh that asks again cannot double
	/// the rows.
	public func fill(with contents: [GitChangeNode]) {
		children = contents
		isFilled = true
	}

	/// Whether this row has been opened and answered.
	///
	/// Empty is a real answer — an untracked directory can hold nothing, which
	/// is what a `mkdir` and nothing else leaves — so it is not "not asked yet".
	public private(set) var isFilled = false

	fileprivate func sortChildren() {
		// Directories first, then case-insensitive name order — the arrangement
		// `FileNode.order` gives the project tree. Two trees in one window that
		// sort differently is a difference nobody can explain.
		children.sort { a, b in
			// `holdsFiles` rather than `isFolder`, so an untracked directory sorts
			// with the folders it is drawn as rather than among the files.
			if a.holdsFiles != b.holdsFiles { return a.holdsFiles }
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

	/// How much of this changed, once somebody has asked `--numstat`.
	///
	/// Optional, and never defaulted to zero. Git answers `-` in both columns
	/// for a binary file, a mode change and a pure rename, and `0 0` would be a
	/// claim that nothing changed — a different statement, and an untrue one.
	public private(set) var lines: GitLineCount?

	/// Puts the counts onto this row and everything under it, and gives a folder
	/// the sum of what it holds.
	///
	/// An untracked directory nobody has opened has no children to sum and no
	/// count of its own — git does not diff a directory — so it says nothing
	/// about lines. Working out what it would say means walking it, which is the
	/// one thing this whole arrangement is built to avoid; once it is opened its
	/// children carry their own counts and the sum appears.
	@discardableResult
	public func applyLineCounts(_ counts: [String: GitLineCount]) -> GitLineCount? {
		guard holdsFiles else {
			lines = counts[path]
			return lines
		}
		var sum: GitLineCount?
		for child in children {
			guard let under = child.applyLineCounts(counts) else { continue }
			sum = (sum ?? GitLineCount(added: 0, removed: 0)) + under
		}
		lines = sum
		return sum
	}
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
	/// The rows for what is inside an untracked directory, as its own little
	/// tree.
	///
	/// The paths come back from git relative to the work tree root — `PI-12/a/b.txt`
	/// for a file two deep — so the folders between are invented here the same
	/// way `build` invents them, and for the same reason: a flat list of
	/// `a/b.txt` under a row would say where nothing is.
	///
	/// Every row is untracked and on the same side of the index as the directory
	/// itself, because that is what it is: nothing in here is known to git.
	public static func contents(
		ofUntrackedDirectory directory: String, files: [String], staged: Bool
	) -> [GitChangeNode] {
		guard !files.isEmpty else { return [] }
		let root = GitChangeNode(path: directory, change: nil)
		var folders: [String: GitChangeNode] = [directory: root]

		for file in files {
			let parent = folder(
				for: (file as NSString).deletingLastPathComponent, in: &folders, under: root
			)
			parent.add(GitChangeNode(
				path: file,
				change: GitChange(path: file, kind: .untracked, isStaged: staged)
			))
		}

		root.sortChildren()
		// Tallied so the invented folders inside can say how much is under them.
		// The directory's own row is not touched: it is `root` here, thrown away
		// on return, and the real row keeps the count of one that `build` gave
		// it.
		root.tally()
		return root.children
	}

	/// The roots of the tree for `changes`, told what is on the other side so
	/// each folder can say whether it is whole.
	///
	/// - Parameter estate: the submodules the paths may be inside, when the
	///   changes come from more than one repository. Paths are then relative to
	///   the superproject, a submodule with anything under it becomes a
	///   repository row above its folders, and its gitlink — if the
	///   superproject reports one as moved — is folded onto that same row.
	///
	///   **A project with no submodules gains nothing from this.** The estate is
	///   empty, no row is marked, and the tree is the tree it always was: a
	///   level with one child that is always the same child would say nothing,
	///   and there is no branch on "is this a superproject" to keep true.
	public static func build(
		_ changes: [GitChange],
		against other: [GitChange] = [],
		in estate: GitEstate? = nil
	) -> [GitChangeNode] {
		let root = GitChangeNode(path: "", change: nil)
		var folders: [String: GitChangeNode] = ["": root]

		// The superproject's entry for a submodule is not a row of its own. It
		// is the same submodule the folder rows below are about, and two rows
		// reading `svc-47` — one a gitlink, one a folder — would be the same
		// thing twice with different verbs on it.
		var gitlinks: [String: GitChange] = [:]
		let changes = changes.filter { change in
			guard let estate, estate.submodule(at: change.path) != nil else { return true }
			gitlinks[GitEstate.normalised(change.path)] = change
			return false
		}

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

		// After the folders exist and before the sort, so a repository row that
		// only moved — nothing dirty inside it — still gets made. `build` makes
		// a folder only where something changed under it, and "the submodule
		// points somewhere new" is a change with nothing under it.
		if let estate {
			for submodule in estate.submodules {
				let hasContents = folders[submodule.path] != nil
				guard hasContents || gitlinks[submodule.path] != nil else { continue }
				let node = folder(for: submodule.path, in: &folders, under: root)
				node.mark(as: submodule, gitlink: gitlinks[submodule.path])
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
