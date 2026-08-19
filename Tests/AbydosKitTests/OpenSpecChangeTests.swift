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

	/// This package, which is a project with an `openspec/` of its own.
	private static var packageRoot: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()  // AbydosKitTests
			.deletingLastPathComponent()  // Tests
			.deletingLastPathComponent()  // package root
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
		// The summary lists what is written and names what is wanted next, and
		// the empty `specs/` counts as neither.
		#expect(change.artifactSummary == "proposal \u{2014} needs design")
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

	@Test func aChangeStillBeingWrittenSaysWhatItNeedsNext() throws {
		let sandbox = Sandbox()
		sandbox.change("early", files: ["proposal.md": "## Why\n"])

		let change = try #require(sandbox.openSpec.changes().first)
		// Nothing at all rather than 0/0: a change still being written has no
		// fraction, and a card says which documents exist instead.
		#expect(change.progress() == nil)
		#expect(change.state(progress: nil) == .writing)
		// And what it is waiting for, which is the useful half at that stage.
		#expect(change.nextArtifact == .design)
		#expect(change.artifactSummary == "proposal \u{2014} needs design")
	}

	/// The chain, one document at a time, which is what a card counts down.
	@Test func whatIsNeededNextFollowsTheSchemasChain() throws {
		let sandbox = Sandbox()
		sandbox.change("a", files: ["design.md": "## Context\n"])
		sandbox.change("b", files: ["proposal.md": "x", "design.md": "x"])
		sandbox.change("c", files: [
			"proposal.md": "x", "design.md": "x", "specs/editor/spec.md": "x",
		])
		sandbox.change("d", files: [
			"proposal.md": "x", "design.md": "x", "specs/editor/spec.md": "x",
			"tasks.md": tasks(done: 0, left: 1),
		])

		let byName = Dictionary(uniqueKeysWithValues: sandbox.openSpec.changes().map { ($0.name, $0) })
		#expect(byName["a"]?.nextArtifact == .proposal)
		#expect(byName["b"]?.nextArtifact == .specs)
		#expect(byName["c"]?.nextArtifact == .tasks)
		// Every document there, so there is nothing to name.
		#expect(byName["d"]?.nextArtifact == nil)
	}

	/// **`openspec list` calls this one `in-progress` and this calls it `ready`,
	/// and the disagreement is the point.** The CLI is answering "has work
	/// started" from a task count; a board is answering "what can I pick up".
	@Test func aChangeWithNothingTickedIsReadyRatherThanInProgress() throws {
		let sandbox = Sandbox()
		sandbox.change("ready", files: ["tasks.md": tasks(done: 0, left: 30)])

		let change = try #require(sandbox.openSpec.changes().first)
		let progress = change.progress()
		// The fraction is the number the CLI reports either way, which is what
		// keeps the disagreement to the eye and out of the data.
		#expect(progress?.summary == "0/30")
		#expect(change.state(progress: progress) == .ready)
		#expect(change.state(progress: progress) != .inProgress)
	}

	@Test func aChangePartWayThroughIsInProgress() throws {
		let sandbox = Sandbox()
		sandbox.change("started", files: ["tasks.md": tasks(done: 4, left: 26)])

		let change = try #require(sandbox.openSpec.changes().first)
		let progress = change.progress()
		#expect(progress?.summary == "4/30")
		#expect(change.state(progress: progress) == .inProgress)
	}

	/// Complete, and not archived — which are two states, because one of them is
	/// waiting for `openspec archive` to be run.
	@Test func aChangeWithEveryTaskTickedIsComplete() throws {
		let sandbox = Sandbox()
		sandbox.change("finished", files: ["tasks.md": tasks(done: 9, left: 0)])

		let change = try #require(sandbox.openSpec.changes().first)
		let progress = change.progress()
		#expect(progress?.isComplete == true)
		#expect(change.state(progress: progress) == .complete)
		#expect(change.state(progress: progress) != .archived)
	}

	@Test func anArchivedChangeIsInItsOwnState() throws {
		let sandbox = Sandbox()
		// Half-ticked on purpose: what makes it archived is where it is, not
		// what its tasks say. `openspec archive` is somebody's decision.
		sandbox.change("done-last-week", archived: true, files: ["tasks.md": tasks(done: 1, left: 1)])

		let change = try #require(sandbox.openSpec.archived().first)
		#expect(change.state(progress: change.progress()) == .archived)
	}

	/// A schema this reader does not know is named, not placed.
	///
	/// The states above are readable from a directory listing because
	/// `spec-driven`'s chain makes `tasks.md` imply the rest. That is true of
	/// exactly one schema, and sorting another one by the same rule would be a
	/// card that looks answered and is guessed.
	@Test func aChangeWithAnUnknownSchemaIsNotSorted() throws {
		let sandbox = Sandbox()
		sandbox.change("elsewhere", files: [
			".openspec.yaml": "schema: some-other-workflow\ncreated: 2026-08-18\n",
			"tasks.md": tasks(done: 3, left: 1),
		])

		let change = try #require(sandbox.openSpec.changes().first)
		#expect(change.isSchemaUnderstood == false)
		// Every task ticked would be `inProgress` under the rule that does not
		// apply here; it goes to `writing` and says why instead.
		#expect(change.state(progress: change.progress()) == .writing)
		#expect(change.artifactSummary == "unknown schema: some-other-workflow")
		#expect(change.nextArtifact == nil)
		// The fraction still counts: `- [x]` means the same thing in any schema.
		#expect(change.progress()?.summary == "3/4")
	}

	/// A missing header is `spec-driven`, not unknown.
	@Test func aChangeWithNoHeaderIsReadAsTheSchemaItLooksLike() throws {
		let sandbox = Sandbox()
		sandbox.change("headerless", files: ["tasks.md": tasks(done: 1, left: 1)])

		let change = try #require(sandbox.openSpec.changes().first)
		#expect(change.schema == nil)
		#expect(change.isSchemaUnderstood)
		#expect(change.state(progress: change.progress()) == .inProgress)
	}

	/// Every state a change can be in is a column, and every column can hold
	/// one — a board with a state nothing reaches is a column nobody can fill.
	@Test func everyStateIsAColumnAndEveryColumnIsReachable() throws {
		let sandbox = Sandbox()
		sandbox.change("only-proposal", files: ["proposal.md": "x"])
		sandbox.change("ready-to-apply", files: ["tasks.md": tasks(done: 0, left: 2)])
		sandbox.change("part-done", files: ["tasks.md": tasks(done: 1, left: 1)])
		sandbox.change("all-done", files: ["tasks.md": tasks(done: 2, left: 0)])
		sandbox.change("last-week", archived: true, files: ["tasks.md": tasks(done: 2, left: 0)])

		let all = sandbox.openSpec.changes() + sandbox.openSpec.archived()
		let reached = Set(all.map { $0.state(progress: $0.progress()) })
		#expect(reached == Set(OpenSpecState.board))
		#expect(OpenSpecState.board.count == 5)
		// Last, where `completed` is on the other board.
		#expect(OpenSpecState.board.last == .archived)
	}

	// MARK: - The command a card offers

	/// **Not `openspec apply`.** There is no such verb — applying is `openspec
	/// instructions apply --change <name>` printing what to do and an agent
	/// then doing it, so what a person pastes is the slash command.
	@Test func aChangeThatCanBePickedUpOffersTheCommandThatPicksItUp() throws {
		let sandbox = Sandbox()
		sandbox.change("ready-to-apply", files: ["tasks.md": tasks(done: 0, left: 2)])

		let change = try #require(sandbox.openSpec.changes().first)
		#expect(
			OpenSpec.applyCommand(for: change, in: .ready)
				== "/opsx:apply ready-to-apply"
		)
	}

	/// Offered where it can be acted on and nowhere else: a command an agent
	/// then refuses is worse than no menu entry.
	@Test func theApplyCommandIsOfferedOnlyWhereItCanBeActedOn() throws {
		let sandbox = Sandbox()
		sandbox.change("a-change", files: ["tasks.md": tasks(done: 0, left: 2)])
		let change = try #require(sandbox.openSpec.changes().first)

		let offered = OpenSpecState.board.filter {
			OpenSpec.applyCommand(for: change, in: $0) != nil
		}
		#expect(offered == [.ready, .inProgress])
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
		let openSpec = OpenSpec(projectRoot: Self.packageRoot)
		guard openSpec.exists else { return }

		// **Not "there is at least one change".** That was written while there
		// were eight, and it went red the afternoon the last of them was
		// archived — a test asserting a fact about the repository on the day it
		// was written, which is the same mistake as a timing bound chosen alone.
		// What is durable is that whatever is there reads correctly.
		let changes = openSpec.changes()
		#expect(changes.allSatisfy { $0.artifacts.contains(.proposal) })
		#expect(changes.allSatisfy { !$0.isArchived })
		// The archive is where this repository's changes end up, and there is no
		// path by which one is un-archived, so this only ever grows.
		#expect(openSpec.archived().allSatisfy { $0.isArchived })
		// And the archive, which is a directory beside them rather than one of
		// them.
		#expect(!changes.contains { $0.name == "archive" })
	}

	/// The fraction on a card is the number the CLI reports.
	///
	/// **The one thing that was already right, held so it stays right** while
	/// the states around it are replaced. `openspec list --json` gives
	/// `completedTasks` and `totalTasks` per change; this counts `- [x]` against
	/// `- [ ]` and never spawns anything. They have agreed for every change in
	/// this repository since the board was written, and this is what would
	/// notice if they stopped.
	///
	/// Skipped where the CLI is not installed, the same way the language-server
	/// tests are: whether somebody has it is a fact about their machine. One
	/// invocation, ~0.60 s of Node start-up — which is affordable once in a
	/// suite and is exactly why nothing on the drawing path does it.
	///
	/// **Archived changes are not in this comparison, because the CLI does not
	/// list them**: `openspec list` has `--specs`, `--changes` and `--sort` and
	/// no way to ask for the archive. They are counted below instead, against a
	/// second implementation written here.
	@Test func theFractionIsTheNumberTheCLIReports() throws {
		let root = Self.packageRoot
		let openSpec = OpenSpec(projectRoot: root)
		guard openSpec.exists, let tool = OpenSpec.commandLine() else { return }

		let process = Process()
		process.executableURL = URL(fileURLWithPath: tool)
		process.arguments = ["list", "--json"]
		process.currentDirectoryURL = root
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = FileHandle.nullDevice
		try process.run()
		let output = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		guard process.terminationStatus == 0 else { return }

		let parsed = try JSONSerialization.jsonObject(with: output) as? [String: Any]
		let listed = (parsed?["changes"] as? [[String: Any]]) ?? []
		guard !listed.isEmpty else { return }

		let read = Dictionary(uniqueKeysWithValues: openSpec.changes().map { ($0.name, $0) })
		for entry in listed {
			let name = try #require(entry["name"] as? String)
			let change = try #require(read[name], "the CLI lists \(name) and this did not read it")
			let total = try #require(entry["totalTasks"] as? Int)
			let done = try #require(entry["completedTasks"] as? Int)
			guard total > 0 else { continue }
			let progress = try #require(change.progress())
			#expect(progress.total == total, "\(name): total")
			#expect(progress.done == done, "\(name): done")
		}
	}

	/// The same counting over the archive, which the CLI will not list.
	///
	/// Against a second implementation rather than against nothing: a plain scan
	/// for lines beginning `- [x]` or `- [ ]`, which is what the fraction claims
	/// to be. Two ways of counting the same file is the most this can do without
	/// the CLI, and it is enough to catch a parser that starts skipping a shape
	/// of line.
	@Test func theArchivesFractionsCountTheSameWayTwice() throws {
		let openSpec = OpenSpec(projectRoot: Self.packageRoot)
		guard openSpec.exists else { return }

		for change in openSpec.archived() {
			guard let progress = change.progress() else { continue }
			let text = try String(contentsOf: change.tasksFile, encoding: .utf8)
			var done = 0
			var total = 0
			for line in text.components(separatedBy: .newlines) {
				let trimmed = line.trimmingCharacters(in: .whitespaces)
				if trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") { done += 1; total += 1 }
				else if trimmed.hasPrefix("- [ ]") { total += 1 }
			}
			#expect(progress.done == done, "\(change.name): done")
			#expect(progress.total == total, "\(change.name): total")
		}
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

	/// The other command handed over rather than run, and for a stronger reason:
	/// `openspec init` asks which assistants to write slash commands and skills
	/// for, and answering that for somebody writes files into their repository.
	/// Spelled once, here, so that a view cannot hold a second spelling.
	@Test func namesTheCommandThatSetsUpOpenSpec() {
		#expect(OpenSpec.initCommand() == "openspec init")
		// No `--tools`: `all` writes two dozen tools' worth of files nobody
		// asked for, `none` leaves a directory no assistant can drive, and the
		// question is the person's to answer in the terminal it is asked in.
		#expect(!OpenSpec.initCommand().contains("--tools"))
	}

	/// A machine with no `openspec` on it can still be told what to install,
	/// which is what the offer says in place of a command it cannot run.
	@Test func saysHowToGetTheToolWhenItIsMissing() {
		#expect(OpenSpec.installHint.contains("openspec"))
		#expect(!OpenSpec.installHint.isEmpty)
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
