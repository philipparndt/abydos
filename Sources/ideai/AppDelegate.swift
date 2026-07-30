import AppKit
import IdeaiKit

final class AppDelegate: NSObject, NSApplicationDelegate {
	private var windowControllers: [MainWindowController] = []

	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.appearance = NSAppearance(named: .darkAqua)
		// Before any view measures text.
		FontRegistry.registerBundledFonts()
		buildMenu()

		// On first launch there is no ideai history, so seed the switcher from
		// JetBrains' own recent-projects list — the point is that the list in the
		// titlebar is already populated with the projects the user cares about.
		RecentProjects.shared.seedFromJetBrainsIfEmpty()

		let options = LaunchOptions.parse()
		if let zoom = options.zoom { Settings.shared.uiScale = zoom }

		let controller: MainWindowController?
		if let path = options.projectPath {
			controller = open(projectAt: URL(fileURLWithPath: path, isDirectory: true))
		} else if let last = RecentProjects.shared.entries.first {
			controller = open(projectAt: last.url)
		} else if options.isScreenshotRun {
			// A capture run must never block on a modal panel.
			controller = nil
		} else {
			openProjectPanel(nil)
			controller = windowControllers.first
		}

		if let filePath = options.filePath {
			controller?.openFile(at: URL(fileURLWithPath: filePath))
		}
		if let previewPath = options.previewPath {
			controller?.previewFile(at: URL(fileURLWithPath: previewPath))
		}
		if options.expandNavigator {
			controller?.expandNavigatorTree()
		}

		NSApp.activate(ignoringOtherApps: true)

		// Simulated input runs after the initial parse lands, so folds and
		// highlights exist by the time it is exercised.
		if options.wordWrap {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				controller?.toggleWordWrap(nil)
			}
		}
		if let query = options.findQuery {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
				controller?.findInFile(nil)
				controller?.setFindQuery(query)
			}
		}
		if let query = options.searchQuery {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
				controller?.findInProject(nil)
				controller?.setProjectSearchQuery(query)
			}
		}

		if options.startReview {
			controller?.reviewBranch(nil)
		}

		if options.openTerminal {
			controller?.toggleTerminal(nil)
			if let input = options.terminalInput {
				// Give the shell time to print its prompt before typing at it.
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
					controller?.sendToTerminal(input + "\n")
				}
			}
		}

		if options.typeText != nil || options.collapseFolds || options.markdownPreview {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(0.5, options.screenshotDelay - 0.5)) {
				if let text = options.typeText { controller?.simulateTyping(text) }
				if options.collapseFolds { controller?.collapseAllFolds(nil) }
				if options.markdownPreview { controller?.toggleMarkdownPreview(nil) }
			}
		}

		if options.openSettings {
			SettingsWindowController.shared.show()
		}

		if let path = options.screenshotPath {
			scheduleScreenshot(
				path: path,
				delay: options.screenshotDelay,
				controller: controller,
				// A capture run asking for Settings wants that window, not the project.
				window: options.openSettings ? SettingsWindowController.shared.window : nil
			)
		}
	}

	/// Captures the window after async work (git status, parsing, folds) settles,
	/// then exits with a status reflecting whether the file was written.
	private func scheduleScreenshot(
		path: String,
		delay: TimeInterval,
		controller: MainWindowController?,
		window explicitWindow: NSWindow? = nil
	) {
		DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
			guard let window = explicitWindow ?? controller?.window ?? NSApp.windows.first else {
				FileHandle.standardError.write(Data("no window to capture\n".utf8))
				exit(2)
			}
			let ok = WindowCapture.write(window: window, to: path)
			exit(ok ? 0 : 3)
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		true
	}

	@objc func showSettings(_ sender: Any?) {
		SettingsWindowController.shared.show()
	}

	/// Flushes pending edits when the app goes to the background, so switching to
	/// a terminal always finds the file on disk current.
	func applicationDidResignActive(_ notification: Notification) {
		guard Settings.shared.saveOnFocusLoss else { return }
		for controller in windowControllers {
			controller.autoSaveAll()
		}
	}

	func applicationWillTerminate(_ notification: Notification) {
		for controller in windowControllers {
			controller.autoSaveAll()
		}
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		for url in urls where url.hasDirectoryPath {
			open(projectAt: url)
		}
	}

	// MARK: - Opening projects

	@discardableResult
	func open(projectAt url: URL) -> MainWindowController {
		// Focus an existing window rather than opening the same project twice.
		if let existing = windowControllers.first(where: { $0.project?.root.standardizedFileURL == url.standardizedFileURL }) {
			existing.showWindow(nil)
			return existing
		}

		let controller = MainWindowController()
		controller.onClose = { [weak self, weak controller] in
			guard let self, let controller else { return }
			self.windowControllers.removeAll { $0 === controller }
		}
		windowControllers.append(controller)
		controller.load(project: Project(root: url))
		controller.showWindow(nil)
		RecentProjects.shared.record(url: url)
		return controller
	}

	var openProjectRoots: [URL] {
		windowControllers.compactMap { $0.project?.root }
	}

	@objc func openProjectPanel(_ sender: Any?) {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.allowsMultipleSelection = false
		panel.prompt = "Open"
		panel.message = "Choose a project directory"

		guard panel.runModal() == .OK, let url = panel.url else {
			// Nothing open and nothing chosen — there is no useful state to sit in.
			if windowControllers.isEmpty { NSApp.terminate(nil) }
			return
		}
		open(projectAt: url)
	}

	// MARK: - Menu

	private func buildMenu() {
		let mainMenu = NSMenu()

		let appMenuItem = NSMenuItem()
		let appMenu = NSMenu()
		appMenu.addItem(withTitle: "About ideai", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
		appMenu.addItem(.separator())
		let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
		settingsItem.target = self
		appMenu.addItem(settingsItem)
		appMenu.addItem(.separator())
		appMenu.addItem(withTitle: "Hide ideai", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
		appMenu.addItem(withTitle: "Quit ideai", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
		appMenuItem.submenu = appMenu
		mainMenu.addItem(appMenuItem)

		let fileMenuItem = NSMenuItem()
		let fileMenu = NSMenu(title: "File")
		let openItem = NSMenuItem(title: "Open…", action: #selector(openProjectPanel(_:)), keyEquivalent: "o")
		openItem.target = self
		fileMenu.addItem(openItem)
		fileMenu.addItem(.separator())
		fileMenu.addItem(withTitle: "Save", action: #selector(MainWindowController.saveDocument(_:)), keyEquivalent: "s")
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
		editMenu.addItem(.separator())
		editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
		editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
		editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
		editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
		editMenu.addItem(.separator())
		editMenu.addItem(withTitle: "Find…", action: #selector(MainWindowController.findInFile(_:)), keyEquivalent: "f")
		let findInProject = NSMenuItem(
			title: "Find in Project…",
			action: #selector(MainWindowController.findInProject(_:)),
			keyEquivalent: "f"
		)
		findInProject.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(findInProject)
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
		agentMenuItem.submenu = agentMenu
		mainMenu.addItem(agentMenuItem)

		let viewMenuItem = NSMenuItem()
		let viewMenu = NSMenu(title: "View")
		viewMenu.addItem(withTitle: "Toggle Project Navigator", action: #selector(MainWindowController.toggleNavigator(_:)), keyEquivalent: "1")
		let terminalItem = NSMenuItem(title: "Toggle Terminal", action: #selector(MainWindowController.toggleTerminal(_:)), keyEquivalent: "j")
		viewMenu.addItem(terminalItem)
		let newTerminalItem = NSMenuItem(title: "New Terminal", action: #selector(MainWindowController.newTerminal(_:)), keyEquivalent: "t")
		newTerminalItem.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(newTerminalItem)
		let foldAll = NSMenuItem(title: "Collapse All", action: #selector(MainWindowController.collapseAllFolds(_:)), keyEquivalent: "-")
		foldAll.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(foldAll)
		let unfoldAll = NSMenuItem(title: "Expand All", action: #selector(MainWindowController.expandAllFolds(_:)), keyEquivalent: "+")
		unfoldAll.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(unfoldAll)
		viewMenu.addItem(.separator())
		// ⌘+ is reported as "=" on most layouts; both are registered so the key
		// works with and without shift.
		let zoomIn = NSMenuItem(title: "Zoom In", action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "+")
		viewMenu.addItem(zoomIn)
		let zoomInAlt = NSMenuItem(title: "Zoom In", action: #selector(MainWindowController.zoomIn(_:)), keyEquivalent: "=")
		zoomInAlt.isAlternate = true
		zoomInAlt.isHidden = true
		viewMenu.addItem(zoomInAlt)
		viewMenu.addItem(withTitle: "Zoom Out", action: #selector(MainWindowController.zoomOut(_:)), keyEquivalent: "-")
		viewMenu.addItem(withTitle: "Actual Size", action: #selector(MainWindowController.resetZoom(_:)), keyEquivalent: "0")
		viewMenu.addItem(.separator())
		let wrapItem = NSMenuItem(
			title: "Toggle Word Wrap",
			action: #selector(MainWindowController.toggleWordWrap(_:)),
			keyEquivalent: "z"
		)
		wrapItem.keyEquivalentModifierMask = [.command, .option]
		viewMenu.addItem(wrapItem)
		let preview = NSMenuItem(
			title: "Toggle Markdown Preview",
			action: #selector(MainWindowController.toggleMarkdownPreview(_:)),
			keyEquivalent: "v"
		)
		preview.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(preview)
		viewMenu.addItem(.separator())
		let nextTab = NSMenuItem(title: "Next Tab", action: #selector(MainWindowController.selectNextTab(_:)), keyEquivalent: "]")
		nextTab.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(nextTab)
		let previousTab = NSMenuItem(title: "Previous Tab", action: #selector(MainWindowController.selectPreviousTab(_:)), keyEquivalent: "[")
		previousTab.keyEquivalentModifierMask = [.command, .shift]
		viewMenu.addItem(previousTab)
		viewMenuItem.submenu = viewMenu
		mainMenu.addItem(viewMenuItem)

		NSApp.mainMenu = mainMenu
	}
}
