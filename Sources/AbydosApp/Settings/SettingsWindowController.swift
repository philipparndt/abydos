import AppKit
import AbydosKit

/// The preferences window (⌘,).
///
/// Uses `NSTabViewController` in toolbar style, which is the standard macOS
/// preferences shape and gets the segmented toolbar, resizing, and tab
/// switching for free.
final class SettingsWindowController: NSWindowController {
	static let shared = SettingsWindowController()

	private init() {
		// The same page the editor shows, in a window of its own.
		//
		// It used to be an `NSTabViewController` in toolbar style, which is the
		// standard preferences shape and cannot show a page under a page at all
		// — so the moment Tools grew children there were two navigations over
		// one list, which is the drift the shared section list exists to
		// prevent. One page, one order, one place to add a setting.
		let controller = NSViewController()
		controller.view = SettingsPage()

		let window = NSWindow(contentViewController: controller)
		window.title = "Settings"
		window.styleMask = [.titled, .closable, .resizable]
		window.setContentSize(NSSize(width: 720, height: 520))
		window.center()
		window.isReleasedWhenClosed = false

		super.init(window: window)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func show() {
		window?.center()
		showWindow(nil)
		NSApp.activate(ignoringOtherApps: true)
	}
}

/// A single settings pane, built from a declarative row list.
///
/// Describing rows as data rather than laying out each control by hand keeps
/// every pane consistent and makes adding a setting a one-line change.
final class SettingsPaneController: NSViewController {
	/// A row's title and whether it can be used, for checking that a switch
	/// which depends on another really is greyed out with it.
	///
	/// - Parameter withHelp: also print the sentence under each control. Off by
	///   default because it is a paragraph a row and makes the common check —
	///   which rows are here, which is on, which is greyed out — unreadable. On
	///   when the *words* are the thing being checked, which 0452 needed: the line
	///   saying what a Java server costs is only in the help, and a dump that
	///   printed titles alone could not show that it was there.
	static func describe(_ rows: [Row], withHelp: Bool = false) -> [String] {
		rows.map { row in
			let line: String
			var help: String?
			switch row {
			case let .toggle(title, said, get, _, isEnabled):
				let state = get() ? "on " : "off"
				line = "\(state) \(isEnabled?() ?? true ? "        " : "disabled") \(title)"
				help = said
			case let .slider(title, said, _, _, _, _, _):
				line = "        slider   \(title)"
				help = said
			case let .stepper(title, said, _, _, _):
				line = "        stepper  \(title)"
				help = said
			case let .text(title, said, _, _):
				line = "        text     \(title)"
				help = said
			case let .choice(title, said, _, get, _):
				line = "\(get())  choice   \(title)"
				help = said
			case let .choiceWithActions(title, said, _, get, _, actions):
				line = "\(get())  choice   \(title) [\(actions.map(\.symbol).joined(separator: " "))]"
				help = said
			case let .button(title, label, _):
				line = "        [\(label)] \(title)"
			case let .group(title, said, rows):
				line = (["── \(title) ──"] + describe(rows, withHelp: withHelp).map { "  " + $0 })
					.joined(separator: "\nSETTING ")
				help = said
			}
			guard withHelp, let help else { return line }
			return line + "\nSETTING            ↳ " + help
		}
	}

	enum Row {
		case toggle(title: String, help: String?, get: () -> Bool, set: (Bool) -> Void,
		            isEnabled: (() -> Bool)? = nil)
		case slider(title: String, help: String?, range: ClosedRange<Double>, step: Double,
		            format: (Double) -> String, get: () -> Double, set: (Double) -> Void)
		case stepper(title: String, help: String?, range: ClosedRange<Int>,
		             get: () -> Int, set: (Int) -> Void)
		case text(title: String, help: String?, get: () -> String, set: (String) -> Void)
		/// One of a fixed set, each with a label and the value it stands for.
		case choice(title: String, help: String?, options: [(label: String, value: String)],
		            get: () -> String, set: (String) -> Void)
		/// The same, with small symbol buttons beside it.
		///
		/// For the things somebody does *to* the list rather than with it —
		/// re-reading it, or opening the folder it comes from. Beside the
		/// control because that is what they are about; small because they are
		/// not the reason anybody opened this page.
		case choiceWithActions(
			title: String, help: String?, options: [(label: String, value: String)],
			get: () -> String, set: (String) -> Void,
			actions: [(symbol: String, help: String, action: () -> Void)]
		)
		case button(title: String, label: String, action: () -> Void)
		/// Settings that only mean anything together, shown in a card of their
		/// own. The rows are inside it rather than following it: a group that
		/// only marks a beginning has no end, and swallows whatever comes next.
		indirect case group(title: String, help: String?, rows: [Row])
	}

	let paneTitle: String
	let paneSymbol: String
	private let rows: [Row]
	/// Controls that must refresh when settings change elsewhere (e.g. Reset).
	private var refreshHandlers: [() -> Void] = []

	init(title: String, symbol: String, rows: [Row]) {
		self.paneTitle = title
		self.paneSymbol = symbol
		self.rows = rows
		super.init(nibName: nil, bundle: nil)
		self.title = title
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func loadView() {
		let grid = NSGridView()
		grid.rowSpacing = 14
		grid.columnSpacing = 12

		for row in flattened(rows) {
			let (label, control, help) = makeRow(row)
			let labelField = NSTextField(labelWithString: label.isEmpty ? "" : label + ":")
			labelField.alignment = .right

			let stack = NSStackView(views: [control])
			stack.orientation = .vertical
			stack.alignment = .leading
			stack.spacing = 2
			if let help {
				let helpField = NSTextField(labelWithString: help)
				helpField.font = .systemFont(ofSize: 11)
				helpField.textColor = .secondaryLabelColor
				stack.addArrangedSubview(helpField)
			}

			grid.addRow(with: [labelField, stack])
		}

		// Only valid once rows exist — a grid has no columns before that, and
		// asking for column 0 on an empty grid raises an NSRangeException.
		if grid.numberOfColumns > 0 {
			grid.column(at: 0).xPlacement = .trailing
		}

		let container = NSView()
		container.addSubview(grid)
		grid.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
			grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
			grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
			grid.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24),
		])
		view = container

		NotificationCenter.default.addObserver(
			forName: .abydosSettingsChanged,
			object: nil,
			queue: .main
		) { [weak self] _ in
			// Reset restores defaults behind the controls' backs.
			self?.refreshHandlers.forEach { $0() }
		}
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	// MARK: - Row construction

	/// A group's heading followed by the settings inside it.
	private func flattened(_ rows: [Row]) -> [Row] {
		rows.flatMap { row -> [Row] in
			guard case let .group(title, help, inside) = row else { return [row] }
			return [.group(title: title, help: help, rows: [])] + inside
		}
	}

	private func makeRow(_ row: Row) -> (String, NSView, String?) {
		switch row {
		case let .group(title, help, _):
			// The window's own settings list has no cards to group inside, so a
			// group is a labelled gap.
			let label = NSTextField(labelWithString: title.uppercased())
			label.font = Theme.current.uiFont(10, weight: .semibold)
			label.textColor = Theme.current.gitIgnored
			return ("", label, help)

		case let .toggle(title, help, get, set, isEnabled):
			let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
			button.state = get() ? .on : .off
			button.isEnabled = isEnabled?() ?? true
			button.onAction = {
				set(button.state == .on)
				// One switch can decide another's fate — turning tmux's tabs
				// off leaves nothing for its status bar setting to be about —
				// so every control re-reads itself after any of them changes.
				NotificationCenter.default.post(name: .abydosSettingsChanged, object: nil)
			}
			refreshHandlers.append {
				button.state = get() ? .on : .off
				button.isEnabled = isEnabled?() ?? true
			}
			return (title, button, help)

		case let .slider(title, help, range, step, format, get, set):
			let value = NSTextField(labelWithString: format(get()))
			value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

			let slider = NSSlider(value: get(), minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
			slider.numberOfTickMarks = Int((range.upperBound - range.lowerBound) / step) + 1
			slider.allowsTickMarkValuesOnly = true
			slider.controlSize = .small
			slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
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
			stack.spacing = 10
			return (title, stack, help)

		case let .stepper(title, help, range, get, set):
			let field = NSTextField(string: "\(get())")
			field.alignment = .right
			field.widthAnchor.constraint(equalToConstant: 46).isActive = true

			let stepper = NSStepper()
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
			stack.spacing = 4
			return (title, stack, help)

		case let .text(title, help, get, set):
			let field = NSTextField(string: get())
			field.widthAnchor.constraint(equalToConstant: 280).isActive = true
			field.onAction = { set(field.stringValue) }
			refreshHandlers.append { field.stringValue = get() }
			return (title, field, help)

		case let .choice(title, help, options, get, set):
			let popUp = NSPopUpButton()
			popUp.addItems(withTitles: options.map(\.label))
			popUp.widthAnchor.constraint(equalToConstant: 200).isActive = true

			func select(_ value: String) {
				let index = options.firstIndex { $0.value == value } ?? 0
				popUp.selectItem(at: index)
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
			let (_, control, _) = makeRow(
				.choice(title: title, help: help, options: options, get: get, set: set)
			)
			let stack = NSStackView(views: [control] + actions.map { item in
				let button = NSButton(
					image: NSImage(
						systemSymbolName: item.symbol, accessibilityDescription: item.help
					) ?? NSImage(),
					target: nil, action: nil
				)
				button.bezelStyle = .rounded
				button.toolTip = item.help
				button.onAction = item.action
				return button
			})
			stack.orientation = .horizontal
			stack.spacing = 6
			return (title, stack, help)

		case let .button(title, label, action):
			let button = NSButton(title: label, target: nil, action: nil)
			button.bezelStyle = .rounded
			button.onAction = action
			return (title, button, nil)
		}
	}

	// MARK: - Somebody's own schemes

	/// Reads the scheme files again, and repaints what they describe.
	///
	/// A scheme is not edited often enough to be worth watching the folder all
	/// day, so this is the moment somebody says they have changed one. Three
	/// things have to happen together, and the middle one is the one that was
	/// missing when this was only `reload()`: the library re-reads, the list of
	/// themes is rebuilt so a new file appears in it, and the palette is taken
	/// again so an edited colour lands on the window that is already open.
	static func reloadSchemes() {
		let library = SchemeLibrary.shared
		library.reload()
		NotificationCenter.default.post(name: .abydosSettingsRowsChanged, object: nil)
		NotificationCenter.default.post(name: .abydosSettingsChanged, object: nil)

		// Said now rather than only in the log. The reload is a moment somebody
		// chose, which is what makes this the one point where a refused file can
		// be reported without a message appearing and clearing while they type.
		if let problem = library.problems.first {
			Toast.post(
				"A scheme was not read",
				detail: library.problems.count > 1
					? "\(problem) — and \(library.problems.count - 1) more, in the log."
					: problem
			)
		}
	}

	/// Opens the folder somebody's own schemes live in.
	///
	/// Made first if it is not there: somebody who has never written one has no
	/// folder, and a button that opens nothing is a bug report.
	static func revealSchemes() {
		let folder = SchemeLibrary.personalDirectory
		try? FileManager.default.createDirectory(
			at: folder, withIntermediateDirectories: true
		)
		NSWorkspace.shared.open(folder)
	}
}

// MARK: - Closure-based control actions

/// Lets controls carry their action inline instead of needing a selector and a
/// separate target object per row.
private final class ActionTrampoline: NSObject {
	let handler: () -> Void
	init(_ handler: @escaping () -> Void) { self.handler = handler }
	@objc func fire() { handler() }
}

private var trampolineKey: UInt8 = 0

extension NSControl {
	var onAction: (() -> Void)? {
		get { (objc_getAssociatedObject(self, &trampolineKey) as? ActionTrampoline)?.handler }
		set {
			guard let newValue else { return }
			let trampoline = ActionTrampoline(newValue)
			objc_setAssociatedObject(self, &trampolineKey, trampoline, .OBJC_ASSOCIATION_RETAIN)
			target = trampoline
			action = #selector(ActionTrampoline.fire)
		}
	}
}


/// The sections settings are grouped into.
///
/// Named once, so the page in the editor and the window behind ⌘, are the same
/// set of settings in the same order rather than two lists that drift.
enum SettingsSections {
	struct Section {
		let title: String
		let symbol: String
		let rows: () -> [SettingsPaneController.Row]
		/// Pages that belong under this one. Two levels is all this needs and
		/// all it allows: a page with a page under it is a place to look, and a
		/// tree deeper than that is a place to get lost in.
		let children: [Section]

		init(
			title: String,
			symbol: String,
			rows: @escaping () -> [SettingsPaneController.Row],
			children: [Section] = []
		) {
			self.title = title
			self.symbol = symbol
			self.rows = rows
			self.children = children
		}
	}

	/// Every page in the order they are shown, each with how deep it sits.
	static var flattened: [(section: Section, depth: Int)] {
		all.flatMap { [($0, 0)] + $0.children.map { child in (child, 1) } }
	}

	/// Reads back what a row *says*, found by page and by part of its title.
	///
	/// **Because a help text is a claim, and claims are what get reported.**
	/// "Hide tmux's own status bar" said nothing else was harmed and the
	/// session being used lost its status line — true clause by clause, wrong
	/// in what it left somebody believing, and unreachable from any run: every
	/// verb here sets values or photographs the page, and a sentence below the
	/// fold is in neither. This prints the words, so the next report about what
	/// a setting claims can be answered against the build rather than against
	/// the source somebody happens to be reading.
	static func says(_ said: String) -> String {
		let halves = said.split(separator: "/", maxSplits: 1).map(String.init)
		guard halves.count == 2 else { return "cannot read \(said) — expected Page/Row" }
		guard let section = flattened.first(where: { $0.section.title == halves[0] })?.section
		else { return "no settings page called \(halves[0])" }

		let found = words(in: section.rows(), matching: halves[1])
		guard !found.isEmpty else { return "no row matching \(halves[1]) on \(halves[0])" }
		return found.map {
			"\(halves[0]) ▸ \($0.title)\n    \($0.help ?? "(no help)")"
		}.joined(separator: "\n")
	}

	/// The title and help of every row whose title contains `needle`, walking
	/// into groups, which is where half the tmux rows live.
	private static func words(
		in rows: [SettingsPaneController.Row], matching needle: String
	) -> [(title: String, help: String?)] {
		rows.flatMap { row -> [(title: String, help: String?)] in
			switch row {
			case let .toggle(title, help, _, _, _),
			     let .slider(title, help, _, _, _, _, _),
			     let .stepper(title, help, _, _, _),
			     let .text(title, help, _, _),
			     let .choice(title, help, _, _, _),
			     let .choiceWithActions(title, help, _, _, _, _):
				return title.localizedCaseInsensitiveContains(needle) ? [(title, help)] : []
			case let .button(title, label, _):
				return title.localizedCaseInsensitiveContains(needle) ? [(title, label)] : []
			case let .group(title, help, rows):
				let inside = words(in: rows, matching: needle)
				return title.localizedCaseInsensitiveContains(needle)
					? [(title, help)] + inside
					: inside
			}
		}
	}

	/// Sets one row's value, found by page and title, and says what it did.
	///
	/// For driving a preference change from the command line, and it goes through
	/// the row's own `set` — the very closure the control calls — rather than
	/// writing to `UserDefaults` beside it. That is the point rather than
	/// tidiness: a value written into the defaults from outside changes the
	/// stored answer and notifies nobody, which is the state 0460 was reported
	/// *from*. What has to be exercised is a preference changing while the app is
	/// running and something reacting to it.
	static func choose(_ said: String) -> String {
		guard let slash = said.firstIndex(of: "/"),
		      let equals = said[slash...].firstIndex(of: "=")
		else { return "cannot read \(said) — expected Page/Row=value" }
		let page = String(said[..<slash])
		let title = String(said[said.index(after: slash)..<equals])
		let value = String(said[said.index(after: equals)...])

		guard let section = flattened.first(where: { $0.section.title == page })?.section else {
			return "no settings page called \(page)"
		}
		for row in section.rows() {
			switch row {
			case let .choice(rowTitle, _, _, _, set) where rowTitle == title,
			     let .choiceWithActions(rowTitle, _, _, _, set, _) where rowTitle == title,
			     let .text(rowTitle, _, _, set) where rowTitle == title:
				set(value)
				return "\(page) ▸ \(title) = \(value)"
			case let .toggle(rowTitle, _, _, set, _) where rowTitle == title:
				set(value == "true" || value == "on")
				return "\(page) ▸ \(title) = \(value)"
			default:
				continue
			}
		}
		return "no row called \(title) on \(page)"
	}

	static let all: [Section] = [
		// What the app looks like, first and in one place. It used to be split
		// between the editor's page and the terminal's, which is how somebody
		// ended up with a warm amber editor beside a deep blue terminal without
		// ever choosing that.
		Section(title: "Appearance", symbol: "paintpalette", rows: SettingsPaneController.appearanceRows),
		Section(title: "Terminal", symbol: "terminal", rows: SettingsPaneController.terminalRows),
		Section(title: "Editor", symbol: "textformat", rows: SettingsPaneController.editorRows),
		Section(title: "Saving", symbol: "square.and.arrow.down", rows: SettingsPaneController.savingRows),
		Section(title: "Navigator", symbol: "folder", rows: SettingsPaneController.navigatorRows),
		Section(title: "Git", symbol: "arrow.trianglehead.branch", rows: SettingsPaneController.gitRows),
		Section(title: "Agent", symbol: "sparkles", rows: SettingsPaneController.agentRows),
		Section(title: "Trust", symbol: "hand.raised", rows: SettingsPaneController.trustRows),
		Section(title: "System", symbol: "macwindow.on.rectangle", rows: SettingsPaneController.systemRows),
		Section(
			title: "Tools",
			symbol: "shippingbox",
			rows: SettingsPaneController.toolRows,
			// One page per tool rather than one page of every tool. The list
			// only grows — six language servers, a renderer, and whatever comes
			// next — and a page somebody has to scroll past six things to reach
			// the seventh is a page they stop reading.
			children: [
				// First among the children, because it is the question that comes
				// before theirs: which server answers for a language at all, and
				// only then where that server comes from.
				Section(
					title: "Language servers",
					symbol: "text.book.closed",
					rows: SettingsPaneController.languageServerRows
				),
			] + ToolImageCatalogue.tools.map { tool in
				Section(
					title: tool.title,
					symbol: "shippingbox",
					rows: { SettingsPaneController.rows(for: tool) }
				)
			}
		),
	]
}
