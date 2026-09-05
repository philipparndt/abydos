import AppKit
import AbydosKit

/// The open pull requests of this repository, and which of them are waiting on
/// you.
///
/// **A review list is opened to answer one question**: what is waiting on me.
/// So the ones this account has been asked to review are marked, and the rest
/// are listed under them rather than mixed in with them — a wall of rows in
/// which the two are told apart by reading each one is a wall.
///
/// Draft and checks are on the row for the same kind of reason. A pull request
/// whose build is red is usually not worth reading line by line yet, and that is
/// a fact about the work rather than about the reviewer's taste.
///
/// **What is not here is a poll.** The list is fetched when the pane opens and
/// when somebody asks for it again. `gh` is a process and a network call, GitHub
/// has rate limits, and a sidebar that re-asks on every filesystem event — which
/// is what the other git panes do, because git is local and cheap — would spend
/// somebody's API budget on nothing.
final class PullRequestsPane: NSView {
	/// Somebody chose one to read.
	var onOpen: ((PullRequest) -> Void)?
	/// Check its branch out beside the project, or finish with that checkout.
	var onCheckOut: ((PullRequest) -> Void)?
	var onFinishCheckout: ((PullRequest) -> Void)?
	/// Point the window at the checkout made for it.
	var onOpenCheckout: ((PullRequest) -> Void)?
	/// Whether there is a checkout of it to open or finish with.
	var isCheckedOut: (PullRequest) -> Bool = { _ in false }

	private let root: URL
	private var requests: [PullRequest] = []
	/// What stopped the list being a list, when something did.
	private var trouble: String?

	private var table: PullRequestTable!
	private var scroll: NSScrollView!
	private var scopeControl: DrawnChoice!
	private var refreshButton: DrawnButton!
	private var troubleView: NSTextField!
	private var activity: PaneActivityView?
	/// Which `gh`, for a driven run — see `reportForTesting`.
	private var cliVersion: String?

	private var scope: ReviewRequestScope {
		Settings.shared.reviewRequestsIncludeTeams ? .meOrMyTeams : .me
	}

	init(root: URL) {
		self.root = root
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.sidebarBackground.cgColor
		build()
		activity = PaneActivityView.install(over: self, message: "Asking GitHub…")
		reload()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var acceptsFirstResponder: Bool { true }

	override func becomeFirstResponder() -> Bool {
		// After this call, not during it — the window is still assigning the
		// responder it was asked for. `HistoryPane` says why at length.
		DispatchQueue.main.async { [weak self] in self?.focusList() }
		return super.becomeFirstResponder()
	}

	/// Puts the keyboard in the list, which is the only thing here to walk.
	func focusList() {
		guard let window, window.firstResponder === self else { return }
		window.makeFirstResponder(table)
	}

	// MARK: - Layout

	private func build() {
		// Two segments rather than a checkbox, so the question being asked is on
		// screen rather than remembered. Which of the two is right depends on
		// how a repository assigns its reviews, which cannot be worked out from
		// here — see `ReviewRequestScope`.
		scopeControl = DrawnChoice(
			segments: ReviewRequestScope.allCases.map { .words($0.title) },
			selectedIndex: scope == .meOrMyTeams ? 1 : 0
		) { [weak self] index in self?.scopeChanged(to: index) }

		// **Asked for, never polled.** The list costs a network call and an API
		// budget; a button is how somebody says they want to spend one.
		refreshButton = DrawnButton(
			symbol: "arrow.clockwise", description: "Ask GitHub again"
		) { [weak self] in self?.refreshPressed() }
		refreshButton.tip = StyledTip.Tip(
			title: "Ask GitHub again",
			detail: "The list is asked for rather than polled: it costs a network call and an API budget."
		)

		table = PullRequestTable()
		table.headerView = nil
		table.backgroundColor = Theme.current.sidebarBackground
		table.selectionHighlightStyle = .regular
		table.rowSizeStyle = .custom
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column")))
		table.delegate = self
		table.dataSource = self
		table.target = self
		table.doubleAction = #selector(rowDoubleClicked)
		table.onOpenSelection = { [weak self] in self?.openSelection() }
		table.onMenu = { [weak self] row in self?.menu(forRow: row) }

		scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.sidebarBackground

		// **A sentence, not an empty list.** The three answers that are not
		// errors land here, and the whole reason they exist is that a blank pane
		// says "this repository has no pull requests" whatever the truth is.
		troubleView = NSTextField(wrappingLabelWithString: "")
		troubleView.font = Theme.current.uiFont(11.5)
		troubleView.textColor = Theme.current.gitIgnored
		troubleView.alignment = .left
		troubleView.isSelectable = true
		troubleView.isHidden = true

		let head = NSStackView(views: [scopeControl, refreshButton])
		head.orientation = .horizontal
		head.spacing = Theme.current.scaled(6)

		for view in [head, scroll, troubleView] as [NSView] {
			addSubview(view)
			view.translatesAutoresizingMaskIntoConstraints = false
		}

		let inset = Theme.current.scaled(8)
		NSLayoutConstraint.activate([
			head.topAnchor.constraint(equalTo: topAnchor, constant: inset),
			head.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			head.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),

			scroll.topAnchor.constraint(equalTo: head.bottomAnchor, constant: inset / 2),
			scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

			troubleView.topAnchor.constraint(equalTo: head.bottomAnchor, constant: inset),
			troubleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			troubleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
		])
	}

	// MARK: - Asking

	/// Asks GitHub, once.
	func reload() {
		let asked = scope
		Task { @MainActor [weak self] in
			guard let self else { return }
			self.refreshButton.isEnabled = false
			if self.cliVersion == nil {
				self.cliVersion = await GitHubCLI.version(in: self.root)
			}
			let reply = await GitHubPullRequests.list(in: self.root, scope: asked)
			self.refreshButton.isEnabled = true
			self.activity?.finish()
			self.activity = nil
			// Another scope was chosen while this was in flight.
			guard asked == self.scope else { return }
			self.show(reply)
		}
	}

	private func show(_ reply: ForgeReply<[PullRequest]>) {
		switch reply {
		case .answered(let listed):
			// Waiting on the reader first, and the rest under them, each half
			// newest first. The sort is what makes the mark worth having: a
			// list somebody has to read all of to find their two has not
			// answered the question it was opened for.
			requests = listed.sorted {
				if $0.isWaitingOnMe != $1.isWaitingOnMe { return $0.isWaitingOnMe }
				return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
			}
			trouble = requests.isEmpty ? "No pull requests are open." : nil
		case .unavailable, .failed:
			requests = []
			trouble = reply.trouble
		}

		troubleView.stringValue = trouble ?? ""
		troubleView.isHidden = trouble == nil
		scroll.isHidden = trouble != nil
		table.reloadData()
	}

	private func scopeChanged(to index: Int) {
		Settings.shared.reviewRequestsIncludeTeams = index == 1
		reload()
	}

	@objc private func refreshPressed() { reload() }

	@objc private func rowDoubleClicked() { openSelection() }

	/// What a right-click over a pull request offers.
	///
	/// **A double click is not a way anybody finds.** Starting a review is the
	/// thing this whole pane exists for, and until now it was a gesture with no
	/// sign of itself — so it is the first item of a menu, in words, with
	/// everything else that can be done to a row under it.
	private func menu(forRow row: Int) -> NSMenu? {
		guard requests.indices.contains(row) else { return nil }
		// The selection moves to what was aimed at, so the commands act on it.
		table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		let request = requests[row]

		let menu = NSMenu()
		menu.autoenablesItems = false
		func add(_ title: String, _ action: Selector) {
			let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
			item.target = self
			menu.addItem(item)
		}

		add("Review #\(request.number)…", #selector(openSelected))
		menu.addItem(.separator())
		if isCheckedOut(request) {
			add("Open the Checkout", #selector(openCheckoutOfSelected))
			add("Finish With the Checkout", #selector(finishCheckoutOfSelected))
		} else {
			add("Check Out the Branch", #selector(checkOutSelected))
		}
		menu.addItem(.separator())
		add("Copy Link", #selector(copyLinkOfSelected))
		add("Open in Browser", #selector(openSelectedInBrowser))
		menu.addItem(.separator())
		add("Ask GitHub Again", #selector(refreshPressed))
		return menu
	}

	private var selectedRequest: PullRequest? {
		requests.indices.contains(table.selectedRow) ? requests[table.selectedRow] : nil
	}

	@objc private func openSelected() { openSelection() }

	@objc private func checkOutSelected() {
		guard let request = selectedRequest else { return }
		onCheckOut?(request)
	}

	@objc private func finishCheckoutOfSelected() {
		guard let request = selectedRequest else { return }
		onFinishCheckout?(request)
	}

	@objc private func openCheckoutOfSelected() {
		guard let request = selectedRequest else { return }
		onOpenCheckout?(request)
	}

	@objc private func copyLinkOfSelected() {
		guard let url = selectedRequest?.url else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(url.absoluteString, forType: .string)
	}

	@objc private func openSelectedInBrowser() {
		guard let url = selectedRequest?.url else { return }
		NSWorkspace.shared.open(url)
	}

	private func openSelection() {
		guard requests.indices.contains(table.selectedRow) else { return }
		onOpen?(requests[table.selectedRow])
	}

	// MARK: - Testing

	/// What each row says, and which `gh` said it.
	///
	/// The version is here rather than in a log line because `gh`'s JSON is a
	/// contract this program does not own: a run that decodes something
	/// unexpected has to be able to say which version produced it, or the change
	/// is a mystery rather than a diagnosis.
	/// How many rows a report prints before counting the rest.
	private static let reportRows = 8

	func reportForTesting() -> String {
		var said = ["gh=\(cliVersion ?? "not installed")"]
		said.append("scope=\(scope.rawValue)")
		if let trouble { said.append("trouble=\(trouble)") }
		said.append("rows=\(requests.count)")
		// **A cap, said out loud.** A repository with sixty open pull requests
		// prints sixty lines, and a report nobody reads to the end is a report
		// that hides what changed in it. Eight is enough to show the order and
		// the marks; the rest are counted rather than dropped silently.
		let shown = requests.prefix(Self.reportRows)
		said += shown.map { request in
			var parts = ["  #\(request.number)", request.title]
			parts.append("by \(request.author)")
			parts.append("on \(request.headRefName) → \(request.baseRefName)")
			if request.isDraft { parts.append("draft") }
			if !request.checks.summary.isEmpty { parts.append(request.checks.summary) }
			if request.isWaitingOnMe { parts.append("waiting on you") }
			return parts.joined(separator: " · ")
		}
		if requests.count > shown.count {
			said.append("  … and \(requests.count - shown.count) more not printed")
		}
		return said.joined(separator: "\n")
	}

	/// What the menu over a row offers, one item per line.
	///
	/// A list rather than a photograph of an open menu, for the reason the
	/// commit menu's report gives: a list diffs and a picture does not.
	func menuForTesting(row: Int) -> String {
		guard let menu = menu(forRow: row) else { return "no menu" }
		return menu.items.map { $0.isSeparatorItem ? "--" : $0.title }.joined(separator: "\n")
	}

	/// Opens one by number, for a driven run that knows which it wants.
	@discardableResult
	func openForTesting(number: Int) -> Bool {
		guard let request = requests.first(where: { $0.number == number }) else { return false }
		onOpen?(request)
		return true
	}

	/// Whether the answer has come back, so a driven run can wait for it.
	var hasAnsweredForTesting: Bool { activity == nil }

	func setScopeForTesting(_ scope: ReviewRequestScope) {
		let index = scope == .meOrMyTeams ? 1 : 0
		scopeControl.selectedIndex = index
		scopeChanged(to: index)
	}
}

// MARK: - The list

extension PullRequestsPane: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { requests.count }

	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		Theme.current.scaled(40)
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		guard requests.indices.contains(row) else { return nil }
		return PullRequestRowView(request: requests[row])
	}

	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		ThemedRowView()
	}
}

/// A table that opens the selected row on ↩.
private final class PullRequestTable: NSTableView {
	var onOpenSelection: (() -> Void)?
	/// What to offer over a row.
	var onMenu: ((Int) -> NSMenu?)?

	override func menu(for event: NSEvent) -> NSMenu? {
		let row = self.row(at: convert(event.locationInWindow, from: nil))
		guard row >= 0 else { return nil }
		return onMenu?(row)
	}

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.resignFirstResponder()
	}

	override func keyDown(with event: NSEvent) {
		// ↩ and ⌤, which is what opens a row everywhere else in this app.
		if event.keyCode == 36 || event.keyCode == 76 {
			onOpenSelection?()
			return
		}
		super.keyDown(with: event)
	}
}

/// One pull request: what it is, whose it is, and whether it is yours to read.
private final class PullRequestRowView: NSView {
	private let request: PullRequest
	override var isFlipped: Bool { true }

	init(request: PullRequest) {
		self.request = request
		super.init(frame: .zero)
		toolTip = [
			"#\(request.number) \(request.title)",
			"\(request.headRefName) → \(request.baseRefName)",
			request.url?.absoluteString,
		].compactMap { $0 }.joined(separator: "\n")
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let left = RowMetrics.textInset
		let right = bounds.maxX - RowMetrics.trailingInset

		// Two lines: what it is, and everything used to decide whether to open
		// it. Each drawn into a band of its own, so the row is laid out rather
		// than nudged.
		let upper = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.midY)
		let lower = NSRect(x: 0, y: bounds.midY, width: bounds.width, height: bounds.midY)

		// **The mark, in the glyph column every other list here uses.** Not a
		// colour on the title: a row that says "yours" by being a different
		// shade of the same text is a row somebody has to compare against its
		// neighbours to read, which is the scanning this is meant to save.
		if request.isWaitingOnMe {
			RowMetrics.glyph(
				"person.crop.circle.badge.checkmark",
				colour: Theme.current.gitAdded,
				in: bounds
			)
		}

		var limit = right
		if let checks = Self.checksGlyph(request.checks) {
			let size = Theme.current.scaled(13)
			checks.drawFitted(in: NSRect(
				x: right - size, y: upper.midY - size / 2, width: size, height: size
			))
			limit -= size + Theme.current.scaled(6)
		}

		let number = NSAttributedString(string: "#\(request.number)", attributes: [
			.font: Theme.current.monoFont(10.5, weight: .regular),
			.foregroundColor: Theme.current.gitIgnored,
		])
		number.draw(at: NSPoint(x: left, y: upper.midY - number.size().height / 2))

		RowMetrics.draw(
			request.title,
			font: Theme.current.uiFont(12, weight: request.isWaitingOnMe ? .medium : .regular),
			colour: Theme.current.sidebarText,
			at: left + number.size().width + Theme.current.scaled(6),
			in: upper,
			limit: limit
		)

		// Whose it is, which branch, and the draft badge.
		var under = [request.author, request.headRefName]
		if request.isDraft { under.append("draft") }
		RowMetrics.draw(
			under.joined(separator: " · "),
			font: Theme.current.uiFont(10.5),
			colour: Theme.current.gitIgnored,
			at: left,
			in: lower,
			limit: right
		)
	}

	/// The checks, as a glyph rather than a word.
	///
	/// Nothing at all when there is nothing to say: a repository with no checks
	/// configured and one whose checks have not started are indistinguishable
	/// from outside, and neither is a tick or a cross.
	private static func checksGlyph(_ state: ChecksState) -> NSImage? {
		switch state {
		case .passing: return Theme.symbol("checkmark.circle", size: 12, color: Theme.current.gitAdded)
		case .failing: return Theme.symbol("xmark.circle", size: 12, color: Theme.current.gitConflict)
		case .pending: return Theme.symbol("clock", size: 12, color: Theme.current.gitIgnored)
		case .none:    return nil
		}
	}
}
