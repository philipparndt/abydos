import AppKit
import IdeaiKit

/// The parts of a launch configuration worth changing by hand.
///
/// A panel of the app's own rather than a system alert: an alert draws its
/// chrome in the system's colours, and a light box of controls in front of a
/// dark window looks like it belongs to some other program. Everything the
/// entry carries that is not shown here — including keys this app knows
/// nothing about — is left exactly as it was found.
@MainActor
final class LaunchConfigurationEditor: NSObject {
	/// The edited configuration, or nil if it is to be deleted.
	var onApply: ((LaunchConfiguration?) -> Void)?

	private var window: NSPanel?
	private let original: LaunchConfiguration
	private let isNew: Bool

	private var nameInput: NSTextField!
	private var programInput: NSTextField!
	private var argumentsInput: NSTextField!
	private var directoryInput: NSTextField!
	private var environmentView: NSTextView!

	init(configuration: LaunchConfiguration, isNew: Bool) {
		self.original = configuration
		self.isNew = isNew
		super.init()
	}

	func show(over parent: NSWindow?) {
		guard let parent else { return }
		let window = makeWindow()
		self.window = window

		let frame = parent.frame
		let size = window.frame.size
		window.setFrameOrigin(NSPoint(
			x: frame.midX - size.width / 2,
			// Above centre, where a dialog is looked for, but clear of the
			// titlebar the panel would otherwise sit under.
			y: frame.midY - size.height / 2 + frame.height * 0.08
		))

		parent.addChildWindow(window, ordered: .above)
		if NSApp.isActive {
			window.makeKeyAndOrderFront(nil)
			window.makeFirstResponder(nameInput)
		} else {
			window.orderFront(nil)
		}
	}

	private func close() {
		guard let window else { return }
		window.parent?.removeChildWindow(window)
		window.orderOut(nil)
		self.window = nil
	}

	// MARK: - Building

	private func makeWindow() -> NSPanel {
		let content = ColoredView(color: Theme.current.sidebarBackground)
		var previous: NSView?

		func caption(_ text: String) -> NSTextField {
			let label = NSTextField(labelWithString: text)
			label.font = Theme.current.uiFont(10.5)
			label.textColor = Theme.current.gitIgnored
			return label
		}

		func input(_ value: String, monospaced: Bool = false) -> NSTextField {
			let field = NSTextField(string: value)
			field.font = monospaced
				? Theme.terminalFont(size: Theme.current.fontSize - 1)
				: Theme.current.uiFont(12)
			field.textColor = Theme.current.sidebarText
			field.backgroundColor = Theme.current.editorBackground
			field.drawsBackground = true
			field.isBordered = false
			field.focusRingType = .none
			field.bezelStyle = .roundedBezel
			field.isBezeled = true
			return field
		}

		/// Stacks a captioned field below whatever came before it.
		func row(_ text: String, _ field: NSView, height: CGFloat) {
			let label = caption(text)
			for view in [label, field] {
				view.translatesAutoresizingMaskIntoConstraints = false
				content.addSubview(view)
				NSLayoutConstraint.activate([
					view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
					view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
				])
			}
			NSLayoutConstraint.activate([
				label.topAnchor.constraint(
					equalTo: previous?.bottomAnchor ?? content.topAnchor,
					constant: previous == nil ? 18 : 14
				),
				field.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 5),
				field.heightAnchor.constraint(equalToConstant: height),
			])
			previous = field
		}

		nameInput = input(original.name)
		programInput = input(original.program, monospaced: true)
		argumentsInput = input(ArgumentLine.join(original.arguments), monospaced: true)
		directoryInput = input(original.workingDirectory, monospaced: true)

		row("Name", nameInput, height: 24)
		row(original.type == "go" ? "Package" : "Program", programInput, height: 24)
		row("Arguments", argumentsInput, height: 24)
		row("Working directory", directoryInput, height: 24)

		// Environment as `KEY=value` lines: it is how everybody writes them, and
		// a table with two rows in it would be worse to use.
		environmentView = NSTextView()
		environmentView.string = EnvironmentLines.format(original.environment)
		environmentView.font = Theme.terminalFont(size: Theme.current.fontSize - 1)
		environmentView.textColor = Theme.current.sidebarText
		environmentView.backgroundColor = Theme.current.editorBackground
		environmentView.insertionPointColor = Theme.current.sidebarText
		environmentView.isRichText = false
		environmentView.isAutomaticQuoteSubstitutionEnabled = false
		environmentView.textContainerInset = NSSize(width: 4, height: 4)

		let environmentScroll = NSScrollView()
		environmentScroll.documentView = environmentView
		environmentScroll.hasVerticalScroller = true
		environmentScroll.drawsBackground = true
		environmentScroll.backgroundColor = Theme.current.editorBackground
		environmentScroll.borderType = .noBorder
		environmentScroll.wantsLayer = true
		environmentScroll.layer?.cornerRadius = 5
		row("Environment, one KEY=value per line", environmentScroll, height: 74)

		let hint = caption("${workspaceFolder} stands for the project directory.")
		let buttons = makeButtons()
		for view in [hint, buttons] {
			view.translatesAutoresizingMaskIntoConstraints = false
			content.addSubview(view)
		}
		NSLayoutConstraint.activate([
			hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
			hint.topAnchor.constraint(equalTo: previous!.bottomAnchor, constant: 14),

			buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
			buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
			buttons.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 14),
			buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
		])

		let window = EditorPanel(
			contentRect: NSRect(x: 0, y: 0, width: 460, height: 10),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: true
		)
		window.title = isNew ? "New Configuration" : "Edit “\(original.name)”"
		window.backgroundColor = Theme.current.sidebarBackground
		window.contentView = content
		window.onCancel = { [weak self] in self?.cancel() }

		// Sized to whatever the constraints came out at, so a longer caption
		// cannot clip the row below it.
		let height = content.fittingSize.height
		window.setContentSize(NSSize(width: 460, height: height))
		return window
	}

	private func makeButtons() -> NSView {
		let container = NSView()

		let save = NSButton(title: isNew ? "Create" : "Apply", target: self, action: #selector(apply))
		save.bezelStyle = .rounded
		save.keyEquivalent = "\r"

		let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
		cancel.bezelStyle = .rounded
		cancel.keyEquivalent = "\u{1b}"

		for button in [save, cancel] {
			button.translatesAutoresizingMaskIntoConstraints = false
			container.addSubview(button)
		}
		NSLayoutConstraint.activate([
			save.trailingAnchor.constraint(equalTo: container.trailingAnchor),
			save.topAnchor.constraint(equalTo: container.topAnchor),
			save.bottomAnchor.constraint(equalTo: container.bottomAnchor),

			cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -8),
			cancel.centerYAnchor.constraint(equalTo: save.centerYAnchor),
		])

		// Deleting is destructive and belongs away from the button the return
		// key presses.
		guard !isNew else { return container }
		let delete = NSButton(title: "Delete", target: self, action: #selector(deleteConfiguration))
		delete.bezelStyle = .rounded
		delete.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(delete)
		NSLayoutConstraint.activate([
			delete.leadingAnchor.constraint(equalTo: container.leadingAnchor),
			delete.centerYAnchor.constraint(equalTo: save.centerYAnchor),
		])
		return container
	}

	// MARK: - Actions

	@objc private func apply() {
		let name = nameInput.stringValue.trimmingCharacters(in: .whitespaces)
		// A configuration is found by its name, so an empty one would be
		// unreachable from the menu that lists them.
		guard !name.isEmpty else {
			window?.makeFirstResponder(nameInput)
			NSSound.beep()
			return
		}

		var updated = original
		updated.name = name
		updated.program = programInput.stringValue.trimmingCharacters(in: .whitespaces)
		updated.arguments = ArgumentLine.split(argumentsInput.stringValue)
		updated.workingDirectory = directoryInput.stringValue.trimmingCharacters(in: .whitespaces)
		updated.environment = EnvironmentLines.parse(environmentView.string)

		close()
		onApply?(updated)
	}

	@objc private func cancel() {
		close()
	}

	@objc private func deleteConfiguration() {
		close()
		onApply?(nil)
	}

	// MARK: - Testing

	func applyForTesting(name: String? = nil, arguments: String? = nil, environment: String? = nil) {
		if let name { nameInput.stringValue = name }
		if let arguments { argumentsInput.stringValue = arguments }
		if let environment { environmentView.string = environment }
		apply()
	}
}

/// Closes on escape, like every other dialog in the app.
private final class EditorPanel: NSPanel {
	var onCancel: (() -> Void)?
	override var canBecomeKey: Bool { true }

	override func close() {
		onCancel?()
	}

	override func cancelOperation(_ sender: Any?) {
		onCancel?()
	}
}
