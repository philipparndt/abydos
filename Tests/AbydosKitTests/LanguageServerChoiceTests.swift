import Foundation
import Testing
@testable import AbydosKit

/// A project choosing which language server answers for a language.
///
/// Most of these are asked of a table this file makes up rather than of the
/// app's own, and that is deliberate rather than lazy. The mechanism was built
/// before there was anything to choose between — 0450 adds the second Java
/// server — so proving it needed two servers for one language, and the
/// alternative was a file of tests that could only be written the day the second
/// one landed. The ones that *are* asked of the real table are the ones that
/// matter today: a project naming a server this app has not got.
struct LanguageServerChoiceTests {
	/// Two servers for Java with opposite trades, which is the case the whole
	/// thing exists for: one that reads the build file and costs a JVM, and one
	/// that is instant and syntactic.
	private let table: [LanguageServerDefinition] = [
		LanguageServerDefinition(
			languageIds: ["java"],
			command: "jdtls",
			installHint: "brew install jdtls",
			rootMarkers: ["pom.xml"],
			setup: .java
		),
		LanguageServerDefinition(
			languageIds: ["java"],
			command: "kmp-lsp",
			installHint: "cargo install kmp-lsp",
			rootMarkers: ["pom.xml", "build.gradle"]
		),
		LanguageServerDefinition(
			languageIds: ["c", "cpp", "objc"],
			command: "clangd",
			installHint: "brew install llvm",
			rootMarkers: ["compile_commands.json"]
		),
	]

	private func makeTree(_ names: [String]) throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("choice-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		for name in names {
			try "".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
		}
		return root
	}

	private func write(_ json: String, to root: URL) throws {
		let folder = AbydosFolder.url(in: root)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		try json.write(to: ToolImages.url(in: root), atomically: true, encoding: .utf8)
	}

	// MARK: - Which one

	@Test func takesTheFirstOfSeveralWhenNobodyHasChosen() {
		let chosen = LanguageServers.selection(forLanguage: "java", choosing: .none, among: table)
		#expect(chosen == .server(table[0], source: .builtIn))
	}

	@Test func takesTheOneTheProjectNamed() {
		let choices = LanguageServerChoices(
			byLanguage: ["java": .init(name: "kmp-lsp", source: .project)]
		)
		let chosen = LanguageServers.selection(forLanguage: "java", choosing: choices, among: table)
		#expect(chosen == .server(table[1], source: .project))
	}

	/// 0424 settled this for a diagram's theme and it is the same rule here: the
	/// file is a statement about the project, the setting is one person's
	/// default, and the project wins.
	@Test func theFileWinsAndTheSettingIsTheDefault() {
		let settings = LanguageServerChoices.settings(["java": "kmp-lsp"])
		#expect(
			LanguageServers.selection(forLanguage: "java", choosing: settings, among: table)
				== .server(table[1], source: .settings)
		)

		let both = LanguageServerChoices.resolve(
			project: LanguageServerChoices(
				byLanguage: ["java": .init(name: "jdtls", source: .project)]
			),
			settings: settings
		)
		#expect(
			LanguageServers.selection(forLanguage: "java", choosing: both, among: table)
				== .server(table[0], source: .project)
		)
	}

	/// A setting about one language does not answer for another.
	@Test func aChoiceIsAboutOneLanguageOnly() {
		let choices = LanguageServerChoices.settings(["java": "kmp-lsp"])
		#expect(
			LanguageServers.selection(forLanguage: "cpp", choosing: choices, among: table)
				== .server(table[2], source: .builtIn)
		)
	}

	// MARK: - Saying so rather than falling back

	/// **The failure this item exists to prevent.** Somebody asks for the fast
	/// server, it is not here, and the answer is a sentence — not the 1.9 GB one
	/// started quietly in its place.
	@Test func aServerNobodyHasIsSaidRatherThanSwappedForTheOther() {
		// `java-language-server` is a real Java server and one this app has
		// never heard of, which is the case. It used to be `kmp-lsp`, on the
		// strength of the app's table having one Java server; 0450 put a second
		// in it and this test started asserting that the server it had just
		// added did not exist.
		let choices = LanguageServerChoices(
			byLanguage: ["java": .init(name: "java-language-server", source: .project)]
		)
		#expect(
			LanguageServers.selection(forLanguage: "java", choosing: choices)
				== .noSuchServer(name: "java-language-server", source: .project)
		)
		#expect(LanguageServers.definition(forLanguage: "java", choosing: choices) == nil)

		let said = LanguageServers.refusal(
			named: "java-language-server", forLanguage: "java", source: .project
		)
		#expect(said.contains(".abydos/tools.json"))
		#expect(said.contains("no language server called java-language-server"))
		// It names what there is instead, and says plainly that it has not
		// started it. Both halves matter: the first is what to type, the second
		// is why nobody should go looking for a running server.
		#expect(said.contains("jdtls"))
		#expect(said.contains("kmp-lsp"))
		#expect(said.contains("Nothing has been started in its place"))
	}

	/// A real server, named for a language it does not answer for. Refused too,
	/// and told apart from a name nobody has ever heard of, because the two need
	/// different things done about them.
	@Test func aServerThatAnswersForAnotherLanguageIsRefusedByName() {
		let choices = LanguageServerChoices(
			byLanguage: ["java": .init(name: "gopls", source: .settings)]
		)
		#expect(
			LanguageServers.selection(forLanguage: "java", choosing: choices)
				== .noSuchServer(name: "gopls", source: .settings)
		)

		let said = LanguageServers.refusal(named: "gopls", forLanguage: "java", source: .settings)
		#expect(said.contains("answers for Go rather than for Java"))
		#expect(said.contains("Settings"))
	}

	// MARK: - What the choice moves with it

	/// A server is filed under its own name, so changing the choice does not
	/// find the one that was running before.
	@Test func theRunningServerIsFiledUnderTheServerChosen() {
		let project = URL(fileURLWithPath: "/tmp/project")
		let choices = LanguageServerChoices(
			byLanguage: ["java": .init(name: "kmp-lsp", source: .project)]
		)
		#expect(
			LanguageServers.serverKey(
				project: project, languageId: "java", choosing: choices, among: table
			) == "/tmp/project#kmp-lsp"
		)
		#expect(
			LanguageServers.serverKey(project: project, languageId: "java", choosing: .none)
				== "/tmp/project#jdtls"
		)
	}

	/// And a name nothing answers to keeps a key of its own, so what is
	/// remembered about the refusal is not remembered about the other server.
	@Test func aServerNobodyHasStillGetsAKeyOfItsOwn() {
		let choices = LanguageServerChoices(
			byLanguage: ["java": .init(name: "kmp-lsp", source: .project)]
		)
		#expect(
			LanguageServers.serverKey(
				project: URL(fileURLWithPath: "/tmp/project"), languageId: "java", choosing: choices
			) == "/tmp/project#kmp-lsp"
		)
	}

	/// Two servers for one language is what the entry ruled out, and this is
	/// where it is ruled out: the scan that starts a project's servers offers
	/// the chosen one and not both.
	@Test func onlyTheChosenServerIsStarted() throws {
		let root = try makeTree(["pom.xml"])
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(
			LanguageServers.suitedDefinitions(in: root, choosing: .none, among: table)
				.map(\.name) == ["jdtls"]
		)

		let choices = LanguageServerChoices(
			byLanguage: ["java": .init(name: "kmp-lsp", source: .project)]
		)
		#expect(
			LanguageServers.suitedDefinitions(in: root, choosing: choices, among: table)
				.map(\.name) == ["kmp-lsp"]
		)
	}

	/// One server answers for several languages, and pointing one of them
	/// elsewhere does not drop it: clangd still answers for C++ and Objective-C.
	/// The caller starting one server per definition has to ask about a language
	/// this server is still the choice for, which is not `languageIds.first`.
	@Test func aServerKeepsTheLanguagesItIsStillChosenFor() throws {
		let root = try makeTree(["compile_commands.json"])
		defer { try? FileManager.default.removeItem(at: root) }

		let other = LanguageServerDefinition(
			languageIds: ["c"], command: "ccls", installHint: "brew install ccls",
			rootMarkers: ["compile_commands.json"]
		)
		let table = self.table + [other]
		let choices = LanguageServerChoices(byLanguage: ["c": .init(name: "ccls", source: .project)])

		let suited = LanguageServers.suitedDefinitions(in: root, choosing: choices, among: table)
		#expect(suited.map(\.name).sorted() == ["ccls", "clangd"])

		let clangd = try #require(suited.first { $0.name == "clangd" })
		#expect(
			LanguageServers.chosenLanguage(for: clangd, choosing: choices, among: table) == "cpp"
		)
	}

	/// The settings page asks one question per set of languages that share an
	/// answer, rather than four identical ones about TypeScript, JavaScript,
	/// TSX and JSX.
	@Test func languagesThatShareAnAnswerAreOneQuestion() {
		let groups = LanguageServers.languageGroups(among: table)
		#expect(groups.count == 2)
		#expect(groups[0].languageIds == ["java"])
		#expect(groups[0].candidates.map(\.name) == ["jdtls", "kmp-lsp"])
		#expect(groups[1].languageIds == ["c", "cpp", "objc"])
		#expect(groups[1].candidates.map(\.name) == ["clangd"])
	}

	// MARK: - The file

	@Test func readsTheChoiceOutOfTheProjectsOwnFile() throws {
		let root = try makeTree([])
		defer { try? FileManager.default.removeItem(at: root) }
		try write(#"{"languages": {"java": "kmp-lsp"}}"#, to: root)

		let choices = LanguageServerChoices.inProject(root)
		#expect(choices.chosen(forLanguage: "java")?.name == "kmp-lsp")
		#expect(choices.chosen(forLanguage: "java")?.source == .project)
	}

	/// Which server and where it comes from are two questions, and the file
	/// keeps them apart. `plantuml` is why: it is both a renderer that comes
	/// from an image and a language a server answers for, so one flat map would
	/// have a key whose meaning depended on which reader got to it first.
	@Test func theServerAndTheImageAreDifferentSections() throws {
		let root = try makeTree([])
		defer { try? FileManager.default.removeItem(at: root) }
		try write("""
		{
		  "languages": {"java": "kmp-lsp"},
		  "plantuml": "plantuml/plantuml:1.2025.4",
		  "kmp-lsp": "example/kmp-lsp:dev"
		}
		""", to: root)

		let images = ToolImages.inProject(root)
		#expect(images.image(for: "plantuml") == "plantuml/plantuml:1.2025.4")
		#expect(images.image(for: "kmp-lsp") == "example/kmp-lsp:dev")
		// And the section is not read as a tool that comes from an image.
		#expect(images.image(for: "languages") == nil)

		let choices = LanguageServerChoices.inProject(root)
		#expect(choices.chosen(forLanguage: "java")?.name == "kmp-lsp")
		// An image named for the PlantUML renderer says nothing about which
		// server answers for a `.puml` file.
		#expect(choices.chosen(forLanguage: "plantuml") == nil)
	}

	/// A file nobody can read is the same as no file, as it is for images: a
	/// broken one must not stop the project opening.
	@Test func abrokenFileIsTheSameAsNoFile() throws {
		let root = try makeTree([])
		defer { try? FileManager.default.removeItem(at: root) }
		try write("not json at all", to: root)
		#expect(LanguageServerChoices.inProject(root).isEmpty)

		try write(#"{"languages": {"java": ""}}"#, to: root)
		#expect(LanguageServerChoices.inProject(root).isEmpty)

		try write(#"{"languages": "kmp-lsp"}"#, to: root)
		#expect(LanguageServerChoices.inProject(root).isEmpty)
	}

	@Test func aProjectThatSaysNothingChoosesNothing() throws {
		let root = try makeTree([])
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(LanguageServerChoices.inProject(root).isEmpty)
		#expect(
			LanguageServers.definition(forLanguage: "java", choosing: .none)?.name == "jdtls"
		)
	}

	/// Asked of the app's own table rather than the made-up one above, because
	/// this is the claim that table cannot make: Java really does have two
	/// servers now. Until 0450 every test in this file was about a mechanism
	/// with nothing to choose between.
	@Test func javaReallyHasTwoServersAndTheSlowOneIsStillTheDefault() {
		#expect(LanguageServers.candidates(forLanguage: "java").map(\.name) == ["jdtls", "kmp-lsp"])
		// The order is the default, so a project that says nothing keeps the
		// server that reads the pom. Adding a second must change nothing for
		// anybody who has not asked.
		#expect(LanguageServers.definition(forLanguage: "java", choosing: .none)?.name == "jdtls")

		let asked = LanguageServerChoices(
			byLanguage: ["java": .init(name: "kmp-lsp", source: .project)]
		)
		#expect(
			LanguageServers.definition(forLanguage: "java", choosing: asked)?.name == "kmp-lsp"
		)
	}

	/// The debugger stays with jdtls, and that is the price of the fast one: the
	/// adapter is an Eclipse bundle loaded *inside* that server rather than a
	/// program beside it, so `setup == .java` is exactly the servers it can be
	/// offered to.
	@Test func onlyTheServerThatHostsTheDebugBundleIsSetUpAsJava() {
		#expect(LanguageServers.server(named: "jdtls")?.setup == .java)
		#expect(LanguageServers.server(named: "kmp-lsp")?.setup == .plain)
	}
}
