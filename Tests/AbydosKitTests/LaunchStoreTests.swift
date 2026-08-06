import Foundation
import Testing
@testable import AbydosKit

/// Where a project's launch configurations live.
struct LaunchStoreTests {
	private func project() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("store-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	@Test func writesOneFilePerConfiguration() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		_ = try LaunchStore.save(LaunchConfiguration(name: "run the api"), in: root)
		_ = try LaunchStore.save(LaunchConfiguration(name: "run the worker"), in: root)

		let files = try FileManager.default.contentsOfDirectory(
			atPath: AbydosFolder.runDirectory(in: root).path
		).sorted()
		#expect(files == ["run-the-api.json", "run-the-worker.json"])
		#expect(LaunchStore.read(in: root).map(\.name) == ["run the api", "run the worker"])
	}

	/// Renaming is a remove and a save, which is what the editor does; what
	/// must not happen is the old file surviving it.
	@Test func renamingLeavesOneFile() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		var configuration = LaunchConfiguration(name: "old name")
		_ = try LaunchStore.save(configuration, in: root)
		_ = try LaunchStore.remove(named: "old name", in: root)
		configuration.name = "new name"
		_ = try LaunchStore.save(configuration, in: root)

		#expect(LaunchStore.read(in: root).map(\.name) == ["new name"])
		#expect(try FileManager.default.contentsOfDirectory(
			atPath: AbydosFolder.runDirectory(in: root).path
		) == ["new-name.json"])
	}

	/// The same name under two file names — a copied file, a slug that
	/// changed — shows up once, not twice.
	@Test func keepsOneFilePerName() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		_ = try LaunchStore.save(LaunchConfiguration(name: "app"), in: root)
		let copy = AbydosFolder.runDirectory(in: root).appendingPathComponent("copy.json")
		try FileManager.default.copyItem(at: LaunchStore.fileURL(for: "app", in: root), to: copy)
		#expect(LaunchStore.read(in: root).count == 2)

		_ = try LaunchStore.save(LaunchConfiguration(name: "app", arguments: ["-x"]), in: root)
		#expect(LaunchStore.read(in: root).map(\.name) == ["app"])
	}

	@Test func removesOne() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		_ = try LaunchStore.save(LaunchConfiguration(name: "keep"), in: root)
		_ = try LaunchStore.save(LaunchConfiguration(name: "drop"), in: root)
		#expect(try LaunchStore.remove(named: "drop", in: root).map(\.name) == ["keep"])
	}

	/// Everything a configuration carries survives the round trip, including
	/// the keys only this app understands.
	@Test func keepsWhatAConfigurationSays() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		var configuration = LaunchConfiguration(
			name: "in the cluster",
			program: "${workspaceFolder}/app",
			arguments: ["--config", "dev.json"],
			workingDirectory: "${workspaceFolder}/app",
			environment: ["LOG": "debug"]
		)
		configuration.devPod = LaunchConfiguration.DevPodSettings(
			context: "k3c-demo1", namespace: "devpod", kubeconfig: "~/.kube/other"
		)
		_ = try LaunchStore.save(configuration, in: root)

		let read = try #require(LaunchStore.read(in: root).first)
		#expect(read == configuration)
		#expect(read.devPod?.kubeconfig == "~/.kube/other")
	}

	/// A project with a VS Code file gets its configurations, once, without
	/// that file being written to.
	@Test func importsVSCodeConfigurations() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		try LaunchFile.write([
			LaunchConfiguration(name: "from vscode", program: "./cmd/app"),
		], in: root)

		let imported = try LaunchStore.importVSCode(in: root)
		#expect(imported.map(\.name) == ["from vscode"])
		#expect(LaunchStore.readOwn(in: root).map(\.name) == ["from vscode"])

		// Twice changes nothing: it is already here.
		#expect(try LaunchStore.importVSCode(in: root).isEmpty)
	}

	/// One this app has been edited in wins over the imported one of the same
	/// name — it is the newer of the two.
	@Test func doesNotOverwriteWhatIsAlreadyHere() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		_ = try LaunchStore.save(
			LaunchConfiguration(name: "app", arguments: ["--ours"]), in: root
		)
		try LaunchFile.write([LaunchConfiguration(name: "app", arguments: ["--theirs"])], in: root)

		#expect(try LaunchStore.importVSCode(in: root).isEmpty)
		#expect(LaunchStore.read(in: root).first?.arguments == ["--ours"])
		#expect(LaunchStore.read(in: root).count == 1)
	}

	/// A VS Code file that has not been imported is still offered, so a
	/// project cloned this morning runs without a migration step.
	@Test func readsAVSCodeFileThatWasNeverImported() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		try LaunchFile.write([LaunchConfiguration(name: "theirs")], in: root)
		#expect(LaunchStore.read(in: root).map(\.name) == ["theirs"])
		#expect(LaunchStore.readOwn(in: root).isEmpty)
	}

	@Test func makesFileNamesOutOfConfigurationNames() {
		#expect(LaunchStore.slug("make dev") == "make-dev")
		#expect(LaunchStore.slug("Run: the API (dev)") == "run-the-api-dev")
		#expect(LaunchStore.slug("///") == "configuration")
	}
}

/// The folder itself.
struct AbydosFolderTests {
	@Test func commitsTheRunConfigurationsAndNothingElse() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("folder-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		_ = try AbydosFolder.create(in: root)
		let ignore = try String(
			contentsOf: AbydosFolder.url(in: root).appendingPathComponent(".gitignore"),
			encoding: .utf8
		)
		#expect(ignore.contains("*"))
		#expect(ignore.contains("!run/"))
		#expect(ignore.contains("!run/**"))

		// The rule is only worth anything if git agrees with it.
		_ = GitRepository.runSync(["init", "-q", "."], in: root)
		try "{}".write(
			to: LaunchStore.fileURL(for: "keep me", in: root), atomically: true, encoding: .utf8
		)
		try SessionStore.write(
			ProjectSession(files: [.init(path: "/x/main.go")], activePath: "/x/main.go"), in: root
		)

		let listed = GitRepository.runSync(
			["status", "--porcelain", "--untracked-files=all"], in: root
		).stdout
		#expect(listed.contains(".abydos/run/keep-me.json"))
		#expect(!listed.contains("session.json"))
	}

	/// Somebody who edits the rule has a reason.
	@Test func leavesAnEditedGitignoreAlone() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("folder-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		_ = try AbydosFolder.create(in: root)
		let ignore = AbydosFolder.url(in: root).appendingPathComponent(".gitignore")
		try "# mine\n".write(to: ignore, atomically: true, encoding: .utf8)

		_ = try AbydosFolder.create(in: root)
		#expect(try String(contentsOf: ignore, encoding: .utf8) == "# mine\n")
	}
}

/// What was open in a project, kept beside it.
struct SessionStoreTests {
	private func project() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("session-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	@Test func remembersWhatWasOpen() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		let session = ProjectSession(
			files: [
				.init(path: "/p/main.go", line: 42),
				.init(path: "/p/notes.md", line: 1, isPreview: true),
			],
			activePath: "/p/main.go"
		)
		try SessionStore.write(session, in: root)

		let read = try #require(SessionStore.read(in: root))
		#expect(read.files.map(\.path) == ["/p/main.go", "/p/notes.md"])
		#expect(read.files.first?.line == 42)
		#expect(read.files.last?.isPreview == true)
		#expect(read.activePath == "/p/main.go")
	}

	/// Closing everything is a state worth keeping: reopening the project
	/// should not bring back what was deliberately closed.
	@Test func forgetsWhenNothingIsOpen() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(ProjectSession(files: [.init(path: "/p/a.go")]), in: root)
		try SessionStore.write(ProjectSession(), in: root)
		#expect(SessionStore.read(in: root) == nil)
	}

	@Test func hasNothingToSayAboutAProjectItHasNotSeen() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(SessionStore.read(in: root) == nil)
	}
}

/// Naming a copy.
struct LaunchNameTests {
	@Test func addsCopyToTheName() {
		#expect(LaunchNames.copy(of: "run the api", avoiding: []) == "run the api copy")
	}

	/// Copying twice must not produce two configurations with one name — the
	/// menu finds one by name, and saving would replace the other.
	@Test func numbersFurtherCopies() {
		let taken = ["app", "app copy"]
		#expect(LaunchNames.copy(of: "app", avoiding: taken) == "app copy 2")
		#expect(LaunchNames.copy(of: "app", avoiding: taken + ["app copy 2"]) == "app copy 3")
	}

	@Test func leavesAFreeNameAlone() {
		#expect(LaunchNames.free(like: "go run app", avoiding: ["something else"]) == "go run app")
		#expect(LaunchNames.free(like: "go run app", avoiding: ["go run app"]) == "go run app 2")
	}
}

/// Which runs are worth saving as a configuration.
struct TestConfigurationTests {
	private func configuration(name: String, executable: String, arguments: [String]) -> RunConfiguration {
		RunConfiguration(
			name: name,
			source: .goModule,
			executable: executable,
			arguments: arguments,
			workingDirectory: "/p",
			environment: [:]
		)
	}

	/// A test is run, not configured: one saved configuration per test
	/// function would leave a project with hundreds of them.
	@Test func recognisesATestRun() {
		#expect(RunConfigurationDiscovery.isTest(
			configuration(name: "go test", executable: "go", arguments: ["test", "./..."])
		))
		#expect(RunConfigurationDiscovery.isTest(
			configuration(name: "TestGreet", executable: "go", arguments: ["test", "-run", "TestGreet"])
		))
		#expect(RunConfigurationDiscovery.isTest(
			configuration(name: "unit test", executable: "make", arguments: ["test"])
		))
	}

	@Test func leavesAnOrdinaryRunAlone() {
		#expect(!RunConfigurationDiscovery.isTest(
			configuration(name: "go run app", executable: "go", arguments: ["run", "."])
		))
		#expect(!RunConfigurationDiscovery.isTest(
			configuration(name: "make dev", executable: "make", arguments: ["dev"])
		))
	}
}

/// Terminals are part of where somebody left off.
struct SessionTerminalTests {
	private func project() throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("session-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	@Test func terminalsSurviveBeingWrittenDown() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		let session = ProjectSession(
			files: [ProjectSession.OpenFile(path: root.appendingPathComponent("a.go").path)],
			terminals: [
				ProjectSession.OpenTerminal(name: "build box", directory: root.path, isRenamed: true),
				ProjectSession.OpenTerminal(name: "Local"),
			],
			isPanelVisible: true
		)
		try SessionStore.write(session, in: root)

		let read = try #require(SessionStore.read(in: root))
		#expect(read.terminals == session.terminals)
		#expect(read.isPanelVisible)
	}

	/// A window with terminals and no files open still has something to
	/// remember — writing nothing would lose them.
	@Test func aSessionOfNothingButTerminalsIsStillASession() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(
			ProjectSession(terminals: [ProjectSession.OpenTerminal(name: "Local")]), in: root
		)
		let read = try #require(SessionStore.read(in: root))
		#expect(read.files.isEmpty)
		#expect(read.terminals.count == 1)
	}

	/// A name the shell chose is not a name somebody typed, and only the second
	/// one has to survive the shell changing its mind.
	@Test func onlyARenamedTerminalSaysSo() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(
			ProjectSession(terminals: [ProjectSession.OpenTerminal(name: "vim")]), in: root
		)
		let read = try #require(SessionStore.read(in: root))
		#expect(read.terminals.first?.isRenamed == false)
	}

	@Test func anEmptySessionRemovesTheFile() throws {
		let root = try project()
		defer { try? FileManager.default.removeItem(at: root) }

		try SessionStore.write(
			ProjectSession(terminals: [ProjectSession.OpenTerminal(name: "Local")]), in: root
		)
		try SessionStore.write(ProjectSession(), in: root)
		#expect(SessionStore.read(in: root) == nil)
	}
}
