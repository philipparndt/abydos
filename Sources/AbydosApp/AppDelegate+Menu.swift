import AppKit
import AbydosKit

/// The menu bar: every menu, every item, and the key each answers to.
@MainActor
extension AppDelegate {
	func buildMenu() {
		let mainMenu = NSMenu()

		let appMenuItem = NSMenuItem()
		let appMenu = NSMenu()
		// Ours rather than the standard panel, which shows the version but not
		// which build it came from — the one thing worth knowing when the
		// question is whether an install took.
		appMenu.addItem(
			withTitle: "About \(Self.applicationName)",
			action: #selector(showAbout(_:)),
			keyEquivalent: ""
		)
		appMenu.addItem(.separator())
		let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
		settingsItem.target = self
		appMenu.addItem(settingsItem)
		appMenu.addItem(.separator())
		appMenu.addItem(withTitle: "Hide \(Self.applicationName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
		appMenu.addItem(withTitle: "Quit \(Self.applicationName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
		appMenuItem.submenu = appMenu
		mainMenu.addItem(appMenuItem)

		let fileMenuItem = NSMenuItem()
		let fileMenu = NSMenu(title: "File")
		// A second window on the same project: two files side by side, or a
		// terminal in one and the code in the other.
		let newWindow = NSMenuItem(
			title: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n"
		)
		newWindow.target = self
		fileMenu.addItem(newWindow)

		// **The two the tree could only be right-clicked for.** Both put the
		// naming field on a row in the project tree, which is what New ▸ File
		// does there — this is the same gesture from where hands look for it
		// first. No key equivalent: ⌘N is the window and ⇧⌘N the scratch file,
		// and inventing a third is worse than a menu item that is found by
		// reading. The palette gets both for nothing, being built from this menu.
		let newFile = NSMenuItem(
			title: "New File",
			action: #selector(MainWindowController.newProjectFile(_:)),
			keyEquivalent: ""
		)
		fileMenu.addItem(newFile)
		let newFolder = NSMenuItem(
			title: "New Folder",
			action: #selector(MainWindowController.newProjectFolder(_:)),
			keyEquivalent: ""
		)
		fileMenu.addItem(newFolder)

		let openItem = NSMenuItem(title: "Open…", action: #selector(openProjectPanel(_:)), keyEquivalent: "o")
		openItem.target = self
		fileMenu.addItem(openItem)

		// The shortcut the capsule advertises. In the menu rather than on the
		// view, so it works wherever the keyboard focus happens to be and can be
		// found by somebody who never reads a titlebar.
		//
		// ⇧⌘P, where a decade of VS Code has taught everybody's hands to reach
		// for a palette. Presentation Mode had it and moved to ⌃⌘P: that is
		// wanted a few times a year and this a few times an hour.
		//
		// Not plain ⌘K, which clears the terminal as it does in Terminal and
		// every console — a menu's key equivalent is matched before any view
		// sees the key, so taking it would have quietly stopped that working.
		// **Where the trust gesture lives when the strip is away.** The strip
		// can be dismissed without trusting anything, and a window with no
		// strip needs somewhere the project can still be trusted from — this,
		// and the settings page that lists what is trusted already.
		//
		// A submenu rather than an item, carrying the same scopes the strip's
		// dropdown carries: this project, the folder it sits in, where a clone
		// says it came from — and, once it is trusted, taking that back. Built
		// on opening, from whichever window is in front, since every one of
		// those depends on the project being looked at.
		let trustItem = NSMenuItem(title: "Project Trust", action: nil, keyEquivalent: "")
		let trustSubmenu = NSMenu(title: "Project Trust")
		trustSubmenu.delegate = trustMenuDelegate
		trustItem.submenu = trustSubmenu
		fileMenu.addItem(trustItem)

		let switcherItem = NSMenuItem(
			title: "Go to Anything…",
			action: #selector(MainWindowController.showProjectSwitcher(_:)),
			keyEquivalent: "p"
		)
		switcherItem.keyEquivalentModifierMask = [.command, .shift]
		fileMenu.addItem(switcherItem)
		let scratchItem = NSMenuItem(
			title: "New Scratch File",
			action: #selector(MainWindowController.newScratchFile(_:)),
			keyEquivalent: "n"
		)
		scratchItem.keyEquivalentModifierMask = [.command, .shift]
		fileMenu.addItem(scratchItem)
		fileMenu.addItem(.separator())
		fileMenu.addItem(withTitle: "Save", action: #selector(MainWindowController.saveDocument(_:)), keyEquivalent: "s")
		fileMenu.addItem(.separator())
		// Any file as bytes, and back: the binary notice's button is the door
		// for a binary, these are the doors for everything else.
		fileMenu.addItem(withTitle: "Open as Hex", action: #selector(MainWindowController.openAsHex(_:)), keyEquivalent: "")
		fileMenu.addItem(withTitle: "Open as Text", action: #selector(MainWindowController.openAsText(_:)), keyEquivalent: "")
		fileMenu.addItem(.separator())
		fileMenu.addItem(withTitle: "Close Tab", action: #selector(MainWindowController.closeTab(_:)), keyEquivalent: "w")
		let closeWindow = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
		closeWindow.keyEquivalentModifierMask = [.command, .shift]
		fileMenu.addItem(closeWindow)
		fileMenuItem.submenu = fileMenu
		mainMenu.addItem(fileMenuItem)

		let editMenuItem = NSMenuItem()
		let editMenu = NSMenu(title: "Edit")
		editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
		let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
		redo.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(redo)
		let localHistory = NSMenuItem(
			title: "File History…",
			action: #selector(MainWindowController.showFileHistory(_:)),
			keyEquivalent: "z"
		)
		localHistory.keyEquivalentModifierMask = [.command, .option]
		editMenu.addItem(localHistory)
		editMenu.addItem(.separator())
		editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
		editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
		editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
		editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
		editMenu.addItem(.separator())

		// ⌘/, which is Xcode's, VS Code's and IDEA's alike — the one shortcut in
		// this menu nobody has to be told. `"/"` was unbound anywhere in the app,
		// so nothing had to give it up.
		let toggleComment = NSMenuItem(
			title: "Toggle Comment",
			action: #selector(MainWindowController.toggleLineComment(_:)),
			keyEquivalent: "/"
		)
		toggleComment.keyEquivalentModifierMask = [.command]
		// **The one item in this menu bar that keeps its literal key**, and 0479 is
		// the account of why. Left to itself, the system moves a key equivalent it
		// judges awkward on the current layout to one that needs no shift: `/` on a
		// German keyboard is ⇧7, so the menu read **⌘ß**, and the person who had
		// asked for ⌘/ pressed ⌘⇧7 and got nothing. Both halves of that were
		// measured — ⌘ß was the only press that reached it, and ⌘⇧7 reached nothing
		// — with `--comment-key`.
		//
		// Turning the relocation off works *here* because AppKit forgives a modifier
		// the mask does not ask for when that modifier is what types the character,
		// so ⌘⇧7 reaches this item with `/` intact. Measured, not reasoned about,
		// and it is the whole reason this is the fix rather than declaring the
		// shortcut twice.
		//
		// **It is off for this item and nothing else**, and that is a judgement the
		// same measurement supports. The other punctuation shortcuts here — `[`, `]`
		// for Back and Forward, `\` for the splits, `=` for Zoom In — all need ⌥ on
		// this keyboard, so keeping *their* literals costs a whole extra modifier
		// where the relocation gives them one key in the same place it is on a US
		// keyboard: ⌘Ö rather than ⌥⌘5. Worse, `\` is ⌥⇧7, so with the literal kept
		// the forgiven shift makes `⌘\` and `⇧⌘\` **the same press** — Split Right
		// answers and Split Down becomes unpressable. `/` has neither problem: one
		// extra shift, no collision with anything.
		//
		// So the cost of this line is that a German user presses ⌘⇧7 rather than
		// ⌘ß, for the shortcut every editor documents, spelled in the menu the way
		// somebody told "⌘/" would look for it. ⌘ß was a key nobody would ever try,
		// so what that cost was the whole feature. `--menu-keys` prints which press
		// reaches every shortcut in the menu bar, which is how all of this stopped
		// being a guess.
		toggleComment.allowsAutomaticKeyEquivalentLocalization = false
		editMenu.addItem(toggleComment)
		editMenu.addItem(.separator())
		let symbolInFile = NSMenuItem(
			title: "Go to Declaration\u{2026}",
			action: #selector(MainWindowController.goToSymbolInFile(_:)),
			keyEquivalent: "o"
		)
		symbolInFile.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(symbolInFile)

		let symbolInProject = NSMenuItem(
			title: "Go to Symbol\u{2026}",
			action: #selector(MainWindowController.goToSymbolInProject(_:)),
			keyEquivalent: "o"
		)
		symbolInProject.keyEquivalentModifierMask = [.command, .option]
		editMenu.addItem(symbolInProject)

		// ⇧F6, which is IDEA's, for the same reason the two below are.
		let rename = NSMenuItem(
			title: "Rename…",
			action: #selector(MainWindowController.renameSymbol(_:)),
			keyEquivalent: String(UnicodeScalar(UInt32(NSF6FunctionKey))!)
		)
		rename.keyEquivalentModifierMask = [.shift]
		editMenu.addItem(rename)

		// **⌃Space, which is IDEA's and Eclipse's, and the key everybody
		// presses.** A list appears while typing too, but only for a word of two
		// letters or a character the server asked to be woken by — deliberately,
		// since a list on every keystroke is in the way. That leaves the case
		// somebody most wants help with unanswerable: a caret in the middle of
		// nothing, where the question is "what can go here at all".
		//
		// A menu item rather than a key caught in the text view, for the reason
		// the item below gives — and one more. macOS may have ⌃Space bound to
		// "select the previous input source"; a system shortcut wins over both,
		// but as a menu item at least the key is written down where somebody
		// looking for it can see it and go and free it up.
		let complete = NSMenuItem(
			title: "Complete",
			action: #selector(MainWindowController.completeAtCaret(_:)),
			keyEquivalent: " "
		)
		complete.keyEquivalentModifierMask = [.control]
		editMenu.addItem(complete)

		// **⌥⏎, which is IDEA's, and the only always-on way in.** Measured in
		// 0538 against gopls and jdtls: a server answers *something* for every
		// line of a real file — organise imports, generate accessors, and in
		// gopls's case a kind of its own invention — so an indicator driven by
		// "are there actions here" would be on every row. A keystroke asks only
		// when somebody asks.
		//
		// A menu item rather than a key handled in the text view, because a menu
		// item's key equivalent is matched before the view sees the event: ⌥⏎ in
		// a text view is a newline, and catching it afterwards would be catching
		// it after something else had already done it.
		let actions = NSMenuItem(
			title: "Show Context Actions",
			action: #selector(MainWindowController.showCodeActions(_:)),
			keyEquivalent: "\r"
		)
		actions.keyEquivalentModifierMask = [.option]
		editMenu.addItem(actions)

		// **⌘⇧C for the reference, and nothing for the permalink.** The
		// question the design left open was whether a keystroke is worth
		// spending on a gesture done twice a week; the answer is that the
		// reference is not that gesture. It is the string handed to an
		// assistant, and handing one over is something somebody does several
		// times in a sitting — this session alone produced dozens of
		// `file:line` references by hand. The permalink is the twice-a-week one:
		// it goes into a message or a bookmark, deliberately, and reaching the
		// menu for it costs nothing anybody will notice.
		//
		// ⌘⇧C is free here and is what IDEA puts "copy reference" on, which is
		// where the muscle memory comes from.
		let copyReference = NSMenuItem(
			title: "Copy Reference",
			action: #selector(MainWindowController.copyReference(_:)),
			keyEquivalent: "c"
		)
		copyReference.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(copyReference)

		let copyPermalink = NSMenuItem(
			title: "Copy Permalink",
			action: #selector(MainWindowController.copyPermalink(_:)),
			keyEquivalent: ""
		)
		editMenu.addItem(copyPermalink)

		// The other end of the same road, and the only door there is: nothing
		// registers an `abydos://` scheme, so a link is followed by pasting it.
		let goToCopied = NSMenuItem(
			title: "Go to Copied Place",
			action: #selector(MainWindowController.goToCopiedPlace(_:)),
			keyEquivalent: "v"
		)
		goToCopied.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(goToCopied)

		// The file's own, which have no caret: `source.*` is about the whole
		// file — organise imports, fix everything of one kind — and a menu that
		// opens where somebody is typing is the wrong place for it.
		let sourceActions = NSMenuItem(
			title: "Source Actions…",
			action: #selector(MainWindowController.showSourceActions(_:)),
			keyEquivalent: ""
		)
		editMenu.addItem(sourceActions)

		// IDEA's shortcuts on macOS, since that is where the muscle memory
		// comes from.
		let back = NSMenuItem(
			title: "Back",
			action: #selector(MainWindowController.navigateBack(_:)),
			keyEquivalent: "["
		)
		back.keyEquivalentModifierMask = [.command]
		editMenu.addItem(back)

		let forward = NSMenuItem(
			title: "Forward",
			action: #selector(MainWindowController.navigateForward(_:)),
			keyEquivalent: "]"
		)
		forward.keyEquivalentModifierMask = [.command]
		editMenu.addItem(forward)
		editMenu.addItem(.separator())
		editMenu.addItem(withTitle: "Find…", action: #selector(MainWindowController.findInFile(_:)), keyEquivalent: "f")
		editMenu.addItem(withTitle: "Go to Offset…", action: #selector(MainWindowController.goToOffset(_:)), keyEquivalent: "l")
		let findInProject = NSMenuItem(
			title: "Find in Project…",
			action: #selector(MainWindowController.findInProject(_:)),
			keyEquivalent: "f"
		)
		findInProject.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(findInProject)
		editMenu.addItem(
			withTitle: "Replace\u{2026}",
			action: #selector(MainWindowController.replaceInFile(_:)),
			keyEquivalent: "r"
		)
		editMenu.addItem(withTitle: "Find Next", action: #selector(MainWindowController.findNext(_:)), keyEquivalent: "g")
		let findPrevious = NSMenuItem(
			title: "Find Previous",
			action: #selector(MainWindowController.findPrevious(_:)),
			keyEquivalent: "g"
		)
		findPrevious.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(findPrevious)
		editMenuItem.submenu = editMenu
		mainMenu.addItem(editMenuItem)

		let runMenuItem = NSMenuItem()
		let runMenu = NSMenu(title: "Run")
		let goRun = NSMenuItem(title: "Go Run", action: #selector(MainWindowController.goRun(_:)), keyEquivalent: "r")
		goRun.keyEquivalentModifierMask = [.command, .control]
		runMenu.addItem(goRun)
		runMenu.addItem(withTitle: "Go Build", action: #selector(MainWindowController.goBuild(_:)), keyEquivalent: "")
		let goTest = NSMenuItem(title: "Go Test", action: #selector(MainWindowController.goTest(_:)), keyEquivalent: "t")
		goTest.keyEquivalentModifierMask = [.command, .control]
		runMenu.addItem(goTest)
		runMenu.addItem(.separator())
		let goDebug = NSMenuItem(title: "Go Debug (Delve)", action: #selector(MainWindowController.goDebug(_:)), keyEquivalent: "d")
		goDebug.keyEquivalentModifierMask = [.command, .control]
		runMenu.addItem(goDebug)
		let runItem = NSMenuItem(
			title: "Run…",
			action: #selector(MainWindowController.showRunConfigurations(_:)),
			keyEquivalent: "r"
		)
		runItem.keyEquivalentModifierMask = [.control]
		runMenu.addItem(runItem)
		let runSelected = NSMenuItem(
			title: "Run",
			action: #selector(MainWindowController.runSelected(_:)),
			keyEquivalent: "r"
		)
		runSelected.keyEquivalentModifierMask = [.control]
		runMenu.addItem(runSelected)

		let debugSelected = NSMenuItem(
			title: "Debug",
			action: #selector(MainWindowController.debugSelected(_:)),
			keyEquivalent: "d"
		)
		debugSelected.keyEquivalentModifierMask = [.control]
		runMenu.addItem(debugSelected)
		let fromMake = NSMenuItem(
			title: "New from Make goal\u{2026}",
			action: #selector(MainWindowController.newFromMakeGoal(_:)),
			keyEquivalent: ""
		)
		runMenu.addItem(fromMake)
		runMenu.addItem(.separator())

		let profiler = NSMenuItem(
			title: "Profile\u{2026}",
			action: #selector(MainWindowController.showProfiler(_:)),
			keyEquivalent: "p"
		)
		profiler.keyEquivalentModifierMask = [.control, .shift]
		runMenu.addItem(profiler)
		runMenu.addItem(.separator())

		let debugExecutable = NSMenuItem(
			title: "Debug Executable\u{2026}",
			action: #selector(MainWindowController.debugExecutable(_:)),
			keyEquivalent: ""
		)
		runMenu.addItem(debugExecutable)
		let attachItem = NSMenuItem(
			title: "Attach to Process\u{2026}",
			action: #selector(MainWindowController.attachToProcess(_:)),
			keyEquivalent: ""
		)
		runMenu.addItem(attachItem)
		runMenu.addItem(.separator())

		// The function keys IDEA and Xcode both use, so the fingers that
		// already know them do not have to learn anything.
		let resume = NSMenuItem(
			title: "Continue", action: #selector(MainWindowController.debugContinue(_:)), keyEquivalent: "\u{F70C}"
		)
		resume.keyEquivalentModifierMask = []
		runMenu.addItem(resume)

		let pause = NSMenuItem(
			title: "Pause", action: #selector(MainWindowController.debugPause(_:)), keyEquivalent: ""
		)
		runMenu.addItem(pause)

		let stepOver = NSMenuItem(
			title: "Step Over", action: #selector(MainWindowController.debugStepOver(_:)), keyEquivalent: "\u{F70B}"
		)
		stepOver.keyEquivalentModifierMask = []
		runMenu.addItem(stepOver)

		let stepInto = NSMenuItem(
			title: "Step Into", action: #selector(MainWindowController.debugStepInto(_:)), keyEquivalent: "\u{F70A}"
		)
		stepInto.keyEquivalentModifierMask = []
		runMenu.addItem(stepInto)

		let stepOut = NSMenuItem(
			title: "Step Out", action: #selector(MainWindowController.debugStepOut(_:)), keyEquivalent: "\u{F70B}"
		)
		stepOut.keyEquivalentModifierMask = [.shift]
		runMenu.addItem(stepOut)

		let stopDebugging = NSMenuItem(
			title: "Stop", action: #selector(MainWindowController.debugStop(_:)), keyEquivalent: "\u{F705}"
		)
		stopDebugging.keyEquivalentModifierMask = [.command]
		runMenu.addItem(stopDebugging)

		runMenu.addItem(.separator())
		runMenu.addItem(withTitle: "Go Trace", action: #selector(MainWindowController.goTrace(_:)), keyEquivalent: "")
		runMenu.addItem(withTitle: "Go CPU Profile", action: #selector(MainWindowController.goProfile(_:)), keyEquivalent: "")
		runMenuItem.submenu = runMenu
		mainMenu.addItem(runMenuItem)

		// Agent actions get their own menu: this is the part of the app that is
		// meant to grow.
		let agentMenuItem = NSMenuItem()
		let agentMenu = NSMenu(title: "Agent")
		let reviewItem = NSMenuItem(
			title: "Review Branch…",
			action: #selector(MainWindowController.reviewBranch(_:)),
			keyEquivalent: "r"
		)
		reviewItem.keyEquivalentModifierMask = [.command, .shift]
		agentMenu.addItem(reviewItem)

		let uncommittedItem = NSMenuItem(
			title: "Review Uncommitted Changes…",
			action: #selector(MainWindowController.reviewUncommittedChanges(_:)),
			keyEquivalent: "u"
		)
		uncommittedItem.keyEquivalentModifierMask = [.command, .shift]
		agentMenu.addItem(uncommittedItem)

		agentMenu.addItem(.separator())
		// The list of what is running everywhere, on a key: the pill on the
		// terminal's title bar is the other way to it, and it needs the panel
		// open and a small target aimed at.
		let sessionsItem = NSMenuItem(
			title: "Running Sessions",
			action: #selector(MainWindowController.showRunningSessions(_:)),
			keyEquivalent: "a"
		)
		sessionsItem.keyEquivalentModifierMask = [.command, .shift]
		agentMenu.addItem(sessionsItem)

		agentMenu.addItem(.separator())
		let backlogItem = NSMenuItem(
			title: "Backlog",
			action: #selector(MainWindowController.showBacklog(_:)),
			keyEquivalent: "b"
		)
		backlogItem.keyEquivalentModifierMask = [.command, .shift]
		agentMenu.addItem(backlogItem)

		agentMenu.addItem(withTitle: "Start the Next Ready Item\u{2026}",
		                  action: #selector(MainWindowController.startNextBacklogItem(_:)),
		                  keyEquivalent: "")

		agentMenuItem.submenu = agentMenu
		mainMenu.addItem(agentMenuItem)

		let viewMenuItem = NSMenuItem()
		// **Grouped, because it was fifty items in one column.** A menu that
		// long is read top to bottom every time, and the things that belong
		// together — every terminal verb, every editor toggle, the three git
		// pages — were separated by the order they were added in. What stays
		// at the top level is what is pressed from memory: the four sidebar
		// tools on ⌘1–4, the zoom, and the two secret verbs the specs name as
		// *View ▸ Reveal Secrets* and *View ▸ Running Servers and Containers*.
		// Everything else is a submenu named for what it is about; the palette
		// reads the path, so "Terminal ▸ New Terminal Tab" is what it finds.
		let viewMenu = NSMenu(title: "View")
		viewMenu.addItem(withTitle: "Project", action: #selector(MainWindowController.showProjectView(_:)), keyEquivalent: "1")
		viewMenu.addItem(withTitle: "Git", action: #selector(MainWindowController.toggleBranchesView(_:)), keyEquivalent: "2")
		viewMenu.addItem(withTitle: "Structure", action: #selector(MainWindowController.toggleStructureView(_:)), keyEquivalent: "3")
		viewMenu.addItem(withTitle: "Scratches", action: #selector(MainWindowController.toggleScratchesView(_:)), keyEquivalent: "4")
		viewMenu.addItem(
			withTitle: "Pull Requests",
			action: #selector(MainWindowController.togglePullRequestsView(_:)),
			keyEquivalent: ""
		)
		// ⌘5 and ⌘6 used to be Commit and History; the items stay, hidden, so
		// the old press says where the thing went rather than doing nothing.
		viewMenu.addItem(withTitle: "Commit (moved)", action: #selector(MainWindowController.movedShortcut(_:)), keyEquivalent: "5")
			.isHidden = true
		viewMenu.addItem(withTitle: "History (moved)", action: #selector(MainWindowController.movedShortcut(_:)), keyEquivalent: "6")
			.isHidden = true
		viewMenu.addItem(.separator())

		// The git pages at the size a graph or a message needs.
		let gitPages = NSMenu(title: "Git Pages")
		let logItem = gitPages.addItem(
			withTitle: "Log", action: #selector(MainWindowController.showLogPage(_:)), keyEquivalent: "l"
		)
		logItem.keyEquivalentModifierMask = [.command, .shift]
		let commitItem = gitPages.addItem(
			withTitle: "Commit Page", action: #selector(MainWindowController.showCommitPage(_:)),
			keyEquivalent: "k"
		)
		commitItem.keyEquivalentModifierMask = [.command, .shift]
		let estateItem = gitPages.addItem(
			withTitle: "Submodules", action: #selector(MainWindowController.showEstatePage(_:)),
			keyEquivalent: "m"
		)
		estateItem.keyEquivalentModifierMask = [.command, .shift]
		gitPages.addItem(.separator())
		gitPages.addItem(NSMenuItem(
			title: "Arrange Commit Files by Folder",
			action: #selector(MainWindowController.toggleCommitFilesByFolder(_:)),
			keyEquivalent: ""
		))
		let gitPagesItem = NSMenuItem(title: "Git Pages", action: nil, keyEquivalent: "")
		gitPagesItem.submenu = gitPages
		viewMenu.addItem(gitPagesItem)

		let diff = NSMenu(title: "Diff")
		let sideBySide = diff.addItem(
			withTitle: "Side by Side Diff",
			action: #selector(MainWindowController.toggleSideBySideDiff(_:)),
			keyEquivalent: ""
		)
		sideBySide.state = Settings.shared.diffIsSideBySide ? .on : .off
		let chrome = diff.addItem(
			withTitle: "Show Diff Headers",
			action: #selector(MainWindowController.toggleDiffChrome(_:)),
			keyEquivalent: ""
		)
		chrome.state = Settings.shared.diffShowsChrome ? .on : .off
		let diffItem = NSMenuItem(title: "Diff", action: nil, keyEquivalent: "")
		diffItem.submenu = diff
		viewMenu.addItem(diffItem)
		viewMenu.addItem(.separator())

		// How the front tab is shown. The item used to have no title of its
		// own and read as "NSMenuItem", the class's name, in the menu.
		let previewItem = NSMenuItem(title: "Show As", action: nil, keyEquivalent: "")
		let previewMenu = NSMenu(title: "Show As")
		for (index, mode) in PreviewMode.allCases.enumerated() {
			let item = NSMenuItem(
				title: mode.title,
				action: #selector(MainWindowController.choosePreviewMode(_:)),
				keyEquivalent: String(index + 1)
			)
			item.keyEquivalentModifierMask = [.control, .command]
			item.representedObject = mode.rawValue
			previewMenu.addItem(item)
		}
		previewItem.submenu = previewMenu
		viewMenu.addItem(previewItem)

		let editor = NSMenu(title: "Editor")
		let wrapItem = NSMenuItem(
			title: "Toggle Word Wrap",
			action: #selector(MainWindowController.toggleWordWrap(_:)),
			keyEquivalent: "z"
		)
		wrapItem.keyEquivalentModifierMask = [.command, .option]
		editor.addItem(wrapItem)
		let blameItem = NSMenuItem(
			title: "Toggle Blame",
			action: #selector(MainWindowController.toggleBlame(_:)),
			keyEquivalent: "b"
		)
		blameItem.keyEquivalentModifierMask = [.command, .option]
		editor.addItem(blameItem)
		let preview = NSMenuItem(
			title: "Toggle Markdown Preview",
			action: #selector(MainWindowController.toggleMarkdownPreview(_:)),
			keyEquivalent: "v"
		)
		preview.keyEquivalentModifierMask = [.command, .shift]
		editor.addItem(preview)
		editor.addItem(.separator())
		let foldAll = NSMenuItem(title: "Collapse All", action: #selector(MainWindowController.collapseAllFolds(_:)), keyEquivalent: "-")
		foldAll.keyEquivalentModifierMask = [.command, .shift]
		editor.addItem(foldAll)
		let unfoldAll = NSMenuItem(title: "Expand All", action: #selector(MainWindowController.expandAllFolds(_:)), keyEquivalent: "+")
		unfoldAll.keyEquivalentModifierMask = [.command, .shift]
		editor.addItem(unfoldAll)
		editor.addItem(.separator())
		let splitRight = NSMenuItem(
			title: "Split Right",
			action: #selector(MainWindowController.splitEditorRight(_:)),
			keyEquivalent: "\\"
		)
		editor.addItem(splitRight)
		let splitDown = NSMenuItem(
			title: "Split Down",
			action: #selector(MainWindowController.splitEditorDown(_:)),
			keyEquivalent: "\\"
		)
		splitDown.keyEquivalentModifierMask = [.command, .shift]
		editor.addItem(splitDown)
		let maximizeEditor = NSMenuItem(
			title: "Maximize Editor",
			action: #selector(MainWindowController.toggleEditorMaximized(_:)),
			keyEquivalent: "\r"
		)
		maximizeEditor.keyEquivalentModifierMask = [.command, .shift]
		editor.addItem(maximizeEditor)
		editor.addItem(.separator())
		let nextTab = NSMenuItem(title: "Next Tab", action: #selector(MainWindowController.selectNextTab(_:)), keyEquivalent: "]")
		nextTab.keyEquivalentModifierMask = [.command, .shift]
		editor.addItem(nextTab)
		let previousTab = NSMenuItem(title: "Previous Tab", action: #selector(MainWindowController.selectPreviousTab(_:)), keyEquivalent: "[")
		previousTab.keyEquivalentModifierMask = [.command, .shift]
		editor.addItem(previousTab)
		let editorItem = NSMenuItem(title: "Editor", action: nil, keyEquivalent: "")
		editorItem.submenu = editor
		viewMenu.addItem(editorItem)

		let terminal = NSMenu(title: "Terminal")
		terminal.addItem(NSMenuItem(title: "Toggle Terminal", action: #selector(MainWindowController.toggleTerminal(_:)), keyEquivalent: "j"))
		let newTerminalItem = NSMenuItem(title: "New Terminal", action: #selector(MainWindowController.newTerminal(_:)), keyEquivalent: "t")
		newTerminalItem.keyEquivalentModifierMask = [.command, .shift]
		terminal.addItem(newTerminalItem)
		terminal.addItem(NSMenuItem(
			title: MainWindowController.containerTerminalTitle,
			action: #selector(MainWindowController.newTerminalInContainer(_:)),
			keyEquivalent: ""
		))
		let terminalTabItem = NSMenuItem(
			title: "New Terminal Tab",
			action: Selector(("newTerminalTab:")),
			keyEquivalent: "t"
		)
		terminalTabItem.keyEquivalentModifierMask = [.command]
		terminal.addItem(terminalTabItem)
		let terminalTabBesideItem = NSMenuItem(
			title: "New Terminal Tab Here",
			action: Selector(("newTerminalTabBeside:")),
			keyEquivalent: "d"
		)
		terminalTabBesideItem.keyEquivalentModifierMask = [.command]
		terminal.addItem(terminalTabBesideItem)
		terminal.addItem(.separator())
		let followTerminal = NSMenuItem(
			title: "Follow Terminal Project",
			action: #selector(MainWindowController.toggleFollowTerminal(_:)),
			keyEquivalent: "f"
		)
		followTerminal.keyEquivalentModifierMask = [.command, .control]
		terminal.addItem(followTerminal)
		let maximizeTerminal = NSMenuItem(
			title: "Maximize Terminal",
			action: #selector(MainWindowController.togglePanelMaximized(_:)),
			keyEquivalent: "j"
		)
		maximizeTerminal.keyEquivalentModifierMask = [.command, .shift]
		terminal.addItem(maximizeTerminal)
		let terminalItem = NSMenuItem(title: "Terminal", action: nil, keyEquivalent: "")
		terminalItem.submenu = terminal
		viewMenu.addItem(terminalItem)
		viewMenu.addItem(.separator())

		let revealItem = NSMenuItem(
			title: "Reveal Secrets",
			action: #selector(MainWindowController.toggleRevealSecrets(_:)),
			keyEquivalent: ""
		)
		viewMenu.addItem(revealItem)
		viewMenu.addItem(NSMenuItem(
			title: "Decrypt with sops",
			action: #selector(MainWindowController.decryptWithSops(_:)),
			keyEquivalent: ""
		))
		let runningTools = NSMenuItem(
			title: "Running Servers and Containers…",
			action: #selector(showRunningTools(_:)),
			keyEquivalent: ""
		)
		runningTools.target = self
		viewMenu.addItem(runningTools)
		viewMenu.addItem(.separator())

		let zoomIn = NSMenuItem(title: "Zoom In", action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "+")
		viewMenu.addItem(zoomIn)
		let zoomInAlt = NSMenuItem(title: "Zoom In", action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "=")
		zoomInAlt.isAlternate = true
		zoomInAlt.isHidden = true
		viewMenu.addItem(zoomInAlt)
		viewMenu.addItem(withTitle: "Zoom Out", action: #selector(MainWindowController.zoomOut(_:)), keyEquivalent: "-")
		viewMenu.addItem(withTitle: "Actual Size", action: #selector(MainWindowController.resetZoom(_:)), keyEquivalent: "0")
		let presentation = NSMenuItem(
			title: "Presentation Mode",
			action: #selector(MainWindowController.togglePresentationMode(_:)),
			keyEquivalent: "p"
		)
		presentation.keyEquivalentModifierMask = [.command, .control]
		viewMenu.addItem(presentation)
		viewMenuItem.submenu = viewMenu
		mainMenu.addItem(viewMenuItem)

		NSApp.mainMenu = mainMenu
	}
}
