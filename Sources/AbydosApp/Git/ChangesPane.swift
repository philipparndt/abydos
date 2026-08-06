import AppKit
import AbydosKit

/// Staging and committing, in the shape Fork uses: unstaged above, staged
/// below, the commit message under both.
///
/// Two lists rather than one with checkboxes. The index is a real thing with
/// its own contents — a file can be half in it — and a single list with a tick
/// per row cannot show that a file is in both states at once.
final class ChangesPane: NSView {
	/// A change was selected, to show its diff.
	var onSelectChange: ((GitChange) -> Void)?
	/// Something was staged, unstaged or committed.
	var onWorkingCopyChanged: (() -> Void)?

	private let root: URL

	private var status = GitWorkingCopyStatus()
	private var unstagedTable: ChangesTableView!
	private var stagedTable: ChangesTableView!
	private var unstagedHeader: SectionHeaderView!
	private var stagedHeader: SectionHeaderView!

	private var subjectField: NSTextField!
	private var bodyView: NSTextView!
	private var amendCheckbox: NSButton!
	private var commitButton: NSButton!
	private var pushButton: NSButton!
	/// Where the branch stands against its remote, for what push should say.
	private var pushState: GitPush.State?

	/// Guards against a refresh landing while a git command is still running and
	/// showing a half-applied state.
	private var isBusy = false

	init(root: URL) {
		self.root = root
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
		refresh()

		// The lists have to follow the work tree, not just this view's own
		// commands: editing a file in the editor changes what is stageable.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(workingCopyMayHaveChanged),
			name: .abydosRepositoryChanged,
			object: nil
		)
	}

	deinit { NotificationCenter.default.removeObserver(self) }

	@objc private func workingCopyMayHaveChanged() {
		refresh()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: - Layout

	private func build() {
		unstagedHeader = SectionHeaderView(title: "Unstaged", actionTitle: "Stage")
		unstagedHeader.onAction = { [weak self] in self?.stageSelected() }
		stagedHeader = SectionHeaderView(title: "Staged", actionTitle: "Unstage")
		stagedHeader.onAction = { [weak self] in self?.unstageSelected() }

		unstagedTable = makeTable()
		unstagedTable.onActivate = { [weak self] in self?.stageSelected() }
		unstagedTable.menu = makeChangeMenu()
		stagedTable = makeTable()
		stagedTable.onActivate = { [weak self] in self?.unstageSelected() }
		stagedTable.menu = makeChangeMenu()

		let unstagedScroll = makeScrollView(for: unstagedTable)
		let stagedScroll = makeScrollView(for: stagedTable)

		// The subject is where a commit starts, so it has to look like the
		// field you type in first: the same dark ground and border as the body
		// below it, and a little larger. Flat and grey it read as disabled, and
		// people went to the body instead and left the subject empty.
		subjectField = InsetTextField()
		subjectField.placeholderString = "Summary"
		subjectField.font = Theme.current.uiFont(12, weight: .medium)
		subjectField.delegate = self
		subjectField.focusRingType = .none
		subjectField.isBordered = false
		subjectField.drawsBackground = false
		subjectField.textColor = Theme.current.sidebarText
		subjectField.wantsLayer = true
		subjectField.layer?.backgroundColor = Theme.current.editorBackground.cgColor
		subjectField.layer?.borderColor = Theme.current.separator.cgColor
		subjectField.layer?.borderWidth = 1
		subjectField.layer?.cornerRadius = 3

		bodyView = NSTextView()
		bodyView.font = Theme.current.uiFont(12)
		bodyView.textColor = Theme.current.sidebarText
		bodyView.backgroundColor = Theme.current.editorBackground
		bodyView.isRichText = false
		bodyView.textContainerInset = NSSize(width: 4, height: 4)

		let bodyScroll = NSScrollView()
		bodyScroll.documentView = bodyView
		bodyScroll.hasVerticalScroller = true
		bodyScroll.borderType = .lineBorder
		bodyScroll.drawsBackground = true
		bodyScroll.backgroundColor = Theme.current.editorBackground

		amendCheckbox = NSButton(checkboxWithTitle: "Amend", target: self, action: #selector(amendToggled))
		amendCheckbox.font = Theme.current.uiFont(11)

		commitButton = NSButton(title: "Commit", target: self, action: #selector(commit))
		commitButton.bezelStyle = .rounded
		commitButton.controlSize = .small
		commitButton.keyEquivalent = "\r"

		// Beside commit rather than inside it: "commit and push" is one gesture
		// people want, but pushing what somebody else committed is a different
		// decision from making a commit, and hiding it in a split button makes
		// it hard to do on its own.
		pushButton = NSButton(title: "Push", target: self, action: #selector(push))
		pushButton.bezelStyle = .rounded
		pushButton.controlSize = .small
		pushButton.isEnabled = false

		// Commit then push: that is the order the two happen in, and reading the
		// row left to right should not be backwards from doing it.
		let commitRow = NSStackView(views: [amendCheckbox, NSView(), commitButton, pushButton])
		commitRow.spacing = Theme.current.scaled(6)
		commitRow.orientation = .horizontal
		commitRow.distribution = .fill

		let stack = NSStackView(views: [
			unstagedHeader, unstagedScroll,
			stagedHeader, stagedScroll,
			subjectField, bodyScroll, commitRow,
		])
		stack.orientation = .vertical
		stack.spacing = 0
		stack.setCustomSpacing(Theme.current.scaled(8), after: stagedScroll)
		stack.setCustomSpacing(Theme.current.scaled(4), after: subjectField)
		stack.setCustomSpacing(Theme.current.scaled(6), after: bodyScroll)
		stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: Theme.current.scaled(8), right: 0)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		for view in [subjectField, bodyScroll, commitRow] as [NSView] {
			stack.setCustomSpacing(stack.customSpacing(after: view), after: view)
		}

		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),

			// The two lists share the space that is left after the commit box,
			// so neither can squeeze the other out.
			unstagedScroll.heightAnchor.constraint(equalTo: stagedScroll.heightAnchor),
			bodyScroll.heightAnchor.constraint(equalToConstant: Theme.current.scaled(70)),
			subjectField.heightAnchor.constraint(equalToConstant: Theme.current.scaled(24)),
		])

		// Inset the message box from the edges without inseting the lists, which
		// read better running the full width.
		for view in [subjectField, bodyScroll, commitRow] as [NSView] {
			stack.setHuggingPriority(.defaultLow, for: .horizontal)
			view.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(8)),
				view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(8)),
			])
		}
	}

	private func makeTable() -> ChangesTableView {
		let table = ChangesTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.sidebarBackground
		table.selectionHighlightStyle = .regular
		table.allowsMultipleSelection = true
		table.rowSizeStyle = .custom
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("change")))
		table.delegate = self
		table.dataSource = self
		return table
	}

	private func makeScrollView(for table: NSTableView) -> NSScrollView {
		let scrollView = NSScrollView()
		scrollView.documentView = table
		scrollView.hasVerticalScroller = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = Theme.current.sidebarBackground
		scrollView.scrollerStyle = .overlay
		return scrollView
	}

	// MARK: - Data

	func refresh() {
		guard !isBusy else { return }
		// Outside the comparison below: a clean working copy produces the same
		// status every time, and the branch can still have moved ahead of its
		// remote since the last look.
		refreshPushState()
		Task { @MainActor in
			let fresh = await GitWorkingCopy.status(in: root)
			guard fresh != status else { return }
			status = fresh
			reload()
		}
	}

	private func reload() {
		unstagedTable.reloadData()
		stagedTable.reloadData()
		unstagedHeader.setCount(status.unstaged.count)
		stagedHeader.setCount(status.staged.count)
		updateCommitButton()
	}

	private func updateCommitButton() {
		let count = status.staged.count
		let hasSubject = !subjectField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty

		// Amend can commit nothing new — rewording the last commit is a normal
		// thing to want — so it is the one case where an empty index is allowed.
		let isAmending = amendCheckbox.state == .on
		commitButton.isEnabled = hasSubject && (count > 0 || isAmending)
		commitButton.title = count > 0
			? "Commit \(count) File\(count == 1 ? "" : "s")"
			: (isAmending ? "Amend" : "Commit")

		pushButton.title = pushState?.buttonTitle ?? "Push"
		pushButton.isEnabled = !isBusy && pushState?.canPush == true
		pushButton.toolTip = pushTooltip

		// The accent goes to whichever action the page is actually for: with
		// nothing staged there is nothing to commit, and what is left to do is
		// send what is already committed. Return follows the accent, since the
		// default button is what Return means.
		let primary = CommitPageAction.primary(
			staged: count, isAmending: isAmending, canPush: pushButton.isEnabled
		)
		commitButton.keyEquivalent = primary == .commit ? "\r" : ""
		pushButton.keyEquivalent = primary == .push ? "\r" : ""
	}

	private var pushTooltip: String {
		guard let pushState else { return "Push this branch" }
		guard pushState.hasRemote else { return "This repository has no remote" }
		guard let upstream = pushState.upstream else {
			return "Push “\(pushState.branch)” to origin and track it"
		}
		if pushState.ahead == 0 { return "Nothing to push to \(upstream)" }
		return "Push \(pushState.ahead) commit\(pushState.ahead == 1 ? "" : "s") to \(upstream)"
	}

	/// Re-reads where the branch stands, and says so on the button.
	private func refreshPushState() {
		Task { @MainActor in
			pushState = await GitPush.state(in: root)
			updateCommitButton()
		}
	}

	@objc private func push() {
		guard let state = pushState, state.canPush else { return }
		let setsUpstream = state.upstream == nil

		isBusy = true
		updateCommitButton()
		Task { @MainActor in
			let result = await GitPush.push(in: root, setUpstream: setsUpstream)
			isBusy = false

			if result.exitCode == 0 {
				// git reports a push on stderr, which is where the branch and
				// the range it sent are named.
				let summary = result.stderr.isEmpty ? result.stdout : result.stderr
				Toast.post(
					"Pushed \(state.branch)",
					detail: summary.trimmingCharacters(in: .whitespacesAndNewlines),
					kind: .information
				)
			} else {
				presentFailure(result.stderr.isEmpty ? result.stdout : result.stderr)
			}

			refreshPushState()
			// The history and the branch list both show what has been pushed.
			NotificationCenter.default.post(name: .abydosRepositoryChanged, object: root)
			onWorkingCopyChanged?()
		}
	}

	// MARK: - Actions

	private func makeChangeMenu() -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false
		menu.delegate = self
		return menu
	}

	/// The change the menu was opened on, whichever list it is in.
	private var clickedChange: (change: GitChange, isStaged: Bool)? {
		for table in [unstagedTable, stagedTable] {
			guard let table else { continue }
			let row = table.clickedRow >= 0 ? table.clickedRow : -1
			guard row >= 0 else { continue }
			let source = table === stagedTable ? status.staged : status.unstaged
			guard source.indices.contains(row) else { continue }
			return (source[row], table === stagedTable)
		}
		return nil
	}

	@objc private func revealClicked() {
		guard let clicked = clickedChange else { return }
		NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(clicked.change.path)])
	}

	@objc private func copyClickedPath() {
		guard let clicked = clickedChange else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(clicked.change.path, forType: .string)
	}

	/// Offers a pattern for this file and writes it once it is agreed.
	///
	/// Offered rather than imposed: "ignore this" can mean this exact file,
	/// anything with this name, or everything this build step produces, and
	/// guessing wrong writes a line into a tracked file somebody else has to
	/// notice and undo.
	@objc private func ignoreClicked() {
		guard let clicked = clickedChange else { return }
		let path = clicked.change.path
		let isDirectory = (try? root.appendingPathComponent(path)
			.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
		let suggestions = GitIgnore.suggestions(for: path, isDirectory: isDirectory)

		let alert = NSAlert()
		alert.messageText = "Ignore \((path as NSString).lastPathComponent)"
		alert.informativeText = "The pattern is written to .gitignore. Edit it if it is not quite right."
		alert.addButton(withTitle: "Ignore")
		alert.addButton(withTitle: "Cancel")

		let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 54))
		let popup = NSPopUpButton(frame: NSRect(x: 0, y: 30, width: 360, height: 24))
		popup.addItems(withTitles: suggestions.map { "\($0.pattern)   —   \($0.explanation)" })
		container.addSubview(popup)

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
		field.stringValue = suggestions.first?.pattern ?? path
		field.font = Theme.terminalFont(size: 12)
		container.addSubview(field)

		// Choosing from the list fills the field, which stays editable: the
		// suggestions are a starting point, not the only answers.
		popup.target = self
		popup.action = #selector(ignorePatternChosen)
		ignoreSuggestions = suggestions
		ignoreField = field

		alert.accessoryView = container
		let apply: (NSApplication.ModalResponse) -> Void = { [weak self] response in
			guard response == .alertFirstButtonReturn, let self else { return }
			let pattern = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !pattern.isEmpty else { return }
			do {
				try GitIgnore.add(pattern, toRepositoryAt: self.root)
				self.refresh()
				NotificationCenter.default.post(name: .abydosRepositoryChanged, object: self.root)
			} catch {
				Toast.post("Could not write .gitignore", detail: error.localizedDescription)
			}
		}
		if let window { alert.beginSheetModal(for: window, completionHandler: apply) } else { apply(alert.runModal()) }
	}

	private var ignoreSuggestions: [GitIgnore.Suggestion] = []
	private weak var ignoreField: NSTextField?

	@objc private func ignorePatternChosen(_ sender: NSPopUpButton) {
		guard ignoreSuggestions.indices.contains(sender.indexOfSelectedItem) else { return }
		ignoreField?.stringValue = ignoreSuggestions[sender.indexOfSelectedItem].pattern
	}

	// MARK: - Stashing

	/// Which paths a stash from the menu would take.
	///
	/// The selection when the click landed inside it, and the clicked row
	/// otherwise — the rule every list follows, and the one that makes
	/// stashing a handful of files a single gesture.
	private func stashablePaths() -> [String] {
		guard let clicked = clickedChange else {
			return (status.staged + status.unstaged).map(\.path)
		}
		let table = clicked.isStaged ? stagedTable : unstagedTable
		let selected = selectedChanges(in: table ?? NSTableView()).map(\.path)
		return selected.contains(clicked.change.path) ? selected : [clicked.change.path]
	}

	@objc private func stashSelected() {
		let paths = stashablePaths()
		guard !paths.isEmpty else { return }
		promptForStashMessage(
			title: paths.count == 1
				? "Stash “\((paths[0] as NSString).lastPathComponent)”"
				: "Stash \(paths.count) files",
			message: "The changes come out of the working copy and wait in the list, "
				+ "under whatever this says.",
			suggestion: paths.count == 1 ? (paths[0] as NSString).lastPathComponent : ""
		) { [weak self] message in
			guard let self else { return }
			self.run { await GitStash.push(in: self.root, message: message, paths: paths) }
		}
	}

	@objc private func stashEverything() {
		let count = status.staged.count + status.unstaged.count
		guard count > 0 else { return }
		promptForStashMessage(
			title: "Stash all changes",
			message: "\(count) file\(count == 1 ? "" : "s") come out of the working copy and "
				+ "wait in the list, under whatever this says.",
			suggestion: ""
		) { [weak self] message in
			guard let self else { return }
			self.run { await GitStash.push(in: self.root, message: message) }
		}
	}

	/// Asks what the entry should be called.
	///
	/// A stash nobody named says `WIP on main` and nothing else, which is no
	/// help at all once there are three of them.
	private func promptForStashMessage(
		title: String,
		message: String,
		suggestion: String,
		then act: @escaping (String) -> Void
	) {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		alert.addButton(withTitle: "Stash")
		alert.addButton(withTitle: "Cancel")

		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
		field.placeholderString = "What this is"
		field.stringValue = suggestion
		alert.accessoryView = field

		let handle: (NSApplication.ModalResponse) -> Void = { response in
			guard response == .alertFirstButtonReturn else { return }
			act(field.stringValue.trimmingCharacters(in: .whitespaces))
		}
		if let window {
			alert.beginSheetModal(for: window, completionHandler: handle)
			window.makeFirstResponder(field)
		} else {
			handle(alert.runModal())
		}
	}

	private func selectedChanges(in table: NSTableView) -> [GitChange] {
		let source = table === stagedTable ? status.staged : status.unstaged
		return table.selectedRowIndexes.compactMap { source.indices.contains($0) ? source[$0] : nil }
	}

	@objc private func stageClicked() {
		guard let clicked = clickedChange else { return }
		run { await GitWorkingCopy.stage(paths: [clicked.change.path], in: self.root) }
	}

	@objc private func unstageClicked() {
		guard let clicked = clickedChange else { return }
		run { await GitWorkingCopy.unstage(paths: [clicked.change.path], in: self.root) }
	}

	private func stageSelected() {
		let paths = selectedChanges(in: unstagedTable).map(\.path)
		guard !paths.isEmpty else { return }
		run { await GitWorkingCopy.stage(paths: paths, in: self.root) }
	}

	private func unstageSelected() {
		let paths = selectedChanges(in: stagedTable).map(\.path)
		guard !paths.isEmpty else { return }
		run { await GitWorkingCopy.unstage(paths: paths, in: self.root) }
	}

	@objc private func amendToggled() {
		// Turning amend on offers the previous message, since rewording is the
		// usual reason to amend. It is not forced on a message already typed.
		if amendCheckbox.state == .on, subjectField.stringValue.isEmpty, bodyView.string.isEmpty {
			Task { @MainActor in
				guard let previous = await GitWorkingCopy.lastCommitMessage(in: root) else { return }
				subjectField.stringValue = previous.subject
				bodyView.string = previous.body
				updateCommitButton()
			}
		}
		updateCommitButton()
	}

	@objc private func commit() {
		let subject = subjectField.stringValue
		let body = bodyView.string
		let amend = amendCheckbox.state == .on
		guard !subject.trimmingCharacters(in: .whitespaces).isEmpty else { return }

		isBusy = true
		Task { @MainActor in
			let result = await GitWorkingCopy.commit(subject: subject, body: body, amend: amend, in: root)
			isBusy = false

			guard result.exitCode == 0 else {
				presentFailure(result.stderr.isEmpty ? result.stdout : result.stderr)
				return
			}

			subjectField.stringValue = ""
			bodyView.string = ""
			amendCheckbox.state = .off
			refresh()
			onWorkingCopyChanged?()
		}
	}

	/// Runs a git command, then refreshes both this view and the navigator.
	private func run(_ operation: @escaping () async -> GitRepository.ProcessResult) {
		isBusy = true
		Task { @MainActor in
			let result = await operation()
			isBusy = false

			if result.exitCode != 0 {
				presentFailure(result.stderr.isEmpty ? result.stdout : result.stderr)
			}
			refresh()
			onWorkingCopyChanged?()
		}
	}

	private func presentFailure(_ message: String) {
		Toast.post(
			"git reported a problem",
			detail: message.trimmingCharacters(in: .whitespacesAndNewlines)
		)
	}

	func pushForTesting() { push() }

	/// Selects the first unstaged change, so the screenshot harness can verify
	/// the diff without a click.
	func selectFirstChangeForTesting() {
		guard !status.unstaged.isEmpty else { return }
		unstagedTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
	}

	func applyThemeChange() {
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		subjectField.font = Theme.current.uiFont(12)
		bodyView.font = Theme.current.uiFont(12)
		unstagedTable.reloadData()
		stagedTable.reloadData()
	}
}

// MARK: - Table

extension ChangesPane: NSMenuDelegate {
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()

		func item(_ title: String, _ selector: Selector) -> NSMenuItem {
			let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
			entry.target = self
			return entry
		}

		guard let clicked = clickedChange else {
			// Nothing under the pointer, so the only thing on offer is what
			// applies to the lot.
			if !status.staged.isEmpty || !status.unstaged.isEmpty {
				menu.addItem(item("Stash All Changes…", #selector(stashEverything)))
			}
			return
		}

		menu.addItem(item(clicked.isStaged ? "Unstage" : "Stage", clicked.isStaged
			? #selector(unstageClicked) : #selector(stageClicked)))
		menu.addItem(.separator())
		// Only for something git is not already tracking: ignoring a tracked
		// file does nothing, which is a confusing thing to offer.
		if clicked.change.kind == .untracked {
			menu.addItem(item("Add to .gitignore\u{2026}", #selector(ignoreClicked)))
		}
		menu.addItem(.separator())
		// What is chosen, or what was clicked when nothing is.
		let chosen = stashablePaths()
		menu.addItem(item(
			chosen.count > 1 ? "Stash \(chosen.count) Files…" : "Stash This File…",
			#selector(stashSelected)
		))
		menu.addItem(item("Stash All Changes…", #selector(stashEverything)))
		menu.addItem(.separator())
		menu.addItem(item("Reveal in Finder", #selector(revealClicked)))
		menu.addItem(item("Copy Path", #selector(copyClickedPath)))
	}
}

extension ChangesPane: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int {
		(tableView === stagedTable ? status.staged : status.unstaged).count
	}

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		Theme.current.scaled(22)
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		let source = tableView === stagedTable ? status.staged : status.unstaged
		guard source.indices.contains(row) else { return nil }
		return ChangeRowView(change: source[row])
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		guard let table = notification.object as? NSTableView else { return }
		guard let change = selectedChanges(in: table).first else { return }

		// Selecting in one list clears the other, so the diff on screen always
		// belongs to the row that is highlighted.
		let other = table === stagedTable ? unstagedTable : stagedTable
		if !(other?.selectedRowIndexes.isEmpty ?? true) {
			other?.deselectAll(nil)
		}

		onSelectChange?(change)
	}
}

extension ChangesPane: NSTextFieldDelegate {
	func controlTextDidChange(_ notification: Notification) {
		updateCommitButton()
	}
}

/// Table that reports Return and double-click, for stage/unstage.
private final class ChangesTableView: NSTableView {
	var onActivate: (() -> Void)?

	override func keyDown(with event: NSEvent) {
		// 36 is Return, 76 the numeric keypad's.
		if event.keyCode == 36 || event.keyCode == 76 {
			onActivate?()
			return
		}
		super.keyDown(with: event)
	}

	override func mouseDown(with event: NSEvent) {
		super.mouseDown(with: event)
		if event.clickCount == 2 { onActivate?() }
	}
}

/// A section title with a count and its bulk action.
private final class SectionHeaderView: NSView {
	var onAction: (() -> Void)?

	private let title: String
	private var count = 0
	private let button: NSButton

	override var isFlipped: Bool { true }

	init(title: String, actionTitle: String) {
		self.title = title
		button = NSButton(title: actionTitle, target: nil, action: nil)
		super.init(frame: .zero)

		button.bezelStyle = .rounded
		button.controlSize = .small
		button.font = Theme.current.uiFont(11)
		button.target = self
		button.action = #selector(buttonClicked)
		button.translatesAutoresizingMaskIntoConstraints = false
		addSubview(button)

		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Theme.current.scaled(26)),
			button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(8)),
			button.centerYAnchor.constraint(equalTo: centerYAnchor),
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func setCount(_ count: Int) {
		self.count = count
		button.isEnabled = count > 0
		needsDisplay = true
	}

	@objc private func buttonClicked() { onAction?() }

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.sidebarBackground.setFill()
		bounds.fill()
		Theme.current.separator.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

		let text = count > 0 ? "\(title) (\(count))" : title
		let label = NSAttributedString(string: text, attributes: [
			.font: NSFont.systemFont(ofSize: Theme.current.scaled(11), weight: .semibold),
			.foregroundColor: Theme.current.sidebarHeaderText,
		])
		label.draw(at: NSPoint(x: Theme.current.scaled(8), y: bounds.midY - label.size().height / 2))
	}
}

/// One changed path: status letter, icon, name, then the directory.
private final class ChangeRowView: NSView {
	private let change: GitChange

	override var isFlipped: Bool { true }

	init(change: GitChange) {
		self.change = change
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var x = Theme.current.scaled(8)
		let badgeSize = Theme.current.scaled(13)

		// The status letter in its colour, as git prints it — the same letter
		// people already read in `git status`.
		let badge = NSRect(x: x, y: bounds.midY - badgeSize / 2, width: badgeSize, height: badgeSize)
		color(for: change.kind).setFill()
		NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3).fill()

		let letter = NSAttributedString(string: letter(for: change.kind), attributes: [
			.font: NSFont.systemFont(ofSize: Theme.current.scaled(9), weight: .bold),
			.foregroundColor: NSColor.black.withAlphaComponent(0.85),
		])
		letter.draw(at: NSPoint(
			x: badge.midX - letter.size().width / 2,
			y: badge.midY - letter.size().height / 2
		))
		x = badge.maxX + Theme.current.scaled(6)

		// The name first, and it gives way before the directory does: two files
		// with the same name in different places are told apart by the
		// directory, so that is the part worth keeping when the pane is narrow.
		let limit = bounds.maxX - RowMetrics.trailingInset
		x = RowMetrics.draw(
			change.name,
			font: Theme.current.uiFont(12),
			colour: Theme.current.sidebarText,
			at: x, in: bounds, limit: limit
		)

		guard !change.directory.isEmpty else { return }
		let paragraph = NSMutableParagraphStyle()
		// From the head: the end of a path says where the file is; the start of
		// it is the same for everything in the project.
		paragraph.lineBreakMode = .byTruncatingHead
		let directory = NSAttributedString(string: change.directory, attributes: [
			.font: Theme.current.uiFont(10.5),
			.foregroundColor: Theme.current.gitIgnored,
			.paragraphStyle: paragraph,
		])
		let start = x + Theme.current.scaled(6)
		directory.draw(in: NSRect(
			x: start,
			y: bounds.midY - directory.size().height / 2,
			width: max(0, limit - start),
			height: directory.size().height
		))
	}

	private func letter(for kind: GitChange.Kind) -> String {
		switch kind {
		case .added:      return "A"
		case .modified:   return "M"
		case .deleted:    return "D"
		case .renamed:    return "R"
		case .copied:     return "C"
		case .untracked:  return "U"
		case .conflicted: return "!"
		}
	}

	private func color(for kind: GitChange.Kind) -> NSColor {
		switch kind {
		case .added, .copied:  return Theme.current.gitAdded
		case .modified, .renamed: return Theme.current.gitModified
		case .deleted:         return Theme.current.gitUnversioned
		case .untracked:       return Theme.current.gitUnversioned
		case .conflicted:      return Theme.current.gitUnversioned
		}
	}
}


/// A text field with room around its text.
///
/// The commit subject draws its own background, and a field's text otherwise
/// sits hard against the left edge of it.
private final class InsetTextField: NSTextField {
	override class var cellClass: AnyClass? {
		get { InsetTextFieldCell.self }
		set { super.cellClass = newValue }
	}
}

private final class InsetTextFieldCell: NSTextFieldCell {
	/// Inset from the edges, and sitting in the middle of them.
	///
	/// A field taller than its line — which this one is, to be comfortable to
	/// click — draws the text against the top otherwise, and the placeholder
	/// sits above the line everything else is on.
	private func inset(_ rect: NSRect) -> NSRect {
		let room = rect.insetBy(dx: 5, dy: 0)
		let height = ceil(font?.boundingRectForFont.height ?? room.height)
		guard height < room.height else { return room }
		return NSRect(
			x: room.minX,
			y: room.minY + ((room.height - height) / 2).rounded(),
			width: room.width,
			height: height
		)
	}

	override func drawingRect(forBounds rect: NSRect) -> NSRect {
		super.drawingRect(forBounds: inset(rect))
	}

	override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
		super.edit(withFrame: inset(rect), in: view, editor: editor, delegate: delegate, event: event)
	}

	override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
		super.select(withFrame: inset(rect), in: view, editor: editor, delegate: delegate, start: start, length: length)
	}
}
