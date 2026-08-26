import AppKit
import AbydosKit

/// What a language server offers to change, and taking it: renaming a symbol,
/// the code actions over a diagnostic, and applying a workspace edit across
/// files that may not be open.
///
/// It shares a `// MARK` neighbourhood with results presentation on the window
/// controller and shares no state with it — which is what the split of
/// `ResultsPresenter` found and this is the other half of.
@MainActor
final class ServerActions {
	let editor: EditorAreaController
	let navigator: ProjectNavigatorViewController
	let panel: BottomPanel
	let toasts: ToastPresenter

	var currentProject: () -> Project? = { nil }
	var onNotify: (String, String?, Toast.Kind) -> Void = { _, _, _ in }

	/// The window's toast, with the labels its callers already use.
	func notify(_ title: String, detail: String? = nil, kind: Toast.Kind = .error) {
		onNotify(title, detail, kind)
	}
	var results: () -> ResultsPresenter? = { nil }

	/// Putting an agent on a diagnostic opens the panel it runs in.
	var onSetPanelVisible: (Bool) -> Void = { _ in }

	init(
		editor: EditorAreaController,
		navigator: ProjectNavigatorViewController,
		panel: BottomPanel,
		toasts: ToastPresenter
	) {
		self.editor = editor
		self.navigator = navigator
		self.panel = panel
		self.toasts = toasts
	}

	/// Right-clicks in the editor and finds usages of whatever is at the caret.
	/// Renames the symbol at a position, the way somebody would, and says what
	/// happened to the files.
	///
	/// Through the same door the context menu uses, and through the field: the
	/// name really is typed into `RenameField` and committed, so what this drives
	/// is the gesture and not a shortcut past it.
	func exerciseRenameForTesting(line: Int, character: Int, to newName: String) {
		guard let url = editor.activeGroup?.activeTabURL else {
			print("RENAME: no file open")
			return
		}
		renameSymbol(in: url, line: line, character: character)

		DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
			guard let self, let codeView = self.editor.activeGroup?.activeCodeView else { return }
			guard codeView.isRenaming else {
				print("RENAME: no field opened")
				return
			}
			print("RENAME: field open on “\(codeView.renameTextForTesting ?? "")”")
			codeView.commitRenameForTesting(newName)

			DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
				let buffer = self.editor.activeGroup?.activeDocument?.rope.string ?? ""
				print("RENAME: the open buffer "
					+ (buffer.contains(newName) ? "says" : "does not say") + " \(newName)")
				let root = self.currentProject()?.scopeRoot
				let hits = root.map { Self.filesContaining(newName, under: $0) } ?? []
				print("RENAME: \(hits.count) files on disk say \(newName)")
				for name in hits.prefix(10) { print("RENAME FILE: \(name)") }
			}
		}
	}

	func exerciseFindUsagesForTesting(line: Int, character: Int) {
		guard let url = editor.activeGroup?.activeTabURL else { return }
		results()?.exerciseFindUsagesForTesting(line: line, character: character, in: url)
	}

	/// Puts an agent on what the language server is complaining about.
	///
	/// The same Claude Code that reviews a branch, given one problem instead:
	/// the file, the line, the message, and the instruction to keep the change
	/// to what is wrong. It opens in the panel so the fix can be read, argued
	/// with, and undone like any other edit.
	func fixWithAI(url: URL, line: Int, diagnostic: LSPDiagnostic) {
		guard let root = currentProject()?.root else { return }
		// Canonical on both sides. Subtracting the root from the file only
		// works when the two were reached the same way, and this canonicalised
		// one of them: under `/tmp` or `/var`, both symlinks on macOS, the
		// subtraction did nothing and the agent was told to fix a problem in an
		// absolute path on somebody's machine. Same asymmetry as 0430.
		let relative = FilePath.canonical(url)
			.replacingOccurrences(of: FilePath.canonical(root) + "/", with: "")

		let prompt = """
		Fix this problem, reported by the language server in \(relative) at line \(line + 1):

		\(diagnostic.message)

		Read the file first. Change as little as possible: the fix is for this \
		problem, not for anything else you find on the way. Say in one sentence \
		what you changed and why.
		"""

		onSetPanelVisible(true)
		if case let .failure(error) = panel.startAgent(title: "Fix", prompt: prompt) {
			notify("Could not start the agent", detail: error.message)
		}
	}

	/// Renaming the symbol at a position, from the offer to the files on disk.
	///
	/// The whole of 0453's gesture, and it is four steps with a decision at each
	/// of the first three:
	///
	///  1. **Is there anything to rename here, and will this server do it?**
	///     Asked before a field appears, because an offer that fails is worse
	///     than an absence.
	///  2. **The name is typed where the old one is** — `RenameField`, over the
	///     symbol, in the text. Not a dialog: the navigator renames a file in
	///     place on its row, and this is that gesture one layer in.
	///  3. **The server is asked**, and what comes back is a description of a
	///     change rather than a change.
	///  4. **The change is worked out in full and then made**, by
	///     `WorkspaceEditPlan` and `WorkspaceEditApplier`, which is where every
	///     hard part of this lives: open documents against closed ones, files
	///     that move, one undo, and what to do when it fails halfway.
	/// Edit ▸ Rename…, which is ⇧F6.
	///
	/// The same gesture the context menu offers, from the caret rather than from
	/// where somebody right-clicked. Silent when there is no file open: a menu
	/// item that does nothing is better than one that says so.
	@objc func renameSymbol(_ sender: Any?) {
		guard let group = editor.activeGroup,
		      let codeView = group.activeCodeView,
		      let url = group.activeTabURL,
		      let position = codeView.caretPositionForRequest()
		else { return }
		renameSymbol(in: url, line: position.line, character: position.character)
	}

	func renameSymbol(in url: URL, line: Int, character: Int) {
		guard let project = currentProject(),
		      let group = editor.activeGroup,
		      let codeView = group.activeCodeView,
		      let languageId = group.activeDocument?.languageId
		else { return }

		let position = LSPPosition(line: line, character: character)
		let word = codeView.wordAtCaret()
		let fallback = word.map {
			RenameSubject(
				name: $0.text,
				range: LSPRange(
					start: LSPPosition(line: line, character: character),
					end: LSPPosition(line: line, character: character)
				)
			)
		}

		// `[weak self]` on the task and not only on the callback inside it. The
		// callback's weak capture is load-bearing for a different reason — the
		// code view keeps that closure, so a strong one is a cycle — but a task
		// capturing the window controller strongly held it alive for the whole of
		// the `renameOffer` round trip, which is a language server being asked a
		// question over a pipe and can be seconds. A window closed in that gap
		// stayed alive until the server answered, and the answer was then laid
		// over a code view nobody is looking at.
		Task { @MainActor [weak self] in
			// The file's own root, not the scope: a rename is asked of the
			// server that was told about this file, and the scope pill may be
			// pointing at another subproject entirely.
			let offer = await LanguageService.shared.renameOffer(
				url: url, position: position, languageId: languageId,
				project: LanguageService.shared.root(
					for: url, languageId: languageId, project: project.root
				),
				fallback: fallback
			)
			// Closed while the server was being asked. Nothing to say and nowhere
			// to put a field.
			guard let self else { return }

			guard case let .offered(subject) = offer else {
				// Two of the three refusals say nothing at all — no server, and
				// the server's own "nothing here", which is what the caret being
				// on a bracket looks like every time.
				if let refusal = offer.refusal {
					notify("Cannot rename here", detail: refusal, kind: .information)
				}
				return
			}

			// The extent to lay the field over. The server's range where it gave
			// one, since it knows things the editor's idea of a word does not —
			// a Swift `` `default` `` is one symbol and three tokens.
			guard let extent = self.utf16Range(of: subject, in: codeView, fallback: word?.range) else {
				return
			}

			codeView.beginRename(
				utf16Range: extent, name: subject.name, caveat: subject.caveat
			) { [weak self] newName in
				guard let self else { return true }
				self.performRename(
					in: url, position: position, to: newName,
					languageId: languageId,
					project: LanguageService.shared.root(
						for: url, languageId: languageId, project: project.root
					)
				)
				return true
			}
		}
	}

	/// The symbol's extent in the document, from whichever of the two answers
	/// there is.
	func utf16Range(
		of subject: RenameSubject, in codeView: CodeView, fallback: Range<Int>?
	) -> Range<Int>? {
		guard let document = codeView.document else { return fallback }
		let rope = document.rope
		func offset(_ position: LSPPosition) -> Int? {
			guard position.line >= 0, position.line < rope.lineCount else { return nil }
			let start = rope.utf16Offset(fromByte: rope.byteOffset(ofLine: position.line))
			return start + position.character
		}
		guard let start = offset(subject.range.start), let end = offset(subject.range.end),
		      end > start
		else { return fallback }
		return start..<end
	}

	/// Asks for the edit and makes it.
	func performRename(
		in url: URL, position: LSPPosition, to newName: String,
		languageId: String, project: URL
	) {
		Task { @MainActor in
			let answer = await LanguageService.shared.rename(
				url: url, position: position, to: newName, languageId: languageId, project: project
			)

			// The sentences live on `RenameAnswer`, where the other rename
			// sentences do, so what is said can be read without a window.
			guard let refusal = answer.refusal else {
				if let edit = answer.edit { self.apply(edit, named: newName) }
				return
			}
			notify(
				refusal.title, detail: refusal.detail,
				kind: refusal.isFailure ? .error : .information
			)
		}
	}

	/// What a server offers about the caret — ⌥⏎.
	///
	/// **A keystroke and not a mark, and that was measured rather than
	/// preferred.** Asked at every line of a real file, gopls answered something
	/// about 16 lines of 16 and jdtls about 10 of 10; an indicator meaning "there
	/// is something here" would therefore be on every row of every file, which is
	/// an indicator nobody reads. Asking when somebody asks costs one request and
	/// is never noise.
	/// ⌃Space, which is IDEA's and Eclipse's, and what everybody presses.
	@objc func completeAtCaret(_ sender: Any?) {
		editor.completeAtCaret()
	}

	@objc func showCodeActions(_ sender: Any?) {
		offerCodeActions(fileWide: false)
	}

	/// What a server offers about the *file* — organise imports, fix all of a
	/// kind. These have no caret, so they are not in the menu that opens at one.
	@objc func showSourceActions(_ sender: Any?) {
		offerCodeActions(fileWide: true)
	}

	func offerCodeActions(fileWide: Bool) {
		guard let group = editor.activeGroup,
		      let codeView = group.activeCodeView,
		      let url = group.activeTabURL,
		      let languageId = group.activeDocument?.languageId,
		      let project = currentProject(),
		      let caret = codeView.caretPositionForRequest()
		else { return }

		let position = LSPPosition(line: caret.line, character: caret.character)
		// The file's own root rather than the scope's, the way a rename asks:
		// the server that was told about this file is the one with anything to
		// say about it.
		let root = LanguageService.shared.root(for: url, languageId: languageId, project: project.root)
		// A file-wide question is asked about the whole file rather than about
		// where somebody happens to be standing, and asked with `only`, so a
		// server that can answer it cheaply does.
		let range = fileWide
			? LSPRange(start: LSPPosition(line: 0, character: 0), end: position)
			: LSPRange(start: position, end: position)

		Task { @MainActor [weak self] in
			let offer = await LanguageService.shared.codeActions(
				url: url, range: range, languageId: languageId, project: root,
				only: fileWide ? ["source"] : nil
			)
			guard let self else { return }
			guard let offer else {
				// No server for this file. Silent for the reason a rename is:
				// it is most files in most projects, and what there is to say
				// about a missing server is the strip above the file.
				return
			}

			// `source.*` is about the file: in the caret's menu it would be a
			// list of things that have nothing to do with where somebody is.
			let wanted = offer.actions.filter { fileWide ? $0.isSourceAction : !$0.isSourceAction }
			guard !wanted.isEmpty else {
				notify(
					fileWide ? "Nothing to do to this file" : "Nothing on offer here",
					detail: "\(offer.server) offers nothing "
						+ (fileWide ? "about this file." : "about this line."),
					kind: .information
				)
				return
			}

			let menu = self.codeActionMenu(
				wanted, from: offer, url: url, languageId: languageId, project: root
			)
			guard let point = codeView.caretScreenPoint() else { return }
			menu.popUp(positioning: nil, at: NSPoint(x: point.x, y: point.y), in: nil)
		}
	}

	/// The menu of what a server offers, in the server's own words.
	///
	/// **Whatever it offers is what is shown**, unedited and unsorted — the same
	/// rule rename follows. The only thing added is who is talking: 0449 lets a
	/// project choose its server, and a syntactic one's list is shorter and
	/// different in kind. Somebody should be able to tell which they are getting
	/// rather than wondering why the menu changed.
	func codeActionMenu(
		_ actions: [LSPCodeAction],
		from offer: LanguageService.CodeActionOffer,
		url: URL,
		languageId: String,
		project: URL
	) -> NSMenu {
		let menu = NSMenu()
		for action in actions {
			let entry = NSMenuItem(
				title: action.title,
				action: #selector(takeCodeActionFromMenu(_:)),
				keyEquivalent: ""
			)
			entry.target = self
			entry.representedObject = TakenCodeAction(
				action: action, url: url, languageId: languageId, project: project
			)
			// A server may send an action it will not run, with a reason meant
			// to be read. Shown and not runnable, rather than dropped.
			if let reason = action.disabledReason {
				entry.isEnabled = false
				entry.toolTip = reason
			}
			menu.addItem(entry)
		}
		menu.addItem(.separator())
		let who = NSMenuItem(
			title: offer.isSyntactic
				? "from \(offer.server), which matches names rather than types"
				: "from \(offer.server)",
			action: nil,
			keyEquivalent: ""
		)
		who.isEnabled = false
		menu.addItem(who)
		return menu
	}

	@objc func takeCodeActionFromMenu(_ sender: NSMenuItem) {
		guard let taken = sender.representedObject as? TakenCodeAction else { return }
		take(taken)
	}

	/// Carries out one action: resolve it if it arrived empty, apply its edit,
	/// run its command.
	///
	/// **In that order, and all three.** An action may carry an edit *and* a
	/// command — the protocol allows it and jdtls uses it — and doing only the
	/// first half of one is worse than doing neither.
	func take(_ taken: TakenCodeAction) {
		Task { @MainActor [weak self] in
			guard let self else { return }
			// **Resolved on the way to being applied, never treated as empty.**
			// A server that answers cheaply and fills in the work when asked is
			// the normal case, not the corner one: of 83 actions jdtls offered
			// in the measurement, 81 arrived with nothing in them.
			let action = await LanguageService.shared.resolve(
				taken.action, url: taken.url, languageId: taken.languageId, project: taken.project
			)

			if action.needsResolving {
				notify(
					"“\(action.title)” could not be worked out",
					detail: "The server offered it and then had nothing to do for it.",
					kind: .warning
				)
				return
			}

			if let edit = action.edit, !edit.isEmpty {
				self.apply(edit, named: action.title)
			}
			if let command = action.command {
				let taken = await LanguageService.shared.run(
					command, url: taken.url, languageId: taken.languageId, project: taken.project
				)
				// The server may now ask this window to apply an edit, which
				// arrives as `workspace/applyEdit` and is answered there.
				if !taken {
					notify(
						"“\(action.title)” was refused",
						detail: "The server would not run it.",
						kind: .warning
					)
				}
			}
		}
	}

	/// Says that this window will carry out the edits servers ask for.
	///
	/// **The same applying a rename uses, and deliberately not a second one.**
	/// An edit arriving through `workspace/applyEdit` touches open documents and
	/// closed files exactly as a rename's does, wants the same single undo entry
	/// and the same refusal when part of it cannot be done — and a second
	/// implementation of that is the one thing 0453 exists to prevent.
	func takeServerEdits() {
		LanguageService.shared.applyEditFromServer = { [weak self] edit, label, answer in
			guard let self else {
				answer(false, "The window the edit was for has closed.")
				return
			}
			let outcome = self.apply(edit, named: label ?? "the server’s edit")
			switch outcome {
			case .applied:
				answer(true, nil)
			case let .refused(reasons):
				answer(false, reasons.joined(separator: " "))
			case let .putBack(failure):
				answer(false, failure)
			case let .halfDone(failure, changed, _):
				// The state this whole design exists to make rare. The server is
				// told `false` — the edit it asked for did not happen as asked —
				// and told which files are not as either side believes.
				answer(false, failure + " Left changed: "
					+ changed.map(\.lastPathComponent).joined(separator: ", "))
			}
		}
	}

	/// Turns a workspace edit into files, and puts one entry on the undo stack
	/// for the whole of it.
	@discardableResult
	func apply(_ edit: WorkspaceEdit, named newName: String) -> WorkspaceEditApplier.Outcome {
		let files = workspaceEditFiles()
		let plan = WorkspaceEditPlan.make(edit, contents: files.contents, exists: files.exists)

		// Tabs on files that are about to move are closed first, so that nothing
		// auto-saves a buffer back to a path the move has just emptied.
		let reopening = plan.moves.compactMap { move -> (from: URL, to: URL)? in
			editor.document(for: move.from) != nil ? (move.from, move.to) : nil
		}
		for move in reopening { editor.closeTab(showing: move.from) }

		let outcome = WorkspaceEditApplier.apply(plan, to: files)

		for move in reopening where FileManager.default.fileExists(atPath: move.to.path) {
			editor.open(fileURL: move.to)
		}
		navigator.reloadTree()

		if let summary = outcome.summary {
			notify(summary.title, detail: summary.detail, kind: outcome.isUntouched ? .warning : .error)
		}

		guard case let .applied(applied) = outcome, !applied.isEmpty else { return outcome }
		remember(applied, named: newName)
		return outcome
	}

	/// The one undo entry for the whole rename.
	///
	/// One entry however many files it was — the rule `FileUndo` settled for
	/// what the tree does, and this is the editor's version of it. Forty files
	/// renamed and undone forty times is not an undo, and neither is forty
	/// presses that each take back one file's worth of a refactoring that only
	/// makes sense whole.
	///
	/// On the *tree's* undo stack rather than each document's, and that is the
	/// only place it can be: a document's `UndoTree` is that document's history
	/// and knows nothing of the thirty-nine others, and a rename that also moved
	/// a file is not a text edit at all.
	func remember(_ plan: WorkspaceEditPlan, named newName: String) {
		navigator.rememberWorkspaceEdit(plan, title: "Rename to “\(newName)”") { [weak self] plan in
			guard let self else { return }
			let files = self.workspaceEditFiles()
			// Same shape as applying: the tabs on files that are about to move
			// back are closed first.
			let reopening = plan.moves.compactMap { move -> (from: URL, to: URL)? in
				self.editor.document(for: move.to) != nil ? (move.to, move.from) : nil
			}
			for move in reopening { self.editor.closeTab(showing: move.from) }

			let outcome = WorkspaceEditApplier.reverse(plan, in: files)

			for move in reopening where FileManager.default.fileExists(atPath: move.to.path) {
				self.editor.open(fileURL: move.to)
			}
			self.navigator.reloadTree()
			if let summary = outcome.summary {
				notify(summary.title, detail: summary.detail)
			}
		}
	}

	/// The files a workspace edit acts on, in this window.
	///
	/// **This is where an open document stops being a file.** A file with an
	/// editor on it is read from its rope and written through it, so the buffer
	/// and the disk never come to say different things; everything else is read
	/// and written on disk without an editor being made for it, which is what a
	/// rename across five hundred bundles needs.
	func workspaceEditFiles() -> WorkspaceEditFiles {
		let disk = WorkspaceEditFiles.disk
		return WorkspaceEditFiles(
			contents: { [weak self] url in
				self?.editor.document(for: url)?.rope.string ?? disk.contents(url)
			},
			exists: disk.exists,
			write: { [weak self] url, text in
				guard self?.editor.applyRenamedText(text, to: url) != true else { return }
				try disk.write(url, text)
			},
			move: disk.move,
			trash: disk.trash
		)
	}

	func findUsages(in url: URL, line: Int, character: Int) {
		guard let project = currentProject(), let languageId = editor.activeGroup?.activeDocument?.languageId else { return }
		results()?.noteUsagesRequest(url: url, line: line, character: character)

		Task { @MainActor in
			let locations = await LanguageService.shared.references(
				url: url,
				position: LSPPosition(line: line, character: character),
				languageId: languageId,
				project: LanguageService.shared.root(
					for: url, languageId: languageId, project: project.root
				)
			)
			guard !locations.isEmpty else {
				notify("No usages found", kind: .information)
				return
			}
			// One result is not a list; it is the place to go.
			if locations.count == 1, let only = locations.first, let target = only.url {
				editor.open(
					fileURL: target,
					atLine: only.range.start.line + 1,
					column: only.range.start.character + 1,
					length: only.range.widthOnOneLine
				)
				return
			}
			results()?.showUsages(
				locations,
				of: symbolName(in: url, line: line, character: character),
				at: "\(url.path):\(line):\(character)"
			)
		}
	}

	/// The word the caret is on, for the heading and the tab.
	///
	/// Read out of the open document rather than asked of the server: the server
	/// has already answered the only question worth a round trip, and a heading
	/// that says "usages of `Close`" is worth more than one that says "usages"
	/// only if it arrives with the list.
	func symbolName(in url: URL, line: Int, character: Int) -> String {
		guard let text = editor.document(for: url)?.rope.string else { return "" }
		let lines = text.components(separatedBy: "\n")
		guard lines.indices.contains(line) else { return "" }
		let units = Array(lines[line].utf16)
		guard character <= units.count else { return "" }

		func isWord(_ unit: UInt16) -> Bool {
			guard let scalar = Unicode.Scalar(unit) else { return false }
			return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
		}

		var start = min(character, max(0, units.count - 1))
		var end = start
		while start > 0, isWord(units[start - 1]) { start -= 1 }
		while end < units.count, isWord(units[end]) { end += 1 }
		guard end > start else { return "" }
		return String(decoding: units[start..<end], as: UTF16.self)
	}

	/// Why the symbol list is empty, in a sentence somebody can act on.
	func reasonForNoSymbols(query: String, scope: SymbolPalette.Scope) -> String {
		guard let project = currentProject() else { return "No project is open." }
		let status = LanguageService.shared.serverStatus(project: project.scopeRoot)

		// About the file that is open, not about the project. A project with
		// Go and TypeScript in it is missing the TypeScript server whether or
		// not that has anything to do with the Go file on screen — and being
		// told to sidebar.install a TypeScript server while looking at main.go reads
		// like the editor has lost track of what it is showing.
		if scope == .document {
			guard let languageId = editor.activeGroup?.activeDocument?.languageId else {
				return "Open a file to see what it declares."
			}
			if let missing = status.missing.first(where: { $0.language == languageId }) {
				return "No language server for \(missing.language).\n\(missing.hint)"
			}
			// A server that has already said it cannot work is the answer to
			// "why is this empty" — better than the guess that it might still
			// be starting, which it will never stop doing.
			// The server that would have answered about this file, which is the
			// one filed under the file's own root.
			if let failure = LanguageService.shared.failure(
				forLanguage: languageId,
				project: editor.activeGroup?.activeTabURL.map {
					LanguageService.shared.root(for: $0, languageId: languageId, project: project.root)
				} ?? project.scopeRoot
			) {
				return "The \(languageId) language server cannot read this project.\n\(failure)"
					+ "\n\n\(LanguageService.logPath) has the rest."
			}
			// **Definitively, rather than as the hedge this used to be.** "Nothing
			// declared in this file, or the language server is still starting"
			// is two answers in one sentence and neither of them is actionable:
			// the reader cannot tell whether to wait or to go and look at the
			// file. The service knows which it is.
			if let notReady = LanguageService.shared.notReadySentence(
				languageId: languageId,
				project: editor.activeGroup?.activeTabURL.map {
					LanguageService.shared.root(for: $0, languageId: languageId, project: project.root)
				} ?? project.scopeRoot
			) {
				return "\(notReady)\nThis list fills in by itself when it is ready."
			}
			return query.isEmpty
				? "Nothing declared in this file."
				: "Nothing matching \u{201C}\(query)\u{201D}."
		}

		if status.running.isEmpty, let missing = status.missing.first {
			return "No language server for \(missing.language).\n\(missing.hint)"
		}
		if status.running.isEmpty {
			return "No language server is running for this project."
		}
		if scope == .workspace, query.isEmpty {
			return "Type to search \(status.running.joined(separator: ", "))."
		}
		if scope == .document, editor.activeGroup?.activeTabURL == nil {
			return "Open a file to see what it declares."
		}
		return query.isEmpty ? "Nothing to show." : "Nothing matching “\(query)”."
	}

	func symbols(matching query: String, scope: SymbolPalette.Scope) async -> [LSPSymbol] {
		guard let project = currentProject() else { return [] }

		switch scope {
		case .workspace:
			// An empty query would ask the server for every symbol it knows,
			// which for a large project is a great deal of nothing useful.
			guard !query.isEmpty else { return [] }
			return await LanguageService.shared
				.workspaceSymbols(matching: query, project: project.scopeRoot)
				.sorted { better($0, than: $1, for: query) }
				.prefix(200)
				.map { $0 }

		case .document:
			guard let url = editor.activeGroup?.activeTabURL,
			      let languageId = editor.activeGroup?.activeDocument?.languageId
			else { return [] }

			// A Makefile has no language server, and the grammar it borrows is
			// bash's, which knows nothing about targets — so the one file in a
			// project that is a list of named things was the one file this
			// could not list. Its own parser already reads them.
			//
			// Asked of the file, not of the language. Borrowing bash's grammar
			// means the language *is* bash, so the question this used to ask
			// ("is the language makefile?") had no answer but no, and ⇧⌘O on a
			// Makefile came back empty in every project.
			// A build file is in the same position, for the same reason: a POM
			// borrows HTML's grammar and a Gradle build borrows Groovy's or
			// Kotlin's, and none of those knows a module from a dependency. The
			// build files' own parsers do.
			let buildSymbols: [LSPSymbol]? = {
				if Makefile.isMakefile(url) { return Makefile.symbols(at: url) }
				if MavenProject.isPom(url) { return MavenProject.symbols(at: url) }
				if GradleBuild.isBuildFile(url) { return GradleBuild.symbols(at: url) }
				return nil
			}()
			if let buildSymbols {
				guard !query.isEmpty else { return buildSymbols }
				return buildSymbols.filter { $0.name.localizedCaseInsensitiveContains(query) }
			}

			// A document's symbols come from the server that was told about that
			// document, which is the one its own root is filed under.
			let all = await LanguageService.shared
				.documentSymbols(
					url: url, languageId: languageId,
					project: LanguageService.shared.root(
						for: url, languageId: languageId, project: project.root
					)
				)
			guard !query.isEmpty else { return all }
			return all
				.filter { $0.name.localizedCaseInsensitiveContains(query) }
				.sorted { better($0, than: $1, for: query) }
		}
	}

	/// Exact match first, then prefix, then merely containing it.
	///
	/// Servers match loosely — sourcekit-lsp will happily return a five-hundred
	/// character initialiser for a three-letter query — so the sort has to put
	/// what was actually asked for at the top. Ties go to the shorter name,
	/// which is nearly always the one meant.
	func better(_ left: LSPSymbol, than right: LSPSymbol, for query: String) -> Bool {
		let leftRank = rank(left, for: query)
		let rightRank = rank(right, for: query)
		if leftRank != rightRank { return leftRank < rightRank }
		if left.name.count != right.name.count { return left.name.count < right.name.count }
		return left.name < right.name
	}

	func rank(_ symbol: LSPSymbol, for query: String) -> Int {
		let name = symbol.name.lowercased()
		let needle = query.lowercased()
		if name == needle { return 0 }
		if name.hasPrefix(needle) { return 1 }
		if name.contains(needle) { return 2 }
		return 3
	}

	/// What a server offers about a line, taken, with the file before and after
	/// — for `--code-actions`.
	///
	/// **Driven through the same path the keystroke takes**, so what is watched
	/// is what ⌥⏎ does: the offer is asked for exactly as `showCodeActions`
	/// asks, and the action is taken exactly as the menu takes it. A report that
	/// called the client directly would prove the client works and say nothing
	/// about the editor.
	func reportCodeActionsForTesting(line: Int, character: Int = 0, take wanted: String?) {
		guard let group = editor.activeGroup,
		      let url = group.activeTabURL,
		      let languageId = group.activeDocument?.languageId,
		      let project = currentProject()
		else {
			print("ACTIONS: nothing open")
			fflush(stdout)
			return
		}
		let root = LanguageService.shared.root(for: url, languageId: languageId, project: project.root)
		let position = LSPPosition(line: line, character: character)

		Task { @MainActor [weak self] in
			guard let self else { return }
			let caret = await LanguageService.shared.codeActions(
				url: url, range: LSPRange(start: position, end: position),
				languageId: languageId, project: root
			)
			guard let caret else {
				print("ACTIONS line \(line): no server for this file")
				fflush(stdout)
				return
			}
			let atTheCaret = caret.actions.filter { !$0.isSourceAction }
			print("ACTIONS line \(line) from \(caret.server): "
				+ (atTheCaret.isEmpty
					? "nothing on offer"
					: atTheCaret.prefix(8).map(\.title).joined(separator: " | ")))
			print("ACTIONS line \(line) needing resolve: "
				+ "\(atTheCaret.filter(\.needsResolving).count) of \(atTheCaret.count)")

			// The file's own, asked separately and never shown at the caret.
			let file = await LanguageService.shared.codeActions(
				url: url,
				range: LSPRange(start: LSPPosition(line: 0, character: 0), end: position),
				languageId: languageId, project: root, only: ["source"]
			)
			print("ACTIONS source: "
				+ ((file?.actions.filter(\.isSourceAction).map(\.title).prefix(6).joined(separator: " | "))
					.map { $0.isEmpty ? "nothing on offer" : $0 } ?? "no server"))
			fflush(stdout)

			// The caret's list first, then the file's: a source action is taken
			// the same way, from the place it belongs.
			// The gesture itself, so that what a person would see is what is
			// reported: the menu at the caret, or the sentence when there is
			// nothing to put in it.
			if wanted == nil {
				self.showCodeActions(nil)
				DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
					print("ACTIONS said: \(self.toasts.saidForTesting.last ?? "nothing")")
					fflush(stdout)
				}
			}

			guard let wanted,
			      let chosen = atTheCaret.first(where: { $0.title.contains(wanted) })
				?? file?.actions.first(where: { $0.isSourceAction && $0.title.contains(wanted) })
			else {
				if wanted != nil { print("ACTIONS: nothing offered called \(wanted ?? "")") }
				fflush(stdout)
				return
			}
			let before = LanguageService.shared.serverEditsForTesting
			print("ACTIONS taking a \(chosen.command == nil ? "plain edit" : "command")")
			print("ACTIONS taking: \(chosen.title)")
			fflush(stdout)
			self.take(TakenCodeAction(
				action: chosen, url: url, languageId: languageId, project: root
			))

			// The edit arrives through the rope or the disk; either way it is
			// the file afterwards that says whether this worked.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
				let text = self.editor.document(for: url)?.rope.string
					?? (try? String(contentsOf: url, encoding: .utf8))
					?? ""
				let head = text.components(separatedBy: "\n").prefix(6).joined(separator: " ⏎ ")
				print("ACTIONS file after: \(head)")
				// The other half of a command: the server asking this program to
				// apply an edit, which is a request it waits on.
				print("ACTIONS edits the server asked for: "
					+ "\(LanguageService.shared.serverEditsForTesting - before)")
				fflush(stdout)
			}
		}
	}

	/// Which files under a directory hold a word. For the driver above only.
	static func filesContaining(_ word: String, under root: URL) -> [String] {
		guard let walk = FileManager.default.enumerator(
			at: root, includingPropertiesForKeys: nil
		) else { return [] }
		var found: [String] = []
		for case let url as URL in walk {
			guard !url.hasDirectoryPath else { continue }
			guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
			if text.contains(word) { found.append(url.lastPathComponent) }
		}
		return found.sorted()
	}

	/// One action, and everything needed to carry it out.
	final class TakenCodeAction: NSObject {
		let action: LSPCodeAction
		let url: URL
		let languageId: String
		let project: URL

		init(action: LSPCodeAction, url: URL, languageId: String, project: URL) {
			self.action = action
			self.url = url
			self.languageId = languageId
			self.project = project
		}
	}
}
