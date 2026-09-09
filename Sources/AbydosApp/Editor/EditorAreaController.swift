import AppKit
import AbydosKit

/// Hosts one or more editor groups in a tree of splits.
///
/// Each pane is a full editor group with its own tabs and find bar, rather than
/// a shared set of tabs shown twice. The status line is the exception: there is
/// one for the window, showing whichever pane is active, because caret position
/// and language describe where you are working, and you work in one pane. Splits are built from nested
/// two-child `NSSplitView`s, which keeps the arrangement recursive: any pane can
/// be split again, horizontally or vertically, to any depth.
///
/// The window talks to this controller, which forwards to whichever group is
/// active, so the rest of the app is unaware there is more than one.
final class EditorAreaController: NSViewController {

	// Kept in the body because a stored property cannot live in an
	// extension; what each is for is said where it is used.
	/// Emptying and refilling the window is not the user closing tabs.
	///
	/// Clearing first would otherwise record "nothing is open" and then read
	/// that back as what to restore, so swapping projects would quietly lose
	/// every scratch tab. Recorded once, when the dust has settled.
	var suppressedRecording = 0
	var isClosing = false
	var conditionalBreakpoints: [String: Set<Int>] = [:]
	var onEditBreakpoint: ((URL, Int) -> Void)? {
		didSet { for group in groups { group.onEditBreakpoint = onEditBreakpoint } }
	}
	var onFixWithAI: ((URL, Int, LSPDiagnostic) -> Void)? {
		didSet { for group in groups { group.onFixWithAI = onFixWithAI } }
	}
	var onFindUsages: ((URL, Int, Int) -> Void)? {
		didSet { for group in groups { group.onFindUsages = onFindUsages } }
	}
	var onRename: ((URL, Int, Int) -> Void)? {
		didSet { for group in groups { group.onRename = onRename } }
	}
	var onWatch: ((String) -> Void)? {
		didSet { for group in groups { group.onWatch = onWatch } }
	}
	var onCopyLink: ((URL, CodeView.LinkForm, Int, Int?) -> Void)? {
		didSet { for group in groups { group.onCopyLink = onCopyLink } }
	}
	var runnableLines: [String: Set<Int>] = [:]
	/// Told where the editor went, and where it was standing before.
	///
	/// Both halves matter: going back should return to the line somebody was
	/// reading, which is not where they arrived at that file.
	/// A tab was double-clicked and it was already permanent: the editor is
	/// asking for the window.
	var onMaximize: (() -> Void)?
	var onNavigated: ((NavigationHistory.Place?, NavigationHistory.Place) -> Void)?
	/// Suspended while a session is restored, or opening yesterday's twelve
	/// tabs would fill the history before anybody navigated anywhere.
	var recordsNavigation = true
	/// A tab asked for blame, or a blame entry was clicked; the window answers.
	var onBlameRequested: ((URL) -> Void)?
	var onRevealCommit: ((GitBlame.Line, URL) -> Void)?
	/// A tab was pulled out of every window and wants one of its own.
	var onTearOffTab: ((EditorViewController.Tab, NSPoint) -> Void)?
	/// Every group here is empty, which for a torn-off window means it is done.
	var onBecameEmpty: (() -> Void)?

	init() {
		super.init(nibName: nil, bundle: nil)
		EditorAreas.register(self)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func group(withID id: UUID) -> EditorViewController? {
		groups.first { $0.groupID == id }
	}

	/// Takes a tab into whichever group is active.
	func adopt(_ tab: EditorViewController.Tab) {
		guard let target = activeGroup ?? groups.first else { return }
		target.adopt(tab)
		activeGroup = target
	}

	/// The group a dragged tab came from, in this window or any other.
	private func source(
		for payload: EditorTabDrag.Payload
	) -> (area: EditorAreaController, group: EditorViewController)? {
		if let mine = group(withID: payload.groupID) { return (self, mine) }
		return EditorAreas.owner(ofGroup: payload.groupID)
	}

	/// Called after a tab is taken out, since the window it left may now be an
	/// empty one that only existed to hold it.
	private func noteTabRemoved() {
		guard groups.allSatisfy(\.isEmpty) else { return }
		onBecameEmpty?()
	}

	var groups: [EditorViewController] = []
	var activeGroup: EditorViewController! {
		didSet { refreshStatus(from: activeGroup) }
	}

	var project: Project?
	var topInset: CGFloat = 40

	/// Holds the split tree. Separate from `view` so the status bar below it
	/// survives the tree being rebuilt.
	var splitHost: NSView!
	var statusBar: EditorStatusView!
	var statusBarHeightConstraint: NSLayoutConstraint!

	// Forwarded from the active group.
	/// Files dropped on any group in this area, in the order they were dropped.
	///
	/// Passed straight out. What a dropped file *means* — a tab here, a project
	/// for a folder, the tree told, the panel making room — belongs to the
	/// window, which already answers all of that for a file opened from a
	/// terminal.
	var onFilesDropped: (([URL]) -> Void)?
	var onActiveFileChanged: ((URL?) -> Void)?
	var onToggleBreakpoint: ((URL, Int) -> Void)?
	var onSetBreakpointEnabled: ((URL, Int, Bool) -> Void)?
	var onDeleteBreakpoint: ((URL, Int) -> Void)?
	var onSetOtherBreakpointsEnabled: ((URL, Int, Bool) -> Void)?
	var onLinesChanged: ((URL, Int, Int, Int) -> Void)?
	var onFileReloaded: ((URL) -> Void)?
	var onRunLine: ((URL, Int) -> Void)?
	var onApplyDiffSelection: ((GitChange, String, Set<Int>) -> Void)?
	var onDiscardDiffSelection: ((GitChange, String, Set<Int>) -> Void)?
	/// Nil where stashing a hunk is not possible — an old git — so the menu
	/// item is absent rather than failing when pressed.
	var onStashDiffSelection: ((GitChange, String, Set<Int>) -> Void)?

	override func loadView() {
		let container = ColoredView(color: Theme.current.editorBackground)
		view = container

		splitHost = NSView()
		statusBar = EditorStatusView()
		for subview in [splitHost, statusBar] as [NSView] {
			container.addSubview(subview)
			subview.translatesAutoresizingMaskIntoConstraints = false
		}

		statusBar.onSecretsToggled = { [weak self] in self?.toggleRevealSecrets() }
		statusBar.onSopsPressed = { [weak self] in self?.pressSops() }
		statusBar.onPassphraseEntered = { [weak self] text in self?.answerPassphrase(text) }
		statusBar.onPassphraseCancelled = { [weak self] in self?.answerPassphrase(nil) }
		statusBar.onIgnoreFile = { [weak self] in self?.activeGroup?.ignoreActiveFile() }
		statusBar.onIndentChosen = { [weak self] style in
			self?.activeGroup?.convertIndentation(to: style)
		}
		statusBar.onLanguageChosen = { [weak self] languageId in
			self?.activeGroup?.setActiveLanguage(languageId)
		}
		statusBarHeightConstraint = statusBar.heightAnchor.constraint(
			equalToConstant: Theme.current.scaled(24)
		)
		NSLayoutConstraint.activate([
			splitHost.topAnchor.constraint(equalTo: container.topAnchor),
			splitHost.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			splitHost.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			splitHost.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

			statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
			statusBarHeightConstraint,
		])

		let first = makeGroup()
		activeGroup = first
		install(rootView: first.view)
	}

	/// Shows the active group's caret position, language and server.
	///
	/// Every caret move comes through here, so all three are reads of values the
	/// group is already holding. `statusServer` in particular is worked out when
	/// a server starts, stops or is refused — never here: the three draw in one
	/// view, and a lookup on this path would be a lookup per keystroke.
	/// A line added to `.gitignore`, or a file added to the index, changes what
	/// git can see without changing any file — so the window's git refresh asks
	/// every open tab again.
	func refreshWhatGitCanSee() {
		for group in groups { group.refreshWhatGitCanSee() }
	}

	/// Every pane's marks again, once git is known. See
	/// `EditorViewController.refreshChangeMarks`.
	func refreshChangeMarks() { for group in groups { group.refreshChangeMarks() } }

	func refreshStatus(from group: EditorViewController?) {
		guard let group, group === activeGroup else { return }
		statusBar.isHidden = group.isEmpty
		if let text = group.statusPositionText {
			statusBar.setPosition(text: text)
		} else {
			statusBar.setPosition(line: group.statusLine, column: group.statusColumn)
		}
		statusBar.setLanguage(group.statusLanguage)
		statusBar.setServer(group.statusServer)
		let secrets = group.secretsState
		statusBar.setSecrets(concealing: secrets.conceals, revealed: secrets.revealed)
		statusBar.setSops(group.sopsState)
		statusBar.setExposure(group.exposureState)
		statusBar.setIndent(group.indentState)
	}

	// MARK: - SOPS

	/// Where a decrypted buffer is parked on a switch and taken back from on
	/// a restore — the window's, handed to every group as it is made.
	var parkDecrypted: ((URL, DecryptedBuffer) -> Void)? {
		didSet { for group in groups { group.parkDecrypted = parkDecrypted } }
	}
	var takeParkedDecrypted: ((URL) -> DecryptedBuffer?)? {
		didSet { for group in groups { group.takeParkedDecrypted = takeParkedDecrypted } }
	}

	func pressSops() {
		activeGroup.pressSops()
		refreshStatus(from: activeGroup)
	}
	func sopsForTesting(_ steps: String) { activeGroup.sopsForTesting(steps) }

	/// The decrypt waiting on the passphrase field; see `+Passphrase`.
	var pendingPassphrase: ((String?) -> Void)?

	/// The indent menu's pick and the driver, the same routing the SOPS
	/// chip's take. The pick needs no refresh of its own: the conversion
	/// is what lets the group's own status change through.
	func indentChipForTesting(_ steps: String) { activeGroup.indentChipForTesting(steps) }
	func parkDecryptedTabs() { for group in groups { group.parkDecryptedTabs() } }
	var editedDecryptedTabs: [(group: EditorViewController, tab: EditorViewController.Tab)] {
		groups.flatMap { group in group.editedDecryptedTabs.map { (group, $0) } }
	}

	// MARK: - Groups

	func makeGroup() -> EditorViewController {
		let group = EditorViewController()
		// Force the view to load so its callbacks exist before use.
		_ = group.view
		group.setTopInset(topInset)
		if let project { group.setProject(project) }

		group.onActiveFileChanged = { [weak self] url in
			self?.onActiveFileChanged?(url)
		}
		group.onMaximize = { [weak self] in self?.onMaximize?() }
		group.parkDecrypted = parkDecrypted
		group.takeParkedDecrypted = takeParkedDecrypted
		group.onNavigated = { [weak self] departure, arrival in
			guard let self, self.recordsNavigation else { return }
			self.onNavigated?(departure, arrival)
		}
		group.onToggleBreakpoint = { [weak self] url, line in
			self?.onToggleBreakpoint?(url, line)
		}
		group.onEditBreakpoint = onEditBreakpoint
		group.onSetBreakpointEnabled = { [weak self] url, line, enabled in
			self?.onSetBreakpointEnabled?(url, line, enabled)
		}
		group.onDeleteBreakpoint = { [weak self] url, line in
			self?.onDeleteBreakpoint?(url, line)
		}
		group.onSetOtherBreakpointsEnabled = { [weak self] url, line, enabled in
			self?.onSetOtherBreakpointsEnabled?(url, line, enabled)
		}
		group.onLinesChanged = { [weak self] url, first, removed, inserted in
			self?.onLinesChanged?(url, first, removed, inserted)
		}
		group.onFileReloaded = { [weak self] url in
			self?.onFileReloaded?(url)
		}
		group.onFindUsages = onFindUsages
		group.onRename = onRename
		group.onWatch = onWatch
		group.onFixWithAI = onFixWithAI
		group.setConditionalBreakpoints(conditionalBreakpoints)
		group.onRunLine = { [weak self] url, line in
			self?.onRunLine?(url, line)
		}
		group.setRunnableLines(runnableLines)
		group.onApplyDiffSelection = { [weak self] change, diff, selected in
			self?.onApplyDiffSelection?(change, diff, selected)
		}
		group.onDiscardDiffSelection = { [weak self] change, diff, selected in
			self?.onDiscardDiffSelection?(change, diff, selected)
		}
		group.onStashDiffSelection = onStashDiffSelection == nil ? nil : { [weak self] change, diff, selected in
			self?.onStashDiffSelection?(change, diff, selected)
		}
		group.onActivated = { [weak self] activated in
			self?.activeGroup = activated
		}
		group.onTearOffTab = { [weak self] group, index, screenPoint in
			self?.tearOff(from: group, index: index, at: screenPoint)
		}
		group.onBecameEmpty = { [weak self] empty in
			// The last group stays even when empty; it is the editor area itself.
			self?.removeGroup(empty)
		}
		group.onTabsChanged = { [weak self] in self?.recordOpenScratches() }
		group.onStatusChanged = { [weak self] reporting in
			self?.refreshStatus(from: reporting)
		}
		wirePassphrase(group)
		group.onBlameRequested = { [weak self] url in self?.onBlameRequested?(url) }
		group.onRevealCommit = { [weak self] entry, url in self?.onRevealCommit?(entry, url) }
		group.onTabDropped = { [weak self] payload, zone, target in
			self?.handleDrop(payload: payload, zone: zone, target: target)
		}
		group.onFilesDropped = { [weak self] urls in self?.onFilesDropped?(urls) }
		group.onTabDroppedOnTabBar = { [weak self] payload, index, target in
			self?.handleTabBarDrop(payload: payload, index: index, target: target)
		}

		groups.append(group)
		addChild(group)
		return group
	}

	func install(rootView: NSView) {
		splitHost.subviews.forEach { $0.removeFromSuperview() }
		rootView.translatesAutoresizingMaskIntoConstraints = false
		splitHost.addSubview(rootView)
		NSLayoutConstraint.activate([
			rootView.topAnchor.constraint(equalTo: splitHost.topAnchor),
			rootView.bottomAnchor.constraint(equalTo: splitHost.bottomAnchor),
			rootView.leadingAnchor.constraint(equalTo: splitHost.leadingAnchor),
			rootView.trailingAnchor.constraint(equalTo: splitHost.trailingAnchor),
		])
	}

	// MARK: - Splitting

	private func handleDrop(
		payload: EditorTabDrag.Payload,
		zone: EditorTabDrag.Zone,
		target: EditorViewController
	) {
		guard let (sourceArea, source) = source(for: payload) else { return }

		// Dropping a group's only tab back into itself would destroy and rebuild
		// the same pane for no reason.
		if source === target, zone == .center { return }
		if source === target, source.tabCount <= 1 { return }

		let index = source.indexOfTab(withPath: payload.path) ?? payload.index
		guard let tab = source.detachTab(at: index) else { return }
		sourceArea.noteTabRemoved()

		guard let splitsVertically = zone.splitsVertically else {
			target.adopt(tab)
			activeGroup = target
			return
		}

		let newGroup = makeGroup()
		newGroup.adopt(tab)
		split(target: target, with: newGroup, vertical: splitsVertically, before: zone.insertsBefore)
		activeGroup = newGroup
	}

	/// Moves a dropped tab into `target`'s strip at the slot it was released over.
	///
	/// Within one group this is a reorder; across groups it moves the tab, which
	/// may leave the source group empty and collapse its split.
	func handleTabBarDrop(
		payload: EditorTabDrag.Payload,
		index: Int,
		target: EditorViewController
	) {
		guard let (sourceArea, source) = source(for: payload) else { return }
		let from = source.indexOfTab(withPath: payload.path) ?? payload.index

		if source === target {
			// The slot is measured against the strip as it looks now, with the tab
			// still in it, so removing an earlier tab shifts every later slot left.
			source.moveTab(from: from, to: index > from ? index - 1 : index)
			activeGroup = target
			return
		}

		guard let tab = source.detachTab(at: from) else { return }
		sourceArea.noteTabRemoved()
		target.adopt(tab, at: index)
		activeGroup = target
		view.window?.makeKeyAndOrderFront(nil)
	}

	/// Replaces `target`'s position in the tree with a split holding both panes.
	func split(
		target: EditorViewController,
		with newGroup: EditorViewController,
		vertical: Bool,
		before: Bool
	) {
		let targetView = target.view
		let parent = targetView.superview

		let split = EditorGroupSplitView(vertical: vertical)

		// Where the target sat, the split now sits.
		let isRoot = (parent === splitHost)
		var indexInParent: Int?
		if let parentSplit = parent as? NSSplitView {
			indexInParent = parentSplit.arrangedSubviews.firstIndex(of: targetView)
		}

		targetView.removeFromSuperview()
		targetView.translatesAutoresizingMaskIntoConstraints = true

		if before {
			split.addArrangedSubview(newGroup.view)
			split.addArrangedSubview(targetView)
		} else {
			split.addArrangedSubview(targetView)
			split.addArrangedSubview(newGroup.view)
		}

		if isRoot {
			install(rootView: split)
		} else if let parentSplit = parent as? NSSplitView, let index = indexInParent {
			split.translatesAutoresizingMaskIntoConstraints = true
			parentSplit.insertArrangedSubview(split, at: index)
		}

		// Even halves, which is what a split gesture implies.
		split.divideEvenly()
		DispatchQueue.main.async { [weak self] in self?.updateGroupInsets() }
	}

	/// Removes an empty group and collapses the split that held it.
	/// Pulls a tab out into a window of its own.
	func tearOff(from group: EditorViewController, index: Int, at screenPoint: NSPoint) {
		// A window's only tab has nowhere to go: it would empty this window to
		// fill an identical new one.
		guard groups.count > 1 || group.tabCount > 1 else { return }
		guard let tab = group.detachTab(at: index) else { return }
		onTearOffTab?(tab, screenPoint)
	}
}
