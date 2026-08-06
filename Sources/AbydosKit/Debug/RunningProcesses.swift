import Foundation

/// A process that could be attached to.
public struct RunningProcess: Equatable, Sendable, Identifiable {
	public let pid: Int
	/// The executable's name, which is what somebody recognises it by.
	public let name: String
	/// Its full path, which is what decides which debugger to use.
	public let path: String

	public var id: Int { pid }

	public init(pid: Int, name: String, path: String) {
		self.pid = pid
		self.name = name
		self.path = path
	}
}

/// What is running, for attaching to.
public enum RunningProcesses {
	/// Processes worth offering, most recently started first.
	///
	/// Only this user's, and only things that look like programs somebody
	/// wrote: a list containing every daemon on the machine is a list nobody
	/// can find anything in.
	public static func list(limit: Int = 200) -> [RunningProcess] {
		let output = run(["/bin/ps", "-x", "-o", "pid=,comm="])
		guard !output.isEmpty else { return [] }
		return parse(output, limit: limit)
	}

	static func parse(_ text: String, limit: Int = 200) -> [RunningProcess] {
		var processes: [RunningProcess] = []
		let ownPID = Int(ProcessInfo.processInfo.processIdentifier)

		for line in text.split(separator: "\n") {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard let space = trimmed.firstIndex(of: " "),
			      let pid = Int(trimmed[trimmed.startIndex..<space])
			else { continue }

			let path = String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
			guard !path.isEmpty, pid != ownPID else { continue }

			// System processes are noise: nobody attaches a debugger to
			// WindowServer, and there are hundreds of them.
			guard !path.hasPrefix("/System/"), !path.hasPrefix("/usr/libexec/"),
			      !path.hasPrefix("/usr/sbin/"), !path.hasPrefix("/Library/Apple/")
			else { continue }

			processes.append(RunningProcess(
				pid: pid, name: (path as NSString).lastPathComponent, path: path
			))
		}

		// Newest first: a process started to be debugged has a high pid.
		return Array(processes.sorted { $0.pid > $1.pid }.prefix(limit))
	}

	private static func run(_ arguments: [String]) -> String {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: arguments[0])
		process.arguments = Array(arguments.dropFirst())

		let output = Pipe()
		process.standardOutput = output
		process.standardError = Pipe()

		guard (try? process.run()) != nil else { return "" }
		let data = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return String(data: data, encoding: .utf8) ?? ""
	}
}
