import Testing
import Foundation
@testable import IdeaiKit

/// Settings are exercised against an isolated `UserDefaults` suite so the tests
/// never touch the real preferences.
struct SettingsTests {
	private func makeSettings() -> (Settings, UserDefaults, String) {
		let suite = "ideai.tests.\(UUID().uuidString)"
		let defaults = UserDefaults(suiteName: suite)!
		return (Settings(defaults: defaults), defaults, suite)
	}

	@Test func autoSaveIsOnByDefault() {
		let (settings, _, suite) = makeSettings()
		defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

		#expect(settings.autoSaveEnabled, "auto save must default to on")
		// Long by default, so writing a file does not set off everything
		// watching it while somebody is still typing the line.
		#expect(settings.autoSaveDelay == 15.0)
		#expect(settings.saveOnFocusLoss)
	}

	@Test func hiddenFilesShownByDefault() {
		let (settings, _, suite) = makeSettings()
		defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
		// .gitignore and .idea are part of a project and appear in IDEA too.
		#expect(settings.showHiddenFiles)
	}

	@Test func valuesRoundTrip() {
		let (settings, _, suite) = makeSettings()
		defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

		settings.autoSaveEnabled = false
		settings.autoSaveDelay = 2.5
		settings.editorFontSize = 15
		settings.tabWidth = 8
		settings.showHiddenFiles = false
		settings.excludedDirectories = ["build", "vendor"]

		#expect(settings.autoSaveEnabled == false)
		#expect(settings.autoSaveDelay == 2.5)
		#expect(settings.editorFontSize == 15)
		#expect(settings.tabWidth == 8)
		#expect(settings.showHiddenFiles == false)
		#expect(settings.excludedDirectories == ["build", "vendor"])
	}

	/// Out-of-range values would produce an unusable editor, so they clamp
	/// rather than being trusted.
	@Test func clampsOutOfRangeValues() {
		let (settings, _, suite) = makeSettings()
		defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

		settings.editorFontSize = 900
		#expect(settings.editorFontSize <= 32)

		settings.editorFontSize = 0
		#expect(settings.editorFontSize >= 8)

		settings.tabWidth = 0
		#expect(settings.tabWidth >= 1)

		settings.autoSaveDelay = 0
		#expect(settings.autoSaveDelay >= 0.2)
	}

	// MARK: - Zoom

	@Test func zoomStartsAtActualSize() {
		let (settings, _, suite) = makeSettings()
		defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
		#expect(settings.uiScale == 1.0)
	}

	@Test func zoomStepsThroughDiscreteValues() {
		let (settings, _, suite) = makeSettings()
		defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

		#expect(settings.zoomIn() == 1.1)
		#expect(settings.zoomIn() == 1.25)
		#expect(settings.zoomOut() == 1.1)
		#expect(settings.zoomOut() == 1.0)
		#expect(settings.zoomOut() == 0.9)
	}

	/// Repeated zooming must not run away past the usable range.
	@Test func zoomClampsAtBothEnds() {
		let (settings, _, suite) = makeSettings()
		defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

		for _ in 0..<20 { settings.zoomIn() }
		#expect(settings.uiScale == Settings.zoomSteps.last)

		for _ in 0..<40 { settings.zoomOut() }
		#expect(settings.uiScale == Settings.zoomSteps.first)
	}

	@Test func resetZoomReturnsExactlyToOne() {
		let (settings, _, suite) = makeSettings()
		defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

		settings.zoomIn()
		settings.zoomIn()
		settings.resetZoom()
		// Exactly 1.0, not merely close: it is the documented "Actual Size".
		#expect(settings.uiScale == 1.0)
	}

	@Test func zoomIsClampedWhenSetDirectly() {
		let (settings, _, suite) = makeSettings()
		defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

		settings.uiScale = 99
		#expect(settings.uiScale <= Settings.zoomSteps.last!)

		settings.uiScale = 0.01
		#expect(settings.uiScale >= Settings.zoomSteps.first!)
	}

	@Test func resetRestoresDefaults() {
		let (settings, _, suite) = makeSettings()
		defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

		settings.autoSaveEnabled = false
		settings.tabWidth = 8
		settings.resetToDefaults()

		#expect(settings.autoSaveEnabled)
		#expect(settings.tabWidth == 4)
	}

	@Test func changesPostNotification() async {
		let (settings, _, suite) = makeSettings()
		defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

		// Open windows rely on this to apply preferences without a restart.
		// The notification is global and tests run in parallel, so other suites
		// touching settings can post it too — hence "at least once".
		await confirmation("settings change is announced", expectedCount: 1...) { confirmed in
			let token = NotificationCenter.default.addObserver(
				forName: .ideaiSettingsChanged, object: nil, queue: nil
			) { _ in confirmed() }
			defer { NotificationCenter.default.removeObserver(token) }

			settings.tabWidth = 2
		}
	}
}

/// Auto-save behaviour on a real file.
struct AutoSaveTests {
	/// Each document gets its own settings suite, so these tests neither read
	/// nor disturb the real preferences and can run in parallel.
	private func makeDocument(_ contents: String, autoSave: Bool) throws -> (TextDocument, URL, String) {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("ideai-autosave-\(UUID().uuidString).swift")
		try contents.write(to: url, atomically: true, encoding: .utf8)

		let suite = "ideai.tests.\(UUID().uuidString)"
		let settings = Settings(defaults: UserDefaults(suiteName: suite)!)
		settings.autoSaveEnabled = autoSave

		let document = try TextDocument(url: url)
		document.settings = settings
		return (document, url, suite)
	}

	@Test func autoSaveIfNeededWritesAndClearsDirty() throws {
		let (document, url, suite) = try makeDocument("let a = 1\n", autoSave: true)
		defer {
			try? FileManager.default.removeItem(at: url)
			UserDefaults.standard.removePersistentDomain(forName: suite)
		}

		document.replace(utf16Range: 0..<0, with: "// added\n", caretBefore: 0)
		#expect(document.isDirty)

		#expect(document.autoSaveIfNeeded())
		#expect(!document.isDirty)

		let onDisk = try String(contentsOf: url, encoding: .utf8)
		#expect(onDisk.hasPrefix("// added"))
	}

	@Test func autoSaveIsSkippedWhenDisabled() throws {
		let (document, url, suite) = try makeDocument("let a = 1\n", autoSave: false)
		defer {
			try? FileManager.default.removeItem(at: url)
			UserDefaults.standard.removePersistentDomain(forName: suite)
		}

		document.replace(utf16Range: 0..<0, with: "// added\n", caretBefore: 0)
		#expect(document.autoSaveIfNeeded() == false, "must not write when disabled")
		#expect(document.isDirty, "the file stays dirty so ⌘S still has work to do")

		let onDisk = try String(contentsOf: url, encoding: .utf8)
		#expect(!onDisk.contains("// added"))
	}

	@Test func autoSaveIsANoOpWhenClean() throws {
		let (document, url, suite) = try makeDocument("let a = 1\n", autoSave: true)
		defer {
			try? FileManager.default.removeItem(at: url)
			UserDefaults.standard.removePersistentDomain(forName: suite)
		}

		#expect(document.autoSaveIfNeeded() == false, "nothing to write")
	}

	@Test func savePreservesBytesExactly() throws {
		// Round-tripping must not normalise line endings or re-encode.
		let (document, url, suite) = try makeDocument("alpha\r\nbeta\r\n", autoSave: false)
		defer {
			try? FileManager.default.removeItem(at: url)
			UserDefaults.standard.removePersistentDomain(forName: suite)
		}

		document.replace(utf16Range: 0..<0, with: "x", caretBefore: 0)
		try document.save()

		let data = try Data(contentsOf: url)
		#expect(String(decoding: data, as: UTF8.self) == "xalpha\r\nbeta\r\n")
	}
}

/// Whether choosing a project takes over the window or opens another.
struct ProjectWindowSettingTests {
	private func settings() -> Settings {
		let defaults = UserDefaults(suiteName: "ideai.tests.\(UUID().uuidString)")!
		return Settings(defaults: defaults)
	}

	/// Switching in place is the default: the window is where the work was.
	@Test func switchesInPlaceByDefault() {
		#expect(settings().opensProjectsInNewWindow == false)
	}

	@Test func remembersTheChoice() {
		let settings = settings()
		settings.opensProjectsInNewWindow = true
		#expect(settings.opensProjectsInNewWindow)
	}
}
