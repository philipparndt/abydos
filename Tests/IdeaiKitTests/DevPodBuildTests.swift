import Foundation
import Testing
@testable import IdeaiKit

/// Working out how to build a project for a pod that runs Linux.
///
/// The pod's architecture is not this machine's and its system is not either,
/// so something has to cross-compile — and which something depends entirely on
/// what the project is written in. Guessing wrong is what produced a Go error
/// in an Odin project, so each of these says what it expects to happen.
struct DevPodBuildStrategyTests {
	private func project(_ files: [String]) throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("build-\(UUID().uuidString)")
		for file in files {
			let url = root.appendingPathComponent(file)
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(), withIntermediateDirectories: true
			)
			try "".write(to: url, atomically: true, encoding: .utf8)
		}
		return root
	}

	private func configuration(_ program: String, type: String = "lldb") -> LaunchConfiguration {
		var configuration = LaunchConfiguration(name: "in the cluster", type: type)
		configuration.program = program
		return configuration
	}

	// MARK: - Which build

	@Test func aGoModuleIsBuiltWithGo() throws {
		let root = try project(["go.mod", "main.go"])
		defer { try? FileManager.default.removeItem(at: root) }

		guard case .go = DevPodBuild.strategy(
			for: configuration("${workspaceFolder}", type: "go"), root: root
		) else {
			Issue.record("expected a Go build")
			return
		}
	}

	@Test func aZigProjectIsBuiltWithZig() throws {
		let root = try project(["build.zig", "src/main.zig"])
		defer { try? FileManager.default.removeItem(at: root) }

		guard case .zig = DevPodBuild.strategy(
			for: configuration("${workspaceFolder}/zig-out/bin/thing"), root: root
		) else {
			Issue.record("expected a Zig build")
			return
		}
	}

	@Test func anOdinProjectIsBuiltWithOdin() throws {
		let root = try project(["src/main.odin"])
		defer { try? FileManager.default.removeItem(at: root) }

		guard case .odin = DevPodBuild.strategy(
			for: configuration("${workspaceFolder}/src"), root: root
		) else {
			Issue.record("expected an Odin build")
			return
		}
	}

	@Test func aCProjectGoesThroughZig() throws {
		let root = try project(["src/main.c", "Makefile"])
		defer { try? FileManager.default.removeItem(at: root) }

		guard case let .clang(_, isCPlusPlus) = DevPodBuild.strategy(
			for: configuration("${workspaceFolder}/build/thing"), root: root
		) else {
			Issue.record("expected a C build")
			return
		}
		#expect(!isCPlusPlus)
	}

	@Test func aCPlusPlusProjectIsToldApartFromC() throws {
		let root = try project(["src/main.cpp"])
		defer { try? FileManager.default.removeItem(at: root) }

		guard case let .clang(_, isCPlusPlus) = DevPodBuild.strategy(
			for: configuration("${workspaceFolder}/build/thing"), root: root
		) else {
			Issue.record("expected a C++ build")
			return
		}
		#expect(isCPlusPlus)
	}

	@Test func aRustProjectIsBuiltWithCargo() throws {
		let root = try project(["Cargo.toml", "src/main.rs"])
		defer { try? FileManager.default.removeItem(at: root) }

		guard case .rust = DevPodBuild.strategy(
			for: configuration("${workspaceFolder}/target/debug/thing"), root: root
		) else {
			Issue.record("expected a Rust build")
			return
		}
	}

	/// The project's own build wins over every guess: a Makefile that already
	/// cross-compiles knows things this cannot, and it is the only way a
	/// language nothing here handles can run in a cluster at all.
	@Test func aMakeStepBeatsTheLanguage() throws {
		let root = try project(["go.mod", "main.go", "Makefile"])
		defer { try? FileManager.default.removeItem(at: root) }

		var configuration = configuration("${workspaceFolder}/build/thing", type: "go")
		configuration.extras["ideai.make"] = .object([
			"targets": .array([.string("linux")]),
			"directory": .string("${workspaceFolder}"),
		])

		guard case let .make(targets, directory, artefact) = DevPodBuild.strategy(
			for: configuration, root: root
		) else {
			Issue.record("expected a make build")
			return
		}
		#expect(targets == ["linux"])
		#expect(directory == "${workspaceFolder}")
		#expect(artefact == "${workspaceFolder}/build/thing")
	}

	/// Nothing recognised and no build of its own: better to say so than to run
	/// `go build` in a project with no Go in it, which is where the error about
	/// a missing Go module came from.
	@Test func somethingUnrecognisedIsNotGuessedAt() throws {
		let root = try project(["CMakeLists.txt", "README.md"])
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(DevPodBuild.strategy(
			for: configuration("${workspaceFolder}/build/thing"), root: root
		) == nil)
	}

	// MARK: - What gets run

	@Test func architecturesAreNamedTheWayCompilersNameThem() {
		#expect(DevPodBuild.machine("arm64") == "aarch64")
		#expect(DevPodBuild.machine("amd64") == "x86_64")
		#expect(DevPodBuild.rustTriple("arm64") == "aarch64-unknown-linux-musl")
		#expect(DevPodBuild.rustTriple("amd64") == "x86_64-unknown-linux-musl")
	}

	/// musl, not glibc: the image the pod runs has no libc in it, so the binary
	/// has to carry its own.
	@Test func cIsCompiledStaticallyForTheClustersArchitecture() {
		let arguments = DevPodBuild.clangArguments(
			compiler: "/opt/homebrew/bin/zig",
			sources: ["/p/src/main.c"],
			architecture: "amd64",
			output: "/tmp/out",
			isCPlusPlus: false
		)
		#expect(arguments.prefix(4) == ["/opt/homebrew/bin/zig", "cc", "-target", "x86_64-linux-musl"])
		#expect(arguments.contains("/p/src/main.c"))
		#expect(arguments.suffix(2) == ["-o", "/tmp/out"])
	}

	/// Unoptimised and with debug information, for the reason the Go build is:
	/// a breakpoint has to land on the line it was put on.
	@Test func theBuildKeepsWhatADebuggerNeeds() {
		let arguments = DevPodBuild.clangArguments(
			compiler: "zig", sources: ["a.c"], architecture: "arm64",
			output: "out", isCPlusPlus: false
		)
		#expect(arguments.contains("-g"))
		#expect(arguments.contains("-O0"))
	}

	@Test func cPlusPlusGetsItsOwnDriverAndStandard() {
		let arguments = DevPodBuild.clangArguments(
			compiler: "zig", sources: ["a.cpp"], architecture: "arm64",
			output: "out", isCPlusPlus: true
		)
		#expect(arguments[1] == "c++")
		#expect(arguments.contains("-std=c++20"))
	}

	// MARK: - Which sources

	@Test func sourcesAreTakenFromTheDirectoryAndFromSrc() throws {
		let root = try project(["main.c", "src/helper.c", "src/notes.md", "build/old.c"])
		defer { try? FileManager.default.removeItem(at: root) }

		let found = DevPodBuild.sources(withExtension: "c", in: root)
			.map { $0.lastPathComponent }
		#expect(found.contains("main.c"))
		#expect(found.contains("helper.c"))
		// Not from build output, which is where the last binary's leftovers are.
		#expect(!found.contains("old.c"))
		#expect(!found.contains("notes.md"))
	}

	@Test func aDirectoryWithNoSourcesFindsNone() throws {
		let root = try project(["README.md"])
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(DevPodBuild.sources(withExtension: "c", in: root).isEmpty)
	}
}
