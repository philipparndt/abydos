import AppKit

/// Command-line options.
///
/// `--screenshot` exists so the UI can be verified during development without
/// Screen Recording permission: the window renders itself into a bitmap
/// in-process, which exercises exactly the same drawing code the display uses.
struct LaunchOptions {
	var projectPath: String?
	var filePath: String? { filePaths.first }
	/// Files to open, in the order given: `--file` may be repeated.
	var filePaths: [String] = []
	var screenshotPath: String?
	/// Seconds to wait before capturing, so async parse/git work settles.
	var screenshotDelay: TimeInterval = 1.5
	var expandNavigator = false
	/// Text typed into the editor before capture, for verifying the edit path.
	var typeText: String?
	/// Collapse every fold before capture, for verifying folding.
	var collapseFolds = false
	/// Opened as a provisional tab, as a single click in the tree would.
	var previewPath: String?
	/// Show the markdown preview before capture.
	var markdownPreview = false
	/// Open the Settings window, and capture it instead of the project window.
	var openSettings = false
	/// UI zoom applied before capture.
	var zoom: Double?
	/// Open the terminal panel before capture.
	var openTerminal = false
	/// Text typed into the terminal before capture.
	var terminalInput: String?
	/// Start an agent review before capture.
	var startReview = false
	/// Start a review of the working tree instead of the branch.
	var reviewUncommitted = false
	/// Show the staging view in the sidebar before capture.
	var showChanges = false
	/// Switch to changes and back, to verify the sidebar tabs.
	var sidebarCycle = false
	/// Zooms in and back out again, to check what a live zoom change disturbs.
	var zoomCycle = false
	/// A second file to open, then drag out into a window of its own and back.
	var tearOffFile: String?
	/// Times terminal redraws, to see what a frame costs.
	var benchRender = false
	/// Renders the terminal through Metal, straight to a PNG.
	var metalShot: String?
	/// Gives the terminal the whole window.
	var maximizeTerminal = false
	/// Follows the terminal's project, for checking that it does.
	var followTerminal = false
	/// Click this panel tab position and report which tab it actually brought
	/// forward, as "index@seconds".
	var clickPanelTab: String?
	/// Print which build this is and exit.
	var reportVersion = false
	/// Open a detail dialog over the window, for verifying that it shows what it
	/// was given. It cannot be reached without a click otherwise.
	var detailDialog = false
	/// Show the window as it looks while presenting, without storing the mode.
	var presentation = false
	/// Close every terminal tab after this many seconds, leaving the panel
	/// belonging to a tmux session with nothing attached to it.
	var closeTerminals: Double?
	/// Toggle a breakpoint on this 1-based line before capture.
	var breakpointLine: Int?
	/// Print where the open file's breakpoints ended up, after each of these
	/// many seconds — which is how anchoring is checked without reading a
	/// gutter. Repeatable, since the interesting thing is what changed between
	/// before a file was rewritten and after.
	var breakpointReports: [Double] = []
	/// Show a sidebar tool before capture: project | changes | branches | structure.
	var sidebarTool: String?
	/// Invoke the gutter run action on this 1-based line before capture.
	var runLine: Int?
	/// Debug the configuration on this 1-based line before capture.
	var debugLine: Int?
	/// Create a folder at the project root before capture.
	var newFolder: String?
	/// Create a file at the project root before capture.
	var newFile: String?
	/// Open a scratch file before capture.
	var newScratch: Bool = false
	/// Show the scratches pane, optionally with something typed into its search.
	var scratchSearch: String?
	/// Open the first scratch listed, as clicking it would.
	var openScratch = false
	/// Show the history, and open the first file of the given commit row.
	var historyCommit: Int?
	/// Underline made-up problems, to see how they are drawn.
	var fakeDiagnostics = false
	/// Exercise ⌥-arrow navigation and report where the caret ends up.
	var wordNavigation = false
	/// Type this at the end of the file and leave the completion list showing.
	var completeText: String?
	/// Ring the terminal bell this many seconds before the Metal capture.
	var bellBefore: Double?
	/// Type, undo, type again, and show the file's history.
	var undoTree = false
	/// Start the debugger, stop at the breakpoint, and step a few times.
	var debugSteps = false
	/// Press ⌘T in the editor and again in the terminal, and report both.
	var terminalTabKey = false
	/// Type a block with returns in it and print what came out.
	var typeBlock = false
	/// Put a condition on the breakpoint before starting, and say where it stopped.
	var breakpointCondition: String?
	/// Opens the breakpoint options sheet on a line, so it can be looked at.
	var editBreakpointLine: Int?
	/// Writes the debug toolbar to a PNG, with a location tag when given one.
	var toolbarImage: String?
	var toolbarLocation: String?
	/// `bare:composed` pairs to press with Option held, for the key path.
	var optionKeys: [String] = []

	/// Key codes to press in the terminal, as `10,14` — with an `s` after a code
	/// for Shift, which is where a German layout keeps its grave accent.
	var deadKeys: String?

	/// Click in the empty space under the last line of a short file.
	var clickBelowLastLine = false

	/// Print what a right-click on the tab strip offers.
	var tabMenu = false

	/// Print the palette's commands for this query.
	var paletteQuery: String?

	/// Print what the project offers to run.
	var listRunConfigurations = false

	/// Keys to press in the palette's list, comma separated.
	var switcherKeys: String?

	/// Apply these theme settings in turn and say what each resolved to.
	var appearanceWalk: String?

	/// Move down the tree this many steps, then copy with ⌘C.
	var copyPath: String?

	/// Feed the terminal this many frames at once, and report the redraws.
	var burstFrames: Int?

	/// Click into the commit details field and type this.
	var commitBody: String?
	/// `from:to:in|out` — indent or outdent a block, for checking Tab.
	var indentBlock: String?
	/// Prints what the editor is holding, saved or not.
	var printText = false
	/// The palette to run in, so a capture does not depend on whoever's
	/// settings the machine happens to have.
	var theme: String?
	/// Start the debugger and inspect where it stopped, without stepping.
	var debugInspect = false
	/// Debug this binary with whichever adapter suits it.
	var debugBinary: String?
	/// Raise a toast, to see what one looks like.
	var showToast = false
	/// Press play, as if from the titlebar.
	var launchRun = false
	/// Press the debug button beside it.
	var launchDebug = false
	/// Show the debugger's console rather than its variables.
	var debugConsole = false
	/// Press push in the commit view.
	var pushChanges = false
	/// Walk the navigation history: "back", "forward", or both.
	var navigateSteps: String?
	/// A comma-separated script for the project tree: `down`, `up`, `right`,
	/// `left`, `collapse`, `locate`.
	var treeSteps: String?
	/// How many keystrokes to time in the terminal.
	var typingPresses: Int?
	/// Which row of the branches view to open the menu on.
	var branchMenuRow: Int?
	/// Push this branch from the branches view.
	var pushBranch: String?
	/// Print where the active terminal thinks it is, for checking that the
	/// window can follow it.
	var reportsTerminalDirectory = false
	/// Print the terminal's geometry, for the clipped-bottom-row bug.
	var reportsTerminalGeometry = false
	/// Turn blame on for the file that was opened.
	var showsBlame = false
	/// Resize the window part-way through, for layout that only settles once.
	var resizeWidth: Double?
	/// Switch the appearance part-way through, to see it change live.
	var switchAppearance: String?
	/// Force the sidebar open to a width, for photographing a pane.
	var sidebarWidth: Double?
	/// Draw the sidebar's pane straight into a file.
	var sidebarShot: String?
	/// Fold a merge in the history, to check the graph.
	var collapseRow: Int?
	/// Open tmux's own menu and move the pointer through it.
	var tmuxMenuHovers: Int?
	/// Hover the editor at line:character with ⌘ held.
	var commandHoverAt: String?
	/// Open the attach-to-process picker, filtered by this text.
	var attachFilter: String?
	/// Light the titlebar pills, to see their highlight against the toolbar.
	var highlightPills = false
	/// Open the profiler on this address and collect from it.
	var profilerAddress: String?
	/// Which profile to collect; defaults to the heap, which is instant.
	var profilerKind: String?
	/// Open the pod picker, filtered by this text.
	var podFilter: String?
	/// Profile the first pod the filter finds.
	var podChoose = false
	/// Derive a launch configuration from this make goal, then run or debug it.
	var makeGoal: String?
	/// Debug rather than run the derived configuration.
	var makeDebug = false
	/// Save the gutter's run at this line as a launch configuration.
	var saveGutterLine: Int?
	/// Narrow the window, to see what the titlebar does with no room.
	var windowWidth: Double?
	/// The whole window, for a capture that has to look the same on two
	/// machines. A screenshot for the documentation is worthless if its size is
	/// whatever the last person left the window at.
	var windowSize: CGSize?
	/// How tall the bottom panel is, for the same reason: the split position is
	/// remembered per machine, and one somebody dragged to the top of the
	/// window hides everything a screenshot is meant to show.
	var panelHeight: Double?
	/// Open the list of launch configurations.
	var launchMenu = false
	/// Open the editor for the selected configuration.
	var launchEditor = false
	/// Open the symbol palette with this query and report what came back.
	var symbolQuery: String?
	/// Search the whole project rather than the open file.
	var symbolProject = false
	/// Find usages of the symbol at line:character (1-based line).
	var usagesAt: String?
	/// Jump to the definition of the symbol at line:character (1-based line).
	var definitionAt: String?
	/// Dock the usages list into the sidebar after finding them.
	var dockUsages = false
	/// Wait this long before capturing, for a language server to answer.
	var lspWait: Double?
	/// Rewrite the open file externally after this many seconds.
	var externalEdit: Double?
	/// Raw bytes to send to the terminal, for verifying key encodings.
	var terminalBytes: String?
	/// Preview mode to select before capture: source | preview | split.
	var previewMode: String?
	/// Export the diagram in front from its preview pane: `png` or `svg`.
	var exportDiagram: String?
	/// How large the diagram pane draws: `width` or `actual`.
	var diagramFit: String?
	/// Ask whether this app can reach the local network: `host:port`.
	///
	/// The permission belongs to the app and everything it launches inherits
	/// the answer, so when a debugged program cannot reach a broker this says
	/// whether the broker is down or the app was never granted.
	var probeLAN: String?
	/// Query for the in-file find bar.
	var findQuery: String?
	/// Query for project-wide search.
	var searchQuery: String?
	/// Open a folder inside the project as a subproject before capture.
	var subproject: String?
	/// Which settings section to show.
	var settingsSection: String?
	/// Which settings section to fold away, as its triangle does.
	var settingsFold: String?
	/// Arrow keys to press in the settings sidebar, comma separated: `left`,
	/// `right`, `up`, `down`. The keyboard path to the same folding.
	var settingsKeys: String?
	/// Print where the development pod's chart was found.
	var reportChart = false
	/// Press the window's zoom button before capture.
	var zoomWindow = false
	/// A tab close command to run: "others:1", "left:2", "right:0", "all:0".
	var closeTabs: String?
	/// Which launch configuration to select first.
	var launchConfiguration: String?
	/// Profile the selected configuration before capture.
	var launchProfile = false
	/// Turn soft wrap on before capture.
	var wordWrap = false
	/// Open the project switcher, optionally with a filter applied.
	var switcherFilter: String?
	/// Switch this window to another project before capture, the way the
	/// switcher does. `path` or `path@seconds`, the way the other timed steps
	/// are said.
	///
	/// The seconds matter to anything counting what a switch costs: a switch a
	/// second in happens while the first project's servers are still starting,
	/// and what is counted afterwards is then a race rather than a rule.
	var switchTo: String?
	/// When to switch, in seconds. Read off `--switch-to path@seconds`.
	var switchToAt: Double = 1.0
	/// Rename the terminal tab before capture, as a double-click does.
	var renameTerminal: String?
	/// Put two terminals side by side before capture.
	var splitTerminals = false
	/// Pull a terminal out into a window before capture.
	var tearOffTerminal = false
	/// Put two different panes side by side before capture.
	var splitPanes = false
	/// Put the pane in front beside itself, as the menu does.
	var splitActive = false
	/// Split, then do what used to collapse a split.
	var splitThenDisturb = false
	/// Show the terminal drop preview before capture.
	var previewTerminalDrop = false
	/// Split the editor before capture: "right" or "down".
	var split: String?
	/// Put settings in a group beside the editor and drag the divider between
	/// them to this position, reporting the widths at every stage.
	var settingsDivider: Double?
	/// The same with a file in both panes, as the control it needs.
	var editorDivider: Double?
	/// Draw a tab drop preview before capture, without a real drag.
	var dropZone: String?
	/// Block the main thread for this many milliseconds, to see the stall
	/// watch catch it.
	var stallMilliseconds: Int?
	/// Press the terminal strip's + before capture.
	/// Press + on the terminal strip, this many seconds in. `--tab-add` on its
	/// own means three; a number after it says when, for the sequences where
	/// something has to happen first.
	var addTerminalTabAt: Double?
	/// Which button on the missing-server bar to press, if any: `report`,
	/// `details`, `ignore` or `dismiss`.
	var serverBanner: String?
	/// Press Run twice, to see whether the second one reuses the first's
	/// console. The value is a make goal to select first, or `selected`.
	var rerun: String?
	/// Close this tmux tab from its menu before capture.
	var closeTmuxTab: Int?
	/// Press the + on tmux's strip before capture.
	var addTmuxWindow = false
	/// Turn "tabs are tmux's windows" off part-way through, to see the strip
	/// and the status bar follow.
	var toggleStrictTmuxOff = false
	/// Print a settings section's rows and whether each can be used.
	var dumpSettings: String?
	/// Pick a Makefile goal from the run menu, the way clicking it does.
	var chooseMakeRun: String?
	/// Drag a tmux tab from one position to another: "from:to".
	var dragTmuxTab: String?
	/// Set a breakpoint on this line and turn it off, to see how it is drawn.
	var disabledBreakpointLine: Int?
	/// Press stop this many seconds in, to see what the tab does afterwards.
	var stopAfter: Double?
	/// Open a terminal in the project's devcontainer and report what is in it.
	var devContainerTerminal = false

	/// Which of them, when the project offers several: a number counting from
	/// one in the order the menu offers them, or "all" for one terminal in each,
	/// each after the last has answered. Nil is the one the View menu opens.
	var devContainerWhich: String?

	/// Print what the titlebar's devcontainer pill says, this many seconds in.
	///
	/// A pill in the titlebar cannot be read from a window rendering, which
	/// leaves out sheets and menus and is what the rest of these dumps exist
	/// for; and the thing worth checking is that it is *absent* for a project
	/// whose container was declined, which a screenshot can never prove — an
	/// empty toolbar looks the same as one that has not finished loading.
	var devContainerPillAt: Double?

	/// Print what the chevron beside the panel's + offers, and which of the two
	/// hit areas beside the last tab a click at each lands in.
	var terminalAddMenu = false

	/// Close the window opened last, this many seconds in.
	///
	/// For counting what a closed window takes with it, which is now nothing:
	/// a language server outlives the window that started it and ends with the
	/// app. That is a thing only `ps` can say, and only if something closes a
	/// window without a hand on the mouse.
	var closeLastWindowAt: Double?

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
			case "--delay":      options.screenshotDelay = next().flatMap(Double.init) ?? 1.5
			case "--expand":     options.expandNavigator = true
			case "--type":       options.typeText = next()
			case "--collapse":   options.collapseFolds = true
			case "--preview":    options.previewPath = next()
			case "--markdown":   options.markdownPreview = true
			case "--subproject": options.subproject = next()
			case "--settings-section": options.settingsSection = next()
			case "--settings-fold": options.settingsFold = next()
			case "--settings-keys": options.settingsKeys = next()
			case "--settings":   options.openSettings = true
			case "--zoom":       options.zoom = next().flatMap(Double.init)
			case "--terminal":   options.openTerminal = true
			case "--run":        options.terminalInput = next()
			case "--review":     options.startReview = true
			case "--review-uncommitted": options.reviewUncommitted = true
			case "--changes":    options.showChanges = true
			case "--push":       options.pushChanges = true
			case "--navigate":   options.navigateSteps = next()
			case "--tree":       options.treeSteps = next()
			case "--type-latency": options.typingPresses = next().flatMap(Int.init)
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
			case "--make-run":   options.chooseMakeRun = next()
			case "--tmux-drag":  options.dragTmuxTab = next()
			case "--branch-menu": options.branchMenuRow = next().flatMap(Int.init)
			case "--push-branch": options.pushBranch = next()
			case "--report-cwd": options.reportsTerminalDirectory = true
			case "--devcontainer":
				options.devContainerTerminal = true
				// Which one is optional, so peek rather than consume: without it
				// the next argument is the next flag.
				if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
					options.devContainerWhich = arguments[index + 1]
					index += 1
				}
			case "--devcontainer-pill":
				options.devContainerPillAt = next().flatMap(Double.init) ?? 8
			case "--tab-add-menu": options.terminalAddMenu = true
			case "--close-window": options.closeLastWindowAt = next().flatMap(Double.init) ?? 5
			case "--report-geometry": options.reportsTerminalGeometry = true
			case "--blame": options.showsBlame = true
			case "--resize": options.resizeWidth = next().flatMap(Double.init)
			case "--switch-appearance": options.switchAppearance = next()
			case "--sidebar-width": options.sidebarWidth = next().flatMap(Double.init)
			case "--sidebar-shot": options.sidebarShot = next()
			case "--collapse-row": options.collapseRow = next().flatMap(Int.init)
			case "--tmux-menu": options.tmuxMenuHovers = next().flatMap(Int.init) ?? 0
			case "--cmd-hover":  options.commandHoverAt = next()
			case "--attach-picker": options.attachFilter = next()
			case "--pills":      options.highlightPills = true
			case "--profile":    options.profilerAddress = next()
			case "--profile-kind": options.profilerKind = next()
			case "--pods":       options.podFilter = next()
			case "--pod-profile": options.podChoose = true
			case "--make-goal":  options.makeGoal = next()
			case "--make-debug": options.makeDebug = true
			case "--save-config": options.saveGutterLine = next().flatMap(Int.init)
			case "--window-width": options.windowWidth = next().flatMap(Double.init)
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
			case "--complete":   options.completeText = next()
			case "--bell":       options.bellBefore = next().flatMap(Double.init) ?? 0.15
			case "--undo-tree":  options.undoTree = true
			case "--debug-steps": options.debugSteps = true
			case "--terminal-tab-key": options.terminalTabKey = true
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
			case "--run-configs": options.listRunConfigurations = true
			case "--appearance-walk": options.appearanceWalk = next()
			case "--copy-path": options.copyPath = next() ?? "down"
			case "--burst": options.burstFrames = next().flatMap(Int.init)
			case "--commit-body": options.commitBody = next()
			case "--indent-block": options.indentBlock = next()
			case "--print-text": options.printText = true
			case "--theme": options.theme = next()
			case "--debug-inspect": options.debugInspect = true
			case "--debug-binary": options.debugBinary = next()
			case "--toast":      options.showToast = true
			case "--launch-run":    options.launchRun = true
			case "--launch-debug":  options.launchDebug = true
			case "--launch-profile": options.launchProfile = true
			case "--launch-config": options.launchConfiguration = next()
			case "--close-tabs": options.closeTabs = next()
			case "--zoom-window": options.zoomWindow = true
			case "--chart-path": options.reportChart = true
			case "--debug-console": options.debugConsole = true
			case "--launch-menu":   options.launchMenu = true
			case "--launch-editor": options.launchEditor = true
			case "--symbols":    options.symbolQuery = next() ?? ""
			case "--symbols-project": options.symbolProject = true
			case "--usages":     options.usagesAt = next()
			case "--definition": options.definitionAt = next()
			case "--dock-usages": options.dockUsages = true
			case "--lsp-wait":   options.lspWait = next().flatMap(Double.init)
			case "--external-edit": options.externalEdit = next().flatMap(Double.init)
			case "--send-bytes": options.terminalBytes = next()
			case "--preview-mode": options.previewMode = next()
			case "--export":     options.exportDiagram = next()
			case "--diagram-fit": options.diagramFit = next()
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
			case "--search":     options.searchQuery = next()
			case "--wrap":       options.wordWrap = true
			case "--switcher":   options.switcherFilter = next()
			case "--switcher-keys": options.switcherKeys = next()
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

	var isScreenshotRun: Bool { screenshotPath != nil }
}

/// A view holding something AppKit's own capture cannot see.
///
/// `cacheDisplay(in:to:)` walks the view tree and draws what is in it. A
/// `CAMetalLayer`'s contents are not, so a pane rendering through Metal comes
/// out empty — and nothing anywhere says why. A view that knows it has such
/// content answers with a picture of it instead.
protocol SnapshotDrawable: NSView {
	func snapshotImage(size: CGSize) -> CGImage?
}

enum WindowCapture {
	/// Renders a window to a PNG.
	///
	/// Draws the theme frame when reachable so the capture includes the titlebar
	/// and its pills; otherwise falls back to the content view.
	@discardableResult
	static func write(window: NSWindow, to path: String) -> Bool {
		// A child window is a window of its own, so it is nowhere in the frame
		// drawn below it. Each is written beside the capture instead.
		for (index, child) in window.childWindows?.enumerated() ?? [NSWindow]().enumerated() {
			let beside = (path as NSString).deletingPathExtension + "-child\(index).png"
			write(window: child, to: beside)
		}

		// A sheet is a window of its own, so it is nowhere in the frame that
		// gets drawn below it. It is written beside the capture instead.
		if let sheet = window.attachedSheet {
			let beside = (path as NSString).deletingPathExtension + "-sheet.png"
			write(window: sheet, to: beside)
		}

		guard let contentView = window.contentView else { return false }
		let target = contentView.superview ?? contentView

		target.layoutSubtreeIfNeeded()
		guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { return false }
		target.cacheDisplay(in: target.bounds, to: rep)
		drawSnapshots(under: target, into: rep, of: target)

		guard let data = rep.representation(using: .png, properties: [:]) else { return false }
		do {
			try data.write(to: URL(fileURLWithPath: path))
			return true
		} catch {
			FileHandle.standardError.write(Data("screenshot write failed: \(error)\n".utf8))
			return false
		}
	}

	/// Paints in what the view tree could not draw.
	///
	/// After the ordinary capture, because these go *over* the empty rectangles
	/// it left behind: every view that says it holds Metal content is asked for
	/// a picture, and it is drawn where that view is.
	private static func drawSnapshots(under view: NSView, into rep: NSBitmapImageRep, of target: NSView) {
		var pending: [SnapshotDrawable] = []
		func collect(_ view: NSView) {
			if let drawable = view as? SnapshotDrawable { pending.append(drawable) }
			for subview in view.subviews { collect(subview) }
		}
		collect(view)
		guard !pending.isEmpty, let context = NSGraphicsContext(bitmapImageRep: rep) else { return }

		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current = context
		for drawable in pending {
			let rect = drawable.convert(drawable.bounds, to: target)
			guard rect.width > 1, rect.height > 1,
			      let image = drawable.snapshotImage(size: rect.size)
			else { continue }
			NSImage(cgImage: image, size: rect.size).draw(in: rect)
		}
		NSGraphicsContext.restoreGraphicsState()
	}
}
