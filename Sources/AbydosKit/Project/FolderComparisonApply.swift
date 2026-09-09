import Foundation

/// The marks the gutter makes on a folder diff, and what applying them does.
///
/// A mark changes nothing on disk. It is an intention, counted in the title
/// and listed in a sheet, and *Apply* does the lot together — because a copy
/// that happens on click is a copy that happened on a mis-click, and a folder
/// diff is the one place in this app where a click can overwrite a file that
/// was never open.
///
/// What was there goes to the Trash first, the way `git-safety` leaves a
/// backup ref: every apply is undone from the Finder's *Put Back*, without a
/// backup directory of this app's own to know about.
extension FolderComparison {
	public enum Mark: Sendable, Equatable {
		case copyToRight
		case copyToLeft
		/// Removed from whichever side holds it and can be written to.
		case delete

		public var said: String {
			switch self {
			case .copyToRight: return "copy to B"
			case .copyToLeft: return "copy to A"
			case .delete: return "delete"
			}
		}
	}

	/// One thing an apply will do, for the sheet.
	public struct Operation: Sendable, Equatable {
		public enum Kind: Sendable, Equatable {
			case copy(toRight: Bool)
			case delete(left: Bool, right: Bool)
		}

		public let path: String
		public let kind: Kind

		public var said: String {
			switch kind {
			case .copy(let toRight): return "\(path)  \(toRight ? "A → B" : "A ← B")"
			case .delete(let left, let right):
				let sides = [left ? "A" : nil, right ? "B" : nil].compactMap { $0 }.joined(separator: " and ")
				return "\(path)  delete on \(sides)"
			}
		}
	}

	/// What happened to one operation.
	public struct Applied: Sendable, Equatable {
		public let operation: Operation
		/// Nil when it went through.
		public let error: String?
	}

	/// The marks a row can take: a copy only towards a side that takes
	/// writes and from a side that has the row, a delete only where it is
	/// held on a writable side, nothing on an equal row.
	public func offeredMarks(for node: Node) -> [Mark] {
		guard node !== root, node.state != .equal, !node.state.isIgnored else { return [] }
		var marks: [Mark] = []
		if node.left != nil, right.isWritable { marks.append(.copyToRight) }
		if node.right != nil, left.isWritable { marks.append(.copyToLeft) }
		if (node.left != nil && left.isWritable) || (node.right != nil && right.isWritable) {
			marks.append(.delete)
		}
		return marks
	}

	/// Marks a row, or clears it with nil. A mark the row cannot take is
	/// refused — nothing is written, and the caller's tip says why.
	@discardableResult
	public func setMark(_ mark: Mark?, at relativePath: String) -> Bool {
		let path = Self.normalised(relativePath)
		guard let node = nodes[path] else { return false }
		guard let mark else {
			marks.removeValue(forKey: path)
			onChange?()
			return true
		}
		guard offeredMarks(for: node).contains(mark) else { return false }
		marks[path] = mark
		onChange?()
		return true
	}

	public func mark(at relativePath: String) -> Mark? { marks[Self.normalised(relativePath)] }

	/// What *Apply* will do, in path order, for the sheet and the count.
	public var operations: [Operation] {
		marks.keys.sorted().compactMap { path in
			guard let mark = marks[path], let node = nodes[path] else { return nil }
			switch mark {
			case .copyToRight: return Operation(path: path, kind: .copy(toRight: true))
			case .copyToLeft: return Operation(path: path, kind: .copy(toRight: false))
			case .delete:
				return Operation(path: path, kind: .delete(
					left: node.left != nil && left.isWritable,
					right: node.right != nil && right.isWritable
				))
			}
		}
	}

	/// Does every marked operation, trashing what it overwrites or removes
	/// first, and lists the directories it touched again.
	///
	/// `trash` is the one step a test replaces: the real one moves a file to
	/// the user's Trash, which a test must not fill.
	public func apply(
		trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
	) async -> [Applied] {
		let planned = operations
		var results: [Applied] = []
		var touched = Set<String>()
		for operation in planned {
			do {
				try await perform(operation, trash: trash)
				results.append(Applied(operation: operation, error: nil))
			} catch {
				results.append(Applied(operation: operation, error: error.localizedDescription))
			}
			marks.removeValue(forKey: operation.path)
			touched.insert((operation.path as NSString).deletingLastPathComponent)
		}
		// The rows it touched come back from disk, as they would from a
		// watcher: the same listing, run now rather than a quarter-second
		// later, so that what the page shows after *Apply* is what is there.
		refresh(directories: Array(touched))
		onChange?()
		return results
	}

	private func perform(_ operation: Operation, trash: (URL) throws -> Void) async throws {
		let manager = FileManager.default
		guard let node = nodes[operation.path] else { return }
		switch operation.kind {
		case .copy(let toRight):
			let from = (toRight ? left : right).descending(to: operation.path, isDirectory: node.isDirectory)
			guard let destinationRoot = (toRight ? right : left).diskURL else {
				throw ApplyError.readOnly(toRight ? "B" : "A")
			}
			let destination = destinationRoot.appendingPathComponent(operation.path, isDirectory: node.isDirectory)
			if manager.fileExists(atPath: destination.path) { try trash(destination) }
			try manager.createDirectory(
				at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try await write(from, to: destination, isDirectory: node.isDirectory)
		case .delete(let left, let right):
			if left, let url = self.left.diskURL?.appendingPathComponent(operation.path), manager.fileExists(atPath: url.path) {
				try trash(url)
			}
			if right, let url = self.right.diskURL?.appendingPathComponent(operation.path), manager.fileExists(atPath: url.path) {
				try trash(url)
			}
		}
	}

	/// A disk source is copied whole; a blob is written; a tree at a commit is
	/// written blob by blob, since nothing on disk holds it.
	private func write(_ source: CompareSource, to destination: URL, isDirectory: Bool) async throws {
		switch source {
		case .file(let url), .folder(let url):
			try FileManager.default.copyItem(at: url, to: destination)
		case .blob:
			guard let data = await source.readData() else { throw ApplyError.missing(source.origin) }
			try data.write(to: destination, options: .atomic)
		case .tree(let repository, let commit, let path):
			try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
			let entries = await FolderListing.listTree(repository: repository, commit: commit, path: path)
			for entry in entries where !entry.isDirectory {
				let blob = CompareSource.blob(repository: repository, commit: commit, path: path.isEmpty ? entry.relativePath : path + "/" + entry.relativePath)
				guard let data = await blob.readData() else { throw ApplyError.missing(blob.origin) }
				let file = destination.appendingPathComponent(entry.relativePath)
				try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
				try data.write(to: file, options: .atomic)
			}
		}
	}

	enum ApplyError: LocalizedError {
		case readOnly(String)
		case missing(String)

		var errorDescription: String? {
			switch self {
			case .readOnly(let side): return "Side \(side) is a commit and cannot be written to."
			case .missing(let what): return "\(what) could not be read."
			}
		}
	}
}
