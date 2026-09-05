import AppKit
import AbydosKit

/// Driving the window from the command line, continued.
///
/// The second half of `MainWindowController+Driving.swift`, split only because
/// one file of all of it is over the length limit. The seam is arbitrary and
/// says so; the first file explains why any of this is here.
extension MainWindowController {
	/// The views a press can be aimed at, which are the two paths that differ:
	/// the terminal has mouse handlers of its own, and the editor has none and
	/// passes everything up.
	func viewForMouseTesting(named name: String) -> NSView? {
		switch name {
		case "terminal": return bottomPanel.showTerminal()?.terminalView
		case "tree":     return navigator.view
		default:         return editor.view
		}
	}

	func pressForTesting(button number: Int, on view: NSView) {
		let middle = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
		let inWindow = view.convert(middle, to: nil)
		let onScreen = view.window?.convertPoint(toScreen: inWindow) ?? .zero
		let flipped = CGPoint(
			x: onScreen.x,
			y: (NSScreen.screens.first?.frame.height ?? 0) - onScreen.y
		)
		for type in [CGEventType.otherMouseDown, .otherMouseUp] {
			guard let raw = CGEvent(
				mouseEventSource: nil,
				mouseType: type,
				mouseCursorPosition: flipped,
				mouseButton: .center
			) else { continue }
			raw.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
			guard let event = NSEvent(cgEvent: raw) else { continue }
			if type == .otherMouseDown {
				view.otherMouseDown(with: event)
			} else {
				view.otherMouseUp(with: event)
			}
		}
	}

	/// Drives the project tree and reports what the editor did about it.
	///
	/// Arrowing through the tree is supposed to show each file it lands on, and
	/// that is a claim about two views at once — which is why this prints both.
	/// Selects a row in the tree and copies it the way ⌘C does, then says what
	/// landed on the pasteboard.
	///
	/// Through `NSApp.sendAction`, which is exactly what the Edit menu's Copy
	/// does: what could be wrong here is not the copying but whether the tree
	/// is ever asked, and calling the method directly would answer the wrong
	/// question. The pasteboard is put back afterwards — a test has no business
	/// throwing away whatever somebody had copied.
	func copyPathForTesting(steps: String) -> String {
		let saved = NSPasteboard.general.string(forType: .string)
		defer {
			NSPasteboard.general.clearContents()
			if let saved { NSPasteboard.general.setString(saved, forType: .string) }
		}

		navigator.focusTree()
		for step in steps.split(separator: ",") {
			switch step {
			case "down": navigator.pressKeyForTesting(125)
			// So that copying several rows can be asked for at all.
			case "shift-down": navigator.pressKeyForTesting(125, modifiers: .shift)
			default: continue
			}
		}

		let sent = NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
		let copied = NSPasteboard.general.string(forType: .string) ?? "nothing"
		// Newlines would break the one-line report into several that look like
		// separate answers.
		let onOneLine = (copied as String).replacingOccurrences(of: "\n", with: " | ")
		return "sent=\(sent) clipboard=\(onOneLine)"
	}

	/// Drives the picture in front through the View menu's **own** zoom actions,
	/// one step per word: `in`, `out`, `actual`, `fit`, `pinch:0.25`.
	///
	/// **Down the responder chain rather than by calling the pane**, and that is
	/// the whole reason this verb exists rather than `--image-fit` growing a
	/// number. What item 0537 changes is not arithmetic — `ImageFit` is tested
	/// without a window — it is *where ⌘+ arrives*: the picture pane takes the
	/// keyboard and answers `zoomIn(_:)` before the window controller does. A
	/// driver that called `pane.zoomIn(nil)` would pass with that routing removed,
	/// which makes it a test of nothing. So the report says **who took it**, and
	/// `took=ImageFileView` against `took=MainWindowController` is the whole of
	/// this item in one word.
	///
	/// It also prints the interface's zoom beside the picture's, because the
	/// claim being checked is about two numbers: one moves and the other does not.
	/// What the front tab's player is doing, in text: a driven run cannot hear
	/// autoplay, and "paused" in a report is the claim the open makes.
	func videoReportForTesting() {
		print("VIDEO: " + (editor.activeGroup?.videoPreview?.reportForTesting
			?? "nothing showing a video"))
		fflush(stdout)
	}

	func zoomImageForTesting(_ raw: String) {
		guard let pane = editor.activeGroup?.imagePreview else {
			print("IMAGE: nothing showing a picture")
			return
		}
		window?.makeFirstResponder(pane)
		var took: [String] = []
		for step in raw.split(separator: ",").map({
			$0.trimmingCharacters(in: .whitespaces).lowercased()
		}) {
			switch step {
			case "in":  took.append(sendToKeyboard(#selector(MainWindowController.zoomIn(_:))))
			case "out": took.append(sendToKeyboard(#selector(MainWindowController.zoomOut(_:))))
			case "actual":
				took.append(sendToKeyboard(#selector(MainWindowController.resetZoom(_:))))
			// The two that are not keys and so have no chain to walk: `Fit to
			// Window` lives only in the pane's own menu, and a pinch goes to the
			// view under the pointer. Said as `direct` rather than dressed up as a
			// class that answered, since nothing was asked.
			case "fit":
				pane.setFit(.pane)
				took.append("direct")
			case let pinch where pinch.hasPrefix("pinch:"):
				pane.magnify(by: CGFloat(Double(pinch.dropFirst("pinch:".count)) ?? 0))
				took.append("direct")
			default:
				print("IMAGE: --image-zoom does not know \(step)")
			}
		}
		let holder = (window?.firstResponder).map { String(describing: type(of: $0)) } ?? "nobody"
		print("IMAGE zoom: keyboard=\(holder) took=\(took.joined(separator: ",")) \(pane.reportForTesting)")
	}

	/// - Parameter thenExit: true when no picture was asked for, so the run ends
	///   when the script does.
	///
	///   **Because a script longer than a second and a half could not be
	///   written.** The steps start 1.5 s before the shutter and the shutter
	///   calls `exit`, so a longer `--delay` moved the script later rather than
	///   giving it room, and everything after the second `settle` was killed
	///   mid-flight — silently, since the process was gone. A run with no
	///   capture in it now ends on its own last step, the way the breakpoint
	///   report already does, and takes as long as its script needs.
	func treeStepsForTesting(_ steps: String, thenExit: Bool = false) {
		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			// **Flushed however the step leaves.** A driven run is killed rather
			// than ended: stdout is a pipe, nothing drains its buffer at exit,
			// and a report written after the last flushing step is simply lost.
			// `defer` rather than a line at the bottom because half these cases
			// `continue` past it — which is exactly how the losses happened.
			defer { fflush(stdout) }
			// `settle`, and `settle:3` for longer. Everything after it goes back
			// to the run loop rather than being waited for here, because the trash
			// answers on the main queue and a nested `RunLoop.run(until:)` does not
			// drain it — measured, not assumed, when a script that trashed and then
			// pressed ⌘Z found an empty stack however long it "waited".
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else {
					// A `settle` with nothing after it is a wait somebody meant,
					// so it is waited out before the run ends.
					if thenExit {
						DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
					}
					return
				}
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.treeStepsForTesting(rest, thenExit: thenExit)
				}
				return
			}

			switch step {
			case "focus": navigator.focusTree()
			// A real click on a row and who has the keyboard after it, then the
			// selection by path — the tree-behaviour claim asked of this tree
			// the way it is asked of the other three.
			case let step where step.hasPrefix("click"):
				print("TREE \(navigator.clickRowForTesting(Int(step.dropFirst("click".count)) ?? 0))")
				continue
			case "selected":
				print("TREE selected: \(navigator.selectedPathsForTesting().joined(separator: " | "))")
				continue
			// What a right-click over the selection offers, submenus included.
			case "menu":
				print("TREE menu: \(navigator.contextMenuTitlesForTesting().joined(separator: " | "))")
				continue
			// The Compare submenu's verbs on the selected row, and what the
			// editor then shows: the diff tab's title is the claim.
			case "compare-head": navigator.compareForTesting(history: false)
			case "compare-history": navigator.compareForTesting(history: true)
			case "tabs":
				print("TREE tabs: "
					+ (editor.activeGroup?.tabTitlesForTesting.joined(separator: ", ") ?? "no group"))
				continue
			case "down": navigator.pressKeyForTesting(125)
			case "up": navigator.pressKeyForTesting(126)
			case "right": navigator.pressKeyForTesting(124)
			case "left": navigator.pressKeyForTesting(123)
			case "return": navigator.pressKeyForTesting(36)
			// The four keys the navigator answers, each one a different gesture
			// from the same key without its modifier: F2 and ⌥⏎ both rename, ⌘⌫
			// trashes the selection, ⌘↓ opens as it always did.
			case "f2": navigator.pressKeyForTesting(120)
			case "alt-return": navigator.pressKeyForTesting(36, modifiers: .option)
			case "cmd-delete": navigator.pressKeyForTesting(51, modifiers: .command)
			case "cmd-down": navigator.pressKeyForTesting(125, modifiers: .command)
			case "escape": navigator.pressKeyForTesting(53)
			// Space, and what the panel it opens is showing. Two steps because
			// the panel is a window of its own and a screenshot of ours cannot
			// see it — the same reason the delete dialog is reported rather
			// than shot.
			case "space": navigator.pressKeyForTesting(49)
			case "quicklook":
				print("TREE \(navigator.quickLookReportForTesting)")
				continue
			// ⇧↓ and ⇧↑: a run of rows, selected the way somebody selects one.
			case "shift-down": navigator.pressKeyForTesting(125, modifiers: .shift)
			case "shift-up": navigator.pressKeyForTesting(126, modifiers: .shift)
			// What a build writing files does to the tree, on demand: the point
			// is what is still selected afterwards.
			case "reload": navigator.reloadForTesting()
			case "copy":
				print("TREE copy: clipboard=\(navigator.copyTextForTesting().replacingOccurrences(of: "\n", with: " | "))")
				continue
			// ⌘C for real and then ⌘V or ⌥⌘V, through the general pasteboard, so
			// what the copy writes is what the paste reads rather than two
			// closures agreeing with each other.
			case "copy-files":
				navigator.copyToPasteboardForTesting()
				continue
			case "paste": navigator.pasteForTesting(move: false)
			case "paste-move": navigator.pasteForTesting(move: true)
			// ⌘Z the way the Edit menu sends it: at nobody in particular, down the
			// responder chain from whatever has the keyboard. That is the half
			// `undo` cannot answer — which of the two stacks a ⌘Z reaches is
			// decided by the chain, so the harness has to ask the chain rather
			// than the tree.
			case "undo-key":
				// Key first: `target(forAction:)` starts at the *key* window's
				// first responder, and an app launched from a terminal need not
				// have one — which showed up as "answered by nobody" while the
				// tree plainly had the keyboard.
				NSApp.activate(ignoringOtherApps: true)
				window?.makeKeyAndOrderFront(nil)
				let selector = Selector(("undo:"))
				// The chain walked by hand as well, because it is the mechanism
				// under test and it can be named. AppKit's own answer is printed
				// beside it so the two can be seen to agree.
				var responder = window?.firstResponder
				while let step = responder, !step.responds(to: selector) {
					responder = step.nextResponder
				}
				func named(_ object: Any?) -> String {
					object.map { String(describing: type(of: $0)) } ?? "nobody"
				}
				print("TREE undo-key: chain=\(named(responder)) "
					+ "appkit=\(named(NSApp.target(forAction: selector))) "
					+ "first=\(named(window?.firstResponder))")
				// Sent the way the menu sends it, and by hand only when there is no
				// key window to send it through — either way the chain decides who
				// answers, which is the whole question.
				if !NSApp.sendAction(selector, to: nil, from: nil) {
					_ = responder?.tryToPerform(selector, with: nil)
				}
			// And the tree's own, straight at the outline view, for scripts that
			// only want the file half.
			case "undo": navigator.undoForTesting()
			// What is standing in the corner, which is where an undo that refused
			// says so.
			case "toasts":
				print("TREE \(toastReportForTesting())")
				continue
			// And the key itself, which is the half `paste-move` cannot ask
			// about: ⌥⌘V is in no menu, so `handleKeyDown` is the only thing
			// standing between the keystroke and the move.
			case "alt-cmd-v": navigator.pressKeyForTesting(9, modifiers: [.command, .option])
			case "collapse": navigator.collapseAll()
			case "locate": navigator.selectFileInEditor()
			// How far the text in front can be scrolled sideways. Here rather
			// than in `--navigate` for the same reason `type:` is: only this
			// list can put an edit and a question in a chosen order, and the
			// question is only interesting *after* something has been typed.
			//
			// A screenshot cannot answer it. An overlay scroller is invisible
			// until somebody scrolls, so "there is no scrollbar" and "there is
			// nothing to scroll to" look exactly alike in a picture — which is
			// how a document view that never grew past its pane went unnoticed.
			case "scroll":
				print("EDITOR scroll: "
					+ (editor.activeGroup?.activeCodeView?.scrollReportForTesting ?? "no code view in front"))
				continue
			// The header's third button. A row count with it off and the same
			// count with it on is the whole claim this change makes, and `rows`
			// is what says both.
			case "compact": navigator.toggleCompactPackages()
			// The Dependencies section, which is not on disk and so is the one
			// part of the tree `ls:` can say nothing about. `deps` is what the
			// section holds whether or not anything is open; `rows` is what the
			// pane is actually showing, which is the half that proves the rows
			// arrived rather than only the model.
			case "deps":
				print("TREE deps: \(navigator.dependencyReportForTesting().joined(separator: " | "))")
				continue
			case "rows":
				print("TREE rows: \(navigator.rowsForTesting().joined(separator: " | "))")
				continue
			// What the trash itself cost, which is the number this stopped
			// waiting for rather than the number it made smaller.
			case "trash-time":
				print("TREE trash took \(navigator.trashTimeForTesting)")
				continue
			// The section sits below the whole tree, which on a repository of
			// eight subprojects is several screens down.
			// Which roots the tree has, and what the third of them holds — the
			// one thing a screenshot of a tree several screens long cannot say.
			case "roots":
				print("TREE roots: \(navigator.rootsForTesting())")
			case "session-right-click":
				print("TREE session-right-click:\n    \(navigator.sessionRightClicksForTesting())")
			case "session-menu":
				print("TREE session-menu: \(navigator.sessionMenuForTesting())")
			case "sessions-rebuild": navigator.rebuildSessionsForTesting()
			case "sessions-open": navigator.openSessionsForTesting(files: false)
			case "sessions-open-all": navigator.openSessionsForTesting(files: true)
			case "deps-open": navigator.openDependenciesForTesting(groups: false)
			case "deps-open-all": navigator.openDependenciesForTesting(groups: true)
			// The field on the row, left standing: where its text sits and how
			// far it reaches are the whole of what is wrong with it, and
			// `rename:` commits too quickly to photograph.
			case "rename-begin":
				navigator.beginRename()
				print("TREE rename-begin: \(navigator.renameFieldReportForTesting)")
			default:
				// What is on disk under the project root, so "Escape left nothing
				// behind" is answered by the file system rather than by the tree
				// agreeing with itself. `ls:.` for the root, `ls:Sources` for a
				// folder inside it.
				// A file by absolute path, revealed the way activating its tab
				// does — the gesture item 508 is about, driven without a symbol
				// to follow. It prints which package the file turned out to be
				// in and where that package came from, which is what a
				// screenshot cannot say.
				if step.hasPrefix("reveal:") {
					navigator.revealForTesting(String(step.dropFirst("reveal:".count)))
					continue
				}
				// `rm:src/main.py` — the file taken out from under its row, the
				// way a terminal does it, without giving the watcher its quarter
				// of a second to notice. The row is still on screen when the next
				// step runs, which is the only way to press ⌘⌫ at a stale row on
				// purpose.
				if step.hasPrefix("rm:") {
					guard let root = project?.root else { continue }
					let doomed = root.appendingPathComponent(String(step.dropFirst("rm:".count)))
					let removed = (try? FileManager.default.removeItem(at: doomed)) != nil
					print("TREE rm \(doomed.lastPathComponent): "
						+ (removed ? "gone from disk" : "could not remove it"))
					continue
				}
				if step.hasPrefix("ls:") {
					let folder = String(step.dropFirst("ls:".count))
					guard let root = project?.root else { continue }
					let url = folder == "." ? root : root.appendingPathComponent(folder)
					let names = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
						.sorted()
					print("TREE ls \(folder): \(names.joined(separator: " "))")
					continue
				}
				// `type:abc`, into whatever the editor is showing. Here rather than
				// only in `--type` so that one script can put an edit and a file
				// gesture in a chosen order and then press ⌘Z once: which of the two
				// undo stacks answers is the question, and it cannot be asked from
				// two flags that fire at different times.
				if step.hasPrefix("type:") {
					simulateTyping(String(step.dropFirst("type:".count)))
					break
				}
				// `export:png`, the file's own context-menu action on whatever the
				// tree has selected.
				if step.hasPrefix("export:") {
					let raw = String(step.dropFirst("export:".count)).lowercased()
					let editable = raw.hasPrefix("editable-")
					guard let format = DiagramFormat(
						rawValue: editable ? String(raw.dropFirst("editable-".count)) : raw
					) else { continue }
					navigator.exportSelectionForTesting(format, editable: editable)
					continue
				}
				// `drop:a.swift+b.swift>Sources`, and `drop-copy:` for the ⌥
				// version — the whole of what a drag does once the mouse is up,
				// without a mouse. Everything is relative to the project root.
				// `paste-picture:<png>` — ⌘V over a picture, from a board the run
				// makes for itself so the general clipboard is left alone. The path
				// is the project's when relative, the machine's when absolute.
				// `line:<n>` — what a line of the open document reads, for the
				// claims a caret report cannot make: that a reference went in, or
				// that ⌘Z took it out again.
				if step.hasPrefix("line:") {
					let n = Int(step.dropFirst("line:".count)) ?? 0
					print("EDITOR line \(n): \(editor.lineTextForTesting(n))")
					continue
				}
				// `paste-picture-editor:<png>` — the same board, into the document
				// the editor is showing rather than into the tree.
				if step.hasPrefix("paste-picture-editor:") {
					let body = String(step.dropFirst("paste-picture-editor:".count))
					let picture = body.hasPrefix("/") ? URL(fileURLWithPath: body)
						: (project?.root ?? URL(fileURLWithPath: ".")).appendingPathComponent(body)
					editor.pastePictureForTesting(picture)
					continue
				}
				if step.hasPrefix("paste-picture:") {
					let body = String(step.dropFirst("paste-picture:".count))
					let picture = body.hasPrefix("/") ? URL(fileURLWithPath: body)
						: (project?.root ?? URL(fileURLWithPath: ".")).appendingPathComponent(body)
					navigator.pastePictureForTesting(picture)
					continue
				}
				if step.hasPrefix("drop:") || step.hasPrefix("drop-copy:") {
					let move = step.hasPrefix("drop:")
					let body = String(step.dropFirst(move ? "drop:".count : "drop-copy:".count))
					guard let root = project?.root, let arrow = body.firstIndex(of: ">") else { continue }
					let sources = body[..<arrow].split(separator: "+").map {
						root.appendingPathComponent(String($0))
					}
					navigator.dropForTesting(
						sources, into: root.appendingPathComponent(String(body[body.index(after: arrow)...])),
						move: move
					)
					continue
				}
				// `new-begin:file`, `new-begin:folder`, `new-begin:py` — the row
				// put in the tree with the field on it and left standing, which
				// is the half a committed name cannot show: where the row went,
				// what the field starts with, and which part of it is selected.
				if step.hasPrefix("new-begin:") {
					navigator.beginNewForTesting(kind: String(step.dropFirst("new-begin:".count)))
					print("TREE new-begin: \(navigator.renameFieldReportForTesting)")
				} else if step.hasPrefix("new:") {
					// `new:file:notes.txt`, `new:folder:docs`, `new:py:script` — the
					// whole gesture, the way `rename:` is: the row appears, takes
					// the name, and Return writes it. A kind fills the extension
					// in, so `new:py:script` makes `script.py`.
					let parts = step.dropFirst("new:".count).split(separator: ":", maxSplits: 1)
					guard let kind = parts.first else { continue }
					navigator.createSelectionForTesting(
						kind: String(kind), name: parts.count > 1 ? String(parts[1]) : nil
					)
				} else {
					// `rename:new-name.swift`, which is the whole gesture: the field
					// appears on the row, takes the name, and commits it.
					guard step.hasPrefix("rename:") else { continue }
					navigator.renameSelectionForTesting(String(step.dropFirst("rename:".count)))
				}
			}
			let selection = navigator.selectionForTesting
			let showing = editor.activeGroup?.activeTabURL?.lastPathComponent ?? "nothing"
			// Arrowing shows a file without leaving the tree, so which pane has
			// the keyboard is what separates Return opening a file from Return
			// merely selecting one — and `renaming` is what separates it from
			// Return doing what it did last week.
			let renaming = navigator.renamingNameForTesting
			let focus: String
			if renaming != nil {
				focus = "rename-field"
			} else if let responder = window?.firstResponder as? NSView {
				if responder.isDescendant(of: navigator.view) {
					focus = "tree"
				} else if responder.isDescendant(of: editor.view) {
					focus = "editor"
				} else {
					focus = "elsewhere"
				}
			} else {
				focus = "elsewhere"
			}
			print(
				"TREE \(step): selected=\(selection.name) rows=\(selection.rows) "
					+ "editor=\(showing) focus=\(focus) renaming=\(renaming ?? "no")"
			)
		}
		// The script has run out. A run with a picture coming waits for the
		// shutter to end it; one without would otherwise sit with a window open
		// until something killed it.
		if thenExit {
			fflush(stdout)
			exit(0)
		}
	}

	/// Whether the terminal panel is showing, what is in it, and what the pane in
	/// front last said — for 0444's part 4, whose whole claim is about a pane that
	/// appears without being asked for and must not be asked for again to be seen.
	/// ⌘⇧] and ⌘⇧[ with the keyboard in the panel, then in the editor, for
	/// `--next-tab-in-panel`. The strip is read after each press, with its
	/// active tab starred, so the report says where the keys went.
	func exerciseNextTabForTesting() {
		bottomPanel.selectAndFocusTabForTesting(0)
		let inPanel = isTerminalFocused
		let before = bottomPanel.tabsForTesting
		selectNextTab(nil)
		let forward = bottomPanel.tabsForTesting
		selectPreviousTab(nil)
		let back = bottomPanel.tabsForTesting
		editor.focusForTesting()
		let inEditor = !isTerminalFocused
		selectNextTab(nil)
		print("NEXTTAB: panel focused=\(inPanel) before=[\(before)] next=[\(forward)] previous=[\(back)]")
		print("NEXTTAB: editor focused=\(inEditor) panel=[\(bottomPanel.tabsForTesting)]")
	}

	func panelTabsForTesting(tail: Int = 0) -> String {
		var said = "PANEL: visible=\(isPanelVisible) \(bottomPanel.tabsForTesting)"
		if tail > 0 { said += "\n  last: " + bottomPanel.activeTerminalTailForTesting(lines: tail) }
		return said
	}

	/// Which project the window is on, and what it has open.
	///
	/// Beside the terminal's directory rather than instead of it, because 0509 is
	/// exactly the two disagreeing: a shell that never moved, and a window that
	/// left the project anyway. One of the two numbers alone says nothing — the
	/// directory is right in both builds, and a project name on its own cannot be
	/// told from a window that was opened on that project to begin with. The tabs
	/// are here because they are what the switch destroys.
	func projectReportForTesting() -> String {
		let root = project?.root.lastPathComponent ?? "none"
		let scope = subprojectRoot?.lastPathComponent ?? "whole"
		let titles = editor.activeGroup?.tabTitlesForTesting ?? []
		return "project=\(root) subproject=\(scope) tabs=[\(titles.joined(separator: " "))]"
	}

	/// Opens the run list and prints what is in it.
	///
	/// **This used to print a menu it built and threw away**, because opening
	/// the real one was what a capture run could not do: an `NSMenu` runs a
	/// nested event loop, so the window was never drawn, the screenshot never
	/// taken, and the run had to be killed — taking the output with it. A
	/// popover does not do that, so the harness can now open the thing somebody
	/// actually sees instead of a second copy of it that was free to drift.
	func showConfigurationMenuForTesting(open goal: String? = nil) {
		// The destinations first, because they are the part worth checking and
		// they arrive about twelve seconds after the menu is drawn — printing
		// before they land prints "Finding destinations…" and proves nothing.
		Task { @MainActor in
			// And discovery before that. A reactor of a hundred modules is a
			// walk of some seconds, and a run that printed at 1.2 s printed
			// "No configurations yet" whatever the project held — which is a
			// harness that cannot tell an empty project from a slow one.
			// Generous: a reactor of a hundred and eighty modules takes 94 s to
			// walk, measured, and most of that is the 45,772 Java files the main
			// classes are found in.
			let deadline = Date().addingTimeInterval(240)
			while self.run.runConfigurations.isEmpty, Date() < deadline {
				try? await Task.sleep(for: .milliseconds(200))
			}

			for configuration in self.run.runConfigurations where configuration.source == .xcodeScheme {
				guard let target = configuration.xcode else { continue }
				_ = await XcodeDestinations.shared.destinations(
					for: target,
					workingDirectory: URL(fileURLWithPath: configuration.workingDirectory)
				)
			}
			self.run.printConfigurationMenuForTesting(open: goal)
		}
	}

	/// What is drawn in an item's mark column, as something printable.
	///
	/// The two marks are the point of the dump: ▶ is the run glyph, on the
	/// things a click starts, and ✓ is the tick that still means "this one is
	/// selected". A list where they are muddled is the bug, and a picture of a
	/// menu is not something a test can read.
	private func markForTesting(_ item: NSMenuItem) -> String {
		guard item.state == .on else { return "" }
		return item.onStateImage === RunCoordinator.runMark() ? " ▶" : " ✓"
	}



	/// Sets a breakpoint as a gutter click would, for verifying alignment.
	/// Presses stop, as the titlebar button does.
	func stopRunningForTesting() { run.stopRunning() }

	/// Presses a key with Option held in the terminal, and says what it sent.
	func optionKeyForTesting(bare: String, composed: String) -> String {
		setPanelVisible(true)
		return bottomPanel.optionKeyForTesting(bare: bare, composed: composed)
	}

	/// Feeds the terminal a burst of frames, as a program running unwatched does.
	func burstForTesting(frames: Int) -> Int {
		setPanelVisible(true)
		return bottomPanel.burstForTesting(frames: frames)
	}

	/// Presses keys by key code in the terminal, and says what each one did.
	func deadKeyForTesting(presses: [(code: UInt16, shift: Bool)]) -> String {
		setPanelVisible(true)
		return bottomPanel.deadKeyForTesting(presses: presses)
	}

	/// Invokes the gutter's run action, for verifying it end to end.
	func runLineForTesting(_ line: Int) {
		guard let url = editor.activeGroup.activeTabURL else { return }
		run.runConfiguration(forFile: url, line: line)
	}

	/// Presses Run twice on whatever is selected, and says what the panel is
	/// holding after each — the whole question being whether that is one
	/// console or two.
	func rerunSelectedForTesting(_ goal: String?) {
		if let goal { run.chooseMakeRunForTesting(goal) }
		runSelected(nil)
		DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
			guard let self else { return }
			print("RERUN: after one run \(self.bottomPanel.runConsolesForTesting)")
			self.runSelected(nil)
			DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
				print("RERUN: after two runs \(self.bottomPanel.runConsolesForTesting)")
			}
		}
	}

	/// Opens the first value on the stopped line that has anything under it, and
	/// says what came back — for `--open-value`.
	///
	/// Through the same callback the click uses, so what is driven is what a
	/// click does. The count either side is the claim that drawing asks the
	/// adapter for nothing: scrolling a stopped file with values beside every
	/// line must not move it.
	func openValueForTesting() {
		guard let session = debugSession else { return print("VALUE: no session") }
		let before = session.childrenRequestsForTesting
		editor.scrollStoppedFileForTesting()
		print("VALUE: children requests after scrolling = \(session.childrenRequestsForTesting - before)")
		guard let opened = editor.openFirstInlineValueForTesting() else {
			print("VALUE: nothing on the stopped line can be opened")
			// The pane's tree is there regardless, and it is checked regardless:
			// this early return is why the pane's own selection bug was driven
			// and never seen.
			bottomPanel.walkThePaneForTesting()
			return
		}
		print("VALUE: opened \(opened)")
		// The fetch is a `Task`; give it the hop it needs before reading.
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
			guard let self else { return }
			print("VALUE: children requests total = \(session.childrenRequestsForTesting - before)")
			print("VALUE tree:\n\(self.editor.openValueReportForTesting())")
			// A value with nothing under it is a piece of text, and a click on
			// it belongs to the editor.
			print("VALUE leaf: \(self.editor.inlineValueClickForTesting(named: "stage"))")
			// And a field inside it, which is the second request and the first
			// one that was not made until somebody reached for it.
			print("VALUE expand: \(self.editor.expandInsideOpenValueForTesting())")
			print("VALUE \(self.editor.openValueMenuForTesting())")
			// The arrows, on the window that opened: down onto the field.
			print("VALUE walk down: \(self.editor.walkOpenValueForTesting(["down"]))")
			// Down onto a field, then → to open it: the case where the
			// selection used to be lost, read after the children arrive.
			// → on a row whose children have never been fetched: the branch
			// that reloads the tree, and the one that lost the selection.
			self.editor.walkOpenValueThenSettleForTesting(["right"]) { after in
				print("VALUE right on a fresh field, once its children arrived: \(after)")
				fflush(stdout)
			}
			print("VALUE placement: \(self.editor.openValueReportForTesting().split(separator: "\n").first ?? "")")
			print("VALUE selection: \(self.editor.openValueSelectionColourForTesting())")
			// And the panel's own tree, which never had the keyboard either.
			bottomPanel.walkThePaneForTesting()

			// And letting the program go takes it away, which is the other half
			// of what makes this safe to leave open.
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
				print("VALUE after expanding: requests = \(session.childrenRequestsForTesting - before)")
				print("VALUE tree:\n\(self.editor.openValueReportForTesting())")
				fflush(stdout)

				// And letting the program go takes it away, which is the other
				// half of what makes this safe to leave open.
				session.resume()
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
					print("VALUE after resuming: \(self.editor.openValueReportForTesting())")
					fflush(stdout)
				}
			}
		}
	}

	/// Presses ⌃Space on an empty line and says what came back.
	///
	/// An empty line on purpose: with nothing typed there is no prefix, which is
	/// the case the typing rule can never answer and the whole reason the key
	/// exists. What it must never print here is nothing at all.
	func exerciseExplicitCompletionForTesting() {
		editor.moveCaretToEndForTesting()
		editor.simulateTyping("\n")
		serverActions.completeAtCaret(nil)
		// Twice, a second apart: the first says whether anything appeared at
		// all, the second whether what appeared was the answer or the notice.
		// A server asked cold answers some way after it is asked.
		for delay in [1.0, 6.0] {
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
				guard let self else { return }
				print("COMPLETENOW +\(delay)s: \(self.editor.completionReportForTesting)")
				fflush(stdout)
			}
		}
	}

	/// Drives the editor's real text-input path, so a capture run exercises the
	/// same code a keystroke does rather than poking the buffer directly.
	func simulateTyping(_ text: String) {
		editor.simulateTyping(text)
	}

	/// Opens the debug pane with nothing running and says what its list holds.
	///
	/// The claim is that there is a pane to open at all: it used to be built only
	/// by a session starting, so the rail's ladybird had nothing to show and
	/// asked how to start one instead.
	/// - Parameter thenExit: false when a shot has been asked for, since a run
	///   that quit before the shutter would photograph nothing.
	func reportBreakpointListForTesting(setting lines: [Int], thenDebug: Bool, thenExit: Bool = true) {
		for line in lines { debug.toggleBreakpointForTesting(line: line) }
		showDebugPanel(nil)
		sayBreakpointList("empty")

		guard thenDebug else {
			if thenExit { exit(0) }
			return
		}

		// A session starting while the empty pane is open must take it over
		// rather than leave two: `makeDebugSession` closes an existing debug pane
		// before installing its own, and an empty one is not special.
		goDebug(nil)
		DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
			self?.sayBreakpointList("debugging")
			exit(0)
		}
	}

	private func sayBreakpointList(_ when: String) {
		let pane = bottomPanel.activeDebugPane
		print("BREAKPOINTS \(when): pane=\(pane == nil ? "none" : "open")"
			+ " panes=\(bottomPanel.debugPaneCountForTesting)"
			+ " session=\(bottomPanel.activeDebugSession == nil ? "none" : "running")")
		print("BREAKPOINTS \(when) list: \(pane?.breakpointList.reportForTesting ?? "no pane")")
		fflush(stdout)
	}

	/// Selects a string and says which other places lit up because of it.
	///
	/// Two prints, half a second apart: the scan is debounced like every other
	/// one here, and a report taken the instant the selection is made would show
	/// an empty list and prove nothing.
	/// - Parameter thenExit: false when a shot has been asked for, since the
	///   claim this makes is about what something looks like and a run that quit
	///   before the shutter would photograph nothing.
	func reportOccurrencesForTesting(selecting text: String, thenExit: Bool = true) {
		let found = editor.selectTextForTesting(text)
		print("OCCURRENCES selected=\(found ? "yes" : "not found") \(editor.occurrenceReportForTesting)")
		fflush(stdout)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
			guard let self else { return }
			print("OCCURRENCES settled: \(self.editor.occurrenceReportForTesting)")
			fflush(stdout)
			if thenExit { exit(0) }
		}
	}

	/// Replaces from the find bar and says what happened, for a driven run.
	func replaceForTesting(query: String, replacement: String, all: Bool, regex: Bool) -> String {
		editor.replaceForTesting(query: query, replacement: replacement, all: all, regex: regex)
	}

	/// The file as it now reads, for saying what a replace made of it.
	var textForTesting: String? { editor.textForTesting }

	/// Walks a sequence of theme settings and says what each one resolved to.
	///
	/// The sequence is the point: switching to "system" after a fixed theme is
	/// the case that was broken, and asking about "system" on its own would
	/// never have shown it — the app only answers with the appearance it was
	/// forced once something has forced one.
	func appearanceWalkForTesting(_ steps: String) -> String {
		var said: [String] = ["system is \(Theme.systemIsDark ? "dark" : "light")"]
		for step in steps.split(separator: ",") {
			Settings.shared.appearance = String(step)
			Theme.apply()
			said.append("\(step) → \(Theme.current.name)")
		}
		return said.joined(separator: " | ")
	}

	/// What the palette offers for a query, with the keys each answers to.
	///
	/// Read from the menus, which is where they come from: a list that says how
	/// many there are and what they are called is the only way to see that a
	/// command added to a menu arrived here without anybody doing anything.
	func paletteCommandsForTesting(query: String) -> String {
		// Menu validation answers about the responder chain of the key window,
		// so a run that never came to the front sees every item disabled and
		// the palette reports nothing at all.
		NSApp.activate(ignoringOtherApps: true)
		window?.makeKeyAndOrderFront(nil)

		let commands = CommandSearch.match(MenuCommands.all().map(\.descriptor), query: query)
		let lines = commands.prefix(12).map { command in
			"  \(command.qualifiedTitle)\(command.shortcut.map { "  [\($0)]" } ?? "")"
		}
		return "\(commands.count) commands\n" + lines.joined(separator: "\n")
	}

	func showBranchMenuForTesting() { showBranchMenu() }

	/// Hands the window's inbox a draft for a named project, as a late answer
	/// from `claude` does, and says where it went.
	///
	/// The pane on screen is asked to apply it afterwards, which is what
	/// happens in earnest: a pane whose own root does not match declines and
	/// the draft stays in the inbox for the project that asked.
	func deliverDraftForTesting(root path: String) -> String {
		let root = URL(fileURLWithPath: path)
		drafts.hold(
			ClaudeDraft.Draft(
				summary: "feat: drafted for \(root.lastPathComponent)",
				description: "Belongs to \(root.lastPathComponent)."
			),
			for: root
		)
		sidebar.applyHeldDraftsForTesting()
		return "held for \(root.lastPathComponent); "
			+ "window is on \(project?.root.lastPathComponent ?? "none")"
	}

	/// Puts the pointer on a named chrome control and says whether it lit and
	/// what its tip would tell somebody.
	///
	/// One door for the four areas, because it is one gesture: `rail:git`,
	/// `header:collapse`, `run:debug`, and a bare name for the terminal
	/// strip's own trailing controls, which had this first.
	func hoverChromeForTesting(_ name: String) -> String {
		let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
		guard parts.count == 2 else { return bottomPanel.hoverStripControlForTesting(name) }
		switch parts[0] {
		case "rail":   return "rail " + toolStrip.hoverToolForTesting(parts[1])
		case "header": return "header " + navigator.hoverHeaderActionForTesting(parts[1])
		case "run":    return "run " + (run.runControl?.hoverPartForTesting(parts[1]) ?? "no run control")
		case "strip":  return bottomPanel.hoverStripControlForTesting(parts[1])
		default:       return "no area called \(parts[0])"
		}
	}
}
