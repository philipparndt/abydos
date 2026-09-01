import AppKit
import QuickLookUI
import AbydosKit

/// The project tree from image 1: a bold root row carrying the home-relative
/// path, then lazily-loaded directories with type icons and VCS colouring.
final class ProjectNavigatorViewController: NSViewController {
	/// `focusEditor` is true when the user committed to the file (Return or a
	/// double-click) rather than merely highlighting it.
	var onSelectFile: ((URL, _ focusEditor: Bool) -> Void)?
	/// Asked to open a terminal in the given directory.
	var onOpenTerminal: ((URL) -> Void)?
	/// Asked to work on part of the project, or on the whole of it again.
	var onOpenSubproject: ((URL) -> Void)?
	var onLeaveSubproject: (() -> Void)?
	/// Asked to show a 3D model in the external viewer.
	var onPreviewModel: ((URL) -> Void)?
	/// Compare ▸ Against Last Commit on a file row.
	var onCompareFile: ((URL) -> Void)?
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
	private var isSelectingSilently = false

	private var project: Project?
	private var rootNode: FileNode?
	/// What the project depends on, as the second root beside the tree.
	///
	/// Nil for a project of no recognised kind, and then there is no section at
	/// all — an empty *Dependencies* row is exactly the "this project has none"
	/// that item 508 was filed to avoid, and a project with no build system in
	/// it genuinely has nothing to say.
	private var dependencies: DependencyTree?
	/// The toolchains somebody has been into from this window.
	///
	/// Not read on open and deliberately so: a toolchain is not declared by
	/// anything, so the only honest way to know *which* one this project uses
	/// is to be told, and what tells us is the path a language server answers a
	/// definition with. So the list starts empty, grows the first time a symbol
	/// is followed into a compiler's own sources, and is thrown away with the
	/// window. See `ToolchainSources`.
	private var toolchains: [Toolchain] = []
	/// What past agent sessions left behind for this project, as a third root.
	///
	/// Nil when there is nothing — the rule *Dependencies* keeps, for the reason
	/// item 508 was filed: a permanent empty row is worse than no row. Unlike a
	/// toolchain, whether a session left anything is knowable without being
	/// told, so this can be read on open.
	private var sessions: SessionNode?
	/// When the section was last read.
	///
	/// A burst too large for FSEvents to name file by file — a build, a
	/// checkout — arrives as "scan this subtree", and reading the section on
	/// every one of those would walk the project's subprojects four times a
	/// second for as long as the build ran. A named write to a manifest or a
	/// lock file is always honoured; an unnamed burst waits.
	private var lastDependencyRead = Date.distantPast
	/// The folder being worked on, marked in the tree so it is obvious which
	/// part of a repository the run button belongs to.
	private(set) var subprojectRoot: URL?
	private var watcher: FileSystemWatcher?
	private var outlineView: NavigatorOutlineView!
	private var headerView: NavigatorHeaderView!
	private var headerTopConstraint: NSLayoutConstraint!
	private var headerHeightConstraint: NSLayoutConstraint!
	private var gitRoot: URL?

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
		// callback so NavigatorRowView can draw the rounded highlight itself.
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
		outline.canPaste = { !FilePasteboard.files().isEmpty }
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

	// MARK: - Loading

	/// Marks a folder as the one being worked on.
	func setSubproject(_ url: URL?) {
		guard url?.path != subprojectRoot?.path else { return }
		subprojectRoot = url
		outlineView.reloadData()
		if let url { reveal(url: url) }
	}

	func load(project: Project) {
		self.project = project
		let root = FileNode(url: project.root, isDirectory: true)
		rootNode = root
		// The previous project's, which must not be shown against this one even
		// for the moment before the read below lands.
		dependencies = nil
		lastDependencyRead = .distantPast
		// The stack belongs to the project that was open, not to the window. A
		// ⌘Z after switching projects that put a file back somewhere in the
		// previous one would be an undo happening off screen.
		fileUndo.removeAllActions()

		outlineView.reloadData()
		outlineView.expandItem(root)
		// The first of 0428's two launch numbers that is not about the window:
		// the root has been listed and its rows exist, so there is something to
		// click. Colour has not arrived — that is `git status` below, and on a
		// repository this size the gap between the two is the whole question.
		LaunchClock.mark("tree listed")

		startWatching(root: project.root)

		// **Before anything can ask to reveal a file, and not after the first
		// paint.** It was written the other way first — queued to the main
		// queue, so the rows somebody clicks are drawn before eight
		// subprojects' manifests are read — and that lost a race that matters:
		// `abydos --file …/​.build/checkouts/Cadova/…/Extrusion.swift` opens the
		// tab in the same turn, the reveal finds no section to put it in, and
		// the ordinary tree answers instead — which for a Swift package means
		// opening `.build` and walking down to the checkout. The file was
		// shown, in the one place that cannot say which package it is.
		//
		// The cost is a directory walk two deep and a JSON parse per
		// subproject, which `LaunchClock` reports beside the rest of the open.
		refreshDependencies()
		LaunchClock.mark("dependencies read")
		refreshSessions()
		LaunchClock.mark("sessions read")
	}

	// MARK: - What past sessions left

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
	private var cheapSessions: [String: AgentSession] = [:]
	private var measuredSessions: [String: AgentSession] = [:]
	/// At most one walk at a time. A second is not queued: when one lands it
	/// reads again, and anything that arrived meanwhile is picked up then.
	private var walkingSessions = false

	private func refreshSessions() {
		guard let project else { return }
		// **News from outside the run is declined on a driven run.** This is 0451
		// arriving by a different door: a capture with somebody else's session at
		// work in the tree is a picture that looks different for everybody who
		// takes it, and `--screenshot` is pointed at the tree far more often than
		// at the toast corner. Both outside sources go: `ClaudeWatch` never
		// subscribes on such a run, so the register stays empty, and the
		// transcript times are declined here. What is left is what the run itself
		// put in the register with `--claude-running`, which is how a picture of
		// this can be taken at all.
		let running = RunningSessions.shared.ids(forSlugs: AgentSessions.slugs(of: project.root))
		let fresh = AgentSessions.sessions(
			of: project.root,
			running: running,
			readingTranscripts: !LaunchOptions.parse().isDrivenRun
		)

		// What an earlier walk counted, put back on the sessions whose own files
		// have not moved since. A session merely going on running changes no
		// file, and the row it is beside should not lose its size to say so.
		let carried = fresh.map { session -> AgentSession in
			guard cheapSessions[session.id]?.unchangedOnDisk(from: session) == true,
			      let counted = measuredSessions[session.id]
			else { return session }
			return counted.saying(session.liveness)
		}
		cheapSessions = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

		let read = SessionNode.build(carried)
		// Compared before redrawing, for the reason the dependency section is:
		// `reloadData` throws away every row's identity, and a root that
		// rebuilt itself on each refresh would collapse what somebody had open
		// while they were reading it. Liveness is part of that identity, so a
		// row can stop saying `running` — and *only* liveness changing gets the
		// redraw without the walk below, which finds nothing left to count.
		guard read?.identityForRefresh != sessions?.identityForRefresh else { return }

		show(read)
		// **And then the expensive half, off this thread.** Counting what is in
		// each session means walking it, which for the seven this repository has
		// on this machine is 6,920 files and 127 ms — a tenth of a second on the
		// project-open path, growing with every session anybody ever ran. The
		// rows are up without it, and gain their sizes when the walk lands.
		guard let read, !walkingSessions else { return }
		let unmeasured = read.sessions.filter { !$0.isMeasured }
		guard !unmeasured.isEmpty else { return }
		// What was on screen when the walk started. Compared against on the way
		// back — not against what the walk built, which may hold fewer rows
		// once the empty ones are known.
		let expected = read.identityIgnoringSize
		walkingSessions = true
		DispatchQueue.global(qos: .utility).async { [weak self] in
			let measured = unmeasured.map(AgentSessions.measured)
			DispatchQueue.main.async {
				guard let self else { return }
				self.walkingSessions = false
				// Only if this window is still showing the same sessions: the
				// project may have changed while the walk was running, and
				// putting these rows back would show the last project's.
				guard self.sessions?.identityIgnoringSize == expected else { return }
				for session in measured { self.measuredSessions[session.id] = session }
				// Merged into what is on screen rather than replacing it: a
				// session that started while the walk ran has a row now, and its
				// liveness is newer than anything the walk carried.
				let merged = (self.sessions?.sessions ?? []).map { shown in
					measured.first { $0.id == shown.id }?.saying(shown.liveness) ?? shown
				}
				self.show(SessionNode.build(merged))
				// And once more, in case anything arrived while it ran. It stops
				// here: nothing is unmeasured now, so the read above returns
				// early on an identity that has not changed.
				self.refreshSessions()
			}
		}
	}

	/// A hook event said something about a project. Read the root again if it
	/// was this one.
	///
	/// Called for the events that changed which sessions are running, or that
	/// ended a turn — never for the tool-use events, which arrive dozens of times
	/// a minute and say nothing new. `RunningSessions.note` is what decides.
	func claudeSessionsChanged(slug: String) {
		guard let project else { return }
		guard AgentSessions.slugs(of: project.root).contains(slug) else { return }
		refreshSessions()
	}

	/// Puts a read of the root on screen, keeping what was open and selected.
	private func show(_ node: SessionNode?) {
		let expanded = expandedPaths()
		let selected = selectedPaths()
		sessions = node
		outlineView.reloadData()
		restore(expandedPaths: expanded)
		restoreSelection(paths: selected)
	}

	// MARK: - Dependencies

	/// Reads the Dependencies section, and redraws only if it came out different.
	///
	/// Compared rather than reloaded blindly because this is called from the
	/// filesystem watcher: `reloadData` throws away every row's identity, so a
	/// section that rebuilt itself on each event would collapse whatever
	/// somebody had open while they were reading it.
	/// **Off the main thread, because it is a directory walk.**
	///
	/// `ExternalDependencies.read` walks the project two deep and parses a
	/// manifest per subproject. On a work tree of thirteen thousand folders that
	/// measured 1,196 ms — and it ran inside `load(project:)`, so it was 1,196 ms
	/// of a window that had stopped answering. Switching projects "felt like it
	/// had crashed", and the terminal stopped drawing with it, because the main
	/// thread was in here.
	///
	/// The read itself is a static over the filesystem with no shared state, so
	/// the only thing that has to stay on the main thread is what it is applied
	/// to.
	private func refreshDependencies() {
		guard let project else { return }
		lastDependencyRead = Date()
		let root = project.root
		isReadingDependencies = true

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			let sets = ExternalDependencies.read(project: root)
			DispatchQueue.main.async {
				guard let self else { return }
				// The project may have been switched again while this walked.
				// Applying it would put one project's packages under another's
				// name, which is worse than not having them yet.
				guard self.project?.root == root else { return }
				self.isReadingDependencies = false
				// Whatever the answer, the reveals that arrived while this was
				// out are owed another look — see `deferredReveals`.
				defer { self.replayDeferredReveals() }
				guard sets != self.dependencies?.sets else { return }
				self.rebuildDependencies(sets: sets)
			}
		}
	}

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
	private var isReadingDependencies = false
	private var deferredReveals: [URL] = []

	private func replayDeferredReveals() {
		let owed = deferredReveals
		deferredReveals = []
		guard !owed.isEmpty else { return }
		reveal(urls: owed)
	}

	/// Redraws the section, keeping what was open and what was selected.
	///
	/// The toolchains are carried across every rebuild. They are not read from
	/// disk like the sets are — they are learned from paths that arrived one at
	/// a time — so a rebuild that dropped them would take the row away again
	/// the next time somebody saved a `go.mod`, with the tab that needs it
	/// still open.
	private func rebuildDependencies(sets: [DependencySet]) {
		guard let project else { return }
		let expanded = expandedPaths()
		let selected = selectedPaths()
		dependencies = DependencyTree(sets: sets, toolchains: toolchains, project: project.root)
		outlineView.reloadData()
		restore(expandedPaths: expanded)
		restoreSelection(paths: selected)
	}

	/// Learns a toolchain from a path something is about to be revealed at.
	///
	/// **This is where the toolchain root comes from**, and it comes from the
	/// answer rather than from a question — see `ToolchainSources` for why that
	/// is not an exception to the section's no-build-tool rule but a stricter
	/// version of it. gopls has just answered `textDocument/definition` with
	/// `…/go/libexec/src/time/time.go`; `$GOROOT` is the part of that path
	/// above `src`, and no `go env` is run to find out.
	///
	/// Cheap on the ordinary case, which is every tab switch: a file inside the
	/// project is skipped on a string comparison, and a file already inside a
	/// known package or a known toolchain never reaches the disk either.
	private func noteToolchains(for urls: [URL]) {
		guard let project else { return }
		let inside = FilePath.canonical(project.root) + "/"
		var found: [Toolchain] = []
		for url in urls {
			let path = FilePath.canonical(url)
			guard !path.hasPrefix(inside) else { continue }
			guard dependencies?.locate(url) == nil else { continue }
			let known = toolchains + found
			guard !known.contains(where: { path.hasPrefix(FilePath.canonical($0.sources) + "/") }),
			      let toolchain = ToolchainSources.identify(url),
			      !known.contains(toolchain)
			else { continue }
			found.append(toolchain)
		}
		guard !found.isEmpty else { return }
		toolchains += found
		rebuildDependencies(sets: dependencies?.sets ?? [])
	}

	/// Mends the palette's file list, or says it can no longer be trusted.
	///
	/// Named paths are added and removed one at a time; a batch the kernel gave
	/// up describing only marks. Nothing here builds — a `swift build` produces
	/// these events by the second and each build of the list is a `git ls-files`
	/// over the whole repository, so the rebuild waits for somebody to open the
	/// palette and want an answer.
	private func updateFileIndex(with change: FileSystemChange) {
		guard let files = project?.files else { return }
		guard change.namesEveryPath else {
			Task { await files.markStale() }
			return
		}
		let paths = change.paths
		guard !paths.isEmpty else { return }
		Task { await files.noticed(changed: paths) }
	}

	/// Whether this batch of filesystem events could have changed the section.
	private func changeTouchesDependencies(_ change: FileSystemChange) -> Bool {
		guard change.namesEveryPath else {
			// Unnamed: it could be anything, including a `swift package resolve`
			// in the middle of it. Honoured, but not more than once every few
			// seconds — see `lastDependencyRead`.
			return Date().timeIntervalSince(lastDependencyRead) > 5
		}
		return change.paths.contains {
			ExternalDependencies.definingFileNames.contains($0.lastPathComponent)
		}
	}

	func windowWillClose() {
		watcher?.stop()
		watcher = nil
		// Nothing here is a cycle — the registrations hold `undoTarget`, which
		// holds this controller weakly. Emptied anyway, because a stack of paths
		// outliving the window that could act on them is only clutter.
		fileUndo.removeAllActions()
		NotificationCenter.default.removeObserver(self)
	}

	// MARK: - Version control

	func refreshGitStatus() {
		guard let project, let git = project.git, let rootNode else { return }

		// One `git status` at a time, with at most one more queued behind it.
		// The tree asks for this on every watcher event, and a project being
		// built produces a great many of those.
		guard !isReadingGitStatus else {
			wantsAnotherGitStatus = true
			return
		}
		isReadingGitStatus = true

		Task { @MainActor in
			defer {
				isReadingGitStatus = false
				if wantsAnotherGitStatus {
					wantsAnotherGitStatus = false
					refreshGitStatus()
				}
			}

			// Re-read it: the cache was filled when the project opened, so a
			// file written since — a build's output, or the binary a debugger
			// leaves behind — had no status at all and was drawn as if it were
			// tracked and unmodified.
			await git.refresh()
			let repoRoot = git.root
			gitRoot = repoRoot

			// Collect the lookups on the actor, then apply them synchronously so
			// the tree is never left half-updated between frames.
			//
			// **One visit to the actor, not one per node.** This asked for each
			// node's status separately, which for a tree with a few thousand open
			// rows is a few thousand hops onto the actor and a few thousand
			// continuations resumed back here — every one of them a block
			// scheduled on the main queue, interleaving with the terminal's own
			// drain, on every watcher event in a project being built. The git
			// subprocess was never the problem and is not touched: the answers
			// come from a cache the actor already holds, and the only thing that
			// changed is how many times the main queue is asked to come back for
			// them.
			var pending: [(path: String, isDirectory: Bool)] = []
			StallWatch.mark("navigator git status") {
				collectPaths(node: rootNode, gitRoot: repoRoot, into: &pending)
			}

			// **The rows about to be drawn, asked about before they are drawn.**
			// Without this the tree paints them as part of the project and they
			// turn grey when the full sweep lands hundreds of milliseconds
			// later, which is a flash of the wrong answer on every project
			// switch. `git status --ignored` cannot use git's untracked cache
			// so it walks the whole work tree cold — 0.41 s against 0.03 s on
			// this project, whose `.build` is 6.4 GB and 31,350 files — while
			// `check-ignore` costs the number of paths asked about: 0.01 s for
			// forty of them.
			//
			// Only what the tree has open, which is what `pending` already is.
			// The full sweep still runs and still replaces the lot, because it
			// is the one that notices a folder that has *stopped* being ignored.
			await git.primeIgnored(for: pending)

			let statuses = await git.statuses(for: pending)
			var results: [String: GitFileStatus] = [:]
			results.reserveCapacity(pending.count)
			for (query, status) in zip(pending, statuses) {
				results["\(query.isDirectory ? "d" : "f"):\(query.path)"] = status
			}

			StallWatch.mark("navigator git status") {
				rootNode.applyGitStatus(gitRoot: repoRoot) { path, isDirectory in
					results["\(isDirectory ? "d" : "f"):\(path)"] ?? .unmodified
				}
				// Deliberately not reloadData(): the row structure has not changed,
				// only the colours, and a reload would clear the selection — which
				// is what made keyboard-expanding a folder lose your place.
				redrawVisibleRows()
			}
			// The other half of "usable": the tree is coloured, so what the
			// working copy has changed is visible rather than about to appear.
			// First only — this runs again on every watcher event for the rest
			// of the session, and a mark that moved each time would report how
			// long ago the last build was rather than what opening cost.
			LaunchClock.mark("tree coloured")
			onChangeCount?(await git.changedFileCount())

			// And the greying-out, which is a slower question asked less often.
			// Deliberately after the colours are on screen and deliberately
			// outside the one-at-a-time gate above: reading the ignored set
			// walks the whole work tree, and holding the gate for it would stop
			// the tree recolouring for as long as that takes.
			refreshIgnoredIfRulesChanged()
		}
	}

	/// Re-reads what git ignores, when the ignore rules have moved.
	///
	/// Its own task and its own gate. `git status --ignored` cannot use git's
	/// untracked cache, so on a work tree with tens of thousands of untracked
	/// files it takes seconds every time — which is why it is not on the
	/// filesystem-event path with everything else. `needsIgnoredRefresh()` is
	/// the cheap question that keeps it off: it stats the ignore files, and a
	/// build writing class files does not touch one.
	private func refreshIgnoredIfRulesChanged() {
		guard let git = project?.git, !isReadingIgnored else { return }
		isReadingIgnored = true

		Task { @MainActor [weak self] in
			defer { self?.isReadingIgnored = false }
			guard await git.needsIgnoredRefresh() else { return }
			await git.refreshIgnored()
			// One more pass to put the new answer on screen. Through the
			// ordinary refresh so there is one place that applies colours, and
			// it will not come back here: the fingerprint now matches.
			self?.refreshGitStatus()
		}
	}

	private var isReadingIgnored = false

	/// The submenu under "New", filled in as it is about to be shown.
	private var newMenu: NSMenu?
	/// The submenu under "Export", which is only ever shown over a diagram.
	private var exportMenu: NSMenu?
	/// The kinds this project is made of, counted once and kept.
	///
	/// Counted lazily and not at open: walking a project to fill in a menu
	/// nobody has asked for yet is work for nothing. Dropped when the tree
	/// changes, so the first file of a new kind shows up in the menu after it
	/// exists rather than after the project is reopened.
	private var fileKinds: [NewFileKind]?
	/// Whether `fileKinds` is known to be behind the project.
	///
	/// Separate from throwing the list away, because the menu is not allowed to
	/// wait for a new one: the last answer is shown while a fresh one is worked
	/// out behind it. A project does not change what kinds of file it is made of
	/// very often, so the shown answer is almost always the right one, and when
	/// it is not it is right a moment later.
	private var fileKindsAreStale = true
	/// The recount in flight, so a burst of filesystem events schedules one.
	private var fileKindsTask: Task<Void, Never>?

	private var isReadingGitStatus = false
	private var wantsAnotherGitStatus = false
	private var hasScheduledGitStatusRefresh = false

	/// Repaints rows in place. Cells read `node.gitStatus` when they draw, so
	/// marking them dirty is enough to pick up new version-control state.
	private func redrawVisibleRows() {
		outlineView.enumerateAvailableRowViews { rowView, _ in
			rowView.needsDisplay = true
			for subview in rowView.subviews { subview.needsDisplay = true }
		}
	}

	/// Gathers relative paths for loaded nodes only; unloaded subtrees resolve
	/// their status when the user expands them.
	private func collectPaths(
		node: FileNode, gitRoot: URL, into result: inout [(path: String, isDirectory: Bool)]
	) {
		let base = gitRoot.path
		let path = node.url.path
		let relative: String
		if path == base {
			relative = ""
		} else if path.hasPrefix(base + "/") {
			relative = String(path.dropFirst(base.count + 1))
		} else {
			relative = ""
		}
		result.append((relative, node.isDirectory))

		guard node.hasLoadedChildren else { return }
		for child in node.children {
			collectPaths(node: child, gitRoot: gitRoot, into: &result)
		}
	}

	@objc private func repositoryChanged(_ notification: Notification) {
		guard let changedRoot = notification.object as? URL,
		      let gitRoot,
		      changedRoot.standardizedFileURL == gitRoot.standardizedFileURL
		else { return }
		reloadTree()
	}

	// MARK: - Filesystem watching

	private func startWatching(root: URL) {
		watcher?.stop()
		watcher = FileSystemWatcher(root: root) { [weak self] change in
			self?.handleFilesystemChange(change)
		}
		watcher?.start()
	}

	/// What the watcher has delivered and what the tree did about it, since the
	/// window opened.
	///
	/// 0428 asks for "filesystem events per build, and what the tree does with
	/// them", and those are three different numbers: how many batches FSEvents
	/// coalesced the build into, how many directories those batches named, and
	/// how many of them the tree was actually open on. The third is the one
	/// `loadedNode(for:)` was written to keep small, and it can only be counted
	/// from here — `FileNode.directoryReadsForTesting` counts listings anywhere,
	/// including the ones somebody's clicking causes.
	struct WatcherTally {
		var batches = 0
		var directories = 0
		var reloaded = 0
	}
	nonisolated(unsafe) static var watcherTallyForTesting = WatcherTally()

	/// What the tree costs right now, for `--report-open`.
	func scaleReportForTesting() -> [String] {
		let tally = Self.watcherTallyForTesting
		return [
			String(format: "OPEN %-24s %8d", ("tree rows" as NSString).utf8String!, outlineView.numberOfRows),
			String(format: "OPEN %-24s %8d", ("tree nodes held" as NSString).utf8String!, rootNode?.loadedNodeCount ?? 0),
			String(format: "OPEN %-24s %8d", ("directories listed" as NSString).utf8String!, FileNode.directoryReadsForTesting),
			String(format: "OPEN %-24s %8d batches, %d paths, %d reloaded",
				("watcher" as NSString).utf8String!, tally.batches, tally.directories, tally.reloaded),
		]
	}

	private func handleFilesystemChange(_ change: FileSystemChange) {
		Self.watcherTallyForTesting.batches += 1
		Self.watcherTallyForTesting.directories += change.directories.count
		StallWatch.mark("navigator watcher") { handleFilesystemChangeMarked(change) }
	}

	/// Named for the stall log, because this runs on every filesystem event and
	/// an agent writing files makes that dozens a minute. A stall recorded as
	/// "idle" is one nobody can act on, and most of the log was idle.
	private func handleFilesystemChangeMarked(_ change: FileSystemChange) {
		let directories = change.directories
		// Reported before the early return below: the staging view cares about
		// any edit, not only ones in a directory the tree happens to have
		// expanded.
		onFilesChanged?(change)

		// And so does the colouring, for a reason that is easy to miss: an edit
		// to an ignore file changes the status of files that did not themselves
		// change. Saving `.abydos/.gitignore` with `!backlog/` in it makes two
		// folders elsewhere in the tree stop being ignored, and nothing about
		// those folders was written. This used to be asked only when a directory
		// somebody had expanded was re-read, so the answer depended on which
		// parts of the tree happened to be open. The refresh coalesces — one
		// `git status` at a time with at most one queued — which is what makes
		// asking on every event affordable.
		refreshGitStatus()
		// And the first file of a new kind should be offered as one, without the
		// project being reopened. Marked rather than cleared: see
		// `fileKindsAreStale`.
		fileKindsAreStale = true
		// The palette's file list, which is why this is here rather than in the
		// palette: the palette is shut when the file somebody is about to look
		// for is saved, and the watcher is the only thing awake to see it.
		updateFileIndex(with: change)

		// A lock file being written is the one event that changes the
		// Dependencies section, and it is exactly what `swift package resolve`
		// and `go get` produce. Before the early return below, because the
		// section is not a directory anybody has expanded and would otherwise
		// only be re-read when something else in the tree happened to move.
		if changeTouchesDependencies(change) { refreshDependencies() }

		guard let rootNode else { return }
		guard !holdRebuildForRename() else { return }

		// Only re-read directories the user has actually expanded — and only ask
		// the question through directories that are already open. `node(for:)`
		// lists a directory to look inside it, so asking it about a path under
		// `.build` read `.build` and everything down to the event's parent, on
		// this queue, to find out that none of it was open. `loadedNode(for:)`
		// stops at the first closed door, which is where the answer already is.
		var touched = false
		for directory in directories {
			guard let node = rootNode.loadedNode(for: directory), node.isDirectory, node.hasLoadedChildren
			else { continue }
			node.reloadPreservingIdentity()
			Self.watcherTallyForTesting.reloaded += 1
			touched = true
		}
		guard touched else { return }

		// A reload drops the selection, so it is captured by path and restored.
		let expanded = expandedPaths()
		let selected = selectedPaths()
		outlineView.reloadData()
		restore(expandedPaths: expanded)
		// Or lands on the file somebody is waiting for. This is the path a
		// written file actually arrives by — the watcher re-reads the one
		// directory rather than the whole tree — and it used to put the old
		// selection back regardless, so `pendingReveal` was only honoured when
		// something else happened to reload everything.
		restoreSelectionOrReveal(paths: selected)
		// The status was already asked for above, for every change rather than
		// only the ones that landed here; rows that have just appeared are
		// covered by the same read.
	}

	/// Re-reads the tree after a settings change.
	///
	/// Hiding or showing dotfiles changes which nodes exist, so cached children
	/// have to be discarded rather than merely repainted.
	func applySettings() {
		outlineView.rowHeight = Theme.current.scaled(24)
		outlineView.indentationPerLevel = Theme.current.scaled(14)
		headerHeightConstraint.constant = Theme.current.scaled(30)
		headerView.isCompactingPackages = Settings.shared.compactsPackages
		headerView.restyle()
		guard let rootNode else { return }
		let expanded = expandedPaths()
		let selected = selectedPaths()
		rootNode.invalidate()
		outlineView.reloadData()
		outlineView.expandItem(rootNode)
		restore(expandedPaths: expanded)
		restoreSelection(paths: selected)
		refreshGitStatus()
	}

	/// Paths to select once the tree has caught up with the file system.
	///
	/// Creating a folder does not refresh the tree directly — the watcher does,
	/// a moment later — so the selection has to wait for the node to exist.
	///
	/// A list rather than one path, since 0436: a drop or a paste puts several
	/// files somewhere at once, and following one of them would be the same
	/// shrinking-selection fault `TreeSelection` exists for. Everything that
	/// makes one thing hands in a list of one and is unchanged.
	private var pendingReveal: [URL] = []

	/// Re-reads every directory the tree has loaded.
	///
	/// Called when the window comes forward, since the watcher is not the only
	/// way the tree goes stale — the app may have been asleep, or the events
	/// may have been coalesced away.
	func refreshFromDisk() {
		reloadTree()
		// **And the sessions, which the tree reload does not touch.** They are
		// not read from a directory the tree has loaded, so nothing else here
		// would notice a session that started while the app was asleep — or one
		// whose hooks are not installed, which is the only way such a session is
		// ever seen at all.
		refreshSessions()
	}

	/// Redraws the tree from the file system.
	///
	/// Internal rather than private since 0453: a workspace edit from a language
	/// server changes files nobody in this window went near, and the tree that
	/// is showing them is not otherwise told.
	func reloadTree() {
		StallWatch.mark("navigator reload") { reloadTreeMarked() }
	}

	private func reloadTreeMarked() {
		guard let rootNode else { return }
		guard !holdRebuildForRename() else { return }
		let expanded = expandedPaths()
		let selected = selectedPaths()
		rootNode.reloadPreservingIdentity()
		outlineView.reloadData()
		restore(expandedPaths: expanded)

		restoreSelectionOrReveal(paths: selected)
		refreshGitStatus()
	}

	/// Puts the selection back where it was — or on a file that has just been
	/// written, when the tree has caught up with it.
	/// Whichever of the pending paths the tree can find, or the old selection.
	///
	/// Any rather than all: a drop is one `FileManager` loop that finishes before
	/// the watcher fires, so in practice they arrive together — but a file that
	/// never arrives at all, a dotfile with hidden files switched off, would
	/// otherwise hold the reveal open for ever and the selection would sit on
	/// whatever was highlighted before the drop. What has arrived is selected;
	/// what has not is given up on. Not proved against a partial arrival, since
	/// nothing here can make one happen on purpose.
	private func restoreSelectionOrReveal(paths: [String]) {
		if !pendingReveal.isEmpty {
			let arrived = pendingReveal.filter { rootNode?.node(for: $0) != nil }
			if !arrived.isEmpty {
				pendingReveal = []
				selectWithoutOpening(urls: arrived)
				return
			}
		}
		restoreSelection(paths: paths)
	}

	/// Every selected path, in tree order.
	///
	/// All of them, not the first: the tree reloads on every filesystem event,
	/// and a build writing files reloads it dozens of times a minute. A capture
	/// that kept one path would shrink a selection of five to one while nobody
	/// was looking at it, which is the kind of fault nobody reports precisely.
	private func selectedPaths() -> [String] {
		TreeSelection.paths(rows: Array(outlineView.selectedRowIndexes)) { row in
			let item = outlineView.item(atRow: row)
			if let node = item as? FileNode { return node.url.path }
			// A session's own row is a selection too, and it is not a file. Held
			// the way its expansion is, so the one set carries both.
			if let node = item as? SessionNode { return "session:" + node.identity }
			return nil
		}
	}

	/// Every selected row as a node, in tree order.
	///
	/// The selection rather than `contextNodes`, which starts from `clickedRow`:
	/// this is what the keyboard's gestures act on, and a row clicked ten minutes
	/// ago is still the clicked row.
	private func selectedNodes() -> [FileNode] {
		outlineView.selectedRowIndexes.sorted().compactMap {
			outlineView.item(atRow: $0) as? FileNode
		}
	}

	/// Reselects by path, since reloadData replaces the row indices.
	private func restoreSelection(paths: [String]) {
		guard !paths.isEmpty, let rootNode else { return }
		// Through open directories only. A path that was selected was on screen,
		// so everything above it is expanded and therefore loaded; a path that
		// cannot be reached that way has no row to select either, and reading a
		// directory to prove it has no row is work for nothing on the queue the
		// watcher runs this from.
		let rows = TreeSelection.rows(for: paths) { path in
			// **Whichever root holds it.** This asked `rootNode` alone, so a
			// selected file under a Claude session — which lives outside the
			// project, in `/tmp/claude-…` — was looked for in the project tree,
			// not found, and dropped. Every rebuild of that section therefore
			// lost the selection entirely, and the section rebuilds on every
			// file an agent writes.
			if path.hasPrefix("session:") {
				guard let node = self.sessionNode(withIdentity: String(path.dropFirst(8))) else {
					return -1
				}
				return outlineView.row(forItem: node)
			}
			let url = URL(fileURLWithPath: path)
			if let node = rootNode.loadedNode(for: url) { return outlineView.row(forItem: node) }
			if let located = dependencies?.locate(url) {
				return outlineView.row(forItem: located.node)
			}
			// Through open directories only, as above: `loadedNode` gives up
			// rather than reading a directory to prove a row does not exist.
			if let session = sessions?.session(containing: url),
			   let fileRoot = session.fileRoot,
			   let node = fileRoot.loadedNode(for: url) {
				return outlineView.row(forItem: node)
			}
			return -1
		}
		guard !rows.isEmpty else { return }

		// Restoring must not be mistaken for somebody choosing the file, which
		// would reopen it in the editor.
		let wasSilent = isSelectingSilently
		isSelectingSilently = true
		outlineView.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
		isSelectingSilently = wasSilent
	}

	/// A session row by the name its selection was held under.
	private func sessionNode(withIdentity identity: String) -> SessionNode? {
		func find(_ node: SessionNode) -> SessionNode? {
			if node.identity == identity { return node }
			for child in node.childNodes {
				if let found = find(child) { return found }
			}
			return nil
		}
		guard let sessions else { return nil }
		return find(sessions)
	}

	// MARK: - Expansion state

	/// What is open, by name rather than by object, so it survives a reload.
	///
	/// Two kinds of name in one set: an absolute path for a file row, and
	/// `dep:` plus an identity for one of the Dependencies section's own rows.
	/// One set and not two, because every caller captures this before a reload
	/// and puts it back afterwards, and a second set would be one more thing for
	/// the next call site to forget — there are six of them already.
	private func expandedPaths() -> Set<String> {
		var paths = Set<String>()
		for row in 0..<outlineView.numberOfRows {
			let item = outlineView.item(atRow: row)
			if let node = item as? FileNode, outlineView.isItemExpanded(node) {
				paths.insert(node.url.path)
			} else if let node = item as? DependencyNode, outlineView.isItemExpanded(node) {
				paths.insert("dep:" + node.identity)
			} else if let node = item as? SessionNode, outlineView.isItemExpanded(node) {
				// **The third root was missing from here, and that is item 0540.**
				// A session's row rebuilds whenever the session's size changes —
				// which, while an agent is working in it, is every file it
				// writes — and nothing recorded that the row had been open. So
				// the section folded shut under whoever was reading it, dozens of
				// times a minute.
				paths.insert("session:" + node.identity)
			}
		}
		return paths
	}

	private func restoreExpansion() {
		guard let rootNode else { return }
		outlineView.expandItem(rootNode)
	}

	private func restore(expandedPaths paths: Set<String>) {
		let paths = FilePath.withAncestors(of: paths)
		if let rootNode {
			outlineView.expandItem(rootNode)
			expand(node: rootNode, matching: paths)
		}
		// **Each root, and no early return between them.** This used to `guard
		// let dependencies else { return }`, so a project without a Dependencies
		// section never reached the sessions below it — and one with a section
		// never reached them either, because nothing here walked them at all.
		if let dependencies { expand(dependency: dependencies.root, matching: paths) }
		if let sessions { expand(session: sessions, matching: paths) }
	}

	/// The same for the Claude Sessions root and its own rows, and then on into
	/// the session's directory, where the rows are files again and
	/// `expand(node:matching:)` takes over.
	private func expand(session node: SessionNode, matching paths: Set<String>) {
		guard paths.contains("session:" + node.identity) else { return }
		outlineView.expandItem(node)
		for child in node.childNodes { expand(session: child, matching: paths) }
		if let fileRoot = node.fileRoot { expand(node: fileRoot, matching: paths) }
	}

	private func expand(node: FileNode, matching paths: Set<String>) {
		guard node.hasLoadedChildren else { return }
		// The rows, not the children: with compaction on, half the directories
		// under this one have no row to open, and the one that has is several
		// levels down. Its path is in `paths` either way, which is what makes
		// the saved set survive the toggle.
		for child in rows(under: node) where child.isDirectory && paths.contains(child.url.path) {
			outlineView.expandItem(child)
			expand(node: child, matching: paths)
		}
	}

	/// The same for the section's own rows, which are not files and have no
	/// paths — and then on into the package's directory, where they are files
	/// again and the rule above takes over.
	private func expand(dependency node: DependencyNode, matching paths: Set<String>) {
		guard paths.contains("dep:" + node.identity) else { return }
		outlineView.expandItem(node)
		for child in node.childNodes { expand(dependency: child, matching: paths) }
		if let fileRoot = node.fileRoot { expand(node: fileRoot, matching: paths) }
	}

	// MARK: - Selection

	/// Opens a row, or closes it. The one gesture the Dependencies section's own
	/// rows have — a package is not a file, so there is nothing to show for it
	/// but what is inside it.
	private func toggle(_ item: Any) {
		if outlineView.isItemExpanded(item) {
			outlineView.collapseItem(item)
		} else {
			outlineView.expandItem(item)
		}
	}

	@objc private func rowDoubleClicked() {
		let clicked = outlineView.item(atRow: outlineView.clickedRow)
		if let dependency = clicked as? DependencyNode {
			toggle(dependency)
			return
		}
		guard let node = clicked as? FileNode else { return }
		if node.isDirectory {
			if outlineView.isItemExpanded(node) {
				outlineView.collapseItem(node)
			} else {
				outlineView.expandItem(node)
			}
		} else {
			// Committing to a file hands keyboard focus to the editor.
			onSelectFile?(node.url, true)
		}
	}

	// MARK: - Context menu

	private func makeContextMenu() -> NSMenu {
		let menu = NSMenu()
		menu.delegate = self

		// `NSMenu` sends to the first responder chain; targeting self keeps the
		// actions here regardless of what currently has focus.
		func item(_ title: String, _ selector: Selector) -> NSMenuItem {
			let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			item.target = self
			return item
		}

		// One "New", with what this project is made of under it. The two
		// original items are the first things in the submenu and behave exactly
		// as they did: the kinds below them are a shortcut past typing an
		// extension, not another way of creating things.
		//
		// No ellipsis on either since 0439. It said a dialog was about to ask
		// for the name, and nothing asks any more — the row appears in the tree
		// with the name selected on it, which is what the Finder's "New Folder"
		// does and why the Finder does not write an ellipsis on it either.
		// A session's row, and only that: the id is unreadable and is exactly
		// what `claude --resume` takes, so the row hands it over as a command.
		// First in the menu, because for a session row it is the only item in it
		// that means anything.
		let resume = item("Copy Resume Command", #selector(contextCopyResumeCommand))
		resumeItem = resume
		menu.addItem(resume)
		// **And a way into the directory itself**, for both rows of that root.
		// Reported: right-clicking `Claude Sessions` offered the whole file menu
		// — New, Rename, *Move to Trash* — and nothing that applies to it. Its
		// own two items are these, and the file menu is not one of them.
		let revealSession = item("Reveal in Finder", #selector(contextRevealSessionInFinder))
		revealSessionItem = revealSession
		menu.addItem(revealSession)

		let new = NSMenuItem(title: "New", action: nil, keyEquivalent: "")
		let kinds = NSMenu()
		kinds.addItem(item("File", #selector(contextNewFile)))
		kinds.addItem(item("Folder", #selector(contextNewFolder)))
		new.submenu = kinds
		newMenu = kinds
		menu.addItem(new)
		menu.addItem(.separator())
		menu.addItem(item("Open", #selector(contextOpen)))
		menu.addItem(item("Open Externally", #selector(contextOpenExternally)))
		// Space does this too. Written down here because a key with nothing
		// naming it is a key nobody finds — and hidden per click, like the
		// model preview below, because whether it is worth offering depends on
		// what was clicked.
		let look = item("Quick Look", #selector(contextQuickLook))
		look.keyEquivalent = " "
		look.keyEquivalentModifierMask = []
		menu.addItem(look)
		// Built once and hidden per click: the menu exists long before anything
		// has been right-clicked, so it cannot be decided here.
		menu.addItem(item("Preview in GoSTL", #selector(contextPreviewModel)))
		// Comparing the file with its git past. Both destinations exist — the
		// diff tab and the file-scoped log — and neither was reachable from
		// the file it is about.
		let compare = NSMenuItem(title: "Compare", action: nil, keyEquivalent: "")
		let comparing = NSMenu()
		let against = item("Against Last Commit", #selector(contextCompareAgainstHead))
		let history = item("History\u{2026}", #selector(contextCompareHistory))
		comparing.addItem(against)
		comparing.addItem(history)
		compare.submenu = comparing
		compareMenu = comparing
		compareAgainstItem = against
		compareHistoryItem = history
		menu.addItem(compare)
		menu.addItem(.separator())
		menu.addItem(item("Open as Subproject", #selector(contextOpenSubproject)))
		menu.addItem(item("Leave Subproject", #selector(contextLeaveSubproject)))
		menu.addItem(.separator())
		menu.addItem(item("Open Terminal Here", #selector(contextOpenTerminal)))
		menu.addItem(item("Reveal in Finder", #selector(contextRevealInFinder)))
		menu.addItem(.separator())
		// ⌘C, written down at last: it has always copied the absolute paths, and
		// since 0436 it copies the files themselves alongside them.
		let copyPath = item("Copy Path", #selector(contextCopyPath))
		copyPath.keyEquivalent = "c"
		copyPath.keyEquivalentModifierMask = [.command]
		menu.addItem(copyPath)
		// The Finder's two words for the two pastes. Like Rename… and Move to
		// Trash below, nothing dispatches these — a contextual menu is not the
		// main menu — but this is the only place ⌥⌘V is written down at all.
		let pasteItem = item("Paste Item", #selector(contextPaste))
		pasteItem.keyEquivalent = "v"
		pasteItem.keyEquivalentModifierMask = [.command]
		menu.addItem(pasteItem)
		let moveItem = item("Move Item Here", #selector(contextPasteAsMove))
		moveItem.keyEquivalent = "v"
		moveItem.keyEquivalentModifierMask = [.command, .option]
		menu.addItem(moveItem)
		menu.addItem(.separator())
		menu.addItem(item("Add to .gitignore\u{2026}", #selector(contextIgnore)))
		menu.addItem(item("Copy Relative Path", #selector(contextCopyRelativePath)))
		// Only ever shown over a diagram, so it costs nothing to be here for
		// every other file: `menuNeedsUpdate` hides it.
		let export = NSMenuItem(title: "Export", action: nil, keyEquivalent: "")
		// Filled in by `menuNeedsUpdate`, from the same list the preview pane's
		// own menu is built from: what it offers depends on the theme and on
		// whether the file has stated a look, and both change while a menu exists.
		let formats = NSMenu()
		formats.autoenablesItems = false
		export.submenu = formats
		exportMenu = formats
		menu.addItem(export)
		menu.addItem(.separator())
		// The two keys written down where somebody will find them. A contextual
		// menu is not in the menu bar, so nothing dispatches these — AppKit only
		// searches the main menu for key equivalents, and `handleKeyDown` is
		// what actually answers them. They are here to be read.
		//
		// Ellipsis-free for the same reason New is: renaming has edited the row
		// in place since 0411, so the promise of a dialog was already stale.
		let rename = item("Rename", #selector(contextRename))
		// F2 rather than ⌥⏎, of the two keys that rename: an item carries one
		// equivalent, and F2 is the one somebody arrives already knowing. ⌥⏎ is
		// for the hands that spent a week with Return meaning rename.
		rename.keyEquivalent = String(UnicodeScalar(NSF2FunctionKey)!)
		rename.keyEquivalentModifierMask = []
		menu.addItem(rename)
		let trash = item("Move to Trash", #selector(contextTrash))
		trash.keyEquivalent = String(UnicodeScalar(NSBackspaceCharacter)!)
		trash.keyEquivalentModifierMask = [.command]
		menu.addItem(trash)
		menu.addItem(.separator())
		// The same two the header offers, for anybody who looks for them here.
		menu.addItem(item("Select Opened File", #selector(contextSelectOpenFile)))
		menu.addItem(item("Collapse All", #selector(contextCollapseAll)))
		return menu
	}

	@objc private func contextCollapseAll() { collapseAll() }
	@objc private func contextSelectOpenFile() { selectFileInEditor() }

	@objc private func contextOpenSubproject() {
		guard let node = contextNode, node.isDirectory else { return }
		onOpenSubproject?(node.url)
	}

	@objc private func contextLeaveSubproject() {
		onLeaveSubproject?()
	}

	/// Every row the menu applies to, in tree order.
	///
	/// Right-clicking inside the selection means all of it — the gesture every
	/// file manager has, and the reason ⇧-clicking four files and asking for the
	/// trash works. Right-clicking a row *outside* the selection means that row
	/// alone: the pointer is the more recent statement of what is meant.
	private var contextNodes: [FileNode] {
		let clicked = outlineView.clickedRow
		if clicked >= 0, !outlineView.selectedRowIndexes.contains(clicked) {
			return (outlineView.item(atRow: clicked) as? FileNode).map { [$0] } ?? []
		}
		if outlineView.selectedRowIndexes.isEmpty, clicked >= 0 {
			return (outlineView.item(atRow: clicked) as? FileNode).map { [$0] } ?? []
		}
		return outlineView.selectedRowIndexes.sorted().compactMap {
			outlineView.item(atRow: $0) as? FileNode
		}
	}

	/// The one row the menu applies to, or nil when it applies to several.
	///
	/// Rename, "open terminal here", "open as subproject" and "reveal" are all
	/// single-row gestures: there is no sensible answer for four, and doing it
	/// to whichever came first is worse than not offering it. `validateMenuItem`
	/// switches them off from the same answer.
	private var contextNode: FileNode? {
		let nodes = contextNodes
		return nodes.count == 1 ? nodes.first : nil
	}

	/// The two items that belong to the sessions root and the rows under it.
	private weak var resumeItem: NSMenuItem?
	private weak var revealSessionItem: NSMenuItem?

	/// The Compare submenu and its two entries, held so `menuNeedsUpdate` can
	/// prune them to the row's truth: an untracked file has no last commit to
	/// compare against and no history to show.
	private weak var compareMenu: NSMenu?
	private weak var compareAgainstItem: NSMenuItem?
	private weak var compareHistoryItem: NSMenuItem?

	/// The row of the sessions root the menu was opened on — the root itself, or
	/// one session — if it was opened on either.
	private var contextSessionRow: SessionNode? {
		let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
		guard row >= 0 else { return nil }
		return outlineView.item(atRow: row) as? SessionNode
	}

	/// The session row the menu was opened on, if it was opened on one. The
	/// root is not one: it has no id, and no session to resume.
	private var contextSession: AgentSession? { contextSessionRow?.session }

	/// The directory a row of that root stands for: a session's own, or the one
	/// every session of this project sits in.
	private var contextSessionDirectory: URL? {
		guard let row = contextSessionRow else { return nil }
		if let session = row.session { return session.directory }
		// The root: taken from one of its sessions rather than rebuilt from a
		// slug nobody should have to spell twice.
		return row.childNodes.first?.session?.directory.deletingLastPathComponent()
	}

	@objc private func contextRevealSessionInFinder() {
		guard let directory = contextSessionDirectory else { return }
		NSWorkspace.shared.activateFileViewerSelecting([directory])
	}

	/// Copies what somebody would type to carry that session on.
	///
	/// **What a session id is for.** It is unreadable and unmemorable, and it is
	/// exactly what `claude --resume` wants — so the row that could not be named
	/// by its id hands the id over as a command instead.
	@objc private func contextCopyResumeCommand() {
		// Not for one that is already running, which the menu also hides — but
		// hiding an item is a thing a menu does, not a thing the action knows,
		// and the driven report reads the two separately: `offers=[…] copied=…`
		// said in one line that nothing was offered and something was copied.
		guard let session = contextSession, !session.isLive else { return }
		let command = AgentSessions.resumeCommand(for: session)
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(command, forType: .string)
		Toast.post("Copied", detail: command, kind: .information)
	}

	@objc private func contextOpen() {
		guard let node = contextNode else { return }
		if node.isDirectory {
			outlineView.isItemExpanded(node) ? outlineView.collapseItem(node) : outlineView.expandItem(node)
		} else {
			onSelectFile?(node.url, true)
		}
	}

	@objc private func contextPreviewModel() {
		guard let node = contextNode else { return }
		onPreviewModel?(node.url)
	}

	@objc private func contextOpenExternally() {
		guard let node = contextNode else { return }
		NSWorkspace.shared.open(node.url)
	}

	@objc private func contextOpenTerminal() {
		guard let node = contextNode else { return }
		// A file's directory is what you want to be in; the file itself is not a
		// place a shell can start.
		let directory = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
		onOpenTerminal?(directory)
	}

	@objc private func contextRevealInFinder() {
		guard let node = contextNode else { return }
		NSWorkspace.shared.activateFileViewerSelecting([node.url])
	}

	/// One path a line, in tree order — the shape a list of files is wanted in —
	/// and the files themselves alongside, which is what ⌘C is.
	@objc private func contextCopyPath() {
		let urls = contextNodes.map(\.url)
		guard !urls.isEmpty else { return }
		FilePasteboard.write(urls)
	}

	@objc private func contextCopyRelativePath() {
		guard let root = project?.root else { return }
		let paths = contextNodes.map { node -> String in
			let path = node.url.path
			return path.hasPrefix(root.path + "/")
				? String(path.dropFirst(root.path.count + 1))
				: path
		}
		guard !paths.isEmpty else { return }
		copyToPasteboard(paths)
	}

	/// Text and nothing else, which is right for the one caller left: a relative
	/// path names no file the rest of the machine could find.
	private func copyToPasteboard(_ paths: [String]) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
	}

	/// Writes a folder straight to disk, without the row or the field, for the
	/// harness's older scripts: this is the file system doing it, not the
	/// gesture. `beginNewForTesting` is the gesture.
	func createFolderForTesting(named name: String) {
		guard let root = project?.root else { return }
		let destination = root.appendingPathComponent(name)
		try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
		pendingReveal = [destination]
	}

	func createFileForTesting(named name: String) {
		guard let root = project?.root else { return }
		let destination = root.appendingPathComponent(name)
		try? FileManager.default.createDirectory(
			at: destination.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try? Data().write(to: destination, options: .withoutOverwriting)
		pendingReveal = [destination]
		onSelectFile?(destination, true)
	}

	/// Where a new entry from the context menu goes.
	///
	/// The same answer a drop gets, from the same function: inside the folder
	/// that was clicked, or beside the file that was clicked. The first of
	/// several, since a new file has one place to go and the topmost row is the
	/// one somebody would point at.
	private var contextParentDirectory: URL? {
		destinationFolder(for: contextNodes.first)
	}

	/// Offers a pattern for whatever was right-clicked, and writes it once it
	/// is agreed.
	@objc private func contextIgnore() {
		guard let node = contextNode, let project else { return }
		let root = gitRoot ?? project.root
		let path = node.url.path
		guard path.hasPrefix(root.path + "/") else {
			Toast.post("Not in this repository", detail: "\(node.name) is outside \(root.lastPathComponent).")
			return
		}
		let relative = String(path.dropFirst(root.path.count + 1))
		presentIgnoreDialog(relativePath: relative, isDirectory: node.isDirectory, root: root)
	}

	private func presentIgnoreDialog(relativePath: String, isDirectory: Bool, root: URL) {
		let suggestions = GitIgnore.suggestions(for: relativePath, isDirectory: isDirectory)

		let alert = NSAlert()
		alert.messageText = "Ignore \((relativePath as NSString).lastPathComponent)"
		alert.informativeText = "The pattern is written to .gitignore. Edit it if it is not quite right."
		alert.addButton(withTitle: "Ignore")
		alert.addButton(withTitle: "Cancel")

		let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 54))
		let popup = NSPopUpButton(frame: NSRect(x: 0, y: 30, width: 360, height: 24))
		popup.addItems(withTitles: suggestions.map { "\($0.pattern)   —   \($0.explanation)" })
		container.addSubview(popup)

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
		field.stringValue = suggestions.first?.pattern ?? relativePath
		field.font = Theme.terminalFont(size: 12)
		container.addSubview(field)

		ignoreSuggestions = suggestions
		ignoreField = field
		popup.target = self
		popup.action = #selector(ignorePatternChosen)
		alert.accessoryView = container

		let apply: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn else { return }
			let pattern = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !pattern.isEmpty else { return }
			do {
				try GitIgnore.add(pattern, toRepositoryAt: root)
				self?.refreshGitStatus()
				NotificationCenter.default.post(name: .abydosRepositoryChanged, object: root)
			} catch {
				Toast.post("Could not write .gitignore", detail: error.localizedDescription)
			}
		}
		if let window = view.window {
			alert.beginSheetModal(for: window, completionHandler: apply)
		} else {
			apply(alert.runModal())
		}
	}

	private var ignoreSuggestions: [GitIgnore.Suggestion] = []
	private weak var ignoreField: NSTextField?

	@objc private func ignorePatternChosen(_ sender: NSPopUpButton) {
		guard ignoreSuggestions.indices.contains(sender.indexOfSelectedItem) else { return }
		ignoreField?.stringValue = ignoreSuggestions[sender.indexOfSelectedItem].pattern
	}

	/// Puts this project's own kinds under "New", below File and Folder.
	///
	/// Rebuilt as the menu opens rather than kept in step with the tree: the
	/// count is cached, so this is a few string comparisons unless something
	/// has changed, and a menu that is right whenever it is looked at needs no
	/// invalidation rules of its own.
	/// Counts the kinds of file the project holds, from the palette's index.
	///
	/// The index is built by one `git ls-files` and mended as files come and go,
	/// so this costs a map over a list that is already in memory — against the
	/// walk it replaces, which `FileIndex` itself documents as 3.05 s where the
	/// index took 0.03 s.
	///
	/// One at a time: a `git checkout` names thousands of files in a few batches
	/// and every batch marks the count stale, and there is no sense in a second
	/// recount of a list the first one is already reading.
	private func recountFileKinds() {
		guard fileKindsTask == nil, let files = project?.files else { return }
		// Cleared before the work rather than after it, so a change arriving
		// during the recount is not forgotten — it marks the flag again and the
		// next menu asks for another.
		fileKindsAreStale = false
		fileKindsTask = Task { [weak self] in
			let paths = await files.indexedPaths()
			let kinds = NewFileKinds.choose(from: paths)
			await MainActor.run {
				guard let self else { return }
				self.fileKindsTask = nil
				// An index that has not finished its first build answers with
				// nothing, and nothing is not an answer — it would empty a submenu
				// that had perfectly good entries in it. Left alone, and asked
				// again next time.
				guard !kinds.isEmpty else {
					self.fileKindsAreStale = true
					return
				}
				guard kinds != self.fileKinds else { return }
				self.fileKinds = kinds
				self.refreshNewMenu()
			}
		}
	}

	private func refreshNewMenu() {
		guard let menu = newMenu else { return }
		while menu.numberOfItems > 2 { menu.removeItem(at: menu.numberOfItems - 1) }

		// **Never a walk of the project from here.** This runs inside
		// `menuNeedsUpdate`, which AppKit calls while the menu is opening, on the
		// main thread, with the menu on screen waiting for it to return. It used
		// to call `NewFileKinds.inProject`, which collects every file in the
		// project — and because the watcher cleared the cache on any change, that
		// walk was paid again on the next right-click after every save. On a
		// repository of 43,600 entries a right-click took seconds, for a submenu
		// of five items.
		//
		// What is shown is whatever was last counted; a recount is asked for here
		// and arrives later.
		if fileKindsAreStale { recountFileKinds() }
		guard let kinds = fileKinds, !kinds.isEmpty else { return }

		menu.addItem(.separator())
		for kind in kinds {
			let item = NSMenuItem(
				title: kind.title, action: #selector(contextNewFileOfKind(_:)), keyEquivalent: ""
			)
			item.target = self
			item.representedObject = kind.name
			menu.addItem(item)
		}
	}

	/// A new file whose extension is already decided.
	///
	/// Everything else is what New ▸ File does — the same row, the same field,
	/// the same validation — because the shortcut is about the extension and
	/// nothing else. What it changes is the two things the field starts with:
	/// the name has the extension on it already, and only the stem is selected.
	@objc private func contextNewFileOfKind(_ sender: NSMenuItem) {
		guard let suffix = sender.representedObject as? String else { return }
		let kind = NewFileKind(name: suffix, count: 0, title: sender.title)
		beginNew(kind: .file, named: NewFileKinds.name(EntryName.draftName(kind: .file), endingIn: kind))
	}

	@objc private func contextNewFile() {
		beginNew(kind: .file)
	}

	@objc private func contextNewFolder() {
		beginNew(kind: .folder)
	}

	// MARK: - Naming on the row

	/// What the field standing on a row is for.
	///
	/// The two are one gesture from different starting points, so they share the
	/// field, its geometry, the rules that refuse a name, the hold on the
	/// watcher's rebuild and the reveal that follows the path afterwards. All
	/// that differs is whether there was a row before it began and what happens
	/// on Return.
	private enum NameEdit {
		/// An existing row, being called something else.
		case rename(node: FileNode, original: String)
		/// A row that is not a file yet. **Nothing is on disk until Return** —
		/// which is the whole reason the order is this way round rather than
		/// create-then-rename: Escape has to leave nothing behind, and an empty
		/// file already written is something.
		case create(placeholder: FileNode, parent: FileNode, kind: EntryName.Kind, anchor: [String])

		var node: FileNode {
			switch self {
			case .rename(let node, _): return node
			case .create(let placeholder, _, _, _): return placeholder
			}
		}

		var kind: EntryName.Kind {
			switch self {
			case .rename(let node, _): return node.isDirectory ? .folder : .file
			case .create(_, _, let kind, _): return kind
			}
		}

		/// What a refusal is a refusal to do. Renaming with a name the rules do
		/// not allow has said "Cannot create that file" since the two paths were
		/// separate machines; sharing one is what makes it worth fixing.
		var verb: String {
			switch self {
			case .rename: return "rename"
			case .create: return "create"
			}
		}
	}

	/// The field standing in for a row's label while its name is being edited.
	private var nameField: NSTextField?
	/// What that field is doing, and what it needs to undo if it is abandoned.
	private var editing: NameEdit?

	/// The row that stands for a file which does not exist yet.
	///
	/// A `FileNode` like any other, handed to the outline view by the data
	/// source and belonging to nothing on disk. **It sits at the end of its
	/// folder's children and stays there while the name is typed**, rather than
	/// sorting into place letter by letter — see `beginNew` for why.
	private var placeholder: (node: FileNode, parent: FileNode)?

	/// Edits a name where the name is.
	///
	/// The Finder's gesture, and the reason it is the right one here: the file
	/// stays in its place in the tree while it is renamed, so what is being
	/// renamed is never in doubt and the files around it stay readable. A sheet
	/// in the middle of the window answers the same question with less of the
	/// answer on screen.
	func beginRename(row: Int? = nil) {
		// A row named explicitly, or the selection when it is one row. Renaming
		// is a single-row gesture: with several selected Return does nothing
		// rather than renaming whichever came first.
		if row == nil, outlineView.numberOfSelectedRows > 1 { return }
		let index = row ?? outlineView.selectedRow
		guard index >= 0, let node = outlineView.item(atRow: index) as? FileNode,
		      node !== rootNode, nameField == nil
		else { return }

		beginEditing(.rename(node: node, original: node.name), row: index, name: node.name)
	}

	/// Puts a row where the new entry is going to be and asks for its name
	/// there, which is the whole of 0439.
	///
	/// **At the end of its folder, and it stays there while the name is typed.**
	/// The alternative — re-sorting on every keystroke, so the row is always
	/// where the finished name would put it — moves the row out from under the
	/// cursor of the person reading it, which is reason enough. The mechanical
	/// reason is worse: the field is a subview of the outline view at absolute
	/// coordinates over one row, so a row that moved would leave the field
	/// behind on whatever is now at those coordinates, and re-placing it every
	/// keystroke means recomputing the geometry 0411 took four attempts to get
	/// right, mid-edit, under a caret. The row does jump once on Return —
	/// `pendingReveal` is what makes the jump end with it selected and scrolled
	/// to, rather than lost.
	///
	/// Nothing is written until Return. See `NameEdit.create`.
	private func beginNew(kind: EntryName.Kind, named draft: String? = nil) {
		guard nameField == nil, let rootNode else { return }
		// Where a drop aimed at this row would land: inside the selected folder,
		// or beside the selected file, or the project root when nothing is
		// selected. One answer for both gestures, from one function.
		guard let folder = contextParentDirectory, let parent = rootNode.node(for: folder) else { return }

		let name = draft ?? EntryName.draftName(kind: kind)
		let node = FileNode(url: parent.url.appendingPathComponent(name), isDirectory: kind == .folder)
		// Whatever was highlighted before, so Escape can put it back: the
		// placeholder takes the selection while it is up, and the row it came
		// from is where somebody was.
		let anchor = selectedPaths()

		placeholder = (node, parent)
		// The whole tree, because the row structure has changed and the outline
		// view has to ask for the children again. Expansion is restored by path
		// the way every other rebuild here does it, and then the folder the row
		// is going into is opened whether it was before or not — a new child of
		// a collapsed folder is otherwise made and never seen.
		let expanded = expandedPaths()
		outlineView.reloadData()
		restore(expandedPaths: expanded)
		outlineView.expandItem(parent)

		let index = outlineView.row(forItem: node)
		guard index >= 0 else {
			placeholder = nil
			outlineView.reloadData()
			restore(expandedPaths: expanded)
			return
		}
		// Scrolled to before the field is measured: the frame is worked out from
		// the row's rectangle against the visible one, so a row still below the
		// fold would be given a field somewhere off screen.
		outlineView.scrollRowToVisible(index)
		let wasSilent = isSelectingSilently
		isSelectingSilently = true
		outlineView.selectRowIndexes([index], byExtendingSelection: false)
		isSelectingSilently = wasSilent

		beginEditing(
			.create(placeholder: node, parent: parent, kind: kind, anchor: anchor),
			row: index, name: name
		)
	}

	/// Puts the field on a row and hands it the keyboard.
	///
	/// One field for both gestures, which is the point: everything 0411 argued
	/// out about where the box sits, how big its text is and where it stops is
	/// paid for once and had by both.
	private func beginEditing(_ edit: NameEdit, row index: Int, name: String) {
		// The rows have to exist before a field can be put on top of one.
		//
		// An outline view builds its row views at the next layout pass, not when
		// it is told to reload — so on a brand-new row the field went in first
		// and the row view was built over it a moment later, and the box was
		// simply not there. Seen on screen and nowhere else: the geometry the
		// harness prints was right the whole time, and the row correctly stopped
		// drawing its own name, so everything readable as a number agreed while
		// the pane showed an empty row. Renaming never met this, because its row
		// was already on screen before anybody asked.
		outlineView.layoutSubtreeIfNeeded()

		// Over the label, not the whole row: the icon stays, so the row still
		// says what kind of thing is being named.
		let cell = outlineView.frameOfCell(atColumn: 0, row: index)
		// Where `NavigatorCellView` puts the name: the icon's width and the two
		// gaps around it. Taken from the same numbers rather than guessed at, so
		// the name does not move sideways as the field appears over it.
		let inset = Theme.current.scaled(2) + Theme.current.scaled(16) + Theme.current.scaled(6)
		let trailing = Theme.current.scaled(8)

		let field = NSTextField(frame: .zero)
		// A cell that centres its text, for editing as well as drawing. A plain
		// one puts the text against the top of whatever height it is given, which
		// is what made the name jump up as the field appeared — and jump further
		// the taller the row, so it looked worst at a large zoom.
		let centred = CentredFieldCell(textCell: "")
		centred.isEditable = true
		centred.isSelectable = true
		centred.usesSingleLineMode = true
		centred.wraps = false
		// Scrolls inside itself rather than clipping, so a name longer than the
		// pane can still be read and edited to its end without the pane being
		// dragged wider first.
		centred.isScrollable = true
		field.cell = centred
		// The row's own font. At 12 against the label's 13 the name visibly
		// shrank the moment editing began.
		field.font = Theme.current.uiFont(13)
		// The row's height, less a hair so the border does not touch the rows
		// above and below. The text inside is centred by the cell.
		let height = max(1, cell.height - Theme.current.scaled(2))
		// Stops where the pane does, not where the widest name does: the outline
		// is as wide as its longest row, so measuring against that put the right
		// edge of the field beyond the edge of the view, and the pane had to be
		// dragged wider than the filename before the whole field could be seen.
		let rightEdge = min(outlineView.rect(ofRow: index).maxX, outlineView.visibleRect.maxX)
		field.frame = NSRect(
			x: cell.minX + inset,
			y: (cell.minY + (cell.height - height) / 2).rounded(),
			width: max(60, rightEdge - cell.minX - inset - trailing),
			height: height
		)
		field.stringValue = name
		// Not bezeled: a bezel in a dark appearance is translucent and draws its
		// own background, so `drawsBackground` is ignored and the row's label
		// shows through — the old name and the new one on top of each other.
		field.isBezeled = false
		field.isBordered = false
		field.focusRingType = .none
		field.wantsLayer = true
		field.layer?.cornerRadius = 3
		field.layer?.borderWidth = 1
		field.layer?.borderColor = Theme.current.caret.cgColor
		// Opaque, in the sidebar's own colours: the row keeps drawing its label
		// underneath, and a field that lets it through shows the old name and
		// the new one on top of each other.
		field.drawsBackground = true
		field.backgroundColor = Theme.current.editorBackground
		field.textColor = Theme.current.sidebarText
		field.delegate = self
		// Above the rows: they are subviews too, and a field merely added is
		// behind the label it is standing in for.
		outlineView.addSubview(field, positioned: .above, relativeTo: nil)
		nameField = field
		editing = edit
		// Told, not reloaded. `reloadItem` would build a fresh row view and lay
		// it over the field, which is the fault the deferred rebuild above
		// exists for — the box vanishes while still taking the typing.
		showsName(at: index, false)

		outlineView.window?.makeFirstResponder(field)
		// The stem, the way the Finder does it: the extension is nearly never
		// what somebody meant to change, and having it selected is how a `.swift`
		// gets typed over by accident. The same rule for both gestures — it is
		// what makes `untitled.py` arrive with `untitled` selected, so typing
		// replaces the name and keeps the extension.
		if let editor = field.currentEditor() {
			editor.selectedRange = NSRange(
				location: 0, length: EntryName.stemLength(of: name, kind: edit.kind)
			)
		}
	}

	/// Renames the selected row, for the capture harness: the same three steps
	/// somebody takes, without a keyboard.
	func renameSelectionForTesting(_ name: String) {
		beginRename()
		nameField?.stringValue = name
		commitName()
	}

	/// The other gesture, whole: New, the name, Return. `kind` is `file`,
	/// `folder`, or an extension such as `swift`, which is the submenu's
	/// shortcut.
	///
	/// Typed into the selection rather than assigned to the field, which is the
	/// difference between asking what this does and asking what a harness does:
	/// the draft arrives with only its stem selected, so `new:py:script` has to
	/// come out `script.py`. Setting `stringValue` would replace the extension
	/// as well and prove nothing about the selection at all — and did: the first
	/// run of this made a file called `script`.
	func createSelectionForTesting(kind: String, name: String?) {
		beginNewForTesting(kind: kind)
		if let name { nameField?.currentEditor()?.insertText(name) }
		commitName()
	}

	/// New without the Return, so the row and the field it puts up can be
	/// photographed and measured — which is the half a committed name cannot
	/// show.
	func beginNewForTesting(kind: String) {
		switch kind {
		case "file": beginNew(kind: .file)
		case "folder": beginNew(kind: .folder)
		default:
			let suffix = NewFileKind(name: kind, count: 0, title: NewFileKinds.title(for: kind))
			beginNew(
				kind: .file,
				named: NewFileKinds.name(EntryName.draftName(kind: .file), endingIn: suffix)
			)
		}
	}

	/// Where the field is and what it is drawing with, for the harness.
	///
	/// The three things that were wrong with it were all geometry — the text's
	/// size, where it sat in the row, and where it stopped — so they are worth
	/// being able to read as numbers rather than only off a photograph.
	///
	/// `selected` since 0439: which part of the name the field opens with
	/// highlighted is a decision — the stem and not the extension — and a
	/// screenshot of a one-pixel-high highlight is not evidence of it.
	var renameFieldReportForTesting: String {
		guard let field = nameField else { return "no field" }
		let row = outlineView.rect(ofRow: outlineView.selectedRow)
		let range = field.currentEditor()?.selectedRange ?? NSRange(location: 0, length: 0)
		let text = field.stringValue as NSString
		let selected = NSMaxRange(range) <= text.length ? text.substring(with: range) : "?"
		return "frame=\(field.frame) row=\(row) visible=\(outlineView.visibleRect) "
			+ "font=\(field.font?.pointSize ?? 0) name=\(field.stringValue) selected=“\(selected)”"
	}

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
	private var deferredRebuild = false

	/// True when a rebuild must not happen yet, and remembers that one is owed.
	private func holdRebuildForRename() -> Bool {
		guard nameField != nil else { return false }
		deferredRebuild = true
		return true
	}

	/// Whether a row draws its own name, for the row the field is standing on.
	private func showsName(at row: Int, _ shows: Bool) {
		guard row >= 0,
		      let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
		      	as? NavigatorCellView
		else { return }
		cell.isRenaming = !shows
	}

	/// Takes the field away, and with it the row when there was no row before.
	///
	/// **Escape leaves nothing**: no file, no folder, and no row where one was
	/// about to be. That is the whole of what `create` has to undo, and it is
	/// only that little because nothing was written on the way in.
	private func endEditing() {
		// Forgotten before the field is taken away, not after: removing a field
		// that is being edited ends the editing then and there, and
		// `controlTextDidEndEditing` arrives while this is still half-done. It
		// would commit the very name Escape had just rejected — and did:
		// beginning a rename, changing the name and pressing Escape renamed the
		// file. Nothing left to find means nothing left to commit.
		let field = nameField
		let edit = editing
		nameField = nil
		editing = nil
		if case .rename(let node, _) = edit {
			showsName(at: outlineView.row(forItem: node), true)
		}
		field?.removeFromSuperview()

		if case .create(_, _, _, let anchor) = edit {
			// The placeholder goes before the tree is asked anything else, so
			// nothing can be handed a row that stands for no file.
			placeholder = nil
			let expanded = expandedPaths()
			outlineView.reloadData()
			restore(expandedPaths: expanded)
			// Whatever a successful Return left waiting, or the row the gesture
			// started from — which is where somebody was before they asked for a
			// new file, and where Escape should put them back.
			restoreSelectionOrReveal(paths: anchor)
		}

		outlineView.window?.makeFirstResponder(outlineView)
		// Whatever changed on disk while the field was up, caught up with now
		// rather than at the next event — which may be a long time coming.
		if deferredRebuild {
			deferredRebuild = false
			reloadTree()
		}
	}

	/// Return: renames the file, or writes the new one, or says why it cannot.
	///
	/// Validated before the field goes: a name that is refused leaves the field
	/// up with the name still in it, since taking it away would look like a
	/// rename that happened — and for a new file it would be worse, because
	/// there would be nothing left of what was typed at all.
	private func commitName() {
		guard let field = nameField, let edit = editing else { return }
		let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

		switch edit {
		case .rename(let node, let original):
			// An empty field, or the name it already had, is a cancel rather than
			// an error: neither is somebody asking for anything.
			guard !name.isEmpty, name != original else {
				endEditing()
				return
			}
			let folder = node.url.deletingLastPathComponent()
			guard let destination = accepted(name, kind: edit.kind, in: folder) else { return }
			do {
				try FileManager.default.moveItem(at: node.url, to: destination)
			} catch {
				refuse(error.localizedDescription, kind: edit.kind)
				return
			}
			remember(FileUndo.renamed(from: node.url, to: destination))
			// The watcher rebuilds the tree, and the row is a different object
			// afterwards — so the selection follows the path rather than the node.
			pendingReveal = [destination]
			endEditing()

		case .create(_, let parent, let kind, _):
			// An empty field is a cancel, exactly as it is for a rename: nothing
			// was written on the way in, so there is nothing to undo.
			guard !name.isEmpty else {
				endEditing()
				return
			}
			guard let destination = accepted(name, kind: kind, in: parent.url) else { return }
			do {
				switch kind {
				case .folder:
					try FileManager.default.createDirectory(
						at: destination, withIntermediateDirectories: false
					)
				case .file:
					try Data().write(to: destination, options: .withoutOverwriting)
				}
			} catch {
				refuse(error.localizedDescription, kind: kind)
				return
			}
			// Undoing this moves it to the trash, and the date is read now so that
			// a ⌘Z arriving after somebody has written in the file refuses instead
			// — which is the case the change check exists for.
			remember(FileUndo.created(destination, isDirectory: kind == .folder) {
				Self.modificationDate(of: $0)
			})
			// The folder has just been written to, so its listing is stale by one
			// entry. Re-read here rather than waiting for the watcher: the row
			// the placeholder stood for has to be replaced by the real one in the
			// same breath, or the tree shows the file gone for as long as it
			// takes an event to arrive.
			parent.reloadPreservingIdentity()
			pendingReveal = [destination]
			endEditing()
			// Opened straight away, and only a file: a new file is made in order
			// to write in it. A folder is made to put things in, and there is
			// nothing to open.
			if kind == .file { onSelectFile?(destination, true) }
		}
	}

	/// The name checked before it reaches the disk, or nil with the field left
	/// standing.
	///
	/// Both halves refuse rather than overwrite, which is the rule everywhere
	/// else now, and both leave the field up with the keyboard in it so the name
	/// can be corrected rather than thrown away and retyped.
	private func accepted(_ name: String, kind: EntryName.Kind, in folder: URL) -> URL? {
		if let problem = EntryName.problem(
			name, kind: kind, showingHiddenFiles: Settings.shared.showHiddenFiles
		) {
			refuse(problem, kind: kind)
			return nil
		}
		let destination = folder.appendingPathComponent(name)
		guard !FileManager.default.fileExists(atPath: destination.path) else {
			refuse("“\(name)” already exists here.", kind: kind)
			return nil
		}
		return destination
	}

	/// Says why, and gives the keyboard back to the field that is still there.
	///
	/// **Only when the field has not got it already.** `makeFirstResponder` on
	/// the field that is already being edited is not a no-op: it tears the field
	/// editor down and builds another, `controlTextDidEndEditing` arrives, and
	/// the name is committed a second time — refused a second time, and reported
	/// a second time. Two identical toasts stacked up in the corner, which is
	/// how this was noticed; the same double report was there for a refused
	/// rename before the two paths shared this.
	private func refuse(_ problem: String, kind: EntryName.Kind) {
		Toast.post(
			"Cannot \(editing?.verb ?? "create") that \(kind == .file ? "file" : "folder")",
			detail: problem
		)
		guard let field = nameField, let window = outlineView.window else { return }
		let responder = window.firstResponder
		guard responder !== field, responder !== field.currentEditor() else { return }
		window.makeFirstResponder(field)
	}

	/// Writes the diagram out as a picture beside itself.
	///
	/// One file, like Rename and unlike Move to Trash. Four diagrams exported at
	/// once is four separate answers — this one overwrote a previous export,
	/// that one refused because something else already had the name, the third
	/// has a syntax error on line 12 — and there is nowhere to say four things
	/// that anybody would read. The menu greys itself over a multiple selection
	/// rather than doing three of the four and reporting the fourth.
	///
	/// From disk rather than from the editor's buffer, because the tree is about
	/// files: the pane's own Export is the one that draws unsaved edits, and it
	/// is the one that is looking at them.
	@objc private func contextExport(_ sender: NSMenuItem) {
		guard let node = contextNode, !node.isDirectory,
		      let code = sender.representedObject as? String,
		      let choice = DiagramExportMenu.choice(for: code)
		else { return }
		DiagramExportCommand.run(
			url: node.url, format: choice.format, theme: choice.theme,
			editable: choice.editable, projectRoot: project?.root
		)
	}

	/// What a file states about its own look, read from disk.
	///
	/// From disk rather than from an editor, for the same reason the export from
	/// here is: the tree is about files. It costs one read of a text file while a
	/// menu is being filled in, and only over a diagram.
	private func statedLook(of node: FileNode?) -> String? {
		guard let node, let text = try? String(contentsOf: node.url, encoding: .utf8) else {
			return nil
		}
		return DiagramExport.statedLook(of: node.url, source: text)
	}

	/// The same gesture without the menu, for verifying it end to end.
	func exportSelectionForTesting(
		_ format: DiagramFormat, theme: DiagramTheme? = nil, editable: Bool = false
	) {
		guard let node = contextNode, !node.isDirectory, DiagramExport.holdsADiagram(node.url) else {
			print("EXPORT: nothing to export")
			return
		}
		DiagramExportCommand.run(
			url: node.url, format: format, theme: theme ?? (Theme.current.isLight ? .light : .dark),
			editable: editable, projectRoot: project?.root
		) { written in
			print("EXPORT: \(written.map(\.lastPathComponent).joined(separator: ", "))")
		}
	}

	/// The submenu's two verbs without the menu, for driving them end to end;
	/// `menu` is the step that proves they are offered.
	func compareForTesting(history: Bool) {
		history ? contextCompareHistory() : contextCompareAgainstHead()
	}

	@objc private func contextCompareAgainstHead() {
		guard let node = contextNode, !node.isDirectory else { return }
		onCompareFile?(node.url)
	}

	@objc private func contextCompareHistory() {
		guard let node = contextNode, !node.isDirectory else { return }
		onShowFileHistory?(node.url)
	}

	/// What a right-click offers over whatever is selected, with the submenus
	/// spelled out and the shortcuts each item shows: a menu cannot be
	/// photographed while it is open, and the keys it writes down are half of
	/// what the menu is for.
	func contextMenuTitlesForTesting() -> [String] {
		guard let menu = outlineView.menu else { return [] }
		menuNeedsUpdate(menu)
		return menu.items.flatMap { item -> [String] in
			guard !item.isHidden else { return [] }
			func mark(_ entry: NSMenuItem) -> String {
				(entry.isEnabled ? "" : " (disabled)") + Self.shortcutText(entry)
			}
			let children = (item.submenu?.items ?? [])
				.filter { !$0.isSeparatorItem && !$0.isHidden }.map {
				"\(item.title) ▸ \($0.title)\(mark($0))"
			}
			return ["\(item.title)\(mark(item))"] + children
		}
	}

	/// An item's key equivalent the way the menu draws it.
	private static func shortcutText(_ item: NSMenuItem) -> String {
		guard let key = item.keyEquivalent.unicodeScalars.first else { return "" }
		let flags = item.keyEquivalentModifierMask
		var text = " "
		if flags.contains(.control) { text += "⌃" }
		if flags.contains(.option) { text += "⌥" }
		if flags.contains(.shift) { text += "⇧" }
		if flags.contains(.command) { text += "⌘" }
		switch Int(key.value) {
		case NSF2FunctionKey: text += "F2"
		case NSBackspaceCharacter, NSDeleteCharacter: text += "⌫"
		case NSCarriageReturnCharacter: text += "⏎"
		default: text += item.keyEquivalent.uppercased()
		}
		return text
	}

	/// Selects a picture that has just been written, once the tree has it.
	///
	/// Selected and not opened: an export happens while somebody is working on
	/// the diagram, and a PNG tab taking the front of the editor would be the
	/// export stealing their place. The file being shown to have arrived, in the
	/// folder they expected, is the whole of what is wanted.
	func revealExported(_ url: URL) {
		if rootNode?.node(for: url) != nil {
			selectWithoutOpening(url: url)
		} else {
			pendingReveal = [url]
		}
	}

	@objc private func contextRename() {
		// The same gesture from the menu, so there is one way it works.
		let row = contextNode.map { outlineView.row(forItem: $0) } ?? -1
		guard row >= 0 else { return }
		outlineView.selectRowIndexes([row], byExtendingSelection: false)
		beginRename(row: row)
	}

	@objc private func contextTrash() {
		trash(contextNodes)
	}

	/// ⌘⌫: whatever the tree has highlighted, and nothing to do with the pointer.
	///
	/// The selection rather than `contextNodes`, which starts from `clickedRow`:
	/// a row clicked earlier is still the clicked row long afterwards, and the
	/// keyboard should never trash something the keyboard cannot see it is about
	/// to trash.
	private func trashSelection() {
		let doomed = outlineView.selectedRowIndexes
		// Worked out before anything goes, because afterwards there is no row to
		// count back from.
		let successor = rowSurviving(above: doomed)
		trash(doomed.sorted().compactMap { outlineView.item(atRow: $0) as? FileNode })
		if let successor { pendingReveal = [successor] }
	}

	/// Where the selection goes once these rows have gone. `TreeSelection` has
	/// the rule and the tests; this hands it the rows.
	private func rowSurviving(above doomed: IndexSet) -> URL? {
		TreeSelection.surviving(above: Set(doomed)) { row in
			(outlineView.item(atRow: row) as? FileNode)?.url.path
		}
		.map { URL(fileURLWithPath: $0) }
	}

	/// Moves rows to the trash.
	///
	/// All of them, and the project root is never one of them. This is the one
	/// place several rows makes the work smaller rather than larger: `recycle`
	/// already takes an array, and moving three files to the trash stops being
	/// three gestures.
	private func trash(_ nodes: [FileNode]) {
		let urls = nodes.filter { $0 !== rootNode }.map(\.url)
		guard !urls.isEmpty else { return }
		// Trash rather than delete: recoverable, and no confirmation needed.
		//
		// The dictionary `recycle` answers with is original URL to the place in
		// the trash each file went, and it is kept because there is nowhere else
		// to get it: the trash renames on collision, so two files called `main.py`
		// from different folders do not both keep the name in there, and no
		// amount of looking afterwards says which is which. It was discarded here
		// until 0442, and that — rather than anything unwritten — is what made ⌘Z
		// after a delete impossible.
		//
		// Whatever did arrive is recorded even when the call also reports an
		// error, because `recycle` can refuse one file out of four and the other
		// three are still undoable.
		NSWorkspace.shared.recycle(urls) { [weak self] moved, error in
			DispatchQueue.main.async {
				if let error {
					Toast.post("Could not move that to the trash", detail: error.localizedDescription)
				}
				self?.remember(FileUndo.trashed(moved))
			}
		}
	}

	// MARK: - Moving and copying

	/// Where a drop or a paste aimed at a row actually lands.
	///
	/// A folder is itself. A *file* is the folder holding it, which is what
	/// pointing at a file in a list of files means — and a drop between two rows
	/// is the same answer, because the tree is the file system's order rather
	/// than a list: there is nothing to insert between two names. Nothing at all
	/// under the pointer is the project root.
	private func destinationFolder(for node: FileNode?) -> URL? {
		guard let node else { return project?.root }
		return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
	}

	/// Which way round a drag goes.
	///
	/// **A drag that starts in the tree moves, wherever it lands; ⌥ copies. A
	/// drag that arrives from another application always copies.**
	///
	/// The Finder moves within a volume and copies across one, and following
	/// that was the obvious answer — but the Finder's window names the volume
	/// every file is on and this one does not. A folder inside a project can be
	/// a mount point or a symlink onto another disk with nothing in the tree
	/// saying so, and a gesture that silently changes meaning on information the
	/// window never shows is a gesture nobody can predict. Inside one project
	/// the tree is one thing, so the drag means one thing.
	///
	/// Nothing in the implementation wanted the distinction either:
	/// `FileManager.moveItem` already does copy-then-remove when the two ends
	/// are on different volumes. Not proved here against a real pair of volumes.
	///
	/// Arriving from outside is the other way round, and there the Finder's rule
	/// is plainly right: an import that emptied the USB stick it came from would
	/// be a way to lose files, and the tree cannot even show what it took them
	/// from. So an external drop copies, full stop — ⌘ does not turn it into a
	/// move.
	private func operation(for info: NSDraggingInfo) -> FileTransfer.Operation {
		let isOurOwn = (info.draggingSource as? NSOutlineView) === outlineView
		guard isOurOwn else { return .copy }
		// The live modifier state rather than `draggingSourceOperationMask`.
		// AppKit is documented to narrow that mask by the modifier keys, but the
		// question here — is ⌥ down *now* — is one `NSEvent` answers without
		// depending on that narrowing being what it is thought to be.
		return NSEvent.modifierFlags.contains(.option) ? .copy : .move
	}

	/// Moves or copies files into a folder, and says once what did not happen.
	///
	/// Returns whether anything arrived, which is what `acceptDrop` answers with.
	@discardableResult
	private func transfer(
		_ sources: [URL], into folder: URL, operation: FileTransfer.Operation
	) -> Bool {
		let plan = FileTransfer.plan(
			sources, into: folder, operation: operation, projectRoot: project?.root,
			exists: { FileManager.default.fileExists(atPath: $0.path) }
		)

		// The ones that actually happened rather than the ones that were planned,
		// so nothing on the undo stack claims work the file system refused.
		var done: [FileTransfer.Transfer] = []
		var failures: [String] = []
		for transfer in plan.transfers {
			do {
				switch operation {
				case .move: try FileManager.default.moveItem(at: transfer.source, to: transfer.destination)
				case .copy: try FileManager.default.copyItem(at: transfer.source, to: transfer.destination)
				}
				done.append(transfer)
			} catch {
				failures.append("“\(transfer.source.lastPathComponent)”: \(error.localizedDescription)")
			}
		}
		let arrived = done.map(\.destination)
		// A move goes home again; a copy goes to the trash. Recorded before the
		// message, so a drop that half worked is still half undoable.
		remember(FileUndo.transferred(done, operation: operation) { Self.modificationDate(of: $0) })

		// One message for the whole drop, however many files it was. Skipping
		// rather than prompting is what keeps the gesture a gesture, and three
		// dialogs arriving afterwards instead of during would undo that.
		if let said = plan.summary(operation: operation, done: arrived.count, failures: failures) {
			Toast.post(said.title, detail: said.detail)
		}

		guard !arrived.isEmpty else { return false }
		// Opened, so there is somewhere for the files to appear.
		if let node = rootNode?.node(for: folder), node !== rootNode {
			outlineView.expandItem(node)
		}
		// The watcher rebuilds the tree a moment from now and every row is a
		// different object afterwards, so the selection follows the paths rather
		// than the nodes — the same problem rename has, and the same answer.
		pendingReveal = arrived
		return true
	}

	/// ⌘V, and ⌥⌘V which moves instead — the Finder's two keys.
	///
	/// Whatever is on the pasteboard as files, so it works with a copy made in
	/// the Finder as readily as with one made here.
	private func paste(_ operation: FileTransfer.Operation, into folder: URL?) {
		let files = FilePasteboard.files()
		guard !files.isEmpty, let folder else { return }
		transfer(files, into: folder, operation: operation)
	}

	/// The keyboard's paste: into the selected folder, or the folder holding the
	/// selected file, or the project root when nothing is selected.
	///
	/// From the selection rather than from `contextNodes`, which starts at
	/// `clickedRow`: a row clicked ten minutes ago is still the clicked row, and
	/// the keyboard must never put files somewhere the keyboard cannot see.
	private func pasteIntoSelection(_ operation: FileTransfer.Operation) {
		paste(operation, into: destinationFolder(for: selectedNodes().first))
	}

	@objc private func contextPaste() { paste(.copy, into: contextParentDirectory) }
	@objc private func contextPasteAsMove() { paste(.move, into: contextParentDirectory) }

	/// The same two gestures without a pasteboard or a mouse, for verifying them
	/// end to end: the files named, dropped into the folder named.
	func dropForTesting(_ sources: [URL], into folder: URL, move: Bool) {
		let arrived = transfer(sources, into: folder, operation: move ? .move : .copy)
		print("TREE drop: \(move ? "move" : "copy") \(sources.count) → \(folder.lastPathComponent) "
			+ "arrived=\(arrived)")
	}

	/// ⌘C then ⌘V, driven through the real pasteboard so what ⌘C writes is what
	/// ⌘V reads.
	func pasteForTesting(move: Bool) {
		pasteIntoSelection(move ? .move : .copy)
	}

	// MARK: - Undo

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
	private let fileUndo = UndoManager()

	/// What the manager holds on to, which must not be this controller.
	///
	/// `registerUndo(withTarget:handler:)` keeps a strong reference to its
	/// target, so registering `self` would leave the navigator — and the whole
	/// tree behind it — alive after its window had gone. The handler is given
	/// the target and reaches the navigator weakly through it.
	private lazy var undoTarget: FileUndoTarget = {
		let target = FileUndoTarget()
		target.navigator = self
		return target
	}()

	/// The manager, or nil while a name is being edited on a row.
	///
	/// Nil then because the rename field is a *subview of the outline view*, so
	/// the field editor's responder chain runs straight through it: without this
	/// the tree would answer the ⌘Z meant to take back a mistyped letter, and
	/// undo a delete instead. Answering nil makes `NavigatorOutlineView`
	/// transparent to `undo:` — see its `responds(to:)` — so the chain carries on
	/// past the tree to the window's undo manager, which is where the field
	/// editor's text undo lives.
	fileprivate var fileUndoManager: UndoManager? { nameField == nil ? fileUndo : nil }

	/// Puts one gesture on the stack, under the name the Edit menu will show.
	///
	/// A gesture that did nothing is not recorded: a ⌘Z that pops an entry and
	/// has nothing to do would silently eat the one before it, which is the same
	/// "cannot be trusted" this was written to avoid.
	private func remember(_ action: FileUndo.Action) {
		guard !action.isEmpty else { return }
		fileUndo.registerUndo(withTarget: undoTarget) { target in
			target.navigator?.takeBack(action)
		}
		fileUndo.setActionName(action.gesture.title)
	}

	/// Puts one entry on this stack for a whole workspace edit.
	///
	/// **On the tree's stack, and this is the only place it can be.** A rename
	/// through a language server changes forty files, most of which nothing in
	/// this window has open; a `TextDocument`'s own `UndoTree` is that document's
	/// history and knows nothing of the other thirty-nine, and a rename that
	/// also moved `Foo.java` to `Bar.java` is not a text edit at all. This stack
	/// already holds the gestures that act on files rather than on text, which is
	/// exactly what a workspace edit is, and it is already the stack somebody's
	/// ⌘Z reaches from the tree.
	///
	/// One entry, however many files — the rule `remember` above settled, for the
	/// same reason: forty presses that each take back one file's worth of a
	/// refactoring which only makes sense whole is not an undo.
	func rememberWorkspaceEdit(
		_ plan: WorkspaceEditPlan, title: String, undo: @escaping (WorkspaceEditPlan) -> Void
	) {
		guard !plan.isEmpty else { return }
		fileUndo.registerUndo(withTarget: undoTarget) { _ in undo(plan) }
		fileUndo.setActionName(title)
	}

	/// When a file was last written, for the check that stops an undo throwing
	/// away work somebody did after the gesture.
	private static func modificationDate(of url: URL) -> Date? {
		(try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
	}

	/// Takes one gesture back, or says in a sentence why it cannot.
	///
	/// Silent when it works, because the tree showing the file where it belongs
	/// is the whole of what was asked for. Never silent when it does not: an
	/// emptied trash, a name taken since, a folder that has itself gone are all
	/// ordinary, and each gets said.
	///
	/// Nothing is registered back on the stack, so there is no redo — see
	/// `NavigatorOutlineView`, which does not answer `redo:` for that reason.
	fileprivate func takeBack(_ action: FileUndo.Action) {
		let reversal = FileUndo.reverse(
			action,
			exists: { FileManager.default.fileExists(atPath: $0.path) },
			modified: { Self.modificationDate(of: $0) }
		)

		var restored: [URL] = []
		var failures: [String] = []
		for restore in reversal.restores {
			do {
				try FileManager.default.moveItem(at: restore.from, to: restore.to)
				restored.append(restore.to)
			} catch {
				failures.append("“\(restore.to.lastPathComponent)”: \(error.localizedDescription)")
			}
		}

		guard !reversal.discards.isEmpty else {
			finish(action, reversal, restored: restored, discarded: 0, failures: failures)
			return
		}
		// The other half of the family, and the only undo in the app that takes
		// something away: it goes to the trash rather than being unlinked, so
		// undo is not the one operation here that deletes outright.
		//
		// The message waits for this rather than counting the files as gone the
		// moment they are handed over — `recycle` is asynchronous and can refuse,
		// and a summary written before the answer arrives would be a guess.
		NSWorkspace.shared.recycle(reversal.discards) { [weak self] moved, error in
			DispatchQueue.main.async {
				var failures = failures
				if let error { failures.append(error.localizedDescription) }
				self?.finish(
					action, reversal, restored: restored, discarded: moved.count,
					failures: failures
				)
			}
		}
	}

	/// The one message the whole undo gets, and the selection put where the
	/// files went back to.
	private func finish(
		_ action: FileUndo.Action, _ reversal: FileUndo.Reversal,
		restored: [URL], discarded: Int, failures: [String]
	) {
		// One message for the whole gesture, however many files it was — the same
		// rule a drop keeps, and for the same reason: ⌘Z is one gesture.
		if let said = reversal.summary(
			gesture: action.gesture, done: restored.count + discarded, failures: failures
		) {
			Toast.post(said.title, detail: said.detail)
		}

		guard !restored.isEmpty else { return }
		// Opened, so there is somewhere for the files to come back to — the
		// folder they were in may well have been folded away since.
		for url in restored {
			let folder = url.deletingLastPathComponent()
			if let node = rootNode?.node(for: folder), node !== rootNode {
				outlineView.expandItem(node)
			}
		}
		// The watcher rebuilds a moment from now and every row is a different
		// object afterwards, so the selection follows the paths.
		pendingReveal = restored
	}

	/// ⌘Z sent straight at the tree, for scripts that want the file half without
	/// asking the responder chain anything. Naming what is on the stack is the
	/// only way to tell "⌘Z did the right thing" from "⌘Z did nothing".
	func undoForTesting() {
		print("TREE undo: can=\(fileUndo.canUndo) action=\(fileUndo.undoActionName)")
		outlineView.undo(nil)
	}

	// MARK: - Keyboard

	/// Returns true when the event was consumed.
	///
	/// Up/Down/Left/Right are left to `NSOutlineView`, which already moves the
	/// selection and expands or collapses rows correctly — and moving the
	/// selection is what shows the file, so there is nothing to add to them.
	private func handleKeyDown(_ event: NSEvent) -> Bool {
		// Nothing on this list while a name is being edited on a row. The field
		// has the keyboard then, so these events do not normally reach here at
		// all — but ⌘⌫ reaching here would move the file being renamed to the
		// trash, and that is not a mistake worth leaving one responder-chain
		// accident away. Return is the same story with a smaller cost: in the
		// field it commits the name, which `control(_:textView:doCommandBy:)`
		// does.
		guard nameField == nil else { return false }

		// ⌥⌘V, the Finder's "Move Item Here". It arrives here rather than through
		// the responder chain because AppKit only dispatches key equivalents it
		// finds in the *main* menu, and the Edit menu's Paste is ⌘V alone —
		// which is the one that does reach `NavigatorOutlineView.paste`.
		//
		// Matched by its character and not by a key code, unlike everything in
		// the switch below: a key code is a position on an ANSI keyboard, and
		// this is the only binding here that is a letter rather than a position.
		// `charactersIgnoringModifiers` drops everything but Shift, so ⌥ does not
		// turn the "v" into a "√".
		if event.modifierFlags.intersection([.command, .option, .control, .shift])
			== [.command, .option],
			event.charactersIgnoringModifiers?.lowercased() == "v"
		{
			pasteIntoSelection(.move)
			return true
		}

		switch event.keyCode {
		case 36, 76: // Return, Keypad Enter
			// Return opens, which is what every editor does. It renamed for a
			// week, after the Finder, and the cost was that the one key everyone
			// presses to open a file no longer opened it.
			//
			// ⌥Return renames instead — one of the two rename keys, and the one
			// for hands that had learned Return meant rename.
			if event.modifierFlags.contains(.option) {
				beginRename()
			} else {
				openSelection(focusEditor: true)
			}
			return true
		case 120: // F2
			// The other rename key, and the one the menu writes down: F2 renames
			// in VS Code and in every file manager that is not the Finder.
			// Deliberately two keys for one gesture — there is nothing to
			// remember wrong, at the cost of a second binding to keep working.
			beginRename()
			return true
		case 51 where event.modifierFlags.contains(.command): // ⌘⌫
			// The Finder's key for it, reached for repeatedly before it did
			// anything. The whole selection, since `recycle` takes a list.
			trashSelection()
			return true
		case 125 where event.modifierFlags.contains(.command): // ⌘↓
			// Kept, though Return now does it: it costs nothing, and somebody's
			// hands may already know it from the week Return did not.
			openSelection(focusEditor: true)
			return true
		case 49: // Space
			// **Quick Look for what Quick Look is for.** An image, a video, a
			// PDF: the provisional open this used to do put a notice in the
			// editor with a Quick Look button on it, which is two presses to
			// reach the thing Space reaches everywhere else on this machine.
			//
			// Everything else keeps the provisional open, which is what Space
			// is for in a tree of source files — and `offersQuickLook` is the
			// same list the notice uses, so the two cannot disagree about what
			// the system will actually render.
			if !quickLookSelection().isEmpty {
				outlineView.showQuickLook()
			} else {
				openSelection(focusEditor: false)
			}
			return true
		default:
			return false
		}
	}

	/// What the preview panel is showing, and whether the tree is driving it.
	var quickLookReportForTesting: String { outlineView.quickLookReportForTesting }

	/// The selected files Quick Look would show something for, in tree order.
	///
	/// Empty when there is nothing worth previewing, which is what decides
	/// whether Space previews or opens. A directory is never previewable here:
	/// Quick Look draws one as a large folder icon, and Space on a folder in
	/// this tree has always folded it.
	private func quickLookSelection() -> [URL] {
		outlineView.selectedRowIndexes.sorted().compactMap { row in
			guard let node = outlineView.item(atRow: row) as? FileNode, !node.isDirectory
			else { return nil }
			guard FileNotice.offersQuickLook(forExtension: node.url.pathExtension) else {
				return nil
			}
			return node.url
		}
	}

	/// Opens the panel from the menu, on the row that was clicked.
	@objc private func contextQuickLook() {
		guard let node = contextNode else { return }
		// The clicked row, and the selection only when the click was inside it:
		// right-clicking one file with three selected previews that one, as it
		// does in the Finder.
		let selected = quickLookSelection()
		if !selected.contains(node.url) {
			outlineView.selectRowIndexes(
				IndexSet(integer: outlineView.row(forItem: node)), byExtendingSelection: false
			)
		}
		outlineView.showQuickLook()
	}

	private func openSelection(focusEditor: Bool) {
		// One row, for the same reason a selection change opens only one: four
		// tabs from one keystroke, and the last one to arrive is whichever the
		// tree happened to order last.
		guard outlineView.numberOfSelectedRows == 1 else { return }
		let row = outlineView.selectedRow
		guard row >= 0 else { return }
		if let dependency = outlineView.item(atRow: row) as? DependencyNode {
			toggle(dependency)
			return
		}
		guard let node = outlineView.item(atRow: row) as? FileNode else { return }

		if node.isDirectory {
			// Return on a directory toggles it, which is what IDEA does.
			if outlineView.isItemExpanded(node) {
				outlineView.collapseItem(node)
			} else {
				outlineView.expandItem(node)
			}
			return
		}
		onSelectFile?(node.url, focusEditor)
	}

	/// Gives the tree keyboard focus, so arrow keys work without a click first.
	func focusTree() {
		view.window?.makeFirstResponder(outlineView)
		if outlineView.selectedRow < 0, outlineView.numberOfRows > 0 {
			outlineView.selectRowIndexes([0], byExtendingSelection: false)
		}
	}

	/// Folds the whole tree away, leaving the root.
	///
	/// Not the root itself: collapsing that would leave one row and nothing to
	/// click, which is a worse place to start again from than the top level.
	func collapseAll() {
		guard let rootNode else { return }
		let selected = (outlineView.item(atRow: outlineView.selectedRow) as? FileNode)?.url

		// Backwards, because collapsing a row removes the rows under it and the
		// indices of everything after them.
		for row in stride(from: outlineView.numberOfRows - 1, through: 0, by: -1) {
			let item = outlineView.item(atRow: row)
			// The other two roots fold away with everything else, their own rows
			// included: "collapse all" means all.
			if let dependency = item as? DependencyNode {
				outlineView.collapseItem(dependency)
				continue
			}
			if let session = item as? SessionNode {
				outlineView.collapseItem(session)
				continue
			}
			guard let node = item as? FileNode, node !== rootNode else { continue }
			outlineView.collapseItem(node)
		}
		outlineView.expandItem(rootNode)

		// Whatever was selected is probably inside something that just folded up,
		// so the selection moves to the folder it went into. Losing it entirely
		// would send the next arrow key back to the top of the tree.
		guard var url = selected else { return }
		while outlineView.row(forItem: rootNode.node(for: url)) < 0 {
			let parent = url.deletingLastPathComponent()
			guard parent.path != url.path, parent.path.hasPrefix(rootNode.url.path) else { return }
			url = parent
		}
		selectWithoutOpening(url: url)
	}

	/// Folds chains of single-directory folders into one row, or unfolds them.
	///
	/// The rebuild is deliberately not done here. Setting the preference posts
	/// `.abydosSettingsChanged`, and every window's `applySettings` puts its own
	/// tree back — the same route Show Hidden Files takes, and the reason a
	/// second window does not sit there in the old shape.
	func toggleCompactPackages() {
		Settings.shared.compactsPackages.toggle()
	}

	/// Finds the file the editor is showing.
	///
	/// The tree already follows along when tabs change; this is for after
	/// somebody has browsed away from it and wants to know where they were.
	func selectFileInEditor() {
		guard let url = currentEditorFile?() else { return }
		selectWithoutOpening(url: url)
		// **Asked, and unanswerable — so it says so.** This gesture used to do
		// nothing at all for a file the tree has no row for: the selection
		// stayed where it was, and the only way to tell a reveal that landed
		// somewhere from one that could not was to look at the pane and notice
		// nothing had moved. That is the failure item 539 was actually reported
		// as. Only on this gesture, and never on a tab switch, which calls the
		// same reveal a hundred times an hour and must stay silent.
		if let reason = placementProblem(for: url) {
			Toast.post(
				"\(url.lastPathComponent) is not in the tree",
				detail: reason + "\n" + url.path,
				kind: .information
			)
		}
		view.window?.makeFirstResponder(outlineView)
	}

	/// Why a file has no row, or nil when it has one.
	///
	/// The sentence names what is true of *this* file rather than a fixed
	/// apology — the same rule the section's own notes follow. A file inside no
	/// project and no package is a different situation from one whose project
	/// is a different window's.
	func placementProblem(for url: URL) -> String? {
		if dependencies?.locate(url) != nil { return nil }
		if sessions?.session(containing: url) != nil { return nil }
		if rootNode?.node(for: url) != nil { return nil }
		guard let project else { return "no project is open in this window." }
		let path = FilePath.canonical(url)
		guard !path.hasPrefix(FilePath.canonical(project.root) + "/") else {
			// Inside the project and still unfound: a filter is hiding it, or
			// the folder above it has not been listed. Worth telling apart from
			// the case below, because the answer is different — one is a
			// setting, the other is nothing anybody can do.
			return "it is inside the project but hidden by a filter."
		}
		return "it is outside the project, no package or toolchain in Dependencies "
			+ "holds it, and no session left it behind."
	}

	/// Expands the root's immediate children, matching how IDEA shows a freshly
	/// opened project rather than a single collapsed row.
	func expandTopLevel() {
		guard let rootNode else { return }
		outlineView.expandItem(rootNode)
		for child in rows(under: rootNode) where child.isDirectory && !child.isExcluded {
			outlineView.expandItem(child)
		}
	}

	/// Selects a file without opening it.
	///
	/// Used when the editor switches tabs: the tree should follow along, but
	/// must not call back and reopen the file it was just told about.
	func selectWithoutOpening(url: URL) {
		selectWithoutOpening(urls: [url])
	}

	/// The same for several files, which is what a drop or a paste lands.
	func selectWithoutOpening(urls: [URL]) {
		let wasSilent = isSelectingSilently
		isSelectingSilently = true
		reveal(urls: urls)
		isSelectingSilently = wasSilent
	}

	// MARK: - Verification

	/// Sends a key to the tree as the keyboard would, so what arrowing through
	/// it actually does can be checked from outside.
	///
	/// The modifiers are part of the event, so ⇧↓ selects a run of rows and ⌥⏎,
	/// ⌘⌫ and ⌘↓ are askable at all — each of them is a different gesture from
	/// the key without them.
	func pressKeyForTesting(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) {
		// While a name is being edited the field has the keyboard, and taking it
		// back here would end the edit before the key ever arrived — which is
		// exactly what "⌘⌫ must not trash the file being renamed" has to be able
		// to ask about. So the key goes wherever the keyboard actually is.
		if nameField == nil { view.window?.makeFirstResponder(outlineView) }
		// The characters matter: `interpretKeyEvents` maps those, not the key
		// code, and an event with none does nothing at all.
		let characters: String
		switch keyCode {
		case 126: characters = String(UnicodeScalar(NSUpArrowFunctionKey)!)
		case 125: characters = String(UnicodeScalar(NSDownArrowFunctionKey)!)
		case 123: characters = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
		case 124: characters = String(UnicodeScalar(NSRightArrowFunctionKey)!)
		case 120: characters = String(UnicodeScalar(NSF2FunctionKey)!)
		case 36: characters = "\r"
		case 49: characters = " "
		case 51: characters = String(UnicodeScalar(NSDeleteCharacter)!)
		case 53: characters = "\u{1B}" // Escape
		// The one letter the tree binds, and the reason `handleKeyDown` matches
		// ⌥⌘V on its character: the code is where "v" sits on an ANSI keyboard.
		case 9: characters = "v"
		default: characters = ""
		}
		guard let event = NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: modifiers,
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: view.window?.windowNumber ?? 0, context: nil,
			characters: characters, charactersIgnoringModifiers: characters,
			isARepeat: false, keyCode: keyCode
		) else { return }
		// The field editor when a name is being edited, so a key pressed during
		// a rename does to the field what it would really do to it.
		let target: NSResponder = nameField?.currentEditor() ?? outlineView
		target.keyDown(with: event)
	}

	/// The name in the field standing on a row, or nil when nothing is being
	/// renamed — the difference between Return opening a file and Return doing
	/// what it used to do.
	var renamingNameForTesting: String? { nameField?.stringValue }

	/// Rebuilds the tree the way a filesystem event does, so a selection can be
	/// checked to have survived one.
	func reloadForTesting() {
		reloadTree()
	}

	/// What ⌘C would put on the pasteboard — the same closure the Edit menu
	/// reaches, asked directly, so what several selected rows copy can be read
	/// without a key window to send an action through.
	///
	/// The text form of it, which `FilePasteboardTests` proves is what AppKit
	/// joins the per-item strings into: the harness's output is unchanged by ⌘C
	/// having become a file copy as well.
	func copyTextForTesting() -> String {
		let files = outlineView.copyFiles?() ?? []
		guard !files.isEmpty else { return "nothing" }
		return files.map(\.path).joined(separator: "\n")
	}

	/// ⌘C for real, onto the general pasteboard, so a ⌘V after it has something
	/// to read.
	func copyToPasteboardForTesting() {
		FilePasteboard.write(selectedNodes().map(\.url))
	}

	/// What the tree has highlighted, and how many rows it is showing.
	///
	/// Every selected row, joined — one row reads exactly as it always did, so
	/// the harness's existing output is unchanged, and several are visible at
	/// all, which is what checking that a multi-row selection survives a reload
	/// needs.
	var selectionForTesting: (name: String, rows: Int) {
		let selected = outlineView.selectedRowIndexes.sorted()
		guard !selected.isEmpty else { return ("nothing@-1", outlineView.numberOfRows) }
		let names = selected.map { row -> String in
			let item = outlineView.item(atRow: row)
			// A dependency row is named too, since 508: the selection landing on
			// a package or on the section is a thing a script has to be able to
			// tell from the selection landing on nothing at all.
			if let node = item as? FileNode { return "\(node.name)@\(row)" }
			if let node = item as? DependencyNode { return "\(node.title)@\(row)" }
			if let node = item as? SessionNode { return "\(node.title)@\(row)" }
			return "nothing@\(row)"
		}
		return (names.joined(separator: "+"), outlineView.numberOfRows)
	}

	/// Every row the tree is showing, with its depth.
	///
	/// The Dependencies section cannot be checked any other way: it is not on
	/// disk, so `ls:` says nothing about it, and a screenshot proves it is drawn
	/// without saying what it says. Each row is `depth·name — subtitle`, which
	/// is exactly what somebody reads off the pane.
	func rowsForTesting() -> [String] {
		(0..<outlineView.numberOfRows).map { row in
			let item = outlineView.item(atRow: row)
			let indent = String(repeating: "  ", count: outlineView.level(forRow: row))
			// Which row is selected, because "the selection survived a rebuild"
			// is the claim and a list of names cannot make it.
			let mark = outlineView.selectedRowIndexes.contains(row) ? "  <-" : ""
			if let node = item as? DependencyNode {
				return indent + node.title + (node.subtitle.map { " — " + $0 } ?? "") + mark
			}
			if let node = item as? SessionNode {
				return indent + node.title + (node.subtitle.map { " — " + $0 } ?? "") + mark
			}
			guard let node = item as? FileNode else { return indent + "?" }
			// **And the colour it is drawn in.** A report that says which rows
			// exist cannot catch a row that exists in the wrong colour, which is
			// the whole of what a git tint is — `.gitignore` rules going
			// unnoticed looks exactly like a tree that is working.
			let tint: String
			switch node.gitStatus {
			case .unmodified:  tint = ""
			case .ignored:     tint = "  ignored"
			case .unversioned: tint = "  untracked"
			case .added:       tint = "  added"
			case .modified:    tint = "  modified"
			case .deleted:     tint = "  deleted"
			case .conflicted:  tint = "  conflicted"
			}
			return indent + title(for: node) + tint + mark
		}
	}

	/// The section as the model has it, whether or not anything is expanded —
	/// the half `rowsForTesting` cannot answer, since a folded row has no rows
	/// under it to print.
	func dependencyReportForTesting() -> [String] {
		dependencies?.report() ?? ["no dependencies section"]
	}

	/// Opens the Dependencies section and scrolls to it.
	///
	/// The section sits below the whole project tree, which on a repository of
	/// eight subprojects is several screens down — so a script that wants to
	/// photograph it has to be able to ask for it rather than arrow there.
	func openDependenciesForTesting(groups: Bool) {
		guard let dependencies else { return }
		outlineView.expandItem(dependencies.root)
		if groups {
			for child in dependencies.root.childNodes { outlineView.expandItem(child) }
		}
		let row = outlineView.row(forItem: dependencies.root)
		guard row >= 0 else { return }
		// The last row first, so the section ends up at the top of the pane
		// rather than at its bottom edge: `scrollRowToVisible` does the least it
		// can, and a row already on screen moves nothing.
		outlineView.scrollRowToVisible(outlineView.numberOfRows - 1)
		outlineView.scrollRowToVisible(row)
		outlineView.selectRowIndexes([row], byExtendingSelection: false)
	}

	/// What a **real right-click** offers over each row of the sessions root.
	///
	/// Through `NSView.menu(for:)` with a synthetic right-click at the row's own
	/// rectangle, which is the gesture rather than the delegate: the previous
	/// check called `menuNeedsUpdate` directly with a row *selected*, and a
	/// selected row and a clicked row are not the same thing.
	func sessionRightClicksForTesting() -> String {
		guard let sessions else { return "no sessions" }
		outlineView.expandItem(sessions)

		var said: [String] = []
		for row in 0..<outlineView.numberOfRows {
			guard let node = outlineView.item(atRow: row) as? SessionNode else { continue }
			let rect = outlineView.rect(ofRow: row)
			let inView = NSPoint(x: rect.midX, y: rect.midY)
			guard let event = NSEvent.mouseEvent(
				with: .rightMouseDown,
				location: outlineView.convert(inView, to: nil),
				modifierFlags: [], timestamp: 0,
				windowNumber: outlineView.window?.windowNumber ?? 0,
				context: nil, eventNumber: 0, clickCount: 1, pressure: 1
			) else { continue }

			let menu = outlineView.menu(for: event)
			// **`update()` is not the delegate.** `NSMenu.update()` on a menu
			// that is not on screen validates items and does not necessarily ask
			// a delegate to rebuild — so the state read here is whatever was set
			// last. The delegate is called directly beside it, which is what
			// AppKit does before showing the menu.
			menu?.update()
			let beforeDelegate = (menu?.items ?? []).filter { !$0.isHidden }.map(\.title)
			if let menu { menuNeedsUpdate(menu) }
			let offered = (menu?.items ?? []).filter { !$0.isHidden }.map(\.title)
			_ = beforeDelegate
			let kind: String
			switch node.row {
			case .section: kind = "root"
			case .session: kind = "session"
			}
			said.append("\(kind)@\(row) clicked=\(outlineView.clickedRow) "
				+ "session=\(contextSession?.id.prefix(8) ?? "nil") "
				+ "offers=[\(offered.joined(separator: ", "))]")
		}
		return said.joined(separator: "\n    ")
	}

	/// What the context menu offers over a session's row, and what its one item
	/// copies — for `session-menu`.
	func sessionMenuForTesting() -> String {
		guard let sessions, let first = sessions.childNodes.first else { return "no sessions" }
		outlineView.expandItem(sessions)
		let row = outlineView.row(forItem: first)
		guard row >= 0 else { return "no row for the first session" }
		outlineView.selectRowIndexes([row], byExtendingSelection: false)

		// **The same reader the `menu` step uses**, and that is the point: the
		// first version of this called `menu.update()` and read the items itself,
		// which reported all seventeen file items as offered while the menu on
		// screen showed one. `contextMenuTitlesForTesting` calls the delegate
		// directly, so what it prints is what a right-click gets.
		let offered = contextMenuTitlesForTesting()
		contextCopyResumeCommand()
		return "offers=[\(offered.joined(separator: ", "))] "
			+ "copied=\(NSPasteboard.general.string(forType: .string) ?? "nothing")"
	}

	/// Opens the Claude Sessions root and brings it into view, which on a
	/// repository of this size is several screens down.
	func openSessionsForTesting(files: Bool) {
		guard let sessions else { return }
		outlineView.expandItem(sessions)
		if files {
			for child in sessions.childNodes { outlineView.expandItem(child) }
		}
		let row = outlineView.row(forItem: sessions)
		guard row >= 0 else { return }
		// The last row first, so the root ends up at the top of the pane rather
		// than at its bottom edge — the same reason `deps-open` does it.
		outlineView.scrollRowToVisible(outlineView.numberOfRows - 1)
		outlineView.scrollRowToVisible(row)
		outlineView.selectRowIndexes([row], byExtendingSelection: false)
	}

	/// What roots the tree has and what is under the third of them, for
	/// `--tree-roots`.
	func rootsForTesting() -> String {
		var said = ["project=\(rootNode?.name ?? "none")"]
		said.append("dependencies=\(dependencies == nil ? "absent" : "present")")
		guard let sessions else {
			said.append("sessions=absent")
			return said.joined(separator: " ")
		}
		said.append("sessions=\(sessions.childNodes.count)")
		for node in sessions.childNodes.prefix(4) {
			said.append("\n    \(node.title) [\(node.subtitle ?? "")]")
		}
		return said.joined(separator: " ")
	}

	/// Opens the section down to a file and selects it, the way activating a tab
	/// on a file outside the project does.
	/// Rebuilds the Claude Sessions root from the sessions it already holds, so
	/// what a rebuild costs can be asked for on purpose.
	///
	/// **New node objects, which is the whole point.** `refreshSessions` returns
	/// early unless a session's size or liveness has moved, and what breaks when
	/// it does *not* return early is that `reloadData` throws away every row's
	/// identity. This is that moment, without having to make an agent write a
	/// file to get it.
	func rebuildSessionsForTesting() {
		guard let sessions else {
			print("TREE sessions-rebuild: no sessions")
			return
		}
		show(SessionNode.build(sessions.sessions))
	}

	func revealForTesting(_ path: String) {
		let url = URL(fileURLWithPath: path)
		selectWithoutOpening(url: url)
		let package = dependency(containing: url)
		// Which root claimed it, because three can and only one did.
		let claimed = dependencies?.locate(url) != nil
			? "dependencies"
			: (sessions?.session(containing: url) != nil ? "sessions" : "tree")
		print("TREE reveal: \(url.lastPathComponent) "
			+ "claimed-by=\(claimed) "
			+ "package=\(package?.name ?? "none") "
			+ "origin=\(package?.origin ?? "none") "
			+ "selection=\(selectionForTesting.name) "
			+ "unplaceable=\(placementProblem(for: url) ?? "no")")
	}

	/// Selects and scrolls to a file, expanding ancestors as needed.
	func reveal(url: URL) {
		reveal(urls: [url])
	}

	/// The same for several files at once.
	///
	/// Every ancestor is expanded first and the selection set once at the end,
	/// rather than a row at a time: expanding renumbers the rows under it, so
	/// indices collected as they went would name the wrong files by the time the
	/// last folder opened. The topmost is what gets scrolled to.
	func reveal(urls: [URL]) {
		guard !urls.isEmpty else { return }

		// Held back while the dependency walk is out, and done again when it
		// lands. Without this a reveal during those milliseconds answers from
		// `.build` rather than from the Dependencies section — see
		// `deferredReveals` for why that is the wrong row.
		if isReadingDependencies {
			deferredReveals.append(contentsOf: urls)
			return
		}

		// Before anything is looked up: a file from a toolchain has no row yet,
		// and this is the moment its path is in hand. Gives the section a row
		// for the toolchain if one of these came out of it, so the lookup below
		// finds it like any other.
		noteToolchains(for: urls)

		var found: [FileNode] = []
		for url in urls {
			// **The Dependencies section wins.** A file under
			// `.build/checkouts/Cadova` is reachable both ways — the section, and
			// the `.build` folder in the ordinary tree — and only one of the two
			// can say which package it is and where that package came from. That
			// is the whole of what item 508 was filed for, so a reveal that
			// landed in `.build` would answer the question with the one row that
			// does not.
			if let located = dependencies?.locate(url) {
				for node in located.chain { outlineView.expandItem(node) }
				let target = row(for: located.node)
				if let package = located.chain.last, let fileRoot = package.fileRoot {
					expandAncestors(of: target, under: fileRoot)
				}
				found.append(target)
				continue
			}
			// **Then Claude Sessions**, which is the third and last claimant.
			// The order never has to be argued about, because nothing lives in
			// two of them: a package's sources are not under `/tmp/claude-*`,
			// and a session's scratch directory is not inside the project.
			if let sessions, let session = sessions.session(containing: url),
			   let fileRoot = session.fileRoot, let node = fileRoot.node(for: url) {
				outlineView.expandItem(sessions)
				outlineView.expandItem(session)
				let target = row(for: node)
				expandAncestors(of: target, under: fileRoot)
				found.append(target)
				continue
			}
			guard let rootNode, let node = rootNode.node(for: url) else { continue }
			let target = row(for: node)
			expandAncestors(of: target, under: rootNode)
			found.append(target)
		}
		guard !found.isEmpty else { return }

		let rows = found.map { outlineView.row(forItem: $0) }.filter { $0 >= 0 }.sorted()
		guard let first = rows.first else { return }
		outlineView.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
		outlineView.scrollRowToVisible(first)
	}

	/// Opens every folder between a node and the root it was found under.
	///
	/// Outermost first, and the rows are asked for only once everything is open
	/// — expanding renumbers the rows beneath it, so an index collected on the
	/// way would name the wrong file by the time the last folder opened.
	private func expandAncestors(of node: FileNode, under root: FileNode) {
		var ancestors: [FileNode] = []
		var current: FileNode? = node
		while let parent = current?.parentNode(in: root) {
			ancestors.append(parent)
			current = parent
		}
		// A directory folded into the row below it has no row of its own, and
		// `expandItem` on something the outline has never been handed does
		// nothing — silently, which is the failure that would be hard to see.
		// The row that stands for it is further down and is opened in its turn.
		for ancestor in ancestors.reversed() where !(compactsPackages && ancestor.isCompactedAway) {
			outlineView.expandItem(ancestor)
		}
	}

	/// The row a node is drawn on: itself, unless compaction has folded it into
	/// the row below it.
	///
	/// A file is always its own row, so this only ever moves a *directory* — the
	/// reveal of a folder inside a chain, which would otherwise select nothing.
	private func row(for node: FileNode) -> FileNode {
		compactsPackages ? node.compactedRow : node
	}

	/// Which package a file belongs to, for anything outside the tree that wants
	/// to say where it came from.
	func dependency(containing url: URL) -> ExternalDependency? {
		dependencies?.package(containing: url)
	}
}

private extension FileNode {
	/// Walks from a known root, since `parent` is weak and may be nil for nodes
	/// reached by path lookup.
	func parentNode(in root: FileNode) -> FileNode? {
		let parentURL = url.deletingLastPathComponent().standardizedFileURL
		guard parentURL.path != url.path, parentURL.path.hasPrefix(root.url.path) else { return nil }
		return root.node(for: parentURL)
	}
}

// MARK: - Outline data

/// The row's name field while it is being edited.
///
/// Return commits, Escape abandons, and clicking elsewhere commits — which is
/// what every other in-place rename on this machine does, and what somebody who
/// has typed a name and looked away expects to have happened. Abandoning is the
/// one thing the two gestures differ on: a rename keeps the old name, and a new
/// row goes away entirely, having never been written.
extension ProjectNavigatorViewController: NSTextFieldDelegate {
	func control(
		_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
	) -> Bool {
		switch selector {
		case #selector(NSResponder.insertNewline(_:)):
			commitName()
			return true
		case #selector(NSResponder.cancelOperation(_:)):
			endEditing()
			return true
		default:
			return false
		}
	}

	func controlTextDidEndEditing(_ notification: Notification) {
		// Only when the field is going of its own accord — committing already
		// takes it away, and this would otherwise commit a name it just refused.
		//
		// A new row commits here too, the way the Finder's does: clicking away
		// from a folder called `untitled folder` leaves you with a folder called
		// `untitled folder`, not with nothing. Escape is the way to mean nothing.
		guard nameField != nil, notification.object as? NSTextField === nameField else { return }
		commitName()
	}
}

extension ProjectNavigatorViewController: NSOutlineViewDataSource, NSOutlineViewDelegate,
	NSMenuDelegate, NSMenuItemValidation {
	/// Whether a chain of directories each holding one directory is drawn as one
	/// row. Off by default; the header's third button turns it on.
	private var compactsPackages: Bool { Settings.shared.compactsPackages }

	/// The rows under a directory — its children, or the folded ones.
	///
	/// Every walk in this file goes through here rather than through `children`
	/// directly, which is what stops the outline and the four hand-written walks
	/// disagreeing about which rows exist.
	private func rows(under node: FileNode) -> [FileNode] {
		compactsPackages ? node.compactedChildren : node.children
	}

	/// What a row is called: its own name, or the whole chain folded into it.
	private func title(for node: FileNode) -> String {
		compactsPackages ? node.compactedName : node.name
	}

	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		// Two roots when there is a Dependencies section: the project's own
		// directory, and everything that is not it. IntelliJ's *External
		// Libraries* sits in the same place, below the tree rather than inside
		// it, because a dependency is not in the project — that is what it means.
		guard let item else {
			guard rootNode != nil else { return 0 }
			// Up to three, and each is there only when it holds something.
			return 1 + (dependencies == nil ? 0 : 1) + (sessions == nil ? 0 : 1)
		}
		if let node = item as? SessionNode {
			// A session row *is* a directory, the same as a package row: from
			// here down the rows are ordinary files.
			if let fileRoot = node.fileRoot { return rows(under: fileRoot).count }
			return node.childNodes.count
		}
		if let node = item as? DependencyNode {
			// A package row *is* a directory: from here down the rows are
			// ordinary files and everything the tree does works on them.
			if let fileRoot = node.fileRoot { return rows(under: fileRoot).count }
			return node.childNodes.count
		}
		guard let node = item as? FileNode, node.isDirectory else { return 0 }

		// Children are read the first time the outline view asks for them,
		// which may be long after the last status refresh — and rows that
		// appeared since would be drawn as though everything about them were
		// unremarkable. Asking again is cheap; the refresh coalesces.
		let wasLoaded = node.hasLoadedChildren
		let count = rows(under: node).count
		if !wasLoaded { scheduleGitStatusRefresh() }
		// And the one row that is not a file. It is last, so it changes nothing
		// about the rows above it and cannot move while a name is being typed
		// into it — see `beginNew`.
		return count + (placeholder?.parent === node ? 1 : 0)
	}

	/// Asks for a status refresh once the current run of layout is over.
	///
	/// Not immediately: this is called from inside the outline view's own data
	/// source, and reloading rows from there is how a table ends up drawing
	/// stale geometry.
	private func scheduleGitStatusRefresh() {
		guard !hasScheduledGitStatusRefresh else { return }
		hasScheduledGitStatusRefresh = true
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.hasScheduledGitStatusRefresh = false
			self.refreshGitStatus()
		}
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		guard let item else {
			// The project, then Dependencies, then Claude Sessions — the order
			// the reveal claims a file in, so the tree reads the same way it
			// resolves.
			guard index > 0 else { return rootNode! }
			if let dependencies { return index == 1 ? dependencies.root : sessions! }
			return sessions!
		}
		if let node = item as? SessionNode {
			if let fileRoot = node.fileRoot { return rows(under: fileRoot)[index] }
			return node.childNodes[index]
		}
		if let node = item as? DependencyNode {
			if let fileRoot = node.fileRoot { return rows(under: fileRoot)[index] }
			return node.childNodes[index]
		}
		let node = item as! FileNode
		let children = rows(under: node)
		if index == children.count, let placeholder, placeholder.parent === node {
			return placeholder.node
		}
		return children[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		if let node = item as? SessionNode { return node.isExpandable }
		if let node = item as? DependencyNode { return node.isExpandable }
		guard let node = item as? FileNode else { return false }
		// A new folder has nothing in it and does not exist yet, so it gets no
		// disclosure triangle: opening it would list a directory that is not
		// there.
		guard node !== placeholder?.node else { return false }
		// Reporting expandable without reading the directory keeps opening a
		// project O(1) in the number of subdirectories.
		return node.isDirectory
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		if let node = item as? SessionNode {
			let cell = NavigatorCellView()
			cell.configure(session: node)
			// The transcript's path lives here and nowhere else: worth having
			// for pointing another tool at it, not worth opening as a file.
			cell.toolTip = node.detail
			return cell
		}
		if let node = item as? DependencyNode {
			let cell = NavigatorCellView()
			cell.configure(dependency: node)
			// The whole origin, which the row itself has to cut down to fit. A
			// package's tooltip is the URL, the version and where the sources
			// are — the three things somebody following a symbol out of their
			// own code wants and cannot otherwise find out.
			cell.toolTip = node.detail
			return cell
		}
		guard let node = item as? FileNode else { return nil }
		let isRoot = (node === rootNode)
		let cell = NavigatorCellView()
		// The whole path, which a folded row is the reason for: `com.example.myapp`
		// says which package and not where it is, and the row is too narrow for
		// both. Every file row has it, so a folded one is not a special case.
		cell.toolTip = node.url.path
		cell.configure(
			node: node,
			title: title(for: node),
			isRoot: isRoot,
			subtitle: isRoot ? project?.displayPath : nil,
			isExpanded: outlineView.isItemExpanded(node),
			isSubproject: node.url.path == subprojectRoot?.path,
			isRenaming: editing?.node === node
		)
		return cell
	}

	func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
		let node = item as? FileNode
		let row = NavigatorRowView()
		row.isExcluded = node?.isExcluded ?? false
		return row
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		// Unless the tree is moving its own selection to follow something else.
		guard !isSelectingSilently else { return }

		// One row shows the file it landed on, which is what makes arrowing
		// through the tree feel like browsing. Several show nothing new: a
		// ⇧-click over four files that opened four tabs would be a surprise, and
		// the last one opened would not be the one under the pointer.
		guard outlineView.numberOfSelectedRows == 1 else { return }

		let row = outlineView.selectedRow
		guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode, !node.isDirectory else { return }
		// The row for a file that does not exist yet opens nothing: it is a name
		// being typed, not a file to show.
		guard node !== placeholder?.node else { return }
		// Provisionally, and without taking focus: a click or an arrow key shows
		// the file while the tree keeps the keyboard, so the next arrow works.
		// Return, or a double-click, is what pins the tab and moves focus.
		onSelectFile?(node.url, false)
	}

	/// Tailors the menu to the row it was opened on: directories cannot be
	/// "opened externally" in a meaningful way, and the project root should not
	/// offer to trash itself.
	/// Files can be dragged out — onto the terminal, or into another app.
	///
	/// The URL is the whole payload: every receiver already knows what to do
	/// with one, and the terminal turns it into a path.
	func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
		(item as? FileNode)?.url as NSURL?
	}

	/// Whether the drop under the pointer would do anything, and which of the
	/// two things it would do.
	///
	/// The row it highlights is retargeted to the folder the files will really
	/// land in — a file's parent, or the folder a line between two rows sits
	/// inside — so what is about to happen is visible before the mouse comes up
	/// rather than explained after.
	///
	/// The whole plan is worked out here and thrown away, which is what makes a
	/// drag onto a folder that could only refuse show the "no" cursor instead of
	/// accepting and then posting a toast. It is a few string comparisons and a
	/// `fileExists` per dragged file, per mouse move over a row.
	func outlineView(
		_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
		proposedItem item: Any?, proposedChildIndex index: Int
	) -> NSDragOperation {
		guard let folder = destinationFolder(for: item as? FileNode) else { return [] }
		let target = rootNode?.node(for: folder)
		outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)

		let sources = FilePasteboard.files(on: info.draggingPasteboard)
		guard !sources.isEmpty else { return [] }

		let operation = operation(for: info)
		let wanted: NSDragOperation = operation == .move ? .move : .copy
		// Some applications offer only `.generic`; a file URL is a file URL
		// either way, so that counts as permission to copy.
		guard info.draggingSourceOperationMask.contains(wanted)
			|| info.draggingSourceOperationMask.contains(.generic)
		else { return [] }

		let plan = FileTransfer.plan(
			sources, into: folder, operation: operation, projectRoot: project?.root,
			exists: { FileManager.default.fileExists(atPath: $0.path) }
		)
		return plan.hasWork ? wanted : []
	}

	/// The mouse came up. Everything that decides anything is in `transfer`, so
	/// a drop and a ⌘V are the same act arriving by two routes.
	func outlineView(
		_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
		item: Any?, childIndex index: Int
	) -> Bool {
		guard let folder = destinationFolder(for: item as? FileNode) else { return false }
		let sources = FilePasteboard.files(on: info.draggingPasteboard)
		guard !sources.isEmpty else { return false }
		let arrived = transfer(sources, into: folder, operation: operation(for: info))
		// The one gesture in the family that does not already leave the keyboard
		// in the tree. Every other route — the menu, ⌘⌫, ⌥⌘V — starts from a click
		// or a keystroke in the tree and ends with it still focused, but a drag
		// from the Finder can land here while the caret is in the editor, and then
		// ⌘Z would mean the editor's undo rather than this drop's. Undo lives
		// where the gesture happened, so the gesture takes the keyboard.
		if arrived, nameField == nil { view.window?.makeFirstResponder(outlineView) }
		return arrived
	}

	/// Tailors each item to how many rows the menu was opened over.
	///
	/// `node` is the single row, and nil when there are several — so everything
	/// that only makes sense one at a time switches itself off without being
	/// told about the count. `nodes` is all of them, for the two that take a
	/// list.
	func menuNeedsUpdate(_ menu: NSMenu) {
		refreshNewMenu()
		let nodes = contextNodes
		let node = contextNode
		let isRoot = node === rootNode
		// **A session row is not a file, so nothing else in this menu belongs
		// over it.** Driven, and the first version offered every file item on a
		// session's row — New, Rename, Open Externally, and *Move to Trash*,
		// which reads as an offer to delete somebody's session. They do nothing,
		// because each guards on a file being clicked, but a menu of seventeen
		// items that do nothing is not a menu. One item, which is the only one
		// that means anything there.
		// Reported again after the first attempt: right-clicking **the root** —
		// which is the row anybody would try — still offered the whole file
		// menu, because only a *session* row was being told apart. The root is
		// not a file either.
		// **And not over a session that is already running.** `claude --resume`
		// on a live session is not a thing anybody wants pasted into a terminal:
		// the conversation it names is open in a window somewhere, and what the
		// command does with one is not this app's to promise.
		resumeItem?.isHidden = contextSession.map(\.isLive) ?? true
		revealSessionItem?.isHidden = contextSessionDirectory == nil
		if contextSessionRow != nil {
			for item in menu.items where item !== resumeItem && item !== revealSessionItem {
				item.isHidden = true
			}
			return
		}
		for item in menu.items where item !== resumeItem && item !== revealSessionItem {
			// Put back whatever a session row hid on the way past.
			item.isHidden = false
			// The two items that are only a submenu, before anything looks at an
			// action — because an item with a submenu does not have the action it
			// was made with. AppKit replaces it with its own `submenuAction:` the
			// moment the submenu is attached, so `case nil where item.submenu ===`
			// never matched and "New" has been quietly following the rule meant
			// for everything else: greyed over four rows, though a new file has
			// one place to go however many are selected.
			if item.submenu === exportMenu {
				// Hidden unless a diagram was clicked — it means nothing over a
				// Swift file — and greyed when several rows were, for the same
				// reason Rename is: one file, one answer.
				// `holdsADiagram` rather than `isDiagram`, because a Markdown file
				// is one only when somebody has written a ```mermaid block in it —
				// and an Export over every `.md` in a repository would be wrong far
				// more often than right.
				item.isHidden = !nodes.contains { !$0.isDirectory && DiagramExport.holdsADiagram($0.url) }
				let single = node.map { !$0.isDirectory && DiagramExport.holdsADiagram($0.url) } ?? false
				item.isEnabled = single
				if let submenu = item.submenu {
					DiagramExportMenu.fill(
						submenu, theme: Theme.current.isLight ? .light : .dark,
						stated: single ? statedLook(of: node) : nil,
						target: self, action: #selector(contextExport(_:)), enabled: single,
						// The picture that is also the document, which only
						// draw.io has: `architecture.drawio.png` rather than
						// `architecture.png`.
						editable: single && (node.map { Drawio.isDiagram($0.url) } ?? false)
					)
				}
				continue
			}
			if item.submenu === compareMenu {
				// A file's question and only a file's: folders and the root
				// have no one file's working copy to compare. An untracked or
				// ignored file offers Against Last Commit disabled — there is
				// no last commit of it — and no History…, git holding none.
				let file = node.map { !$0.isDirectory } ?? false
				item.isHidden = !file || isRoot
				item.isEnabled = file
				if let node, file {
					let outside = node.gitStatus == .unversioned || node.gitStatus == .ignored
					compareAgainstItem?.isEnabled = !outside
					compareHistoryItem?.isHidden = outside
				}
				continue
			}
			if item.submenu === newMenu {
				// A new file has one place to go whatever is selected: beside the
				// topmost row, or in the project root when nothing is.
				item.isEnabled = rootNode != nil
				continue
			}

			switch item.action {
			case #selector(contextOpenExternally):
				item.isHidden = node?.isDirectory ?? true
			case #selector(contextQuickLook):
				// Only where the system would actually render something. A
				// menu item that opens a panel showing a large grey icon is an
				// offer to do nothing, which is the argument `offersQuickLook`
				// was written for.
				item.isHidden = !(node.map {
					!$0.isDirectory && FileNotice.offersQuickLook(forExtension: $0.url.pathExtension)
				} ?? false)
			case #selector(contextPreviewModel):
				// `holdsAModel` rather than `canPreview`, for the same reason Export
				// above uses `holdsADiagram`: a go3mf recipe is a `.yaml`, and the
				// name of a `.yaml` says nothing at all. This reads the head of the
				// one file that was right-clicked, and only when it is named like a
				// recipe could be — the row, never the tree. See 0482.
				item.isHidden = !(node.map { !$0.isDirectory && ModelPreview.holdsAModel($0.url) } ?? false)
					|| !ModelPreview.isAvailable
			case #selector(contextOpenSubproject):
				// Only a folder, and not the one already being worked on.
				let folder = node?.isDirectory == true && !isRoot
				item.isHidden = !folder || node?.url.path == subprojectRoot?.path
			case #selector(contextLeaveSubproject):
				item.isHidden = subprojectRoot == nil
			case #selector(contextRename):
				// One row. Renaming whichever came first is worse than not
				// offering it.
				item.isEnabled = node != nil && !isRoot
			case #selector(contextTrash):
				// All of them, less the project root, which never trashes itself.
				item.isEnabled = nodes.contains { $0 !== rootNode }
			case #selector(contextCopyPath), #selector(contextCopyRelativePath):
				item.isEnabled = !nodes.isEmpty
			case #selector(contextPaste), #selector(contextPasteAsMove):
				// About the board and the folder, not about how many rows are
				// highlighted: pasting four files into a folder is one act, and
				// right-clicking empty space still has somewhere to put them.
				item.isEnabled = rootNode != nil && !FilePasteboard.files().isEmpty
			case #selector(contextCollapseAll):
				// About the tree, not about a row: right-clicking empty space
				// still offers it.
				item.isEnabled = rootNode != nil
			case #selector(contextSelectOpenFile):
				item.isEnabled = currentEditorFile?() != nil
			default:
				item.isEnabled = node != nil
			}
		}
	}

	/// Keeps what `menuNeedsUpdate` decided.
	///
	/// Without this, AppKit's automatic enabling runs after the delegate and
	/// switches every item back on merely because this object answers to its
	/// action — which is exactly what "Rename… is off for four rows" is not
	/// about. The rule lives in one place; this stops the frame overruling it.
	func validateMenuItem(_ item: NSMenuItem) -> Bool { item.isEnabled }

	/// Lets the outline view's built-in type-select find rows. Without this the
	/// custom cells expose no string and typing does nothing.
	func outlineView(_ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any) -> String? {
		(item as? FileNode).map { title(for: $0) }
	}

	func outlineViewItemDidExpand(_ notification: Notification) {
		// Newly-loaded children have no VCS state yet.
		refreshGitStatus()
	}
}

// MARK: - Header

/// The "Project ⌄" strip above the tree.
private final class NavigatorHeaderView: NSView {
	override var isFlipped: Bool { true }

	/// The three things a tree this size needs and cannot do by itself: fold
	/// everything away, find its way back to whatever the editor is showing, and
	/// stop spending five rows on what one row could say.
	var onCollapseAll: (() -> Void)?
	var onSelectOpenFile: (() -> Void)?
	var onToggleCompactPackages: (() -> Void)?

	/// Whether the third button is on, which is the one thing about this header
	/// that is a state rather than a gesture — so it is the one thing drawn
	/// differently.
	var isCompactingPackages = false {
		didSet { if isCompactingPackages != oldValue { restyle() } }
	}

	private lazy var collapseButton = button(
		symbol: "arrow.down.right.and.arrow.up.left",
		tooltip: "Collapse all",
		action: #selector(collapseAll)
	)
	private lazy var locateButton = button(
		symbol: "scope",
		tooltip: "Select the file in the editor",
		action: #selector(selectOpenFile)
	)
	private lazy var compactButton = button(
		symbol: "rectangle.compress.vertical",
		tooltip: "Compact middle packages",
		action: #selector(toggleCompactPackages)
	)

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		for view in [locateButton, collapseButton, compactButton] { addSubview(view) }
		compactButton.wantsLayer = true
		layoutButtons()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) { fatalError("not from a nib") }

	private func button(symbol: String, tooltip: String, action: Selector) -> NSButton {
		let button = NSButton(image: NSImage(), target: self, action: action)
		button.image = Theme.symbol(
			symbol, size: Theme.current.scaled(11),
			color: Theme.current.sidebarHeaderText, weight: .medium
		)
		button.isBordered = false
		button.bezelStyle = .shadowlessSquare
		button.imagePosition = .imageOnly
		button.toolTip = tooltip
		// Nothing here should take focus from the tree, which is the point of
		// the buttons: the keyboard stays where it was.
		button.refusesFirstResponder = true
		return button
	}

	override func layout() {
		super.layout()
		layoutButtons()
	}

	private func layoutButtons() {
		let size = Theme.current.scaled(20)
		var x = bounds.maxX - Theme.current.scaled(8) - size
		// Rightmost first.
		for view in [locateButton, collapseButton, compactButton] {
			view.frame = NSRect(x: x, y: (bounds.height - size) / 2, width: size, height: size)
			x -= size + Theme.current.scaled(2)
		}
		compactButton.layer?.cornerRadius = Theme.current.scaled(4)
	}

	/// Redrawn on a theme or zoom change, since the symbols carry their colour
	/// and their size in the image itself.
	func restyle() {
		collapseButton.image = Theme.symbol(
			"arrow.down.right.and.arrow.up.left", size: Theme.current.scaled(11),
			color: Theme.current.sidebarHeaderText, weight: .medium
		)
		locateButton.image = Theme.symbol(
			"scope", size: Theme.current.scaled(11),
			color: Theme.current.sidebarHeaderText, weight: .medium
		)
		compactButton.image = Theme.symbol(
			"rectangle.compress.vertical", size: Theme.current.scaled(11),
			color: Theme.current.sidebarHeaderText, weight: .medium
		)
		// On is a pill behind the symbol rather than a colour on it: the symbol
		// is eleven points of line work, and a tint on something that small
		// reads as a rendering artefact on one theme and as nothing at all on
		// the other.
		compactButton.layer?.backgroundColor = isCompactingPackages
			? Theme.current.selectionActive.withAlphaComponent(0.45).cgColor
			: NSColor.clear.cgColor
		layoutButtons()
		needsDisplay = true
	}

	@objc private func collapseAll() { onCollapseAll?() }
	@objc private func selectOpenFile() { onSelectOpenFile?() }
	@objc private func toggleCompactPackages() { onToggleCompactPackages?() }

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()

		let attributed = NSAttributedString(string: "Project", attributes: [
			.font: Theme.current.uiFont(13, weight: .semibold),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		let size = attributed.size()
		attributed.draw(at: NSPoint(x: Theme.current.scaled(12), y: bounds.midY - size.height / 2))

		let path = NSBezierPath()
		let x = Theme.current.scaled(12) + size.width + Theme.current.scaled(8)
		path.move(to: NSPoint(x: x, y: bounds.midY - 2))
		path.line(to: NSPoint(x: x + 3.5, y: bounds.midY + 2))
		path.line(to: NSPoint(x: x + 7, y: bounds.midY - 2))
		path.lineWidth = 1.3
		path.lineCapStyle = .round
		path.lineJoinStyle = .round
		Theme.current.sidebarText.withAlphaComponent(0.8).setStroke()
		path.stroke()
	}
}

// MARK: - Rows

/// What the tree's undo manager holds instead of the navigator.
///
/// A registered undo keeps its target alive, and the target has to outlive the
/// registration for the handler to have anything to run on — so it cannot be
/// weak. Making it this rather than the controller keeps the strong reference
/// off the view controller, and the one weak hop is all the handler needs.
private final class FileUndoTarget {
	weak var navigator: ProjectNavigatorViewController?
}

/// Outline view that hands key events to the controller before acting on them.
final class NavigatorOutlineView: NSOutlineView {
	var onKeyDown: ((NSEvent) -> Bool)?
	/// The files Quick Look should show, in tree order — the whole selection,
	/// so the panel's arrow keys walk it the way they do in the Finder.
	var quickLookFiles: (() -> [URL])?
	/// The tree's file undo stack, asked for rather than held: the controller
	/// withholds it while a name is being edited on a row.
	fileprivate var fileUndoManager: (() -> UndoManager?)?
	/// What ⌘C should put on the pasteboard, in tree order.
	var copyFiles: (() -> [URL])?
	/// ⌘V, and ⌥⌘V, which is the same gesture the other way round.
	var onPaste: ((FileTransfer.Operation) -> Void)?
	/// Whether there is anything on the board to paste, so the Edit menu's
	/// Paste greys itself out over an empty one.
	var canPaste: (() -> Bool)?

	override var acceptsFirstResponder: Bool { true }

	/// ⌘C copies the selected files — as files, and as their paths.
	///
	/// Answered here rather than bound to a key, so it arrives the way copying
	/// arrives everywhere else: the Edit menu sends `copy:` down the responder
	/// chain, this is the responder when the tree has the keyboard, and the
	/// menu item greys itself out when there is nothing selected to copy.
	///
	/// `FilePasteboard` is what makes it both things at once. The text form is
	/// unchanged — one absolute path a line, in tree order — and the same ⌘C now
	/// pastes as a file in the Finder and in this tree.
	@objc func copy(_ sender: Any?) {
		let files = copyFiles?() ?? []
		guard !files.isEmpty else { return }
		FilePasteboard.write(files)
	}

	/// ⌘V. ⌥⌘V is the same thing as a move, and arrives through `keyDown`
	/// instead: AppKit only dispatches key equivalents it finds in the main
	/// menu, and the Edit menu's Paste is ⌘V alone.
	@objc func paste(_ sender: Any?) {
		onPaste?(.copy)
	}

	/// ⌘Z over the tree, which is files and never text.
	///
	/// Answered here rather than left to the window's undo manager, and that is
	/// the whole of how the two stacks stay apart. `undo:` is sent from the Edit
	/// menu with no target, so AppKit walks the responder chain from the first
	/// responder and stops at the first object answering to it: this one when the
	/// keyboard is in the tree, `CodeView` when it is in the editor. Neither pane
	/// is in the other's chain, so a ⌘Z aimed at a stray character can never put
	/// back a folder somebody meant to trash, and a ⌘Z after a delete never
	/// rewrites a file.
	///
	/// There is deliberately no `undoManager` override to go with this. Returning
	/// the file stack from that property would hand it to the *rename field*,
	/// whose editor sits inside this view and asks the chain for the manager to
	/// register its typing on — the two stacks would then be one, which is
	/// exactly what this is for. One door, and it is this method.
	///
	/// No `redo:` either. Taking a gesture back registers nothing in its place,
	/// so a redo here would be a menu item that is always empty; leaving the
	/// selector unanswered lets ⇧⌘Z carry on down the chain rather than being
	/// swallowed by something that could never do anything. Redoing a copy means
	/// keeping the source it came from, which is a larger promise than 0442 made.
	@objc func undo(_ sender: Any?) {
		fileUndoManager?()?.undo()
	}

	/// Transparent to `undo:` while a name is being edited on a row.
	///
	/// The rename field is a subview of this view, so its field editor's
	/// responder chain runs through here. Merely answering `undo:` with a no-op
	/// then would swallow the key — `tryToPerform` asks this, not the method's
	/// body — and typing in the field would have no undo at all. Saying no lets
	/// the chain reach the window's undo manager, which is the one the field
	/// editor registered its typing on.
	override func responds(to selector: Selector!) -> Bool {
		if selector == #selector(undo(_:)) { return fileUndoManager?() != nil }
		return super.responds(to: selector)
	}

	override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		if item.action == #selector(copy(_:)) { return !(copyFiles?().isEmpty ?? true) }
		if item.action == #selector(paste(_:)) { return canPaste?() ?? false }
		// Greyed out over an empty stack rather than swallowing the key: an Undo
		// that is enabled and does nothing is the same lie as one that undoes the
		// wrong thing, only quieter.
		if item.action == #selector(undo(_:)) { return fileUndoManager?()?.canUndo ?? false }
		return super.validateUserInterfaceItem(item)
	}

	override func keyDown(with event: NSEvent) {
		if onKeyDown?(event) == true { return }
		super.keyDown(with: event)
	}

	// MARK: - Quick Look

	/// Opens the system's preview panel on the selection.
	///
	/// **Here rather than on the controller**, because the panel asks the key
	/// window's responder chain who wants to control it and this is what has
	/// the keyboard when the tree does. The same handshake `FileNoticeView`
	/// does, and for the same measured reason: the documented route is the
	/// three `…PreviewPanelControl` methods, the panel only walks the chain
	/// when the application is active, and a panel opened while it is not is
	/// one controlled by nobody, showing nothing.
	func showQuickLook() {
		guard let panel = QLPreviewPanel.shared() else { return }
		// **A toggle, as everywhere else on this machine.** Space opens it and
		// Space closes it; without this the second press reloaded the panel it
		// had already opened and looked like a key that had stopped working.
		if panel.isVisible, panel.dataSource === self {
			panel.orderOut(nil)
			return
		}
		window?.makeFirstResponder(self)
		panel.dataSource = self
		panel.delegate = self
		panel.makeKeyAndOrderFront(nil)
		panel.reloadData()
	}

	override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

	override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
		panel.dataSource = self
		panel.delegate = self
	}

	override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
		// Only what this view put there. The panel outlives the tree's focus,
		// and clearing somebody else's source would leave their panel blank.
		guard panel.dataSource === self else { return }
		panel.dataSource = nil
		panel.delegate = nil
	}

	/// What the panel is showing, for a driven run.
	var quickLookReportForTesting: String {
		guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared()
		else { return "QUICKLOOK no panel" }
		let mine = panel.dataSource === self
		return "QUICKLOOK \(panel.isVisible ? "open" : "shut")"
			+ " controlled=\(mine ? "tree" : "somebody else")"
			+ " showing=\((panel.currentPreviewItem?.previewItemURL?.lastPathComponent) ?? "nothing")"
			+ " of=\(mine ? (quickLookFiles?().count ?? 0) : 0)"
	}

	/// Redraw selected rows when focus moves, so the highlight dims correctly.
	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		return super.resignFirstResponder()
	}
}

extension NavigatorOutlineView: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
	func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
		quickLookFiles?().count ?? 0
	}

	func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
		let files = quickLookFiles?() ?? []
		guard index >= 0, index < files.count else { return nil }
		return files[index] as NSURL
	}

	/// Zooms out of the row it is previewing rather than appearing from
	/// nowhere, which is what the panel does everywhere else on this machine.
	func previewPanel(
		_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!
	) -> NSRect {
		guard let window, let url = item.previewItemURL as URL? else { return .zero }
		// **The row holding this file**, found by its path rather than by
		// counting. The two lists are not the same length — four rows selected
		// with two of them previewable is a panel of two — so the item's
		// position in the panel is not its position in the selection, and
		// indexing one by the other zooms out of somebody else's row.
		// `self.item(atRow:)` spelled out: the parameter of this delegate method
		// is also called `item`, and shadows the method.
		guard let row = selectedRowIndexes.first(where: {
			(self.item(atRow: $0) as? FileNode)?.url == url
		}) else { return .zero }
		return window.convertToScreen(convert(rect(ofRow: row), to: nil))
	}

	/// The panel takes the keys while it is up — except the ones that belong to
	/// the tree underneath it, so ↑ and ↓ still move the selection and the
	/// preview follows it, as in the Finder.
	func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
		guard event.type == .keyDown, event.keyCode == 125 || event.keyCode == 126 else {
			return false
		}
		keyDown(with: event)
		panel.reloadData()
		return true
	}
}

private final class NavigatorRowView: NSTableRowView {
	var isExcluded = false

	/// Cells draw their label colour from the selection state, so they have to
	/// repaint when it changes — NSTableRowView only invalidates itself.
	override var isSelected: Bool {
		didSet {
			guard isSelected != oldValue else { return }
			for subview in subviews { subview.needsDisplay = true }
		}
	}

	override func drawBackground(in dirtyRect: NSRect) {
		super.drawBackground(in: dirtyRect)
		// Excluded output directories get a warm tint, as in the reference.
		if isExcluded && !isSelected {
			Theme.current.excludedDirectoryTint.withAlphaComponent(0.35).setFill()
			bounds.fill()
		}
	}

	override func drawSelection(in dirtyRect: NSRect) {
		// A rounded, inset pill rather than a full-bleed band — the shape IDEA
		// uses. Focused selection is blue; unfocused grey, so the tree still
		// shows where you are while the editor has keyboard focus.
		//
		// Through `Theme.selection` rather than the two colours by name: the
		// results list and the editor answer the same question now, and this is
		// where the answer was first worked out.
		let color = Theme.current.selection(.row, hasKeyboard: isTreeFocused)
		let rect = bounds.insetBy(dx: Theme.current.scaled(5), dy: 1)
		let radius = Theme.current.scaled(6)
		let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
		color.setFill()
		path.fill()
	}

	/// True when the outline view containing this row holds keyboard focus.
	var isTreeFocused: Bool {
		guard let window, let responder = window.firstResponder as? NSView else { return false }
		return responder === superview || responder.isDescendant(of: superview ?? self)
	}
}

/// A text field cell whose text sits in the middle of its box.
///
/// `NSTextFieldCell` draws its text at the top of whatever height it is given
/// and offers no way to say otherwise, which is why every list that edits a
/// name in place ends up with one of these. The three overrides are the three
/// rects it uses: one to draw through, and two for the field editor, which is a
/// separate view laid into the cell and would otherwise stay at the top while
/// the drawn text moved.
private final class CentredFieldCell: NSTextFieldCell {
	private func centred(_ rect: NSRect) -> NSRect {
		let height = cellSize(forBounds: rect).height
		guard rect.height > height else { return rect }
		var centred = rect
		centred.origin.y += ((rect.height - height) / 2).rounded()
		centred.size.height = height
		return centred
	}

	override func drawingRect(forBounds rect: NSRect) -> NSRect {
		super.drawingRect(forBounds: centred(rect))
	}

	override func edit(
		withFrame rect: NSRect, in controlView: NSView,
		editor: NSText, delegate: Any?, event: NSEvent?
	) {
		super.edit(
			withFrame: centred(rect), in: controlView,
			editor: editor, delegate: delegate, event: event
		)
	}

	override func select(
		withFrame rect: NSRect, in controlView: NSView,
		editor: NSText, delegate: Any?, start: Int, length: Int
	) {
		super.select(
			withFrame: centred(rect), in: controlView,
			editor: editor, delegate: delegate, start: start, length: length
		)
	}
}

private final class NavigatorCellView: NSTableCellView {
	private var node: FileNode?
	/// What to draw, which is the node's own name until a chain of directories
	/// is folded into this row and it becomes all of their names.
	private var title = ""
	private var isRoot = false
	private var subtitle: String?
	private var isExpanded = false
	/// Set instead of `node` for one of the Dependencies section's own rows.
	/// A package is not a file and has no `FileNode` behind it — the files
	/// start one level below it.
	private var dependency: DependencyNode?
	/// And for one of the Claude Sessions root's own rows, for the same reason:
	/// a session is not a file, and its files start one level below it.
	private var session: SessionNode?

	func configure(dependency: DependencyNode) {
		self.dependency = dependency
		self.subtitle = dependency.subtitle
		needsDisplay = true
	}

	func configure(session: SessionNode) {
		self.session = session
		self.subtitle = session.subtitle
		needsDisplay = true
	}

	func configure(
		node: FileNode,
		title: String,
		isRoot: Bool,
		subtitle: String?,
		isExpanded: Bool,
		isSubproject: Bool = false,
		isRenaming: Bool = false
	) {
		self.node = node
		self.title = title
		self.isRoot = isRoot
		self.subtitle = subtitle
		self.isExpanded = isExpanded
		self.isSubproject = isSubproject
		self.isRenaming = isRenaming
		needsDisplay = true
	}

	/// Whether the field is standing on this row.
	///
	/// The name is then not drawn at all. Drawing it under the field and
	/// covering it up looks the same only while the field is as wide as the
	/// name it replaced — and it is not, since it stops at the edge of the
	/// pane, so the tail of the old name showed past the field's right border
	/// with the new one already typed in front of it.
	var isRenaming = false {
		didSet { if isRenaming != oldValue { needsDisplay = true } }
	}

	/// The folder the run button, git and the language server are pointed at.
	private var isSubproject = false

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		// On a selected row the VCS colour would fight the pill behind it, so the
		// label goes to whichever plain ink the palette reads with — the
		// treatment IDEA uses. Near-white was written for the dark theme's blue
		// and disappeared entirely on the light theme's pale one, which the
		// presentation mode ships by default.
		let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
		let selectedInk: NSColor = Theme.current.isLight
			? Theme.current.sidebarHeaderText
			: .hex(0xE8EAED)

		/// The selected ink, still saying whether git cares about the file.
		///
		/// **Selecting a row used to take its status away.** Every row went to
		/// `selectedInk`, so an ignored file — the one state a reader is most
		/// likely to be checking, because it decides whether the file is part of
		/// the project at all — looked exactly like a tracked one for as long as
		/// it was selected. Clicking a row to find out about it removed the
		/// answer.
		///
		/// Dimmed rather than recoloured. The selection has to stay legible
		/// against its blue, so `gitIgnored`'s own grey is not what to use here;
		/// what carries over is the *quietness*, which is what the colour was
		/// saying. The other states keep the plain ink: modified and added are
		/// already marked in the trailing column, and this row is not where
		/// those are read.
		func ink(saying status: GitFileStatus) -> NSColor {
			switch status {
			case .ignored, .deleted: return selectedInk.withAlphaComponent(0.55)
			default:                 return selectedInk
			}
		}

		let icon: NSImage?
		let text: String
		let nameColor: NSColor
		let nameFont: NSFont

		if let session {
			text = session.title
			switch session.row {
			case .section:
				icon = FileIcon.sessionSection()
				// The other roots are written this way: this is a root of the
				// tree, not a folder inside anything.
				nameColor = isSelected ? selectedInk : Theme.current.sidebarHeaderText
				nameFont = Theme.current.uiFont(13, weight: .bold)
			case let .session(_, asked):
				icon = FileIcon.session()
				// A session the transcript said nothing about is named by its
				// id, which is not a name — so it is drawn in the grey a note
				// uses rather than as a title somebody wrote.
				nameColor = isSelected
					? selectedInk
					: (asked == nil ? Theme.current.gitIgnored : Theme.current.sidebarHeaderText)
				nameFont = Theme.current.uiFont(13)
			}
		} else if let dependency {
			text = dependency.title
			switch dependency.row {
			case .section:
				icon = FileIcon.dependencySection()
				// Written the way the project root above it is: this is the other
				// root of the tree, not a folder inside anything.
				nameColor = isSelected ? selectedInk : Theme.current.sidebarHeaderText
				nameFont = Theme.current.uiFont(13, weight: .bold)
			case .group:
				icon = FileIcon.subprojectFolder()
				nameColor = isSelected ? selectedInk : Theme.current.sidebarHeaderText
				nameFont = Theme.current.uiFont(13, weight: .bold)
			case let .package(package):
				icon = FileIcon.dependencyPackage(fetched: package.localPath != nil)
				nameColor = isSelected ? selectedInk : Theme.current.sidebarHeaderText
				nameFont = Theme.current.uiFont(13)
			case .toolchain:
				icon = FileIcon.dependencyToolchain()
				nameColor = isSelected ? selectedInk : Theme.current.sidebarHeaderText
				nameFont = Theme.current.uiFont(13)
			case .note:
				icon = FileIcon.dependencyNote()
				// The grey the subtitle uses, because a note *is* a subtitle
				// wearing the name's place: nothing is wrong with the project.
				nameColor = isSelected ? selectedInk : Theme.current.gitIgnored
				nameFont = Theme.current.uiFont(13)
			}
		} else {
			guard let node else { return }
			text = title
			// The folder being worked on is tinted rather than decorated: a mark
			// beside the name reads as a status — modified, added — and this is
			// not a status. It is which folder everything is pointed at.
			icon = isSubproject
				? FileIcon.subprojectFolder()
				: FileIcon.image(for: node, isExpanded: isExpanded)
			// The subproject is written the way the project above it is — bold
			// and bright — because that is what it is here: the project
			// everything is pointed at. The blue folder says which of the two.
			nameColor = isSelected
				? (isRoot || isSubproject
					? selectedInk
					: ink(saying: node.gitStatus))
				: (isRoot || isSubproject
					? Theme.current.sidebarHeaderText
					: Theme.current.color(for: node.gitStatus))
			nameFont = isRoot || isSubproject
				? Theme.current.uiFont(13, weight: .bold)
				: Theme.current.uiFont(13)
		}

		var x = Theme.current.scaled(2)
		let iconSize = Theme.current.scaled(16)
		if let icon {
			icon.drawFitted(
				in: NSRect(x: x, y: bounds.midY - iconSize / 2, width: iconSize, height: iconSize)
			)
		}
		x += iconSize + Theme.current.scaled(6)

		// The icon stays while the name is being edited — it says what kind of
		// thing this is, and the field does not cover it — but the name itself
		// belongs to the field now.
		if isRenaming { return }

		// Truncated rather than run past the edge: a long name would otherwise
		// draw straight over the row's rounded selection and out of the pane.
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let name = NSAttributedString(string: text, attributes: [
			.font: nameFont,
			.foregroundColor: nameColor,
			.paragraphStyle: paragraph,
		])
		let nameSize = name.size()
		let trailing = Theme.current.scaled(8)
		let available = max(0, bounds.width - x - trailing)
		let nameWidth = min(ceil(nameSize.width), available)
		name.draw(in: NSRect(
			x: x,
			y: bounds.midY - nameSize.height / 2,
			width: nameWidth,
			height: nameSize.height
		))
		x += nameWidth + trailing

		if let subtitle {
			let attributed = NSAttributedString(string: subtitle, attributes: [
				.font: Theme.current.uiFont(11),
				.foregroundColor: Theme.current.gitIgnored,
				.paragraphStyle: paragraph,
			])
			let size = attributed.size()
			attributed.draw(in: NSRect(
				x: x,
				y: bounds.midY - size.height / 2,
				width: max(0, bounds.width - x - trailing),
				height: size.height
			))
		}
	}

}
