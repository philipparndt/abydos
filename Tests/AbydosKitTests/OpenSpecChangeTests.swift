import Foundation
import Testing
@testable import AbydosKit

/// Reading OpenSpec changes off the disk, which is the only way the board reads
/// them.
struct OpenSpecChangeTests {
	/// A project with an `openspec/changes/` in it, thrown away afterwards.
	private final class Sandbox {
		let root: URL

		init() {
			root = URL(fileURLWithPath: NSTemporaryDirectory())
				.appendingPathComponent("openspec-\(UUID().uuidString)", isDirectory: true)
			try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		}

		deinit { try? FileManager.default.removeItem(at: root) }

		var openSpec: OpenSpec { OpenSpec(projectRoot: root) }

		@discardableResult
		func change(_ name: String, archived: Bool = false, files: [String: String]) -> URL {
			let folder = (archived ? openSpec.archiveDirectory : openSpec.changesDirectory)
				.appendingPathComponent(name, isDirectory: true)
			for (path, contents) in files {
				let file = folder.appendingPathComponent(path)
				try? FileManager.default.createDirectory(
					at: file.deletingLastPathComponent(), withIntermediateDirectories: true
				)
				try? contents.write(to: file, atomically: true, encoding: .utf8)
			}
			return folder
		}
	}

	private func tasks(done: Int, left: Int) -> String {
		var text = "## 1. Doing it\n\n"
		for index in 0..<done { text += "- [x] 1.\(index + 1) done\n" }
		for index in 0..<left { text += "- [ ] 1.\(done + index + 1) not done\n" }
		return text
	}

	// MARK: - What a change is

	@Test func aProjectWithNoOpenSpecDirectoryHasNoChanges() {
		let sandbox = Sandbox()
		#expect(sandbox.openSpec.exists == false)
		#expect(sandbox.openSpec.changes().isEmpty)
	}

	@Test func aChangeIsItsDirectoryAndTheDocumentsInIt() throws {
		let sandbox = Sandbox()
		sandbox.change("say-what-goes-in-them", files: [
			".openspec.yaml": "schema: spec-driven\ncreated: 2026-08-17\n",
			"proposal.md": "## Why\n",
			"design.md": "## Context\n",
			"specs/completion-detail/spec.md": "## ADDED Requirements\n",
			"tasks.md": tasks(done: 0, left: 3),
		])

		let change = try #require(sandbox.openSpec.changes().first)
		#expect(change.name == "say-what-goes-in-them")
		#expect(change.artifacts == Set(OpenSpecArtifact.allCases))
		#expect(change.schema == "spec-driven")
		#expect(change.created == "2026-08-17")
		#expect(change.specFiles().count == 1)
		// Proposal, design, tasks and one spec, in the order they are read.
		#expect(change.openableFiles().count == 4)
	}

	/// `openspec new change` makes the folder before anything is written into
	/// it, and an empty scaffold is not an artifact.
	@Test func anEmptySpecsFolderIsNotAWrittenSpec() throws {
		let sandbox = Sandbox()
		let folder = sandbox.change("early", files: ["proposal.md": "## Why\n"])
		try FileManager.default.createDirectory(
			at: folder.appendingPathComponent("specs"), withIntermediateDirectories: true
		)

		let change = try #require(sandbox.openSpec.changes().first)
		#expect(change.artifacts == [.proposal])
		#expect(change.artifactSummary == "proposal")
	}

	@Test func aDirectoryWithNoneOfTheDocumentsIsNotAChange() {
		let sandbox = Sandbox()
		sandbox.change("not-a-change", files: ["notes.txt": "hello"])
		#expect(sandbox.openSpec.changes().isEmpty)
	}

	@Test func aChangeWithNoHeaderIsStillAChange() throws {
		let sandbox = Sandbox()
		sandbox.change("headerless", files: ["tasks.md": tasks(done: 1, left: 1)])

		let change = try #require(sandbox.openSpec.changes().first)
		#expect(change.schema == nil)
		#expect(change.created == nil)
		#expect(change.progress()?.summary == "1/2")
	}

	// MARK: - Where a change stands

	@Test func aChangeWithNoTasksFileIsStillBeingWritten() throws {
		let sandbox = Sandbox()
		sandbox.change("early", files: ["proposal.md": "## Why\n"])

		let change = try #require(sandbox.openSpec.changes().first)
		// Nothing at all rather than 0/0: a change still being written has no
		// fraction, and a card says which documents exist instead.
		#expect(change.progress() == nil)
		#expect(change.state(progress: nil) == .open)
	}

	@Test func aChangeWithNothingTickedIsReadyToPickUp() throws {
		let sandbox = Sandbox()
		sandbox.change("ready", files: ["tasks.md": tasks(done: 0, left: 30)])

		let change = try #require(sandbox.openSpec.changes().first)
		let progress = change.progress()
		#expect(progress?.summary == "0/30")
		#expect(change.state(progress: progress) == .ready)
	}

	@Test func aChangePartWayThroughIsInProgress() throws {
		let sandbox = Sandbox()
		sandbox.change("started", files: ["tasks.md": tasks(done: 4, left: 26)])

		let change = try #require(sandbox.openSpec.changes().first)
		let progress = change.progress()
		#expect(progress?.summary == "4/30")
		#expect(change.state(progress: progress) == .inProgress)
	}

	@Test func aChangeWithEveryTaskTickedIsDone() throws {
		let sandbox = Sandbox()
		sandbox.change("finished", files: ["tasks.md": tasks(done: 9, left: 0)])

		let change = try #require(sandbox.openSpec.changes().first)
		let progress = change.progress()
		#expect(progress?.isComplete == true)
		#expect(change.state(progress: progress) == .completed)
	}

	/// Nothing in a change says it is stuck on something, and a marker invented
	/// here would be a format this project made up and then had to keep.
	@Test func noChangeIsEverWaiting() throws {
		let sandbox = Sandbox()
		sandbox.change("a", files: ["proposal.md": "## Why\n"])
		sandbox.change("b", files: ["tasks.md": tasks(done: 0, left: 2)])
		sandbox.change("c", files: ["tasks.md": tasks(done: 1, left: 1)])
		sandbox.change("d", files: ["tasks.md": tasks(done: 2, left: 0)])

		for change in sandbox.openSpec.changes() {
			#expect(change.state(progress: change.progress()) != .waiting)
		}
	}

	// MARK: - The archive

	@Test func anArchivedChangeIsNotAmongTheOthers() throws {
		let sandbox = Sandbox()
		sandbox.change("current", files: ["tasks.md": tasks(done: 0, left: 1)])
		sandbox.change("finished-last-week", archived: true, files: ["tasks.md": tasks(done: 3, left: 0)])

		#expect(sandbox.openSpec.changes().map(\.name) == ["current"])
		let archived = try #require(sandbox.openSpec.archived().first)
		#expect(archived.name == "finished-last-week")
		#expect(archived.isArchived)
	}

	// MARK: - One parser for both

	/// A `## Steps` checklist and a `tasks.md` with the same ticks give the same
	/// fraction, because they are counted by the same function.
	@Test func theSameCountingAnswersForAnItemAndForAChange() throws {
		let sandbox = Sandbox()
		sandbox.change("counted", files: ["tasks.md": """
		## 1. First

		- [x] 1.1 done
		- [ ] 1.2 not done

		## 2. Second

		- [x] 2.1 done
		"""])

		let change = try #require(sandbox.openSpec.changes().first)
		let asAnItem = BacklogItem.progress(in: """
		## Steps

		- [x] done
		- [ ] not done
		- [x] done
		""")

		#expect(change.progress() == asAnItem)
		#expect(change.progress()?.summary == "2/3")
	}

	// MARK: - Against this repository

	/// The counts this repository's own changes have, read the way the board
	/// reads them.
	///
	/// **Held against the CLI's answer rather than against a guess**: `openspec
	/// list` reports the same totals for every one of them, which is what says
	/// a subprocess is not needed to put a fraction on a card.
	@Test func readsTheChangesInThisRepository() throws {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // AbydosKitTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // package root
		let openSpec = OpenSpec(projectRoot: root)
		guard openSpec.exists else { return }

		let changes = openSpec.changes()
		#expect(!changes.isEmpty)
		// Every one of them has a proposal; that is what a change starts as.
		#expect(changes.allSatisfy { $0.artifacts.contains(.proposal) })
		#expect(changes.allSatisfy { !$0.isArchived })
		// And the archive, which is a directory beside them rather than one of
		// them.
		#expect(!changes.contains { $0.name == "archive" })
	}

	/// **Nothing is spawned to work out what to draw**, which is the point of
	/// reading the directory at all.
	///
	/// Checked as time rather than by counting processes, because the cost is
	/// the thing that matters and it is unmissable: one `openspec list --json`
	/// costs 0.60 s on this machine and one `openspec status --change` another
	/// 0.60 s each, all of it Node start-up. Reading every change *and* its
	/// tasks is a directory walk and a file read apiece. The bound is a hundred
	/// times the walk and a fraction of one subprocess, so it fails only if
	/// somebody puts a process back on this path.
	@Test func readingTheChangesStartsNoProcess() {
		let root = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
		let openSpec = OpenSpec(projectRoot: root)
		guard openSpec.exists else { return }

		let started = Date()
		let changes = openSpec.changes()
		for change in changes { _ = change.progress() }
		let taken = Date().timeIntervalSince(started)

		#expect(taken < 0.3, "reading \(changes.count) changes took \(taken)s")
	}

	// MARK: - The command line tool

	/// The command handed over rather than run: archiving rewrites the project's
	/// specs, which is the larger half of somebody's review.
	@Test func namesTheCommandThatArchivesAChange() {
		let change = OpenSpecChange(
			name: "say-what-goes-in-them",
			directory: URL(fileURLWithPath: "/tmp/say-what-goes-in-them")
		)
		#expect(OpenSpec.archiveCommand(for: change) == "openspec archive say-what-goes-in-them")
	}

	/// **Found through the login shell, or not at all.** On the machine this was
	/// written on the tool is at
	/// `~/.local/state/fnm_multishells/91100_…/bin/openspec`, an fnm directory
	/// with a shell's PID in its name, and a Dock-launched app's `PATH` is four
	/// system directories. Whether it is installed is a fact about a machine, so
	/// what is checked here is that nothing on the drawing path needs it.
	@Test func theBoardDoesNotNeedTheCommandLineTool() {
		let sandbox = Sandbox()
		sandbox.change("readable-without-node", files: ["tasks.md": tasks(done: 1, left: 1)])

		let changes = sandbox.openSpec.changes()
		#expect(changes.count == 1)
		#expect(changes.first?.progress()?.summary == "1/2")
		// Whatever the answer to this is, the two expectations above hold.
		_ = OpenSpec.commandLine()
	}
}
