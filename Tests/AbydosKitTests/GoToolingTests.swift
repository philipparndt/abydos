import Testing
import Foundation
@testable import AbydosKit

struct GoToolingTests {
	/// Builds a small module with two commands and a library.
	private func makeModule() throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("ideai-go-\(UUID().uuidString)")
		let fm = FileManager.default
		try fm.createDirectory(at: root.appendingPathComponent("cmd/server"), withIntermediateDirectories: true)
		try fm.createDirectory(at: root.appendingPathComponent("cmd/tool"), withIntermediateDirectories: true)
		try fm.createDirectory(at: root.appendingPathComponent("internal/lib"), withIntermediateDirectories: true)
		try fm.createDirectory(at: root.appendingPathComponent("vendor/other"), withIntermediateDirectories: true)

		try "module example.com/thing\n\ngo 1.22\n".write(
			to: root.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8
		)
		try "package main\n\nfunc main() {}\n".write(
			to: root.appendingPathComponent("cmd/server/main.go"), atomically: true, encoding: .utf8
		)
		try "package main\n\nfunc main() {}\n".write(
			to: root.appendingPathComponent("cmd/tool/main.go"), atomically: true, encoding: .utf8
		)
		try "package lib\n\nfunc Helper() {}\n".write(
			to: root.appendingPathComponent("internal/lib/lib.go"), atomically: true, encoding: .utf8
		)
		// Vendored code must not be offered as something to run.
		try "package main\n\nfunc main() {}\n".write(
			to: root.appendingPathComponent("vendor/other/main.go"), atomically: true, encoding: .utf8
		)
		return root
	}

	@Test func detectsAGoModule() throws {
		let root = try makeModule()
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(GoTooling.isGoModule(root))
		#expect(GoTooling.modulePath(in: root) == "example.com/thing")
	}

	@Test func nonModuleIsNotDetected() throws {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("ideai-nogo-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }

		#expect(!GoTooling.isGoModule(root))
		#expect(GoTooling.modulePath(in: root) == nil)
	}

	@Test func findsEveryMainPackage() throws {
		let root = try makeModule()
		defer { try? FileManager.default.removeItem(at: root) }

		let packages = GoTooling.findMainPackages(in: root)
		#expect(packages.contains("./cmd/server"))
		#expect(packages.contains("./cmd/tool"))
		// A library package is not runnable.
		#expect(!packages.contains("./internal/lib"))
	}

	/// Vendored code is a dependency, not something this project runs.
	@Test func skipsVendoredCode() throws {
		let root = try makeModule()
		defer { try? FileManager.default.removeItem(at: root) }
		#expect(!GoTooling.findMainPackages(in: root).contains { $0.contains("vendor") })
	}

	@Test func recognisesPackageMainOnlyOutsideComments() {
		#expect(GoTooling.declaresPackageMain("package main\n"))
		#expect(GoTooling.declaresPackageMain("// a comment\npackage main\n"))
		#expect(!GoTooling.declaresPackageMain("package lib\n"))
		// A mention inside a comment is not a declaration.
		#expect(!GoTooling.declaresPackageMain("// package main is documented here\npackage lib\n"))
	}

	// MARK: - Commands

	@Test func buildsRunAndTestCommands() {
		let run = GoTooling.runCommand(executable: "/usr/bin/go", package: "./cmd/server")
		#expect(run.arguments == ["run", "./cmd/server"])

		let test = GoTooling.testCommand(executable: "/usr/bin/go")
		// Verbose so individual results appear as they run.
		#expect(test.arguments == ["test", "-v", "./..."])
	}

	/// Tracing is two steps, so it runs through a shell; the executable path must
	/// be quoted in case it contains spaces.
	@Test func traceChainsTestAndViewer() {
		let trace = GoTooling.traceCommand(executable: "/opt/home brew/bin/go")
		#expect(trace.executable == "/bin/sh")
		let script = trace.arguments.last ?? ""
		#expect(script.contains("test -trace"))
		#expect(script.contains("tool trace"))
		#expect(script.contains("'/opt/home brew/bin/go'"))
	}

	@Test func profileCollectsThenReports() {
		let profile = GoTooling.profileCommand(executable: "/usr/bin/go")
		let script = profile.arguments.last ?? ""
		#expect(script.contains("-cpuprofile"))
		#expect(script.contains("tool pprof"))
	}

	@Test func debugUsesDelve() {
		let debug = GoTooling.debugCommand(delve: "/usr/local/bin/dlv", package: "./cmd/server")
		#expect(debug.executable == "/usr/local/bin/dlv")
		#expect(debug.arguments == ["debug", "./cmd/server"])
	}

	@Test func shellQuotingSurvivesApostrophes() {
		#expect(GoTooling.shellQuote("it's") == "'it'\\''s'")
	}
}
