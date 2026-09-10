import Foundation
import Testing
@testable import AbydosKit

/// What a double-click on the empty part of the tab strip does, as a setting.
///
/// Asked for 2026-09-10: the gesture was hard-wired to a project scratch, and
/// the maintainer reaches for it to expand the editor.
struct TabStripDoubleClickTests {
	private func makeSettings() -> (Settings, UserDefaults) {
		let defaults = TestDefaults.make()
		return (Settings(defaults: defaults), defaults)
	}

	@Test func theDefaultIsToExpandTheEditor() {
		let (settings, _) = makeSettings()
		#expect(settings.tabStripDoubleClick == .maximize)
	}

	@Test func aChoiceIsKeptAsItsRawValue() {
		let (settings, defaults) = makeSettings()
		settings.tabStripDoubleClick = .globalScratch
		#expect(defaults.string(forKey: "tabStripDoubleClick") == "globalScratch")
		#expect(settings.tabStripDoubleClick == .globalScratch)
	}

	/// A build with more or fewer values wrote something this one does not
	/// know: that reads as the default, not as nothing.
	@Test func anUnknownStoredValueReadsAsTheDefault() {
		let (settings, defaults) = makeSettings()
		defaults.set("teleport", forKey: "tabStripDoubleClick")
		#expect(settings.tabStripDoubleClick == .maximize)
	}

	/// The page words them as the things they do.
	@Test func everyValueHasALabelThatIsNotItsIdentifier() {
		for value in TabStripDoubleClick.allCases {
			#expect(value.label != value.rawValue)
			#expect(value.label.contains(" "))
		}
	}
}
