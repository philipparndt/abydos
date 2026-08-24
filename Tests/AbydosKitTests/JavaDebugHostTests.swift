import Foundation
import Testing
@testable import AbydosKit

/// 0452: the debugger no longer goes with the choice of editing server.
///
/// The claim these are about is a negative one — that a second jdtls started for
/// the debugger answers *nothing* about files — and a negative is what a comment
/// is worst at holding. So the first four are about the surface, which is where
/// the enforcement lives, and the last one drives a real server and counts what
/// it threw away.
@MainActor
struct JavaDebugHostTests {
	/// Which server hosts the adapter is not the project's decision.
	///
	/// The whole of 0452 in one assertion. `definition(forLanguage:choosing:)`
	/// answers with the server the project picked for *editing*; asking it here
	/// would give back kmp-lsp, which has no adapter in it, and the debugger would
	/// be exactly as absent as before.
	@Test func theAdapterHostIsNotWhicheverServerTheProjectChose() {
		#expect(JavaDebugHost.definition(forLanguage: "java")?.name == "jdtls")

		let chose = LanguageServerChoices(
			byLanguage: ["java": .init(name: "kmp-lsp", source: .project)]
		)
		// The editing server really is the other one, so this is not a test that
		// would pass by both answers happening to agree.
		#expect(LanguageServers.definition(forLanguage: "java", choosing: chose)?.name == "kmp-lsp")
		#expect(JavaDebugHost.definition(forLanguage: "java")?.name == "jdtls")

		// And nothing hosts one for a language whose servers are not set up for it.
		#expect(JavaDebugHost.definition(forLanguage: "go") == nil)
	}

	/// `hostsDebugAdapter` is exactly the servers the bundle is offered to.
	@Test func onlyTheServerTheBundleIsLoadedIntoHostsIt() {
		#expect(LanguageServers.server(named: "jdtls")?.hostsDebugAdapter == true)
		#expect(LanguageServers.server(named: "kmp-lsp")?.hostsDebugAdapter == false)
		#expect(LanguageServers.server(named: "gopls")?.hostsDebugAdapter == false)
		// It is the setup and not the name, which is what keeps it true the day
		// jdtls is packaged under another one.
		#expect(LanguageServers.known.filter(\.hostsDebugAdapter).allSatisfy { $0.setup == .java })
	}

	/// The debugger's jdtls gets an Eclipse workspace of its own.
	///
	/// Two jdtls in one `-data` directory corrupt it. They cannot both run for one
	/// project by construction — a project whose chosen server hosts the adapter
	/// debugs through the server it already has — but the second directory is what
	/// makes that safe even if somebody changes the choice mid-session.
	@Test func theDebuggersWorkspaceIsNotTheEditingServers() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(JavaDebugHost.workspace(for: root) != JavaTooling.serverWorkspace(for: root))
		// Beside it rather than inside it, so neither is a subdirectory of the
		// other and cleaning one up cannot take the other with it.
		#expect(
			JavaDebugHost.workspace(for: root).deletingLastPathComponent()
				== JavaTooling.serverWorkspace(for: root).deletingLastPathComponent()
		)
	}

	/// Every reason Debug cannot be honoured is knowable before anything waits.
	@Test func whyItCannotBeDebuggedIsAnsweredWithoutStartingAnything() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		// No build file: this is not a project any Java server would be started
		// for, so nothing can host an adapter for it.
		#expect(JavaDebugHost.refusal(project: root) == .nothingHostsIt)

		// A project worked on inside its own devcontainer. Refused whatever else
		// is true of the machine, and refused *first*: the bundle is a path out
		// here and the JVM would be this machine's.
		try JavaTestDirectory.write("<project/>", to: root.appendingPathComponent("pom.xml"))
		#expect(
			JavaDebugHost.refusal(project: root, inDevContainer: "abydos-devcontainer-1")
				== .inDevContainer(name: "abydos-devcontainer-1")
		)

		// Which of them stops Debug being offered at all, and which is offered and
		// explained when pressed. Installing a jar is a minute; a devcontainer is
		// the project saying which toolchain it is worked on with.
		#expect(JavaDebugHost.Failure.nothingHostsIt.isSettledHere)
		#expect(JavaDebugHost.Failure.inDevContainer(name: "x").isSettledHere)
		#expect(!JavaDebugHost.Failure.noBundle.isSettledHere)
		#expect(!JavaDebugHost.Failure.notInstalled(hint: "brew install jdtls").isSettledHere)
		#expect(!JavaDebugHost.Failure.stillImporting(seconds: 90, saying: nil).isSettledHere)
	}

	/// A wait that cannot say what it is waiting for looks like a hang, and this
	/// is the sentence it says.
	@Test func theWaitNamesWhatItIsWaitingForAndHowLong() {
		let quiet = JavaDebugHost.Failure.stillImporting(seconds: 274, saying: nil)
		#expect(quiet.localizedDescription.contains("274 s"))
		#expect(quiet.localizedDescription.contains("importing"))

		let said = JavaDebugHost.Failure.stillImporting(
			seconds: 274, saying: "Starting 42% Importing Maven project(s)"
		)
		#expect(said.localizedDescription.contains("Importing Maven project(s)"))
	}

	/// An answer with nothing in it is not a wait, and it does not read as one.
	///
	/// Measured on a Tycho bundle: jdtls answers `getClasspaths` at once with an
	/// empty list, because that bundle's classpath comes from an OSGi target
	/// platform and its pom declares nothing. The older code sent the launch
	/// anyway and the JVM died with `ClassNotFoundException` on the class somebody
	/// had asked for, which reads as a missing class.
	@Test func anEmptyClasspathIsAnAnswerAndNotAWait() {
		let said = JavaDebugHost.Failure.noClasspath(project: "org.eclipse.sirius")
		#expect(said.localizedDescription.contains("org.eclipse.sirius"))
		// It must not read as "come back in a minute", because it will say the same
		// thing in a minute.
		#expect(said.localizedDescription.contains("not still working it out"))
		// And it cannot decide whether Debug is offered: nothing knows it until a
		// server has been asked.
		#expect(!JavaDebugHost.Failure.noClasspath(project: "x").isSettledHere)
	}

	/// A classpath about another project is not this project's classpath.
	///
	/// jdtls answers `getClasspaths` about `jdt.ls-java-project` — its own fallback
	/// workspace, inside its `-data` directory — until the real import has
	/// finished. It is a well-formed answer for the wrong thing, and taking it
	/// compiled a class against the newest JDK on the machine and launched it on an
	/// older one: `UnsupportedClassVersionError`, from a project that pins its
	/// release in its pom and has nothing wrong with it.
	@Test func aClasspathAboutSomebodyElsesProjectIsNotAnAnswer() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(JavaDebugHost.isInside(root.path, root))
		#expect(JavaDebugHost.isInside(root.appendingPathComponent("src").path, root))
		// The fallback, which lives in the caches directory and not in any project.
		#expect(!JavaDebugHost.isInside(
			JavaDebugHost.workspace(for: root).appendingPathComponent("jdt.ls-java-project").path,
			root
		))
		// And the neighbour whose name starts the same way, which is the mistake a
		// bare `hasPrefix` makes.
		#expect(!JavaDebugHost.isInside(root.path + "-old", root))
	}

	/// **And it arrives as a URI, not as a path.** java-debug answers
	/// `projectRoot` with `file:/Users/…` — one slash, not three — and
	/// `URL(fileURLWithPath:)` reads that as a relative path whose first
	/// component is `file:`, so it comes back as the working directory with the
	/// whole URI on the end and is inside nothing.
	///
	/// Every test above passes a `.path`, which is why this went unseen while it
	/// rejected every classpath java-debug 0.53.2 ever returned: a module of the
	/// repository being debugged was reported as being somewhere else, and the
	/// editor said the import had not finished about an import that had finished
	/// half an hour earlier.
	@Test func aProjectRootArrivingAsAURIIsStillInsideTheProject() throws {
		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }

		let module = root.appendingPathComponent("cli/com.vector.acli.application")
		#expect(JavaDebugHost.isInside("file:" + module.path, root))
		#expect(JavaDebugHost.isInside("file://" + module.path, root))
		#expect(JavaDebugHost.isInside(module.path, root), "a plain path still works")

		// The checks above must not have been bought by making everything inside.
		#expect(!JavaDebugHost.isInside("file:" + root.path + "-old", root))
		#expect(!JavaDebugHost.isInside(
			"file:" + JavaDebugHost.workspace(for: root)
				.appendingPathComponent("jdt.ls-java-project").path,
			root
		))
	}

	/// The name comes off the same answer, so it needs the same parse. It used to
	/// be right by accident — the last component of a mis-parsed URI is still the
	/// last component — and naming a project by accident is not naming it.
	@Test func theProjectNameIsReadFromAURIToo() {
		#expect(
			JavaDebugHost.projectName(fromRoot: "file:/a/b/com.vector.acli.application")
				== "com.vector.acli.application"
		)
		#expect(JavaDebugHost.projectName(fromRoot: "/a/b/plain") == "plain")
		// Percent-encoding, which a path with a space in it arrives carrying.
		#expect(JavaDebugHost.projectName(fromRoot: "file:/a/b/two%20words") == "two words")
	}

	/// Where somebody chooses between two servers, both of them say what they
	/// cost.
	///
	/// 0449 asked for this line and left it to whoever knew the trade; 0450 wrote
	/// it into its own entry rather than onto the screen. A language with one
	/// server has no trade to describe, so it carries none.
	@Test func everyServerSomebodyHasToChooseBetweenSaysWhatItCosts() {
		for group in LanguageServers.languageGroups() where group.candidates.count > 1 {
			for candidate in group.candidates {
				#expect(candidate.trade != nil, "\(candidate.name) offers a choice and no reason")
			}
		}
		// And the sentence beside the fast one says the debugger still works,
		// which is the fact 0452 changed.
		let fast = LanguageServers.server(named: "kmp-lsp")?.trade ?? ""
		#expect(fast.contains("Debug"))
	}

	/// The whole of it against a real jdtls: a host that answers the debugger's
	/// two questions and nothing about any file.
	///
	/// **`diagnosticsDropped` is the measurement, not the port.** jdtls reports
	/// compilation problems for everything it imports whether anybody asked or
	/// not, and those are what a second server for one language would put on
	/// screen beside the first server's — which is the mess 0449 refused. A count
	/// greater than zero says jdtls did send them and this host passed none on; a
	/// count of zero would prove nothing either way, so it is checked as a range
	/// rather than asserted as an absence.
	///
	/// Under `SCALE=1`, for the reason `JavaLiveTests` gives about itself: this
	/// holds a second JVM open beside the suite, and timing assertions in
	/// unrelated suites start failing at the load that puts there.
	///
	///     make test SCALE=1 FILTER=aDebugHostAnswers
	@Test func aDebugHostAnswersTheDebuggerAndNothingAboutFiles() async throws {
		guard ProcessInfo.processInfo.environment["SCALE"] != nil else { return }
		guard let definition = JavaDebugHost.definition(forLanguage: "java"),
		      LanguageServers.executable(for: definition) != nil,
		      JavaTooling.debugPlugin() != nil
		else { return }

		let root = try Self.makeProject()
		defer { try? FileManager.default.removeItem(at: root) }
		defer { try? FileManager.default.removeItem(at: JavaDebugHost.workspace(for: root)) }

		// The project chose the *other* server for editing, which is the case this
		// exists for. Nothing here starts that server — the point is that the
		// debugger does not need it to have been started.
		let chose = LanguageServerChoices(
			byLanguage: ["java": .init(name: "kmp-lsp", source: .project)]
		)
		#expect(LanguageServers.definition(forLanguage: "java", choosing: chose)?.name == "kmp-lsp")

		let host = try JavaDebugHost.start(project: root)
		defer { host.stop() }
		try await host.handshake()

		let anchor = root.appendingPathComponent("src/main/java/com/example/live/Server.java")
		let ready = try await host.waitUntilLaunchable(anchor: anchor, deadline: 180)
		#expect(ready.port > 0)
		#expect(!ready.classPaths.isEmpty)
		// The classpath is the module's own output directory plus whatever the pom
		// pulled in, and `target/classes` is the one every Maven project has.
		#expect(ready.classPaths.contains { $0.contains("target/classes") })

		// What it heard about files, and where that went.
		#expect(host.diagnosticsDropped >= 0)
		print("  debug host: \(host.diagnosticsDropped) publishDiagnostics dropped, "
			+ "\(ready.classPaths.count) classpath entries, port \(ready.port)")
	}

	/// The smallest thing jdtls will import, written where a live server can read
	/// it. The same shape `JavaLiveTests` uses, and separate on purpose: a test
	/// that shared a fixture directory with another live test would have two
	/// servers importing one workspace.
	static func makeProject() throws -> URL {
		let root = try JavaTestDirectory.make()
		try JavaTestDirectory.write("""
		<?xml version="1.0" encoding="UTF-8"?>
		<project xmlns="http://maven.apache.org/POM/4.0.0">
			<modelVersion>4.0.0</modelVersion>
			<groupId>com.example</groupId>
			<artifactId>debughost</artifactId>
			<version>1.0.0</version>
			<properties>
				<maven.compiler.release>21</maven.compiler.release>
			</properties>
		</project>
		""", to: root.appendingPathComponent("pom.xml"))
		try JavaTestDirectory.write("""
		package com.example.live;

		public class Server {
			public static void main(String[] args) {
				System.out.println("up");
			}
		}
		""", to: root.appendingPathComponent("src/main/java/com/example/live/Server.java"))
		return root
	}
}
