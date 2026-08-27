import Testing
import Foundation
@testable import AbydosKit

/// Reading which submodules a repository has, from what git actually prints.
struct GitSubmoduleInventoryTests {
	/// `git ls-files --stage -z` over a superproject: gitlinks are mode 160000
	/// and everything else in the index is not.
	@Test func onlyGitlinksAreSubmodules() {
		let output = [
			"100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0\t.gitmodules",
			"100644 a1b2c3d4e5f60718293a4b5c6d7e8f9012345678 0\tREADME.md",
			"160000 70e7a598b14c5bcca5cfa1b4a66e2c4004e2b17e 0\tsvc-3",
			"160000 c47961a6909e345f62eb83c998ad67773b4298ac 0\tsvc-47",
		].joined(separator: "\0") + "\0"

		let found = GitSubmodules.parseStage(output)
		#expect(found.map(\.path) == ["svc-3", "svc-47"])
		#expect(found[0].commit == "70e7a598b14c5bcca5cfa1b4a66e2c4004e2b17e")
	}

	/// `-z` is asked for so that a path git would otherwise escape stays a path
	/// something else can find — the reason `GitWorkingCopy.status` asks for it.
	@Test func aPathThatIsNotAsciiSurvives() {
		let output = "160000 70e7a598b14c5bcca5cfa1b4a66e2c4004e2b17e 0\tdienste/kühlschrank\0"
		#expect(GitSubmodules.parseStage(output).map(\.path) == ["dienste/kühlschrank"])
	}

	@Test func aPathWithSpacesInItIsOnePath() {
		let output = "160000 70e7a598b14c5bcca5cfa1b4a66e2c4004e2b17e 0\tmy services/svc one\0"
		#expect(GitSubmodules.parseStage(output).map(\.path) == ["my services/svc one"])
	}

	@Test func anIndexWithNoGitlinksIsNoEstate() {
		let output = "100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0\tREADME.md\0"
		#expect(GitSubmodules.parseStage(output).isEmpty)
	}

	// MARK: - .gitmodules

	@Test func gitmodulesIsKeyedByThePathItGives() {
		let output = [
			"submodule.svc-3.path\nsvc-3",
			"submodule.svc-3.url\nhttps://example.invalid/acme/svc-3.git",
			"submodule.svc-47.path\nsvc-47",
			"submodule.svc-47.url\n../pool/svc-47",
		].joined(separator: "\0") + "\0"

		let configured = GitSubmodules.parseGitmodules(output)
		#expect(configured["svc-3"]?.name == "svc-3")
		#expect(configured["svc-3"]?.url == "https://example.invalid/acme/svc-3.git")
		#expect(configured["svc-47"]?.url == "../pool/svc-47")
	}

	/// A submodule's name may hold dots. Taking the second component as the name
	/// would call this one `com`, and then match nothing against the index.
	@Test func aNameMayHoldDots() {
		let output = "submodule.github.com/acme/svc.path\ndienste/svc\0"
		let configured = GitSubmodules.parseGitmodules(output)
		#expect(configured["dienste/svc"]?.name == "github.com/acme/svc")
	}

	/// The path is where a submodule is; the name is what somebody called it.
	/// A rename leaves them differing, and only one of them matches the index.
	@Test func aNameThatIsNotItsPathStillMatches() {
		let output = [
			"submodule.old-name.path\ndienste/new-place",
			"submodule.old-name.url\n../pool/svc",
		].joined(separator: "\0") + "\0"
		let configured = GitSubmodules.parseGitmodules(output)
		#expect(configured["dienste/new-place"]?.name == "old-name")
	}

	@Test func settingsThatAreNotPathOrUrlAreIgnored() {
		let output = [
			"submodule.svc-3.path\nsvc-3",
			"submodule.svc-3.branch\nmain",
			"submodule.svc-3.update\nrebase",
		].joined(separator: "\0") + "\0"
		let configured = GitSubmodules.parseGitmodules(output)
		#expect(configured.count == 1)
		#expect(configured["svc-3"]?.url == nil)
	}

	@Test func aMissingGitmodulesIsNoSubmodules() {
		#expect(GitSubmodules.parseGitmodules("").isEmpty)
	}
}
