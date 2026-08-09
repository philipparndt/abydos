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
	static func describe(_ rows: [Row]) -> [String] {
		rows.map { row in
			switch row {
			case let .toggle(title, _, get, _, isEnabled):
				let state = get() ? "on " : "off"
				return "\(state) \(isEnabled?() ?? true ? "        " : "disabled") \(title)"
			case let .slider(title, _, _, _, _, _, _): return "        slider   \(title)"
			case let .stepper(title, _, _, _, _):      return "        stepper  \(title)"
			case let .text(title, _, _, _):            return "        text     \(title)"
			case let .choice(title, _, _, get, _):     return "\(get())  choice   \(title)"
			case let .choiceWithActions(title, _, _, get, _, actions):
				return "\(get())  choice   \(title) [\(actions.map(\.symbol).joined(separator: " "))]"
			case let .button(title, label, _):         return "        [\(label)] \(title)"
			case let .group(title, _, rows):
				return (["── \(title) ──"] + describe(rows).map { "  " + $0 }).joined(separator: "\nSETTING ")
			}
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

	// MARK: - Pane definitions

	/// How code is shown and how big everything is.
	/// What the app looks like: one page for the editor and the terminal
	/// together, since they are one thing to look at.
	static func appearanceRows() -> [Row] {
		[
			.group(title: "Theme", help: nil, rows: [
				.choiceWithActions(
					title: "Theme",
					help: "Abydos is this app's own, warm. Blue is the one it started with, "
						+ "and the palette most editors' dark themes are a version of. "
						+ "Your own go in ~/.config/abydos/schemes — the folder button opens it, "
						+ "and the arrows read it again.",
					options: Appearance.families.map { ($0.title, $0.id) },
					get: { Settings.shared.themeFamily },
					set: { Settings.shared.themeFamily = $0 },
					actions: [
						(
							symbol: "arrow.triangle.2.circlepath",
							help: "Read the schemes folder again",
							action: { reloadSchemes() }
						),
						(
							symbol: "folder",
							help: "Open the folder your own schemes live in",
							action: { revealSchemes() }
						),
					]
				),
				.choice(
					title: "Light or dark",
					help: "Each theme has both. Following the system switches between them "
						+ "without changing which theme it is.",
					options: Appearance.Mode.allCases.map { ($0.title, $0.rawValue) },
					get: { Settings.shared.appearanceMode },
					set: { Settings.shared.appearanceMode = $0 }
				),
				.choice(
					title: "Terminal colours",
					help: "Same as the theme uses the palette that belongs to it. Editor colours "
						+ "paints the terminal in the editor's own background and text instead, so "
						+ "the two panes are one surface. Blue is the palette Ghostty ships with. "
						+ "All of them have a light and a dark form.",
					options: [("Same as the theme", Appearance.followsEditor)]
						+ TerminalScheme.all.map { ($0.title, $0.id) },
					// Through the identifier, so a preference still holding what
					// "Editor colours" used to be called selects the right row.
					get: { Appearance.terminalSchemeIdentifier(for: Settings.shared.terminalScheme) },
					set: { Settings.shared.terminalScheme = $0 }
				),
			]),
			.group(title: "Size", help: nil, rows: [
				.slider(
					title: "UI zoom",
					help: "Scales the whole window. Also ⌘+ / ⌘− / ⌘0.",
					// Continuous here rather than the discrete keyboard steps, since a
					// slider invites fine adjustment.
					range: 0.75...2.0, step: 0.05,
					format: { String(format: "%.0f%%", $0 * 100) },
					get: { Settings.shared.uiScale },
					set: { Settings.shared.uiScale = $0 }
				),
				.slider(
					title: "Editor font size",
					help: nil,
					range: 9...20, step: 0.5,
					format: { String(format: "%.1f pt", $0) },
					get: { Settings.shared.editorFontSize },
					set: { Settings.shared.editorFontSize = $0 }
				),
				.slider(
					title: "Editor line height",
					help: nil,
					range: 1.0...2.0, step: 0.1,
					format: { String(format: "%.1f×", $0) },
					get: { Settings.shared.editorLineHeight },
					set: { Settings.shared.editorLineHeight = $0 }
				),
				.text(
					title: "Terminal font",
					help: "Leave empty to choose automatically. Powerline prompts need a Nerd Font.",
					get: { Settings.shared.terminalFontName },
					set: { Settings.shared.terminalFontName = $0.trimmingCharacters(in: .whitespaces) }
				),
				.toggle(
					title: "Ligatures",
					help: "Draws -> and != and =~ as one shape, in the editor and the terminal "
						+ "both. Needs a font that has them — JetBrains Mono, Fira Code, "
						+ "Cascadia and Iosevka all do.",
					get: { Settings.shared.fontLigatures },
					set: { Settings.shared.fontLigatures = $0 }
				),
			]),
		]
	}

	static func editorRows() -> [Row] {
		[
			.toggle(
				title: "Word wrap",
				help: "Soft-wrap long lines instead of scrolling sideways (⌥⌘Z).",
				get: { Settings.shared.wordWrap },
				set: { Settings.shared.wordWrap = $0 }
			),
			.stepper(
				title: "Tab width",
				help: "Columns a tab character advances to.",
				range: 1...16,
				get: { Settings.shared.tabWidth },
				set: { Settings.shared.tabWidth = $0 }
			),
			.toggle(
				title: "Show problems beside the line",
				help: "The message is written after the code, dimmed. Off, only the "
					+ "squiggle and the tooltip say what is wrong.",
				get: { Settings.shared.showsInlineDiagnostics },
				set: { Settings.shared.showsInlineDiagnostics = $0 }
			),
		]
	}

	/// The terminal's own look, and how it draws.
	static func terminalRows() -> [Row] {
		// Sections rather than one long list: what the terminal looks like,
		// what it does when a window opens, and the tmux switches that only
		// mean anything together.
		var sections: [Row] = [
			.group(title: "Bell and keys", help: "Colours and fonts are on the Appearance page.", rows: [
				.choice(
					title: "Terminal bell",
					help: "VHS shakes the picture and splits its colours, like a worn tape. "
						+ "Needs GPU rendering.",
					options: [("Sound", "sound"), ("VHS", "vhs"), ("Ignore", "none")],
					get: { Settings.shared.terminalBellStyle },
					set: { Settings.shared.terminalBellStyle = $0 }
				),
				.toggle(
					title: "Option sends Meta",
					help: "Off, so Option types what your keyboard says it does — on a German "
						+ "layout that is where the braces and brackets are. On, so ⌥B and ⌥F "
						+ "move by words instead.",
					get: { Settings.shared.terminalOptionAsMeta },
					set: { Settings.shared.terminalOptionAsMeta = $0 }
				),
				.toggle(
					title: "GPU terminal rendering",
					help: "Draw the terminal with Metal. Faster when a program repaints the whole "
						+ "screen; still new.",
					get: { Settings.shared.terminalGPURendering },
					set: { Settings.shared.terminalGPURendering = $0 }
				),
			]),
			.group(title: "Behaviour", help: nil, rows: [
				.choice(
					title: "Terminal when a window opens",
					help: "Closed, open at its usual height, or filling the window.",
					options: [
						(label: "Closed", value: "closed"),
						(label: "Open", value: "open"),
						(label: "Filling the window", value: "full"),
					],
					get: { Settings.shared.terminalAtStartup },
					set: { Settings.shared.terminalAtStartup = $0 }
				),
				.toggle(
					title: "Follow the terminal's project",
					help: "When the terminal moves into another project, the window opens it. "
						+ "New windows start this way; each window can still be switched by hand.",
					get: { Settings.shared.followsTerminalProject },
					set: { Settings.shared.followsTerminalProject = $0 }
				),
			]),
		]

		// Offered only where there is a tmux to attach to: a switch that can do
		// nothing is worse than no switch. In the order they depend on each
		// other, each greyed while the one above it is off.
		if Executables.locate("tmux") != nil {
			sections.append(.group(
				title: "tmux",
				help: "Each of these only means anything while the one above it is on.",
				rows: [
					.toggle(
						title: "Attach the first terminal to tmux",
						help: "One session per project, so reopening it comes back to the panes it "
							+ "was left with. Terminals opened afterwards are plain shells.",
						get: { Settings.shared.startsTmux },
						set: { Settings.shared.startsTmux = $0 }
					),
					.toggle(
						title: "Tabs are tmux's windows",
						help: "The strip shows the session's windows and switching a tab switches "
							+ "tmux. One terminal, one shell: changing tabs costs nothing.",
						get: { Settings.shared.strictTmux },
						// The status bar goes with it: leaving somebody with no
						// window list at all would be this switch quietly
						// breaking their tmux.
						set: { TmuxSettings.setTabsAreTmuxWindows($0) },
						isEnabled: { Settings.shared.startsTmux }
					),
					.toggle(
						title: "Hide tmux's own status bar",
						help: "Those tabs already show this session's windows, so tmux's bar is the "
							+ "same list twice. Set on the session as it is attached — nothing is "
							+ "written to ~/.tmux.conf, and other sessions keep their bar.",
						get: { TmuxSettings.wantsStatusBarHidden },
						set: { TmuxSettings.wantsStatusBarHidden = $0 },
						isEnabled: { TmuxSettings.tabsAreTmuxWindows }
					),
				]
			))
		}
		return sections
	}

	/// What Claude Code is allowed to do on your behalf.
	/// Tools that can come from a container image instead of from this machine.
	///
	/// One row per tool that supports it, rather than a table of arbitrary
	/// pairs: a settings page is for the things somebody actually sets, and a
	/// free-form map of tool names invites typing one that means nothing.
	static func toolRows() -> [Row] {
		[
			.choice(
				title: "Container runtime",
				help: "Where a tool that comes from an image is run. Apple's needs no daemon; "
					+ "docker needs its own running. Saying which means being told when it is "
					+ "missing, rather than quietly getting the other one. Each tool below "
					+ "chooses whether it comes from an image at all.",
				options: ContainerRuntime.Preference.allCases.map { ($0.title, $0.rawValue) },
				get: { Settings.shared.containerRuntime },
				set: { Settings.shared.containerRuntime = $0 }
			),
		]
	}

	/// One tool's page: where it comes from, and what an image has to do.
	///
	/// The requirement is spelled out beside the field, because an image that
	/// does not meet it fails as an empty pane and nothing on screen would say
	/// why.
	static func rows(for tool: ToolImageCatalogue.Tool) -> [Row] {
		[
			.choice(
				title: "\(tool.title) from",
				help: "Installed on this machine is used unless an image is chosen. "
					+ "A project naming its own in .abydos/tools.json overrides both.",
				options: ToolImageCatalogue.options(for: tool),
				get: {
					ToolImageCatalogue.selection(
						for: Settings.shared.toolImages[tool.key] ?? "", tool: tool
					)
				},
				set: { value in
					var images = Settings.shared.toolImages
					switch value {
					case ToolImageCatalogue.useInstalled:
						images[tool.key] = nil
					case ToolImageCatalogue.custom:
						// Keep whatever is in the field: choosing "custom" is
						// saying "the one I typed", not clearing it.
						if images[tool.key] == nil { images[tool.key] = "" }
					default:
						images[tool.key] = value
					}
					Settings.shared.toolImages = images
				}
			),
			.text(
				title: "Custom image",
				help: tool.requirement,
				get: { Settings.shared.toolImages[tool.key] ?? "" },
				set: { image in
					var images = Settings.shared.toolImages
					let wanted = image.trimmingCharacters(in: .whitespaces)
					images[tool.key] = wanted.isEmpty ? nil : wanted
					Settings.shared.toolImages = images
				}
			),
		]
	}

	static func agentRows() -> [Row] {
		[
			.choice(
				title: "What an agent may do",
				help: "A review or a fix runs Claude Code. Accepting edits keeps it from stopping "
					+ "to ask whether it may change the file it was asked to change.",
				options: [("Accept edits", "acceptEdits"), ("Ask", "ask"), ("Everything", "full")],
				get: { Settings.shared.agentPermissions },
				set: { Settings.shared.agentPermissions = $0 }
			),
		]
	}

	static func savingRows() -> [Row] {
		[
			.toggle(
				title: "Auto save",
				help: "Write changes to disk automatically after a pause in typing.",
				get: { Settings.shared.autoSaveEnabled },
				set: { Settings.shared.autoSaveEnabled = $0 }
			),
			.slider(
				title: "Delay",
				help: "Idle time before writing. Long, so file watchers are not set off mid-word; "
					+ "switching away and running both save regardless.",
				range: 1...60, step: 1,
				format: { String(format: "%.0f s", $0) },
				get: { Settings.shared.autoSaveDelay },
				set: { Settings.shared.autoSaveDelay = $0 }
			),
			.toggle(
				title: "Save on focus loss",
				help: "Also write when Abydos goes to the background.",
				get: { Settings.shared.saveOnFocusLoss },
				set: { Settings.shared.saveOnFocusLoss = $0 }
			),
		]
	}

	static func navigatorRows() -> [Row] {
		[
			.toggle(
				title: "Open projects in a new window",
				help: "Off, choosing another project changes this window. On, it opens beside it.",
				get: { Settings.shared.opensProjectsInNewWindow },
				set: { Settings.shared.opensProjectsInNewWindow = $0 }
			),
			.toggle(
				title: "Show hidden files",
				help: "Files and folders beginning with a dot.",
				get: { Settings.shared.showHiddenFiles },
				set: { Settings.shared.showHiddenFiles = $0 }
			),
			.text(
				title: "Excluded folders",
				help: "Comma-separated. Tinted as build output. Press Return to apply.",
				get: { Settings.shared.excludedDirectories.joined(separator: ", ") },
				set: { value in
					Settings.shared.excludedDirectories = value
						.components(separatedBy: ",")
						.map { $0.trimmingCharacters(in: .whitespaces) }
						.filter { !$0.isEmpty }
				}
			),
			.button(title: "", label: "Restore Defaults") {
				Settings.shared.resetToDefaults()
			},
		]
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
		Section(title: "Agent", symbol: "sparkles", rows: SettingsPaneController.agentRows),
		Section(
			title: "Tools",
			symbol: "shippingbox",
			rows: SettingsPaneController.toolRows,
			// One page per tool rather than one page of every tool. The list
			// only grows — six language servers, a renderer, and whatever comes
			// next — and a page somebody has to scroll past six things to reach
			// the seventh is a page they stop reading.
			children: ToolImageCatalogue.tools.map { tool in
				Section(
					title: tool.title,
					symbol: "shippingbox",
					rows: { SettingsPaneController.rows(for: tool) }
				)
			}
		),
	]
}
