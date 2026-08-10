import AppKit
import AbydosKit

/// The list of what this app has started and has not ended.
///
/// **A window of its own, and not a settings page or a panel tab.** All three
/// shapes exist in this app and each was weighed. A settings page is where
/// somebody chooses a value: its rows are declarative `get`/`set` pairs, nothing
/// in it refreshes, and nobody opens Settings because the fan came on. A panel
/// tab beside the terminal is where live things live — but the panel belongs to
/// a window and a window belongs to a project, and what is listed here belongs
/// to the *application*: `ToolProcesses`, `ToolContainers` and `LanguageService`
/// are one each for the whole app, and two project windows would have shown the
/// same nine servers twice with two Stop buttons for each. A window of its own
/// is the shape that matches what is in it, it outlives the project window whose
/// servers it is listing, and it is the shape everybody already knows this job
/// by from Activity Monitor.
///
/// Found from View ▸ Running Servers and Containers, which the command palette
/// is generated from — so it is also one ⇧⌘P and the word "running", or
/// "servers", or "containers", away.
///
/// **It refreshes when somebody looks at it and not otherwise.** Opening it,
/// bringing it to the front, pressing Refresh, and stopping something are the
/// four moments. There is no timer: `docker stats` is about a second of a
/// runtime's attention, and a window that spent that every few seconds to show
/// what is wasting the machine would be a joke at the owner's expense.
@MainActor
final class RunningToolsWindowController: NSWindowController, NSWindowDelegate {
	static let shared = RunningToolsWindowController()

	private var rows: [RunningTools.Row] = []
	private var table: NSTableView!
	private var summary: NSTextField!
	private var refreshButton: NSButton!
	/// Set while a measurement is out, so pressing Refresh twice does not send
	/// two `docker stats` at a daemon that may be the reason somebody is here.
	private var isMeasuring = false
	/// Who is waiting to be told the list is current.
	private var waiting: [@MainActor @Sendable () -> Void] = []
	/// Whether somebody asked for a refresh while one was already out.
	///
	/// The distinction is the whole of what makes `refresh(then:)` mean
	/// anything. A measurement that was already running started before the ask,
	/// so its numbers can be older than whatever the caller just did — pressing
	/// Stop and then being handed the list from before the Stop is exactly the
	/// wrong answer, and it is the answer this window gave until this flag
	/// existed. So an ask during a measurement runs another one after it, and
	/// nobody is told anything until a measurement that began after they asked
	/// has landed. One flag rather than a count: two asks during one measurement
	/// still only need one more.
	private var askedAgain = false

	private init() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = "Running Servers and Containers"
		window.backgroundColor = Theme.current.sidebarBackground
		window.isReleasedWhenClosed = false
		window.minSize = NSSize(width: 560, height: 220)
		super.init(window: window)
		window.contentView = build()
		window.delegate = self
		window.center()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func show() {
		showWindow(nil)
		window?.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		// Coming to the front has usually refreshed it already, by the line
		// below; this is for the time it was in front to begin with. Skipped
		// while one is out rather than queued behind it, because both are the
		// same ask and `docker stats` is a second of a runtime's attention.
		if !isMeasuring { refresh() }
	}

	/// Coming back to the window is somebody asking again.
	func windowDidBecomeKey(_ notification: Notification) { refresh() }

	// MARK: - Building

	private func build() -> NSView {
		summary = NSTextField(labelWithString: "")
		summary.font = Theme.current.uiFont(12.5)
		summary.textColor = Theme.current.sidebarText

		refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshPressed))
		refreshButton.bezelStyle = .rounded

		table = NSTableView()
		table.backgroundColor = Theme.current.sidebarBackground
		table.rowHeight = Theme.current.scaled(38)
		table.intercellSpacing = NSSize(width: 8, height: 0)
		table.gridStyleMask = []
		table.style = .plain
		table.usesAlternatingRowBackgroundColors = false
		table.allowsColumnSelection = false
		// Room a wider window brings is shared out rather than left at the right
		// edge, and the `maxWidth` below then decides who gets it.
		table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
		for (identifier, title, width) in Self.columns {
			let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
			column.title = title
			column.width = width
			column.minWidth = width / 2
			// A wider window goes to "For" and to nothing else. It is the column
			// with something to show for the room — a container's whole name is
			// forty characters — and the alternative is what this looked like
			// first: an empty half-window to the right of the Stop buttons.
			if identifier != "for" { column.maxWidth = width }
			table.addTableColumn(column)
		}
		table.dataSource = self
		table.delegate = self

		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.sidebarBackground

		// Why the number beside a row is bigger than the server: the sentence
		// 0427 was opened by not knowing.
		let footnote = NSTextField(labelWithString:
			"Memory is the process and everything under it — a language server's own is small "
				+ "and the compilers it starts are not. Stopping one is not for ever: a server "
				+ "starts again the next time a file needs it.")
		footnote.font = Theme.current.uiFont(10.5)
		footnote.textColor = Theme.current.gitIgnored
		footnote.lineBreakMode = .byWordWrapping
		footnote.maximumNumberOfLines = 2

		let content = ColoredView(color: Theme.current.sidebarBackground)
		for view in [summary, refreshButton, scroll, footnote] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			content.addSubview(view)
		}
		NSLayoutConstraint.activate([
			summary.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
			summary.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
			summary.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -12),

			refreshButton.centerYAnchor.constraint(equalTo: summary.centerYAnchor),
			refreshButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

			scroll.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 12),
			scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: footnote.topAnchor, constant: -10),

			footnote.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
			footnote.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
			footnote.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
		])
		return content
	}

	private static let columns: [(String, String, CGFloat)] = [
		("what", "What", 230),
		// Wide enough for a container's whole name, which is the handle
		// somebody needs if they do go and look with `docker` after all.
		("for", "For", 250),
		("up", "Up", 70),
		("memory", "Memory", 110),
		("stop", "", 70),
	]

	// MARK: - Refreshing

	@objc private func refreshPressed() { refresh() }

	/// Asks what is running, and then what it costs — the second half off the
	/// main thread, because it is a `ps` and a runtime command.
	func refresh(then finished: (@MainActor @Sendable () -> Void)? = nil) {
		if let finished { waiting.append(finished) }
		guard !isMeasuring else {
			askedAgain = true
			return
		}
		isMeasuring = true
		askedAgain = false
		refreshButton.isEnabled = false
		let descriptors = RunningTools.descriptors()
		Task.detached(priority: .userInitiated) {
			let measured = RunningTools.measure(descriptors)
			await MainActor.run { [weak self] in
				guard let self else { return }
				self.rows = measured
				self.isMeasuring = false
				self.refreshButton.isEnabled = true
				self.table.reloadData()
				self.updateSummary()
				// Somebody asked while this one was out, so what is on screen is
				// older than their ask. Measured again, and nobody is told until
				// that one lands.
				guard !self.askedAgain else {
					self.refresh()
					return
				}
				let waiting = self.waiting
				self.waiting = []
				for hand in waiting { hand() }
			}
		}
	}

	/// The headline, which is the number somebody came here for.
	private func updateSummary() {
		guard !rows.isEmpty else {
			summary.stringValue = "Nothing this app started is still running."
			return
		}
		let servers = rows.filter { row -> Bool in
			guard case .languageServer = row.handle else { return false }
			return true
		}
		let total: Int64 = rows.compactMap(\.residentBytes).reduce(0, +)
		var parts: [String] = []
		if !servers.isEmpty { parts.append(count(servers.count, "language server")) }
		let containers = rows.count - servers.count
		if containers > 0 { parts.append(count(containers, "container")) }
		summary.stringValue = parts.joined(separator: ", ")
			+ " — \(RunningTools.memory(total)) between them"
	}

	private func count(_ number: Int, _ noun: String) -> String {
		"\(number) \(noun)\(number == 1 ? "" : "s")"
	}

	// MARK: - Stopping

	@objc private func stopPressed(_ sender: NSButton) {
		guard rows.indices.contains(sender.tag) else { return }
		stop(rows[sender.tag])
	}

	private func stop(_ row: RunningTools.Row, then finished: (@MainActor @Sendable () -> Void)? = nil) {
		let handle = row.handle
		let title = row.title
		Task { @MainActor in
			let said = await RunningTools.stop(handle)
			Toast.post("\(title) stopped", detail: said, kind: .information)
			// Measured again rather than crossed off the list: a container that
			// would not go is a row that has to still be there.
			self.refresh(then: finished)
		}
	}

	// MARK: - Testing

	/// What the list says, one line per row.
	///
	/// The path is in it because a measurement of 0427 that leaves it out cannot
	/// answer the question the entry's second fault was about — which toolchain
	/// the server on screen is actually running from.
	var reportForTesting: String {
		guard !rows.isEmpty else { return "empty" }
		return rows.map {
			"\($0.title) | \($0.startedFor) | \(RunningTools.uptime($0.uptime)) | "
				+ "\(RunningTools.memory($0.residentBytes))"
				+ ($0.descendants > 0 ? " +\($0.descendants)" : "")
				+ ($0.from.isEmpty ? "" : " | \($0.from)")
		}.joined(separator: "\n")
	}

	/// The process the last `stopForTesting` was aimed at.
	///
	/// So that a measurement can ask the operating system whether the thing went,
	/// rather than asking this window — which reads the app's own register, and
	/// the register believing a server has gone is precisely what 0427 found was
	/// not the same as the server having gone.
	private(set) var stoppedPidForTesting: pid_t?

	/// Presses Stop on the first row whose title or subject contains this.
	func stopForTesting(matching text: String, then finished: @escaping @MainActor @Sendable () -> Void) {
		guard let row = rows.first(where: {
			$0.title.localizedCaseInsensitiveContains(text)
				|| $0.startedFor.localizedCaseInsensitiveContains(text)
		}) else {
			print("RUNNING: nothing matching \(text)")
			finished()
			return
		}
		stoppedPidForTesting = row.pid
		print("RUNNING: stopping \(row.title) (\(row.startedFor)) pid \(row.pid.map(String.init) ?? "none")")
		stop(row, then: finished)
	}
}

extension RunningToolsWindowController: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row index: Int) -> NSView? {
		guard rows.indices.contains(index), let column else { return nil }
		let row = rows[index]

		switch column.identifier.rawValue {
		case "what":
			// Two lines: what it is, and the executable actually running. The
			// second is 0427's second fault made visible — the servers were
			// swiftly's while the build was Xcode's, and only the path says so.
			return stacked(row.title, under: row.from, tooltip: row.from)
		case "for":
			return stacked(row.startedFor, under: "", tooltip: row.startedFor)
		case "up":
			return number(RunningTools.uptime(row.uptime))
		case "memory":
			let text = RunningTools.memory(row.residentBytes)
			return number(row.descendants > 0 ? "\(text)  +\(row.descendants)" : text,
			              tooltip: row.descendants > 0
			                  ? "\(row.descendants) process(es) started by this one are in that number."
			                  : nil)
		default:
			let button = NSButton(title: "Stop", target: self, action: #selector(stopPressed(_:)))
			button.bezelStyle = .rounded
			button.controlSize = .small
			button.tag = index
			let holder = NSView()
			button.translatesAutoresizingMaskIntoConstraints = false
			holder.addSubview(button)
			NSLayoutConstraint.activate([
				button.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
				button.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
			])
			return holder
		}
	}

	private func stacked(_ title: String, under detail: String, tooltip: String?) -> NSView {
		let name = NSTextField(labelWithString: title)
		name.font = Theme.current.uiFont(12.5, weight: .medium)
		name.textColor = Theme.current.sidebarText
		name.lineBreakMode = .byTruncatingTail

		let holder = NSView()
		holder.toolTip = tooltip?.isEmpty == false ? tooltip : nil
		name.translatesAutoresizingMaskIntoConstraints = false
		holder.addSubview(name)

		guard !detail.isEmpty else {
			NSLayoutConstraint.activate([
				name.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
				name.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
				name.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
			])
			return holder
		}

		let path = NSTextField(labelWithString: detail)
		path.font = Theme.current.uiFont(10)
		path.textColor = Theme.current.gitIgnored
		// From the tail: what distinguishes one toolchain's `sourcekit-lsp`
		// from another's is the directory it is in, not the file name.
		path.lineBreakMode = .byTruncatingHead
		path.translatesAutoresizingMaskIntoConstraints = false
		holder.addSubview(path)

		NSLayoutConstraint.activate([
			name.topAnchor.constraint(equalTo: holder.topAnchor, constant: Theme.current.scaled(5)),
			name.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
			name.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
			path.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),
			path.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
			path.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
		])
		return holder
	}

	private func number(_ text: String, tooltip: String? = nil) -> NSView {
		let field = NSTextField(labelWithString: text)
		field.font = .monospacedDigitSystemFont(ofSize: Theme.current.scaled(11.5), weight: .regular)
		field.textColor = Theme.current.sidebarText
		field.alignment = .right
		let holder = NSView()
		holder.toolTip = tooltip
		field.translatesAutoresizingMaskIntoConstraints = false
		holder.addSubview(field)
		NSLayoutConstraint.activate([
			field.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
			field.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
			field.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
		])
		return holder
	}
}
