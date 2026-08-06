import Foundation

/// Discovers Go projects and builds the commands to run, test and trace them.
///
/// Kept free of view code so the awkward parts — locating the toolchain from a
/// GUI app, finding which package holds `main`, deciding what "run" means for a
/// given project — are testable without a window.
public enum GoTooling {
	/// Locates the `go` binary.
	///
	/// A GUI app inherits no login shell, so `PATH` usually lacks Homebrew and
	/// the standard Go install location. Checking the known paths directly is
	/// more reliable than hoping the environment is right.
	public static func findGoExecutable() -> String? {
		let candidates = [
			"/opt/homebrew/bin/go",
			"/usr/local/go/bin/go",
			"/usr/local/bin/go",
			NSHomeDirectory() + "/go/bin/go",
			NSHomeDirectory() + "/sdk/go/bin/go",
		]
		if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
			return found
		}
		// Fall back to whatever PATH we do have.
		if let path = ProcessInfo.processInfo.environment["PATH"] {
			for directory in path.split(separator: ":") {
				let candidate = String(directory) + "/go"
				if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
			}
		}
		return nil
	}

	/// True when the directory is the root of a Go module.
	public static func isGoModule(_ root: URL) -> Bool {
		FileManager.default.fileExists(atPath: root.appendingPathComponent("go.mod").path)
	}

	/// Module path declared in go.mod, if there is one.
	public static func modulePath(in root: URL) -> String? {
		let goMod = root.appendingPathComponent("go.mod")
		guard let contents = try? String(contentsOf: goMod, encoding: .utf8) else { return nil }
		for line in contents.components(separatedBy: .newlines) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard trimmed.hasPrefix("module ") else { continue }
			return String(trimmed.dropFirst("module ".count)).trimmingCharacters(in: .whitespaces)
		}
		return nil
	}

	/// Package directories containing `package main`, relative to the root.
	///
	/// Reported so the user can pick when a repository ships several commands,
	/// which is the normal shape for a Go project of any size.
	public static func findMainPackages(in root: URL, limit: Int = 20) -> [String] {
		var results: [String] = []
		let skipped: Set<String> = ["vendor", ".git", "node_modules", "testdata"]

		guard let enumerator = FileManager.default.enumerator(
			at: root,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles]
		) else { return [] }

		for case let url as URL in enumerator {
			if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
				if skipped.contains(url.lastPathComponent) { enumerator.skipDescendants() }
				continue
			}
			guard url.pathExtension == "go", !url.lastPathComponent.hasSuffix("_test.go") else { continue }
			guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
			guard declaresPackageMain(contents) else { continue }

			let directory = url.deletingLastPathComponent()
			let relative = relativePath(of: directory, from: root)
			if !results.contains(relative) { results.append(relative) }
			if results.count >= limit { break }
		}
		return results.sorted()
	}

	/// Checks for `package main` outside comments.
	static func declaresPackageMain(_ source: String) -> Bool {
		for line in source.components(separatedBy: .newlines) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.hasPrefix("//") { continue }
			// The package clause is always the first non-comment statement.
			if trimmed.hasPrefix("package ") {
				return trimmed == "package main" || trimmed.hasPrefix("package main ")
			}
		}
		return false
	}

	static func relativePath(of url: URL, from root: URL) -> String {
		let base = root.standardizedFileURL.path
		let path = url.standardizedFileURL.path
		if path == base { return "." }
		if path.hasPrefix(base + "/") { return "./" + String(path.dropFirst(base.count + 1)) }
		return path
	}

	// MARK: - Commands

	public struct Command: Equatable {
		public let title: String
		public let executable: String
		public let arguments: [String]

		public init(title: String, executable: String, arguments: [String]) {
			self.title = title
			self.executable = executable
			self.arguments = arguments
		}
	}

	public static func runCommand(executable: String, package: String) -> Command {
		Command(title: "Run", executable: executable, arguments: ["run", package])
	}

	public static func buildCommand(executable: String, package: String) -> Command {
		Command(title: "Build", executable: executable, arguments: ["build", "-v", package])
	}

	/// Tests with verbose output, so individual results appear as they run.
	public static func testCommand(executable: String, package: String = "./...") -> Command {
		Command(title: "Test", executable: executable, arguments: ["test", "-v", package])
	}

	/// Runs tests under the execution tracer and opens the trace viewer.
	///
	/// Two steps chained through a shell because `go tool trace` needs the file
	/// the first command produces. The viewer serves a local web UI and opens a
	/// browser, which is how Go's tracing has always been consumed.
	public static func traceCommand(executable: String, package: String = "./...") -> Command {
		let quoted = shellQuote(executable)
		let script = """
		set -e
		echo "Running \(package) under the execution tracer…"
		\(quoted) test -trace /tmp/ideai-go-trace.out \(shellQuote(package))
		echo
		echo "Opening the trace viewer. Press ctrl-c here when finished."
		\(quoted) tool trace /tmp/ideai-go-trace.out
		"""
		return Command(title: "Trace", executable: "/bin/sh", arguments: ["-c", script])
	}

	/// Profiles CPU usage while running the tests, then opens pprof.
	public static func profileCommand(executable: String, package: String = "./...") -> Command {
		let quoted = shellQuote(executable)
		let script = """
		set -e
		echo "Collecting a CPU profile for \(package)…"
		\(quoted) test -cpuprofile /tmp/ideai-go-cpu.prof -bench=. -run=^$ \(shellQuote(package))
		echo
		\(quoted) tool pprof -top /tmp/ideai-go-cpu.prof
		"""
		return Command(title: "Profile", executable: "/bin/sh", arguments: ["-c", script])
	}

	/// Debugs under Delve, in its terminal UI.
	///
	/// Delve's own TUI rather than a native debugger panel: it is fully featured
	/// today, and the terminal already hosts it properly. A native front end
	/// would need a DAP client and its own breakpoint, stack and variable views.
	public static func debugCommand(delve: String, package: String) -> Command {
		Command(title: "Debug", executable: delve, arguments: ["debug", package])
	}

	public static func findDelveExecutable() -> String? {
		let candidates = [
			"/opt/homebrew/bin/dlv",
			"/usr/local/bin/dlv",
			NSHomeDirectory() + "/go/bin/dlv",
		]
		return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
	}

	static func shellQuote(_ value: String) -> String {
		"'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}
}
