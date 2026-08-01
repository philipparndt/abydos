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
			Key.uiScale: 1.0,
			Key.terminalFontName: "",
			Key.wordWrap: false,
			Key.terminalGPURendering: false,
			Key.terminalScheme: "blue",
			Key.terminalBellStyle: "sound",
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
		static let uiScale = "uiScale"
		static let terminalFontName = "terminalFontName"
		static let wordWrap = "wordWrap"
		static let terminalGPURendering = "terminalGPURendering"
		static let terminalScheme = "terminalScheme"
		static let terminalBellStyle = "terminalBellStyle"
		static let projectSearchPaths = "projectSearchPaths"
		static let projectSearchDepth = "projectSearchDepth"
	}

	// MARK: - Zoom

	/// Multiplier applied to every dimension in the window — fonts, row heights,
	/// icons, padding, the sidebar. Driven by ⌘+ / ⌘- / ⌘0.
	///
	/// A single scalar rather than per-area font settings: zooming should move
	/// the whole interface together, the way a browser does, so proportions stay
	/// intact instead of the tree growing while its icons stay put.
	public var uiScale: Double {
		get {
			let stored = defaults.double(forKey: Key.uiScale)
			return stored == 0 ? 1.0 : max(Self.zoomSteps.first!, min(Self.zoomSteps.last!, stored))
		}
		set { set(newValue, Key.uiScale) }
	}

	/// Discrete steps, so repeated zooming lands on predictable values and
	/// always returns exactly to 1.0.
	public static let zoomSteps: [Double] = [0.75, 0.85, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]

	@discardableResult
	public func zoomIn() -> Double {
		let next = Self.zoomSteps.first { $0 > uiScale + 0.001 } ?? Self.zoomSteps.last!
		uiScale = next
		return next
	}

	@discardableResult
	public func zoomOut() -> Double {
		let next = Self.zoomSteps.last { $0 < uiScale - 0.001 } ?? Self.zoomSteps.first!
		uiScale = next
		return next
	}

	public func resetZoom() {
		uiScale = 1.0
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

	/// Terminal font family. Empty means "choose automatically".
	///
	/// Prompts like starship and powerlevel10k draw their separators with
	/// Private Use Area glyphs that only Nerd Fonts carry, so the terminal needs
	/// a different font from the editor.
	public var terminalFontName: String {
		get { defaults.string(forKey: Key.terminalFontName) ?? "" }
		set { set(newValue, Key.terminalFontName) }
	}

	/// Soft-wrap long lines in the editor.
	public var wordWrap: Bool {
		get { defaults.bool(forKey: Key.wordWrap) }
		set { set(newValue, Key.wordWrap) }
	}

	/// Which set of colours the terminal uses.
	///
	/// Its own setting rather than the editor's theme: a terminal's palette is
	/// a language of its own, and people arrive with one they already know.
	public var terminalScheme: String {
		get { defaults.string(forKey: Key.terminalScheme) ?? "blue" }
		set { set(newValue, Key.terminalScheme) }
	}

	/// What the terminal does when a program rings the bell.
	///
	/// `sound` is the system beep, `vhs` shakes the text and splits its colours
	/// like a worn tape, `none` ignores it. The visual one needs the GPU
	/// renderer: it is a shader, and the CoreGraphics path cannot do it.
	public var terminalBellStyle: String {
		get { defaults.string(forKey: Key.terminalBellStyle) ?? "sound" }
		set { set(newValue, Key.terminalBellStyle) }
	}

	/// Draw the terminal on the GPU rather than through CoreGraphics.
	///
	/// Off by default while it is new. The two paths draw the same screen; the
	/// GPU one costs the same whether every cell has its own colour or none do,
	/// which is what a full-screen program repainting constantly asks for.
	public var terminalGPURendering: Bool {
		get { defaults.bool(forKey: Key.terminalGPURendering) }
		set { set(newValue, Key.terminalGPURendering) }
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

	/// Directories scanned for checkouts the switcher can offer.
	public var projectSearchPaths: [String] {
		get { defaults.stringArray(forKey: Key.projectSearchPaths) ?? ProjectDiscovery.defaultSearchPaths }
		set { set(newValue, Key.projectSearchPaths) }
	}

	/// How far below a search path a checkout may sit.
	///
	/// Depth is the cost control: each level multiplies the directories to stat,
	/// and checkouts more than a few levels down are usually vendored copies
	/// rather than things anyone opens.
	public var projectSearchDepth: Int {
		get {
			let stored = defaults.integer(forKey: Key.projectSearchDepth)
			return stored > 0 ? stored : 3
		}
		set { set(max(1, newValue), Key.projectSearchDepth) }
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
			Key.uiScale, Key.terminalFontName, Key.wordWrap,
			Key.terminalScheme, Key.terminalGPURendering, Key.terminalBellStyle,
		] {
			defaults.removeObject(forKey: key)
		}
		NotificationCenter.default.post(name: .ideaiSettingsChanged, object: nil)
	}
}

public extension Notification.Name {
	static let ideaiSettingsChanged = Notification.Name("ideai.settingsChanged")
}
