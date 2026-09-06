import AbydosKit
import AppKit

/// The pane beside the bytes: what they are, what they hash to, how random
/// they are, what text they hold, and how the file is built.
///
/// In the tab and not in the sidebar, because the values follow the caret at
/// keystroke frequency and the outline highlights bytes in the very view
/// beside it. Every number here is computed by a kit type off the main
/// thread and only drawn here.
final class HexInspectorPane: NSView, ScaleFollowing {
	/// A value was typed into an editable field. Returns a complaint or nil.
	var onValueTyped: ((ByteValues.Field, String) -> String?)?
	var onOrderChanged: ((ByteOrder) -> Void)?
	var onChecksumPressed: ((Checksum) -> Void)?
	var onSelectRange: ((Range<Int>) -> Void)?
	var onMinimapModeChanged: ((HexMinimap.Mode) -> Void)?
	var onStringsFilterChanged: ((String) -> Void)?

	let structure = HexStructureOutline()

	private var valueFields: [ByteValues.Field: NSTextField] = [:]
	private var valueLengths: [ByteValues.Field: Int] = [:]
	private var orderControl: NSSegmentedControl!
	private var checksumRows: [Checksum: ChecksumRow] = [:]
	private var checksumScope: NSTextField!
	private var checksumResults: [Checksum: String] = [:]
	private let curve = EntropyCurveView()
	private var notesStack: NSStackView!
	private var stringsFilter: ScaledSearchField!
	private var stringsTable: NSTableView!
	private var stringsCount: NSTextField!
	private var strings: [PrintableStrings.Found] = []
	private var sections: NSStackView!
	private var minimapMode: NSSegmentedControl!
	private var bandLabels: [NSTextField] = []
	private var nameLabels: [NSTextField] = []
	private var valueGrids: [NSGridView] = []
	private var stacks: [(NSStackView, CGFloat)] = []
	private let heights = ScaledHeights()

	init() {
		super.init(frame: .zero)
		wantsLayer = true
		build()
		applyTheme()
		ScaledControls.register(self)
	}

	/// The fonts and the spacing again, as the zoom moves. The heights go
	/// through `ScaledHeights`; the rows the pane is made of — headings,
	/// value fields, checksum rows — follow on their own.
	func applyTheme() {
		let theme = Theme.current
		layer?.backgroundColor = theme.sidebarBackground.cgColor
		orderControl.font = theme.uiFont(10)
		minimapMode.font = theme.uiFont(10)
		for band in bandLabels { band.font = theme.uiFont(9, weight: .semibold) }
		for name in nameLabels { name.font = theme.uiFont(11) }
		for grid in valueGrids {
			grid.column(at: 0).width = theme.scaled(104)
			grid.columnSpacing = theme.scaled(8)
		}
		checksumScope.font = theme.uiFont(10)
		stringsCount.font = theme.uiFont(10)
		stringsTable.rowHeight = theme.scaled(17)
		stringsTable.reloadData()
		for (stack, design) in stacks { stack.spacing = theme.scaled(design) }
		sections.edgeInsets = NSEdgeInsets(top: theme.scaled(10), left: theme.scaled(10), bottom: theme.scaled(10), right: theme.scaled(10))
		for (index, view) in sections.arrangedSubviews.enumerated()
		where view is SectionHeading && index > 0 {
			sections.setCustomSpacing(theme.scaled(20), after: sections.arrangedSubviews[index - 1])
		}
		for view in notesStack.arrangedSubviews {
			(view as? NSButton)?.font = theme.uiFont(10)
			(view as? NSTextField)?.font = theme.uiFont(10)
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// A section's name with a rule running off it to the pane's edge.
	///
	/// Five headings in one scrolling column, each 10 pt and dim, were not
	/// boundaries — they read as more rows. The rule is what makes a heading
	/// the top of something rather than a line in the middle of it.
	private func heading(_ text: String) -> SectionHeading { SectionHeading(text) }

	private func build() {
		let theme = Theme.current
		sections = NSStackView(views: [
			heading("Structure"), structure,
			heading("Values"), buildValues(),
			heading("Checksums"), buildChecksums(),
			heading("Entropy"), buildEntropy(),
			heading("Strings"), buildStrings(),
		])
		sections.orientation = .vertical
		sections.alignment = .leading
		// A heading belongs to what is under it, so the air goes above it
		// rather than being shared evenly between every row in the column;
		// `applyTheme` sets both spacings, and again at every zoom.
		stacks.append((sections, 6))
		sections.translatesAutoresizingMaskIntoConstraints = false
		for view in sections.arrangedSubviews where !(view is NSTextField) {
			view.widthAnchor.constraint(equalTo: sections.widthAnchor, constant: -theme.scaled(20)).isActive = true
		}

		// In a flipped document, so the pane opens at its top: an unflipped
		// one starts scrolled to the bottom, which put SHA-512 first.
		let document = TopDownView()
		document.translatesAutoresizingMaskIntoConstraints = false
		document.addSubview(sections)
		let scroll = NSScrollView()
		scroll.documentView = document
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = false
		scroll.translatesAutoresizingMaskIntoConstraints = false
		addSubview(scroll)
		NSLayoutConstraint.activate([
			scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
			scroll.topAnchor.constraint(equalTo: topAnchor),
			scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
			document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
			sections.leadingAnchor.constraint(equalTo: document.leadingAnchor),
			sections.trailingAnchor.constraint(equalTo: document.trailingAnchor),
			sections.topAnchor.constraint(equalTo: document.topAnchor),
			sections.bottomAnchor.constraint(equalTo: document.bottomAnchor),
		])
	}

	// MARK: - Values

	private func buildValues() -> NSView {
		let theme = Theme.current
		orderControl = NSSegmentedControl(labels: ["Little-endian", "Big-endian"], trackingMode: .selectOne, target: self, action: #selector(orderPicked))
		orderControl.selectedSegment = 0

		let column = NSStackView(views: [orderControl])
		column.orientation = .vertical
		column.alignment = .leading
		stacks.append((column, 6))

		// One band at a time, so that the eye finds UInt32 by the shape of the
		// list rather than by reading every label down to it.
		for (group, fields) in ByteValues.Field.grouped {
			let band = NSTextField(labelWithString: group.name.uppercased())
			band.textColor = theme.gitIgnored
			bandLabels.append(band)

			let grid = NSGridView()
			grid.rowSpacing = theme.scaled(1)
			for field in fields {
				let name = NSTextField(labelWithString: field.name)
				name.textColor = theme.gitIgnored
				nameLabels.append(name)
				let value = ValueField(field: field)
				valueFields[field] = value
				grid.addRow(with: [name, value])
			}
			grid.column(at: 1).xPlacement = .fill
			valueGrids.append(grid)

			column.addArrangedSubview(band)
			column.addArrangedSubview(grid)
			column.setCustomSpacing(theme.scaled(10), after: column.arrangedSubviews[column.arrangedSubviews.count - 3])
			grid.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
		}
		return column
	}

	@objc private func orderPicked() {
		onOrderChanged?(orderControl.selectedSegment == 0 ? .little : .big)
	}

	@objc private func valueEntered(_ sender: NSTextField) {
		guard let field = valueFields.first(where: { $0.value === sender })?.key else { return }
		if let complaint = onValueTyped?(field, sender.stringValue) {
			sender.textColor = Theme.current.gitConflict
			sender.toolTip = complaint
			NSSound.beep()
		} else {
			sender.textColor = Theme.current.editorText
		}
	}

	func show(readings: [ByteValues.Reading]) {
		for reading in readings {
			guard let field = valueFields[reading.field] else { continue }
			// Not while somebody is typing into it.
			if window?.firstResponder === field.currentEditor() { continue }
			field.stringValue = reading.text ?? reading.unavailable
			field.textColor = reading.text == nil ? Theme.current.gitIgnored : Theme.current.editorText
			valueLengths[reading.field] = reading.length
		}
	}

	func setOrder(_ order: ByteOrder) {
		orderControl.selectedSegment = order == .little ? 0 : 1
	}

	var readingsForTesting: [String: String] {
		Dictionary(uniqueKeysWithValues: valueFields.map { ($0.key.name, $0.value.stringValue) })
	}

	// MARK: - Checksums

	private func buildChecksums() -> NSView {
		let theme = Theme.current
		checksumScope = NSTextField(labelWithString: "over the whole file")
		checksumScope.textColor = theme.gitIgnored

		let column = NSStackView(views: [checksumScope])
		column.orientation = .vertical
		column.alignment = .leading
		stacks.append((column, 1))
		column.setCustomSpacing(theme.scaled(6), after: checksumScope)

		// One row shape, whatever state the row is in. Four columns whose
		// contents came and went — a bezelled button, a bar, a digest, a copy
		// — meant nothing lined up down the pane, and a row that had computed
		// nothing still showed a bar at zero and a button that copied nothing.
		for kind in Checksum.allCases {
			let row = ChecksumRow(kind: kind, target: self, compute: #selector(checksumPressed(_:)), copy: #selector(copyChecksum(_:)))
			checksumRows[kind] = row
			column.addArrangedSubview(row)
			row.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
		}
		return column
	}

	@objc private func checksumPressed(_ sender: NSButton) {
		guard let raw = sender.identifier?.rawValue, let kind = Checksum(rawValue: raw) else { return }
		onChecksumPressed?(kind)
	}

	@objc private func copyChecksum(_ sender: NSButton) {
		guard let raw = sender.identifier?.rawValue, let kind = Checksum(rawValue: raw), let digest = checksumResults[kind] else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(digest, forType: .string)
	}

	enum ChecksumState: Equatable {
		case idle
		case running(Double)
		case done(String)
		case stale(String)
	}

	func setChecksumScope(_ text: String) { checksumScope.stringValue = text }

	func setChecksum(_ kind: Checksum, _ state: ChecksumState) {
		guard let row = checksumRows[kind] else { return }
		row.show(state)
		checksumResults[kind] = {
			if case let .done(digest) = state { return digest }
			return nil
		}()
	}

	var checksumsForTesting: [String: String] {
		Dictionary(uniqueKeysWithValues: checksumRows.map { ($0.key.name, $0.value.result.stringValue) })
	}

	// MARK: - Entropy

	private func buildEntropy() -> NSView {
		heights.height(curve, design: 64).isActive = true
		curve.toolTip = "Shannon entropy per block, 0 to 8 bits a byte; the band is what is on screen"
		let mode = NSSegmentedControl(labels: ["Minimap: kinds", "Minimap: entropy"], trackingMode: .selectOne, target: self, action: #selector(minimapModePicked(_:)))
		mode.selectedSegment = 0
		minimapMode = mode
		notesStack = NSStackView()
		notesStack.orientation = .vertical
		notesStack.alignment = .leading
		stacks.append((notesStack, 2))
		let stack = NSStackView(views: [curve, mode, notesStack])
		stack.orientation = .vertical
		stack.alignment = .leading
		stacks.append((stack, 6))
		curve.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		return stack
	}

	@objc private func minimapModePicked(_ sender: NSSegmentedControl) {
		onMinimapModeChanged?(sender.selectedSegment == 0 ? .classes : .entropy)
	}

	func show(statistics: ByteStatistics?, visible: Range<Int>) {
		curve.statistics = statistics
		curve.visibleRange = visible
		let notes = statistics?.notes ?? []
		let shown = notesStack.arrangedSubviews.compactMap { $0 as? NSButton }.map(\.title)
		let wanted = notes.prefix(8).map(\.said)
		guard shown != wanted else { return }
		for view in notesStack.arrangedSubviews { notesStack.removeArrangedSubview(view); view.removeFromSuperview() }
		for note in notes.prefix(8) {
			let button = NSButton(title: note.said, target: self, action: #selector(notePressed(_:)))
			button.bezelStyle = .inline
			button.font = Theme.current.uiFont(10)
			button.contentTintColor = Theme.current.gitConflict
			button.toolTip = "Select these bytes"
			button.identifier = .init("\(note.range.lowerBound):\(note.range.upperBound)")
			notesStack.addArrangedSubview(button)
		}
		if notes.count > 8 {
			let more = NSTextField(labelWithString: "\(notes.count - 8) more regions")
			more.font = Theme.current.uiFont(10)
			more.textColor = Theme.current.gitIgnored
			notesStack.addArrangedSubview(more)
		}
	}

	@objc private func notePressed(_ sender: NSButton) {
		let parts = sender.identifier?.rawValue.split(separator: ":").compactMap { Int($0) } ?? []
		guard parts.count == 2 else { return }
		onSelectRange?(parts[0]..<parts[1])
	}

	var notesForTesting: [String] {
		notesStack.arrangedSubviews.compactMap { ($0 as? NSButton)?.title }
	}

	// MARK: - Strings

	private func buildStrings() -> NSView {
		let theme = Theme.current
		stringsFilter = ScaledSearchField(placeholder: "Filter strings", fontSize: 11)
		stringsFilter.target = self
		stringsFilter.action = #selector(filterChanged)
		stringsFilter.sendsSearchStringImmediately = true
		stringsCount = NSTextField(labelWithString: "")
		stringsCount.textColor = theme.gitIgnored

		stringsTable = NSTableView()
		stringsTable.headerView = nil
		stringsTable.backgroundColor = .clear
		stringsTable.style = .plain
		let column = NSTableColumn(identifier: .init("string"))
		column.resizingMask = .autoresizingMask
		stringsTable.addTableColumn(column)
		stringsTable.dataSource = self
		stringsTable.delegate = self
		stringsTable.target = self
		stringsTable.action = #selector(stringClicked)
		let scroll = NSScrollView()
		scroll.documentView = stringsTable
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = false
		heights.height(scroll, design: 160).isActive = true

		let stack = NSStackView(views: [stringsFilter, scroll, stringsCount])
		stack.orientation = .vertical
		stack.alignment = .leading
		stacks.append((stack, 4))
		stringsFilter.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		return stack
	}

	@objc private func filterChanged() {
		onStringsFilterChanged?(stringsFilter.stringValue)
	}

	@objc private func stringClicked() {
		let row = stringsTable.clickedRow
		guard strings.indices.contains(row) else { return }
		onSelectRange?(strings[row].offset..<(strings[row].offset + strings[row].length))
	}

	func show(strings: [PrintableStrings.Found], total: Int, unlisted: Int) {
		self.strings = strings
		stringsTable.reloadData()
		var said = "\(strings.count) shown"
		if strings.count != total { said += " of \(total)" }
		if unlisted > 0 { said += ", \(unlisted) more not listed" }
		stringsCount.stringValue = said
	}

	var stringsFilterText: String { stringsFilter.stringValue }
	func setStringsFilter(_ text: String) { stringsFilter.stringValue = text; onStringsFilterChanged?(text) }
	var stringsForTesting: [String] { strings.prefix(20).map { String(format: "0x%llX: %@", $0.offset, $0.text) } }
}

extension HexInspectorPane: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { strings.count }

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let theme = Theme.current
		let found = strings[row]
		let line = NSMutableAttributedString(string: String(format: "%08X  ", found.offset), attributes: [.font: theme.monoFont(10), .foregroundColor: theme.gitIgnored])
		line.append(NSAttributedString(string: found.text, attributes: [.font: theme.monoFont(11), .foregroundColor: theme.editorText]))
		let cell = NSTextField(labelWithAttributedString: line)
		cell.lineBreakMode = .byTruncatingTail
		return cell
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		let row = stringsTable.selectedRow
		guard strings.indices.contains(row) else { return }
		onSelectRange?(strings[row].offset..<(strings[row].offset + strings[row].length))
	}
}

/// A document view whose origin is at the top, so a scroll view opens there.
final class TopDownView: NSView {
	override var isFlipped: Bool { true }
}

/// The entropy of the file as a curve, with the viewport marked.
final class EntropyCurveView: NSView {
	var statistics: ByteStatistics? { didSet { needsDisplay = true } }
	var visibleRange: Range<Int> = 0..<0 { didSet { needsDisplay = true } }

	override var isFlipped: Bool { true }

	override func draw(_ dirtyRect: NSRect) {
		let theme = Theme.current
		theme.editorBackground.setFill()
		bounds.fill()
		guard let statistics, !statistics.blocks.isEmpty, bounds.width > 2 else { return }

		// The threshold line, so a curve near it reads against it.
		let thresholdY = bounds.height * (1 - CGFloat(ByteStatistics.highEntropy / 8))
		theme.gitConflict.withAlphaComponent(0.35).setStroke()
		let threshold = NSBezierPath()
		threshold.move(to: NSPoint(x: 0, y: thresholdY))
		threshold.line(to: NSPoint(x: bounds.width, y: thresholdY))
		threshold.lineWidth = 1
		threshold.stroke()

		if statistics.count > 0 {
			let x0 = CGFloat(visibleRange.lowerBound) / CGFloat(statistics.count) * bounds.width
			let x1 = max(x0 + 2, CGFloat(visibleRange.upperBound) / CGFloat(statistics.count) * bounds.width)
			theme.selection(.text, hasKeyboard: true).withAlphaComponent(0.3).setFill()
			NSRect(x: x0, y: 0, width: x1 - x0, height: bounds.height).fill()
		}

		// One point a pixel column, from the blocks that column covers.
		let columns = Int(bounds.width)
		let blocks = statistics.blocks
		let path = NSBezierPath()
		var started = false
		for column in 0..<columns {
			let first = column * blocks.count / columns
			let last = max(first + 1, (column + 1) * blocks.count / columns)
			var sum = 0.0, measured = 0
			for index in first..<min(blocks.count, last) {
				guard let block = blocks[index] else { continue }
				sum += block.entropy; measured += 1
			}
			guard measured > 0 else { started = false; continue }
			let point = NSPoint(x: CGFloat(column), y: bounds.height * (1 - CGFloat(sum / Double(measured) / 8)))
			if started { path.line(to: point) } else { path.move(to: point); started = true }
		}
		theme.gitAdded.setStroke()
		path.lineWidth = 1
		path.stroke()
	}
}


/// A section's name, with a rule running off it to the pane's edge.
private final class SectionHeading: NSView, ScaleFollowing {
	private let label = NSTextField(labelWithString: "")
	private let rule = NSView()
	private let stack: NSStackView

	init(_ text: String) {
		stack = NSStackView(views: [label, rule])
		super.init(frame: .zero)
		label.stringValue = text.uppercased()
		rule.wantsLayer = true
		rule.translatesAutoresizingMaskIntoConstraints = false
		rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
		rule.setContentHuggingPriority(.defaultLow, for: .horizontal)
		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.translatesAutoresizingMaskIntoConstraints = false
		applyTheme()
		ScaledControls.register(self)
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func applyTheme() {
		let theme = Theme.current
		label.font = theme.uiFont(10, weight: .semibold)
		label.textColor = theme.gitIgnored
		rule.layer?.backgroundColor = theme.separator.cgColor
		stack.spacing = theme.scaled(8)
	}
}

/// A value that looks like a value until somebody goes to change it.
///
/// Ten bordered boxes against five bare labels was two languages in one list,
/// and the boxes were the louder of them: a column of empty rectangles is what
/// the pane showed before a caret had been anywhere. The box is what says
/// *this one takes typing*, so it is drawn when that is the question being
/// asked — under the pointer, or while the field has the keyboard — and not
/// for the whole time the pane is open.
private final class ValueField: NSTextField, ScaleFollowing {
	private let editableValue: Bool
	private var hovering = false
	private var editing = false

	init(field: ByteValues.Field) {
		editableValue = field.isEditable
		super.init(frame: .zero)
		alignment = .right                    // digits line up, which is the point of them
		isEditable = field.isEditable
		isSelectable = true
		isBordered = false
		isBezeled = false
		drawsBackground = false
		lineBreakMode = .byTruncatingTail
		wantsLayer = true
		if field.isEditable {
			toolTip = "Type a value and press Return to write it as bytes at the caret"
		}
		applyTheme()
		ScaledControls.register(self)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func applyTheme() {
		let theme = Theme.current
		font = theme.monoFont(11)
		layer?.cornerRadius = theme.scaled(3)
		drawBox()
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		for area in trackingAreas { removeTrackingArea(area) }
		guard editableValue else { return }
		addTrackingArea(NSTrackingArea(
			rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self
		))
	}

	override func mouseEntered(with event: NSEvent) { hovering = true; drawBox() }
	override func mouseExited(with event: NSEvent) { hovering = false; drawBox() }

	override func becomeFirstResponder() -> Bool {
		let became = super.becomeFirstResponder()
		if became { editing = true; drawBox() }
		return became
	}

	override func textDidEndEditing(_ notification: Notification) {
		super.textDidEndEditing(notification)
		editing = false
		drawBox()
	}

	private func drawBox() {
		let theme = Theme.current
		let shown = editableValue && (hovering || editing)
		layer?.backgroundColor = shown ? theme.editorBackground.cgColor : NSColor.clear.cgColor
		layer?.borderWidth = shown ? 1 : 0
		layer?.borderColor = theme.separator.cgColor
	}
}

/// One checksum, in the one shape it has in every state.
private final class ChecksumRow: NSView, ScaleFollowing {
	let kind: Checksum
	let result = NSTextField(labelWithString: "")
	private let name = NSTextField(labelWithString: "")
	private let compute: NSButton
	private let progress = NSProgressIndicator()
	private let copy: NSButton
	private let stack: NSStackView
	private let nameWidth: NSLayoutConstraint
	private let progressWidth: NSLayoutConstraint

	init(kind: Checksum, target: AnyObject, compute computeAction: Selector, copy copyAction: Selector) {
		self.kind = kind
		compute = NSButton(title: "compute", target: target, action: computeAction)
		copy = NSButton(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")!, target: target, action: copyAction)
		stack = NSStackView(views: [name, compute, result, progress, NSView(), copy])
		nameWidth = name.widthAnchor.constraint(equalToConstant: 0)
		progressWidth = progress.widthAnchor.constraint(equalToConstant: 0)
		super.init(frame: .zero)

		name.stringValue = kind.name
		name.translatesAutoresizingMaskIntoConstraints = false
		nameWidth.isActive = true

		compute.identifier = .init(kind.rawValue)
		compute.bezelStyle = .inline
		compute.isBordered = false
		compute.toolTip = "Compute \(kind.name), streamed over the file or the selection"

		result.isSelectable = true
		result.lineBreakMode = .byTruncatingMiddle
		result.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		progress.style = .bar
		progress.isIndeterminate = false
		progress.minValue = 0
		progress.maxValue = 1
		progress.translatesAutoresizingMaskIntoConstraints = false
		progressWidth.isActive = true

		copy.identifier = .init(kind.rawValue)
		copy.bezelStyle = .accessoryBarAction
		copy.isBordered = false
		copy.toolTip = "Copy the digest"

		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
		applyTheme()
		show(.idle)
		ScaledControls.register(self)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func applyTheme() {
		let theme = Theme.current
		name.font = theme.uiFont(11)
		name.textColor = theme.gitIgnored
		compute.font = theme.uiFont(11)
		compute.contentTintColor = theme.gitIgnored
		result.font = theme.monoFont(11)
		copy.contentTintColor = theme.gitIgnored
		nameWidth.constant = theme.scaled(72)
		progressWidth.constant = theme.scaled(70)
		stack.spacing = theme.scaled(6)
	}

	func show(_ state: HexInspectorPane.ChecksumState) {
		let theme = Theme.current
		switch state {
		case .idle:
			compute.isHidden = false
			compute.title = "compute"
			result.stringValue = ""
			result.isHidden = true
			progress.isHidden = true
			copy.isHidden = true
		case .running(let fraction):
			compute.isHidden = false
			compute.title = "stop"
			result.isHidden = true
			progress.isHidden = false
			progress.doubleValue = fraction
			copy.isHidden = true
		case .done(let digest):
			compute.isHidden = true
			result.isHidden = false
			result.stringValue = digest
			result.textColor = theme.editorText
			result.toolTip = digest
			progress.isHidden = true
			copy.isHidden = false
		case .stale(let digest):
			compute.isHidden = false
			compute.title = "again"
			result.isHidden = false
			result.stringValue = digest
			result.textColor = theme.gitIgnored
			result.toolTip = "The bytes changed since this was computed; press again to compute it afresh."
			progress.isHidden = true
			copy.isHidden = true
		}
	}
}
