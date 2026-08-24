import Foundation
import Testing
@testable import AbydosKit

/// Drafting a commit message from what is staged.
///
/// What is *asked* is testable and is what matters: that it describes the
/// commit being made rather than everything on disk, that this repository's own
/// subjects go with it, and that a diff too large to send says which files it
/// did not read rather than quietly summarising half a commit. Whether the
/// model answers well is not a claim this suite can check.
struct ClaudeDraftTests {
	@discardableResult
	private func git(_ arguments: [String], in directory: URL) -> Int32 {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["git"] + arguments
		process.currentDirectoryURL = directory
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		try? process.run()
		process.waitUntilExit()
		return process.terminationStatus
	}

	private func write(_ text: String, _ name: String, in root: URL) throws {
		try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
	}

	private func repository() throws -> URL {
		let root = FileManager.default.temporaryDirectory
			.appendingPathComponent("draft-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		for command in [
			["init", "-q", "-b", "main", "."],
			["config", "user.email", "t@example.com"],
			["config", "user.name", "T"],
		] {
			#expect(git(command, in: root) == 0)
		}
		try write("one\n", "a.txt", in: root)
		#expect(git(["add", "."], in: root) == 0)
		#expect(git(["commit", "-qm", "A Java edit reaches the JVM that is already running"], in: root) == 0)
		return root
	}

	@Test func nothingStagedIsNothingToDescribe() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		// Changed but not staged: the draft describes the commit being made,
		// and there is not one.
		try write("changed\n", "a.txt", in: root)
		#expect(await ClaudeDraft.ask(in: root) == nil)
	}

	@Test func whatIsSentIsTheStagedDiff() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("staged change\n", "a.txt", in: root)
		#expect(git(["add", "a.txt"], in: root) == 0)
		// And something else that is only in the working copy.
		try write("not staged\n", "b.txt", in: root)

		guard let ask = await ClaudeDraft.ask(in: root) else {
			Issue.record("something is staged")
			return
		}
		#expect(ask.prompt.contains("staged change"))
		#expect(!ask.prompt.contains("not staged"), "the working copy is not the commit")
		#expect(ask.unread.isEmpty)
	}

	/// This repository does not write `fix: update handler`.
	@Test func theRepositorysOwnSubjectsGoWithIt() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write("staged change\n", "a.txt", in: root)
		#expect(git(["add", "a.txt"], in: root) == 0)

		guard let ask = await ClaudeDraft.ask(in: root) else {
			Issue.record("something is staged")
			return
		}
		#expect(ask.prompt.contains("A Java edit reaches the JVM that is already running"))
	}

	/// Quietly summarising half a commit produces a message that is wrong about
	/// the other half, and nothing on screen would say so.
	@Test func anOversizedDiffNamesWhatItDidNotRead() async throws {
		let root = try repository()
		defer { try? FileManager.default.removeItem(at: root) }

		try write(String(repeating: "a line of it\n", count: 400), "big.txt", in: root)
		try write(String(repeating: "and more\n", count: 400), "bigger.txt", in: root)
		#expect(git(["add", "."], in: root) == 0)

		guard let ask = await ClaudeDraft.ask(in: root, limit: 1_000) else {
			Issue.record("something is staged")
			return
		}
		#expect(!ask.unread.isEmpty, "not everything can have fitted in a thousand characters")
		for name in ask.unread {
			#expect(ask.prompt.contains(name), "\(name) is named as unread")
		}
		#expect(ask.prompt.contains("too large to include"))
	}

	@Test func aMissingCommandIsAbsenceRatherThanFailure() {
		// Nowhere to look at all: there is no `claude`, and the answer is that
		// there is none rather than an error somebody reads after pressing a
		// button that should not have been there.
		#expect(ClaudeDraft.executable(environment: ["PATH": ""], besides: []) == nil)

		// And a place that does have one is found, which is the other half of
		// the claim — otherwise this passes on a machine where nothing works.
		let bin = FileManager.default.temporaryDirectory
			.appendingPathComponent("bin-\(UUID().uuidString)")
		try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: bin) }
		let pretend = bin.appendingPathComponent("claude")
		FileManager.default.createFile(
			atPath: pretend.path, contents: Data("#!/bin/sh\n".utf8),
			attributes: [.posixPermissions: 0o755]
		)
		#expect(ClaudeDraft.executable(environment: ["PATH": bin.path], besides: []) == pretend)
	}

	@Test func theFirstLineIsTheSummaryAndTheRestIsTheDescription() {
		let draft = ClaudeDraft.parse("""
		A stash says whether it still applies

		Applying one into a mess that then has to be untangled is the failure
		worth engineering away.
		""")
		#expect(draft.summary == "A stash says whether it still applies")
		#expect(draft.description.hasPrefix("Applying one into a mess"))
	}

	@Test func aSummaryOnItsOwnHasNoDescription() {
		let draft = ClaudeDraft.parse("Release 0.4.0\n")
		#expect(draft.summary == "Release 0.4.0")
		#expect(draft.description.isEmpty)
	}

	/// A model that wraps its answer anyway should not put ``` into somebody's
	/// commit.
	@Test func fencesAroundTheAnswerAreTakenOff() {
		let draft = ClaudeDraft.parse("```\nRelease 0.4.0\n\nThe notes.\n```")
		#expect(draft.summary == "Release 0.4.0")
		#expect(draft.description == "The notes.")
	}
}
