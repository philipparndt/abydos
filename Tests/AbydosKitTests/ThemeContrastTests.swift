import Foundation
import Testing
@testable import AbydosKit

/// A theme's text can be read on the ground it is drawn on — the app half of
/// the claim `TerminalContrastTests` makes for the terminal.
struct ThemeContrastTests {
	@Test func textRolesHaveGroundsAndHighlightsDoNot() {
		#expect(SchemeContrast.ground(for: .editorText)?.ground == .editorBackground)
		#expect(SchemeContrast.ground(for: .gutterText)?.isDim == true)
		#expect(SchemeContrast.ground(for: .gitIgnored)?.isDim == true)
		#expect(SchemeContrast.ground(for: .gitAdded)?.isDim == false)
		#expect(SchemeContrast.ground(for: .selectionBackground) == nil)
		#expect(SchemeContrast.ground(for: .indentGuide) == nil)
	}

	/// Comments recede on purpose; code does not.
	@Test func commentsAreDimAndKeywordsAreNot() {
		#expect(SchemeContrast.isDim(.comment))
		#expect(SchemeContrast.isDim(.documentation))
		#expect(!SchemeContrast.isDim(.keyword))
		#expect(SchemeContrast.floor(promised: nil, dim: true) == 3.0)
		#expect(SchemeContrast.floor(promised: 7, dim: true) == 4.5)
		#expect(SchemeContrast.floor(promised: 7, dim: false) == 7)
	}

	/// The claim, over every shipped theme, both halves, at the floor each
	/// file promises. The message is the list.
	@Test func everyBundledThemeCanBeReadOnItsOwnGrounds() {
		let library = SchemeLibrary(personal: nil, logsProblems: false)
		#expect(library.appSchemes.count >= 5, "the bundled themes were not found")
		let shortfalls = SchemeContrast.appShortfalls(in: library)
		let list = shortfalls.map { "  \($0)" }.joined(separator: "\n")
		#expect(shortfalls.isEmpty, Comment(rawValue: "\(shortfalls.count) under the floor:\n\(list)"))
	}

	@Test func theAAAThemePromisesSevenInBothHalves() {
		let library = SchemeLibrary(personal: nil, logsProblems: false)
		let aaa = library.scheme(id: "wcag-level-aaa")
		#expect(aaa?.app?.floor == 7)
		#expect(aaa?.terminal?.floor == 7)
	}

	@Test func anAppFloorThatIsNotANumberRefusesTheFile() {
		let data = SchemeFileTests.wholeScheme(app: true, terminal: false)
		let broken = Data(
			String(decoding: data, as: UTF8.self)
				.replacingOccurrences(of: "\t\"app\": {", with: "\t\"app\": {\n\t\t\"floor\": \"loud\",")
				.utf8
		)
		#expect(throws: SchemeProblem.notANumber(key: "app.floor", found: "\"loud\"")) {
			try Scheme.read(broken, isPersonal: false, origin: "/tmp/x.json")
		}
	}
}
