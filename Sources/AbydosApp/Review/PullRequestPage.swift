import AppKit
import AbydosKit

/// One pull request, opened to be read: the files it changes and the diff of
/// each.
///
/// **A page and not a panel**, for the reason the log and the commit view are
/// pages: a diff is read, and a third of a window is not for reading.
///
/// **Built from what those pages are made of.** The file list is
/// `ChangedFileList` — the same outline, the same two arrangements, the same
/// line counts and the same keyboard the commit page has always had — and the
/// diff is `DiffView`. A second arrangement of the same thing is how the two
/// come to disagree about what a rename looks like.
final class PullRequestPage: NSView {
	private let root: URL
	private(set) var request: PullRequest

	/// The head the page was opened at. Every tick is recorded against it and
	/// every comment written against it; see the `pull-requests` spec.
	private(set) var head: String?

	/// The whole diff, cut into one piece per file.
	private var diffs: [String: String] = [:]
	/// What each file's diff hashes to at the head this page was read at, which
	/// is what a tick is recorded against.
	private var tokens: [String: String] = [:]
	/// The file text at the head, for the whole-file view — asked for once per
	/// file and kept, because turning the switch off and on again should not be
	/// a second network call.
	private var contents: [String: String] = [:]

	private var fileList: ChangedFileList!
	private var diffView: DiffView!
	private var diffScroll: NSScrollView!
	private var arrangeControl: NSSegmentedControl!
	private var wholeFileSwitch: NSButton!
	private var hideReadSwitch: NSButton!
	private var progressLabel: NSTextField!
	private var headingLabel: NSTextField!
	private var subheadingLabel: NSTextField!
	private var split: NSSplitView!
	private var hasPlacedDivider = false
	private var activity: PaneActivityView?
	/// What stopped the page being a page, when something did.
	private(set) var trouble: String?

	init(root: URL, request: PullRequest) {
		self.root = root
		self.request = request
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
		activity = PaneActivityView.install(over: self, message: "Reading #\(request.number)…")
		reload()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var acceptsFirstResponder: Bool { true }

	override func becomeFirstResponder() -> Bool {
		DispatchQueue.main.async { [weak self] in self?.focusList() }
		return super.becomeFirstResponder()
	}

	/// Puts the keyboard in the file list, which is what a page is walked by.
	func focusList() {
		guard let window, window.firstResponder === self else { return }
		fileList.focusList()
	}

	// MARK: - Layout

	private func build() {
		headingLabel = NSTextField(labelWithString: "#\(request.number)  \(request.title)")
		headingLabel.font = Theme.current.uiFont(13, weight: .medium)
		headingLabel.textColor = Theme.current.sidebarText
		headingLabel.lineBreakMode = .byTruncatingTail

		subheadingLabel = NSTextField(labelWithString: subheading())
		subheadingLabel.font = Theme.current.uiFont(11)
		subheadingLabel.textColor = Theme.current.gitIgnored
		subheadingLabel.lineBreakMode = .byTruncatingTail

		fileList = ChangedFileList(
			rowHeight: Theme.current.scaled(22),
			arrangedByFolder: Settings.shared.commitFilesByFolder
		)
		fileList.onSelect = { [weak self] file in self?.show(file: file) }
		// **A file is ticked as it is read.** A reviewer's place in a long list
		// is the thing most easily lost and the most annoying to find again.
		fileList.allowsTicking = true
		fileList.onTicksChanged = { [weak self] in
			guard let self else { return }
			self.showProgress()
			self.onTicksChanged?(self.request.number, self.fileList.ticks)
		}

		diffView = DiffView()
		// **Nothing here stages anything.** `DiffView` offers staging by line
		// because the changes pane needs it; on somebody else's branch those
		// gestures are meaningless, and a menu item that cannot work is worse
		// than none. The design left this open and this is the answer: not
		// offered — and what the page gains instead is the switch below.
		diffView.isReadOnly = true

		diffScroll = NSScrollView()
		diffScroll.documentView = diffView
		diffScroll.hasVerticalScroller = true
		diffScroll.drawsBackground = true
		diffScroll.backgroundColor = Theme.current.editorBackground
		// **The document view has to be told its width** — a custom view handed
		// to a scroll view keeps the frame it was born with, which is zero. The
		// log page's comment says what that looks like.
		diffView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			diffView.leadingAnchor.constraint(equalTo: diffScroll.contentView.leadingAnchor),
			diffView.trailingAnchor.constraint(equalTo: diffScroll.contentView.trailingAnchor),
			diffView.topAnchor.constraint(equalTo: diffScroll.contentView.topAnchor),
		])

		arrangeControl = ChangedFileList.makeArrangeControl(
			target: self, action: #selector(arrangementChanged)
		)
		arrangeControl.selectedSegment = Settings.shared.commitFilesByFolder ? 1 : 0

		// **The whole file, not three lines either side of the change.** This is
		// the advantage a review in an editor has and a review in a browser
		// cannot have: the file is here, the language server is here, and the
		// question a reviewer has is usually about the code around the change
		// rather than the change.
		wholeFileSwitch = NSButton(
			checkboxWithTitle: "Whole file", target: self, action: #selector(wholeFileChanged)
		)
		wholeFileSwitch.controlSize = .small
		wholeFileSwitch.font = Theme.current.uiFont(11)
		wholeFileSwitch.state = Settings.shared.reviewShowsWholeFile ? .on : .off
		wholeFileSwitch.toolTip = "Show the change inside the whole file, not only its hunks"

		hideReadSwitch = NSButton(
			checkboxWithTitle: "Hide read", target: self, action: #selector(hideReadChanged)
		)
		hideReadSwitch.controlSize = .small
		hideReadSwitch.font = Theme.current.uiFont(11)
		hideReadSwitch.toolTip = "Leave only the files still to read"

		progressLabel = NSTextField(labelWithString: "")
		progressLabel.font = Theme.current.uiFont(11)
		progressLabel.textColor = Theme.current.gitIgnored

		let controls = NSStackView(views: [progressLabel, hideReadSwitch, arrangeControl, wholeFileSwitch])
		controls.orientation = .horizontal
		controls.spacing = Theme.current.scaled(10)

		// A scroll view on each side, and nothing else: a split view wants
		// children with no intrinsic height, which the log page's own comment
		// explains at length.
		let listSide = NSView()
		listSide.addSubview(fileList)
		fileList.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			fileList.topAnchor.constraint(equalTo: listSide.topAnchor),
			fileList.leadingAnchor.constraint(equalTo: listSide.leadingAnchor),
			fileList.trailingAnchor.constraint(equalTo: listSide.trailingAnchor),
			fileList.bottomAnchor.constraint(equalTo: listSide.bottomAnchor),
		])

		split = NSSplitView()
		split.isVertical = true
		split.dividerStyle = .thin
		split.addArrangedSubview(listSide)
		split.addArrangedSubview(diffScroll)
		split.delegate = self
		split.translatesAutoresizingMaskIntoConstraints = false

		for view in [headingLabel, subheadingLabel, controls, split] as [NSView] {
			addSubview(view)
			view.translatesAutoresizingMaskIntoConstraints = false
		}

		let inset = Theme.current.scaled(10)
		NSLayoutConstraint.activate([
			headingLabel.topAnchor.constraint(equalTo: topAnchor, constant: inset),
			headingLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			headingLabel.trailingAnchor.constraint(
				lessThanOrEqualTo: controls.leadingAnchor, constant: -inset
			),

			controls.topAnchor.constraint(equalTo: topAnchor, constant: inset),
			controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

			subheadingLabel.topAnchor.constraint(equalTo: headingLabel.bottomAnchor, constant: 2),
			subheadingLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			subheadingLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

			split.topAnchor.constraint(equalTo: subheadingLabel.bottomAnchor, constant: inset / 2),
			split.leadingAnchor.constraint(equalTo: leadingAnchor),
			split.trailingAnchor.constraint(equalTo: trailingAnchor),
			split.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	private func subheading() -> String {
		var parts = ["\(request.author) wants to merge \(request.headRefName) into \(request.baseRefName)"]
		if request.isDraft { parts.append("draft") }
		if !request.checks.summary.isEmpty { parts.append(request.checks.summary) }
		if let trouble { parts.append(trouble) }
		return parts.joined(separator: " · ")
	}

	/// Puts the divider somewhere sensible the first time there is a width to
	/// put it at — once, so a drag is not undone by the next layout.
	override func layout() {
		super.layout()
		guard !hasPlacedDivider, bounds.width > 1 else { return }
		hasPlacedDivider = true
		split.setPosition(bounds.width * 0.32, ofDividerAt: 0)
	}

	// MARK: - Asking

	func reload() {
		Task { @MainActor [weak self] in
			guard let self else { return }
			let head = await GitHubPullRequests.head(of: self.request.number, in: self.root)
			let files = await GitHubPullRequests.files(of: self.request.number, in: self.root)
			let diff = await GitHubPullRequests.diff(of: self.request.number, in: self.root)

			self.activity?.finish()
			self.activity = nil
			self.head = head
			self.diffs = FileDiffs.split(diff.value ?? "")
			self.contents = [:]

			// **What a tick was made against is that file's diff at that head.**
			// Not the head commit: a rebase moves the head without changing a
			// single file's diff, and clearing every tick on every push is how a
			// checklist comes to be ignored.
			self.tokens = self.diffs.mapValues { FileDiffs.token(forDiff: $0) }
			self.fileList.setTokens(self.tokens)

			switch files {
			case .answered(let listed):
				self.trouble = listed.isEmpty ? "This pull request changes no files." : diff.trouble
				self.fileList.setFiles(
					listed.map(\.asCommitFile),
					lineCounts: Dictionary(
						listed.map { ($0.path, $0.lineCount) }, uniquingKeysWith: { first, _ in first }
					)
				)
				self.onFilesLoaded?(listed)
				// The ticks come back, and then the ones whose file has moved
				// under them go. Said out loud rather than silently: a tick
				// disappearing without a word reads as a bug.
				let cleared = self.fileList.revalidateTicks()
				if !cleared.isEmpty {
					self.clearedByThePush = cleared
				}
				self.showProgress()
				// Opened to be read: the first file, rather than an empty half.
				if let first = listed.first { self.fileList.select(path: first.path) }
			case .unavailable, .failed:
				self.trouble = files.trouble
				self.fileList.setFiles([])
			}
			self.subheadingLabel.stringValue = self.subheading()
		}
	}

	/// The files, once they are known — for whatever is built on top of them.
	var onFilesLoaded: (([PullRequestFile]) -> Void)?

	/// Somebody ticked a file, so whatever remembers ticks should.
	var onTicksChanged: ((Int, Checklist<String>) -> Void)?

	/// Which ticks the last read cleared, for the report to say.
	private(set) var clearedByThePush: Set<String> = []

	/// The ticks as they stand, for whatever writes them down.
	var ticks: Checklist<String> { fileList.ticks }

	/// Puts a remembered set of ticks back. Called before the files arrive, so
	/// the revalidation that follows them has something to check.
	func restore(ticks: Checklist<String>) { fileList.setTicks(ticks) }

	/// The diff of one file at the head this page was opened at.
	func diff(of path: String) -> String? { diffs[path] }

	private func show(file: GitCommitFile) {
		guard let diff = diffs[file.path] else {
			diffView.setDiff("", staged: false)
			return
		}
		onFileShown?(file.path)

		guard Settings.shared.reviewShowsWholeFile, let head else {
			diffView.setDiff(diff, staged: false, url: root.appendingPathComponent(file.path))
			return
		}

		// The narrow diff first and the wide one when it arrives: a network
		// call is not something to leave a pane blank for, and the two draw the
		// same change.
		diffView.setDiff(diff, staged: false, url: root.appendingPathComponent(file.path))
		if let text = contents[file.path] {
			showWholeFile(diff: diff, contents: text, path: file.path)
			return
		}
		Task { @MainActor [weak self] in
			guard let self else { return }
			let reply = await GitHubPullRequests.contents(of: file.path, at: head, in: self.root)
			guard let text = reply.value else { return }
			self.contents[file.path] = text
			// The selection may have moved on while this was in flight.
			guard self.fileList.selectedPath == file.path else { return }
			self.showWholeFile(diff: diff, contents: text, path: file.path)
		}
	}

	private func showWholeFile(diff: String, contents: String, path: String) {
		// Nil rather than a guess when the patch and the text do not fit each
		// other; the hunks are then what is drawn, which is never wrong.
		guard let wide = WholeFileDiff.expand(diff: diff, contents: contents) else { return }
		diffView.setDiff(wide, staged: false, url: root.appendingPathComponent(path))
	}

	/// Which file the diff is showing — for whatever is built on top of it.
	var onFileShown: ((String) -> Void)?

	@objc private func arrangementChanged() {
		Settings.shared.commitFilesByFolder = arrangeControl.selectedSegment == 1
		fileList.arrangesByFolder = Settings.shared.commitFilesByFolder
	}

	@objc private func hideReadChanged() {
		fileList.setHidesDone(hideReadSwitch.state == .on)
	}

	/// How much of the list has been read, and what a cleared tick did.
	private func showProgress() {
		let (done, total) = fileList.progress
		progressLabel.stringValue = total == 0 ? "" : "\(done) of \(total) read"
	}

	@objc private func wholeFileChanged() {
		Settings.shared.reviewShowsWholeFile = wholeFileSwitch.state == .on
		guard let file = fileList.selectedFile else { return }
		show(file: file)
	}

	// MARK: - Testing

	/// What the page holds: the pull request, its files, and the diff on screen.
	func reportForTesting() -> String {
		var said = ["#\(request.number) \(request.title)"]
		said.append("head=\(head?.prefix(8).description ?? "unknown")")
		said.append("whole-file=\(Settings.shared.reviewShowsWholeFile ? "on" : "off")")
		if let trouble { said.append("trouble=\(trouble)") }
		let (done, total) = fileList.progress
		said.append("read=\(done)/\(total)")
		if !clearedByThePush.isEmpty {
			said.append("cleared=" + clearedByThePush.sorted().joined(separator: ", "))
		}
		said.append("files=\(fileList.files.count)")
		said += fileList.rowsForTesting().prefix(12).map { "  " + $0 }
		said.append("diff=\(diffView.reportForTesting)")
		return said.joined(separator: "\n")
	}

	/// Whether the answer has come back, so a driven run can wait for it.
	var hasAnsweredForTesting: Bool { activity == nil }

	func fileKeysForTesting(_ steps: String) -> String { fileList.keysForTesting(steps) }

	func selectFileForTesting(_ index: Int) { fileList.select(index: index) }

	/// Ticks or unticks the selected file, as ␣ does.
	func toggleReadForTesting() { fileList.setDoneAtSelection(nil) }

	/// Goes to the next file nobody has read, as ⌥↓ does.
	@discardableResult
	func nextUnreadForTesting() -> Bool { fileList.selectNextUndone() }

	/// Pretends the author pushed a change to one file.
	///
	/// **It fakes the input and nothing else**, and says so rather than hiding
	/// it: the token that file's diff hashes to is replaced, and everything
	/// downstream — the revalidation, the row, the count — is the real path. The
	/// honest version of this would move a real head, which means pushing to a
	/// repository, and nothing here may do that.
	///
	/// Called with no path it revalidates against the tokens as they are, which
	/// is the other case that matters: a rebase that changed no file's diff
	/// clears nothing.
	func pretendPushForTesting(_ path: String) -> String {
		if !path.isEmpty {
			tokens[path] = (tokens[path] ?? "") + "-pushed"
			fileList.setTokens(tokens)
		}
		let cleared = fileList.revalidateTicks()
		clearedByThePush = cleared
		showProgress()
		let (done, total) = fileList.progress
		return cleared.isEmpty
			? "nothing cleared, \(done) of \(total) still read"
			: "cleared " + cleared.sorted().joined(separator: ", ") + ", \(done) of \(total) still read"
	}

	func setHideReadForTesting(_ on: Bool) {
		hideReadSwitch.state = on ? .on : .off
		hideReadChanged()
	}

	func setWholeFileForTesting(_ on: Bool) {
		wholeFileSwitch.state = on ? .on : .off
		wholeFileChanged()
	}

	/// The first lines of the diff on screen, so a run can show what changed
	/// rather than only how many rows there are.
	func diffTextForTesting(lines: Int = 12) -> String {
		guard let path = fileList.selectedPath else { return "nothing selected" }
		guard let diff = diffs[path] else { return "no diff for \(path)" }
		let shown = Settings.shared.reviewShowsWholeFile
			? contents[path].flatMap { WholeFileDiff.expand(diff: diff, contents: $0) } ?? diff
			: diff
		let all = shown.split(separator: "\n", omittingEmptySubsequences: false)
		let head = all.prefix(lines).joined(separator: "\n")
		guard all.count > lines else { return head }
		return head + "\n… and \(all.count - lines) more lines not printed"
	}
}

extension PullRequestPage: NSSplitViewDelegate {
	func splitView(
		_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int
	) -> CGFloat {
		Theme.current.scaled(180)
	}

	func splitView(
		_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int
	) -> CGFloat {
		splitView.bounds.width - Theme.current.scaled(240)
	}
}
