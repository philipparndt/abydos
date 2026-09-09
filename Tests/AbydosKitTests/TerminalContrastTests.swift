import Foundation
import Testing
@testable import AbydosKit

private extension Data {
	func replacingFirst(_ old: String, with new: String) -> Data {
		Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: old, with: new).utf8)
	}
}

/// A terminal palette can be read on the ground it is drawn on — in the light
/// theme too, which is the half nobody here looks at.
struct TerminalContrastTests {
	@Test func theRatioIsWCAGsAndDoesNotCareWhichWayRound() {
		#expect(abs(SchemeContrast.ratio(0x000000, 0xFFFFFF) - 21) < 0.001)
		#expect(abs(SchemeContrast.ratio(0xFFFFFF, 0x000000) - 21) < 0.001)
		#expect(SchemeContrast.ratio(0x808080, 0x808080) == 1)
		// A published pair: #767676 on white is the smallest grey that passes
		// 4.5:1, and the number every contrast checker gives for it.
		#expect(abs(SchemeContrast.ratio(0x767676, 0xFFFFFF) - 4.54) < 0.01)
	}

	@Test func blackIsExemptAndTheDimOneIsHeldLower() {
		#expect(SchemeContrast.floor(for: .black) == nil)
		#expect(SchemeContrast.floor(for: .brightBlack) == 3.0)
		#expect(SchemeContrast.floor(for: .red) == 4.5)
		#expect(SchemeContrast.floor(for: .brightWhite) == 4.5)
	}

	/// "High contrast" is a promise in the file, and the test holds the file to
	/// it: 7:1 for the fourteen, and the dim one moves up a step with them.
	@Test func aPaletteThatPromisesMoreIsHeldToIt() throws {
		#expect(SchemeContrast.floor(for: .red, promised: 7) == 7)
		#expect(SchemeContrast.floor(for: .brightBlack, promised: 7) == 4.5)
		#expect(SchemeContrast.floor(for: .black, promised: 7) == nil)

		let scheme = try Scheme.read(
			SchemeFileTests.wholeScheme(id: "loud", app: false, terminal: true, follows: true, floor: 7),
			isPersonal: false, origin: "/tmp/loud.json"
		)
		#expect(scheme.terminal?.floor == 7)
		// #333333 on white is 12.6:1 and passes 7; on a light grey ground of
		// #C0C0C0 it is 6.4:1, which an ordinary palette would pass and this
		// one may not.
		let shortfalls = SchemeContrast.shortfalls(in: scheme, editorGrounds: [
			("paper", SchemePair(light: 0xFFFFFF, dark: 0x000000)),
			("mist", SchemePair(light: 0xC0C0C0, dark: 0x000000)),
		])
		#expect(!shortfalls.isEmpty)
		#expect(shortfalls.allSatisfy { $0.ground == "mist" && $0.floor == 7 })
	}

	@Test func aFloorThatIsNotANumberRefusesTheFile() {
		let data = SchemeFileTests.wholeScheme(app: false, terminal: true, follows: true, floor: nil)
			.replacingFirst("\"follows\": \"editor\"", with: "\"follows\": \"editor\", \"floor\": \"high\"")
		#expect(throws: SchemeProblem.notANumber(key: "terminal.floor", found: "\"high\"")) {
			try Scheme.read(data, isPersonal: false, origin: "/tmp/x.json")
		}
	}

	/// The claim the report made false, measured on every bundled palette on
	/// both grounds. The message is the list: which scheme, which half, which
	/// colour, against whose ground, at what ratio — so a scheme added later
	/// that fails says exactly where.
	@Test func everyBundledPaletteCanBeReadOnBothOfItsGrounds() {
		let library = SchemeLibrary(personal: nil, logsProblems: false)
		#expect(library.terminalSchemes.count >= 5, "the bundled schemes were not found")
		let shortfalls = SchemeContrast.shortfalls(in: library)
		let list = shortfalls.map { "  \($0)" }.joined(separator: "\n")
		#expect(shortfalls.isEmpty, Comment(rawValue: "\(shortfalls.count) colour(s) under the floor:\n\(list)"))
	}

	/// A palette that follows the editor has no ground of its own, so it is
	/// measured against every theme's — and a colour fine on one theme's
	/// ground and not another's is named with the theme.
	@Test func aPaletteThatFollowsTheEditorIsMeasuredOnEveryThemesGround() throws {
		let scheme = try Scheme.read(
			SchemeFileTests.wholeScheme(id: "grey", app: false, terminal: true, follows: true),
			isPersonal: false, origin: "/tmp/grey.json"
		)
		// The ANSI colours in that file are #333333 in the light: readable on
		// a white editor, not on a dark grey one that is nearly the same.
		let shortfalls = SchemeContrast.shortfalls(in: scheme, editorGrounds: [
			("paper", SchemePair(light: 0xFFFFFF, dark: 0x000000)),
			("slate", SchemePair(light: 0x3A3A3A, dark: 0x000000)),
		])
		#expect(shortfalls.allSatisfy { $0.ground == "slate" && $0.isLight })
		#expect(shortfalls.contains { $0.colour == .red && $0.ground == "slate" })
	}
}
