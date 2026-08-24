import Foundation
import Testing
@testable import AbydosKit

/// Turning a make goal into something debuggable.
struct MakeLaunchTests {
	/// The shape of a real project's Makefile: a frontend build, a Go build
	/// with stripped symbols, and a run line carrying credentials that come
	/// out of a shell.
	private let text = """
	GO = go
	VERSION ?= $(shell git describe --tags --always)
	LDFLAGS = -ldflags "-s -w -X 'app/version.Version=$(VERSION)'"
	BUILD_DIR = build
	CONFIG_DIR = $(PWD)/../production/config
	WEB_DIR = web
	BINARY_NAME = mqtt-unifi-network

	SECRETS = $(HOME)/secrets.yaml
	WITH_CREDS = UNIFI_USER=$$(sops -d $(SECRETS) | awk '/UNIFI_USER:/{print $$2}')

	.PHONY: build-frontend
	build-frontend: ## Build the web UI
	\t@cd $(WEB_DIR) && pnpm install && pnpm run build

	.PHONY: build-backend
	build-backend: ## Build the Go binary
	\t@$(GO) build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) .

	.PHONY: dev
	dev: build-frontend build-backend ## Build everything and run
	\t@echo "Starting the application..."
	\t@$(WITH_CREDS) $(BUILD_DIR)/$(BINARY_NAME) $(CONFIG_DIR)/config.json

	.PHONY: test
	test: ## Run the Go tests
	\t@$(GO) test ./...
	"""

	private var makefile: Makefile {
		Makefile.parse(text, path: URL(fileURLWithPath: "/p/app/Makefile"))
	}

	/// The Go build is left out: make strips the symbols out of that binary,
	/// and the debugger has to build its own.
	@Test func buildsEverythingExceptTheGoBinary() throws {
		let plan = try #require(MakeLaunch.plan(for: "dev", in: makefile))
		#expect(plan.buildTargets == ["build-frontend"])
		#expect(plan.package == ".")
	}

	@Test func keepsTheArgumentsTheRecipeWouldPass() throws {
		let plan = try #require(MakeLaunch.plan(for: "dev", in: makefile))
		#expect(plan.arguments == ["/p/app/../production/config/config.json"])
	}

	/// A credential that comes out of sops cannot be a static value, so it is
	/// carried as the command that produces it.
	@Test func carriesEnvironmentThatComesFromAShell() throws {
		let plan = try #require(MakeLaunch.plan(for: "dev", in: makefile))
		#expect(plan.environment.isEmpty)
		#expect(plan.environmentCommands["UNIFI_USER"]?.contains("sops") == true)
	}

	/// A goal that runs no program of this project is not something to debug.
	@Test func refusesAGoalThatStartsNothing() {
		#expect(MakeLaunch.plan(for: "test", in: makefile) == nil)
		#expect(MakeLaunch.plan(for: "build-frontend", in: makefile) == nil)
		#expect(MakeLaunch.plan(for: "nonexistent", in: makefile) == nil)
	}

	/// A goal whose only step is the Go build and the run still works, and has
	/// nothing to build first.
	@Test func handlesAGoalWithNoOtherSteps() throws {
		let simple = Makefile.parse("""
		run: ## Build and run
		\tgo build -o bin/app ./cmd/app
		\t./bin/app --config dev.json
		""", path: URL(fileURLWithPath: "/p/Makefile"))

		let plan = try #require(MakeLaunch.plan(for: "run", in: simple))
		#expect(plan.package == "./cmd/app")
		#expect(plan.arguments == ["--config", "dev.json"])
		#expect(plan.buildTargets.isEmpty)
	}

	/// Static environment stays static.
	@Test func readsPlainEnvironmentAssignments() throws {
		let simple = Makefile.parse("""
		run:
		\tgo build -o bin/app .
		\tLOG_LEVEL=debug PORT=8080 ./bin/app
		""", path: URL(fileURLWithPath: "/p/Makefile"))

		let plan = try #require(MakeLaunch.plan(for: "run", in: simple))
		#expect(plan.environment == ["LOG_LEVEL": "debug", "PORT": "8080"])
		#expect(plan.environmentCommands.isEmpty)
	}

	/// What lands in launch.json: a package to debug, the arguments, and our
	/// own keys for the parts VS Code has no word for.
	@Test func writesALaunchConfiguration() throws {
		let configuration = try #require(MakeLaunch.configuration(
			for: "dev", in: makefile, projectRoot: URL(fileURLWithPath: "/p")
		))

		#expect(configuration.name == "make dev")
		#expect(configuration.type == "go")
		#expect(configuration.program == "${workspaceFolder}/app")
		#expect(configuration.workingDirectory == "${workspaceFolder}/app")

		let make = try #require(configuration.extras["abydos.make"])
		guard case let .object(fields) = make, case let .array(targets) = fields["targets"] else {
			Issue.record("no make targets")
			return
		}
		#expect(targets == [.string("build-frontend")])
		#expect(configuration.extras["abydos.envCommands"] != nil)
	}

	/// Whatever we add has to survive a round trip through the file, since
	/// nothing else that reads launch.json knows these keys.
	@Test func survivesTheLaunchFile() throws {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("make-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		let configuration = try #require(MakeLaunch.configuration(
			for: "dev", in: makefile, projectRoot: URL(fileURLWithPath: "/p")
		))
		_ = try LaunchFile.save(configuration, in: root)

		let read = try #require(LaunchFile.read(in: root).first)
		#expect(read == configuration)
		#expect(read.extras["abydos.make"] != nil)
	}
}

/// The parts of a configuration only this app understands.
struct LaunchExtrasTests {
	@Test func readsTheMakeStepBack() {
		let configuration = LaunchConfiguration(
			name: "make dev",
			extras: ["abydos.make": .object([
				"targets": .array([.string("build-frontend"), .string("assets")]),
				"directory": .string("${workspaceFolder}/app"),
			])]
		)
		let step = configuration.makeStep
		#expect(step?.targets == ["build-frontend", "assets"])
		#expect(step?.commandLine(root: URL(fileURLWithPath: "/p"))
			== "make -C /p/app build-frontend assets")
	}

	@Test func hasNoStepWhenNothingSaysSo() {
		#expect(LaunchConfiguration(name: "plain").makeStep == nil)
		#expect(LaunchConfiguration(name: "plain").environmentCommands.isEmpty)
		// A malformed entry is the same as none, rather than a crash.
		#expect(LaunchConfiguration(name: "x", extras: ["abydos.make": .string("nonsense")])
			.makeStep == nil)
	}

	@Test func readsEnvironmentCommands() {
		let configuration = LaunchConfiguration(
			name: "x",
			extras: ["abydos.envCommands": .object(["TOKEN": .string("$(echo secret)")])]
		)
		#expect(configuration.environmentCommands == ["TOKEN": "$(echo secret)"])
	}
}

/// Producing environment values with a shell.
struct ShellEnvironmentTests {
	@Test func evaluatesACommand() async {
		let result = await ShellEnvironment.evaluate(
			["GREETING": "$(echo hello)"], in: URL(fileURLWithPath: NSTemporaryDirectory())
		)
		#expect(result.values["GREETING"] == "hello")
		#expect(result.failures.isEmpty)
	}

	/// A command that produces nothing is reported rather than passed on as an
	/// empty value: a program started without its password fails later and
	/// less clearly.
	@Test func reportsOneThatProducesNothing() async {
		let result = await ShellEnvironment.evaluate(
			["TOKEN": "$(command-that-does-not-exist 2>/dev/null)"],
			in: URL(fileURLWithPath: NSTemporaryDirectory())
		)
		#expect(result.values["TOKEN"] == nil)
		#expect(result.failures["TOKEN"] != nil)
	}

	@Test func evaluatesSeveral() async {
		let result = await ShellEnvironment.evaluate(
			["A": "$(echo one)", "B": "$(echo two)"],
			in: URL(fileURLWithPath: NSTemporaryDirectory())
		)
		#expect(result.values == ["A": "one", "B": "two"])
	}
}
