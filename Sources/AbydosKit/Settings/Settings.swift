import Foundation

/// User preferences, persisted in `UserDefaults`.
///
/// Every setting here is actually wired to behaviour — a preferences window full
/// of controls that do nothing is worse than no preferences window. Changes post
/// `.abydosSettingsChanged` so open windows can apply them live rather than
/// requiring a restart.
public final class Settings {
	public static let shared = Settings()

	private let defaults: UserDefaults

	/// Brings settings over from the identifier the app used to have.
	///
	/// Preferences are keyed by bundle identifier, so changing one — which is
	/// what going to the App Store took — would otherwise look to somebody
	/// using the app like every setting being reset at once. Copied once: the
	/// old domain is left alone, so an older build still works, and anything
	/// already set in the new one wins.
	public static func migrate(
		from oldIdentifier: String,
		into defaults: UserDefaults = .standard
	) {
		guard defaults.object(forKey: Key.appearance) == nil,
		      defaults.object(forKey: Key.terminalScheme) == nil,
		      defaults.object(forKey: Key.uiScale) == nil
		else { return }
		guard let old = defaults.persistentDomain(forName: oldIdentifier), !old.isEmpty else { return }

		for (key, value) in old where defaults.object(forKey: key) == nil {
			defaults.set(value, forKey: key)
		}
	}

	public init(defaults: UserDefaults = .standard) {
		self.defaults = defaults

		// Before the defaults are registered, which is the only moment the
		// difference is visible: a registered value answers `object(forKey:)`
		// exactly as a chosen one does. Somebody who never picked a terminal
		// palette now follows the editor — that is what "by default they change
		// together" means — and somebody who picked one keeps it, because an
		// upgrade that repaints a terminal they chose is a bug with a nice
		// explanation.
		if defaults.object(forKey: Key.terminalSchemeFollowed) == nil {
			let chosen = defaults.object(forKey: Key.terminalScheme) as? String
			defaults.set(Appearance.migratedTerminalSetting(stored: chosen), forKey: Key.terminalScheme)
			defaults.set(true, forKey: Key.terminalSchemeFollowed)
		}

		defaults.register(defaults: [
			Key.autoSaveEnabled: true,
			Key.autoSaveDelay: 15.0,
			Key.saveOnFocusLoss: true,
			Key.editorFontSize: 12.5,
			Key.editorLineHeight: 1.4,
			Key.tabWidth: 4,
			Key.showHiddenFiles: true,
			Key.excludedDirectories: Array(FileNode.defaultExcludedDirectoryNames).sorted(),
			Key.uiScale: 1.0,
			// Big enough to read from the back of a room, and light, because a
			// projector washes a dark theme out to a grey smear.
			Key.presenting: false,
			Key.presentationScale: 1.5,
			Key.presentationAppearance: "light",
			Key.terminalFontName: "",
			Key.wordWrap: false,
			Key.terminalGPURendering: false,
			Key.terminalOptionAsMeta: false,
			Key.appearance: "system",
			Key.followsTerminalProject: false,
			Key.terminalAtStartup: "open",
			Key.tmuxTabsAtBottom: true,
			Key.startsTmux: false,
			Key.strictTmux: false,
			Key.terminalScheme: Appearance.defaultTerminalSetting,
			Key.terminalBellStyle: "sound",
			Key.opensProjectsInNewWindow: false,
			Key.showsInlineDiagnostics: true,
			Key.agentPermissions: "acceptEdits",
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
		static let opensProjectsInNewWindow = "opensProjectsInNewWindow"
		static let showsInlineDiagnostics = "showsInlineDiagnostics"
		static let agentPermissions = "agentPermissions"
		static let excludedDirectories = "excludedDirectories"
		static let uiScale = "uiScale"
		static let presenting = "presenting"
		static let presentationScale = "presentationScale"
		static let presentationAppearance = "presentationAppearance"
		static let terminalFontName = "terminalFontName"
		static let wordWrap = "wordWrap"
		static let terminalGPURendering = "terminalGPURendering"
		static let terminalOptionAsMeta = "terminalOptionAsMeta"
		static let toolImages = "toolImages"
		static let containerRuntime = "containerRuntime"
		static let appearance = "appearance"
		static let followsTerminalProject = "followsTerminalProject"
		static let terminalAtStartup = "terminalAtStartup"
		static let tmuxTabsAtBottom = "tmuxTabsAtBottom"
		static let hidesTmuxStatus = "hidesTmuxStatus"
		static let startsTmux = "startsTmux"
		static let strictTmux = "strictTmux"
		static let terminalScheme = "terminalScheme"
		/// Set once, when the choice above was allowed to mean "follow the editor".
		static let terminalSchemeFollowed = "terminalSchemeFollowed"
		static let terminalBellStyle = "terminalBellStyle"
		static let projectSearchPaths = "projectSearchPaths"
		static let ignoredLanguageServers = "ignoredLanguageServers"
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

	// MARK: - Presentation

	/// Whether the window is set up to be shown to a room rather than worked in.
	///
	/// Presenting is a different set of the same two preferences — bigger, and
	/// light, because a projector turns a dark theme into a grey smear — and
	/// the point is that going back afterwards is exact. So it is a second set
	/// held alongside the first rather than a mode that saves the first
	/// somewhere and puts it back: nothing to restore, and nothing that can
	/// leave a talk's zoom behind after the talk.
	public var presenting: Bool {
		get { presentingOverride ?? defaults.bool(forKey: Key.presenting) }
		set { set(newValue, Key.presenting) }
	}

	/// Presentation mode forced on for one run, without storing it.
	///
	/// The screenshot harness shares this preferences domain with the installed
	/// app — same bundle, same defaults — so a test that simply switched the
	/// mode on would leave somebody's editor presenting to an empty room.
	public var presentingOverride: Bool?

	/// The zoom used while presenting, kept apart from the working one so that
	/// zooming during a talk does not resize the desk you go back to.
	public var presentationScale: Double {
		get {
			let stored = defaults.double(forKey: Key.presentationScale)
			return stored == 0 ? 1.5 : max(Self.zoomSteps.first!, min(Self.zoomSteps.last!, stored))
		}
		set { set(newValue, Key.presentationScale) }
	}

	/// The palette used while presenting: light, dark, or the system's.
	public var presentationAppearance: String {
		get { defaults.string(forKey: Key.presentationAppearance) ?? "light" }
		set { set(newValue, Key.presentationAppearance) }
	}

	/// The zoom actually in force, and the one the zoom commands move.
	///
	/// Everything that draws asks for this rather than for `uiScale`, so ⌘+ in
	/// the middle of a talk makes the talk bigger and leaves the desk alone.
	public var activeScale: Double {
		get { presenting ? presentationScale : uiScale }
		set { if presenting { presentationScale = newValue } else { uiScale = newValue } }
	}

	/// The palette actually in force.
	public var activeAppearance: String {
		presenting ? presentationAppearance : appearance
	}

	/// Which palette, and how light, as two settings over the one that is
	/// stored. Everything downstream still reads a single name.
	public var themeFamily: String {
		get { Appearance.family(of: appearance).rawValue }
		set {
			let family = Appearance.Family(rawValue: newValue) ?? .blue
			appearance = Appearance.name(family: family, mode: Appearance.mode(of: appearance))
		}
	}

	public var appearanceMode: String {
		get { Appearance.mode(of: appearance).rawValue }
		set {
			let mode = Appearance.Mode(rawValue: newValue) ?? .system
			appearance = Appearance.name(family: Appearance.family(of: appearance), mode: mode)
		}
	}

	@discardableResult
	public func zoomIn() -> Double {
		let next = Self.zoomSteps.first { $0 > activeScale + 0.001 } ?? Self.zoomSteps.last!
		activeScale = next
		return next
	}

	@discardableResult
	public func zoomOut() -> Double {
		let next = Self.zoomSteps.last { $0 < activeScale - 0.001 } ?? Self.zoomSteps.first!
		activeScale = next
		return next
	}

	public func resetZoom() {
		activeScale = presenting ? 1.5 : 1.0
	}

	// MARK: - Saving

	/// On by default: this is a browser first, and losing edits to a file you
	/// tweaked while reading is the worst possible surprise.
	public var autoSaveEnabled: Bool {
		get { defaults.bool(forKey: Key.autoSaveEnabled) }
		set { set(newValue, Key.autoSaveEnabled) }
	}

	/// Idle time before an edited file is written, in seconds.
	///
	/// Fifteen, which is what IDEA uses, and for the reason IDEA uses it: a
	/// file on disk is watched by other things — a test runner, a bundler, a
	/// preview — and writing it a second after every pause in typing sets all
	/// of them off on text that is half-written. The save that matters is the
	/// one before you switch away or run something, and both of those happen
	/// regardless of this timer.
	public var autoSaveDelay: TimeInterval {
		get { max(0.2, min(600, defaults.double(forKey: Key.autoSaveDelay))) }
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
		get { defaults.string(forKey: Key.terminalScheme) ?? Appearance.defaultTerminalSetting }
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

	/// Whether Option means Meta rather than what the keyboard layout says.
	///
	/// Off, because a layout that puts `{` behind ⌥8 — German, Swiss, Nordic —
	/// otherwise cannot type a brace into a shell at all. On, for anybody who
	/// would rather have ⌥B and ⌥F move by words, which is what a US layout
	/// gives up nothing for.
	public var terminalOptionAsMeta: Bool {
		get { defaults.bool(forKey: Key.terminalOptionAsMeta) }
		set { set(newValue, Key.terminalOptionAsMeta) }
	}

	/// Container images to get tools from, for somebody who would rather not
	/// install them: tool name to image, as `docker pull` would name it.
	///
	/// A project that names its own in `.abydos/tools.json` overrides this —
	/// what a checked-in diagram is drawn by is the project's business, not a
	/// personal preference.
	/// Which container runtime tools come from, when they come from an image.
	///
	/// "Whichever is installed" unless somebody says otherwise — and somebody
	/// who says Docker and has none is told so, rather than quietly given the
	/// other one.
	public var containerRuntime: String {
		get { defaults.string(forKey: Key.containerRuntime) ?? "automatic" }
		set { set(newValue, Key.containerRuntime) }
	}

	public var toolImages: [String: String] {
		get { defaults.dictionary(forKey: Key.toolImages) as? [String: String] ?? [:] }
		set { set(newValue, Key.toolImages) }
	}

	/// How the terminal arrives when a window opens.
	///
	/// `closed`, `open`, or `full` — the last giving it the whole window, for
	/// somebody whose day starts in a shell and who reaches for the editor
	/// afterwards.
	/// Whether somebody has asked for tmux's own status bar to be out of the
	/// way while the panel's tabs are showing the same windows.
	///
	/// A wish rather than the state of their tmux: it is remembered while the
	/// tabs are switched off — when the bar has to come back — so switching
	/// them on again puts things as they were.
	public var hidesTmuxStatus: Bool {
		get { defaults.bool(forKey: Key.hidesTmuxStatus) }
		set { set(newValue, Key.hidesTmuxStatus) }
	}

	/// Whether tmux's windows get a strip of their own along the bottom,
	/// leaving the top strip for what the panel holds.
	public var tmuxTabsAtBottom: Bool {
		get { defaults.bool(forKey: Key.tmuxTabsAtBottom) }
		set { set(newValue, Key.tmuxTabsAtBottom) }
	}

	public var terminalAtStartup: String {
		get { defaults.string(forKey: Key.terminalAtStartup) ?? "open" }
		set { set(newValue, Key.terminalAtStartup) }
	}

	/// Whether the first terminal of a window attaches to tmux.
	///
	/// Only the first: the ones opened afterwards are for the odd job that
	/// should not join the session. One session per project, so reopening a
	/// project comes back to the panes it was left with.
	public var startsTmux: Bool {
		get { defaults.bool(forKey: Key.startsTmux) }
		set { set(newValue, Key.startsTmux) }
	}

	/// Whether the terminal's tabs are tmux's windows.
	///
	/// In this mode there is one terminal and one pty; the strip shows what
	/// tmux has and switching a tab switches tmux's window. Nothing is torn
	/// down or built up to change tabs, which is why it costs nothing — and
	/// why a window renamed in tmux renames the tab.
	public var strictTmux: Bool {
		get { defaults.bool(forKey: Key.strictTmux) }
		set { set(newValue, Key.strictTmux) }
	}

	/// Dark, light, or whatever the system is set to.
	///
	/// `system` by default: a machine that turns dark at sunset should take the
	/// editor with it, and somebody who disagrees says so once.
	public var appearance: String {
		get { defaults.string(forKey: Key.appearance) ?? "system" }
		set { set(newValue, Key.appearance) }
	}

	/// Whether a new window follows the terminal into whatever project it is
	/// standing in.
	///
	/// Off by default, because a window that changes project on its own is a
	/// surprise the first time. Somebody who works by `cd`-ing to the thing
	/// they want turns it on once and never thinks about it again.
	public var followsTerminalProject: Bool {
		get { defaults.bool(forKey: Key.followsTerminalProject) }
		set { set(newValue, Key.followsTerminalProject) }
	}

	// MARK: - Navigator

	/// Dotfiles are shown by default: `.gitignore` and friends are part of a
	/// project, and IDEA shows them too.
	public var showHiddenFiles: Bool {
		get { defaults.bool(forKey: Key.showHiddenFiles) }
		set { set(newValue, Key.showHiddenFiles) }
	}

	/// Whether choosing another project opens a window or replaces this one.
	///
	/// Replacing by default: the window is where you were working, and a
	/// second one for the same task is a window to close later. Somebody with
	/// two projects open side by side wants the opposite, which is what the
	/// setting is for.
	public var opensProjectsInNewWindow: Bool {
		get { defaults.bool(forKey: Key.opensProjectsInNewWindow) }
		set { set(newValue, Key.opensProjectsInNewWindow) }
	}

	/// How much an agent may do without being asked.
	///
	/// `acceptEdits` by default: an agent asked to fix one problem that then
	/// stops to ask whether it may edit the file is an agent that has not been
	/// asked anything. `ask` is the tool's own behaviour, and `full` is
	/// everything, including commands.
	public var agentPermissions: String {
		get { defaults.string(forKey: Key.agentPermissions) ?? "acceptEdits" }
		set { set(newValue, Key.agentPermissions) }
	}

	/// Whether a problem's message is written beside the line it is on.
	public var showsInlineDiagnostics: Bool {
		get { defaults.bool(forKey: Key.showsInlineDiagnostics) }
		set { set(newValue, Key.showsInlineDiagnostics) }
	}

	/// Directory names treated as build output and tinted accordingly.
	public var excludedDirectories: [String] {
		get { defaults.stringArray(forKey: Key.excludedDirectories) ?? [] }
		set { set(newValue, Key.excludedDirectories) }
	}

	/// Languages nobody wants to be told about a missing server for.
	///
	/// Per language rather than per file or per project: the answer to "no
	/// server for JSON" is the same in every project on the machine, and being
	/// asked again in the next one is the whole complaint.
	public var ignoredLanguageServers: [String] {
		get { defaults.stringArray(forKey: Key.ignoredLanguageServers) ?? [] }
		set { set(Array(Set(newValue)).sorted(), Key.ignoredLanguageServers) }
	}

	/// Stops offering a server for this language, from anywhere.
	public func ignoreLanguageServer(for languageId: String) {
		ignoredLanguageServers = ignoredLanguageServers + [languageId]
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
		NotificationCenter.default.post(name: .abydosSettingsChanged, object: nil)
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
		NotificationCenter.default.post(name: .abydosSettingsChanged, object: nil)
	}
}

public extension Notification.Name {
	static let abydosSettingsChanged = Notification.Name("abydos.settingsChanged")
}
