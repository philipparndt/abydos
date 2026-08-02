import AppKit
import IdeaiKit

/// The preferences window (⌘,).
///
/// Uses `NSTabViewController` in toolbar style, which is the standard macOS
/// preferences shape and gets the segmented toolbar, resizing, and tab
/// switching for free.
final class SettingsWindowController: NSWindowController {
	static let shared = SettingsWindowController()

	private init() {
		let tabController = NSTabViewController()
		tabController.tabStyle = .toolbar

		let editor = SettingsPaneController(
			title: "Editor",
			symbol: "textformat",
			rows: SettingsPaneController.editorRows()
		)
		let saving = SettingsPaneController(
			title: "Saving",
			symbol: "square.and.arrow.down",
			rows: SettingsPaneController.savingRows()
		)
		let navigator = SettingsPaneController(
			title: "Navigator",
			symbol: "folder",
			rows: SettingsPaneController.navigatorRows()
		)

		for pane in [editor, saving, navigator] {
			let item = NSTabViewItem(viewController: pane)
			item.label = pane.paneTitle
			item.image = NSImage(systemSymbolName: pane.paneSymbol, accessibilityDescription: pane.paneTitle)
			tabController.addTabViewItem(item)
		}

		let window = NSWindow(contentViewController: tabController)
		window.title = "Settings"
		window.styleMask = [.titled, .closable]
		window.setContentSize(NSSize(width: 520, height: 300))
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
	enum Row {
		case toggle(title: String, help: String?, get: () -> Bool, set: (Bool) -> Void)
		case slider(title: String, help: String?, range: ClosedRange<Double>, step: Double,
		            format: (Double) -> String, get: () -> Double, set: (Double) -> Void)
		case stepper(title: String, help: String?, range: ClosedRange<Int>,
		             get: () -> Int, set: (Int) -> Void)
		case text(title: String, help: String?, get: () -> String, set: (String) -> Void)
		/// One of a fixed set, each with a label and the value it stands for.
		case choice(title: String, help: String?, options: [(label: String, value: String)],
		            get: () -> String, set: (String) -> Void)
		case button(title: String, label: String, action: () -> Void)
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

		for row in rows {
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
			forName: .ideaiSettingsChanged,
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

	private func makeRow(_ row: Row) -> (String, NSView, String?) {
		switch row {
		case let .toggle(title, help, get, set):
			let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
			button.state = get() ? .on : .off
			button.onAction = { set(button.state == .on) }
			refreshHandlers.append { button.state = get() ? .on : .off }
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

		case let .button(title, label, action):
			let button = NSButton(title: label, target: nil, action: nil)
			button.bezelStyle = .rounded
			button.onAction = action
			return (title, button, nil)
		}
	}

	// MARK: - Pane definitions

	static func editorRows() -> [Row] {
		[
			.toggle(
				title: "Show problems beside the line",
				help: "The message is written after the code, dimmed. Off, only the "
					+ "squiggle and the tooltip say what is wrong.",
				get: { Settings.shared.showsInlineDiagnostics },
				set: { Settings.shared.showsInlineDiagnostics = $0 }
			),
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
				title: "Font size",
				help: "Applies to the code editor.",
				range: 9...20, step: 0.5,
				format: { String(format: "%.1f pt", $0) },
				get: { Settings.shared.editorFontSize },
				set: { Settings.shared.editorFontSize = $0 }
			),
			.slider(
				title: "Line height",
				help: nil,
				range: 1.0...2.0, step: 0.1,
				format: { String(format: "%.1f×", $0) },
				get: { Settings.shared.editorLineHeight },
				set: { Settings.shared.editorLineHeight = $0 }
			),
			.toggle(
				title: "Word wrap",
				help: "Soft-wrap long lines instead of scrolling sideways (⌥⌘Z).",
				get: { Settings.shared.wordWrap },
				set: { Settings.shared.wordWrap = $0 }
			),
			.choice(
				title: "Terminal colours",
				help: "Blue is the palette Ghostty ships with. Dark matches the editor.",
				options: TerminalScheme.allCases.map { ($0.title, $0.rawValue) },
				get: { Settings.shared.terminalScheme },
				set: { Settings.shared.terminalScheme = $0 }
			),
			.choice(
				title: "Terminal bell",
				help: "VHS shakes the picture and splits its colours, like a worn tape. Needs GPU rendering.",
				options: [("Sound", "sound"), ("VHS", "vhs"), ("Ignore", "none")],
				get: { Settings.shared.terminalBellStyle },
				set: { Settings.shared.terminalBellStyle = $0 }
			),
			.toggle(
				title: "GPU terminal rendering",
				help: "Draw the terminal with Metal. Faster when a program repaints the whole screen; still new.",
				get: { Settings.shared.terminalGPURendering },
				set: { Settings.shared.terminalGPURendering = $0 }
			),
			.text(
				title: "Terminal font",
				help: "Leave empty to choose automatically. Powerline prompts need a Nerd Font.",
				get: { Settings.shared.terminalFontName },
				set: { Settings.shared.terminalFontName = $0.trimmingCharacters(in: .whitespaces) }
			),
			.stepper(
				title: "Tab width",
				help: "Columns a tab character advances to.",
				range: 1...16,
				get: { Settings.shared.tabWidth },
				set: { Settings.shared.tabWidth = $0 }
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
				help: "Also write when ideai goes to the background.",
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
