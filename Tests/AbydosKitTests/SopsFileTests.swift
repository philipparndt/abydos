import Foundation
import Testing
@testable import AbydosKit

/// Which files are SOPS's, decided by looking rather than by name.
struct SopsFileTests {
	private let encrypted = """
	db:
	    password: ENC[AES256_GCM,data:abc,iv:def,tag:ghi,type:str]
	sops:
	    age:
	        - recipient: age1abc
	    version: 3.13.3
	"""

	@Test func anEncryptedYamlIsOne() {
		#expect(SopsFile.looksEncrypted(name: "secrets-dev.yaml", contents: encrypted))
		#expect(SopsFile.looksEncrypted(name: "secrets.yml", contents: encrypted))
	}

	@Test func aYamlWithASopsKeyAndNoCiphertextIsNot() {
		let plain = "sops:\n    version: 3\ndb:\n    password: hunter2\n"
		#expect(!SopsFile.looksEncrypted(name: "values.yaml", contents: plain))
	}

	@Test func ciphertextInAStringWithNoBlockIsNot() {
		let fixture = "example: \"ENC[AES256_GCM,data:x,type:str]\"\nnotes: a fixture\n"
		#expect(!SopsFile.looksEncrypted(name: "fixture.yaml", contents: fixture))
	}

	@Test func aNestedSopsKeyIsNotTheBlock() {
		let nested = "x: ENC[AES256_GCM,data:x,type:str]\nmeta:\n    sops: true\n"
		#expect(!SopsFile.looksEncrypted(name: "a.yaml", contents: nested))
	}

	@Test func aTxtIsNotHoweverItReads() {
		#expect(!SopsFile.looksEncrypted(name: "secrets.txt", contents: encrypted))
	}

	@Test func aJsonFileIsDecidedByItsQuotedKey() {
		let json = "{\n  \"token\": \"ENC[AES256_GCM,data:x,type:str]\",\n  \"sops\": {\"version\": \"3.13.3\"}\n}\n"
		#expect(SopsFile.looksEncrypted(name: "secrets.json", contents: json))
	}

	/// SOPS writes its block last, so the block of a long file sits past
	/// any head-sized look.
	@Test func theBlockAtTheEndOfALongFileIsStillFound() {
		var lines = (0..<3000).map { "key\($0): ENC[AES256_GCM,data:value\($0),type:str]" }
		lines.append("sops:")
		lines.append("    version: 3.13.3")
		let contents = lines.joined(separator: "\n")
		#expect(contents.utf8.count > 8 * 1024)
		#expect(contents.utf8.count < SopsFile.inspectedBytes)
		#expect(SopsFile.looksEncrypted(name: "big.yaml", contents: contents))
	}

	@Test func theFormatWordIsSopsOwn() {
		#expect(SopsFile.format(for: URL(fileURLWithPath: "/p/a.yml")) == "yaml")
		#expect(SopsFile.format(for: URL(fileURLWithPath: "/p/.env")) == "dotenv")
		#expect(SopsFile.format(for: URL(fileURLWithPath: "/p/a.ini")) == "ini")
		#expect(SopsFile.format(for: URL(fileURLWithPath: "/p/a.txt")) == nil)
	}

	/// The two command lines, so that a change to either is a test that fails.
	@Test func theCommandLinesAreWhatSopsExpects() {
		let file = URL(fileURLWithPath: "/p/secrets.yaml")
		#expect(Sops.decryptArguments(for: file) == ["--decrypt", "/p/secrets.yaml"])
		#expect(Sops.encryptArguments(for: file, format: "yaml") == [
			"--encrypt", "--input-type", "yaml", "--output-type", "yaml",
			"--filename-override", "/p/secrets.yaml", "/dev/stdin",
		])
	}

	/// Nothing here runs `sops`; the not-installed answer is a sentence and an
	/// exit code, which is what the chip and the toast are built from.
	@Test func aMachineWithoutSopsSaysSo() {
		let result = Sops.runSyncForTesting(["--version"], tool: nil)
		#expect(result.exitCode == -1)
		#expect(result.stderr == "sops is not installed")
	}
}

/// A decrypted buffer parked while its project is not in the window.
struct DecryptedBuffersTests {
	private let a = URL(fileURLWithPath: "/p/a")
	private let b = URL(fileURLWithPath: "/p/b")
	private let file = URL(fileURLWithPath: "/p/a/secrets.yaml")
	private let buffer = DecryptedBuffer(text: "k: v\n", isEdited: true, caretLine: 0)

	@Test func parkedForOneProjectIsNotFoundForAnother() {
		let park = DecryptedBuffers()
		park.park(buffer, root: a, file: file)
		#expect(park.take(root: b, file: file) == nil)
		#expect(park.take(root: a, file: file) == buffer)
	}

	@Test func takingEmptiesTheSlot() {
		let park = DecryptedBuffers()
		park.park(buffer, root: a, file: file)
		#expect(park.take(root: a, file: file) == buffer)
		#expect(park.take(root: a, file: file) == nil)
		#expect(park.isEmpty)
	}

	@Test func aLaterParkReplaces() {
		let park = DecryptedBuffers()
		park.park(buffer, root: a, file: file)
		let newer = DecryptedBuffer(text: "k: w\n", isEdited: true, caretLine: 1)
		park.park(newer, root: a, file: file)
		#expect(park.take(root: a, file: file) == newer)
	}

	/// A buffer edited and undone back to the decrypt's own text parks with
	/// its baseline and the baseline comes back with it — the round trip is
	/// what lets a save after the switch skip the encrypt, which `isEdited`
	/// alone would never say.
	@Test func theBaselineSurvivesThePark() {
		let park = DecryptedBuffers()
		let undone = DecryptedBuffer(
			text: "k: v\n", isEdited: true, caretLine: 0, baseline: "k: v\n"
		)
		park.park(undone, root: a, file: file)
		#expect(park.take(root: a, file: file)?.baseline == "k: v\n")
	}

	@Test func aTrailingSlashIsTheSameRoot() {
		let park = DecryptedBuffers()
		park.park(buffer, root: URL(fileURLWithPath: "/p/a/"), file: file)
		#expect(park.take(root: a, file: file) == buffer)
	}

	/// Quitting asks about the edited ones only; the ciphertext of an
	/// unedited one is on disk already.
	@Test func onlyEditedBuffersAreAskedAbout() {
		let park = DecryptedBuffers()
		park.park(DecryptedBuffer(text: "k: v\n", isEdited: false, caretLine: 0), root: a, file: file)
		park.park(buffer, root: b, file: URL(fileURLWithPath: "/p/b/x.env"))
		let asked = park.edited()
		#expect(asked.map(\.file.path) == ["/p/b/x.env"])
		#expect(asked.first?.root.path == "/p/b")
	}
}
