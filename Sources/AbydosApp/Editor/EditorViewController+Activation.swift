import AppKit
import CryptoKit
import QuickLookUI
import GoSTL
import AbydosKit
import SwiftUI

/// Which page is in front, closing one, and the commands the editor answers.
extension EditorViewController {
	// MARK: - Activation

	func activate(index: Int, focusEditor: Bool) {
		guard tabs.indices.contains(index) else { return }
		// Insert is turned off when a hex tab is left, so a mode nobody is
		// looking at cannot shift a file by a byte when they come back.
		if let leaving = activeTab, leaving !== tabs[index] { leaving.hex?.tabWasLeft() }

		// Whether the keyboard is in the tab about to be taken off screen.
		//
		// Item 523, and the half of it that is not about the results list.
		// `removeFromSuperview` on a view that holds the window's first responder
		// does not move the responder along — it resets it to the **window**,
		// which is nobody at all, and every keystroke after that reaches nothing.
		// It is invisible whenever `focusEditor` is true, because the branch at
		// the bottom puts a responder back; it is exactly visible when it is
		// false, which is every open that is deliberately not meant to move the
		// keyboard. Measured with the caret in the editor and a result row
		// clicked: `who` said `NSWindow`.
		//
		// Asked before the removal, because after it the answer is gone.
		let keyboardWasInTheTabLeaving = (view.window?.firstResponder as? NSView)
			.map { $0.isDescendant(of: contentArea) } ?? false

		// Swap the installed content view; the outgoing one keeps its state.
		contentArea.subviews.forEach { $0.removeFromSuperview() }

		let tab = tabs[index]
		activeIndex = index

		let content = tab.contentView
		content.translatesAutoresizingMaskIntoConstraints = false
		contentArea.addSubview(content)
		NSLayoutConstraint.activate([
			content.topAnchor.constraint(equalTo: contentArea.topAnchor),
			content.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
			content.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
			content.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
		])

		// A binary tab has no language to report.
		statusLanguage = tab.document?.displayLanguageName
		// Nor a caret. The indicator is one control shared by the whole group,
		// so a tab arriving without saying where its caret is leaves the line
		// the *previous* tab was on next to the new tab's language. Easiest to
		// see with `abydos deep.txt:150 main.go`, which put "150:1 Go" beside a
		// two-line file — but any click between two tabs did the same.
		tab.codeView?.reportCaretPosition()
		// Find belongs to the tab, so the bar shows this one's. Placed here, with
		// the other things a tab brings with it, and deliberately clear of the
		// responder handling below — where the keyboard goes after a switch is
		// settled twice already, with the measurements in those comments.
		restoreFind(for: tab)
		onStatusChanged?(self)
		refreshServerState()
		updateChrome()
		refreshTabBar()
		onActivated?(self)

		if focusEditor {
			// A notice tab has no code view to focus.
			view.window?.makeFirstResponder(tab.hex?.editor ?? tab.codeView ?? tab.contentView)
		} else if keyboardWasInTheTabLeaving {
			// Nobody asked for the keyboard to move, and the removal above took it
			// from the view that had it. Putting it in the tab now showing is what
			// "do not move the keyboard" meant: it was in this editor before and it
			// is in this editor after. This can only ever *keep* the keyboard in
			// the editor — a responder outside `contentArea` never reaches here —
			// so a results row clicked with the keyboard in the list is untouched,
			// which is item 510's rule and must stay true.
			view.window?.makeFirstResponder(tab.hex?.editor ?? tab.codeView ?? tab.contentView)
		}
		onActiveFileChanged?(tab.url)
	}

	func promoteToPermanent(index: Int) {
		guard tabs.indices.contains(index) else { return }
		tabs[index].isPreview = false
		activate(index: index, focusEditor: true)
	}

	func refreshTabBar() {
		let items = tabs.map { tab in
			let scratch = ScratchFiles.isScratch(tab.url)
			return EditorTabItem(
				url: tab.url,
				title: tab.pageTitle
					?? (scratch ? ScratchFiles.title(for: tab.url) : tab.url.lastPathComponent),
				// A scratch keeps its dot whether or not it is written out. It
				// has nowhere in the project it belongs to, and the dot is what
				// says so — the same mark Sublime and Zed leave on one.
				isDirty: tab.isDirty || scratch,
				isPreview: tab.isPreview,
				subtitle: tab.pageTitle != nil
					? (tab.pageSubtitle ?? "")
					: tab.archiveOrigin?.said ?? tab.diffCommit ?? (tab.isDiff ? "diff" : (scratch ? "scratch" : relativeDirectory(for: tab.url))),
				pageSymbol: tab.pageSymbol,
				isExternal: tab.pageTitle == nil && !scratch && !tab.isDiff && tab.archiveOrigin == nil && isOutsideProject(tab.url)
			)
		}
		tabBar.setItems(items, activeIndex: activeIndex)
		onTabsChanged?()

		// The control belongs to the active tab: a file with no rendered form
		// shows none, so the strip does not offer something that does nothing.
		if let tab = activeTab, !tab.isDiff {
			let modes = availableModes(for: tab)
			tabBar.setPreview(
				// One mode is no choice: a PNG and a binary mesh each have only
				// their rendered form, and a control whose menu holds the item
				// that is already chosen is a button that does nothing.
				modes: modes.count > 1 ? modes : [],
				current: tab.previewMode
			)
		} else {
			tabBar.setPreview(modes: [], current: .source)
		}
	}

	private func relativeDirectory(for url: URL) -> String {
		guard let root = project?.root, !isOutsideProject(url) else { return outsideProject(url) }
		let base = FilePath.canonical(root)
		let path = FilePath.canonical(url)
		let relative = String(path.dropFirst(base.count + 1))
		return (relative as NSString).deletingLastPathComponent
	}

	/// Whether a file lives outside the project that is open.
	func isOutsideProject(_ url: URL) -> Bool {
		guard let root = project?.root else { return true }
		return !FilePath.canonical(url).hasPrefix(FilePath.canonical(root) + "/")
	}

	/// A file that is not in the project, said so.
	///
	/// Without this it reads like a file at the project's root — same tab, same
	/// blank subtitle — and editing the wrong copy of a file is a mistake that
	/// takes a while to notice.
	private func outsideProject(_ url: URL) -> String {
		let directory = url.deletingLastPathComponent().path
		let home = NSHomeDirectory()
		let shown = directory.hasPrefix(home + "/") || directory == home
			? "~" + directory.dropFirst(home.count)
			: directory[...]
		return "↗ " + shown
	}

	// MARK: - Closing

	func closeTab(at index: Int) {
		guard tabs.indices.contains(index) else { return }
		let tab = tabs[index]

		// With auto save on, closing must not interrogate the user — it just
		// writes, which is the whole point of the setting.
		if tab.isDirty, tab.document?.autoSaveIfNeeded() != true, !confirmDiscard(for: tab) {
			return
		}

		removeTab(at: index)
		discardIfEmptyScratch(tab)
	}

	/// Takes a tab out and settles on what to show instead, asking nothing.
	func removeTab(at index: Int) {
		guard tabs.indices.contains(index) else { return }

		announceClosed(tabs[index])
		tabs[index].hex?.close()
		teardown(tabs[index])
		tabs.remove(at: index)

		if tabs.isEmpty {
			activeIndex = nil
			contentArea.subviews.forEach { $0.removeFromSuperview() }
			updateChrome()
			refreshTabBar()
			onActiveFileChanged?(nil)
			onBecameEmpty?(self)
			return
		}

		// Prefer the tab that slid into this slot, else the one before it.
		let next = min(index, tabs.count - 1)
		activeIndex = nil
		activate(index: next, focusEditor: false)
	}

	/// Returns true if the caller should proceed with closing.
	func confirmDiscard(for tab: Tab) -> Bool {
		let alert = NSAlert()
		alert.messageText = "Save changes to \(tab.url.lastPathComponent)?"
		alert.informativeText = "Your changes will be lost if you don't save them."
		alert.addButton(withTitle: "Save")
		alert.addButton(withTitle: "Discard")
		alert.addButton(withTitle: "Cancel")

		switch alert.runModal() {
		case .alertFirstButtonReturn:
			// Never `save()` for a decrypted buffer: that would write the
			// plaintext over the ciphertext, which is the one thing this whole
			// feature exists not to do.
			if tab.isDecrypted { return encryptAndSaveSync(tab) }
			do {
				try tab.document?.save()
				return true
			} catch {
				Toast.post("Could not save \(tab.url.lastPathComponent)", detail: error.localizedDescription)
				return false
			}
		case .alertSecondButtonReturn:
			return true
		default:
			return false
		}
	}

	/// Tells the server about a file this group has stopped showing.
	///
	/// A file nobody has open is one the server can stop thinking about. Said
	/// once per tab that goes, and only when no other tab here is still showing
	/// the same file.
	func announceClosed(_ closing: Tab) {
		guard let languageId = closing.document?.languageId,
		      let root = serverRoot(for: closing),
		      !tabs.contains(where: { $0 !== closing && $0.url == closing.url })
		else { return }
		LanguageService.shared.closed(
			url: closing.url, languageId: languageId, project: root
		)
	}

	func teardown(_ tab: Tab) {
		if let scrollView = tab.contentView as? NSScrollView {
			NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
		}
		tab.document?.onSyntaxUpdated = nil
		tab.contentView.removeFromSuperview()
	}

	private func presentUnopenable(_ url: URL, reason: String) {
		Toast.post("Cannot open \(url.lastPathComponent)", detail: reason, kind: .warning)
	}

	// MARK: - Commands

	func save() {
		guard let tab = activeTab else { return }
		// An entry inside an archive is read only, and ⌘S is where somebody
		// finds that out — so it says where the file is and how to get one
		// that can be changed, rather than writing into the cache.
		if let origin = tab.archiveOrigin {
			Toast.post(
				"\(tab.url.lastPathComponent) is inside \(origin.archive.lastPathComponent)",
				detail: "Use Extract… on it in the project tree to make a file you can change.",
				kind: .information
			)
			return
		}
		// A decrypted buffer is never written as it is: ⌘S sends it through the
		// encrypt path — which runs `sops` over the file when something was
		// edited into it, and only locks it back when nothing was — and the
		// plaintext stays where it was.
		if tab.isDecrypted {
			Task { @MainActor in await self.encryptAndSave(tab) }
			return
		}
		// A `.drawio` is edited by draw.io rather than by this app, and draw.io
		// reports a change a fraction of a second after it happens. That is soon
		// enough for the dot but not for ⌘S, which somebody may press while
		// still holding the shape they dragged — so the editor is asked what it
		// has before the file is written. Every other tab writes straight away,
		// exactly as it always did.
		if let pane: DrawioPreviewView = Self.pane(in: tab.contentView) {
			Task { @MainActor in
				await pane.flush()
				self.write(tab)
			}
			return
		}
		write(tab)
	}

	private func write(_ tab: Tab) {
		do {
			if let hex = tab.hex {
				try hex.save()
			} else {
				try tab.document?.save()
			}
			refreshTabBar()
			told(tab, wasSaved: true)
			refreshChangedLines(for: tab)
		} catch {
			Toast.post("Could not save \(tab.url.lastPathComponent)", detail: error.localizedDescription)
		}
	}

	/// Tells the language server the file is now on disk.
	///
	/// **`didChange` is not `didSave`, and nothing was sending the second one for
	/// a save somebody made.** `LanguageService.saved` had exactly one caller,
	/// `reloadExternallyChangedFiles` — so a server was told a file had been
	/// saved when *something else* wrote it, and never when the person at the
	/// keyboard did. For most servers that is invisible: they answer about the
	/// text they were given either way, which is why it went unnoticed for as
	/// long as it did.
	///
	/// For jdtls it is the difference between a build that compiles and one that
	/// does nothing. Eclipse builds *resources*, not dirty working copies, so
	/// `vscode.java.buildWorkspace` after a save with no `didSave` recompiled
	/// nothing and answered "Build completed" — measured on the hot-swap example,
	/// where the source was saved at 05:52:38 and `target/classes` still held a
	/// class file from 05:51:04 with the old string in it.
	private func told(_ tab: Tab, wasSaved: Bool) {
		guard wasSaved, let document = tab.document, let languageId = document.languageId,
		      let root = serverRoot(for: tab)
		else { return }
		let url = tab.url
		let snapshot = document.rope
		Task { @MainActor in
			let text = await withCheckedContinuation { continuation in
				EditorViewController.languageTextQueue.async {
					continuation.resume(returning: snapshot.string(in: 0..<snapshot.byteCount))
				}
			}
			LanguageService.shared.saved(
				url: url, languageId: languageId, text: text, project: root
			)
		}
	}

	func closeActiveTab() {
		guard let activeIndex else { return }
		closeTab(at: activeIndex)
	}

	func selectNextTab(offset: Int) {
		guard !tabs.isEmpty, let activeIndex else { return }
		let next = (activeIndex + offset + tabs.count) % tabs.count
		activate(index: next, focusEditor: true)
	}

	/// Returns keyboard focus to the code view, used when the panel closes.
	func focusActiveEditor() {
		guard let tab = activeTab else { return }
		view.window?.makeFirstResponder(tab.hex?.editor ?? tab.codeView ?? tab.contentView)
	}

	/// Shows or hides who last touched each line, for the file in front.
	///
	/// Per editor rather than for all of them: blame is something you turn on
	/// to answer a question about one file, and a column of names beside every
	/// other file afterwards is not what anybody asked for.
	/// Drives the editor's context menus from outside: `gutter` and `text`
	/// print the menu a right-click builds on each side of the boundary,
	/// `blame` presses the toggle the gutter's entry presses.
	func editorMenuForTesting(_ steps: String) {
		let script = steps.split(separator: ",").map(String.init)
		for (index, step) in script.enumerated() {
			// `settle` waits, as the sops driver's does: blame arrives from git
			// a moment after the toggle, and a report taken before it says nothing.
			if step.hasPrefix("settle") {
				let seconds = step.hasPrefix("settle:") ? Double(step.dropFirst("settle:".count)) ?? 1.5 : 1.5
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.editorMenuForTesting(rest)
				}
				return
			}
			// The two reports that need no editor come first: after a click on
			// a blame entry the log page is the front tab, and that is what
			// they are there to say.
			if step == "pages" {
				print("EDITOR-MENU pages: \(tabTitlesForTesting.joined(separator: ", "))")
				continue
			}
			if step == "log-report" {
				(view.window?.windowController as? MainWindowController)?.sidebarForTesting.logPageForTesting("report")
				continue
			}
			guard let codeView = activeTab?.codeView else {
				print("EDITOR-MENU: no editor for \(step)")
				continue
			}
			switch step {
			case "gutter":
				print("EDITOR-MENU gutter: \(codeView.contextMenuReportForTesting(atGutter: true))")
			case "text":
				print("EDITOR-MENU text: \(codeView.contextMenuReportForTesting(atGutter: false))")
			case let step where step.hasPrefix("gutter-right:"):
				// A right-click at the gutter's left edge on a line, through
				// the same decision the real one takes.
				let line = Int(step.dropFirst("gutter-right:".count)) ?? 1
				print("EDITOR-MENU gutter-right \(line): \(codeView.gutterRightClickReportForTesting(line: line - 1))")
			case "blame":
				toggleBlame()
			case let step where step.hasPrefix("blame-click:"):
				// The click on a line's entry, through the same callback.
				let line = Int(step.dropFirst("blame-click:".count)) ?? 1
				if let entry = codeView.blameEntry(forLine: line - 1) {
					print("EDITOR-MENU blame-click \(line): \(entry.shortCommit) \(entry.author)\(entry.isUncommitted ? " uncommitted" : "")")
					codeView.onShowBlameDetail?(entry)
				} else {
					print("EDITOR-MENU blame-click \(line): no entry")
				}
			case let step where step.hasPrefix("blame-hover:"):
				// The pointer on a line's entry, for the lit run and the tip's words.
				let line = Int(step.dropFirst("blame-hover:".count)) ?? 1
				print("EDITOR-MENU blame-hover \(line): \(codeView.hoverBlameForTesting(line: line - 1))")
			case "blame-report":
				print("EDITOR-MENU blame: visible=\(codeView.isBlameVisible) authors=\(codeView.blameEntriesForTesting.map(\.author).joined(separator: ","))")
			default:
				print("EDITOR-MENU: unknown step \(step)")
			}
		}
		fflush(stdout)
	}
}
