import AbydosKit
import AppKit

/// Choosing one of the boards on the vboard server, to open it as it is.
///
/// A list you type into, as attaching to a process is: a team's server has
/// more boards than a menu holds, and the one somebody wants is found by name.
/// The server does the filtering (`VboardClient.boards`), asked again a moment
/// after the last key, so a large installation is never fetched whole.
@MainActor
final class VboardBoardPicker: NSObject {
	/// The board chosen, and the server it is on.
	var onChoose: ((VboardBoardSummary, URL) -> Void)?

	private let server: URL
	private var client: VboardClient?
	private let signIn = VboardSignInSheet()
	private var window: NSPanel?
	private var searchField: NSTextField!
	private var table: NSTableView!
	private var statusLabel: NSTextField!
	private var signInButton: NSButton!
	private var shown: [VboardBoardSummary] = []
	/// Which question the list on screen answers: an answer to an older one,
	/// arriving late, is dropped.
	private var asked = 0
	private var pendingQuery: DispatchWorkItem?

	init(server: URL) {
		self.server = server
	}

	/// The picker on screen, kept alive by being here until it closes.
	private static var showing: VboardBoardPicker?

	func show(over parent: NSWindow?) {
		guard let parent else { return }
		Self.showing?.close()
		Self.showing = self
		let window = makeWindow()
		self.window = window

		let frame = parent.frame
		let size = NSSize(width: min(620, frame.width - 120), height: min(460, frame.height - 160))
		window.setFrame(NSRect(
			x: frame.midX - size.width / 2,
			y: frame.midY - size.height / 2 + frame.height * 0.05,
			width: size.width,
			height: size.height
		), display: true)

		parent.addChildWindow(window, ordered: .above)
		if NSApp.isActive {
			window.makeKeyAndOrderFront(nil)
			window.makeFirstResponder(searchField)
		} else {
			window.orderFront(nil)
		}
		Task { await connect() }
	}

	private func close() {
		signIn.cancel()
		pendingQuery?.cancel()
		if Self.showing === self { Self.showing = nil }
		guard let window else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
		self.window = nil
	}

	// MARK: - Reaching the server

	/// Direct when the server needs nobody signed in, with the kept token when
	/// it does, and through the sign-in sheet when there is none — the order a
	/// board tab asks in.
	private func connect() async {
		setStatus("Connecting to \(host)…")
		let open = VboardClient(server: server)
		switch await open.signedIn() {
		case .done:
			ready(open)
		case .signedOut:
			if let kept = KeychainVboardCredentials.shared.credential(for: server) {
				let signed = VboardClient(server: server, token: kept.token)
				if await signed.signedIn() == .done {
					ready(signed)
					return
				}
				KeychainVboardCredentials.shared.forget(for: server)
			}
			setStatus("Sign in to \(host) to see its boards.", signIn: true)
		case .unreachable(let why):
			setStatus("\(host) cannot be reached: \(why)")
		case let outcome:
			setStatus("\(host) would not list its boards (\(outcome)).")
		}
	}

	@objc private func startSignIn() {
		let opened = signIn.start(server: server, over: window) { [weak self] ending in
			guard let self else { return }
			switch ending {
			case .signedIn(let credential): self.ready(VboardClient(server: self.server, token: credential.token))
			case .cancelled: self.setStatus("Sign-in was cancelled.", signIn: true)
			case .failed(let why): self.setStatus("Signing in did not work: \(why)", signIn: true)
			}
		}
		if !opened { setStatus("The sign-in window would not open.", signIn: true) }
	}

	private func ready(_ client: VboardClient) {
		self.client = client
		query(searchField.stringValue)
	}

	private var host: String { server.host ?? server.absoluteString }

	// MARK: - Asking

	private func query(_ text: String) {
		guard let client else { return }
		asked += 1
		let question = asked
		setStatus("Looking…")
		Task {
			let answer = await client.boards(matching: text.trimmingCharacters(in: .whitespaces))
			guard question == asked else { return }
			switch answer {
			case .success(let boards):
				shown = boards
				table.reloadData()
				if !boards.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
				setStatus(boards.isEmpty
					? (text.isEmpty ? "\(host) has no boards this account can open." : "No board is called that.")
					: "Opens the live board: what you change there, everybody sees.")
			case .failure(let failure) where failure.outcome == .signedOut:
				KeychainVboardCredentials.shared.forget(for: server)
				self.client = nil
				setStatus("Sign in to \(host) to see its boards.", signIn: true)
			case .failure(let failure):
				setStatus("\(host) would not list its boards (\(failure.outcome)).")
			}
		}
	}

	/// A moment after the last key, so typing a name is one question and not
	/// one per letter.
	private func queryAfterTyping() {
		pendingQuery?.cancel()
		let work = DispatchWorkItem { [weak self] in
			guard let self else { return }
			self.query(self.searchField.stringValue)
		}
		pendingQuery = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
	}

	private func setStatus(_ text: String, signIn: Bool = false) {
		statusLabel.stringValue = text
		signInButton.isHidden = !signIn
	}

	// MARK: - Building

	private func makeWindow() -> NSPanel {
		searchField = NSTextField()
		searchField.placeholderString = "Filter boards by name"
		searchField.font = Theme.current.uiFont(13)
		searchField.textColor = Theme.current.sidebarText
		searchField.backgroundColor = Theme.current.editorBackground
		searchField.drawsBackground = true
		searchField.isBezeled = true
		searchField.bezelStyle = .roundedBezel
		searchField.focusRingType = .none
		searchField.delegate = self

		table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.sidebarBackground
		table.rowHeight = Theme.current.scaled(30)
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.style = .plain
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("board")))
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.doubleAction = #selector(choose)

		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = true
		scroll.backgroundColor = Theme.current.sidebarBackground
		scroll.scrollerStyle = .overlay

		statusLabel = NSTextField(labelWithString: "")
		statusLabel.font = Theme.current.uiFont(10.5)
		statusLabel.textColor = Theme.current.gitIgnored
		statusLabel.lineBreakMode = .byTruncatingTail

		signInButton = NSButton(title: "Sign In", target: self, action: #selector(startSignIn))
		signInButton.bezelStyle = .rounded
		signInButton.isHidden = true

		let openButton = NSButton(title: "Open", target: self, action: #selector(choose))
		openButton.bezelStyle = .rounded
		openButton.keyEquivalent = "\r"

		let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
		cancelButton.bezelStyle = .rounded
		cancelButton.keyEquivalent = "\u{1b}"

		let content = ColoredView(color: Theme.current.sidebarBackground)
		for view in [searchField, scroll, statusLabel, signInButton, openButton, cancelButton] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			content.addSubview(view)
		}

		NSLayoutConstraint.activate([
			searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
			searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
			searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
			searchField.heightAnchor.constraint(equalToConstant: 24),

			scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
			scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: openButton.topAnchor, constant: -12),

			statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
			statusLabel.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),
			statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: signInButton.leadingAnchor, constant: -8),

			signInButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -8),
			signInButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),
			openButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
			openButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
			cancelButton.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -8),
			cancelButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),
		])

		let window = BoardPickerPanel(
			contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: true
		)
		window.title = "Open a Board on \(host)"
		window.backgroundColor = Theme.current.sidebarBackground
		window.contentView = content
		window.onCancel = { [weak self] in self?.cancel() }
		return window
	}

	// MARK: - Actions

	@objc private func choose() {
		let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
		guard shown.indices.contains(row) else { return }
		let chosen = shown[row]
		close()
		onChoose?(chosen, server)
	}

	@objc private func cancel() { close() }
}

extension VboardBoardPicker: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		guard shown.indices.contains(row) else { return nil }
		return BoardRowView(board: shown[row])
	}
}

extension VboardBoardPicker: NSTextFieldDelegate {
	func controlTextDidChange(_ notification: Notification) {
		queryAfterTyping()
	}

	/// Down out of the field moves into the list, so the keyboard alone can
	/// pick a board.
	func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
		switch selector {
		case #selector(NSResponder.moveDown(_:)):
			window?.makeFirstResponder(table)
			return true
		case #selector(NSResponder.insertNewline(_:)):
			choose()
			return true
		case #selector(NSResponder.cancelOperation(_:)):
			cancel()
			return true
		default:
			return false
		}
	}
}

/// Closes on escape, like every other dialog here.
private final class BoardPickerPanel: NSPanel {
	var onCancel: (() -> Void)?
	override var canBecomeKey: Bool { true }

	override func close() { onCancel?() }
	override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// One board: its name, and when anything on it last changed.
private final class BoardRowView: NSView {
	private let board: VboardBoardSummary
	override var isFlipped: Bool { true }

	init(board: VboardBoardSummary) {
		self.board = board
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		var nameWidth = bounds.width - Theme.current.scaled(28)
		if let updated = board.updated {
			let formatter = RelativeDateTimeFormatter()
			formatter.unitsStyle = .full
			let when = NSAttributedString(string: formatter.localizedString(for: updated, relativeTo: Date()), attributes: [
				.font: Theme.current.uiFont(10.5),
				.foregroundColor: Theme.current.gitIgnored,
			])
			let size = when.size()
			when.draw(at: NSPoint(x: bounds.width - Theme.current.scaled(14) - size.width, y: bounds.midY - size.height / 2))
			nameWidth -= size.width + Theme.current.scaled(12)
		}
		let name = NSAttributedString(string: board.name, attributes: [
			.font: Theme.current.uiFont(12.5, weight: .medium),
			.foregroundColor: Theme.current.sidebarText,
		])
		let height = name.size().height
		name.draw(with: NSRect(
			x: Theme.current.scaled(14),
			y: bounds.midY - height / 2,
			width: max(0, nameWidth),
			height: height
		), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
	}
}
