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

	func treeStepsForTesting(_ steps: String) {
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
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.treeStepsForTesting(rest)
				}
				return
			}

			switch step {
			case "focus": navigator.focusTree()
			// What a right-click over the selection offers, submenus included.
			case "menu":
				print("TREE menu: \(navigator.contextMenuTitlesForTesting().joined(separator: " | "))")
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
	}

	/// Everything 0428 asks a running window for, printed in one place.
	///
	/// One report rather than a flag per number, because these have to be read
	/// together: a "time to something usable" of four seconds means one thing
	/// beside a tree of 400 rows and another beside a tree of 40,000, and the
	/// load average has to sit next to both or neither can be argued with later.
	func scaleReportForTesting(typing presses: Int) {
		// First, and the whole path. Driving this app with `--open` has come up
		// on something from the recent list before now, and a set of timings
		// labelled "platform" that were taken on whatever was open last is
		// worse than no timings: they look like an answer. A harness can refuse
		// to believe the rest of this report unless this line names what it
		// asked for.
		print("OPEN project \(project?.root.path ?? "nothing")")
		for line in LaunchClock.report() { print(line) }
		for line in navigator.scaleReportForTesting() { print(line) }
		// Beside the watcher's batches, because the pair is the finding: before
		// 0446 these were the same number, and the whole of the fix is the
		// distance between them.
		let runs = RunCoordinator.runConfigurationTallyForTesting
		print(String(format: "OPEN %-24s %8d asked, %d skipped, %d coalesced, %d walked",
			("run configurations" as NSString).utf8String!,
			runs.asked, runs.skipped, runs.coalesced, runs.walked))

		if presses > 0 {
			let costs = editor.measureTypingForTesting(presses: presses)
			if costs.isEmpty {
				print("OPEN keystroke                no file open")
			} else {
				let walls = costs.map { $0.wall }.sorted()
				let cpus = costs.map { $0.cpu }.sorted()
				// Median and worst, not the mean. The mean of a hundred
				// keystrokes hides the one that took 300 ms, and the one that
				// took 300 ms is the entire complaint.
				func at(_ values: [TimeInterval], _ fraction: Double) -> Double {
					values[min(values.count - 1, Int(Double(values.count) * fraction))] * 1000
				}
				print(String(format: "OPEN keystroke wall       %8.2f ms median, %.2f ms p90, %.2f ms worst",
					at(walls, 0.5), at(walls, 0.9), walls.last! * 1000))
				print(String(format: "OPEN keystroke cpu        %8.2f ms median, %.2f ms p90, %.2f ms worst",
					at(cpus, 0.5), at(cpus, 0.9), cpus.last! * 1000))
			}
		}

		// The main thread going away is what "usable" fails to be, so the worst
		// of them are printed with the numbers rather than left in the log.
		for stall in StallWatch.worst(limit: 8) { print("OPEN stall \(stall.line)") }
	}

	/// What switching to another project costs, in the one number that matters:
	/// how long the main thread is gone.
	///
	/// The complaint is not that a large project takes a while to finish
	/// arriving — it is that the window stops answering while it does, so
	/// switching between projects "feels like it crashed" and the terminal
	/// stops drawing with it. The wall time around `switchProject` *is* that
	/// number: it runs on the main thread, so nothing else can happen inside it.
	///
	/// The stalls are printed beside it because the total says a switch was
	/// slow and `StallWatch` says which part of it was, which is the difference
	/// between a number and a lead.
	func measureProjectSwitchForTesting(to root: URL) {
		StallWatch.clear()
		let before = Date()
		switchProject(to: root)
		let elapsed = Date().timeIntervalSince(before) * 1000

		print(String(format: "SWITCH main thread held    %8.2f ms", elapsed))
		// The load beside the number, which the house rules ask for: a timing
		// without it cannot be told from a regression.
		var average = [Double](repeating: 0, count: 3)
		getloadavg(&average, 3)
		print(String(format: "SWITCH load                %.2f %.2f %.2f",
			average[0], average[1], average[2]))

		// After the run loop has turned a few times: the work this is about
		// finishing off the main thread is exactly the work that would not show
		// up in a reading taken the instant the call returned.
		DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
			for stall in StallWatch.worst(limit: 8) { print("SWITCH stall \(stall.line)") }
			// What arrived after the switch returned. The point of moving the
			// walks off the main thread is that these land *later*, so a reading
			// that did not check them would be measuring the app forgetting to
			// do the work rather than doing it elsewhere.
			print("SWITCH deps \(self.navigator.dependencyReportForTesting().joined(separator: " | "))")
			print("SWITCH settled")
			// Flushed, because stdout to a pipe is block-buffered and a harness
			// that kills the app when it has seen enough would otherwise lose
			// every line written after the last flush — which is all of these.
			fflush(stdout)
		}
	}

	/// Asks the language server a real question, over and over, until it answers.
	///
	/// 0428's missing number — *time until Java answers* — and the reason it went
	/// missing twice over. Once because the app was burning eight cores beside
	/// the server, so any figure would have described the app rather than the
	/// server; 0446 fixed that. And once because there was no way to ask: every
	/// other driver flag puts one question at a fixed delay, which can only tell
	/// you whether the delay happened to be long enough. On a Tycho reactor the
	/// honest answer is minutes, and a twelve-second `--lsp-wait` reports silence
	/// from a server that was working perfectly well.
	///
	/// Three questions rather than one, because they become answerable at
	/// different moments and the distance between them is the finding. An outline
	/// of the open file needs only that file parsed; completion and
	/// go-to-definition need the classpath, which for jdtls means the reactor
	/// imported. A server that answers the first at once and the last at four
	/// minutes is a very different thing to wait for than one that answers
	/// nothing until it is ready.
	///
	/// **And two more, for the debugger**, which is 0452's question and could not
	/// be asked either: whether the adapter inside the server is listening, and
	/// whether the import has got far enough to say what a launch would *run*.
	/// Taken on the same run as the file questions on purpose — one machine, one
	/// load — so that "the adapter was ready at fifty seconds while completion
	/// was still silent at eleven minutes" is a comparison rather than two
	/// readings from two afternoons.
	///
	/// **In a loop of their own, and that is not tidiness.** The first reading
	/// taken here put all five in one round and reported the adapter at 50.6
	/// seconds — five milliseconds after the outline, in the same round, which is
	/// the shape of a number bounded by its neighbours rather than measured. A
	/// round is as slow as the slowest question in it, `completion` was timing out
	/// at thirty seconds a go, and the adapter had very likely been listening for
	/// most of that. Two loops, one request each, and the two figures are then
	/// about the two things.
	///
	/// The file questions are asked together each round so a round costs one
	/// request timeout rather than three, and the granularity of every figure
	/// below is therefore the round — a second, plus however long the server took
	/// to refuse.
	func measureFirstAnswerForTesting(line: Int, character: Int, deadline: TimeInterval) {
		guard let project else {
			print("ANSWER no project")
			fflush(stdout)
			return
		}
		let position = LSPPosition(line: line, character: character)

		func say(_ what: String, _ detail: String) {
			let at = Date().timeIntervalSince(LaunchClock.processStart)
			print(String(format: "ANSWER %-16s %8.0f ms  %@  (%@)",
				(what as NSString).utf8String!, at * 1000,
				detail as NSString, LaunchClock.loadSaid as NSString))
			fflush(stdout)
		}

		func silence(_ what: String, _ waited: TimeInterval) {
			print(String(format: "ANSWER %-16s      —     still silent at %.0f s",
				(what as NSString).utf8String!, waited))
			fflush(stdout)
		}

		/// The file on screen, once the editor has finished opening it. On a large
		/// project the window arrives before the file does.
		func onScreen() -> (url: URL, languageId: String)? {
			guard let url = editor.activeGroup?.activeTabURL,
			      let languageId = editor.activeGroup?.activeDocument?.languageId
			else { return nil }
			return (url, languageId)
		}

		// What the editor asks for.
		Task { @MainActor in
			var outline = false, completion = false, definition = false
			while !(outline && completion && definition),
			      Date().timeIntervalSince(LaunchClock.processStart) < deadline {
				guard let (url, languageId) = onScreen() else {
					try? await Task.sleep(nanoseconds: 500_000_000)
					continue
				}

				let service = LanguageService.shared
				// The file's own root, not the scope. Measuring against the
				// scope would time a server that was never going to answer
				// about this file — which is the fault this verb is being used
				// to check, measured wrongly.
				let root = service.root(for: url, languageId: languageId, project: project.root)
				async let symbols = service.documentSymbols(url: url, languageId: languageId, project: root)
				async let completions = service.completions(
					url: url, position: position, languageId: languageId, project: root)
				async let locations = service.definition(
					url: url, position: position, languageId: languageId, project: root)
				let (foundSymbols, foundCompletions, foundLocations) =
					await (symbols, completions, locations)

				if !outline, !foundSymbols.isEmpty {
					outline = true
					say("outline", "\(foundSymbols.count) symbols in \(url.lastPathComponent)")
				}
				if !completion, !foundCompletions.isEmpty {
					completion = true
					say("completion", "\(foundCompletions.count) suggestions")
				}
				if !definition, let first = foundLocations.first {
					definition = true
					say("definition", first.url?.lastPathComponent ?? "somewhere")
				}
				try? await Task.sleep(nanoseconds: 1_000_000_000)
			}

			// Silence is a result and has to be printed as one. A missing line
			// reads as a harness that crashed; "still silent at 300 s" is the
			// answer to the question that was asked.
			let waited = Date().timeIntervalSince(LaunchClock.processStart)
			for (what, answered) in [
				("outline", outline), ("completion", completion), ("definition", definition),
			] where !answered { silence(what, waited) }
			print(String(format: "ANSWER done               %8.0f ms  %@", waited * 1000,
				LaunchClock.loadSaid as NSString))
			fflush(stdout)
		}

		// What the debugger asks for, on its own clock.
		Task { @MainActor in
			var adapter = false, classpath = false
			while !(adapter && classpath),
			      Date().timeIntervalSince(LaunchClock.processStart) < deadline {
				guard let open = onScreen() else {
					try? await Task.sleep(nanoseconds: 500_000_000)
					continue
				}
				// A file that is open and is not Java: nothing here hosts an
				// adapter, so these are not questions this project can be asked.
				// Left unsaid rather than reported as silence, which would put two
				// lines about a debugger at the end of every run that was not
				// about Java.
				guard open.languageId == "java" else { return }
				let url = open.url
				let ready = await LanguageService.shared
					.javaDebugReadinessForTesting(
						url: url,
						project: LanguageService.shared.root(
							for: url, languageId: open.languageId, project: project.root
						)
					)
				if !adapter, let port = ready.port {
					adapter = true
					say("debug adapter", "listening on port \(port)")
				}
				// An answer with nothing in it is an answer, and it is reported as
				// one. jdtls does that on a Tycho bundle — promptly, and for ever —
				// and a harness that counted it as silence would report a wait that
				// was never going to end as a wait.
				if !classpath, let count = ready.classPaths {
					classpath = true
					say("debug classpath", count == 0
						? "answered, and empty — nothing to launch a JVM with"
						: "\(count) entries")
				}
				try? await Task.sleep(nanoseconds: 1_000_000_000)
			}

			let waited = Date().timeIntervalSince(LaunchClock.processStart)
			for (what, answered) in [("debug adapter", adapter), ("debug classpath", classpath)]
			where !answered { silence(what, waited) }
		}
	}

	/// Whether the terminal panel is showing, what is in it, and what the pane in
	/// front last said — for 0444's part 4, whose whole claim is about a pane that
	/// appears without being asked for and must not be asked for again to be seen.
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
}
