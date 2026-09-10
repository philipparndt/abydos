import Foundation

/// Whether a terminal palette can be read on the ground it is drawn on.
///
/// A report on 2026-09-09 said the light theme's terminal could not be used:
/// the contrast was too low. Nobody working on the app uses the light theme, so
/// the light half of every palette had shipped unlooked-at — and measured, the
/// default palette had thirteen of its sixteen colours under the floor a body
/// of text needs. This is the measurement, kept in the kit rather than in the
/// test that runs it, so a tool can print it and a scheme file can be judged
/// before it is shipped.
///
/// The formula is WCAG 2's: relative luminance from the sRGB channels, and the
/// ratio `(lighter + 0.05) / (darker + 0.05)`. Its floors are the ones people
/// already know — 4.5:1 for text, 3:1 for what may be large or dim — which is
/// why they are used here rather than a number of this app's own.
public enum SchemeContrast {
	/// Relative luminance of an `0xRRGGBB` colour, 0 for black and 1 for white.
	public static func luminance(_ rgb: UInt32) -> Double {
		func channel(_ shift: UInt32) -> Double {
			let value = Double((rgb >> shift) & 0xFF) / 255
			return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
		}
		return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
	}

	/// The contrast ratio between two colours, 1 for the same colour and 21
	/// for black on white, whichever way round they are given.
	public static func ratio(_ first: UInt32, _ second: UInt32) -> Double {
		let one = luminance(first), other = luminance(second)
		return (max(one, other) + 0.05) / (min(one, other) + 0.05)
	}

	/// The floor an ordinary palette is held to: WCAG's for text.
	public static let ordinary = 4.5

	/// What a colour has to reach against its ground, or nil for one that is
	/// not held to any.
	///
	/// - `black` is exempt: it is the ground's own colour by convention, drawn
	///   as text only by a program that means it to disappear, and on a dark
	///   ground every palette on the machine has it at one-to-one.
	/// - `brightBlack` is the dim one — comments, timestamps, the parts of a
	///   prompt that are not the point — and is held one step down: 3:1, the
	///   floor for text that is meant to recede, under an ordinary palette, and
	///   4.5:1 under one that promises 7:1, since the dim colour of a
	///   high-contrast palette still has to be read.
	/// - The other fourteen carry prompts, listings and diffs, and are held to
	///   what the palette promises — 4.5:1 unless its file says more.
	public static func floor(for colour: SchemeAnsi, promised: Double? = nil) -> Double? {
		let text = promised ?? ordinary
		switch colour {
		case .black: return nil
		case .brightBlack: return text >= 7 ? 4.5 : 3.0
		default: return text
		}
	}

	/// One colour under its floor on one ground.
	public struct Shortfall: Equatable, Sendable, CustomStringConvertible {
		public let scheme: String
		public let isLight: Bool
		/// Whose ground it was measured against: the scheme's own, or — for a
		/// palette that follows the editor — the theme whose editor it followed.
		public let ground: String
		public let colour: SchemeAnsi
		public let value: UInt32
		public let ratio: Double
		public let floor: Double

		public var description: String {
			String(
				format: "%@ %@ %@ on %@ ground: #%06X is %.2f:1, floor %.1f:1",
				scheme, isLight ? "light" : "dark", colour.rawValue, ground, value, ratio, floor
			)
		}
	}

	/// Every colour of a terminal palette that is under its floor, on both of
	/// its grounds.
	///
	/// A palette that states its own ground is measured against that. One that
	/// follows the editor is measured against the editor ground of every theme
	/// it could be following — which is every scheme with an `app` section —
	/// because that is every ground it will actually be drawn on.
	public static func shortfalls(
		in scheme: Scheme,
		editorGrounds: [(theme: String, ground: SchemePair)]
	) -> [Shortfall] {
		guard let terminal = scheme.terminal else { return [] }
		let grounds: [(String, SchemePair)]
		if let own = terminal.background {
			grounds = [(scheme.id, own)]
		} else {
			grounds = editorGrounds
		}
		var found: [Shortfall] = []
		for isLight in [true, false] {
			let named = terminal.named(isLight: isLight)
			for (theme, pair) in grounds {
				let ground = pair.value(isLight: isLight)
				for (colour, value) in zip(SchemeAnsi.allCases, named) {
					guard let floor = floor(for: colour, promised: terminal.floor) else { continue }
					let ratio = ratio(value, ground)
					if ratio < floor {
						found.append(Shortfall(
							scheme: scheme.id, isLight: isLight, ground: theme,
							colour: colour, value: value, ratio: ratio, floor: floor
						))
					}
				}
			}
		}
		return found
	}

	// MARK: - What programs paint

	/// One pair a program paints — a text colour on a background colour, both
	/// from the palette — under its floor.
	public struct PaintedShortfall: Equatable, Sendable, CustomStringConvertible {
		public let scheme: String
		public let isLight: Bool
		public let text: SchemeAnsi
		public let background: SchemeAnsi
		public let ratio: Double
		public let floor: Double

		public var description: String {
			String(
				format: "%@ %@ %@ on %@: %.2f:1, floor %.1f:1",
				scheme, isLight ? "light" : "dark", text.rawValue, background.rawValue, ratio, floor
			)
		}
	}

	/// The floor for dark text on a background a program painted: WCAG's for
	/// text that may be large or is meant to recede, and what a program's own
	/// pairing can reasonably be asked to survive.
	public static let painted = 3.0

	/// The painted pairs a palette is held to: `black` as text on each of the
	/// fourteen colours a program paints as a highlight — the base six and the
	/// bright eight, `brightBlack` excepted — on the dark ground.
	///
	/// **Why these, and not every pair.** Measured over every bundled palette
	/// on 2026-09-10, the pairs a program paints came out in three groups. Dark
	/// text on a painted colour — a selected row, a badge, a status bar —
	/// passes everywhere and is what k9s paints. Light text on one of the base
	/// six fails everywhere, by construction: a palette whose base six can be
	/// read as text on a dark ground has made them light, and white on light
	/// is not a pair any single colour can rescue. And the dim colour on a
	/// coloured background fails everywhere too, at 1.5:1 to 2.9:1, for the
	/// mirror of the same reason. Holding those would fail every palette that
	/// exists and say nothing. `pairTable` prints all of them for reading.
	///
	/// The dark ground only. The light halves of these palettes make their
	/// bright colours dark so they can be read on white, and a program's dark
	/// text on them is a fault of a different shape — see the change's design.
	public static func paintedShortfalls(in scheme: Scheme) -> [PaintedShortfall] {
		guard let terminal = scheme.terminal else { return [] }
		let named = terminal.named(isLight: false)
		let black = named[0]
		var found: [PaintedShortfall] = []
		// Not the dim grey: it is text that recedes, not a colour a program
		// paints a row with, and a palette's black on its own dim grey is a
		// pair nobody chose — the editor palette's sits at 2.99:1.
		for (colour, value) in zip(SchemeAnsi.allCases, named) where colour != .black && colour != .brightBlack {
			let ratio = ratio(black, value)
			if ratio < painted {
				found.append(PaintedShortfall(
					scheme: scheme.id, isLight: false, text: .black, background: colour,
					ratio: ratio, floor: painted
				))
			}
		}
		return found
	}

	public static func paintedShortfalls(in library: SchemeLibrary) -> [PaintedShortfall] {
		library.terminalSchemes.flatMap(paintedShortfalls(in:))
	}

	/// Every colour on every other, for reading rather than for holding.
	public static func pairTable(in scheme: Scheme, isLight: Bool) -> [(text: SchemeAnsi, background: SchemeAnsi, ratio: Double)] {
		guard let terminal = scheme.terminal else { return [] }
		let named = terminal.named(isLight: isLight)
		var table: [(SchemeAnsi, SchemeAnsi, Double)] = []
		for (text, textValue) in zip(SchemeAnsi.allCases, named) {
			for (background, backgroundValue) in zip(SchemeAnsi.allCases, named) where text != background {
				table.append((text, background, ratio(textValue, backgroundValue)))
			}
		}
		return table
	}

	// MARK: - The app half

	/// The ground a text role is drawn on, and whether it is meant to recede.
	///
	/// Three classes. Text — the editor's, the sidebar's, the git colours a file
	/// name is drawn in, the fold placeholder's, and the caret, which is a shape
	/// but a shape nobody can find is a bug — is held to the promised floor. Dim
	/// text — line numbers and ignored files — is held one step down, as bright
	/// black is in the terminal: meant to be read less, not to be unreadable.
	/// Grounds and highlights are not text and return nil; `BundledSchemeTests`
	/// judges those by their own relations.
	public static func ground(for role: SchemeRole) -> (ground: SchemeRole, isDim: Bool)? {
		switch role {
		case .editorText, .caret: return (.editorBackground, false)
		case .gutterText: return (.editorBackground, true)
		case .gutterCurrentLineText: return (.currentLineBackground, true)
		case .sidebarText, .sidebarHeaderText: return (.sidebarBackground, false)
		case .gitAdded, .gitModified, .gitUnversioned, .gitConflict: return (.sidebarBackground, false)
		case .gitIgnored: return (.sidebarBackground, true)
		case .foldPlaceholderText: return (.foldPlaceholderBackground, false)
		default: return nil
		}
	}

	/// Comments and documentation recede on purpose; every other kind is code.
	public static func isDim(_ kind: HighlightKind) -> Bool {
		kind == .comment || kind == .documentation
	}

	/// What a text role or syntax kind has to reach: the promise, or one step
	/// down for what is meant to recede.
	public static func floor(promised: Double?, dim: Bool) -> Double {
		let text = promised ?? ordinary
		return dim ? (text >= 7 ? 4.5 : 3.0) : text
	}

	/// One role or syntax kind under its floor on its ground.
	public struct AppShortfall: Equatable, Sendable, CustomStringConvertible {
		public let scheme: String
		public let isLight: Bool
		/// A role's name, or `syntax.<kind>`.
		public let role: String
		public let ground: String
		public let value: UInt32
		public let ratio: Double
		public let floor: Double

		public var description: String {
			String(
				format: "%@ %@ %@ on %@: #%06X is %.2f:1, floor %.1f:1",
				scheme, isLight ? "light" : "dark", role, ground, value, ratio, floor
			)
		}
	}

	/// Every text role and syntax kind of a theme under its floor, both halves.
	public static func appShortfalls(in scheme: Scheme) -> [AppShortfall] {
		guard let app = scheme.app else { return [] }
		var found: [AppShortfall] = []
		for isLight in [true, false] {
			for role in SchemeRole.allCases {
				guard let (groundRole, dim) = ground(for: role) else { continue }
				let value = app.colour(role, isLight: isLight)
				let ground = app.colour(groundRole, isLight: isLight)
				let floor = floor(promised: app.floor, dim: dim)
				let ratio = ratio(value, ground)
				if ratio < floor {
					found.append(AppShortfall(
						scheme: scheme.id, isLight: isLight, role: role.rawValue, ground: groundRole.rawValue,
						value: value, ratio: ratio, floor: floor
					))
				}
			}
			let editor = app.colour(.editorBackground, isLight: isLight)
			for kind in HighlightKind.allCases {
				let value = app.colour(kind, isLight: isLight)
				let floor = floor(promised: app.floor, dim: isDim(kind))
				let ratio = ratio(value, editor)
				if ratio < floor {
					found.append(AppShortfall(
						scheme: scheme.id, isLight: isLight, role: "syntax." + kind.schemeKey,
						ground: SchemeRole.editorBackground.rawValue, value: value, ratio: ratio, floor: floor
					))
				}
			}
		}
		return found
	}

	/// The app-half shortfalls of every theme in a library.
	public static func appShortfalls(in library: SchemeLibrary) -> [AppShortfall] {
		library.appSchemes.flatMap(appShortfalls(in:))
	}

	/// The shortfalls of every terminal palette in a library, against the
	/// editor grounds of every theme in it.
	public static func shortfalls(in library: SchemeLibrary) -> [Shortfall] {
		let grounds: [(theme: String, ground: SchemePair)] = library.schemes.compactMap { scheme in
			guard let app = scheme.app else { return nil }
			return (scheme.id, SchemePair(
				light: app.colour(.editorBackground, isLight: true),
				dark: app.colour(.editorBackground, isLight: false)
			))
		}
		return library.terminalSchemes.flatMap { shortfalls(in: $0, editorGrounds: grounds) }
	}
}
