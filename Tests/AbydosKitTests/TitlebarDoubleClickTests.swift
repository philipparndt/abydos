import AppKit
import Foundation
import Testing
@testable import AbydosKit

/// What a double-click on the titlebar means.
///
/// The window's top strip is a view this app draws, so the gesture has to be
/// answered by hand — and answered the way the machine answers it everywhere
/// else, which is a setting rather than a preference of this app's.
struct TitlebarDoubleClickTests {
	static func defaults(_ value: String?) -> UserDefaults {
		let suite = UserDefaults(suiteName: "titlebar-\(UUID().uuidString)")!
		if let value { suite.set(value, forKey: "AppleActionOnDoubleClick") }
		return suite
	}

	@Test func readsWhatTheSystemWasToldToDo() {
		#expect(TitlebarDoubleClick.action(from: Self.defaults("Maximize")) == .zoom)
		#expect(TitlebarDoubleClick.action(from: Self.defaults("Minimize")) == .minimise)
		#expect(TitlebarDoubleClick.action(from: Self.defaults("None")) == .nothing)
	}

	/// Unset is the state a Mac ships in, and that Mac zooms.
	@Test func zoomsWhenNobodyHasSaidOtherwise() {
		#expect(TitlebarDoubleClick.action(from: Self.defaults(nil)) == .zoom)
	}

	/// A value nobody here knows is not a reason to do nothing: the gesture
	/// should still do the usual thing rather than appear broken.
	@Test func fallsBackToZoomOnSomethingUnrecognised() {
		#expect(TitlebarDoubleClick.action(from: Self.defaults("Fullscreen")) == .zoom)
	}

	@MainActor
	@Test func zoomsTheWindowItIsGiven() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		let before = window.frame
		TitlebarDoubleClick.perform(on: window, action: .zoom)
		#expect(window.frame != before)

		// And back again, which is what zoom means: the same gesture twice
		// leaves a window where it was.
		TitlebarDoubleClick.perform(on: window, action: .zoom)
		#expect(window.frame == before)
	}

	@MainActor
	@Test func doesNothingWhenThatIsWhatWasAskedFor() {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		let before = window.frame
		TitlebarDoubleClick.perform(on: window, action: .nothing)
		#expect(window.frame == before)
	}
}
