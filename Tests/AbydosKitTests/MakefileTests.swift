import Foundation
import Testing
@testable import AbydosKit

/// Reading a Makefile.
struct MakefileTests {
	private func parse(_ text: String) -> Makefile {
		Makefile.parse(text, path: URL(fileURLWithPath: "/p/app/Makefile"))
	}

	@Test func readsTargetsAndTheirHelp() {
		let makefile = parse("""
		.PHONY: build
		build: deps ## Build everything
		\t@go build -o build/app .

		.PHONY: test
		test: ## Run the tests
		\tgo test ./...
		""")

		#expect(makefile.targets.map(\.name) == ["build", "test"])
		#expect(makefile.target(named: "build")?.summary == "Build everything")
		#expect(makefile.target(named: "build")?.prerequisites == ["deps"])
		// The `@` is make's way of not echoing, not part of the command.
		#expect(makefile.target(named: "build")?.recipe == ["go build -o build/app ."])
	}

	@Test func readsVariables() {
		let makefile = parse("""
		GO = go
		BUILD_DIR = build
		BINARY := app
		VERSION ?= dev
		""")
		#expect(makefile.variables["GO"] == "go")
		#expect(makefile.variables["BUILD_DIR"] == "build")
		#expect(makefile.variables["BINARY"] == "app")
		#expect(makefile.variables["VERSION"] == "dev")
	}

	/// Variables refer to each other, so expanding one has to expand what it
	/// names.
	@Test func expandsVariablesThroughEachOther() {
		let makefile = parse("""
		BUILD_DIR = build
		NAME = app
		BINARY = $(BUILD_DIR)/$(NAME)
		""")
		#expect(makefile.expand("$(BINARY) --flag") == "build/app --flag")
		#expect(makefile.expand("${BUILD_DIR}/x") == "build/x")
	}

	/// `$(PWD)` is where the Makefile is, which is what make would say.
	@Test func expandsTheWorkingDirectory() {
		let makefile = parse("CONFIG = $(PWD)/../production/config")
		#expect(makefile.expand("$(CONFIG)") == "/p/app/../production/config")
	}

	/// A shell call is not a variable and cannot be looked up; it is left for
	/// whoever runs the line.
	@Test func leavesShellCallsAlone() {
		let makefile = parse("VERSION ?= $(shell git describe --tags)")
		#expect(makefile.expand("$(VERSION)") == "$(shell git describe --tags)")
	}

	@Test func joinsContinuedLines() {
		let makefile = parse("""
		WITH_CREDS = USER=$$(sops -d x) \\
		             PASSWORD=$$(sops -d y)
		""")
		#expect(makefile.variables["WITH_CREDS"]?.contains("PASSWORD") == true)
	}

	/// A colon inside a variable does not start a rule.
	@Test func ignoresColonsThatAreNotRules() {
		let makefile = parse("""
		IMAGE = registry.example.com/team/app:latest
		LDFLAGS = -ldflags "-X 'main.Version=$(VERSION)'"
		""")
		#expect(makefile.targets.isEmpty)
		#expect(makefile.variables["IMAGE"] == "registry.example.com/team/app:latest")
	}

	/// The order make would build in: prerequisites before the thing that
	/// needs them.
	@Test func walksThePrerequisiteChain() {
		let makefile = parse("""
		dev: build-frontend build-backend
		\t./build/app config.json

		build-frontend:
		\tpnpm build

		build-backend: deps
		\tgo build -o build/app .

		deps:
		\tgo mod download
		""")
		#expect(makefile.chain(from: "dev").map(\.name)
			== ["build-frontend", "deps", "build-backend", "dev"])
	}

	@Test func survivesAMakefileItCannotUnderstand() {
		let makefile = parse("%.o: %.c\n\t$(CC) -c $<\n")
		#expect(makefile.targets.isEmpty)
	}
}
