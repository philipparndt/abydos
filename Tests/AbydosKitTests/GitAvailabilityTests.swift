import Foundation
import Testing
@testable import AbydosKit

/// What the git shim says when it will not run git, told apart from what git
/// says when it runs.
struct GitAvailabilityTests {
	static let licence = GitRepository.ProcessResult(
		stdout: "",
		stderr: "You have not agreed to the Xcode license agreements. Please run 'sudo xcodebuild "
			+ "-license' from within a Terminal window to review and agree to the Xcode and Apple SDKs license.\n",
		exitCode: 0
	)
	static let tools = GitRepository.ProcessResult(
		stdout: "",
		stderr: "xcrun: error: invalid active developer path (/Library/Developer/CommandLineTools), "
			+ "missing xcrun at: /Library/Developer/CommandLineTools/usr/bin/xcrun\n",
		exitCode: 1
	)
	static let notARepository = GitRepository.ProcessResult(
		stdout: "", stderr: "fatal: not a git repository (or any of the parent directories): .git\n", exitCode: 128
	)
	static let version = GitRepository.ProcessResult(stdout: "git version 2.54.0 (Apple Git-157)\n", stderr: "", exitCode: 0)

	/// **The shim exits 0.** The exit code says nothing, so the sentence has to.
	@Test func theLicenceRefusalIsRecognisedAtExitZero() {
		#expect(Self.licence.exitCode == 0)
		#expect(GitAvailability.classify(Self.licence) == .licenceNotAccepted)
	}

	@Test func missingDeveloperToolsAreRecognised() {
		#expect(GitAvailability.classify(Self.tools) == .developerToolsMissing)
	}

	@Test func aFailureFromGitItselfIsNotARefusal() {
		#expect(GitAvailability.classify(Self.notARepository) == nil)
		#expect(GitAvailability.classify(Self.version) == nil)
	}

	@Test func eachCauseHasASentenceAndACommand() {
		#expect(GitAvailability.Cause.licenceNotAccepted.command == "sudo xcodebuild -license accept")
		#expect(GitAvailability.Cause.developerToolsMissing.command == "xcode-select --install")
		for cause in GitAvailability.Cause.allCases {
			#expect(cause.sentence.hasPrefix("git cannot run: "))
		}
	}

	@Test func aRefusalStopsGitRunningAndASuccessStartsItAgain() async {
		let availability = GitAvailability()
		#expect(availability.isRunning)
		availability.note(Self.licence)
		#expect(!availability.isRunning)
		#expect(availability.cause == .licenceNotAccepted)

		// Told once, with nil, when the answer changes back — and not for a
		// second refusal that changes nothing.
		availability.note(Self.licence)
		let told: GitAvailability.Cause? = await withCheckedContinuation { continuation in
			availability.observe { continuation.resume(returning: $0) }
			availability.note(Self.version)
		}
		#expect(told == nil)
		#expect(availability.isRunning)
	}

	@Test func aForcedCauseWinsOverWhatGitSays() {
		let availability = GitAvailability()
		availability.forcedCause = .developerToolsMissing
		availability.note(Self.version)
		#expect(availability.cause == .developerToolsMissing)
		#expect(GitAvailability.Cause(rawValue: "licence") == .licenceNotAccepted)
	}
}
