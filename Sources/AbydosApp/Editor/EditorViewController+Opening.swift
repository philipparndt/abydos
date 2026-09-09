import AppKit
import CryptoKit
import QuickLookUI
import GoSTL
import AbydosKit
import SwiftUI

/// Opening a file: which group it goes in, what kind of page it becomes, and
/// the scratch files that have no path until they are saved.
extension EditorViewController {
	// MARK: - Project

	func setProject(_ project: Project) {
		self.project = project
	}

	// MARK: - Scratch files

	/// Somewhere to put something that is not part of the project.
	///
	/// A real file, so it highlights, folds and searches like anything else —
	/// but one kept outside the repository, where it cannot end up in a commit.
	/// A global one belongs to no project: notes about a language or a way of
	/// doing something, which outlive whichever checkout they were written in.
	func newScratch(global: Bool = false) {
		let files: ScratchFiles
		if global {
			files = .global()
		} else {
			guard let root = project?.root else { return }
			files = ScratchFiles(projectRoot: root)
		}

		do {
			let url = try files.create()
			open(fileURL: url, focusEditor: true)
			NotificationCenter.default.post(name: .ideaiScratchesChanged, object: nil)
		} catch {
			presentScratchFailure(error)
		}
	}

	/// Reopens the scratches this project was left with.
	///
	/// The ones that were open, not every one it has: after a few weeks those
	/// are different numbers, and a window full of old notes is not a restored
	/// workspace. Anything not reopened is still in the Scratches pane — this
	/// decides which tabs come back, never which notes exist.
	func restoreScratches() {
		guard let project else { return }

		// No record yet — the first launch after this was added, or a project
		// only ever opened before it. What it has is the best guess at what it
		// had open. Asked under `sessionRoot`, which is what recorded them.
		let remembered = OpenScratches().existing(forProject: project.sessionRoot)
			?? ScratchFiles(projectRoot: project.root).all()

		for url in remembered where !tabs.contains(where: { $0.url == url }) {
			open(fileURL: url, focusEditor: false)
		}
	}

	/// The scratches open in this group, in tab order.
	var openScratchURLs: [URL] {
		tabs.map(\.url).filter { ScratchFiles.isScratch($0) }
	}

	/// Throws away a scratch that was closed with nothing in it.
	///
	/// Without this every stray double-click would come back at the next open,
	/// for ever. One with something in it is kept: nobody else has that text.
	func discardIfEmptyScratch(_ tab: Tab) {
		// Not asked which project it belongs to: closing everything to swap
		// projects happens once the window has already taken the new one, and
		// the tabs going away are still the old one's.
		guard ScratchFiles.isScratch(tab.url) else { return }

		// Empty on disk and empty in the editor. Both, because a document that
		// still holds text the disk does not is exactly the case where throwing
		// the file away would lose something — whether the write failed or the
		// text was never written at all. A scratch is the only copy of what is
		// in it, so anything short of certainly-nothing is kept.
		if let document = tab.document, !document.isEmptyText { return }
		let size = (try? tab.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
		guard size == 0 else { return }

		// To the Trash even though it is empty: nothing here is certain enough
		// to be worth an unrecoverable delete.
		_ = try? ScratchFiles.moveToTrash(tab.url)
		NotificationCenter.default.post(name: .ideaiScratchesChanged, object: nil)
	}

	/// Writes an open scratch out before something else moves it.
	///
	/// A rename that left unsaved text behind would either lose it or write it
	/// back to the name the file no longer has.
	func saveIfOpen(_ url: URL) {
		guard let tab = tabs.first(where: { $0.url == url }), tab.isDirty else { return }
		try? tab.document?.save()
	}

	/// The scope moved, so every open file is announced again.
	///
	/// A file opened while the whole checkout was in view went to the server for
	/// the checkout; working on the subproject it belongs to gives it a
	/// different server, and one that has never heard of it answers nothing
	/// about it. `LanguageService.opened` is what closes it at the old one and
	/// opens it at the new, and does nothing at all when they are the same.
	func rescope() {
		guard project != nil else { return }
		for tab in tabs {
			guard !tab.isDiff, let document = tab.document, let languageId = document.languageId
			else { continue }
			// Re-worked out rather than reused: a rescope is exactly when a
			// file may have changed which root owns it.
			tab.serverRoot = nil
			guard let root = serverRoot(for: tab) else { continue }
			LanguageService.shared.opened(
				url: tab.url, languageId: languageId, text: text(of: document),
				project: root
			)
		}
		refreshServerState()
	}

	/// A scratch was renamed, moved, or thrown away: follow it.
	func scratchMoved(from: URL, to destination: URL?) {
		guard let index = tabs.firstIndex(where: { $0.url == from }) else { return }
		let wasActive = activeIndex == index
		removeTab(at: index)
		if let destination { open(fileURL: destination, focusEditor: wasActive) }
	}

	private func presentScratchFailure(_ error: Error) {
		Toast.post("Could not create a scratch file", detail: error.localizedDescription)
	}

	// MARK: - Opening

	/// Opens a file.
	///
	/// - `preview`: a single click in the tree opens provisionally, reusing the
	///   one preview slot. A double-click (or editing) makes it permanent.
	/// - Already-open files are activated rather than reopened, which is what
	///   makes clicking a file in the tree select its existing tab.
	/// The tab already showing a file, whatever spelling of its path is asked.
	///
	/// **Two names for one file is the ordinary case, not the exotic one.** A
	/// project reached through a symlink has two: the one somebody typed and the
	/// one the file system answers with. `/tmp` is itself a symlink to
	/// `/private/tmp` on every Mac, so a project under it has two spellings
	/// before anybody has done anything unusual.
	///
	/// That is not hypothetical here. `abydos <file>` in a pane resolves its
	/// argument with `pwd -P`, because a shell's idea of where it is has to be
	/// made absolute before it can be sent anywhere — and the app is holding the
	/// unresolved name. Compared as URLs, those are different files, so the
	/// command opened a second tab onto the file already on screen.
	///
	/// Compared here rather than by canonicalising the tab's URL, because the
	/// URL a tab holds is what is *shown* — in the tab, the title and the
	/// breadcrumbs — and rewriting somebody's `~/dev/thing` into
	/// `/private/var/…` to win an argument about identity would be a poor trade.
	/// The tab keeps the name it was opened under; only the question "is this
	/// already open" is asked in the file system's terms.
	///
	/// `FilePath.canonical` is the same answer breakpoints needed, for the same
	/// reason: one keyed `/tmp/x` never matched the `/private/tmp/x` the
	/// debugger reported, and so was set and never hit.
	private func indexOfTab(showing fileURL: URL) -> Int? {
		if let exact = tabs.firstIndex(where: { $0.url == fileURL }) { return exact }
		let wanted = FilePath.canonical(fileURL)
		return tabs.firstIndex { FilePath.canonical($0.url) == wanted }
	}

	/// - Parameters:
	///   - preview: a provisional tab, the italic one a single click opens.
	///   - mode: how to show it, when a session remembered. Nil is not `.source`
	///     but "whatever this kind of file opens as" — see `FilePreview`.
	///   - dividerFraction: where the divider was, for a mode that has one.
	func open(
		fileURL: URL,
		focusEditor: Bool = false,
		preview: Bool = false,
		mode: PreviewMode? = nil,
		dividerFraction: Double? = nil
	) {
		let departure = currentPlace
		defer {
			DispatchQueue.main.async { [weak self] in
				guard let self, let arrival = self.currentPlace else { return }
				self.reportNavigation(from: departure, to: arrival)
			}
		}

		if let existing = indexOfTab(showing: fileURL) {
			// Committing to a file that is currently provisional pins it.
			if !preview { tabs[existing].isPreview = false }
			activate(index: existing, focusEditor: focusEditor)
			return
		}

		guard let tab = makeTab(
			for: fileURL, preview: preview, mode: mode, dividerFraction: dividerFraction
		) else { return }

		if preview, let previewIndex = tabs.firstIndex(where: { $0.isPreview }) {
			// Replace the provisional tab in place, so it does not jump position.
			//
			// The file it held is told to the server as closed, which replacement
			// did not do: the slot is recycled rather than removed, so nothing went
			// through `removeTab`, and walking a usage list through forty files
			// left forty documents open at a server that had been told about every
			// one of them and about the end of none.
			announceClosed(tabs[previewIndex])
			teardown(tabs[previewIndex])
			tabs[previewIndex] = tab
			activate(index: previewIndex, focusEditor: focusEditor)
		} else {
			let insertAt = activeIndex.map { $0 + 1 } ?? tabs.count
			tabs.insert(tab, at: min(insertAt, tabs.count))
			activate(index: min(insertAt, tabs.count - 1), focusEditor: focusEditor)
		}
	}

	private func makeTab(
		for fileURL: URL,
		preview: Bool,
		mode: PreviewMode? = nil,
		dividerFraction: Double? = nil
	) -> Tab? {
		// Rendering a huge or binary blob as text helps nobody, but refusing to
		// open it is not the answer either — the tab explains itself and offers
		// the hex viewer instead.
		// A mesh has no source worth reading, so it opens rendered. Checked
		// before the size and binary tests, both of which an STL fails on its
		// way to being useful.
		if FilePreview.defaultMode(for: fileURL) == .preview, FilePreview.hasPreview(fileURL) {
			// A picture opens as the picture; a mesh opens rendered. Both skip
			// the size and binary tests below, which each of them fails on the
			// way to being useful.
			switch FilePreview.kind(for: fileURL) {
			case .image:
				// Unless it is a drawing with text behind it, which goes the
				// ordinary way and comes back rendered at the end.
				if !FilePreview.hasReadableSource(fileURL) {
					return makeImageTab(for: fileURL, preview: preview)
				}
			case .model:
				return makeModelTab(for: fileURL, preview: preview)
			case .pdf:
				// A PDF is a picture's case exactly: nothing to edit, no source to
				// read, and it fails the binary test below on its way to being
				// useful.
				return makePdfTab(for: fileURL, preview: preview)
			case .video:
				// And a video is the picture's case at twenty-five frames a
				// second. Only the containers AVFoundation plays natively
				// arrive here; a `.webm` keeps the notice and its Quick Look.
				return makeVideoTab(for: fileURL, preview: preview)
			default:
				// A `.drawio` opens rendered and has no source half, and it is
				// still a document this app owns: it goes the ordinary way and
				// gets a `TextDocument` like every other file, which is what
				// makes ⌘S, the edited dot and the close prompt work. The
				// branch above used to assume "rendered and not a picture"
				// meant "mesh", and sent every `.drawio` to the 3D viewer.
				break
			}
		}

		// The binary test first, and it costs nothing to ask it there: it reads
		// eight thousand bytes whatever the file's size, so the old order —
		// size, then kind — was not buying anything with it. `FileNotice.reason`
		// holds which of the two answers wins, where a test can pin it.
		let byteSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
		if let reason = FileNotice.reason(
			isBinary: FileInspector.isProbablyBinary(url: fileURL),
			isTooLargeForText: byteSize > 64 * 1024 * 1024
		) {
			return makeNoticeTab(for: fileURL, reason: reason, preview: preview)
		}

		let document: TextDocument
		do {
			document = try TextDocument(url: fileURL)
		} catch {
			return makeNoticeTab(for: fileURL, reason: error.localizedDescription, preview: preview)
		}

		let codeView = CodeView()
		let scrollView = NSScrollView()
		scrollView.documentView = codeView
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		// Not forced to .overlay: that ignores "Show scroll bars: Always" in
		// System Settings, so someone who asked for permanent scrollers never
		// got them and had no way to tell there was anything to scroll to.
		scrollView.scrollerStyle = NSScroller.preferredScrollerStyle
		scrollView.contentView.postsBoundsChangedNotifications = true
		// Soft wrap is measured against the viewport, so the layout has to be
		// rebuilt when the viewport changes size — a window resize, a split, a
		// divider drag. Bounds changes alone are scrolls, not resizes.
		scrollView.contentView.postsFrameChangedNotifications = true

		NotificationCenter.default.addObserver(
			forName: NSView.frameDidChangeNotification,
			object: scrollView.contentView,
			queue: .main
		) { [weak codeView] _ in
			codeView?.viewportChanged()
		}

		// The gutter is drawn relative to the clip view, so a horizontal scroll
		// has to repaint even though the document content did not change.
		NotificationCenter.default.addObserver(
			forName: NSView.boundsDidChangeNotification,
			object: scrollView.contentView,
			queue: .main
		) { [weak codeView] _ in
			codeView?.viewportChanged()
			codeView?.needsDisplay = true
		}

		let tab = Tab(url: fileURL, document: document, codeView: codeView, contentView: scrollView, isPreview: preview)
		// The one place a file is looked at from *outside its name* to decide what
		// previews it has. Costs nothing unless the name is a `.yaml`, and then the
		// head of it; nothing unless the name is a `.swift`, and then a walk up to
		// `Package.swift` and a read of it. Once per tab — see `Tab.looksLikeRecipe`
		// and `Tab.cadova` for why neither is asked again.
		tab.looksLikeRecipe = Go3mfRecipe.looksLikeRecipe(fileURL)
		tab.isSopsFile = SopsFile.looksEncrypted(fileURL)
		// The other side of the same look: a plaintext file a creation rule
		// matches is one the chip can offer to encrypt. Read from
		// `.sops.yaml`, so most files are asked about and nothing is said.
		if !tab.isSopsFile, let root = project?.root, Sops.isAvailable {
			tab.sopsOffer = SopsRules.matches(fileURL, in: root)
		}
		tab.cadova = CadovaModel.find(for: fileURL, stoppingAt: project?.root)
		askWhatGitCanSee(of: tab)

		// Clicking a name in the blame column goes to that commit — the log
		// page, scoped to this file — which is the answer to "what was this
		// change" that a toast only named.
		codeView.onShowBlameDetail = { [weak self, weak codeView] entry in
			guard let self, let url = tabs.first(where: { $0.codeView === codeView })?.url,
				  let onRevealCommit else {
				let when = DateFormatter.localizedString(from: entry.date, dateStyle: .medium, timeStyle: .short)
				Toast.post(
					entry.summary.isEmpty ? entry.shortCommit : entry.summary,
					detail: "\(entry.shortCommit) · \(entry.author) · \(when)",
					kind: .information
				)
				return
			}
			onRevealCommit(entry, url)
		}

		codeView.onCaretMoved = { [weak self] line, column in
			guard let self, self.activeTab === tab else { return }
			self.setStatus(line: line, column: column)
		}
		codeView.onDirtyChanged = { [weak self] _ in
			// Editing a provisional tab is a commitment to it, the same rule
			// VS Code and IDEA use.
			tab.isPreview = false
			self?.refreshTabBar()
			self?.scheduleLanguageSync(for: tab)
		}
		// Auto save clears the dirty marker without any further user action.
		document.onAutoSaved = { [weak self] in
			self?.refreshTabBar()
			guard let self, let languageId = document.languageId,
			      let root = self.serverRoot(for: fileURL, languageId: languageId) else { return }
			// The other half of what repeats. An auto-save follows every typing
			// pause, so this built the whole file as a `String` on the main
			// thread as often as the sync above did.
			self.withText(of: document) { text in
				LanguageService.shared.saved(
					url: fileURL, languageId: languageId, text: text, project: root
				)
			}
		}

		// A value beside the code, opened. The fetching belongs to whoever holds
		// the session — this side knows where the hint was and nothing else.
		codeView.onOpenInlineValue = { [weak self] hint, rect in
			guard let self else { return }
			self.openInlineValue(hint, at: rect, over: codeView)
		}

		codeView.onToggleBreakpoint = { [weak self] line in
			// The gutter works in 0-based lines; everything outside is 1-based.
			self?.onToggleBreakpoint?(fileURL, line + 1)
		}
		codeView.onEditBreakpoint = { [weak self] line in
			self?.onEditBreakpoint?(fileURL, line + 1)
		}
		codeView.onSetBreakpointEnabled = { [weak self] line, enabled in
			self?.onSetBreakpointEnabled?(fileURL, line + 1, enabled)
		}
		codeView.onDeleteBreakpoint = { [weak self] line in
			self?.onDeleteBreakpoint?(fileURL, line + 1)
		}
		codeView.onSetOtherBreakpointsEnabled = { [weak self] line, enabled in
			self?.onSetOtherBreakpointsEnabled?(fileURL, line + 1, enabled)
		}
		codeView.onLinesChanged = { [weak self] first, removed, inserted in
			self?.onLinesChanged?(fileURL, first, removed, inserted)
		}
		codeView.onTextReplaced = { [weak self, weak tab] range, inserted in
			guard let tab else { return }
			self?.textReplaced(in: tab, replacing: range, insertedLength: inserted)
		}
		refreshChangedLines(for: tab)
		tab.codeView?.setConcealsSecrets(
			Settings.shared.concealsSecrets
				&& DotenvSecrets.conceals(fileNamed: tab.url.lastPathComponent)
		)
		tab.codeView?.onSecretsAutoConcealed = { [weak self] in
			guard let self else { return }
			// The lock in the status bar shuts with the covers.
			onStatusChanged?(self)
		}
		tab.codeView?.onCoveredSecretClicked = {
			// The message, not the value: a click is exactly what a presenter
			// does absentmindedly on the screen everybody is watching.
			Toast.post(
				"Secrets are locked",
				detail: "Press the lock in the status bar, or View ▸ Reveal Secrets, to show them.",
				kind: .information
			)
		}
		// Said upward at once: the status bar's lock is drawn from this flag,
		// and the refresh that runs during the open reads it before this line.
		onStatusChanged?(self)
		codeView.onRunLine = { [weak self] line in
			// Already 1-based: the gutter converts before reporting a run.
			self?.onRunLine?(fileURL, line)
		}
		codeView.onGoToDefinition = { [weak self] line, character in
			self?.goToDefinition(from: tab, line: line, character: character)
		}
		codeView.onFindUsages = { [weak self] line, character in
			self?.onFindUsages?(tab.url, line, character)
		}
		codeView.onRename = { [weak self] line, character in
			self?.onRename?(tab.url, line, character)
		}
		codeView.onWatch = { [weak self] expression in
			self?.onWatch?(expression)
		}
		codeView.onFixWithAI = { [weak self] line, diagnostic in
			self?.onFixWithAI?(tab.url, line, diagnostic)
		}
		codeView.onCopyLink = { [weak self] form, line, endLine in
			self?.onCopyLink?(tab.url, form, line, endLine)
		}
		codeView.onRequestCompletions = { [weak self] prefix, wasTriggered, _ in
			self?.scheduleCompletions(for: tab, prefix: prefix, wasTriggered: wasTriggered)
		}
		codeView.onRequestCompletionsNow = { [weak self] prefix in
			self?.completeNow(in: tab, prefix: prefix)
		}
		codeView.onDismissCompletions = { [weak self] in
			self?.completionWork?.cancel()
			self?.completions.hide()
		}
		codeView.onSnippetStopChanged = { [weak self, weak tab] name in
			guard let self, let tab else { return }
			self.hintForSnippetStop(name, in: tab)
		}
		codeView.onRequestSignatureHelp = { [weak self, weak tab] in
			guard let self, let tab else { return }
			self.askForSignatureHelp(in: tab)
		}
		codeView.completionKeyHandler = { [weak self] selector in
			self?.handleCompletionKey(selector) ?? false
		}
		codeView.load(document: document)
		codeView.setWordWrap(Settings.shared.wordWrap)
		applyDebugState(to: tab)
		applyConditionalBreakpoints(to: tab)
		tab.sourceView = scrollView

		// The server is told about the file as it is opened, and answers about
		// it from then on.
		if let languageId = document.languageId,
		   let root = serverRoot(for: fileURL, languageId: languageId) {
			// Worked out once, here, and carried by the tab: every later
			// question must reach the server this `didOpen` went to.
			tab.serverRoot = root
			LanguageService.shared.opened(
				url: fileURL, languageId: languageId, text: text(of: document), project: root
			)
			codeView.setDiagnostics(
				LanguageService.shared.diagnostics(for: fileURL),
				fromPreparingServer: LanguageService.shared.isPreparing(
					languageId: languageId, project: root
				)
			)
			refreshCompletionTriggers(for: tab)
		}

		// A file whose rendered form is the point of it does not open as text:
		// an SVG in a documentation folder is a picture first and its path data
		// second, and a PlantUML file is a diagram somebody is checking against
		// the lines that describe it, so it opens with both.
		//
		// Unless a session says otherwise, in which case that is what it opens
		// as. Decided here rather than by putting the tab right afterwards, so a
		// `.scad` coming back as its source does not build a model view first and
		// throw it away — a restore opens every tab the project had at once.
		let opening = FilePreview.restoredMode(mode, for: fileURL, facts: tab.previewFacts)
		if opening != .source, FilePreview.hasPreview(fileURL, facts: tab.previewFacts) {
			tab.previewMode = opening
			tab.contentView = makeContentView(for: tab, mode: opening, dividerFraction: dividerFraction)
		}
		return tab
	}
}
