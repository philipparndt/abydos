import Foundation

/// The `claude` command, found and run.
///
/// Shared by the commit draft and the hex editor's ask, which are the two
/// places this app asks Claude a question in prose. **Through the command
/// rather than the API**: this app already meets Claude in its terminals and
/// through `ClaudeHookRunner`; the API would add a dependency and a credential
/// path to something that has neither. When the command is not there the
/// feature is *absent* rather than failing when pressed, so callers ask
/// `isAvailable` before showing a button.
public enum ClaudeCommand {
	/// The places to look besides the `PATH`.
	///
	/// A parameter so a test can say "nowhere" and mean it: these are absolute
	/// and exist on the machine the suite runs on, so an empty `PATH` alone
	/// does not describe a machine without the command.
	public static func fallbackPlaces(
		home: URL = FileManager.default.homeDirectoryForCurrentUser
	) -> [URL] {
		[
			home.appendingPathComponent(".local/bin"),
			home.appendingPathComponent(".claude/local"),
			URL(fileURLWithPath: "/opt/homebrew/bin"),
			URL(fileURLWithPath: "/usr/local/bin"),
		]
	}

	/// Where the command is, or nil when it is not anywhere.
	///
	/// The `PATH` this process has, and then the places a per-user install puts
	/// it — a GUI app launched from Finder does not inherit the shell's `PATH`,
	/// so looking only there would say "not installed" on most machines that
	/// have it.
	public static func executable(
		environment: [String: String] = ProcessInfo.processInfo.environment,
		besides extra: [URL]? = nil
	) -> URL? {
		var places = (environment["PATH"] ?? "")
			.split(separator: ":")
			.map { URL(fileURLWithPath: String($0)) }
		places += extra ?? fallbackPlaces()

		for place in places {
			let candidate = place.appendingPathComponent("claude")
			if FileManager.default.isExecutableFile(atPath: candidate.path) {
				return candidate
			}
		}
		return nil
	}

	public static var isAvailable: Bool { executable() != nil }

	public struct Outcome: Sendable {
		public let stdout: String
		public let stderr: String
		public let exitCode: Int32
	}

	/// Runs `claude -p` with the prompt on standard input.
	///
	/// On stdin rather than as an argument: a staged diff or a hex dump is
	/// tens of thousands of characters and an argument list has a limit that
	/// walks straight through. Cancelling the task terminates the process,
	/// which is how a second ask cancels the first.
	public static func run(
		_ command: URL,
		prompt: String,
		in root: URL,
		arguments: [String] = ["-p"]
	) async -> Outcome {
		let process = Process()
		process.executableURL = command
		process.arguments = arguments
		process.currentDirectoryURL = root

		return await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				DispatchQueue.global(qos: .userInitiated).async {
					let out = Pipe(), err = Pipe(), input = Pipe()
					process.standardOutput = out
					process.standardError = err
					process.standardInput = input

					do {
						try process.run()
					} catch {
						continuation.resume(returning: Outcome(stdout: "", stderr: "\(error)", exitCode: -1))
						return
					}

					// Written on a thread of its own and both pipes drained
					// together: a program blocked writing to a pipe nobody is
					// reading deadlocks against a reader waiting for it to
					// finish. The same lesson `ProcessPipes` records, and the
					// same several afternoons.
					DispatchQueue.global(qos: .utility).async {
						input.fileHandleForWriting.write(Data(prompt.utf8))
						try? input.fileHandleForWriting.close()
					}
					var problem = Data()
					let drain = DispatchGroup()
					drain.enter()
					DispatchQueue.global(qos: .utility).async {
						problem = err.fileHandleForReading.readDataToEndOfFile()
						drain.leave()
					}
					let data = out.fileHandleForReading.readDataToEndOfFile()
					drain.wait()
					process.waitUntilExit()
					continuation.resume(returning: Outcome(
						stdout: String(decoding: data, as: UTF8.self),
						stderr: String(decoding: problem, as: UTF8.self),
						exitCode: process.terminationStatus
					))
				}
			}
		} onCancel: {
			if process.isRunning { process.terminate() }
		}
	}
}
