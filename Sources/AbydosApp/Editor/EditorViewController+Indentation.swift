import AppKit
import CryptoKit
import QuickLookUI
import GoSTL
import AbydosKit
import SwiftUI

/// What a file is indented with, and the change marks down the side.
extension EditorViewController {
	// MARK: - Indentation

	/// What the footer's indent chip says for the front tab: the style its
	/// view holds, asked of the view because the view is what inserts. Nil
	/// with no editor, which is when the bar is hidden anyway.
	var indentState: IndentStyle? { activeTab?.codeView?.indentStyle }

	/// The footer menu's pick, routed to the view that owns the buffer: the
	/// file's indentation converted to the chosen style, and the style made
	/// the one that is inserted from here. The view does the converting —
	/// it holds the buffer and the style both — and this lets the bar hear
	/// about it, the choice's one obligation to the world above it.
	func convertIndentation(to style: IndentStyle) {
		activeTab?.codeView?.convertIndentation(to: style)
		onStatusChanged?(self)
	}

	/// Drives the chip, its menu and the keys around it from outside:
	/// `report` (the chip's words, the menu's offer and the buffer's head,
	/// tail on a longer file, tabs as `→`), `menu` (the offer alone),
	/// `choose:tabs` or `choose:<width>` (the menu's pick), `tab`, `return`,
	/// `caret:<line>`, `type:<text>`, `shift:<from>-<to>` and
	/// `unshift:<from>-<to>` (lines 1-based, inclusive, shifted as ⇥ and ⇧⇥
	/// shift them), `undo`, `settle`.
	func indentChipForTesting(_ steps: String) {
		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			if step.hasPrefix("settle") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.indentChipForTesting(rest)
				}
				return
			}
			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "report": print("INDENT: \(indentChipReportForTesting())")
			case "menu": print("INDENT: \(indentMenuReportForTesting())")
			case "choose":
				if argument == "tabs" {
					convertIndentation(to: .tabs)
				} else if let width = Int(argument) {
					convertIndentation(to: .spaces(width: width))
				} else {
					print("INDENT: unknown style \(argument)")
				}
			case "tab": simulateTab()
			case "return": simulateReturn()
			case "caret": activeTab?.codeView?.moveCaretForTesting(toLine: (Int(argument) ?? 1) - 1)
			case "type": simulateTyping(argument)
			case "undo": undoForTesting()
			case "shift", "unshift":
				// Lines the way the other steps name them, 1-based and
				// inclusive, handed to the block driver that ⇥ and ⇧⇥ go
				// through — the same door, so what is measured is what the
				// keys do.
				let bounds = argument.split(separator: "-").compactMap { Int($0) }
				guard bounds.count == 2, bounds[0] <= bounds[1] else {
					print("INDENT: unknown lines \(argument)")
					continue
				}
				_ = indentForTesting(
					fromLine: bounds[0] - 1, toLine: bounds[1] - 1, outdent: step.hasPrefix("unshift")
				)
			default: print("INDENT: unknown step \(step)")
			}
		}
		fflush(stdout)
	}

	private func indentChipReportForTesting() -> String {
		guard let tab = activeTab, let codeView = tab.codeView else { return "no editor" }
		// The head and, on a file longer than the head, the tail with an ellipsis:
		// a return proof types at the end, and the head alone would not show it.
		let lines = codeView.textForTesting.components(separatedBy: "\n")
		let visible = { (line: String) in line.replacingOccurrences(of: "\t", with: "→") }
		var shown = lines.prefix(8).map(visible)
		if lines.count > 8 { shown += ["…"] + lines.suffix(4).map(visible) }
		return "chip=\(codeView.indentStyle.words) file=\(tab.url.lastPathComponent)"
			+ " \(indentMenuReportForTesting()) lines=\(shown.joined(separator: " ⏎ "))"
	}

	/// The menu's offer, from the same rule the menu is built from — one
	/// source in the engine, read by both — with the current style named.
	private func indentMenuReportForTesting() -> String {
		guard let codeView = activeTab?.codeView else { return "menu=none" }
		let currentWidth: Int?
		if case .spaces(let width) = codeView.indentStyle { currentWidth = width } else { currentWidth = nil }
		let offered = (["Tabs"] + IndentStyle.offeredWidths(currentWidth: currentWidth).map(String.init))
			.joined(separator: "/")
		return "menu=\(offered) ticked=\(codeView.indentStyle.words)"
	}

	/// Drives the covers from outside: `report`, `caret:<line>` (as an
	/// arrow-walk would arrive, which must lift nothing), `toggle` (the lock
	/// and the View menu's file-wide reveal, which is the only reveal).
	func secretsForTesting(_ steps: String) {
		guard let codeView = activeTab?.codeView else {
			print("SECRETS: no editor")
			fflush(stdout)
			return
		}
		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			// Everything after a settle goes back to the run loop, the way
			// every other driver waits: the idle re-conceal is a deferred
			// check, and a nested wait here would never see it fire.
			if step.hasPrefix("settle") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.5
					: 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.secretsForTesting(rest)
				}
				return
			}
			let argument = String(step.drop(while: { $0 != ":" }).dropFirst())
			switch step.prefix(while: { $0 != ":" }) {
			case "report": print("SECRETS:\n\(codeView.secretsReportForTesting())")
			case "idle-limit": codeView.secretsIdleLimit = Double(argument) ?? 300
			case "caret":  codeView.moveCaretForTesting(toLine: (Int(argument) ?? 1) - 1)
			case "toggle": toggleRevealSecrets()
			default:       print("SECRETS: unknown step \(step)")
			}
		}
		fflush(stdout)
	}

	/// Per tab, like blame: revealing one file's secrets says nothing about
	/// the next file's. Only meaningful on a tab that conceals at all.
	func toggleRevealSecrets() {
		guard let codeView = activeTab?.codeView, codeView.showsSecretCovers else { return }
		codeView.setSecretsRevealed(!codeView.secretsRevealedAll)
		onStatusChanged?(self)
	}

	/// Whether the front tab conceals, and whether it is revealed — the menu
	/// item's enabledness and its tick.
	var secretsState: (conceals: Bool, revealed: Bool) {
		guard let codeView = activeTab?.codeView else { return (false, false) }
		return (codeView.showsSecretCovers, codeView.secretsRevealedAll)
	}

	/// The column on, from a row that only ever turns it on: *Blame* on the
	/// tree and the tab. Nothing when it is on already.
	func showBlame() {
		guard let codeView = activeTab?.codeView, !codeView.isBlameVisible else { return }
		toggleBlame()
	}

	func toggleBlame() {
		guard let tab = activeTab, let codeView = tab.codeView else { return }
		let url = tab.url
		let showing = !codeView.isBlameVisible
		codeView.setBlameVisible(showing)
		guard showing else { return }

		// **In the repository that has the file's history.** `git blame` run in
		// the superproject over a path inside a submodule fails outright —
		// `no such path in HEAD`, because the superproject holds the gitlink
		// and not the file — and an empty answer reads here as "never
		// committed". So blame said there was nothing to blame for every file
		// in an estate. `GitEstate.place(of:)` is the same helper Compare and
		// History use, and it gives the root git is asked in; `GitBlame` takes
		// the path relative to that root itself.
		guard let place = repositoryPlace(of: url) else { return }
		let root = place.root
		Task { @MainActor in
			let lines = await GitBlame.lines(for: url, in: root)
			// The tab may have been closed, or blame turned off again, while
			// git was reading a file with ten thousand lines in it.
			guard codeView.isBlameVisible else { return }
			codeView.setBlame(lines)
			if lines.isEmpty {
				Toast.post(
					"Nothing to blame",
					detail: "\(url.lastPathComponent) is not in this repository, or has never been committed.",
					kind: .information
				)
			}
		}
	}

	var isBlameVisible: Bool { activeTab?.codeView?.isBlameVisible ?? false }

	/// Which repository a file's git verbs are aimed at. `Project.place(of:)`
	/// is the one answer; this is only the name the two call sites here use.
	private func repositoryPlace(of url: URL) -> GitEstate.Place? {
		project?.place(of: url)
	}

	/// Flips soft wrap for every open editor and remembers the choice.
	func toggleWordWrap() {
		let enabled = !Settings.shared.wordWrap
		Settings.shared.wordWrap = enabled
		for tab in tabs { tab.codeView?.setWordWrap(enabled) }
	}

	func collapseAllFolds() { activeTab?.codeView?.collapseAllFolds() }
	func expandAllFolds() { activeTab?.codeView?.expandAllFolds() }

	var hasOpenFiles: Bool { !tabs.isEmpty }


	/// Whether the editor has the window, for the strip's own control.
	func setMaximized(_ maximized: Bool) { tabBar.setMaximized(maximized) }


	func reportNavigation(
		from departure: (url: URL, line: Int)?,
		to arrival: (url: URL, line: Int)
	) {
		guard isReportingSuppressed == 0 else { return }
		onNavigated?(
			departure.map { NavigationHistory.Place(file: $0.url, line: $0.line) },
			NavigationHistory.Place(file: arrival.url, line: arrival.line)
		)
	}

	/// The file and line the caret is in, for recording where you were before
	/// jumping somewhere else.
	var currentPlace: (url: URL, line: Int)? {
		guard let tab = activeTab else { return nil }
		return (tab.url, (tab.codeView?.caretLine ?? 0) + 1)
	}

	/// What this group has open, as plain values.
	func captureSession() -> ProjectSession {
		// Pages are left out: they are the app's own views, not files, and a
		// path like /ideai/page/launch is nothing to reopen.
		ProjectSession(
			files: tabs.filter { $0.pageTitle == nil }.map { tab in
				ProjectSession.OpenFile(
					path: tab.url.path,
					line: (tab.codeView?.caretLine ?? 0) + 1,
					isPreview: tab.isPreview,
					// Only for a file that has a rendered form. Every other tab is
					// `.source` and always will be, and writing that down for each
					// of them says nothing.
					previewMode: FilePreview.hasPreview(
						tab.url, facts: tab.previewFacts
					) ? tab.previewMode : nil,
					dividerFraction: tab.dividerFraction,
					hex: tab.hex?.sessionState
				)
			},
			activePath: activeTab?.url.path
		)
	}

	/// Puts back what a project had open, without disturbing anything else.
	func restore(_ session: ProjectSession) {
		closeAllTabs()
		for file in session.files {
			let url = URL(fileURLWithPath: file.path)
			guard FileManager.default.fileExists(atPath: file.path) else { continue }
			open(
				fileURL: url,
				focusEditor: false,
				preview: file.isPreview,
				mode: file.previewMode,
				dividerFraction: file.dividerFraction
			)
			// A decrypted buffer the switch parked goes back into its tab
			// before anything is drawn, edits and all.
			if let parked = takeParkedDecrypted?(url),
			   let tab = tabs.last(where: { $0.url.path == file.path }) {
				restoreDecrypted(parked, into: tab)
			}
			// A hex tab comes back as the hex editor, with its caret, its
			// reading and what Claude said — not as the notice it was before
			// somebody pressed the button.
			if let state = file.hex, let tab = tabs.last(where: { $0.url.path == file.path }) {
				showHexEditor(for: tab)
				tab.hex?.restore(state)
			}
			if file.line > 1 {
				// Deferred: a document that has just been opened has not laid
				// out, so scrolling to a line now would measure against nothing.
				DispatchQueue.main.async { [weak self] in
					self?.tabs.last(where: { $0.url.path == file.path })?
						.codeView?.reveal(line: file.line - 1)
				}
			}
		}
		if let activePath = session.activePath,
		   let index = tabs.firstIndex(where: { $0.url.path == activePath }) {
			activate(index: index, focusEditor: false)
		}
	}

	/// Closes the tabs on one side of a tab, or all but it.
	///
	/// Right to left, always: closing a tab shifts everything after it, and a
	/// loop that walks forwards would skip every other one.
	func closeTabs(keeping index: Int) {
		guard let kept = tabs[safe: index] else { return }
		for position in tabs.indices.reversed() where tabs[position] !== kept {
			closeTab(at: position)
		}
	}

	func closeTabs(before index: Int) {
		guard let anchor = tabs[safe: index] else { return }
		for position in (0..<index).reversed() where tabs.indices.contains(position) {
			guard tabs[position] !== anchor else { continue }
			closeTab(at: position)
		}
	}

	func closeTabs(after index: Int) {
		guard tabs.indices.contains(index) else { return }
		for position in tabs.indices.reversed() where position > index {
			closeTab(at: position)
		}
	}

	/// Runs what a tab's menu runs, for the capture harness.
	func closeTabsForTesting(_ command: String, at index: Int) {
		switch command {
		case "others": closeTabs(keeping: index)
		case "left": closeTabs(before: index)
		case "right": closeTabs(after: index)
		case "all": closeAllTabs()
		default: closeTab(at: index)
		}
	}

	/// What the tab bar shows, in order. A provisional tab is marked, because
	/// "one tab for the whole list" is a claim about which kind of tab it is.
	var tabTitlesForTesting: [String] {
		tabs.map { tab in
			(tab.pageTitle ?? tab.url.lastPathComponent) + (tab.isPreview ? "~" : "")
				// An entry inside an archive says so, and that it is read only,
				// which is the whole of what makes its tab different.
				+ (tab.archiveOrigin.map { " [\($0.said)\(tab.document?.isReadOnly == true ? ", read only" : "")]" } ?? "")
		}
	}

	/// Closes every tab, for swapping one project's editors for another's.
	func closeAllTabs() {
		while !tabs.isEmpty { closeTab(at: tabs.count - 1) }
	}

	/// Presses a key with modifiers, the way a keyboard would.
	///
	/// Through `keyDown` rather than by calling the command directly: what is
	/// being checked is that the system's key bindings reach the editor, not
	/// that the editor has a method with the right name.
	///
	/// The arrows, Page Up and Page Down, and the letters the emacs bindings
	/// use are all in here together. They are the same kind of key to a text
	/// view — something AppKit turns into a selector — and a second function
	/// differing only in a key code would be the one somebody forgets to keep
	/// up with this one. It was called `simulateArrow` while it knew only the
	/// six navigation keys, and ⌃B could not be pressed through it at all.
	func simulateKey(_ key: String, modifiers: NSEvent.ModifierFlags) {
		// Guarded like the typing verbs, and for the same reason: `--emacs-nav`
		// is mostly motion, but ⌃O opens a line and ⌃K takes one away. A verb
		// that reads as navigation still changes a file.
		guard let codeView = codeViewToDrive("--emacs-nav") else { return }
		view.window?.makeFirstResponder(codeView)

		let navigationKeys: [String: (code: Int, character: Int)] = [
			"left": (123, NSLeftArrowFunctionKey), "right": (124, NSRightArrowFunctionKey),
			"down": (125, NSDownArrowFunctionKey), "up": (126, NSUpArrowFunctionKey),
			"pageup": (116, NSPageUpFunctionKey), "pagedown": (121, NSPageDownFunctionKey),
		]
		// The emacs letters — ⌃A ⌃B ⌃D ⌃E ⌃F ⌃K ⌃N ⌃O ⌃P — whether or not
		// anything presses all of them today, because looking a key code up
		// again is the cost of leaving them out.
		let letterKeys = ["a": 0, "b": 11, "d": 2, "e": 14, "f": 3, "k": 40, "n": 45, "o": 31, "p": 35]

		let code: Int
		let characters: String
		let ignoringModifiers: String
		if let navigation = navigationKeys[key.lowercased()] {
			code = navigation.code
			characters = String(UnicodeScalar(navigation.character)!)
			ignoringModifiers = characters
		} else if let letter = letterKeys[key.lowercased()], let scalar = key.lowercased().unicodeScalars.first {
			code = letter
			// A letter held with Control reports the control character in
			// `characters` and the bare letter in `charactersIgnoringModifiers`
			// — Shift reaching only the second of the two. AppKit matches the
			// binding against the pair, so a key built with the same string in
			// both fields arrives as nothing at all.
			ignoringModifiers = modifiers.contains(.shift) ? key.uppercased() : key.lowercased()
			characters = modifiers.contains(.control)
				? String(UnicodeScalar(UInt8(scalar.value & 0x1F)))
				: ignoringModifiers
		} else {
			return
		}

		guard let event = NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: modifiers,
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: view.window?.windowNumber ?? 0,
			context: nil,
			characters: characters,
			charactersIgnoringModifiers: ignoringModifiers,
			isARepeat: false,
			keyCode: UInt16(code)
		) else { return }
		codeView.keyDown(with: event)
	}

	/// What the completion list is showing.
	var completionReportForTesting: String {
		guard completions.isVisible else { return "no list" }
		if let notice = completions.noticeForTesting { return "waiting: \(notice)" }
		let frame = completions.frameForTesting
		let caret = activeTab?.codeView?.caretScreenPoint() ?? .zero
		return "\(completions.labelsForTesting.count) items: "
			+ completions.labelsForTesting.prefix(6).joined(separator: ", ")
			+ String(format: " | list at (%.0f, %.0f) %.0fx%.0f, caret at (%.0f, %.0f)",
				frame.minX, frame.minY, frame.width, frame.height, caret.x, caret.y)
	}

	/// The first line of what the panel beside the list is showing, and how much
	/// of it there is.
	///
	/// A line rather than the page: a driver's output is read in a terminal, and
	/// `cube`'s documentation is a wiki page. The length is what says the rest
	/// arrived.
	var completionDocumentationForTesting: String {
		guard let prose = completions.documentationForTesting else { return "no documentation" }
		let first = prose.components(separatedBy: .newlines).first ?? ""
		return "\(prose.count) characters, first line: \(first)"
	}

	/// What the strip above the line says, which is the answer to "what goes
	/// here" once the list has closed.
	var parameterHintForTesting: String {
		guard let text = parameterHint.textForTesting else { return "no hint" }
		guard let range = parameterHint.emphasisForTesting else { return text }
		let units = Array(text.utf16)
		let clamped = range.clamped(to: 0..<units.count)
		return "\(text) | filling in: \(String(decoding: units[clamped], as: UTF16.self))"
	}

	/// The text of the active tab, drawn to a PNG.
	@discardableResult
	func writeEditorImageForTesting(to path: String) -> Bool {
		activeTab?.codeView?.writeImageForTesting(to: path) ?? false
	}

	@discardableResult
	func writeCompletionImageForTesting(to path: String) -> Bool {
		completions.writeImageForTesting(to: path)
	}

	/// Chooses from the list as pressing return would.
	func commitCompletionForTesting() -> Bool {
		completions.commitSelection()
	}

	func moveCompletionSelectionForTesting(by delta: Int) {
		completions.moveSelection(by: delta)
	}

	func moveCaretToEndForTesting() {
		guard let codeView = activeTab?.codeView, let document = activeTab?.document else { return }
		view.window?.makeFirstResponder(codeView)
		codeView.setCaretForTesting(document.rope.utf16Count)
	}

	/// A negative line counts back from the end, so -1 is the last line.
	func setCaretForTesting(line: Int, column: Int) {
		guard let codeView = activeTab?.codeView else { return }
		view.window?.makeFirstResponder(codeView)
		codeView.setCaretForTesting(line: line, column: column)
	}

	/// Where the caret is and what is selected, for checking a motion landed.
	var caretReportForTesting: String {
		guard let codeView = activeTab?.codeView else { return "no editor" }
		return codeView.caretReportForTesting
	}

	/// Whether what was last revealed is on screen, with the file it is in.
	var revealReportForTesting: String {
		guard let codeView = activeTab?.codeView, let tab = activeTab else { return "no editor" }
		return "\(tab.url.lastPathComponent) \(codeView.revealReportForTesting)"
	}

	/// The caret's line and the one after it, with `|` where the caret is.
	///
	/// `caretReportForTesting` prints the *selected* text, which is empty
	/// whenever the caret is collapsed — so a key that inserts a newline and
	/// leaves the caret where it was reads exactly like a key that did
	/// nothing. `textTailForTesting` is no help either: it reports the end of
	/// the file, and an edit in the middle of one does not reach it. A key
	/// that inserts text has to show the text.
	///
	/// Tabs come out as `⇥`, because the question a driver asks about an
	/// inserted line is usually whether it is empty or full of whitespace, and
	/// a real tab in a terminal transcript answers that invisibly.
	///
	/// The line count comes with them. A newline inserted at the end of a line
	/// leaves an empty line after it, and the line after *that* one was
	/// already there — so two lines of text are the same either side of the
	/// press and only the count says the file grew.
	var caretLinesForTesting: String {
		guard let codeView = activeTab?.codeView, let document = activeTab?.document else {
			return "no file"
		}
		let rope = document.rope
		let offset = codeView.caretOffset
		let index = rope.line(atByteOffset: rope.byteOffset(fromUTF16: offset))
		let start = rope.utf16Offset(fromByte: rope.lineByteRange(index).lowerBound)
		let units = Array(rope.lineText(index).utf16)
		let column = max(0, min(offset - start, units.count))
		let marked = String(decoding: units[0..<column], as: UTF16.self) + "|"
			+ String(decoding: units[column...], as: UTF16.self)
		let shown = { (text: String) in text.replacingOccurrences(of: "\t", with: "⇥") }
		let next = index + 1 < document.lineCount ? rope.lineText(index + 1) : nil
		return "line \(index) “\(shown(marked))”"
			+ (next.map { " then \(index + 1) “\(shown($0))”" } ?? " (last line)")
			+ " — \(document.lineCount) lines"
	}

	/// Presses ⌘/ over a caret or a selection the spec names.
	func toggleCommentForTesting(_ spec: String) -> (LineComment.Outcome, String)? {
		guard let codeView = codeViewToDrive("--comment") else { return nil }
		view.window?.makeFirstResponder(codeView)
		return codeView.toggleCommentForTesting(spec)
	}

	/// Selects whole lines and leaves the keyboard exactly where it was.
	///
	/// No `makeFirstResponder`, unlike every other verb here: the point of it is
	/// a selection this view is drawing while the keyboard is in the terminal.
	func selectLinesForTesting(fromLine: Int, toLine: Int) -> Bool {
		guard let codeView = activeTab?.codeView else { return false }
		codeView.selectLinesForTesting(fromLine: fromLine, toLine: toLine)
		return true
	}

	/// Indents or outdents whole lines, the way Tab and ⇧Tab do.
	func indentForTesting(fromLine: Int, toLine: Int, outdent: Bool) -> String? {
		guard let codeView = codeViewToDrive("--indent-block") else { return nil }
		view.window?.makeFirstResponder(codeView)
		codeView.indentForTesting(fromLine: fromLine, toLine: toLine, outdent: outdent)
		return codeView.textForTesting
	}

	/// What the editor is holding, saved or not — for checking what typing did.
	var textForTesting: String? { activeTab?.codeView?.textForTesting }

	/// Presses the strip menu's global item, says where the file landed, and
	/// takes it away again — a check that leaves nothing behind in somebody's
	/// notes.
	func globalScratchDirectoryForTesting() -> String {
		let before = Set(ScratchFiles.global().all())
		_ = tabBar.contextMenuTitlesForTesting(overTab: false)  // builds the same menu
		newScratch(global: true)
		guard let made = ScratchFiles.global().all().first(where: { !before.contains($0) })
		else { return "nothing created" }
		defer { try? FileManager.default.removeItem(at: made) }
		return made.deletingLastPathComponent().path
	}

	/// Where the strip and the file's view actually ended up.
	func layoutReportForTesting() -> String {
		let content = activeTab?.contentView
		let centre = tabBar.convert(NSPoint(x: tabBar.bounds.midX, y: tabBar.bounds.midY), to: nil)
		let onTop = view.window?.contentView?.hitTest(centre)
		return "strip hidden=\(tabBar.isHidden) alpha=\(tabBar.alphaValue) items=\(tabBar.items.count)"
			+ " frame=\(NSStringFromRect(tabBar.frame))"
			+ " onTopOfStrip=\(onTop.map { String(describing: type(of: $0)) } ?? "nothing")"
			+ " content=\(content.map { String(describing: type(of: $0)) } ?? "none")"
			+ " area=\(NSStringFromRect(contentArea.frame))"

	}

	/// What the tab strip's menu offers over a tab and over its empty part.
	func tabMenuTitlesForTesting(overTab: Bool) -> [String] {
		tabBar.contextMenuTitlesForTesting(overTab: overTab)
	}

	/// Clicks under the last line of the file that is showing.
	func clickBelowLastLineForTesting() -> String {
		guard let codeView = activeTab?.codeView else { return "no editor" }
		view.window?.makeFirstResponder(codeView)
		return codeView.clickBelowLastLineForTesting()
	}

	/// Routes text through `NSTextInputClient.insertText`, the same entry point
	/// a real keystroke takes.
	func simulateTyping(_ text: String) {
		guard let codeView = codeViewToDrive("--type") else { return }
		view.window?.makeFirstResponder(codeView)
		for character in text {
			// A newline is the return key, not a character. Inserted directly
			// it skips everything return does — the indent, the closing brace
			// — so a test that typed one was testing something nobody does.
			if character == "\n" {
				codeView.doCommand(by: #selector(NSStandardKeyBindingResponding.insertNewline(_:)))
				continue
			}
			codeView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
		}
	}

	/// What each keystroke costs the main thread, in the file that is open.
	///
	/// The performance suite has measured this since 0416, but only against a
	/// document built in memory: `Rope`, the highlighter and the fold finder,
	/// with no window, no project, no language server and no filesystem watcher.
	/// 0428 asks the same question in a file inside a large bundle in a large
	/// project, where all four of those exist and every one of them wants the
	/// same queue — and the difference between the two answers is the whole
	/// reason the item names keystroke latency separately.
	///
	/// Synchronous, one character after another with nothing in between, so what
	/// comes back is the cost of the keystroke rather than the interval it was
	/// typed at. Both clocks: the wall is what a person waits and the processor
	/// time is what changes when the code does, which is 0416's distinction and
	/// is why a run under load is still worth taking.
	func measureTypingForTesting(presses: Int) -> [(wall: TimeInterval, cpu: TimeInterval)] {
		guard let codeView = codeViewToDrive("--type-latency") else { return [] }
		view.window?.makeFirstResponder(codeView)
		let letters = Array("abcdefghijklmnopqrstuvwxyz")
		var costs: [(TimeInterval, TimeInterval)] = []
		for press in 0..<presses {
			var cpuStart = timespec(), cpuEnd = timespec()
			clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpuStart)
			let wallStart = DispatchTime.now().uptimeNanoseconds
			codeView.insertText(
				String(letters[press % letters.count]),
				replacementRange: NSRange(location: NSNotFound, length: 0)
			)
			let wall = Double(DispatchTime.now().uptimeNanoseconds - wallStart) / 1_000_000_000
			clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpuEnd)
			costs.append((wall, Double(cpuEnd.tv_sec - cpuStart.tv_sec)
				+ Double(cpuEnd.tv_nsec - cpuStart.tv_nsec) / 1_000_000_000))
		}
		return costs
	}

	/// Flushes every dirty document, used on focus loss and quit.
	func autoSaveAll() {
		for tab in tabs {
			guard let document = tab.document, document.isDirty else { continue }
			document.autoSaveIfNeeded()
			// Saved means the diff on disk is the truth again.
			if !document.isDirty { refreshChangedLines(for: tab) }
		}
		refreshTabBar()
	}

	// MARK: - Change marks

	/// Reads which of a tab's lines differ from HEAD and hands the marks to
	/// its gutter. Async and generation-counted so a result arriving for a
	/// tab that has moved on — a newer save, a close — is dropped, the way
	/// `anchoringWork` drops stale re-anchors. Never per keystroke: the
	/// callers are open, save, reload, and the repository moving.
	func refreshChangedLines(for tab: Tab) {
		guard tab.codeView != nil else { return }
		// **A decrypted buffer has nothing to compare.** The marks say what
		// differs from HEAD, and HEAD holds the ciphertext: every line of the
		// plaintext differs from it, which says nothing about whether anybody
		// has changed anything. The diff comes back when the ciphertext does.
		guard !tab.isDecrypted else {
			tab.codeView?.setChangedLines(GitChangedLines())
			return
		}
		tab.changedLinesGeneration += 1
		let generation = tab.changedLinesGeneration
		let url = tab.url.standardizedFileURL
		// The repository that owns the file, not the project's own: a
		// `git diff HEAD` in the superproject over a path inside a submodule
		// answers nothing and exits 0, so a file in an estate had no change
		// marks in its gutter at all — no bar, ever, whatever was edited.
		let place = repositoryPlace(of: url)

		Task { @MainActor [weak self, weak tab] in
			guard let self, let place else {
				tab?.codeView?.setChangedLines(GitChangedLines())
				return
			}
			let diff = await GitWorkingCopy.diffAgainstHead(for: place.path, in: place.root)
			guard let tab, tab.changedLinesGeneration == generation else { return }
			_ = self
			let changed = diff.map { GitChangedLines.read(GitPatch.parse($0)) } ?? GitChangedLines()
			tab.codeView?.setChangedLines(changed)
		}
	}


	/// The concealment setting reaches the tabs already open, not only the
	/// next one: turning protection on must not require reopening the file it
	/// is about.
	@objc func settingsChangedForSecrets(_ note: Notification) {
		let wanted = Settings.shared.concealsSecrets
		for tab in tabs {
			tab.codeView?.setConcealsSecrets(
				wanted && DotenvSecrets.conceals(fileNamed: tab.url.lastPathComponent)
			)
		}
		onStatusChanged?(self)
	}

	@objc func repositoryChangedForMarks(_ note: Notification) {
		marksRefresh?.cancel()
		let work = DispatchWorkItem { [weak self] in
			guard let self else { return }
			for tab in tabs { refreshChangedLines(for: tab) }
		}
		marksRefresh = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
	}

	/// Re-reads any open file that something else has written.
	///
	/// A file with unsaved edits is left alone: replacing it would throw away
	/// work the user has not seen saved, and the two versions cannot be merged
	/// without asking. Auto-save is on by default, so that window is short.
	func reloadExternallyChangedFiles() {
		for tab in tabs {
			// A decrypted buffer is skipped as a dirty one is: the file on disk
			// is ciphertext, and putting it back over the plaintext would be a
			// reload nobody asked for. A save over a moved file is refused.
			guard let document = tab.document, !document.isDirty, !tab.isDecrypted else { continue }
			guard document.hasChangedOnDisk else { continue }
			guard tab.codeView?.reloadFromDisk() == true else { continue }
			onFileReloaded?(tab.url)
			refreshChangedLines(for: tab)

			// And tell the language server, or its diagnostics go on describing
			// the file as it was — which after something else has just fixed
			// one of them is the wrong answer written in red.
			guard let languageId = document.languageId, let root = serverRoot(for: tab) else { continue }
			LanguageService.shared.changed(
				url: tab.url, languageId: languageId, text: text(of: document), project: root
			)
			LanguageService.shared.saved(
				url: tab.url, languageId: languageId, text: text(of: document), project: root
			)
		}
	}

	/// Re-reads settings that affect the editor and repaints.
	func applySettings() {
		tabBarHeightConstraint.constant = EditorTabBar.height
		placeholder.font = Theme.current.uiFont(13)
		styleScratchButton()
		tabBar.applyThemeChange()
		findBar.applyThemeChange()
		if !findBar.isHidden { findBarHeight.constant = Theme.current.scaled(34) }
		serverBanner.applyTheme()
		if !serverBanner.isHidden { serverBannerHeight.constant = LanguageServerBanner.height }
		for tab in tabs {
			tab.codeView?.setWordWrap(Settings.shared.wordWrap)
			tab.codeView?.applyThemeChange()
			// A page of the app's own is a view in a tab and nothing else in the
			// window walks into one, so without this it was the one thing that
			// did not follow ⌘+: settings opened at 1× kept 1× rows and 1× type
			// for as long as it stayed open.
			(tab.contentView as? ScalingPage)?.applySettings()
		}
	}

	func windowWillClose() {
		autoSaveAll()
		for tab in tabs { teardown(tab) }
		tabs.removeAll()
		NotificationCenter.default.removeObserver(self)
	}
}
