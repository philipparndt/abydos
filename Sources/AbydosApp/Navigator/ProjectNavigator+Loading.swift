import AppKit
import AbydosKit

/// Filling the tree: reading the folder, what a past session left open, the
/// dependencies row, and what version control says about each file.
extension ProjectNavigatorViewController {
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
		// And whatever was unrolled last time, over the root that has just been
		// opened. After the reload, because `restore(expandedPaths:)` walks the
		// rows the reload made.
		if let foldsToRestore {
			self.foldsToRestore = nil
			folds = foldsToRestore
		}
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


	func refreshSessions() {
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
	func show(_ node: SessionNode?) {
		let expanded = expandedPaths()
		let selected = selectedPaths()
		let place = rememberPlace()
		sessions = node
		outlineView.reloadData()
		restore(expandedPaths: expanded)
		restoreSelection(paths: selected)
		restore(place: place)
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
	func refreshDependencies() {
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
		let place = rememberPlace()
		dependencies = DependencyTree(sets: sets, toolchains: toolchains, project: project.root)
		outlineView.reloadData()
		restore(expandedPaths: expanded)
		restoreSelection(paths: selected)
		restore(place: place)
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
	func noteToolchains(for urls: [URL]) {
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
	func updateFileIndex(with change: FileSystemChange) {
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
	func changeTouchesDependencies(_ change: FileSystemChange) -> Bool {
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

	@objc func repositoryChanged(_ notification: Notification) {
		guard let changedRoot = notification.object as? URL,
		      let gitRoot,
		      changedRoot.standardizedFileURL == gitRoot.standardizedFileURL
		else { return }
		reloadTree()
	}
}
