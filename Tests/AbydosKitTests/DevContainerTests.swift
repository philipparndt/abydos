import Foundation
import Testing
@testable import AbydosKit

/// The commands that start a project's devcontainer and run things inside it.
///
/// Every one of these is a string comparison against a command line, which is
/// the part worth pinning: a flag in the wrong place is a container that comes
/// up mounted somewhere else, and that shows up as an editor whose files are
/// missing rather than as a wrong argument.
struct DevContainerTests {
	private let docker = ContainerRuntime.docker("/usr/bin/docker")

	private func read(
		_ json: String, project: String = "/Users/me/service"
	) throws -> DevContainerConfiguration {
		let reading = DevContainerFile.parse(
			Data(json.utf8), project: URL(fileURLWithPath: project), environment: [:]
		)
		return try #require(reading.configuration, "\(reading.refusal ?? "")")
	}

	private func session(_ configuration: DevContainerConfiguration) -> DevContainers.Session {
		DevContainers.Session(
			name: "abydos-devcontainer-4242-1", configuration: configuration, runtime: docker
		)
	}

	// MARK: - Starting it

	@Test func startsTheContainerWithTheProjectMountedWhereTheFileSays() throws {
		let configuration = try read("""
		{
			"image": "mcr.microsoft.com/devcontainers/go:1.24",
			"containerUser": "root",
			"containerEnv": {"CGO_ENABLED": "0"},
			"forwardPorts": [8080],
			"runArgs": ["--cap-add=SYS_PTRACE"]
		}
		""")
		let start = DevContainers.startCommand(
			configuration, name: "abydos-devcontainer-4242-1", using: docker
		)
		#expect(start.executable == "/usr/bin/docker")
		#expect(start.arguments == [
			"run", "-d", "--name", "abydos-devcontainer-4242-1",
			"--entrypoint", "/bin/sh",
			"-v", "/Users/me/service:/workspaces/service",
			"-w", "/workspaces/service",
			"-u", "root",
			"-e", "CGO_ENABLED=0",
			// The loopback address only: a devcontainer's port is for the person
			// at this keyboard, and every interface is a decision nobody made.
			"-p", "127.0.0.1:8080:8080",
			"--cap-add=SYS_PTRACE",
			"mcr.microsoft.com/devcontainers/go:1.24",
			"-c", DevContainers.keepAlive,
		])
	}

	/// Detached and kept, so switching away from the project and back does not
	/// start it again — and the image's own command replaced, because an image
	/// built to run a program exits and leaves nothing to open a terminal in.
	@Test func keepsTheContainerUpInsteadOfLettingItFinish() throws {
		let configuration = try read(#"{"image": "alpine:3.20"}"#)
		let start = DevContainers.startCommand(configuration, name: "abydos-x", using: docker)
		#expect(start.arguments.contains("-d"))
		#expect(!start.arguments.contains("--rm"))
		#expect(DevContainers.keepAlive.contains("trap"))
		#expect(start.arguments.last == DevContainers.keepAlive)
	}

	@Test func buildsTheImageWhenTheFileNamesADockerfile() throws {
		let configuration = try read("""
		{
			"build": {
				"dockerfile": "Dockerfile",
				"context": "..",
				"args": {"GO_VERSION": "1.24"},
				"target": "development"
			}
		}
		""")
		let build = try #require(DevContainers.buildCommand(configuration, using: docker))
		#expect(build.arguments == [
			"build", "-t", "abydos-devcontainer:service",
			"-f", "/Users/me/service/.devcontainer/Dockerfile",
			"--build-arg", "GO_VERSION=1.24",
			"--target", "development",
			"/Users/me/service",
		])
		// And the container is then started from what was just built.
		let start = DevContainers.startCommand(configuration, name: "abydos-x", using: docker)
		#expect(start.arguments.contains("abydos-devcontainer:service"))

		// Nothing to build when the file names an image.
		let pulled = try read(#"{"image": "alpine:3.20"}"#)
		#expect(DevContainers.buildCommand(pulled, using: docker) == nil)
	}

	// MARK: - Running something in it

	/// `remoteUser` and `remoteEnv` rather than the container ones, which is the
	/// spec's distinction and a real one: the container is what it is, and what
	/// attaches to it afterwards gets the remote pair.
	@Test func runsAThingInsideItAsTheRemoteUser() throws {
		let configuration = try read("""
		{
			"image": "alpine:3.20",
			"containerUser": "root",
			"remoteUser": "vscode",
			"containerEnv": {"CGO_ENABLED": "0"},
			"remoteEnv": {"GOFLAGS": "-mod=mod"}
		}
		""")
		let exec = DevContainers.execCommand(session(configuration), arguments: ["go", "version"])
		#expect(exec.arguments == [
			"exec", "-i",
			"-w", "/workspaces/service",
			"-u", "vscode",
			"-e", "GOFLAGS=-mod=mod",
			"abydos-devcontainer-4242-1",
			"go", "version",
		])
	}

	/// Which shells an image carries is not something this side can know, so the
	/// choice is made inside the container: a terminal that opens onto
	/// "executable file not found" is worse than a plain `sh`.
	@Test func opensATerminalOnAShellTheImageActuallyHas() throws {
		let configuration = try read(#"{"image": "alpine:3.20"}"#)
		let terminal = DevContainers.terminalCommand(session(configuration))
		#expect(terminal.arguments.prefix(2) == ["exec", "-it"])
		#expect(terminal.arguments.contains("abydos-devcontainer-4242-1"))
		let line = try #require(terminal.arguments.last)
		#expect(line.contains("exec bash -l"))
		#expect(line.contains("exec sh -l"))
	}

	/// The user is the container's own when the file names no remote one, rather
	/// than the flag being dropped and the image's default quietly used.
	@Test func fallsBackToTheContainersUserWhenThereIsNoRemoteOne() throws {
		let configuration = try read("""
		{"image": "alpine:3.20", "containerUser": "node"}
		""")
		let exec = DevContainers.execCommand(session(configuration), arguments: ["true"])
		#expect(exec.arguments.contains("-u"))
		#expect(exec.arguments.contains("node"))

		let anonymous = try read(#"{"image": "alpine:3.20"}"#)
		#expect(!DevContainers.execCommand(session(anonymous), arguments: ["true"])
			.arguments.contains("-u"))
	}

	// MARK: - The name, and getting rid of it

	/// Through the register that names, tracks and sweeps every container this
	/// app starts — which is the whole of 0406.
	@Test func namesTheContainerSoItCanBeFoundAndRemoved() {
		let name = ToolContainers.mint("devcontainer")
		#expect(name.hasPrefix("abydos-devcontainer-"))
		#expect(ToolContainers.isOurs(name))
		#expect(ToolContainers.owner(of: name) == ProcessInfo.processInfo.processIdentifier)
		// And so a sweep after this process is gone would take it.
		#expect(ToolContainers.stale(among: [name], isAlive: { _ in false }) == [name])
		#expect(ToolContainers.stale(among: [name], isAlive: { _ in true }).isEmpty)
	}

	// MARK: - What it will not do

	/// Both runtimes start one now: what made this docker-only was that removing
	/// a container by name was unproven against Apple's, and it is proven.
	@Test func bothRuntimesStartOneNowThatBothCanBeTidiedUpAfter() {
		#expect(DevContainers.canStart(.docker("/usr/bin/docker")))
		#expect(DevContainers.canStart(.apple("/usr/local/bin/container")))
	}

	/// The one thing that does not work on Apple's runtime, refused by name
	/// rather than started and left silently unreachable.
	@Test func aForwardedPortIsRefusedOnApplesRuntimeAndOnlyThat() throws {
		let apple = ContainerRuntime.apple("/usr/local/bin/container")
		let ported = try read(#"{"image": "alpine:3", "forwardPorts": [8080, 5432]}"#)
		let reason = try #require(DevContainers.unsupported(ported, on: apple))
		#expect(reason.contains("8080, 5432"))
		#expect(reason.contains("accepted and then reset"))
		#expect(reason.contains("Docker"))
		#expect(reason.contains("service"))

		// Docker forwards ports perfectly well, so nothing is refused there.
		#expect(DevContainers.unsupported(ported, on: docker) == nil)
		// And a devcontainer that forwards nothing has nothing to be wrong.
		let plain = try read(#"{"image": "alpine:3"}"#)
		#expect(DevContainers.unsupported(plain, on: apple) == nil)
	}

	/// Docker answers the one field; Apple's has no `-f` and answers with the
	/// whole record, which is read rather than searched for the word "true".
	@Test func eachRuntimeIsAskedForItsStateInItsOwnWords() {
		let apple = ContainerRuntime.apple("/usr/local/bin/container")
		#expect(DevContainers.stateCommand(name: "abydos-x", using: docker).arguments
			== ["inspect", "-f", "{{.State.Running}}", "abydos-x"])
		#expect(DevContainers.stateCommand(name: "abydos-x", using: apple).arguments
			== ["inspect", "abydos-x"])

		#expect(DevContainers.isRunning("true\n", using: docker))
		#expect(!DevContainers.isRunning("false\n", using: docker))

		let running = #"[{"id":"abydos-x","status":{"state":"running","networks":[]}}]"#
		let stopped = #"[{"id":"abydos-x","status":{"state":"stopped","networks":[]}}]"#
		#expect(DevContainers.isRunning(running, using: apple))
		#expect(!DevContainers.isRunning(stopped, using: apple))
		// The word in an image reference is not a state, which a `contains` would
		// have taken it for.
		#expect(!DevContainers.isRunning(
			#"[{"id":"x","configuration":{"image":"example/true-running:1"},"status":{"state":"stopped"}}]"#,
			using: apple
		))
		#expect(!DevContainers.isRunning("Error: container not found", using: apple))
	}

	@Test func saysWhichOfTheUsualThingsStoppedIt() {
		#expect(DevContainers.explainStart(
			"docker: Error response from daemon: driver failed programming external "
				+ "connectivity: Bind for 127.0.0.1:8080 failed: port is already allocated.",
			project: "service"
		).contains("already in use"))

		#expect(DevContainers.explainStart(
			"Cannot connect to the Docker daemon at unix:///var/run/docker.sock.",
			project: "service"
		) == "Docker is not running, so the devcontainer for service could not be started.")

		// And the runtime that could not be reached is named, so nobody is sent to
		// start the wrong one.
		#expect(DevContainers.explainStart(
			"Error: cannot connect to the API server",
			project: "service", runtime: .apple("/usr/local/bin/container")
		) == "container is not running, so the devcontainer for service could not be started.")

		#expect(DevContainers.explainStart("", project: "service")
			.contains("said nothing about why"))
	}
}
