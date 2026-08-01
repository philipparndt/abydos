import Foundation
import Testing
@testable import IdeaiKit

/// Reading and writing .vscode/launch.json.
struct LaunchConfigurationTests {
	private func makeProject() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("launch-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	private func write(_ text: String, to root: URL) throws {
		let file = LaunchFile.url(in: root)
		try FileManager.default.createDirectory(
			at: file.deletingLastPathComponent(), withIntermediateDirectories: true
		)
		try text.write(to: file, atomically: true, encoding: .utf8)
	}

	@Test func readsWhatVSCodeWrote() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("""
		{
		  "version": "0.2.0",
		  "configurations": [
		    {
		      "name": "Run server",
		      "type": "go",
		      "request": "launch",
		      "program": "${workspaceFolder}/app",
		      "args": ["--config", "dev.yaml"],
		      "cwd": "${workspaceFolder}/app",
		      "env": { "LOG": "debug" }
		    }
		  ]
		}
		""", to: root)

		let configurations = LaunchFile.read(in: root)
		#expect(configurations.count == 1)

		let first = try #require(configurations.first)
		#expect(first.name == "Run server")
		#expect(first.type == "go")
		#expect(first.arguments == ["--config", "dev.yaml"])
		#expect(first.environment == ["LOG": "debug"])
	}

	/// The file is JSON with comments, which no JSON parser accepts.
	@Test func survivesCommentsAndTrailingCommas() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("""
		{
		  // What this project runs
		  "version": "0.2.0",
		  "configurations": [
		    {
		      "name": "Run", /* inline */
		      "type": "go",
		      "request": "launch",
		      "program": "${workspaceFolder}",
		    },
		  ]
		}
		""", to: root)

		#expect(LaunchFile.read(in: root).map(\.name) == ["Run"])
	}

	/// Editing one field must not delete keys some other tool relies on.
	@Test func carriesUnknownKeysThrough() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }
		try write("""
		{
		  "version": "0.2.0",
		  "configurations": [{
		    "name": "Run",
		    "type": "go",
		    "request": "launch",
		    "program": "${workspaceFolder}",
		    "showLog": true,
		    "buildFlags": "-tags=integration",
		    "port": 2345
		  }]
		}
		""", to: root)

		var configuration = try #require(LaunchFile.read(in: root).first)
		configuration.arguments = ["--verbose"]
		_ = try LaunchFile.save(configuration, in: root)

		let reread = try #require(LaunchFile.read(in: root).first)
		#expect(reread.arguments == ["--verbose"])
		#expect(reread.extras["showLog"] == .bool(true))
		#expect(reread.extras["buildFlags"] == .string("-tags=integration"))
		#expect(reread.extras["port"] == .number(2345))
	}

	@Test func writesAFileThatCanBeReadBack() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let configuration = LaunchConfiguration(
			name: "Serve",
			program: "${workspaceFolder}/cmd/server",
			arguments: ["-p", "8080"],
			workingDirectory: "${workspaceFolder}/cmd/server",
			environment: ["ENV": "dev"]
		)
		_ = try LaunchFile.save(configuration, in: root)

		#expect(LaunchFile.read(in: root) == [configuration])
		let text = try String(contentsOf: LaunchFile.url(in: root), encoding: .utf8)
		#expect(text.contains("\"version\" : \"0.2.0\"") || text.contains("\"version\": \"0.2.0\""))
		// Paths must not come back escaped, which is what JSON does by default.
		#expect(!text.contains("\\/"))
	}

	@Test func replacesTheOneWithTheSameName() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		_ = try LaunchFile.save(LaunchConfiguration(name: "Run", arguments: ["a"]), in: root)
		_ = try LaunchFile.save(LaunchConfiguration(name: "Run", arguments: ["b"]), in: root)
		_ = try LaunchFile.save(LaunchConfiguration(name: "Other"), in: root)

		let all = LaunchFile.read(in: root)
		#expect(all.map(\.name) == ["Run", "Other"])
		#expect(all.first?.arguments == ["b"])
	}

	@Test func removesOneByName() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		_ = try LaunchFile.save(LaunchConfiguration(name: "Run"), in: root)
		_ = try LaunchFile.save(LaunchConfiguration(name: "Other"), in: root)
		#expect(try LaunchFile.remove(named: "Run", in: root).map(\.name) == ["Other"])
	}

	// MARK: - Variables

	@Test func fillsInTheVariablesVSCodeUses() {
		let root = URL(fileURLWithPath: "/dev/project")
		let configuration = LaunchConfiguration(
			name: "Run",
			program: "${workspaceFolder}/app",
			arguments: ["--root", "${workspaceFolder}"],
			workingDirectory: "${workspaceFolder}/app",
			environment: ["HOME_COPY": "${userHome}"]
		)

		#expect(configuration.expandedProgram(root: root) == "/dev/project/app")
		#expect(configuration.expandedArguments(root: root) == ["--root", "/dev/project"])
		#expect(configuration.expandedWorkingDirectory(root: root) == "/dev/project/app")
		#expect(configuration.expandedEnvironment(root: root)["HOME_COPY"] == NSHomeDirectory())
	}

	/// The unexpanded form is what is written back, so a file stays portable.
	@Test func keepsVariablesWhenWriting() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		_ = try LaunchFile.save(
			LaunchConfiguration(name: "Run", program: "${workspaceFolder}/app"), in: root
		)
		let text = try String(contentsOf: LaunchFile.url(in: root), encoding: .utf8)
		#expect(text.contains("${workspaceFolder}/app"))
	}

	@Test func picksTheAdapterFromTheType() {
		#expect(LaunchConfiguration(name: "a", type: "go").adapterID == "delve")
		#expect(LaunchConfiguration(name: "a", type: "lldb").adapterID == "lldb")
		#expect(LaunchConfiguration(name: "a", type: "cppdbg").adapterID == "lldb")
	}

	// MARK: - Starting from nothing

	/// Pressing play in a project with no file should run the obvious thing and
	/// leave a record of what it did.
	@Test func suggestsSomethingForAGoProject() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }
		try "module x\n".write(
			to: root.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8
		)

		let suggested = try #require(LaunchFile.suggestion(for: root))
		#expect(suggested.type == "go")
		#expect(suggested.program == "${workspaceFolder}")
		#expect(suggested.name == root.lastPathComponent)
	}

	@Test func pointsAtTheModuleWhenItIsNotAtTheRoot() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }
		let app = root.appendingPathComponent("app")
		try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
		try "module x\n".write(to: app.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)

		let suggested = try #require(LaunchFile.suggestion(for: root))
		#expect(suggested.program == "${workspaceFolder}/app")
	}

	@Test func suggestsNothingForAProjectItDoesNotUnderstand() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(LaunchFile.suggestion(for: root) == nil)
	}

	@Test func readsNothingFromAProjectWithNoFile() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(LaunchFile.read(in: root).isEmpty)
	}
}

/// What a configuration's environment and directory turn into on the wire.
struct LaunchRequestTests {
	/// Delve takes an object; lldb-dap takes lines. Sending either the wrong
	/// one is rejected, so the shape matters more than the content.
	@Test func delveTakesTheEnvironmentAsAnObject() {
		let request = DebugAdapters.launchArguments(
			for: DebugAdapters.delve,
			program: "/tmp/pkg",
			workingDirectory: "/tmp/pkg",
			environment: ["LOG": "debug"]
		)
		#expect(request["env"] as? [String: String] == ["LOG": "debug"])
		#expect(request["mode"] as? String == "debug")
	}

	@Test func lldbTakesTheEnvironmentAsLines() {
		let request = DebugAdapters.launchArguments(
			for: DebugAdapters.lldb,
			program: "/tmp/a.out",
			workingDirectory: "/tmp",
			environment: ["B": "2", "A": "1"]
		)
		// Sorted, so two runs of the same configuration send the same request.
		#expect(request["env"] as? [String] == ["A=1", "B=2"])
	}

	/// An empty environment must not appear at all: some adapters treat an
	/// empty `env` as "run with nothing set" rather than "inherit".
	@Test func omitsAnEmptyEnvironment() {
		let request = DebugAdapters.launchArguments(
			for: DebugAdapters.delve, program: "/tmp/pkg", workingDirectory: "/tmp/pkg"
		)
		#expect(request["env"] == nil)
	}
}

/// Expansion, where the paths are the whole point.
struct LaunchExpansionTests {
	/// A project opened through a symlinked path must still expand to the path
	/// the tools themselves see, or `go run` reports the package as being
	/// outside the module it is sitting in.
	@Test func expandsToTheRealPath() throws {
		let base = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("expand-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: base) }

		let real = base.appendingPathComponent("real")
		try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
		let link = base.appendingPathComponent("link")
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

		let expanded = LaunchConfiguration.expand("${workspaceFolder}/cmd", root: link)
		#expect(expanded == FilePath.canonical(real) + "/cmd")
	}

	@Test func expandsEverythingAConfigurationCarries() {
		let root = URL(fileURLWithPath: "/usr")
		let configuration = LaunchConfiguration(
			name: "app",
			program: "${workspaceFolder}/cmd/app",
			arguments: ["--config", "${workspaceFolder}/dev.yaml"],
			workingDirectory: "${workspaceFolder}",
			environment: ["DATA": "${workspaceFolder}/data"]
		)
		#expect(configuration.expandedArguments(root: root) == ["--config", "/usr/dev.yaml"])
		#expect(configuration.expandedEnvironment(root: root) == ["DATA": "/usr/data"])
		#expect(configuration.expandedProgram(root: root) == "/usr/cmd/app")
	}
}
