import Foundation
import Testing
@testable import AbydosKit

/// The devcontainers in the examples repository, read by the reader they were
/// written against.
///
/// 0424 says the examples are the fixtures, and a fixture nothing asserts about
/// drifts: an example meant to demonstrate `forwardPorts` that quietly stopped
/// being read, or one meant to be refused that started being accepted, are both
/// silent until somebody opens them. This is the cheap half of not letting that
/// happen — the file, read, and what it is for. The container coming up is
/// `devcontainers/check.sh` in that repository, which needs docker.
///
/// Skipped when the examples repository is not beside this one, the way the
/// live tests skip without their runtime. It is a separate repository and a
/// checkout of this one does not imply a checkout of that one.
struct ExampleDevContainerTests {
	/// `../abydos-examples`, from this file rather than from the working
	/// directory, which a test runner is entitled to choose for itself.
	private static var examples: URL? {
		let source = URL(fileURLWithPath: #filePath)
		let repository = source
			.deletingLastPathComponent() // AbydosKitTests
			.deletingLastPathComponent() // Tests
			.deletingLastPathComponent() // the checkout
		// A worktree lives under .claude/worktrees/<name>, so the sibling is
		// three more levels up. Whichever of the two exists is the answer.
		let candidates = [
			repository.deletingLastPathComponent(),
			repository
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.deletingLastPathComponent()
				.deletingLastPathComponent(),
		]
		for beside in candidates {
			let url = beside.appendingPathComponent("abydos-examples")
			var isDirectory: ObjCBool = false
			if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
			   isDirectory.boolValue,
			   FileManager.default.fileExists(atPath: url.appendingPathComponent("devcontainers").path)
			{
				return URL(fileURLWithPath: FilePath.canonical(url), isDirectory: true)
			}
		}
		return nil
	}

	/// The configuration, or the refusal reported as the failure it would be.
	///
	/// An example that stopped being understood has to say *what it said*: "the
	/// configuration was nil" sends somebody back to the file to find out why,
	/// and the sentence they need is the one the reader already wrote.
	private func understood(_ reading: DevContainerFile.Reading) -> DevContainerConfiguration? {
		if let configuration = reading.configuration { return configuration }
		Issue.record("refused: \(reading.refusal ?? "for no stated reason")")
		return nil
	}

	private func read(_ project: String) -> DevContainerFile.Reading? {
		guard let examples = Self.examples else { return nil }
		return DevContainerFile.read(
			project: examples.appendingPathComponent(project),
			environment: ["HOME": "/Users/somebody"]
		)
	}

	// MARK: - The ones that come up

	/// The plainest thing that works, which is the one that proves the path end
	/// to end: an image, and nothing else to go wrong.
	@Test func goServiceNamesOneImageAndNothingElse() throws {
		guard let reading = read("go-service") else { return }
		guard let configuration = understood(reading) else { return }
		#expect(configuration.name == "go-service")
		#expect(configuration.image == "golang:1.24-alpine")
		#expect(configuration.build == nil)
		#expect(configuration.paths.container == "/workspaces/go-service")
		#expect(configuration.workspaceFolder == "/workspaces/go-service")
	}

	/// Ports on a project that has something worth reaching on one, and the two
	/// environments that are not the same environment.
	@Test func smartHomeForwardsThePortsItListensOn() throws {
		guard let reading = read("smart-home-microservice") else { return }
		guard let configuration = understood(reading) else { return }
		#expect(configuration.forwardPorts == [8080, 6060])
		#expect(configuration.containerEnv["STAGE"] == "container")
		#expect(configuration.remoteEnv["SMART_HOME_CONFIG"] == "config/dev.json")
		// The distinction is the point: one is baked in at run, the other added
		// at exec, and a file that set both to the same thing would prove
		// nothing about which was which.
		#expect(configuration.containerEnv["SMART_HOME_CONFIG"] == nil)
	}

	/// A Dockerfile instead of an image, with every relative path in it
	/// resolved against the *file* rather than against the project.
	@Test func dockerfileBuildResolvesItsPathsAgainstTheFile() throws {
		guard let examples = Self.examples else { return }
		let project = examples.appendingPathComponent("devcontainers/dockerfile-build")
		guard let reading = read("devcontainers/dockerfile-build") else { return }
		guard let configuration = understood(reading) else { return }
		guard let build = configuration.build else { Issue.record("dockerfile-build names no build"); return }
		let root = FilePath.canonical(project)

		#expect(configuration.image == nil)
		#expect(build.dockerfile == root + "/.devcontainer/Dockerfile")
		// `context: ".."` from inside .devcontainer is the project itself,
		// which is the only way COPY can see tools/hello.sh.
		#expect(build.context == root)
		#expect(build.args == ["ALPINE": "3.21", "EXTRA": "jq"])
		#expect(build.target == "development")
		#expect(configuration.builtImageName == "abydos-devcontainer:dockerfile-build")
	}

	/// The two user fields, which are handed to two different commands.
	@Test func nonRootUserSeparatesTheContainerFromTheShell() throws {
		guard let reading = read("devcontainers/non-root-user") else { return }
		guard let configuration = understood(reading) else { return }
		#expect(configuration.containerUser == "root")
		#expect(configuration.remoteUser == "vscode")

		let start = DevContainers.startCommand(
			configuration, name: "abydos-devcontainer-1-1", using: .docker("/usr/bin/docker")
		)
		#expect(start.arguments.contains("-u"))
		#expect(start.arguments.contains("root"))

		let session = DevContainers.Session(
			name: "abydos-devcontainer-1-1",
			configuration: configuration,
			runtime: .docker("/usr/bin/docker")
		)
		let exec = DevContainers.execCommand(session, arguments: ["whoami"])
		#expect(exec.arguments.contains("vscode"))
		#expect(!exec.arguments.contains("root"))
	}

	/// Every `${…}` the reader answers, and the three fields it hands straight
	/// to the runtime.
	@Test func substitutionsResolveEverythingThisSideCanAnswer() throws {
		guard let examples = Self.examples else { return }
		let project = examples.appendingPathComponent("devcontainers/substitutions")
		guard let reading = read("devcontainers/substitutions") else { return }
		guard let configuration = understood(reading) else { return }
		let root = FilePath.canonical(project)

		#expect(configuration.name == "Substitutions in substitutions")
		// workspaceMount put the checkout somewhere other than /workspaces/<name>.
		#expect(configuration.paths.host == root)
		#expect(configuration.paths.container == "/src")
		#expect(configuration.workspaceFolder == "/src")

		#expect(configuration.containerEnv["ABYDOS_HOST_PROJECT"] == root)
		#expect(configuration.containerEnv["ABYDOS_PROJECT"] == "substitutions")
		#expect(configuration.containerEnv["ABYDOS_INSIDE"] == "/src")
		#expect(configuration.containerEnv["ABYDOS_HOME"] == "/Users/somebody")
		// The variable is not set in the environment handed in above, so the
		// fallback is what a machine without it gets.
		#expect(configuration.containerEnv["ABYDOS_TOKEN"] == "no token on this machine")
		// Left exactly as written, which is the only answer that cannot corrupt
		// a value nobody understood.
		#expect(configuration.containerEnv["ABYDOS_UNKNOWN"] == "${somethingNobodyDefined}")
		#expect(configuration.remoteEnv["ABYDOS_SHELL_SAW"] == "src")

		#expect(configuration.extraMounts == ["target=/scratch,type=tmpfs"])
		#expect(configuration.runArgs == ["--hostname", "abydos-substitutions"])
	}

	/// The example that exists to be slow on purpose, now that the lifecycle
	/// commands run rather than refuse.
	@Test func postCreateIsReadAsTheOneCommandItNames() throws {
		guard let reading = read("devcontainers/post-create") else { return }
		guard let configuration = understood(reading) else { return }
		let lifecycle = configuration.lifecycle
		#expect(lifecycle[.postCreateCommand] == .shell("sh .devcontainer/post-create.sh"))
		// And nothing else, because the fixture is about one moment: a file that
		// grew a second command would be a different test.
		#expect(lifecycle.stages == [.postCreateCommand])
		#expect(lifecycle.hasCreationCommands)
	}

	/// Its harder half: a command that fails, and one after it that must not run
	/// when it does.
	@Test func postCreateFailsAlsoNamesTheCommandThatMustNotRun() throws {
		guard let reading = read("devcontainers/post-create-fails") else { return }
		guard let configuration = understood(reading) else { return }
		let lifecycle = configuration.lifecycle
		#expect(lifecycle[.postCreateCommand] == .shell("sh .devcontainer/post-create.sh"))
		#expect(lifecycle[.postStartCommand] != nil)
		// The order is the promise: postStartCommand is after the three that
		// create the container, so a failure in one of those never reaches it.
		#expect(lifecycle.stages == [.postCreateCommand, .postStartCommand])
	}

	/// Two devcontainers in one project, which was refused whole until there was
	/// a menu to ask in.
	///
	/// What has to be right is the *names*: they share a project, a checkout and
	/// a mount, so if they cannot name themselves apart the menu offering them
	/// says less than the refusal it replaced.
	@Test func twoContainersAreBothOfferedAndNameThemselvesApart() throws {
		guard let examples = Self.examples else { return }
		let project = examples.appendingPathComponent("devcontainers/two-containers")
		let choices = DevContainerFile.choices(in: project)
		#expect(choices.map(\.name) == ["Small", "With a Go toolchain"])
		#expect(choices.map { $0.file.deletingLastPathComponent().lastPathComponent }
			== ["alpine", "go"])
		// And each is read as itself rather than as the other, which is the whole
		// of what the menu entries have to be able to do.
		let images = choices.map { DevContainerFile.read($0.file, project: project)
			.configuration?.image
		}
		#expect(images == ["alpine:3.21", "golang:1.24-alpine"])
		// The caller with nowhere to ask — a language server — gets the first.
		#expect(read("devcontainers/two-containers")?.configuration?.image == "alpine:3.21")
	}

	// MARK: - The ones that are refused

	/// Each of these is a file `devcontainer up` builds without complaint, kept
	/// so that the refusal is a thing somebody can watch happen. The sentence is
	/// asserted rather than merely the fact of refusing, because "it said no" is
	/// not the promise — "it said what it found, by name" is.
	@Test(arguments: [
		(
			"multi-tier",
			"builds this project with Docker Compose (docker-compose.yml), which this app does not run"
		),
		(
			"devcontainers/features",
			"installs devcontainer features (ghcr.io/devcontainers/features/github-cli:1), "
				+ "which this app does not build"
		),
	])
	func refusesTheExamplesThatAreThereToBeRefused(project: String, saying: String) throws {
		guard let reading = read(project) else { return }
		guard let refusal = reading.refusal else {
			Issue.record("\(project) was understood, and is there to be refused")
			return
		}
		#expect(refusal.contains(saying), "\(project) said: \(refusal)")
	}

	/// Every devcontainer in the repository is one of the two, and there is no
	/// third answer — an example that is neither is an example nobody looked at.
	@Test func everyExampleIsEitherUnderstoodOrRefusedByName() throws {
		guard let examples = Self.examples else { return }
		let understood = [
			"go-service", "smart-home-microservice",
			"devcontainers/dockerfile-build", "devcontainers/non-root-user",
			"devcontainers/substitutions",
			// Both of these were refused until the lifecycle commands ran. They
			// are the same two files; what changed is this side.
			"devcontainers/post-create", "devcontainers/post-create-fails",
			// And this one was refused until there was a menu to ask which of its
			// two containers somebody meant. Same two files; this side changed.
			"devcontainers/two-containers",
		]
		let refused = ["multi-tier", "devcontainers/features"]
		for project in understood + refused {
			let url = examples.appendingPathComponent(project)
			#expect(DevContainerFile.exists(in: url), "\(project) has no devcontainer.json")
		}
		for project in understood {
			#expect(read(project)?.configuration != nil, "\(project) is no longer understood")
		}
		for project in refused {
			#expect(read(project)?.refusal != nil, "\(project) is no longer refused")
		}
	}
}
