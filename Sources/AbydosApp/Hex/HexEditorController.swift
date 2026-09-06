import AbydosKit
import AppKit

/// A tab's worth of hex editor: the bar, the bytes, the minimap and the
/// inspector, and the tasks behind them.
///
/// Everything whole-file runs on a task this owns — the statistics pass, a
/// search, each checksum, the strings list, the structure parse, the ask to
/// Claude — and `close` cancels the lot. The views draw what has arrived;
/// nothing here computes on the main thread but the inspector's eight bytes.
@MainActor
final class HexEditorController {
	let url: URL
	let document: ByteDocument
	let view = NSStackView()
	let editor: HexEditorView
	let bar = HexBar()
	let minimap = HexMinimap()
	let inspector = HexInspectorPane()
	private let split = PreviewSplitView()
	private let scrollView = NSScrollView()
	private let fieldLabel = NSTextField(labelWithString: "")
	private let fieldStrip = NSView()

	/// The tab bar's dot and the status bar's text.
	var onDirtyChanged: (() -> Void)?
	var onStatusChanged: (() -> Void)?

	private(set) var statistics: ByteStatistics
	var statisticsTask: Task<Void, Never>?
	var searchTask: Task<Void, Never>?
	var checksumTasks: [Checksum: Task<Void, Never>] = [:]
	private var checksumScopes: [Checksum: Range<Int>?] = [:]
	var stringsTask: Task<Void, Never>?
	var structureTask: Task<Void, Never>?
	var askTask: Task<Void, Never>?
	private var refreshWork: DispatchWorkItem?

	private(set) var pattern: BytePattern?
	private(set) var matches: [Int] = []
	private(set) var searchCapped = false
	private(set) var structure: StructureNode?
	var claudeNodes: [StructureNode] = []
	var claudeSummary: String?
	var lastPrompt: String?
	private(set) var lastFailure: String?
	private(set) var strings = PrintableStrings.Listing(strings: [], unlisted: 0)
	private var stringsFilter = ""
	var order: ByteOrder = .little
	private(set) var isInspectorShown = true
	var checksumStates: [Checksum: HexInspectorPane.ChecksumState] = [:]
	private var promptWindow: NSWindow?

	init(url: URL) throws {
		self.url = url
		document = try ByteDocument(url: url)
		editor = HexEditorView(document: document)
		statistics = ByteStatistics(count: document.count)
		build()
		wire()
		startStatistics(indices: 0..<statistics.blocks.count)
		refreshDerived()
		refreshInspectorValues()
		inspector.structure.setAskAvailable(HexAnalysis.isAvailable)
	}

	// MARK: - Assembly

	private func build() {
		let theme = Theme.current
		scrollView.documentView = editor
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.drawsBackground = true
		scrollView.backgroundColor = theme.editorBackground
		scrollView.scrollerStyle = NSScroller.preferredScrollerStyle
		scrollView.contentView.postsBoundsChangedNotifications = true
		// Frames too: the viewport's first size arrives as a frame change, and
		// without it the minimap's rectangle stayed empty until the first scroll.
		scrollView.contentView.postsFrameChangedNotifications = true
		scrollView.translatesAutoresizingMaskIntoConstraints = false

		// The caret's field, as a strip of its own between the bar and the
		// bytes: over the bytes it covered the text column.
		fieldLabel.font = theme.uiFont(10)
		fieldLabel.textColor = theme.gitIgnored
		fieldLabel.lineBreakMode = .byTruncatingMiddle
		fieldLabel.translatesAutoresizingMaskIntoConstraints = false
		fieldStrip.wantsLayer = true
		fieldStrip.layer?.backgroundColor = theme.sidebarBackground.cgColor
		fieldStrip.translatesAutoresizingMaskIntoConstraints = false
		fieldStrip.addSubview(fieldLabel)
		fieldStrip.isHidden = true
		NSLayoutConstraint.activate([
			fieldStrip.heightAnchor.constraint(equalToConstant: theme.scaled(18)),
			fieldLabel.leadingAnchor.constraint(equalTo: fieldStrip.leadingAnchor, constant: theme.scaled(12)),
			fieldLabel.centerYAnchor.constraint(equalTo: fieldStrip.centerYAnchor),
			fieldLabel.trailingAnchor.constraint(lessThanOrEqualTo: fieldStrip.trailingAnchor, constant: -theme.scaled(12)),
		])

		let bytesArea = NSView()
		bytesArea.translatesAutoresizingMaskIntoConstraints = false
		minimap.translatesAutoresizingMaskIntoConstraints = false
		bytesArea.addSubview(scrollView)
		bytesArea.addSubview(minimap)
		NSLayoutConstraint.activate([
			scrollView.leadingAnchor.constraint(equalTo: bytesArea.leadingAnchor),
			scrollView.topAnchor.constraint(equalTo: bytesArea.topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bytesArea.bottomAnchor),
			scrollView.trailingAnchor.constraint(equalTo: minimap.leadingAnchor),
			minimap.topAnchor.constraint(equalTo: bytesArea.topAnchor),
			minimap.bottomAnchor.constraint(equalTo: bytesArea.bottomAnchor),
			minimap.trailingAnchor.constraint(equalTo: bytesArea.trailingAnchor),
		])

		split.isVertical = true
		split.dividerStyle = .thin
		split.addArrangedSubview(bytesArea)
		split.addArrangedSubview(inspector)
		split.wantedFraction = 0.68
		split.translatesAutoresizingMaskIntoConstraints = false
		inspector.widthAnchor.constraint(greaterThanOrEqualToConstant: theme.scaled(220)).isActive = true

		view.orientation = .vertical
		view.spacing = 0
		view.alignment = .leading
		view.addArrangedSubview(bar)
		view.addArrangedSubview(fieldStrip)
		view.addArrangedSubview(split)
		bar.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
		fieldStrip.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
		split.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
	}

	private func wire() {
		editor.onCaretChanged = { [weak self] _ in
			guard let self else { return }
			refreshInspectorValues()
			refreshFieldLabel()
			checksumScopeChanged()
			onStatusChanged?()
		}
		editor.onModeChanged = { [weak self] editor in
			self?.bar.setInsert(editor.insertMode)
			self?.onStatusChanged?()
		}
		document.onChange = { [weak self] range, delta in
			self?.documentChanged(range, delta: delta)
		}
		for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
			NotificationCenter.default.addObserver(
				forName: name, object: scrollView.contentView, queue: .main
			) { [weak self] _ in
				MainActor.assumeIsolated { self?.viewportChanged() }
			}
		}

		bar.onGoTo = { [weak self] text in self?.goTo(text) }
		bar.onFindChanged = { [weak self] query, kind in self?.search(query, kind: kind) }
		bar.onFindNext = { [weak self] in self?.stepMatch(by: 1) }
		bar.onFindPrevious = { [weak self] in self?.stepMatch(by: -1) }
		bar.onBytesPerRowChanged = { [weak self] count in
			self?.editor.bytesPerRow = count
			self?.viewportChanged()
		}
		bar.onEncodingChanged = { [weak self] encoding in
			self?.editor.encoding = encoding
			self?.refreshInspectorValues()
			self?.refreshStrings()
		}
		bar.onInsertToggled = { [weak self] in
			guard let self else { return }
			editor.setInsertMode(!editor.insertMode)
			bar.setInsert(editor.insertMode)
		}
		bar.onInspectorToggled = { [weak self] in self?.setInspectorShown(!(self?.isInspectorShown ?? true)) }
		bar.setInspectorShown(true)

		minimap.onScrollTo = { [weak self] offset in self?.editor.scroll(toShow: offset) }
		minimap.count = document.count

		inspector.onOrderChanged = { [weak self] order in
			self?.order = order
			self?.refreshInspectorValues()
		}
		inspector.onValueTyped = { [weak self] field, text in self?.write(text, as: field) }
		inspector.onChecksumPressed = { [weak self] kind in self?.toggleChecksum(kind) }
		inspector.onSelectRange = { [weak self] range in
			self?.editor.select(range)
			self?.editor.scroll(toShow: range.lowerBound)
		}
		inspector.onMinimapModeChanged = { [weak self] mode in self?.minimap.mode = mode }
		inspector.onStringsFilterChanged = { [weak self] text in
			self?.stringsFilter = text
			self?.showStrings()
		}
		inspector.structure.onSelectRange = { [weak self] range in
			self?.editor.select(range)
			self?.editor.scroll(toShow: range.lowerBound)
		}
		inspector.structure.onActivateRange = { [weak self] range in
			self?.editor.select(range)
			self?.editor.scroll(toShow: range.lowerBound)
			self?.focusEditor()
		}
		inspector.curve.onScrollTo = { [weak self] offset in self?.editor.scroll(toShow: offset) }
		inspector.structure.onAsk = { [weak self] in self?.toggleAsk() }
		inspector.structure.onShowPrompt = { [weak self] in self?.showPrompt() }
		inspector.setChecksumScope("over the whole file, \(ByteSize.said(Int64(document.count)))")
	}

	// MARK: - The document

	private func documentChanged(_ range: Range<Int>, delta: Int) {
		editor.documentChanged()
		minimap.count = document.count
		minimap.editedRanges = document.editedRanges
		onDirtyChanged?()
		onStatusChanged?()

		// The pass: the blocks the edit touched, or everything after it.
		if delta != 0 && statistics.count != document.count {
			statistics = ByteStatistics(count: document.count, blockSize: statistics.blockSize)
			startStatistics(indices: 0..<statistics.blocks.count)
		} else {
			let stale = statistics.invalidate(range, delta: delta)
			if !stale.isEmpty { startStatistics(indices: stale) }
		}

		for (kind, scope) in checksumScopes {
			if case .done(let digest)? = checksumStates[kind] {
				// A digest over a selection the edit did not touch still stands.
				if let scope, delta == 0, !scope.overlaps(range) { continue }
				checksumStates[kind] = .stale(digest)
				inspector.setChecksum(kind, .stale(digest))
			}
		}
		refreshInspectorValues()
		// The strings and the structure are re-read once typing pauses; a
		// re-parse per nibble would be a parse per keystroke.
		refreshWork?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.refreshDerived() }
		refreshWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
		if pattern != nil { search(bar.query, kind: bar.kind) }
	}

	// MARK: - The session

	/// What the session file keeps of this tab.
	var sessionState: ProjectSession.HexState {
		ProjectSession.HexState(
			caret: editor.caret,
			bytesPerRow: editor.bytesPerRow,
			encoding: editor.encoding.rawValue,
			order: order.rawValue,
			claudeSummary: claudeSummary,
			claudeFields: claudeNodes.map {
				ProjectSession.HexState.ClaudeField(name: $0.name, offset: $0.range.lowerBound, length: $0.range.count, meaning: $0.meaning)
			},
			claudePrompt: lastPrompt
		)
	}

	/// Puts a session's state back. The caret's scroll is deferred, because
	/// the view has no size until it is laid out and a scroll now would
	/// measure against nothing — the same reason a text tab defers its line.
	func restore(_ state: ProjectSession.HexState) {
		if [8, 16, 32].contains(state.bytesPerRow) {
			editor.bytesPerRow = state.bytesPerRow
			bar.setBytesPerRow(state.bytesPerRow)
		}
		if let encoding = ByteEncoding(rawValue: state.encoding) {
			editor.encoding = encoding
			bar.setEncoding(encoding)
		}
		if let order = ByteOrder(rawValue: state.order) {
			self.order = order
			inspector.setOrder(order)
		}
		claudeSummary = state.claudeSummary
		lastPrompt = state.claudePrompt
		claudeNodes = state.claudeFields.compactMap { field in
			guard field.offset >= 0, field.length >= 0, field.offset + field.length <= document.count else { return nil }
			return StructureNode(name: field.name, range: field.offset..<(field.offset + field.length), meaning: field.meaning, source: .claude)
		}
		showStructure()
		let caret = max(0, min(document.count, state.caret))
		editor.moveCaret(to: caret, extending: false)
		DispatchQueue.main.async { [weak self] in self?.editor.scroll(toShow: caret) }
		refreshInspectorValues()
	}

	func save() throws {
		try document.save()
		editor.documentChanged()
		minimap.editedRanges = []
		onDirtyChanged?()
	}

	var isDirty: Bool { document.isDirty }
	var statusText: String { editor.statusText }

	func focusFind() { bar.focusFind() }
	func focusOffset() { bar.focusOffset() }
	func focusEditor() { editor.window?.makeFirstResponder(editor) }

	/// Insert is turned off when the tab is left: a mode that is on without
	/// being looked at is how a gigabyte gets shifted by one byte.
	func tabWasLeft() {
		editor.setInsertMode(false)
		bar.setInsert(false)
	}

	func close() {
		statisticsTask?.cancel()
		searchTask?.cancel()
		for task in checksumTasks.values { task.cancel() }
		stringsTask?.cancel()
		structureTask?.cancel()
		askTask?.cancel()
		refreshWork?.cancel()
		NotificationCenter.default.removeObserver(self)
	}

	func setInspectorShown(_ shown: Bool) {
		isInspectorShown = shown
		inspector.isHidden = !shown
		bar.setInspectorShown(shown)
		split.adjustSubviews()
	}

	// MARK: - Going somewhere

	/// Hex with or without `0x`, decimal, or `+`/`-` from the caret. Says
	/// when the offset is past the end rather than clamping silently.
	func goTo(_ text: String) -> String? {
		var trimmed = text.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return nil }
		var relative = 0
		if trimmed.hasPrefix("+") { relative = 1; trimmed.removeFirst() }
		else if trimmed.hasPrefix("-") { relative = -1; trimmed.removeFirst() }
		let value: Int?
		if trimmed.lowercased().hasPrefix("0x") {
			value = Int(trimmed.dropFirst(2), radix: 16)
		} else if trimmed.lowercased().hasSuffix("h") {
			value = Int(trimmed.dropLast(), radix: 16)
		} else {
			value = Int(trimmed)
		}
		guard let value else { return "“\(text)” is not an offset" }
		let target = relative == 0 ? value : editor.caret + relative * value
		guard target >= 0, target <= document.count else {
			return "The file is \(document.count) bytes long (0x\(String(document.count, radix: 16, uppercase: true)))"
		}
		editor.moveCaret(to: target, extending: false)
		editor.scroll(toShow: target)
		focusEditor()
		return nil
	}

	// MARK: - Finding

	func search(_ query: String, kind: HexBar.FindKind) {
		searchTask?.cancel()
		searchTask = nil
		matches = []
		searchCapped = false
		editor.matches = []
		editor.currentMatch = nil
		minimap.matches = []
		bar.setProgress(nil)
		guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
			pattern = nil
			bar.clearStatusReservation()
			bar.setStatus("")
			return
		}
		let made: Result<BytePattern, BytePattern.Problem>
		switch kind {
		case .hex: made = BytePattern.hex(query)
		case .text: made = BytePattern.text(query, encoding: bar.encoding)
		case .number: made = BytePattern.number(query, width: bar.width, order: bar.order)
		}
		switch made {
		case .failure(let problem):
			pattern = nil
			bar.setStatus(problem.said, isComplaint: true)
		case .success(let found):
			pattern = found
			editor.matchLength = found.count
			let snapshot = document.snapshot()
			let caret = editor.caret
			bar.setStatus("searching…")
			searchTask = Task { [weak self] in
				var picked = false
				for await batch in ByteSearch.search(for: found, in: snapshot) {
					guard let self, !Task.isCancelled else { return }
					matches.append(contentsOf: batch.found)
					searchCapped = batch.capped
					editor.matches = matches
					minimap.matches = matches
					if !picked, let first = matches.first(where: { $0 >= caret }) ?? (batch.finished ? matches.first : nil) {
						picked = true
						editor.currentMatch = first
					}
					bar.setProgress(batch.finished ? nil : batch.fraction)
					reserveSearchStatus()
					bar.setStatus(searchStatus(finished: batch.finished, fraction: batch.fraction))
				}
			}
		}
	}

	private func searchStatus(finished: Bool, fraction: Double) -> String {
		let count = matches.count == 1 ? "1 match" : "\(matches.count) matches"
		if searchCapped { return "\(count), stopped at \(ByteSearch.maximumMatches)" }
		if !finished { return "\(count) · \(Int(fraction * 100))% searched" }
		if let current = editor.currentMatch, let index = matches.firstIndex(of: current) {
			return "\(index + 1) of \(count)"
		}
		return count
	}

	/// Keeps the bar's status column wide enough for every step of this
	/// search, so that walking the matches does not move the find field.
	///
	/// The widest it can say is the *last* index against the count — "128 of
	/// 128 matches" — which is known as soon as the count is, and long before
	/// anybody steps far enough to reach it.
	private func reserveSearchStatus() {
		guard !matches.isEmpty else {
			bar.clearStatusReservation()
			return
		}
		let count = matches.count == 1 ? "1 match" : "\(matches.count) matches"
		bar.reserveStatus(for: "\(matches.count) of \(count)")
	}

	func stepMatch(by delta: Int) {
		guard !matches.isEmpty else { return }
		let caret = editor.caret
		let next: Int
		if delta > 0 {
			next = matches.first(where: { $0 > caret || ($0 == caret && editor.selection == nil) }) ?? matches[0]
		} else {
			next = matches.last(where: { $0 < caret }) ?? matches[matches.count - 1]
		}
		editor.currentMatch = next
		editor.select(next..<(next + max(1, pattern?.count ?? 1)))
		editor.scroll(toShow: next)
		reserveSearchStatus()
		bar.setStatus(searchStatus(finished: true, fraction: 1))
	}

	// MARK: - The inspector

	func refreshInspectorValues() {
		let at = editor.selection?.lowerBound ?? editor.caret
		inspector.show(readings: ByteValues.readings(at: at, in: document.snapshot(), order: order, encoding: editor.encoding))
	}

	func write(_ text: String, as field: ByteValues.Field) -> String? {
		switch ByteValues.encode(text, as: field, order: order) {
		case .failure(let problem):
			return problem.said
		case .success(let data):
			let at = editor.selection?.lowerBound ?? editor.caret
			editor.undo.beginUndoGrouping()
			document.overwrite(data, at: at)
			editor.undo.endUndoGrouping()
			editor.moveCaret(to: at, extending: false)
			return nil
		}
	}

	private func refreshFieldLabel() {
		let at = editor.selection?.lowerBound ?? editor.caret
		let label = structure?.label(at: at)
		fieldLabel.stringValue = label ?? ""
		fieldStrip.isHidden = label == nil
		editor.highlightedField = structure?.path(at: at).last.flatMap { $0.range.isEmpty ? nil : $0.range }
	}

	var fieldLabelText: String? { fieldStrip.isHidden ? nil : fieldLabel.stringValue }

	// MARK: - Statistics

	private func startStatistics(indices: Range<Int>) {
		statisticsTask?.cancel()
		guard !indices.isEmpty else { return }
		let snapshot = document.snapshot()
		let blockSize = statistics.blockSize
		statisticsTask = Task { [weak self] in
			var pending: [ByteStatistics.Delivery] = []
			var lastShown = Date()
			for await delivery in ByteStatistics.pass(over: snapshot, blockSize: blockSize, indices: indices) {
				guard let self, !Task.isCancelled else { return }
				pending.append(delivery)
				// Shown in batches: the strip fills from the top over a second
				// or two, and four thousand redraws would be the cost otherwise.
				if pending.count >= 64 || Date().timeIntervalSince(lastShown) > 0.1 {
					for item in pending { statistics.set(item) }
					pending.removeAll(keepingCapacity: true)
					lastShown = Date()
					showStatistics()
				}
			}
			guard let self else { return }
			for item in pending { statistics.set(item) }
			showStatistics()
		}
	}

	private func showStatistics() {
		minimap.statistics = statistics
		inspector.show(statistics: statistics, visible: editor.visibleRange)
	}

	private func viewportChanged() {
		minimap.visibleRange = editor.visibleRange
		inspector.show(statistics: statistics, visible: editor.visibleRange)
	}

	// MARK: - Checksums

	private func checksumScopeChanged() {
		if let selection = editor.selection {
			inspector.setChecksumScope("over the selection, \(selection.count) bytes")
		} else {
			inspector.setChecksumScope("over the whole file, \(ByteSize.said(Int64(document.count)))")
		}
	}

	var checksumScopeText: String {
		editor.selection.map { "selection, \($0.count) bytes" } ?? "whole file"
	}

	func toggleChecksum(_ kind: Checksum) {
		if let running = checksumTasks[kind] {
			running.cancel()
			checksumTasks[kind] = nil
			checksumStates[kind] = .idle
			inspector.setChecksum(kind, .idle)
			return
		}
		let scope = editor.selection
		let snapshot = document.snapshot()
		checksumScopes[kind] = scope
		checksumStates[kind] = .running(0)
		inspector.setChecksum(kind, .running(0))
		checksumTasks[kind] = Task { [weak self] in
			for await progress in Checksums.stream(kind, over: snapshot, range: scope) {
				guard let self, !Task.isCancelled else { return }
				if let result = progress.result {
					checksumStates[kind] = .done(result)
					inspector.setChecksum(kind, .done(result))
				} else {
					inspector.setChecksum(kind, .running(progress.fraction))
				}
			}
			self?.checksumTasks[kind] = nil
		}
	}

	// MARK: - Strings and structure

	private func refreshDerived() {
		refreshStrings()
		refreshStructure()
	}

	private func refreshStrings() {
		stringsTask?.cancel()
		let snapshot = document.snapshot()
		let encoding = editor.encoding
		// The list is made on a detached task and applied on this actor once
		// it is back, so nothing here hops threads with `self` in hand.
		stringsTask = Task { [weak self] in
			let listing = await Task.detached(priority: .utility) {
				PrintableStrings.list(in: snapshot, encoding: encoding)
			}.value
			guard let self, !Task.isCancelled else { return }
			strings = listing
			showStrings()
		}
	}

	private func showStrings() {
		let needle = stringsFilter.lowercased()
		let shown = needle.isEmpty ? strings.strings : strings.strings.filter { $0.text.lowercased().contains(needle) }
		inspector.show(strings: Array(shown.prefix(2000)), total: strings.strings.count, unlisted: strings.unlisted)
	}

	private func refreshStructure() {
		structureTask?.cancel()
		let snapshot = document.snapshot()
		let ext = url.pathExtension
		structureTask = Task { [weak self] in
			let tree = await Task.detached(priority: .userInitiated) {
				BinaryFormats.explain(snapshot, extension: ext)
			}.value
			guard let self, !Task.isCancelled else { return }
			structure = tree
			showStructure()
			refreshFieldLabel()
		}
	}

	private func showStructure() {
		inspector.structure.show(parsed: structure, claude: claudeNodes, claudeSummary: claudeSummary)
	}

	// MARK: - Claude

	func toggleAsk() {
		if let running = askTask {
			running.cancel()
			askTask = nil
			inspector.structure.setAsking(false, selection: editor.selection != nil)
			return
		}
		guard HexAnalysis.isAvailable else { return }
		let snapshot = document.snapshot()
		let selection = editor.selection
		let name = url.lastPathComponent
		let root = url.deletingLastPathComponent()
		let table = statistics
		let listing = strings
		let tree = structure
		let count = document.count
		inspector.structure.setAsking(true, selection: selection != nil)
		lastFailure = nil
		askTask = Task { [weak self] in
			let ask = await Task.detached(priority: .userInitiated) {
				HexAnalysis.ask(snapshot, fileName: name, selection: selection, statistics: table, strings: listing, structure: tree)
			}.value
			guard !Task.isCancelled else { return }
			let result = await HexAnalysis.analyse(ask, count: count, in: root)
			guard let self, !Task.isCancelled else { return }
			askTask = nil
			inspector.structure.setAsking(false, selection: editor.selection != nil)
			switch result {
			case .success(let answer):
				claudeNodes = answer.nodes
				claudeSummary = answer.summary
				lastPrompt = answer.prompt
				showStructure()
			case .failure(let failure):
				lastFailure = failure.said
				lastPrompt = ask.prompt
				if failure != .cancelled { inspector.structure.showFailure(failure.said) }
			}
		}
	}

	/// The prompt, in a window of its own, because an answer about a sample
	/// should be judged knowing what the sample was.
	private func showPrompt() {
		guard let prompt = lastPrompt else { return }
		let scroll = NSTextView.scrollableTextView()
		guard let text = scroll.documentView as? NSTextView else { return }
		text.string = prompt
		text.isEditable = false
		text.font = Theme.current.monoFont(11)
		text.textColor = Theme.current.editorText
		text.backgroundColor = Theme.current.editorBackground
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
			styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
		)
		window.title = "What was asked about \(url.lastPathComponent)"
		window.contentView = scroll
		window.isReleasedWhenClosed = false
		window.center()
		window.makeKeyAndOrderFront(nil)
		promptWindow = window
	}
}
