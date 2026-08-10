import Foundation
import Testing
@testable import AbydosKit

/// The spec, and folding an item's delta into it.
struct BacklogSpecTests {
	private func makeProject() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("spec-\(UUID().uuidString)")
			.appendingPathComponent("project")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	private func cleanUp(_ root: URL) {
		try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
	}

	// MARK: - Reading

	@Test func aDocumentKeepsWhatComesBeforeTheFirstRequirement() {
		let document = SpecDocument.parse("""
		# Terminal

		What this part of the program is.

		## Requirement: Ligatures survive a pane change

		The cache is per font.

		### Scenario: two panes

		- **Then** it still draws one glyph

		## Requirement: Images scale inside tmux

		Body.
		""", capability: "terminal")

		#expect(document.preamble.contains("What this part of the program is."))
		#expect(document.requirements.map(\.name) == [
			"Ligatures survive a pane change",
			"Images scale inside tmux",
		])
		// The scenario belongs to the requirement above it, not to the document.
		#expect(document.requirements[0].body.contains("### Scenario: two panes"))
	}

	@Test func aDocumentRoundTrips() {
		let text = """
		# Terminal

		Preamble.

		## Requirement: One

		First.

		## Requirement: Two

		Second.
		"""
		let document = SpecDocument.parse(text, capability: "terminal")
		let again = SpecDocument.parse(document.text, capability: "terminal")
		#expect(again == document)
	}

	@Test func aDeltaTakesOnlyTheVerbHeadings() {
		let delta = SpecDelta.parse("""
		<!-- a comment, and some notes nobody should have to strip by hand -->

		## ADDED Requirement: A new thing

		Body of the new thing.

		## MODIFIED Requirement: An old thing

		How it now reads.

		## REMOVED Requirement: A gone thing

		Because nothing used it.
		""", capability: "terminal")

		#expect(delta.entries.map(\.change) == [.added, .modified, .removed])
		#expect(delta.entries[0].requirement.body == "Body of the new thing.")
	}

	// MARK: - Folding

	@Test func foldingAppliesTheThreeVerbs() {
		let document = SpecDocument.parse("""
		# Terminal

		## Requirement: Old
		Was.

		## Requirement: Doomed
		Goes.
		""", capability: "terminal")

		let delta = SpecDelta.parse("""
		## MODIFIED Requirement: Old
		Is now.

		## REMOVED Requirement: Doomed
		Nothing used it.

		## ADDED Requirement: New
		Arrives.
		""", capability: "terminal")

		let result = SpecFold.apply(delta, to: document)
		#expect(result.problems.isEmpty)
		#expect(result.changed)
		#expect(result.document.requirements.map(\.name) == ["Old", "New"])
		#expect(result.document.requirement(named: "Old")?.body == "Is now.")
		// The preamble is not touched by any of the three.
		#expect(result.document.preamble.contains("# Terminal"))
	}

	@Test func aDeltaThatDoesNotDescribeTheSpecSaysSoAndTheRestStillGoesIn() {
		let document = SpecDocument.parse("## Requirement: Here\nBody.", capability: "terminal")
		let delta = SpecDelta.parse("""
		## MODIFIED Requirement: Not here
		Never was.

		## ADDED Requirement: Here
		Written twice by two people.

		## ADDED Requirement: Fine
		Goes in.
		""", capability: "terminal")

		let result = SpecFold.apply(delta, to: document)
		#expect(result.problems.count == 2)
		#expect(result.problems.map(\.change) == [.modified, .added])
		// The one that could be applied was, rather than the whole delta being
		// refused over the two that could not.
		#expect(result.document.requirements.map(\.name) == ["Here", "Fine"])
		#expect(result.document.requirement(named: "Here")?.body == "Body.")
	}

	@Test func foldingTheSameDeltaTwiceChangesNothingTheSecondTime() {
		let document = SpecDocument.parse("## Requirement: Here\nBody.", capability: "terminal")
		let delta = SpecDelta.parse("## MODIFIED Requirement: Here\nBody.", capability: "terminal")

		let result = SpecFold.apply(delta, to: document)
		#expect(result.problems.isEmpty)
		#expect(result.changed == false)
	}

	// MARK: - Through the store

	@Test func anItemsDeltaLandsInTheSpec() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [])
		let backlog = Backlog(projectRoot: root)
		let store = BacklogSpecStore(backlog: backlog)

		let item = try backlog.create(title: "Scale images in tmux", carriesFiles: true)
		let deltas = item.folder!.appendingPathComponent(Backlog.specDirectoryName, isDirectory: true)
		try FileManager.default.createDirectory(at: deltas, withIntermediateDirectories: true)
		try """
		## ADDED Requirement: Images scale inside tmux

		The pane's size is asked of tmux, not of the window.
		""".write(to: deltas.appendingPathComponent("terminal.md"), atomically: true, encoding: .utf8)

		// Nothing has been said about `terminal` yet, so an ADDED is right and
		// the check passes before the fold.
		#expect(store.check(item).isEmpty)
		let problems = try store.fold(item)
		#expect(problems.isEmpty)

		let written = store.document(for: "terminal")
		#expect(written.requirements.map(\.name) == ["Images scale inside tmux"])
		#expect(store.documents().map(\.capability) == ["terminal"])
	}

	@Test func theSpecReadmeIsNotACapability() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [])

		// `init` writes one, explaining the format. Counting it made a project
		// with nothing in its spec report one capability and no requirements.
		let store = BacklogSpecStore(backlog: Backlog(projectRoot: root))
		#expect(store.documents().isEmpty)
	}
}
