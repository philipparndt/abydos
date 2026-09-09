import AppKit
import AbydosKit

/// What the window can be asked from a script, and what it knows about the
/// Claude sessions running in its terminals.
extension MainWindowController {
	// MARK: - Testing

	/// Takes a tab dragged out of another window.
	func adopt(_ tab: EditorViewController.Tab) {
		editor.adopt(tab)
	}



	func makeSidebar() -> SidebarController {
		let bar = SidebarController(editor: editor, navigator: navigator)
		bar.project = { [weak self] in self?.project }
		bar.hostWindow = { [weak self] in self?.window }
		bar.gitCommandRoot = { [weak self] in self?.gitCommandRoot }
		bar.rememberedMessage = { [weak self] in self?.rememberedMessage }
		bar.rememberedFolds = { [weak self] in self?.rememberedFolds ?? [:] }
		bar.holdDraft = { [weak self] root, draft in self?.drafts.hold(draft, for: root) }
		bar.heldDraft = { [weak self] root in self?.drafts.peek(for: root) }
		// A buffer is parked under the project being left, which is still
		// `project` when the switch parks — and taken under the one that has
		// just been loaded when its session reopens the file.
		editor.parkDecrypted = { [weak self] file, buffer in
			guard let self, let root = self.project?.root else { return }
			self.decrypted.park(buffer, root: root, file: file)
		}
		editor.takeParkedDecrypted = { [weak self] file in
			guard let self, let root = self.project?.root else { return nil }
			return self.decrypted.take(root: root, file: file)
		}
		bar.discardDraft = { [weak self] root in self?.drafts.discard(for: root) }
		// Restoring these two, not opening them fresh: both refuse to take the
		// window from a maximised terminal on this path, since nobody asked.
		bar.openLaunchConfigurationsPage = { [weak self] in
			self?.run.showLaunchConfigurations()
		}
		bar.openSettingsPage = { [weak self] in self?.showSettingsPage(nil) }
		bar.relativePathOfActiveFile = { [weak self] in self?.relativePathOfActiveFile() }
		bar.symbols = { [weak self] query, scope in
			await self?.serverActions.symbols(matching: query, scope: scope) ?? []
		}
		bar.notify = { [weak self] title, detail in self?.notify(title, detail: detail) }
		bar.isNavigatorVisible = { [weak self] in
			guard let self, let container = self.navigatorContainer else { return false }
			return !container.isHidden
				&& !self.splitView.isSubviewCollapsed(container)
				&& container.frame.width >= 2
		}
		bar.showNavigator = { [weak self] in self?.openNavigator() }
		bar.hideNavigator = { [weak self] in self?.toggleNavigator(nil) }
		bar.isPanelMaximized = { [weak self] in self?.isPanelMaximized ?? false }
		bar.leaveMaximised = { [weak self] in self?.togglePanelMaximized(nil) }
		bar.leaveTerminalFullScreen = { [weak self] in self?.leaveTerminalFullScreen() }
		bar.onInsetsChanged = { [weak self] in self?.updateTopInsets() }
		bar.giveTheEditorTheWindow = { [weak self] in self?.giveTheEditorTheWindow() }
		bar.isPanelVisible = { [weak self] in self?.isPanelVisible ?? false }
		bar.readGit = { [weak self] in self?.readGit() }
		bar.openProject = { [weak self] url in
			guard let self else { return }
			(NSApp.delegate as? AppDelegate)?.open(projectAt: url, from: self)
		}
		return bar
	}


	func makeDebug() -> DebugCoordinator {
		let coordinator = DebugCoordinator(editor: editor, panel: bottomPanel)
		coordinator.debugSession = { [weak self] in self?.bottomPanel.activeDebugSession }
		coordinator.projectRoot = { [weak self] in self?.project?.root }
		coordinator.hostWindow = { [weak self] in self?.window }
		coordinator.onRememberBreakpoints = { [weak self] in self?.rememberBreakpoints() }
		coordinator.onBreakpointsChanged = { [weak self] in self?.refreshBreakpointList() }
		coordinator.onDebugContinue = { [weak self] in self?.debugContinue($0) }
		coordinator.onDebugStepOver = { [weak self] in self?.debugStepOver($0) }
		coordinator.onDebugStepInto = { [weak self] in self?.debugStepInto($0) }
		coordinator.onDebugStepOut = { [weak self] in self?.debugStepOut($0) }
		coordinator.onWatchFromEditor = { [weak self] expression in self?.watchFromEditor(expression) }
		return coordinator
	}

	var debugSession: DebugSession? { bottomPanel.activeDebugSession }




	// Menu-bar selectors. AppKit resolves these against the responder chain and
	// finds them here; the work is the collaborator's.
	@objc func renameSymbol(_ sender: Any?) { serverActions.renameSymbol(sender) }
	@objc func completeAtCaret(_ sender: Any?) { serverActions.completeAtCaret(sender) }
	@objc func showCodeActions(_ sender: Any?) { serverActions.showCodeActions(sender) }
	@objc func showSourceActions(_ sender: Any?) { serverActions.showSourceActions(sender) }
	@objc func copyReference(_ sender: Any?) { codeLinks.copyReference(sender) }
	@objc func copyPermalink(_ sender: Any?) { codeLinks.copyPermalink(sender) }
	@objc func goToCopiedPlace(_ sender: Any?) { codeLinks.goToCopiedPlace(sender) }

	// Menu-bar selectors, which AppKit resolves against the responder chain and
	// finds here rather than on the coordinator.
	@objc func showRunConfigurations(_ sender: Any?) { run.showRunConfigurations(sender) }
	@objc func newFromMakeGoal(_ sender: Any?) { run.newFromMakeGoal(sender) }
	@objc func debugStop(_ sender: Any?) { run.debugStop(sender) }

	/// The run strip in the titlebar.
	///
	/// Built here rather than by `TitlebarController`: it sits in that toolbar
	/// and every button on it is about running, which is this class's until
	/// there is a run coordinator to take it.
	func makeRunToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
		let item = NSToolbarItem(itemIdentifier: identifier)
		let control = RunControl()
		control.onRun = { [weak self] in self?.run.runSelectedConfiguration(debug: false) }
		control.onDebug = { [weak self] in self?.run.runSelectedConfiguration(debug: true) }
		control.onStop = { [weak self] in self?.run.stopRunning() }
		control.onProfile = { [weak self] in self?.run.profileSelectedConfiguration() }
		control.onCoverage = { [weak self] in self?.run.runSelectedWithCoverage() }
		// The ways of starting a debug session that used to live on the rail's
		// ladybird. The bodies did not move — only which control asks.
		control.onDebugExecutable = { [weak self] in self?.debugExecutable(nil) }
		control.onAttachToProcess = { [weak self] in self?.attachToProcess(nil) }
		control.onDebugGoPackage = { [weak self] in self?.goDebug(nil) }
		control.isGoProject = { [weak self] in
			guard let root = self?.project?.root else { return false }
			return GoTooling.isGoModule(root) || !RunConfigurationDiscovery
				.searchDirectories(from: root)
				.filter(GoTooling.isGoModule)
				.isEmpty
		}
		control.onChooseConfiguration = { [weak self, weak control] rect in
			guard let control else { return }
			self?.showConfigurationMenu(from: rect, in: control)
		}
		control.onRunStateChanged = { [weak self] state in
			self?.titlebar.setRunState(state)
		}
		run.runControl = control
		item.view = control
		run.refreshRunControl()

		// The whole strip in a menu: run, debug, stop and the list of
		// configurations, so a narrow window loses the buttons but not the
		// ability to press them.
		let menu = NSMenuItem(title: "Run", action: nil, keyEquivalent: "")
		menu.submenu = runOverflowMenu()
		item.menuFormRepresentation = menu
		// Last to go: it is the one thing here that is pressed rather than
		// read.
		item.visibilityPriority = .high
		return item
	}

	/// The list of configurations, and the ways to change them.
	///
	/// **A popover rather than the flat menu it used to be.** The menu printed
	/// goals × modules: a reactor of a hundred modules offering three goals came
	/// to three hundred rows, two hundred and ninety-seven of them saying the
	/// same three words, running off the bottom of the screen and under a scroll
	/// arrow — and an `NSMenu` cannot be typed at, so there was nothing to do
	/// but scroll it. `RunPicker` names each goal once and treats the module as
	/// the second choice it is; this is the same popover the project pill and
	/// the branch pill use, so the filtering and the keys are the ones already
	/// there.
	func showConfigurationMenu(from rect: NSRect, in control: RunControl) {
		ProjectSwitcherPopover.show(
			relativeTo: control,
			anchorRect: rect,
			currentProject: project,
			owner: self,
			focus: .runs,
			runs: run.runList()
		)
	}

	func runOverflowMenu() -> NSMenu {
		let menu = NSMenu()
		menu.addItem(menuItem("Run", #selector(runSelected(_:))))
		menu.addItem(menuItem("Debug", #selector(debugSelected(_:))))
		menu.addItem(menuItem("Stop", #selector(stopSelected(_:))))
		menu.addItem(.separator())

		for configuration in run.launchConfigurations {
			let item = NSMenuItem(
				title: configuration.name,
				action: #selector(RunCoordinator.configurationChosen(_:)),
				keyEquivalent: ""
			)
			item.target = run
			item.representedObject = configuration.name
			item.state = configuration.name == run.selectedConfiguration?.name ? .on : .off
			menu.addItem(item)
		}
		return menu
	}

	// Menu-bar items find their target through the responder chain, and this
	// class is on it while `SidebarController` is not. So the actions stay
	// here, one line each, and the work is the sidebar's.
	@objc func showLogPage(_ sender: Any?) { sidebar.showLogPage(scopedTo: nil) }
	@objc func showCommitPage(_ sender: Any?) { sidebar.showCommitPage(carrying: nil) }
	@objc func showEstatePage(_ sender: Any?) { sidebar.showEstatePage() }

	/// Flips how the git page arranges a commit's files, and ticks itself.
	@objc func toggleCommitFilesByFolder(_ sender: Any?) {
		Settings.shared.commitFilesByFolder.toggle()
		sidebar.logPage?.applyFileArrangement()
		(sender as? NSMenuItem)?.state = Settings.shared.commitFilesByFolder ? .on : .off
	}
	var toolStrip: ToolWindowBar { sidebar.rail }








	/// Says something without stopping anything.
	///
	/// Automatic modals are banned here: they take the keyboard and demand
	/// dismissal for news as small as "no go.mod in this project". A toast
	/// says it in the corner and opens the details if it turns out to matter.
	func notify(
		_ title: String,
		detail: String? = nil,
		kind: Toast.Kind = .error,
		actionTitle: String? = nil,
		action: (() -> Void)? = nil
	) {
		toasts.show(Toast(
			kind: kind, title: title, detail: detail, actionTitle: actionTitle, action: action
		))
	}

	// MARK: - Claude sessions in the terminal

	/// The tmux session the panel's tabs are showing, if they are showing one.
	var mirroredTmuxSession: String? { bottomPanel.mirroredTmuxSession }

	/// Which of those windows is the active one.
	var activeTmuxWindow: Int? { bottomPanel.activeTmuxWindow }

	/// Tells the rail which panes are in front.
	///
	/// The same shape as the `setSidebarSelection` call beside it, which is the
	/// point: both groups of the rail now answer one question in one way.
}
