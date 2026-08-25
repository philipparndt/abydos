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
}
