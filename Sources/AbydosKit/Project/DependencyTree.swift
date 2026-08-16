import Foundation

/// A row in the project view's Dependencies section.
///
/// A class rather than a value, because `NSOutlineView` identifies its items by
/// object and a struct handed out twice would be two different rows to it —
/// which is the same reason `FileNode` is a class.
///
/// **A package row is a directory**, and that is the whole design. Its children
/// are ordinary `FileNode`s rooted at the checkout, so listing, sorting, git
/// colour, the context menu, arrow keys and reveal all work inside a dependency
/// without a line written for them. The dependency nodes are only the few rows
/// above the files: the section, the subproject groups, the packages, and the
/// notes for a kind nothing reads yet.
public final class DependencyNode {
	public enum Row {
		/// The one root row: "Dependencies".
		case section
		/// One root's worth, when there is more than one root to tell apart.
		///
		/// The name is carried rather than taken from the root's last component:
		/// two subprojects called `service` in different folders are exactly the
		/// case this row exists to tell apart, and the path relative to the
		/// project is what does it.
		case group(DependencySet, name: String)
		/// A package, which is where the origin is read off.
		case package(ExternalDependency)
		/// A kind that was not read, or a project that has resolved nothing.
		/// The row that stops an empty section reading as "no dependencies".
		case note(DependencySet)
	}

	public let row: Row
	public private(set) var childNodes: [DependencyNode]
	/// The directory whose contents are this row's children, for a package whose
	/// sources are on disk.
	public let fileRoot: FileNode?

	init(row: Row, childNodes: [DependencyNode] = [], fileRoot: FileNode? = nil) {
		self.row = row
		self.childNodes = childNodes
		self.fileRoot = fileRoot
	}

	/// What the row is called.
	public var title: String {
		switch row {
		case .section: return "Dependencies"
		case let .group(_, name): return name
		case let .package(package): return package.name
		case let .note(set): return set.kind.title
		}
	}

	/// The grey half of the row: the version and where it came from, the kind of
	/// project a group is, or why a note is there.
	public var subtitle: String? {
		switch row {
		case .section:
			return nil
		case let .group(set, _):
			return set.kind.title
		case let .package(package):
			let origin = package.shortOrigin
			guard let version = package.version else { return origin.isEmpty ? nil : origin }
			return origin.isEmpty ? version : version + "  ·  " + origin
		case let .note(set):
			switch set.contents {
			case .notRead:
				// The item number is on the row on purpose. Somebody looking at a
				// Maven project can see both that its dependencies are not read
				// and where that is written down, without going to the backlog.
				guard let item = set.kind.pendingItem else { return "not read yet" }
				return String(format: "not read yet (%04d)", item)
			case let .unresolved(reason):
				return reason
			case .packages:
				return nil
			}
		}
	}

	/// The whole of what is known about the row, for the tooltip — the origin
	/// unabbreviated, which is the one thing `subtitle` has to cut.
	public var detail: String? {
		switch row {
		case .section:
			return nil
		case let .group(set, _):
			return set.kind.title + " in " + set.root.path
		case let .package(package):
			var lines = [package.origin]
			if let version = package.version { lines.append("version " + version) }
			lines.append(package.localPath?.path ?? "not fetched")
			return lines.joined(separator: "\n")
		case let .note(set):
			return set.kind.title + " in " + set.root.path
		}
	}

	/// Whether there is anything under this row.
	public var isExpandable: Bool {
		switch row {
		case .section, .group: return !childNodes.isEmpty
		case .package: return fileRoot != nil
		case .note: return false
		}
	}

	/// A name for this row that survives the tree being rebuilt, so expansion
	/// state can be put back. Paths and package names, never object identity.
	public var identity: String {
		switch row {
		case .section: return "section"
		case let .group(set, _): return "group:" + set.kind.rawValue + ":" + set.root.path
		case let .package(package): return "package:" + package.origin + ":" + package.name
		case let .note(set): return "note:" + set.kind.rawValue + ":" + set.root.path
		}
	}
}

/// The Dependencies section, built from what the readers found.
public struct DependencyTree {
	public let sets: [DependencySet]
	public let root: DependencyNode

	/// Nil when there is nothing to show at all — a project of no recognised
	/// kind, which gets no section rather than an empty one.
	public init?(sets: [DependencySet], project: URL) {
		guard !sets.isEmpty else { return nil }
		self.sets = sets

		// One root's worth needs no grouping: the packages hang straight off the
		// section. The item asked for the subproject to be named "where there is
		// more than one", and a lone `cadova-models` heading between the section
		// and its seven packages is a row that answers a question nobody asked.
		let children: [DependencyNode]
		if sets.count == 1, let only = sets.first {
			children = DependencyTree.rows(for: only)
		} else {
			children = sets.map { set in
				DependencyNode(
					row: .group(set, name: DependencyTree.rootName(set.root, in: project)),
					childNodes: DependencyTree.rows(for: set)
				)
			}
		}
		root = DependencyNode(row: .section, childNodes: children)
	}

	private static func rows(for set: DependencySet) -> [DependencyNode] {
		switch set.contents {
		case let .packages(packages):
			guard !packages.isEmpty else {
				// Read, and there is genuinely nothing — a `go.mod` with no
				// `require`. Said in words, because a group with no rows under it
				// is indistinguishable from one nobody has expanded.
				return [DependencyNode(row: .note(DependencySet(
					root: set.root, kind: set.kind, contents: .unresolved("no dependencies")
				)))]
			}
			return packages.map { package in
				DependencyNode(
					row: .package(package),
					fileRoot: package.localPath.map { FileNode(url: $0, isDirectory: true) }
				)
			}
		case .notRead, .unresolved:
			return [DependencyNode(row: .note(set))]
		}
	}

	/// How a root is named in the section: the subproject's path relative to the
	/// project, or the project's own name for the project itself.
	public static func rootName(_ root: URL, in project: URL) -> String {
		let relative = Subprojects.relativePath(root, to: project)
		guard relative != FilePath.canonical(root) else { return root.lastPathComponent }
		return relative
	}

	/// Every row in the section, top down, for a harness to print.
	public func report() -> [String] {
		var lines: [String] = []
		func walk(_ node: DependencyNode, depth: Int) {
			let indent = String(repeating: "  ", count: depth)
			let subtitle = node.subtitle.map { " — " + $0 } ?? ""
			lines.append(indent + node.title + subtitle)
			for child in node.childNodes { walk(child, depth: depth + 1) }
		}
		walk(root, depth: 0)
		return lines
	}

	/// Where a file sits in this section, if it sits in it at all.
	///
	/// This is what makes reveal work for a file with no place in the project
	/// tree. The answer is the chain of rows from the section down to the
	/// package, and the file's node inside that package — the caller expands the
	/// chain and selects the node.
	///
	/// Ordered longest checkout first, so a package inside another package's
	/// directory — which SwiftPM does not do but a vendored layout might —
	/// answers for its own files rather than the outer one.
	public func locate(_ file: URL) -> (chain: [DependencyNode], node: FileNode)? {
		let path = FilePath.canonical(file)
		var best: (chain: [DependencyNode], node: FileNode)?
		var bestLength = -1

		func walk(_ node: DependencyNode, chain: [DependencyNode]) {
			let chain = chain + [node]
			if let fileRoot = node.fileRoot {
				let base = FilePath.canonical(fileRoot.url)
				if path == base || path.hasPrefix(base + "/"), base.count > bestLength {
					// Walked back through the *node's* own URL rather than the
					// canonical one: the prefix test has to resolve symlinks —
					// `/tmp` against `/private/tmp` is 508's whole reason for
					// `FilePath` — but `FileNode` names its children by the path
					// it listed them under, and a lookup by a canonical path
					// would match none of them.
					let relative = path.dropFirst(base.count).drop { $0 == "/" }
					let target = relative.isEmpty
						? fileRoot.url
						: fileRoot.url.appendingPathComponent(String(relative))
					if let found = fileRoot.node(for: target) {
						best = (chain, found)
						bestLength = base.count
					}
				}
			}
			for child in node.childNodes { walk(child, chain: chain) }
		}
		walk(root, chain: [])
		return best
	}

	/// Which package a file belongs to, for anything that wants to say where a
	/// file came from without opening the tree.
	public func package(containing file: URL) -> ExternalDependency? {
		guard let found = locate(file) else { return nil }
		for node in found.chain.reversed() {
			if case let .package(package) = node.row { return package }
		}
		return nil
	}
}
