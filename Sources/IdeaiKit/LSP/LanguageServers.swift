import Foundation

/// How to start a language server.
public struct LanguageServerDefinition: Equatable, Sendable {
	/// The languages it answers for, as the editor names them.
	public let languageIds: [String]
	/// The command, looked up on the path.
	public let command: String
	public let arguments: [String]
	/// Where to get it, said in the one sentence somebody needs when it is
	/// missing rather than left as "no language server found".
	public let installHint: String
	/// A file that marks the root of a project this server understands, so a
	/// Go server is not started for a repository with one `.go` file in a
	/// vendored directory.
	public let rootMarkers: [String]

	public init(
		languageIds: [String],
		command: String,
		arguments: [String] = [],
		installHint: String,
		rootMarkers: [String] = []
	) {
		self.languageIds = languageIds
		self.command = command
		self.arguments = arguments
		self.installHint = installHint
		self.rootMarkers = rootMarkers
	}
}

/// Which server answers for which language, and whether it is installed.
///
/// No server is bundled and none is installed on anybody's behalf. A language
/// server is a large program with opinions about your toolchain, and the one
/// already on the machine — the one matching the compiler actually being used
/// — is nearly always the right one.
public enum LanguageServers {
	public static let known: [LanguageServerDefinition] = [
		LanguageServerDefinition(
			languageIds: ["swift"],
			command: "sourcekit-lsp",
			installHint: "Comes with Xcode and with the Swift toolchain.",
			rootMarkers: ["Package.swift", "*.xcodeproj", "compile_commands.json"]
		),
		LanguageServerDefinition(
			languageIds: ["go"],
			command: "gopls",
			installHint: "go install golang.org/x/tools/gopls@latest",
			rootMarkers: ["go.mod", "go.work"]
		),
		LanguageServerDefinition(
			languageIds: ["rust"],
			command: "rust-analyzer",
			installHint: "rustup component add rust-analyzer",
			rootMarkers: ["Cargo.toml"]
		),
		LanguageServerDefinition(
			languageIds: ["typescript", "javascript", "tsx", "jsx"],
			command: "typescript-language-server",
			arguments: ["--stdio"],
			installHint: "npm install -g typescript-language-server typescript",
			rootMarkers: ["package.json", "tsconfig.json"]
		),
		LanguageServerDefinition(
			languageIds: ["python"],
			command: "pyright-langserver",
			arguments: ["--stdio"],
			installHint: "npm install -g pyright",
			rootMarkers: ["pyproject.toml", "setup.py", "requirements.txt"]
		),
		LanguageServerDefinition(
			languageIds: ["c", "cpp", "objc"],
			command: "clangd",
			installHint: "Comes with Xcode's toolchain, or: brew install llvm",
			rootMarkers: ["compile_commands.json", "CMakeLists.txt"]
		),
		LanguageServerDefinition(
			languageIds: ["json"],
			command: "vscode-json-language-server",
			arguments: ["--stdio"],
			installHint: "npm install -g vscode-langservers-extracted",
			rootMarkers: []
		),
	]

	public static func definition(forLanguage languageId: String) -> LanguageServerDefinition? {
		known.first { $0.languageIds.contains(languageId) }
	}

	/// Where the command lives, or nil if it is not installed.
	///
	/// A GUI app inherits almost nothing of a login shell's `PATH`, so the
	/// usual places are searched explicitly. Without this, everything works
	/// from a terminal and nothing works from the Dock.
	public static func executable(for definition: LanguageServerDefinition) -> String? {
		if definition.command.contains("/") {
			return FileManager.default.isExecutableFile(atPath: definition.command) ? definition.command : nil
		}

		for directory in searchPaths {
			let candidate = (directory as NSString).appendingPathComponent(definition.command)
			if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
		}

		// Swift's server is usually reached through xcrun rather than sitting
		// on the path at all.
		if definition.command == "sourcekit-lsp", let found = xcrunPath(for: "sourcekit-lsp") {
			return found
		}
		return nil
	}

	/// Directories searched for a server, in order.
	public static var searchPaths: [String] {
		var paths: [String] = []
		if let environment = ProcessInfo.processInfo.environment["PATH"] {
			paths += environment.split(separator: ":").map(String.init)
		}

		let home = FileManager.default.homeDirectoryForCurrentUser.path
		paths += [
			"/opt/homebrew/bin",
			"/usr/local/bin",
			"/usr/bin",
			"\(home)/go/bin",
			"\(home)/.cargo/bin",
			"\(home)/.local/bin",
			"\(home)/.bun/bin",
			"\(home)/.volta/bin",
		]

		var seen = Set<String>()
		return paths.filter { seen.insert($0).inserted }
	}

	private static func xcrunPath(for tool: String) -> String? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		process.arguments = ["--find", tool]
		let output = Pipe()
		process.standardOutput = output
		process.standardError = Pipe()

		guard (try? process.run()) != nil else { return nil }
		let data = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else { return nil }

		let path = String(data: data, encoding: .utf8)?
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		return FileManager.default.isExecutableFile(atPath: path) ? path : nil
	}

	/// Whether a project looks like one this server should be started for.
	///
	/// A server with no markers is happy anywhere; one with markers wants to
	/// see at least one of them, so opening a repository that happens to
	/// contain a stray `.py` file does not start a Python server for it.
	public static func suits(_ definition: LanguageServerDefinition, root: URL) -> Bool {
		guard !definition.rootMarkers.isEmpty else { return true }
		let manager = FileManager.default

		for marker in definition.rootMarkers {
			if marker.hasPrefix("*.") {
				let suffix = String(marker.dropFirst(1))
				let contents = (try? manager.contentsOfDirectory(atPath: root.path)) ?? []
				if contents.contains(where: { $0.hasSuffix(suffix) }) { return true }
			} else if manager.fileExists(atPath: root.appendingPathComponent(marker).path) {
				return true
			}
		}
		return false
	}

	/// The server to start for a language in a project, if there is one and it
	/// is installed.
	public static func resolve(
		languageId: String,
		root: URL
	) -> (definition: LanguageServerDefinition, executable: String)? {
		guard let definition = definition(forLanguage: languageId),
		      suits(definition, root: root),
		      let executable = executable(for: definition)
		else { return nil }
		return (definition, executable)
	}
}
