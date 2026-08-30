import AppKit
import AbydosKit

/// Following the terminal, and going to a place in the code.
///
/// The window can follow the terminal into another project, which is a per-window
/// switch rather than a setting. Going to a place — a file and a line, from a
/// stack frame, a link or a search — is here because both end in the same act:
/// making room for the editor and putting the caret somewhere.
extension MainWindowController {
	/// Debugs a binary, whatever produced it.
	///
	/// The other half of "Go Debug": a native executable is debugged by LLDB,
	/// which speaks the same protocol, so nothing above the adapter changes.
	@objc func debugExecutable(_ sender: Any?) {
		// Works with no project open: a binary is a thing you can debug on its
		// own, and needing a project first would be a rule for its own sake.
		let root = project?.root ?? FileManager.default.homeDirectoryForCurrentUser

		let panel = NSOpenPanel()
		panel.title = "Debug an executable"
		panel.message = "Pick a compiled program. It is debugged as it is, and not rebuilt."
		panel.canChooseDirectories = false
		panel.canChooseFiles = true
		panel.allowsMultipleSelection = false
		panel.directoryURL = root

		let start: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .OK, let url = panel.url, let self else { return }
			// Judged from where the binary is when there is no project to judge
			// from — a Go binary sitting next to a go.mod is still Go's.
			let adapter = DebugAdapters.adapter(
				forProgramAt: url.path,
				projectRoot: self.project?.root ?? url.deletingLastPathComponent()
			)
			guard let executable = DebugAdapters.executable(for: adapter) else {
				self.presentGoError("Could not find `\(adapter.command)`. \(adapter.installHint)")
				return
			}
			self.setPanelVisible(true)
			guard let session = self.bottomPanel.startDebugging(
				adapter: adapter,
				executable: executable,
				start: .launch(program: FilePath.canonical(url), arguments: []),
				breakpoints: self.debug.pendingBreakpoints
			) else { return }
			self.wire(session)
		}
		if let window { panel.beginSheetModal(for: window, completionHandler: start) } else { start(panel.runModal()) }
	}

	/// Attaches to something already running.
	///
	/// The case launching cannot cover: a server that is already up, or a
	/// process that only misbehaves after an hour of work.
	@objc func attachToProcess(_ sender: Any?) {
		let processes = RunningProcesses.list()
		guard !processes.isEmpty else {
			notify("Nothing to attach to", detail: "No running processes were found.")
			return
		}

		let picker = ProcessPicker()
		run.processPicker = picker
		picker.onAttach = { [weak self] chosen in
			guard let self else { return }
			self.run.processPicker = nil
			self.attach(to: chosen)
		}
		picker.show(processes: processes, over: window)
	}

	/// Starts a session on a process that is already running.
	private func attach(to process: RunningProcess) {
		let adapter = DebugAdapters.adapter(
			forProgramAt: process.path,
			projectRoot: project?.root ?? URL(fileURLWithPath: process.path).deletingLastPathComponent()
		)
		guard let executable = DebugAdapters.executable(for: adapter) else {
			notify("\(adapter.name) is not installed", detail: adapter.installHint)
			return
		}

		setPanelVisible(true)
		guard let session = bottomPanel.startDebugging(
			adapter: adapter,
			executable: executable,
			start: .attach(pid: process.pid),
			breakpoints: debug.pendingBreakpoints
		) else { return }
		wire(session)
	}

	@objc func debugContinue(_ sender: Any?) { debugSession?.resume() }

	@objc func debugPause(_ sender: Any?) { debugSession?.pause() }

	@objc func debugStepOver(_ sender: Any?) { debugSession?.stepOver() }

	@objc func debugStepInto(_ sender: Any?) { debugSession?.stepInto() }

	@objc func debugStepOut(_ sender: Any?) { debugSession?.stepOut() }

	/// Greys out the debug commands when nothing is being debugged.
	///
	/// A menu full of commands that do nothing is worse than one that says so.
	func validateMenuItem(_ item: NSMenuItem) -> Bool {
		// A shortcut the terminal needs belongs to the terminal while somebody
		// is typing in one. ⌃D ends a shell and answers k9s; ⌃R searches a
		// shell's history; ⌃P and ⌃N walk it. A menu item that claims those
		// swallows them before the program ever sees them — and a disabled item
		// lets the keystroke carry on down to the view that wants it.
		if bottomPanel.hasKeyboardFocus, Self.terminalShortcuts.contains(where: {
			$0.key == item.keyEquivalent
				&& item.keyEquivalentModifierMask.subtracting(.function) == $0.modifiers
		}) {
			return false
		}

		if item.action == #selector(choosePreviewMode(_:)) {
			guard let state = previewModeState(),
			      let raw = item.representedObject as? String,
			      let mode = PreviewMode(rawValue: raw)
			else {
				item.state = .off
				return false
			}
			item.state = mode == state.current ? .on : .off
			return state.available.contains(mode)
		}

		switch item.action {
		case #selector(debugContinue(_:)), #selector(debugPause(_:)),
		     #selector(debugStepOver(_:)), #selector(debugStepInto(_:)),
		     #selector(debugStepOut(_:)), #selector(debugStop(_:)):
			return debugSession?.isActive ?? false
		case #selector(newTerminalTab(_:)), #selector(newTerminalTabBeside(_:)):
			return bottomPanel.hasKeyboardFocus
		case #selector(newTerminalInContainer(_:)):
			// Off for the projects that have no such file, which is most of
			// them: an item that is always there and always fails is worse than
			// one that says by being grey which projects it is for.
			//
			// Named here rather than once at build time because which container
			// it means changes with the subproject being worked in, and this is
			// the moment before it is read.
			//
			// An item carrying a choice is named after *that* one: the chevron's
			// menu has one entry per devcontainer and they all come through here,
			// so naming them all after the preferred one would make every entry
			// in a project with two read the same.
			item.title = devContainerMenuTitle(for: choice(carriedBy: item))
			return hasDevContainer
		case #selector(navigateBack(_:)):
			return canNavigateBack
		case #selector(navigateForward(_:)):
			return canNavigateForward
		case #selector(togglePresentationMode(_:)):
			// Ticked while presenting, since the whole point is that it is a
			// mode you are in rather than a change you made.
			item.state = Settings.shared.presenting ? .on : .off
			return true
		default:
			return true
		}
	}

	/// Every state this file has been in, including abandoned branches.
	@objc func showFileHistory(_ sender: Any?) {
		editor.toggleFileHistory()
	}

	@objc func closeTab(_ sender: Any?) {
		// Falls back to closing the window when nothing is open, matching ⌘W.
		if editor.hasOpenFiles {
			editor.closeActiveTab()
		} else {
			window?.performClose(nil)
		}
	}

	/// Turns following on or off.
	@objc func toggleFollowTerminal(_ sender: Any? = nil) {
		followsTerminal.toggle()
		bottomPanel.isFollowingProject = followsTerminal
		guard followsTerminal else { return }
		// Catch up straight away rather than waiting for the shell to move.
		bottomPanel.reportWorkingDirectory()
	}

	/// The terminal moved. Follow it, if the window was asked to.
	///
	/// Only whole projects: moving between directories inside one changes
	/// nothing, which is what makes this bearable to leave switched on. Inside
	/// *the project*, not inside the repository around it — `projectToFollow`
	/// is where that distinction lives and why it has to be made.
	func terminalDirectoryChanged(to directory: URL) {
		// Never during a capture. A screenshot is of a project somebody named
		// on the command line, and a restored tmux session whose shell sits in
		// another checkout would quietly swap it for that one — which is a
		// screenshot of the wrong program, taken without complaint.
		//
		// The sentence above was true when nobody was photographing anything
		// too, and 0509 is what it cost. The guard stays: a driven run is about
		// a named project and must not follow a shell anywhere, including
		// somewhere the rule below would rightly follow it.
		//
		// **It asked about the picture and it meant the driving**, which is
		// 0534. A run with a verb and no `--screenshot` was not guarded at all,
		// so a terminal whose working directory had been deleted underneath it
		// took the window somewhere nobody named — reproduced five times out of
		// five, and the driver then did its work to whatever that window had
		// open. 0509 had already found this rule broader than photography once;
		// the comment was widened then and the test was not.
		guard !LaunchOptions.parse().isDrivenRun else { return }
		guard followsTerminal else { return }
		follow(reported: directory)
	}

	/// Acts on a pane's report of where it is.
	///
	/// Both reports come through here — a shell that changed directory, and a
	/// pane brought forward carrying the root it was made under — so a directory
	/// is classified in one place. **When they did not, the second one made a
	/// project of whatever it was given.** A pane created while the window was
	/// showing a folder in no working copy carries that folder as its root, and
	/// bringing it forward switched to it as a *project*: `.abydos` written
	/// beside it, a recents entry, and — the folder being the home directory —
	/// every directory underneath it then counted as inside the project, so no
	/// later `cd` moved the window again. Reported as "the folder navigator is
	/// stuck on my home folder", and the `.abydos` left behind would have kept
	/// it that way across a restart.
	func follow(reported directory: URL) {
		switch ProjectRoot.whereToFollow(
			from: directory, showing: showing,
			intoLooseFolders: Settings.shared.followsLooseFolders
		) {
		case .stay:
			return
		case let .project(root):
			switchProject(to: root, followingTerminal: true)
		case let .looseFolder(folder):
			switchProject(to: folder, followingTerminal: true, asLooseFolder: true)
		}
	}

	/// What this window is showing, in the terms the follow rule is written in.
	///
	/// Asked of the project rather than of the file system, because the answer
	/// is not always what the file system would say: a folder somebody opened
	/// deliberately is a project even with no marker above it, and the rule that
	/// keeps its tabs safe from a `cd` into a subdirectory depends on knowing
	/// that.
	private var showing: ProjectRoot.Showing {
		guard let project else { return .nothing }
		return project.isLooseFolder ? .looseFolder(project.root) : .project(project.root)
	}

	/// Swaps one project for another in place, keeping what each had open.
	///
	/// - Parameter followingTerminal: whether the terminal is what moved. Then
	///   the window it is showing is the one somebody just chose, and neither
	///   half of remembering a tmux window applies: see the two notes below,
	///   which between them are why this parameter exists.
	/// - Parameter asLooseFolder: whether the root is a folder in no working copy
	///   rather than a project. Only a terminal reaches this: every explicit way
	///   of opening a folder makes a project of it. See `Project.isLooseFolder`.
	func switchProject(
		to root: URL,
		followingTerminal: Bool = false,
		asLooseFolder: Bool = false
	) {
		let root = root.standardizedFileURL
		guard root.path != project?.root.standardizedFileURL.path else { return }

		// Named, so that a stall inside a switch says "project switch" rather
		// than "idle". It used to say idle — a two-and-a-half-second stall with
		// nothing to say for itself — which is the one thing the stall log
		// exists not to do.
		StallWatch.mark("project switch") {
			switchProjectBody(
				to: root, followingTerminal: followingTerminal, asLooseFolder: asLooseFolder
			)
		}
	}

	private func switchProjectBody(to root: URL, followingTerminal: Bool, asLooseFolder: Bool) {
		leftScope()

		let wasLooseFolder = project?.isLooseFolder ?? false

		// Moving between two folders is not a project switch. Every folder
		// shares one session, so putting it away and restoring it would be a tab
		// set torn down and rebuilt to what it already was — except that what
		// comes back is read per *root*, and a folder has nothing stored under
		// its own name, so the files somebody was reading would close because
		// they had walked into the next directory. The tree, the search and the
		// file index re-point, because where the shell is is worth showing.
		// Nothing else moves.
		if wasLooseFolder, asLooseFolder {
			load(project: Project(root: root, isLooseFolder: true), focusTree: false)
			return
		}

		if let current = project?.root {
			var session = editor.captureSession()
			session.terminals = bottomPanel.captureTerminals()
			session.isPanelVisible = isPanelVisible
			// The window it was left in, which is not the one showing when the
			// switch is *because* the terminal moved: see the rule itself, in
			// ProjectSession, for what recording that leads to.
			session.tmuxWindow = ProjectSession.rememberedWindow(
				showing: bottomPanel.currentTmuxWindowID,
				stored: sessions.session(for: current)?.tmuxWindow
					?? SessionStore.read(in: wasLooseFolder ? nil : current)?.tmuxWindow,
				followingTerminal: followingTerminal
			)
			session.subprojectPath = subprojectRoot.map { Subprojects.relativePath($0, to: current) }
			session.selectedConfiguration = run.selectedConfigurationName
			session.xcodeDestinations = run.xcodeDestinations
			session.breakpoints = debug.breakpointsToRemember()
			session.reviewTicks = sidebar.pullRequests.ticksToRemember()
			session.reviewCheckouts = sidebar.pullRequests.checkoutsToRemember()
			// The in-memory store is keyed by root, which is the wrong key for a
			// folder: they share one session, so a folder's goes straight to the
			// file every folder reads.
			if !wasLooseFolder { sessions.store(session, for: current) }
			// And beside the project, so tomorrow's window opens on today's
			// files: what was open is a property of the project, not of the
			// application that happened to be running. Nothing is written beside
			// a folder — nil is the one file they share.
			try? SessionStore.write(session, in: wasLooseFolder ? nil : current)
			// Its language servers stay running. Switching back has to be
			// instant, and stopping one costs a re-index — see 0427, where that
			// is decided and what it costs is written down.
		}

		// Read before anything is loaded: opening a project touches the editor
		// and the panel, and anything that writes the session on the way past
		// would overwrite the very thing being restored.
		let previous = asLooseFolder
			? SessionStore.read(in: nil)
			: (sessions.take(for: root) ?? SessionStore.read(in: root))

		load(project: Project(root: root, isLooseFolder: asLooseFolder), focusTree: false)
		// A folder somebody walked through is not something they opened, and a
		// recents list that fills up with every directory a shell passed through
		// is a list nobody can find a project in.
		if !asLooseFolder { RecentProjects.shared.record(url: root) }

		if let previous {
			editor.restore(previous)
		} else {
			editor.closeAllTabs()
			editor.restoreScratches()
		}

		// The terminals a project had, but only into a window that has none.
		//
		// A terminal is a place somebody is, not a property of the project: the
		// window follows the shell around when that is turned on, so closing
		// the shell that just changed directory would kill the thing doing the
		// navigating — and with it any way of navigating back.
		// The window it was left in, before the terminals — tmux has to be
		// attached for either, and going back to the right window first means
		// the tabs come up showing it rather than showing one and then moving.
		//
		// Never while following the terminal: the window showing then is the one
		// somebody selected a moment ago, and this is the app arguing with them
		// about it. It is also the other half of the loop described above —
		// selecting a window moves the shell, which moves the project, which
		// selects a window.
		if !followingTerminal, let window = previous?.tmuxWindow {
			bottomPanel.restoreTmuxWindow(window)
		}

		if !bottomPanel.hasTerminals, let previous, !previous.terminals.isEmpty {
			bottomPanel.restoreTerminals(previous.terminals)
			// And the panel itself, if it was showing: terminals that came back
			// behind a closed panel look like terminals that did not.
			if previous.isPanelVisible { setPanelVisible(true) }
		}
	}

	/// Writes what is open beside the project, so the next window on it opens
	/// where this one left off.
	func rememberOpenEditors() {
		guard let project, !isTornOff else { return }
		let root = project.root
		var session = editor.captureSession()
		session.terminals = bottomPanel.captureTerminals()
		session.isPanelVisible = isPanelVisible
		session.tmuxWindow = bottomPanel.currentTmuxWindowID
		session.subprojectPath = subprojectRoot.map { Subprojects.relativePath($0, to: root) }
		session.selectedConfiguration = run.selectedConfigurationName
		session.xcodeDestinations = run.xcodeDestinations
		session.breakpoints = debug.breakpointsToRemember()
		session.reviewTicks = sidebar.pullRequests.ticksToRemember()
		session.reviewCheckouts = sidebar.pullRequests.checkoutsToRemember()
		try? SessionStore.write(session, in: project.sessionRoot)
	}

	func setPanelVisible(_ visible: Bool) {
		guard visible != isPanelVisible else { return }

		// **This used to be `setTerminalSelected(visible)`, and that was the
		// reported fault.** The panel being open lit the *terminal* button, so a
		// window showing the backlog had the terminal lit and the backlog not.
		// The rail now asks which panes are in front, which is empty while the
		// panel is closed — so closing it still unlights the group, by the rule
		// rather than by a special case.
		defer { updateRailForPanel() }

		if visible {
			bottomPanel.isHidden = false
			verticalSplitView.adjustSubviews()
			// Deferred: at launch the split view has no height yet, so computing
			// the divider position now would place it at zero.
			DispatchQueue.main.async { [weak self] in
				guard let self else { return }
				let total = self.verticalSplitView.bounds.height
				guard total > 200 else { return }
				self.verticalSplitView.setPosition(total - self.panelHeight, ofDividerAt: 0)
			}
		} else {
			if isPanelMaximized {
				isPanelMaximized = false
				bottomPanel.isMaximized = false
				bottomPanel.setTopInset(0)
				splitView.isHidden = false
			}
			// Remember the height so reopening restores the same size.
			panelHeight = max(160, bottomPanel.frame.height)
			bottomPanel.isHidden = true
			verticalSplitView.adjustSubviews()
			editor.focusActiveEditor()
		}
	}

	@objc func toggleTerminal(_ sender: Any?) {
		if isPanelVisible, bottomPanel.hasSessions {
			setPanelVisible(false)
		} else {
			setPanelVisible(true)
			bottomPanel.showTerminal()
		}
	}

	/// Hands a model to GoSTL.
	///
	/// Launched rather than embedded: GoSTL's package vends an executable, and
	/// an executable target cannot also be linked into another app. It watches
	/// the file it is given, so editing a .scad here refreshes the preview
	/// there on its own.
	static func previewModel(at url: URL) {
		guard let executable = ModelPreview.executable() else { return }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = [url.path]
		try? process.run()
	}

	/// Opens a shell in a specific directory, from the navigator's context menu.
	func openTerminal(in directory: URL) {
		setPanelVisible(true)
		bottomPanel.newTerminal(in: directory)
	}

	/// Writes text into the active terminal, as though typed.
	func sendToTerminal(_ text: String) {
		bottomPanel.showTerminal()?.terminalView.send(text)
	}

	@objc func findInFile(_ sender: Any?) {
		editor.showFind()
	}

	/// Edit ▸ Toggle Comment, which is ⌘/.
	///
	/// The work is `CodeView.toggleLineComment()` and through it `LineComment`;
	/// the only thing that happens here is the refusal, because saying something
	/// needs the window's corner and the code view does not have one.
	///
	/// **The refusal is said every press, not once per file.** A stylesheet has no
	/// line comment and never will, and remembering that it had already been
	/// mentioned would make the second ⌘/ the silent keystroke this is here to
	/// avoid — which is the worst of the three ways to answer a gesture a language
	/// cannot do.
	@objc func toggleLineComment(_ sender: Any?) {
		guard let codeView = editor.activeGroup?.activeCodeView else { return }
		say(codeView.toggleLineComment())
	}

	/// The refusal, out loud. Split out so the menu item and the driver that
	/// exercises it produce the same sentence rather than two that can drift.
	func say(_ outcome: LineComment.Outcome) {
		guard case let .unavailable(reason) = outcome else { return }
		notify("Nothing was commented out", detail: reason, kind: .information)
	}

	func setFindQuery(_ query: String) { editor.setFindQuery(query) }

	func setProjectSearchQuery(_ query: String) {
		results.showProjectSearch(query: query)
	}

	@objc func findNext(_ sender: Any?) { editor.findNext() }

	@objc func findPrevious(_ sender: Any?) { editor.findPrevious() }

	@objc func findInProject(_ sender: Any?) {
		// No `setPanelVisible(true)` here since item 506: the panel is one of
		// four homes now, and showing it for a search that is about to appear
		// under the project view is a panel opening for nothing.
		//
		// Seed from the selection, which is what you usually want to search for.
		results.showProjectSearch(query: editor.selectedTextForSearch())
	}

	@objc func goRun(_ sender: Any?) { runGo(.run) }

	@objc func goBuild(_ sender: Any?) { runGo(.build) }

	@objc func goTest(_ sender: Any?) { runGo(.test) }

	@objc func goTrace(_ sender: Any?) { runGo(.trace) }

	@objc func goProfile(_ sender: Any?) { runGo(.profile) }

	@objc func goDebug(_ sender: Any?) { runGo(.debug) }

	/// Draws the pending debug.breakpoints in the gutter, which is what makes a
	/// restored one visible rather than merely remembered.
	/// Writes them down as soon as they change, the way the terminals do.
	///
	/// Not only when the window closes: a breakpoint costs a moment to place
	/// and is worth nothing after a crash that took the note of it, and the
	/// window may be closed by something that never asks — a restart, a build
	/// that replaces the app underneath it.
	func rememberBreakpoints() {
		rememberOpenEditors()
	}

	/// Moves the debug.breakpoints in a file with the text they were put on.
	///
	/// Typing above a breakpoint used to leave it on its line number while the
	/// code moved out from under it — so it stopped somewhere nobody had asked
	/// it to. A breakpoint on a line that is deleted goes with it.
	func moveBreakpoints(inFile url: URL, editedFrom first: Int, removed: Int, inserted: Int) {
		guard removed != inserted else { return }
		let path = FilePath.canonical(url)
		let list = debug.breakpoints(inFile: path)
		guard !list.isEmpty else { return }

		debug.replaceBreakpoints(inFile: path, with: list.compactMap { breakpoint in
			guard let line = BreakpointAnchors.moved(
				line: breakpoint.line, editedFrom: first, removed: removed, inserted: inserted
			) else { return nil }
			guard line != breakpoint.line else { return breakpoint }
			return Breakpoint(
				file: breakpoint.file,
				line: line,
				isEnabled: breakpoint.isEnabled,
				// Where it is now is not where the adapter bound it, so it
				// is drawn as unbound until the adapter says otherwise.
				isVerified: false,
				condition: breakpoint.condition,
				hitCondition: breakpoint.hitCondition,
				logMessage: breakpoint.logMessage,
				anchor: breakpoint.anchor
			)
		}
		.sorted { $0.line < $1.line })

		// The anchors now describe where these were before the edit. Taking them
		// again is a query over the whole file, so it waits for typing to stop.
		debug.scheduleAnchoring(inFile: url)
	}

	private func runGo(_ action: GoAction) {
		guard let project else { return }
		// The module need not be at the project root — a Go repository commonly
		// keeps go.mod in a subdirectory — so the modules found by discovery
		// decide where these commands run.
		guard let moduleRoot = chooseModuleRoot(in: scopeRoot ?? project.root) else { return }
		guard let go = GoTooling.findGoExecutable() else {
			presentGoError("Could not find the `go` executable. Install Go, or make sure it is in /opt/homebrew/bin or /usr/local/go/bin.")
			return
		}

		// Whatever is about to read these files reads them from disk, so what
		// is in the editor has to be there first. IDEA does the same before a
		// run, and it is what makes a long idle timer safe.
		autoSaveAll()

		let command: GoTooling.Command
		switch action {
		case .run, .build, .debug:
			// These need a specific main package; ask when there is a choice.
			guard let package = chooseMainPackage(in: moduleRoot) else { return }
			switch action {
			case .run: command = GoTooling.runCommand(executable: go, package: package)
			case .build: command = GoTooling.buildCommand(executable: go, package: package)
			default:
				guard let delve = GoTooling.findDelveExecutable() else {
					presentGoError("Could not find `dlv`. Install Delve with: go sidebar.install github.com/go-delve/delve/cmd/dlv@latest")
					return
				}
				run.startNativeDebugger(delve: delve, package: package)
				return
			}
		case .test: command = GoTooling.testCommand(executable: go)
		case .trace: command = GoTooling.traceCommand(executable: go)
		case .profile: command = GoTooling.profileCommand(executable: go)
		}

		setPanelVisible(true)
		bottomPanel.runCommand(
			title: command.title,
			executable: command.executable,
			arguments: command.arguments,
			// In the module, not the project root: `go test ./...` from a
			// directory with no go.mod fails whatever the arguments say.
			workingDirectory: moduleRoot,
			// One console per Go action per module: `go test` run again lands
			// where the last one was, and does not sit beside `go run`.
			reusing: "go:\(command.title):\(moduleRoot.path)"
		)
	}

	/// Connects a session to the window, whichever debugger is behind it.
	///
	/// Every way of starting one goes through here. Wiring it at the Go entry
	/// point instead meant a session started any other way ran perfectly and
	/// told the editor nothing: no execution marker, no breakpoint state.
	func wire(_ session: DebugSession) {
		session.onHotSwap = { [weak self, weak session] event, wasStopped in
			guard let self, let session else { return }
			self.run.reportHotSwap(event, wasStopped: wasStopped, in: session)
		}
		session.onBreakpointsChanged = { [weak self, weak session] in
			guard let self, let session else { return }
			self.debug.syncBreakpointsToEditor(from: session)
		}
		// The values, on every stop and every frame change — the pane rebuilds
		// its tree from the same callback, and the editor draws the same numbers
		// at the ends of the lines that name them.
		session.observeVariables { [weak self, weak session] in
			self?.editor.setInlineValues(session?.inlineValues)
		}
		// Opening one asks the adapter for its children, by the reference it
		// gave — the same request the panel's tree makes, from the one function
		// that makes it.
		editor.setVariableChildren { [weak session] reference in
			await session?.variables(reference: reference) ?? []
		}
		session.observeStopped { [weak self] file, line in
			guard let self else { return }
			// Room to see it, before opening it. Stopping somewhere is the one
			// moment the editor has to be visible, and the panel is often not
			// merely tall but the whole window.
			self.makeRoomForTheEditor()
			self.debug.executionMarker = (file, line)
			self.editor.open(fileURL: URL(fileURLWithPath: file), atLine: line)
			self.editor.setExecutionLocation(file: file, line: line)
		}
		toolStrip.setDebugRunning(true)
		session.observeState { [weak self, weak session] state in
			self?.toolStrip.setDebugRunning(state != .idle && state != .terminated)
			self?.run.updateRunControl(for: state, session: session)
			// The marker must go when execution resumes or the process ends.
			switch state {
			case .running, .terminated, .idle:
				self?.debug.executionMarker = nil
				self?.editor.setExecutionLocation(file: nil, line: nil)
				// A value that was true at the last breakpoint is not true a
				// microsecond after `continue`, and it is drawn in the same grey
				// either way.
				self?.editor.setInlineValues(nil)
			default:
				break
			}
		}
		debug.syncBreakpointsToEditor(from: session)
	}

	/// Picks the main package, prompting only when there is more than one.
	/// The Go module these commands should act on.
	///
	/// The project root itself when it holds go.mod, otherwise whichever module
	/// was found below it — asking only when there is genuinely a choice.
	private func chooseModuleRoot(in root: URL) -> URL? {
		if GoTooling.isGoModule(root) { return root }

		let modules = RunConfigurationDiscovery
			.searchDirectories(from: root)
			.filter { GoTooling.isGoModule($0) }

		if modules.isEmpty {
			presentGoError("No go.mod was found in this project or below it.")
			return nil
		}
		if modules.count == 1 { return modules[0] }

		let alert = NSAlert()
		alert.messageText = "Which module?"
		alert.informativeText = "This project contains several Go modules."
		alert.addButton(withTitle: "Choose")
		alert.addButton(withTitle: "Cancel")

		let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
		popup.addItems(withTitles: modules.map { relativeDescription(of: $0, from: root) })
		alert.accessoryView = popup

		guard alert.runModal() == .alertFirstButtonReturn else { return nil }
		return modules[popup.indexOfSelectedItem]
	}

	private func relativeDescription(of url: URL, from root: URL) -> String {
		guard url.path.hasPrefix(root.path + "/") else { return url.lastPathComponent }
		return String(url.path.dropFirst(root.path.count + 1))
	}

	private func chooseMainPackage(in root: URL) -> String? {
		let packages = GoTooling.findMainPackages(in: root)
		if packages.isEmpty {
			presentGoError("No package main found in this module.")
			return nil
		}
		if packages.count == 1 { return packages[0] }

		let alert = NSAlert()
		alert.messageText = "Which command?"
		alert.informativeText = "This module contains several main packages."
		alert.addButton(withTitle: "Run")
		alert.addButton(withTitle: "Cancel")

		let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
		popup.addItems(withTitles: packages)
		alert.accessoryView = popup

		guard alert.runModal() == .alertFirstButtonReturn else { return nil }
		return packages[popup.indexOfSelectedItem]
	}

	private func presentGoError(_ message: String) {
		// The first line is what fits in the corner; the rest is behind it.
		let firstLine = message.split(separator: "\n").first.map(String.init) ?? message
		notify(firstLine, detail: message.count > firstLine.count ? message : nil)
	}
}
