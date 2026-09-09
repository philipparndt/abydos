import AppKit
import AbydosKit

/// Putting the pane together: the two lists, the message field, the diff
/// beside them, and what moves when the pane is narrow.
extension ChangesPane {
	// MARK: - Layout

	func build() {
		unstagedHeader = SectionHeaderView(title: "Unstaged", actionTitle: "Stage")
		unstagedHeader.onAction = { [weak self] in self?.stageSelected() }
		stagedHeader = SectionHeaderView(title: "Staged", actionTitle: "Unstage")
		stagedHeader.onAction = { [weak self] in self?.unstageSelected() }

		unstagedTable = makeTable()
		unstagedTable.onActivate = { [weak self] row in
			guard let self else { return }
			self.activate(row: row, in: self.unstagedTable)
		}
		unstagedTable.menu = makeChangeMenu()
		stagedTable = makeTable()
		stagedTable.onActivate = { [weak self] row in
			guard let self else { return }
			self.activate(row: row, in: self.stagedTable)
		}
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
		// The library's radius, not a third one: a corner that disagrees with
		// the drawn buttons' by two points reads as a different kind of object.
		subjectField.layer?.cornerRadius = ControlMetrics.radius(scale: Theme.current.scale)

		bodyView = NSTextView()
		bodyView.font = Theme.current.uiFont(12)
		bodyView.textColor = Theme.current.sidebarText
		bodyView.backgroundColor = Theme.current.editorBackground
		bodyView.isRichText = false
		bodyView.textContainerInset = NSSize(width: 4, height: 4)

		// What a text view in a scroll view needs before it is any size at all.
		// Without it the view keeps its empty starting frame however large the
		// box around it looks, so every click in the details field landed on the
		// scroll view behind it and the caret never arrived — the field looked
		// like a field and refused to be typed in.
		bodyView.isEditable = true
		bodyView.isSelectable = true
		bodyView.isVerticallyResizable = true
		bodyView.isHorizontallyResizable = false
		bodyView.autoresizingMask = [.width]
		bodyView.minSize = .zero
		bodyView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		bodyView.textContainer?.widthTracksTextView = true
		bodyView.textContainer?.containerSize = NSSize(
			width: 0, height: CGFloat.greatestFiniteMagnitude
		)

		let bodyScroll = NSScrollView()
		bodyScroll.documentView = bodyView
		bodyScroll.hasVerticalScroller = true
		bodyScroll.borderType = .lineBorder
		bodyScroll.drawsBackground = true
		bodyScroll.backgroundColor = Theme.current.editorBackground

		amendCheckbox = DrawnCheckbox(title: "Amend") { [weak self] in self?.amendToggled() }

		commitButton = DrawnButton(title: "Commit") { [weak self] in self?.commit() }
		commitButton.tip = StyledTip.Tip(
			title: "Commit the staged changes",
			detail: "What is under Staged, with the message above."
		)
		commitButton.keyEquivalent = "\r"
		// **⌘Return, not Return.** The button carried plain Return, which is the
		// key the summary field now uses to open the description — and a page
		// where the summary cannot be committed from the keyboard at all would be
		// worse than either. ⌘Return is what a page with a text area on it means
		// by "commit" everywhere else, and it works from the description too,
		// where Return has always been a newline.
		commitButton.keyEquivalentModifierMask = [.command]

		// Beside commit rather than inside it: "commit and push" is one gesture
		// people want, but pushing what somebody else committed is a different
		// decision from making a commit, and hiding it in a split button makes
		// it hard to do on its own.
		pushButton = DrawnButton(title: "Push") { [weak self] in self?.push() }
		pushButton.tip = StyledTip.Tip(
			title: "Push this branch",
			detail: "To its upstream, or setting one if it has none yet."
		)
		pushButton.isEnabled = false
		// The two swap `\r` between them in `updateCommitButton`, so the modifier
		// belongs to both or the swap would give Return back.
		pushButton.keyEquivalentModifierMask = [.command]

		// Commit then push: that is the order the two happen in, and reading the
		// row left to right should not be backwards from doing it.
		let commitRow = NSStackView(views: [amendCheckbox, NSView(), commitButton, pushButton])
		commitRow.spacing = Theme.current.scaled(6)
		commitRow.orientation = .horizontal
		commitRow.distribution = .fill

		if arrangement == .page {
			arrangePage(
				unstaged: unstagedScroll, staged: stagedScroll,
				body: bodyScroll, commitRow: commitRow
			)
			return
		}

		// **The description leaves the column.** Seventy points of text view is
		// where a commit message goes to be one line long; the page is where a
		// message somebody will read in a year gets written, and `…` is how you
		// get there with what you have already typed.
		let more = DrawnButton(title: "…") { [weak self] in self?.openPage() }
		more.tip = StyledTip.Tip(
			title: "Open the commit page",
			detail: "The same commit, with room for the description and the file list."
		)
		commitRow.addArrangedSubview(more)

		let stack = NSStackView(views: [
			unstagedHeader, unstagedScroll,
			stagedHeader, stagedScroll,
			subjectField, commitRow,
		])
		stack.orientation = .vertical
		stack.spacing = 0
		stack.setCustomSpacing(Theme.current.scaled(8), after: stagedScroll)
		stack.setCustomSpacing(Theme.current.scaled(6), after: subjectField)
		stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: Theme.current.scaled(8), right: 0)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		for view in [subjectField, commitRow] as [NSView] {
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
			heights.height(subjectField, design: 24),
		])
		ControlRow.matchHeights(to: subjectField, of: [amendCheckbox, commitButton, pushButton, more])

		// Inset the message box from the edges without inseting the lists, which
		// read better running the full width.
		for view in [subjectField, commitRow] as [NSView] {
			stack.setHuggingPriority(.defaultLow, for: .horizontal)
			view.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(8)),
				view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(8)),
			])
		}
	}

	/// The trees, the diff beside them, and the message under both.
	///
	/// The same shape the log page takes, because it is the same thing in
	/// another tense: a list of changes on the left, the diff of the selected
	/// one on the right, and what to do with the set along the bottom. The
	/// working copy is the commit that has not happened yet.
	private func arrangePage(
		unstaged: NSScrollView, staged: NSScrollView,
		body: NSScrollView, commitRow: NSStackView
	) {
		diffView = DiffView()
		let diffScroll = NSScrollView()
		diffScroll.documentView = diffView
		diffScroll.hasVerticalScroller = true
		diffScroll.drawsBackground = true
		diffScroll.backgroundColor = Theme.current.editorBackground

		// **The document view has to be told its width.** A custom view handed
		// to a scroll view keeps whatever frame it was born with — zero — so
		// there was nothing to scroll and nothing to click: the diff was drawn
		// by a view the size of a point. Pinned to the clip view's width, with
		// the height coming from `intrinsicContentSize`, which is what it is
		// for.
		diffView?.translatesAutoresizingMaskIntoConstraints = false
		if let diffView {
			NSLayoutConstraint.activate([
				diffView.leadingAnchor.constraint(equalTo: diffScroll.contentView.leadingAnchor),
				diffView.trailingAnchor.constraint(equalTo: diffScroll.contentView.trailingAnchor),
				diffView.topAnchor.constraint(equalTo: diffScroll.contentView.topAnchor),
			])
		}

		let lists = NSStackView(views: [unstagedHeader, unstaged, stagedHeader, staged])
		lists.orientation = .vertical
		lists.spacing = 0
		unstaged.heightAnchor.constraint(equalTo: staged.heightAnchor).isActive = true

		// **The description starts put away.** The message area cost a fixed 224
		// points at every height — a 26-point summary, a description pinned at
		// 150, the commit row, two gaps and the insets — so a short page showed
		// four lines of diff under a box nobody had typed in. The sidebar keeps
		// the one-line case; this page is reached because somebody wants the
		// diff or a longer message, and the diff is the half that is already
		// there.
		descriptionChevron = DrawnButton(
			symbol: "chevron.right", description: "Show the description"
		) { [weak self] in self?.toggleDescription() }
		descriptionChevron.prominence = .quiet

		// **The messages this repository has already committed, one menu away.**
		// A message like the last one — a repeated chore, a second try after an
		// amend — had to be retyped or fished out of the log page by hand.
		// Hidden while there are no commits, the amend checkbox's emptiness
		// rule: there is no history to show.
		let history = DrawnButton(
			symbol: "clock", description: "Message history"
		) { [weak self] in self?.openMessageHistory() }
		history.tip = StyledTip.Tip(
			title: "Message history",
			detail: "One of the repository's recent commit messages, to start from."
		)
		history.prominence = .quiet
		historyButton = history

		// **The draft sits beside the summary**, because that is the field it
		// fills and the one that is hardest to start. Disabled rather than
		// absent when there is no `claude` to run: a disabled control fails
		// nothing when pressed, and the absent one was requested as a missing
		// feature by somebody whose machine was hiding it. The reason sits in
		// the tooltip, the way the push button explains itself.
		draftButton = DrawnButton(title: "Draft") { [weak self] in self?.draftMessage() }
		// **Quiet, all three.** The chevron, the clock and Draft help write the
		// message; Commit and Push act on it. Drawn alike, five bordered
		// controls at three heights said nothing about which two mattered.
		draftButton!.prominence = .quiet
		let summaryRow: [NSView] = [descriptionChevron, subjectField, history, draftButton!]
		let summary = NSStackView(views: summaryRow)
		summary.orientation = .horizontal
		summary.spacing = Theme.current.scaled(6)

		descriptionBox = body
		let message = NSStackView(views: [summary, body, commitRow])
		messageStack = message
		message.orientation = .vertical
		message.spacing = Theme.current.scaled(6)
		message.edgeInsets = NSEdgeInsets(
			top: Theme.current.scaled(8), left: Theme.current.scaled(8),
			bottom: Theme.current.scaled(8), right: Theme.current.scaled(8)
		)

		// **The message belongs to the diff, not to the page.** It used to span
		// the whole width, under the file lists as well — which cost the tree
		// height for a message that has nothing to do with it. In the split's
		// right-hand side it is the diff's width, and the divider moves the two
		// together.
		let commitSide = NSStackView(views: [diffScroll, message])
		commitSide.orientation = .vertical
		commitSide.spacing = 0

		let split = NSSplitView()
		split.isVertical = true
		split.dividerStyle = .thin
		split.addArrangedSubview(lists)
		split.addArrangedSubview(commitSide)
		// The list gives way first: a diff with its right-hand columns cut off
		// is unreadable, where a path that has lost a folder or two is not.
		split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
		split.translatesAutoresizingMaskIntoConstraints = false
		pageSplit = split

		addSubview(split)

		descriptionHeight = heights.height(body, design: 150)
		NSLayoutConstraint.activate([
			split.topAnchor.constraint(equalTo: topAnchor),
			split.leadingAnchor.constraint(equalTo: leadingAnchor),
			split.trailingAnchor.constraint(equalTo: trailingAnchor),
			split.bottomAnchor.constraint(equalTo: bottomAnchor),

			heights.height(subjectField, design: 26),
			lists.widthAnchor.constraint(greaterThanOrEqualToConstant: Theme.current.scaled(280)),
			diffScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: Theme.current.scaled(320)),
		])
		// **Amend on the field's edge, not the chevron's**, through a slot the
		// chevron's width inside the row. A constraint from the checkbox across
		// to the field pulled the whole row over instead, and left Push 32
		// points short of Draft.
		let slot = NSView()
		commitRow.insertArrangedSubview(slot, at: 0)
		slot.widthAnchor.constraint(equalTo: descriptionChevron.widthAnchor).isActive = true
		ControlRow.matchHeights(to: subjectField, of: [
			descriptionChevron, history, draftButton!, amendCheckbox, commitButton, pushButton,
		])

		// Collapsed at build, and the same at every height: a description that
		// appeared and disappeared as the page was resized would be a layout
		// nobody can predict, and the height at which it changed a number nobody
		// knows.
		setDescription(showing: false)
	}

	/// Shows or hides the description, keeping whatever is in it.
	func setDescription(showing: Bool) {
		// The sidebar arrangement has no chevron and no description of its own:
		// it is the one-line case, and the `…` beside it is how a message gets
		// somewhere with room. Called from the draft, which both arrangements
		// offer.
		guard descriptionChevron != nil else { return }
		isDescriptionShowing = showing
		descriptionBox.isHidden = !showing
		descriptionHeight.isActive = showing
		descriptionChevron.setSymbol(
			showing ? "chevron.down" : "chevron.right",
			description: showing ? "Hide the description" : "Write a description"
		)
		descriptionChevron.toolTip = showing ? "Hide the description" : "Write a description"
	}

	@objc func toggleDescription() {
		setDescription(showing: !isDescriptionShowing)
		if isDescriptionShowing { window?.makeFirstResponder(bodyView) }
	}

	/// Puts the divider somewhere sensible the first time there is a width for
	/// it, and never again — a split that reset itself on every layout would
	/// undo the drag somebody had just made.
	override func layout() {
		super.layout()
		guard !hasPlacedDivider, let pageSplit, bounds.width > 1 else { return }
		hasPlacedDivider = true
		pageSplit.setPosition(bounds.width * 0.42, ofDividerAt: 0)
	}

	private func makeTable() -> ChangesOutlineView {
		let table = ChangesOutlineView()
		table.headerView = nil
		table.backgroundColor = Theme.current.sidebarBackground
		table.selectionHighlightStyle = .regular
		table.allowsMultipleSelection = true
		table.rowSizeStyle = .custom
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		// The navigator's indent, so the two trees in the window line up.
		table.indentationPerLevel = Theme.current.scaled(14)
		table.autoresizesOutlineColumn = false
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("change"))
		table.addTableColumn(column)
		table.outlineTableColumn = column
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
}
