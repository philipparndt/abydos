import Foundation
import Testing
@testable import AbydosKit

/// Reading a project's `devcontainer.json`, and refusing the parts of it this
/// app cannot honestly honour.
///
/// Pure, every one of these: a string in, a configuration or a sentence out.
/// The container coming up is `DevContainerLiveTests`.
struct DevContainerFileTests {
	/// A project directory that exists, since the reader canonicalises the path
	/// it is given and a path that is nowhere cannot be canonicalised.
	private func makeProject() throws -> URL {
		let root = try JavaTestDirectory.make()
		return URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)
	}

	private func read(
		_ json: String, in project: URL, environment: [String: String] = [:]
	) -> DevContainerFile.Reading {
		DevContainerFile.parse(Data(json.utf8), project: project, environment: environment)
	}

	// MARK: - The dialect

	/// JSON with comments and trailing commas, which is what the spec says the
	/// file is and what `JSONSerialization` will not take.
	@Test func readsCommentsAndTrailingCommas() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let reading = read("""
		{
			// The image this project is worked on in.
			"name": "Go",
			/* Pinned, because an example everybody pulls should be
			   the same one tomorrow. */
			"image": "mcr.microsoft.com/devcontainers/go:1.24",
			"forwardPorts": [8080,],
		}
		""", in: project)

		let configuration = try #require(reading.configuration)
		#expect(configuration.name == "Go")
		#expect(configuration.image == "mcr.microsoft.com/devcontainers/go:1.24")
		#expect(configuration.forwardPorts == [8080])
	}

	/// A `//` inside a string is not a comment. The stripper this shares with
	/// launch.json knows that, and a registry URL is where it would show.
	@Test func leavesSlashesInsideStringsAlone() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let reading = read(#"{"image": "ghcr.io/owner/image:1.2", "name": "a // b"}"#, in: project)
		let configuration = try #require(reading.configuration)
		#expect(configuration.image == "ghcr.io/owner/image:1.2")
		#expect(configuration.name == "a // b")
	}

	/// A file nobody can parse says so, rather than being treated as no file at
	/// all: a project with a broken devcontainer.json is a project whose author
	/// meant it to have one.
	@Test func refusesAFileThatIsNotJSON() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let reason = try #require(read("{ not json at all", in: project).refusal)
		#expect(reason == ".devcontainer/devcontainer.json is not valid JSON, "
			+ "so nothing in it could be read.")

		#expect(read("[1, 2, 3]", in: project).refusal != nil)
		#expect(read("", in: project).refusal != nil)
	}

	// MARK: - Where the file is allowed to be

	@Test func findsTheFileInEveryPlaceItIsAllowed() throws {
		let plain = try makeProject()
		defer { try? FileManager.default.removeItem(at: plain) }
		try JavaTestDirectory.write(
			#"{"image": "alpine:3.20"}"#,
			to: plain.appendingPathComponent(".devcontainer/devcontainer.json")
		)
		#expect(DevContainerFile.read(project: plain)?.configuration?.image == "alpine:3.20")

		let beside = try makeProject()
		defer { try? FileManager.default.removeItem(at: beside) }
		try JavaTestDirectory.write(
			#"{"image": "alpine:3.21"}"#, to: beside.appendingPathComponent(".devcontainer.json")
		)
		#expect(DevContainerFile.read(project: beside)?.configuration?.image == "alpine:3.21")

		let named = try makeProject()
		defer { try? FileManager.default.removeItem(at: named) }
		try JavaTestDirectory.write(
			#"{"image": "alpine:3.22"}"#,
			to: named.appendingPathComponent(".devcontainer/backend/devcontainer.json")
		)
		#expect(DevContainerFile.read(project: named)?.configuration?.image == "alpine:3.22")

		// And a project with none is not a failure — most projects have none.
		let bare = try makeProject()
		defer { try? FileManager.default.removeItem(at: bare) }
		#expect(DevContainerFile.read(project: bare) == nil)
		#expect(!DevContainerFile.exists(in: bare))
	}

	/// Several is a question VS Code answers by asking, and this app has nowhere
	/// to ask it: picking one quietly would be picking somebody's toolchain.
	@Test func refusesToChooseBetweenSeveralOfThem() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }
		try JavaTestDirectory.write(
			#"{"image": "alpine:3.20"}"#,
			to: project.appendingPathComponent(".devcontainer/backend/devcontainer.json")
		)
		try JavaTestDirectory.write(
			#"{"image": "alpine:3.21"}"#,
			to: project.appendingPathComponent(".devcontainer/frontend/devcontainer.json")
		)
		let reason = try #require(DevContainerFile.read(project: project)?.refusal)
		#expect(reason.contains("more than one devcontainer.json"))
		#expect(reason.contains(".devcontainer/backend/devcontainer.json"))
		#expect(reason.contains(".devcontainer/frontend/devcontainer.json"))
	}

	// MARK: - ${…}

	@Test func resolvesEverySubstitutionItPromises() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }
		let basename = project.lastPathComponent

		let reading = read("""
		{
			"image": "alpine:3.20",
			"workspaceFolder": "/src/${localWorkspaceFolderBasename}",
			"containerEnv": {
				"HOST": "${localWorkspaceFolder}",
				"TOKEN": "${localEnv:ABYDOS_TEST_TOKEN}",
				"REGION": "${localEnv:ABYDOS_TEST_MISSING:eu-west-1}",
				"NOTHING": "[${localEnv:ABYDOS_TEST_MISSING}]",
				"HERE": "${containerWorkspaceFolder}",
				"LEAF": "${containerWorkspaceFolderBasename}",
				"UNKNOWN": "${somethingNobodyHasHeardOf}"
			}
		}
		""", in: project, environment: ["ABYDOS_TEST_TOKEN": "s3cret"])

		let configuration = try #require(reading.configuration)
		#expect(configuration.workspaceFolder == "/src/\(basename)")
		#expect(configuration.containerEnv["HOST"] == project.path)
		#expect(configuration.containerEnv["TOKEN"] == "s3cret")
		// A variable this machine does not have falls back, and without a
		// fallback becomes empty rather than staying as the literal `${…}`.
		#expect(configuration.containerEnv["REGION"] == "eu-west-1")
		#expect(configuration.containerEnv["NOTHING"] == "[]")
		#expect(configuration.containerEnv["HERE"] == "/src/\(basename)")
		#expect(configuration.containerEnv["LEAF"] == basename)
		// Left exactly as written, which is the only answer that does not
		// corrupt a value nobody understood.
		#expect(configuration.containerEnv["UNKNOWN"] == "${somethingNobodyHasHeardOf}")
	}

	/// `${containerEnv:…}` cannot be answered before the container exists, and a
	/// PATH quietly resolved to nothing is a container that comes up and finds
	/// no tools.
	@Test func refusesAVariableOnlyTheContainerKnows() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let reason = try #require(read("""
		{"image": "alpine:3.20", "remoteEnv": {"PATH": "/opt/bin:${containerEnv:PATH}"}}
		""", in: project).refusal)
		#expect(reason == ".devcontainer/devcontainer.json uses ${containerEnv:PATH}, whose value "
			+ "only exists once the container is running, and this app cannot read it before "
			+ "starting one.")
	}

	// MARK: - Where the project goes

	/// The default is the one the reference implementation uses, because the
	/// published images expect it.
	@Test func mountsTheProjectWhereTheDefaultSaysWhenTheFileDoesNot() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let configuration = try #require(read(#"{"image": "alpine:3.20"}"#, in: project).configuration)
		#expect(configuration.paths.host == project.path)
		#expect(configuration.paths.container == "/workspaces/\(project.lastPathComponent)")
		#expect(configuration.workspaceFolder == configuration.paths.container)
		#expect(configuration.paths.mount.flag
			== "\(project.path):/workspaces/\(project.lastPathComponent)")
		#expect(!configuration.paths.mount.isReadOnly)
	}

	@Test func honoursAWorkspaceMountAndWorksInsideIt() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let configuration = try #require(read("""
		{
			"image": "alpine:3.20",
			"workspaceMount": "source=${localWorkspaceFolder},target=/code,type=bind,consistency=cached",
			"workspaceFolder": "/code/service"
		}
		""", in: project).configuration)
		#expect(configuration.paths.container == "/code")
		#expect(configuration.workspaceFolder == "/code/service")
		#expect(configuration.paths.toHost(path: "/code/service") == project.path + "/service")
	}

	/// `ContainerPaths` is what knows where the project stops, and it is asked
	/// rather than a second rule being written beside it.
	@Test func refusesToWorkOutsideTheMountedProject() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let reason = try #require(read("""
		{
			"image": "alpine:3.20",
			"workspaceMount": "source=${localWorkspaceFolder},target=/code,type=bind",
			"workspaceFolder": "/somewhere/else"
		}
		""", in: project).refusal)
		#expect(reason.contains("/code"))
		#expect(reason.contains("/somewhere/else"))
		#expect(reason.contains("not inside it"))
	}

	@Test func refusesToMountSomethingOtherThanTheProject() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let elsewhere = try #require(read("""
		{"image": "alpine:3.20", "workspaceMount": "source=/etc,target=/code,type=bind"}
		""", in: project).refusal)
		#expect(elsewhere.contains("/etc"))

		let volume = try #require(read("""
		{"image": "alpine:3.20", "workspaceMount": "source=cache,target=/code,type=volume"}
		""", in: project).refusal)
		#expect(volume.contains("stay on this machine"))
	}

	// MARK: - What the container comes from

	@Test func readsADockerfileAndItsContextRelativeToTheFile() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let configuration = try #require(read("""
		{
			"build": {
				"dockerfile": "Dockerfile",
				"context": "..",
				"args": {"GO_VERSION": "1.24", "USER": "${localEnv:ABYDOS_TEST_USER}"},
				"target": "development"
			}
		}
		""", in: project, environment: ["ABYDOS_TEST_USER": "dev"]).configuration)

		let build = try #require(configuration.build)
		#expect(build.dockerfile == project.path + "/.devcontainer/Dockerfile")
		#expect(build.context == project.path)
		#expect(build.args == ["GO_VERSION": "1.24", "USER": "dev"])
		#expect(build.target == "development")
		// Named after the project, in one repository, so a machine with several
		// of these does not rebuild one over another.
		#expect(configuration.imageReference == configuration.builtImageName)
		#expect(configuration.builtImageName.hasPrefix("abydos-devcontainer:"))
	}

	@Test func refusesAFileThatNamesNothingToStart() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let nothing = try #require(read(#"{"name": "Empty"}"#, in: project).refusal)
		#expect(nothing == ".devcontainer/devcontainer.json names neither an image nor a "
			+ "Dockerfile, so there is nothing to start this project in.")

		let both = try #require(read("""
		{"image": "alpine:3.20", "build": {"dockerfile": "Dockerfile"}}
		""", in: project).refusal)
		#expect(both.contains("both an image and a Dockerfile"))
	}

	// MARK: - The boundary of the subset

	/// Features are a package manager, and a container built without the tools
	/// they install does not look like an unsupported file — it looks like a
	/// broken editor.
	@Test func refusesFeaturesAndSaysWhichOne() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let reason = try #require(read("""
		{
			"image": "mcr.microsoft.com/devcontainers/base:ubuntu",
			"features": {
				"ghcr.io/devcontainers/features/go:1": {"version": "1.24"}
			}
		}
		""", in: project).refusal)
		#expect(reason == ".devcontainer/devcontainer.json installs devcontainer features "
			+ "(ghcr.io/devcontainers/features/go:1), which this app does not build — put what "
			+ "they provide into the image or the Dockerfile the file names.")

		// An empty `features` is not a use of them, and is not refused.
		#expect(read(#"{"image": "alpine:3.20", "features": {}}"#, in: project).configuration != nil)
	}

	@Test func refusesComposeAndNamesTheFile() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let reason = try #require(read("""
		{"dockerComposeFile": "docker-compose.yml", "service": "app", "workspaceFolder": "/code"}
		""", in: project).refusal)
		#expect(reason == ".devcontainer/devcontainer.json builds this project with Docker Compose "
			+ "(docker-compose.yml), which this app does not run — a single image or "
			+ "build.dockerfile is what it can start.")

		// The list form names the first of them rather than saying nothing.
		let list = try #require(read("""
		{"dockerComposeFile": ["base.yml", "dev.yml"], "service": "app"}
		""", in: project).refusal)
		#expect(list.contains("base.yml"))
	}

	/// `postCreateCommand` is where a project runs `go mod download`. A
	/// container up without it has tools missing for a reason nothing on screen
	/// explains, so it refuses until step five of 0424 runs them.
	@Test func refusesALifecycleCommandItCannotRunYet() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let reason = try #require(read("""
		{"image": "alpine:3.20", "postCreateCommand": "go mod download"}
		""", in: project).refusal)
		#expect(reason == ".devcontainer/devcontainer.json has a postCreateCommand, and this app "
			+ "does not run the lifecycle commands yet — the container would come up without "
			+ "whatever that command installs.")

		for command in [
			"initializeCommand", "onCreateCommand", "updateContentCommand",
			"postStartCommand", "postAttachCommand",
		] {
			let refusal = read(
				#"{"image": "alpine:3.20", "\#(command)": "true"}"#, in: project
			).refusal
			#expect(refusal?.contains(command) == true)
		}
	}

	// MARK: - The rest of the subset

	@Test func readsTheUsersEnvironmentPortsMountsAndRunArguments() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let configuration = try #require(read("""
		{
			"image": "alpine:3.20",
			"containerUser": "root",
			"remoteUser": "vscode",
			"containerEnv": {"CGO_ENABLED": "0"},
			"remoteEnv": {"GOFLAGS": "-mod=mod"},
			"forwardPorts": [8080, "9090"],
			"mounts": [
				"source=${localWorkspaceFolder}/.cache,target=/home/vscode/.cache,type=bind",
				{"source": "go-modules", "target": "/go/pkg/mod", "type": "volume"}
			],
			"runArgs": ["--cap-add=SYS_PTRACE", "--security-opt", "seccomp=unconfined"]
		}
		""", in: project).configuration)

		#expect(configuration.containerUser == "root")
		#expect(configuration.remoteUser == "vscode")
		#expect(configuration.containerEnv == ["CGO_ENABLED": "0"])
		#expect(configuration.remoteEnv == ["GOFLAGS": "-mod=mod"])
		// A number and a number written as a string are the same port.
		#expect(configuration.forwardPorts == [8080, 9090])
		#expect(configuration.extraMounts == [
			"source=\(project.path)/.cache,target=/home/vscode/.cache,type=bind",
			"source=go-modules,target=/go/pkg/mod,type=volume",
		])
		#expect(configuration.runArgs
			== ["--cap-add=SYS_PTRACE", "--security-opt", "seccomp=unconfined"])
	}

	/// A port naming another compose service is only reachable with compose,
	/// which is already refused — but a number is what this publishes, and
	/// anything else says so rather than being dropped.
	@Test func refusesAPortItCannotPublish() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let reason = try #require(read("""
		{"image": "alpine:3.20", "forwardPorts": ["db:5432"]}
		""", in: project).refusal)
		#expect(reason.contains("db:5432"))
		#expect(reason.contains("a plain number"))
	}
}
