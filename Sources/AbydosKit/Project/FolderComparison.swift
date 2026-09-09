import Foundation

/// One side's view of a relative path: what its listing said, and nothing that
/// needed the file opened.
public struct FolderEntry: Sendable, Equatable {
	public let relativePath: String
	public let isDirectory: Bool
	/// Bytes, from the listing; a directory's is 0.
	public let size: Int
	/// When it was last written, on disk; nil for a tree at a commit, whose
	/// blob stands in for it.
	public let modified: Date?
	/// The blob a tree at a commit holds for it.
	public let blob: String?

	public var name: String { (relativePath as NSString).lastPathComponent }

	/// What decides whether a comparison is still current: a file that has
	/// neither changed size nor been written since is the file it was.
	var fingerprint: String {
		"\(size):\(modified?.timeIntervalSinceReferenceDate ?? 0):\(blob ?? "")"
	}
}

/// Two folders aligned by relative path, and what is known about each pair.
///
/// The row states are the four a folder diff has always had — *different*,
/// *equal*, *unmatched*, *ignored* — plus the one that makes a big tree usable:
/// *unknown*. Sizes come free with a listing, and two files of different sizes
/// are different at once, which is most of them. Files of equal size are read
/// on a background queue, in chunks, stopping at the first byte that differs,
/// and a row takes its answer when it arrives. Nothing here reads a file to
/// list it, which is what let a folder diff over a `node_modules` be walkable
/// before it was fully compared.
///
/// Listing is one directory at a time, both sides together, so that rows
/// appear as their directory is reached rather than after the whole tree is.
/// The same per-directory step is what a filesystem event re-runs: the
/// directories a batch names, and nothing else.
@MainActor
public final class FolderComparison {
	public enum State: Sendable, Equatable {
		/// Matched on both sides, sizes agree, not yet read.
		case unknown
		case different
		case equal
		/// On one side only.
		case unmatched
		/// Left out by a rule, and which rule, so the tip can say.
		case ignored(rule: String)

		public var isIgnored: Bool {
			if case .ignored = self { return true }
			return false
		}
	}

	/// What the title says.
	public struct Counts: Sendable, Equatable {
		public var different = 0
		public var equal = 0
		public var unmatched = 0
		public var ignored = 0
		/// Pairs read and not yet answered.
		public var comparing = 0
		public var isListing = false

		public var said: String {
			var parts = [
				"\(different) Different",
				"\(equal) Equal (not shown)",
				"\(unmatched) Unmatched",
				"\(ignored) Ignored",
			]
			if isListing { parts.append("listing…") }
			if comparing > 0 { parts.append("\(comparing) comparing…") }
			return parts.joined(separator: ", ")
		}
	}

	/// One relative path, on either side or both.
	public final class Node {
		public let relativePath: String
		public let isDirectory: Bool
		public internal(set) var left: FolderEntry?
		public internal(set) var right: FolderEntry?
		public internal(set) var state: State = .unknown
		/// Sorted: directories first, then by name, the way the tree lists.
		public internal(set) var children: [Node] = []
		public internal(set) weak var parent: Node?
		/// Whether a directory's children have been listed.
		public internal(set) var isListed = false
		/// Which read of this pair is current; an answer from an earlier one
		/// is dropped.
		var generation = 0

		public var name: String { (relativePath as NSString).lastPathComponent }

		init(relativePath: String, isDirectory: Bool, parent: Node?) {
			self.relativePath = relativePath
			self.isDirectory = isDirectory
			self.parent = parent
		}

		/// Both sides present.
		public var isMatched: Bool { left != nil && right != nil }

		/// A file on one side and a folder on the other: two things with one
		/// name, never listed into and never read.
		public var isKindMismatch: Bool {
			guard let left, let right else { return false }
			return left.isDirectory != right.isDirectory
		}
	}

	public private(set) var left: CompareSource
	public private(set) var right: CompareSource
	public private(set) var root: Node
	public private(set) var counts = Counts()
	/// Something moved: a row, a state, a count.
	public var onChange: (() -> Void)?

	/// Directory names never descended into, whatever side they are on: build
	/// output is the one kind of tree a folder diff is never about. The
	/// navigator's own list, and a parameter so a test can bring its own.
	public let excludedDirectoryNames: Set<String>

	/// The marks the gutter has made, by relative path.
	public internal(set) var marks: [String: Mark] = [:]

	/// Every node by path, for the lookups the views and the watcher make.
	var nodes: [String: Node] = [:]
	/// Answers by path, valid while both fingerprints match.
	private var cache: [String: (fingerprint: String, equal: Bool)] = [:]
	/// The listings of a tree at a commit, read once per side.
	private var treeIndex: [Bool: [String: [FolderEntry]]] = [:]
	private var pendingDirectories: [String] = []
	private var walking = false
	private var comparisons: [String: Task<Void, Never>] = [:]
	private var waiters: [CheckedContinuation<Void, Never>] = []
	private var watchers: [FileSystemWatcher] = []
	private var isStopped = false

	/// How many directory listings and byte comparisons have been made, so a
	/// test can say "nothing else was read".
	public private(set) var listings = 0
	public private(set) var reads = 0

	/// How many pairs are read at once. Three, not one per pair: a folder of
	/// ten thousand equal-sized files is ten thousand file handles otherwise.
	private static let gate = ComparisonGate(slots: 3)

	public init(
		left: CompareSource,
		right: CompareSource,
		excludedDirectoryNames: Set<String> = FileNode.defaultExcludedDirectoryNames
	) {
		precondition(left.isFolder && right.isFolder, "a folder diff is of two folders")
		self.left = left
		self.right = right
		self.excludedDirectoryNames = excludedDirectoryNames
		root = Node(relativePath: "", isDirectory: true, parent: nil)
		root.left = FolderEntry(relativePath: "", isDirectory: true, size: 0, modified: nil, blob: nil)
		root.right = root.left
		nodes[""] = root
	}

	/// Lists both trees, one directory at a time, and starts the comparisons.
	public func start() {
		guard !walking, !root.isListed else { return }
		enqueue(directory: "")
	}

	/// Watches both disk sides, so a file written under either moves its row.
	public func watch() {
		for source in [left, right] {
			guard let url = source.diskURL else { continue }
			let watcher = FileSystemWatcher(root: url) { [weak self] change in
				guard let self else { return }
				let touched = change.directories.compactMap { self.relativePath(of: $0, under: url) }
				self.refresh(directories: touched)
			}
			watcher.start()
			watchers.append(watcher)
		}
	}

	/// Stops the watchers and drops every read in flight.
	public func stop() {
		isStopped = true
		watchers.forEach { $0.stop() }
		watchers = []
		comparisons.values.forEach { $0.cancel() }
		comparisons = [:]
		counts.comparing = 0
		pendingDirectories = []
		resumeWaitersIfIdle()
	}

	/// The other way round, in place: every row keeps its node, its state and
	/// its place in the tree, with its two sides exchanged and its mark
	/// pointing the other way. Rebuilding for a swap threw away what was
	/// expanded and what was selected, for an answer that was already known.
	public func swapSides() {
		(left, right) = (right, left)
		for node in nodes.values {
			(node.left, node.right) = (node.right, node.left)
			if case .ignored(let rule) = node.state {
				// The side letter in the rule follows its side.
				if rule.hasPrefix("A: ") { node.state = .ignored(rule: "B: " + rule.dropFirst(3)) }
				else if rule.hasPrefix("B: ") { node.state = .ignored(rule: "A: " + rule.dropFirst(3)) }
			}
		}
		marks = marks.mapValues { mark in
			switch mark {
			case .copyToRight: return .copyToLeft
			case .copyToLeft: return .copyToRight
			case .delete: return .delete
			}
		}
		// A cached answer is keyed by both fingerprints in order; the order
		// turned round, so the keys do too.
		cache = cache.mapValues { entry in
			let halves = entry.fingerprint.split(separator: "|", maxSplits: 1).map(String.init)
			return (halves.count == 2 ? halves[1] + "|" + halves[0] : entry.fingerprint, entry.equal)
		}
		if let l = treeIndex[true], let r = treeIndex[false] {
			treeIndex = [true: r, false: l]
		} else if let l = treeIndex[true] {
			treeIndex = [false: l]
		} else if let r = treeIndex[false] {
			treeIndex = [true: r]
		}
		onChange?()
	}

	/// Lists these directories again — one listing each, however many paths a
	/// batch named under them — and re-decides their children. A directory
	/// not yet listed, or under an ignored one, is left alone.
	public func refresh(directories: [String]) {
		var seen = Set<String>()
		for directory in directories {
			let path = Self.normalised(directory)
			guard seen.insert(path).inserted else { continue }
			guard let node = nodes[path], node.isDirectory, node.isListed, !node.state.isIgnored else { continue }
			enqueue(directory: path)
		}
	}

	/// The node for a relative path, if it has been listed.
	public func node(at relativePath: String) -> Node? { nodes[Self.normalised(relativePath)] }

	/// The rows shown under a directory: equal ones only when asked for, and
	/// under a filter only the rows whose name contains it or that lead to one.
	public func children(of node: Node, showingEqual: Bool, filter: String = "") -> [Node] {
		node.children.filter { child in
			if !showingEqual, child.state == .equal { return false }
			guard !filter.isEmpty else { return true }
			return matches(child, filter: filter)
		}
	}

	private func matches(_ node: Node, filter: String) -> Bool {
		if node.name.localizedCaseInsensitiveContains(filter) { return true }
		return node.children.contains { matches($0, filter: filter) }
	}

	/// Waits until nothing is being listed or read.
	public func settled() async {
		guard counts.isListing || counts.comparing > 0 else { return }
		await withCheckedContinuation { waiters.append($0) }
	}

	// MARK: - Listing

	private func enqueue(directory: String) {
		guard !isStopped else { return }
		if !pendingDirectories.contains(directory) { pendingDirectories.append(directory) }
		guard !walking else { return }
		walking = true
		counts.isListing = true
		onChange?()
		Task { await self.walk() }
	}

	private func walk() async {
		while !pendingDirectories.isEmpty, !isStopped {
			let directory = pendingDirectories.removeFirst()
			guard let node = nodes[directory] else { continue }
			listings += 1
			async let leftEntries = list(left, directory: directory, side: true)
			async let rightEntries = list(right, directory: directory, side: false)
			let (l, r) = await (leftEntries, rightEntries)
			guard !isStopped else { break }
			merge(into: node, left: l, right: r)
			onChange?()
		}
		walking = false
		// Still listing while git is asked what it ignores: a read that
		// finishes in the meantime would otherwise wake `settled()` with the
		// rows one answer short, which under load it did.
		await applyIgnoreRules()
		counts.isListing = false
		recount()
		onChange?()
		resumeWaitersIfIdle()
	}

	/// One directory of one side. Disk listings run off the main actor; a
	/// tree at a commit is one `git ls-tree` for the whole side, indexed by
	/// directory the first time it is asked for.
	private func list(_ source: CompareSource, directory: String, side isLeft: Bool) async -> [FolderEntry]? {
		switch source {
		case .folder(let url):
			let excluded = excludedDirectoryNames
			return await Task.detached(priority: .userInitiated) {
				FolderListing.listDisk(url, directory: directory, excludedDirectoryNames: excluded)
			}.value
		case .tree(let repository, let commit, let path):
			if treeIndex[isLeft] == nil {
				let entries = await FolderListing.listTree(repository: repository, commit: commit, path: path)
				treeIndex[isLeft] = FolderListing.byDirectory(entries)
			}
			return treeIndex[isLeft]?[directory] ?? []
		case .file, .blob:
			return nil
		}
	}

	/// The children of one directory, from both listings, aligned by name.
	///
	/// A child already there keeps its node — and its marks, its expansion in
	/// a view, its cached answer — so that a refresh after one saved file is
	/// one row moving and not a tree rebuilt.
	private func merge(into node: Node, left: [FolderEntry]?, right: [FolderEntry]?) {
		let leftByName = Dictionary(uniqueKeysWithValues: (left ?? []).map { ($0.name, $0) })
		let rightByName = Dictionary(uniqueKeysWithValues: (right ?? []).map { ($0.name, $0) })
		var children: [Node] = []
		for name in Set(leftByName.keys).union(rightByName.keys) {
			let l = leftByName[name], r = rightByName[name]
			let isDirectory = (l?.isDirectory ?? false) || (r?.isDirectory ?? false)
			let path = node.relativePath.isEmpty ? name : node.relativePath + "/" + name
			let child: Node
			if let existing = nodes[path], existing.isDirectory == isDirectory {
				child = existing
			} else {
				// A file that became a folder, or the other way round, is a
				// new row; the old one goes with its marks.
				if let existing = nodes[path] { forget(existing) }
				child = Node(relativePath: path, isDirectory: isDirectory, parent: node)
				nodes[path] = child
			}
			// A name that is a file on one side and a folder on the other is
			// two things with one name: unmatched, and never read.
			if let l, let r, l.isDirectory != r.isDirectory {
				child.left = l
				child.right = r
				settle(child, state: .unmatched)
				children.append(child)
				continue
			}
			let sidesChanged = child.left != l || child.right != r
			child.left = l
			child.right = r
			children.append(child)
			decide(child, sidesChanged: sidesChanged)
		}
		// Children that went away take their subtrees with them.
		for gone in node.children where !children.contains(where: { $0 === gone }) {
			forget(gone)
		}
		node.children = children.sorted {
			if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
			return $0.name.localizedStandardCompare($1.name) == .orderedAscending
		}
		node.isListed = true
		// The directories not yet listed go on the queue — an unmatched one
		// too, listed on its one side so that its files can be copied across
		// one at a time. A directory already listed is left alone: a refresh
		// is of the directories an event named and not of everything under
		// them.
		for child in node.children
		where child.isDirectory && !child.isListed && !child.state.isIgnored && !child.isKindMismatch
			&& !pendingDirectories.contains(child.relativePath) {
			pendingDirectories.append(child.relativePath)
		}
		refold(node)
	}

	/// What a listing alone can say about a row; the rest is a read.
	private func decide(_ node: Node, sidesChanged: Bool) {
		if node.isDirectory, excludedDirectoryNames.contains(node.name) {
			settle(node, state: .ignored(rule: "build output — \(node.name)/ is never compared"))
			return
		}
		guard let l = node.left, let r = node.right else {
			settle(node, state: .unmatched)
			return
		}
		if node.isDirectory {
			// Decided by the children, once they are listed.
			if !node.isListed { node.state = .unknown }
			return
		}
		if l.size != r.size {
			settle(node, state: .different)
			return
		}
		let fingerprint = l.fingerprint + "|" + r.fingerprint
		if let cached = cache[node.relativePath], cached.fingerprint == fingerprint {
			settle(node, state: cached.equal ? .equal : .different)
			return
		}
		guard sidesChanged || node.state == .unknown else { return }
		node.state = .unknown
		read(node, fingerprint: fingerprint)
	}

	private func settle(_ node: Node, state: State) {
		if let read = comparisons.removeValue(forKey: node.relativePath) {
			read.cancel()
			counts.comparing = max(0, counts.comparing - 1)
		}
		node.generation += 1
		node.state = state
	}

	private func forget(_ node: Node) {
		settle(node, state: .unmatched)
		if nodes[node.relativePath] === node { nodes.removeValue(forKey: node.relativePath) }
		marks.removeValue(forKey: node.relativePath)
		for child in node.children { forget(child) }
	}

	// MARK: - Reading

	/// Compares a pair by bytes, off the main actor, and settles the row.
	private func read(_ node: Node, fingerprint: String) {
		comparisons[node.relativePath]?.cancel()
		node.generation += 1
		let generation = node.generation
		let leftSide = left.descending(to: node.relativePath, isDirectory: false)
		let rightSide = right.descending(to: node.relativePath, isDirectory: false)
		let path = node.relativePath
		reads += 1
		counts.comparing += 1
		comparisons[path] = Task(priority: .utility) { [weak self] in
			await Self.gate.enter()
			let equal = await FolderListing.bytesAreEqual(leftSide, rightSide)
			await Self.gate.leave()
			guard !Task.isCancelled else { return }
			await MainActor.run {
				guard let self, let node = self.nodes[path], node.generation == generation else { return }
				self.comparisons.removeValue(forKey: path)
				self.cache[path] = (fingerprint, equal)
				node.state = equal ? .equal : .different
				self.counts.comparing = max(0, self.counts.comparing - 1)
				self.refold(node.parent)
				self.recount()
				self.onChange?()
				self.resumeWaitersIfIdle()
			}
		}
	}

	/// A directory follows its children: different if any is not equal or
	/// ignored, unknown while any is still being read, equal otherwise.
	private func refold(_ node: Node?) {
		var current = node
		while let folder = current, folder.isDirectory, folder.isMatched, !folder.isKindMismatch,
			!folder.state.isIgnored {
			var state = State.equal
			for child in folder.children {
				switch child.state {
				case .different, .unmatched:
					state = .different
				case .unknown:
					if state == .equal { state = .unknown }
				case .equal, .ignored:
					break
				}
				if state == .different { break }
			}
			if !folder.isListed { state = .unknown }
			folder.state = state
			current = folder.parent
		}
	}

	private func recount() {
		var counts = Counts()
		counts.isListing = self.counts.isListing
		counts.comparing = self.counts.comparing
		func visit(_ node: Node) {
			for child in node.children {
				switch child.state {
				case .ignored: counts.ignored += 1
				case .unmatched: counts.unmatched += 1
				case .different: if !child.isDirectory { counts.different += 1 }
				case .equal: if !child.isDirectory { counts.equal += 1 }
				case .unknown: break
				}
				if child.isDirectory, !child.state.isIgnored, child.isMatched, !child.isKindMismatch { visit(child) }
			}
		}
		visit(root)
		self.counts = counts
	}

	private func resumeWaitersIfIdle() {
		guard !counts.isListing, counts.comparing == 0 || isStopped else { return }
		let resumed = waiters
		waiters = []
		resumed.forEach { $0.resume() }
	}

	// MARK: - Ignore rules

	/// Asks each disk side's git what it ignores, once the walk has listed
	/// everything there is to ask about, and greys the rows it names.
	private func applyIgnoreRules() async {
		for (source, isLeft) in [(left, true), (right, false)] {
			guard let url = source.diskURL else { continue }
			let paths = nodes.keys.filter { !$0.isEmpty }.sorted()
			let ignored = await FolderIgnore.ignoredPaths(paths, under: url)
			guard !isStopped else { return }
			for (path, rule) in ignored {
				guard let node = nodes[path], !node.state.isIgnored else { continue }
				settle(node, state: .ignored(rule: "\(isLeft ? "A" : "B"): \(rule)"))
				for child in node.children { forget(child) }
				node.children = []
				refold(node.parent)
			}
		}
	}

	// MARK: - Paths

	private func relativePath(of url: URL, under root: URL) -> String? {
		let rootPath = root.standardizedFileURL.path
		let path = url.standardizedFileURL.path
		if path == rootPath { return "" }
		guard path.hasPrefix(rootPath + "/") else { return nil }
		return String(path.dropFirst(rootPath.count + 1))
	}

	static func normalised(_ path: String) -> String {
		var trimmed = Substring(path)
		while trimmed.hasPrefix("/") { trimmed = trimmed.dropFirst() }
		while trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
		return String(trimmed)
	}
}

/// A counting semaphore for the reads, so a folder of ten thousand equal-sized
/// files opens three handles at a time rather than ten thousand.
actor ComparisonGate {
	private let slots: Int
	private var used = 0
	private var waiting: [CheckedContinuation<Void, Never>] = []

	init(slots: Int) { self.slots = slots }

	func enter() async {
		if used < slots {
			used += 1
			return
		}
		await withCheckedContinuation { waiting.append($0) }
		used += 1
	}

	func leave() {
		used -= 1
		if !waiting.isEmpty { waiting.removeFirst().resume() }
	}
}

/// The reads a folder diff makes, all of them off the main actor.
enum FolderListing {
	/// One directory of a folder on disk, as entries relative to the folder.
	///
	/// `.git` is never listed — it is the repository, not the folder — and a
	/// name on the excluded list is listed as a directory but never entered.
	static func listDisk(_ root: URL, directory: String, excludedDirectoryNames: Set<String>) -> [FolderEntry] {
		let url = directory.isEmpty ? root : root.appendingPathComponent(directory, isDirectory: true)
		let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]
		guard let contents = try? FileManager.default.contentsOfDirectory(
			at: url, includingPropertiesForKeys: keys, options: []
		) else { return [] }
		return contents.compactMap { child in
			let name = child.lastPathComponent
			if name == ".git" || name == ".DS_Store" { return nil }
			guard let values = try? child.resourceValues(forKeys: Set(keys)) else { return nil }
			let isDirectory = values.isDirectory ?? false
			return FolderEntry(
				relativePath: directory.isEmpty ? name : directory + "/" + name,
				isDirectory: isDirectory,
				size: isDirectory ? 0 : (values.fileSize ?? 0),
				modified: values.contentModificationDate,
				blob: nil
			)
		}
	}

	/// Everything under one directory of a commit, in one process: `ls-tree
	/// -r -l` gives the mode, the blob and the size of every file, and the
	/// directories are implied by the paths.
	static func listTree(repository: URL, commit: String, path: String) async -> [FolderEntry] {
		var arguments = ["ls-tree", "-r", "-l", "-z", commit]
		if !path.isEmpty { arguments += ["--", path + "/"] }
		let result = await GitRepository.run(arguments, in: repository)
		guard result.exitCode == 0 else { return [] }
		let prefix = path.isEmpty ? "" : path + "/"
		var entries: [FolderEntry] = []
		var directories = Set<String>()
		for record in result.stdout.split(separator: "\0") {
			// <mode> SP <type> SP <object> SP <size> TAB <path>
			guard let tab = record.firstIndex(of: "\t") else { continue }
			let head = record[record.startIndex..<tab].split(separator: " ", omittingEmptySubsequences: true)
			guard head.count == 4, head[1] == "blob" else { continue }
			var relative = String(record[record.index(after: tab)...])
			guard relative.hasPrefix(prefix) else { continue }
			relative = String(relative.dropFirst(prefix.count))
			let size = Int(head[3]) ?? 0
			entries.append(FolderEntry(
				relativePath: relative, isDirectory: false, size: size, modified: nil, blob: String(head[2])
			))
			var directory = (relative as NSString).deletingLastPathComponent
			while !directory.isEmpty, directories.insert(directory).inserted {
				entries.append(FolderEntry(relativePath: directory, isDirectory: true, size: 0, modified: nil, blob: nil))
				directory = (directory as NSString).deletingLastPathComponent
			}
		}
		return entries
	}

	/// A flat listing grouped by the directory each entry is in.
	static func byDirectory(_ entries: [FolderEntry]) -> [String: [FolderEntry]] {
		var result: [String: [FolderEntry]] = [:]
		for entry in entries {
			result[(entry.relativePath as NSString).deletingLastPathComponent, default: []].append(entry)
		}
		return result
	}

	/// Whether two file sides hold the same bytes, read in chunks and stopped
	/// at the first that differs.
	static func bytesAreEqual(_ left: CompareSource, _ right: CompareSource) async -> Bool {
		if let l = left.diskURL, let r = right.diskURL {
			return await Task.detached(priority: .utility) { filesAreEqual(l, r) }.value
		}
		// A blob is read whole — git hands it over as one — and the disk side,
		// if there is one, in chunks against it.
		async let leftData = left.readData()
		async let rightData = right.readData()
		let (l, r) = await (leftData, rightData)
		return l != nil && l == r
	}

	private static func filesAreEqual(_ left: URL, _ right: URL) -> Bool {
		guard let a = try? FileHandle(forReadingFrom: left), let b = try? FileHandle(forReadingFrom: right) else {
			return false
		}
		defer { try? a.close(); try? b.close() }
		let chunk = 1 << 20
		while true {
			let x = a.readData(ofLength: chunk)
			let y = b.readData(ofLength: chunk)
			if x != y { return false }
			if x.isEmpty { return true }
		}
	}
}
