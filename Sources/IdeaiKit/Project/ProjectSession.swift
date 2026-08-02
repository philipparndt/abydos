import Foundation

/// What was open in a project, so coming back to it looks as it was left.
///
/// Kept as plain values rather than views: a project that is not on screen has
/// no views, and the point is to be able to put them back.
public struct ProjectSession: Equatable, Sendable {
	public struct OpenFile: Equatable, Sendable {
		public var path: String
		/// Where the caret was, one-based as the editor counts.
		public var line: Int
		/// Provisional tabs — opened by a single click and replaced by the next
		/// one — come back the same way rather than becoming permanent.
		public var isPreview: Bool

		public init(path: String, line: Int = 1, isPreview: Bool = false) {
			self.path = path
			self.line = line
			self.isPreview = isPreview
		}
	}

	/// A terminal that was open, and what it was called.
	///
	/// The shell itself is not saved — a process cannot be — but where it was
	/// and what it was named can be, and starting one there again is what
	/// "my terminals are still here" means in practice.
	public struct OpenTerminal: Equatable, Sendable {
		public var name: String
		/// Where the shell starts, or nil for the project.
		public var directory: String?
		/// Whether the person named this one, in which case the shell's own
		/// title must not take the name back.
		public var isRenamed: Bool

		public init(name: String, directory: String? = nil, isRenamed: Bool = false) {
			self.name = name
			self.directory = directory
			self.isRenamed = isRenamed
		}
	}

	public var files: [OpenFile]
	/// Which one was in front.
	public var activePath: String?
	public var terminals: [OpenTerminal]
	/// Whether the panel the terminals live in was showing.
	public var isPanelVisible: Bool

	public init(
		files: [OpenFile] = [],
		activePath: String? = nil,
		terminals: [OpenTerminal] = [],
		isPanelVisible: Bool = false
	) {
		self.files = files
		self.activePath = activePath
		self.terminals = terminals
		self.isPanelVisible = isPanelVisible
	}

	public var isEmpty: Bool { files.isEmpty && terminals.isEmpty }
}

/// What was open in each project, for as long as the app is running.
///
/// Bounded, because following a terminal around a machine could otherwise
/// collect every project ever visited: the ones not returned to for longest go
/// first, which is the order they are least likely to be wanted in.
public struct ProjectSessions {
	private var byRoot: [String: ProjectSession] = [:]
	/// Least recently used first.
	private var order: [String] = []
	private let limit: Int

	public init(limit: Int = 32) {
		self.limit = max(1, limit)
	}

	public mutating func store(_ session: ProjectSession, for root: URL) {
		let key = root.standardizedFileURL.path
		byRoot[key] = session
		order.removeAll { $0 == key }
		order.append(key)

		while order.count > limit, let oldest = order.first {
			order.removeFirst()
			byRoot.removeValue(forKey: oldest)
		}
	}

	public mutating func take(for root: URL) -> ProjectSession? {
		let key = root.standardizedFileURL.path
		guard let session = byRoot[key] else { return nil }
		order.removeAll { $0 == key }
		order.append(key)
		return session
	}

	public func session(for root: URL) -> ProjectSession? {
		byRoot[root.standardizedFileURL.path]
	}

	public var count: Int { byRoot.count }
}
