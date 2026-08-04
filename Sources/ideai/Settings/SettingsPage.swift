import AppKit
import IdeaiKit

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
final class SettingsPage: NSView {
	private var sections: [SettingsSections.Section] = SettingsSections.all
	private var selected = 0
	/// Controls that have to be re-read when something changes them from
	/// outside — Restore Defaults, or the other window.
	private var refreshHandlers: [() -> Void] = []

	private let list = NSTableView()
	private let form = NSStackView()
	private var scroll: NSScrollView!

	override init(frame: NSRect) {
		super.init(frame: frame)
		build()
		show(section: 0)

		NotificationCenter.default.addObserver(
			forName: .ideaiSettingsChanged, object: nil, queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?.refreshHandlers.forEach { $0() } }
		}
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// Shows a section by name, for the capture harness.
	func show(named name: String) {
		guard let index = sections.firstIndex(where: {
			$0.title.lowercased() == name.lowercased()
		}) else { return }
		list.selectRowIndexes([index], byExtendingSelection: false)
		show(section: index)
	}

	deinit { NotificationCenter.default.removeObserver(self) }

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
			sidebar.widthAnchor.constraint(equalToConstant: Theme.current.scaled(190)),

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
		])
	}

	private func makeSidebar() -> NSView {
		let background = ColoredView(color: Theme.current.sidebarBackground)

		list.headerView = nil
		list.backgroundColor = .clear
		list.selectionHighlightStyle = .regular
		list.rowSizeStyle = .custom
		list.rowHeight = Theme.current.scaled(28)
		list.intercellSpacing = .zero
		list.gridStyleMask = []
		list.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section")))
		list.delegate = self
		list.dataSource = self
		list.selectRowIndexes([0], byExtendingSelection: false)

		let scroll = NSScrollView()
		scroll.documentView = list
		scroll.hasVerticalScroller = true
		scroll.drawsBackground = false
		scroll.borderType = .noBorder

		let title = NSTextField(labelWithString: "Settings")
		title.font = Theme.current.uiFont(11, weight: .semibold)
		title.textColor = Theme.current.gitIgnored

		for view in [title, scroll] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			background.addSubview(view)
		}
		NSLayoutConstraint.activate([
			title.topAnchor.constraint(equalTo: background.topAnchor, constant: Theme.current.scaled(14)),
			title.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Theme.current.scaled(14)),

			scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: Theme.current.scaled(8)),
			scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Theme.current.scaled(10)),
		])
		return background
	}

	// MARK: - Contents

	/// Shows one section, replacing whatever was there.
	private func show(section index: Int) {
		guard sections.indices.contains(index) else { return }
		selected = index
		refreshHandlers.removeAll()
		for view in form.arrangedSubviews { view.removeFromSuperview() }

		let section = sections[index]
		let heading = NSTextField(labelWithString: section.title)
		heading.font = Theme.current.uiFont(17, weight: .semibold)
		heading.textColor = Theme.current.sidebarHeaderText
		form.addArrangedSubview(heading)

		let card = ColoredView(color: Theme.current.sidebarBackground)
		card.wantsLayer = true
		card.layer?.cornerRadius = 8
		card.layer?.borderWidth = 1
		card.layer?.borderColor = Theme.current.separator.withAlphaComponent(0.6).cgColor

		let rows = NSStackView(views: section.rows().map { row(for: $0) })
		rows.orientation = .vertical
		rows.alignment = .leading
		rows.spacing = Theme.current.scaled(16)
		rows.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(rows)
		NSLayoutConstraint.activate([
			rows.topAnchor.constraint(equalTo: card.topAnchor, constant: Theme.current.scaled(16)),
			rows.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Theme.current.scaled(16)),
			rows.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Theme.current.scaled(18)),
			rows.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Theme.current.scaled(18)),
		])
		for view in rows.arrangedSubviews {
			view.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
		}
		form.addArrangedSubview(card)

		// Wide enough to read and no wider — and the cap is on the card alone,
		// so nothing here can decide how wide the editor area has to be.
		for view in form.arrangedSubviews {
			let full = view.widthAnchor.constraint(
				equalTo: form.widthAnchor, constant: -Theme.current.scaled(56)
			)
			full.priority = .defaultHigh
			full.isActive = true
		}
	}

	/// One setting: its name, its control, and a sentence about it.
	///
	/// The control goes on the right of the name, and the help under both —
	/// which reads as one thing rather than as a grid, and leaves the sentence
	/// the whole width to be a sentence in.
	private func row(for row: SettingsPaneController.Row) -> NSView {
		if case let .group(title, help) = row { return groupHeading(title, help: help) }

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

	/// A heading inside a card, over the settings it gathers.
	private func groupHeading(_ title: String, help: String?) -> NSView {
		let label = NSTextField(labelWithString: title.uppercased())
		label.font = Theme.current.uiFont(10, weight: .semibold)
		label.textColor = Theme.current.gitIgnored

		let stack = NSStackView(views: [label])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = Theme.current.scaled(2)

		if let help {
			let text = NSTextField(wrappingLabelWithString: help)
			text.font = Theme.current.uiFont(11)
			text.textColor = Theme.current.gitIgnored.withAlphaComponent(0.8)
			text.isSelectable = false
			stack.addArrangedSubview(text)
			text.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		}
		return stack
	}

	/// The control for a row, in this app's colours.
	private func build(_ row: SettingsPaneController.Row) -> (String, NSView, String?) {
		switch row {
		case let .toggle(title, help, get, set, isEnabled):
			let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
			button.state = get() ? .on : .off
			button.isEnabled = isEnabled?() ?? true
			button.onAction = {
				set(button.state == .on)
				// One switch decides another's fate, so every control re-reads
				// itself — and its own state — after any of them changes.
				NotificationCenter.default.post(name: .ideaiSettingsChanged, object: nil)
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
			slider.controlSize = .small
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

		case let .group(title, _):
			return (title, NSView(), nil)

		case let .button(title, label, action):
			let button = NSButton(title: label, target: nil, action: nil)
			button.bezelStyle = .rounded
			button.font = Theme.current.uiFont(12)
			button.onAction = action
			return (title, button, nil)
		}
	}

	private func field(text: String, width: CGFloat) -> NSTextField {
		let field = NSTextField(string: text)
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
	func numberOfRows(in tableView: NSTableView) -> Int { sections.count }

	func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
		let cell = NSTableCellView()
		let text = NSTextField(labelWithString: sections[row].title)
		text.font = Theme.current.uiFont(12)
		text.textColor = Theme.current.sidebarText

		let icon = NSImageView()
		icon.image = Theme.symbol(
			sections[row].symbol, size: 11 * Theme.current.scale, color: Theme.current.gitIgnored
		)

		for view in [icon, text] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			cell.addSubview(view)
		}
		NSLayoutConstraint.activate([
			icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: Theme.current.scaled(12)),
			icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			icon.widthAnchor.constraint(equalToConstant: Theme.current.scaled(14)),
			text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Theme.current.scaled(7)),
			text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -Theme.current.scaled(8)),
			text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
		])
		return cell
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		let row = list.selectedRow
		guard row >= 0, row != selected else { return }
		show(section: row)
	}
}

/// Top-down coordinates, so a stack in a scroll view starts at the top.
private final class FlippedContainer: NSView {
	override var isFlipped: Bool { true }
}
