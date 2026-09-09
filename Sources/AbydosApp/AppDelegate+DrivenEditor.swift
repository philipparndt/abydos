import AppKit
import AbydosKit

/// The flags a driven run applies once its window is up.
///
/// Every one of them is the same shape — a flag was given, so do the thing and
/// often print what happened — and they are in no order but the one they were
/// written in. Splitting them three ways is splitting a list, and the list is
/// what it is: `--help` is the index.
///
/// This third is the editor and the window it is in: the files opened, the
/// panes split, trust, the palette, and what typing does.
@MainActor
extension AppDelegate {
	func driveTheEditor(_ options: LaunchOptions, in controller: MainWindowController?) {

		for path in options.filePaths {
			controller?.openFile(at: URL(fileURLWithPath: path))
		}
		if let previewPath = options.previewPath {
			controller?.previewFile(at: URL(fileURLWithPath: previewPath))
		}
		if options.expandNavigator {
			controller?.expandNavigatorTree()
		}

		// A capture run never takes the keyboard.
		//
		// The screenshot is drawn straight from the view hierarchy, so it needs
		// no focus at all — and an app that steals it while somebody is typing
		// somewhere else does not merely interrupt them: their next keystrokes
		// arrive in whatever this window has open, and get saved there.
		// `writesACapture` rather than the two flags that used to be named here:
		// a picture is drawn from the view hierarchy whichever flag asked for
		// it, and the pair was a list that went out of date the moment a third
		// capture flag was added.
		if options.writesACapture {
			NSApp.setActivationPolicy(.accessory)
		} else {
			NSApp.activate(ignoringOtherApps: true)
		}

		// Simulated input runs after the initial parse lands, so folds and
		// highlights exist by the time it is exercised.
		if options.splitActive {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.splitActiveForTesting()
			}
		}
		if options.splitThenDisturb {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.splitThenDisturbForTesting()
			}
		}
		if options.splitPanes {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.splitPanesForTesting()
			}
		}
		if options.splitTerminals {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.splitTerminalsForTesting()
			}
		}
		if options.previewTerminalDrop {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.previewTerminalDropForTesting()
			}
		}
		if options.tearOffTerminal {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.tearOffTerminalForTesting()
			}
			// And then the command a person reaches for out there, through the
			// responder chain the menu uses rather than by calling the method:
			// calling it proves the method exists, which was never in doubt.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				let item = NSMenuItem(
					title: "New Terminal Tab",
					action: Selector(("newTerminalTab:")),
					keyEquivalent: "t"
				)
				let window = TerminalWindowController.lastOpenedForTesting
				let before = window?.terminalCountForTesting ?? -1
				let enabled = window?.validateMenuItem(item) ?? false
				// Down that window's own responder chain rather than the
				// application's: a capture run has no key window, so an
				// app-wide send starts nowhere and proves nothing.
				window?.window?.makeKeyAndOrderFront(nil)
				let delivered = window?.window?.tryToPerform(item.action!, with: item) ?? false
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
					print("TORNOFF: enabled=\(enabled) delivered=\(delivered) "
						+ "terminals \(before) -> \(window?.terminalCountForTesting ?? -1)")
				}
			}
		}

		if let name = options.renameTerminal {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.renameActiveTerminalForTesting(to: name)
			}
		}

		if let path = options.switchTo {
			DispatchQueue.main.asyncAfter(deadline: .now() + options.switchToAt) {
				let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
				// Timed in place when there is a window to switch, because that
				// is the thing being complained about: a switch inside the window
				// somebody is looking at, not a second window opening beside it.
				if let controller = self.windowControllers.first {
					controller.measureProjectSwitchForTesting(to: url)
					print("SWITCHED to \(controller.project?.root.lastPathComponent ?? "nothing"); "
						+ "\(self.windowControllers.count) window(s)")
				} else {
					let to = self.open(projectAt: url)
					print("SWITCHED to \(to.project?.root.lastPathComponent ?? "nothing"); "
						+ "\(self.windowControllers.count) window(s)")
				}
				fflush(stdout)
			}
		}

		if let query = options.paletteFiles {
			ProjectSwitcherPopover.reportsForTesting = true
			// Late enough that the project has opened and the tree has settled:
			// what is being measured is the palette, not the window behind it.
			DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
				controller?.showProjectSwitcher(nil)
				// A character at a time, at about the rate somebody types.
				for length in 1...max(query.count, 1) {
					let so_far = String(query.prefix(length))
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(length) * 0.15) {
						ProjectSwitcherPopover.applyFilterForTesting(so_far)
					}
				}
				DispatchQueue.main.asyncAfter(
					deadline: .now() + 0.5 + Double(max(query.count, 1)) * 0.15 + 2.5
				) {
					for line in ProjectSwitcherPopover.rowsForTesting() {
						print("PALETTEFILES \(line)")
					}
					fflush(stdout)
					if options.writesACapture { return }
					exit(0)
				}
			}
		}

		if options.trust.remoteHost || options.trust.remoteOwner {
			// Later than the folder's: the remote is read from git after the
			// project loads, and trusting where a clone came from needs the
			// answer to have arrived.
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
				controller?.trustRemoteForTesting(owner: options.trust.remoteOwner)
			}
		}
		if options.trust.project || options.trust.parent {
			// Before anything else asks: the point of the flag is a run that
			// starts where a person would be after pressing Trust.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				controller?.trustProjectForTesting(coveringChildren: options.trust.parent)
			}
		}
		if let path = options.terminalServicePath {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				print("SERVICE: " + self.terminalService.openTerminalForTesting(path))
				fflush(stdout)
				// What it opened and where its terminal is, a moment later: the
				// window has to exist before it can be asked.
				DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
					let controller = self.frontmostController
					print("SERVICE window: project="
						+ (controller?.project?.root.lastPathComponent ?? "none")
						+ " terminals=\(controller?.panelForTesting.terminalIdentities.count ?? 0)")
					fflush(stdout)
					if options.writesACapture { return }
					exit(0)
				}
			}
		}
		if options.trust.dismiss {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.hideTrustBanner()
			}
		}
		if options.trust.heldBack {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.heldBackForTesting()
			}
		}
		if options.trust.report {
			// Late enough to be *after* whatever the run asked for: the useful
			// question is what the window says once a refusal has happened, and
			// a report before the press only ever says "idle".
			DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
				let root = controller?.project?.root
				let trusted = root.map { ProjectTrust.shared.isTrusted($0) } ?? false
				print("TRUST menu: " + (controller?.trustMenuForTesting() ?? "no window"))
				print("TRUST run control: "
					+ (controller?.runForTesting.runControl?.statusReportForTesting ?? "none"))
				print("TRUST: trusted=\(trusted) banner=["
					+ (controller?.trustBannerReportForTesting() ?? "no window") + "]")
				fflush(stdout)
			}
		}
		if let filter = options.switcherFilter {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				if options.switcherFromPill {
					controller?.showProjectSwitcherAtPill()
				} else {
					controller?.showProjectSwitcher(nil)
				}
				// Where it landed, said before anything is typed: the key's
				// palette is centred over the window that answered it, and a
				// placement claim is one a report can make without a picture.
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
					print("SWITCHER placement: \(ProjectSwitcherPopover.placementForTesting())")
					fflush(stdout)
				}
				if !filter.isEmpty {
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
						ProjectSwitcherPopover.applyFilterForTesting(filter)
					}
				}
				if let keys = options.switcherKeys {
					DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
						for key in keys.split(separator: ",") {
							// `again` is the shortcut pressed a second time,
							// which is a different door from the list's own
							// keys: it goes to the panel, not to the table.
							let said = key == "again"
								? ProjectSwitcherPopover.pressTheKeyAgainForTesting()
								: ProjectSwitcherPopover.pressForTesting(String(key))
							print("SWITCHER \(key): \(said)")
						}
						fflush(stdout)
						if options.writesACapture { return }
						exit(0)
					}
				}
			}
		}
		if let split = options.split {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				if split == "down" {
					controller?.splitEditorDown(nil)
				} else {
					controller?.splitEditorRight(nil)
				}
			}
		}
		if let position = options.settingsDivider {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.dragSettingsDividerForTesting(to: position)
			}
		}
		if let position = options.editorDivider {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.dragSettingsDividerForTesting(to: position, settings: false)
			}
		}
		if let name = options.dropZone {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				let zone: EditorTabDrag.Zone
				switch name {
				case "left":   zone = .left
				case "right":  zone = .right
				case "top":    zone = .top
				case "bottom": zone = .bottom
				default:       zone = .center
				}
				controller?.previewDropZone(zone)
			}
		}
		if options.wordWrap {
			// Set rather than toggled: the setting persists, so toggling made a
			// capture depend on how the previous run left it.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				controller?.setWordWrap(true)
			}
		}
		if let query = options.findQuery {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
				controller?.findInFile(nil)
				controller?.setFindQuery(query)
			}
		}
		if let steps = options.findNextSteps {
			// After the query has been typed and the debounced search has run;
			// stepping before there are any matches is a no-op that looks like the
			// verb being broken.
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
				controller?.editorForTesting.findNextFromEditorForTesting(steps)
			}
		}
		if let query = options.searchQuery {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
				controller?.findInProject(nil)
				controller?.setProjectSearchQuery(query)
			}
		}

		if let delay = options.externalEdit, let path = options.filePath {
			// Written by another process, the way an agent would.
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
				let url = URL(fileURLWithPath: path)
				guard var text = try? String(contentsOf: url, encoding: .utf8) else { return }
				text = "// added by the agent\n" + text
				try? text.write(to: url, atomically: true, encoding: .utf8)
			}
		}

		if let raw = options.previewMode, let mode = PreviewMode(rawValue: raw) {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.setPreviewMode(mode)
			}
		}

		// After the preview has had a moment to draw: the pane's Export uses the
		// text it drew, which is the whole point of exporting from the preview.
		if let raw = options.exportDiagram {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				controller?.editorForTesting.exportDiagramForTesting(raw)
			}
		}

		// Just before the capture rather than at a moment of its own: a size is
		// only interesting once there is a drawing to be that size, and how long
		// that takes is the whole reason `--delay` is a number somebody passes —
		// a diagram drawn in a container has a container to start first.
		if let raw = options.diagramFit {
			let at = options.isScreenshotRun ? max(3.0, options.screenshotDelay - 1.5) : 8.0
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.editorForTesting.setDiagramFitForTesting(raw)
			}
		}

		// The same moment for a picture, and sooner: a picture is a file read
		// off the disk rather than a drawing something else has to make, so
		// there is nothing to wait for but the window.
		if let raw = options.imageFit {
			let at = options.isScreenshotRun ? max(1.2, options.screenshotDelay - 1.0) : 2.0
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.editorForTesting.setImageFitForTesting(raw)
			}
		}

		// After the size and before the pan, for the same reason the pan is last:
		// each of the three depends on the one above it.
		if let steps = options.editorMenuSteps {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.editorForTesting.editorMenuForTesting(steps)
			}
		}

		if let steps = options.secretsSteps {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.editorForTesting.secretsForTesting(steps)
			}
		}

		if let steps = options.sopsSteps {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.editorForTesting.sopsForTesting(steps)
			}
		}

		if let steps = options.indentSteps {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.editorForTesting.indentChipForTesting(steps)
			}
		}

		if options.videoReport {
			// After the player has had a moment to load the asset: duration is
			// part of the report, and an unloaded item has none.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.videoReportForTesting()
			}
		}

		if let raw = options.imageZoom {
			let at = options.isScreenshotRun ? max(1.3, options.screenshotDelay - 0.9) : 2.2
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.zoomImageForTesting(raw)
			}
		}

		// After the size, because where a picture can be scrolled to depends on
		// how large it is being drawn.
		if let raw = options.imagePan {
			let at = options.isScreenshotRun ? max(1.4, options.screenshotDelay - 0.8) : 2.4
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.editorForTesting.panImageForTesting(raw)
			}
		}

		if let name = options.newFolder {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.navigatorForTesting.createFolderForTesting(named: name)
			}
		}

		if let name = options.newFile {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.navigatorForTesting.createFileForTesting(named: name)
			}
		}

		if options.newScratch {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
				controller?.newScratchForTesting()
			}
		}

		if options.typeBlock {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.editorForTesting.exerciseReturnIndentForTesting()
			}
		}

		if options.terminalTabKey {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				controller?.exerciseTerminalTabKeyForTesting()
			}
		}
		if options.nextTabInPanel {
			// After `--tab-fill` has finished filling: it starts at three
			// seconds and spaces its tabs a quarter of a second apart.
			DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
				controller?.exerciseNextTabForTesting()
			}
		}

		if options.printText {
			DispatchQueue.main.asyncAfter(deadline: .now() + max(2.0, options.screenshotDelay - 0.2)) {
				let text = controller?.editorForTesting.editorTextForTesting() ?? "no editor"
				print("TEXT ----------")
				for line in text.components(separatedBy: "\n") {
					print("| " + line.replacingOccurrences(of: "\t", with: "→"))
				}
				print("---------------")
			}
		}

		if !options.commentBlocks.isEmpty {
			// A second apart, so each press lands on the text the one before it
			// left rather than on a rope still being reparsed.
			for (step, spec) in options.commentBlocks.enumerated() {
				DispatchQueue.main.asyncAfter(deadline: .now() + 2.5 + Double(step)) {
					controller?.toggleCommentForTesting(spec)
				}
			}
		}

		if options.commentKey {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.editorForTesting.commentKeyReportForTesting()
			}
		}

		if let spec = options.snippet {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.editorForTesting.exerciseSnippetForTesting(spec)
			}
		}

		if options.menuKeys {
			// After the menu is built and the system has had its chance to move
			// anything: the relocation happens when the menu becomes the
			// application's, and reading a key equivalent before that reports the
			// literal from the source rather than the one somebody will press.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				MenuKeyReport.print()
				if !options.writesACapture { exit(0) }
			}
		}

		if let spec = options.selectLines {
			// Late, so whatever else the run asked for — a terminal, a results list
			// — has already taken the keyboard. The selection is made after it and
			// takes nothing back, which is the state being photographed.
			DispatchQueue.main.asyncAfter(deadline: .now() + max(2.5, options.screenshotDelay - 1.0)) {
				let parts = spec.split(separator: ":").compactMap { Int($0) }
				guard parts.count == 2 else { return }
				controller?.editorForTesting.selectLinesForTesting(from: parts[0], to: parts[1])
			}
		}

		if let spec = options.indentBlock {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				let parts = spec.split(separator: ":").map(String.init)
				guard parts.count == 3, let from = Int(parts[0]), let to = Int(parts[1]) else { return }
				controller?.editorForTesting.exerciseIndentForTesting(from: from, to: to, outdent: parts[2] == "out")
			}
		}

		if !options.optionKeys.isEmpty {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				for pair in options.optionKeys {
					let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
					guard parts.count == 2 else { continue }
					let sent = controller?.optionKeyForTesting(bare: parts[0], composed: parts[1])
					print("OPTIONKEY ⌥\(parts[0]) → \(sent ?? "no window") "
						+ "(bytes: \(Array((sent ?? "").utf8)))")
				}
			}
		}

		if let text = options.commitBody {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				print("COMMITBODY \(controller?.sidebarForTesting.typeInCommitBodyForTesting(text) ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if let frames = options.burstFrames {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				let sent = controller?.burstForTesting(frames: frames) ?? -1
				// A second later: long enough for the backlog to drain and for
				// the picture at the end of it to be drawn.
				DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
					print("BURST frames=\(sent) draws=\(TerminalView.drawCountForTesting)")
					fflush(stdout)
					if options.writesACapture { return }
					exit(0)
				}
			}
		}

		if let steps = options.copyPath {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				print("COPYPATH \(controller?.copyPathForTesting(steps: steps) ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if let steps = options.appearanceWalk {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				print("APPEARANCE \(controller?.appearanceWalkForTesting(steps) ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if options.listRunConfigurations {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				print("RUNCONFIGS\n  \(controller?.runForTesting.runConfigurationsForTesting() ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if let query = options.paletteQuery {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				print("PALETTE \(controller?.paletteCommandsForTesting(query: query) ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if let query = options.performCommand {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				print("COMMAND \(controller?.performCommandForTesting(query: query) ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if options.tabMenu {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				for over in [true, false] {
					let titles = controller?.editorForTesting.tabMenuTitlesForTesting(overTab: over) ?? []
					print("TABMENU \(over ? "tab" : "empty"): \(titles.joined(separator: " | "))")
				}
				print("LAYOUT \(controller?.editorForTesting.layoutReportForTesting() ?? "no window")")
				print("GLOBALSCRATCH \(controller?.editorForTesting.globalScratchDirectoryForTesting() ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if options.clickBelowLastLine {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				print("CLICKBELOW \(controller?.editorForTesting.clickBelowLastLineForTesting() ?? "no window")")
				fflush(stdout)
				if options.writesACapture { return }
				exit(0)
			}
		}

		if let spec = options.deadKeys {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				let presses = spec.split(separator: ",").compactMap { part -> (code: UInt16, shift: Bool)? in
					let shift = part.hasSuffix("s")
					guard let code = UInt16(shift ? part.dropLast() : part) else { return nil }
					return (code, shift)
				}
				let report = controller?.deadKeyForTesting(presses: presses)
				print("DEADKEY \(report ?? "no window")")
				// Piped output is held until the process ends, and a test that
				// is killed on a timeout takes the answer with it.
				fflush(stdout)
				// Unless a picture is being taken of what it left on screen.
				if options.writesACapture { return }
				exit(0)
			}
		}

		if let path = options.toolbarImage {
			DebugToolbarPreview.write(to: path, location: options.toolbarLocation)
			print("TOOLBAR: \(path)")
			exit(0)
		}

		if let line = options.editBreakpointLine {
			// The sheet itself, for a capture run: it is drawn by hand and a
			// hand-drawn thing cannot be checked by reading it.
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
				controller?.debugForTesting.editBreakpointForTesting(line: line)
			}
		}

		if let condition = options.breakpointCondition, let line = options.breakpointLine {
			// Before anything is running, which is when conditions are really
			// set: while writing the code, not while stopped in it.
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
				controller?.debugForTesting.setBreakpointConditionForTesting(line: line, condition: condition)
			}
		}

		if options.showBreakpointList {
			// After the file has opened and the gutter has something to click.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				controller?.reportBreakpointListForTesting(
					setting: options.breakpointLines,
					thenDebug: options.breakpointsThenDebug,
					thenExit: options.screenshotPath == nil
				)
			}
		}

		if let text = options.selectText {
			// After `--find` has had its say, so that the run which asks whether
			// find's matches win is the same shape as the one that does not.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.reportOccurrencesForTesting(
					selecting: text, thenExit: options.screenshotPath == nil
				)
			}
		}

		if let replacement = options.replaceWith {
			// After `--find` has typed its query and the debounced search has
			// run: replacing before there are matches proves nothing.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.editorForTesting.exerciseReplaceForTesting(
					query: options.findQuery ?? "",
					replacement: replacement,
					all: options.replaceAll,
					regex: options.findRegex
				)
			}
		}

		if options.findAcrossTabs {
			// After `--find` has typed its query and the debounced search has
			// run; stepping before there are matches proves nothing.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.editorForTesting.exerciseFindAcrossTabsForTesting()
			}
		}

		if options.dragTab {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.editorForTesting.dragTabForTesting()
			}
		}

		if !options.dropFiles.isEmpty {
			// After the window has a project and whatever `--file` asked for is
			// open, or "before" is a report of an empty editor.
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.dropFilesForTesting(options.dropFiles)
			}
		}

		if let offer = options.backlogOffer {
			// Before any pane is built, which is what makes the pretence
			// possible at all: the view asks once, when it is made.
			if offer == "missing" { BacklogAbsentView.pretendsTheToolIsMissing = true }
			// After the walk that reads both folders, which happens off the main
			// thread: asked sooner, every project looks like one with nothing.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				print("OFFER project: \(controller?.project?.root.path ?? "none")")
				print(controller?.backlogOfferReportForTesting() ?? "no window")
				if offer == "openspec" {
					print("OFFER pressed: " + (controller?.pressOpenSpecOfferForTesting() ?? "no window"))
				}
				fflush(stdout)
			}

			// The same pane asked again, for `--backlog-offer watch`: a record
			// of work made while it was up — by the terminal it started, or by
			// somebody in another window — should have replaced the offer with
			// a board, and the pane is not reopened in between.
			if offer == "watch" {
				// Shown, and then read a moment later. Asking is what triggers
				// the re-read — the pane reloads whenever it is shown — and the
				// walk that answers it runs off the main thread, so a report
				// printed in the same breath prints the state before it. That
				// is not a delay somebody waits: it is one dispatch away, and
				// the gap here is generous so the check cannot be flaky.
				DispatchQueue.main.asyncAfter(deadline: .now() + 9.5) {
					print("OFFER again: "
						+ (controller?.backlogOfferAsItStandsForTesting() ?? "no window"))
					fflush(stdout)
				}
			}
		}

		if let at = options.engineSwitchAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.panelForTesting.switchEngineForTesting()
			}
		}

		for at in options.engineReportsAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.panelForTesting.reportEnginesForTesting()
			}
		}

		if options.unhandledMotions {
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				controller?.editorForTesting.reportUnhandledMotionsForTesting()
			}
		}

		if let branch = options.checkoutBranch {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				controller?.codeLinksForTesting.checkoutBranchForTesting(branch, pressing: options.pressOffer)
			}
		}

		if let asked = options.copyLink {
			// After the file is open and its document is real: a reference is
			// about a tab, and there is none for the first second.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				let parts = asked.split(separator: ":").map(String.init)
				let form = parts.first ?? "reference"
				let lines = (parts.count > 1 ? parts[1] : "1")
					.split(separator: "-").compactMap { Int($0) }
				controller?.codeLinksForTesting.copyLinkForTesting(
					form, line: lines.first ?? 1, endLine: lines.count > 1 ? lines[1] : nil
				)
			}
		}

		if let link = options.followLink {
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
				controller?.codeLinksForTesting.followLinkForTesting(link)
			}
		}

		if let asked = options.codeActionsAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + asked.after) {
				controller?.serverActionsForTesting.reportCodeActionsForTesting(
					line: asked.line, character: asked.character, take: options.codeActionTake
				)
			}
		}

		if let at = options.openValueAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.openValueForTesting()
			}
		}

		for at in options.diagnosticsAt {
			DispatchQueue.main.asyncAfter(deadline: .now() + at) {
				controller?.editorForTesting.reportDiagnosticsForTesting(at: at)
			}
		}
	}
}
