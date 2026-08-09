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

	// MARK: - The language servers inside it

	/// A server `exec`'d into the container the project is already open in,
	/// rather than started beside it in one of its own.
	///
	/// Every assertion here is one of the three things that hold on this machine
	/// and not in there, and each of them is a bug that would show up as a
	/// language server which starts and then answers nothing.
	@Test func startsALanguageServerInsideTheContainerTheProjectIsOpenIn() throws {
		let project = try #require(makeGoProject())
		defer { try? FileManager.default.removeItem(at: project) }

		let configuration = try read("""
		{
			"image": "golang:1.24-alpine",
			"workspaceMount": "source=${localWorkspaceFolder},target=/src,type=bind",
			"workspaceFolder": "/src",
			"remoteUser": "vscode",
			"remoteEnv": {"GOFLAGS": "-mod=mod"}
		}
		""", project: project.path)
		let session = session(configuration)

		let resolved = try #require(LanguageServers.resolve(
			languageId: "go", project: project, inDevContainer: session
		))

		// The devcontainer's own mapping, which is the file's rather than
		// `/workspace` — a server told anything else names files that exist on
		// neither side.
		#expect(resolved.launch.paths == ContainerPaths(host: project.path, container: "/src"))
		// Nothing is fetched for it and nothing is removed with it: the
		// container belongs to the project, and taking it away when a server
		// stops would take somebody's terminal with it.
		#expect(resolved.launch.image == nil)
		#expect(resolved.launch.container == nil)

		let run = resolved.launch.invocation
		#expect(run.executable == "/usr/bin/docker")
		#expect(run.arguments == [
			"exec", "-i",
			// Rooted where the manifest is, in the container's own names.
			"-w", "/src",
			// `remoteUser` and `remoteEnv`, which are what things attached to a
			// running container get.
			"-u", "vscode",
			"-e", "GOFLAGS=-mod=mod",
			"abydos-devcontainer-4242-1",
			// The bare command. Not a path from this machine, and above all not
			// one from `xcrun`: the server is not here.
			"gopls",
		])
	}

	/// A directory with a go.mod in it, so the Go server has a root to be
	/// rooted at — the resolution asks the file system, not the file.
	private func makeGoProject() -> URL? {
		guard let root = try? JavaTestDirectory.make() else { return nil }
		try? JavaTestDirectory.write(
			"module example.com/probe\n", to: root.appendingPathComponent("go.mod")
		)
		return URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)
	}

	/// A lifecycle command that failed, in one sentence somebody can act on.
	///
	/// What this has to get right is not classifying the failure — there is only
	/// one kind — but *naming* it: which of six commands that all look alike from
	/// outside, what it exited with, and the line it wrote before it gave up.
	@Test func namesTheLifecycleCommandThatFailedAndWhatItSaid() {
		let failed = RuntimeCommand.Result(
			// The order `RuntimeCommand` puts them in, which is why the two are
			// kept apart: the last line of standard output is only how far the
			// command got, and the line worth reading is on the other stream.
			output: "error: no such package: a-package-that-does-not-exist\n"
				+ "post-create: step 1 of 3 — this works\n"
				+ "post-create: step 2 of 3 — this works too\n"
				+ "post-create: step 3 of 3 — fetching a dependency that is not there\n",
			errorOutput: "error: no such package: a-package-that-does-not-exist\n",
			exitCode: 3,
			timedOut: false
		)
		#expect(DevContainers.explainLifecycle(
			label: "postCreateCommand",
			line: "sh .devcontainer/post-create.sh",
			result: failed,
			project: "post-create-fails"
		) == "post-create-fails's postCreateCommand exited 3: error: no such package: "
			+ "a-package-that-does-not-exist. The container was removed and nothing after it was "
			+ "run — fix `sh .devcontainer/post-create.sh` in the devcontainer.json and open the "
			+ "project again.")

		// The object form names the member too, because "postCreateCommand
		// failed" of a file with three of them is not enough to go on.
		#expect(DevContainers.explainLifecycle(
			label: "postCreateCommand (install)",
			line: "npm ci",
			result: failed,
			project: "web"
		).hasPrefix("web's postCreateCommand (install) exited 3:"))

		// A command that never finished says so, rather than reporting the
		// terminate signal as an exit status somebody would go looking for.
		let stuck = RuntimeCommand.Result(
			output: "", errorOutput: "", exitCode: 15, timedOut: true
		)
		#expect(DevContainers.explainLifecycle(
			label: "postCreateCommand", line: "npm ci", result: stuck, project: "web"
		).contains("took longer than 30 minutes and was stopped"))
	}
}
