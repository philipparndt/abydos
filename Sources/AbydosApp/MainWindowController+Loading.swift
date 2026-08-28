import AppKit
import AbydosKit

/// Opening a project in this window, and switching to another.
///
/// Everything a window has to be told when the project under it changes: the
/// tree, the titlebar, the run configurations, the language servers, the
/// session that remembers what was open. It is the window controller's own
/// work — it is the one thing that knows about all of them.
extension MainWindowController {

	/// Where launch configurations are read from and written to.
	///
	/// The subproject when one is open: `ideai-examples` has eight sets of
	/// configurations, one per project in it, and the run button must offer
	/// the ones belonging to the part being worked on.
	var launchRoot: URL { subprojectRoot ?? project?.root ?? URL(fileURLWithPath: ".") }

	/// What scoped things work against.
	var scopeRoot: URL? { subprojectRoot ?? project?.root }

	/// The directory git commands belong in, which is not `scopeRoot`.
	///
	/// `git status` reports paths from the work tree root whatever directory it
	/// ran in, while `git add` and friends resolve a pathspec against the
	/// current one — so a pane running git inside a subproject and handing it
	/// those root-relative paths made git look for `sub/sub/…` and refuse.
	/// Staging did not work at all while a subproject was open.
	///
	/// Falls back to the scope only until the repository has been found, which
	/// is also the one case where there is nothing better to say.
	var gitCommandRoot: URL? { project?.gitRoot ?? scopeRoot }

	/// Works on part of the project instead of the whole of it.
	func openSubproject(at url: URL) {
		guard let project else { return }
		guard Subprojects.resolve(Subprojects.relativePath(url, to: project.root), in: project.root) != nil
		else { return }
		guard url.path != subprojectRoot?.path else { return }

		leftScope()
		subprojectRoot = url.standardizedFileURL
		applyScope()
	}

	/// Back to the whole project.
	func leaveSubproject() {
		guard subprojectRoot != nil else { return }
		leftScope()
		subprojectRoot = nil
		applyScope()
	}

	/// The window is about to stop showing this scope.
	///
	/// A question in the corner about the scope's devcontainer goes with it: it
	/// names a project, and asking it over a window now showing a different one
	/// would put an answer about somewhere else one click away. Nothing is
	/// decided by this — the project asks again the next time something needs the
	/// container — and the pill in the titlebar is the standing way in either
	/// way.
	func leftScope() {
		guard let scope = scopeRoot else { return }
		LanguageService.shared.withdrawDevContainerQuestion(for: scope)
	}

	/// Reads the repository for the current scope, and tells the window.
	///
	/// One task, kept: it is what the branch pill awaits when the toolbar gets
	/// around to building it.
	@discardableResult
	func readGit() -> Task<GitRepository.Head?, Never> {
		branchRead?.cancel()
		let askedAt = Date()
		// Said before the asking, because the asking is the part that takes the
		// time. This is the 784 ms the pill used to spend absent.
		titlebar.isReadingBranch = true
		titlebar.relayout()
		let read = Task { @MainActor [weak self] () -> GitRepository.Head? in
			guard let self, let project = self.project else { return nil }
			await project.loadGit()
			return await project.git?.currentHead()
		}
		branchRead = read

		Task { @MainActor [weak self] in
			let head = await read.value
			guard let self, !Task.isCancelled else { return }
			self.titlebar.setBranch(head?.name, isUnborn: head?.isUnborn ?? false)
			if ProjectSwitcherPopover.reportsForTesting {
				print(String(format: "BRANCHPILL appeared after %8.2f ms  (%@)",
					Date().timeIntervalSince(askedAt) * 1000, head?.name ?? "no branch"))
				fflush(stdout)
			}
			// The capsule only gets its width once it has a name to show.
			self.titlebar.relayout()
			self.navigator.refreshGitStatus()

			// Changes, history and branches hold on to one repository, so a
			// *different* work tree needs them built again — which is what
			// this said and not what it did. Rebuilding whatever the answer
			// came back as threw away a pane somebody was already using:
			// reading the repository finishes a second or two after a window
			// opens, and it took with it the commit message half typed into the
			// pane and the folders unfolded in it.
			if self.sidebar.currentSidebarTool == .changes || self.sidebar.currentSidebarTool == .branches {
				let holding = self.sidebar.currentSidebarTool == .changes
					? self.sidebar.changesPane?.repositoryRoot
					: self.sidebar.branchesPane?.repositoryRoot
				if holding != (self.scopeRoot ?? self.project?.root) {
					self.sidebar.install(tool: self.sidebar.currentSidebarTool, force: true)
				}
			}
			self.run.refreshRunConfigurations()
		}
		return read
	}

	/// Points everything scoped at the current scope.
	private func applyScope() {
		guard let project, let scope = scopeRoot else { return }

		// Set before anything reads it: a git load started for the whole project
		// may still be in flight, and both must look in the same place.
		project.scope = subprojectRoot

		run.selectedConfigurationName = nil
		run.refreshRunControl()
		LanguageService.shared.warmUp(project: scope)
		// The files already on screen belong to the new scope's servers now.
		// Without this the container's server comes up knowing about nothing,
		// and the file somebody is looking at is the one it has not been told
		// about — which is 0432 from the other end.
		editor.rescope()
		startWatchingRepository(at: scope)
		bottomPanel.setWorkingDirectory(scope)

		titlebar.setSubprojectPath(
			subprojectRoot.map { Subprojects.relativePath($0, to: project.root) }
		)
		// The devcontainer is the subproject's whenever it has one, so moving
		// between them moves which container the titlebar is talking about.
		titlebar.refreshDevContainer()
		titlebar.relayout()
		navigator.setSubproject(subprojectRoot)
		rememberOpenEditors()

		// Git is per work tree, and a subproject may be its own repository — a
		// checkout of several is the case this exists for.
		readGit()
	}

	func load(project: Project, focusTree: Bool = true) {
		// **Read before a single thing is touched.** `switchProject` says this
		// above its own read and it is right — "anything that writes the session
		// on the way past would overwrite the very thing being restored" — but
		// this function then read the file a *second* time, at the bottom, and
		// that is the read the subproject comes from. In between,
		// `selectedConfigurationName = nil` fires its own `didSet`, which calls
		// `rememberOpenEditors` for a window whose project is already the new one
		// and whose `subprojectRoot` has just been cleared. So the session on disk
		// was rewritten without its `subproject` before the line that needed it
		// looked.
		let remembered = SessionStore.read(in: project.sessionRoot)

		self.project = project
		subprojectRoot = nil
		// And on the project itself, which is what everything scoped reads: a
		// Project handed back by the switcher may be one that was open before,
		// with the scope it had then still on it.
		project.scope = nil
		titlebar.setSubprojectPath(nil)
		window?.title = project.name

		// No badge and no colour: which project this is gets stated once, by the
		// name, and colour is kept for the switcher — where there is more than
		// one project on screen and it has something to tell apart.
		titlebar.setProjectName(project.name)
		// Cleared rather than left standing: the pill of the project being left
		// would sit in the titlebar of the one arriving until git answered, and
		// the two repositories have nothing to do with each other.
		titlebar.clearWorktrees()
		titlebar.setBranch(nil, isUnborn: false)
		// Reading, not absent: this window is about to ask git about the project
		// that has just arrived, and that is what the half should say meanwhile.
		titlebar.isReadingBranch = true
		titlebar.refreshDevContainer()
		titlebar.relayout()
		titlebar.readWorktrees()

		navigator.load(project: project)
		editor.setProject(project)

		// A project brought in from a `.vscode/launch.json` keeps its
		// configurations once, so editing one here does not change a file the
		// rest of the team shares with another editor.
		if !AbydosFolder.exists(in: project.root) {
			_ = try? LaunchStore.importVSCode(in: project.root)
		}
		// Started now rather than when a file of that language is first opened,
		// so asking for a symbol straight after opening a project works.
		LanguageService.shared.warmUp(project: project.root)
		run.selectedConfigurationName = nil
		run.refreshRunControl()
		startWatchingRepository(at: project.root)
		sidebar.scratchesPane?.setProject(project.root)
		// The panes that are about a project follow it. Told with `project.root`
		// rather than through `setWorkingDirectory`, which also carries a
		// subproject scope — see `BottomPanel.setProject`.
		bottomPanel.setProject(project.root)
		bottomPanel.setWorkingDirectory(project.root)

		// What was open here last time, from the folder beside the project —
		// which is what makes opening it again feel like coming back rather
		// than starting.
		if let remembered {
			if !editor.hasOpenFiles { editor.restore(remembered) }
			// Where the work was left off, which for a repository of several
			// projects is as much a part of it as the open files.
			if let path = remembered.subprojectPath,
			   let url = Subprojects.resolve(path, in: project.root) {
				subprojectRoot = url
				applyScope()
			}
			// And what the play button was pointing at. Set before the
			// configurations have finished loading, which is fine: it is a
			// name, and the list is only needed when something is run.
			if let chosen = remembered.selectedConfiguration {
				run.selectedConfigurationName = chosen
				run.refreshRunControl()
			}
			run.xcodeDestinations = remembered.xcodeDestinations

			// The gutter, from what was there last time. Only when nothing has
			// set any yet: a window that already has debug.breakpoints is one where
			// somebody has been working, and a file restored over that would
			// take them away.
			if debug.pendingBreakpoints.isEmpty, !remembered.breakpoints.isEmpty {
				debug.pendingBreakpoints = remembered.breakpoints
				debug.showPendingBreakpoints()
			}
		}

		// The terminal is where half the work happens, so a window arrives with
		// it up — unless this project was left with it closed, which is a
		// decision and outlives the default.
		// One tmux session per project, for whoever asked for tmux at all.
		bottomPanel.tmuxSession = TmuxSessionName.of(project.root)

		// Once per window. Opening another project in the same window is not a
		// window opening, and having the terminal take the screen again — in
		// the middle of switching to something — is a jump nobody asked for.
		let wanted = hasArrangedTerminal ? "keep" : Settings.shared.terminalAtStartup
		hasArrangedTerminal = true
		if wanted != "closed", wanted != "keep" {
			// The setting is explicit and wins over what the project was last
			// left with: somebody who asked for the terminal to fill the window
			// asked for every window, not for the ones whose session happens to
			// agree.
			setPanelVisible(true)
			let remembered = SessionStore.read(in: project.sessionRoot)
			// A panel with nothing in it is not a terminal being open. The
			// session's own terminals come back a moment later if it had any;
			// this is for the window that has none.
			if !bottomPanel.hasTerminals, remembered?.terminals.isEmpty ?? true {
				_ = bottomPanel.showTerminal()
			}
			if wanted == "full" { maximizeTerminalWhenLaidOut() }
		}

		// Scratches come back with the project. Only when the window is empty:
		// following a terminal into a project puts back what it had open, and
		// that already includes whichever scratches were among it.
		if !editor.hasOpenFiles { editor.restoreScratches() }

		// Deferred: the titlebar has no measurable height until the window has
		// laid out at least once.
		DispatchQueue.main.async { [weak self] in
			self?.updateTopInsets()
			// The tree takes focus on open, so arrow keys work without clicking.
			// Not when the terminal is what moved us here: the user is typing in
			// it, and taking the keyboard away mid-command would be worse than
			// not following at all.
			if focusTree { self?.navigator.focusTree() }
		}

		readGit()
		run.refreshRunConfigurations()
	}

	/// Opens a file as a permanent tab and selects it in the tree.
	func openFile(at url: URL) {
		editor.open(fileURL: url, focusEditor: true, preview: false)
		navigator.selectWithoutOpening(url: url)
	}

	/// `abydos <file>`, typed in one of this window's terminals.
	///
	/// Three things, and the third is what makes it a gesture rather than a
	/// background event: the file opens in *this* window's editor, the keyboard
	/// goes with it, and the terminal comes back to a split if it had the window
	/// to itself. A file opened into a pane nobody can see is the same as not
	/// opening it, and the next thing typed would still go to the shell.
	///
	/// The panel stays down afterwards. Sending it back up when the editor loses
	/// focus would be a mode nobody asked for, and it would fight with the next
	/// click; this is the same restore the debugger and the tree already do.
	///
	/// It comes back to the height it had before it was maximised, and then to
	/// half the window if that height was more — the same rule the debugger
	/// uses, for the same reason. A terminal maximised from a panel that was
	/// already most of the window restores to most of the window, and a file
	/// opened behind a strip of editor is a file nobody can read.
	///
	/// A file outside the project opens here as a loose tab rather than being
	/// refused or taking the window to another project. Somebody typing
	/// `abydos ~/notes.md` in a pane is asking to read it beside what they are
	/// working on, not to stop working on it.
	func openFromTerminal(_ request: TerminalOpenRequest) {
		let url = URL(fileURLWithPath: request.path).standardizedFileURL
		// A directory is a project, whoever asked; that is what `abydos` with no
		// arguments means and it is not this window's to reinterpret.
		var isDirectory: ObjCBool = false
		guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
		      !isDirectory.boolValue else { return }

		makeRoomForTheEditor()
		// The pane may be in a torn-off terminal window, in which case this one
		// is not in front and the file would open behind it.
		window?.makeKeyAndOrderFront(nil)
		if let line = request.line {
			editor.open(fileURL: url, atLine: line)
		} else {
			editor.open(fileURL: url, focusEditor: true, preview: false)
		}
		navigator.selectWithoutOpening(url: url)
	}

	/// Opens what was dropped on the editor.
	///
	/// **The window's project does not change.** `openFromTerminal` is the
	/// precedent and the reason is what switching costs: the tree, git, the run
	/// configurations, the language servers and the remembered session all belong
	/// to the project, so re-pointing them because somebody dragged a file in is
	/// a very large answer to a very small gesture. A file dropped on the *Dock
	/// icon* is a different case — that one is addressed to the application,
	/// which has no window in mind and must find one, and it does switch.
	///
	/// A folder is a project, which it means everywhere else here — `abydos
	/// <dir>`, the Dock icon, the switcher — so it goes through the same opening
	/// as those and obeys the same setting about taking this window or another.
	///
	/// Files open in order, last in front, and none of them provisional: a
	/// preview tab is the answer to a single click in the tree, where the next
	/// click replaces it, and a drag is deliberate.
	func openDropped(_ urls: [URL]) {
		let (folders, files) = EditorDrop.separate(urls)

		// **Folders first, and the files go to the window that results.**
		//
		// The other order was tried and measured: a file opened here and a
		// folder opened after it left `project=inner-project tabs=[]` — the file
		// was opened into the project being left, and switching restored the
		// arriving project's session over the top of it. The file was simply
		// lost, which is not "each does what it would have done alone".
		var target = self
		for folder in folders {
			guard let opened = (NSApp.delegate as? AppDelegate)?.open(projectAt: folder, from: target)
			else { continue }
			// The first folder's window takes the files. A drag with several
			// folders opens several projects; the files belong with the first,
			// which is the one the drop was aimed at.
			if target === self { target = opened }
		}

		for file in files {
			target.makeRoomForTheEditor()
			target.editor.open(fileURL: file, focusEditor: true, preview: false)
			target.navigator.selectWithoutOpening(url: file)
		}
	}

	/// Opens a file provisionally, as a single click in the tree would.
	func previewFile(at url: URL) {
		editor.open(fileURL: url, focusEditor: false, preview: true)
		navigator.selectWithoutOpening(url: url)
	}

	/// Flushes every dirty document in this window.
	func autoSaveAll() {
		editor.autoSaveAll()
	}

	/// Applies changed preferences: editor metrics, and tree filters that change
	/// which files exist at all.
	func applySettings() {
		// A palette change reaches everything that draws. Most of it reads the
		// theme as it draws and needs only a repaint; the colours that were
		// copied into a layer or a control when it was built are recognised and
		// swapped for their counterparts.
		if Theme.apply() { applyPalette() }

		// Whatever the theme did, the terminal's palette may have moved on its
		// own: "Terminal colours" is a setting of its own and can change while
		// the theme stands still. `applyPalette` above runs only when the theme
		// actually changed, so this cannot live in there.
		//
		// It matters now in a way it did not before: `TerminalScheme.current` used
		// to be worked out on every access, so a changed scheme took effect by
		// itself and nobody had to say so. It is remembered now, because working
		// it out meant two `UserDefaults` reads per frame, so forgetting it is
		// something that has to be *done* — and this is the moment a preference
		// changed. Cheap: it nils a cache, and the table is rebuilt on the next
		// draw rather than here.
		TerminalPalette.invalidate()

		editor.applySettings()
		navigator.applySettings()
		toolStrip.applySettings()
		bottomPanel.applySettings()

		// The pills re-measure at the new scale, and the toolbar item has to be
		// told to re-lay-out around them.
		titlebar.relayout()
		window?.toolbar?.validateVisibleItems()

		// The tool strip's width changed, which moves everything to its right.
		toolStripWidthConstraint?.constant = ToolWindowBar.width
		updateTopInsets()
	}

	/// Re-reads the palette everywhere it was copied when a view was built.
	private func applyPalette() {
		window?.backgroundColor = Theme.current.windowBackground
		window?.appearance = NSAppearance(named: Theme.current.isLight ? .aqua : .darkAqua)

		if let content = window?.contentView {
			ThemeSwap.apply(from: Theme.previous, to: Theme.current, in: content)
		}
		splitView.needsDisplay = true

		// The terminal keeps its palette as a table of components, and the
		// theme-following scheme is a different table in daylight.
		TerminalPalette.invalidate()
		bottomPanel.applySettings()

		// Rebuilt rather than swapped: a sidebar pane is cheap to make and
		// draws a dozen shades that are chosen as it builds.
		sidebar.install(tool: sidebar.currentSidebarTool, force: true)
	}

	/// Gives the project tree keyboard focus.
	func focusNavigator() {
		navigator.focusTree()
	}

	/// Also reachable by double-clicking the empty part of the tab strip.
	@objc func newScratchFile(_ sender: Any?) {
		editor.newScratch()
	}
}
