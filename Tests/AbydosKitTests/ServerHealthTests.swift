import Testing
@testable import AbydosKit

/// 0461. A server that starts and then cannot read the project used to look
/// exactly like one that was working, and the rule for telling them apart has to
/// be careful in both directions: silent about a server that grumbles and goes
/// on working, and loud about one that will never answer anything.
struct ServerHealthTests {
	@Test func aServerThatHasSaidNothingIsWorking() {
		let health = ServerHealth()
		#expect(health.isWorking)
		#expect(health.said == nil)
		#expect(health.sentence(for: "gopls") == nil)
	}

	@Test func anErrorFromARunningServerIsAReportRatherThanAVerdict() {
		var health = ServerHealth()
		health.said("failed to load workspace: no go.mod")
		#expect(!health.isWorking)
		#expect(health.said == "failed to load workspace: no go.mod")
		// Said, not proved: the sentence stops short of claiming the server is
		// useless, because at this point nobody knows that it is.
		#expect(health.sentence(for: "gopls") == "gopls is running and says something is wrong "
			+ "with this project.")
	}

	@Test func aServerThatGoesOnAnsweringIsNotCalledBroken() {
		var health = ServerHealth()
		health.said("ERROR duplicate DidOpenTextDocument: /workspace/src/main.rs")
		health.answered(withContent: true)
		#expect(health.isWorking)
		#expect(health.sentence(for: "rust-analyzer") == nil)
	}

	@Test func aQuestionItCouldNotAnswerAfterSayingSoIsTheVerdict() {
		var health = ServerHealth()
		health.said("Failed to resolve the classpath for this project")
		health.answered(withContent: false)
		#expect(health.sentence(for: "jdtls") == "jdtls is running and cannot read this "
			+ "project, so nothing here will be answered.")
		#expect(health.said == "Failed to resolve the classpath for this project")
	}

	/// The half that keeps this out of the strip for a busy server: an empty
	/// answer means nothing on its own, and a file with nothing declared in it
	/// gives one on every keystroke in the symbol palette.
	@Test func anEmptyAnswerOnItsOwnSaysNothing() {
		var health = ServerHealth()
		health.answered(withContent: false)
		health.answered(withContent: false)
		#expect(health.isWorking)
	}

	/// Measured against the log this item came from: the diagnosis arrives once
	/// and the noise arrives for ever afterwards.
	@Test func theFirstDiagnosisIsKeptRatherThanTheLatestNoise() {
		var health = ServerHealth()
		health.said("custom toolchain 'esp' specified in override file is not installed")
		health.said("ERROR duplicate DidOpenTextDocument: /workspace/src/main.rs")
		#expect(health.said == "custom toolchain 'esp' specified in override file is not installed")
	}

	@Test func aVerdictIsGivenBackWhenTheServerStartsAnswering() {
		var health = ServerHealth()
		health.said("Failed to read Cargo metadata")
		health.answered(withContent: false)
		#expect(!health.isWorking)
		health.answered(withContent: true)
		#expect(health.isWorking)
	}

	@Test func aServerThatStoppedSaysWhyAndIsNotAskedAgain() {
		var health = ServerHealth()
		health.stopped(saying: "error: custom toolchain 'esp' specified in override file "
			+ "'/workspace/esp32/rust-toolchain.toml' is not installed")
		#expect(health.sentence(for: "rust-analyzer")
			== "rust-analyzer started for this project and is not running any more.")
		// Nothing can be asked of a process that is gone, so an answer arriving
		// from somewhere does not move it.
		health.answered(withContent: true)
		#expect(health.said?.contains("custom toolchain 'esp'") == true)
	}

	/// A server that stopped after having complained is described by how it
	/// stopped: the words on the way out are the ones that say why.
	@Test func stoppingOverridesWhatWasSaidBefore() {
		var health = ServerHealth()
		health.said("cargo check failed to start")
		health.stopped(saying: "the language server is not running")
		#expect(health.said == "the language server is not running")
	}

	@Test func aServerThatStoppedWithoutSayingAnythingStillSaysSomething() {
		var health = ServerHealth()
		health.stopped(saying: "   ")
		#expect(health.said == "It stopped without saying why.")
	}

	/// None of the sentences may read as a crash: the server is a program that
	/// started, two of the three say it is still running, and the next project
	/// it is asked about may be perfectly readable.
	@Test func noneOfTheSentencesSayTheServerCrashed() {
		var reported = ServerHealth()
		reported.said("something")
		var proved = ServerHealth()
		proved.said("something")
		proved.answered(withContent: false)
		var gone = ServerHealth()
		gone.stopped(saying: "something")
		for health in [reported, proved, gone] {
			let sentence = health.sentence(for: "clangd") ?? ""
			#expect(sentence.contains("clangd"))
			#expect(!sentence.lowercased().contains("crash"))
			#expect(sentence.contains("this project"))
		}
	}
}
