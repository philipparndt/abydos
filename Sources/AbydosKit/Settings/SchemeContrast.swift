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
