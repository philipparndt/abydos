import AppKit
import AbydosKit

/// How the window is divided, and what gets the room.
///
/// The splits, the panel's height, the insets every child measures itself
/// against, and the two maximise gestures — the editor taking the window and
/// the terminal taking it. Also what is remembered of all that per project.
///
/// This is the window controller's own work rather than a collaborator's: it is
/// about the window, and there is nothing here that another object could own
/// without being handed the window to do it.
extension MainWindowController {
	/// What AppKit files this window's frame and dividers under.
	///
	/// Renamed with the app, and **carried across rather than simply renamed**:
	/// these are the only `ideai` names that held something a person would miss.
	/// A rename on its own puts the window back at its default size and both
	/// dividers back to the middle, once, for everybody — which is a small loss
	/// but an avoidable one, and nobody would connect it to a rename.
	static let mainWindowLayoutName = "AbydosMainWindow"

	static let splitLayoutName = "AbydosSplit"

	static let panelSplitLayoutName = "AbydosPanelSplit"


	/// Copies what the old names saved onto the new ones, once.
	///
	/// The defaults keys are AppKit's own spelling — `NSWindow Frame <name>` and
	/// `NSSplitView Subview Frames <name>` — which is why they are written out
	/// here rather than derived: they are somebody else's format and worth being
	/// able to read.
	///
	/// Only when the new key is absent, so this cannot undo a later change; and
	/// the old keys are left where they are, because a copy nobody reads costs a
	/// few bytes and deleting somebody's data to save them is the wrong trade.
	static func carryRememberedLayoutAcross() {
		let defaults = UserDefaults.standard
		let moves = [
			("NSWindow Frame IdeaiMainWindow", "NSWindow Frame \(mainWindowLayoutName)"),
			("NSSplitView Subview Frames IdeaiSplit", "NSSplitView Subview Frames \(splitLayoutName)"),
			("NSSplitView Subview Frames IdeaiPanelSplit",
			 "NSSplitView Subview Frames \(panelSplitLayoutName)"),
		]
		for (old, new) in moves where defaults.object(forKey: new) == nil {
			guard let saved = defaults.object(forKey: old) else { continue }
			defaults.set(saved, forKey: new)
		}
	}

	func updateRailForPanel() {
		toolStrip.setPanelSelection(bottomPanel.frontPaneKinds)
	}

	/// A hook event said something about the sessions of some project. The
	/// navigator decides whether it was the one this window is showing.
	func claudeSessionsChanged(slug: String) {
		navigator.claudeSessionsChanged(slug: slug)
	}

	/// The counts on the panel's pill moved, which happens more often than the
	/// tree's rows change: a session starting to work is one of these and not
	/// one of those.
	func runningSessionsChanged() {
		bottomPanel.runningSessionsChanged()
	}

	/// The tabs this window's panel holds, so a row in any window can say a
	/// session is in one of the app's tabs.
	var terminalIdentities: Set<String> { bottomPanel.terminalIdentities }

	/// Brings this window and one of its tabs forward, for a row clicked in
	/// another window. False when the tab is not here.
	func revealTerminalTab(identity: String) -> Bool {
		guard bottomPanel.revealTab(identity: identity) else { return false }
		window?.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		return true
	}

	func revealTmuxWindow(_ index: Int) {
		window?.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		bottomPanel.revealTmuxWindow(index)
	}

	/// Shows a toast raised from somewhere with no window of its own.
	///
	/// Exactly one window says it, so a message does not appear three times on
	/// a machine with three of them open.
	@objc private func toastPosted(_ notification: Notification) {
		guard speaksForTheApp, let toast = notification.userInfo?["toast"] as? Toast else { return }
		toasts.show(toast)
		// Answered while `Toast.post` is still on the stack, which is what lets a
		// question that landed in a gap between windows be asked again rather than
		// vanishing. See `Toast.ask`.
		(notification.userInfo?["taken"] as? Toast.Taken)?.value = true
	}

	/// A question in the corner is no longer worth asking.
	///
	/// Every window rather than the one that speaks for the app: the question was
	/// shown by whichever window was frontmost when it was asked, which is not
	/// necessarily this one now, and a question withdrawn from the wrong window is
	/// a question left on screen.
	@objc private func toastWithdrawn(_ notification: Notification) {
		guard let identifier = notification.userInfo?["identifier"] as? String else { return }
		toasts.withdraw(identifier)
	}

	/// Whether this window is the one to say something the whole app has to
	/// say.
	///
	/// The key window when there is one. When there is not — the app is in the
	/// background, which is exactly where it is while a language server takes
	/// its first few seconds to fail — the frontmost window says it instead,
	/// and it is still there when somebody comes back. "Only the key window"
	/// meant that news dropped silently whenever nobody was looking, which is
	/// most of the time news arrives.
	private var speaksForTheApp: Bool {
		guard let window else { return false }
		if let key = NSApp.keyWindow { return window === key }
		if let main = NSApp.mainWindow { return window === main }
		return window === NSApp.orderedWindows.first(where: { $0.isVisible })
	}

	func buildContent() {
		let root = ColoredView(color: Theme.current.windowBackground)
		root.colourSource = { Theme.current.windowBackground }

		toolStrip.onToggleNavigator = { [weak self] in self?.sidebar.showSidebarTool(.project) }
		toolStrip.onToggleTerminal = { [weak self] in self?.toggleTerminal(nil) }
		toolStrip.onReviewBranch = { [weak self] in self?.reviewBranch(nil) }
		toolStrip.onReviewUncommitted = { [weak self] in self?.reviewUncommittedChanges(nil) }
		toolStrip.onToggleChanges = { [weak self] in self?.sidebar.showSidebarTool(.changes) }
		toolStrip.onToggleBranches = { [weak self] in self?.sidebar.showSidebarTool(.branches) }
		toolStrip.onToggleStructure = { [weak self] in self?.sidebar.showSidebarTool(.structure) }
		toolStrip.onToggleScratches = { [weak self] in self?.sidebar.showSidebarTool(.scratches) }
		toolStrip.onToggleHistory = { [weak self] in self?.sidebar.showSidebarTool(.history) }
		toolStrip.onTogglePullRequests = { [weak self] in self?.sidebar.showSidebarTool(.pullRequests) }
		wireReviewing()
		toolStrip.onToggleBacklog = { [weak self] in self?.showBacklog(nil) }
		NotificationCenter.default.addObserver(
			self, selector: #selector(toastPosted(_:)), name: .abydosToast, object: nil
		)
		NotificationCenter.default.addObserver(
			self, selector: #selector(toastWithdrawn(_:)), name: .abydosToastWithdrawn, object: nil
		)

		bottomPanel.onDebugPaneOpened = { [weak self] pane in self?.wireBreakpoints(of: pane) }
		toolStrip.onToggleDebug = { [weak self] in self?.showDebugPanel(nil) }
		toolStrip.isDebugRunning = { [weak self] in self?.bottomPanel.activeDebugSession != nil }

		navigatorContainer = ColoredView(color: Theme.current.sidebarBackground)
		navigatorContainer.colourSource = { Theme.current.sidebarBackground }

		// The sidebar holds the tool, and a results list under it when one has
		// been put there.
		//
		// It used to be a split with a second pane underneath for a docked view,
		// and the only thing ever docked there was the usages list — which item
		// 470 moved into the bottom panel beside search, where the checklist it
		// shares already lives. It was made one view again because "a split with
		// one pane in it and a divider nobody can reach is not worth keeping for
		// a route nothing takes".
		//
		// **That reason was about the route, not about the split, and item 506 is
		// the route.** So the split is back, with the objection answered rather
		// than repeated: `sidebar.sidebarSplit` holds exactly one arranged subview
		// whenever nothing is docked below, and an `NSSplitView` with one subview
		// draws no divider at all. There is nothing to reach until there is
		// something to reach for.
		let toolContainer = ColoredView(color: Theme.current.sidebarBackground)
		toolContainer.colourSource = { Theme.current.sidebarBackground }

		sidebar.sidebarSplit = ThinDividerSplitView()
		sidebar.sidebarSplit.isVertical = false
		sidebar.sidebarSplit.dividerStyle = .thin
		sidebar.sidebarSplit.addArrangedSubview(toolContainer)
		sidebar.sidebarSplit.translatesAutoresizingMaskIntoConstraints = false
		navigatorContainer.addSubview(sidebar.sidebarSplit)
		NSLayoutConstraint.activate([
			sidebar.sidebarSplit.topAnchor.constraint(equalTo: navigatorContainer.topAnchor),
			sidebar.sidebarSplit.bottomAnchor.constraint(equalTo: navigatorContainer.bottomAnchor),
			sidebar.sidebarSplit.leadingAnchor.constraint(equalTo: navigatorContainer.leadingAnchor),
			sidebar.sidebarSplit.trailingAnchor.constraint(equalTo: navigatorContainer.trailingAnchor),
		])

		sidebar.primaryContainer = toolContainer

		sidebar.primaryContainer.addSubview(navigator.view)
		navigator.view.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			navigator.view.topAnchor.constraint(equalTo: sidebar.primaryContainer.topAnchor),
			navigator.view.bottomAnchor.constraint(equalTo: sidebar.primaryContainer.bottomAnchor),
			navigator.view.leadingAnchor.constraint(equalTo: sidebar.primaryContainer.leadingAnchor),
			navigator.view.trailingAnchor.constraint(equalTo: sidebar.primaryContainer.trailingAnchor),
		])
		sidebar.primaryToolView = navigator.view

		splitView = ThinDividerSplitView()
		splitView.isVertical = true
		splitView.dividerStyle = .thin
		splitView.addArrangedSubview(navigatorContainer)
		splitView.addArrangedSubview(editor.view)
		// No name in a driven run, for the reason the window frame gives: an
		// autosaved split writes `UserDefaults.standard` from inside AppKit. A
		// capture that wants a particular sidebar says so with `--sidebar-width`,
		// which is what `Scripts/screenshots.sh` has always done and why.
		splitView.autosaveName = DrivenRun.isActive ? "" : Self.splitLayoutName
		// The tree keeps the width it was given; the editor takes the rest.
		// Without this the split view re-divides whenever what is in the editor
		// changes shape — and opening a page of controls made the tree jump
		// wider, which is not what opening a page means.
		splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
		splitView.setHoldingPriority(.defaultLow + 10, forSubviewAt: 1)

		// The tree is as wide as it was left, said as a constraint rather than
		// left to the split view to work out. Whatever is in the editor changes
		// shape — a page of controls, a wide file, a diff — and every time it
		// did, the split view re-divided the window and the tree jumped.
		navigatorWidthConstraint = navigatorContainer.widthAnchor
			.constraint(equalToConstant: navigatorWidth)
		navigatorWidthConstraint.priority = .defaultHigh
		navigatorWidthConstraint.isActive = true
		splitView.delegate = self

		// The tree's own contents must not be able to demand a width. A row
		// showing a long path has an enormous natural size, and any layout pass
		// that consults it — such as the one that happens when a page opens in
		// the editor — would widen the tree to fit a path that is meant to be
		// truncated.
		for view in [navigatorContainer, navigator.view] as [NSView] {
			view.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
		}

		// The panel spans the full width below both the tree and the editor,
		// which is where IDEA puts its tool windows.
		verticalSplitView = ThinDividerSplitView()
		verticalSplitView.isVertical = false
		verticalSplitView.dividerStyle = .thin
		verticalSplitView.addArrangedSubview(splitView)
		verticalSplitView.addArrangedSubview(bottomPanel)
		verticalSplitView.autosaveName = DrivenRun.isActive ? "" : Self.panelSplitLayoutName
		// For `splitViewDidResizeSubviews`, which rounds the panel down to
		// whole terminal rows.
		verticalSplitView.delegate = self

		bottomPanel.onRequestHide = { [weak self] in self?.setPanelVisible(false) }
		bottomPanel.onToggleMaximize = { [weak self] in self?.togglePanelMaximized() }
		bottomPanel.onRequestNewTerminalMenu = { [weak self] view, point in
			guard let self else { return }
			self.newTerminalMenu().popUp(positioning: nil, at: point, in: view)
		}
		// Written when they change rather than only on the way out: a terminal
		// that survives a restart has to survive the kind of exit nobody plans.
		bottomPanel.onTerminalsChanged = { [weak self] in self?.rememberOpenEditors() }
		bottomPanel.onTearOffTerminal = { [weak self] detached, screenPoint in
			self?.openTerminalWindow(detached, at: screenPoint)
		}
		// The setting decides how a window starts; the control on the panel is
		// what changes it afterwards.
		bottomPanel.isFollowingProject = followsTerminal
		bottomPanel.onToggleFollowProject = { [weak self] in self?.toggleFollowTerminal() }
		bottomPanel.projectRoot = { [weak self] in self?.project?.root }
		bottomPanel.onWorkingDirectoryChanged = { [weak self] directory in
			self?.terminalDirectoryChanged(to: directory)
		}
		// A finding opens the file at its line, in the editor above the panel.
		bottomPanel.onOpenSymbol = { [weak self] frame in
			guard let self else { return }
			// The profiler knows a name, not a place; the symbol search is what
			// turns one into the other.
			self.results.showSymbols(query: ProfileFrame.symbolName(in: frame))
		}
		// The debugger's own toolbar, once the program has ended: whatever the
		// play button up in the titlebar would start is what these start too.
		// A run or a debugger brought forward takes the window back to the
		// project it belongs to — while the window is following its terminal,
		// which is the only time it is anywhere else.
		// Every route into a pane comes through the panel's column rebuild —
		// the button, ⇧⌘B, the Agent menu, a tab closing and leaving another in
		// front, a split. So the rail is told from there rather than from each
		// of the places somebody can open one.
		bottomPanel.onFrontPanesChanged = { [weak self] in self?.updateRailForPanel() }

		bottomPanel.onPaneNeedsProject = { [weak self] root in
			guard let self, self.followsTerminal else { return }
			// The other place a pane's report moves the window, and reachable in
			// a driven run: `--debug-steps` and `--run-line` both bring a pane
			// forward. Guarded where the report is acted on rather than by
			// filtering what a driven run is allowed to read, so the rule is in
			// the two places that could move the window and nowhere else.
			guard !LaunchOptions.parse().isDrivenRun else { return }
			// Following, so the same rule as a shell that moved: the panel is
			// where the change came from and is not to be moved by it. Through
			// the same classification too — a pane's root is a directory like
			// any other, and whether it is a project is not the pane's to say.
			self.follow(reported: root)
		}
		bottomPanel.onRunAgain = { [weak self] in self?.run.runSelectedConfiguration(debug: false) }
		bottomPanel.onDebugAgain = { [weak self] in self?.run.runSelectedConfiguration(debug: true) }
		// Room first, for the reason `makeRoomForTheEditor` already gives about a
		// breakpoint's line: everything that comes through here is a *pane*
		// asking for a file, and a pane can have the whole window. A backlog
		// item opened from a maximised board, a review finding, a search result
		// — each of them opened the file behind the thing that opened it, which
		// from the outside is indistinguishable from nothing happening.
		bottomPanel.onOpenFinding = { [weak self] url, line in
			guard let self else { return }
			self.makeRoomForTheEditor()
			self.editor.open(fileURL: url, atLine: line)
		}
		// A checklist row, which also says whether the keyboard goes with it. Room
		// is made for the editor either way — a preview nobody can see is not one
		// — but a preview leaves the keyboard in the list.
		bottomPanel.onOpenResult = { [weak self] url, match, intent in
			guard let self else { return }
			self.makeRoomForTheEditor()
			self.results.openFromChecklist(url, match: match, intent: intent)
		}
		bottomPanel.onOpenFileFromTerminal = { [weak self] request in
			self?.openFromTerminal(request)
		}
		// Through the delegate rather than `switchProject`, so a worktree
		// opened from a backlog card obeys the same rule as one opened from
		// the project switcher: this window or a new one, whichever the
		// setting says, and an already-open checkout is raised rather than
		// opened twice.
		bottomPanel.onOpenProject = { [weak self] root in
			guard let self else { return }
			(NSApp.delegate as? AppDelegate)?.open(projectAt: root, from: self)
		}
		// Set synchronously, not deferred: anything that opens the panel during
		// launch would otherwise be undone when the deferred block ran.
		bottomPanel.isHidden = true

		root.addSubview(toolStrip)
		// **Above everything the project can reach, and across the window.**
		// The strip is about the project, not about a file, so it belongs above
		// the editor *and* the panel rather than inside one editor group —
		// which would draw it twice in a split and not at all in a window
		// showing only a terminal.
		root.addSubview(trustBanner)
		root.addSubview(verticalSplitView)
		toolStrip.translatesAutoresizingMaskIntoConstraints = false
		trustBanner.translatesAutoresizingMaskIntoConstraints = false
		verticalSplitView.translatesAutoresizingMaskIntoConstraints = false

		toolStripWidthConstraint = toolStrip.widthAnchor.constraint(equalToConstant: ToolWindowBar.width)
		trustBannerHeight = trustBanner.heightAnchor.constraint(equalToConstant: 0)
		trustBannerTop = trustBanner.topAnchor.constraint(equalTo: root.topAnchor)
		trustBanner.isHidden = true
		trustBanner.onTrust = { [weak self] in self?.askToTrustProject() }
		trustBanner.onDetails = { [weak self] in self?.sayWhatTrustHoldsBack() }

		NSLayoutConstraint.activate([
			toolStrip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
			toolStrip.topAnchor.constraint(equalTo: root.topAnchor),
			toolStrip.bottomAnchor.constraint(equalTo: root.bottomAnchor),
			toolStripWidthConstraint,

			trustBanner.leadingAnchor.constraint(equalTo: toolStrip.trailingAnchor),
			trustBanner.trailingAnchor.constraint(equalTo: root.trailingAnchor),
			// **Below the titlebar, not under it.** The content view spans the
			// whole window — the titlebar is transparent — so every pane here
			// takes a top inset to clear it, and a strip pinned to the top
			// edge is a strip drawn behind the traffic lights. It was, and the
			// photograph is how that was found: the report said the strip was
			// up and the window did not show it.
			trustBannerTop,
			trustBannerHeight,

			verticalSplitView.leadingAnchor.constraint(equalTo: toolStrip.trailingAnchor),
			verticalSplitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
			verticalSplitView.topAnchor.constraint(equalTo: trustBanner.bottomAnchor),
			verticalSplitView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
		])

		window?.contentView = root
		refreshTrustBanner()

		// A click in the tree opens provisionally and keeps focus in the tree;
		// Return or a double-click pins the tab and moves focus to the editor.
		navigator.onSelectFile = { [weak self] url, focusEditor in
			guard let self else { return }
			// Only when it is being opened to look at: arrowing through the
			// tree in a popover should not throw the terminal out of the window
			// on the way past.
			if focusEditor { self.leaveTerminalFullScreen() }
			self.editor.open(fileURL: url, focusEditor: focusEditor, preview: !focusEditor)
		}
		navigator.onOpenTerminal = { [weak self] directory in
			self?.openTerminal(in: directory)
		}
		navigator.onOpenSubproject = { [weak self] url in self?.openSubproject(at: url) }
		navigator.onCompareFile = { [weak self] url in self?.sidebar.compareFileAgainstHead(url) }
		navigator.onShowFileHistory = { [weak self] url in self?.sidebar.showFileHistory(of: url) }
		navigator.onLeaveSubproject = { [weak self] in self?.leaveSubproject() }
		navigator.onPreviewModel = { url in
			MainWindowController.previewModel(at: url)
		}
		navigator.currentEditorFile = { [weak self] in self?.editor.activeGroup?.activeTabURL }
		// The tree reads the working copy's status anyway; the strip shows it.
		navigator.onChangeCount = { [weak self] count in
			guard let self else { return }
			self.toolStrip.uncommittedCount = count
			// What is committed but not sent is worth the same glance: the
			// same read the push button uses, on the same occasion the tree
			// reads the working copy.
			Task { @MainActor in
				guard let root = self.scopeRoot ?? self.project?.root else { return }
				let state = await GitPush.state(in: root)
				self.toolStrip.unpushedCount = state?.ahead ?? 0
			}
		}
		navigator.onFilesChanged = { [weak self] change in
			// Something wrote inside the project — possibly a file that is open.
			self?.editor.reloadExternallyChangedFiles()
			// With the change, so a superproject re-reads the one submodule the
			// write landed in — 0.01 s — rather than sweeping all of them.
			self?.sidebar.changesPane?.refresh(after: change)
			// A new main.go or Makefile target should get its play button
			// without reopening the project — but only when what was written
			// could be one. See `run.refreshRunConfigurations(because:)`.
			self?.run.refreshRunConfigurations(because: change)
		}
		// Switching tabs moves the tree's selection to match.
		editor.onTearOffTab = { [weak self] tab, screenPoint in
			guard let self else { return }
			onTearOffTab?(tab, screenPoint, self)
		}
		editor.onBecameEmpty = { [weak self] in
			guard let self, isTornOff else { return }
			// Nothing left in the window that was made to hold it.
			window?.close()
		}
		editor.onFilesDropped = { [weak self] urls in self?.openDropped(urls) }
		editor.onActiveFileChanged = { [weak self] url in
			// The outline belongs to the file in front, so it follows the tabs.
			self?.sidebar.refreshStructure()
			// The history offers to narrow itself to whatever is in front.
			self?.sidebar.historyPane?.offerScope(path: self?.relativePathOfActiveFile())
			guard let url else { return }
			self?.navigator.selectWithoutOpening(url: url)
		}
		// Clicking the breakpoint gutter reaches the running debug session, and
		// is remembered even when nothing is running yet.
		editor.onFindUsages = { [weak self] url, line, character in
			self?.serverActions.findUsages(in: url, line: line, character: character)
		}
		editor.onRename = { [weak self] url, line, character in
			self?.serverActions.renameSymbol(in: url, line: line, character: character)
		}
		editor.onWatch = { [weak self] expression in
			self?.watchFromEditor(expression)
		}
		editor.onFixWithAI = { [weak self] url, line, diagnostic in
			self?.serverActions.fixWithAI(url: url, line: line, diagnostic: diagnostic)
		}
		editor.onCopyLink = { [weak self] url, form, line, endLine in
			self?.codeLinks.copyLink(to: url, form: form, line: line, endLine: endLine)
		}
		editor.onEditBreakpoint = { [weak self] url, line in
			self?.debug.editBreakpoint(file: url, line: line)
		}
		editor.onToggleBreakpoint = { [weak self] url, line in
			self?.debug.toggleBreakpoint(file: url, line: line)
		}
		editor.onSetBreakpointEnabled = { [weak self] url, line, enabled in
			self?.debug.setBreakpoint(file: url, line: line, enabled: enabled)
		}
		editor.onDeleteBreakpoint = { [weak self] url, line in
			self?.debug.deleteBreakpoint(file: url, line: line)
		}
		editor.onSetOtherBreakpointsEnabled = { [weak self] url, line, enabled in
			self?.debug.setOtherBreakpoints(file: url, line: line, enabled: enabled)
		}
		editor.onLinesChanged = { [weak self] url, first, removed, inserted in
			self?.moveBreakpoints(inFile: url, editedFrom: first, removed: removed, inserted: inserted)
		}
		editor.onFileReloaded = { [weak self] url in
			self?.debug.reanchorBreakpoints(inFile: url)
		}
		editor.onRunLine = { [weak self] url, line in
			self?.run.runConfiguration(forFile: url, line: line)
		}
		editor.onApplyDiffSelection = { [weak self] change, diff, selected in
			self?.sidebar.applyDiffSelection(change: change, diff: diff, lines: selected)
		}
		editor.onDiscardDiffSelection = { [weak self] change, diff, selected in
			self?.sidebar.discardDiffSelection(change: change, diff: diff, lines: selected)
		}
		// **Offered only where git can do it.** `stash push --staged` arrived
		// in 2.35; on an older one the item is absent rather than a menu entry
		// that fails when pressed. Asked once, when the window is built.
		if let root = project?.root {
			Task { @MainActor [weak self] in
				guard await GitStash.canPushStaged(in: root) else { return }
				self?.editor.onStashDiffSelection = { [weak self] change, diff, selected in
					self?.sidebar.stashDiffSelection(change: change, diff: diff, lines: selected)
				}
			}
		}

		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			self.splitView.setPosition(self.navigatorWidth, ofDividerAt: 0)
			self.verticalSplitView.adjustSubviews()
		}
	}

	var isPanelVisible: Bool { !bottomPanel.isHidden }



	/// Gives the panel the whole window, or hands it back.
	///
	/// Everything above it goes: the tree, the editors and their tabs. The
	/// panel's own tabs stay, since they are how you get between terminals.
	/// Gives the window back, for anything that needs the editor to be visible.
	///
	/// A page opened while the terminal has the whole window would open behind
	/// it: the editor is hidden, not merely small. Asking for one is asking to
	/// look at it.
	func leaveTerminalFullScreen() {
		guard isPanelMaximized else { return }
		togglePanelMaximized(nil)
	}

	/// Gives the editor enough of the window to be looked at.
	///
	/// Two things can hide the line a breakpoint is on — or the file `abydos
	/// notes.md` just opened — and both are ordinary: the terminal can have the
	/// whole window, in which case the editor is hidden rather than small; and
	/// the panel can simply be tall, because it was dragged that way while
	/// reading a log. Neither is a state somebody chose *for this* — they chose
	/// it for the thing they were doing a minute ago, and something that arrives
	/// behind them has nothing to show.
	///
	/// Half the window is the most the panel keeps. Not a fixed height: the
	/// stack, the variables and the console all need room too, and taking the
	/// panel down to a strip to reveal one line is the opposite mistake.
	func makeRoomForTheEditor() {
		leaveTerminalFullScreen()
		guard isPanelVisible else { return }

		// After layout: leaving full screen lays out on the next pass, and a
		// divider position set before that is computed against the old
		// geometry — which puts it in the wrong place and looks like a bug in
		// the debugger rather than in the arithmetic.
		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			let total = self.verticalSplitView.bounds.height
			guard total > 200 else { return }

			let half = (total / 2).rounded(.down)
			guard self.bottomPanel.frame.height > half else { return }
			self.verticalSplitView.setPosition(
				total - half - self.verticalSplitView.dividerThickness, ofDividerAt: 0
			)
			self.tellTerminalsTheySizeChanged()
		}
	}


	var isEditorMaximized: Bool { beforeEditorMaximized != nil }

	/// Gives the editor the window if it has not got it, and does nothing if it
	/// has.
	///
	/// For the pages that are unreadable small: a log is a graph, a list of
	/// commits and a diff, and a review is a list of files and their diffs. Both
	/// are opened *to be read*, which is not what a third of a window is for.
	///
	/// **The commit page used to be one of them and no longer is.** It was
	/// unreadable small for a reason that has been fixed rather than for what it
	/// holds: a fixed 224 points of message area across the whole width, which
	/// left four lines of diff on a short page. With the message two rows tall
	/// and under the diff, it reads at the size it is given.
	///
	/// **It does not give the window back when the page closes.** The panel
	/// staying down after `makeRoomForTheEditor` is the same decision and its
	/// comment is the argument: putting panes back when the editor loses the
	/// focus that opened it is a mode nobody asked for, and it would fight the
	/// next click. Double-clicking the tab gives it back, and so does the menu.
	func giveTheEditorTheWindow() {
		guard !isEditorMaximized else { return }
		toggleEditorMaximized(nil)
	}

	/// Gives the editor the whole window, or gives it back.
	///
	/// A double-click on a tab that is already permanent, and the mirror of
	/// `togglePanelMaximized` — which does the same for the terminal, from the
	/// other side. Both hide rather than resize, for the reason that one records:
	/// a split view will not put a pane fully away, and a sliver of tree left
	/// showing is not what "give the editor the window" means.
	@objc func toggleEditorMaximized(_ sender: Any? = nil) {
		// Every editor strip draws the control, so every one is told which way
		// its arrows go.
		defer { editor.setMaximized(isEditorMaximized) }
		if let before = beforeEditorMaximized {
			beforeEditorMaximized = nil
			if before.navigator { openNavigator() }
			if before.panel { setPanelVisible(true) }
			updateTopInsets()
			return
		}

		// The terminal cannot have the window at the same moment. Un-maximising
		// it first, rather than refusing, because the gesture says what somebody
		// wants and the two states are exclusive.
		if isPanelMaximized { togglePanelMaximized(nil) }

		let navigatorShowing = !(navigatorContainer?.isHidden ?? true)
			&& (navigatorContainer?.frame.width ?? 0) >= 2
		beforeEditorMaximized = (navigator: navigatorShowing, panel: isPanelVisible)
		if navigatorShowing { toggleNavigator(nil) }
		if isPanelVisible { setPanelVisible(false) }
		updateTopInsets()
	}

	@objc func togglePanelMaximized(_ sender: Any? = nil) {
		if isPanelMaximized {
			sidebar.toolPopover?.performClose(nil)
			isPanelMaximized = false
			bottomPanel.isMaximized = false
			splitView.isHidden = false
			bottomPanel.setTopInset(0)
			verticalSplitView.adjustSubviews()
			let total = verticalSplitView.bounds.height
			let restored = heightBeforeMaximize ?? panelHeight
			if total > 200 {
				verticalSplitView.setPosition(
					total - restored - verticalSplitView.dividerThickness, ofDividerAt: 0
				)
			}
			tellTerminalsTheySizeChanged()

			// The sidebar comes back as it was left, whatever was looked at
			// over the terminal in the meantime — and the strip says so, which
			// it could not while there was no sidebar to point at.
			sidebar.install(tool: sidebar.currentSidebarTool, force: true)
			updateTopInsets()
			sidebar.updateSidebarSelection()
			return
		}

		setPanelVisible(true)
		isPanelMaximized = true
		bottomPanel.isMaximized = true
		// Nothing in the sidebar is showing any more, and the strip should not
		// claim otherwise; what it offers now opens over the terminal.
		toolStrip.setSidebarSelection(visible: false, tool: sidebar.currentSidebarTool)
		heightBeforeMaximize = max(160, bottomPanel.frame.height)
		// Hidden rather than resized to nothing: a split view will not put a
		// pane fully away, and a sliver of editor left showing is not what
		// "give the terminal the window" means.
		splitView.isHidden = true
		bottomPanel.setTopInset(sidebar.sidebarTopInset)
		verticalSplitView.adjustSubviews()
		verticalSplitView.setPosition(0, ofDividerAt: 0)
		tellTerminalsTheySizeChanged()
	}

	/// Once layout has settled, so the size read is the one the pane ended up
	/// with rather than the one it had.
	func tellTerminalsTheySizeChanged() {
		DispatchQueue.main.async { [weak self] in
			self?.bottomPanel.viewportChanged()
		}
	}

	@objc func zoomIn(_ sender: Any?) {
		Settings.shared.zoomIn()
	}

	@objc func zoomOut(_ sender: Any?) {
		Settings.shared.zoomOut()
	}

	@objc func resetZoom(_ sender: Any?) {
		Settings.shared.resetZoom()
	}

	/// Sets the window up to be shown to a room, or puts it back.
	///
	/// Both halves are one switch: the zoom a room needs and a palette a
	/// projector can actually show. Neither overwrites what was there — they
	/// are a second pair of preferences — so coming back is exact, whatever was
	/// zoomed or re-themed during the talk.
	@objc func togglePresentationMode(_ sender: Any?) {
		Settings.shared.presenting.toggle()
	}

	@objc func splitEditorRight(_ sender: Any?) {
		editor.splitActiveGroup(vertical: true)
	}

	@objc func splitEditorDown(_ sender: Any?) {
		editor.splitActiveGroup(vertical: false)
	}

	func previewDropZone(_ zone: EditorTabDrag.Zone) {
		editor.previewDropZoneForTesting(zone)
	}


	/// Gives the terminal the window, once there is a window to give.
	///
	/// Maximising divides the window's height, and a window that has not been
	/// laid out has none to divide — the split silently does nothing and the
	/// terminal stays where it was, which is what "not reliably" looked like.
	/// So it waits for a height, and gives up after a second rather than
	/// spinning if one never arrives.
	func maximizeTerminalWhenLaidOut(attempt: Int = 0) {
		DispatchQueue.main.async { [weak self] in
			guard let self, !self.isPanelMaximized else { return }
			guard self.verticalSplitView.bounds.height > 200 else {
				guard attempt < 60 else { return }
				self.maximizeTerminalWhenLaidOut(attempt: attempt + 1)
				return
			}
			self.togglePanelMaximized(nil)
		}
	}

	/// Kept for the menu items and the screenshot harness.
	@objc func showProjectView(_ sender: Any?) { sidebar.showSidebarTool(.project) }

	@objc func toggleChanges(_ sender: Any?) { sidebar.showSidebarTool(.changes) }

	@objc func toggleBranchesView(_ sender: Any?) { sidebar.showSidebarTool(.branches) }

	@objc func toggleStructureView(_ sender: Any?) { sidebar.showSidebarTool(.structure) }

	@objc func toggleScratchesView(_ sender: Any?) { sidebar.showSidebarTool(.scratches) }

	@objc func toggleHistoryView(_ sender: Any?) { sidebar.showSidebarTool(.history) }

	@objc func togglePullRequestsView(_ sender: Any?) { sidebar.showSidebarTool(.pullRequests) }

	/// Tells the review object the six things it cannot work out for itself.
	///
	/// **Wired from the window rather than from the sidebar**, which is where
	/// this began: every one of these is about the editor area or the project,
	/// and both belong to the window. The sidebar was only in the middle because
	/// the list has a button on the rail.
	private func wireReviewing() {
		let reviewing = sidebar.pullRequests
		reviewing.showList = { [weak self] in self?.sidebar.showSidebarTool(.pullRequests) }
		reviewing.rail = { [weak self] in self?.sidebar.railReportForTesting() ?? "" }
		reviewing.repositoryRoot = { [weak self] in
			self?.gitCommandRoot ?? self?.project?.root
		}
		reviewing.existingPage = { [weak self] identifier in
			self?.editor.activeGroup?.page(identifier: identifier)
		}
		reviewing.rememberSession = { [weak self] in self?.rememberOpenEditors() }
		reviewing.openCheckout = { [weak self] path in self?.switchProject(to: path) }
		reviewing.notify = { title, body in Toast.post(title, detail: body) }
		reviewing.openPage = { [weak self] page, title, identifier, symbol in
			guard let self, let group = self.editor.activeGroup else { return }
			self.leaveTerminalFullScreen()
			group.openPage(page, title: title, identifier: identifier, symbol: symbol)
			self.giveTheEditorTheWindow()
		}
	}

	/// The two questions every diff in this app answers, flipped from the View
	/// menu. Each `DiffView` hears about it through the settings notification.
	@objc func toggleSideBySideDiff(_ sender: Any?) {
		Settings.shared.diffIsSideBySide.toggle()
		(sender as? NSMenuItem)?.state = Settings.shared.diffIsSideBySide ? .on : .off
	}

	@objc func toggleDiffChrome(_ sender: Any?) {
		Settings.shared.diffShowsChrome.toggle()
		(sender as? NSMenuItem)?.state = Settings.shared.diffShowsChrome ? .on : .off
	}

	/// A key that used to open something and now opens the git tool.
	///
	/// **Doing nothing would be the worse answer.** ⌘2 and ⌘6 have been Commit
	/// and History for as long as this app has had them, and fingers do not
	/// read release notes. For one release they land somewhere sensible and say
	/// where the thing they used to open has gone.
	@objc func movedShortcut(_ sender: Any?) {
		sidebar.showSidebarTool(.branches)
		guard let item = sender as? NSMenuItem else { return }
		if item.keyEquivalent == "5" {
			Toast.post(
				"Committing is ⇧⌘K now",
				detail: "The working copy is in the git tool on ⌘2, and the message is written "
					+ "on a page of its own.",
				kind: .information
			)
		} else {
			Toast.post(
				"The log is ⇧⌘L now",
				detail: "It opens as a page, where a graph has room for its lanes.",
				kind: .information
			)
		}
	}

	/// What the editor has open, relative to the project — the file a history
	/// view offers to narrow itself to.
	func relativePathOfActiveFile() -> String? {
		guard let project, let url = editor.activeGroup?.activeTabURL else { return nil }
		// Canonical on both sides. A tab carries whatever URL opened it, and a
		// tab opened by a language server or a debugger carries the real path
		// while one opened from the tree carries the path the project was opened
		// by — so with the root normalised one way and the file the other, a
		// file under `/tmp` or `/var` narrowed the history to nothing. Same
		// asymmetry as 0430.
		// Against the *git* root, which is what a path handed to `git log` is
		// resolved from, and which may sit above the project root — a project
		// opened on a subdirectory of a checkout is the ordinary case. Measured
		// from the project root instead, the path was short by however many
		// components separate the two, and the history came back empty.
		let root = FilePath.canonical(gitCommandRoot ?? project.root)
		let path = FilePath.canonical(url)
		guard path.hasPrefix(root + "/") else { return nil }
		return String(path.dropFirst(root.count + 1))
	}

	func setWordWrap(_ enabled: Bool) {
		guard Settings.shared.wordWrap != enabled else { return }
		toggleWordWrap(nil)
	}

	func setPreviewMode(_ mode: PreviewMode) {
		editor.setPreviewMode(mode)
	}

	/// The four preview modes, as menu commands.
	///
	/// One action rather than four: the mode is on the item, which is what the
	/// tab strip's own dropdown already does, and it keeps the four of them
	/// from drifting apart. Being menu commands is what gives them keys at all,
	/// and — since the palette is the menus — what puts them in the palette.
	@objc func choosePreviewMode(_ sender: Any?) {
		guard let item = sender as? NSMenuItem,
		      let raw = item.representedObject as? String,
		      let mode = PreviewMode(rawValue: raw)
		else { return }
		setPreviewMode(mode)
	}

	/// Which modes the file in front can be shown in, and which it is in now.
	func previewModeState() -> (available: [PreviewMode], current: PreviewMode)? {
		// Asked of the group, which asks the tab. A menu is validated on every open,
		// so this cannot be a question that reads the file — the tab decided it once,
		// when it opened. See 0482.
		guard let modes = editor.activeGroup?.activeTabPreviewModes else { return nil }
		guard modes.count > 1 else { return nil }
		return (modes, editor.activeGroup?.currentPreviewMode ?? .source)
	}

	@objc func toggleBlame(_ sender: Any?) {
		editor.toggleBlame()
	}

	/// The explicit action the covers wait for, file-wide: enabled only for a
	/// tab that conceals, ticked while it is revealed.
	@objc func toggleRevealSecrets(_ sender: Any?) {
		editor.toggleRevealSecrets()
	}

	/// View ▸ Decrypt with sops: the chip's press, from the keyboard.
	@objc func decryptWithSops(_ sender: Any?) {
		editor.pressSops()
	}

	/// Asks about every edited decrypted buffer — open or parked — before the
	/// app quits, per file: *Encrypt and save*, *Discard*, *Cancel*. False
	/// stops the quit. Quitting is the one thing that loses a buffer kept in
	/// memory, so it is the one place that asks; an unedited buffer needs no
	/// answer, since the ciphertext is on disk.
	func settleDecryptedBuffersForQuit() -> Bool {
		for (group, tab) in editor.editedDecryptedTabs {
			switch askAboutDecrypted(named: tab.url.lastPathComponent) {
			case .alertFirstButtonReturn:
				guard group.encryptAndSaveSync(tab) else { return false }
			case .alertSecondButtonReturn:
				continue
			default:
				return false
			}
		}
		for parked in decrypted.edited() {
			switch askAboutDecrypted(named: parked.file.lastPathComponent) {
			case .alertFirstButtonReturn:
				// The same skip the editor's save path takes, for a loop that
				// does not go through it: a buffer whose text is still the
				// decrypt's own is a text whose ciphertext is already on disk,
				// byte for byte, and `sops` would mint a fresh one. Dropped as
				// *Discard* drops it, because there is nothing in it the disk
				// has not.
				if parked.buffer.baseline == parked.buffer.text {
					decrypted.discard(root: parked.root, file: parked.file)
					continue
				}
				let result = Sops.encryptSync(parked.buffer.text, for: parked.file)
				guard result.exitCode == 0, !result.stdout.isEmpty,
				      (try? Data(result.stdout.utf8).write(to: parked.file, options: .atomic)) != nil
				else {
					Toast.post(
						"Could not encrypt \(parked.file.lastPathComponent)",
						detail: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
					)
					return false
				}
				decrypted.discard(root: parked.root, file: parked.file)
			case .alertSecondButtonReturn:
				decrypted.discard(root: parked.root, file: parked.file)
			default:
				return false
			}
		}
		return true
	}

	private func askAboutDecrypted(named name: String) -> NSApplication.ModalResponse {
		let alert = NSAlert()
		alert.messageText = "Encrypt and save \(name)?"
		alert.informativeText = "It was decrypted in the editor and edited. "
			+ "Nothing decrypted has been written to disk; discarding loses the edits."
		alert.addButton(withTitle: "Encrypt and Save")
		alert.addButton(withTitle: "Discard")
		alert.addButton(withTitle: "Cancel")
		return alert.runModal()
	}

	@objc func toggleWordWrap(_ sender: Any?) {
		editor.toggleWordWrap()
	}

	@objc func toggleMarkdownPreview(_ sender: Any?) {
		editor.toggleMarkdownPreview()
	}

	/// ⌘⇧] and ⌘⇧[: the tabs in front of whoever is typing.
	///
	/// These went to the editor wherever the keyboard was, so pressed in a
	/// terminal they changed the file behind the panel and the panel's own strip
	/// — the `tmux` tab, the `Local` terminals — had no keyboard route at all.
	@objc func selectNextTab(_ sender: Any?) { selectTab(offset: 1) }

	@objc func selectPreviousTab(_ sender: Any?) { selectTab(offset: -1) }

	private func selectTab(offset: Int) {
		if isTerminalFocused {
			bottomPanel.selectNeighbouringTab(offset: offset)
		} else {
			editor.selectNextTab(offset: offset)
		}
	}

	/// Expands the first level of the tree, used by capture runs and after
	/// opening a project so the navigator is not just a single root row.
	func expandNavigatorTree() {
		navigator.expandTopLevel()
	}
}
