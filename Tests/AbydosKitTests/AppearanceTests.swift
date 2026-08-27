import Foundation
import Testing
@testable import AbydosKit

/// Two questions about what the app looks like — which palette, and how light —
/// where there used to be one list with an entry per pairing.
struct AppearanceTests {
	@Test func offersFourPalettesAndThreeLightnesses() {
		#expect(Appearance.families.map(\.id) == ["abydos", "blue", "dracula", "gray"])
		#expect(Appearance.families.map(\.title) == ["Abydos", "Blue", "Dracula", "Gray"])
		#expect(Appearance.Mode.allCases.map(\.rawValue) == ["system", "light", "dark"])
	}

	/// Every pairing has a name, including the one the old list could not say
	/// at all: Abydos, following the system.
	@Test func namesEveryPairing() {
		#expect(Appearance.name(family: "blue", mode: .system) == "system")
		#expect(Appearance.name(family: "blue", mode: .light) == "light")
		#expect(Appearance.name(family: "blue", mode: .dark) == "dark")
		#expect(Appearance.name(family: "abydos", mode: .system) == "abydos-system")
		#expect(Appearance.name(family: "abydos", mode: .light) == "abydos-light")
		#expect(Appearance.name(family: "abydos", mode: .dark) == "abydos")
	}

	/// And every name decomposes again, which is also the whole of the
	/// migration: whatever was stored when this was one list means the same
	/// pair now.
	@Test func everyStoredValueDecomposes() {
		for family in Appearance.families {
			for mode in Appearance.Mode.allCases {
				let stored = Appearance.name(family: family.id, mode: mode)
				#expect(Appearance.family(of: stored) == family.id)
				#expect(Appearance.mode(of: stored) == mode)
			}
		}
	}

	/// Dracula, which people arrive with rather than discover here — and its
	/// daylight half, which upstream calls Alucard.
	@Test func draculaDecomposesLikeTheRest() {
		#expect(Appearance.name(family: "dracula", mode: .dark) == "dracula")
		#expect(Appearance.name(family: "dracula", mode: .light) == "dracula-light")
		#expect(Appearance.name(family: "dracula", mode: .system) == "dracula-system")
		#expect(Appearance.family(of: "dracula-light") == "dracula")
		#expect(Appearance.isLight("dracula-light", systemIsDark: true))
		#expect(!Appearance.isLight("dracula", systemIsDark: false))
	}

	/// Every palette names a terminal palette of its own. A family added
	/// without one silently falls back to blue, which is how somebody ends up
	/// with a Dracula editor beside a terminal nobody chose.
	@Test func everyFamilyNamesItsOwnTerminalPalette() {
		for family in Appearance.families {
			let stored = Appearance.name(family: family.id, mode: .dark)
			#expect(Appearance.terminalScheme(following: stored) == family.id)
		}
	}

	/// Something unknown is the system's business rather than a crash or a
	/// silent swap to another palette.
	@Test func treatsAnUnknownValueAsFollowingTheSystem() {
		#expect(Appearance.mode(of: "something-else") == .system)
		#expect(Appearance.family(of: "something-else") == "blue")
	}

	@Test func knowsWhichWayRoundTheContrastGoes() {
		#expect(Appearance.isLight("abydos-light", systemIsDark: true))
		#expect(!Appearance.isLight("abydos", systemIsDark: false))
		#expect(Appearance.isLight("abydos-system", systemIsDark: false))
		#expect(!Appearance.isLight("abydos-system", systemIsDark: true))
		#expect(!Appearance.isLight("system", systemIsDark: true))
	}

	/// Each family has a terminal palette of its own, and each of those knows
	/// what to do in daylight — so following the theme survives the light
	/// switch without being asked again.
	@Test func pairsEachFamilyWithATerminalPalette() {
		#expect(Appearance.terminalScheme(following: "abydos") == "abydos")
		#expect(Appearance.terminalScheme(following: "abydos-light") == "abydos")
		#expect(Appearance.terminalScheme(following: "abydos-system") == "abydos")
		#expect(Appearance.terminalScheme(following: "dark") == "blue")
		#expect(Appearance.terminalScheme(following: "light") == "blue")
		#expect(Appearance.terminalScheme(following: "system") == "blue")
	}

	/// "Follow" is a value the setting can hold, not a second switch beside it.
	@Test func resolvesFollowingToTheThemesOwnPalette() {
		#expect(Appearance.resolvedTerminalScheme(setting: "follow", stored: "abydos-light") == "abydos")
		#expect(Appearance.resolvedTerminalScheme(setting: "", stored: "dark") == "blue")
	}

	/// A palette somebody chose is used, whatever the theme is. A green-on-black
	/// terminal beside a light editor is a preference, not a mistake.
	@Test func leavesAChosenPaletteAlone() {
		#expect(Appearance.resolvedTerminalScheme(setting: "blue", stored: "abydos-light") == "blue")
		#expect(Appearance.resolvedTerminalScheme(setting: "dark", stored: "abydos") == "dark")
	}

	/// The palettes are files now, so a name nobody ships resolves to the one
	/// the app had before it had a second.
	@Test func anUnknownFamilyMeansTheDefaultOne() {
		#expect(Appearance.name(family: "nord", mode: .dark) == "dark")
		#expect(Appearance.defaultFamily == "blue")
	}

	/// "Editor colours" was called "dark" while the terminal palettes were an
	/// enum, and somebody who chose it then still has that word stored.
	@Test func answersToWhatTheEditorPaletteUsedToBeCalled() {
		#expect(Appearance.terminalSchemeIdentifier(for: "dark") == "editor")
		#expect(Appearance.terminalSchemeIdentifier(for: "abydos") == "abydos")
		#expect(Appearance.terminalSchemeIdentifier(for: Appearance.followsEditor) == "follow")
	}

	@Test func startsByFollowingTheTheme() {
		#expect(Appearance.defaultTerminalSetting == Appearance.followsEditor)
		#expect(Appearance.migratedTerminalSetting(stored: nil) == "follow")
		#expect(Appearance.migratedTerminalSetting(stored: "") == "follow")
	}

	/// Somebody who picked one two months ago keeps it.
	@Test func neverTakesAwayAChoiceAlreadyMade() {
		#expect(Appearance.migratedTerminalSetting(stored: "blue") == "blue")
		#expect(Appearance.migratedTerminalSetting(stored: "dark") == "dark")
	}
}

/// The same through the settings store, where the two questions are written
/// into the one value everything downstream reads.
struct AppearanceSettingsTests {
	private func store(_ existing: [String: Any] = [:]) -> Settings {
		// In memory rather than a named suite: a suite leaves a plist behind for
		// every test that ever ran, which `TestDefaults` exists to say.
		let defaults = TestDefaults.make()
		for (key, value) in existing { defaults.set(value, forKey: key) }
		return Settings(defaults: defaults)
	}

	@Test func changingOneQuestionLeavesTheOtherAlone() {
		let settings = store(["appearance": "abydos-light"])
		#expect(settings.themeFamily == "abydos")
		#expect(settings.appearanceMode == "light")

		settings.appearanceMode = "dark"
		#expect(settings.appearance == "abydos")
		#expect(settings.themeFamily == "abydos")

		settings.themeFamily = "blue"
		#expect(settings.appearance == "dark")
		#expect(settings.appearanceMode == "dark")
	}

	/// Somebody on the plain dark theme keeps it, and now has a palette named
	/// for it rather than an entry that only said "dark".
	@Test func anOldValueMeansTheSameThing() {
		let settings = store(["appearance": "dark"])
		#expect(settings.themeFamily == "blue")
		#expect(settings.appearanceMode == "dark")
	}

	@Test func aFreshInstallationHasTheTerminalFollowing() {
		#expect(store().terminalScheme == Appearance.followsEditor)
	}

	@Test func anExistingChoiceSurvivesTheUpgrade() {
		#expect(store(["terminalScheme": "blue"]).terminalScheme == "blue")
	}

	@Test func theMigrationOnlyHappensOnce() {
		let defaults = TestDefaults.make()
		defaults.set("blue", forKey: "terminalScheme")

		let first = Settings(defaults: defaults)
		#expect(first.terminalScheme == "blue")
		first.terminalScheme = Appearance.followsEditor

		let second = Settings(defaults: defaults)
		#expect(second.terminalScheme == Appearance.followsEditor)
	}
}

/// What a fresh installation is painted with.
///
/// Two questions that look like one: what somebody who has never chosen gets,
/// and what a value stored before schemes were files means. The first changed to
/// the Abydos scheme; the second must not, or choosing `dark` years ago would
/// silently come to mean a different palette.
struct FreshInstallationAppearanceTests {
	@Test func aFreshInstallationIsAbydos() {
		let settings = Settings(defaults: TestDefaults.make())
		#expect(settings.themeFamily == "abydos")
		#expect(settings.appearanceMode == "system")
	}

	/// The terminal follows the theme without being asked, which was already so
	/// and is asserted here because the two are one answer to somebody looking
	/// at a new window.
	@Test func aFreshInstallationsTerminalFollowsTheTheme() {
		let settings = Settings(defaults: TestDefaults.make())
		#expect(settings.terminalScheme == Appearance.followsEditor)
	}

	/// The legacy decode is untouched: `dark` was the blue scheme's dark before
	/// schemes were files, and still is.
	@Test func aValueStoredBeforeSchemesWereFilesStillMeansBlue() {
		#expect(Appearance.family(of: "dark") == "blue")
		#expect(Appearance.family(of: "light") == "blue")
		#expect(Appearance.family(of: "system") == "blue")
	}
}
