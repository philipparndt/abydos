import Foundation
import Testing
@testable import AbydosKit

/// Reacting to a preference that decides which server answers and where it
/// comes from.
///
/// The fault these are written against is 0460: an image chosen for a server
/// that had already failed, a preference stored correctly, and nothing
/// happening at all. What is proved here is the decision — which keys stop being
/// evidence, and which running servers are no longer the ones being asked for —
/// rather than the starting, which needs an app and a language server and is
/// driven instead.
struct ToolPreferencesTests {
	/// Two servers for Java with opposite trades, as `LanguageServerChoiceTests`
	/// makes them, plus one that answers for several ids. Asked of a table this
	/// file makes up so that the answers do not move the day the app's own table
	/// gains a server.
	private let table: [LanguageServerDefinition] = [
		LanguageServerDefinition(
			languageIds: ["java"],
			command: "jdtls",
			installHint: "brew install jdtls",
			rootMarkers: ["pom.xml"],
			setup: .java
		),
		LanguageServerDefinition(
			languageIds: ["java"],
			command: "kmp-lsp",
			installHint: "cargo install kmp-lsp",
			rootMarkers: ["pom.xml", "build.gradle"]
		),
		LanguageServerDefinition(
			languageIds: ["rust"],
			command: "rust-analyzer",
			installHint: "rustup component add rust-analyzer",
			rootMarkers: ["Cargo.toml"]
		),
	]

	private let project = URL(fileURLWithPath: "/tmp/a-project", isDirectory: true)

	private func key(_ server: String) -> String {
		LanguageServers.serverKey(project: project, server: server)
	}

	// MARK: - What changed

	@Test func aSettingNobodyTouchedIsNoChangeAtAll() {
		let before = ToolPreferences(images: ["rust-analyzer": "build"], servers: [:], runtime: "automatic")
		#expect(before.changes(since: before).isEmpty)
	}

	@Test func anImageChosenForAToolIsAChangeToThatTool() {
		let before = ToolPreferences(images: [:], servers: [:], runtime: "automatic")
		let after = ToolPreferences(images: ["rust-analyzer": "build"], servers: [:], runtime: "automatic")
		let change = after.changes(since: before)
		#expect(change.tools == ["rust-analyzer"])
		#expect(change.languages.isEmpty)
		#expect(!change.runtime)
	}

	@Test func goingBackToTheInstalledCopyIsAChangeToo() {
		let before = ToolPreferences(images: ["rust-analyzer": "build"], servers: [:], runtime: "automatic")
		let after = ToolPreferences(images: [:], servers: [:], runtime: "automatic")
		#expect(after.changes(since: before).tools == ["rust-analyzer"])
	}

	@Test func anotherServerForALanguageIsAChangeToThatLanguage() {
		let before = ToolPreferences(images: [:], servers: [:], runtime: "automatic")
		let after = ToolPreferences(images: [:], servers: ["java": "kmp-lsp"], runtime: "automatic")
		#expect(after.changes(since: before).languages == ["java"])
	}

	@Test func theRuntimeIsItsOwnAnswer() {
		let before = ToolPreferences(images: [:], servers: [:], runtime: "automatic")
		let after = ToolPreferences(images: [:], servers: [:], runtime: "docker")
		#expect(after.changes(since: before).runtime)
	}

	/// The settings page writes an empty image the moment "Custom" is picked,
	/// before anybody has typed the name. It means "the one I am about to give
	/// you", and reacting to it would stop a running server on the way to a
	/// value that does not exist yet.
	@Test func anEmptyCustomImageIsNotYetAChoice() {
		let before = ToolPreferences(images: [:], servers: [:], runtime: "automatic")
		let after = ToolPreferences(images: ["plantuml": ""], servers: [:], runtime: "automatic")
		#expect(after.changes(since: before).isEmpty)
	}

	@Test func typingTheNameIsTheChoice() {
		let picked = ToolPreferences(images: ["plantuml": ""], servers: [:], runtime: "automatic")
		let typed = ToolPreferences(images: ["plantuml": "plantuml/plantuml:1.2025.4"], servers: [:], runtime: "automatic")
		#expect(typed.changes(since: picked).tools == ["plantuml"])
	}

	// MARK: - What a project does about it

	private func reconsideration(
		change: ToolPreferences.Change,
		was: LanguageServerChoices = .none,
		wasFrom: ToolImages = ToolImages(),
		now: LanguageServerChoices = .none,
		nowFrom: ToolImages = ToolImages(),
		running: Set<String> = [],
		inDevContainer: Bool = false
	) -> ServerReconsideration {
		ServerReconsideration(
			change: change,
			project: project,
			was: was,
			wasFrom: wasFrom,
			now: now,
			nowFrom: nowFrom,
			running: running,
			inDevContainer: inDevContainer,
			among: table
		)
	}

	/// The reported case: rust-analyzer failed, an image was chosen for it, and
	/// what was remembered about the failure has to stop being evidence.
	@Test func anImageForAServerThatFailedIsForgotten() {
		let decision = reconsideration(
			change: .init(tools: ["rust-analyzer"], languages: [], runtime: false),
			nowFrom: ToolImages(images: ["rust-analyzer": "build"])
		)
		#expect(decision.forget == [key("rust-analyzer")])
		#expect(decision.stop.isEmpty)
		#expect(decision.languages == ["rust"])
	}

	/// A server running from the copy on this machine is not the one that was
	/// asked for once an image is named for it.
	@Test func aServerRunningFromSomewhereElseIsStopped() {
		let decision = reconsideration(
			change: .init(tools: ["rust-analyzer"], languages: [], runtime: false),
			nowFrom: ToolImages(images: ["rust-analyzer": "build"]),
			running: [key("rust-analyzer")]
		)
		#expect(decision.stop == [key("rust-analyzer")])
	}

	/// The file wins and the setting is the default, so a project that pins its
	/// own image is a project this preference did not change.
	@Test func aProjectThatPinsItsOwnImageIsUntouched() {
		let pinned = ToolImages(images: ["rust-analyzer": "ghcr.io/x/ra:1"])
		let decision = reconsideration(
			change: .init(tools: ["rust-analyzer"], languages: [], runtime: false),
			wasFrom: pinned,
			nowFrom: pinned,
			running: [key("rust-analyzer")]
		)
		#expect(decision.isEmpty)
	}

	/// Changing where one tool comes from says nothing about any other, which is
	/// what keeps this from re-importing a Java project every time somebody
	/// picks an image for a renderer.
	@Test func anotherToolsImageLeavesARunningServerAlone() {
		let decision = reconsideration(
			change: .init(tools: ["plantuml"], languages: [], runtime: false),
			nowFrom: ToolImages(images: ["plantuml": "plantuml/plantuml:1.2025.4"]),
			running: [key("jdtls")]
		)
		#expect(decision.stop.isEmpty)
	}

	/// 0449's section, one question along: the jdtls that is running is under a
	/// key nothing will ask about again, and nothing else would ever stop it.
	@Test func theServerThatIsNoLongerChosenIsStopped() {
		let decision = reconsideration(
			change: .init(tools: [], languages: ["java"], runtime: false),
			now: LanguageServerChoices.settings(["java": "kmp-lsp"]),
			running: [key("jdtls")]
		)
		#expect(decision.stop == [key("jdtls")])
		// Both keys: the old one so nothing is remembered about a server that is
		// no longer asked for, the new one so a refusal from an earlier session
		// is not in the way of the server that is.
		#expect(decision.forget == [key("jdtls"), key("kmp-lsp")])
		#expect(decision.languages == ["java"])
	}

	/// The project's own file overrides the setting, so the setting moving does
	/// not move this project.
	@Test func aProjectWhoseFileNamesItsOwnServerIsUntouched() {
		let file = LanguageServerChoices(byLanguage: ["java": .init(name: "jdtls", source: .project)])
		let decision = reconsideration(
			change: .init(tools: [], languages: ["java"], runtime: false),
			was: file,
			now: file,
			running: [key("jdtls")]
		)
		#expect(decision.isEmpty)
	}

	/// "Nothing here can run a container" is remembered as a failure like any
	/// other, and choosing a runtime that is installed is what undoes it.
	@Test func aRuntimeThatCanRunSomethingUndoesTheOneThatCouldNot() {
		let named = ToolImages(images: ["rust-analyzer": "build"])
		let decision = reconsideration(
			change: .init(tools: [], languages: [], runtime: true),
			wasFrom: named,
			nowFrom: named,
			running: [key("rust-analyzer")]
		)
		#expect(decision.forget == [key("rust-analyzer")])
		#expect(decision.stop == [key("rust-analyzer")])
	}

	/// A runtime nothing in the project would have used is not a change to the
	/// project.
	@Test func aRuntimeChangeWithNoImageNamedChangesNothing() {
		let decision = reconsideration(
			change: .init(tools: [], languages: [], runtime: true),
			running: [key("rust-analyzer")]
		)
		#expect(decision.isEmpty)
	}

	/// A project worked on inside its own devcontainer takes its servers from in
	/// there, so an image named out here is not a question it asks — and
	/// stopping its server would cost the container's start for nothing.
	@Test func aProjectInItsDevContainerIgnoresAnImageChosenOutHere() {
		let decision = reconsideration(
			change: .init(tools: ["rust-analyzer"], languages: [], runtime: true),
			nowFrom: ToolImages(images: ["rust-analyzer": "build"]),
			running: [key("rust-analyzer")],
			inDevContainer: true
		)
		#expect(decision.isEmpty)
	}

	/// Which server answers is still that project's question, container or not.
	@Test func aProjectInItsDevContainerStillFollowsTheServerChosenForIt() {
		let decision = reconsideration(
			change: .init(tools: [], languages: ["java"], runtime: false),
			now: LanguageServerChoices.settings(["java": "kmp-lsp"]),
			running: [key("jdtls")],
			inDevContainer: true
		)
		#expect(decision.stop == [key("jdtls")])
	}

	// MARK: - The key itself

	@Test func aServerIsFiledUnderItsOwnNameAndTheProjectsPath() {
		#expect(
			LanguageServers.serverKey(
				project: project, languageId: "java",
				choosing: LanguageServerChoices.settings(["java": "kmp-lsp"]), among: table
			) == key("kmp-lsp")
		)
	}
}
