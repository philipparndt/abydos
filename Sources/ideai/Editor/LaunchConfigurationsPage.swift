import AppKit
import IdeaiKit

/// The launch configurations, as a page in the editor.
///
/// Not a dialog. A configuration is edited while looking at the code it runs —
/// which package, which arguments, which file the service reads — and a modal
/// panel takes the project away for as long as it is open. As a tab it can be
/// left open, switched away from, and come back to.
///
/// The list on the left is the whole set, so moving between them is one click
/// rather than close-reopen-choose. Changes are written when a field is done
/// being edited, the way the rest of the app writes files.
@MainActor
final class LaunchConfigurationsPage: NSView {
	/// Writes a configuration. The second name is what it was called before,
	/// when a rename means the old file has to go.
	var onSave: ((LaunchConfiguration, String?) -> Void)?
	var onDelete: ((String) -> Void)?
	/// Starts what is on screen, so a change can be tried without leaving.
	var onStart: ((LaunchConfiguration, StartMode) -> Void)?

	/// The ways of starting a configuration.
	enum StartMode {
		case run, debug, profile, coverage
	}

	private var configurations: [LaunchConfiguration] = []
	private var selected: Int?
	/// What the selected configuration was called when it was loaded.
	private var originalName: String?
	private var root: URL?
	private var contexts: [String] = []

	private let list = NSTableView()
	private let form = NSStackView()
	private var fields: [String: NSTextField] = [:]
	private var kindPopUp: NSPopUpButton!
	private var contextPopUp: NSPopUpButton!
	private var environmentView: NSTextView!
	private var filesList: FileDropList!
	private var clusterSection: NSView!
	private var chartSection: NSView!
	private var secretsBox: NSButton!
	private var installBox: NSButton!
	private var emptyLabel: NSTextField!
	/// What is wrong with the configuration being edited, if anything.
	private var warningsStack: NSStackView!
	private var headerTitle: NSTextField!
	private var scroll: NSScrollView!

	override init(frame: NSRect) {
		super.init(frame: frame)
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: - Contents

	func load(_ configurations: [LaunchConfiguration], root: URL, selecting name: String?) {
		self.configurations = configurations
		self.root = root

		let index = configurations.firstIndex { $0.name == name } ?? (configurations.isEmpty ? nil : 0)
		list.reloadData()
		select(index)
	}

	/// The clusters this machine knows about, once kubectl has been asked.
	func setContexts(_ contexts: [String]) {
		self.contexts = contexts
		guard let index = selected, configurations.indices.contains(index) else { return }
		fillContexts(selecting: configurations[index].devPod?.context ?? "")
	}

	private func select(_ index: Int?) {
		commit()
		selected = index
		originalName = index.map { configurations[$0].name }

		if let index, configurations.indices.contains(index) {
			list.selectRowIndexes([index], byExtendingSelection: false)
			show(configurations[index])
		} else {
			list.deselectAll(nil)
			showNothing()
		}
	}

	// MARK: - Layout

	private func build() {
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor

		let sidebar = makeSidebar()
		scroll = NSScrollView()
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = false
		scroll.borderType = .noBorder

		form.orientation = .vertical
		form.alignment = .leading
		form.spacing = Theme.current.scaled(18)
		form.edgeInsets = NSEdgeInsets(
			top: Theme.current.scaled(24), left: Theme.current.scaled(28),
			bottom: Theme.current.scaled(32), right: Theme.current.scaled(28)
		)
		form.translatesAutoresizingMaskIntoConstraints = false

		let clip = FlippedView()
		clip.addSubview(form)
		scroll.documentView = clip
		clip.translatesAutoresizingMaskIntoConstraints = false

		emptyLabel = NSTextField(labelWithString: "No launch configurations yet.\nThe + below adds one.")
		emptyLabel.font = Theme.current.uiFont(12.5)
		emptyLabel.textColor = Theme.current.gitIgnored
		emptyLabel.alignment = .center
		emptyLabel.isHidden = true

		for view in [sidebar, scroll, emptyLabel] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}

		// A form is not a reason to make the editor area wider: the sidebar and
		// the navigator beside it were the size somebody chose, and opening a
		// page should not move them.
		for view in [sidebar, scroll] as [NSView] {
			view.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
			view.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
		}

		NSLayoutConstraint.activate([
			sidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
			sidebar.topAnchor.constraint(equalTo: topAnchor),
			sidebar.bottomAnchor.constraint(equalTo: bottomAnchor),
			sidebar.widthAnchor.constraint(equalToConstant: Theme.current.scaled(210)),

			scroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
			scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
			scroll.topAnchor.constraint(equalTo: topAnchor),
			scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

			clip.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
			clip.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
			clip.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),

			form.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
			form.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
			form.topAnchor.constraint(equalTo: clip.topAnchor),
			form.bottomAnchor.constraint(equalTo: clip.bottomAnchor),

			emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
			emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor, constant: -40),
		])

		buildForm()
	}

	private func makeSidebar() -> NSView {
		let background = ColoredView(color: Theme.current.sidebarBackground)

		list.headerView = nil
		list.backgroundColor = .clear
		list.selectionHighlightStyle = .regular
		list.rowSizeStyle = .custom
		list.rowHeight = Theme.current.scaled(26)
		list.intercellSpacing = .zero
		list.gridStyleMask = []
		list.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
		list.delegate = self
		list.dataSource = self
		list.target = self
		list.doubleAction = #selector(runSelected)

		let scroll = NSScrollView()
		scroll.documentView = list
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = false
		scroll.borderType = .noBorder

		let title = NSTextField(labelWithString: "Configurations")
		title.font = Theme.current.uiFont(11, weight: .semibold)
		title.textColor = Theme.current.gitIgnored

		let buttons = NSStackView(views: [
			toolButton("plus", "New configuration", #selector(addConfiguration)),
			toolButton("doc.on.doc", "Duplicate", #selector(duplicateConfiguration)),
			toolButton("trash", "Delete", #selector(deleteConfiguration)),
			NSView(),
		])
		buttons.orientation = .horizontal
		buttons.spacing = Theme.current.scaled(2)

		for view in [title, scroll, buttons] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			background.addSubview(view)
		}
		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: background.topAnchor, constant: Theme.current.scaled(14)),
			title.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Theme.current.scaled(14)),

			scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: Theme.current.scaled(8)),
			scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -Theme.current.scaled(4)),

			buttons.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Theme.current.scaled(8)),
			buttons.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Theme.current.scaled(8)),
			buttons.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Theme.current.scaled(10)),
			buttons.heightAnchor.constraint(equalToConstant: Theme.current.scaled(22)),
		])
		return background
	}

	private func toolButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
		let button = NSButton()
		button.bezelStyle = .texturedRounded
		button.isBordered = false
		button.image = Theme.symbol(symbol, size: 12 * Theme.current.scale, color: Theme.current.sidebarText)
		button.imagePosition = .imageOnly
		button.toolTip = tip
		button.target = self
		button.action = action
		button.widthAnchor.constraint(equalToConstant: Theme.current.scaled(24)).isActive = true
		return button
	}

	// MARK: - The form

	private func buildForm() {
		kindPopUp = popUp(LaunchConfiguration.Kind.allCases.map(\.rawValue), action: #selector(kindChanged))
		contextPopUp = popUp(["Current context"], action: #selector(fieldChanged))

		environmentView = NSTextView()
		environmentView.font = Theme.terminalFont(size: Theme.current.fontSize - 1)
		environmentView.textColor = Theme.current.sidebarText
		environmentView.backgroundColor = Theme.current.sidebarBackground
		environmentView.insertionPointColor = Theme.current.sidebarText
		environmentView.isRichText = false
		environmentView.isAutomaticQuoteSubstitutionEnabled = false
		environmentView.textContainerInset = NSSize(width: 6, height: 6)
		environmentView.delegate = self

		let environmentScroll = NSScrollView()
		environmentScroll.documentView = environmentView
		environmentScroll.hasVerticalScroller = true
		environmentScroll.drawsBackground = true
		environmentScroll.backgroundColor = Theme.current.sidebarBackground
		environmentScroll.borderType = .noBorder
		environmentScroll.wantsLayer = true
		environmentScroll.layer?.cornerRadius = 6
		environmentScroll.heightAnchor.constraint(equalToConstant: Theme.current.scaled(90)).isActive = true

		filesList = FileDropList()
		filesList.onChange = { [weak self] in self?.commit() }
		filesList.projectRoot = { [weak self] in self?.root }

		form.addArrangedSubview(makeHeader())

		warningsStack = NSStackView()
		warningsStack.orientation = .vertical
		warningsStack.alignment = .leading
		warningsStack.spacing = Theme.current.scaled(4)
		warningsStack.isHidden = true
		form.addArrangedSubview(warningsStack)

		form.addArrangedSubview(section("Target", rows: [
			field("Name", key: "name"),
			labelled("What it runs", kindPopUp),
			field("Package or program", key: "program", monospaced: true, chooses: .directory),
			field("Arguments", key: "arguments", monospaced: true),
			field("Working directory", key: "cwd", monospaced: true, chooses: .directory),
		]))

		form.addArrangedSubview(section("Environment", caption: "One KEY=value per line.", rows: [
			environmentScroll,
		]))

		clusterSection = section("Cluster", caption: "Where this runs when it does not run here.", rows: [
			labelled("Context", contextPopUp),
			field("Only run on contexts matching", key: "allowed", monospaced: true, placeholder: "*-local, k3c-*"),
			field("Namespace", key: "namespace", monospaced: true, placeholder: "ideai-dev"),
			field("Kubeconfig", key: "kubeconfig", monospaced: true, placeholder: "~/.kube/config"),
			field("Pod image", key: "image", monospaced: true, placeholder: DevPodImage.default),
			field("Service port", key: "port", monospaced: true, placeholder: "8080"),
			field(
				"Published at", key: "ingressHost", monospaced: true,
				placeholder: "lamarzocco.dev.example.com — empty for none"
			),
			labelled("Files to send", filesList),
		])
		form.addArrangedSubview(clusterSection)

		// A project with a chart of its own runs that chart, and one container
		// of it is put into development mode. Left empty, the development pod's
		// own chart is used instead.
		secretsBox = checkbox("The values files are encrypted (helm-secrets)")
		installBox = checkbox("Install the chart when the release is not there")
		chartSection = section(
			"Chart",
			caption: "The project's own chart: its values, its secrets, its neighbours.",
			rows: [
				field("Chart", key: "chart", monospaced: true, placeholder: "deploy/chart", chooses: .directory),
				field("Release", key: "release", monospaced: true, placeholder: "smarthome"),
				field(
					"Values files", key: "valueFiles", monospaced: true,
					placeholder: "deploy/values.yaml, deploy/values-dev.yaml"
				),
				field(
					"Container to replace", key: "container", monospaced: true,
					placeholder: "app — the one this configuration runs"
				),
				secretsBox,
				installBox,
			]
		)
		form.addArrangedSubview(chartSection)

		let hint = NSTextField(labelWithString: TemplatePath.variables
			.map { "\($0.name) — \($0.meaning)" }
			.joined(separator: "     "))
		hint.font = Theme.current.uiFont(10.5)
		hint.textColor = Theme.current.gitIgnored
		form.addArrangedSubview(hint)

		for view in form.arrangedSubviews {
			view.widthAnchor.constraint(
				equalTo: form.widthAnchor, constant: -Theme.current.scaled(56)
			).isActive = true
		}
	}

	/// The name of what is being edited, and the two things to do with it.
	///
	/// Run and debug are here because trying a change is the reason for making
	/// one, and going back to the titlebar to do it loses the page.
	private func makeHeader() -> NSView {
		headerTitle = NSTextField(labelWithString: "")
		headerTitle.font = Theme.current.uiFont(17, weight: .semibold)
		headerTitle.textColor = Theme.current.sidebarHeaderText
		headerTitle.lineBreakMode = .byTruncatingTail

		// All four here rather than behind a chevron: the titlebar is short of
		// room and this page is not, and this is the place where somebody is
		// deciding what a configuration should do.
		let stack = NSStackView(views: [
			headerTitle,
			NSView(),
			actionButton("play.fill", "Run", #selector(runSelected)),
			actionButton("ladybug.fill", "Debug", #selector(debugSelected)),
			actionButton("gauge.with.needle", "Profile", #selector(profileSelected)),
			actionButton("checkmark.seal", "Cover", #selector(coverSelected)),
		])
		stack.orientation = .horizontal
		stack.spacing = Theme.current.scaled(8)
		stack.alignment = .centerY
		return stack
	}

	private func actionButton(_ symbol: String, _ title: String, _ action: Selector) -> NSButton {
		let button = NSButton(title: " " + title, target: self, action: action)
		button.bezelStyle = .rounded
		button.image = Theme.symbol(symbol, size: 11 * Theme.current.scale, color: Theme.current.sidebarText)
		button.imagePosition = .imageLeading
		button.font = Theme.current.uiFont(12)
		return button
	}

	/// A titled group of rows, drawn as one panel.
	///
	/// Sections rather than one long list of fields: a configuration answers
	/// three separate questions — what to run, what it runs with, and where —
	/// and they are read one at a time.
	private func section(_ title: String, caption: String? = nil, rows: [NSView]) -> NSView {
		let heading = NSTextField(labelWithString: title.uppercased())
		heading.font = Theme.current.uiFont(10, weight: .semibold)
		heading.textColor = Theme.current.gitIgnored

		let card = ColoredView(color: Theme.current.sidebarBackground)
		card.wantsLayer = true
		card.layer?.cornerRadius = 8
		card.layer?.borderWidth = 1
		card.layer?.borderColor = Theme.current.separator.withAlphaComponent(0.6).cgColor

		let inner = NSStackView(views: rows)
		inner.orientation = .vertical
		inner.alignment = .leading
		inner.spacing = Theme.current.scaled(12)
		inner.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(inner)
		NSLayoutConstraint.activate([
			inner.topAnchor.constraint(equalTo: card.topAnchor, constant: Theme.current.scaled(14)),
			inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Theme.current.scaled(14)),
			inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Theme.current.scaled(16)),
			inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Theme.current.scaled(16)),
		])
		for row in rows {
			row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
		}

		let group = NSStackView(views: [heading, card])
		group.orientation = .vertical
		group.alignment = .leading
		group.spacing = Theme.current.scaled(7)

		// Wide enough to read and no wider: a text field the width of a big
		// display is harder to take in than one the width of a paragraph. The
		// cap is on the card alone — putting a maximum anywhere in the chain
		// that reaches the page would make the whole editor area refuse to be
		// wider than a form, and the split view would hand the difference to
		// the project tree.
		card.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true

		if let caption {
			let text = NSTextField(labelWithString: caption)
			text.font = Theme.current.uiFont(10.5)
			text.textColor = Theme.current.gitIgnored
			group.insertArrangedSubview(text, at: 1)
		}
		return group
	}

	private func field(
		_ label: String,
		key: String,
		monospaced: Bool = false,
		placeholder: String = "",
		chooses: FileChoice? = nil
	) -> NSView {
		let input = NSTextField()
		input.font = monospaced
			? Theme.terminalFont(size: Theme.current.fontSize - 1)
			: Theme.current.uiFont(12)
		input.textColor = Theme.current.sidebarText
		input.backgroundColor = Theme.current.editorBackground
		input.drawsBackground = true
		input.isBordered = false
		input.isBezeled = true
		input.bezelStyle = .roundedBezel
		input.focusRingType = .none
		input.placeholderString = placeholder
		input.delegate = self
		input.target = self
		input.action = #selector(fieldChanged)
		input.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
		input.cell?.isScrollable = true
		input.cell?.wraps = false
		fields[key] = input

		// A field that names a path gets a way to pick one, because the value
		// it wants is not the path a chooser returns: it is that path written
		// with a variable, so the configuration still means something on
		// somebody else's machine. Typing that from memory is the part nobody
		// should have to do.
		guard let chooses else { return labelled(label, input) }

		let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseFile(_:)))
		choose.font = Theme.current.uiFont(11)
		choose.bezelStyle = .rounded
		choose.identifier = NSUserInterfaceItemIdentifier(key)
		choosers[key] = chooses
		choose.setContentHuggingPriority(.required, for: .horizontal)

		let row = NSStackView(views: [input, choose])
		row.orientation = .horizontal
		row.spacing = Theme.current.scaled(6)
		input.heightAnchor.constraint(equalToConstant: Theme.current.scaled(24)).isActive = true
		return labelled(label, row)
	}

	/// What a field's chooser may pick.
	enum FileChoice {
		case file
		case directory
	}

	private var choosers: [String: FileChoice] = [:]

	@objc private func chooseFile(_ sender: NSButton) {
		guard let key = sender.identifier?.rawValue,
		      let field = fields[key],
		      let root,
		      let window
		else { return }

		let panel = NSOpenPanel()
		panel.canChooseFiles = choosers[key] != .directory
		panel.canChooseDirectories = choosers[key] != .file
		panel.allowsMultipleSelection = false
		// Where the field already points, so picking the file beside it is one
		// click rather than a walk from the project root.
		panel.directoryURL = TemplatePath.startingDirectory(for: field.stringValue, root: root)

		panel.beginSheetModal(for: window) { [weak self] response in
			guard response == .OK, let url = panel.url else { return }
			field.stringValue = TemplatePath.shareable(url.path, root: root)
			self?.commit()
			self?.refreshWarnings()
		}
	}

	private func checkbox(_ title: String) -> NSButton {
		let box = NSButton(checkboxWithTitle: title, target: self, action: #selector(fieldChanged))
		box.font = Theme.current.uiFont(11.5)
		box.contentTintColor = Theme.current.sidebarText
		return box
	}

	private func labelled(_ text: String, _ control: NSView) -> NSView {
		let label = NSTextField(labelWithString: text)
		label.font = Theme.current.uiFont(10.5)
		label.textColor = Theme.current.gitIgnored

		let stack = NSStackView(views: [label, control])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = Theme.current.scaled(4)
		control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		if control is NSTextField || control is NSPopUpButton {
			control.heightAnchor.constraint(equalToConstant: Theme.current.scaled(24)).isActive = true
		}
		return stack
	}

	private func popUp(_ titles: [String], action: Selector) -> NSPopUpButton {
		let button = NSPopUpButton()
		button.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
		button.font = Theme.current.uiFont(12)
		button.addItems(withTitles: titles)
		button.target = self
		button.action = action
		return button
	}

	// MARK: - Showing and collecting

	private func showNothing() {
		scroll.isHidden = true
		emptyLabel.isHidden = false
	}

	private func show(_ configuration: LaunchConfiguration) {
		scroll.isHidden = false
		emptyLabel.isHidden = true
		defer { refreshWarnings() }

		headerTitle.stringValue = configuration.name
		fields["name"]?.stringValue = configuration.name
		fields["program"]?.stringValue = configuration.program
		fields["arguments"]?.stringValue = ArgumentLine.join(configuration.arguments)
		fields["cwd"]?.stringValue = configuration.workingDirectory
		kindPopUp.selectItem(withTitle: configuration.kind.rawValue)
		environmentView.string = EnvironmentLines.format(configuration.environment)

		let settings = configuration.devPod ?? LaunchConfiguration.DevPodSettings()
		fields["allowed"]?.stringValue = settings.allowedContexts
		fields["namespace"]?.stringValue = settings.namespace
		fields["kubeconfig"]?.stringValue = settings.kubeconfig
		fields["image"]?.stringValue = settings.image
		// Empty means the image is chosen from the language, so the placeholder
		// says which one that is rather than leaving somebody to wonder.
		fields["image"]?.placeholderString = DevPodImage.resolved(
			"", for: configuration, root: root ?? URL(fileURLWithPath: ".")
		)
		fields["port"]?.stringValue = settings.port > 0 ? String(settings.port) : ""
		fields["ingressHost"]?.stringValue = settings.ingressHost
		filesList.files = settings.files
		fillContexts(selecting: settings.context)

		let chart = configuration.helm
		fields["chart"]?.stringValue = chart?.chart ?? ""
		fields["release"]?.stringValue = chart?.release ?? ""
		fields["valueFiles"]?.stringValue = (chart?.valueFiles ?? []).joined(separator: ", ")
		fields["container"]?.stringValue = chart?.container ?? ""
		secretsBox.state = (chart?.usesSecrets ?? false) ? .on : .off
		installBox.state = (chart?.install ?? true) ? .on : .off

		clusterSection.isHidden = !configuration.kind.runsInCluster
		chartSection.isHidden = configuration.kind != .helmDevPod
	}

	/// A comma-separated field, as the list it stands for.
	private func list(_ field: NSTextField?) -> [String] {
		(field?.stringValue ?? "")
			.split(separator: ",")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
	}

	private func fillContexts(selecting current: String) {
		contextPopUp.removeAllItems()
		contextPopUp.addItem(withTitle: "Current context")
		contextPopUp.addItems(withTitles: contexts)
		if let index = contexts.firstIndex(of: current) {
			contextPopUp.selectItem(at: index + 1)
		} else {
			contextPopUp.selectItem(at: 0)
		}
	}

	/// What is on screen, as a configuration.
	private func collect(from original: LaunchConfiguration) -> LaunchConfiguration {
		var updated = original
		updated.name = fields["name"]?.stringValue.trimmingCharacters(in: .whitespaces) ?? original.name
		if updated.name.isEmpty { updated.name = original.name }
		updated.kind = LaunchConfiguration.Kind.allCases[max(0, kindPopUp.indexOfSelectedItem)]
		updated.program = fields["program"]?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
		updated.arguments = ArgumentLine.split(fields["arguments"]?.stringValue ?? "")
		updated.workingDirectory = fields["cwd"]?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
		updated.environment = EnvironmentLines.parse(environmentView.string)

		if updated.kind.runsInCluster {
			if updated.kind == .helmDevPod {
				updated.helm = LaunchConfiguration.HelmSettings(
					chart: fields["chart"]?.stringValue.trimmingCharacters(in: .whitespaces) ?? "",
					release: fields["release"]?.stringValue.trimmingCharacters(in: .whitespaces) ?? "",
					valueFiles: list(fields["valueFiles"]),
					usesSecrets: secretsBox.state == .on,
					sets: original.helm?.sets ?? [],
					container: fields["container"]?.stringValue.trimmingCharacters(in: .whitespaces) ?? "",
					install: installBox.state == .on
				)
			}

			let index = contextPopUp.indexOfSelectedItem - 1
			updated.devPod = LaunchConfiguration.DevPodSettings(
				context: contexts.indices.contains(index) ? contexts[index] : "",
				namespace: fields["namespace"]?.stringValue.trimmingCharacters(in: .whitespaces) ?? "",
				pod: original.devPod?.pod ?? "",
				kubeconfig: fields["kubeconfig"]?.stringValue.trimmingCharacters(in: .whitespaces) ?? "",
				allowedContexts: fields["allowed"]?.stringValue.trimmingCharacters(in: .whitespaces) ?? "",
				allowInstall: original.devPod?.allowInstall ?? true,
				files: filesList.files,
				image: fields["image"]?.stringValue.trimmingCharacters(in: .whitespaces) ?? "",
				ingressHost: fields["ingressHost"]?.stringValue.trimmingCharacters(in: .whitespaces) ?? "",
				port: Int(fields["port"]?.stringValue.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
			)
		}
		return updated
	}

	/// Writes the edited configuration, if anything about it changed.
	/// Says what is wrong with this configuration, where it is being edited.
	///
	/// Every one of these fails at run time in a way that points somewhere
	/// else: LLDB on a Go package starts nothing and says nothing, an argument
	/// naming a file that is not there is passed through as written so the
	/// program complains about its own configuration, and a file that cannot be
	/// sent is skipped without a word. Read here, each is a sentence; met at run
	/// time, each was an hour.
	private func refreshWarnings() {
		for view in warningsStack.arrangedSubviews {
			warningsStack.removeArrangedSubview(view)
			view.removeFromSuperview()
		}

		guard let index = selected, configurations.indices.contains(index), let root else {
			warningsStack.isHidden = true
			return
		}

		let problems = LaunchConfigurationCheck.problems(for: configurations[index], root: root)
		warningsStack.isHidden = problems.isEmpty

		for problem in problems {
			// Named, because the list sits above the fields rather than beside
			// them: "Nothing at nowhere" is a puzzle, "Working directory:
			// nothing at nowhere" is an instruction.
			let text = problem.fix.map { "\(problem.message) \($0)" } ?? problem.message
			let label = NSTextField(
				wrappingLabelWithString: "⚠︎  \(Self.fieldLabel(problem.field)): \(text)"
			)
			label.font = Theme.current.uiFont(11)
			// System orange rather than a theme colour: the palette has none for
			// a warning, and this one follows light and dark on its own.
			label.textColor = .systemOrange
			label.isSelectable = true
			warningsStack.addArrangedSubview(label)
			label.widthAnchor.constraint(equalTo: warningsStack.widthAnchor).isActive = true
		}
	}

	/// What each field is called on this page, so a warning can point at one.
	static func fieldLabel(_ field: String) -> String {
		switch field {
		case "type": return "What it runs"
		case "program": return "Package or program"
		case "cwd": return "Working directory"
		case "arguments": return "Arguments"
		case "files": return "Files to send"
		default: return field
		}
	}

	private func commit() {
		guard let index = selected, configurations.indices.contains(index) else { return }
		let updated = collect(from: configurations[index])
		guard updated != configurations[index] else { return }

		configurations[index] = updated
		refreshWarnings()
		onSave?(updated, originalName)
		originalName = updated.name
		list.reloadData()
		list.selectRowIndexes([index], byExtendingSelection: false)
	}

	// MARK: - Actions

	@objc private func fieldChanged(_ sender: Any?) { commit() }

	func controlTextDidChange(_ notification: Notification) {
		guard let field = notification.object as? NSTextField, field === fields["name"] else { return }
		headerTitle.stringValue = field.stringValue
	}

	@objc private func kindChanged(_ sender: Any?) {
		guard let index = selected, configurations.indices.contains(index) else { return }
		commit()
		clusterSection.isHidden = !configurations[index].kind.runsInCluster
		chartSection.isHidden = configurations[index].kind != .helmDevPod
	}

	@objc private func addConfiguration() {
		commit()
		let name = LaunchNames.free(like: "New configuration", avoiding: configurations.map(\.name))
		var configuration = LaunchConfiguration(name: name, type: "go")
		configuration.request = "launch"
		configuration.program = "${workspaceFolder}"

		configurations.append(configuration)
		onSave?(configuration, nil)
		list.reloadData()
		select(configurations.count - 1)
		window?.makeFirstResponder(fields["name"])
	}

	@objc private func duplicateConfiguration() {
		commit()
		guard let index = selected, configurations.indices.contains(index) else { return }

		var copy = configurations[index]
		copy.name = LaunchNames.copy(of: copy.name, avoiding: configurations.map(\.name))
		configurations.insert(copy, at: index + 1)
		onSave?(copy, nil)
		list.reloadData()
		select(index + 1)
	}

	@objc private func deleteConfiguration() {
		guard let index = selected, configurations.indices.contains(index) else { return }
		let name = configurations[index].name
		configurations.remove(at: index)
		selected = nil
		onDelete?(name)
		list.reloadData()
		select(configurations.isEmpty ? nil : min(index, configurations.count - 1))
	}

	@objc private func runSelected() { start(.run) }
	@objc private func debugSelected() { start(.debug) }
	@objc private func profileSelected() { start(.profile) }
	@objc private func coverSelected() { start(.coverage) }

	private func start(_ mode: StartMode) {
		commit()
		guard let index = selected, configurations.indices.contains(index) else { return }
		onStart?(configurations[index], mode)
	}
}

// MARK: - The list

extension LaunchConfigurationsPage: NSTableViewDataSource, NSTableViewDelegate {
	func numberOfRows(in tableView: NSTableView) -> Int { configurations.count }

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		let cell = NSTableCellView()
		let text = NSTextField(labelWithString: configurations[row].name)
		text.font = Theme.current.uiFont(12)
		text.textColor = Theme.current.sidebarText
		text.lineBreakMode = .byTruncatingTail

		let icon = NSImageView()
		icon.image = Theme.symbol(
			configurations[row].kind == .devPod ? "cloud" : "play.circle",
			size: 11 * Theme.current.scale,
			color: Theme.current.gitIgnored
		)

		for view in [icon, text] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			cell.addSubview(view)
		}
		NSLayoutConstraint.activate([
			icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Theme.current.scaled(12)),
			icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			icon.widthAnchor.constraint(equalToConstant: Theme.current.scaled(14)),
			text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Theme.current.scaled(6)),
			text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Theme.current.scaled(8)),
			text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
		])
		return cell
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		let row = list.selectedRow
		guard row != selected else { return }
		select(row >= 0 ? row : nil)
	}
}

// MARK: - Editing text

extension LaunchConfigurationsPage: NSTextFieldDelegate, NSTextViewDelegate {
	func controlTextDidEndEditing(_ notification: Notification) { commit() }

	func textDidEndEditing(_ notification: Notification) { commit() }
}

/// A list of files to send, which files can be dropped onto.
///
/// Dropping is how somebody has the file in front of them: it is in the
/// project tree or the Finder, and typing its path again is work the pointer
/// has already done. A path inside the project is kept relative to it, so the
/// configuration is the same for everybody who has the repository.
@MainActor
final class FileDropList: NSView {
	var onChange: (() -> Void)?
	/// Where the project is, for turning a dropped path into a relative one.
	var projectRoot: (() -> URL?)?

	var files: [String] = [] {
		didSet { rebuild() }
	}

	private let rows = NSStackView()
	private let hint = NSTextField(labelWithString: "Drop files here, or +")
	private var isTarget = false { didSet { needsDisplay = true } }

	override init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
		layer?.cornerRadius = 6

		rows.orientation = .vertical
		rows.alignment = .leading
		rows.spacing = Theme.current.scaled(2)
		rows.translatesAutoresizingMaskIntoConstraints = false
		addSubview(rows)

		hint.font = Theme.current.uiFont(11)
		hint.textColor = Theme.current.gitIgnored
		hint.translatesAutoresizingMaskIntoConstraints = false
		addSubview(hint)

		let add = NSButton()
		add.isBordered = false
		add.image = Theme.symbol("plus", size: 11 * Theme.current.scale, color: Theme.current.sidebarText)
		add.imagePosition = .imageOnly
		add.target = self
		add.action = #selector(browse)
		add.toolTip = "Choose a file to send"
		add.translatesAutoresizingMaskIntoConstraints = false
		addSubview(add)

		// The hint sits under the list rather than at the bottom of the box: a
		// box that grows with the files in it would otherwise print the hint
		// straight through the last of them.
		NSLayoutConstraint.activate([
			rows.topAnchor.constraint(equalTo: topAnchor, constant: Theme.current.scaled(6)),
			rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(8)),
			rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(30)),

			hint.topAnchor.constraint(equalTo: rows.bottomAnchor, constant: Theme.current.scaled(4)),
			hint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.current.scaled(10)),
			hint.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.current.scaled(7)),

			add.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.current.scaled(6)),
			add.topAnchor.constraint(equalTo: topAnchor, constant: Theme.current.scaled(5)),
			add.widthAnchor.constraint(equalToConstant: Theme.current.scaled(20)),

			heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.current.scaled(58)),
		])

		registerForDraggedTypes([.fileURL])
		rebuild()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
		Theme.current.editorBackground.setFill()
		path.fill()

		// Dashed while empty, and lit while something is over it: a box you can
		// drop onto should look like one.
		let border = isTarget ? Theme.current.gitModified : Theme.current.separator
		border.setStroke()
		path.lineWidth = isTarget ? 2 : 1
		if files.isEmpty && !isTarget { path.setLineDash([4, 3], count: 2, phase: 0) }
		path.stroke()
	}

	private func rebuild() {
		for view in rows.arrangedSubviews { view.removeFromSuperview() }
		hint.stringValue = files.isEmpty ? "Drop files here, or +" : "Sent before the program starts"

		for (index, file) in files.enumerated() {
			let label = NSTextField(labelWithString: file)
			label.font = Theme.terminalFont(size: Theme.current.fontSize - 2)
			label.textColor = Theme.current.sidebarText
			label.lineBreakMode = .byTruncatingMiddle

			let remove = NSButton()
			remove.isBordered = false
			remove.image = Theme.symbol("xmark", size: 8 * Theme.current.scale, color: Theme.current.gitIgnored)
			remove.imagePosition = .imageOnly
			remove.target = self
			remove.tag = index
			remove.action = #selector(removeFile(_:))
			remove.widthAnchor.constraint(equalToConstant: Theme.current.scaled(16)).isActive = true

			let row = NSStackView(views: [label, NSView(), remove])
			row.orientation = .horizontal
			row.spacing = Theme.current.scaled(4)
			rows.addArrangedSubview(row)
			row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
		}
		needsDisplay = true
	}

	@objc private func removeFile(_ sender: NSButton) {
		guard files.indices.contains(sender.tag) else { return }
		files.remove(at: sender.tag)
		onChange?()
	}

	@objc private func browse() {
		let panel = NSOpenPanel()
		panel.canChooseFiles = true
		panel.canChooseDirectories = false
		panel.allowsMultipleSelection = true
		panel.directoryURL = projectRoot?()
		guard panel.runModal() == .OK else { return }
		add(panel.urls)
	}

	// MARK: - Dropping

	override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
		isTarget = !urls(from: sender).isEmpty
		return isTarget ? .copy : []
	}

	override func draggingExited(_ sender: (any NSDraggingInfo)?) { isTarget = false }

	override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
		isTarget = false
		let dropped = urls(from: sender)
		guard !dropped.isEmpty else { return false }
		add(dropped)
		return true
	}

	private func urls(from sender: any NSDraggingInfo) -> [URL] {
		let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
		return items.filter { url in
			var directory: ObjCBool = false
			let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
			return exists && !directory.boolValue
		}
	}

	private func add(_ urls: [URL]) {
		let root = projectRoot?()
		for url in urls {
			let path = DevPodFiles.entry(for: url, in: root)
			guard !files.contains(path) else { continue }
			files.append(path)
		}
		onChange?()
	}
}

/// Top-down coordinates, so a stack in a scroll view starts at the top.
private final class FlippedView: NSView {
	override var isFlipped: Bool { true }
}
