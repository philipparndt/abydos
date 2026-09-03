import Foundation

/// A file as git holds it, as bytes.
///
/// `GitHistory.contents` reads `git show <rev>:<path>` as text, which is what
/// every caller until now wanted. A picture diff wants the bytes: a PNG run
/// through `String(decoding:as: UTF8.self)` is not a PNG any more. So the same
/// command, drained as data.
public enum GitBlob {
	/// The file at a revision — `HEAD`, a hash, or the empty string for the
	/// index, which git spells `:<path>`. Nil when git has no such blob.
	public static func read(_ rev: String, path: String, in root: URL) async -> Data? {
		let result = await GitRepository.runData(["show", "\(rev):\(path)"], in: root)
		return result.exitCode == 0 ? result.stdout : nil
	}

	/// The working file, read the same way so the two sides of a diff come
	/// from one place. Nil when there is no such file.
	public static func readWorkingFile(_ path: String, in root: URL) -> Data? {
		try? Data(contentsOf: root.appendingPathComponent(path))
	}
}

public extension GitRepository {
	/// Runs a git subcommand and hands back its output as bytes.
	///
	/// `run` decodes stdout as UTF-8, which is right for everything git says
	/// about a repository and wrong for a blob that is a picture. The same
	/// process plumbing, drained as data; stderr is dropped, since a caller
	/// asking for bytes has one question and the exit code answers it.
	static func runData(_ arguments: [String], in directory: URL) async -> (stdout: Data, exitCode: Int32) {
		await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				let process = Process()
				process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
				process.arguments = arguments
				process.currentDirectoryURL = directory
				var env = ProcessInfo.processInfo.environment
				env["GIT_TERMINAL_PROMPT"] = "0"
				env["GIT_OPTIONAL_LOCKS"] = "0"
				process.environment = env
				let out = Pipe()
				process.standardOutput = out
				process.standardError = FileHandle.nullDevice
				process.standardInput = FileHandle.nullDevice
				do {
					try process.run()
				} catch {
					continuation.resume(returning: (Data(), -1))
					return
				}
				let data = ProcessPipes.drain(process, out: out)
				continuation.resume(returning: (data, process.terminationStatus))
			}
		}
	}
}
