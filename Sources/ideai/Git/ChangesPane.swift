import AppKit
import IdeaiKit

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
			name: .ideaiRepositoryChanged,
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
		stagedTable = makeTable()
		stagedTable.onActivate = { [weak self] in self?.unstageSelected() }

		let unstagedScroll = makeScrollView(for: unstagedTable)
		let stagedScroll = makeScrollView(for: stagedTable)

		subjectField = NSTextField()
		subjectField.placeholderString = "Commit subject"
		subjectField.font = Theme.current.uiFont(12)
		subjectField.delegate = self
		subjectField.focusRingType = .none

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

		let commitRow = NSStackView(views: [amendCheckbox, NSView(), commitButton])
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
	}

	// MARK: - Actions

	private func selectedChanges(in table: NSTableView) -> [GitChange] {
		let source = table === stagedTable ? status.staged : status.unstaged
		return table.selectedRowIndexes.compactMap { source.indices.contains($0) ? source[$0] : nil }
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
		let alert = NSAlert()
		alert.messageText = "git reported a problem"
		alert.informativeText = message.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let window else {
			alert.runModal()
			return
		}
		alert.beginSheetModal(for: window)
	}

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

		let name = NSAttributedString(string: change.name, attributes: [
			.font: Theme.current.uiFont(12),
			.foregroundColor: Theme.current.sidebarText,
		])
		name.draw(at: NSPoint(x: x, y: bounds.midY - name.size().height / 2))
		x += name.size().width + Theme.current.scaled(6)

		// The directory follows in grey, so files with the same name in
		// different places are still tellable apart.
		guard !change.directory.isEmpty else { return }
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingHead
		let directory = NSAttributedString(string: change.directory, attributes: [
			.font: Theme.current.uiFont(10.5),
			.foregroundColor: Theme.current.gitIgnored,
			.paragraphStyle: paragraph,
		])
		directory.draw(in: NSRect(
			x: x,
			y: bounds.midY - directory.size().height / 2,
			width: max(0, bounds.width - x - Theme.current.scaled(8)),
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
