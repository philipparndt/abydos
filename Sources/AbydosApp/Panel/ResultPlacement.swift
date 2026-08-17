import AppKit

/// Where a results list — search or usages — is showing.
///
/// Four homes and no fifth. The two that were already here are `panel` and
/// `window`, which item 470 built as one button whose title turned around;
/// item 506 added the two the user asked for by name, and the moment there
/// were more than two the button had to stop being a toggle.
///
/// ## Why this is a property of the *list* and not of the panel
///
/// The obvious generalisation is a docking system: every pane declares where it
/// may live, every host declares what it takes, and anything goes anywhere. That
/// was offered and declined, and the line is drawn here rather than there on
/// purpose. A results list is the one pane in this program that is *asked for*
/// rather than opened — Find Usages and ⇧⌘F produce one, and the only question
/// is where the answer appears. Everything else in the bottom strip (changes,
/// branches, backlog, scratches, a terminal, a debugger) is a thing somebody
/// went to, and it is already where they went.
///
/// So placement lives on the list. The panel and the sidebar each take one
/// guest, by name, and neither becomes a general host: nothing else in the
/// program grows a Place control, and no host has to answer "what can I hold".
enum ResultPlacement: String, CaseIterable {
	/// A tab in the bottom panel's strip, beside the terminal tabs. Where a
	/// list has arrived since item 470, and still the default.
	case panel
	/// Under the project view, in the lower half of a split sidebar. IDEA's
	/// left-bottom tool window slot.
	case sidebar
	/// A column of the bottom panel of its own, with a terminal in the other
	/// one — *beside* a terminal rather than instead of it, which is the whole
	/// difference between this and `panel`.
	case beside
	/// A window of its own, for a list too long to read forty rows at a time.
	case window

	/// What the control says while the list is here. Short, because it is the
	/// button's own title and the button sits in a row with a heading in it.
	var shortTitle: String {
		switch self {
		case .panel: return "Panel"
		case .sidebar: return "Tree"
		case .beside: return "Terminals"
		case .window: return "Window"
		}
	}

	/// What the menu says, which is where there is room to say where it goes.
	var menuTitle: String {
		switch self {
		case .panel: return "In the Panel"
		case .sidebar: return "Under the Project View"
		case .beside: return "Beside the Terminals"
		case .window: return "In a Window of Its Own"
		}
	}
}

/// The one control that chooses among the four.
///
/// ## Why a pull-down and not the alternatives
///
/// A button that toggles cannot choose between four, and the three shapes that
/// can were each weighed:
///
///   - **A drag**, the way a terminal tab is dragged into a column. It works
///     where there is already a drop target and this list has to reach two
///     places that accept no drops at all — the sidebar and a window — so two
///     of the four homes would need drop targets invented for one guest, which
///     is the docking system that was declined.
///   - **A submenu on the pane's context menu.** The context menu over the list
///     is the row menu — Mark as Done, Mark as Not Done, Hide Rows Marked Done
///     — and putting the pane's own layout under the same right-click as the
///     row's marking is how somebody ends up moving the list when they meant to
///     tick a row.
///   - **A pull-down where the button was.** One control, in the place the
///     Expand button already occupied, naming all four destinations and showing
///     with a tick which one it is in now. Nothing has to be discovered and
///     nothing has to be dragged.
///
/// The button's own title is where it is *now* rather than where it would go,
/// which is the one thing the old two-state button got right: a control titled
/// "Expand" beside a docked list said what the press would do, and with four
/// destinations there is no single next one to name.
final class PlacementControl: NSPopUpButton {
	var onChoose: ((ResultPlacement) -> Void)?

	private var placement: ResultPlacement = .panel

	init() {
		super.init(frame: .zero, pullsDown: true)
		bezelStyle = .rounded
		controlSize = .small
		font = Theme.current.uiFont(10, weight: .medium)
		rebuild()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func setPlacement(_ placement: ResultPlacement) {
		guard placement != self.placement else { return }
		self.placement = placement
		rebuild()
	}

	func applySettings() {
		font = Theme.current.uiFont(10, weight: .medium)
	}

	private func rebuild() {
		let menu = NSMenu()
		// A pull-down takes its title from the first item, which is never
		// chosen. So the title is the current home, and the four below it are
		// the ones to go to.
		menu.addItem(NSMenuItem(title: placement.shortTitle, action: nil, keyEquivalent: ""))
		for home in ResultPlacement.allCases {
			let item = NSMenuItem(title: home.menuTitle, action: #selector(chose(_:)), keyEquivalent: "")
			item.target = self
			item.representedObject = home.rawValue
			item.state = home == placement ? .on : .off
			menu.addItem(item)
		}
		self.menu = menu
		toolTip = "Where these results show — now \(placement.menuTitle.lowercased())"
	}

	/// Picks from the menu the way a click on it does.
	///
	/// The `place:` steps call the pane's `onPlace` directly, which says nothing
	/// about the control — a menu built with the wrong represented object, or an
	/// item with no target, would leave every one of them passing. This goes
	/// through the item's own target and action, and reports the state of the
	/// ticks after, which is the other half of what the control has to get right.
	func chooseForTesting(_ home: ResultPlacement) -> String {
		guard let item = menu?.items.first(where: {
			$0.representedObject as? String == home.rawValue
		}) else { return "no item for \(home.rawValue)" }
		guard let action = item.action, let target = item.target as? NSObject else {
			return "item “\(item.title)” answers to nobody"
		}
		target.perform(action, with: item)
		let ticked = menu?.items.filter { $0.state == .on }.map(\.title) ?? []
		return "title=\(title) ticked=\(ticked.joined(separator: "|"))"
	}

	@objc private func chose(_ sender: NSMenuItem) {
		guard let raw = sender.representedObject as? String,
		      let home = ResultPlacement(rawValue: raw)
		else { return }
		onChoose?(home)
	}
}

/// A list that can be put in any of the four homes.
///
/// Both results panes are one: search and usages are the same checklist under
/// two different headings, and the whole argument of item 506's third decision
/// is that a home usages can reach and search cannot would be a difference the
/// spec has to explain and could not.
@MainActor
protocol ResultsPane: NSView {
	/// Asked to move. The window decides whether it can, and calls back with
	/// `setPlacement` once it has.
	var onPlace: ((ResultPlacement) -> Void)? { get set }
	/// Told where it now is, so the control says so.
	func setPlacement(_ placement: ResultPlacement)
	/// The keyboard, put in the list. Called on every arrival, in every home.
	func focusList()
	/// What to call its tab and its window.
	var paneTitle: String { get }
}

extension ResultsPane {
	/// Sends a key the way a person's finger does: to the *window*, for the
	/// responder chain to route.
	///
	/// The steps that already exist send a key straight to the table, which is
	/// the right test of what the table does with a key and no test at all of
	/// whether the key would have reached it. That second question is the whole
	/// of item 506's hardest home: a list sitting in a column of the bottom
	/// panel with a live terminal in the other one, and a terminal takes every
	/// keystroke it is given. A claim about that has to be able to fail, and one
	/// made by calling the table directly cannot.
	func pressAtWindowForTesting(_ name: String) {
		// ⇥ is here for item 510, and it is the one that most needs sending this
		// way: it is now the only gesture that hands the keyboard to the editor,
		// and a ⇥ delivered straight to the table would show that the table
		// answers it while saying nothing about the four homes — where ⇥ is also
		// how the key view loop walks between controls.
		// ⌫ is here for item 523, and it is the claim that item's fix has to be
		// able to fail: a click that did not put the keyboard in the list leaves
		// ⌫ reaching whatever still has it, and since item 505 that key ticks a
		// row. Sent to the window rather than to the table, because "the table
		// answers ⌫" was never in doubt — whether the key gets there is.
		let keys: [String: (UInt16, String)] = [
			"space": (49, " "),
			"down": (125, "\u{F701}"),
			"up": (126, "\u{F700}"),
			"return": (36, "\r"),
			"tab": (48, "\t"),
			"delete": (51, "\u{7F}"),
		]
		guard let (code, characters) = keys[name], let window else { return }
		guard let event = NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: [],
			timestamp: ProcessInfo.processInfo.systemUptime,
			windowNumber: window.windowNumber, context: nil,
			characters: characters, charactersIgnoringModifiers: characters,
			isARepeat: false, keyCode: code
		) else { return }
		window.sendEvent(event)
	}
}
