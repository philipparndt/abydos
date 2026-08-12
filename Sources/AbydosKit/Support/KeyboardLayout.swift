import Carbon.HIToolbox
import Foundation

/// Which physical press types which character, according to the keyboard layout
/// this machine is set to.
///
/// This exists because a menu's key equivalent is a *character* and a keystroke
/// is a *key*, and on most of the world's layouts those are not the same thing.
/// `⌘/` is one press on a US keyboard and ⌘⇧7 on a German one, and 0479 is the
/// account of what happens when nobody checks: the shortcut was declared `"/"`,
/// the system moved it to ⌘ß because that needs no shift, and the person who
/// asked for ⌘/ pressed ⌘⇧7 and got nothing. Neither the declaration nor the
/// menu was enough to tell — only the layout can say which press reaches which
/// character, so it is asked.
///
/// Read once and kept: the layout data is a `CFData` from the input source, and
/// asking Text Input Services for it per keystroke would be a syscall on a path
/// that has none. It does not follow a layout change at runtime, so anything
/// long-lived should read `current()` again rather than hold one of these — the
/// callers today are diagnostics that run and print.
public struct KeyboardLayout: Sendable {
	/// The name the input source calls itself: `German`, `U.S.`, `British`.
	public let name: String

	/// `UCKeyboardLayout`, as the input source handed it over.
	private let data: Data

	/// A press: a key on the keyboard, and which of the two modifiers that
	/// change the character it produces were held.
	///
	/// Command and control are not in here on purpose. Neither changes the
	/// character a key types — ⌘7 types `7` — so neither belongs in a
	/// description of what a key *makes*. Which modifiers a shortcut *wants* is
	/// the menu item's business, not the layout's.
	public struct Press: Hashable, Sendable {
		public let keyCode: UInt16
		public let shift: Bool
		public let option: Bool

		public init(keyCode: UInt16, shift: Bool = false, option: Bool = false) {
			self.keyCode = keyCode
			self.shift = shift
			self.option = option
		}
	}

	/// Text Input Services validates an input source against a list it keeps, and
	/// **it aborts the process if two threads ask at once** — not a crash in the
	/// caller's code but `abort()` inside `isValidateInputSourceRef`, with no
	/// exception and nothing pointing back here. Four tests that each passed alone
	/// took the whole suite down with signal 6 together, which is how this was
	/// found. `UCKeyTranslate` is fine; only the asking is not, so the lock is
	/// only around the asking.
	private static let inputSources = NSLock()

	/// The layout the keyboard is set to now, or nothing if Text Input Services
	/// will not say — which happens for input methods that are not a layout at
	/// all, such as Pinyin, where there is no key-to-character table to hand out.
	public static func current() -> KeyboardLayout? {
		inputSources.lock()
		defer { inputSources.unlock() }
		guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
		      let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
		else { return nil }
		let name = TISGetInputSourceProperty(source, kTISPropertyLocalizedName)
			.map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
		return KeyboardLayout(
			name: name ?? "unknown",
			data: Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
		)
	}

	public init(name: String, data: Data) {
		self.name = name
		self.data = data
	}

	/// What this press types, or the empty string if it types nothing.
	///
	/// Dead keys are translated as though they were not: on a German layout the
	/// key beside `p` is a dead acute, and a caller asking what it makes wants
	/// `´` rather than nothing at all while the layout waits for a vowel.
	public func characters(for press: Press) -> String {
		var carbon: UInt32 = 0
		if press.shift { carbon |= UInt32(shiftKey >> 8) }
		if press.option { carbon |= UInt32(optionKey >> 8) }

		var deadKeyState: UInt32 = 0
		var length = 0
		var buffer = [UniChar](repeating: 0, count: 8)
		let status = data.withUnsafeBytes { raw -> OSStatus in
			guard let base = raw.baseAddress else { return -1 }
			return UCKeyTranslate(
				base.assumingMemoryBound(to: UCKeyboardLayout.self),
				press.keyCode,
				UInt16(kUCKeyActionDown),
				carbon,
				UInt32(LMGetKbdType()),
				OptionBits(kUCKeyTranslateNoDeadKeysBit),
				&deadKeyState,
				buffer.count,
				&length,
				&buffer
			)
		}
		guard status == noErr, length > 0 else { return "" }
		return String(utf16CodeUnits: buffer, count: length)
	}

	/// Every press that types this character, lowest key code first.
	///
	/// Usually more than one, and the extras matter: `/` on a German keyboard is
	/// ⇧7 on the main block *and* the divide key on a numeric keypad, and a
	/// shortcut reachable only on the keypad is one a laptop cannot press.
	public func presses(typing character: String) -> [Press] {
		guard !character.isEmpty else { return [] }
		var found: [Press] = []
		// The whole key code space, because there is no list of the keys a
		// layout defines — 0…127 is what `UCKeyTranslate` accepts and the ones
		// that are not keys translate to nothing.
		for keyCode in UInt16(0) ... 127 {
			for shift in [false, true] {
				for option in [false, true] {
					let press = Press(keyCode: keyCode, shift: shift, option: option)
					if characters(for: press) == character { found.append(press) }
				}
			}
		}
		return found
	}

	/// Which keys are on the main block rather than the numeric keypad.
	///
	/// The keypad's codes are a fixed set on every layout, so this is a list and
	/// not a lookup. It exists so a report can say that a shortcut is reachable
	/// *only* on a keypad, which on a laptop means not at all.
	public static let numericKeypadKeyCodes: Set<UInt16> = [
		65, 67, 69, 71, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92,
	]
}
