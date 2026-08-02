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
	private var kindPopUp: NSPopUpButton!
	private var kindHint: NSTextField!
	private var contextPopUp: NSPopUpButton!
	private var namespaceInput: NSTextField!
	private var kubeconfigInput: NSTextField!
	private var allowedInput: NSTextField!
	/// A row of the form, kept so it can be collapsed.
	@MainActor
	private struct Row {
		let label: NSTextField
		let field: NSView
		let top: NSLayoutConstraint
		let gap: NSLayoutConstraint
		let height: NSLayoutConstraint
		let naturalHeight: CGFloat

		func setVisible(_ visible: Bool) {
			label.isHidden = !visible
			field.isHidden = !visible
			top.constant = visible ? 14 : 0
			gap.constant = visible ? 5 : 0
			height.constant = visible ? naturalHeight : 0
		}
	}

	/// The rows only a cluster configuration needs.
	private var clusterRows: [Row] = []
	private var contexts: [String] = []
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
		///
		/// The pieces are kept so a row can be collapsed rather than merely
		/// hidden: a hidden view still holds its place, and a dialog with a
		/// hole in the middle looks broken.
		@discardableResult
		func row(_ text: String, _ field: NSView, height: CGFloat) -> Row {
			let label = caption(text)
			for view in [label, field] {
				view.translatesAutoresizingMaskIntoConstraints = false
				content.addSubview(view)
				NSLayoutConstraint.activate([
					view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
					view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
				])
			}
			let top = label.topAnchor.constraint(
				equalTo: previous?.bottomAnchor ?? content.topAnchor,
				constant: previous == nil ? 18 : 14
			)
			let gap = field.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 5)
			let tall = field.heightAnchor.constraint(equalToConstant: height)
			NSLayoutConstraint.activate([top, gap, tall])
			previous = field

			return Row(label: label, field: field, top: top, gap: gap, height: tall, naturalHeight: height)
		}

		nameInput = input(original.name)
		programInput = input(original.program, monospaced: true)
		argumentsInput = input(ArgumentLine.join(original.arguments), monospaced: true)
		directoryInput = input(original.workingDirectory, monospaced: true)

		// What this starts, said in the terms somebody chooses between rather
		// than the ones the file stores.
		kindPopUp = NSPopUpButton()
		kindPopUp.controlSize = .regular
		kindPopUp.font = Theme.current.uiFont(12)
		kindPopUp.addItems(withTitles: LaunchConfiguration.Kind.allCases.map(\.rawValue))
		kindPopUp.selectItem(withTitle: original.kind.rawValue)
		kindPopUp.target = self
		kindPopUp.action = #selector(kindChanged)

		row("Name", nameInput, height: 24)
		row("Type", kindPopUp, height: 24)

		kindHint = caption(original.kind.explanation)
		kindHint.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(kindHint)
		NSLayoutConstraint.activate([
			kindHint.topAnchor.constraint(equalTo: kindPopUp.bottomAnchor, constant: 4),
			kindHint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
			kindHint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
		])
		previous = kindHint

		row(original.type == "go" ? "Package" : "Program", programInput, height: 24)
		row("Arguments", argumentsInput, height: 24)
		row("Working directory", directoryInput, height: 24)

		// Where the cluster is. Empty context means whichever kubectl would
		// use, which is what somebody who has one cluster expects.
		let settings = original.devPod ?? LaunchConfiguration.DevPodSettings()
		contextPopUp = NSPopUpButton()
		contextPopUp.controlSize = .regular
		contextPopUp.font = Theme.current.uiFont(12)
		contextPopUp.addItem(withTitle: "Current context")
		if !settings.followsCurrentContext { contextPopUp.addItem(withTitle: settings.context) }
		contextPopUp.selectItem(at: settings.followsCurrentContext ? 0 : 1)

		namespaceInput = input(settings.namespace, monospaced: true)
		namespaceInput.placeholderString = "Every namespace"
		kubeconfigInput = input(settings.kubeconfig, monospaced: true)
		kubeconfigInput.placeholderString = "~/.kube/config"
		allowedInput = input(settings.allowedContexts, monospaced: true)
		allowedInput.placeholderString = "*-local, k3c-*"
		allowedInput.toolTip = "Contexts this may run on. Empty allows any."


		clusterRows = [
			row("Cluster", contextPopUp, height: 24),
			row("Only run on contexts matching", allowedInput, height: 24),
			row("Namespace", namespaceInput, height: 24),
			row("Kubeconfig", kubeconfigInput, height: 24),
		]
		updateKindRows()
		loadContexts(selecting: settings.context)

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

	@objc private func kindChanged() {
		let kind = LaunchConfiguration.Kind.allCases[max(0, kindPopUp.indexOfSelectedItem)]
		kindHint.stringValue = kind.explanation
		updateKindRows()
	}

	private func updateKindRows() {
		let showsCluster = LaunchConfiguration.Kind
			.allCases[max(0, kindPopUp.indexOfSelectedItem)] == .devPod
		for row in clusterRows { row.setVisible(showsCluster) }

		// The panel is as tall as what it shows.
		guard let window, let content = window.contentView else { return }
		content.layoutSubtreeIfNeeded()
		let height = content.fittingSize.height
		guard height > 0, abs(window.frame.height - height) > 1 else { return }
		var frame = window.frame
		frame.origin.y += frame.height - height
		frame.size.height = height
		window.setFrame(frame, display: true, animate: false)
	}

	/// Fills the cluster list from kubectl, keeping whatever was already set.
	private func loadContexts(selecting current: String) {
		guard Kubernetes.isAvailable else { return }
		Task { @MainActor in
			contexts = await Kubernetes.contexts()
			guard !contexts.isEmpty else { return }

			contextPopUp.removeAllItems()
			contextPopUp.addItem(withTitle: "Current context")
			contextPopUp.addItems(withTitles: contexts)
			if let index = contexts.firstIndex(of: current) {
				contextPopUp.selectItem(at: index + 1)
			} else {
				contextPopUp.selectItem(at: 0)
			}
		}
	}

	private var chosenContext: String {
		let index = contextPopUp.indexOfSelectedItem - 1
		return contexts.indices.contains(index) ? contexts[index] : ""
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
		updated.kind = LaunchConfiguration.Kind.allCases[max(0, kindPopUp.indexOfSelectedItem)]
		if updated.kind == .devPod {
			updated.devPod = LaunchConfiguration.DevPodSettings(
				context: chosenContext,
				namespace: namespaceInput.stringValue.trimmingCharacters(in: .whitespaces),
				pod: original.devPod?.pod ?? "",
				kubeconfig: kubeconfigInput.stringValue.trimmingCharacters(in: .whitespaces),
				allowedContexts: allowedInput.stringValue.trimmingCharacters(in: .whitespaces)
			)
		}
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
