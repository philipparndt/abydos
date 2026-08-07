import Foundation
import Testing
@testable import AbydosKit

/// Finding and running PlantUML, which is never bundled.
struct PlantUMLTests {
	@Test func knowsWhichFilesAreDiagrams() {
		#expect(PlantUML.isDiagram(URL(fileURLWithPath: "/p/sequence.puml")))
		#expect(PlantUML.isDiagram(URL(fileURLWithPath: "/p/Design.PlantUML")))
		#expect(PlantUML.isDiagram(URL(fileURLWithPath: "/p/notes.wsd")))
		#expect(!PlantUML.isDiagram(URL(fileURLWithPath: "/p/notes.md")))
	}

	/// The command on the PATH wins: somebody who installed it that way expects
	/// that one, wrapper script and all.
	@Test func prefersTheInstalledCommand() {
		let found = PlantUML.discover(
			environment: ["PLANTUML_JAR": "/somewhere/plantuml.jar"],
			locate: { $0 == "plantuml" ? "/opt/homebrew/bin/plantuml" : "/usr/bin/java" },
			fileExists: { _ in true }
		)
		#expect(found == .command("/opt/homebrew/bin/plantuml"))
	}

	/// No command, but a jar named outright.
	@Test func takesTheJarItIsPointedAt() {
		let found = PlantUML.discover(
			environment: ["PLANTUML_JAR": "/home/me/plantuml.jar"],
			locate: { $0 == "java" ? "/usr/bin/java" : nil },
			fileExists: { $0 == "/home/me/plantuml.jar" }
		)
		#expect(found == .jar(path: "/home/me/plantuml.jar", java: "/usr/bin/java"))
	}

	/// A jar that was named but is not there is not a PlantUML: falling back to
	/// the usual places is better than failing to run something that is gone.
	@Test func ignoresAJarThatIsNotThere() {
		let found = PlantUML.discover(
			environment: ["PLANTUML_JAR": "/gone/plantuml.jar"],
			locate: { $0 == "java" ? "/usr/bin/java" : nil },
			fileExists: { $0 == "/opt/homebrew/opt/plantuml/libexec/plantuml.jar" }
		)
		#expect(found == .jar(path: "/opt/homebrew/opt/plantuml/libexec/plantuml.jar", java: "/usr/bin/java"))
	}

	/// A jar is no use without a Java to run it.
	@Test func findsNothingWithoutJava() {
		let found = PlantUML.discover(
			environment: ["PLANTUML_JAR": "/home/me/plantuml.jar"],
			locate: { _ in nil },
			fileExists: { _ in true }
		)
		#expect(found == nil)
	}

	@Test func findsNothingWhenThereIsNothing() {
		#expect(PlantUML.discover(environment: [:], locate: { _ in nil }, fileExists: { _ in false }) == nil)
	}

	/// Reading from standard input and writing to standard output, so nothing
	/// is ever written beside somebody's source.
	@Test func runsThroughAPipe() {
		let run = PlantUML.invocation(for: .command("/opt/homebrew/bin/plantuml"))
		#expect(run.executable == "/opt/homebrew/bin/plantuml")
		#expect(run.arguments == ["-pipe", "-tpng", "-charset", "UTF-8"])

		let svg = PlantUML.invocation(for: .command("/bin/plantuml"), format: .svg)
		#expect(svg.arguments.contains("-tsvg"))
	}

	/// A jar is run headless, or the JVM takes the focus every time a preview
	/// refreshes — which, while somebody is typing, is every few keystrokes.
	@Test func runsAJarWithoutADockIcon() {
		let run = PlantUML.invocation(for: .jar(path: "/p/plantuml.jar", java: "/usr/bin/java"))
		#expect(run.executable == "/usr/bin/java")
		#expect(run.arguments.first == "-Djava.awt.headless=true")
		#expect(run.arguments.contains("-jar"))
		#expect(run.arguments.contains("/p/plantuml.jar"))
	}

	/// A file nobody has written a diagram in yet is not an error to draw.
	@Test func waitsForADiagramBeforeDrawingOne() {
		#expect(!PlantUML.hasDiagram(""))
		#expect(!PlantUML.hasDiagram("// just a thought\n"))
		#expect(PlantUML.hasDiagram("@startuml\nAlice -> Bob\n@enduml\n"))
		#expect(PlantUML.hasDiagram("@startmindmap\n* root\n@endmindmap\n"))
	}

	/// An error picture is still a picture, and it names the line that is
	/// wrong. Nothing at all is what a broken installation looks like.
	@Test func showsWhatCameBackUnlessNothingDid() {
		#expect(PlantUML.isPicture(Data([0x89, 0x50, 0x4E, 0x47])))
		#expect(!PlantUML.isPicture(Data()))
	}
}

/// The signal a preview follows.
///
/// PlantUML has no grammar here, so nothing reparses when a diagram is edited
/// and the callback the markdown preview uses never fires. A preview hung on
/// that one would draw once when the file opened and never again.
struct DocumentTextChangeTests {
	private func document(named name: String, contents: String) throws -> (TextDocument, URL) {
		let directory = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("abydos-text-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let url = directory.appendingPathComponent(name)
		try contents.write(to: url, atomically: true, encoding: .utf8)
		return (try TextDocument(url: url), url)
	}

	@Test func aDiagramIsItsOwnLanguageWithNoGrammar() throws {
		let (document, _) = try document(named: "d.puml", contents: "@startuml\n@enduml\n")
		#expect(document.languageId == "plantuml")
		#expect(document.displayLanguageName == "PlantUML")
	}

	@Test func saysTheTextChangedEvenWithNothingToParse() throws {
		let (document, _) = try document(named: "d.puml", contents: "@startuml\n@enduml\n")
		var changes = 0
		document.onTextChanged = { changes += 1 }

		_ = document.replace(utf16Range: 0..<0, with: "Alice -> Bob\n", caretBefore: 0)
		#expect(changes == 1)

		_ = document.replace(utf16Range: 0..<0, with: "' a note\n", caretBefore: 0)
		#expect(changes == 2)
	}

	/// And when somebody else writes the file.
	@Test func saysSoWhenTheFileIsRewrittenFromOutside() throws {
		let (document, url) = try document(named: "d.puml", contents: "@startuml\n@enduml\n")
		var changes = 0
		document.onTextChanged = { changes += 1 }

		try "@startuml\nAlice -> Bob\n@enduml\n".write(to: url, atomically: true, encoding: .utf8)
		#expect(try document.reloadFromDisk())
		#expect(changes == 1)
	}
}
