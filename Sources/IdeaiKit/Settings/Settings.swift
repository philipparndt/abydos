import Foundation

/// User preferences, persisted in `UserDefaults`.
///
/// Every setting here is actually wired to behaviour — a preferences window full
/// of controls that do nothing is worse than no preferences window. Changes post
/// `.ideaiSettingsChanged` so open windows can apply them live rather than
/// requiring a restart.
public final class Settings {
	public static let shared = Settings()

	private let defaults: UserDefaults

	public init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
		defaults.register(defaults: [
			Key.autoSaveEnabled: true,
			Key.autoSaveDelay: 1.0,
			Key.saveOnFocusLoss: true,
			Key.editorFontSize: 12.5,
			Key.editorLineHeight: 1.4,
			Key.tabWidth: 4,
			Key.showHiddenFiles: true,
			Key.excludedDirectories: Array(FileNode.defaultExcludedDirectoryNames).sorted(),
		])
	}

	private enum Key {
		static let autoSaveEnabled = "autoSaveEnabled"
		static let autoSaveDelay = "autoSaveDelay"
		static let saveOnFocusLoss = "saveOnFocusLoss"
		static let editorFontSize = "editorFontSize"
		static let editorLineHeight = "editorLineHeight"
		static let tabWidth = "tabWidth"
		static let showHiddenFiles = "showHiddenFiles"
		static let excludedDirectories = "excludedDirectories"
	}

	// MARK: - Saving

	/// On by default: this is a browser first, and losing edits to a file you
	/// tweaked while reading is the worst possible surprise.
	public var autoSaveEnabled: Bool {
		get { defaults.bool(forKey: Key.autoSaveEnabled) }
		set { set(newValue, Key.autoSaveEnabled) }
	}

	/// Idle time before an edited file is written, in seconds.
	public var autoSaveDelay: TimeInterval {
		get { max(0.2, min(30, defaults.double(forKey: Key.autoSaveDelay))) }
		set { set(newValue, Key.autoSaveDelay) }
	}

	/// Also write when the app loses focus, so switching to a terminal always
	/// finds the file on disk up to date.
	public var saveOnFocusLoss: Bool {
		get { defaults.bool(forKey: Key.saveOnFocusLoss) }
		set { set(newValue, Key.saveOnFocusLoss) }
	}

	// MARK: - Editor

	public var editorFontSize: Double {
		get { max(8, min(32, defaults.double(forKey: Key.editorFontSize))) }
		set { set(newValue, Key.editorFontSize) }
	}

	public var editorLineHeight: Double {
		get { max(1.0, min(2.5, defaults.double(forKey: Key.editorLineHeight))) }
		set { set(newValue, Key.editorLineHeight) }
	}

	public var tabWidth: Int {
		get { max(1, min(16, defaults.integer(forKey: Key.tabWidth))) }
		set { set(newValue, Key.tabWidth) }
	}

	// MARK: - Navigator

	/// Dotfiles are shown by default: `.gitignore` and friends are part of a
	/// project, and IDEA shows them too.
	public var showHiddenFiles: Bool {
		get { defaults.bool(forKey: Key.showHiddenFiles) }
		set { set(newValue, Key.showHiddenFiles) }
	}

	/// Directory names treated as build output and tinted accordingly.
	public var excludedDirectories: [String] {
		get { defaults.stringArray(forKey: Key.excludedDirectories) ?? [] }
		set { set(newValue, Key.excludedDirectories) }
	}

	// MARK: - Change notification

	private func set(_ value: Any, _ key: String) {
		defaults.set(value, forKey: key)
		NotificationCenter.default.post(name: .ideaiSettingsChanged, object: nil)
	}

	/// Restores every setting to its registered default.
	public func resetToDefaults() {
		for key in [
			Key.autoSaveEnabled, Key.autoSaveDelay, Key.saveOnFocusLoss,
			Key.editorFontSize, Key.editorLineHeight, Key.tabWidth,
			Key.showHiddenFiles, Key.excludedDirectories,
		] {
			defaults.removeObject(forKey: key)
		}
		NotificationCenter.default.post(name: .ideaiSettingsChanged, object: nil)
	}
}

public extension Notification.Name {
	static let ideaiSettingsChanged = Notification.Name("ideai.settingsChanged")
}
