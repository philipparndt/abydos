import Foundation
import Testing
@testable import AbydosKit

/// The warnings a launch configuration earns before it is run. Each case here
/// is a failure that happened, and each was expensive precisely because none of
/// them fails in a way that points at the configuration.
struct LaunchConfigurationCheckTests {
	/// A project shaped like the one these were found in: the module in `app`,
	/// the configuration beside the project.
	static func project() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("check-\(UUID().uuidString)")
		let app = root.appendingPathComponent("app")
		let config = root.appendingPathComponent("production/config")
		try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
		try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
		try "module app\n".write(to: app.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
		try "{}".write(to: config.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
		return root
	}

	/// The one that cost a morning: LLDB pointed at a Go package starts
	/// nothing and says nothing, so the debugger appears broken.
	@Test func noticesLLDBOnAGoPackage() throws {
		let root = try Self.project()
		defer { try? FileManager.default.removeItem(at: root) }

		let configuration = LaunchConfiguration(
			name: "mqtt", type: "lldb", program: "${workspaceFolder}/app"
		)
		let problems = LaunchConfigurationCheck.problems(for: configuration, root: root)
		#expect(problems.contains { $0.field == "type" && $0.message.contains("LLDB") })

		// The same configuration with the right debugger is quiet.
		var fixed = configuration
		fixed.type = "go"
		#expect(LaunchConfigurationCheck.problems(for: fixed, root: root).isEmpty)
	}

	/// The second one: an argument naming a file that is not there is passed
	/// through as written, and the program complains about its own
	/// configuration rather than about this one.
	@Test func noticesAnArgumentThatNamesNothing() throws {
		let root = try Self.project()
		defer { try? FileManager.default.removeItem(at: root) }

		let configuration = LaunchConfiguration(
			name: "mqtt", program: "${workspaceFolder}/app",
			arguments: ["${workspaceFolder}/config.json"]
		)
		let problems = LaunchConfigurationCheck.problems(for: configuration, root: root)
		#expect(problems.contains { $0.field == "arguments" && $0.message.contains("config.json") })

		// And is quiet about the path that is actually there.
		var right = configuration
		right.arguments = ["${workspaceFolder}/production/config/config.json"]
		#expect(LaunchConfigurationCheck.problems(for: right, root: root).isEmpty)
	}

	/// Flags, numbers and words are not paths, and warning about them would
	/// teach people to ignore the warnings.
	@Test func leavesOrdinaryArgumentsAlone() throws {
		let root = try Self.project()
		defer { try? FileManager.default.removeItem(at: root) }

		let configuration = LaunchConfiguration(
			name: "mqtt", program: "${workspaceFolder}/app",
			arguments: ["--verbose", "8080", "serve", "-c", "/etc/elsewhere.json"]
		)
		#expect(LaunchConfigurationCheck.problems(for: configuration, root: root).isEmpty)
	}

	/// The third: a file listed to send that is not there is skipped without a
	/// word, and the pod starts without the configuration it was promised.
	@Test func noticesAFileThatCannotBeSent() throws {
		let root = try Self.project()
		defer { try? FileManager.default.removeItem(at: root) }

		var configuration = LaunchConfiguration(name: "cluster", program: "${workspaceFolder}/app")
		configuration.extras["abydos.devPod"] = .object([
			"files": .array([.string("production/config/missing.json")]),
		])
		let problems = LaunchConfigurationCheck.problems(for: configuration, root: root)
		#expect(problems.contains { $0.field == "files" })

		// Relative to the project, which is how this app writes them.
		configuration.extras["abydos.devPod"] = .object([
			"files": .array([.string("production/config/config.json")]),
		])
		#expect(LaunchConfigurationCheck.problems(for: configuration, root: root).isEmpty)
	}

	@Test func noticesAProgramAndDirectoryThatAreNotThere() throws {
		let root = try Self.project()
		defer { try? FileManager.default.removeItem(at: root) }

		let configuration = LaunchConfiguration(
			name: "gone", program: "${workspaceFolder}/nowhere",
			workingDirectory: "${workspaceFolder}/nor-here"
		)
		let problems = LaunchConfigurationCheck.problems(for: configuration, root: root)
		#expect(problems.contains { $0.field == "program" })
		#expect(problems.contains { $0.field == "cwd" })
	}
}

/// Turning a chosen path back into something a shared configuration can hold.
struct TemplatePathTests {
	@Test func writesAProjectPathAsTheVariable() {
		let root = URL(fileURLWithPath: "/Users/somebody/dev/thing")
		#expect(TemplatePath.shareable("/Users/somebody/dev/thing/app", root: root)
			== "${workspaceFolder}/app")
		#expect(TemplatePath.shareable("/Users/somebody/dev/thing", root: root) == "${workspaceFolder}")
	}

	/// A tool on this machine is still better written with the home variable
	/// than with whose machine it is.
	@Test func writesAHomePathAsTheHomeVariable() {
		let root = URL(fileURLWithPath: "/opt/project")
		let inHome = NSHomeDirectory() + "/go/bin/dlv"
		#expect(TemplatePath.shareable(inHome, root: root) == "${userHome}/go/bin/dlv")
	}

	@Test func leavesAPathThatIsNeitherAlone() {
		#expect(TemplatePath.shareable("/usr/local/bin/thing", root: URL(fileURLWithPath: "/opt/project"))
			== "/usr/local/bin/thing")
	}

	/// The chooser opens where the field already points, so picking a
	/// neighbouring file is one click rather than a walk from the project root.
	@Test func opensBesideWhatTheFieldAlreadyNames() throws {
		let root = try LaunchConfigurationCheckTests.project()
		defer { try? FileManager.default.removeItem(at: root) }

		let beside = TemplatePath.startingDirectory(
			for: "${workspaceFolder}/production/config/config.json", root: root
		)
		#expect(beside.lastPathComponent == "config")

		// A directory opens as itself, and an empty field at the project.
		#expect(TemplatePath.startingDirectory(for: "${workspaceFolder}/app", root: root)
			.lastPathComponent == "app")
		#expect(FilePath.canonical(TemplatePath.startingDirectory(for: "", root: root))
			== FilePath.canonical(root))
	}
}
