import AppKit
import CryptoKit
import QuickLookUI
import GoSTL
import AbydosKit
import SwiftUI

/// Completion, and the signature of whatever is being filled in.
extension EditorViewController {
	// MARK: - Completion

	/// Asks for completions a moment after typing stops.
	///
	/// Debounced, and never on the first character of a word: a list offered
	/// after one letter is mostly noise, and asking a language server on every
	/// keystroke is asking it to answer about text nobody has finished writing.
	///
	/// **A trigger character skips the two-letter rule and nothing else.** The
	/// caret after a `.` is in no word, so waiting for a second letter means
	/// waiting for something that will never come — but the debounce still
	/// applies, so `.centerX` typed at speed is one request for where the
	/// typing stopped rather than seven.
	func scheduleCompletions(for tab: Tab, prefix: String, wasTriggered: Bool = false) {
		completionWork?.cancel()
		guard wasTriggered || prefix.count >= 2 else {
			completions.hide()
			return
		}

		let work = DispatchWorkItem { [weak self, weak tab] in
			guard let self, let tab else { return }
			Task { @MainActor in await self.showCompletions(for: tab, prefix: prefix) }
		}
		completionWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
	}

	/// Answers ⌃Space: a list now, and a reason when there cannot be one.
	///
	/// Not `scheduleCompletions`, and not because of the prefix rule alone. That
	/// waits 150 ms so a list does not chase somebody's typing, which is right
	/// for typing and wrong for a keystroke whose whole meaning is *now*.
	func completeNow(in tab: Tab, prefix: String) {
		completionWork?.cancel()
		completionWork = nil

		// **Said before the question, not after it.** Asking a server is an
		// await, and until it answers nothing is on screen — measured against
		// sourcekit-lsp at 1.0 s and 6.0 s after ⌃Space on an empty line: an
		// empty popup, then twenty items. That first second is exactly the
		// moment somebody wonders whether the key did anything, and if the
		// reason it is slow is that the server is still starting, that is the
		// answer they need and it is already known here.
		if let codeView = tab.codeView, let languageId = tab.document?.languageId,
		   let root = serverRoot(for: tab), let point = codeView.caretScreenPoint() {
			if let obstacle = LanguageService.shared.notReadySentence(
				languageId: languageId, project: root
			) {
				completions.show(
					notice: obstacle,
					below: point,
					lineHeight: codeView.lineHeightForTesting,
					parent: view.window
				)
			} else {
				// A server with nothing wrong with it can still be slow:
				// sourcekit-lsp, warm and finished preparing, took over a second
				// to answer an empty line. Said after a moment rather than at
				// once — a notice that flashed and was replaced on every fast
				// answer would be worse than the silence it replaces — and only
				// if nothing else has appeared by then.
				let deadline = DispatchTime.now() + 0.15
				DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self, weak tab] in
					guard let self, let tab, self.activeTab === tab,
					      !self.completions.isVisible,
					      let point = tab.codeView?.caretScreenPoint()
					else { return }
					self.completions.show(
						notice: "Asking the \(languageId) server…",
						below: point,
						lineHeight: codeView.lineHeightForTesting,
						parent: self.view.window
					)
				}
			}
		}

		Task { @MainActor in await self.showCompletions(for: tab, prefix: prefix, wasAsked: true) }
	}

	/// Asks again for a list that was told to wait.
	///
	/// Only where the popup is showing the sentence: every other list on screen
	/// is already an answer, and re-asking for one on every server notification
	/// would be a request per start, stop and reconsideration in the window.
	func reaskIfWaitingOnAServer() {
		guard completions.isWaitingOnAServer, let tab = activeTab, let codeView = tab.codeView
		else { return }
		let prefix = codeView.currentWordPrefix()
		Task { @MainActor in await self.showCompletions(for: tab, prefix: prefix) }
	}

	/// Tells a tab's view what its server wants to be woken by.
	///
	/// Asked again when a server finishes starting, because the first keystrokes
	/// in a file are usually typed before it has finished the handshake — and a
	/// trigger set read once, too early, is empty for the life of the tab.
	func refreshCompletionTriggers(for tab: Tab) {
		guard let codeView = tab.codeView, let languageId = tab.document?.languageId,
		      let root = serverRoot(for: tab)
		else { return }
		let completion = LanguageService.shared.completionTriggers(languageId: languageId, project: root)
		codeView.completionTriggerCharacters = Set(completion.compactMap { $0.first })
		let signature = LanguageService.shared.signatureTriggers(languageId: languageId, project: root)
		codeView.signatureTriggerCharacters = Set(signature.compactMap { $0.first })
	}

	// MARK: - What is being filled in


	/// Says what the stop now being filled in takes, or takes the strip away.
	func hintForSnippetStop(_ name: String?, in tab: Tab) {
		guard let name, let codeView = tab.codeView else {
			parameterHint.hide()
			takenDocumentation = nil
			return
		}

		// Where the server has signature help, that is the better answer — it
		// knows the whole call rather than one paragraph — and asking is worth
		// a round trip because the stop has only just been arrived at.
		if let languageId = tab.document?.languageId, let root = serverRoot(for: tab),
		   LanguageService.shared.offersSignatureHelp(languageId: languageId, project: root) {
			askForSignatureHelp(in: tab)
			return
		}

		// **Exact, or nothing.** A near match would put a neighbouring
		// parameter's type under the caret, and a wrong answer here is worse
		// than none because it will be believed.
		guard let prose = takenDocumentation,
		      let description = ServerDocumentation.description(ofParameter: name, in: prose),
		      let point = codeView.caretScreenPoint()
		else {
			parameterHint.hide()
			return
		}

		let text = "\(name) — \(description)"
		let name16 = name.utf16.count
		parameterHint.show(text, emphasising: 0..<name16, above: point, parent: view.window)
	}

	/// Asks the server what call the caret is in, and says so above the line.
	///
	/// **Debounced like the completion list, and for a stronger reason.** The
	/// characters this fires on are `(`, `[`, `,` and `:` — sourcekit-lsp's own
	/// retrigger set — so an argument list typed at speed would otherwise be one
	/// request per comma. One request for where the typing stopped instead.
	///
	/// What one costs, measured against sourcekit-lsp on a warm file: 104 ms for
	/// the first and 1 ms for the five after it. So the debounce is not there to
	/// protect the server — it is cheap once it has answered about a file — but
	/// to stop a request going out for a call nobody has finished typing, whose
	/// answer would arrive and be replaced.
	///
	/// Nothing is sent at all to a server that did not claim the capability;
	/// openscad-lsp is never asked, which is what keeps a `.scad` from waiting
	/// on a reply that never comes.
	func askForSignatureHelp(in tab: Tab) {
		signatureWork?.cancel()
		let work = DispatchWorkItem { [weak self, weak tab] in
			guard let self, let tab else { return }
			Task { @MainActor in await self.showSignatureHelp(for: tab) }
		}
		signatureWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
	}

	@MainActor
	private func showSignatureHelp(for tab: Tab) async {
		guard activeTab === tab, let codeView = tab.codeView, let document = tab.document,
		      let languageId = document.languageId
		else { return }

		// The same reason as the completion list: a call the server has not been
		// told about is a call it answers about the version before it.
		await syncTextNow(for: tab)
		guard activeTab === tab else { return }

		let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: codeView.caretOffset))
		let lineStart = document.rope.utf16Offset(fromByte: document.rope.byteOffset(ofLine: line))
		let character = codeView.caretOffset - lineStart

		guard let root = serverRoot(for: tab) else { return }
		let help = await LanguageService.shared.signatureHelp(
			url: tab.url,
			position: LSPPosition(line: line, character: character),
			languageId: languageId,
			project: root
		)

		guard activeTab === tab, let active = help?.active, let point = codeView.caretScreenPoint()
		else {
			parameterHint.hide()
			return
		}
		parameterHint.show(
			active.signature.label,
			emphasising: active.parameter?.range,
			above: point,
			parent: view.window
		)
	}

	@MainActor
	private func showCompletions(for tab: Tab, prefix: String, wasAsked: Bool = false) async {
		guard activeTab === tab, let codeView = tab.codeView, let document = tab.document else { return }

		// The prefix may have moved on while this was being asked for.
		guard codeView.currentWordPrefix() == prefix else { return }

		var items: [CompletionItem] = []
		if let project, let languageId = document.languageId {
			// Before the question, so it is asked about the text on screen.
			await syncTextNow(for: tab)
			guard activeTab === tab, codeView.currentWordPrefix() == prefix else { return }

			let line = document.rope.line(atByteOffset: document.rope.byteOffset(fromUTF16: codeView.caretOffset))
			let lineStart = document.rope.utf16Offset(fromByte: document.rope.byteOffset(ofLine: line))
			let character = codeView.caretOffset - lineStart

			let fromServer = await LanguageService.shared.completions(
				url: tab.url,
				position: LSPPosition(line: line, character: character),
				languageId: languageId,
				project: serverRoot(for: tab) ?? project.root
			)
			// A server answers about types and scope; the words in the file
			// cannot, so anything it says is worth more than anything they do.
			//
			// Matched on `matchText` — the server's own `filterText` where it
			// sent one — rather than on the label. Neither server driven here
			// labels an item with its name: openscad-lsp's `cube` is labelled
			// `cube(size, center=false)`, which starts with the word by luck,
			// and sourcekit-lsp labels a function with its whole signature, so
			// the label filter threw away most of a Swift answer.
			let typed = prefix.lowercased()
			items = fromServer
				.filter { $0.matchText.lowercased().hasPrefix(typed) }
				.prefix(20)
				.map(CompletionItem.init)
		}

		// **A server that has not finished starting has not said no.** It is the
		// words in the file that used to be shown here, and they look like an
		// answer: measured against a Cadova package, sourcekit-lsp answered
		// nothing at 1, 11, 32 and 62 seconds after the file was opened, and the
		// enum cases somebody was waiting for at 123, once it had built 651
		// files. Four empty answers and a right one, indistinguishable from
		// "this language has nothing to offer" for the whole two minutes.
		if items.isEmpty, let languageId = document.languageId,
		   let root = serverRoot(for: tab),
		   let obstacle = LanguageService.shared.notReadySentence(
			   languageId: languageId, project: root
		   ) {
			guard let point = codeView.caretScreenPoint() else { return }
			completions.show(
				notice: obstacle,
				below: point,
				lineHeight: codeView.lineHeightForTesting,
				parent: view.window
			)
			return
		}

		if items.isEmpty {
			let text = document.rope.string(in: 0..<document.rope.byteCount)
			items = WordCompletions
				.candidates(matching: prefix, in: text, near: codeView.caretOffset)
				.map { CompletionItem(label: $0, isFromServer: false) }
		}

		guard !items.isEmpty, codeView.currentWordPrefix() == prefix else {
			// A question asked on purpose is answered, including when the answer
			// is nothing. Typing that finds nothing simply takes the list away,
			// because there was no question — but ⌃Space over a blank line and
			// then silence is indistinguishable from a key that does not work.
			if wasAsked, let point = codeView.caretScreenPoint() {
				completions.show(
					notice: "No completions here",
					below: point,
					lineHeight: codeView.lineHeightForTesting,
					parent: view.window
				)
			} else {
				completions.hide()
			}
			return
		}

		completionPrefixLength = prefix.utf16.count
		completions.onCommit = { [weak codeView, weak self] item in
			guard let self else { return }
			// Kept for the life of the session the insertion is about to start:
			// for a server with no signature help this is the only thing that
			// knows what the stops mean.
			self.takenDocumentation = item.documentationSource
			// A snippet is not text to paste: `union() $0` means "put the caret
			// between the braces", and inserted as written it is a syntax
			// error somebody has to go back and delete. Where it has more than
			// one place for the caret to go, the view steps through them on Tab.
			let snippet = item.isSnippet
				? Snippet.expand(item.insertText)
				: Snippet(text: item.insertText, caret: item.insertText.utf16.count)
			codeView?.applyCompletion(snippet, replacingPrefixOfLength: self.completionPrefixLength)
		}
		guard let point = codeView.caretScreenPoint() else { return }
		completions.show(
			items: items,
			below: point,
			lineHeight: codeView.lineHeightForTesting,
			parent: view.window
		)
	}

	/// The keys the list takes before the document sees them.
	func handleCompletionKey(_ selector: Selector) -> Bool {
		guard completions.isVisible else { return false }
		switch selector {
		case #selector(NSResponder.moveUp(_:)):     return completions.moveSelection(by: -1)
		case #selector(NSResponder.moveDown(_:)):   return completions.moveSelection(by: 1)
		case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
			return completions.commitSelection()
		case #selector(NSResponder.cancelOperation(_:)):
			completions.hide()
			return true
		default:
			// Arrow keys sideways, or anything else, simply put it away: the
			// caret has left the word the list was built for.
			if selector == #selector(NSResponder.moveLeft(_:))
				|| selector == #selector(NSResponder.moveRight(_:)) {
				completions.hide()
			}
			return false
		}
	}

	/// Follows a ⌘-click to wherever the symbol is defined.
	func goToDefinition(from tab: Tab, line: Int, character: Int) {
		guard let project, let languageId = tab.document?.languageId else { return }
		Task { @MainActor in
			let locations = await LanguageService.shared.definition(
				url: tab.url,
				position: LSPPosition(line: line, character: character),
				languageId: languageId,
				project: serverRoot(for: tab) ?? project.root
			)
			guard let first = locations.first, let url = first.url else { return }
			open(fileURL: url, atLine: first.range.start.line + 1)
		}
	}

	/// Applies whatever a server last said about the files that are open.
	@objc func diagnosticsChanged(_ notification: Notification) {
		guard let url = notification.object as? URL else { return }
		for tab in tabs where tab.url.absoluteString == url.absoluteString {
			applyDiagnostics(to: tab)
		}
	}

	/// What a server said about this tab's file, and how sure it was.
	///
	/// **Whether the server is preparing is asked here, on the path the
	/// diagnostics already take**, rather than being carried with them: it is a
	/// fact about the server at the moment of drawing, and it changes without
	/// any diagnostic arriving to say so.
	func applyDiagnostics(to tab: Tab) {
		guard let codeView = tab.codeView else { return }
		let preparing = isServerPreparing(for: tab)
		codeView.setDiagnostics(
			LanguageService.shared.diagnostics(for: tab.url), fromPreparingServer: preparing
		)
	}

	/// Whether the server that answers for this tab's file has said it is not
	/// ready.
	///
	/// By project and language, which is what `isPreparing` is keyed by and what
	/// a tab knows about its own file — so a window holding a preparing Swift
	/// server and a settled Go one behaves correctly by construction rather than
	/// by a special case.
	private func isServerPreparing(for tab: Tab) -> Bool {
		guard let languageId = tab.document?.languageId,
		      let root = serverRoot(for: tab) ?? project?.root
		else { return false }
		return LanguageService.shared.isPreparing(languageId: languageId, project: root)
	}
}
