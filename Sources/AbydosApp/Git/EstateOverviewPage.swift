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
		}
	}

	private var branches: [String: GitSubmoduleBranch] = [:]
	private var movements: [String: GitGitlinkMovement] = [:]

	private func reloadRows() {
		rows = GitEstateOverview.rows(
			in: submodules.estate,
			status: submodules.status,
			branches: branches,
			movements: movements
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
		summaryLabel.stringValue = hidden > 0
			? "\(GitEstateOverview.summary(of: rows)) — \(hidden) hidden by the filter"
			: GitEstateOverview.summary(of: rows)
		table.reloadData()
	}

	// MARK: - What a row says

	/// The three columns, as text. In the engine's terms rather than the view's,
	/// so a driven run can be asked the same question the eye is.
	static func columns(for row: GitEstateRow) -> (state: String, branch: String, moved: String) {
		let state: String
		switch row.state {
		case .conflicted:        state = "conflicted"
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
			return [row.path, said.state, said.branch, said.moved]
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
		("branch", "Branch", 220),
		("moved", "Against what the superproject records", 420),
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

	@objc private func openClicked() {
		guard table.clickedRow >= 0, table.clickedRow < shown.count else { return }
		onOpenSubmodule?(shown[table.clickedRow].path)
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
		return field
	}
}
