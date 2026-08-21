import Foundation
import Testing
@testable import AbydosKit

/// Finding what a past session left behind.
///
/// Everything here is a directory tree this test builds, except the last suite,
/// which reads the real ones on this machine when they are there — a layout
/// belonging to another program is not a contract, and a suite that only ever
/// reads its own fixtures cannot notice it changing.
struct AgentSessionSlugTests {
	@Test func aProjectPathBecomesADirectoryName() {
		#expect(AgentSessions.slug(ofPath: "/Users/philipparndt/dev/abydos")
			== "-Users-philipparndt-dev-abydos")
	}

	/// Two characters in a row become two dashes, which is what a worktree under
	/// `.claude` looks like — checked against the ones on this machine.
	@Test func aDotAfterASeparatorMakesTwoDashes() {
		#expect(AgentSessions.slug(ofPath: "/Users/philipparndt/dev/abydos/.claude/worktrees/backlog-spec")
			== "-Users-philipparndt-dev-abydos--claude-worktrees-backlog-spec")
	}

	@Test func aDotInsideANameIsADashToo() {
		#expect(AgentSessions.slug(ofPath: "/tmp/my.project") == "-tmp-my-project")
	}

	/// A trailing separator would put a trailing dash on the name, which is a
	/// directory nobody has.
	@Test func aTrailingSeparatorIsNotPartOfTheName() {
		#expect(AgentSessions.slug(ofPath: "/Users/x/dev/abydos/") == "-Users-x-dev-abydos")
		#expect(AgentSessions.slug(ofPath: "/") == "-")
	}

	/// **The mapping is lossy and nothing inverts it.** These two paths are
	/// different directories and produce one name; the section reads the name a
	/// project's own path produces and guesses nothing.
	@Test func twoPathsCanProduceOneName() {
		#expect(AgentSessions.slug(ofPath: "/a/b.c") == AgentSessions.slug(ofPath: "/a/b/c"))
	}

	/// `/tmp` is a symlink here, and a session started under it is filed under
	/// whichever spelling its shell had. Both are offered.
	@Test func aSymlinkedPathIsTriedBothWays() {
		let names = AgentSessions.slugs(of: URL(fileURLWithPath: "/tmp"))
		#expect(names.contains("-tmp"))
		#expect(names.contains("-private-tmp"))
	}

	@Test func aPathThatResolvesToItselfIsTriedOnce() {
		let names = AgentSessions.slugs(of: URL(fileURLWithPath: "/Users"))
		#expect(names == ["-Users"])
	}
}

/// The sessions of a project, read off a tree this test makes.
struct AgentSessionReadingTests {
	/// A `/tmp` and a `~` of the test's own, so nothing reads the machine's.
	private struct Machine {
		let root: URL
		let temporary: URL
		let home: URL
		let project: URL
		let uid: uid_t = 501

		init() throws {
			root = URL(fileURLWithPath: NSTemporaryDirectory())
				.appendingPathComponent("agent-sessions-\(UUID().uuidString)")
			temporary = root.appendingPathComponent("tmp")
			home = root.appendingPathComponent("home")
			project = root.appendingPathComponent("work/probe")
			for url in [temporary, home, project] {
				try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
			}
		}

		var slug: String { AgentSessions.slug(ofPath: FilePath.canonical(project)) }

		/// Writes a session's files, as Claude Code would leave them.
		@discardableResult
		func session(
			_ id: String, files: [String: String], tasks: [String: String] = [:],
			transcript: String? = nil
		) throws -> URL {
			let directory = temporary
				.appendingPathComponent("claude-\(uid)/\(slug)/\(id)", isDirectory: true)
			for (name, contents) in files {
				let url = directory.appendingPathComponent("scratchpad/\(name)")
				try FileManager.default.createDirectory(
					at: url.deletingLastPathComponent(), withIntermediateDirectories: true
				)
				try contents.write(to: url, atomically: true, encoding: .utf8)
			}
			for (name, contents) in tasks {
				let url = directory.appendingPathComponent("tasks/\(name)")
				try FileManager.default.createDirectory(
					at: url.deletingLastPathComponent(), withIntermediateDirectories: true
				)
				try contents.write(to: url, atomically: true, encoding: .utf8)
			}
			if let transcript {
				let url = home.appendingPathComponent(".claude/projects/\(slug)/\(id).jsonl")
				try FileManager.default.createDirectory(
					at: url.deletingLastPathComponent(), withIntermediateDirectories: true
				)
				try transcript.write(to: url, atomically: true, encoding: .utf8)
			}
			return directory
		}

		func sessions() -> [AgentSession] {
			AgentSessions.sessions(
				of: project, uid: uid, temporaryDirectory: temporary, home: home
			)
		}

		func clean() { try? FileManager.default.removeItem(at: root) }
	}

	private func userLine(_ text: String) -> String {
		let record: [String: Any] = ["type": "user", "message": ["role": "user", "content": text]]
		let data = try! JSONSerialization.data(withJSONObject: record)
		return String(decoding: data, as: UTF8.self)
	}

	@Test func aSessionThatLeftFilesHasEverythingARowNeeds() throws {
		let machine = try Machine()
		defer { machine.clean() }
		try machine.session(
			"aaaa-1", files: ["run.log": "output", "shot.png": "not really a png"],
			tasks: ["agent-1.jsonl": "{}"],
			transcript: userLine("fix the crash when a tab is torn off")
		)

		let sessions = machine.sessions()
		#expect(sessions.count == 1)
		let unmeasured = try #require(sessions.first)
		// **The cheap read says nothing about size**, because counting means
		// walking and that happens after the tree is up.
		#expect(unmeasured.isMeasured == false)
		#expect(unmeasured.fileCount == 0)
		#expect(unmeasured.hasAnything)

		let session = AgentSessions.measured(unmeasured)
		#expect(session.id == "aaaa-1")
		#expect(session.isMeasured)
		#expect(session.fileCount == 3)
		#expect(session.bytes > 0)
		#expect(session.scratchpad?.lastPathComponent == "scratchpad")
		#expect(session.tasks?.lastPathComponent == "tasks")
		#expect(session.transcript != nil)
		#expect(session.lastWrote > .distantPast)

		let asked = AgentSessions.firstRequest(in: try #require(session.transcript))
		#expect(asked == "fix the crash when a tab is torn off")
	}

	/// **`/tmp` is cleared on reboot.** A session whose files are gone has no
	/// row: one leading nowhere is worse than an absence.
	@Test func aSessionThatLeftNothingIsNotThere() throws {
		let machine = try Machine()
		defer { machine.clean() }
		// The directory exists and holds no files at all.
		try FileManager.default.createDirectory(
			at: machine.temporary.appendingPathComponent(
				"claude-501/\(machine.slug)/empty-1/scratchpad", isDirectory: true
			),
			withIntermediateDirectories: true
		)
		try machine.session("full-1", files: ["a.txt": "something"])

		#expect(machine.sessions().map(\.id) == ["full-1"])
	}

	@Test func newestFirst() throws {
		let machine = try Machine()
		defer { machine.clean() }
		let older = try machine.session("older", files: ["a.txt": "one"])
		try machine.session("newer", files: ["b.txt": "two"])
		// Backdate the first, since both were written in the same instant.
		try FileManager.default.setAttributes(
			[.modificationDate: Date().addingTimeInterval(-3600)],
			ofItemAtPath: older.appendingPathComponent("scratchpad/a.txt").path
		)

		#expect(machine.sessions().map(\.id) == ["newer", "older"])
	}

	@Test func anotherProjectsSessionsAreNotThisProjects() throws {
		let machine = try Machine()
		defer { machine.clean() }
		try machine.session("mine", files: ["a.txt": "one"])
		// A session filed under a different project's name.
		try FileManager.default.createDirectory(
			at: machine.temporary.appendingPathComponent(
				"claude-501/-somewhere-else/theirs/scratchpad", isDirectory: true
			),
			withIntermediateDirectories: true
		)
		try "x".write(
			to: machine.temporary.appendingPathComponent(
				"claude-501/-somewhere-else/theirs/scratchpad/b.txt"
			),
			atomically: true, encoding: .utf8
		)

		#expect(machine.sessions().map(\.id) == ["mine"])
	}

	@Test func aProjectNobodyHasWorkedOnHasNone() throws {
		let machine = try Machine()
		defer { machine.clean() }
		#expect(machine.sessions().isEmpty)
	}

	@Test func aSessionWithNoTranscriptStillHasARow() throws {
		let machine = try Machine()
		defer { machine.clean() }
		try machine.session("no-transcript", files: ["a.txt": "one"])

		let session = try #require(machine.sessions().first)
		#expect(session.transcript == nil)
		#expect(AgentSessions.measured(session).fileCount == 1)
	}

	// MARK: - What was asked

	private func transcript(_ lines: [String]) throws -> URL {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("transcript-\(UUID().uuidString).jsonl")
		try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
		return url
	}

	/// A slash command is what somebody typed, and the two tags together are it.
	@Test func aSlashCommandIsSaidAsOne() throws {
		let url = try transcript([userLine(
			"<command-message>opsx:propose</command-message>\n"
			+ "<command-name>/opsx:propose</command-name>\n"
			+ "<command-args>improve the editor's tabs</command-args>"
		)])
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(AgentSessions.firstRequest(in: url) == "/opsx:propose improve the editor's tabs")
	}

	/// The harness's own caveat is not a request, and the real one is later.
	@Test func aCaveatBlockIsSkippedForWhatComesAfterIt() throws {
		let url = try transcript([
			userLine("<local-command-caveat>Caveat: The messages below were generated…</local-command-caveat>"),
			userLine("the backlog does not show the progress bar"),
		])
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(AgentSessions.firstRequest(in: url) == "the backlog does not show the progress bar")
	}

	/// Content arrives as blocks as well as a string.
	@Test func contentInBlocksIsReadToo() throws {
		let record: [String: Any] = [
			"type": "user",
			"message": ["role": "user", "content": [
				["type": "text", "text": "why is the pane empty"],
			]],
		]
		let line = String(decoding: try JSONSerialization.data(withJSONObject: record), as: UTF8.self)
		let url = try transcript([line])
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(AgentSessions.firstRequest(in: url) == "why is the pane empty")
	}

	@Test func aRequestIsOneLineAndBounded() throws {
		let url = try transcript([userLine("first line\n\n   second     line\t" + String(repeating: "x", count: 300))])
		defer { try? FileManager.default.removeItem(at: url) }
		let asked = try #require(AgentSessions.firstRequest(in: url))
		#expect(!asked.contains("\n"))
		#expect(asked.hasPrefix("first line second line "))
		#expect(asked.count == 121)   // 120 and the ellipsis
	}

	/// **Nothing found is a row named by its time and size**, which is still
	/// more than an id — so this answers nothing rather than something wrong.
	@Test func aTranscriptWithNothingAskedInItAnswersNothing() throws {
		let url = try transcript([
			#"{"type":"mode","mode":"normal"}"#,
			#"{"type":"assistant","message":{"role":"assistant","content":"hello"}}"#,
			"not json at all",
		])
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(AgentSessions.firstRequest(in: url) == nil)
	}

	@Test func aMissingTranscriptAnswersNothing() {
		#expect(AgentSessions.firstRequest(
			in: URL(fileURLWithPath: "/nowhere/at/all/x.jsonl")
		) == nil)
	}

	/// The read is bounded, and a record beyond the bound is not found — which
	/// is the trade the bound exists to make.
	@Test func whatIsPastTheBoundIsNotFound() throws {
		let padding = String(repeating: " ", count: 4096)
		let url = try transcript([
			#"{"type":"mode","padding":""# + padding + #""}"#,
			userLine("the request nobody will see"),
		])
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(AgentSessions.firstRequest(in: url, limit: 512) == nil)
		#expect(AgentSessions.firstRequest(in: url, limit: 64 * 1024) == "the request nobody will see")
	}
}

/// The real directories on this machine, when there are any.
///
/// **Another program's layout is not a contract**, and a suite that only reads
/// its own fixtures cannot notice it changing. Skipped where there is nothing to
/// read, which is what a machine that has never run Claude Code looks like.
struct AgentSessionLiveTests {
	@Test func thisRepositorysOwnSessionsAreFound() throws {
		let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
		let sessions = AgentSessions.sessions(of: project)
		guard !sessions.isEmpty else { return }

		print("  SESSIONS: \(sessions.count) for \(project.lastPathComponent)")
		for session in sessions.prefix(3).map(AgentSessions.measured) {
			let asked = session.transcript.flatMap { AgentSessions.firstRequest(in: $0) }
			print("    \(session.id.prefix(8))  \(session.fileCount) files, "
				+ "\(session.bytes / 1024) KiB — \(asked ?? "(nothing asked)")")
		}

		// Every one of them has something, because one without is not listed.
		#expect(sessions.allSatisfy { $0.hasAnything })
		// And they are in order.
		#expect(sessions == sessions.sorted { $0.lastWrote > $1.lastWrote })
	}
}

/// What real transcripts taught the reader.
struct AgentSessionRealShapeTests {
	private func transcript(_ records: [[String: Any]]) throws -> URL {
		let url = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("real-\(UUID().uuidString).jsonl")
		let lines = records.map {
			String(decoding: try! JSONSerialization.data(withJSONObject: $0), as: UTF8.self)
		}
		try lines.joined(separator: "\n").appending("\n")
			.write(to: url, atomically: true, encoding: .utf8)
		return url
	}

	private func user(_ text: String) -> [String: Any] {
		["type": "user", "message": ["role": "user", "content": text]]
	}

	/// **Found by reading the real ones**: a session on this machine begins with
	/// `/clear`, and a row labelled "/clear" says nothing about what that
	/// session was for. The request after it does.
	@Test func aBareCommandLosesToTheRequestAfterIt() throws {
		let url = try transcript([
			user("<command-name>/clear</command-name>\n<command-args></command-args>"),
			user("make the tabs come back out of the overflow menu"),
		])
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(AgentSessions.firstRequest(in: url) == "make the tabs come back out of the overflow menu")
	}

	/// And it wins when there is nothing else: `/clear` is more than an id.
	@Test func aBareCommandIsBetterThanNothing() throws {
		let url = try transcript([
			user("<command-name>/clear</command-name>\n<command-args></command-args>"),
		])
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(AgentSessions.firstRequest(in: url) == "/clear")
	}

	/// A command with arguments is what somebody typed, and is taken first.
	@Test func aCommandWithArgumentsIsTheLabel() throws {
		let url = try transcript([
			user("<command-name>/opsx:apply</command-name>\n<command-args>a-change-name</command-args>"),
			user("and now something else"),
		])
		defer { try? FileManager.default.removeItem(at: url) }
		#expect(AgentSessions.firstRequest(in: url) == "/opsx:apply a-change-name")
	}
}

/// What reading the real ones costs.
///
/// **The bound in `measure` is why this is here.** A scratchpad is somebody's
/// working directory and one on this machine holds 3,409 files and 27 MB; the
/// root is read when the tree is read, so it has to cost nothing anybody
/// notices. The load is printed beside the number, because a number without it
/// cannot be told from a regression.
struct AgentSessionCostTests {
	@Test func readingThemCostsNothingWorthNoticing() {
		let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
		guard !AgentSessions.sessions(of: project).isEmpty else { return }

		let started = Date()
		let sessions = AgentSessions.sessions(of: project)
		let read = Date().timeIntervalSince(started)

		// The half that used to be on the open path.
		let walking = Date()
		let measured = sessions.map(AgentSessions.measured)
		let walked = Date().timeIntervalSince(walking)

		let labelled = Date()
		let labels = sessions.compactMap { $0.transcript.flatMap { AgentSessions.firstRequest(in: $0) } }
		let labelling = Date().timeIntervalSince(labelled)

		let files = measured.reduce(0) { $0 + $1.fileCount }
		print(String(
			format: "  SESSIONS cost: %d sessions, %d files — "
				+ "read %.0f ms, measured %.0f ms, %d labels %.0f ms",
			sessions.count, files, read * 1000, walked * 1000, labels.count, labelling * 1000
		))
		print("  " + MachineLoad.said)
		// **The claim: the read is the cheap one.** What used to be one number
		// is now two, and only the first is on the path that opens a project.
		#expect(read < walked)

		// A bound rather than a budget: what this must not be is *seconds*, and
		// `Stopwatch` is the thing that decides whether a tighter one may be
		// asserted at all under the suite's own load.
		#expect(read < 5)
		#expect(labelling < 5)
	}
}
