import Foundation

/// Every scheme the app can offer: the ones it ships and the ones somebody
/// keeps.
///
/// Both from the start, rather than the bundle now and a folder later. A scheme
/// is a file, and the whole point of it being a file is that dropping one in a
/// directory is enough — no build, no fork, no waiting for a palette to be
/// accepted upstream because somebody likes green.
///
/// Nothing here can stop the app starting. A file that will not parse is
/// reported and skipped; a directory that is not there is not an error, it is
/// the ordinary case; and if the whole shipped set went missing there is still
/// a grey scheme below to draw a window with while somebody reads the log.
public final class SchemeLibrary {
	public static let shared = SchemeLibrary()

	/// Where the shipped ones are: a resource of this module, so they travel
	/// into `.app` bundles with the grammar queries.
	public static var bundledDirectory: URL? {
		Bundle.module.url(forResource: "Schemes", withExtension: nil)
	}

	/// Where somebody's own go: `~/.config/abydos/schemes`.
	///
	/// A path already in a dotfiles repository rather than one inside a bundle
	/// an upgrade replaces — the app is allowed to overwrite what it shipped,
	/// and never what somebody wrote.
	public static var personalDirectory: URL { UserConfiguration.folder("schemes") }

	private let bundled: URL?
	private let personal: URL?
	private let logsProblems: Bool

	public private(set) var schemes: [Scheme] = []

	/// What was wrong with the files that were refused, in the order they were
	/// read. Also written to `~/Library/Logs/Abydos/schemes.log`, since the one
	/// place a wrong colour is not visible is the screen it did not paint.
	public private(set) var problems: [String] = []

	public init(
		bundled: URL? = SchemeLibrary.bundledDirectory,
		personal: URL? = SchemeLibrary.personalDirectory,
		logsProblems: Bool = true
	) {
		self.bundled = bundled
		self.personal = personal
		self.logsProblems = logsProblems
		reload()
	}

	/// Reads both directories again.
	///
	/// Cheap — a handful of small files — so it is done at startup and whenever
	/// the settings window is opened, which is the moment somebody who has just
	/// dropped a file in goes looking for it. Not watched: a scheme is not
	/// edited often enough to be worth a file watcher running all day.
	public func reload() {
		var found: [String: Scheme] = [:]
		var reported: [String] = []

		func read(_ directory: URL?, isPersonal: Bool) {
			guard let directory else { return }
			for file in Self.schemeFiles(in: directory) {
				do {
					let data = try Data(contentsOf: file)
					var scheme = try Scheme.read(data, isPersonal: isPersonal, origin: file.path)
					if let existing = found[scheme.id] {
						// A personal file with a bundled name replaces it: that
						// is the only way to adjust one, and the alternative —
						// refusing it, or listing two schemes with one name —
						// is worse than the rule being stated.
						reported.append("\(file.path): replaces the \(existing.isPersonal ? "" : "bundled ")scheme \"\(scheme.id)\"")
						if scheme.order == nil {
							scheme = Scheme(
								id: scheme.id, title: scheme.title, order: existing.order,
								about: scheme.about, app: scheme.app, terminal: scheme.terminal,
								isPersonal: scheme.isPersonal, origin: scheme.origin
							)
						}
					}
					found[scheme.id] = scheme
				} catch let problem as SchemeProblem {
					reported.append("\(file.path): \(problem.reason) — the file is ignored")
				} catch {
					reported.append("\(file.path): \(error.localizedDescription) — the file is ignored")
				}
			}
		}

		read(bundled, isPersonal: false)
		read(personal, isPersonal: true)

		schemes = found.values.sorted(by: Self.inListOrder)
		if schemes.isEmpty {
			reported.append("no schemes could be read at all — falling back to the built-in grey")
			schemes = [.fallback]
		}
		problems = reported
		if logsProblems {
			for line in reported { DiagnosticLog.write(line, to: "schemes") }
		}
	}

	/// The `.json` files in a directory, in a settled order so two machines
	/// list the same schemes the same way.
	static func schemeFiles(in directory: URL) -> [URL] {
		let contents = (try? FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: nil
		)) ?? []
		return contents.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
	}

	/// Stated order first, then alphabetically — so a personal scheme that says
	/// nothing lands at the end of the list rather than in the middle of the
	/// shipped ones.
	private static func inListOrder(_ first: Scheme, _ second: Scheme) -> Bool {
		let left = first.order ?? Int.max
		let right = second.order ?? Int.max
		if left != right { return left < right }
		return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
	}

	// MARK: - Asking for one

	public func scheme(id: String) -> Scheme? { schemes.first { $0.id == id } }

	/// The ones that dress the editor, which is what the theme list offers.
	public var appSchemes: [Scheme] { schemes.filter { $0.app != nil } }

	/// The ones that dress the terminal — the same set plus the one that only
	/// dresses the terminal, by following the editor.
	public var terminalSchemes: [Scheme] { schemes.filter { $0.terminal != nil } }

	public func appScheme(id: String) -> Scheme? { appSchemes.first { $0.id == id } }

	/// What an unrecognised stored value, or a missing file, means.
	public var defaultAppScheme: Scheme {
		appScheme(id: Appearance.defaultFamily) ?? appSchemes.first ?? .fallback
	}

	public var defaultTerminalScheme: Scheme {
		terminalSchemes.first { $0.id == Appearance.defaultFamily }
			?? terminalSchemes.first ?? .fallback
	}
}

public extension Scheme {
	/// Enough of a scheme to draw a window with when there are none.
	///
	/// Deliberately nobody's taste: grey on grey, so it is recognisable as "the
	/// schemes did not load" rather than mistaken for a palette somebody chose.
	/// It exists so that a broken install is a plain window and a line in a log
	/// instead of an app that will not start.
	static let fallback: Scheme = {
		func grey(_ light: UInt32, _ dark: UInt32) -> SchemePair { SchemePair(light: light, dark: dark) }
		var roles: [SchemeRole: SchemePair] = [:]
		for role in SchemeRole.allCases {
			switch role {
			case .windowBackground, .sidebarBackground, .editorBackground, .toolbarBackground,
			     .currentLineBackground, .foldPlaceholderBackground:
				roles[role] = grey(0xF2F2F2, 0x1E1E1E)
			case .separator, .indentGuide, .selectionInactive, .excludedDirectoryTint:
				roles[role] = grey(0xD8D8D8, 0x3A3A3A)
			case .selectionActive, .selectionBackground:
				roles[role] = grey(0xC8C8C8, 0x4A4A4A)
			default:
				roles[role] = grey(0x202020, 0xD0D0D0)
			}
		}
		var syntax: [HighlightKind: SchemePair] = [:]
		for kind in HighlightKind.allCases { syntax[kind] = grey(0x202020, 0xD0D0D0) }
		var ansi: [SchemeAnsi: SchemePair] = [:]
		for colour in SchemeAnsi.allCases { ansi[colour] = grey(0x404040, 0xC0C0C0) }

		return Scheme(
			id: Appearance.defaultFamily,
			title: "Fallback",
			order: 0,
			about: "What is left when no scheme file could be read.",
			app: SchemeApp(stored: SchemeApp.Stored(dark: "dark", light: "light", system: "system"),
			               roles: roles, syntax: syntax),
			terminal: SchemeTerminal(background: grey(0xFFFFFF, 0x151515),
			                         foreground: grey(0x202020, 0xD0D0D0),
			                         cursor: grey(0x202020, 0xD0D0D0),
			                         ansi: ansi),
			origin: "built in"
		)
	}()
}
