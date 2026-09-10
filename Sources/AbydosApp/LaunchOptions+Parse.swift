import AppKit
import AbydosKit

/// Reading the command line into `LaunchOptions`.
///
/// One long switch over the arguments, and it is long because the list of
/// flags is: this file is the reader and the file beside it is what is read
/// into. Splitting them is what lets somebody looking for a flag read the
/// declarations without walking through the parsing of every other one.
extension LaunchOptions {
	static func parse(_ arguments: [String] = CommandLine.arguments) -> LaunchOptions {
		var options = LaunchOptions()
		var index = 1
		while index < arguments.count {
			let argument = arguments[index]
			func next() -> String? {
				guard index + 1 < arguments.count else { return nil }
				index += 1
				return arguments[index]
			}

			switch argument {
			case "--open":       options.projectPath = next()
			case "--file":       if let path = next() { options.filePaths.append(path) }
			case "--screenshot": options.screenshotPath = next()
			// The editor view alone, at whatever size it has.
			//
			// **A window capture is not evidence about the editor.** How much of
			// the window the editor gets is decided by the bottom panel, and a
			// run whose panel happens to be large photographs a terminal —
			// which is what 0540's own "after" picture came out as.
			case "--editor-shot": options.editorShotPath = next()
			case "--delay":      options.screenshotDelay = next().flatMap(Double.init) ?? 1.5
			case "--expand":     options.expandNavigator = true
			case "--type":       options.typeText = next()
			case "--replace":    options.replaceWith = next()
			case "--replace-all": options.replaceAll = true
			case "--select-text": options.selectText = next()
			case "--break-at":    if let line = next().flatMap(Int.init) { options.breakpointLines.append(line) }
			case "--breakpoints": options.showBreakpointList = true
			case "--breakpoints-debug":
				options.showBreakpointList = true
				options.breakpointsThenDebug = true
			case "--regex":      options.findRegex = true
			case "--collapse":   options.collapseFolds = true
			case "--preview":    options.previewPath = next()
			case "--markdown":   options.markdownPreview = true
			case "--subproject": options.subproject = next()
			case "--deliver-draft":
				let said = next() ?? ""
				let halves = said.split(separator: "@", maxSplits: 1)
				if let root = halves.first {
					options.deliverDraft = (
						root: String(root),
						at: halves.count > 1 ? (Double(halves[1]) ?? 9) : 9
					)
				}
			case "--settings-says": options.settingsSays = next()
			case "--settings-section": options.settingsSection = next()
			case "--settings-fold": options.settingsFold = next()
			case "--settings-keys": options.settingsKeys = next()
			case "--settings-filter": options.settingsFilter = next()
			case "--settings":   options.openSettings = true
			case "--about":      options.openAbout = true
			case "--zoom":       options.zoom = next().flatMap(Double.init)
			case "--terminal":   options.openTerminal = true
			case "--run":        if let line = next() { options.terminalInput.append(line) }
			case "--select":     if let drag = next() { options.terminalSelections.append(drag) }
			case "--tab-double": options.tabDoubleClicks.append(next().flatMap(Int.init) ?? 0)
			case "--quick-look": options.quickLook = true
			case "--review":     options.startReview = true
			case "--backlog":
				// The mode is optional, so peek rather than consume: without
				// one the next argument is the next flag.
				if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
					options.backlogMode = next()
				} else {
					options.backlogMode = "board"
				}
			case "--backlog-menu":
				let named = next()
				// A number is an item, anything else is a change's name. An
				// item's name *is* its number, so there is nothing to collide.
				if let number = named.flatMap(Int.init) {
					options.backlogMenu = number
				} else {
					options.backlogMenuChange = named
				}
			case "--backlog-tasks":
				let named = next()
				if let number = named.flatMap(Int.init) {
					options.backlogTasks = number
				} else {
					options.backlogTasksChange = named
				}
			case "--backlog-tick":
				// `<name|number>:<n>`, split at the last colon so a name with
				// one in it is still readable — and the index is what has to be
				// a number, not the card.
				let spec = next() ?? ""
				if let colon = spec.lastIndex(of: ":"),
				   let index = Int(spec[spec.index(after: colon)...]) {
					options.backlogTick = (card: String(spec[spec.startIndex..<colon]), index: index)
				}
			case "--backlog-tasks-shot": options.backlogTasksShot = next()
			case "--backlog-untick": options.backlogUntick = next()
			case "--backlog-new":  options.backlogNew = next()
			case "--backlog-init": options.backlogInit = true
			case "--review-uncommitted": options.reviewUncommitted = true
			case "--changes":    options.showChanges = true
			case "--push":       options.pushChanges = true
			case "--navigate":   options.navigateSteps = next()
			case "--tree":       options.treeSteps = next()
			case "--changes-tree": options.changesSteps = next()
			// The same steps again, later: a switch-and-return proof has to
			// compose before the switch and read after it, which one script
			// fired at a fixed moment cannot do. `--changes-later 14@steps`.
			case "--changes-later":
				let spec = (next() ?? "").split(separator: "@", maxSplits: 1)
				if spec.count == 2 {
					options.changesLater = (Double(spec[0]) ?? 12, String(spec[1]))
				}
			case "--pill-state": options.pillState = true
			case "--branch-rows": options.branchRowSteps = next()
			case "--hex":        options.hexSteps = next()
			case "--compare":
				if let a = next(), let b = next() { options.comparePaths = (a, b) }
			case "--compare-steps": options.compareSteps = next()
			case "--commit-menu": options.commitMenuRow = next().flatMap(Int.init)
			case "--log-page": options.logPageSteps = next()
			case "--commit-page": options.commitPageSteps = next()
			case "--pull-requests": options.pullRequestSteps = next()
			case "--estate": options.estateSteps = next()
			case "--type-latency": options.typingPresses = next().flatMap(Int.init)
			case "--report-open":
				options.openReportsAt = (next() ?? "10")
					.split(separator: ",").compactMap { Double($0) }
			case "--report-typing": options.openReportTyping = next().flatMap(Int.init) ?? 100
			case "--branch-pill":
				options.branchPillAt = next().flatMap(Double.init) ?? 8.0
			case "--report-answer": options.answerAt = next()
			case "--answer-until": options.answerDeadline = next().flatMap(Double.init) ?? 300
			case "--stall":      options.stallMilliseconds = next().flatMap(Int.init)
			case "--tab-add":
				// The number is optional, so peek rather than consume: without
				// one the next argument is the next flag.
				if index + 1 < arguments.count, let at = Double(arguments[index + 1]) {
					options.addTerminalTabAt = at
					index += 1
				} else {
					options.addTerminalTabAt = 3.0
				}
			case "--tab-fill":   options.fillTerminalTabs = next().flatMap(Int.init) ?? 12
			case "--panel-maximize": options.panelMaximizeAt = next().flatMap(Double.init) ?? 6
			case "--restore-pages":
				let said = next() ?? "log@8"
				let halves = said.split(separator: "@", maxSplits: 1)
				options.restorePages = (
					identifiers: halves[0].split(separator: ",").map(String.init),
					at: halves.count > 1 ? (Double(halves[1]) ?? 8) : 8
				)
			case "--tmux-tab-fill": options.fillTmuxTabs = next().flatMap(Int.init) ?? 16
			case "--click-tmux-tab":
				let said = next() ?? "1@14"
				let halves = said.split(separator: "@", maxSplits: 1)
				options.clickTmuxTab = (
					index: Int(halves[0]) ?? 1,
					at: halves.count > 1 ? (Double(halves[1]) ?? 14) : 14
				)
			case "--tab-close":  options.closeTerminalTabs = next().flatMap(Int.init) ?? 5
			case "--lsp-banner":  options.serverBanner = next() ?? "report"
			case "--rerun":      options.rerun = next() ?? "selected"
			case "--tmux-close": options.closeTmuxTab = next().flatMap(Int.init)
			case "--tmux-add":   options.addTmuxWindow = true
			case "--close-terminals": options.closeTerminals = next().flatMap(Double.init)
			case "--presentation": options.presentation = true
			case "--version": options.reportVersion = true
			case "--detail-dialog": options.detailDialog = true
			case "--click-panel-tab": options.clickPanelTab = next()
			case "--untmux":     options.toggleStrictTmuxOff = true
			case "--dump-settings": options.dumpSettings = next()
			case "--with-help": options.dumpSettingsHelp = true
			case "--make-run":   options.chooseMakeRun = next()
			case "--tmux-drag":  options.dragTmuxTab = next()
			case "--branch-menu": options.branchMenuRow = next().flatMap(Int.init)
			case "--push-branch": options.pushBranch = next()
			case "--report-cwd": options.reportsTerminalDirectory = true
			case "--devcontainer":
				options.pills.terminal = true
				// Which one is optional, so peek rather than consume: without it
				// the next argument is the next flag.
				if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
					options.pills.which = arguments[index + 1]
					index += 1
				}
			case "--devcontainer-pill":
				options.pills.devContainerAt = (next() ?? "8")
					.split(separator: ",").compactMap { Double($0) }
			case "--toasts":
				options.toastReportsAt = (next() ?? "6")
					.split(separator: ",").compactMap { Double($0) }
			case "--answer-toast": options.answerToast = next()
			case "--panel-tabs":
				options.panelTabsAt = (next() ?? "8")
					.split(separator: ",").compactMap { Double($0) }
			case "--panel-tail":
				options.panelTabsTail = next().flatMap(Int.init) ?? 12
			case "--worktree-pill":
				options.pills.worktreeAt = (next() ?? "8")
					.split(separator: ",").compactMap { Double($0) }
			case "--worktree-menu":
				options.pills.worktreeMenuAt = next().flatMap(Double.init) ?? 8
			case "--devcontainer-menu":
				options.pills.devContainerMenuAt = next().flatMap(Double.init) ?? 8
			case "--press-devcontainer-menu":
				if let spec = next() { options.pills.pressDevContainer.append(spec) }
			case "--banner-at":
				options.serverBannersAt = (next() ?? "3")
					.split(separator: ",").compactMap { Double($0) }
			case "--switch-project":
				let spec = (next() ?? "").split(separator: "@")
				if let path = spec.first {
					options.switchProjects.append(
						(String(path), spec.count > 1 ? Double(spec[1]) ?? 5 : 5)
					)
				}
			case "--report-focus":
				options.focusReportsAt = (next() ?? "3")
					.split(separator: ",").compactMap { Double($0) }
			case "--tab-add-menu": options.terminalAddMenu = true
			case "--close-window": options.closeLastWindowAt = next().flatMap(Double.init) ?? 5
			case "--report-geometry": options.reportsTerminalGeometry = true
			case "--terminal-link":
				let parts = (next() ?? "").split(separator: ":").map(String.init)
				if parts.count >= 2, let row = Int(parts[0]), let column = Int(parts[1]) {
					let mode = parts.count > 2 ? parts[2] : ""
					options.terminalLink = (row, column, mode == "click" || mode == "bare", mode == "bare")
				}
			case "--terminal-screen-at":
				options.terminalScreenAt = (next() ?? "5").split(separator: ",").compactMap { Double($0) }
			case "--tip-report":
				options.tipReportAt = (next() ?? "4").split(separator: ",").compactMap { Double($0) }
			case "--backlog-geometry":
				options.backlogGeometryAt = (next() ?? "3").split(separator: ",").compactMap { Double($0) }
			case "--blame": options.showsBlame = true
			case "--resize": options.resizeWidth = next().flatMap(Double.init)
			case "--switch-appearance": options.switchAppearance = next()
			case "--sidebar-width": options.sidebarWidth = next().flatMap(Double.init)
			case "--sidebar-shot": options.sidebarShot = next()
			case "--tab-close-hover": options.tabCloseHover = next()
			case "--collapse-row": options.collapseRow = next().flatMap(Int.init)
			case "--tmux-menu": options.tmuxMenuHovers = next().flatMap(Int.init) ?? 0
			case "--cmd-hover":  options.commandHoverAt = next()
			case "--attach-picker": options.attachFilter = next()
			case "--pills":      options.highlightPills = true
			case "--profile":    options.profilerAddress = next()
			case "--profile-kind": options.profilerKind = next()
			case "--running-tools": options.runningTools = true
			case "--stop-running":
				options.runningTools = true
				options.stopRunning = next()
			case "--pods":       options.podFilter = next()
			case "--pod-profile": options.podChoose = true
			case "--make-goal":  options.makeGoal = next()
			case "--make-debug": options.makeDebug = true
			case "--save-config": options.saveGutterLine = next().flatMap(Int.init)
			case "--window-width": options.windowWidth = next().flatMap(Double.init)
			// `--widen 300@6`: at six seconds, make the window 300 points wider
			// and report the panel's height either side.
			case "--widen":
				let spec = (next() ?? "").split(separator: "@")
				if let extra = spec.first.flatMap({ Double($0) }) {
					options.widenBy = (extra, spec.count > 1 ? Double(spec[1]) ?? 6 : 6)
				}
			case "--window-size":
				// `1600x1000`, the way every other tool spells it.
				let parts = (next() ?? "").split(separator: "x").compactMap { Double($0) }
				if parts.count == 2 { options.windowSize = CGSize(width: parts[0], height: parts[1]) }
			case "--panel-height": options.panelHeight = next().flatMap(Double.init)
			case "--sidebar":    options.sidebarTool = next()
			case "--run-line":   options.runLine = next().flatMap(Int.init)
			case "--debug-line": options.debugLine = next().flatMap(Int.init)
			case "--new-folder": options.newFolder = next()
			case "--new-file":   options.newFile = next()
			case "--scratch":    options.newScratch = true
			case "--scratches":  options.scratchSearch = next() ?? ""
			case "--open-scratch": options.openScratch = true
			case "--history":    options.historyCommit = next().flatMap(Int.init) ?? 0
			case "--fake-diagnostics": options.fakeDiagnostics = true
			case "--word-nav":   options.wordNavigation = true
			case "--vertical-nav": options.verticalNavigation = true
			case "--emacs-nav":  options.emacsNavigation = true
			case "--complete":   options.completeText = next()
			case "--complete-now":
				options.completeNow = true
				if let seconds = next().flatMap(Double.init) { options.completeNowAt = seconds }
			case "--bell":       options.bellBefore = next().flatMap(Double.init) ?? 0.15
			case "--undo-tree":  options.undoTree = true
			case "--debug-steps": options.debugSteps = true
			case "--terminal-tab-key": options.terminalTabKey = true
			case "--next-tab-in-panel": options.nextTabInPanel = true
			case "--type-block": options.typeBlock = true
			case "--bp-condition": options.breakpointCondition = next()
			case "--bp-edit": options.editBreakpointLine = next().flatMap(Int.init)
			case "--toolbar-image": options.toolbarImage = next()
			case "--toolbar-location": options.toolbarLocation = next()
			case "--option-key": if let pair = next() { options.optionKeys.append(pair) }
			case "--dead-key": options.deadKeys = next()
			case "--click-below": options.clickBelowLastLine = true
			case "--tab-menu": options.tabMenu = true
			case "--palette": options.paletteQuery = next() ?? ""
			case "--command": options.performCommand = next()
			case "--palette-files": options.paletteFiles = next() ?? ""
			case "--run-configs": options.listRunConfigurations = true
			case "--run-config": options.runConfigNamed = next()
			case "--cadova-watch":
				// The number is optional, so peek rather than consume: without one
				// the next argument is the next flag. Written the consuming way it
				// ate the `--file` after it, so `--cadova-watch --file model.swift`
				// opened no file and then reported, truthfully and uselessly, that
				// there was no Cadova pane in the tab in front — for the whole run.
				// 0507 spent a while believing that report.
				if index + 1 < arguments.count, let seconds = Double(arguments[index + 1]) {
					options.cadovaWatchSeconds = seconds
					index += 1
				} else {
					options.cadovaWatchSeconds = 30
				}
			case "--diagram-watch":
				// Peeked rather than consumed, for the reason above: `--diagram-watch
				// --file render.puml` must open the file.
				if index + 1 < arguments.count, let seconds = Double(arguments[index + 1]) {
					options.diagramWatchSeconds = seconds
					index += 1
				} else {
					options.diagramWatchSeconds = 10
				}
			case "--appearance-walk": options.appearanceWalk = next()
			case "--copy-path": options.copyPath = next() ?? "down"
			case "--burst": options.burstFrames = next().flatMap(Int.init)
			case "--commit-body": options.commitBody = next()
			case "--indent-block": options.indentBlock = next()
			case "--comment": if let spec = next() { options.commentBlocks.append(spec) }
			case "--comment-key": options.commentKey = true
			case "--snippet": options.snippet = next()
			case "--menu-keys": options.menuKeys = true
			case "--print-text": options.printText = true
			case "--theme": options.theme = next()
			case "--terminal-scheme": options.terminalScheme = next()
			case "--debug-stop": options.debugStop = true
			case "--debug-finish": options.debugStop = true; options.debugFinish = true
			case "--debug-inspect": options.debugInspect = true
			case "--debug-binary": options.debugBinary = next()
			case "--rail":       options.railReport = true
			case "--debug-interrupt": options.debugInterruptAt = Double(next() ?? "8") ?? 8
			case "--close-panel": options.closePanel = true
			case "--toast":      options.showToast = true
			case "--claude-running":
				// `<id>[@<seconds>][:<status>]`: the id is a UUID and holds
				// neither character, so each is taken off the end in turn.
				var said = next() ?? "0000dead-beef-4000-8000-000000000000"
				var spec = ClaudeRunning(id: said)
				if let colon = said.firstIndex(of: ":") {
					// `:<status>[:tab<n>]`
					let rest = said[said.index(after: colon)...].split(separator: ":").map(String.init)
					spec.status = rest.first ?? "working"
					for part in rest.dropFirst() {
						if part.hasPrefix("tab") { spec.tab = Int(part.dropFirst("tab".count)) }
						if part.hasPrefix("sub") { spec.subagents = Int(part.dropFirst("sub".count)) ?? 0 }
					}
					said = String(said[..<colon])
				}
				if let at = said.firstIndex(of: "@") {
					spec.after = Double(said[said.index(after: at)...]) ?? 0
					said = String(said[..<at])
				}
				spec.id = said
				options.claudeRunning.append(spec)
			case "--claude-seeded": options.seededWindows = next().flatMap(Int.init) ?? 6
			case "--hover-control":
				options.hoverControls += (next() ?? "").split(separator: ",").map(String.init)
			case "--running-sessions":
				options.running.at = (next() ?? "6")
					.split(separator: ",").compactMap { Double($0) }
			case "--running-sessions-menu":
				options.running.menuAt = next().flatMap(Double.init) ?? 6
			case "--running-sessions-palette":
				options.running.paletteAt = (next() ?? "6")
					.split(separator: ",").compactMap { Double($0) }
			case "--running-sessions-filter": options.running.filter = next()
			case "--running-sessions-keys": options.running.keys = next()
			case "--zoom-gesture":
				let said = next() ?? "zoom"
				let halves = said.split(separator: "@", maxSplits: 1)
				options.zoomGesture = String(halves[0])
				if halves.count > 1 { options.zoomGestureAt = Double(halves[1]) ?? 4 }
			case "--presentation-at":
				options.presentationAt = (next() ?? "4").split(separator: ",").compactMap { Double($0) }
			case "--running-sessions-choose":
				options.running.chooseAt = next().flatMap(Double.init) ?? 7
			case "--launch-run":    options.launchRun = true
			case "--launch-debug":  options.launchDebug = true
			case "--launch-profile": options.launchProfile = true
			case "--launch-config": options.launchConfiguration = next()
			case "--close-tabs": options.closeTabs = next()
			case "--zoom-window": options.zoomWindow = true
			case "--chart-path": options.reportChart = true
			case "--debug-console": options.debugConsole = true
			case "--tab-beside": options.terminalTabBeside = true
			case "--launch-menu":   options.launchMenu = true
			case "--launch-menu-open":
				options.launchMenu = true
				options.launchMenuGoal = next()
			case "--launch-editor": options.launchEditor = true
			case "--symbols":    options.symbolQuery = next() ?? ""
			case "--symbols-project": options.symbolProject = true
			case "--usages":     options.usagesAt = next()
			case "--rename":     options.renameAt = next()
			case "--definition": options.definitionAt = next()
			case "--usages-steps": options.usagesSteps = next()
			case "--lsp-wait":   options.lspWait = next().flatMap(Double.init)
			case "--lsp-root":   options.lspRoot = true
			case "--card-report": options.cardReport = true
			case "--draw-report": options.drawReport = true
			case "--mouse":      options.mouseSteps = next() ?? "report"
			case "--wobble":     options.wobblePixels = next().flatMap(Int.init) ?? 3
			case "--engine-switch": options.engineSwitchAt = next().flatMap(Double.init) ?? 5
			case "--engine-refuses": options.engineRefuses = true
			case "--engines": options.engineReportsAt = (next() ?? "4")
				.split(separator: ",").compactMap { Double($0) }
			case "--unhandled-motions": options.unhandledMotions = true
			case "--open-value": options.openValueAt = next().flatMap(Double.init) ?? 8.0
			case "--code-actions":
				// `12` or `12:6` — the column matters: gopls offers "Add test
				// for Greeting" over the name and nothing over the margin.
				let where_ = (next() ?? "1").split(separator: ":")
				let line = where_.first.flatMap { Int($0) } ?? 1
				options.codeActionsAt = (
					line: line - 1,
					character: where_.count > 1 ? (Int(where_[1]) ?? 0) : 0,
					after: next().flatMap(Double.init) ?? 20
				)
			case "--code-action-take": options.codeActionTake = next()
			case "--checkout-branch": options.checkoutBranch = next()
			case "--press-offer": options.pressOffer = true
			case "--copy-link": options.copyLink = next()
			case "--follow-link": options.followLink = next()
			case "--diagnostics":
				options.diagnosticsAt = (next() ?? "20")
					.split(separator: ",").compactMap { Double($0) }
			case "--backlog-offer":
				if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
					options.backlogOffer = next()
				} else {
					options.backlogOffer = "report"
				}
			case "--drag-tab": options.dragTab = true
			case "--drop-files":
				options.dropFiles = (next() ?? "").split(separator: ",").map(String.init)
			case "--find-across-tabs": options.findAcrossTabs = true
			case "--check-old-watcher": options.checkOldWatcher = true
			case "--external-edit": options.externalEdit = next().flatMap(Double.init)
			case "--send-bytes": options.terminalBytes = next()
			case "--preview-mode": options.previewMode = next()
			case "--export":     options.exportDiagram = next()
			case "--diagram-fit": options.diagramFit = next()
			case "--image-fit":  options.imageFit = next()
			case "--image-zoom": options.imageZoom = next()
			case "--video-report": options.videoReport = true
			case "--secrets":    options.secretsSteps = next()
			case "--sops":       options.sopsSteps = next()
			case "--indent":     options.indentSteps = next()
			case "--editor-menu": options.editorMenuSteps = next()
			case "--image-pan":  options.imagePan = next()
			case "--probe-lan":  options.probeLAN = next()
			case "--sidebar-cycle": options.sidebarCycle = true
			case "--zoom-cycle":  options.zoomCycle = true
			case "--tear-off":   options.tearOffFile = next()
			case "--bench-render": options.benchRender = true
			case "--metal-shot": options.metalShot = next()
			case "--maximize-terminal": options.maximizeTerminal = true
			case "--follow-terminal": options.followTerminal = true
			case "--breakpoint": options.breakpointLine = next().flatMap(Int.init)
			case "--breakpoint-report":
				if let at = next().flatMap(Double.init) { options.breakpointReports.append(at) }
			case "--breakpoint-off": options.disabledBreakpointLine = next().flatMap(Int.init)
			case "--stop-after": options.stopAfter = next().flatMap(Double.init)
			case "--find":       options.findQuery = next()
			case "--find-next":  options.findNextSteps = next().flatMap(Int.init) ?? 1
			case "--select-lines": options.selectLines = next()
			case "--search":     options.searchQuery = next()
			case "--search-steps": options.searchSteps = next()
			case "--wrap":       options.wordWrap = true
			case "--switcher":   options.switcherFilter = next()
			case "--switcher-keys": options.switcherKeys = next()
			case "--switcher-pill": options.switcherFromPill = true
			case "--trust":         options.trust.project = true
			case "--trust-parent":  options.trust.parent = true
			case "--trust-remote":  options.trust.remoteHost = true
			case "--trust-owner":   options.trust.remoteOwner = true
			case "--trust-report":  options.trust.report = true
			case "--trust-held-back": options.trust.heldBack = true
			case "--trust-dismiss": options.trust.dismiss = true
			case "--terminal-service": options.terminalServicePath = next()
			case "--switch-to":
				let said = next() ?? ""
				// `path@seconds`, and a path with no `@` in it keeps the default.
				if let at = said.lastIndex(of: "@"),
				   let seconds = Double(said[said.index(after: at)...]) {
					options.switchTo = String(said[..<at])
					options.switchToAt = seconds
				} else {
					options.switchTo = said
				}
			case "--choose-setting":
				let said = next() ?? ""
				// `Page/Row=value@seconds`, the way the other timed steps are
				// said, and a value with no `@` in it keeps the default.
				if let at = said.lastIndex(of: "@"),
				   let seconds = Double(said[said.index(after: at)...]) {
					options.chooseSetting = String(said[..<at])
					options.chooseSettingAt = seconds
				} else {
					options.chooseSetting = said
				}
			case "--rename-terminal": options.renameTerminal = next()
			case "--split-terminals": options.splitTerminals = true
			case "--split-panes": options.splitPanes = true
			case "--split-disturb": options.splitThenDisturb = true
			case "--split-active": options.splitActive = true
			case "--tearoff-terminal": options.tearOffTerminal = true
			case "--terminal-drop-preview": options.previewTerminalDrop = true
			case "--split":      options.split = next()
			case "--settings-divider": options.settingsDivider = next().flatMap(Double.init)
			case "--editor-divider": options.editorDivider = next().flatMap(Double.init)
			case "--dropzone":   options.dropZone = next()
			default:
				// A bare path is treated as the project to open.
				if !argument.hasPrefix("-"), options.projectPath == nil {
					options.projectPath = argument
				}
			}
			index += 1
		}
		return options
	}
}
