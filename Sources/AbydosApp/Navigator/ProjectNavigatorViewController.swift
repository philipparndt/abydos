import AppKit
import QuickLookUI
import AbydosKit

/// The project tree from image 1: a bold root row carrying the home-relative
/// path, then lazily-loaded directories with type icons and VCS colouring.
final class ProjectNavigatorViewController: NSViewController {

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// A rebuild that arrived while a name was being edited.
	///
	/// The tree rebuilds on every filesystem event, and `reloadData()` lays
	/// fresh row views over the field standing on the row — which does not
	/// remove it, so the box vanished while still taking the keystrokes being
	/// typed into it. Worse than it sounds: the app writes `.abydos/session.json`
	/// itself, so renaming anything beside it raced against the app's own event
	/// and the field survived or disappeared depending on the timing.
	///
	/// Renaming is short and deliberate, so the rebuild waits for it. Rebuilding
	/// under an open field would move the row out from under it anyway.
	///
	/// The same for a new row and more so: the placeholder is not on disk, so a
	/// rebuild that asked the file system what is in the folder would take the
	/// row away entirely, field and all, with a half-typed name in it.
	var deferredRebuild = false

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// What that field is doing, and what it needs to undo if it is abandoned.
	var editing: NameEdit?
	/// The row that stands for a file which does not exist yet.
	///
	/// A `FileNode` like any other, handed to the outline view by the data
	/// source and belonging to nothing on disk. **It sits at the end of its
	/// folder's children and stays there while the name is typed**, rather than
	/// sorting into place letter by letter — see `beginNew` for why.
	var placeholder: (node: FileNode, parent: FileNode)?

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// The rows a trash has taken and the disk has not yet.
	///
	/// `DoomedRows` holds the rule and its tests; this is the tree's copy, asked
	/// by the one walk every row goes through and cleared by the trash's
	/// completion.
	var doomedRows = DoomedRows()
	/// How long the trash took to answer, and what the machine was doing while
	/// it did.
	///
	/// The number this change exists to make invisible: it is still spent, and a
	/// driven run reads it here so that "the row goes at once" is a claim about
	/// the row and not about a fast trash. A duration with no load beside it
	/// cannot be argued with afterwards, so both are one sentence.
	var trashTimeForTesting = "nothing has been trashed"

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// The two items that belong to the sessions root and the rows under it.
	weak var resumeItem: NSMenuItem?
	weak var revealSessionItem: NSMenuItem?

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// The folds this project was left with, handed in by whoever opens it.
	///
	/// Taken here rather than applied from outside afterwards, because
	/// `load(project:)` expands the root *alone* and anything applied before it
	/// is undone. Nil for a project with nothing recorded, and then the tree
	/// arrives exactly as it always did.
	var foldsToRestore: ProjectSession.TreeFolds?
	/// Reads the Claude Sessions root, and redraws only if it came out
	/// different.
	///
	/// **Read here and not watched.** `/tmp/claude-<uid>` is written by every
	/// agent on the machine, several times a second while one is working, and a
	/// watcher on it would rebuild a root nobody is looking at for somebody
	/// else's session. It is read when the tree is read, which is what
	/// *Dependencies* does.
	/// The last cheap read, by session id, and the last walk's numbers.
	///
	/// Kept so that a refresh caused by a session *starting* does not blank every
	/// row's size and walk six thousand files again to find the same numbers.
	var cheapSessions: [String: AgentSession] = [:]
	var measuredSessions: [String: AgentSession] = [:]
	/// At most one walk at a time. A second is not queued: when one lands it
	/// reads again, and anything that arrived meanwhile is picked up then.
	var walkingSessions = false
	/// How often the sessions root has been rebuilt, for the `place` step to
	/// print beside the scroll position.
	var sessionRebuildsForTesting = 0
	/// Whether the dependency walk is out, and what asked to be revealed while
	/// it was.
	///
	/// **This is the race the old synchronous read was buying off.** `reveal`
	/// asks the Dependencies section first, because a file under
	/// `.build/checkouts/Cadova` is reachable both ways and only the section can
	/// say which package it is. With the read in flight there is no section to
	/// ask, so the reveal would land in `.build` — the one row that cannot answer
	/// the question. Rather than hold the window still until the walk finishes,
	/// the reveal is done again when it lands, and the section wins then.
	var isReadingDependencies = false
	var deferredReveals: [URL] = []

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// The Compare submenu and its two entries, held so `menuNeedsUpdate` can
	/// prune them to the row's truth: an untracked file has no last commit to
	/// compare against and no history to show.
	weak var compareMenu: NSMenu?
	weak var compareAgainstItem: NSMenuItem?
	weak var compareHistoryItem: NSMenuItem?
	weak var compareWithItem: NSMenuItem?
	weak var compareSelectedItem: NSMenuItem?
	var ignoreSuggestions: [GitIgnore.Suggestion] = []
	weak var ignoreField: NSTextField?

	var isReadingIgnored = false
	/// The submenu under "New", filled in as it is about to be shown.
	var newMenu: NSMenu?
	/// The submenu under "Export", which is only ever shown over a diagram.
	var exportMenu: NSMenu?
	/// The kinds this project is made of, counted once and kept.
	///
	/// Counted lazily and not at open: walking a project to fill in a menu
	/// nobody has asked for yet is work for nothing. Dropped when the tree
	/// changes, so the first file of a new kind shows up in the menu after it
	/// exists rather than after the project is reopened.
	var fileKinds: [NewFileKind]?
	/// Whether `fileKinds` is known to be behind the project.
	///
	/// Separate from throwing the list away, because the menu is not allowed to
	/// wait for a new one: the last answer is shown while a fresh one is worked
	/// out behind it. A project does not change what kinds of file it is made of
	/// very often, so the shown answer is almost always the right one, and when
	/// it is not it is right a moment later.
	var fileKindsAreStale = true
	/// The recount in flight, so a burst of filesystem events schedules one.
	var fileKindsTask: Task<Void, Never>?
	var isReadingGitStatus = false
	var wantsAnotherGitStatus = false
	var hasScheduledGitStatusRefresh = false

	/// The tree's own undo stack, and nothing to do with the editor's.
	///
	/// **Two stacks, and focus decides which**, which is the whole risk in this
	/// feature: a ⌘Z aimed at a stray character that put back a folder somebody
	/// deliberately trashed ten minutes ago would be far worse than no undo at
	/// all. The responder chain is what keeps them apart, and it does so by
	/// construction rather than by anything checking.
	///
	/// `undo:` is sent from the Edit menu with no target, so AppKit walks the
	/// chain from the key window's first responder and stops at the first object
	/// that answers to it. When the keyboard is in the editor that is `CodeView`,
	/// which has its own `UndoTree` and never sees this manager. When it is in
	/// the tree that is `NavigatorOutlineView`, which is not in the editor's
	/// chain at all — the two panes are siblings, not ancestors. So neither can
	/// reach the other's undo however the keys are pressed.
	///
	/// This is deliberately *not* the window's undo manager, which is the one
	/// stack both panes would share, and is where the rename field's text undo
	/// goes.
	let fileUndo = UndoManager()
	/// What the manager holds on to, which must not be this controller.
	///
	/// `registerUndo(withTarget:handler:)` keeps a strong reference to its
	/// target, so registering `self` would leave the navigator — and the whole
	/// tree behind it — alive after its window had gone. The handler is given
	/// the target and reaches the navigator weakly through it.
	lazy var undoTarget: FileUndoTarget = {
		let target = FileUndoTarget()
		target.navigator = self
		return target
	}()
	/// Paths to select once the tree has caught up with the file system.
	///
	/// Creating a folder does not refresh the tree directly — the watcher does,
	/// a moment later — so the selection has to wait for the node to exist.
	///
	/// A list rather than one path, since 0436: a drop or a paste puts several
	/// files somewhere at once, and following one of them would be the same
	/// shrinking-selection fault `TreeSelection` exists for. Everything that
	/// makes one thing hands in a list of one and is unchanged.
	var pendingReveal: [URL] = []
	/// The field standing in for a row's label while its name is being edited.
	var nameField: NSTextField?
	/// `focusEditor` is true when the user committed to the file (Return or a
	/// double-click) rather than merely highlighting it.
	var onSelectFile: ((URL, _ focusEditor: Bool) -> Void)?
	/// A file should open as bytes, whatever it is: the tree's door into the
	/// hex editor, beside the notice's button and the tab's menu.
	var onOpenAsHex: ((URL) -> Void)?
	/// A file row's *Blame*: open it and show who last touched each line.
	var onBlame: ((URL) -> Void)?
	/// An entry inside a shown archive should open, from the file the cache
	/// holds it in, read only and named for where it came from; the flag says
	/// whether the tab is pinned.
	var onOpenArchiveEntry: ((URL, ArchiveOrigin, Bool) -> Void)?
	/// The archives somebody asked to see into. See `+Archives`.
	let archives = ArchiveSupport()
	/// Asked to open a terminal in the given directory.
	var onOpenTerminal: ((URL) -> Void)?
	/// Asked to work on part of the project, or on the whole of it again.
	var onOpenSubproject: ((URL) -> Void)?
	var onLeaveSubproject: (() -> Void)?
	/// Asked to show a 3D model in the external viewer.
	var onPreviewModel: ((URL) -> Void)?
	/// Compare ▸ Against Last Commit on a file row.
	var onCompareFile: ((URL) -> Void)?
	/// Compare Selected over two rows of one kind: the first selected is A.
	var onCompareSelected: (([URL]) -> Void)?
	/// Compare ▸ With… on a row: the other side is asked for.
	var onCompareWith: ((URL) -> Void)?
	/// Compare ▸ History… on a file row.
	var onShowFileHistory: ((URL) -> Void)?
	/// Something under the project root changed on disk.
	///
	/// Carries the batch rather than announcing that *something* happened: what
	/// was written decides whether a listener has any work to do, and a listener
	/// that cannot tell a Java source from a language server's `.classpath` has
	/// to assume the worst on every event. 0446 is the bill for that assumption.
	var onFilesChanged: ((FileSystemChange) -> Void)?
	/// How many files the working copy has changed, whenever that is read.
	///
	/// The tree reads `git status` already, on every watcher event; anything
	/// else that wants the number should hear it from here rather than run its
	/// own.
	var onChangeCount: ((Int) -> Void)?
	/// What the editor is showing, so the tree can be asked to find its way back
	/// to it after browsing somewhere else.
	var currentEditorFile: (() -> URL?)?

	/// True while the tree is moving its own selection — restoring it after a
	/// reload, or following the editor's tab — so it does not call back and
	/// reopen the file it was just told about.
	///
	/// Everything else opens: arrowing through the tree shows each file it lands
	/// on, provisionally, the way a click does. Moving the highlight without
	/// showing anything is what made the tree look broken.
	var isSelectingSilently = false

	var project: Project?
	var rootNode: FileNode?
	/// What the project depends on, as the second root beside the tree.
	///
	/// Nil for a project of no recognised kind, and then there is no section at
	/// all — an empty *Dependencies* row is exactly the "this project has none"
	/// that item 508 was filed to avoid, and a project with no build system in
	/// it genuinely has nothing to say.
	var dependencies: DependencyTree?
	/// The toolchains somebody has been into from this window.
	///
	/// Not read on open and deliberately so: a toolchain is not declared by
	/// anything, so the only honest way to know *which* one this project uses
	/// is to be told, and what tells us is the path a language server answers a
	/// definition with. So the list starts empty, grows the first time a symbol
	/// is followed into a compiler's own sources, and is thrown away with the
	/// window. See `ToolchainSources`.
	var toolchains: [Toolchain] = []
	/// What past agent sessions left behind for this project, as a third root.
	///
	/// Nil when there is nothing — the rule *Dependencies* keeps, for the reason
	/// item 508 was filed: a permanent empty row is worse than no row. Unlike a
	/// toolchain, whether a session left anything is knowable without being
	/// told, so this can be read on open.
	var sessions: SessionNode?
	/// When the section was last read.
	///
	/// A burst too large for FSEvents to name file by file — a build, a
	/// checkout — arrives as "scan this subtree", and reading the section on
	/// every one of those would walk the project's subprojects four times a
	/// second for as long as the build ran. A named write to a manifest or a
	/// lock file is always honoured; an unnamed burst waits.
	var lastDependencyRead = Date.distantPast
	/// The folder being worked on, marked in the tree so it is obvious which
	/// part of a repository the run button belongs to.
	var subprojectRoot: URL?
	var watcher: FileSystemWatcher?
	var outlineView: NavigatorOutlineView!
	var headerView: NavigatorHeaderView!

	/// Puts the pointer on one of the header's three buttons and says whether
	/// it lit and what it would tell somebody, for a driven run.
	func hoverHeaderActionForTesting(_ name: String) -> String {
		headerView?.hoverActionForTesting(name) ?? "no header"
	}
	private var headerTopConstraint: NSLayoutConstraint!
	var headerHeightConstraint: NSLayoutConstraint!
	var gitRoot: URL?

	/// The one column follows the view's width.
	///
	/// Left to itself an outline column stays as wide as the widest name it has
	/// been given, so a longer name truncates with an ellipsis while empty pane
	/// sits beside it — and anything measuring against the cell, such as the
	/// rename field, is cut to the same wrong width. Most visible at a large
	/// zoom, where the names grow and the column does not.
	override func viewDidLayout() {
		super.viewDidLayout()
		guard let column = outlineView?.tableColumns.first else { return }
		let width = outlineView.bounds.width
		guard width > 0, abs(column.width - width) > 0.5 else { return }
		column.width = width
	}

	/// Distance from the top of the window to the "Project" header.
	func setTopInset(_ inset: CGFloat) {
		headerTopConstraint.constant = inset + 4
	}

	// MARK: - View

	override func loadView() {
		let container = ColoredView(color: Theme.current.sidebarBackground)
		// The closure its sibling containers in `MainWindowController+Layout`
		// were already given, and this one was not. Without it the view puts
		// the colour it was built with back on every display pass, so anything
		// that repaints it has to know which colour it was.
		container.colourSource = { Theme.current.sidebarBackground }

		let header = NavigatorHeaderView()
		header.onCollapseAll = { [weak self] in self?.collapseAll() }
		header.onSelectOpenFile = { [weak self] in self?.selectFileInEditor() }
		header.onToggleCompactPackages = { [weak self] in self?.toggleCompactPackages() }
		header.isCompactingPackages = Settings.shared.compactsPackages
		headerView = header
		let outline = NavigatorOutlineView()
		outline.headerView = nil
		outline.backgroundColor = Theme.current.sidebarBackground
		// `.none` would suppress drawSelection(in:) entirely; `.regular` keeps the
		// callback so TreeRowView can draw the rounded highlight itself.
		outline.selectionHighlightStyle = .regular
		outline.rowSizeStyle = .custom
		outline.rowHeight = Theme.current.scaled(24)
		outline.intercellSpacing = NSSize(width: 0, height: 0)
		outline.indentationPerLevel = Theme.current.scaled(14)
		outline.autoresizesOutlineColumn = false
		outline.gridStyleMask = []
		outline.usesAutomaticRowHeights = false
		// ⇧-click a run of files, ⌘-click a handful of them, and ⌘A takes
		// everything the tree is showing — which is everything *visible*,
		// because an unexpanded folder's children are not rows and have not
		// been read off the disk. Trashing four files is one gesture now.
		outline.allowsMultipleSelection = true
		outline.focusRingType = .none

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
		column.resizingMask = .autoresizingMask
		outline.addTableColumn(column)
		outline.outlineTableColumn = column

		outline.dataSource = self
		outline.delegate = self
		// Files drag out as URLs: onto the terminal, or into another app. Copy
		// rather than move for another *application* — dragging a file out of
		// the tree should never be a way to lose it from the project.
		//
		// Inside this app the tree is also its own destination, and there a bare
		// drag moves, so `.move` has to be offered: `validateDrop` returning an
		// operation the source never permitted is a drop that quietly does
		// nothing. Which of the two a given drag becomes is decided in
		// `validateDrop`, not here.
		outline.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
		outline.setDraggingSourceOperationMask(.copy, forLocal: false)
		// And the other side of it, which is what 0436 was for: rows can be
		// dropped back into the tree, and so can files from the Finder or from
		// any other application that puts a file URL on the drag board.
		outline.registerForDraggedTypes([.fileURL])
		outline.target = self
		outline.doubleAction = #selector(rowDoubleClicked)
		outline.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? false }
		// Asked for rather than handed over: the panel reads this every time it
		// reloads, and a list captured when the panel opened would go stale the
		// moment ↑ moved the selection underneath it.
		outline.quickLookFiles = { [weak self] in self?.quickLookSelection() ?? [] }
		// The absolute path, which is what "copy path" has always meant here and
		// what a terminal, a Finder window or another program can be given. The
		// menu still offers the relative one, which is the one a commit message
		// or an import wants.
		//
		// Several rows join with newlines, in the order they appear in the tree
		// rather than the order they were clicked: what is being copied is a
		// list of files, and the tree's order is the one that reads.
		//
		// Files rather than a string, since 0436: the text on the board is the
		// same one path a line it always was, and the same ⌘C now pastes as a
		// file in the Finder and back into this tree.
		outline.copyFiles = { [weak self] in
			self?.selectedNodes().map(\.url) ?? []
		}
		outline.onPaste = { [weak self] operation in self?.pasteIntoSelection(operation) }
		// Files, or a picture and no file — a screenshot, which ⌘V writes as a
		// PNG. Asked of the board's types, not its bytes: this runs every time
		// the Edit menu validates.
		outline.canPaste = { !FilePasteboard.files().isEmpty || FilePasteboard.hasPicture() }
		// ⌘Z, which reaches the outline view and stops there. The Undo section
		// below says why that one door is the whole of how the tree's stack and
		// the editor's stay apart, and why the door closes during a rename.
		outline.fileUndoManager = { [weak self] in self?.fileUndoManager }
		outline.menu = makeContextMenu()
		outlineView = outline

		let scrollView = NSScrollView()
		scrollView.documentView = outline
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = false
		scrollView.autohidesScrollers = true
		scrollView.automaticallyAdjustsContentInsets = false

		container.addSubview(header)
		container.addSubview(scrollView)
		header.translatesAutoresizingMaskIntoConstraints = false
		scrollView.translatesAutoresizingMaskIntoConstraints = false

		// Set from the window's actual titlebar height rather than hardcoded.
		headerTopConstraint = header.topAnchor.constraint(equalTo: container.topAnchor, constant: 44)
		headerHeightConstraint = header.heightAnchor.constraint(equalToConstant: Theme.current.scaled(30))

		NSLayoutConstraint.activate([
			headerTopConstraint,
			header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			headerHeightConstraint,

			scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
			scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
		])

		view = container

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(repositoryChanged(_:)),
			name: .abydosRepositoryChanged,
			object: nil
		)
	}
}
