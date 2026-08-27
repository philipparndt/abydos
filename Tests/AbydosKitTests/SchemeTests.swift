import Foundation
import Testing
@testable import AbydosKit

/// A scheme is a file: two sections, every colour a light/dark pair.
struct SchemeFileTests {
	/// A whole one, written the way a scheme file is written.
	static func wholeScheme(
		id: String = "nord",
		title: String = "Nord",
		order: Int? = 7,
		app: Bool = true,
		terminal: Bool = true,
		follows: Bool = false,
		stored: String? = nil,
		omitting: String? = nil
	) -> Data {
		func pair(_ light: String, _ dark: String) -> String {
			"{ \"light\": \"\(light)\", \"dark\": \"\(dark)\" }"
		}
		func section(_ keys: [String], _ light: String, _ dark: String) -> String {
			keys.filter { $0 != omitting }
				.map { "\t\t\"\($0)\": \(pair(light, dark))" }
				.joined(separator: ",\n")
		}

		var parts: [String] = ["\t\"id\": \"\(id)\"", "\t\"title\": \"\(title)\""]
		if let order { parts.append("\t\"order\": \(order)") }
		if let stored { parts.append("\t\"stored\": \(stored)") }
		if app {
			let roles = section(SchemeRole.allCases.map(\.rawValue), "#111111", "#EEEEEE")
			let syntax = section(HighlightKind.allCases.map(\.schemeKey), "#222222", "#DDDDDD")
			parts.append("\t\"app\": {\n\(roles),\n\t\t\"syntax\": {\n\(syntax)\n\t\t}\n\t}")
		}
		if terminal {
			let ansi = section(SchemeAnsi.allCases.map(\.rawValue), "#333333", "#CCCCCC")
			let chrome = follows
				? "\t\t\"follows\": \"editor\""
				: section(["background", "foreground", "cursor"], "#444444", "#BBBBBB")
			parts.append("\t\"terminal\": {\n\(chrome),\n\t\t\"ansi\": {\n\(ansi)\n\t\t}\n\t}")
		}
		return Data("{\n\(parts.joined(separator: ",\n"))\n}\n".utf8)
	}

	private func read(_ data: Data, origin: String = "/tmp/nord.json") throws -> Scheme {
		try Scheme.read(data, isPersonal: false, origin: origin)
	}

	@Test func readsAWholeScheme() throws {
		let scheme = try read(Self.wholeScheme())
		#expect(scheme.id == "nord")
		#expect(scheme.title == "Nord")
		#expect(scheme.order == 7)
		#expect(scheme.app?.colour(.editorBackground, isLight: false) == 0xEEEEEE)
		#expect(scheme.app?.colour(.editorBackground, isLight: true) == 0x111111)
		#expect(scheme.app?.colour(.keyword, isLight: false) == 0xDDDDDD)
		#expect(scheme.terminal?.background?.dark == 0xBBBBBB)
		#expect(scheme.terminal?.named(isLight: true) == Array(repeating: 0x333333, count: 16))
	}

	/// The names the setting holds, which are the id unless the file says
	/// otherwise — and the only file that says otherwise is the palette this app
	/// had before it had two.
	@Test func namesItsStoredValuesAfterItself() throws {
		let scheme = try read(Self.wholeScheme())
		#expect(scheme.app?.stored.dark == "nord")
		#expect(scheme.app?.stored.light == "nord-light")
		#expect(scheme.app?.stored.system == "nord-system")

		let legacy = try read(Self.wholeScheme(
			stored: "{ \"dark\": \"dark\", \"light\": \"light\", \"system\": \"system\" }"
		))
		#expect(legacy.app?.stored.name(for: .dark) == "dark")
		#expect(legacy.app?.stored.name(for: .system) == "system")
	}

	/// The answer to the question this was written for: a missing colour refuses
	/// the file and says which key, because a theme applied nine-tenths of the
	/// way is diagnosed by staring at a window and wondering.
	@Test func refusesAFileMissingAColour() {
		#expect(throws: SchemeProblem.missing("app.syntax.keyword")) {
			try read(Self.wholeScheme(omitting: "keyword"))
		}
		#expect(throws: SchemeProblem.missing("app.caret")) {
			try read(Self.wholeScheme(omitting: "caret"))
		}
		#expect(throws: SchemeProblem.missing("terminal.ansi.brightCyan")) {
			try read(Self.wholeScheme(omitting: "brightCyan"))
		}
		#expect(throws: SchemeProblem.missing("terminal.cursor")) {
			try read(Self.wholeScheme(omitting: "cursor"))
		}
	}

	/// The exceptions, and the whole of their argument: a scheme written before
	/// these roles existed still loads, and gets colours that are visible without
	/// being louder than the thing they sit under.
	@Test func derivesTheRolesAFileMayLeaveOut() throws {
		let stated = try read(Self.wholeScheme())
		#expect(stated.app?.colour(.selectionBackgroundInactive, isLight: false) == 0xEEEEEE)

		// The generated file gives every role the same pair, so a derivation has
		// to be looked at on values that differ.
		let older = Data("""
		{
		  "id": "older", "title": "Older",
		  "app": {
		    "selectionInactive": { "light": "#E9E0CF", "dark": "#2A2018" },
		    "selectionBackground": { "light": "#F6E3BC", "dark": "#4A2C0E" }
		  }
		}
		""".utf8)
		// Not a whole file, so it is refused — but on the *first* missing role,
		// which proves this one is not among them.
		#expect(throws: SchemeProblem.missing("app.windowBackground")) { try read(older) }

		let whole = try read(Self.wholeScheme(omitting: "selectionBackgroundInactive"))
		let app = try #require(whole.app)
		#expect(app.colour(.selectionBackgroundInactive, isLight: false) == 0xEEEEEE)
		#expect(app.colour(.selectionBackgroundInactive, isLight: true) == 0x111111)

		// And the derivation itself, on two colours that are not the same.
		let midway = SchemePair.midway(
			SchemePair(light: 0xE9E0CF, dark: 0x2A2018),
			SchemePair(light: 0xF6E3BC, dark: 0x4A2C0E)
		)
		#expect(midway.dark == 0x3A2613)
		#expect(midway.light == 0xEFE1C5)
	}

	/// The find highlights, which are derived from the selection and the caret —
	/// the caret being the one colour a scheme guarantees can be seen against its
	/// own editor, which is what the current match has to be.
	///
	/// The other matches are derived halfway back towards the selection, so a
	/// scheme nobody has looked at cannot end up with the matches somebody is
	/// *not* reading louder than the one they are. That inversion is 0536, and it
	/// is not something a derivation should be able to reintroduce.
	@Test func derivesTheFindHighlightsFromTheSelectionAndTheCaret() throws {
		let stated = try read(Self.wholeScheme())
		#expect(stated.app?.colour(.searchMatchCurrentBackground, isLight: false) == 0xEEEEEE)

		let file = Data("""
		{
		  "id": "older", "title": "Older",
		  "app": {
		    "windowBackground": { "light": "#FFFFFF", "dark": "#151210" },
		    "selectionBackground": { "light": "#F6E3BC", "dark": "#4A2C0E" },
		    "caret": { "light": "#B07407", "dark": "#F7B44E" }
		  }
		}
		""".utf8)
		// Not a whole file, so it is refused — but never for one of these.
		#expect(throws: SchemeProblem.missing("app.sidebarBackground")) { try read(file) }

		let whole = try read(Self.wholeScheme(
			omitting: "searchMatchCurrentBackground"
		))
		#expect(whole.app?.colour(.searchMatchCurrentBackground, isLight: false) == 0xEEEEEE)

		// The two derivations, on values that are not all the same colour.
		let selection = SchemePair(light: 0xF6E3BC, dark: 0x4A2C0E)
		let caret = SchemePair(light: 0xB07407, dark: 0xF7B44E)
		let current = SchemePair.midway(selection, caret)
		let others = SchemePair.midway(selection, current)
		#expect(current.dark == 0xA0702E)
		#expect(others.dark == 0x754E1E)
	}

	/// Half a pair is as bad as none: a scheme that only says what it looks like
	/// in the dark goes wrong the first morning somebody opens the curtains.
	@Test func refusesHalfAColour() {
		let half = Data("""
		{ "id": "half", "terminal": { "background": { "dark": "#101010" } } }
		""".utf8)
		#expect(throws: SchemeProblem.missing("terminal.background.light")) { try read(half) }
	}

	@Test func refusesSomethingThatIsNotAColour() {
		let wrong = Data("""
		{ "id": "wrong", "terminal": { "background": { "light": "red", "dark": "#101010" } } }
		""".utf8)
		#expect(throws: SchemeProblem.notAColour(key: "terminal.background.light", found: "\"red\"")) {
			try read(wrong)
		}
	}

	@Test func refusesAFileThatIsNotJSON() {
		#expect(throws: SchemeProblem.self) { try read(Data("{ not json at all".utf8)) }
	}

	@Test func refusesAFileWithNoIdentifier() {
		#expect(throws: SchemeProblem.missing("id")) {
			try read(Data("{ \"title\": \"Nameless\" }".utf8))
		}
	}

	/// Neither section is a scheme, not an empty one.
	@Test func refusesAFileWithNeitherSection() {
		#expect(throws: SchemeProblem.emptyScheme) {
			try read(Data("{ \"id\": \"nothing\", \"title\": \"Nothing\" }".utf8))
		}
	}

	/// A terminal palette may say it follows the editor instead of stating a
	/// ground, text and cursor of its own — which is what "Editor colours" is.
	@Test func letsATerminalFollowTheEditor() throws {
		let scheme = try read(Self.wholeScheme(app: false, follows: true))
		#expect(scheme.app == nil)
		#expect(scheme.terminal?.followsEditor == true)
		#expect(scheme.terminal?.background == nil)
		// The sixteen are still its own: ANSI has to mean what ANSI means.
		#expect(scheme.terminal?.named(isLight: false) == Array(repeating: 0xCCCCCC, count: 16))
	}

	@Test func refusesFollowingSomethingElse() {
		let odd = Data("""
		{ "id": "odd", "terminal": { "follows": "the system", "ansi": {} } }
		""".utf8)
		#expect(throws: SchemeProblem.unknownFollows("the system")) { try read(odd) }
	}
}

/// Both directories, from the start: what ships, and what somebody keeps.
struct SchemeLibraryTests {
	private func directory() throws -> URL {
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("abydos-schemes-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}

	private func write(_ data: Data, named name: String, into directory: URL) throws {
		try data.write(to: directory.appendingPathComponent(name))
	}

	private func library(bundled: URL?, personal: URL?) -> SchemeLibrary {
		SchemeLibrary(bundled: bundled, personal: personal, logsProblems: false)
	}

	@Test func readsBothDirectories() throws {
		let bundled = try directory(), personal = try directory()
		try write(SchemeFileTests.wholeScheme(id: "blue", title: "Blue", order: 1), named: "blue.json", into: bundled)
		try write(SchemeFileTests.wholeScheme(id: "nord", title: "Nord", order: 5), named: "nord.json", into: personal)

		let schemes = library(bundled: bundled, personal: personal).schemes
		#expect(schemes.map(\.id) == ["blue", "nord"])
		#expect(schemes.first(where: { $0.id == "nord" })?.isPersonal == true)
		#expect(schemes.first(where: { $0.id == "blue" })?.isPersonal == false)
	}

	/// A personal file with a bundled name replaces it. That is the only way to
	/// adjust a shipped scheme, and the alternatives — refusing it, or listing
	/// two schemes with one name — are worse than the rule being stated.
	@Test func aPersonalSchemeOfTheSameNameWins() throws {
		let bundled = try directory(), personal = try directory()
		try write(SchemeFileTests.wholeScheme(id: "abydos", title: "Abydos", order: 1),
		          named: "abydos.json", into: bundled)
		try write(SchemeFileTests.wholeScheme(id: "abydos", title: "Abydos, mine", order: nil),
		          named: "abydos.json", into: personal)

		let store = library(bundled: bundled, personal: personal)
		#expect(store.schemes.count == 1)
		#expect(store.scheme(id: "abydos")?.title == "Abydos, mine")
		#expect(store.scheme(id: "abydos")?.isPersonal == true)
		// And keeps the place in the list the bundled one had, rather than
		// jumping to the end because it did not think to say where it goes.
		#expect(store.scheme(id: "abydos")?.order == 1)
		#expect(store.problems.count == 1)
		#expect(store.problems[0].contains("replaces the bundled scheme \"abydos\""))
	}

	/// A broken personal file does nothing worse than being ignored with a
	/// reason — and the reason names both the key and the file, since a message
	/// that says only "a scheme is broken" sends somebody reading four hundred
	/// colours.
	@Test func aBrokenFileIsIgnoredWithAReason() throws {
		let bundled = try directory(), personal = try directory()
		try write(SchemeFileTests.wholeScheme(id: "blue", title: "Blue", order: 1),
		          named: "blue.json", into: bundled)
		try write(SchemeFileTests.wholeScheme(id: "nord", title: "Nord", omitting: "caret"),
		          named: "nord.json", into: personal)
		try write(Data("{{{".utf8), named: "broken.json", into: personal)

		let store = library(bundled: bundled, personal: personal)
		#expect(store.schemes.map(\.id) == ["blue"])
		#expect(store.problems.count == 2)
		#expect(store.problems.contains { $0.contains("nord.json") && $0.contains("app.caret is missing") })
		#expect(store.problems.contains { $0.contains("broken.json") })
	}

	/// A directory that is not there is the ordinary case, not a failure.
	@Test func aMissingPersonalDirectoryIsNotAProblem() throws {
		let bundled = try directory()
		try write(SchemeFileTests.wholeScheme(id: "blue", title: "Blue", order: 1), named: "blue.json", into: bundled)
		let store = library(bundled: bundled, personal: bundled.appendingPathComponent("nowhere"))
		#expect(store.schemes.map(\.id) == ["blue"])
		#expect(store.problems.isEmpty)
	}

	/// And if nothing at all can be read the app still starts, in a grey nobody
	/// would mistake for a palette they chose.
	@Test func fallsBackToAGreyWhenThereAreNone() throws {
		let empty = try directory()
		let store = library(bundled: empty, personal: nil)
		#expect(store.schemes.map(\.title) == ["Fallback"])
		#expect(store.defaultAppScheme.app != nil)
		#expect(store.defaultTerminalScheme.terminal != nil)
	}

	/// Stated order first, then alphabetically, so a personal scheme that says
	/// nothing lands at the end rather than in the middle of the shipped ones.
	@Test func listsThemInAStatedOrder() throws {
		let bundled = try directory(), personal = try directory()
		try write(SchemeFileTests.wholeScheme(id: "b", title: "Bee", order: 2), named: "b.json", into: bundled)
		try write(SchemeFileTests.wholeScheme(id: "a", title: "Ay", order: 1), named: "a.json", into: bundled)
		try write(SchemeFileTests.wholeScheme(id: "z", title: "Zed", order: nil), named: "z.json", into: personal)
		try write(SchemeFileTests.wholeScheme(id: "m", title: "Em", order: nil), named: "m.json", into: personal)

		#expect(library(bundled: bundled, personal: personal).schemes.map(\.id) == ["a", "b", "m", "z"])
	}

	/// The theme list offers the ones that dress the editor; the terminal list
	/// offers those and the one that only dresses the terminal.
	@Test func separatesWhatEachListOffers() throws {
		let bundled = try directory()
		try write(SchemeFileTests.wholeScheme(id: "blue", title: "Blue", order: 1), named: "blue.json", into: bundled)
		try write(SchemeFileTests.wholeScheme(id: "editor", title: "Editor colours", order: 2, app: false, follows: true),
		          named: "editor.json", into: bundled)

		let store = library(bundled: bundled, personal: nil)
		#expect(store.appSchemes.map(\.id) == ["blue"])
		#expect(store.terminalSchemes.map(\.id) == ["blue", "editor"])
	}
}

/// The schemes this app actually ships, checked here rather than on screen.
struct BundledSchemeTests {
	private let library = SchemeLibrary.shared

	/// The test the entry asked for: a shipped scheme missing a colour should
	/// fail in the suite, not in somebody's window.
	@Test func everyBundledSchemeReads() {
		#expect(library.problems.isEmpty, "\(library.problems)")
		#expect(library.schemes.map(\.id) == ["abydos", "blue", "dracula", "editor", "gray"])
	}

	/// Every palette names a terminal palette of its own. One added without a
	/// terminal section falls back to blue, which is how somebody ends up with a
	/// Dracula editor beside a terminal nobody chose.
	@Test func everyThemeDressesTheTerminalToo() {
		for scheme in library.appSchemes {
			#expect(scheme.terminal != nil, "\(scheme.id) has no terminal section")
		}
	}

	/// The one shipped scheme that is only a terminal palette, and follows the
	/// editor for its ground, text and cursor.
	@Test func editorColoursIsATerminalPaletteThatFollows() throws {
		let editor = try #require(library.scheme(id: "editor"))
		#expect(editor.app == nil)
		#expect(editor.title == "Editor colours")
		#expect(editor.terminal?.followsEditor == true)
		// And answers to what it was called when the palettes were an enum.
		#expect(Appearance.terminalSchemeIdentifier(for: "dark") == "editor")
	}

	/// The values themselves, spot-checked against what the Swift constants
	/// held: the amber the Abydos caret is, and Dracula's own pink.
	@Test func carriesTheColoursThePaletteAlwaysHad() throws {
		let abydos = try #require(library.appScheme(id: "abydos")?.app)
		#expect(abydos.colour(.caret, isLight: false) == 0xF7B44E)
		#expect(abydos.colour(.caret, isLight: true) == 0xB07407)
		#expect(abydos.colour(.editorBackground, isLight: false) == 0x151210)

		let dracula = try #require(library.appScheme(id: "dracula")?.app)
		#expect(dracula.colour(.keyword, isLight: false) == 0xFF79C6)
		#expect(dracula.colour(.string, isLight: false) == 0xF1FA8C)

		let blue = try #require(library.appScheme(id: "blue")?.app)
		#expect(blue.colour(.editorBackground, isLight: true) == 0xFFFFFF)
		#expect(blue.colour(.keyword, isLight: true) == 0x0033B3)

		// A kind that used to return `editorText` from the Swift switch, and is
		// written out here rather than left to be inherited.
		#expect(blue.colour(.variable, isLight: false) == blue.colour(.editorText, isLight: false))
	}

	/// Every shipped scheme states every role it is allowed to leave out.
	///
	/// The derivations are for schemes nobody has looked at. Ours have been
	/// looked at, in both lightnesses, against a real file — so a shipped scheme
	/// falling back to one would mean somebody added a palette and never saw an
	/// unfocused selection or a find highlight in it.
	@Test func everyBundledSchemeChoosesTheRolesItCouldLeaveOut() throws {
		for scheme in library.appSchemes {
			let data = try Data(contentsOf: URL(fileURLWithPath: scheme.origin))
			let document = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
			let app = try #require(document["app"] as? [String: Any])
			for role in SchemeRole.optional {
				#expect(app[role.rawValue] != nil, "\(scheme.id) leaves \(role.rawValue) to the derivation")
			}
		}

		let abydos = try #require(library.appScheme(id: "abydos")?.app)
		#expect(abydos.colour(.selectionBackgroundInactive, isLight: false) == 0x3A2E24)
		#expect(abydos.colour(.selectionBackgroundInactive, isLight: true) == 0xE5D9C2)
		#expect(abydos.colour(.searchMatchCurrentBackground, isLight: false) == 0xC77B3B)
		#expect(abydos.colour(.searchMatchBackground, isLight: false) == 0x5A4A2A)
	}

	/// The current find match is the loudest thing on the row, in every scheme
	/// and at both lightnesses.
	///
	/// **0536 in one claim.** Three matches of `publish` on adjacent lines, and
	/// the current one was the darkest of the three: it is painted in the strong
	/// colour, then the selection — the match *is* the selection, since revealing
	/// one selects it — was painted over the top of it in the quiet colour. The
	/// paint order is what was fixed and cannot be tested without a window, but
	/// the colours can, and the ordering they have to be in is this one. Two of
	/// the three shipped palettes had never been asked the question at all: the
	/// two values were hardcoded in the view, chosen against a dark amber ground,
	/// and every light scheme got them.
	///
	/// Contrast against the scheme's own editor background, which is the only
	/// ground any of these are seen on.
	@Test func theCurrentFindMatchOutshoutsEverythingItSitsAmong() throws {
		for scheme in library.appSchemes {
			let app = try #require(scheme.app)
			for isLight in [true, false] {
				let ground = app.colour(.editorBackground, isLight: isLight)
				func lift(_ role: SchemeRole) -> Double {
					Contrast.ratio(app.colour(role, isLight: isLight), ground)
				}
				let where_ = "\(scheme.id), \(isLight ? "light" : "dark")"

				// Louder than the matches it is meant to be found among, which is
				// the whole point of there being a current one.
				#expect(lift(.searchMatchCurrentBackground) > lift(.searchMatchBackground), "\(where_)")
				// And louder than either selection colour, so nothing that lands
				// on the same characters can take the eye off it.
				#expect(lift(.searchMatchCurrentBackground) > lift(.selectionBackground), "\(where_)")
				#expect(lift(.searchMatchCurrentBackground) > lift(.selectionBackgroundInactive), "\(where_)")
				// The others still have to be seen. Below this a match on the next
				// line reads as an artefact of the ground rather than a match.
				#expect(lift(.searchMatchBackground) > 1.15, "\(where_)")
			}
		}
	}

	/// Ghostty's sixteen, which is what somebody arriving from Ghostty expects.
	@Test func carriesTheTerminalTablesTheyAlwaysHad() throws {
		let blue = try #require(library.scheme(id: "blue")?.terminal)
		#expect(blue.named(isLight: false).first == 0x1D1F21)
		#expect(blue.named(isLight: false)[1] == 0xCC6666)
		#expect(blue.background?.dark == 0x282935)

		let editor = try #require(library.scheme(id: "editor")?.terminal)
		#expect(editor.named(isLight: false)[1] == 0xC7756B)
		#expect(editor.named(isLight: true)[1] == 0xC8503F)
	}

	/// The prose that used to be the doc comment above the Swift constant
	/// travels with the colours rather than being left behind in a file nobody
	/// opens.
	@Test func saysWhatEachIsFor() {
		for scheme in library.schemes {
			#expect(!scheme.about.isEmpty, "\(scheme.id) says nothing about itself")
		}
	}
}

/// WCAG's contrast ratio, for making a claim about two colours that would
/// otherwise be a matter of taste.
///
/// Here rather than in the app because nothing in the app draws from it — the
/// colours are chosen by eye and checked here, which is the right way round: a
/// number is what stops "it looked fine to me" from being the only account of
/// why one highlight is stronger than another.
enum Contrast {
	static func ratio(_ first: UInt32, _ second: UInt32) -> Double {
		let bright = max(luminance(first), luminance(second))
		let dim = min(luminance(first), luminance(second))
		return (bright + 0.05) / (dim + 0.05)
	}

	private static func luminance(_ colour: UInt32) -> Double {
		func channel(_ shift: UInt32) -> Double {
			let value = Double((colour >> shift) & 0xFF) / 255
			return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
		}
		return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
	}
}
