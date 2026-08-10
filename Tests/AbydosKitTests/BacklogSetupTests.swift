import Foundation
import Testing
@testable import AbydosKit

/// `init`, which has to be safe to run twice.
struct BacklogSetupTests {
	private func makeProject() throws -> URL {
		let root = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("setup-\(UUID().uuidString)")
			.appendingPathComponent("project")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		return root
	}

	private func cleanUp(_ root: URL) {
		try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
	}

	private func read(_ url: URL) -> String {
		(try? String(contentsOf: url, encoding: .utf8)) ?? ""
	}

	@Test func itMakesTheFoldersAndTheDocuments() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [.claude])
		let backlog = Backlog(projectRoot: root)

		#expect(backlog.exists)
		for state in BacklogState.created {
			#expect(FileManager.default.fileExists(atPath: backlog.directory(for: state).path))
			// git tracks files, not directories: an empty `ready/` that is not
			// in the repository is a folder the next clone does not get.
			#expect(FileManager.default.fileExists(
				atPath: backlog.directory(for: state).appendingPathComponent(".gitkeep").path
			))
		}
		#expect(read(backlog.instructionsFile).contains("## Picking up a ready item"))
		#expect(read(backlog.instructionsFile).contains("### The checklist"))
		#expect(FileManager.default.fileExists(atPath: backlog.projectFile.path))
		#expect(FileManager.default.fileExists(
			atPath: root.appendingPathComponent(".claude/skills/backlog/SKILL.md").path
		))
	}

	@Test func theKeepFileGoesOnceTheFolderHasSomethingInIt() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [])
		let backlog = Backlog(projectRoot: root)
		let keep = backlog.directory(for: .open).appendingPathComponent(".gitkeep")
		#expect(FileManager.default.fileExists(atPath: keep.path))

		_ = try backlog.create(title: "Something")
		try BacklogSetup.run(projectRoot: root, assistants: [])
		#expect(!FileManager.default.fileExists(atPath: keep.path))
		// And the empty ones still have theirs.
		#expect(FileManager.default.fileExists(
			atPath: backlog.directory(for: .ready).appendingPathComponent(".gitkeep").path
		))
	}

	@Test func theBacklogIsLetThroughTheAbydosGitignore() throws {
		let root = try makeProject()
		defer { cleanUp(root) }

		// A folder written by an older version, which ignored everything but
		// the run configurations. A backlog under it would never be pushed.
		let folder = root.appendingPathComponent(".abydos", isDirectory: true)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		try "*\n!.gitignore\n!run/\n!run/**\n".write(
			to: folder.appendingPathComponent(".gitignore"),
			atomically: true,
			encoding: .utf8
		)

		try BacklogSetup.run(projectRoot: root, assistants: [])
		let ignore = read(folder.appendingPathComponent(".gitignore"))
		#expect(ignore.contains("!backlog/"))
		#expect(ignore.contains("!backlog/**"))
		// What was there before is still there.
		#expect(ignore.contains("!run/**"))
	}

	@Test func aSecondRunKeepsWhatSomebodyWrote() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [.claude])
		let backlog = Backlog(projectRoot: root)

		try "# Our backlog\n\nRead the wiki.\n".write(
			to: backlog.readmeFile, atomically: true, encoding: .utf8
		)
		try "# This project\n\nIt is a compiler.\n".write(
			to: backlog.projectFile, atomically: true, encoding: .utf8
		)

		try BacklogSetup.run(projectRoot: root, assistants: [.claude])
		#expect(read(backlog.readmeFile).contains("Read the wiki."))
		#expect(read(backlog.projectFile).contains("It is a compiler."))
		// The workflow document is ours, so it is brought up to date.
		#expect(read(backlog.instructionsFile).contains("## Picking up a ready item"))
	}

	@Test func aSecondRunAddsAnAssistantRatherThanReplacingOne() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [.claude])
		try BacklogSetup.run(projectRoot: root, assistants: [.opencode])

		let configuration = BacklogConfiguration.read(Backlog(projectRoot: root).configFile)
		#expect(configuration?.known == [.claude, .opencode])
		// And the first one's files are still written.
		#expect(FileManager.default.fileExists(
			atPath: root.appendingPathComponent(".claude/skills/backlog/SKILL.md").path
		))
		#expect(FileManager.default.fileExists(
			atPath: root.appendingPathComponent(".opencode/command/backlog.md").path
		))
	}

	@Test func aSkillFileIsFrontmatterAndThenReadableMarkdown() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		try BacklogSetup.run(projectRoot: root, assistants: [.claude])
		let skill = read(root.appendingPathComponent(".claude/skills/backlog/SKILL.md"))

		#expect(skill.hasPrefix("---\nname: backlog\n"))
		#expect(skill.contains("\ndescription: "))
		// The body used to be assembled by taking two lines off the shared
		// text and rejoining the rest, which lost every blank line: the whole
		// skill shipped as one run-together paragraph with the first sentence
		// missing. Both halves are worth asserting.
		#expect(skill.contains("keeps everything left to do in `.abydos/backlog/`"))
		#expect(skill.contains("\n\n- `abydos-backlog next`"))
		#expect(skill.contains("`## Steps` checklist"))
	}

	// MARK: - Somebody else's file

	@Test func aSharedFileKeepsItsOwnContentAroundOurSection() {
		let existing = """
		# Contributing

		Run `make test` before you push.
		"""
		let first = BacklogSetup.fencing("Read the backlog document.", into: existing)
		#expect(first.contains("Run `make test` before you push."))
		#expect(first.contains(BacklogInstructions.startMarker))
		// Below what was there, not above it: the author put that first on
		// purpose.
		#expect(first.range(of: "make test")!.lowerBound < first.range(of: BacklogInstructions.startMarker)!.lowerBound)

		let second = BacklogSetup.fencing("Read it again, it changed.", into: first)
		#expect(second.contains("Run `make test` before you push."))
		#expect(second.contains("Read it again, it changed."))
		#expect(!second.contains("Read the backlog document."))
		// One section, however many times it is run.
		#expect(second.components(separatedBy: BacklogInstructions.startMarker).count == 2)
	}

	@Test func anEmptyFileBecomesJustOurSection() {
		let written = BacklogSetup.fencing("Body.", into: nil)
		#expect(written.hasPrefix(BacklogInstructions.startMarker))
		#expect(written.contains("Body."))
	}

	@Test func aSharedFileWrittenByTwoAssistantsIsWrittenOnce() throws {
		let root = try makeProject()
		defer { cleanUp(root) }
		// opencode and Codex both read AGENTS.md.
		try BacklogSetup.run(projectRoot: root, assistants: [.opencode, .codex])

		let agents = read(root.appendingPathComponent("AGENTS.md"))
		#expect(agents.components(separatedBy: BacklogInstructions.startMarker).count == 2)
	}
}
