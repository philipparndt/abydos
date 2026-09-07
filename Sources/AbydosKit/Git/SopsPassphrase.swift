import Darwin
import Foundation

/// A passphrase on its way to gpg, and nowhere else.
///
/// For a PGP recipient sops is a front end for gpg, and gpg needs the key's
/// passphrase. In a terminal the agent asks through a pinentry on the tty; an
/// app launched from the Dock has no tty, and unless a graphical pinentry is
/// installed and configured the ask fails inside gpg. sops runs whatever
/// `SOPS_GPG_EXEC` names, so the app names a wrapper that runs gpg with
/// `--pinentry-mode loopback --passphrase-fd 3`, and the passphrase goes down
/// a pipe whose read end *is* descriptor 3 in the child. It is never an
/// argument, never an environment variable, never a file.
///
/// **Spawned by hand, not through `Process`.** Foundation spawns its children
/// with close-on-exec for every descriptor but the standard three, so a pipe
/// cleared of `FD_CLOEXEC` in this process still did not reach the child —
/// measured before this was written: `sh: 3: Bad file descriptor`. A
/// `posix_spawn` with a `dup2` file action puts the read end at 3 in the child
/// and leaves everything else closed, which is also the right default for a
/// child that will hold a secret.
extension Sops {
	/// The descriptor gpg reads the passphrase from, in the child.
	public static let passphraseDescriptor: Int32 = 3

	/// The wrapper `SOPS_GPG_EXEC` names, written once and kept.
	///
	/// It holds no secret: it is a fixed script whose one job is the three
	/// arguments. `ABYDOS_GPG` lets a test and a driven run stand a fake gpg
	/// in, the way `ABYDOS_SOPS` does for sops.
	public static func gpgWrapper(
		in directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
			.first!.appendingPathComponent("Abydos", isDirectory: true)
	) throws -> URL {
		let url = directory.appendingPathComponent("gpg-with-passphrase.sh")
		let script = """
		#!/bin/sh
		# Written by Abydos: gpg with the key's passphrase read from the descriptor
		# Abydos holds open across sops, so it is never an argument or a file.
		exec "${ABYDOS_GPG:-gpg}" --batch --pinentry-mode loopback --passphrase-fd \(passphraseDescriptor) "$@"

		"""
		if let existing = try? String(contentsOf: url, encoding: .utf8), existing == script {
			return url
		}
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try script.write(to: url, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
		return url
	}

	// MARK: - Reading gpg's words

	/// Whether a failed decrypt failed for want of a passphrase: gpg could
	/// not run a pinentry, or the agent gave up asking. The phrases are gpg
	/// 2.4's and the agent's; a message outside them is some other failure
	/// and keeps the toast.
	public static func needsPassphrase(stderr: String) -> Bool {
		let lower = stderr.lowercased()
		let phrases = [
			"inappropriate ioctl for device",
			"no pinentry",
			"pinentry",
			"problem with the agent",
			"operation cancelled",
			"no passphrase given",
			"timeout",
		]
		return lower.contains("pgp") || lower.contains("gpg") || lower.contains("gnupg")
			? phrases.contains { lower.contains($0) } || wrongPassphrase(stderr: stderr)
			: false
	}

	/// Whether gpg said the passphrase it was given was wrong.
	public static func wrongPassphrase(stderr: String) -> Bool {
		stderr.lowercased().contains("bad passphrase")
	}

	/// The key gpg named, when it did: `ID 1234ABCD5678EF90` after
	/// *encrypted with … key*, so the field can say which key it is asking for.
	public static func keyNamed(in stderr: String) -> String? {
		let pattern = #"(?:key,? ID|ID) ([0-9A-Fa-f]{8,40})"#
		guard let regex = try? NSRegularExpression(pattern: pattern),
			  let match = regex.firstMatch(in: stderr, range: NSRange(stderr.startIndex..., in: stderr)),
			  let range = Range(match.range(at: 1), in: stderr)
		else { return nil }
		return String(stderr[range]).uppercased()
	}

	// MARK: - Running with a passphrase

	/// `sops --decrypt` with the passphrase on descriptor 3 of the child.
	public static func decrypt(_ file: URL, passphrase: String) async -> GitRepository.ProcessResult {
		await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				continuation.resume(returning: runWithPassphrase(
					decryptArguments(for: file), in: file.deletingLastPathComponent(),
					passphrase: passphrase, tool: locate(), gpg: nil, extraEnvironment: [:]
				))
			}
		}
	}

	/// The same with the tools named, so a test can stand fakes in.
	static func runWithPassphraseForTesting(
		_ arguments: [String], in directory: URL, passphrase: String,
		tool: String?, gpg: String?, extraEnvironment: [String: String] = [:]
	) -> GitRepository.ProcessResult {
		runWithPassphrase(arguments, in: directory, passphrase: passphrase, tool: tool, gpg: gpg, extraEnvironment: extraEnvironment)
	}

	private static func runWithPassphrase(
		_ arguments: [String], in directory: URL, passphrase: String,
		tool: String?, gpg: String?, extraEnvironment: [String: String]
	) -> GitRepository.ProcessResult {
		guard let tool else {
			return GitRepository.ProcessResult(stdout: "", stderr: "sops is not installed", exitCode: -1)
		}
		let wrapper: URL
		do {
			wrapper = try gpgWrapper()
		} catch {
			return GitRepository.ProcessResult(stdout: "", stderr: "could not write the gpg wrapper: \(error)", exitCode: -1)
		}
		var environment = toolEnvironment
		environment["SOPS_GPG_EXEC"] = wrapper.path
		if let gpg { environment["ABYDOS_GPG"] = gpg }
		for (key, value) in extraEnvironment { environment[key] = value }

		// Three pipes for the standard streams and one for the passphrase.
		var passphrasePipe: [Int32] = [0, 0], outPipe: [Int32] = [0, 0], errPipe: [Int32] = [0, 0]
		guard pipe(&passphrasePipe) == 0, pipe(&outPipe) == 0, pipe(&errPipe) == 0 else {
			return GitRepository.ProcessResult(stdout: "", stderr: "could not make a pipe", exitCode: -1)
		}

		var actions: posix_spawn_file_actions_t? = nil
		posix_spawn_file_actions_init(&actions)
		defer { posix_spawn_file_actions_destroy(&actions) }
		posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
		posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
		posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)
		posix_spawn_file_actions_adddup2(&actions, passphrasePipe[0], passphraseDescriptor)
		posix_spawn_file_actions_addchdir_np(&actions, directory.path)

		var attributes: posix_spawnattr_t? = nil
		posix_spawnattr_init(&attributes)
		defer { posix_spawnattr_destroy(&attributes) }
		// Everything not named above is closed in the child: a process about
		// to hold a passphrase should inherit nothing it was not given.
		posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

		let argv = ([tool] + arguments).map { strdup($0) } + [nil]
		let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
		defer {
			argv.forEach { free($0) }
			envp.forEach { free($0) }
		}
		var pid: pid_t = 0
		let spawned = posix_spawn(&pid, tool, &actions, &attributes, argv, envp)
		// The child has its ends; this side keeps the ones it reads and writes.
		close(outPipe[1])
		close(errPipe[1])
		close(passphrasePipe[0])
		guard spawned == 0 else {
			close(outPipe[0]); close(errPipe[0]); close(passphrasePipe[1])
			return GitRepository.ProcessResult(stdout: "", stderr: "could not start sops: \(String(cString: strerror(spawned)))", exitCode: -1)
		}

		// The passphrase, then a newline, then the end: gpg reads one line.
		let secret = Data((passphrase + "\n").utf8)
		secret.withUnsafeBytes { bytes in
			var written = 0
			while written < bytes.count {
				let count = write(passphrasePipe[1], bytes.baseAddress! + written, bytes.count - written)
				if count <= 0 { break }
				written += count
			}
		}
		close(passphrasePipe[1])

		// Both streams drained together, so a child blocked writing one never
		// waits on a reader stuck on the other — `ProcessPipes`' lesson.
		let group = DispatchGroup()
		var stdout = Data(), stderr = Data()
		for (descriptor, into) in [(outPipe[0], 0), (errPipe[0], 1)] {
			group.enter()
			DispatchQueue.global(qos: .utility).async {
				var collected = Data()
				var buffer = [UInt8](repeating: 0, count: 64 * 1024)
				while true {
					let count = read(descriptor, &buffer, buffer.count)
					if count <= 0 { break }
					collected.append(buffer, count: count)
				}
				close(descriptor)
				DispatchQueue.main.sync { if into == 0 { stdout = collected } else { stderr = collected } }
				group.leave()
			}
		}
		group.wait()
		var status: Int32 = 0
		waitpid(pid, &status, 0)
		let exitCode = (status & 0x7F) == 0 ? (status >> 8) & 0xFF : -1
		return GitRepository.ProcessResult(
			stdout: String(decoding: stdout, as: UTF8.self),
			stderr: String(decoding: stderr, as: UTF8.self),
			exitCode: exitCode
		)
	}
}

/// The passphrases that worked, for the sitting.
///
/// In memory and nowhere else: a map from the key that was unlocked — gpg's
/// key ID when it named one, the file's project root otherwise — to the
/// passphrase, gone when the app is. Lock-and-decrypt-again then asks
/// nothing; the person who typed it once this sitting is the person still
/// at the keyboard.
public final class Passphrases {
	public static let shared = Passphrases()

	private var kept: [String: String] = [:]
	private let lock = NSLock()

	public init() {}

	public func remember(_ passphrase: String, for key: String) {
		lock.lock(); defer { lock.unlock() }
		kept[key] = passphrase
	}

	public func passphrase(for key: String) -> String? {
		lock.lock(); defer { lock.unlock() }
		return kept[key]
	}

	public func forget(_ key: String) {
		lock.lock(); defer { lock.unlock() }
		kept[key] = nil
	}

	public func forgetAll() {
		lock.lock(); defer { lock.unlock() }
		kept.removeAll()
	}

	public var count: Int {
		lock.lock(); defer { lock.unlock() }
		return kept.count
	}
}
