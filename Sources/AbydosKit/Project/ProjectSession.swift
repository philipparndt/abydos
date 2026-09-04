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
		///
		/// Nothing to do with `previewMode` below, which is the pane: this is the
		/// italic tab a single click opens. The two names have collided since
		/// before either meant anything to the other, and 0454 was written partly
		/// to say so out loud.
		public var isPreview: Bool
		/// How the tab was being shown: the source, the rendered form, or one of
		/// the two splits.
		///
		/// Per tab and not per file kind, which is a decision rather than an
		/// oversight: somebody who always wants a `.scad` split is asking for a
		/// preference, and this answers that question correctly only for files
		/// they have opened before. See 0454, which leaves the preference for
		/// whoever wants it.
		///
		/// Nil for a session written before this was recorded, and that must not
		/// be read as `.source`: an old session has no opinion, and the file kind's
		/// own default is the right answer for it. Every tab open today would
		/// otherwise come back as text once, and blame the change that added this.
		public var previewMode: PreviewMode?
		/// Where the divider was in a split, as a fraction of the pane.
		///
		/// A fraction rather than a position, because the pane it divides is not
		/// the size it was: another window, another screen, a different sidebar
		/// width. Nil when the tab was not split, or when the split was never laid
		/// out and so never had a divider anywhere in particular.
		public var dividerFraction: Double?

		public init(
			path: String,
			line: Int = 1,
			isPreview: Bool = false,
			previewMode: PreviewMode? = nil,
			dividerFraction: Double? = nil
		) {
			self.path = path
			self.line = line
			self.isPreview = isPreview
			self.previewMode = previewMode
			self.dividerFraction = dividerFraction
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
		/// Whether this was the one in front.
		///
		/// Four terminals came back and the first was showing, whichever had
		/// been in front — the names and the directories travelled and the
		/// choice between them did not. Here rather than as an index on the
		/// session, for the reason the tmux window is an id: the list is
		/// rebuilt, and one that fails to start shifts every index after it.
		public var isInFront: Bool

		public init(
			name: String, directory: String? = nil,
			isRenamed: Bool = false, isInFront: Bool = false
		) {
			self.name = name
			self.directory = directory
			self.isRenamed = isRenamed
			self.isInFront = isInFront
		}
	}

	/// What somebody folded and unfolded in one tree.
	///
	/// **Two lists and not one, because the trees do not agree about what an
	/// absent key means.** A refs tree arrives open and records what was *shut*
	/// — `working` is shut on arrival and the rest is not — while `origin` and
	/// `Tags` arrive shut and record what was *opened*, since unrolled they are
	/// the bulk of the pane. The changes tree wants to arrive open for the same
	/// reason the refs tree does, and its untracked directories are positive
	/// again because opening one costs a git call. Merged into a single list of
	/// "expanded things", every one of those rules would have to be guessed at
	/// from the key.
	public struct TreeFolds: Equatable, Sendable {
		/// Keys somebody shut that would otherwise be open.
		public var shut: [String]
		/// Keys somebody opened that would otherwise be shut.
		public var opened: [String]

		public init(shut: [String] = [], opened: [String] = []) {
			self.shut = shut
			self.opened = opened
		}

		public var isEmpty: Bool { shut.isEmpty && opened.isEmpty }

		/// At most this many keys per tree, nearest the root first.
		///
		/// A tree somebody has walked deep into holds thousands of unfolded
		/// folders, and this file is read on every project switch. A fold near
		/// the root is the shape somebody arranged; one twelve levels down is
		/// where they happened to end up. Ruled out: no bound, which is how a
		/// `.abydos` file becomes a megabyte of directory names.
		public static let cap = 500

		/// The same folds, bounded, shallowest first.
		///
		/// Depth is counted in separators, which is what every key here is made
		/// of — `folder:a/b`, `section:origin`, a path relative to the project.
		/// Sorted after trimming so the file does not churn on a set's order.
		public var bounded: TreeFolds {
			TreeFolds(shut: Self.bound(shut), opened: Self.bound(opened))
		}

		private static func bound(_ keys: [String]) -> [String] {
			guard keys.count > cap else { return keys.sorted() }
			return keys
				.sorted { left, right in
					let depths = (
						left.filter { $0 == "/" }.count, right.filter { $0 == "/" }.count
					)
					return depths.0 == depths.1 ? left < right : depths.0 < depths.1
				}
				.prefix(cap)
				.sorted()
		}
	}

	/// A commit message somebody was in the middle of writing.
	///
	/// **The most expensive text in the app to lose.** It is written once, from
	/// a diff that has just been read, and typing it again means reading the
	/// diff again. Both halves, because the description is where the *why* goes
	/// and is the expensive one — carrying only the summary is what the
	/// sidebar-to-page hand-off did, and it is not carrying the message.
	public struct ComposedMessage: Equatable, Sendable {
		public var summary: String
		public var description: String

		public init(summary: String, description: String) {
			self.summary = summary
			self.description = description
		}

		/// Nothing typed is nothing to remember, so an empty pair is not
		/// written and does not make a session non-empty.
		public var isEmpty: Bool {
			summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
				&& description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		}
	}

	/// A page that was open, and what it was showing.
	///
	/// A page was left out of a session on the argument that "a path like
	/// `/ideai/page/launch` is nothing to reopen" — true of the synthetic URL
	/// and false of the page, which is a view over a repository with a scope
	/// and a selection, opened on purpose.
	///
	/// `showing` is what the identifier does not settle: the log page's ref,
	/// its path scope, the stash page's ref. A stash by *ref* rather than by
	/// index, because an index is a different commit after one `git stash push`.
	public struct OpenPage: Equatable, Sendable {
		public var identifier: String
		public var showing: [String: String]

		public init(identifier: String, showing: [String: String] = [:]) {
			self.identifier = identifier
			self.showing = showing
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
	/// Which files of which pull request have been read, and what each tick was
	/// made against.
	///
	/// Keyed by the pull request's number as a string, then by path, with the
	/// token the tick was recorded at — the hash of that file's diff at the head
	/// it was read at. The token has to travel or the ticks cannot be checked
	/// when the page opens again, and a set of ticks that cannot be checked is
	/// exactly the false record this whole feature is against.
	///
	/// A number as a string because this is written as JSON, whose keys are.
	///
	/// Additive: absent from every session written before it existed, which
	/// reads as nobody having read anything — the safe direction.
	public var reviewTicks: [String: [String: String]]
	/// Which checkouts were made to read a pull request, by path.
	///
	/// The mark `ReviewCheckouts` holds, written down so tomorrow's window knows
	/// too. Not in `.git`, for the reason that type gives: it is this program's
	/// opinion about a directory rather than a fact about the repository.
	public var reviewCheckouts: [String: Int]
	/// The commit message being composed, or nil where nothing was typed.
	///
	/// Additive: absent from every session written before it existed, which
	/// reads as nothing having been typed — the safe direction.
	public var composedMessage: ComposedMessage?
	/// The pages that were open, in the order they were in.
	public var pages: [OpenPage]
	/// What was folded and unfolded in each tree, by the tree's own name —
	/// `refs`, `changes.unstaged`, `changes.staged`, `tree`.
	///
	/// Additive: absent from every session written before it existed, which
	/// reads as nothing having been folded, and the panes then arrive the way
	/// they always did. That is what makes this safe to add: the arrival
	/// defaults live in the panes and are not copied here.
	public var folds: [String: TreeFolds]
	/// Which sidebar tool was in front, by its own name.
	///
	/// A window that lived in the git tool came back on the file tree, every
	/// time. Nil for a session written before this existed, and for one where
	/// nothing was chosen.
	public var sidebarTool: String?

	public init(
		files: [OpenFile] = [],
		activePath: String? = nil,
		terminals: [OpenTerminal] = [],
		isPanelVisible: Bool = false,
		tmuxWindow: String? = nil,
		subprojectPath: String? = nil,
		selectedConfiguration: String? = nil,
		xcodeDestinations: [String: String] = [:],
		breakpoints: [String: [Breakpoint]] = [:],
		reviewTicks: [String: [String: String]] = [:],
		reviewCheckouts: [String: Int] = [:],
		composedMessage: ComposedMessage? = nil,
		pages: [OpenPage] = [],
		folds: [String: TreeFolds] = [:],
		sidebarTool: String? = nil
	) {
		// Bounded here rather than at each caller: there are two places a
		// session is captured and both would have to remember.
		self.folds = folds.compactMapValues { $0.isEmpty ? nil : $0.bounded }
		self.sidebarTool = sidebarTool
		self.xcodeDestinations = xcodeDestinations
		self.breakpoints = breakpoints
		self.reviewTicks = reviewTicks
		self.reviewCheckouts = reviewCheckouts
		self.composedMessage = composedMessage
		self.pages = pages
		self.files = files
		self.activePath = activePath
		self.terminals = terminals
		self.isPanelVisible = isPanelVisible
		self.tmuxWindow = tmuxWindow
		self.subprojectPath = subprojectPath
		self.selectedConfiguration = selectedConfiguration
	}

	/// **The folds and the tool are not counted.** A session holding nothing
	/// but the shape of an empty pane is an empty session: the file is removed
	/// rather than written, which is what keeps a `.abydos` from appearing
	/// beside a project somebody only looked at. Nothing is lost by it — with
	/// no files and no terminals there is no arrangement to come back to.
	public var isEmpty: Bool {
		files.isEmpty && terminals.isEmpty && subprojectPath == nil
			&& selectedConfiguration == nil && xcodeDestinations.isEmpty
			&& breakpoints.isEmpty && tmuxWindow == nil && reviewTicks.isEmpty
			&& reviewCheckouts.isEmpty && pages.isEmpty
			&& (composedMessage?.isEmpty ?? true)
	}

	/// The same session with everything that belongs to a project taken out.
	///
	/// What a folder in no working copy remembers: the files, and where the
	/// caret was in each. A folder is not set up to do anything, so there is no
	/// terminal it came with, no tmux window it was left in, no configuration
	/// the play button was pointing at, and no subproject — a folder has no
	/// parts. The breakpoints go too: they are lines in files a debugger was
	/// going to stop at, and there is nothing here to run. So do the commit
	/// message and the git pages: a folder in no working copy has nothing to
	/// commit and no history to page through.
	/// The folds, the tool and the terminal in front go with the rest. Every
	/// folder in no working copy shares one session file, so a fold keyed by a
	/// path relative to one of them names nothing in the next — and a folder
	/// has no git tool to have been in front of.
	public var filesOnly: ProjectSession {
		ProjectSession(files: files, activePath: activePath, isPanelVisible: isPanelVisible)
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
