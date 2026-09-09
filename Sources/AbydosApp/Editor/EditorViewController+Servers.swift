import AppKit
import CryptoKit
import QuickLookUI
import GoSTL
import AbydosKit
import SwiftUI

/// The language server behind the file in front: what it is told, what it is
/// asked, and the history the editor keeps of what it answered.
extension EditorViewController {
	// MARK: - Language servers

	/// Whole text of a document, which is what full synchronisation sends.
	///
	/// Still on the caller's thread, and the caller is usually the main one.
	/// That is fine for the two callers that open a file, which happen once
	/// each; the two that repeat go through `withText(of:)` below.
	func text(of document: TextDocument) -> String {
		document.rope.string(in: 0..<document.rope.byteCount)
	}

	/// Where a file's text is decoded for a language server.
	///
	/// Serial, so two of these cannot cross. A `didChange` carries a version
	/// number and a whole file, and the older of two arriving last would leave
	/// the server describing text that nobody has. A serial queue delivers the
	/// builds in the order they were asked for, and each hands back to the main
	/// queue as it finishes, so the order survives both hops.
	static let languageTextQueue = DispatchQueue(
		label: "abydos.languagetext", qos: .userInitiated
	)

	/// Builds a document's whole text away from the main queue and sends it from
	/// the main queue once it is built.
	///
	/// 0437 left this on the main thread and called it a trade wanting a
	/// measurement, on the grounds that the rope is edited on the main thread
	/// and reading it anywhere else is a race. That is true of the *document* —
	/// the main thread reassigns `TextDocument.rope` on every keystroke — and it
	/// is not true of a `Rope`, which is persistent and `Sendable`: taking the
	/// value is a reference bump, and nothing can change it afterwards. It is
	/// the same free snapshot `TextDocument.symbols` already hands to the
	/// parser's queue, three hundred lines above where the doubt was written.
	///
	/// So there is no trade and nothing to measure. Decoding a megabyte of UTF-8
	/// into a `String` is the whole cost, it happens every 0.4 s of typing and on
	/// every auto-save, and it is now on a queue the keyboard does not share.
	///
	/// Through `WeakRelay` rather than two nested `async` calls, and 0465 is why:
	/// written the obvious way the inner `[weak self]` bought nothing, because the
	/// outer closure had to hold `self` strongly to build it. The editor was kept
	/// alive for the length of every decode in flight, which is exactly the gap
	/// the guard below was written for.
	func withText(
		of document: TextDocument, send: @escaping (String) -> Void
	) {
		let snapshot = document.rope
		WeakRelay.build(on: EditorViewController.languageTextQueue, for: self) {
			snapshot.string(in: 0..<snapshot.byteCount)
		} then: { editor, text in
			// Closed while its text was being decoded. There is no gap to
			// close today, because the send follows the build immediately;
			// there is one now, and a `didChange` for a file the editor no
			// longer holds is one the server cannot make sense of.
			guard editor.tabs.contains(where: { $0.document === document }) else { return }
			StallWatch.mark("language sync") { send(text) }
		}
	}

	/// Tells the server what changed, once the typing pauses.
	///
	/// Debounced because a keystroke is not worth a round trip: a server asked
	/// to reparse on every character spends its time on text nobody has
	/// finished writing, and the diagnostics that come back are about a
	/// half-typed line.
	func scheduleLanguageSync(for tab: Tab) {
		languageSyncWork?.cancel()
		let work = DispatchWorkItem { [weak self, weak tab] in
			guard let self, let tab, let document = tab.document,
			      let languageId = document.languageId
			else { return }
			// Nothing is waiting to be sent once this has run, which is what
			// `showCompletions` reads to decide whether it has to send it first.
			self.languageSyncWork = nil
			let url = tab.url
			guard let root = self.serverRoot(for: tab) else { return }
			withText(of: document) { text in
				LanguageService.shared.changed(
					url: url, languageId: languageId, text: text, project: root
				)
			}
		}
		languageSyncWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
	}

	/// Sends what is waiting, now, and does not come back until it has gone.
	///
	/// **A question about text the server has not been told about is answered
	/// about different text.** The sync is debounced at 0.4 s and a completion
	/// at 0.15 s, so every list was asked for against a document one or two
	/// keystrokes stale. With a word prefix that mostly went unnoticed — the
	/// server answered about the same identifier a moment earlier and the
	/// answer looked right. Driven against a Swift package it was unmissable:
	/// `Corner.` typed at the end of a file asked about a position past the end
	/// of the file the server held, and sourcekit-lsp answered with a *global*
	/// list — `LazyMapCollection`, `LazyFilterSequence` — where the four cases
	/// of the enum were what had been asked for.
	///
	/// The decode still happens off the main thread; what is new is waiting for
	/// it. That costs one decode per list rather than one per 0.4 s of typing,
	/// which is the price of the answer being about the right text.
	func syncTextNow(for tab: Tab) async {
		guard languageSyncWork != nil else { return }
		languageSyncWork?.cancel()
		languageSyncWork = nil

		guard let document = tab.document, let languageId = document.languageId,
		      let root = serverRoot(for: tab)
		else { return }
		let url = tab.url
		let snapshot = document.rope

		let text = await withCheckedContinuation { continuation in
			EditorViewController.languageTextQueue.async {
				continuation.resume(returning: snapshot.string(in: 0..<snapshot.byteCount))
			}
		}
		// Ordering is the whole point and it is the wire that provides it: this
		// notification and the request that follows go down the same pipe, so
		// the server has read the change before it reads the question.
		LanguageService.shared.changed(url: url, languageId: languageId, text: text, project: root)
	}

	// MARK: - History

	/// Shows every state the file has been in, including the ones undo cannot
	/// reach because something else was typed after them.
	func toggleFileHistory() {
		guard let tab = activeTab, let document = tab.document, let codeView = tab.codeView else { return }
		historyPopup.onTravel = { [weak self] state in
			guard let restored = document.travel(to: state) else { return }
			codeView.setCaretForTesting(restored)
			codeView.reloadAfterHistoryTravel()
			self?.refreshTabBar()
		}
		historyPopup.toggle(history: document.history, over: codeView)
	}

	func focusForTesting() {
		guard let codeView = activeTab?.codeView else { return }
		view.window?.makeFirstResponder(codeView)
	}

	/// Presses return, through the same command a key press produces.
	func simulateReturn() {
		guard let codeView = activeTab?.codeView else { return }
		view.window?.makeFirstResponder(codeView)
		codeView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
	}

	/// Tab, which steps to the next snippet stop while a session is live and
	/// indents the rest of the time.
	func simulateTab() {
		guard let codeView = activeTab?.codeView else { return }
		view.window?.makeFirstResponder(codeView)
		codeView.doCommand(by: #selector(NSResponder.insertTab(_:)))
	}

	/// Escape, which is how somebody says they have finished with the stops.
	func simulateEscape() {
		guard let codeView = activeTab?.codeView else { return }
		view.window?.makeFirstResponder(codeView)
		codeView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
	}

	/// Takes a completion the way the list does, then works the keys, saying
	/// where the caret and the selection are after each one.
	///
	/// The spec is a server's own `insertText` and then what to do to it, `|`
	/// between: `tab`, `backtab`, `esc`, `home` and `end` are those keys, and
	/// anything else is typed a character at a time. So
	///
	///     cube(size = ${1:size}, center = false);$0|10|tab
	///
	/// is what openscad-lsp answers `cube` with, `10` typed over the stop it
	/// selects, and Tab to the end of the line.
	///
	/// Through `applyCompletion` and `doCommand` — the same two doors a chosen
	/// completion and a key press come through — because what is worth watching
	/// is whether Tab reaches the stops, and a driver that called the stepping
	/// method directly would prove nothing about that.
	func exerciseSnippetForTesting(_ spec: String) {
		guard let codeView = codeViewToDrive("--snippet") else {
			print("SNIPPET: no editor")
			return
		}
		view.window?.makeFirstResponder(codeView)

		let steps = spec.components(separatedBy: "|")
		codeView.applyCompletion(Snippet.expand(steps[0]), replacingPrefixOfLength: 0)
		print("SNIPPET inserted: \(codeView.caretReportForTesting)")

		for step in steps.dropFirst() {
			switch step {
			case "tab":     codeView.doCommand(by: #selector(NSResponder.insertTab(_:)))
			case "backtab": codeView.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
			case "esc":     codeView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
			case "home":    codeView.doCommand(by: #selector(NSResponder.moveToBeginningOfLine(_:)))
			case "end":     codeView.doCommand(by: #selector(NSResponder.moveToEndOfLine(_:)))
			default:        simulateTyping(step)
			}
			print("SNIPPET \(step): \(codeView.caretReportForTesting)")
		}

		for line in textTailLinesForTesting(3) where !line.isEmpty {
			print("SNIPPET line: |\(line.replacingOccurrences(of: "\t", with: "→"))|")
		}
		fflush(stdout)
	}

	/// The last few lines of the file, for looking at what typing produced.
	func textTailLinesForTesting(_ count: Int) -> [String] {
		guard let document = activeTab?.document else { return [] }
		let text = document.rope.string(in: 0..<document.rope.byteCount)
		let lines: [String] = text.components(separatedBy: "\n")
		return Array(lines.suffix(count))
	}

	/// One line of the file, for watching a key that deletes.
	///
	/// The caret report says nothing about ⌃K: a forward delete leaves the
	/// caret where it was, so the only difference between the key working and
	/// the key doing nothing is in the text. `textTailForTesting` answers the
	/// same question for the *end* of a file, and a driver pressing a deleting
	/// key in the middle of one has to name the line.
	/// ⌘V over a picture in the open document, from a board of the run's own,
	/// so the general clipboard is left alone. Says what was written and what
	/// the caret's line now reads, which is the whole of the claim.
	func pastePictureForTesting(_ picture: URL) {
		guard let codeView = codeViewToDrive("paste-picture") else {
			print("EDITOR paste-picture: nothing to drive")
			return
		}
		view.window?.makeFirstResponder(codeView)
		let board = NSPasteboard(name: NSPasteboard.Name("abydos.driven.paste-picture.\(UUID().uuidString)"))
		defer { board.releaseGlobally() }
		board.clearContents()
		board.setData(
			(try? Data(contentsOf: picture)) ?? Data(),
			forType: picture.pathExtension.lowercased() == "tiff" ? .tiff : .png
		)
		let started = Date()
		codeView.paste(from: board)
		let took = Date().timeIntervalSince(started)
		let written = codeView.lastPastedPictureForTesting.map { file -> String in
			let folder = activeTab?.url.deletingLastPathComponent().path ?? ""
			return file.path.replacingOccurrences(of: folder + "/", with: "")
		} ?? "nothing"
		print("EDITOR paste-picture: \(written)" + String(format: " in %.3f s", took)
			+ " line=\(codeView.caretLine) text=\(lineTextForTesting(codeView.caretLine))"
			+ " \(codeView.caretReportForTesting)")
	}

	func lineTextForTesting(_ line: Int) -> String {
		guard let document = activeTab?.document else { return "no file" }
		guard line >= 0, line < document.rope.lineCount else { return "no line \(line)" }
		return document.rope.lineText(line)
	}

	func goToDefinitionForTesting(line: Int, character: Int) {
		guard let tab = activeTab else { return }
		goToDefinition(from: tab, line: line, character: character)
	}

	func hoverWithCommandForTesting(line: Int, character: Int) {
		activeTab?.codeView?.hoverWithCommandForTesting(line: line, character: character)
	}

	func undoForTesting() {
		codeViewToDrive("--undo-tree")?.undo(nil)
	}

	/// The last line or two of the file, for checking what a jump produced.
	var textTailForTesting: String {
		guard let document = activeTab?.document else { return "no file" }
		let text = document.rope.string(in: 0..<document.rope.byteCount)
		return text.split(separator: "\n").suffix(2).joined(separator: " / ")
	}

	var fileHistoryReportForTesting: String {
		guard let document = activeTab?.document else { return "no file" }
		let history = document.history
		return "\(history.count) states, at \(history.current), "
			+ "\(history.futures.count) way(s) forward"
	}

	func showFileHistoryForTesting() {
		toggleFileHistory()
	}

	var historySummariesForTesting: [String] { historyPopup.summariesForTesting }

	func travelToHistoryRowForTesting(_ index: Int) {
		historyPopup.travelToRowForTesting(index)
	}
}
