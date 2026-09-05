import Foundation

/// The `sops` command, for a file that is already its own.
///
/// Two calls and both through pipes: a decrypt reads the plaintext from
/// `sops`'s standard output, an encrypt writes it to `sops`'s standard input.
/// Nothing here takes a path for the plaintext, which is the whole of the
/// constraint this was written under — the decrypted contents are not
/// persisted to any temp folder or anything like it. `helmsec`'s `.dec` file
/// and SOPS's own editor mode (which writes a temp file for the editor) were
/// both ruled out for the same reason.
public enum Sops {
	/// Where `sops` is, or nil.
	///
	/// `ABYDOS_SOPS` names the one to run, as `ABYDOS_GH` does for `gh`: it is
	/// how a driven run stands a fake in for the not-installed and refused
	/// cases, which a machine with the real thing on it cannot otherwise show.
	public static func locate() -> String? {
		if let named = ProcessInfo.processInfo.environment["ABYDOS_SOPS"], !named.isEmpty {
			return FileManager.default.isExecutableFile(atPath: named) ? named : nil
		}
		return Executables.locate("sops")
	}

	public static var isAvailable: Bool { locate() != nil }

	/// `sops --decrypt <file>`: the plaintext on stdout.
	public static func decryptArguments(for file: URL) -> [String] {
		["--decrypt", file.path]
	}

	/// `sops --encrypt` from stdin, under the file's own name.
	///
	/// `--filename-override` is what lets the project's `.sops.yaml` creation
	/// rules match a file that is arriving as stdin; it is in `sops` since 3.9.
	/// The format is said twice because stdin has no extension to say it.
	public static func encryptArguments(for file: URL, format: String) -> [String] {
		[
			"--encrypt", "--input-type", format, "--output-type", format,
			"--filename-override", file.path, "/dev/stdin",
		]
	}

	public static func decrypt(_ file: URL) async -> GitRepository.ProcessResult {
		await run(decryptArguments(for: file), in: file.deletingLastPathComponent(), input: nil)
	}

	/// Encrypts `text` as the file's format; the ciphertext is on stdout.
	public static func encrypt(_ text: String, for file: URL) async -> GitRepository.ProcessResult {
		guard let format = SopsFile.format(for: file) else {
			return GitRepository.ProcessResult(
				stdout: "", stderr: "\(file.lastPathComponent) is not a format sops handles", exitCode: -1
			)
		}
		return await run(
			encryptArguments(for: file, format: format),
			in: file.deletingLastPathComponent(), input: Data(text.utf8)
		)
	}

	/// The same, on the calling thread — for quitting, where there is no run
	/// loop left to come back to.
	public static func encryptSync(_ text: String, for file: URL) -> GitRepository.ProcessResult {
		guard let format = SopsFile.format(for: file) else {
			return GitRepository.ProcessResult(
				stdout: "", stderr: "\(file.lastPathComponent) is not a format sops handles", exitCode: -1
			)
		}
		return runSync(
			encryptArguments(for: file, format: format),
			in: file.deletingLastPathComponent(), input: Data(text.utf8)
		)
	}

	public static func run(
		_ arguments: [String], in directory: URL, input: Data?
	) async -> GitRepository.ProcessResult {
		await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				continuation.resume(returning: runSync(arguments, in: directory, input: input))
			}
		}
	}

	static func runSync(
		_ arguments: [String], in directory: URL, input: Data?
	) -> GitRepository.ProcessResult {
		runSync(arguments, in: directory, input: input, tool: locate())
	}

	/// The same with the tool named, so a test can say "nowhere" and mean it.
	static func runSyncForTesting(_ arguments: [String], tool: String?) -> GitRepository.ProcessResult {
		runSync(arguments, in: URL(fileURLWithPath: "/"), input: nil, tool: tool)
	}

	private static func runSync(
		_ arguments: [String], in directory: URL, input: Data?, tool: String?
	) -> GitRepository.ProcessResult {
		guard let tool else {
			return GitRepository.ProcessResult(stdout: "", stderr: "sops is not installed", exitCode: -1)
		}
		let process = Process()
		process.executableURL = URL(fileURLWithPath: tool)
		process.arguments = arguments
		process.currentDirectoryURL = directory
		// The process's own environment: `sops` finds an age key where it always
		// does on this platform — `~/Library/Application Support/sops/age/keys.txt`
		// — and a `SOPS_AGE_KEY_FILE` set in a shell profile is not seen by a
		// GUI app, which is said in the notes rather than worked around here.
		process.environment = ProcessInfo.processInfo.environment

		let out = Pipe(), err = Pipe(), stdin = Pipe()
		process.standardOutput = out
		process.standardError = err
		process.standardInput = stdin
		do {
			try process.run()
		} catch {
			return GitRepository.ProcessResult(stdout: "", stderr: "\(error)", exitCode: -1)
		}
		let captured = ProcessPipes.drainText(process, out: out, err: err, input: input, stdin: stdin)
		return GitRepository.ProcessResult(
			stdout: captured.stdout, stderr: captured.stderr, exitCode: process.terminationStatus
		)
	}
}
