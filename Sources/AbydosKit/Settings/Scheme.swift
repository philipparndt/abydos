import Foundation

/// One scheme, read from one JSON file.
///
/// A scheme used to be spread across four places in two Swift files — a case in
/// the family enum, two `Theme` constants, two syntax-colour functions and a
/// terminal palette with two tables of sixteen — so adding one meant editing all
/// of them and remembering which. Here it is a file: two sections, `app` and
/// `terminal`, every colour a light/dark pair, and adding a scheme is adding a
/// file. See `Schemes/README.md` for the format as somebody writing one reads
/// it.
public struct Scheme: Equatable, Sendable {
	/// What the setting stores and what other files refer to. The filename is
	/// not it: a file renamed on disk must not become a different scheme.
	public let id: String
	/// What the settings window shows.
	public let title: String
	/// Where it sits in the list, if it says. Ties, and the files that do not
	/// say, go alphabetically by title after the ones that do.
	public let order: Int?
	/// The prose that used to be the doc comment above the Swift constant, kept
	/// with the colours rather than left behind in a file nobody opens.
	public let about: String
	/// The editor's palette. Absent for a scheme that only dresses the terminal.
	public let app: SchemeApp?
	/// The terminal's. Absent for a scheme that only dresses the editor.
	public let terminal: SchemeTerminal?
	/// Whether it came from somebody's own folder rather than the bundle, which
	/// is what a message about it has to say to be worth reading.
	public let isPersonal: Bool
	/// The file it was read from, for the same reason.
	public let origin: String

	public init(
		id: String,
		title: String,
		order: Int? = nil,
		about: String = "",
		app: SchemeApp? = nil,
		terminal: SchemeTerminal? = nil,
		isPersonal: Bool = false,
		origin: String = ""
	) {
		self.id = id
		self.title = title
		self.order = order
		self.about = about
		self.app = app
		self.terminal = terminal
		self.isPersonal = isPersonal
		self.origin = origin
	}
}

/// A colour, at both lightnesses.
///
/// Both, always: a scheme that only says what it looks like in the dark is a
/// scheme that goes wrong the first morning somebody opens the curtains.
public struct SchemePair: Equatable, Sendable {
	/// 0xRRGGBB.
	public let light: UInt32
	public let dark: UInt32

	public init(light: UInt32, dark: UInt32) {
		self.light = light
		self.dark = dark
	}

	public func value(isLight: Bool) -> UInt32 { isLight ? light : dark }

	/// Halfway between two colours, channel by channel, at each lightness.
	///
	/// What a scheme that leaves one of `SchemeRole.optional` out gets, and the
	/// only derivation in this file. Halfway is bounded by construction — it can
	/// never be louder than the louder of the two it sits between — which is the
	/// property that makes it safe to apply to a scheme nobody has looked at.
	public static func midway(_ first: SchemePair, _ second: SchemePair) -> SchemePair {
		func blend(_ first: UInt32, _ second: UInt32) -> UInt32 {
			var made: UInt32 = 0
			for shift: UInt32 in [16, 8, 0] {
				let left = (first >> shift) & 0xFF
				let right = (second >> shift) & 0xFF
				made |= ((left + right) / 2) << shift
			}
			return made
		}
		return SchemePair(
			light: blend(first.light, second.light),
			dark: blend(first.dark, second.dark)
		)
	}
}

/// The roles the app's chrome is painted in.
public enum SchemeRole: String, CaseIterable, Sendable {
	case windowBackground, sidebarBackground, editorBackground, toolbarBackground, separator
	case sidebarText, sidebarHeaderText, selectionActive, selectionInactive, excludedDirectoryTint
	case gitAdded, gitModified, gitUnversioned, gitIgnored, gitConflict
	case editorText, gutterText, gutterCurrentLineText, currentLineBackground, caret
	case selectionBackground, selectionBackgroundInactive
	case searchMatchBackground, searchMatchCurrentBackground
	case selectionOccurrenceBackground
	case foldPlaceholderBackground, foldPlaceholderText, indentGuide

	/// The roles a file may leave out, and the reason there are any.
	///
	/// Every other colour missing refuses the file, which is the rule this
	/// module argues for at `Scheme.read`. These arrived after schemes were
	/// already files somebody keeps in a dotfiles repository, and requiring one
	/// would refuse every one of them for having been written before it existed.
	/// So they are optional, each with a stated derivation — see
	/// `Scheme.readApp` — rather than a silent default: what you get is written
	/// down, and it is bounded, because `SchemePair.midway` can never be louder
	/// than the louder of the two colours it sits between.
	///
	/// **A set rather than one role, because a second one arrived.** It was a
	/// single `SchemeRole` while `selectionBackgroundInactive` was the only
	/// late-comer, and 0536 needed two more the same day it needed the first
	/// derivation reused. A rule with one member spelt as a special case is a
	/// rule that has to be rewritten the moment there are two.
	public static let optional: Set<SchemeRole> = [
		.selectionBackgroundInactive,
		.searchMatchBackground,
		.searchMatchCurrentBackground,
		.selectionOccurrenceBackground,
	]
}

/// ANSI 0–15, named. Named rather than a list of sixteen so a file missing one
/// can be told which one.
public enum SchemeAnsi: String, CaseIterable, Sendable {
	case black, red, green, yellow, blue, magenta, cyan, white
	case brightBlack, brightRed, brightGreen, brightYellow
	case brightBlue, brightMagenta, brightCyan, brightWhite
}

/// The editor half of a scheme.
public struct SchemeApp: Equatable, Sendable {
	/// What the setting holds for this scheme at each lightness.
	///
	/// Derived from the id — `nord`, `nord-light`, `nord-system` — unless the
	/// file says otherwise, which is only there for the palette this app shipped
	/// before it had more than one and whose stored values are plain `dark`,
	/// `light` and `system`.
	public struct Stored: Equatable, Sendable {
		public let dark: String
		public let light: String
		public let system: String

		public init(dark: String, light: String, system: String) {
			self.dark = dark
			self.light = light
			self.system = system
		}

		public init(id: String) {
			self.init(dark: id, light: "\(id)-light", system: "\(id)-system")
		}

		public func name(for mode: Appearance.Mode) -> String {
			switch mode {
			case .dark:   return dark
			case .light:  return light
			case .system: return system
			}
		}
	}

	public let stored: Stored
	private let roles: [SchemeRole: SchemePair]
	private let syntax: [HighlightKind: SchemePair]

	public init(stored: Stored, roles: [SchemeRole: SchemePair], syntax: [HighlightKind: SchemePair]) {
		self.stored = stored
		self.roles = roles
		self.syntax = syntax
	}

	/// Every role is present: a file missing one is refused rather than loaded,
	/// so the fallback below can only be reached by a bug in this file — and
	/// magenta is what a bug should look like.
	public func colour(_ role: SchemeRole, isLight: Bool) -> UInt32 {
		roles[role]?.value(isLight: isLight) ?? 0xFF00FF
	}

	public func colour(_ kind: HighlightKind, isLight: Bool) -> UInt32 {
		syntax[kind]?.value(isLight: isLight) ?? 0xFF00FF
	}
}

/// The terminal half of a scheme.
public struct SchemeTerminal: Equatable, Sendable {
	/// The ground, the text and the cursor — or nothing at all, when the section
	/// says `"follows": "editor"` and takes those three from the theme in force.
	public let background: SchemePair?
	public let foreground: SchemePair?
	public let cursor: SchemePair?
	private let ansi: [SchemeAnsi: SchemePair]

	public var followsEditor: Bool { background == nil }

	public init(
		background: SchemePair?,
		foreground: SchemePair?,
		cursor: SchemePair?,
		ansi: [SchemeAnsi: SchemePair]
	) {
		self.background = background
		self.foreground = foreground
		self.cursor = cursor
		self.ansi = ansi
	}

	/// ANSI 0–15 in order.
	public func named(isLight: Bool) -> [UInt32] {
		SchemeAnsi.allCases.map { ansi[$0]?.value(isLight: isLight) ?? 0xFF00FF }
	}
}

/// Why a file was refused.
///
/// Every case names the key it is about, because "this scheme is broken" sends
/// somebody reading four hundred colours and "app.syntax.keyword is missing"
/// sends them to a line.
public enum SchemeProblem: Error, Equatable, Sendable {
	case unreadable(String)
	case notAnObject
	case missing(String)
	case notAColour(key: String, found: String)
	case notAnObjectAt(String)
	case emptyScheme
	case unknownFollows(String)

	public var reason: String {
		switch self {
		case let .unreadable(detail):
			return "it is not JSON (\(detail))"
		case .notAnObject:
			return "the top level is not an object"
		case let .missing(key):
			return "\(key) is missing"
		case let .notAColour(key, found):
			return "\(key) is \(found) rather than a light/dark pair of #RRGGBB colours"
		case let .notAnObjectAt(key):
			return "\(key) is not an object"
		case .emptyScheme:
			return "it has neither an app nor a terminal section, so it is not a scheme"
		case let .unknownFollows(value):
			return "terminal.follows says \"\(value)\", and the only thing it can follow is \"editor\""
		}
	}
}

public extension Scheme {
	/// Reads one file.
	///
	/// A colour that is missing refuses the whole file rather than being filled
	/// in from somewhere. That was the open question and this is the answer: a
	/// theme applied nine-tenths of the way is diagnosed by staring at a window
	/// and wondering, where a file that is refused says which key, in which
	/// file, on the first line of a log. Inheriting a default silently makes a
	/// forgotten key and an unread file look exactly the same.
	///
	/// A few roles are exempt, and only because they were added after schemes
	/// became files people keep: `SchemeRole.optional`, which has the argument.
	static func read(_ data: Data, isPersonal: Bool, origin: String) throws -> Scheme {
		let parsed: Any
		do {
			parsed = try JSONSerialization.jsonObject(with: data)
		} catch {
			throw SchemeProblem.unreadable(error.localizedDescription)
		}
		guard let document = parsed as? [String: Any] else { throw SchemeProblem.notAnObject }

		guard let id = document["id"] as? String, !id.isEmpty else {
			throw SchemeProblem.missing("id")
		}
		let title = document["title"] as? String ?? id

		var app: SchemeApp?
		if let section = document["app"] {
			guard let section = section as? [String: Any] else { throw SchemeProblem.notAnObjectAt("app") }
			app = try readApp(section, id: id, stored: document["stored"])
		}

		var terminal: SchemeTerminal?
		if let section = document["terminal"] {
			guard let section = section as? [String: Any] else {
				throw SchemeProblem.notAnObjectAt("terminal")
			}
			terminal = try readTerminal(section)
		}

		guard app != nil || terminal != nil else { throw SchemeProblem.emptyScheme }

		return Scheme(
			id: id,
			title: title,
			order: document["order"] as? Int,
			about: document["about"] as? String ?? "",
			app: app,
			terminal: terminal,
			isPersonal: isPersonal,
			origin: origin
		)
	}

	private static func readApp(_ section: [String: Any], id: String, stored: Any?) throws -> SchemeApp {
		var roles: [SchemeRole: SchemePair] = [:]
		for role in SchemeRole.allCases where !SchemeRole.optional.contains(role) {
			roles[role] = try pair(section[role.rawValue], at: "app.\(role.rawValue)")
		}

		// The roles that may be left out — see `SchemeRole.optional`. Stated, one
		// is read like any other and a broken value is still refused; absent, it
		// is derived from roles that are required and so are already in hand.
		// `read` takes each in the order its derivation needs, since the quiet
		// match colour is derived from the loud one.
		func read(_ role: SchemeRole, orDeriveFrom derive: () -> SchemePair?) throws {
			if let stated = section[role.rawValue] {
				roles[role] = try pair(stated, at: "app.\(role.rawValue)")
			} else {
				roles[role] = derive()
			}
		}

		// Halfway between the gray a tree row goes when the keyboard is elsewhere
		// and the colour selected code is drawn in when it is not.
		try read(.selectionBackgroundInactive) {
			guard let band = roles[.selectionInactive], let strong = roles[.selectionBackground] else { return nil }
			return .midway(band, strong)
		}
		// Halfway between the selection and the caret: the caret is the one
		// colour a scheme guarantees can be seen against its own editor at a
		// glance, which is exactly what the current match has to be.
		try read(.searchMatchCurrentBackground) {
			guard let strong = roles[.selectionBackground], let caret = roles[.caret] else { return nil }
			return .midway(strong, caret)
		}
		// And the other matches halfway again, back towards the selection — so a
		// derived scheme cannot end up with the matches somebody is not looking
		// at louder than the one they are.
		try read(.searchMatchBackground) {
			guard let strong = roles[.selectionBackground],
			      let current = roles[.searchMatchCurrentBackground] else { return nil }
			return .midway(strong, current)
		}
		// And the places the selected text also appears: most of the way back to
		// the ground from the selection, which is what those places *are* — the
		// ones that would look selected if you selected them, said quietly.
		//
		// **Nearer the ground than the selection, and that is the whole of it.**
		// These first sat four fifths of the way *to* the selection, chosen to
		// stay under the find band — the wrong separation, since find's matches
		// win while find is showing and the two never share a page. What they do
		// share a page with is the selection, and at 1.04 to 1.13 against it they
		// were reported as looking exactly like one.
		try read(.selectionOccurrenceBackground) {
			guard let ground = roles[.editorBackground],
			      let selection = roles[.selectionBackground] else { return nil }
			return .midway(ground, selection)
		}

		guard let syntaxSection = section["syntax"] else { throw SchemeProblem.missing("app.syntax") }
		guard let syntaxSection = syntaxSection as? [String: Any] else {
			throw SchemeProblem.notAnObjectAt("app.syntax")
		}
		var syntax: [HighlightKind: SchemePair] = [:]
		for kind in HighlightKind.allCases {
			syntax[kind] = try pair(syntaxSection[kind.schemeKey], at: "app.syntax.\(kind.schemeKey)")
		}

		var names = SchemeApp.Stored(id: id)
		if let stored {
			guard let stored = stored as? [String: Any] else { throw SchemeProblem.notAnObjectAt("stored") }
			names = SchemeApp.Stored(
				dark: stored["dark"] as? String ?? names.dark,
				light: stored["light"] as? String ?? names.light,
				system: stored["system"] as? String ?? names.system
			)
		}
		return SchemeApp(stored: names, roles: roles, syntax: syntax)
	}

	private static func readTerminal(_ section: [String: Any]) throws -> SchemeTerminal {
		var background: SchemePair?
		var foreground: SchemePair?
		var cursor: SchemePair?
		if let follows = section["follows"] {
			guard let follows = follows as? String, follows == "editor" else {
				throw SchemeProblem.unknownFollows(String(describing: follows))
			}
		} else {
			background = try pair(section["background"], at: "terminal.background")
			foreground = try pair(section["foreground"], at: "terminal.foreground")
			cursor = try pair(section["cursor"], at: "terminal.cursor")
		}

		guard let table = section["ansi"] else { throw SchemeProblem.missing("terminal.ansi") }
		guard let table = table as? [String: Any] else { throw SchemeProblem.notAnObjectAt("terminal.ansi") }
		var ansi: [SchemeAnsi: SchemePair] = [:]
		for colour in SchemeAnsi.allCases {
			ansi[colour] = try pair(table[colour.rawValue], at: "terminal.ansi.\(colour.rawValue)")
		}
		return SchemeTerminal(background: background, foreground: foreground, cursor: cursor, ansi: ansi)
	}

	/// `{ "light": "#RRGGBB", "dark": "#RRGGBB" }`, and nothing else.
	private static func pair(_ value: Any?, at key: String) throws -> SchemePair {
		guard let value else { throw SchemeProblem.missing(key) }
		guard let object = value as? [String: Any] else {
			throw SchemeProblem.notAColour(key: key, found: describe(value))
		}
		guard let light = object["light"] else { throw SchemeProblem.missing("\(key).light") }
		guard let dark = object["dark"] else { throw SchemeProblem.missing("\(key).dark") }
		return SchemePair(
			light: try colour(light, at: "\(key).light"),
			dark: try colour(dark, at: "\(key).dark")
		)
	}

	private static func colour(_ value: Any, at key: String) throws -> UInt32 {
		guard let text = value as? String, text.hasPrefix("#"), text.count == 7,
		      let parsed = UInt32(text.dropFirst(), radix: 16)
		else { throw SchemeProblem.notAColour(key: key, found: describe(value)) }
		return parsed
	}

	private static func describe(_ value: Any) -> String {
		if let text = value as? String { return "\"\(text)\"" }
		if value is [Any] { return "a list" }
		if value is [String: Any] { return "an object" }
		return String(describing: value)
	}
}
