import Foundation
import Testing
@testable import AbydosKit

/// One decision about what the app looks like, with the terminal free to differ.
struct AppearanceTests {
	@Test func offersTheDarkAndLightOfEachPalette() {
		let names = Appearance.Theme.allCases.map(\.rawValue)
		#expect(names == ["system", "dark", "light", "abydos", "abydos-light"])
		#expect(Appearance.Theme.abydosLight.title == "Abydos Light")
	}

	@Test func knowsWhichWayRoundTheContrastGoes() {
		#expect(!Appearance.Theme.abydos.isLight(systemIsDark: false))
		#expect(Appearance.Theme.abydosLight.isLight(systemIsDark: true))
		#expect(Appearance.Theme.light.isLight(systemIsDark: true))
		// The one that defers takes the system's answer, whichever it is.
		#expect(Appearance.Theme.system.isLight(systemIsDark: false))
		#expect(!Appearance.Theme.system.isLight(systemIsDark: true))
	}

	/// Abydos pairs with Abydos; the plain palettes pair with the terminal
	/// scheme that takes the editor's own colours, so light and dark follow by
	/// themselves.
	@Test func pairsEachThemeWithATerminalPalette() {
		#expect(Appearance.terminalScheme(following: .abydos) == "abydos")
		#expect(Appearance.terminalScheme(following: .abydosLight) == "abydos")
		#expect(Appearance.terminalScheme(following: .dark) == "dark")
		#expect(Appearance.terminalScheme(following: .light) == "dark")
		#expect(Appearance.terminalScheme(following: .system) == "dark")
	}

	/// "Follow" is a value the setting can hold, not a second switch beside it.
	@Test func resolvesFollowingToWhateverTheThemeUses() {
		#expect(Appearance.resolvedTerminalScheme(setting: "follow", theme: .abydosLight) == "abydos")
		#expect(Appearance.resolvedTerminalScheme(setting: "", theme: .dark) == "dark")
	}

	/// A palette somebody chose is used, whatever the theme is. A green-on-black
	/// terminal beside a light editor is a preference, not a mistake.
	@Test func leavesAChosenPaletteAlone() {
		#expect(Appearance.resolvedTerminalScheme(setting: "blue", theme: .abydosLight) == "blue")
		#expect(Appearance.resolvedTerminalScheme(setting: "abydos", theme: .light) == "abydos")
	}

	/// A new installation follows the theme…
	@Test func startsByFollowingTheTheme() {
		#expect(Appearance.defaultTerminalSetting == Appearance.followsEditor)
		#expect(Appearance.migratedTerminalSetting(stored: nil) == "follow")
		#expect(Appearance.migratedTerminalSetting(stored: "") == "follow")
	}

	/// …and somebody who picked one two months ago keeps it. An upgrade that
	/// repaints a terminal they chose is a bug with a nice explanation.
	@Test func neverTakesAwayAChoiceAlreadyMade() {
		#expect(Appearance.migratedTerminalSetting(stored: "blue") == "blue")
		#expect(Appearance.migratedTerminalSetting(stored: "dark") == "dark")
	}
}

/// The same, through the settings store, since the migration turns on a
/// difference that is only visible before the defaults are registered.
struct AppearanceSettingsTests {
	private func store(_ existing: [String: Any] = [:]) -> Settings {
		let name = "abydos-appearance-\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: name)!
		for (key, value) in existing { defaults.set(value, forKey: key) }
		return Settings(defaults: defaults)
	}

	@Test func aFreshInstallationHasTheTerminalFollowing() {
		#expect(store().terminalScheme == Appearance.followsEditor)
	}

	@Test func anExistingChoiceSurvivesTheUpgrade() {
		#expect(store(["terminalScheme": "blue"]).terminalScheme == "blue")
	}

	/// And it stays survived: the migration runs once, so a later "follow" set
	/// by hand is not undone by the next launch.
	@Test func theMigrationOnlyHappensOnce() {
		let name = "abydos-appearance-\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: name)!
		defaults.set("blue", forKey: "terminalScheme")

		let first = Settings(defaults: defaults)
		#expect(first.terminalScheme == "blue")
		first.terminalScheme = Appearance.followsEditor

		let second = Settings(defaults: defaults)
		#expect(second.terminalScheme == Appearance.followsEditor)
	}
}
