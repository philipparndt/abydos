import AppKit
import AbydosKit

/// The verbs that drive the editor from the command line.
///
/// They were on `MainWindowController` because that is where the launch flag
/// arrives, not because they are the window's: every one of these reaches only
/// into the editor area, and each had to be handed the editor to do it. Sitting
/// there they were part of why 13,030 lines could not be broken up — a driving
/// verb declared away from its subject holds that subject's state open for
/// everybody.
///
/// Declared here they are the editor's own, and `MainWindowController` no
/// longer forwards them: `AppDelegate` reaches `editorForTesting` and asks
/// directly.
extension EditorAreaController {
	func openForTesting(_ url: URL) { open(fileURL: url, focusEditor: true) }

	var activeGroupIDForTesting: UUID? { activeGroupID }

	var tabCountForTesting: Int { activeTabCount }

	/// Types a small block the way somebody would, and prints the result.
	///
	/// Through the editor's own insertion path, so what is measured is what
	/// return actually does rather than what the indent rules would say.
	func exerciseReturnIndentForTesting() {
		moveCaretToEndForTesting()
		simulateTyping("\n")

		// A function, its body, and a nested block — typed exactly as somebody
		// would, with no manual indentation at all.
		simulateTyping("func demo() {")
		simulateReturn()
		simulateTyping("if ready {")
		simulateReturn()
		simulateTyping("run()")
		simulateReturn()
		simulateTyping("}")
		simulateReturn()
		simulateTyping("}")

		print("RETURN:")
		for line in textTailLinesForTesting(6) {
			print("RETURN: |\(line)|")
		}
	}

	/// Find, in every tab, and then the gesture the report is about.
	///
	/// Search in the file in front, switch to the next tab, and step — which is
	/// where one file's offsets used to reach another file's view.
	func exerciseFindAcrossTabsForTesting() {
		print("FIND before:\n\(activeGroup?.findReportForTesting ?? "no group")")
		fflush(stdout)

		activeGroup?.selectNextTab(offset: 1)
		print("FIND after switch:\n\(activeGroup?.findReportForTesting ?? "no group")")
		fflush(stdout)

		// The step. Before this change it used the group's matches, which were
		// the *other* file's.
		activeGroup?.findNext()
		print("FIND after step:\n\(activeGroup?.findReportForTesting ?? "no group")")
		fflush(stdout)

		// And back, to show the first tab kept what it was doing.
		activeGroup?.selectNextTab(offset: -1)
		print("FIND back:\n\(activeGroup?.findReportForTesting ?? "no group")")
		fflush(stdout)

		// Closing the searched tab takes its find state with it, because the
		// state lives on the tab. Asserted rather than assumed: state that
		// outlived its tab is what this change is about.
		if let url = activeGroup?.activeTabURL {
			_ = activeGroup?.closeTab(showing: url)
		}
		print("FIND after close:\n\(activeGroup?.findReportForTesting ?? "no group")")
		fflush(stdout)
		exit(0)
	}

	/// Drags a tab onto the group's right-hand zone, the way another group would.
	///
	/// **The regression check for the drop path**, which this change edited: a
	/// file drag and a tab drag now arrive at the same `performDragOperation`,
	/// and the tab must still split. Driven rather than tested because
	/// `EditorTabDrag` lives in the app target, where the suite cannot reach it.
	func dragTabForTesting() {
		guard let group = activeGroup, let target = group.view as? EditorDropView else {
			print("TABDRAG: no drop view")
			fflush(stdout)
			return
		}
		print("TABDRAG before: groups=\(groupCountForTesting)"
			+ " tabs=[\(openTabNamesForTesting)]")

		let payload: [String: Any] = [
			"group": group.groupID.uuidString, "index": 0,
			"path": group.activeTabURL?.path ?? "",
		]
		let board = NSPasteboard(name: .init("dev.abydos.tabdrag-test"))
		board.clearContents()
		board.setData(
			try? JSONSerialization.data(withJSONObject: payload),
			forType: EditorTabDrag.pasteboardType
		)

		// Well to the right, which is the zone that splits — **in window
		// coordinates**, because `updateZone` converts `draggingLocation` from
		// nil, which is the window. Handing it view coordinates put the point in
		// the centre zone, and a centre drop onto a tab's own group is refused
		// by design: the first run of this read as a broken split and was a
		// broken harness.
		let inView = NSPoint(x: target.bounds.width * 0.9, y: target.bounds.midY)
		let drag = TestingDrag(pasteboard: board, at: target.convert(inView, to: nil))
		let offered = target.draggingEntered(drag)
		print("TABDRAG offered: \(offered.contains(.move) ? "move" : "other")")
		_ = target.performDragOperation(drag)
		fflush(stdout)

		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
			guard let self else { return }
			print("TABDRAG after: groups=\(self.groupCountForTesting)")
			fflush(stdout)
			exit(0)
		}
	}

	/// Which server root the file in front is filed under, for `--lsp-root`.
	func serverRootReportForTesting() -> String {
		activeGroup?.serverRootReportForTesting ?? "no group"
	}

	/// `--find-next`: ⌘G with the keyboard back in the code. Says where the
	/// keyboard ended up, since that is the whole claim the picture it is taken
	/// for makes — the same reason `selectLinesForTesting` reports it.
	func findNextFromEditorForTesting(_ times: Int) {
		findNextFromEditor(times)
		// `view.window` here, where the window controller said `window`: the
		// editor area is in that same window, and it is the keyboard this
		// reports on rather than the window itself.
		let responder = view.window?.firstResponder
		print("FIND NEXT \(times) keyboard=\(responder.map { String(describing: type(of: $0)) } ?? "nothing")")
		fflush(stdout)
	}

	/// Follows ⌘-click, through the same path the click takes.
	func exerciseGoToDefinitionForTesting(line: Int, character: Int) {
		let before = activeGroup?.activeTabURL?.lastPathComponent ?? "nothing"
		goToDefinitionForTesting(line: line, character: character)
		DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
			guard let self else { return }
			let landed = self.activeGroup?.activeTabURL
			let after = landed?.lastPathComponent ?? "nothing"
			print("DEFINITION: \(before) → \(after) \(self.caretReportForTesting)")
			// The whole path, and not decoration: a server running inside a
			// devcontainer answers about /workspaces/…, and what has to arrive
			// here is the same file named as this machine names it. A report
			// giving only the last component cannot tell the two apart.
			print("DEFINITION-PATH: \(landed?.path ?? "nothing")")
			// Flushed, because the run that asks this is usually killed rather
			// than allowed to exit: a `--lsp-wait` long enough for sourcekit-lsp
			// to index a package leaves the driver's `timeout` to end the app,
			// and an unflushed buffer dies with it. Two runs of this verb
			// reported nothing at all for exactly that reason.
			fflush(stdout)
		}
	}

	/// Runs a tab's close command and prints what is left.
	func closeTabsForTesting(_ command: String, at index: Int) {
		guard let group = activeGroup else { return }
		group.closeTabsForTesting(command, at: index)
		print("TABS: \(group.tabTitlesForTesting.joined(separator: ", "))")
	}

	/// Exports the diagram in front from its own preview pane, the way the
	/// pane's menu does, and says what the menu offered on the way past.
	func exportDiagramForTesting(_ raw: String) {
		// `--export editable-png` is the second gesture in the same menu: the
		// picture that is also the document, `x.drawio.png`.
		let asked = raw.lowercased()
		let editable = asked.hasPrefix("editable-")
		guard let format = DiagramFormat(
			rawValue: editable ? String(asked.dropFirst("editable-".count)) : asked
		) else {
			print("EXPORT: no such format \(raw)")
			return
		}
		// A rendered Markdown document is a diagram pane too, in the only sense
		// that matters here: it has an `Export ▸` on it and writing the pictures
		// out is one act however many fences the document holds.
		if activeGroup?.diagramPreview == nil,
		   let markdown = activeGroup?.markdownPreview,
		   let url = markdown.fileURL, let source = markdown.markdownSource?()
		{
			print("EXPORT menu: \(markdown.exportMenuTitlesForTesting.joined(separator: " | "))")
			DiagramExportCommand.run(
				url: url, source: source, format: format,
				theme: Theme.current.isLight ? .light : .dark, projectRoot: nil
			) { written in
				print("EXPORT: \(written.map(\.lastPathComponent).joined(separator: ", "))")
			}
			return
		}
		guard let pane = activeGroup?.diagramPreview else {
			print("EXPORT: nothing showing a diagram")
			return
		}
		print("EXPORT menu: \(pane.menuTitlesForTesting.joined(separator: " | "))")
		pane.export(format, editable: editable) { written in
			print("EXPORT: \(written.map(\.lastPathComponent).joined(separator: ", "))")
		}
	}

	/// Swaps the diagram in front between fitting the pane's width and the
	/// drawing's own size, as a double-click on it does, and says what the
	/// corner now reads.
	///
	/// The percentage is the point: a screenshot shows a diagram got larger and
	/// cannot show what it got larger *to*.
	func setDiagramFitForTesting(_ raw: String) {
		guard let pane = activeGroup?.diagramPreview else {
			print("FIT: nothing showing a diagram")
			return
		}
		pane.setFit(raw.lowercased() == "actual" ? .actual : .width)
		print("FIT: \(pane.scaleReadoutForTesting)")
	}

	/// The same for the picture in front, and it prints more than a percentage.
	///
	/// What 0532 was about is a document view pinned to the pane, and no capture
	/// of a picture can show whether the thing under it is larger than the hole
	/// it is seen through. The numbers can: the report names the picture, the
	/// document it sits in and the part of it on screen, so "pannable rather
	/// than cropped" is arithmetic anybody can check.
	func setImageFitForTesting(_ raw: String) {
		guard let pane = activeGroup?.imagePreview else {
			print("IMAGE: nothing showing a picture")
			return
		}
		pane.setFit(raw.lowercased() == "actual" ? .actual : .pane)
		print("IMAGE: \(pane.reportForTesting)")
	}

	/// Scrolls the picture in front to a corner of itself, `x,y` as fractions.
	func panImageForTesting(_ raw: String) {
		guard let pane = activeGroup?.imagePreview else {
			print("IMAGE: nothing showing a picture")
			return
		}
		let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
		guard parts.count == 2 else {
			print("IMAGE: --image-pan wants x,y as fractions, got \(raw)")
			return
		}
		pane.panForTesting(CGPoint(x: parts[0], y: parts[1]))
		print("IMAGE: \(pane.reportForTesting)")
	}

	/// Presses the settings sidebar's arrow keys, and says where they left it.
	///
	/// Beside `--settings-fold`, which is the triangle: the same folding, by the
	/// other way in. What comes back also carries the sidebar's sizes, so a run
	/// can tell whether the zoom reached the page as well as what the keys did.
	func pressSettingsKeysForTesting(_ keys: String) {
		guard let page = activeGroup?.page(identifier: "settings") as? SettingsPage else {
			print("SETTINGS: no settings page")
			return
		}
		page.pressArrowsForTesting(
			keys.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
		)
		print("SETTINGS: \(page.reportForTesting)")
	}

	/// What the editor is holding, saved or not.
	func editorTextForTesting() -> String? { textForTesting }

	func exerciseIndentForTesting(from: Int, to: Int, outdent: Bool) {
		guard let text = indentForTesting(fromLine: from, toLine: to, outdent: outdent) else {
			print("INDENT: no editor")
			return
		}
		let lines = text.components(separatedBy: "\n").prefix(6)
		print("INDENT\(outdent ? "-OUT" : "-IN"):")
		for (index, line) in lines.enumerated() {
			print("  \(index): \(line.replacingOccurrences(of: "\t", with: "→"))")
		}
	}

	/// Underlines invented problems on the open file, so the drawing can be
	/// looked at without a server having to agree to produce any.
	func injectDiagnosticsForTesting() {
		guard let url = activeGroup?.activeTabURL else { return }
		LanguageService.shared.injectForTesting([
			LSPDiagnostic(
				range: LSPRange(
					start: LSPPosition(line: 4, character: 8),
					end: LSPPosition(line: 4, character: 20)
				),
				severity: .error,
				message: "cannot find 'nonesuch' in scope",
				source: "swiftc"
			),
			LSPDiagnostic(
				range: LSPRange(
					start: LSPPosition(line: 6, character: 4),
					end: LSPPosition(line: 6, character: 16)
				),
				severity: .warning,
				message: "initialization of immutable value was never used",
				source: "swiftc"
			),
			LSPDiagnostic(
				range: LSPRange(
					start: LSPPosition(line: 8, character: 0),
					end: LSPPosition(line: 8, character: 30)
				),
				severity: .information,
				message: "consider using a computed property",
				source: "swiftlint"
			),
		], for: url)
	}

	/// What the editor said about motions nothing handled, for
	/// `--unhandled-motions`.
	func reportUnhandledMotionsForTesting() {
		let named = exerciseUnhandledMotionsForTesting()
		print("MOTIONS: \(named)")
		print("MOTIONS log: \(DiagnosticLog.path("editor"))")
		fflush(stdout)
	}

	/// What a server said about the file in front and how loudly it is drawn,
	/// for `--diagnostics`.
	func reportDiagnosticsForTesting(at seconds: Double) {
		print("DIAGNOSTICS at \(Int(seconds))s: \(diagnosticReportForTesting())")
		fflush(stdout)
	}

	/// Says whether the missing-server bar is up, and what it says.
	func reportServerBannerForTesting() {
		print("BANNER: \(activeGroup?.serverBannerReportForTesting ?? "no editor")")
	}

	/// Presses one of the bar's buttons: details, ignore, or dismiss.
	func pressServerBannerForTesting(_ button: String) {
		activeGroup?.pressServerBannerForTesting(button)
		print("BANNER: pressed \(button) -> \(activeGroup?.serverBannerReportForTesting ?? "no editor")")
	}

	/// Says what a real server had to say by the time this ran.
	func reportDiagnosticsForTesting() {
		let running = LanguageService.shared.runningNames
		guard let url = activeGroup?.activeTabURL else {
			print("LSP: no file open (servers: \(running))")
			return
		}
		let diagnostics = LanguageService.shared.diagnostics(for: url)
		print("LSP: servers=\(running) diagnostics=\(diagnostics.count) for \(url.lastPathComponent)")
		for diagnostic in diagnostics.prefix(5) {
			print("LSP:   \(diagnostic.severity) line \(diagnostic.range.start.line + 1): \(diagnostic.message)")
		}
	}

	/// Types, undoes, types something else, and shows the history.
	///
	/// The sequence a plain undo stack cannot survive: the first attempt is
	/// destroyed the moment the second is typed.
	func exerciseUndoTreeForTesting() {
		moveCaretToEndForTesting()
		simulateTyping("\n// first attempt\n")
		print("UNDO: after first  \(fileHistoryReportForTesting)")

		undoForTesting()
		print("UNDO: after undo   \(fileHistoryReportForTesting)")

		simulateTyping("\n// second attempt\n")
		print("UNDO: after second \(fileHistoryReportForTesting)")

		toggleFileHistory()
		print("UNDO: states       \(historySummariesForTesting)")

		// Back to the abandoned branch, which no amount of redo would reach.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
			guard let self else { return }
			let summaries = self.historySummariesForTesting
			if let index = summaries.firstIndex(where: { $0.contains("first attempt") }) {
				self.travelToHistoryRowForTesting(index)
				print("UNDO: travelled to the first attempt")
			}
			print("UNDO: text tail    \(self.textTailForTesting)")
		}
	}

	/// Types at the end of the file and leaves the completion list up.
	func exerciseCompletionForTesting(typing text: String) {
		moveCaretToEndForTesting()
		simulateTyping("\n")
		simulateTyping(text)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
			guard let self else { return }
			defer { fflush(stdout) }
			print("COMPLETE: \(self.completionReportForTesting)")
			// What the server said about the item that is highlighted, which is
			// the half that used to be parsed and thrown away.
			print("COMPLETE doc: \(self.completionDocumentationForTesting)")

			self.writeCompletionImageForTesting(to: "build/completion-list.png")

			// Down once, then take it, so what lands in the document is the
			// second suggestion rather than whatever was highlighted first.
			self.moveCompletionSelectionForTesting(by: 1)
			print("COMPLETE doc after ↓: \(self.completionDocumentationForTesting)")
			let committed = self.commitCompletionForTesting()
			print("COMMIT: \(committed) → \(self.caretReportForTesting)")

			// **The moment the change is about.** The list has gone and the
			// first stop is selected: this is where somebody asks what it takes.
			print("HINT: \(self.parameterHintForTesting)")
			self.simulateTab()
			print("HINT after tab: \(self.parameterHintForTesting)")
			self.simulateEscape()
			print("HINT after escape: \(self.parameterHintForTesting)")
		}
	}

	/// Walks the caret by word and says where it landed at each step.
	///
	/// The flush at the end is not decoration: a run ends by killing the app,
	/// and six lines still in stdout's buffer when the signal lands make a
	/// driver that works look like one that prints nothing at all.
	func exerciseWordNavigationForTesting() {
		defer { fflush(stdout) }
		print("WORD: start \(caretReportForTesting)")
		simulateKey("right", modifiers: .option)
		print("WORD: ⌥→ \(caretReportForTesting)")
		simulateKey("right", modifiers: .option)
		print("WORD: ⌥→ \(caretReportForTesting)")
		simulateKey("right", modifiers: [.option, .shift])
		print("WORD: ⇧⌥→ \(caretReportForTesting)")
		simulateKey("left", modifiers: .option)
		print("WORD: ⌥← \(caretReportForTesting)")
		simulateKey("left", modifiers: .option)
		print("WORD: ⌥← \(caretReportForTesting)")
	}

	/// `--select-lines`: selects a range and says where the keyboard ended up.
	///
	/// An overload of the plain `selectLinesForTesting(fromLine:toLine:)` rather
	/// than a wrapper with a new name: what a driven run wants is the selection
	/// *and* the report, and the report is the whole claim the picture it is
	/// taken for makes — that selecting lines does not quietly take the keyboard
	/// out of the code.
	func selectLinesForTesting(from: Int, to: Int) {
		let done = selectLinesForTesting(fromLine: from, toLine: to)
		let responder = view.window?.firstResponder
		print("SELECT lines \(from)-\(to) \(done ? "selected" : "no editor") "
			+ "keyboard=\(responder.map { String(describing: type(of: $0)) } ?? "nothing")")
		fflush(stdout)
	}


	/// Whether ⌘/ is wired up, which is a different question from whether the
	/// toggle works and the only one the suite cannot answer.
	///
	/// **Not by pressing the key**, and that was tried first. A menu's key
	/// equivalent is matched against the *key window's* responder chain, and a
	/// binary launched from a terminal never becomes key — activation is a request
	/// to the window server that this process is not granted, and it must not be:
	/// stealing focus from whoever is working is worse than not being tested. So a
	/// synthesised ⌘/ came back unhandled with no key window, which is
	/// indistinguishable from a shortcut that is not there. The command palette is
	/// blank in the same launch for the same reason, for every item in the menu.
	///
	/// So the three things that can actually be wrong are checked directly: that
	/// an item carries `/` with ⌘ and nothing else, that its action is the one this
	/// class implements, and that walking up from the first responder reaches
	/// something that answers to it. Given those three, AppKit's own routing is
	/// what carries the press, and it carries every other item in the same menu.
	///
	/// **Those three were not enough**, and 0479 is what they missed. All three
	/// were satisfied on a German keyboard — the item was there, the mask was ⌘
	/// alone, the chain answered — while no press a person could make reached it:
	/// the system had moved the shortcut from `/` to ß, and this report printed
	/// `key=ß` without anybody reading it as a shortcut nobody would find. So it
	/// now also says which press matches, from `MenuKeyReport`, because *which key*
	/// is the question and the wiring was never the part that was wrong.
	func commentKeyReportForTesting() {
		let selector = #selector(MainWindowController.toggleLineComment(_:))
		let items = (NSApp.mainMenu?.items ?? [])
			.compactMap(\.submenu)
			.flatMap(\.items)
			.filter { $0.action == selector }

		var chain: [String] = []
		var responder: NSResponder? = view.window?.firstResponder
		var answers = false
		while let current = responder {
			chain.append("\(type(of: current))")
			if current.responds(to: selector) { answers = true; break }
			responder = current.nextResponder
		}

		for item in items {
			print("COMMENTKEY item “\(item.title)” in “\(item.menu?.title ?? "?")” "
				+ "key=\(item.keyEquivalent) modifiers=\(item.keyEquivalentModifierMask.rawValue) "
				+ "command-only=\(item.keyEquivalentModifierMask == [.command])")
		}
		if items.isEmpty { print("COMMENTKEY no menu item performs toggleLineComment:") }
		print("COMMENTKEY responder chain answers=\(answers) via \(chain.joined(separator: " → "))")
		if let layout = KeyboardLayout.current() {
			let sweep = MenuKeyReport.findings(in: NSApp.mainMenu, layout: layout)
				.filter { finding in items.contains { $0.title == finding.title } }
			for finding in sweep {
				print("COMMENTKEY on “\(layout.name)” the menu says \(finding.shortcut), "
					+ "and it is pressed as "
					+ (finding.presses.isEmpty ? "NOTHING" : finding.presses.joined(separator: " or ")))
			}
		}

		// And then each of those presses, at the real menu bar, with the text watched
		// either side of it. The sweep says a press *matches*; this says the match
		// reaches the editor and changes the file, which is the question somebody
		// asking "does ⌘/ work" is actually asking. Everything but the window
		// server's own delivery is in this path.
		//
		// Every press rather than the first, because they are not the same key: on a
		// German keyboard ⌘⇧7 is the slash on the main block and ⌘/ is the one on the
		// numeric keypad, and somebody who reaches for the keypad is asking a
		// question the first press cannot answer.
		if let item = items.first {
			for (name, event) in MenuKeyReport.presses(reaching: item) {
				let before = editorTextForTesting()
				let handled = NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
				let after = editorTextForTesting()
				print("COMMENTKEY \(name) at the real menu: answered "
					+ "\(handled ? "it" : "NOTHING") and the text "
					+ "\(before == after ? "DID NOT CHANGE" : "changed")")
			}
		}
		fflush(stdout)
	}

	/// Presses ↑ on the first line and ↓ on the last, the page keys, and ⌘↑ and
	/// ⌘↓ from the middle — each with Shift and without — and says where the
	/// caret and the selection ended up every time.
	///
	/// Started from the middle of a line rather than from its edge, or the
	/// selection ⇧↑ makes would be empty and the run would read the same
	/// whether the caret had moved or not.
	///
	/// Worth running twice, the second time with `--wrap`: the rows a vertical
	/// key moves by are then segments of a line rather than lines, and a caret
	/// partway along a wrapped first line has a row above it to go to even
	/// though it has no line above it. So the run says which mode it is in
	/// rather than leaving it to be worked out from the offsets — and the
	/// setting persists between launches, which is exactly how a run gets read
	/// as the wrong one of the two.
	func exerciseVerticalNavigationForTesting() {
		// Flushed line by line: the app has to be killed to end a run, and a
		// report still sitting in stdout's buffer when the signal arrives is a
		// run that looks like it never happened. `--word-nav` reads as silent
		// for that reason and not because it does nothing.
		func say(_ label: String) {
			let padded = label.padding(toLength: 12, withPad: " ", startingAt: 0)
			print("VERT: \(padded)\(caretReportForTesting)")
			fflush(stdout)
		}
		func place(_ label: String, line: Int, column: Int) {
			setCaretForTesting(line: line, column: column)
			say(label)
		}
		func press(_ key: String, _ label: String, _ modifiers: NSEvent.ModifierFlags) {
			simulateKey(key, modifiers: modifiers)
			say(label)
		}

		print("VERT: word wrap is \(Settings.shared.wordWrap ? "on" : "off")")
		fflush(stdout)

		place("at 0@8", line: 0, column: 8)
		press("up", "⇧↑", .shift)
		place("at 0@8", line: 0, column: 8)
		press("up", "↑", [])

		place("at last@4", line: -1, column: 4)
		press("down", "⇧↓", .shift)
		place("at last@4", line: -1, column: 4)
		press("down", "↓", [])

		// The column has to survive the jump: ⇧↓ to the end of the file and then
		// ↑ belongs back at the column the run started from, and not at whatever
		// column the last line happens to end at.
		place("at last@4", line: -1, column: 4)
		press("down", "⇧↓", .shift)
		press("up", "then ↑", [])

		// The page keys are the same motion with a screenful as the step, and a
		// file shorter than the window is all edge: both of these overshoot.
		place("at 0@8", line: 0, column: 8)
		press("pageup", "⇞", [])
		place("at last@4", line: -1, column: 4)
		press("pagedown", "⇧⇟", .shift)

		// Partway along the first line, which the file this is pointed at wants
		// to make a long one. Wrapped, the first ↑ is the row above and still
		// inside line 0, and only the second one runs out of rows and goes to
		// the start of the file; unwrapped there is no row above at all and the
		// first ↑ is already the start of the file. The column stops at the end
		// of the line, so a short first line makes this its end rather than
		// nothing.
		place("at 0@400", line: 0, column: 400)
		press("up", "↑", [])
		press("up", "↑ again", [])
		place("at 0@400", line: 0, column: 400)
		press("down", "↓", [])
		press("down", "↓ again", [])

		// ⌘↑ and ⌘↓ and their shifted twins, from the middle of the file so that
		// both directions have something to select — from either edge one of the
		// four would select nothing and read the same as the dead key it used to
		// be. Before 0495 the shifted pair were selectors `doCommand` had no case
		// for, so they printed the line placing the caret, unchanged.
		place("at 3@4", line: 3, column: 4)
		press("up", "⌘↑", .command)
		place("at 3@4", line: 3, column: 4)
		press("up", "⌘⇧↑", [.command, .shift])
		place("at 3@4", line: 3, column: 4)
		press("down", "⌘↓", .command)
		place("at 3@4", line: 3, column: 4)
		press("down", "⌘⇧↓", [.command, .shift])
	}

	/// Presses the emacs motions — ⌃B, ⌃F and their shifted twins, with ⌃P and
	/// ⌃N as the control — and says where the caret and the selection landed.
	///
	/// A separate driver from `--vertical-nav` rather than four more lines in
	/// it: these are letter keys with a modifier, they need a file with
	/// ordinary short lines rather than one 723 characters long, and the run
	/// people will want to read is the four keystrokes together.
	///
	/// The caret goes back to the same place before each press, so every line
	/// is an independent keystroke and not a run — a ⌃B after a ⌃F would land
	/// back where it started and say nothing about either.
	func exerciseEmacsNavigationForTesting() {
		func say(_ label: String) {
			let padded = label.padding(toLength: 12, withPad: " ", startingAt: 0)
			print("EMACS: \(padded)\(caretReportForTesting)")
			fflush(stdout)
		}
		func place(_ label: String, line: Int, column: Int) {
			setCaretForTesting(line: line, column: column)
			say(label)
		}
		func press(_ key: String, _ label: String, _ modifiers: NSEvent.ModifierFlags) {
			simulateKey(key, modifiers: modifiers)
			say(label)
		}

		// Said out loud because the setting persists between launches and has
		// twice now made a run read as the wrong one of two. It makes no
		// difference to anything below — every motion here is `caret ± 1` in
		// document offsets, and none of them asks what row it is on.
		print("EMACS: word wrap is \(Settings.shared.wordWrap ? "on" : "off")")
		// Which document the offsets below are offsets into. The first run of
		// this driver reported a caret in a file nobody had asked for — the
		// app opens `--file` some time after launch, and until it lands the
		// active tab is whatever the last session left. A report of caret=26
		// is unfalsifiable without this line, and looks exactly like a motion
		// gone wrong.
		print("EMACS: the file ends \(textTailForTesting)")
		fflush(stdout)

		// Mid-line, so both directions have somewhere to go and the shifted
		// pair have something to select.
		place("at 2@6", line: 2, column: 6)
		press("f", "⌃F", .control)
		place("at 2@6", line: 2, column: 6)
		press("b", "⌃B", .control)
		place("at 2@6", line: 2, column: 6)
		press("f", "⇧⌃F", [.control, .shift])
		place("at 2@6", line: 2, column: 6)
		press("b", "⇧⌃B", [.control, .shift])

		// The edges. At column 0 the character before the caret is the newline
		// that ended the line above, so ⌃B goes to the end of that line rather
		// than staying put — the same step, over a character that happens not
		// to be printable. At offset 0 there is nothing behind the caret at
		// all and the clamp keeps it there.
		place("at 2@0", line: 2, column: 0)
		press("b", "⌃B", .control)
		place("at 0@0", line: 0, column: 0)
		press("b", "⌃B", .control)

		// The control the whole item is built on: the vertical half of the
		// same family, which arrives as plain `moveUp:`/`moveDown:` and has
		// always worked.
		place("at 2@6", line: 2, column: 6)
		press("p", "⌃P", .control)
		place("at 2@6", line: 2, column: 6)
		press("n", "⌃N", .control)

		// The paragraph family: ⌃A, ⌃E and their shifted twins, the two ⌥
		// arrows whose second selector is one of them, and ⌥⇧↑/⌥⇧↓, which are
		// `moveParagraph…AndModifySelection:` and not a pair at all.
		place("at 2@6", line: 2, column: 6)
		press("a", "⌃A", .control)
		place("at 2@6", line: 2, column: 6)
		press("e", "⌃E", .control)
		place("at 2@6", line: 2, column: 6)
		press("a", "⇧⌃A", [.control, .shift])
		place("at 2@6", line: 2, column: 6)
		press("e", "⇧⌃E", [.control, .shift])

		// An indented line, because a paragraph motion that went to the first
		// non-blank instead of to column zero would be right here and wrong
		// below: 3@4 is the first non-blank of a line indented four spaces,
		// and it is where the ⌥↑ two lines further on starts from.
		place("at 3@11", line: 3, column: 11)
		press("a", "⌃A", .control)
		place("at 3@4", line: 3, column: 4)
		press("a", "⌃A", .control)

		// ⌥↑ and ⌥↓ are `['moveBackward:', 'moveToBeginningOfParagraph:']` and
		// `['moveForward:', 'moveToEndOfParagraph:']` — two selectors sent in
		// order. Mid-line the leading nudge makes no difference; at a boundary
		// it is the whole point, and it is why the second selector must be a
		// plain "go to the hard edge" rather than anything that reads where
		// the caret already is.
		place("at 2@6", line: 2, column: 6)
		press("up", "⌥↑", .option)
		place("at 2@6", line: 2, column: 6)
		press("down", "⌥↓", .option)
		place("at 2@0", line: 2, column: 0)
		press("up", "⌥↑ at start", .option)
		place("at 2@end", line: 2, column: 999)
		press("down", "⌥↓ at end", .option)
		place("at 3@4", line: 3, column: 4)
		press("up", "⌥↑ indent", .option)

		// The shifted pair are *not* the shifted version of the two above.
		// `StandardKeyBinding.dict` sends ⌥⇧↑ as the single selector
		// `moveParagraphBackwardAndModifySelection:`, with no nudge in front
		// of it, so that one selector has to step to the previous paragraph
		// by itself when the caret is already at a boundary.
		place("at 2@6", line: 2, column: 6)
		press("up", "⌥⇧↑", [.option, .shift])
		place("at 2@6", line: 2, column: 6)
		press("down", "⌥⇧↓", [.option, .shift])
		place("at 2@0", line: 2, column: 0)
		press("up", "⌥⇧↑ start", [.option, .shift])

		// ⌃K last, and with the line printed either side of it, because a
		// caret report cannot show a deletion — the caret does not move. It
		// is last because it edits the document and the app autosaves, so
		// everything above would be reading a file this run had changed.
		// Regenerate the scratch file between runs.
		place("at 2@6", line: 2, column: 6)
		print("EMACS: line 2 is “\(lineTextForTesting(2))”")
		press("k", "⌃K", .control)
		print("EMACS: line 2 is “\(lineTextForTesting(2))”")
		// At the end of a line there is nothing left of the paragraph to
		// take, and the newline is the boundary rather than part of it, so
		// this is a no-op and does not join the two lines.
		place("at 3@end", line: 3, column: 999)
		press("k", "⌃K", .control)
		print("EMACS: lines 3-4 are “\(lineTextForTesting(3))” / “\(lineTextForTesting(4))”")
		fflush(stdout)
		// ⌃O — open-line, and the one key here that edits the file. macOS
		// sends it as a *pair* of selectors, `insertNewlineIgnoringFieldEditor:`
		// and then `moveBackward:`, so the caret ends where it started with
		// the line split under it — and the caret report alone cannot tell
		// that apart from a key that did nothing, since both say the caret is
		// where it was put. Each press prints the lines as well as the caret.
		//
		// Bottom of the file upwards, because unlike every motion above these
		// presses do not undo themselves: each one adds a line, and going up
		// leaves the line numbers underneath still the ones written here.
		func open(_ label: String, line: Int, column: Int) {
			setCaretForTesting(line: line, column: column)
			say(label)
			print("EMACS:             \(caretLinesForTesting)")
			simulateKey("o", modifiers: .control)
			say("⌃O")
			print("EMACS:             \(caretLinesForTesting)")
			fflush(stdout)
		}
		// An empty line: nothing on either side of the caret, so what ⌃O
		// leaves behind is two empty lines with the caret still on the first.
		open("at 5@0", line: 5, column: 0)
		// The end of an indented line, which is where copying the indent and
		// not copying it differ: the caret does not go to the new line, so a
		// copied indent would be whitespace on a line nobody is on.
		open("at 4@end", line: 4, column: 999)
		// Mid-word, the ordinary case: the word is split and the caret stays
		// in front of the newline, at the end of the first half.
		open("at 2@8", line: 2, column: 8)
	}
}
