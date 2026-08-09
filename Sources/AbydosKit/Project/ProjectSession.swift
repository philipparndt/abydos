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
	/// Which tmux window the terminal was showing — tmux's own id, `@7`.
	///
	/// The id and not the index, because an index is where a window sits and
	/// somebody's window does not stay there: close the one before it and
	/// everything after moves down. Nil for a project whose terminal was not
	/// mirroring a session, and for one saved before this was written.
	public var tmuxWindow: String?
	/// Which part of the project was being worked on, relative to it.
	public var subprojectPath: String?
	/// The launch configuration that was chosen in the titlebar.
	///
	/// The name rather than the configuration: what to run is the project's,
	/// kept in `.ideai/run` and shared with everyone; which of them you had
	/// picked is this window's, and reopening a project to a play button
	/// pointing at something else is a run of the wrong thing one click away.
	public var selectedConfiguration: String?
	/// Where each Xcode project was last run, by the project's path.
	///
	/// The destination and not the scheme, because they are chosen separately:
	/// picking `docscanner-ios` again should send it to the phone it went to
	/// last time rather than back to a simulator. Identifiers rather than names,
	/// since two simulators of the same model differ only by the runtime they
	/// have — and an identifier that no longer exists simply falls back to the
	/// default, which is what unplugging a phone should do.
	///
	/// Per project rather than per scheme, and `XcodeDestinationMemory` says
	/// why — including what becomes of a file that was written when this was
	/// keyed by scheme name.
	public var xcodeDestinations: [String: String]
	/// The breakpoints that were set, by file.
	///
	/// A breakpoint is a note about where to look, and the looking takes more
	/// than one sitting: closing a project to answer something else and coming
	/// back to a gutter swept clean is the sort of thing that teaches people to
	/// keep a scratch file of line numbers. Conditions come too — those are the
	/// ones that took thought.
	public var breakpoints: [String: [Breakpoint]]

	public init(
		files: [OpenFile] = [],
		activePath: String? = nil,
		terminals: [OpenTerminal] = [],
		isPanelVisible: Bool = false,
		tmuxWindow: String? = nil,
		subprojectPath: String? = nil,
		selectedConfiguration: String? = nil,
		xcodeDestinations: [String: String] = [:],
		breakpoints: [String: [Breakpoint]] = [:]
	) {
		self.xcodeDestinations = xcodeDestinations
		self.breakpoints = breakpoints
		self.files = files
		self.activePath = activePath
		self.terminals = terminals
		self.isPanelVisible = isPanelVisible
		self.tmuxWindow = tmuxWindow
		self.subprojectPath = subprojectPath
		self.selectedConfiguration = selectedConfiguration
	}

	public var isEmpty: Bool {
		files.isEmpty && terminals.isEmpty && subprojectPath == nil
			&& selectedConfiguration == nil && xcodeDestinations.isEmpty
			&& breakpoints.isEmpty && tmuxWindow == nil
	}

	/// Which window a project being left should be remembered in.
	///
	/// The window on screen, except when the project is being left *because* the
	/// terminal moved — a shell that changed checkout, or a tmux window somebody
	/// selected. Then the window showing belongs to the project being opened,
	/// not to the one being put away, and writing it down is how two projects
	/// come to hold each other's window.
	///
	/// Which does not stay a wrong note for later: each project then selects the
	/// other's window when it opens, selecting a window moves the shell, the
	/// shell moving switches the project, and the two swap places for ever a
	/// directory poll apart — about once a second, with nobody touching
	/// anything, and every switch reopening every editor tab. That is worth a
	/// function of its own with a test on it.
	public static func rememberedWindow(
		showing: String?,
		stored: String?,
		followingTerminal: Bool
	) -> String? {
		followingTerminal ? stored : showing
	}
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
