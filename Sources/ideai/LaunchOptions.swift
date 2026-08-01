import AppKit

/// Command-line options.
///
/// `--screenshot` exists so the UI can be verified during development without
/// Screen Recording permission: the window renders itself into a bitmap
/// in-process, which exercises exactly the same drawing code the display uses.
struct LaunchOptions {
	var projectPath: String?
	var filePath: String?
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
	/// Toggle a breakpoint on this 1-based line before capture.
	var breakpointLine: Int?
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
	/// Wait this long before capturing, for a language server to answer.
	var lspWait: Double?
	/// Rewrite the open file externally after this many seconds.
	var externalEdit: Double?
	/// Raw bytes to send to the terminal, for verifying key encodings.
	var terminalBytes: String?
	/// Preview mode to select before capture: source | preview | split.
	var previewMode: String?
	/// Query for the in-file find bar.
	var findQuery: String?
	/// Query for project-wide search.
	var searchQuery: String?
	/// Turn soft wrap on before capture.
	var wordWrap = false
	/// Open the project switcher, optionally with a filter applied.
	var switcherFilter: String?
	/// Split the editor before capture: "right" or "down".
	var split: String?
	/// Draw a tab drop preview before capture, without a real drag.
	var dropZone: String?

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
			case "--file":       options.filePath = next()
			case "--screenshot": options.screenshotPath = next()
			case "--delay":      options.screenshotDelay = next().flatMap(Double.init) ?? 1.5
			case "--expand":     options.expandNavigator = true
			case "--type":       options.typeText = next()
			case "--collapse":   options.collapseFolds = true
			case "--preview":    options.previewPath = next()
			case "--markdown":   options.markdownPreview = true
			case "--settings":   options.openSettings = true
			case "--zoom":       options.zoom = next().flatMap(Double.init)
			case "--terminal":   options.openTerminal = true
			case "--run":        options.terminalInput = next()
			case "--review":     options.startReview = true
			case "--review-uncommitted": options.reviewUncommitted = true
			case "--changes":    options.showChanges = true
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
			case "--lsp-wait":   options.lspWait = next().flatMap(Double.init)
			case "--external-edit": options.externalEdit = next().flatMap(Double.init)
			case "--send-bytes": options.terminalBytes = next()
			case "--preview-mode": options.previewMode = next()
			case "--sidebar-cycle": options.sidebarCycle = true
			case "--zoom-cycle":  options.zoomCycle = true
			case "--tear-off":   options.tearOffFile = next()
			case "--bench-render": options.benchRender = true
			case "--metal-shot": options.metalShot = next()
			case "--maximize-terminal": options.maximizeTerminal = true
			case "--follow-terminal": options.followTerminal = true
			case "--breakpoint": options.breakpointLine = next().flatMap(Int.init)
			case "--find":       options.findQuery = next()
			case "--search":     options.searchQuery = next()
			case "--wrap":       options.wordWrap = true
			case "--switcher":   options.switcherFilter = next()
			case "--split":      options.split = next()
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

enum WindowCapture {
	/// Renders a window to a PNG.
	///
	/// Draws the theme frame when reachable so the capture includes the titlebar
	/// and its pills; otherwise falls back to the content view.
	@discardableResult
	static func write(window: NSWindow, to path: String) -> Bool {
		guard let contentView = window.contentView else { return false }
		let target = contentView.superview ?? contentView

		target.layoutSubtreeIfNeeded()
		guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { return false }
		target.cacheDisplay(in: target.bounds, to: rep)

		guard let data = rep.representation(using: .png, properties: [:]) else { return false }
		do {
			try data.write(to: URL(fileURLWithPath: path))
			return true
		} catch {
			FileHandle.standardError.write(Data("screenshot write failed: \(error)\n".utf8))
			return false
		}
	}
}
