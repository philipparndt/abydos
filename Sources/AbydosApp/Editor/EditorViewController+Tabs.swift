import AppKit
import CryptoKit
import QuickLookUI
import GoSTL
import AbydosKit
import SwiftUI

/// The tab groups: making the view, moving a tab between two of them, and the
/// banner that says a language server is missing.
extension EditorViewController {
	// MARK: - View

	override func loadView() {
		let container = EditorDropView(color: Theme.current.editorBackground)

		tabBar = EditorTabBar()
		tabBar.onSelect = { [weak self] index in self?.activate(index: index, focusEditor: true) }
		tabBar.onClose = { [weak self] index in self?.closeTab(at: index) }
		tabBar.onCloseOthers = { [weak self] index in self?.closeTabs(keeping: index) }
		tabBar.onCloseLeft = { [weak self] index in self?.closeTabs(before: index) }
		tabBar.onCloseRight = { [weak self] index in self?.closeTabs(after: index) }
		tabBar.onCloseAll = { [weak self] in self?.closeAllTabs() }
		tabBar.onCopyPath = { [weak self] index in
			guard let url = self?.tabs[safe: index]?.url else { return }
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(url.path, forType: .string)
		}
		tabBar.onOpenAsHex = { [weak self] index in
			guard let self, let tab = tabs[safe: index] else { return }
			showHexEditor(for: tab)
		}
		tabBar.onBlame = { [weak self] index in
			guard let self, let tab = tabs[safe: index] else { return }
			onBlameRequested?(tab.url)
		}
		tabBar.onRevealInFinder = { [weak self] index in
			guard let url = self?.tabs[safe: index]?.url else { return }
			NSWorkspace.shared.activateFileViewerSelecting([url])
		}
		tabBar.onPromote = { [weak self] index in self?.promoteToPermanent(index: index) }
		tabBar.onMaximize = { [weak self] in self?.onMaximize?() }
		tabBar.onNewScratch = { [weak self] in self?.newScratch() }
		tabBar.onNewGlobalScratch = { [weak self] in self?.newScratch(global: true) }
		tabBar.groupID = groupID
		tabBar.onTearOff = { [weak self] index, screenPoint in
			guard let self else { return }
			onTearOffTab?(self, index, screenPoint)
		}
		tabBar.onPreviewModeChange = { [weak self] mode in
			self?.setPreviewMode(mode)
		}
		tabBar.onTabDropped = { [weak self] payload, index in
			guard let self else { return }
			self.onTabDroppedOnTabBar?(payload, index, self)
		}
		tabBar.urlForIndex = { [weak self] index in
			guard let self, self.tabs.indices.contains(index) else { return nil }
			return self.tabs[index].url
		}

		contentArea = NSView()

		findBar = FindBar()
		findBar.isHidden = true
		findBar.onQueryChanged = { [weak self] query, options in
			self?.scheduleFind(query: query, options: options)
		}
		findBar.onNext = { [weak self] in self?.stepMatch(by: 1) }
		findBar.onPrevious = { [weak self] in self?.stepMatch(by: -1) }
		findBar.onClose = { [weak self] in self?.closeFind() }
		findBar.onReplace = { [weak self] delta in self?.replaceCurrent(steppingBy: delta) }
		findBar.onReplaceAll = { [weak self] in self?.replaceAll() }
		// Kept on the tab as it is typed, so switching away and back brings it
		// with the query rather than losing it.
		findBar.onReplacementChanged = { [weak self] text in
			self?.activeTab?.find.replacement = text
		}

		serverBanner = LanguageServerBanner()
		serverBanner.isHidden = true
		serverBanner.onDetails = { [weak self] in self?.showServerManual() }
		serverBanner.onIgnore = { [weak self] in self?.ignoreServerSuggestion() }
		serverBanner.onDismiss = { [weak self] in self?.dismissServerSuggestion() }
		serverBanner.onOffer = { [weak self] in self?.takeServerOffer() }

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(diagnosticsChanged(_:)),
			name: .ideaiDiagnosticsChanged,
			object: nil
		)
		// The project's servers changed which machine they are on, so every file
		// open here has to be opened again at the one that answers for it now —
		// the same thing a subproject scope change does, for the same reason.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(languageServersMoved(_:)),
			name: .ideaiLanguageServersMoved,
			object: nil
		)
		// A server that starts, or is found to be missing, changes what the
		// banner should say — including making it go away.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(languageServersChanged),
			name: .ideaiLanguageServersChanged,
			object: nil
		)
		// A commit, a checkout, a stage from the sidebar: what differs from
		// HEAD changed for every open file at once. A commit must take the
		// marks away — after it, nothing differs any more.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(repositoryChangedForMarks),
			name: .abydosRepositoryChanged,
			object: nil
		)
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(settingsChangedForSecrets),
			name: .abydosSettingsChanged,
			object: nil
		)

		placeholder = NSTextField(labelWithString: "Select a file to open")
		placeholder.font = Theme.current.uiFont(13)
		placeholder.textColor = Theme.current.gitIgnored
		placeholder.alignment = .center

		// The other route to a scratch is double-clicking the tab strip, and an
		// empty window has no tab strip to double-click. Offered here so the
		// window is never a dead end.
		scratchButton = NSButton(title: "New Scratch File", target: self, action: #selector(newScratchFromPlaceholder))
		scratchButton.isBordered = false
		scratchButton.bezelStyle = .inline
		styleScratchButton()

		for subview in [tabBar, findBar, serverBanner, contentArea, placeholder, scratchButton] as [NSView] {
			container.addSubview(subview)
			subview.translatesAutoresizingMaskIntoConstraints = false
		}

		// Set from the window's actual titlebar height rather than hardcoded; the
		// titlebar is taller with a toolbar than without, and guessing clips the
		// tab bar.
		tabBarTopConstraint = tabBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 40)
		tabBarHeightConstraint = tabBar.heightAnchor.constraint(equalToConstant: EditorTabBar.height)
		// Collapsed to zero rather than hidden, so the editor reclaims the space.
		findBarHeight = findBar.heightAnchor.constraint(equalToConstant: 0)
		serverBannerHeight = serverBanner.heightAnchor.constraint(equalToConstant: 0)

		NSLayoutConstraint.activate([
			tabBarTopConstraint,
			tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			tabBarHeightConstraint,

			findBar.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
			findBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			findBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			findBarHeight,

			// Under the find bar, above the file: it is about the file, and it
			// must not push the thing somebody is searching around while they
			// search it.
			serverBanner.topAnchor.constraint(equalTo: findBar.bottomAnchor),
			serverBanner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			serverBanner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			serverBannerHeight,

			contentArea.topAnchor.constraint(equalTo: serverBanner.bottomAnchor),
			contentArea.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			contentArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			contentArea.bottomAnchor.constraint(equalTo: container.bottomAnchor),

			placeholder.centerXAnchor.constraint(equalTo: container.centerXAnchor),
			placeholder.centerYAnchor.constraint(equalTo: container.centerYAnchor),

			scratchButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
			scratchButton.topAnchor.constraint(equalTo: placeholder.bottomAnchor, constant: 10),
		])

		view = container
		// The whole group is a drop target, so a tab can be dropped over the text
		// as well as over the strip.
		container.registerForDraggedTypes([EditorTabDrag.pasteboardType])
		container.owner = self
		updateChrome()
	}

	// MARK: - Moving tabs between groups

	/// Removes a tab without tearing it down, so it can be re-homed intact.
	func detachTab(at index: Int) -> Tab? {
		guard tabs.indices.contains(index) else { return nil }
		let tab = tabs.remove(at: index)
		tab.contentView.removeFromSuperview()

		if tabs.isEmpty {
			activeIndex = nil
			contentArea.subviews.forEach { $0.removeFromSuperview() }
			updateChrome()
			refreshTabBar()
			onBecameEmpty?(self)
		} else {
			activeIndex = nil
			activate(index: min(index, tabs.count - 1), focusEditor: false)
		}
		return tab
	}

	/// Takes ownership of a tab detached from another group.
	func adopt(_ tab: Tab, at index: Int? = nil, focus: Bool = true) {
		// Its callbacks still point at the old group, so they are re-bound.
		rebindCallbacks(for: tab)
		let slot = max(0, min(index ?? tabs.count, tabs.count))
		tabs.insert(tab, at: slot)
		activeIndex = nil
		activate(index: slot, focusEditor: focus)
		applyDebugState(to: tab)
	}

	private func rebindCallbacks(for tab: Tab) {
		tab.codeView?.onCaretMoved = { [weak self, weak tab] line, column in
			guard let self, let tab, self.activeTab === tab else { return }
			self.setStatus(line: line, column: column)
		}
		tab.codeView?.onDirtyChanged = { [weak self, weak tab] _ in
			tab?.isPreview = false
			self?.refreshTabBar()
		}
		tab.codeView?.onSetBreakpointEnabled = { [weak self, weak tab] line, enabled in
			guard let tab else { return }
			self?.onSetBreakpointEnabled?(tab.url, line + 1, enabled)
		}
		tab.codeView?.onDeleteBreakpoint = { [weak self, weak tab] line in
			guard let tab else { return }
			self?.onDeleteBreakpoint?(tab.url, line + 1)
		}
		tab.codeView?.onLinesChanged = { [weak self, weak tab] first, removed, inserted in
			guard let tab else { return }
			self?.onLinesChanged?(tab.url, first, removed, inserted)
		}
		tab.codeView?.onTextReplaced = { [weak self, weak tab] range, inserted in
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
		tab.codeView?.onSetOtherBreakpointsEnabled = { [weak self, weak tab] line, enabled in
			guard let tab else { return }
			self?.onSetOtherBreakpointsEnabled?(tab.url, line + 1, enabled)
		}
		tab.codeView?.onToggleBreakpoint = { [weak self, weak tab] line in
			guard let tab else { return }
			self?.onToggleBreakpoint?(tab.url, line + 1)
		}
		tab.codeView?.onRunLine = { [weak self, weak tab] line in
			guard let tab else { return }
			self?.onRunLine?(tab.url, line)
		}
		tab.document?.onAutoSaved = { [weak self] in
			self?.refreshTabBar()
		}
	}

	/// Index of a tab by identity, for a drag that started here.
	func indexOfTab(withPath path: String) -> Int? {
		tabs.firstIndex { $0.url.path == path }
	}

	/// Shows a unified diff for a path, reusing the tab if it is already open.
	///
	/// A tab of its own rather than an overlay on the file: the diff and the
	/// file are different things to look at, and staging usually means moving
	/// between several of them.
	/// Selects a hunk in the visible diff, so the harness can capture the
	/// selection styling without a click.
	func selectDiffHunkForTesting(_ hunk: Int) {
		guard let tab = activeTab, tab.isDiff else { return }
		((tab.contentView as? NSScrollView)?.documentView as? DiffView)?.selectHunk(hunk)
	}


	func openDiff(for change: GitChange, root: URL, text: String) {
		let url = root.appendingPathComponent(change.path)

		if let index = tabs.firstIndex(where: { $0.isDiff && $0.url.path == url.path }) {
			let existing = (tabs[index].contentView as? NSScrollView)?.documentView as? DiffView
			existing?.setDiff(text, staged: change.isStaged, url: url)
			existing?.onApplySelection = { [weak self] selected in
				self?.onApplyDiffSelection?(change, text, selected)
			}
			existing?.onDiscardSelection = { [weak self] selected in
				self?.onDiscardDiffSelection?(change, text, selected)
			}
			existing?.onStashSelection = onStashDiffSelection == nil ? nil : { [weak self] selected in
				self?.onStashDiffSelection?(change, text, selected)
			}
			activeIndex = nil
			activate(index: index, focusEditor: false)
			return
		}

		let view = DiffView()
		view.setDiff(text, staged: change.isStaged, url: url)
		view.onApplySelection = { [weak self] selected in
			self?.onApplyDiffSelection?(change, text, selected)
		}
		view.onDiscardSelection = { [weak self] selected in
			self?.onDiscardDiffSelection?(change, text, selected)
		}
		view.onStashSelection = onStashDiffSelection == nil ? nil : { [weak self] selected in
			self?.onStashDiffSelection?(change, text, selected)
		}

		let scrollView = NSScrollView()
		scrollView.documentView = view
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		view.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
			view.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
		])

		let tab = Tab(url: url, document: nil, codeView: nil, contentView: scrollView, isPreview: true)
		tab.isDiff = true

		// Replaces the outgoing provisional tab, so clicking down a list of
		// changed files does not leave a tab behind for every one.
		if let existing = tabs.firstIndex(where: { $0.isPreview }) {
			tabs[existing].contentView.removeFromSuperview()
			tabs.remove(at: existing)
		}

		tabs.append(tab)
		activeIndex = nil
		activate(index: tabs.count - 1, focusEditor: false)
	}

	/// Shows what one commit did to one file.
	///
	/// Read-only, unlike a working-copy diff: there is nothing to stage in a
	/// commit that has already happened, and the subtitle says which commit it
	/// is rather than "diff".
	func openCommitDiff(commit: GitCommit, file: GitCommitFile, root: URL, text: String) {
		let url = root.appendingPathComponent(file.path)

		if let index = tabs.firstIndex(where: { $0.diffCommit == commit.shortHash && $0.url.path == url.path }) {
			activeIndex = nil
			activate(index: index, focusEditor: false)
			return
		}

		let view = DiffView()
		view.setDiff(text, staged: true, url: url)
		view.isReadOnly = true

		let scrollView = NSScrollView()
		scrollView.documentView = view
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.editorBackground
		view.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
			view.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
			view.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
		])

		let tab = Tab(url: url, document: nil, codeView: nil, contentView: scrollView, isPreview: true)
		tab.isDiff = true
		tab.diffCommit = commit.shortHash

		// Clicking down a list of files leaves one tab behind, not twenty.
		if let existing = tabs.firstIndex(where: { $0.isPreview }) {
			tabs[existing].contentView.removeFromSuperview()
			tabs.remove(at: existing)
		}

		tabs.append(tab)
		activeIndex = nil
		activate(index: tabs.count - 1, focusEditor: false)
	}

	/// Moves a tab within this group, for a reorder drop.
	func moveTab(from source: Int, to destination: Int) {
		guard tabs.indices.contains(source) else { return }
		let tab = tabs.remove(at: source)
		let target = max(0, min(destination, tabs.count))
		tabs.insert(tab, at: target)
		activeIndex = nil
		activate(index: target, focusEditor: false)
	}

	/// Applies a hand-picked language to the active tab and repaints it.
	func setActiveLanguage(_ languageId: String?) {
		guard let tab = activeTab, let document = tab.document else { return }
		document.setLanguage(languageId)
		statusLanguage = document.displayLanguageName
		onStatusChanged?(self)
		// And which server answers, since that is the language's question one
		// layer down: saying a file is Rust is saying rust-analyzer is what would
		// answer about it, and the chip beside the language must not go on naming
		// the server for the language it used to be.
		refreshServerState()
		// The document fires onSyntaxUpdated, which refreshes folds and repaints.
	}

	func setStatus(line: Int, column: Int) {
		guard line != statusLine || column != statusColumn else { return }
		statusLine = line
		statusColumn = column
		onStatusChanged?(self)
	}

	/// Quiet enough to ignore, and the only coloured thing on an empty page —
	/// which is what makes it findable without shouting.
	func styleScratchButton() {
		scratchButton.attributedTitle = NSAttributedString(
			string: "New Scratch File",
			attributes: [
				.font: Theme.current.uiFont(13),
				.foregroundColor: Theme.current.gitModified,
			]
		)
	}

	@objc private func newScratchFromPlaceholder() {
		newScratch()
	}

	/// Presses the empty page's button, rather than calling what it calls.
	func clickScratchPlaceholderForTesting() -> Bool {
		guard !scratchButton.isHidden else { return false }
		scratchButton.performClick(nil)
		return true
	}

	func updateChrome() {
		let hasTabs = !tabs.isEmpty
		placeholder.isHidden = hasTabs
		scratchButton.isHidden = hasTabs
		tabBar.isHidden = !hasTabs
		contentArea.isHidden = !hasTabs
		if !hasTabs { hideServerBanner() }
		onStatusChanged?(self)
	}

	// MARK: - The missing-server banner

	@objc private func languageServersChanged() {
		refreshServerState()
		// A server that has only just finished the handshake is the usual case
		// here: the first keystrokes in a file are typed before it is up, and a
		// trigger set read at that point is empty for the life of the tab.
		for tab in tabs { refreshCompletionTriggers(for: tab) }
		// And a list that said "still preparing" now has something to ask for.
		// This notification is posted the moment preparing stops — 0501's chip
		// is drawn from the same one — so nothing here polls or waits.
		reaskIfWaitingOnAServer()
		// **The end of preparation repaints what is already on screen.** A
		// server's last act before it is ready may be to withdraw the false
		// diagnostic, or to send nothing at all — so a view that waited for the
		// next one would hold a dimmed error after the server was ready, which
		// is worse than the state being fixed. The same notification carries it,
		// and `setDiagnostics` returns early unless something really changed.
		for tab in tabs { applyDiagnostics(to: tab) }
	}

	/// What the strip above the file and the chip beside the caret should both
	/// say about this file's server.
	///
	/// One refresh, because they are one question asked at two lengths: the strip
	/// is the sentence with the button and the chip is the name with the mark.
	/// Called from the places a server's state can have changed under a file —
	/// activating a tab, a scope moving, choosing a language by hand, and
	/// `.ideaiLanguageServersChanged`, which every start, stop, refusal and
	/// reconsideration already posts.
	func refreshServerState() {
		refreshServerBanner()
		refreshServerFooter()
	}

	/// A project's servers moved between this machine and its devcontainer.
	///
	/// Only for the project this group is showing: a window on another project
	/// has nothing to re-send, and re-opening its files at servers that never
	/// stopped would be a `didOpen` for a document they already hold.
	@objc private func languageServersMoved(_ note: Notification) {
		guard let moved = note.object as? URL, project != nil else { return }
		// **Any root this group's files are filed under**, not the scope. With a
		// root per file, one group can hold files belonging to several — a Swift
		// package and a Go module side by side — and a server moving under any
		// of them is one this group has documents at.
		let path = moved.standardizedFileURL.path
		let mine = tabs.contains { tab in
			serverRoot(for: tab)?.standardizedFileURL.path == path
		}
		guard mine else { return }
		rescope()
	}

	/// The root this tab's file is filed under, worked out once and kept.
	///
	/// The single answer every call site in this file uses. `LanguageService.root`
	/// decides it; this remembers it, because it is a directory walk and the
	/// questions asking it include one per keystroke.
	func serverRoot(for tab: Tab) -> URL? {
		// A decrypted buffer has no server: a YAML server would hold the
		// plaintext in its own process and its own cache, which is a place the
		// plaintext must not go. Nil here is what gates every open, change,
		// save and close announcement at once.
		guard !tab.isDecrypted else { return nil }
		guard let project else { return nil }
		if let known = tab.serverRoot { return known }
		guard let languageId = tab.document?.languageId else { return nil }
		let root = LanguageService.shared.root(
			for: tab.url, languageId: languageId, project: project.root
		)
		tab.serverRoot = root
		return root
	}

	/// The same for a file being opened, before there is a tab to ask.
	func serverRoot(for url: URL, languageId: String) -> URL? {
		guard let project else { return nil }
		return LanguageService.shared.root(for: url, languageId: languageId, project: project.root)
	}

	/// The tabs, in strip order, with the one in front marked.
	var tabNamesForTesting: String {
		tabs.map { ($0 === activeTab ? "*" : "") + $0.url.lastPathComponent }
			.joined(separator: ", ")
	}

	/// What find is doing in every tab, for a driver.
	///
	/// The gesture nothing could drive: find in one file, switch tab, step. The
	/// fault was read out of the code — one file's UTF-16 offsets handed to
	/// another file's view — and a claim read rather than seen is a claim worth
	/// checking.
	var findReportForTesting: String {
		var lines: [String] = []
		lines.append("bar showing=\(!findBar.isHidden) replacing=\(findBar.isReplacing)"
			+ " \(findBar.statusReportForTesting)")
		for (index, tab) in tabs.enumerated() {
			let mark = tab === activeTab ? "*" : " "
			let length = tab.document?.rope.utf16Count ?? 0
			lines.append("\(mark) \(index) \(tab.url.lastPathComponent)"
				+ " showing=\(tab.find.isShowing) query=\u{201C}\(tab.find.query)\u{201D}"
				+ " matches=\(tab.find.matches.count) current=\(tab.find.current.map(String.init) ?? "none")"
				+ " at=[\(tab.find.matches.prefix(8).map { "\($0.utf16Range.lowerBound)..<\($0.utf16Range.upperBound)" }.joined(separator: ","))]"
				+ " caret=\(tab.codeView?.caretOffset ?? -1) of \(length)")
		}
		return lines.joined(separator: "\n")
	}

	/// Which root the file in front is filed under, beside the scope, for a
	/// driver.
	///
	/// The two used to be the same thing by construction, which is the fault.
	/// Printed together so a run can show they are not — and that the file's
	/// answer is the one that follows the file.
	var serverRootReportForTesting: String {
		guard let project else { return "no project" }
		guard let tab = activeTab else { return "no tab" }
		let language = tab.document?.languageId ?? "none"
		let root = serverRoot(for: tab)?.lastPathComponent ?? "none"
		return "file=\(tab.url.lastPathComponent) language=\(language)"
			+ " root=\(root) scope=\(project.scopeRoot.lastPathComponent)"
			+ " project=\(project.root.lastPathComponent)"
	}

	/// Whether this file's language has anything to say about its server, and
	/// says it.
	///
	/// Asked on every activation rather than once per file: installing the
	/// server is the whole point of the bar, and somebody who has just done it
	/// should see it go away by clicking back onto their code rather than by
	/// restarting the app.
	///
	/// Asked of `LanguageService` rather than of `LanguageServers`, which is
	/// 0432's second fault: the second knows only whether the server is on this
	/// machine, and for a project worked on in a devcontainer the answer to that
	/// is "no" for ever — including while the container's own copy is answering.
	/// The first knows whether anything is running, coming, or neither, so the
	/// strip goes away when the server lands however late that is.
	private func refreshServerBanner() {
		if let notice = fileServerNotice() ?? launchNotice {
			serverBanner.show(notice)
			serverBanner.isHidden = false
			serverBannerHeight.constant = LanguageServerBanner.height
			return
		}
		hideServerBanner()
	}

	/// What the file in front of somebody has to say about its own server.
	private func fileServerNotice() -> LanguageService.ServerNotice? {
		guard project != nil,
		      let tab = activeTab,
		      !tab.isDiff,
		      let languageId = tab.document?.languageId,
		      !dismissedSuggestions.contains(languageId),
		      let root = serverRoot(for: tab)
		else { return nil }

		return LanguageService.shared.notice(
			forLanguage: languageId,
			project: root,
			ignoring: Set(Settings.shared.ignoredLanguageServers)
		)
	}


	/// Set by the window when the selected configuration changes.
	///
	/// Held here rather than recomputed, because deciding it needs the run
	/// picker's selection and this controller knows nothing about that.
	func setLaunchNotice(_ notice: LanguageService.ServerNotice?) {
		guard notice != launchNotice else { return }
		if let notice, dismissedSuggestions.contains(notice.languageId) { return }
		launchNotice = notice
		refreshServerBanner()
	}

	/// Works out what the footer's chip says and pushes it, if it has changed.
	///
	/// A diff tab is left out for the reason the strip leaves it out: the file
	/// beside it is a revision nobody's server has been told about, and naming a
	/// server over it would claim it is being checked.
	///
	/// The push is skipped when the answer is the same, which it is for the whole
	/// of a session in which nothing starts or stops. `.ideaiLanguageServersChanged`
	/// is posted by every window's servers, not only this one's, so without the
	/// comparison a project opening in another window would repaint every status
	/// bar in the app.
	private func refreshServerFooter() {
		var footer: LanguageServerFooter?
		if let tab = activeTab, !tab.isDiff, let languageId = tab.document?.languageId,
		   let root = serverRoot(for: tab) {
			// Keyed by the file's own root, so it names the server answering
			// about the file in front rather than the one the pill points at.
			footer = LanguageService.shared.footer(forLanguage: languageId, project: root)
		}
		guard footer != statusServer else { return }
		statusServer = footer
		onStatusChanged?(self)
	}

	private func hideServerBanner() {
		guard serverBanner != nil, !serverBanner.isHidden else { return }
		serverBanner.isHidden = true
		serverBannerHeight.constant = 0
	}

	private func showServerManual() {
		guard let notice = serverBanner.notice, let manual = notice.manual else { return }
		DetailDialog(
			title: "The \(notice.languageName) language server",
			detail: manual,
			isError: false
		).show(over: view.window)
	}

	private func ignoreServerSuggestion() {
		guard let notice = serverBanner.notice, notice.isIgnorable else { return }
		Settings.shared.ignoreLanguageServer(for: notice.languageId)
		hideServerBanner()
		// Every group in every window, not only this one: the answer was about
		// the language, and being asked again in the split beside it would read
		// as the button having done nothing.
		NotificationCenter.default.post(name: .ideaiLanguageServersChanged, object: nil)
	}

	private func dismissServerSuggestion() {
		guard let notice = serverBanner.notice else { return }
		dismissedSuggestions.insert(notice.languageId)
		hideServerBanner()
	}

	/// Takes the strip up on what it offered.
	///
	/// The scope rather than the project root, because that is the folder the
	/// notice was asked about and a subproject with a devcontainer of its own is
	/// the case 0432 exists for — agreeing here must agree to the container the
	/// sentence named.
	private func takeServerOffer() {
		guard let project, let offer = serverBanner.notice?.offer else { return }
		switch offer {
		case .useDevContainer:
			// For the server the banner is about, which is the one answering
			// about the file in front.
			LanguageService.shared.useDevContainer(
				for: activeTab.flatMap { serverRoot(for: $0) } ?? project.root
			)
		}
	}

	// MARK: - Testing

	/// What the bar is saying, or that it is not there.
	var serverBannerReportForTesting: String {
		guard !serverBanner.isHidden else { return "no banner" }
		let offer = serverBanner.offerForTesting
		return "\(serverBanner.sizesForTesting) — \(serverBanner.textForTesting)"
			+ (offer.isEmpty ? "" : " [\(offer)]")
	}

	func pressServerBannerForTesting(_ button: String) {
		switch button {
		case "details": serverBanner.pressDetailsForTesting()
		case "ignore": serverBanner.pressIgnoreForTesting()
		case "offer": serverBanner.pressOfferForTesting()
		default: serverBanner.pressDismissForTesting()
		}
	}

	/// Distance from the top of the window to the first row of content.
	func setTopInset(_ inset: CGFloat) {
		tabBarTopConstraint.constant = inset
		// The drop preview is drawn over this whole view, which begins behind
		// the titlebar; without the same inset its top edge is covered by it.
		(view as? EditorDropView)?.topInset = inset
	}
}
