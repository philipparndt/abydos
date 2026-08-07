import AbydosKit
import AppKit

/// Everything the app can be asked to do, taken from the menu bar.
///
/// The palette used to keep its own short list of actions, written by hand
/// beside the menu's, which meant two places to add a command to and only one
/// of them obvious. Everything it offered was something somebody had remembered
/// to put there twice.
///
/// So the menu is the list. Every action a Mac app has is a menu item already —
/// that is the platform's own rule, not a convention this app invented — and
/// each item carries the three things a palette needs: what the action is
/// called, what key it answers to, and whether it can be done right now. An
/// action added to a menu tomorrow is in the palette the moment it is added,
/// with its shortcut, and nobody has to know this file exists.
enum MenuCommands {
	/// A command and the item that performs it.
	struct Entry {
		let descriptor: CommandDescriptor
		let item: NSMenuItem

		/// Does it, the way clicking the menu item would — validation, target
		/// and the responder chain included.
		@MainActor func perform() {
			guard let menu = item.menu else { return }
			menu.performActionForItem(at: menu.index(of: item))
		}
	}

	/// The menus that hold nothing worth offering.
	///
	/// The Apple menu belongs to the system; Window and Help are lists of
	/// windows and one search field, which a palette can only get in the way
	/// of. Everything else is fair game.
	static let skippedMenus: Set<String> = ["Window", "Help"]

	/// Every action currently available.
	///
	/// Disabled items are left out rather than shown greyed: a palette is a
	/// list of what can be done now, and "Close Tab" with no tab open is a row
	/// that can only disappoint. Validation is what decides that, which is the
	/// same thing that greys the menu item — so the answer is always the one
	/// the menu would give.
	@MainActor static func all(in menu: NSMenu? = nil) -> [Entry] {
		guard let mainMenu = menu ?? NSApp.mainMenu else { return [] }

		var found: [Entry] = []
		for item in mainMenu.items {
			guard let submenu = item.submenu else { continue }
			let name = title(of: item)
			guard !skippedMenus.contains(name) else { continue }
			collect(from: submenu, path: [name], into: &found)
		}
		return found
	}

	private static func collect(from menu: NSMenu, path: [String], into found: inout [Entry]) {
		// Ask the items whether they are available, exactly as opening the menu
		// would. Without this every item reports whatever it was left at, which
		// for a menu nobody has opened yet is "enabled".
		menu.update()

		for item in menu.items {
			if let submenu = item.submenu {
				collect(from: submenu, path: path + [title(of: item)], into: &found)
				continue
			}

			guard !item.isSeparatorItem, !item.title.isEmpty, item.action != nil else { continue }
			guard item.isEnabled, !item.isHidden else { continue }

			found.append(Entry(
				descriptor: CommandDescriptor(
					title: item.title,
					path: path,
					shortcut: shortcut(for: item)
				),
				item: item
			))
		}
	}

	/// What a menu is called.
	///
	/// The name is on the submenu, not on the item that holds it: a menu bar is
	/// built by giving a titleless item a titled menu, and a titleless
	/// `NSMenuItem` answers `title` with its own class name — so reading the
	/// item put "NSMenuItem" in front of every command in the palette.
	static func title(of item: NSMenuItem) -> String {
		if let submenuTitle = item.submenu?.title, !submenuTitle.isEmpty { return submenuTitle }
		// The application menu has no title of its own; it is shown under the
		// app's name, so that is what it is called here too.
		if item.title.isEmpty || item.title == "NSMenuItem" {
			return ProcessInfo.processInfo.processName
		}
		return item.title
	}

	/// The key the item answers to, written the way a menu writes it.
	static func shortcut(for item: NSMenuItem) -> String? {
		let modifiers = item.keyEquivalentModifierMask
		return ShortcutText.describe(
			key: item.keyEquivalent,
			control: modifiers.contains(.control),
			option: modifiers.contains(.option),
			shift: modifiers.contains(.shift),
			command: modifiers.contains(.command)
		)
	}
}
