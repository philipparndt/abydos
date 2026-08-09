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

	/// Several is a question VS Code answers by asking, and this app refused the
	/// whole project for want of anywhere to ask it. There is somewhere now — the
	/// menu behind the terminal panel's + — so both are offered, each named after
	/// itself.
	@Test func offersEveryOneOfThemSeparatelyNamed() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }
		try JavaTestDirectory.write(
			#"{"image": "alpine:3.20", "name": "The back end"}"#,
			to: project.appendingPathComponent(".devcontainer/backend/devcontainer.json")
		)
		// No name of its own, so the folder is what it is called — which is the
		// whole of why several can be offered at all. Two entries both reading
		// "Container" would say less than the refusal they replaced.
		try JavaTestDirectory.write(
			#"{"image": "alpine:3.21"}"#,
			to: project.appendingPathComponent(".devcontainer/frontend/devcontainer.json")
		)

		let choices = DevContainerFile.choices(in: project)
		#expect(choices.map(\.name) == ["The back end", "frontend"])
		#expect(choices.map { $0.file.lastPathComponent } == ["devcontainer.json", "devcontainer.json"])
		#expect(choices[0].file.deletingLastPathComponent().lastPathComponent == "backend")
		#expect(choices[1].file.deletingLastPathComponent().lastPathComponent == "frontend")

		// Each reads as itself rather than as the first of them.
		#expect(DevContainerFile.read(choices[0].file, project: project)
			.configuration?.image == "alpine:3.20")
		#expect(DevContainerFile.read(choices[1].file, project: project)
			.configuration?.image == "alpine:3.21")

		// And the caller with nowhere to ask gets the preferred one rather than a
		// refusal — sorted, so it is the same answer every time.
		#expect(DevContainerFile.read(project: project)?.configuration?.image == "alpine:3.20")
	}

	/// A project reached through a symlink still knows where its own files are.
	///
	/// 0430: the root went through `realpath` and the file did not, so under
	/// `/tmp` — a symlink to `/private/tmp`, and where every scratch project this
	/// app's harness makes lives — every file collapsed to `devcontainer.json`
	/// with no folder in front of it. That took `build.dockerfile` with it, since
	/// it resolves against the file's own place, and it made a project's two
	/// devcontainers indistinguishable from one another.
	@Test func findsItsOwnFilesThroughASymlinkedRoot() throws {
		let real = try makeProject()
		defer { try? FileManager.default.removeItem(at: real) }
		let link = real.deletingLastPathComponent()
			.appendingPathComponent("link-to-\(real.lastPathComponent)")
		try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
		defer { try? FileManager.default.removeItem(at: link) }

		try JavaTestDirectory.write(
			#"{"build": {"dockerfile": "Dockerfile"}}"#,
			to: real.appendingPathComponent(".devcontainer/one/devcontainer.json")
		)
		try JavaTestDirectory.write(
			#"{"image": "alpine:3.21"}"#,
			to: real.appendingPathComponent(".devcontainer/two/devcontainer.json")
		)

		let choices = DevContainerFile.choices(in: link)
		#expect(choices.map(\.name) == ["one", "two"])
		// The two are different files, which is what a project with two
		// containers up at once depends on being true.
		let files = choices.map { DevContainerFile.read($0.file, project: link).configuration?.file }
		#expect(files[0] != files[1])
		#expect(files[0]?.path.hasSuffix("/.devcontainer/one/devcontainer.json") == true)
		// And the Dockerfile is beside the file that names it rather than at the
		// top of the project, which is the half of this that failed to build.
		let build = DevContainerFile.read(choices[0].file, project: link).configuration?.build
		#expect(build?.dockerfile.hasSuffix("/.devcontainer/one/Dockerfile") == true)
	}

	/// A file this app will not start still has to be named, or its refusal is
	/// attributed to nothing on screen.
	@Test func namesOneItCannotStart() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }
		try JavaTestDirectory.write(
			"""
			{
				"name": "With features",
				"image": "alpine:3.20",
				"features": { "ghcr.io/devcontainers/features/go:1": {} }
			}
			""",
			to: project.appendingPathComponent(".devcontainer/tools/devcontainer.json")
		)
		let choices = DevContainerFile.choices(in: project)
		#expect(choices.map(\.name) == ["With features"])
		#expect(DevContainerFile.read(choices[0].file, project: project).refusal != nil)

		// And with nothing to read at all, the folder is still an honest answer.
		try JavaTestDirectory.write(
			"not json", to: project.appendingPathComponent(".devcontainer/broken/devcontainer.json")
		)
		#expect(DevContainerFile.choices(in: project).map(\.name) == ["broken", "With features"])
	}

	/// The common case is the one that must not move: a project with one file in
	/// one of the two fixed places is named after the project, exactly as before.
	@Test func aSingleDevContainerIsNamedTheWayItAlwaysWas() throws {
		let plain = try makeProject()
		defer { try? FileManager.default.removeItem(at: plain) }
		try JavaTestDirectory.write(
			#"{"image": "alpine:3.20"}"#,
			to: plain.appendingPathComponent(".devcontainer/devcontainer.json")
		)
		#expect(DevContainerFile.choices(in: plain).map(\.name) == [plain.lastPathComponent])

		let beside = try makeProject()
		defer { try? FileManager.default.removeItem(at: beside) }
		try JavaTestDirectory.write(
			#"{"image": "alpine:3.21", "name": "Named"}"#,
			to: beside.appendingPathComponent(".devcontainer.json")
		)
		#expect(DevContainerFile.choices(in: beside).map(\.name) == ["Named"])
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

	// MARK: - The lifecycle commands

	/// All six, each read into the moment it belongs to.
	///
	/// This was a refusal until step five of 0424, and the refusal was the right
	/// call while nothing ran them: `postCreateCommand` is where a project runs
	/// `go mod download`, and a container up without it has tools missing for a
	/// reason nothing on screen explains.
	@Test func readsEverySixOfTheLifecycleCommands() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let configuration = try #require(read("""
		{
			"image": "alpine:3.20",
			"initializeCommand": "mkdir -p .cache",
			"onCreateCommand": "apk add git",
			"updateContentCommand": ["go", "mod", "download"],
			"postCreateCommand": { "tools": "npm ci", "fetch": ["go", "mod", "tidy"] },
			"postStartCommand": "service start",
			"postAttachCommand": "echo attached",
		}
		""", in: project).configuration)
		let lifecycle = configuration.lifecycle

		#expect(lifecycle[.initializeCommand] == .shell("mkdir -p .cache"))
		#expect(lifecycle[.onCreateCommand] == .shell("apk add git"))
		// The array form is argv, with no shell between: a file that writes it
		// this way is saying "do not parse these again".
		#expect(lifecycle[.updateContentCommand] == .argv(["go", "mod", "download"]))
		#expect(lifecycle[.postCreateCommand] == .named([
			"tools": .shell("npm ci"),
			"fetch": .argv(["go", "mod", "tidy"]),
		]))
		#expect(lifecycle[.postStartCommand] == .shell("service start"))
		#expect(lifecycle[.postAttachCommand] == .shell("echo attached"))
		#expect(lifecycle.stages == DevContainerStage.allCases)
		#expect(lifecycle.hasCreationCommands)
	}

	/// What each shape becomes when it is run, which is the thing that has to be
	/// right rather than how it was parsed.
	@Test func eachShapeBecomesTheCommandLineItMeans() throws {
		#expect(DevContainerCommand.shell("npm ci && npm test").invocation
			== ["/bin/sh", "-c", "npm ci && npm test"])
		#expect(DevContainerCommand.argv(["go", "mod", "download"]).invocation
			== ["go", "mod", "download"])

		// The object form is several commands, reported in a fixed order so that
		// which one is named first is a fact about the names.
		let named = DevContainerCommand.named(["b": .shell("two"), "a": .shell("one")])
		#expect(named.members.map(\.name) == ["a", "b"])
		#expect(named.members.map(\.command) == [.shell("one"), .shell("two")])
	}

	/// The substitutions reach into them, because a command is a string in the
	/// file like any other.
	@Test func substitutesInsideALifecycleCommand() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let configuration = try #require(read("""
		{
			"image": "alpine:3.20",
			"postCreateCommand": ["sh", "-c", "cd ${containerWorkspaceFolder} && make"],
		}
		""", in: project).configuration)
		#expect(configuration.lifecycle[.postCreateCommand]
			== .argv(["sh", "-c", "cd /workspaces/\(project.lastPathComponent) && make"]))
	}

	/// A shape the spec has no meaning for is refused rather than guessed at.
	@Test func refusesALifecycleCommandItCannotRead() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let reason = try #require(read("""
		{"image": "alpine:3.20", "postCreateCommand": 17}
		""", in: project).refusal)
		#expect(reason == ".devcontainer/devcontainer.json has a postCreateCommand this app could "
			+ "not read — the spec allows a string, a list of arguments, or an object of named "
			+ "commands.")

		// Nested objects have no meaning in the spec, and inventing one would be
		// this app deciding what somebody else's file meant.
		#expect(read("""
		{"image": "alpine:3.20", "onCreateCommand": {"a": {"b": "true"}}}
		""", in: project).refusal?.contains("onCreateCommand") == true)
	}

	/// `waitFor` names one of the five, and anything else is a file saying
	/// something this app would otherwise silently ignore.
	@Test func readsWaitForAndRefusesOneThatNamesNothing() throws {
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		let configuration = try #require(read("""
		{"image": "alpine:3.20", "waitFor": "onCreateCommand"}
		""", in: project).configuration)
		#expect(configuration.lifecycle.waitFor == .onCreateCommand)

		let reason = try #require(read("""
		{"image": "alpine:3.20", "waitFor": "buildCommand"}
		""", in: project).refusal)
		#expect(reason.contains("waits for buildCommand"))
		// initializeCommand runs before the container exists, so waiting for it
		// is not a thing a container can be ready after.
		#expect(read("""
		{"image": "alpine:3.20", "waitFor": "initializeCommand"}
		""", in: project).refusal != nil)
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
