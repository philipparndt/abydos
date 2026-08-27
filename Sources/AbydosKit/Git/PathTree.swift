import Foundation

/// One row of a tree built from slash-separated names: a thing, or a folder
/// with things under it.
///
/// A class rather than a struct because `NSOutlineView` keeps its items and
/// asks about them by identity; a tree is rebuilt from scratch on every refresh
/// and the view puts expansion and selection back by *path*, which is the only
/// thing that survives that. The same arrangement `GitChangeNode` and the
/// project tree already use, and for the same reason.
public final class PathNode<Payload> {
	/// The full name this row stands for: `Sources/AbydosKit`, `feature/tags`.
	public let path: String

	/// What this row is, for a leaf. Nil for a folder.
	public let payload: Payload?

	public private(set) var children: [PathNode<Payload>]

	/// Leaves beneath this row. One for a leaf.
	public private(set) var count: Int = 0

	/// What the row says. Usually the last component — but a folded folder is
	/// several of them, so this is not always derivable from `path` by taking
	/// the last one.
	public private(set) var name: String

	public var isFolder: Bool { payload == nil }

	init(path: String, payload: Payload?, name: String? = nil) {
		self.path = path
		self.payload = payload
		self.children = []
		self.name = name ?? (path as NSString).lastPathComponent
	}

	fileprivate func add(_ child: PathNode<Payload>) { children.append(child) }
	fileprivate func replaceChildren(with children: [PathNode<Payload>]) {
		self.children = children
	}

	fileprivate func rename(to name: String) { self.name = name }

	@discardableResult
	fileprivate func tally() -> Int {
		guard isFolder else {
			count = 1
			return 1
		}
		count = children.reduce(0) { $0 + $1.tally() }
		return count
	}
}

/// Slash-separated names, as the tree they describe.
///
/// **Written once because it is wanted three times.** The project tree, the
/// changes tree and the refs tree are all a list of `/`-separated names drawn
/// as folders, and `GitChangeNode`'s own comment already says it is the "same
/// arrangement as the project tree, and for the same reason". A branch name is
/// a path. A third implementation that sorted differently would be a difference
/// in one window that nobody could explain.
///
/// **What the callers do not agree about is folding**, and that is why it is a
/// parameter rather than a rule. The changes tree deliberately keeps a chain of
/// single-child folders as a chain: folding it would make a row that is not a
/// folder and would take away the row that stages `Sources/AbydosKit` on its
/// own. The refs tree wants the opposite — a `hotfix/` folder holding only
/// `hotfix/0472` has turned one row into two and said nothing, because there is
/// no such thing as checking out a folder of branches.
public enum PathTree {
	/// The roots of the tree for these names.
	///
	/// - Parameter folding: whether a folder with exactly one child is merged
	///   into it, so `hotfix/0472` is one row reading `hotfix/0472`.
	/// - Parameter promoting: leaves the payload gives a rank to sort before
	///   their siblings, lowest rank first; `nil` is not promoted at all.
	///
	///   **A rank rather than a flag, because there is more than one winner.**
	///   The branch you are on and the branch everything merges into are the
	///   two anybody looks for and the two worst to hunt for, and they have an
	///   order between them — which is what `BranchGrouping.arrange` already
	///   pins for the branch pill in the titlebar. A flag can say *both of
	///   these go first* and cannot say *this one of them goes first*, so the
	///   two lists of the same branches would have disagreed about their order.
	/// - Parameter keeping: folder names that are never folded away, whatever
	///   `folding` says and however few children they hold.
	///
	///   **A folder that is an object cannot be flattened, because its verbs go
	///   with it.** Folding is right for a prefix that merely happened to be
	///   shared — `hotfix/0472` as one row — and wrong for `backup/`, which is
	///   a folder this program makes and which the refs tree gives a verb of
	///   its own: deleting the entries older than a given age. One backup ref
	///   meant no backup folder, and no way to sweep the backups. The question
	///   is not how many children a folder has but whether the tree names it in
	///   its own right.
	public static func build<Payload>(
		_ items: [(path: String, payload: Payload)],
		folding: Bool = false,
		keeping: Set<String> = [],
		promoting: ((Payload) -> Int?)? = nil
	) -> [PathNode<Payload>] {
		let root = PathNode<Payload>(path: "", payload: nil)
		var folders: [String: PathNode<Payload>] = ["": root]

		for item in items {
			// A name with no slash in it is a child of the root, which is what
			// `deletingLastPathComponent` answers with an empty string.
			let parent = folder(
				for: (item.path as NSString).deletingLastPathComponent,
				in: &folders,
				under: root
			)
			parent.add(PathNode(path: item.path, payload: item.payload))
		}

		if folding { fold(root, keeping: keeping) }
		sort(root, promoting: promoting)
		root.tally()
		return root.children
	}

	/// Every node in the tree, by path, for putting selection and expansion
	/// back after a rebuild.
	public static func index<Payload>(
		_ roots: [PathNode<Payload>]
	) -> [String: PathNode<Payload>] {
		var found: [String: PathNode<Payload>] = [:]
		var stack = roots
		while let node = stack.popLast() {
			found[node.path] = node
			stack.append(contentsOf: node.children)
		}
		return found
	}

	// MARK: - Building

	private static func folder<Payload>(
		for path: String,
		in folders: inout [String: PathNode<Payload>],
		under root: PathNode<Payload>
	) -> PathNode<Payload> {
		if let found = folders[path] { return found }
		let node = PathNode<Payload>(path: path, payload: nil)
		folders[path] = node
		let parent = folder(
			for: (path as NSString).deletingLastPathComponent, in: &folders, under: root
		)
		parent.add(node)
		return node
	}

	/// Merges a folder that holds exactly one thing into that thing.
	///
	/// Bottom-up, so `a/b/c` with one child at every level becomes the single
	/// row `a/b/c` rather than two passes' worth of half-folded chain. The
	/// child keeps its own path — which is what git is given and what expansion
	/// is remembered by — and takes a name that says the whole way down.
	private static func fold<Payload>(_ node: PathNode<Payload>, keeping: Set<String>) {
		for child in node.children { fold(child, keeping: keeping) }

		let folded = node.children.map { child -> PathNode<Payload> in
			guard child.isFolder, child.children.count == 1 else { return child }
			// Named in its own right, so it keeps its row: see `keeping`.
			// Matched on the last component rather than the whole path, so a
			// `backup` under a folder is still a `backup`.
			guard !keeping.contains((child.path as NSString).lastPathComponent) else {
				return child
			}
			let only = child.children[0]
			// The name is built from the paths rather than by joining the two
			// display names: `only` may itself be a folded row already, and
			// joining names would say `hotfix/0472/0472` for the deeper case.
			only.rename(to: relative(only.path, under: node.path))
			return only
		}
		node.replaceChildren(with: folded)
	}

	/// What is left of `path` once the folder it sits in has been taken off.
	private static func relative(_ path: String, under parent: String) -> String {
		guard !parent.isEmpty else { return path }
		let prefix = parent + "/"
		guard path.hasPrefix(prefix) else { return path }
		return String(path.dropFirst(prefix.count))
	}

	private static func sort<Payload>(
		_ node: PathNode<Payload>,
		promoting: ((Payload) -> Int?)?
	) {
		// Folders first, then case-insensitive name order — the arrangement
		// `FileNode.order` gives the project tree and `GitChangeNode` copies.
		// A promoted leaf comes before its siblings and before the folders,
		// which is the one departure: the branch you are on, and the branch
		// everything merges into, are the answers to the question the list is
		// usually being asked.
		node.replaceChildren(with: node.children.sorted { a, b in
			let rankA = a.payload.flatMap { promoting?($0) ?? nil }
			let rankB = b.payload.flatMap { promoting?($0) ?? nil }
			switch (rankA, rankB) {
			case let (first?, second?): if first != second { return first < second }
			case (.some, .none):        return true
			case (.none, .some):        return false
			case (.none, .none):        break
			}
			if a.isFolder != b.isFolder { return a.isFolder }
			return a.name.localizedStandardCompare(b.name) == .orderedAscending
		})
		for child in node.children { sort(child, promoting: promoting) }
	}
}
