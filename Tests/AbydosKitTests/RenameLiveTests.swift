import Foundation
import Testing
@testable import AbydosKit

/// Renaming through a real language server, and the files afterwards.
///
/// Everything else about this mechanism can be reasoned about: a plan is a pure
/// function of an edit and some text, and `WorkspaceEditPlanTests` drives every
/// refusal and the rollback over files that live in a dictionary. What none of
/// that can prove is that a server *sends* what this code reads — that the
/// capabilities in `LSPClient.clientCapabilities` are the ones that make a
/// server answer with `documentChanges` at all, that a Java rename really does
/// carry the move of `Foo.java` to `Bar.java`, and that the whole of it, put
/// through the plan and the applier, leaves the right text in the right files.
///
/// Skipped where the server is not installed, the way every other live suite
/// here is. A skipped live test is not a pass.
@Suite(.serialized) struct RenameLiveTests {
	/// A rename across three files, with a server that answers in seconds.
	///
	/// The point is the *several files*: a mechanism that renames within one
	/// file is a find-and-replace, and everything hard about this item —
	/// documents that are not open, one undo, failing halfway — only exists
	/// because the answer arrives about files nobody was looking at.
	@Test func goplsRenamesAcrossThreeFilesAndTheUndoPutsThemAllBack() async throws {
		guard let definition = LanguageServers.known.first(where: { $0.name == "gopls" }),
		      let executable = LanguageServers.executable(for: definition)
		else { return }
		print("  rename: driving gopls at \(executable)")

		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)

		try JavaTestDirectory.write(
			"module example.com/probe\n\ngo 1.24\n",
			to: project.appendingPathComponent("go.mod")
		)
		try JavaTestDirectory.write("""
		package probe

		func Greeting() string {
			return "hello"
		}
		""", to: project.appendingPathComponent("greeting.go"))
		try JavaTestDirectory.write("""
		package probe

		func Loud() string {
			return Greeting() + "!"
		}
		""", to: project.appendingPathComponent("loud.go"))
		try JavaTestDirectory.write("""
		package probe

		func Quiet() string {
			return Greeting()
		}
		""", to: project.appendingPathComponent("quiet.go"))

		let client = LSPClient()
		client.callbackQueue = .global()
		defer { client.stop() }
		try client.start(executable: executable, arguments: [], workingDirectory: project)

		let capabilities = try await client.initialize(rootURL: project, timeout: 60)
		// The gate the editor uses, read from a server that really said it.
		#expect(capabilities["renameProvider"] != nil)
		#expect(client.renames)

		let declaration = project.appendingPathComponent("greeting.go")
		let uri = declaration.absoluteString
		client.didOpen(
			uri: uri, languageId: "go", version: 1,
			text: try String(contentsOf: declaration, encoding: .utf8)
		)

		// `Greeting` on the line it is declared on, character 5.
		let position = LSPPosition(line: 2, character: 5)
		let edit = try #require(
			try await settled(within: 60) {
				try await client.rename(uri: uri, position: position, to: "Salutation")
			},
			"gopls answered no edit"
		)

		// Three files, from one question about one of them.
		#expect(edit.files.count == 3, "gopls touched \(edit.files)")

		let files = WorkspaceEditFiles.disk
		let plan = WorkspaceEditPlan.make(edit, contents: files.contents, exists: files.exists)
		#expect(plan.refusals.isEmpty, "\(plan.refusals)")
		#expect(plan.writes.count == 3)

		guard case let .applied(applied) = WorkspaceEditApplier.apply(plan, to: files) else {
			Issue.record("the rename did not apply")
			return
		}

		for name in ["greeting.go", "loud.go", "quiet.go"] {
			let text = try String(
				contentsOf: project.appendingPathComponent(name), encoding: .utf8
			)
			#expect(text.contains("Salutation"), "\(name) still says Greeting")
			#expect(!text.contains("Greeting"), "\(name) still says Greeting")
		}

		// And one undo, over all three.
		#expect(WorkspaceEditApplier.reverse(applied, in: files).isUntouched)
		for name in ["greeting.go", "loud.go", "quiet.go"] {
			let text = try String(
				contentsOf: project.appendingPathComponent(name), encoding: .utf8
			)
			#expect(text.contains("Greeting"), "\(name) was not put back")
			#expect(!text.contains("Salutation"), "\(name) was not put back")
		}
	}

	/// The case the whole `documentChanges` half of this exists for: renaming a
	/// Java class moves the file it is in.
	///
	/// jdtls is slow — it imports the project into an Eclipse workspace before
	/// it answers anything — so this is one project, one rename, and a long
	/// patience. It is worth it: no other server here answers with a file
	/// operation, and a mechanism that had never carried one would be a
	/// mechanism nobody had checked.
	@Test func jdtlsRenamingAClassMovesTheFile() async throws {
		guard let definition = LanguageServers.known.first(where: { $0.name == "jdtls" }),
		      let executable = LanguageServers.executable(for: definition)
		else { return }
		print("  rename: driving jdtls at \(executable)")

		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)

		// An Eclipse project rather than a Maven one, for the reason
		// `ContainerLSPLiveTests` gives: a pom sends jdtls to Maven Central.
		try JavaTestDirectory.write("""
		<?xml version="1.0" encoding="UTF-8"?>
		<projectDescription>
			<name>probe</name>
			<buildSpec>
				<buildCommand>
					<name>org.eclipse.jdt.core.javabuilder</name>
				</buildCommand>
			</buildSpec>
			<natures>
				<nature>org.eclipse.jdt.core.javanature</nature>
			</natures>
		</projectDescription>
		""", to: project.appendingPathComponent(".project"))
		try JavaTestDirectory.write("""
		<?xml version="1.0" encoding="UTF-8"?>
		<classpath>
			<classpathentry kind="src" path="src"/>
			<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER"/>
			<classpathentry kind="output" path="bin"/>
		</classpath>
		""", to: project.appendingPathComponent(".classpath"))
		try JavaTestDirectory.write("""
		public class Greeting {
			static String text() {
				return "hello";
			}
		}
		""", to: project.appendingPathComponent("src/Greeting.java"))
		try JavaTestDirectory.write("""
		public class Caller {
			public static void main(String[] args) {
				System.out.println(Greeting.text());
			}
		}
		""", to: project.appendingPathComponent("src/Caller.java"))

		LanguageServers.prepare(definition, root: project)

		let client = LSPClient()
		client.callbackQueue = .global()
		defer { client.stop() }
		try client.start(
			executable: executable,
			arguments: LanguageServers.arguments(for: definition, root: project),
			workingDirectory: project,
			environment: LanguageServers.serverEnvironment
		)

		_ = try await client.initialize(
			rootURL: project,
			options: LanguageServers.initializationOptions(
				for: definition, root: project, inContainer: false
			),
			timeout: 240
		)
		#expect(client.renames)

		let declaration = project.appendingPathComponent("src/Greeting.java")
		let uri = declaration.absoluteString
		client.didOpen(
			uri: uri, languageId: "java", version: 1,
			text: try String(contentsOf: declaration, encoding: .utf8)
		)

		// `Greeting` in `public class Greeting`.
		let edit = try #require(
			try await settled(within: 240) {
				try await client.rename(
					uri: uri, position: LSPPosition(line: 0, character: 13), to: "Salutation",
					timeout: 240
				)
			},
			"jdtls answered no edit"
		)

		// The move is the thing. A server that answered `changes` rather than
		// `documentChanges` could not have said it, which is what the client
		// capabilities are for.
		let moved = edit.changes.contains { change in
			guard case let .rename(from, to, _, _) = change else { return false }
			return from.hasSuffix("Greeting.java") && to.hasSuffix("Salutation.java")
		}
		#expect(moved, "jdtls did not move the file: \(edit.changes)")

		let files = WorkspaceEditFiles.disk
		let plan = WorkspaceEditPlan.make(edit, contents: files.contents, exists: files.exists)
		#expect(plan.refusals.isEmpty, "\(plan.refusals)")
		#expect(plan.moves.count == 1)

		guard case let .applied(applied) = WorkspaceEditApplier.apply(plan, to: files) else {
			Issue.record("the rename did not apply")
			return
		}

		let renamed = project.appendingPathComponent("src/Salutation.java")
		#expect(FileManager.default.fileExists(atPath: renamed.path))
		#expect(!FileManager.default.fileExists(atPath: declaration.path))
		#expect(try String(contentsOf: renamed, encoding: .utf8).contains("class Salutation"))
		#expect(try String(
			contentsOf: project.appendingPathComponent("src/Caller.java"), encoding: .utf8
		).contains("Salutation.text()"))

		// One undo, and the file is back under its old name with its old text.
		#expect(WorkspaceEditApplier.reverse(applied, in: files).isUntouched)
		#expect(FileManager.default.fileExists(atPath: declaration.path))
		#expect(!FileManager.default.fileExists(atPath: renamed.path))
		#expect(try String(contentsOf: declaration, encoding: .utf8).contains("class Greeting"))
	}

	/// The same rename with the project inside a container.
	///
	/// **The path built for this and never used.** Every URI in the question
	/// goes out as `/workspace/…` and every URI in the answer comes home — and a
	/// workspace edit is the one message in the protocol where a URI is a
	/// dictionary *key*, so this is the first thing that has ever proved that
	/// half of `ContainerPaths` against a real server rather than a fixture.
	///
	/// gopls rather than jdtls: the container leg is about the URIs, and a
	/// server that answers in seconds says the same thing about them as one that
	/// takes four minutes.
	@Test func aRenameCrossesTheContainerBoundaryInBothDirections() async throws {
		let images = ["pharndt/abydos-gopls:dev", "abydos/gopls:dev"]
		guard let (runtime, image) = availableImage(among: images) else { return }
		print("  rename: driving \(image) with \(runtime.name)")

		let root = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: root) }
		let project = URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)

		try JavaTestDirectory.write(
			"module example.com/probe\n\ngo 1.24\n",
			to: project.appendingPathComponent("go.mod")
		)
		try JavaTestDirectory.write("""
		package probe

		func Greeting() string {
			return "hello"
		}
		""", to: project.appendingPathComponent("greeting.go"))
		try JavaTestDirectory.write("""
		package probe

		func Loud() string {
			return Greeting() + "!"
		}
		""", to: project.appendingPathComponent("loud.go"))
		try JavaTestDirectory.write(
			"{\"gopls\": \"\(image)\"}\n", to: ToolImages.url(in: project)
		)

		let definition = try #require(
			LanguageServers.definition(forLanguage: "go", choosing: .none)
		)
		let resolved = try #require(LanguageServers.resolve(
			languageId: "go", project: project, image: image, runtime: runtime, choosing: .none
		))
		let paths = try #require(resolved.launch.paths)
		#expect(paths.container == "/workspace")

		let client = LSPClient()
		client.containerPaths = paths
		client.callbackQueue = .global()
		defer { client.stop() }

		let run = resolved.launch.invocation
		try client.start(
			executable: run.executable,
			arguments: run.arguments,
			workingDirectory: project,
			environment: LanguageServers.serverEnvironment
		)
		_ = try await client.initialize(
			rootURL: project,
			options: LanguageServers.initializationOptions(
				for: definition, root: project, inContainer: true
			),
			timeout: 90
		)
		#expect(client.renames)

		let declaration = project.appendingPathComponent("greeting.go")
		let uri = declaration.absoluteString
		client.didOpen(
			uri: uri, languageId: "go", version: 1,
			text: try String(contentsOf: declaration, encoding: .utf8)
		)

		let edit = try #require(
			try await settled(within: 90) {
				try await client.rename(
					uri: uri, position: LSPPosition(line: 2, character: 5), to: "Salutation"
				)
			},
			"the containerised gopls answered no edit"
		)

		// **Named as this machine names them.** A URI that had not been brought
		// home would be `file:///workspace/greeting.go`, and the plan below
		// would then refuse it as a file that could not be read — which is
		// exactly how the failure would look in the editor.
		for uri in edit.files {
			#expect(uri.hasPrefix(project.absoluteString), "\(uri) did not come home")
		}

		let files = WorkspaceEditFiles.disk
		let plan = WorkspaceEditPlan.make(edit, contents: files.contents, exists: files.exists)
		#expect(plan.refusals.isEmpty, "\(plan.refusals)")
		#expect(plan.writes.count == 2)

		guard case .applied = WorkspaceEditApplier.apply(plan, to: files) else {
			Issue.record("the rename did not apply")
			return
		}
		#expect(try String(
			contentsOf: project.appendingPathComponent("loud.go"), encoding: .utf8
		).contains("Salutation()"))
	}

	// MARK: - At the scale this has to work at

	/// A rename over a real project, at the size the item is about.
	///
	/// **Everything above is a fixture somebody wrote to be renameable.** This is
	/// `eclipse.platform.ui`'s five databinding bundles — 487 Java files nobody
	/// arranged — and `ObservableTracker`, a class used through most of them. The
	/// answer is 32 files and a file that moves, which is the shape the item is
	/// about: an edit arriving about files nobody had open, in directories nobody
	/// had looked at.
	///
	/// **It also proves the `documentChanges` rule against a real server.** jdtls
	/// answers this with *both* shapes — a `changes` map that is **empty** and a
	/// `documentChanges` list of 32 — so a client that read `changes`, as one
	/// that claimed nothing in its capabilities would be sent, applies nothing at
	/// all and reports success. Measured here, not reasoned about.
	///
	/// **On a copy, made here.** `Scripts/corpus.sh` puts the corpus beside the
	/// checkout and it is somebody's checkout: a test that renamed thirty files
	/// in it would break the corpus for every other test that uses it. An APFS
	/// clone is metadata only and is thrown away afterwards.
	///
	/// **Asked for rather than merely available**, under `SCALE=1`, which is the
	/// switch `ScaleLiveTests` already uses for corpus work and for the same
	/// reason. This one imports five Eclipse projects into a JVM, and measured
	/// here it takes the suite from 44 seconds to over two minutes and the load
	/// average past ninety — at which point timing assertions in unrelated
	/// suites start failing, which is exactly the "five people proving the red
	/// was not theirs" that `MachineLoad` was written about. Evidence worth
	/// having is not worth having at the cost of everybody else's.
	///
	///     make test SCALE=1 FILTER=jdtlsRenamesOverTheCorpus
	@Test func jdtlsRenamesOverTheCorpusAndMovesAFileInIt() async throws {
		guard ProcessInfo.processInfo.environment["SCALE"] != nil else { return }
		let corpus = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CORPUS"]
			?? NSString(string: "~/dev/abydos-corpus").expandingTildeInPath)
		let bundles = corpus.appendingPathComponent("platform/eclipse.platform.ui/bundles")
		guard FileManager.default.fileExists(atPath: bundles.path) else {
			print("  rename: no corpus at \(bundles.path) — run Scripts/corpus.sh")
			return
		}
		guard let definition = LanguageServers.known.first(where: { $0.name == "jdtls" }),
		      let executable = LanguageServers.executable(for: definition)
		else { return }

		let scratch = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: scratch) }
		let workspace = scratch.appendingPathComponent("databinding")
		try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

		// The five bundles that hold one another's databinding code. Each carries
		// its own `.project` and `.classpath`, so the directory above them is a
		// workspace jdtls imports without a build tool — which is what keeps this
		// a minute rather than the ten 0450 measured for a Maven reactor.
		let names = try FileManager.default
			.contentsOfDirectory(atPath: bundles.path)
			.filter { $0.contains("databinding") }
			.sorted()
		guard names.count >= 3 else {
			print("  rename: the corpus no longer has the databinding bundles")
			return
		}
		for name in names {
			let clone = Process()
			clone.executableURL = URL(fileURLWithPath: "/bin/cp")
			clone.arguments = [
				"-c", "-R", bundles.appendingPathComponent(name).path,
				workspace.appendingPathComponent(name).path,
			]
			try clone.run()
			clone.waitUntilExit()
		}
		let root = URL(fileURLWithPath: FilePath.canonical(workspace), isDirectory: true)
		let sources = (try? FileManager.default.subpathsOfDirectory(atPath: root.path))?
			.filter { $0.hasSuffix(".java") }.count ?? 0
		print("  rename: driving jdtls over \(names.count) bundles, \(sources) Java files")

		let declaration = root.appendingPathComponent(
			"org.eclipse.core.databinding.observable/src/org/eclipse/core/databinding/"
				+ "observable/ObservableTracker.java"
		)
		guard FileManager.default.fileExists(atPath: declaration.path) else {
			print("  rename: the corpus no longer has ObservableTracker where this expected it")
			return
		}

		LanguageServers.prepare(definition, root: root)
		let client = LSPClient()
		client.callbackQueue = .global()
		defer { client.stop() }
		try client.start(
			executable: executable,
			arguments: LanguageServers.arguments(for: definition, root: root),
			workingDirectory: root,
			environment: LanguageServers.serverEnvironment
		)
		_ = try await client.initialize(
			rootURL: root,
			options: LanguageServers.initializationOptions(
				for: definition, root: root, inContainer: false
			),
			timeout: 300
		)
		#expect(client.renames)

		let text = try String(contentsOf: declaration, encoding: .utf8)
		let uri = declaration.absoluteString
		client.didOpen(uri: uri, languageId: "java", version: 1, text: text)
		guard let position = declare(of: "ObservableTracker", in: text) else {
			Issue.record("could not find the declaration in the file")
			return
		}

		// jdtls answers nothing useful until it has imported every project, and
		// says so by answering an empty edit rather than by failing. Asked again
		// until it has something, which is what the editor does too.
		let deadline = Date().addingTimeInterval(300)
		var edit: WorkspaceEdit?
		while Date() < deadline {
			let answer = try? await settled(within: 300) {
				try await client.rename(
					uri: uri, position: position, to: "ObservableWatcher", timeout: 300
				)
			}
			if let unwrapped = answer ?? nil, !unwrapped.isEmpty {
				edit = unwrapped
				break
			}
			try? await Task.sleep(nanoseconds: 2_000_000_000)
		}
		let workspaceEdit = try #require(edit, "jdtls never answered with an edit")

		let moved = workspaceEdit.changes.contains { change in
			guard case let .rename(from, to, _, _) = change else { return false }
			return from.hasSuffix("ObservableTracker.java") && to.hasSuffix("ObservableWatcher.java")
		}
		#expect(moved, "jdtls did not move the file")
		print("  rename: \(workspaceEdit.files.count) files, and the file moved")
		// Real code, and well past the size at which doing it by hand is the
		// thing a language server exists to stop.
		#expect(workspaceEdit.files.count >= 20, "\(workspaceEdit.files.count) files")

		let files = WorkspaceEditFiles.disk
		let plan = WorkspaceEditPlan.make(
			workspaceEdit, contents: files.contents, exists: files.exists
		)
		#expect(plan.refusals.isEmpty, "\(plan.refusals.prefix(5))")
		#expect(plan.moves.count == 1)

		guard case let .applied(applied) = WorkspaceEditApplier.apply(plan, to: files) else {
			Issue.record("the rename did not apply")
			return
		}
		let renamed = declaration.deletingLastPathComponent()
			.appendingPathComponent("ObservableWatcher.java")
		#expect(FileManager.default.fileExists(atPath: renamed.path))
		#expect(!FileManager.default.fileExists(atPath: declaration.path))
		#expect(try String(contentsOf: renamed, encoding: .utf8).contains("class ObservableWatcher"))

		// One undo, over thirty files and a file that moved.
		#expect(WorkspaceEditApplier.reverse(applied, in: files).isUntouched)
		#expect(FileManager.default.fileExists(atPath: declaration.path))
		#expect(!FileManager.default.fileExists(atPath: renamed.path))
		// Every file says what it said, at the name it had. A write is recorded
		// at the name the file has *after* the moves, so the one that moved is
		// checked at where it went home to rather than where it was written —
		// which the two assertions above have already done.
		let moves = Dictionary(uniqueKeysWithValues: applied.moves.map { ($0.to, $0.from) })
		for write in applied.writes {
			let home = moves[write.url] ?? write.url
			#expect(
				(try? String(contentsOf: home, encoding: .utf8)) == write.before,
				"\(home.lastPathComponent) was not put back"
			)
		}
	}

	/// Where a name is declared in a file, as the protocol counts.
	private func declare(of name: String, in text: String) -> LSPPosition? {
		for (number, line) in text.components(separatedBy: "\n").enumerated() {
			guard line.contains("interface \(name)") || line.contains("class \(name)") else {
				continue
			}
			guard let found = (line as NSString).range(of: name, options: .backwards) as NSRange?,
			      found.location != NSNotFound
			else { continue }
			return LSPPosition(line: number, character: found.location)
		}
		return nil
	}

	// MARK: - Helpers

	/// Asks again while the server says it is still catching up — the same
	/// `ContentModified` wait `ContainerLSPLiveTests` documents.
	private func settled<Value>(
		within patience: TimeInterval, _ ask: () async throws -> Value
	) async throws -> Value {
		let deadline = Date().addingTimeInterval(patience)
		while true {
			do {
				return try await ask()
			} catch LSPClient.ClientError.failed(-32801, _) where Date() < deadline {
				try? await Task.sleep(nanoseconds: 500_000_000)
			}
		}
	}

	private func availableImage(among images: [String]) -> (runtime: ContainerRuntime, image: String)? {
		for image in images {
			for preference in [ContainerRuntime.Preference.apple, .docker] {
				guard let runtime = ContainerRuntime.discover(preference: preference),
				      holdsImage(image, in: runtime)
				else { continue }
				return (runtime, image)
			}
		}
		return nil
	}

	private func holdsImage(_ image: String, in runtime: ContainerRuntime) -> Bool {
		let process = Process()
		let command = ContainerImages.inspect(image, using: runtime)
		process.executableURL = URL(fileURLWithPath: command.executable)
		process.arguments = command.arguments
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		process.standardInput = FileHandle.nullDevice
		guard (try? process.run()) != nil else { return false }

		let deadline = Date().addingTimeInterval(5)
		while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
		guard !process.isRunning else {
			process.terminate()
			return false
		}
		return process.terminationStatus == 0
	}
}
