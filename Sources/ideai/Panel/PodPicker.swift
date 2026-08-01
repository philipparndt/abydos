import AppKit
import IdeaiKit

/// Choosing a pod to profile.
///
/// The list is what `kubectl get pods` would show, filtered by typing, with
/// the port each pod would be profiled on beside it — because the port is the
/// part that goes wrong, and seeing "6060, by convention" beforehand is worth
/// more than a failed connection afterwards.
@MainActor
final class PodPicker: NSObject {
	/// The pod chosen, and the context it lives in.
	var onChoose: ((PodTarget, String?) -> Void)?

	private var window: NSPanel?
	private var contextPopUp: NSPopUpButton!
	private var namespaceField: NSTextField!
	private var searchField: NSTextField!
	private var table: NSTableView!
	private var statusLabel: NSTextField!

	private var contexts: [String] = []
	private var pods: [PodTarget] = []
	private var shown: [PodTarget] = []

	func show(over parent: NSWindow?) {
		guard let parent else { return }
		guard Kubernetes.isAvailable else {
			Toast.post(
				"kubectl is not installed",
				detail: "The pod list comes from kubectl, which is not on the PATH."
			)
			return
		}

		let window = makeWindow()
		self.window = window

		let frame = parent.frame
		let size = NSSize(width: min(720, frame.width - 120), height: min(480, frame.height - 160))
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
		loadContexts()
	}

	private func close() {
		guard let window else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
		self.window = nil
	}

	// MARK: - Loading

	private func loadContexts() {
		setStatus("Reading contexts…")
		Task { @MainActor in
			contexts = await Kubernetes.contexts()
			let current = await Kubernetes.currentContext()

			contextPopUp.removeAllItems()
			contextPopUp.addItems(withTitles: contexts)
			if let current, let index = contexts.firstIndex(of: current) {
				contextPopUp.selectItem(at: index)
			}
			loadPods()
		}
	}

	private var selectedContext: String? {
		contexts.indices.contains(contextPopUp.indexOfSelectedItem)
			? contexts[contextPopUp.indexOfSelectedItem]
			: nil
	}

	@objc private func loadPods() {
		let context = selectedContext
		let namespace = namespaceField.stringValue.trimmingCharacters(in: .whitespaces)
		setStatus(namespace.isEmpty ? "Reading pods in every namespace…" : "Reading pods in \(namespace)…")

		Task { @MainActor in
			pods = await Kubernetes.pods(context: context, namespace: namespace.isEmpty ? nil : namespace)
			// Running pods first: the others cannot be profiled at all, and
			// they are worth showing only so nobody wonders where they went.
			pods.sort { ($0.isRunning ? 0 : 1, $0.namespace, $0.name) < ($1.isRunning ? 0 : 1, $1.namespace, $1.name) }
			filter()
			setStatus(pods.isEmpty ? "No pods, or the cluster is not reachable" : "\(pods.count) pods")
		}
	}

	private func filter() {
		let query = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
		shown = query.isEmpty
			? pods
			: pods.filter {
				$0.name.lowercased().contains(query) || $0.namespace.lowercased().contains(query)
			}
		table.reloadData()
		guard !shown.isEmpty else { return }
		table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
	}

	private func setStatus(_ text: String) {
		statusLabel.stringValue = text
	}

	// MARK: - Building

	private func makeWindow() -> NSPanel {
		contextPopUp = NSPopUpButton()
		contextPopUp.controlSize = .small
		contextPopUp.font = Theme.current.uiFont(11.5)
		contextPopUp.target = self
		contextPopUp.action = #selector(loadPods)

		namespaceField = NSTextField()
		namespaceField.placeholderString = "All namespaces"
		namespaceField.font = Theme.current.uiFont(12)
		namespaceField.textColor = Theme.current.sidebarText
		namespaceField.backgroundColor = Theme.current.editorBackground
		namespaceField.isBezeled = true
		namespaceField.bezelStyle = .roundedBezel
		namespaceField.focusRingType = .none
		namespaceField.target = self
		namespaceField.action = #selector(loadPods)

		searchField = NSTextField()
		searchField.placeholderString = "Filter by name"
		searchField.font = Theme.current.uiFont(12)
		searchField.textColor = Theme.current.sidebarText
		searchField.backgroundColor = Theme.current.editorBackground
		searchField.isBezeled = true
		searchField.bezelStyle = .roundedBezel
		searchField.focusRingType = .none
		searchField.delegate = self

		let header = NSStackView(views: [contextPopUp, namespaceField, searchField])
		header.orientation = .horizontal
		header.spacing = Theme.current.scaled(8)
		header.setHuggingPriority(.required, for: .vertical)
		// The filter takes what is left: the other two are as wide as what
		// they hold, and a namespace squeezed to a sliver cannot be typed in.
		contextPopUp.widthAnchor.constraint(equalToConstant: Theme.current.scaled(180)).isActive = true
		namespaceField.widthAnchor.constraint(equalToConstant: Theme.current.scaled(150)).isActive = true

		table = NSTableView()
		table.headerView = nil
		table.backgroundColor = Theme.current.sidebarBackground
		table.rowHeight = Theme.current.scaled(34)
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.style = .plain
		table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pod")))
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

		let profileButton = NSButton(title: "Profile", target: self, action: #selector(choose))
		profileButton.bezelStyle = .rounded
		profileButton.keyEquivalent = "\r"

		let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
		cancelButton.bezelStyle = .rounded
		cancelButton.keyEquivalent = "\u{1b}"

		let content = ColoredView(color: Theme.current.sidebarBackground)
		for view in [header, scroll, statusLabel, profileButton, cancelButton] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			content.addSubview(view)
		}

		NSLayoutConstraint.activate([
			header.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
			header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
			header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
			header.heightAnchor.constraint(equalToConstant: 24),

			scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
			scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: profileButton.topAnchor, constant: -12),

			statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
			statusLabel.centerYAnchor.constraint(equalTo: profileButton.centerYAnchor),

			profileButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
			profileButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
			cancelButton.trailingAnchor.constraint(equalTo: profileButton.leadingAnchor, constant: -8),
			cancelButton.centerYAnchor.constraint(equalTo: profileButton.centerYAnchor),
		])

		let window = PodPickerPanel(
			contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
			styleMask: [.titled, .closable, .resizable],
			backing: .buffered,
			defer: true
		)
		window.title = "Profile a Pod"
		window.backgroundColor = Theme.current.sidebarBackground
		window.contentView = content
		window.onCancel = { [weak self] in self?.cancel() }
		return window
	}

	// MARK: - Actions

	@objc private func choose() {
		let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
		guard shown.indices.contains(row) else { return }
		let pod = shown[row]
		let context = selectedContext
		close()
		onChoose?(pod, context)
	}

	@objc private func cancel() { close() }

	// MARK: - Testing

	var shownPodsForTesting: [String] { shown.map(\.id) }
	func filterForTesting(_ query: String) {
		searchField.stringValue = query
		filter()
	}

	func chooseFirstForTesting() {
		guard !shown.isEmpty else { return }
		table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		choose()
	}
}

extension PodPicker: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		guard shown.indices.contains(row) else { return nil }
		return PodRowView(pod: shown[row])
	}
}

extension PodPicker: NSTextFieldDelegate {
	func controlTextDidChange(_ notification: Notification) {
		guard notification.object as? NSTextField === searchField else { return }
		filter()
	}

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

private final class PodPickerPanel: NSPanel {
	var onCancel: (() -> Void)?
	override var canBecomeKey: Bool { true }

	override func close() { onCancel?() }
	override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// One pod: what it is called, where it lives, and where its pprof is.
private final class PodRowView: NSView {
	private let pod: PodTarget
	override var isFlipped: Bool { true }

	init(pod: PodTarget) {
		self.pod = pod
		super.init(frame: .zero)
		toolTip = pod.containers.isEmpty ? pod.id : pod.id + "\n" + pod.containers.joined(separator: ", ")
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let dim = !pod.isRunning
		let name = NSAttributedString(string: pod.name, attributes: [
			.font: Theme.current.uiFont(12.5, weight: .medium),
			.foregroundColor: dim ? Theme.current.gitIgnored : Theme.current.sidebarText,
		])
		name.draw(at: NSPoint(x: Theme.current.scaled(14), y: Theme.current.scaled(4)))

		let detail = "\(pod.namespace)  ·  \(pod.phase)\(pod.age.isEmpty ? "" : "  ·  \(pod.age)")"
		let subtitle = NSAttributedString(string: detail, attributes: [
			.font: Theme.current.uiFont(10.5),
			.foregroundColor: Theme.current.gitIgnored,
		])
		subtitle.draw(at: NSPoint(x: Theme.current.scaled(14), y: Theme.current.scaled(19)))

		// The port, and how sure we are of it: a guess is worth saying out
		// loud, because a forward to the wrong port looks like a broken tool.
		let explanation: String
		switch pod.portSource {
		case .annotation: explanation = "annotated"
		case .containerPort: explanation = "declared"
		case .convention: explanation = "by convention"
		}
		let port = NSAttributedString(string: ":\(pod.port)  \(explanation)", attributes: [
			.font: Theme.terminalFont(size: Theme.current.fontSize - 2),
			.foregroundColor: pod.portSource == .convention
				? Theme.current.gitIgnored
				: Theme.current.gitAdded,
		])
		port.draw(at: NSPoint(
			x: bounds.width - port.size().width - Theme.current.scaled(16),
			y: bounds.midY - port.size().height / 2
		))
	}
}
