import Foundation
import Testing
@testable import AbydosKit

/// Asking before a devcontainer is started, and remembering the answer where it
/// belongs. 0433.
///
/// The window layer is not built by this target, so what is proved here is
/// everything that can be: which answers are kept and which is deliberately
/// not, that the answer is per project and survives a path reached two ways,
/// and every sentence the question and the strip are made of. What is *not*
/// proved here is that the sheet appears and that the pill follows a container
/// coming up — those are `LanguageService` and `MainWindowController`, in a
/// target these tests cannot reach.
struct DevContainerConsentTests {
	private func makeSettings() -> Settings {
		Settings(defaults: TestDefaults.make())
	}

	private func makeProject() throws -> URL {
		let root = try JavaTestDirectory.make()
		return URL(fileURLWithPath: FilePath.canonical(root), isDirectory: true)
	}

	/// Nobody has been asked about a project until they have, which is what makes
	/// the question happen once rather than never or every time.
	@Test func aProjectNobodyWasAskedAboutHasNoAnswer() throws {
		let settings = makeSettings()
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		#expect(settings.devContainerConsent(forProject: project) == nil)
	}

	@Test func theTwoAnswersAboutTheProjectAreKept() throws {
		let settings = makeSettings()
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		settings.setDevContainerConsent(.container, forProject: project)
		#expect(settings.devContainerConsent(forProject: project) == .container)

		// Changed rather than added to: somebody who says "work on this machine"
		// after having said yes has one answer, not two.
		settings.setDevContainerConsent(.thisMachine, forProject: project)
		#expect(settings.devContainerConsent(forProject: project) == .thisMachine)
		#expect(settings.devContainerConsent.count == 1)
	}

	/// **"Not now" is about this afternoon.** Writing it down would turn a delay
	/// — the train, the battery, the gigabyte — into a decision nobody made, and
	/// the project would never ask again.
	@Test func notNowIsNotWrittenDown() throws {
		let settings = makeSettings()
		let project = try makeProject()
		defer { try? FileManager.default.removeItem(at: project) }

		settings.setDevContainerConsent(.notNow, forProject: project)
		#expect(settings.devContainerConsent(forProject: project) == nil)
		#expect(settings.devContainerConsent.isEmpty)

		// And it takes an earlier answer away rather than leaving it standing:
		// somebody saying "not now" after having said yes has not said yes.
		settings.setDevContainerConsent(.container, forProject: project)
		settings.setDevContainerConsent(.notNow, forProject: project)
		#expect(settings.devContainerConsent(forProject: project) == nil)
	}

	@Test func consentIsPerProject() throws {
		let settings = makeSettings()
		let one = try makeProject()
		let other = try makeProject()
		defer {
			try? FileManager.default.removeItem(at: one)
			try? FileManager.default.removeItem(at: other)
		}

		settings.setDevContainerConsent(.container, forProject: one)
		settings.setDevContainerConsent(.thisMachine, forProject: other)

		#expect(settings.devContainerConsent(forProject: one) == .container)
		#expect(settings.devContainerConsent(forProject: other) == .thisMachine)
	}

	/// The same checkout reached two ways is one project.
	///
	/// On macOS `/tmp` is a symlink to `/private/tmp`, which is where every
	/// scratch project this suite makes lives — a table keyed by whatever string
	/// the caller happened to hold would ask twice about one directory. This is
	/// the fault 0430 found one floor down, in a different table.
	@Test func aProjectReachedThroughASymlinkIsTheSameProject() throws {
		let settings = makeSettings()
		// As the file manager hands it over — `/var/folders/…`, which is reached
		// through a symlink — beside the real name of the same directory.
		let through = try JavaTestDirectory.make()
		defer { try? FileManager.default.removeItem(at: through) }
		let real = URL(fileURLWithPath: FilePath.canonical(through), isDirectory: true)
		try #require(real.path != through.path, "this machine has no symlink to prove it with")

		settings.setDevContainerConsent(.container, forProject: real)
		#expect(settings.devContainerConsent(forProject: through) == .container)
		#expect(settings.devContainerConsent.count == 1)
	}

	// MARK: - What the question says

	@Test func theQuestionNamesBothTheProjectAndTheContainer() {
		// Neither on its own is the question: a repository of subprojects with a
		// devcontainer each can be asked about twice in one session.
		let asked = DevContainerConsent.question(
			project: "abydos-examples", container: "python-language-server"
		)
		#expect(asked.contains("abydos-examples"))
		#expect(asked.contains("python-language-server"))
	}

	/// The cost is stated in the units somebody on a train cares about, and it
	/// says it is the first time only. Not saying it at all is the whole of what
	/// was reported.
	@Test func theExplanationSaysWhatTheFirstStartCosts() {
		let pulled = DevContainerConsent.explanation(
			container: "python", firstStart: .image("mcr.microsoft.com/devcontainers/python:3.12")
		)
		#expect(pulled.contains("mcr.microsoft.com/devcontainers/python:3.12"))
		#expect(pulled.contains("downloaded"))
		#expect(pulled.contains("minutes"))
		#expect(pulled.contains("gigabyte"))

		let built = DevContainerConsent.explanation(
			container: "go", firstStart: .build(".devcontainer/Dockerfile")
		)
		#expect(built.contains(".devcontainer/Dockerfile"))
		#expect(built.contains("built"))
		#expect(built.contains("minutes"))
	}

	/// A file that could not be read says what is known and not what is not: the
	/// container is still named, and no cost is invented for it.
	@Test func anUnreadableFileCostsNothingItCannotName() {
		let said = DevContainerConsent.explanation(container: "go", firstStart: nil)
		#expect(said.contains("go"))
		#expect(!said.contains("minutes"))
	}

	/// Where the image comes from is read from the file rather than guessed, and
	/// a Dockerfile is named the way the project names it.
	@Test func whatTheFirstStartIsComesFromTheFile() throws {
		let root = try makeProject()
		defer { try? FileManager.default.removeItem(at: root) }

		let pulled = DevContainerFile.parse(
			Data(#"{"image": "alpine:3.20"}"#.utf8), project: root
		).configuration
		#expect(pulled.map(DevContainerConsent.FirstStart.of) == .image("alpine:3.20"))

		let built = DevContainerFile.parse(
			Data(#"{"build": {"dockerfile": "Dockerfile", "context": ".."}}"#.utf8),
			named: ".devcontainer/devcontainer.json",
			project: root
		).configuration
		#expect(built.map(DevContainerConsent.FirstStart.of) == .build(".devcontainer/Dockerfile"))
	}

	/// The button that starts it names the container; the two that do not, do
	/// not. A row of Yes/No/Later is a question somebody has to read twice.
	@Test func theButtonsSayWhatEachAnswerDoes() {
		#expect(
			DevContainerConsent.buttonTitle(.container, container: "go") == "Use go"
		)
		#expect(
			DevContainerConsent.buttonTitle(.thisMachine, container: "go")
				== "Work on This Machine"
		)
		#expect(DevContainerConsent.buttonTitle(.notNow, container: "go") == "Not Now")
		// The project's own answer is offered first, and the one that decides
		// nothing last, because that is the one Escape is wired to.
		#expect(DevContainerConsent.answersInOrder == [.container, .thisMachine, .notNow])
	}

	// MARK: - What is left on screen

	/// **The two declines have to be told apart.** A Python file with no squiggles
	/// at all and one being checked by a server that is not the project's are the
	/// same picture, and which of them is in force is the thing that had nowhere
	/// to be said.
	@Test func theStripSaysWhichDeclineIsInForce() {
		let onThisMachine = DevContainerConsent.notice(
			language: "Python", container: "python-language-server", consent: .thisMachine
		)
		let notNow = DevContainerConsent.notice(
			language: "Python", container: "python-language-server", consent: .notNow
		)
		#expect(onThisMachine != nil)
		#expect(notNow != nil)
		#expect(onThisMachine != notNow)
		#expect(onThisMachine?.contains("this machine") == true)
		#expect(notNow?.contains("has not been started") == true)
		for said in [onThisMachine, notNow] {
			#expect(said?.contains("Python") == true)
			#expect(said?.contains("python-language-server") == true)
		}
	}

	/// A container that is being used has the sentences it already had — coming
	/// up, up, or missing the server — so this adds none.
	@Test func aContainerBeingUsedHasNothingExtraToSay() {
		#expect(
			DevContainerConsent.notice(language: "Python", container: "py", consent: .container)
				== nil
		)
	}

	/// The way back is the same words as the button that would have started it,
	/// so agreeing later and agreeing at once read the same.
	@Test func theWayBackSaysTheSameAsTheAnswerItRestores() {
		#expect(
			DevContainerConsent.offerTitle(container: "go")
				== DevContainerConsent.buttonTitle(.container, container: "go")
		)
	}

	// MARK: - The question in the corner (0438)

	/// The first line is fixed and short, because it is read from the corner of
	/// the eye — and it is the gesture 0433's report went looking for.
	@Test func theQuestionInTheCornerLeadsWithTheGesture() {
		#expect(DevContainerConsent.questionTitle == "Activate dev container")
	}

	/// What the dialog's title and paragraph said between them, in a sentence a
	/// corner 340 points wide can hold: which project, which container, and what
	/// the first start costs.
	@Test func theSentenceUnderItStillNamesBothAndTheCost() {
		let said = DevContainerConsent.questionBody(
			project: "python-language-server",
			container: "Python, with its language server in the container",
			firstStart: .build(".devcontainer/Dockerfile")
		)
		#expect(said.contains("python-language-server"))
		#expect(said.contains("Python, with its language server in the container"))
		#expect(said.contains(".devcontainer/Dockerfile"))
		#expect(said.contains("minutes"))
		#expect(said.contains("gigabyte"))
		// Shorter than the dialog's paragraph, which is the whole reason it exists.
		#expect(said.count < DevContainerConsent.explanation(
			container: "Python, with its language server in the container",
			firstStart: .build(".devcontainer/Dockerfile")
		).count)

		// A file that could not be read invents no cost.
		let unknown = DevContainerConsent.questionBody(
			project: "p", container: "c", firstStart: nil
		)
		#expect(!unknown.contains("minutes"))
	}

	// MARK: - The pill that says a container is there and is not in use (0438)

	/// **It must not nag.** Somebody who chose to work on this machine chose it,
	/// so the sentence states what is true of the container and never argues.
	@Test func theDeclinedPillStatesTheStateAndDoesNotArgue() {
		let states: [DevContainerConsent?] = [.thisMachine, .notNow, nil, .container]
		for state in states {
			let said = DevContainerConsent.pillState(state, container: "py")
			#expect(said.contains("py") || said.contains("this machine"))
			for nagging in ["should", "recommend", "warning", "?", "!"] {
				#expect(!said.contains(nagging), "\(String(describing: state)): \(said)")
			}
		}
	}

	/// **"Not now" and "nobody has been asked" are the same state of the world**:
	/// there is a devcontainer and nothing is running in it. Telling them apart on
	/// screen would be reporting the app's bookkeeping rather than the project.
	@Test func notNowAndNotYetAskedReadTheSame() {
		#expect(
			DevContainerConsent.pillState(.notNow, container: "py")
				== DevContainerConsent.pillState(nil, container: "py")
		)
		// And both differ from the machine this is being worked on instead, which
		// is the distinction 0433 spent an item establishing.
		#expect(
			DevContainerConsent.pillState(.notNow, container: "py")
				!= DevContainerConsent.pillState(.thisMachine, container: "py")
		)
		// A container that was said yes to and has not come up yet is a third
		// thing again, and the pill is dimmed for it too: it is not in use *yet*.
		#expect(DevContainerConsent.pillState(.container, container: "py").contains("starting"))
	}

	@Test func onlyTheAnswersAboutTheProjectAreRemembered() {
		#expect(DevContainerConsent.container.isRemembered)
		#expect(DevContainerConsent.thisMachine.isRemembered)
		#expect(!DevContainerConsent.notNow.isRemembered)
	}
}
