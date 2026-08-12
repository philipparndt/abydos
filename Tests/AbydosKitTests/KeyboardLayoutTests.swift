import Foundation
import Testing
@testable import AbydosKit

/// Which press types which character, on whatever layout the machine running
/// this is set to.
///
/// **Every claim here has to hold on any layout**, which is what makes them worth
/// asserting: this suite runs on a German keyboard on the machine 0479 was found
/// on and on a US one everywhere else, and a test that expected ⇧7 to make `/`
/// would be a test about one desk.
struct KeyboardLayoutTests {
	@Test func theLayoutTheKeyboardIsSetToCanBeRead() throws {
		let layout = try #require(
			KeyboardLayout.current(),
			"no Unicode key layout — the input source is presumably not a layout at all"
		)
		#expect(!layout.name.isEmpty)
	}

	/// The round trip, and the only claim that says the translation is right
	/// rather than merely answering: whatever a key types, that key is among the
	/// presses reported for what it typed.
	@Test func everyPressIsReportedForTheCharacterItTypes() throws {
		let layout = try #require(KeyboardLayout.current())
		var checked = 0
		for keyCode in UInt16(0) ... 127 {
			for shift in [false, true] {
				let press = KeyboardLayout.Press(keyCode: keyCode, shift: shift)
				let typed = layout.characters(for: press)
				guard !typed.isEmpty else { continue }
				checked += 1
				#expect(
					layout.presses(typing: typed).contains(press),
					"\(press) types “\(typed)” but is not among the presses reported for it"
				)
			}
		}
		// A layout with nothing on it would pass the loop above by never entering
		// it, which is the way this test fails to be a test.
		#expect(checked > 20, "only \(checked) keys type anything, which is not a keyboard")
	}

	/// Text Input Services aborts the process when two threads validate an input
	/// source at once, so this suite took the whole run down with signal 6 before
	/// `current()` held a lock — four tests that each passed on their own. This is
	/// the guard, and it fails the way the original did: not with an expectation
	/// but with `abort()` inside HIToolbox, which is louder than a red test and
	/// worth recognising.
	@Test func theLayoutCanBeReadFromSeveralThreadsAtOnce() async {
		await withTaskGroup(of: Bool.self) { group in
			for _ in 0 ..< 8 {
				group.addTask {
					for _ in 0 ..< 40 where KeyboardLayout.current() == nil { return false }
					return true
				}
			}
			for await answered in group { #expect(answered) }
		}
	}

	/// A character no key makes has no presses rather than a wrong one — the case
	/// a menu item declaring a key equivalent nothing on the layout can type falls
	/// into, which is how ⌘[ behaves on a German keyboard.
	@Test func aCharacterNoKeyTypesHasNoPresses() throws {
		let layout = try #require(KeyboardLayout.current())
		#expect(layout.presses(typing: "\u{1F600}").isEmpty)
		#expect(layout.presses(typing: "").isEmpty)
	}

	/// Letters are on the main block on every layout there is, so a shortcut on a
	/// letter is reachable on a laptop. Punctuation is the part that is not, and
	/// the keypad list is what lets a report say which is which.
	@Test func theKeypadIsNotWhereTheLettersAre() throws {
		let layout = try #require(KeyboardLayout.current())
		let letters = "abcdefghijklmnopqrstuvwxyz".map(String.init)
		for letter in letters {
			let presses = layout.presses(typing: letter)
			// Some layouts put a letter behind ⌥ as well as plainly; what matters
			// is that at least one way to type it is not on the keypad.
			#expect(
				presses.contains { !KeyboardLayout.numericKeypadKeyCodes.contains($0.keyCode) },
				"“\(letter)” is typable only on the numeric keypad, which cannot be"
			)
		}
	}
}
