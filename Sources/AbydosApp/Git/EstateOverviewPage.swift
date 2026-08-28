import AppKit
import AbydosKit

/// Every submodule in the estate, as one page: where the refactoring is.
///
/// **The question this exists to answer is "what is left".** A change across
/// forty microservices is forty branches and forty states, and the only thing
/// that has ever held them together is a spreadsheet somebody keeps by hand.
/// The refs tree shows one repository's branches and the commit page composes
/// one repository's commit; neither can be widened to three hundred rows
/// without becoming unreadable.
///
/// A page rather than a pane, for the reason the log and commit pages are:
/// three hundred rows want width, and a 300 pt column gives none.
///
/// **Rows are cheap and the table is virtualised**, because the house rule
/// about anything per row of a table applies literally here. Every row's text
/// is computed when its repository's answers land — in `GitEstateOverview.rows`,
/// which is in the engine and has no view in it — and `viewFor` only puts
/// strings into labels.
@MainActor
final class EstateOverviewPage: NSView {
	/// Opens one submodule's changes. Handed the submodule path.
	var onOpenSubmodule: ((String) -> Void)?

	private let root: URL
	private let submodules: EstateChanges

	/// The rows as last computed. Never recomputed while drawing.
	private var rows: [GitEstateRow] = []
	/// What the filter has left, which is what the table is over.
	private var shown: [GitEstateRow] = []
	private var filterText = ""

	private let summaryLabel = NSTextField(labelWithString: "")
	private let filterField = NSSearchField()
	private let table = NSTableView()
	private var activity: PaneActivityView?

	init(root: URL) {
		self.root = root
		self.submodules = EstateChanges(root: root)
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
		activity = PaneActivityView.install(over: self, message: "Reading the estate…")
		refresh()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: - Reading

	/// Reads the estate and fills the page in two passes.
	///
	/// **The rows exist before any status does.** The inventory is two git calls
	/// and 0.01 s over two hundred submodules, so every row can be on screen —
	/// named, and saying it has not been read — while the statuses are still
	/// arriving. A page that appears whole and then annotates itself is the
	/// difference between opening a project instantly and opening it in half a
	/// second.
	func refresh() {
		Task { @MainActor in
			let estate = await GitEstate.read(from: root)
			rows = GitEstateOverview.rows(in: estate, status: GitEstateStatus())
			reload()
			activity?.finish()
			activity = nil

			// Then the three answers that cost a process a repository, each
			// bounded by `GitEstateReader.concurrency` and each drawn as it
			// lands rather than after all of them have.
			_ = await submodules.refresh(.everything)
			reloadRows()

			let branches = await GitEstateBranches.branches(
				of: submodules.estate.submodules, in: root
			)
			self.branches = branches
			reloadRows()

			// Only of the submodules the superproject has already said moved:
			// two hundred clean repositories cost nothing here.
			let movements = await submodules.movements()
			self.movements = movements
			reloadRows()

			await readConflicts()
			await readPullRequests()
		}
	}

	/// The pull requests raised from the branch the superproject is on.
	///
	/// **Read from the forge every time and never stored.** A local record of
	/// numbers goes stale the moment somebody merges from the web, knows nothing
	/// on a second machine, and becomes a file to reconcile after every
	/// refactoring. The branch is the key and the forge is the record.
	///
	/// Asked last, because it is the only part of this page that needs a
	/// network: everything above it is already on screen by the time this
	/// starts, and a page that waited for a forge to draw a changed file would
	/// be a page nobody opened twice.
	private func readPullRequests() async {
		guard let branch = await GitRepository.head(in: root).name else { return }
		self.branchName = branch
		let entries = await GitEstatePullRequests.set(onBranch: branch, in: submodules.estate)
		pullRequests = Dictionary(
			entries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }
		)
		self.setSummary = GitEstatePullRequests.summary(of: entries)
		reload()
	}

	private var pullRequests: [String: PullRequestSetEntry] = [:]
	private var branchName: String?
	private var setSummary: String?

	/// What a row says about its pull request.
	static func pullRequestColumn(_ entry: PullRequestSetEntry?) -> String {
		guard let entry else { return "" }
		if let absence = entry.absence {
			// A phrase, not a sentence. `ForgeAbsence.summary` is written to be
			// read once, on an empty list where it is the only thing on screen;
			// two hundred rows each carrying "This repository has no GitHub
			// remote." is the same fact two hundred times. The count is in the
			// summary above, and the whole sentence is on the tooltip.
			switch absence {
			case .cliNotInstalled:  return "no gh"
			case .cliNotLoggedIn:   return "gh not logged in"
			case .noGitHubRemote:   return "no GitHub remote"
			}
		}
		guard let request = entry.request else { return "none raised" }

		let said: String
		switch entry.state {
		case .failing:          said = "checks failed"
		case .changesRequested: said = "changes requested"
		case .awaitingReview:   said = "awaiting review"
		case .approved:         said = "approved"
		case .merged:           said = "merged"
		case .draft:            said = "draft"
		case .none, .unavailable: said = ""
		}
		return "#\(request.number) · \(said)"
	}

	private var branches: [String: GitSubmoduleBranch] = [:]
	private var movements: [String: GitGitlinkMovement] = [:]
	private var conflicts: [String: GitGitlinkConflict] = [:]
	private var conflictDistances: [String: GitGitlinkMovement.Relation] = [:]

	/// The superproject's own conflicts about where its submodules point.
	///
	/// One `git ls-files -u` for the lot, and it is only asked at all when the
	/// superproject's status says something is unmerged: a repository that is
	/// not mid-merge — which is nearly always — pays nothing.
	private func readConflicts() async {
		guard submodules.status.superproject.hasConflicts else {
			guard !conflicts.isEmpty else { return }
			conflicts = [:]
			conflictDistances = [:]
			reloadRows()
			return
		}

		let found = await GitGitlinkConflicts.conflicts(in: root)
		conflicts = Dictionary(uniqueKeysWithValues: found.map { ($0.path, $0) })
		reloadRows()

		// The distance is a second call a conflict, and there are never many:
		// a merge that conflicted in two hundred submodules at once is not the
		// case this is sized for.
		var distances: [String: GitGitlinkMovement.Relation] = [:]
		for conflict in found {
			distances[conflict.path] = await GitGitlinkConflicts.distance(of: conflict, in: root)
		}
		conflictDistances = distances
		reloadRows()
	}

	private func reloadRows() {
		rows = GitEstateOverview.rows(
			in: submodules.estate,
			status: submodules.status,
			branches: branches,
			movements: movements,
			conflicts: conflicts,
			conflictDistances: conflictDistances
		)
		reload()
	}

	private func reload() {
		let needle = filterText.lowercased()
		shown = needle.isEmpty
			? rows
			: rows.filter { $0.path.lowercased().contains(needle) }

		// The count of what a filter hid, said rather than left to be guessed.
		let hidden = rows.count - shown.count
		var said = GitEstateOverview.summary(of: rows)
		// The set's own sentence beside the estate's, because they answer
		// different halves of "what is left": one is about the code and the
		// other about who has looked at it.
		if let setSummary, let branchName {
			said += "   ·   \(branchName): \(setSummary)"
		}
		if hidden > 0 { said += " — \(hidden) hidden by the filter" }
		summaryLabel.stringValue = said
		table.reloadData()
	}

	// MARK: - What a row says

	/// The three columns, as text. In the engine's terms rather than the view's,
	/// so a driven run can be asked the same question the eye is.
	static func columns(for row: GitEstateRow) -> (state: String, branch: String, moved: String) {
		let state: String
		switch row.state {
		case .conflicted:
			// Which conflict it is, because the two need different people.
			state = row.conflict != nil ? "gitlink conflict" : "conflicted"
		case .changed(let count): state = "\(count) changed"
		case .ahead(let count):  state = "\(count) to push"
		case .moved:             state = "moved"
		case .clean:             state = "clean"
		case .unread:            state = "reading…"
		case .absent:            state = "not checked out"
		}

		var branch = ""
		if let carried = row.branch {
			branch = carried.isDetached ? "detached" : (carried.branch ?? "")
			if carried.behind > 0 { branch += " · \(carried.behind) behind" }
			if carried.ahead > 0 { branch += " · \(carried.ahead) ahead" }
		}

		// A gitlink conflict is two commits, and the row says what is between
		// them: "conflicted" alone leaves somebody to run `git log` by hand
		// before they can choose a side.
		if row.conflict != nil {
			let between: String
			switch row.conflictDistance {
			case .diverged(let ahead, let behind)?:
				between = "theirs \(ahead) on, ours \(behind) on, from a shared commit"
			case .ahead(let count)?:  between = "theirs is \(count) past ours"
			case .behind(let count)?: between = "ours is \(count) past theirs"
			case .notHere?:           between = "the two sides share no history this copy has"
			case .level?, nil:        between = "both sides moved it"
			}
			return (state, branch, between)
		}

		// Commits, never lines. A gitlink's whole content is one object name, so
		// `+1 −1` for a service that advanced by forty commits is a true number
		// that says nothing.
		var moved = ""
		switch row.movement?.relation {
		case .ahead(let count)?:  moved = "\(count) ahead of what is recorded"
		case .behind(let count)?: moved = "\(count) behind what is recorded"
		case .diverged(let a, let b)?: moved = "diverged, \(a) and \(b)"
		case .notHere?:           moved = "recorded at a commit this copy has not got"
		case .level?, nil:        moved = ""
		}
		if let subject = row.movement?.subject, !moved.isEmpty, row.movement?.relation != .notHere {
			moved += " — \(subject)"
		}
		return (state, branch, moved)
	}

	private func colour(forPullRequest entry: PullRequestSetEntry) -> NSColor {
		switch entry.state {
		case .failing, .changesRequested: return Theme.current.gitConflict
		case .awaitingReview:             return Theme.current.gitModified
		case .approved, .merged:          return Theme.current.gitAdded
		default:                          return Theme.current.gitIgnored
		}
	}

	private func colour(for row: GitEstateRow) -> NSColor {
		switch row.state {
		case .conflicted: return Theme.current.gitConflict
		case .changed:    return Theme.current.gitModified
		case .ahead, .moved: return Theme.current.gitAdded
		case .absent:     return Theme.current.gitIgnored
		case .unread, .clean: return Theme.current.editorText.withAlphaComponent(0.55)
		}
	}

	// MARK: - Driven

	/// Every row, as the page says it. See `--estate`.
	func rowsForTesting() -> String {
		let head = ["summary: \(summaryLabel.stringValue)"]
		return (head + shown.map { row in
			let said = Self.columns(for: row)
			return [
				row.path, said.state, said.branch,
				Self.pullRequestColumn(pullRequests[row.path]), said.moved,
			]
				.filter { !$0.isEmpty }
				.joined(separator: " · ")
		}).joined(separator: "\n")
	}

	func filterForTesting(_ text: String) {
		filterField.stringValue = text
		filterText = text
		reload()
	}

	// MARK: - Chrome

	private static let columnLayout: [(id: String, title: String, width: CGFloat)] = [
		("repository", "Repository", 260),
		("state", "State", 130),
		("branch", "Branch", 200),
		("pr", "Pull request", 200),
		("moved", "Against what the superproject records", 380),
	]

	private func build() {
		// Said before the first read rather than left blank. An empty sentence
		// where a count belongs reads as "nothing to report", which is the one
		// thing a page that has not looked yet must never say.
		summaryLabel.stringValue = "reading the estate…"
		summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
		summaryLabel.textColor = Theme.current.editorText
		summaryLabel.translatesAutoresizingMaskIntoConstraints = false

		filterField.placeholderString = "Filter by name"
		filterField.target = self
		filterField.action = #selector(filterChanged)
		filterField.translatesAutoresizingMaskIntoConstraints = false

		for column in Self.columnLayout {
			let made = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
			made.title = column.title
			made.width = column.width
			table.addTableColumn(made)
		}
		table.delegate = self
		table.dataSource = self
		table.backgroundColor = Theme.current.editorBackground
		table.rowHeight = 22
		table.headerView = NSTableHeaderView()
		table.target = self
		table.doubleAction = #selector(openClicked)
		table.style = .inset
		// Built when it opens rather than held: what a row offers depends on
		// whether that row is conflicted, and the rows are rebuilt three times
		// while the answers arrive.
		let contextMenu = NSMenu()
		contextMenu.delegate = self
		table.menu = contextMenu

		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.editorBackground
		scroll.translatesAutoresizingMaskIntoConstraints = false

		addSubview(summaryLabel)
		addSubview(filterField)
		addSubview(scroll)

		NSLayoutConstraint.activate([
			summaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
			summaryLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),

			filterField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
			filterField.centerYAnchor.constraint(equalTo: summaryLabel.centerYAnchor),
			filterField.widthAnchor.constraint(equalToConstant: 220),
			filterField.leadingAnchor.constraint(
				greaterThanOrEqualTo: summaryLabel.trailingAnchor, constant: 12
			),

			scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
			scroll.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 10),
			scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	@objc private func filterChanged() { filterForTesting(filterField.stringValue) }

	// MARK: - Resolving a gitlink conflict

	/// The three ways out of a gitlink conflict, as a menu on the row.
	///
	/// **No merge tool opens one of these**, which is why they are here rather
	/// than left to the editor as a text conflict is. What is in conflict is
	/// which commit of another repository this one points at, so the resolution
	/// is a commit: take one side, take the other, or go and merge them inside
	/// the submodule and take what that leaves — which is what git's own hint
	/// tells you to do when it gives up on the merge.
	func menu(for row: GitEstateRow) -> NSMenu? {
		guard let conflict = row.conflict else { return nil }
		let menu = NSMenu()

		for side in conflict.sides {
			let item = menu.addItem(
				withTitle: "Take \(side.name) — \(String(side.commit.prefix(7)))",
				action: #selector(takeSide(_:)), keyEquivalent: ""
			)
			item.target = self
			item.representedObject = [conflict.path, side.commit]
		}

		if conflict.theirs != nil {
			menu.addItem(.separator())
			let item = menu.addItem(
				withTitle: "Merge Theirs Inside \(row.path)…",
				action: #selector(mergeInside(_:)), keyEquivalent: ""
			)
			item.target = self
			item.representedObject = conflict.path
		}
		return menu
	}

	@objc private func takeSide(_ sender: NSMenuItem) {
		guard let pair = sender.representedObject as? [String],
		      pair.count == 2,
		      let conflict = conflicts[pair[0]]
		else { return }
		resolve(conflict, to: pair[1])
	}

	/// Merges the other side inside the submodule and takes what that leaves.
	///
	/// The commit that results is neither side, and it is the resolution git's
	/// hint describes: "go to submodule, and either merge commit … or update to
	/// an existing commit which has merged those changes".
	@objc private func mergeInside(_ sender: NSMenuItem) {
		guard let path = sender.representedObject as? String,
		      let conflict = conflicts[path], let theirs = conflict.theirs
		else { return }

		Task { @MainActor in
			let submodule = root.appendingPathComponent(path)
			let merged = await GitRepository.run(
				["merge", "--no-edit", theirs], in: submodule
			)
			guard merged.exitCode == 0 else {
				Toast.post(
					"The merge inside \(path) stopped",
					detail: merged.stderr.isEmpty ? merged.stdout : merged.stderr,
					kind: .warning
				)
				// Left where it is on purpose: the submodule now has a text
				// conflict of its own, which is a thing to open in the editor
				// and not a thing to undo on somebody's behalf.
				refresh()
				return
			}
			let head = await GitRepository.run(["rev-parse", "HEAD"], in: submodule)
				.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !head.isEmpty else { return }
			resolve(conflict, to: head)
		}
	}

	private func resolve(_ conflict: GitGitlinkConflict, to commit: String) {
		Task { @MainActor in
			let result = await GitGitlinkConflicts.resolve(conflict, to: commit, in: root)
			if result.exitCode != 0 {
				Toast.post(
					"\(conflict.path) could not be resolved",
					detail: result.stderr.isEmpty ? result.stdout : result.stderr,
					kind: .warning
				)
			} else {
				Toast.post(
					"\(conflict.path) now points at \(String(commit.prefix(7)))",
					detail: "Staged in the superproject. Its work tree is at that commit."
				)
			}
			refresh()
		}
	}

	/// Resolves from a driven run, so the three ways out are checkable.
	func resolveForTesting(path: String, to side: String) {
		guard let conflict = conflicts[path] else {
			print("ESTATE: \(path) has no gitlink conflict")
			return
		}
		switch side {
		case "ours":   conflict.ours.map { resolve(conflict, to: $0) }
		case "theirs": conflict.theirs.map { resolve(conflict, to: $0) }
		default:       resolve(conflict, to: side)
		}
	}

	/// The row a context menu is about, which is the clicked one and not the
	/// selected one: right-clicking a row does not select it.
	private func rowUnderTheMenu() -> GitEstateRow? {
		let index = table.clickedRow
		guard index >= 0, index < shown.count else { return nil }
		return shown[index]
	}

	/// Opens one repository's pull request, when it has one.
	var onOpenPullRequest: ((Int, URL) -> Void)?

	@objc private func openClicked() {
		guard table.clickedRow >= 0, table.clickedRow < shown.count else { return }
		let row = shown[table.clickedRow]
		// A row with a pull request opens *that*, as the page `pull-requests`
		// defines — a set is read to review it, and a second way of opening the
		// same review would be two pages showing one thing.
		if let request = pullRequests[row.path]?.request {
			onOpenPullRequest?(request.number, root.appendingPathComponent(row.path))
			return
		}
		onOpenSubmodule?(row.path)
	}
}

extension EstateOverviewPage: NSMenuDelegate {
	/// The row under the pointer decides the menu: a conflicted row offers its
	/// ways out, and every other row offers nothing rather than a menu of
	/// items that would do nothing.
	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()
		guard let row = rowUnderTheMenu(), let built = self.menu(for: row) else { return }
		for item in built.items {
			built.removeItem(item)
			menu.addItem(item)
		}
	}
}

extension EstateOverviewPage: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

	func tableView(
		_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int
	) -> NSView? {
		guard index < shown.count, let tableColumn else { return nil }
		let row = shown[index]
		let said = Self.columns(for: row)

		// Nothing is computed here beyond picking which of four strings to show.
		// `viewFor` is asked once per visible row on every reload, and three
		// hundred rows reload three times while the answers arrive.
		let text: String
		var tint = Theme.current.editorText
		switch tableColumn.identifier.rawValue {
		case "repository": text = row.path
		case "state":      text = said.state; tint = colour(for: row)
		case "branch":     text = said.branch; tint = tint.withAlphaComponent(0.75)
		case "pr":
			let entry = pullRequests[row.path]
			text = Self.pullRequestColumn(entry)
			tint = entry.map(colour(forPullRequest:)) ?? tint.withAlphaComponent(0.75)
		default:           text = said.moved; tint = tint.withAlphaComponent(0.75)
		}

		let identifier = NSUserInterfaceItemIdentifier("cell")
		let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField)
			?? {
				let made = NSTextField(labelWithString: "")
				made.identifier = identifier
				made.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
				made.lineBreakMode = .byTruncatingTail
				return made
			}()
		field.stringValue = text
		field.textColor = tint
		// The sentence the phrase above stands in for, where there is one.
		field.toolTip = tableColumn.identifier.rawValue == "pr"
			? pullRequests[row.path]?.absence.map { $0.summary + " " + $0.remedy }
			: nil
		return field
	}
}
