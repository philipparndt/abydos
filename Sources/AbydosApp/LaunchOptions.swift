import AppKit
import AbydosKit

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
	var editorShotPath: String?
	/// Seconds to wait before capturing, so async parse/git work settles.
	var screenshotDelay: TimeInterval = 1.5
	var expandNavigator = false
	/// Text typed into the editor before capture, for verifying the edit path.
	var typeText: String?
	/// What to make of what `--find` found: `--replace` types a replacement into
	/// the bar, and `--replace-all` presses the second button rather than the
	/// first.
	var replaceWith: String?
	var replaceAll = false
	/// Select the first place this string appears and say which other places lit
	/// up: `--select-text`. `--select-lines` cannot ask this — a whole line
	/// carries its newline, and a selection with a line break in it lights
	/// nothing by rule.
	var selectText: String?
	/// Set breakpoints on these lines of the file in front and open the debug
	/// pane to read the list: `--break-at <line>`, repeatable, and
	/// `--breakpoints`. A driven run cannot use a project's own, since the
	/// session file is not read while one is driving.
	var breakpointLines: [Int] = []
	var showBreakpointList = false
	/// And then start a session, to show it takes the empty pane over rather
	/// than opening a second one.
	var breakpointsThenDebug = false
	/// Turns the bar's `.*` switch on, so `--find` is a pattern and `--replace`
	/// a template. Without it there is no way to drive the half of replace that
	/// capture groups are.
	var findRegex = false
	/// Collapse every fold before capture, for verifying folding.
	var collapseFolds = false
	/// Opened as a provisional tab, as a single click in the tree would.
	var previewPath: String?
	/// Show the markdown preview before capture.
	var markdownPreview = false
	/// Open the Settings window, and capture it instead of the project window.
	var openSettings = false
	/// Open the About panel before capture, so what it says can be photographed.
	var openAbout = false
	/// UI zoom applied before capture.
	var zoom: Double?
	/// Open the terminal panel before capture.
	var openTerminal = false
	/// Commands typed into the terminal before capture: one per `--run`, each
	/// given time to finish before the next is sent.
	///
	/// A list rather than one string, because a plain pane cannot be handed a
	/// whole script at once. `kitty icat` outside tmux asks the terminal what it
	/// can do and reads the tty for the answer — and it reads whatever else is
	/// waiting there along with it, so four commands sent together become one
	/// command and three swallowed lines. 0468 is the case that needs four
	/// `icat` in a row, and it needed them paced.
	var terminalInput: [String] = []
	/// Drags in the terminal grid before capture, as
	/// `fromRow,fromColumn,toRow,toColumn[,option]` — one per `--select`.
	///
	/// What a drag *lands on* is the whole question a selection change raises,
	/// and it is the half a screenshot cannot answer: translucent colour over
	/// ragged text is the thing being changed, so "does the highlight stop at
	/// the text" has to come back as numbers.
	var terminalSelections: [String] = []
	/// Tabs to double-click before capture, by index — one per `--tab-double`.
	/// Two of them is the toggle, which is the half a single one cannot show.
	var tabDoubleClicks: [Int] = []
	/// Open Quick Look on the notice in front, before capture.
	var quickLook = false
	/// Start an agent review before capture.
	var startReview = false
	/// Show the backlog dashboard before capture. `list` for the list, anything
	/// else for the board — the two presentations are the thing worth
	/// photographing separately.
	var backlogMode: String?
	/// Print what one card's context menu offers, and stop.
	///
	/// A menu cannot be photographed without a click, and the pane it belongs
	/// to is in the app target where the suite cannot reach it — so the way to
	/// check what a card offers is to open the real board and ask the real menu.
	/// Start under the debugger, wait for the breakpoint, press Stop, and say
	/// what is left on screen afterwards.
	///
	/// The gesture the report is about, and the one nothing could drive: there
	/// were verbs for stepping and for letting a program finish, and none for
	/// stopping one that has not.
	var debugStop = false
	/// The same run, but let the program finish instead of stopping it — the
	/// path where an exit status exists to be reported.
	var debugFinish = false
	var backlogMenu: Int?
	/// The same, for a change — which is named where an item is numbered.
	///
	/// One flag for both, because `--backlog-menu 0540` and `--backlog-menu
	/// find-bands-follow-soft-wrap` are the same question asked of the two
	/// records, and which record is showing is `--backlog`'s business.
	var backlogMenuChange: String?
	/// Open the task tip on a card and print what it lists.
	///
	/// A number is an item and anything else is a change's name, the way
	/// `--backlog-menu` tells the two apart: an item's name *is* its number, so
	/// there is nothing to collide.
	var backlogTasks: Int?
	var backlogTasksChange: String?
	/// Tick the n-th open task through the tip, and print the fraction after.
	/// `--backlog-tick <name|number>:<n>`, one-based as the report numbers its
	/// rows.
	var backlogTick: (card: String, index: Int)?
	/// Draw the tip to a PNG, because a child window is invisible to a capture
	/// of the main one.
	///
	/// **Deliberately not in `writesACapture`**, which every other
	/// image-writing flag is. That set exists so a verb that prints and exits
	/// does not exit before a capture the window layer takes *later*; this one
	/// is written by the same block that prints, a line above the exit. Listed
	/// there, the run would print, decline to exit, and wait for a screenshot
	/// nobody asked for.
	var backlogTasksShot: String?
	/// File a new item from the pane and print where it landed.
	///
	/// The one thing worth proving mechanically about that button: `ready/` is
	/// a promise only a person may make, and a button that quietly landed
	/// something there would turn the one human gate into a formality.
	var backlogNew: String?
	/// Make a backlog from the pane, for a project that has none.
	var backlogInit = false
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
	/// Exercise ↑ and ↓ at the top and bottom of the file, with and without
	/// Shift, and report where the caret and the selection end up.
	var verticalNavigation = false
	/// Exercise the emacs motions — ⌃B, ⌃F, ⇧⌃B, ⇧⌃F, and ⌃P and ⌃N as the
	/// control — and report where the caret and the selection end up.
	var emacsNavigation = false
	/// Type this at the end of the file and leave the completion list showing.
	var completeText: String?
	/// Press ⌃Space on an empty line and report what came back.
	var completeNow = false
	/// When to press it. The point of the seconds is that the two answers worth
	/// telling apart are both real: press early and the server is still
	/// preparing, press late and it has a list.
	var completeNowAt: Double = 2.0
	/// Ring the terminal bell this many seconds before the Metal capture.
	var bellBefore: Double?
	/// Type, undo, type again, and show the file's history.
	var undoTree = false
	/// Start the debugger, stop at the breakpoint, and step a few times.
	var debugSteps = false
	/// Press ⌘T in the editor and again in the terminal, and report both.
	var terminalTabKey = false
	/// Press ⌘⇧] and ⌘⇧[ with the keyboard in the panel, then in the editor,
	/// and say what the panel's strip showed each time.
	var nextTabInPanel = false
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

	/// Perform the first command the palette offers for this query.
	///
	/// `--palette` says what is *there*; this presses it, through the menu item
	/// and the responder chain, which is how a menu-bar command is proved to
	/// reach the thing that does it.
	var performCommand: String?

	/// Open the palette, type this query a character at a time, and report what
	/// the file list cost.
	///
	/// A character at a time rather than all at once, because the number worth
	/// having is per keystroke: pasting a whole word measures one search where
	/// somebody typing measures eight, and the eighth is the cheap one.
	var paletteFiles: String?

	/// Print what the project offers to run.
	var listRunConfigurations = false

	/// Start the discovered configuration with this name and print its console.
	var runConfigNamed: String?

	/// Report what the Cadova pane in the active tab is doing, once a second,
	/// for this many seconds.
	///
	/// `--run-config` from 0498 watches a *run*; this watches a *pane*, which is
	/// the thing 0499 changes. A model cannot be read off a screenshot and a
	/// build cannot be photographed halfway through, so what is worth printing is
	/// the state, the file the viewer has and how many runs have finished — over
	/// time, because the whole claim is that it goes building → model, and then
	/// building → model again when somebody saves.
	var cadovaWatchSeconds: Double?

	/// Report where the diagram pane in the active tab puts its message and its
	/// turning indicator, once a second, for this many seconds.
	///
	/// 0512's instrument, and it makes the same argument `--cadova-watch` makes
	/// one pane over. What that item is about is where two things are *relative
	/// to each other*, which no screenshot settles to a point and no unit test
	/// can ask — there is no test target for `AbydosApp`. So the two rectangles
	/// are printed in the pane's own coordinates and whether they overlap is
	/// arithmetic anybody can do on the line. Over time rather than once,
	/// because a diagram pane's states are a sequence: a message with nothing
	/// turning, then one with the indicator over it, then a picture.
	var diagramWatchSeconds: Double?

	/// Keys to press in the palette's list, comma separated.
	var switcherKeys: String?
	/// The seven trust flags, which are one subject and are asked as one.
	var trust = Trust()
	/// `--terminal-service <path>`: the Finder's *New Terminal Here*, driven
	/// on a path — the handler is reachable without the Finder, and what it
	/// does with a path is the half that is this app's.
	var terminalServicePath: String?
	/// `--switcher-pill`: open the switcher the way a click on the project
	/// pill opens it, rather than the way ⇧⌘P does — the two placements are
	/// the subject, so a run has to be able to ask for either.
	var switcherFromPill = false

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
	/// Press ⌘/ over `from:to`, or over a bare caret at `line@column`. Given more
	/// than once it is pressed again, which is how the second press can be
	/// watched taking the comment off the same lines.
	var commentBlocks: [String] = []
	/// Say whether ⌘/ is wired up: the menu item, its key, and whether the
	/// responder chain answers to its action.
	var commentKey = false
	/// A server's `insertText`, then what to do to it: `tab`, `backtab`, `esc`
	/// or text to type, `|` between. Says where the caret and the selection
	/// land after each one, which is the whole of what a tab stop is.
	var snippet: String?
	/// Every shortcut in the menu bar, and which press reaches it on the keyboard
	/// layout this machine is set to. The only way to see what the system did to
	/// a key equivalent after it was declared.
	var menuKeys = false
	/// Prints what the editor is holding, saved or not.
	var printText = false
	/// The palette to run in, so a capture does not depend on whoever's
	/// settings the machine happens to have.
	var theme: String?
	/// The terminal's own palette, by scheme id, for a capture of one that is
	/// not the editor's: `--theme` alone makes the terminal follow the editor.
	var terminalScheme: String?
	/// Start the debugger and inspect where it stopped, without stepping.
	var debugInspect = false
	/// Debug this binary with whichever adapter suits it.
	var debugBinary: String?
	/// Press ⌃C in the debugger's console, after this many seconds.
	///
	/// The claim it exists to check is not "stopping works" — the Stop button
	/// already covers that — but that a *keystroke* reaches the console at all,
	/// which is the half `acceptsFirstResponder` was refusing.
	var debugInterruptAt: Double?
	/// Close the bottom panel before looking, which nothing else could do.
	///
	/// The app opens a terminal for a project that has no remembered session, so
	/// "the panel is closed" was not a state any driven run could reach — and it
	/// is one of the four the rail has to be right about.
	var closePanel = false
	/// Report which of the rail's buttons are lit, and why.
	///
	/// A picture of the rail says which are filled; it cannot say whether the
	/// ladybird is lit because a session is running or because the pane is in
	/// front, and those are the two the change that added this had to tell apart.
	var railReport = false
	/// Raise a toast, to see what one looks like.
	var showToast = false
	/// Say that a Claude session is running in the project being opened, to see
	/// what its row looks like.
	///
	/// **The same shape as `--toast`, for the same reason.** A driven run
	/// declines news from outside itself — no hook subscription, no transcript
	/// times — so without this there would be no way to photograph a live
	/// session's row, and a tree captured without one looks exactly like a tree
	/// that cannot draw one. That is the failure 0451 records for the toast
	/// corner, and it was found by leaving a way to look.
	///
	/// `--claude-running <id>[@<seconds>][:<status>]`, and more than once, so a
	/// picture of the panel's pill can hold a session in each state.
	///
	/// **Two moments, because they are two different claims.** At zero the
	/// session was already running when the project opened, which is the read on
	/// the open path. After a delay it starts while somebody is watching, which
	/// is the redraw — and that half cannot be driven any other way, since
	/// `ClaudeWatch` never subscribes on a driven run.
	struct ClaudeRunning: Equatable {
		var id: String
		var after: TimeInterval = 0
		/// `working`, `needs` or `done`, as the hook would say it.
		var status = "working"
		/// Which of the panel's tabs the session is in, by index, so a driven
		/// run can put a session in a tab the way the hook's `terminal` does:
		/// `<id>@5:working:tab2`. Nil for a session in no tab of ours.
		var tab: Int?
		/// How many subagents it has out: `<id>:working:sub2`, sent as the tool
		/// uses that spawn them so the register counts them its own way.
		var subagents = 0
	}
	var claudeRunning: [ClaudeRunning] = []
	/// Seed this many badged tmux windows into the register, as the mirror
	/// does: `--claude-seeded 6`. These are the records that carry no session
	/// id, which is a state no other flag can produce.
	var seededWindows: Int?
	/// Put the pointer on one of the window's chrome controls and say what it
	/// is and what it tells somebody: `--hover-control sessions`, and `tag`,
	/// `follow`, `maximize`, `hide`, `overflow`, `add`, `add-menu` on the
	/// terminal strip; `rail:project` and the rail's other tools;
	/// `header:collapse`, `header:locate`, `header:compact` in the project
	/// pane's header; `run:run`, `run:debug`, `run:debug-menu`, `run:scheme`
	/// in the titlebar. One flag for one gesture, whichever part of the chrome
	/// it is asked of.
	///
	/// A comma takes several in turn, spaced far enough apart to be separate
	/// hovers: one run can then say what all eight tell somebody, and the last
	/// one named is the one a capture at the end finds resting on screen.
	var hoverControls: [String] = []
	/// The six flags about the running-sessions list, which are one subject.
	var running = Running()
	/// Toggle presentation mode while the window is up, as the menu does, so a
	/// page can be read before and after: `--presentation-at 4`.
	var presentationAt: [Double] = []
	/// Zoom the window and say what its frame did: `--zoom-gesture click@4` or
	/// `--zoom-gesture zoom@4`.
	var zoomGesture: String?
	var zoomGestureAt: Double = 4
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
	/// A comma-separated script for the changes tree: `report`, `stage:<path>`,
	/// `unstage:<path>`, `shut:<path>`, `open:<path>`, `refresh`.
	var changesSteps: String?
	/// The same steps at a chosen moment, for reading a pane after a switch.
	var changesLater: (at: Double, steps: String)?
	/// Print what the branch half of the titlebar pill says. See
	/// `branchPillForTesting`.
	///
	/// Not `--branch-pill`, which is taken: that one opens the menu under the
	/// pill and takes a number of seconds. This reads the pill itself.
	var pillState = false
	/// Drive the refs tree and print what it holds. See `branchRowsForTesting`.
	var branchRowSteps: String?
	/// `--hex <steps>`: the front tab as bytes, driven, with a report.
	var hexSteps: String?
	/// `--compare <a> <b>`: a compare page over two paths.
	var comparePaths: (String, String)?
	/// `--compare-steps <steps>`: the page in front, driven. See
	/// `ComparePage.stepsForTesting`.
	var compareSteps: String?
	/// Print what the menu over a commit in the log offers.
	var commitMenuRow: Int?
	/// Drive the log page and print what it holds.
	var logPageSteps: String?
	/// Drive the commit page and print what it holds.
	var commitPageSteps: String?
	/// Drive the pull request list and print what each row says.
	var pullRequestSteps: String?
	/// Drive the estate overview and print what each row says.
	var estateSteps: String?
	/// How many keystrokes to time in the terminal.
	var typingPresses: Int?
	/// Print what opening this project cost, at each of these many seconds in.
	///
	/// Several readings rather than one, for the reason `--banner-at` learned in
	/// 0433: at any single moment a large project is still settling, and one
	/// reading cannot tell "finished" from "not yet". At 0428's scale that is
	/// not a subtlety — a reading at five seconds and one at sixty are different
	/// answers to what a project open costs, and both are true.
	var openReportsAt: [Double] = []
	/// How many keystrokes to time in the editor, with `--report-open`.
	var openReportTyping = 0
	/// Keep asking the language server a real question at `line:character` until
	/// it answers, and say how long it took.
	///
	/// 0428 wanted "time until Java answers" and could not take it: a single
	/// question asked at a fixed delay says only whether the delay was long
	/// enough, and the answer for jdtls on a Tycho reactor is minutes rather
	/// than the twelve seconds `--lsp-wait` defaults to. What is wanted is the
	/// moment the server *starts* answering, which nothing but polling can find.
	/// Open the titlebar branch menu and report what it cost, as
	/// `--branch-pill` or `--branch-pill@seconds`.
	var branchPillAt: Double?
	var answerAt: String?
	/// Give up on `--report-answer` after this long. Everything still silent is
	/// reported as such, which is a finding rather than a missing line.
	var answerDeadline: Double = 300
	/// Which row of the branches view to open the menu on.
	var branchMenuRow: Int?
	/// Push this branch from the branches view.
	var pushBranch: String?
	/// Print where the active terminal thinks it is, for checking that the
	/// window can follow it.
	var reportsTerminalDirectory = false
	/// Print the terminal's geometry, for the clipped-bottom-row bug.
	var reportsTerminalGeometry = false
	/// Print the active pane's screen — the rows a program is drawn in, not the
	/// scrollback above them — at these seconds: `--terminal-screen-at 5,8`. For
	/// the question a picture cannot settle: which row a line landed on, and
	/// whether what was above it went into history or under it.
	var terminalScreenAt: [Double] = []
	/// Where the backlog pane's header is against the strip, at these seconds:
	/// `--backlog-geometry 3,5,7`.
	var backlogGeometryAt: [Double] = []
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
	/// Put the pointer on the ✕ of every tab of every strip in the window, say
	/// what each strip made of it, and photograph it hovered and then left.
	var tabCloseHover: String?
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
	/// Open the list of running language servers and containers, and report what
	/// it says.
	///
	/// With no `--screenshot` the run ends when the reading is done, and
	/// `--delay` then says how long to let things settle first rather than when
	/// to take a picture — a server that indexes has nothing under it for the
	/// first few seconds, and the number this list exists to show is what is
	/// under it.
	var runningTools = false
	/// Press Stop on the first row whose name or subject contains this, and
	/// report the list before, after, and once more when a file has asked for a
	/// server again.
	var stopRunning: String?
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
	/// How much wider to make the window, and when — for the claim that a
	/// width-only resize leaves the panel's height alone.
	var widenBy: (extra: Double, at: Double)?
	/// How tall the bottom panel is, for the same reason: the split position is
	/// remembered per machine, and one somebody dragged to the top of the
	/// window hides everything a screenshot is meant to show.
	var panelHeight: Double?
	/// Open the list of launch configurations.
	/// Open three terminal tabs, go back to the middle, and press ⌘D there.
	var terminalTabBeside = false
	var launchMenu = false
	/// A goal in the run list to open, so a capture run can see the places
	/// behind one rather than only the row that holds them.
	var launchMenuGoal: String?
	/// Open the editor for the selected configuration.
	var launchEditor = false
	/// Open the symbol palette with this query and report what came back.
	var symbolQuery: String?
	/// Search the whole project rather than the open file.
	var symbolProject = false
	/// Find usages of the symbol at line:character (1-based line).
	var usagesAt: String?
	/// Rename the symbol at line:character to a new name, as `line:char=NewName`.
	///
	/// The whole gesture from outside, so that a rename can be *driven* rather
	/// than read about: the field opens over the symbol, the name is typed into
	/// it, Return is pressed, and what the files say afterwards is printed.
	var renameAt: String?
	/// Jump to the definition of the symbol at line:character (1-based line).
	var definitionAt: String?
	/// Work the usages list once it has arrived, as a comma-separated script.
	///
	/// The same vocabulary `--search-steps` has, because it is the same list:
	/// `focus`, `down`, `up`, `space`, `rows`, `select:3`, `click:4`, `undo`,
	/// `settle:<n>` … plus its own `expand`, `dock`, `close`, `again`, `heading`,
	/// `traffic` and `hold-down:<n>`, which is a held ↓ rather than n presses.
	///
	/// `--dock-usages` went with the sidebar dock it asked for: the list now
	/// arrives docked in the bottom panel, and `expand` moves it out to a window.
	var usagesSteps: String?
	/// Wait this long before capturing, for a language server to answer.
	var lspWait: Double?
	/// Print which root the file in front is filed under, beside the scope.
	var lspRoot = false
	/// Print the geometry every board card is drawn with.
	var cardReport = false
	/// Have every card print what it drew, each time it draws.
	var drawReport = false
	/// Print what the pane offers a project that keeps no record of work.
	///
	/// The four states this has — neither record, no `openspec` on the machine,
	/// and either record made since — are a view in the app target, which the
	/// suite cannot reach. A line of text can be diffed; a screenshot has to be
	/// looked at.
	/// `report` says what is offered; `openspec` presses the OpenSpec button;
	/// `missing` answers as a machine with no `openspec` on it.
	var backlogOffer: String?
	/// When to say what a server has published about the file in front, and at
	/// what weight it is drawn. A list of seconds, because the state being
	/// watched changes on its own a minute after the file opens.
	var diagnosticsAt: [Double] = []
	/// When to open the first value beside the code that has anything under it.
	var openValueAt: Double?
	/// Switch to this branch the way the titlebar does, and say what came of it.
	var checkoutBranch: String?
	/// And press whatever the notification offered.
	var pressOffer = false
	/// Copy a link to a place, as `reference:12`, `permalink:12` or
	/// `reference:12-18`, and say what landed on the pasteboard.
	var copyLink: String?
	/// Put this on the pasteboard and follow it, saying where the caret went.
	var followLink: String?
	/// Which line to ask a server what it offers about, and after how long.
	///
	/// The wait is the argument rather than a constant because the servers this
	/// is watched against differ by two orders of magnitude: gopls answers in a
	/// second, and jdtls has a Maven import to do first.
	var codeActionsAt: (line: Int, character: Int, after: Double)?
	/// The action to take, matched on its title — the server's own words.
	var codeActionTake: String?
	/// Send the editor a motion nothing handles, and say what it named.
	var unhandledMotions = false
	/// When to say which panes were drawn by the engine that is not the usual
	/// one — a list, because a pane opened after a setting change is the case
	/// worth seeing beside one opened before it.
	var engineReportsAt: [Double] = []
	/// Turn the engine setting on at this moment and open a pane, so that one
	/// older than the change can be seen beside one younger.
	var engineSwitchAt: Double?
	/// Answer as a machine where libghostty-vt will not start.
	var engineRefuses = false
	/// What each mouse button does, and what each layer saw of it.
	///
	/// `report` on its own says what arrives and claims nothing, which is the
	/// verb for a hand on a real mouse: a driver that maps the side buttons to
	/// keystrokes sends no mouse event at all, and "nothing arrived" is a
	/// different answer from "button 3 arrived and was ignored". Otherwise a
	/// list of presses — `3@editor,4@terminal` — with where the editor landed
	/// after each.
	var mouseSteps: String?
	/// How far an unsteady click wobbles, in points, for `--wobble`.
	var wobblePixels: Int?
	/// Drop these files on the editor the way the Finder would.
	var dropFiles: [String] = []
	/// Drag a tab onto the group's right-hand zone, which must still split.
	var dragTab = false
	/// Find in one tab, switch to the next, and step — the gesture that reached
	/// another file's view with this file's offsets.
	var findAcrossTabs = false
	/// After a switch, write into the project that was left and check the board
	/// does not move.
	var checkOldWatcher = false
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
	/// How large the picture pane draws: `fit` or `actual`.
	var imageFit: String?
	/// Steps to drive the picture pane's own zoom through, comma separated:
	/// `in`, `out`, `actual`, `fit`, `pinch:0.25`.
	///
	/// Separate from `--image-fit` because it goes a different way. `--image-fit`
	/// calls the pane; this sends the View menu's own action into the responder
	/// chain, which is what item 0537 actually changed — the picture pane answers
	/// `Zoom In` while it has the keyboard, and the window answers it everywhere
	/// else. The interface's own zoom is `--zoom`, and a run that passes both is
	/// the run that shows the two are no longer one number.
	var imageZoom: String?
	/// Print what the front tab's video player is doing.
	var videoReport = false
	/// Drive the secret covers: report, reveal, caret, toggle.
	var secretsSteps: String?
	/// `--sops <steps>`: the SOPS chip, driven — see `sopsForTesting`.
	var sopsSteps: String?
	/// `--indent <steps>`: the indent chip and the keys around it, driven —
	/// see `indentChipForTesting`.
	var indentSteps: String?
	/// Drive the editor's context menus: gutter, text, blame.
	var editorMenuSteps: String?
	/// Where the picture pane is scrolled to, as fractions of the picture:
	/// `0,0` is its top left corner and `1,1` its bottom right.
	///
	/// The one thing a still capture cannot show on its own is that a picture
	/// *moves*: the scrollers are overlay ones and are invisible unless
	/// something is scrolling. A capture taken at the far corner of a picture
	/// larger than the pane is the evidence that it is pannable rather than
	/// cropped.
	var imagePan: String?
	/// Ask whether this app can reach the local network: `host:port`.
	///
	/// The permission belongs to the app and everything it launches inherits
	/// the answer, so when a debugged program cannot reach a broker this says
	/// whether the broker is down or the app was never granted.
	var probeLAN: String?
	/// Query for the in-file find bar.
	var findQuery: String?
	/// How many times to press ⌘G, with the keyboard put back in the code first.
	///
	/// `--find` on its own leaves the keyboard in the find field, which is the
	/// state the report behind 0536 was in. This is the other one, and there was
	/// no way to photograph it: everything that opens the find bar focuses it,
	/// and everything that focuses the editor closes the bar and throws the
	/// matches away.
	var findNextSteps: Int?
	/// Select whole lines in the editor and leave them selected: `from:to`.
	///
	/// For photographing a selection that the view drawing it does not have the
	/// keyboard for — the second half of item 510. Nothing else here makes a
	/// selection without taking the keyboard with it, because everything else
	/// that makes one is about to type into it.
	var selectLines: String?
	/// Query for project-wide search.
	var searchQuery: String?
	/// Steps to work the search results with, comma separated: `focus`, `down`,
	/// `shift-down`, `space`, `hide`, `rerun`, `undo`, `redo`, `select:3+4`,
	/// `rows`, `status`, and `settle` between them.
	///
	/// The results are a checklist now, and every claim about one is about what
	/// a row *is* rather than what it looks like: struck through, counted on its
	/// heading, still ticked after the search was run a second time. A rendering
	/// shows a grey line; `rows` says which rows the pane believes are done,
	/// which is the half that can be wrong without looking wrong.
	var searchSteps: String?
	/// Open a folder inside the project as a subproject before capture.
	var subproject: String?
	/// Which settings section to show.
	var settingsSection: String?
	/// Print what a settings row says — its title and its help — found by page
	/// and by part of its title: `--settings-says "Terminal/status bar"`.
	/// A help text is a claim, and this is how one is read back from a build.
	var settingsSays: String?
	/// Put a draft into the window's inbox for a named project at a stated
	/// moment: `--deliver-draft /path/to/project@9`.
	///
	/// **The report's own shape.** A draft asked for in one project answers
	/// while the window is showing another, and the page cannot deliver that to
	/// itself — the page on screen belongs to the other project. This arrives
	/// from outside, for the root it was asked about, exactly as a late
	/// `claude` does.
	var deliverDraft: (root: String, at: Double)?
	/// Which settings section to fold away, as its triangle does.
	var settingsFold: String?
	/// Arrow keys to press in the settings sidebar, comma separated: `left`,
	/// `right`, `up`, `down`. The keyboard path to the same folding.
	var settingsKeys: String?
	/// Type this into the settings page's filter once it is up, and print what
	/// is left: `--settings-filter ghostty`.
	var settingsFilter: String?
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
	/// Choose a value on a settings page while the app is running, said as
	/// `Page/Row=value` or `Page/Row=value@seconds`.
	///
	/// Through the row's own setter rather than by writing to the defaults
	/// behind it, because what 0460 is about is what happens *when a preference
	/// changes*: a value put into `UserDefaults` from outside changes the stored
	/// answer and tells nobody, which is the state the fault was reported from
	/// rather than a way of reproducing it.
	var chooseSetting: String?
	/// When to choose it, in seconds. The default is late enough for a project
	/// to have opened and its servers to have failed, since a preference changed
	/// before anything has been tried reconsiders nothing.
	var chooseSettingAt: Double = 10.0
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
	/// Open this many terminal tabs, so the strip has to deal with more of them
	/// than it has room for.
	///
	/// **The only way to reach the fault from a driver.** A strip that overflows
	/// needs a dozen tabs in it, and one `--tab-add` opens one — so what a full
	/// strip looks like was a thing somebody had to make by hand, twelve clicks
	/// at a time, and therefore a thing screenshots never showed.
	var fillTerminalTabs: Int?
	/// Put this many windows on tmux's own strip and say what it does with
	/// them: `--tmux-tab-fill 16`. The mirroring strip cannot otherwise be
	/// filled without a tmux server the run would not live long enough to see.
	var fillTmuxTabs: Int?
	/// Click one of tmux's own window tabs and say what the window did about
	/// it: `--click-tmux-tab 1@14`. Both meanings of "full screen" are read
	/// either side of the click; see `clickTmuxTabAndReportForTesting`.
	var clickTmuxTab: (index: Int, at: Double)?
	/// Give the terminal the whole window at a stated moment:
	/// `--panel-maximize 6`.
	///
	/// `--maximize-terminal` does it at half a second, which is before the
	/// window controller exists on a cold run — so it silently did nothing, and
	/// a run meaning to ask "does *this* take the terminal out of full screen"
	/// was never in full screen to begin with.
	var panelMaximizeAt: Double?
	/// Restore these pages as a project switch would, and say what the panel
	/// did about it: `--restore-pages log,commit@8`.
	var restorePages: (identifiers: [String], at: Double)?
	/// Close this many terminal tabs and say what the strip does next.
	///
	/// The reported gesture, and it needed a count: `--close-terminals` closes
	/// every one of them, which cannot show a strip that fails to lay out again
	/// because there is nothing left in it.
	var closeTerminalTabs: Int?
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
	/// Print the sentence under each control as well.
	///
	/// Off unless asked for: it is a paragraph a row, which drowns out the check
	/// the dump is usually for. On when the words are the thing being checked —
	/// 0452's line saying what a Java server costs lives only in the help.
	var dumpSettingsHelp = false
	/// Pick a Makefile goal from the run menu, the way clicking it does.
	var chooseMakeRun: String?
	/// Drag a tmux tab from one position to another: "from:to".
	var dragTmuxTab: String?
	/// Set a breakpoint on this line and turn it off, to see how it is drawn.
	var disabledBreakpointLine: Int?
	/// Press stop this many seconds in, to see what the tab does afterwards.
	var stopAfter: Double?
	/// Print what has the keyboard, at each of these many seconds in.
	///
	/// Half of what `abydos <file>` promises is that the keyboard moves into the
	/// file it opened, and that is the half a screenshot cannot show: a caret
	/// that happens to be between blinks looks exactly like a caret in a view
	/// nobody is typing into. Several readings, because the claim is about a
	/// change — the terminal before, the editor after.
	var focusReportsAt: [Double] = []

	/// The seven flags about the two titlebar pills, which are one subject.
	var pills = Pills()

	/// Print what the terminal panel holds, at each of these many seconds in.
	///
	/// The panel is the only witness to a devcontainer being brought up where
	/// somebody can watch it (0444), and it is deliberately not shown at the
	/// moment the tab is made — so a screenshot proves nothing and the tab has to
	/// be asked about rather than looked at. Several readings, because the claim
	/// is that a slow start reveals the panel and a fast one leaves it alone.
	var panelTabsAt: [Double] = []

	/// How many lines of the pane in front to print with them.
	var panelTabsTail = 0

	/// Print what is in the corner, at each of these many seconds in.
	///
	/// A toast cannot be told from an empty corner in a window rendering that has
	/// not finished loading, and the thing worth proving about a question is that
	/// it is *still there* after the eight seconds that would have taken a piece
	/// of news away. Several readings, because that is the whole claim.
	var toastReportsAt: [Double] = []

	/// Press the answer whose words are these, this many seconds in:
	/// `<the words>@<seconds>`.
	var answerToast: String?

	/// Switch the window to another project, the way following the terminal
	/// does: `<path>@<seconds>`, repeatable, so that away and back is one run.
	var switchProjects: [(path: String, at: Double)] = []

	/// Print what the strip above the file says, at each of these many seconds.
	///
	/// `--lsp-banner report` fires once, at a fixed three seconds, and 0433 was
	/// right not to trust it: a container that is coming up, a server that is
	/// indexing and a project that has just been switched back to are all states
	/// that are still settling then, and one reading cannot tell "nothing to say"
	/// from "not yet". Several readings can.
	var serverBannersAt: [Double] = []

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
}
