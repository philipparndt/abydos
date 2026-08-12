import AbydosKit
import AppKit

/// Which press reaches each shortcut in the menu bar, on the keyboard layout the
/// machine is set to.
///
/// **This exists because a menu item's key equivalent is not what was written in
/// the source.** AppKit relocates one it decides is hard to reach on the current
/// layout — `allowsAutomaticKeyEquivalentLocalization`, on by default since the
/// macOS 12 SDK — and the item then reports the moved key, not the declared one.
/// 0479 is the account: ⌘/ was declared, the German layout puts `/` behind a
/// shift, the system moved the shortcut to ⌘ß, and the person who had asked for
/// ⌘/ pressed ⌘⇧7 and got nothing. Nothing in the source said ß and nothing in
/// the suite could see it.
///
/// So the answer is *measured*, not worked out. AppKit is handed the keystrokes a
/// keyboard can actually make and asked which of its own items each one matches,
/// which is the same code path a real press takes and the only account of the
/// matching rules that cannot be out of date. Two of those rules were surprising
/// enough to be worth naming, and both were found here:
///
/// - **An extra shift is forgiven.** An item declaring `/` with ⌘ alone *is*
///   matched by ⌘⇧7 on a German keyboard, even though the event carries a shift
///   the mask does not.
/// - **An extra option is not.** `[` on a German keyboard is ⌥5, and no press
///   reaches an item declaring `[` — which is what the automatic localisation is
///   there for, and why turning it off across the app would be a cure worse than
///   the disease.
///
/// ## Why it does not press the real menu
///
/// Each item is copied into a menu of its own whose one item points at a harmless
/// object, and the sweep presses *that*. Sweeping the real menu bar would perform
/// every command it matched — Quit among them, a hundred events in — so the report
/// would end the app it was reporting on. The copies carry the key equivalents the
/// real items report *now*, after any relocation, and are opted out of
/// localisation themselves so nothing is moved twice.
///
/// **One item per shadow menu, and that is not a detail.** A menu answers a key
/// with its first matching item and stops, so a single shadow holding all of them
/// reported ⇧⌘N unreachable because ⌘N sat above it and AppKit forgives the extra
/// shift. Half this report was wrong in exactly the direction that looks like a
/// finding, which is the worst direction for a measurement to be wrong in.
@MainActor
enum MenuKeyReport {
	/// One shortcut and what it answers to.
	struct Finding {
		let path: String
		let title: String
		/// As the menu writes it — `⌘ß` — after any relocation by the system.
		let shortcut: String
		/// The presses that reach it, written the way somebody would say them.
		let presses: [String]
		/// Reachable only on a numeric keypad, which on a laptop means not at all.
		let keypadOnly: Bool
	}

	/// Sweeps the whole menu bar and prints a line per shortcut.
	static func print(menu: NSMenu? = nil, prefix: String = "MENUKEY") {
		guard let layout = KeyboardLayout.current() else {
			Swift.print("\(prefix) no keyboard layout — the input source is not one")
			return
		}
		Swift.print("\(prefix) layout “\(layout.name)”")
		for finding in findings(in: menu ?? NSApp.mainMenu, layout: layout) {
			let reached = finding.presses.isEmpty
				? "NO PRESS REACHES IT"
				: finding.presses.joined(separator: " or ")
				+ (finding.keypadOnly ? " — and that is the numeric keypad only" : "")
			Swift.print("\(prefix) \(finding.path) ▸ \(finding.title): "
				+ "menu says \(finding.shortcut), pressed as \(reached)")
		}
		fflush(stdout)
	}

	/// Every shortcut in the menu bar, and the presses that reach it.
	static func findings(in menu: NSMenu?, layout: KeyboardLayout) -> [Finding] {
		guard let menu else { return [] }
		var items: [(path: String, item: NSMenuItem)] = []
		collect(from: menu, path: [], into: &items)

		// The events once rather than per item: the keyboard does not change while
		// this runs, and there are a thousand of them.
		let events = keystrokes.compactMap { keystroke -> (Keystroke, NSEvent)? in
			keystroke.event().map { (keystroke, $0) }
		}

		let sink = Sink()
		return items.map { entry in
			let shadow = NSMenu()
			let holder = NSMenuItem()
			let flat = NSMenu(title: "shadow")
			let copy = NSMenuItem(
				title: "one",
				action: #selector(Sink.matched(_:)),
				keyEquivalent: entry.item.keyEquivalent
			)
			copy.keyEquivalentModifierMask = entry.item.keyEquivalentModifierMask
			copy.target = sink
			// Whatever the system was going to move has been moved already, in the
			// real item this was copied from. Left on, it would be moved again from
			// wherever it landed, and the report would describe a menu nobody has.
			copy.allowsAutomaticKeyEquivalentLocalization = false
			flat.addItem(copy)
			holder.submenu = flat
			shadow.addItem(holder)

			var reached: [Keystroke] = []
			for (keystroke, event) in events {
				sink.matches = 0
				_ = shadow.performKeyEquivalent(with: event)
				if sink.matches > 0 { reached.append(keystroke) }
			}

			return Finding(
				path: entry.path,
				title: entry.item.title,
				shortcut: MenuCommands.shortcut(for: entry.item) ?? "nothing",
				presses: reached.map { $0.describe(on: layout) },
				keypadOnly: !reached.isEmpty
					&& reached.allSatisfy { KeyboardLayout.numericKeypadKeyCodes.contains($0.keyCode) }
			)
		}
	}

	// MARK: what a person can press

	/// A key held down with modifiers — the event side of the question, where
	/// `KeyboardLayout.Press` is the character side. Command and control are in
	/// here and not there because they are what a *shortcut* is made of while
	/// changing nothing about what the key types.
	@MainActor
	private struct Keystroke {
		let keyCode: UInt16
		let modifiers: NSEvent.ModifierFlags

		/// The event the window server would send for this press.
		///
		/// **Through `CGEvent`, so the system fills the characters in** from the
		/// key code and the flags. Assembling an `NSEvent` by hand and asserting
		/// what it types was tried first and the report it produced was nonsense:
		/// the two character fields of a real event do not agree the way the
		/// documentation reads — with command held, `characters` drops the shift
		/// (`y`) while `charactersIgnoringModifiers` keeps it (`Y`) — and a German
		/// keyboard has `y` where a US one has `z`, so half of what was asserted
		/// was not even on the right key. An event the system builds cannot be
		/// wrong about the layout it was built on.
		func event() -> NSEvent? {
			guard let made = CGEvent(
				keyboardEventSource: MenuKeyReport.eventSource,
				virtualKey: keyCode,
				keyDown: true
			) else { return nil }
			var flags: CGEventFlags = []
			if modifiers.contains(.command) { flags.insert(.maskCommand) }
			if modifiers.contains(.shift) { flags.insert(.maskShift) }
			if modifiers.contains(.option) { flags.insert(.maskAlternate) }
			if modifiers.contains(.control) { flags.insert(.maskControl) }
			made.flags = flags
			guard let event = NSEvent(cgEvent: made) else { return nil }
			// The modifier keys themselves — right command is key code 54 — come
			// back as `flagsChanged`, and asking one of those for its characters
			// **throws**: "Invalid message sent to event". Not nil, not empty, an
			// uncaught NSException that took the app down mid-report.
			guard event.type == .keyDown else { return nil }
			// A key code that is not a key on this keyboard types nothing, and
			// pressing it can match nothing, so there is no point sweeping it.
			return (event.charactersIgnoringModifiers ?? "").isEmpty ? nil : event
		}

		/// The press as somebody would say it: the modifiers, then what is printed
		/// on the key rather than what the press produces. ⇧7 and not ⇧/, because
		/// the 7 key is the one that gets pressed.
		func describe(on layout: KeyboardLayout) -> String {
			let unshifted = layout.characters(for: KeyboardLayout.Press(keyCode: keyCode))
			let named = ShortcutText.describe(
				key: unshifted.isEmpty ? "<key \(keyCode)>" : unshifted,
				control: modifiers.contains(.control),
				option: modifiers.contains(.option),
				shift: modifiers.contains(.shift),
				command: modifiers.contains(.command)
			) ?? "<key \(keyCode)>"
			// Said out loud, because otherwise the keypad's copy of a key looks
			// like the same press reported twice.
			return KeyboardLayout.numericKeypadKeyCodes.contains(keyCode)
				? named + " (keypad)"
				: named
		}
	}

	/// One source for every event, because making one is a round trip to the
	/// window server: a thousand of them took longer than the sweep it was for.
	private static let eventSource = CGEventSource(stateID: .privateState)

	/// The modifier combinations a shortcut in this app is declared with, times
	/// every key code. The combinations without command are in because the
	/// debugger's F-keys have none, and ⌃ is in because Run does.
	private static let modifierCombinations: [NSEvent.ModifierFlags] = [
		[], [.shift],
		[.command], [.command, .shift], [.command, .option], [.command, .option, .shift],
		[.command, .control], [.command, .control, .shift],
		[.control], [.control, .shift], [.control, .option],
	]

	private static var keystrokes: [Keystroke] {
		(UInt16(0) ... 127).flatMap { keyCode in
			modifierCombinations.map { Keystroke(keyCode: keyCode, modifiers: $0) }
		}
	}

	private static func collect(
		from menu: NSMenu,
		path: [String],
		into found: inout [(path: String, item: NSMenuItem)]
	) {
		for item in menu.items {
			if let submenu = item.submenu {
				collect(from: submenu, path: path + [MenuCommands.title(of: item)], into: &found)
				continue
			}
			guard !item.isSeparatorItem, !item.keyEquivalent.isEmpty else { continue }
			found.append((path.joined(separator: " ▸ "), item))
		}
	}

	/// Something for the shadow item to point at, so AppKit finds a target without
	/// a key window. Every real item's target is nil — resolved against the
	/// responder chain of whichever window is key — and a process driven from a
	/// terminal never has one, so a shadow with a nil target would report that
	/// nothing matches anything.
	private final class Sink: NSObject {
		var matches = 0
		@objc func matched(_ sender: Any?) { matches += 1 }
	}
}
