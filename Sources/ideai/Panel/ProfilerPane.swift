import AppKit
import IdeaiKit

/// Profiling a running Go program.
///
/// Everything comes from the `net/http/pprof` endpoint the program is already
/// serving: nothing is installed into it, nothing is rebuilt, and it does not
/// have to be stopped. Say where it is, pick what to measure, and look at the
/// result — which is a flame graph for shape and a table for numbers, because
/// the two answer different questions.
final class ProfilerPane: NSView {
	/// Asked to open a source location, when a frame names one we can find.
	var onOpenFunction: ((String) -> Void)?

	private let client = PprofClient()
	private var endpoint: PprofEndpoint?
	/// The tunnel to a pod, while one is open.
	private var forward: PortForward?
	private var picker: PodPicker?
	private var kinds: [PprofEndpoint.Kind] = PprofEndpoint.standardKinds
	private var graph: FlameGraph?
	private var isBusy = false

	private var addressField: NSTextField!
	private var kindPopUp: NSPopUpButton!
	private var secondsField: NSTextField!
	private var collectButton: NSButton!
	private var statusLabel: NSTextField!
	private var focusButton: NSButton!
	private var podButton: NSButton!
	private var flameScroll: NSScrollView!
	private var flameView: FlameGraphView!
	private var table: NSTableView!
	private var split: NSSplitView!

	override var isFlipped: Bool { true }

	init(defaultAddress: String) {
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
		addressField.stringValue = defaultAddress
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: - Building

	private func build() {
		addressField = NSTextField()
		addressField.placeholderString = "localhost:6060"
		addressField.font = Theme.current.uiFont(12)
		addressField.textColor = Theme.current.sidebarText
		addressField.backgroundColor = Theme.current.sidebarBackground
		addressField.isBezeled = true
		addressField.bezelStyle = .roundedBezel
		addressField.focusRingType = .none
		addressField.target = self
		addressField.action = #selector(connectFromControl)
		addressField.toolTip = "A port, a host and port, or a URL"

		let connectButton = NSButton(title: "Connect", target: self, action: #selector(connectFromControl))
		connectButton.bezelStyle = .rounded
		connectButton.controlSize = .small

		// The same profiler, pointed through a tunnel: a pod in a cluster is
		// where the interesting profiles are, and it is one port-forward away.
		podButton = NSButton(title: "Pod\u{2026}", target: self, action: #selector(choosePod))
		podButton.bezelStyle = .rounded
		podButton.controlSize = .small
		podButton.toolTip = "Profile a pod in Kubernetes"
		podButton.isEnabled = Kubernetes.isAvailable

		kindPopUp = NSPopUpButton()
		kindPopUp.controlSize = .small
		kindPopUp.font = Theme.current.uiFont(11.5)
		kindPopUp.target = self
		kindPopUp.action = #selector(kindChanged)

		// Only meaningful for the profiles collected over a window, so it
		// appears and disappears with them rather than sitting there greyed.
		secondsField = NSTextField(string: "10")
		secondsField.font = Theme.current.uiFont(11.5)
		secondsField.alignment = .right
		secondsField.textColor = Theme.current.sidebarText
		secondsField.backgroundColor = Theme.current.sidebarBackground
		secondsField.isBezeled = true
		secondsField.bezelStyle = .roundedBezel
		secondsField.focusRingType = .none
		secondsField.toolTip = "Seconds to collect for"

		collectButton = NSButton(title: "Collect", target: self, action: #selector(collect))
		collectButton.bezelStyle = .rounded
		collectButton.controlSize = .small
		collectButton.keyEquivalent = "\r"

		statusLabel = NSTextField(labelWithString: "Not connected")
		statusLabel.font = Theme.current.uiFont(11)
		statusLabel.textColor = Theme.current.gitIgnored
		statusLabel.lineBreakMode = .byTruncatingTail

		focusButton = NSButton(title: "Whole profile", target: self, action: #selector(resetFocus))
		focusButton.bezelStyle = .rounded
		focusButton.controlSize = .small
		focusButton.isHidden = true

		let controls = NSStackView(views: [
			addressField, connectButton, podButton, kindPopUp, secondsField, collectButton,
			statusLabel, NSView(), focusButton,
		])
		controls.orientation = .horizontal
		controls.spacing = Theme.current.scaled(6)
		controls.edgeInsets = NSEdgeInsets(
			top: Theme.current.scaled(6), left: Theme.current.scaled(8),
			bottom: Theme.current.scaled(6), right: Theme.current.scaled(8)
		)
		// Without this the row takes the whole pane and the graph gets a
		// single point: a horizontal stack expands vertically unless told that
		// its own height is what it wants.
		controls.setHuggingPriority(.required, for: .vertical)
		controls.setContentCompressionResistancePriority(.required, for: .vertical)
		addressField.widthAnchor.constraint(equalToConstant: Theme.current.scaled(170)).isActive = true
		secondsField.widthAnchor.constraint(equalToConstant: Theme.current.scaled(44)).isActive = true

		flameView = FlameGraphView()
		flameView.onSelect = { [weak self] name in self?.select(function: name) }
		flameView.onFocusChanged = { [weak self] name in
			self?.focusButton.isHidden = name == nil
			guard let name else { return }
			self?.focusButton.title = "Leave \(name)"
		}

		flameScroll = NSScrollView()
		flameScroll.documentView = flameView
		flameScroll.hasVerticalScroller = true
		flameScroll.drawsBackground = true
		flameScroll.backgroundColor = Theme.current.editorBackground
		flameScroll.scrollerStyle = .overlay
		flameView.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			flameView.leadingAnchor.constraint(equalTo: flameScroll.contentView.leadingAnchor),
			flameView.trailingAnchor.constraint(equalTo: flameScroll.contentView.trailingAnchor),
			flameView.topAnchor.constraint(equalTo: flameScroll.contentView.topAnchor),
		])

		table = NSTableView()
		table.headerView = NSTableHeaderView()
		table.backgroundColor = Theme.current.editorBackground
		table.rowHeight = Theme.current.scaled(20)
		table.intercellSpacing = .zero
		table.gridStyleMask = []
		table.style = .plain
		for (identifier, title, width) in [
			("flat", "Self", 90.0), ("cum", "Total", 90.0), ("name", "Function", 460.0),
		] {
			let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
			column.title = title
			column.width = Theme.current.scaled(width)
			table.addTableColumn(column)
		}
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.doubleAction = #selector(rowActivated)

		let tableScroll = NSScrollView()
		tableScroll.documentView = table
		tableScroll.hasVerticalScroller = true
		tableScroll.drawsBackground = true
		tableScroll.backgroundColor = Theme.current.editorBackground
		tableScroll.scrollerStyle = .overlay

		// The graph above the numbers, and resizable between them: which half
		// matters depends on what you are chasing.
		let split = NSSplitView()
		self.split = split
		split.isVertical = false
		split.dividerStyle = .thin
		split.addArrangedSubview(flameScroll)
		split.addArrangedSubview(tableScroll)

		// A little over half to the graph, which is what is read first, and
		// weakly enough that dragging the divider still wins.
		let share = flameScroll.heightAnchor.constraint(
			equalTo: split.heightAnchor, multiplier: 0.55
		)
		share.priority = .defaultLow
		share.isActive = true

		// Constrained rather than stacked: a stack view hands the split view
		// only as much height as it asks for, and a split view asks for none.
		controls.translatesAutoresizingMaskIntoConstraints = false
		split.translatesAutoresizingMaskIntoConstraints = false
		addSubview(controls)
		addSubview(split)
		NSLayoutConstraint.activate([
			controls.topAnchor.constraint(equalTo: topAnchor),
			controls.leadingAnchor.constraint(equalTo: leadingAnchor),
			controls.trailingAnchor.constraint(equalTo: trailingAnchor),

			split.topAnchor.constraint(equalTo: controls.bottomAnchor),
			split.leadingAnchor.constraint(equalTo: leadingAnchor),
			split.trailingAnchor.constraint(equalTo: trailingAnchor),
			split.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		// Last, because filling the list decides whether the seconds field is
		// shown — and that field has to exist by then.
		showKinds(PprofEndpoint.standardKinds)
	}

	private func showKinds(_ kinds: [PprofEndpoint.Kind]) {
		self.kinds = kinds
		kindPopUp.removeAllItems()
		for kind in kinds {
			kindPopUp.addItem(withTitle: kind.name)
			kindPopUp.lastItem?.toolTip = kind.summary
		}
		kindChanged()
	}

	private var selectedKind: PprofEndpoint.Kind? {
		kinds.indices.contains(kindPopUp.indexOfSelectedItem)
			? kinds[kindPopUp.indexOfSelectedItem]
			: kinds.first
	}

	// MARK: - Actions

	@objc private func kindChanged() {
		secondsField.isHidden = selectedKind?.isTimed != true
	}

	@objc private func connectFromControl() { connectNow() }

	private func connectNow() {
		guard let endpoint = PprofEndpoint(text: addressField.stringValue) else {
			setStatus("That is not an address", failed: true)
			return
		}
		self.endpoint = endpoint
		setStatus("Connecting to \(endpoint.displayName)…")

		Task { @MainActor in
			do {
				let kinds = try await client.kinds(at: endpoint)
				showKinds(kinds)
				setStatus("\(endpoint.displayName) — \(kinds.count) profiles")
			} catch {
				setStatus(Self.describe(error), failed: true)
			}
		}
	}

	@objc private func collect() {
		guard let endpoint else {
			connectNow()
			return
		}
		guard let kind = selectedKind, !isBusy else { return }

		let seconds = kind.isTimed ? max(1, Int(secondsField.stringValue) ?? 10) : nil
		isBusy = true
		collectButton.isEnabled = false
		setStatus(seconds.map { "Collecting for \($0)s…" } ?? "Fetching \(kind.name)…")

		Task { @MainActor in
			defer {
				isBusy = false
				collectButton.isEnabled = true
			}
			do {
				let profile = try await client.profile(kind.name, from: endpoint, seconds: seconds)
				let graph = FlameGraph.build(from: profile)
				self.graph = graph
				flameView.show(graph)
				table.reloadData()

				let total = ProfileValue.format(graph.total, unit: graph.unit)
				setStatus("\(kind.name) — \(total) over \(graph.functions.count) functions")
			} catch {
				setStatus(Self.describe(error), failed: true)
			}
		}
	}

	/// Opens the pod list, and profiles whatever is chosen.
	@objc private func choosePod() {
		let picker = PodPicker()
		self.picker = picker
		picker.onChoose = { [weak self] pod, context in
			self?.picker = nil
			self?.profile(pod: pod, context: context)
		}
		picker.show(over: window)
	}

	/// Forwards a local port to the pod and points the profiler at it.
	private func profile(pod: PodTarget, context: String?) {
		forward?.stop()
		forward = nil
		setStatus("Forwarding to \(pod.name):\(pod.port)…")

		Task { @MainActor in
			do {
				let tunnel = try await PortForward.start(to: pod, context: context)
				forward = tunnel
				addressField.stringValue = "localhost:\(tunnel.localPort)"
				setStatus("\(pod.namespace)/\(pod.name) via :\(tunnel.localPort)")
				connectNow()
			} catch {
				setStatus(Self.describe(forwardFailure: error, pod: pod), failed: true)
			}
		}
	}

	private static func describe(forwardFailure error: any Error, pod: PodTarget) -> String {
		guard let failure = error as? PortForward.Failure else { return error.localizedDescription }
		switch failure {
		case .noKubectl:
			return "kubectl is not installed"
		case .noFreePort:
			return "No local port was free"
		case .timedOut:
			return "kubectl did not answer — is \(pod.name) running?"
		case let .failed(reason):
			// The port is the usual thing to be wrong, and the pod said
			// nothing about it, so say so here rather than in a log.
			let hint = pod.portSource == .convention
				? " (:\(pod.port) was a guess)"
				: ""
			return reason.isEmpty ? "The forward failed\(hint)" : reason + hint
		}
	}

	/// Closes the tunnel with the pane.
	func shutdown() {
		forward?.stop()
		forward = nil
	}

	@objc private func resetFocus() {
		flameView.resetFocus()
	}

	@objc private func rowActivated() {
		guard let graph, graph.functions.indices.contains(table.clickedRow) else { return }
		select(function: graph.functions[table.clickedRow].name)
	}

	private func select(function name: String) {
		onOpenFunction?(name)
		guard let index = graph?.functions.firstIndex(where: { $0.name == name }) else { return }
		table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
		table.scrollRowToVisible(index)
	}

	private func setStatus(_ text: String, failed: Bool = false) {
		statusLabel.stringValue = text
		statusLabel.textColor = failed ? .hex(0xD6706E) : Theme.current.gitIgnored
	}

	private static func describe(_ error: any Error) -> String {
		guard let failure = error as? PprofClient.Failure else { return error.localizedDescription }
		switch failure {
		case let .unreachable(reason): return reason
		case let .badStatus(code): return "The program answered \(code)"
		case .notAProfile: return "That endpoint did not return a profile"
		}
	}

	// MARK: - Testing

	/// Points the profiler at an address and connects, without waiting to be
	/// asked. Used when a run has just put something profilable somewhere.
	func connect(to address: String) {
		addressField.stringValue = address
		connectNow()
	}

	func connectForTesting(address: String) {
		connect(to: address)
	}

	func collectForTesting(kind: String, seconds: Int? = nil) {
		if let index = kinds.firstIndex(where: { $0.name == kind }) {
			kindPopUp.selectItem(at: index)
			kindChanged()
		}
		if let seconds { secondsField.stringValue = "\(seconds)" }
		collect()
	}

	var statusForTesting: String { statusLabel.stringValue }

	func showPodPickerForTesting(filter: String, choose: Bool = false, kind: String? = nil) {
		choosePod()
		guard !filter.isEmpty else { return }
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
			guard let self else { return }
			self.picker?.filterForTesting(filter)
			print("PODS: \(self.picker?.shownPodsForTesting.prefix(6) ?? [])")
			guard choose else { return }
			self.picker?.chooseFirstForTesting()

			// After the forward is up and the index page has answered.
			DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
				print("FORWARD: \(self.statusForTesting)")
				guard let kind else { return }
				self.collectForTesting(kind: kind, seconds: 3)
				DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
					print("CLUSTER PROFILE: \(self.statusForTesting) top=\(self.topFunctionsForTesting)")
				}
			}
		}
	}

	var topFunctionsForTesting: [String] { (graph?.functions.prefix(5).map(\.name)) ?? [] }
}

extension ProfilerPane: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { graph?.functions.count ?? 0 }

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		guard let graph, graph.functions.indices.contains(row), let column else { return nil }
		let function = graph.functions[row]

		let text: String
		let monospaced: Bool
		switch column.identifier.rawValue {
		case "flat":
			text = ProfileValue.format(function.flat, unit: graph.unit)
			monospaced = true
		case "cum":
			text = ProfileValue.format(function.cumulative, unit: graph.unit)
			monospaced = true
		default:
			text = function.name
			monospaced = false
		}

		let label = NSTextField(labelWithString: text)
		label.font = monospaced
			? Theme.terminalFont(size: Theme.current.fontSize - 2)
			: Theme.current.uiFont(11.5)
		label.textColor = Theme.current.sidebarText
		label.alignment = monospaced ? .right : .left
		label.lineBreakMode = .byTruncatingHead

		let cell = NSView()
		label.translatesAutoresizingMaskIntoConstraints = false
		cell.addSubview(label)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Theme.current.scaled(6)),
			label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Theme.current.scaled(6)),
			label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
		])
		return cell
	}
}
