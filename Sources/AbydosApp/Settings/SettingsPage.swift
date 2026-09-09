import AppKit
import AbydosKit

/// The settings, as a page in the editor.
///
/// A preferences window is a box of the system's own colours in front of a
/// dark one, sized to whatever fits and closed the moment anything else is
/// wanted. As a tab it is the app's own: it takes the width it is given, the
/// help under each setting has room to be a sentence, and it can be left open
/// beside the thing being adjusted — which is the only way to tell whether the
/// adjustment was right.
///
/// The sections and the settings in them come from the same list the window
/// uses, so the two cannot drift apart.
@MainActor
final class SettingsPage: NSView, ScalingPage {
	/// Every page, parents and their children, in the order they are listed.
	///
	/// Flattened rather than an outline view: two levels is all this nests, and
	/// a table over an array with a depth in it is a list somebody can see all
	/// of. The depth is what the row draws itself with, and folding is a filter
	/// over this array rather than a different kind of view.
	private let sections = SettingsSections.flattened
	/// Which rows are folded, by their place in the list above.
	///
	/// Not remembered between launches, deliberately: there are seven sections
	/// and one of them folds, so opening settings to find a section missing
	/// because of something done last week costs more than folding Tools again
	/// costs. It is a click, and it is where it was left for as long as the
	/// page is open.
	private var collapsed: Set<Int> = []
	/// The rows showing, as places in `sections`.
	private var rows: [Int] = []
	/// Which page is showing, as a place in `sections`.
	private var selected = 0
	/// Controls that have to be re-read when something changes them from
	/// outside — Restore Defaults, or the other window.
	private var refreshHandlers: [() -> Void] = []

	private let list = SettingsSidebarTable()
	private let form = NSStackView()
	private var scroll: NSScrollView!
	private var sidebarTitle: NSTextField!
	/// The filter field in the sidebar, and the words it holds. Empty words is
	/// no filter, and the page is the page it always was.
	private let filterField = NSSearchField()
	private var filterWords: [String] = []
	/// Each section's heading on the results page, by its place in `sections`,
	/// so a click in the narrowed sidebar scrolls to it rather than replacing
	/// the results with one page.
	private var resultHeadings: [Int: NSView] = [:]

	/// Constraints whose constants are design-time sizes, kept beside the size
	/// each was written as.
	///
	/// A page reads the zoom as it builds, so one built at 1× would keep 1×
	/// spacing for as long as it stayed open however far the rest of the window
	/// grew. Holding the design number is what lets the zoom be pushed back in
	/// — the constant on the constraint is the answer, not the question.
	private var scaledConstraints: [(constraint: NSLayoutConstraint, design: CGFloat)] = []

	override init(frame: NSRect) {
		super.init(frame: frame)
		rows = SettingsOutline.visible(depths: sections.map(\.depth), collapsed: collapsed)
		build()
		show(section: 0)

		NotificationCenter.default.addObserver(
			forName: .abydosSettingsChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.refreshHandlers.forEach { $0() } }
		}

		// A row's *options* can change too, and re-reading the controls does not
		// touch those: the list of themes is fixed when the page is built, so a
		// scheme dropped into the folder and reloaded would not appear in it
		// however many times the values were refreshed. The page is built again
		// instead, which is cheap and only happens when somebody asks.
		NotificationCenter.default.addObserver(
			forName: .abydosSettingsRowsChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.redisplay() }
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Shows a section by name, for the capture harness.
	func show(named name: String) {
		guard let index = sections.firstIndex(where: {
			$0.section.title.lowercased() == name.lowercased()
		}) else { return }
		// Whatever it sits under has to be open, or it is being selected out of
		// sight.
		collapsed.subtract(SettingsOutline.ancestors(depths: sections.map(\.depth), of: index))
		refreshRows()
		if let row = rows.firstIndex(of: index) {
			list.selectRowIndexes([row], byExtendingSelection: false)
		}
		show(section: index)
	}

	/// Folds a section away, or opens it again — the disclosure triangle, and
	/// what a capture run presses instead of it.
	func toggleFold(named name: String) {
		guard let index = sections.firstIndex(where: {
			$0.section.title.lowercased() == name.lowercased()
		}) else { return }
		toggleFold(at: index)
	}

	// MARK: - Testing

	/// Presses arrow keys on the sidebar, as a capture run does instead of using
	/// a keyboard.
	///
	/// The events go to the table rather than to `fold(_:)` directly, so what a
	/// run exercises is the path a keyboard takes: up and down are the table's
	/// own and have to keep working, and proving that is half the point.
	func pressArrowsForTesting(_ keys: [String]) {
		let arrows: [String: (character: Int, code: UInt16)] = [
			"left": (NSLeftArrowFunctionKey, 123),
			"right": (NSRightArrowFunctionKey, 124),
			"down": (NSDownArrowFunctionKey, 125),
			"up": (NSUpArrowFunctionKey, 126),
		]
		for key in keys {
			guard let arrow = arrows[key.lowercased()],
			      let scalar = UnicodeScalar(UInt32(arrow.character))
			else { continue }
			let text = String(Character(scalar))
			guard let event = NSEvent.keyEvent(
				with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
				windowNumber: window?.windowNumber ?? 0, context: nil,
				characters: text, charactersIgnoringModifiers: text,
				isARepeat: false, keyCode: arrow.code
			) else { continue }
			list.keyDown(with: event)
		}
	}

	/// Which page is showing, what the sidebar has left in it, and the sizes the
	/// zoom was supposed to reach.
	var reportForTesting: String {
		let showing = rows.map { sections[$0].section.title }
		return "selected=\(sections[selected].section.title)"
			+ " rows=\(showing.count)"
			+ " row-height=\(Int(list.rowHeight))"
			+ " sidebar=\(Int(list.enclosingScrollView?.superview?.frame.width ?? 0))"
			+ " showing=[\(showing.joined(separator: " | "))]"
	}

	private func toggleFold(at index: Int) {
		guard SettingsOutline.hasChildren(depths: sections.map(\.depth), at: index) else { return }
		if collapsed.contains(index) {
			collapsed.remove(index)
		} else {
			collapsed.insert(index)
		}
		refreshRows()

		// Folding away the page somebody is reading would leave the page
		// showing with nothing selected. It shows the section it folded into
		// instead, which is the row still under the pointer.
		if !rows.contains(selected) {
			selected = index
			show(section: index)
		}
		if let row = rows.firstIndex(of: selected) {
			list.selectRowIndexes([row], byExtendingSelection: false)
		}
	}

	private func refreshRows() {
		// Filtering wins over folding: a match under a folded Tools is still a
		// match, and a sidebar that hid it would be a filter that lies.
		rows = filterWords.isEmpty
			? SettingsOutline.visible(depths: sections.map(\.depth), collapsed: collapsed)
			: filteredSections().map(\.index)
		list.reloadData()
	}

	/// Left and right in the sidebar, with an outline view's meaning.
	///
	/// The decision is arithmetic over the depths and lives in `SettingsOutline`
	/// beside the rest of the folding, so what the keys do is settled by a test
	/// rather than by a window; this only carries it out. Up and down are never
	/// here — the table already walks the rows that are showing, which is
	/// exactly the list folding leaves behind.
	///
	/// Answers whether the key was used, so one that does nothing — right on a
	/// leaf, left at the top of the list — goes back to the table rather than
	/// being swallowed.
	@discardableResult
	func fold(_ key: SettingsOutline.Fold) -> Bool {
		let depths = sections.map(\.depth)
		let before = SettingsOutline.FoldState(collapsed: collapsed, selected: selected)
		let after = SettingsOutline.fold(
			depths: depths, collapsed: collapsed, selected: selected, key
		)
		guard after != before else { return false }

		collapsed = after.collapsed
		refreshRows()
		// The page first, so that selecting the row finds it already showing and
		// does not build the same section a second time.
		show(section: after.selected)
		if let row = rows.firstIndex(of: after.selected) {
			list.selectRowIndexes([row], byExtendingSelection: false)
			list.scrollRowToVisible(row)
		}
		return true
	}

	deinit { NotificationCenter.default.removeObserver(self) }

	// MARK: - The zoom

	/// Re-reads the zoom and the palette, the way every other pane in the window
	/// does when ⌘+ is pressed.
	///
	/// Without this the page was the one thing in the window that did not
	/// follow: `applySettings` reaches the editor, the navigator, the tool strip
	/// and the bottom panel, and a settings *tab* is none of those — it is a
	/// view in an editor group, and nothing walked into one. A page opened at 1×
	/// therefore kept 1× rows, a 1× sidebar and 1× type for as long as it stayed
	/// open, however far the window around it grew.
	func applySettings() {
		for (constraint, design) in scaledConstraints {
			constraint.constant = Theme.current.scaled(design)
		}
		applyMetrics()
		// Built again rather than adjusted: every control in a section reads the
		// zoom as it is made, and there is one section on screen.
		redisplay()
		list.reloadData()
	}

	/// The sizes that are not constraints: fonts, row heights and the form's own
	/// padding, all of which are read once when something is built.
	private func applyMetrics() {
		sidebarTitle?.font = Theme.current.uiFont(11, weight: .semibold)
		list.rowHeight = Theme.current.scaled(28)
		form.spacing = Theme.current.scaled(18)
		form.edgeInsets = NSEdgeInsets(
			top: Theme.current.scaled(24), left: Theme.current.scaled(28),
			bottom: Theme.current.scaled(32), right: Theme.current.scaled(28)
		)
	}

	/// Sets a constraint from a design-time size and remembers the pair, so the
	/// zoom can be put back into it later.
	private func scaled(_ constraint: NSLayoutConstraint, _ design: CGFloat) -> NSLayoutConstraint {
		constraint.constant = Theme.current.scaled(design)
		scaledConstraints.append((constraint, design))
		return constraint
	}

	// MARK: - Layout

	private func build() {
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor

		let sidebar = makeSidebar()
		scroll = NSScrollView()
		scroll.hasVerticalScroller = true
		// Sideways too, for the case below: a pane narrower than the widest
		// control has to scroll rather than refuse to be that narrow.
		scroll.hasHorizontalScroller = true
		scroll.drawsBackground = false
		scroll.borderType = .noBorder

		form.orientation = .vertical
		form.alignment = .leading
		form.translatesAutoresizingMaskIntoConstraints = false

		let clip = FlippedContainer()
		clip.addSubview(form)
		scroll.documentView = clip
		clip.translatesAutoresizingMaskIntoConstraints = false

		for view in [sidebar, scroll] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			view.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
			addSubview(view)
		}

		NSLayoutConstraint.activate([
			sidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
			sidebar.topAnchor.constraint(equalTo: topAnchor),
			sidebar.bottomAnchor.constraint(equalTo: bottomAnchor),
			// Wide enough for a child's name at its own indentation: "Rust —
			// rust-analyzer" under "Tools" is the longest thing this list has to
			// hold, and a sidebar that truncates the names is a list you have to
			// click through to read.
			scaled(sidebar.widthAnchor.constraint(equalToConstant: 0), 232),

			scroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
			scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
			scroll.topAnchor.constraint(equalTo: topAnchor),
			scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

			clip.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
			// At least as wide as the pane, and exactly as wide whenever it
			// fits — which is every ordinary case, so this looks like nothing
			// changed. Pinned to *equal* on both sides, the content could never
			// be narrower than the widest control in it, and that width left the
			// scroll view, left this page and reached the split it sits in: a
			// settings tab beside an editor could not be made narrower, and
			// widening the split first and then coming back to settings snapped
			// it shut again. A page decides how tall it is; the split decides
			// how wide.
			clip.trailingAnchor.constraint(
				greaterThanOrEqualTo: scroll.contentView.trailingAnchor
			),
			{
				let fits = clip.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor)
				fits.priority = .defaultLow
				return fits
			}(),
			clip.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),

			form.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
			form.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
			form.topAnchor.constraint(equalTo: clip.topAnchor),
			form.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
		])
	}

	private func makeSidebar() -> NSView {
		let background = ColoredView(color: Theme.current.sidebarBackground)

		list.headerView = nil
		list.backgroundColor = .clear
		list.selectionHighlightStyle = .regular
		list.rowSizeStyle = .custom
		list.intercellSpacing = .zero
		list.gridStyleMask = []
		list.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section")))
		list.delegate = self
		list.dataSource = self
		list.onFold = { [weak self] key in self?.fold(key) ?? false }
		list.selectRowIndexes([0], byExtendingSelection: false)

		let scroll = NSScrollView()
		scroll.documentView = list
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = false
		scroll.borderType = .noBorder

		let title = NSTextField(labelWithString: "Settings")
		title.textColor = Theme.current.gitIgnored
		sidebarTitle = title

		// The filter, where every settings window on the machine has one.
		// Typing narrows the sidebar to the sections with a match and turns the
		// form into the matching rows of all of them; see `applyFilter`.
		filterField.placeholderString = "Filter"
		filterField.sendsSearchStringImmediately = true
		filterField.sendsWholeSearchString = false
		filterField.target = self
		filterField.action = #selector(filterChanged(_:))
		filterField.setAccessibilityLabel("Filter settings")

		for view in [title, filterField, scroll] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			background.addSubview(view)
		}
		NSLayoutConstraint.activate([
			scaled(title.topAnchor.constraint(equalTo: background.topAnchor), 14),
			scaled(title.leadingAnchor.constraint(equalTo: background.leadingAnchor), 14),

			scaled(filterField.topAnchor.constraint(equalTo: title.bottomAnchor), 8),
			scaled(filterField.leadingAnchor.constraint(equalTo: background.leadingAnchor), 10),
			scaled(filterField.trailingAnchor.constraint(equalTo: background.trailingAnchor), -10),

			scaled(scroll.topAnchor.constraint(equalTo: filterField.bottomAnchor), 8),
			scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
			scaled(scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor), -10),
		])
		applyMetrics()
		return background
	}

	// MARK: - Contents

	/// Shows one section, replacing whatever was there.
	private func show(section index: Int) {
		guard sections.indices.contains(index) else { return }
		selected = index
		refreshHandlers.removeAll()
		for view in form.arrangedSubviews { view.removeFromSuperview() }

		let section = sections[index].section
		let heading = NSTextField(labelWithString: section.title)
		heading.font = Theme.current.uiFont(17, weight: .semibold)
		heading.textColor = Theme.current.sidebarHeaderText
		form.addArrangedSubview(heading)

		for block in blocks(for: section.rows()) { form.addArrangedSubview(block) }
		fitFormWidths()
	}

	/// Wide enough to read and no wider — and the cap is on the card alone,
	/// so nothing here can decide how wide the editor area has to be.
	private func fitFormWidths() {
		for view in form.arrangedSubviews {
			let full = view.widthAnchor.constraint(
				equalTo: form.widthAnchor, constant: -Theme.current.scaled(56)
			)
			full.priority = .defaultHigh
			full.isActive = true
		}
	}

	/// The form as it should be now: the selected page, or the results of a
	/// filter that is in force. What every rebuild goes through, so a zoom or a
	/// reloaded scheme list does not throw a filter away.
	private func redisplay() {
		if filterWords.isEmpty {
			show(section: selected)
		} else {
			showResults()
		}
	}

	// MARK: - Filtering

	@objc private func filterChanged(_ sender: Any?) {
		applyFilter(filterField.stringValue)
	}

	/// ⌘F. The menu sends Find to the first responder, and with the sidebar or
	/// the form focused that chain runs through this view before it reaches the
	/// window controller's find-in-file — which has no file here to find in.
	@objc func findInFile(_ sender: Any?) {
		window?.makeFirstResponder(filterField)
	}

	/// Narrows the page to what matches, or puts it back.
	///
	/// Two things at once, because each alone is half a filter: the sidebar
	/// keeps only the sections with a match, and the form shows the matching
	/// rows of every one of them under its heading. Filtering the sidebar alone
	/// would light up "Terminal" for "ghostty" and leave the reader to find the
	/// word on that page; filtering the selected page alone finds nothing for a
	/// row that is on another page, which is the row people search for.
	private func applyFilter(_ query: String) {
		let words = SettingsFilter.words(in: query)
		let hadFilter = !filterWords.isEmpty
		filterWords = words
		refreshRows()
		if words.isEmpty {
			// Back to the page that was selected, with the sidebar as it was.
			guard hadFilter else { return }
			if let row = rows.firstIndex(of: selected) {
				list.selectRowIndexes([row], byExtendingSelection: false)
			}
			show(section: selected)
			return
		}
		showResults()
	}

	/// Every section with a matching row, with those rows — a group kept whole
	/// when its own title matches, and with its matching rows when only they do.
	private func filteredSections() -> [(index: Int, rows: [SettingsPaneController.Row])] {
		sections.indices.compactMap { index in
			let kept = filtered(sections[index].section.rows())
			return kept.isEmpty ? nil : (index, kept)
		}
	}

	private func filtered(_ rows: [SettingsPaneController.Row]) -> [SettingsPaneController.Row] {
		rows.compactMap { row in
			switch row {
			case let .group(title, help, inside):
				if SettingsFilter.matches(title: title, help: help, words: filterWords) { return row }
				let kept = filtered(inside)
				return kept.isEmpty ? nil : .group(title: title, help: help, rows: kept)
			case let .button(title, label, _):
				return SettingsFilter.matches(title: title, help: label, words: filterWords) ? row : nil
			case let .toggle(title, help, _, _, _),
			     let .slider(title, help, _, _, _, _, _),
			     let .stepper(title, help, _, _, _),
			     let .text(title, help, _, _),
			     let .choice(title, help, _, _, _),
			     let .choiceWithActions(title, help, _, _, _, _):
				return SettingsFilter.matches(title: title, help: help, words: filterWords) ? row : nil
			}
		}
	}

	/// The matching rows of every matching section, each under its heading, in
	/// the sidebar's order — or the one line that says nothing matched.
	private func showResults() {
		refreshHandlers.removeAll()
		resultHeadings.removeAll()
		for view in form.arrangedSubviews { view.removeFromSuperview() }

		let found = filteredSections()
		if found.isEmpty {
			let nothing = NSTextField(labelWithString: "Nothing matches \u{201C}\(filterField.stringValue)\u{201D}")
			nothing.font = Theme.current.uiFont(13)
			nothing.textColor = Theme.current.gitIgnored
			form.addArrangedSubview(nothing)
			return
		}
		for (index, rows) in found {
			let heading = NSTextField(labelWithString: resultTitle(for: index))
			heading.font = Theme.current.uiFont(17, weight: .semibold)
			heading.textColor = Theme.current.sidebarHeaderText
			form.addArrangedSubview(heading)
			resultHeadings[index] = heading
			for block in blocks(for: rows) { form.addArrangedSubview(block) }
		}
		fitFormWidths()
	}

	/// A child page's name with its parent's, so "Rust" on a results page says
	/// whose Rust it is.
	private func resultTitle(for index: Int) -> String {
		let title = sections[index].section.title
		guard sections[index].depth > 0,
		      let parent = sections[..<index].lastIndex(where: { $0.depth == 0 })
		else { return title }
		return "\(sections[parent].section.title) \u{25B8} \(title)"
	}

	// MARK: - Testing the filter

	/// Types into the filter, as a driven run does instead of a keyboard.
	func filterForTesting(_ text: String) {
		filterField.stringValue = text
		applyFilter(text)
	}

	/// What the filter left: the sections in the sidebar and the rows on the
	/// results page, by title, in order.
	var filterReportForTesting: String {
		let query = filterField.stringValue
		let found = filteredSections()
		let sections = found.map { resultTitle(for: $0.index) }
		let rows = found.flatMap { entry in
			titles(of: entry.rows).map { "\(resultTitle(for: entry.index)) \u{25B8} \($0)" }
		}
		return "query=\u{201C}\(query)\u{201D} sections=[\(sections.joined(separator: " | "))]"
			+ " rows=\(rows.count)\n" + rows.map { "SETTINGS FILTER   \($0)" }.joined(separator: "\n")
	}

	private func titles(of rows: [SettingsPaneController.Row]) -> [String] {
		rows.flatMap { row -> [String] in
			switch row {
			case let .group(title, _, inside): return titles(of: inside).map { "\(title) / \($0)" }
			case let .button(title, _, _): return [title]
			case let .toggle(title, _, _, _, _),
			     let .slider(title, _, _, _, _, _, _),
			     let .stepper(title, _, _, _, _),
			     let .text(title, _, _, _),
			     let .choice(title, _, _, _, _),
			     let .choiceWithActions(title, _, _, _, _, _):
				return [title]
			}
		}
	}

	/// The rows of a section, with any group gathered into a card of its own.
	///
	/// A heading and a gap were not enough to say "these three belong
	/// together": the switches that depend on each other now sit inside their
	/// own rounded rectangle, which is what a group looks like on this
	/// platform.
	private func blocks(for rows: [SettingsPaneController.Row]) -> [NSView] {
		var blocks: [NSView] = []
		var loose: [NSView] = []

		func flushLoose() {
			guard !loose.isEmpty else { return }
			blocks.append(card(titled: nil, help: nil, rows: loose))
			loose = []
		}

		for row in rows {
			guard case let .group(title, help, inside) = row else {
				loose.append(self.row(for: row))
				continue
			}
			// A section of its own: its name above, its settings in a card
			// under it, the way this platform separates one group from the
			// next.
			flushLoose()
			blocks.append(sectionHeading(title, help: help))
			// **A group with nothing in it is a heading, not an empty box.**
			// Some sections are an explanation and no setting — what trust
			// means, what the Finder will not let this app do — and a card
			// drawn round no rows is a rounded rectangle with nothing in it,
			// which was reported as exactly that.
			guard !inside.isEmpty else { continue }
			blocks.append(card(titled: nil, help: nil, rows: inside.map { self.row(for: $0) }))
		}
		flushLoose()
		return blocks
	}

	/// The name of a section, over the card that holds it — and what the
	/// section is about, if that needs saying.
	///
	/// Above the card rather than inside it: a sentence about the whole group
	/// reads as a note on the first setting when it sits in the same box.
	private func sectionHeading(_ title: String, help: String?) -> NSView {
		let label = NSTextField(labelWithString: title)
		label.font = Theme.current.uiFont(13, weight: .semibold)
		label.textColor = Theme.current.sidebarHeaderText

		guard let help else { return label }

		let text = NSTextField(wrappingLabelWithString: help)
		text.font = Theme.current.uiFont(11)
		text.textColor = Theme.current.gitIgnored
		text.isSelectable = false
		text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		let stack = NSStackView(views: [label, text])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = Theme.current.scaled(2)
		text.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		return stack
	}

	/// A group's own card: a heading, a sentence, and the settings it gathers.
	private func card(titled title: String?, help: String?, rows: [NSView]) -> NSView {
		var top: [NSView] = []
		if let title {
			let heading = NSTextField(labelWithString: title)
			heading.font = Theme.current.uiFont(11.5, weight: .semibold)
			heading.textColor = Theme.current.sidebarText
			top.append(heading)
		}
		if let help {
			let text = NSTextField(wrappingLabelWithString: help)
			text.font = Theme.current.uiFont(11)
			text.textColor = Theme.current.gitIgnored
			text.isSelectable = false
			text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
			top.append(text)
		}

		let stack = NSStackView(views: top + rows)
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = Theme.current.scaled(14)
		if let heading = top.first { stack.setCustomSpacing(Theme.current.scaled(4), after: heading) }
		stack.translatesAutoresizingMaskIntoConstraints = false

		// A shade apart from the card it sits in, so the boundary reads without
		// a heavy line around it.
		let card = ColoredView(color: Theme.current.sidebarBackground)
		card.colourSource = { Theme.current.sidebarBackground }
		card.wantsLayer = true
		card.layer?.cornerRadius = 8
		card.layer?.borderWidth = 1
		card.layer?.borderColor = Theme.current.separator.withAlphaComponent(0.7).cgColor
		card.addSubview(stack)

		let inset = Theme.current.scaled(14)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
			stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -inset),
			stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: inset),
			stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -inset),
		])
		for view in rows { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
		return card
	}

	/// One setting: its name, its control, and a sentence about it.
	///
	/// The control goes on the right of the name, and the help under both —
	/// which reads as one thing rather than as a grid, and leaves the sentence
	/// the whole width to be a sentence in.
	private func row(for row: SettingsPaneController.Row) -> NSView {
		let (title, control, help) = build(row)

		let label = NSTextField(labelWithString: title)
		label.font = Theme.current.uiFont(12.5)
		label.textColor = Theme.current.sidebarText
		label.lineBreakMode = .byTruncatingTail
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		let top = NSStackView(views: title.isEmpty ? [control] : [label, NSView(), control])
		top.orientation = .horizontal
		top.alignment = .centerY
		top.spacing = Theme.current.scaled(12)

		let stack = NSStackView(views: [top])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = Theme.current.scaled(3)
		top.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

		var helpLabel: NSTextField?
		if let help {
			let text = NSTextField(wrappingLabelWithString: help)
			text.font = Theme.current.uiFont(11)
			text.textColor = Theme.current.gitIgnored
			text.isSelectable = false
			text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
			stack.addArrangedSubview(text)
			text.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
			helpLabel = text
		}

		// A switch that cannot be used is only half the message: a disabled
		// checkbox on macOS is a subtle thing, and the name beside it in full
		// strength reads as a setting somebody simply has not turned on.
		if case let .toggle(_, _, _, _, isEnabled) = row, let isEnabled {
			let dim = {
				let on = isEnabled()
				label.textColor = on
					? Theme.current.sidebarText
					: Theme.current.sidebarText.withAlphaComponent(0.35)
				helpLabel?.textColor = on
					? Theme.current.gitIgnored
					: Theme.current.gitIgnored.withAlphaComponent(0.45)
			}
			dim()
			refreshHandlers.append(dim)
		}
		return stack
	}

	/// The control for a row, in this app's colours.
	private func build(_ row: SettingsPaneController.Row) -> (String, NSView, String?) {
		switch row {
		case let .toggle(title, help, get, set, isEnabled):
			let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
			// Every system control on this page is told what size to draw at, not
			// only what font to put in it: see `Theme.controlSize(_:)` for why
			// the font alone leaves the bezel where it was.
			button.controlSize = Theme.current.controlSize()
			button.state = get() ? .on : .off
			button.isEnabled = isEnabled?() ?? true
			button.onAction = {
				set(button.state == .on)
				// One switch decides another's fate, so every control re-reads
				// itself — and its own state — after any of them changes.
				NotificationCenter.default.post(name: .abydosSettingsChanged, object: nil)
			}
			refreshHandlers.append {
				button.state = get() ? .on : .off
				button.isEnabled = isEnabled?() ?? true
			}
			return (title, button, help)

		case let .slider(title, help, range, step, format, get, set):
			let value = NSTextField(labelWithString: format(get()))
			value.font = .monospacedDigitSystemFont(ofSize: Theme.current.scaled(11), weight: .regular)
			value.textColor = Theme.current.gitIgnored
			value.alignment = .right
			value.widthAnchor.constraint(equalToConstant: Theme.current.scaled(52)).isActive = true

			let slider = NSSlider(
				value: get(), minValue: range.lowerBound, maxValue: range.upperBound,
				target: nil, action: nil
			)
			slider.numberOfTickMarks = Int((range.upperBound - range.lowerBound) / step) + 1
			slider.allowsTickMarkValuesOnly = true
			slider.controlSize = Theme.current.controlSize(.small)
			slider.widthAnchor.constraint(equalToConstant: Theme.current.scaled(200)).isActive = true
			slider.onAction = {
				set(slider.doubleValue)
				value.stringValue = format(slider.doubleValue)
			}
			refreshHandlers.append {
				slider.doubleValue = get()
				value.stringValue = format(get())
			}

			let stack = NSStackView(views: [slider, value])
			stack.orientation = .horizontal
			stack.spacing = Theme.current.scaled(10)
			return (title, stack, help)

		case let .stepper(title, help, range, get, set):
			let field = field(text: "\(get())", width: Theme.current.scaled(48))
			field.alignment = .right

			let stepper = NSStepper()
			stepper.controlSize = Theme.current.controlSize()
			stepper.minValue = Double(range.lowerBound)
			stepper.maxValue = Double(range.upperBound)
			stepper.increment = 1
			stepper.integerValue = get()
			stepper.onAction = {
				set(stepper.integerValue)
				field.stringValue = "\(stepper.integerValue)"
			}
			field.onAction = {
				let clamped = min(range.upperBound, max(range.lowerBound, field.integerValue))
				set(clamped)
				stepper.integerValue = clamped
				field.stringValue = "\(clamped)"
			}
			refreshHandlers.append {
				stepper.integerValue = get()
				field.stringValue = "\(get())"
			}

			let stack = NSStackView(views: [field, stepper])
			stack.orientation = .horizontal
			stack.spacing = Theme.current.scaled(4)
			return (title, stack, help)

		case let .text(title, help, get, set):
			let field = field(text: get(), width: Theme.current.scaled(260))
			field.onAction = { set(field.stringValue) }
			refreshHandlers.append { field.stringValue = get() }
			return (title, field, help)

		case let .choice(title, help, options, get, set):
			let popUp = NSPopUpButton()
			popUp.controlSize = Theme.current.controlSize()
			popUp.font = Theme.current.uiFont(12)
			popUp.addItems(withTitles: options.map(\.label))
			popUp.widthAnchor.constraint(equalToConstant: Theme.current.scaled(190)).isActive = true

			func select(_ value: String) {
				popUp.selectItem(at: options.firstIndex { $0.value == value } ?? 0)
			}
			select(get())
			popUp.onAction = {
				let index = popUp.indexOfSelectedItem
				guard options.indices.contains(index) else { return }
				set(options[index].value)
			}
			refreshHandlers.append { select(get()) }
			return (title, popUp, help)

		case let .choiceWithActions(title, help, options, get, set, actions):
			let (_, control, _) = build(
				.choice(title: title, help: help, options: options, get: get, set: set)
			)
			let stack = NSStackView(views: [control] + actions.map { item in
				let button = NSButton(
					image: Theme.symbol(
						item.symbol,
						size: Theme.current.scaled(12),
						color: Theme.current.sidebarText
					) ?? NSImage(),
					target: nil, action: nil
				)
				button.bezelStyle = .rounded
				button.controlSize = Theme.current.controlSize()
				button.toolTip = item.help
				button.onAction = item.action
				return button
			})
			stack.orientation = .horizontal
			stack.spacing = Theme.current.scaled(6)
			return (title, stack, help)

		case let .group(title, _, _):
			return (title, NSView(), nil)

		case let .button(title, label, action):
			let button = NSButton(title: label, target: nil, action: nil)
			button.bezelStyle = .rounded
			button.controlSize = Theme.current.controlSize()
			button.font = Theme.current.uiFont(12)
			button.onAction = action
			return (title, button, nil)
		}
	}

	private func field(text: String, width: CGFloat) -> NSTextField {
		let field = NSTextField(string: text)
		field.controlSize = Theme.current.controlSize()
		field.font = Theme.terminalFont(size: Theme.current.fontSize - 1)
		field.textColor = Theme.current.sidebarText
		field.backgroundColor = Theme.current.editorBackground
		field.drawsBackground = true
		field.isBordered = false
		field.isBezeled = true
		field.bezelStyle = .roundedBezel
		field.focusRingType = .none
		field.widthAnchor.constraint(equalToConstant: width).isActive = true
		return field
	}
}

extension SettingsPage: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

	/// A child sits under its parent rather than beside it, and every name
	/// leaves room for a triangle whether or not it has one, so the icons line
	/// up down the list.
	private func indent(forRow row: Int) -> CGFloat {
		Theme.current.scaled(12) + Theme.current.scaled(14) * CGFloat(sections[rows[row]].depth)
	}

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		let index = rows[row]
		let cell = NSTableCellView()
		let text = NSTextField(labelWithString: sections[index].section.title)
		text.font = Theme.current.uiFont(12)
		text.textColor = Theme.current.sidebarText

		let icon = NSImageView()
		icon.image = Theme.symbol(
			sections[index].section.symbol,
			size: 11 * Theme.current.scale,
			color: Theme.current.gitIgnored
		)

		for view in [icon, text] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			cell.addSubview(view)
		}
		let triangleWidth = Theme.current.scaled(13)
		NSLayoutConstraint.activate([
			icon.leadingAnchor.constraint(
				equalTo: cell.leadingAnchor, constant: indent(forRow: row) + triangleWidth
			),
			icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			icon.widthAnchor.constraint(equalToConstant: Theme.current.scaled(14)),
			text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Theme.current.scaled(7)),
			text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Theme.current.scaled(8)),
			text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
		])

		guard SettingsOutline.hasChildren(depths: sections.map(\.depth), at: index) else { return cell }

		// A button rather than the row watching for clicks near its left edge:
		// the button takes the click, so folding a section does not also select
		// it, and the pointer says what it will do before it is pressed.
		let triangle = NSButton(
			image: Theme.symbol(
				collapsed.contains(index) ? "chevron.right" : "chevron.down",
				size: 8 * Theme.current.scale,
				color: Theme.current.gitIgnored
			) ?? NSImage(),
			target: nil, action: nil
		)
		triangle.isBordered = false
		triangle.setButtonType(.momentaryChange)
		triangle.toolTip = collapsed.contains(index) ? "Show what is under this" : "Fold this away"
		triangle.onAction = { [weak self] in self?.toggleFold(at: index) }
		triangle.translatesAutoresizingMaskIntoConstraints = false
		cell.addSubview(triangle)
		NSLayoutConstraint.activate([
			triangle.leadingAnchor.constraint(
				equalTo: cell.leadingAnchor, constant: indent(forRow: row) - Theme.current.scaled(2)
			),
			triangle.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			triangle.widthAnchor.constraint(equalToConstant: triangleWidth),
			triangle.heightAnchor.constraint(equalToConstant: Theme.current.scaled(18)),
		])
		return cell
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		let row = list.selectedRow
		guard rows.indices.contains(row), rows[row] != selected else { return }
		selected = rows[row]
		// While filtering, the form is every matching section at once, and a
		// click in the sidebar goes to that section's place in it rather than
		// replacing the results with one page.
		if !filterWords.isEmpty {
			if let heading = resultHeadings[selected] {
				scroll.contentView.scroll(to: NSPoint(x: 0, y: heading.frame.minY - Theme.current.scaled(24)))
				scroll.reflectScrolledClipView(scroll.contentView)
			}
			return
		}
		show(section: selected)
	}
}
