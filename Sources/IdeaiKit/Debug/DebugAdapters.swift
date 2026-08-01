import Foundation

/// How to start a debug adapter, and what to tell it.
///
/// The protocol is the same whichever debugger is behind it — that is the
/// point of it — so what differs between Go and everything else is a handful
/// of strings: which program to run, whether it speaks over a socket or over
/// its own standard input, and the shape of the launch request. Keeping that
/// here is what stops the debugger being Go-only.
public struct DebugAdapter: Equatable, Sendable {
	/// How the adapter is spoken to.
	public enum Transport: Equatable, Sendable {
		/// Framed messages over the adapter's stdin and stdout.
		case standardIO
		/// The adapter listens on a port and prints it; we dial in.
		case socket
	}

	public let id: String
	public let name: String
	public let command: String
	public let arguments: [String]
	public let transport: Transport
	/// What the adapter calls itself in the initialize request. Adapters branch
	/// on this, so it has to be the name each one expects.
	public let adapterID: String
	/// Where to get it, in the one sentence somebody needs when it is missing.
	public let installHint: String

	public init(
		id: String,
		name: String,
		command: String,
		arguments: [String],
		transport: Transport,
		adapterID: String,
		installHint: String
	) {
		self.id = id
		self.name = name
		self.command = command
		self.arguments = arguments
		self.transport = transport
		self.adapterID = adapterID
		self.installHint = installHint
	}
}

/// The debuggers this app knows how to drive.
public enum DebugAdapters {
	/// Delve, which is Go's debugger and understands goroutines and Go's own
	/// types in a way nothing else does.
	public static let delve = DebugAdapter(
		id: "delve",
		name: "Delve",
		command: "dlv",
		// A server rather than a stdio adapter: writing to its stdin reaches
		// nothing, so it is given a port and dialled.
		arguments: ["dap", "--listen=127.0.0.1:0"],
		transport: .socket,
		adapterID: "go",
		installHint: "go install github.com/go-delve/delve/cmd/dlv@latest"
	)

	/// LLDB, for everything compiled to a native binary — C, C++, Rust, Swift,
	/// Zig, and anything else that produces one.
	public static let lldb = DebugAdapter(
		id: "lldb",
		name: "LLDB",
		command: "lldb-dap",
		arguments: [],
		transport: .standardIO,
		adapterID: "lldb",
		installHint: "Comes with Xcode; also in LLVM as lldb-dap."
	)

	public static let all: [DebugAdapter] = [delve, lldb]

	public static func adapter(id: String) -> DebugAdapter? {
		all.first { $0.id == id }
	}

	/// Which debugger suits a program, by what it is.
	///
	/// A Go module gets Delve; a native executable gets LLDB. Deciding by the
	/// project rather than asking is what makes "debug this" a single action
	/// instead of a form to fill in.
	public static func adapter(forProgramAt path: String, projectRoot: URL) -> DebugAdapter {
		let directory = (path as NSString).isAbsolutePath
			? URL(fileURLWithPath: path)
			: projectRoot.appendingPathComponent(path)

		// A go.mod anywhere between the program and the project root means Go.
		var cursor = directory.hasDirectoryPath ? directory : directory.deletingLastPathComponent()
		let root = projectRoot.standardizedFileURL.path
		while cursor.path.hasPrefix(root) || cursor.path == root {
			if FileManager.default.fileExists(atPath: cursor.appendingPathComponent("go.mod").path) {
				return delve
			}
			let parent = cursor.deletingLastPathComponent()
			if parent.path == cursor.path { break }
			cursor = parent
		}
		return lldb
	}

	/// Where the adapter's executable is, or nil if it is not installed.
	///
	/// The same explicit search the language servers need, and for the same
	/// reason: a GUI app inherits almost nothing of a login shell's `PATH`.
	public static func executable(for adapter: DebugAdapter) -> String? {
		for directory in LanguageServers.searchPaths {
			let candidate = (directory as NSString).appendingPathComponent(adapter.command)
			if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
		}
		// LLDB's adapter ships inside Xcode rather than on the path.
		return xcrunPath(for: adapter.command)
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

	/// The launch request for a program, in the shape its adapter expects.
	public static func launchArguments(
		for adapter: DebugAdapter,
		program: String,
		workingDirectory: String,
		arguments: [String] = []
	) -> [String: Any] {
		var request: [String: Any] = [
			"request": "launch",
			"program": program,
			"cwd": workingDirectory,
		]
		if !arguments.isEmpty { request["args"] = arguments }

		switch adapter.id {
		case delve.id:
			// Delve builds what it is pointed at, so `program` is a package
			// directory and the mode says to compile it first.
			request["mode"] = "debug"
		case lldb.id:
			// LLDB debugs a binary that already exists, and stopping at the
			// entry point would strand somebody in the C runtime.
			request["stopOnEntry"] = false
		default:
			break
		}
		return request
	}

	/// The attach request for a running process.
	public static func attachArguments(for adapter: DebugAdapter, pid: Int) -> [String: Any] {
		switch adapter.id {
		case delve.id:
			return ["request": "attach", "mode": "local", "processId": pid]
		default:
			return ["request": "attach", "pid": pid]
		}
	}
}
