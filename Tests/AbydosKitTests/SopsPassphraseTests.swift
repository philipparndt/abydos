import Foundation
import Testing
@testable import AbydosKit

/// A passphrase reaching gpg on a descriptor, and nothing else seeing it.
///
/// The claim under the fakes is the one the design makes: the pipe's read end
/// is descriptor 3 in sops, sops leaves it alone, and gpg reads it — two
/// execs down from the app. The fake sops runs `$SOPS_GPG_EXEC` as the real
/// one does; the fake gpg reads the descriptor `--passphrase-fd` names and
/// prints the *length* of what it read, never the text.
struct SopsPassphraseTests {
	private func scratch() throws -> URL {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent("passphrase-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	private func script(_ name: String, _ body: String, in root: URL) throws -> URL {
		let url = root.appendingPathComponent(name)
		try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
		return url
	}

	/// A sops that behaves as the real one does about gpg: runs whatever
	/// `SOPS_GPG_EXEC` names, with arguments of its own, and prints what came
	/// back as the "plaintext".
	private func fakes(in root: URL) throws -> (sops: URL, gpg: URL) {
		let sops = try script("sops", #"exec "$SOPS_GPG_EXEC" --decrypt "$@""#, in: root)
		let gpg = try script("gpg", """
		fd=""
		while [ $# -gt 0 ]; do
			if [ "$1" = "--passphrase-fd" ]; then fd="$2"; shift; fi
			shift
		done
		[ -n "$fd" ] || { echo "no --passphrase-fd" >&2; exit 2; }
		eval "read -r passphrase <&$fd" || { echo "fd $fd: cannot read" >&2; exit 3; }
		echo "gpg read ${#passphrase} characters on fd $fd"
		""", in: root)
		return (sops, gpg)
	}

	@Test func thePassphraseReachesGpgOnTheDescriptorAndIsNotPrinted() throws {
		let root = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		let (sops, gpg) = try fakes(in: root)
		let result = Sops.runWithPassphraseForTesting(
			["--decrypt", "secrets.yaml"], in: root, passphrase: "correct horse battery",
			tool: sops.path, gpg: gpg.path
		)
		#expect(result.exitCode == 0, "stderr: \(result.stderr)")
		#expect(result.stdout.contains("gpg read 21 characters on fd 3"))
		#expect(!result.stdout.contains("correct horse"))
		#expect(!result.stderr.contains("correct horse"))
	}

	/// The wrapper is a fixed script under the app's own directory, holding
	/// no secret, written once.
	@Test func theWrapperIsWrittenOnceAndNamesTheDescriptor() throws {
		let root = try scratch()
		defer { try? FileManager.default.removeItem(at: root) }
		let wrapper = try Sops.gpgWrapper(in: root)
		let text = try String(contentsOf: wrapper, encoding: .utf8)
		#expect(text.contains("--pinentry-mode loopback --passphrase-fd 3"))
		#expect(text.contains(#""${ABYDOS_GPG:-gpg}""#))
		let permissions = try FileManager.default.attributesOfItem(atPath: wrapper.path)[.posixPermissions] as? Int
		#expect(permissions == 0o700)
		let before = try FileManager.default.attributesOfItem(atPath: wrapper.path)[.modificationDate] as? Date
		Thread.sleep(forTimeInterval: 0.02)
		_ = try Sops.gpgWrapper(in: root)
		let after = try FileManager.default.attributesOfItem(atPath: wrapper.path)[.modificationDate] as? Date
		#expect(before == after)
	}

	/// gpg 2.4's words, recorded from a Dock-launched app with no pinentry.
	@Test func gpgsWordsForAMissingPinentryAreReadAsNeedingAPassphrase() {
		let noTTY = """
		gpg: encrypted with rsa4096 key, ID 8A1F2B3C4D5E6F70, created 2024-01-01
		      "Philipp <philipp@example.org>"
		gpg: public key decryption failed: Inappropriate ioctl for device
		gpg: decryption failed: No secret key
		Failed to get the data key required to decrypt the SOPS file.
		Group 0: FAILED
		  8A1F2B3C4D5E6F70: FAILED
		    - | failed to decrypt sops data key with pgp: exit status 2
		"""
		#expect(Sops.needsPassphrase(stderr: noTTY))
		#expect(Sops.keyNamed(in: noTTY) == "8A1F2B3C4D5E6F70")
		#expect(Sops.needsPassphrase(stderr: "gpg: problem with the agent: No pinentry\ngpg: decryption failed: No secret key"))
		#expect(Sops.needsPassphrase(stderr: "gpg: public key decryption failed: Operation cancelled"))
		#expect(Sops.needsPassphrase(stderr: "gpg: public key decryption failed: Bad passphrase"))
		#expect(Sops.wrongPassphrase(stderr: "gpg: public key decryption failed: Bad passphrase"))
	}

	/// A missing key, an age file, or sops not installed are not a passphrase
	/// question, and keep the toast.
	@Test func otherFailuresAreNotAPassphraseQuestion() {
		#expect(!Sops.needsPassphrase(stderr: "gpg: decryption failed: No secret key\nFailed to get the data key required to decrypt the SOPS file."))
		#expect(!Sops.needsPassphrase(stderr: "age: no identity matched any of the recipients"))
		#expect(!Sops.needsPassphrase(stderr: "sops is not installed"))
		#expect(Sops.keyNamed(in: "nothing here") == nil)
	}

	@Test func theKeepIsInMemoryForTheSitting() {
		let keep = Passphrases()
		keep.remember("hunter2", for: "8A1F2B3C4D5E6F70")
		#expect(keep.passphrase(for: "8A1F2B3C4D5E6F70") == "hunter2")
		#expect(keep.passphrase(for: "/p/other") == nil)
		keep.forget("8A1F2B3C4D5E6F70")
		#expect(keep.count == 0)
	}

	/// The real thing, where the machine has it: a key with a passphrase in a
	/// throwaway GNUPGHOME, a file encrypted to it, and a decrypt through the
	/// pipe — with a wrong passphrase refused in gpg's words first.
	@Test func aRealKeyWithAPassphraseDecryptsThroughThePipe() throws {
		guard let sops = Executables.locate("sops"), let gpg = Executables.locate("gpg"),
			  let gpgconf = Executables.locate("gpgconf") else {
			print("SopsPassphraseTests: gpg or sops is not on this machine; the live case is not run")
			return
		}
		let root = try scratch()
		// Under /tmp by name, not the temporary directory: the agent's socket
		// lives in the home, and a Unix socket path is capped at 104 bytes —
		// "can't connect to the gpg-agent: File name too long" otherwise.
		let home = URL(fileURLWithPath: "/tmp/abydos-gpg-\(UUID().uuidString.prefix(8))")
		try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)
		let environment = ["GNUPGHOME": home.path]
		defer {
			_ = run(gpgconf, ["--kill", "all"], in: root, environment: environment)
			try? FileManager.default.removeItem(at: root)
			try? FileManager.default.removeItem(at: home)
		}
		let passphrase = "correct horse battery staple"
		let made = run(gpg, ["--batch", "--pinentry-mode", "loopback", "--passphrase", passphrase, "--quick-gen-key", "abydos-test@example.org", "rsa2048", "encrypt", "0"], in: root, environment: environment)
		guard made.exitCode == 0 else {
			print("SopsPassphraseTests: could not make a key (\(made.stderr.prefix(200))); the live case is not run")
			return
		}
		let listed = run(gpg, ["--batch", "--with-colons", "--list-keys"], in: root, environment: environment)
		// The fingerprint is the tenth colon field, and the fields before it
		// are empty — so the split must keep empty pieces to count them.
		guard let fingerprint = listed.stdout.split(separator: "\n").first(where: { $0.hasPrefix("fpr:") })?
			.split(separator: ":", omittingEmptySubsequences: false).dropFirst(9).first.map(String.init), !fingerprint.isEmpty else {
			Issue.record("no fingerprint listed: \(listed.stdout)")
			return
		}
		let file = root.appendingPathComponent("secrets.yaml")
		try "db:\n    password: hunter2\n".write(to: file, atomically: true, encoding: .utf8)
		let encrypted = run(sops, ["--encrypt", "--in-place", "--pgp", fingerprint, file.path], in: root, environment: environment)
		guard encrypted.exitCode == 0 else {
			Issue.record("sops could not encrypt: \(encrypted.stderr)")
			return
		}
		// The agent holds nothing yet, so a wrong passphrase is refused in words.
		_ = run(gpgconf, ["--kill", "gpg-agent"], in: root, environment: environment)
		let wrong = Sops.runWithPassphraseForTesting(
			["--decrypt", file.path], in: root, passphrase: "not it", tool: sops, gpg: gpg, extraEnvironment: environment
		)
		#expect(wrong.exitCode != 0)
		#expect(Sops.needsPassphrase(stderr: wrong.stderr), "stderr: \(wrong.stderr.prefix(300))")
		let right = Sops.runWithPassphraseForTesting(
			["--decrypt", file.path], in: root, passphrase: passphrase, tool: sops, gpg: gpg, extraEnvironment: environment
		)
		#expect(right.exitCode == 0, "stderr: \(right.stderr.prefix(300))")
		#expect(right.stdout.contains("password: hunter2"))
	}

	private func run(_ tool: String, _ arguments: [String], in directory: URL, environment: [String: String]) -> GitRepository.ProcessResult {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: tool)
		process.arguments = arguments
		process.currentDirectoryURL = directory
		var merged = Sops.toolEnvironment
		for (key, value) in environment { merged[key] = value }
		process.environment = merged
		let out = Pipe(), err = Pipe()
		process.standardOutput = out
		process.standardError = err
		do { try process.run() } catch { return GitRepository.ProcessResult(stdout: "", stderr: "\(error)", exitCode: -1) }
		let captured = ProcessPipes.drainText(process, out: out, err: err)
		return GitRepository.ProcessResult(stdout: captured.stdout, stderr: captured.stderr, exitCode: process.terminationStatus)
	}
}
