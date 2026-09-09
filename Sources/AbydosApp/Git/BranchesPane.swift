import AppKit
import AbydosKit

/// Local branches, remotes and tags, with checkout and the operations that go
/// with it.
///
/// A filter field at the top, because the useful case is a repository with more
/// branches than fit on screen — a list you have to scroll is one you would
/// rather have typed into.
final class BranchesPane: NSView {

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// Makes a branch where the stash was made and puts the work there.
	///
	/// What to offer when the check says the apply would conflict: applied on
	/// the commit it came from, it cannot.
	/// Opens the stash under the pointer as a page.
	var onReviewStash: ((GitStash.Entry) -> Void)?

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// Points origin somewhere, or gives the repository one.
	///
	/// A clone has one and nobody thinks about it; a repository made with `git
	/// init` has none, and everything that talks to a remote — pushing,
	/// opening it on GitHub — has nothing to say until it does.
	/// What to redraw as the remote is typed. Lives here because a text field
	/// needs an Objective-C target and the dialog is a local.
	var remoteFieldChanged: (() -> Void)?
	/// Something changed the repository: refresh the rest of the window.
	var onRepositoryChanged: (() -> Void)?
	/// Open a worktree as a project, which is the point of having one.
	var onOpenWorktree: ((URL) -> Void)?
	/// Somebody wants the commit page.
	var onOpenCommitPage: (() -> Void)?
	/// Opens the submodules overview, from the section that lists them.
	var onOpenEstate: (() -> Void)?
	/// Open these paths in the editor.
	var onOpenFiles: (([String]) -> Void)?
	/// Somebody wants the log, for a ref or for the repository.
	var onShowLog: ((String?) -> Void)?
	/// A change was selected, to show its diff.
	var onSelectChange: ((GitChange) -> Void)?

	let root: URL

	/// The work tree this pane is showing, so the window can tell whether the
	/// one it has is the one it wants rather than building another.
	var repositoryRoot: URL { root }

	var branches: [GitBranch] = []
	/// Where this repository lives on the web, when it lives anywhere: read
	/// from the remote, so GitHub and an Enterprise install are the same case.
	var forge: GitForge.Repository?
	/// The branch everything merges into, read alongside the rest.
	///
	/// It pins `main` to the top of `LOCAL`, which is what the branch pill in
	/// the titlebar already does — `BranchGrouping.arrange` pins the current
	/// branch and then the default. Two lists of the same branches in one
	/// window disagreeing about their order is the fault this avoids.
	var defaultBranch: String?
	/// Local branches whose work is already in the default branch.
	///
	/// Drawn dimmed rather than moved or hidden: where a branch sits in this
	/// list is how it is found, so a branch that moves when it merges is one
	/// somebody hunts for, and one that disappears vanishes at the moment it
	/// becomes safe to delete. Dimming says *nothing here* without saying
	/// *gone*.
	var mergedBranches: Set<String> = []
	/// The same, for the remote-tracking branches — keyed `origin/x`, because a
	/// remote row's own `name` has the remote stripped and `origin/x` and
	/// `upstream/x` would otherwise be one entry.
	///
	/// **Measured against the *remote's* default**, not the local one. The
	/// local `main` can be ahead of `origin/main`, and a branch merged into the
	/// one you are standing on is not yet merged where deleting it matters.
	var mergedRemoteBranches: Set<String> = []
	/// What origin points at, or nil when there is no origin at all.
	var remoteURL: String?
	/// The branch currently being pushed, if one is.
	///
	/// A push talks to another machine and can take a while over a slow link,
	/// and a list that looks exactly as it did is indistinguishable from a
	/// click that never landed.
	var pushingBranch: String?
	/// The branches a delete is working on, if one is running. Same reason as
	/// `pushingBranch`, and more of it: a delete that takes a worktree with it
	/// spends its seconds on `rm -rf`, not on git.
	var deletingBranches: Set<String> = []
	/// Set only while a delete is running against a remote, so a local delete
	/// of `x` cannot set `origin/x` spinning — the two rows share a name.
	var deletingRemote: String?
	/// Kept alive while the recreate sheet is up: it is the combo's delegate,
	/// and a delegate nobody holds is one nobody hears from.
	var tagSourceWatcher: TagSourceWatcher?
	var worktrees: [GitWorktree] = []
	var stashes: [GitStash.Entry] = []
	/// The tree as it stands, and what somebody has folded shut.
	var roots: [GitNode] = []
	/// **The working copy arrives shut.** Every change unrolled under the first
	/// row pushes the branches off the bottom of a column, and the question the
	/// tree is usually asked is "where am I" rather than "what have I changed"
	/// — which is what the commit page is for. The count on the row answers the
	/// other one without spending forty rows on it.
	var collapsedKeys: Set<String> = ["working"]
	/// Sections that start shut and are only open because somebody opened them.
	///
	/// **The inverse of `collapsedKeys`, and it needs to be.** That set is the
	/// positive way round — everything is open unless it was shut — which is
	/// right for a tree of your own branches and wrong for the two sections
	/// that are somebody else's account of things. `origin` is every branch
	/// anybody has pushed and `Tags` is every release there has ever been;
	/// unrolled, they are the bulk of the pane, and what somebody came to the
	/// refs tree for is nearly always above them.
	var openedKeys: Set<String> = []
	/// The keys of the sections that start shut, filled as the tree is built:
	/// a remote's name is whatever somebody called it, so the set cannot be
	/// written down in advance.
	var sectionsThatStartShut: Set<String> = []
	/// Set while expansion is being put back after a rebuild, so the pane's own
	/// work is not mistaken for somebody's — the rule `ChangesPane` keeps.
	var isRestoring = false
	var filterText = ""

	/// What has changed in the working copy, and the trees drawn from it.
	///
	/// **The first row of the tree, and a thing of the same kind as the rest.**
	/// The working copy is the commit that has not happened yet, which is why
	/// it sits above the stashes and the branches rather than in a pane of its
	/// own with a button of its own.
	var working = GitWorkingCopyStatus()
	var unstagedRoots: [GitChangeNode] = []
	var stagedRoots: [GitChangeNode] = []
	/// What a wholly untracked directory turned out to hold, by path.
	///
	/// The rows are rebuilt from scratch on every filesystem event, so an open
	/// folder's insides are new objects each time and have to be put back before
	/// the tree is built — otherwise a folder somebody is reading closes under
	/// them. Asked for again afterwards, because the directory may have gained a
	/// file since.
	var untrackedContents: [String: [GitChangeNode]] = [:]
	/// **Shut to begin with.** Every change in the repository unrolled under
	/// the first row pushes the branches off the bottom of a 300 pt column, and
	/// the question the tree is usually asked is not "what have I changed" —
	/// that is what the commit page is for — but "where am I". The count on the
	/// row answers the other question without spending forty rows on it.
	/// Sections somebody has folded away, by title.
	/// Change folders somebody has folded, by side and path.
	/// Which of the two sides is open. Both, until somebody says otherwise.

	/// Stashes somebody has opened, by the commit each one is.
	///
	/// By commit and not by `stash@{n}`, because dropping one renumbers every
	/// entry after it and a set of positions would open the wrong rows.
	/// What each opened stash holds, and whether it would still go back.
	///
	/// Read when a stash is opened rather than on every refresh: `wouldApply`
	/// captures the working copy and merges three trees, which is nothing to do
	/// once and too much to do for every entry on every filesystem event.
	var stashFiles: [String: [GitCommitFile]] = [:]
	var stashApplies: [String: GitStash.Applicability] = [:]

	/// Folders somebody has folded shut, by section and prefix.
	///
	/// Keyed by both because `feature/` exists under Local and under every
	/// remote that has one, and folding the local one should not fold theirs.
	/// Held the positive way round — the negative of `ChangesPane`'s rule, and
	/// for the opposite reason: a refs tree that opened everything would put
	/// forty branches on screen to show you the one you are on, where a changes
	/// tree that folded anything would hide work that has just appeared.

	/// Said when a merge has stopped, and nothing else on screen says it.
	var conflictBanner: OperationBanner!
	var conflictHeight: NSLayoutConstraint!
	var conflictPaths: [String] = []
	/// Everything the current stop was waiting on when it was first read.
	///
	/// **Git forgets, so the pane has to remember.** A path stops being
	/// unmerged the moment it is staged, so a list built from `paths(in:)`
	/// alone shrinks instead of ticking, and `2 of 3 resolved` cannot be said
	/// at all. Cleared when the operation ends or moves to the next commit —
	/// a rebase that carries on is a new stop with its own set.
	var conflictsThisStop: Set<String> = []
	var conflictStopAt: Int?
	/// What git is in the middle of, as of the last refresh. The banner's
	/// verbs are its verbs, so they are only offered while this is set.
	var currentOperation: GitConflicts.Operation?
	/// The filter, when it is open. Nil is the ordinary state.
	var filterStrip: PaneFilterStrip?
	/// The repository, drawn as the first row and pinned above the scrolling
	/// ones — see `RepositoryRowView` for why it does not scroll.
	var repositoryRow: RepositoryRowView!
	var tableView: BranchesOutlineView!
	/// Where this branch stands against its remote, for what the counter says.
	var trafficState: GitPush.State?
	/// When the remote was last asked, read with the traffic state it dates.
	var lastFetchedAt: Date?
	/// The submodules, and what each of them has to report. Empty for a
	/// repository that holds none, which is most of them.
	let submodules: EstateChanges
	var estateRows: [GitEstateRow] = []
	/// Where the head is when it is not on a branch, and what git has stopped
	/// in the middle of — nil when there is nothing unusual to say. Drawn on
	/// the repository row and as a row of its own at the top of Local.
	var headNotice: String?

	enum Row {
		case header(String)
		/// The working copy, and how much has changed in it.
		case workingCopy(changed: Int)
		/// Staged or unstaged, and how many are on that side.
		case side(String, staged: Bool, count: Int)
		/// One changed file, or a folder of them.
		case change(GitChangeNode, staged: Bool, depth: Int)
		/// A prefix several branches share. `key` is the section and the prefix
		/// together, which is what folding is remembered by; `display` is what
		/// the row says, which for a folded chain is more than one component.
		case folder(key: String, display: String, count: Int, depth: Int)
		/// A branch, how far it is indented, and what it says — which is not
		/// `branch.name`: under `feature/`, the row reads `tags`.
		case branch(GitBranch, depth: Int, display: String)
		case worktree(GitWorktree)
		case stash(GitStash.Entry)
		/// One file inside an opened stash.
		case stashFile(GitStash.Entry, GitCommitFile)
		/// Where the head is when it is on no branch, and what git has stopped
		/// in the middle of. A row rather than a decoration because that is
		/// what the rest of this section is: `for-each-ref` marks nothing
		/// current while the head is detached, so without this the list of
		/// local branches simply has no tick anywhere in it and says nothing
		/// about where you are.
		case detachedHead(String)
		/// One submodule, and everything the overview knows about it.
		case submodule(GitEstateRow)

	}

	/// One row of the tree, and what hangs off it.
	///
	/// **A real tree, drawn by `NSOutlineView`.** This was a flat table with
	/// indentation, chevrons, arrow keys, page keys and expansion state all
	/// written out by hand — and every one of them was reported broken, because
	/// each was a re-implementation of something AppKit already does correctly
	/// and the project tree and the changes tree both already use. The rows are
	/// the same; what draws them is not.
	final class GitNode {
		/// Stable across a rebuild, which is how expansion survives one: the
		/// tree is thrown away and built again on every filesystem event, and
		/// identity is the only thing that does not survive that.
		let key: String
		let row: Row
		fileprivate(set) var children: [GitNode] = []

		init(key: String, row: Row) {
			self.key = key
			self.row = row
		}

		func add(_ child: GitNode) { children.append(child) }

		func insert(_ child: GitNode, at index: Int) {
			children.insert(child, at: min(index, children.count))
		}
	}

	init(root: URL) {
		self.root = root
		self.submodules = EstateChanges(root: root)
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
		beginFirstRead()
		refresh()

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(refresh),
			name: .abydosRepositoryChanged,
			object: nil
		)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Shown until the first read comes back — see `ChangesPane.activity` for
	/// why it is the first only.
	var activity: PaneActivityView?

	private func beginFirstRead() {
		activity = PaneActivityView.install(over: self, message: "Reading branches…")
	}

	func finishFirstRead() {
		activity?.finish()
		activity = nil
	}
	deinit { NotificationCenter.default.removeObserver(self) }
}
