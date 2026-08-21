import Foundation

/// What a past Claude Code session left behind for a project.
///
/// **A session's working files are useful for weeks and reachable by nobody.**
/// Every session gets a scratch directory keyed by the project's path —
/// reproductions, driven-run logs, screenshots of a fault, a throwaway checkout
/// somebody was told not to drive against a real one — and finding one means
/// knowing that the path is
/// `/tmp/claude-<uid>/-Users-philipparndt-dev-abydos/<session-id>/scratchpad`,
/// with every `/` and `.` of the project's own name turned into `-`.
///
/// Read, never written: these are another program's directories, and this reads
/// them the way the dependency sections read a lock file.
public struct AgentSession: Equatable, Sendable {
	/// The session's own id, which is the directory's name.
	public let id: String
	/// `/tmp/claude-<uid>/<slug>/<id>`, which holds the rest.
	public let directory: URL
	/// Where the files are. Nil for a session that made none.
	public let scratchpad: URL?
	/// What subagents wrote, when the session ran any.
	public let tasks: URL?
	/// When anything under it was last written.
	public let lastWrote: Date
	/// How much is in it, and how many files — what a row says instead of an id.
	///
	/// **Zero until it has been measured.** Reading these on open cost 127 ms
	/// for the seven sessions this repository has on this machine, because it
	/// means walking 6,920 files — one scratchpad alone holds 3,409 of them and
	/// 27 MB, since a scratchpad is somebody's working directory and may hold a
	/// checkout. That is a tenth of a second added to opening a project, growing
	/// with every session anybody ever ran, for two numbers in a subtitle. So
	/// the walk happens after the tree is up and off the main thread, and
	/// `isMeasured` says whether it has.
	public let bytes: Int64
	public let fileCount: Int
	/// Whether `bytes` and `fileCount` have been counted yet.
	public let isMeasured: Bool
	/// `~/.claude/projects/<slug>/<id>.jsonl`, when it is still there.
	///
	/// **Not a file to open.** It is where a row's label comes from, and its
	/// path is worth having for pointing another tool at it; the session
	/// writing this one produced twenty megabytes of it.
	public let transcript: URL?

	public init(
		id: String,
		hasAnything: Bool = true,
		directory: URL,
		scratchpad: URL?,
		tasks: URL?,
		lastWrote: Date,
		bytes: Int64,
		fileCount: Int,
		isMeasured: Bool = true,
		transcript: URL?
	) {
		self.id = id
		self.hasAnything = hasAnything
		self.directory = directory
		self.scratchpad = scratchpad
		self.tasks = tasks
		self.lastWrote = lastWrote
		self.bytes = bytes
		self.fileCount = fileCount
		self.isMeasured = isMeasured
		self.transcript = transcript
	}

	/// Whether there is anything to show. A session that left nothing has no
	/// row: a row leading nowhere is worse than an absence.
	///
	/// Answered without counting: a directory with an entry in it has something,
	/// and how much is a question for later.
	public let hasAnything: Bool
}

public enum AgentSessions {
	/// How Claude Code spells a project's path when it uses it as a directory
	/// name: every `/` and every `.` becomes `-`.
	///
	/// `/Users/philipparndt/dev/abydos` → `-Users-philipparndt-dev-abydos`, and a
	/// worktree under `.claude` gets a double dash from the two characters in a
	/// row: `-Users-…-abydos--claude-worktrees-backlog-spec`.
	///
	/// **Lossy on purpose, and not reversed anywhere.** Both `/` and `.` map to
	/// the same character, so two paths can produce one key. Nothing here tries
	/// to invert it: a project's own path produces one name, that directory is
	/// read, and nothing is guessed.
	public static func slug(ofPath path: String) -> String {
		var trimmed = path
		// A trailing separator would add a trailing dash. `URL.path` does not
		// produce one, but a path from a string may.
		while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
		return String(trimmed.map { $0 == "/" || $0 == "." ? "-" : $0 })
	}

	/// The names this project could be filed under.
	///
	/// **Two, because `/tmp` is a symlink here.** A session started in a
	/// directory under `/tmp` is filed under whatever spelling its shell had —
	/// this machine holds one filed as `-private-tmp-claude-501-…`, which is the
	/// resolved form — and a project opened from the other spelling would look
	/// at an empty directory. Both are tried and whichever exists is used;
	/// neither is invented.
	public static func slugs(of project: URL) -> [String] {
		var names = [slug(ofPath: project.path)]
		let resolved = FilePath.canonical(project)
		if resolved != project.path { names.append(slug(ofPath: resolved)) }
		return names
	}

	/// Where a session's files live, for a user id.
	public static func root(
		uid: uid_t = getuid(), temporaryDirectory: URL = URL(fileURLWithPath: "/tmp")
	) -> URL {
		temporaryDirectory.appendingPathComponent("claude-\(uid)", isDirectory: true)
	}

	/// Where the transcripts live.
	public static func transcriptRoot(
		home: URL = FileManager.default.homeDirectoryForCurrentUser
	) -> URL {
		home.appendingPathComponent(".claude/projects", isDirectory: true)
	}

	/// The sessions that left something behind for this project, newest first.
	///
	/// Nothing is run and nothing is written. A session that left no files is
	/// not in the list at all — `/tmp` is cleared on reboot, so a row for one
	/// whose files are gone would lead nowhere.
	public static func sessions(
		of project: URL,
		uid: uid_t = getuid(),
		temporaryDirectory: URL = URL(fileURLWithPath: "/tmp"),
		home: URL = FileManager.default.homeDirectoryForCurrentUser
	) -> [AgentSession] {
		let manager = FileManager.default
		let base = root(uid: uid, temporaryDirectory: temporaryDirectory)

		var found: [AgentSession] = []
		var seen: Set<String> = []
		for name in slugs(of: project) {
			let directory = base.appendingPathComponent(name, isDirectory: true)
			guard let ids = try? manager.contentsOfDirectory(atPath: directory.path) else { continue }
			let transcripts = transcriptRoot(home: home).appendingPathComponent(name, isDirectory: true)
			for id in ids where !id.hasPrefix(".") {
				guard seen.insert(id).inserted else { continue }
				let session = read(
					id: id,
					in: directory.appendingPathComponent(id, isDirectory: true),
					transcripts: transcripts
				)
				if session.hasAnything { found.append(session) }
			}
		}
		// Newest first: which session this was is remembered by when, far more
		// often than by name.
		return found.sorted { $0.lastWrote > $1.lastWrote }
	}

	/// One session, without walking anything.
	///
	/// Three stats and at most two shallow listings: whether the directories are
	/// there, when they last changed, and whether there is an entry in them.
	/// What is *in* them is `measure(_:)`'s question, asked later and elsewhere.
	private static func read(id: String, in directory: URL, transcripts: URL) -> AgentSession {
		let manager = FileManager.default
		func directoryIfPresent(_ name: String) -> URL? {
			let url = directory.appendingPathComponent(name, isDirectory: true)
			var isDirectory: ObjCBool = false
			guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory),
			      isDirectory.boolValue
			else { return nil }
			return url
		}
		let scratchpad = directoryIfPresent("scratchpad")
		let tasks = directoryIfPresent("tasks")
		let places = [scratchpad, tasks].compactMap { $0 }

		// A directory's own modification time, which is when something was last
		// added to it or taken out of it. Less exact than the newest file's —
		// rewriting a file in place does not touch it — which is why the
		// measuring pass sharpens it afterwards.
		var newest = Date.distantPast
		for place in [directory] + places {
			if let written = (try? place.resourceValues(forKeys: [.contentModificationDateKey]))?
				.contentModificationDate { newest = max(newest, written) }
		}

		let anything = places.contains { place in
			!((try? manager.contentsOfDirectory(atPath: place.path))?
				.filter { !$0.hasPrefix(".") } ?? []).isEmpty
		}

		let transcript = transcripts.appendingPathComponent("\(id).jsonl")
		return AgentSession(
			id: id,
			hasAnything: anything,
			directory: directory,
			scratchpad: scratchpad,
			tasks: tasks,
			lastWrote: newest,
			bytes: 0,
			fileCount: 0,
			isMeasured: false,
			transcript: manager.fileExists(atPath: transcript.path) ? transcript : nil
		)
	}

	/// The same session with its files counted.
	///
	/// **Off the main thread and after the tree is up.** This is the expensive
	/// half — a bounded walk of everything under the session — and it exists so
	/// that a row can say how much is in it without opening a project costing a
	/// tenth of a second per seven sessions.
	public static func measured(_ session: AgentSession) -> AgentSession {
		var bytes: Int64 = 0
		var files = 0
		var newest = Date.distantPast
		for place in [session.scratchpad, session.tasks].compactMap({ $0 }) {
			let walked = measure(place)
			bytes += walked.bytes
			files += walked.files
			newest = max(newest, walked.newest)
		}
		// **The files' own time, not the greater of the two.** A directory's
		// modification time is when something was last added to it or taken out,
		// which is a fair proxy before anything has been walked and a worse
		// answer afterwards: a scratchpad whose files are a week old, copied into
		// a directory made this morning, is a week old. Where the walk found no
		// files there is nothing better than the proxy, so it stands.
		if files == 0 { newest = session.lastWrote }
		return AgentSession(
			id: session.id,
			hasAnything: session.hasAnything,
			directory: session.directory,
			scratchpad: session.scratchpad,
			tasks: session.tasks,
			lastWrote: newest,
			bytes: bytes,
			fileCount: files,
			isMeasured: true,
			transcript: session.transcript
		)
	}

	/// How much is under a directory, and when it was last written.
	///
	/// **Bounded.** A scratchpad is somebody's working directory and may hold a
	/// checkout of a whole project; walking all of it to put a size on a row
	/// nobody has opened is not worth a second of anybody's time. The walk stops
	/// at `limit` entries and what it has by then is what the row says.
	static func measure(_ directory: URL, limit: Int = 4000) -> (bytes: Int64, files: Int, newest: Date) {
		let manager = FileManager.default
		guard let walker = manager.enumerator(
			at: directory,
			includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
			options: [.skipsHiddenFiles]
		) else { return (0, 0, (try? directory.resourceValues(forKeys: [.contentModificationDateKey]))?
			.contentModificationDate ?? .distantPast) }

		var bytes: Int64 = 0
		var files = 0
		var newest = Date.distantPast
		var visited = 0
		for case let url as URL in walker {
			visited += 1
			if visited > limit { break }
			guard let values = try? url.resourceValues(
				forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
			) else { continue }
			if let written = values.contentModificationDate { newest = max(newest, written) }
			guard values.isRegularFile == true else { continue }
			files += 1
			bytes += Int64(values.fileSize ?? 0)
		}
		return (bytes, files, newest)
	}

	/// What somebody would type to carry on a session.
	///
	/// **The one thing a session id is actually good for.** Claude Code resumes a
	/// conversation by id, so the id nobody can memorise becomes a command
	/// anybody can paste — which is what makes a row for a session from last
	/// Tuesday worth more than the files under it.
	///
	/// Run in the project the session belongs to: the sessions of a directory are
	/// keyed by that directory, and `--resume` looks for the id under the one it
	/// is started in. No `cd` is put in front of it, because the terminal in this
	/// app is already there and a paste with somebody else's path in it is a
	/// paste to edit.
	public static func resumeCommand(for session: AgentSession) -> String {
		"claude --resume \(session.id)"
	}

	/// The first thing that was asked of a session, from the head of its
	/// transcript.
	///
	/// **From the head, never by reading the file.** A day's session in this
	/// repository produced a twenty-megabyte transcript and there are eighteen of
	/// them for one project; a tree row is not worth a hundred megabytes of I/O.
	/// What is not in the first `limit` bytes is not found, and the row is then
	/// named by its time and size, which is still more than an id.
	///
	/// Three shapes arrive, all three seen on this machine:
	///
	///  - **prose**, which is the answer;
	///  - **a slash command**, wrapped in `<command-name>` and `<command-args>` —
	///    those two together are what somebody typed, and the label says so;
	///  - **a caveat block** the harness inserts before a local command's
	///    output, which is nobody's request and is skipped.
	public static func firstRequest(in transcript: URL, limit: Int = 64 * 1024) -> String? {
		guard let handle = try? FileHandle(forReadingFrom: transcript) else { return nil }
		defer { try? handle.close() }
		guard let head = try? handle.read(upToCount: limit), !head.isEmpty else { return nil }

		// The last line of a bounded read is very likely cut in half; it is
		// dropped rather than parsed.
		var lines = String(decoding: head, as: UTF8.self).split(separator: "\n").map(String.init)
		if lines.count > 1, head.last != UInt8(ascii: "\n") { lines.removeLast() }

		// **A bare command is a last resort, and that came from looking at real
		// transcripts.** One session on this machine begins with `/clear`,
		// which says nothing about what the session was for; the request after
		// it does. A command *with* arguments — `/opsx:propose improve the
		// editor's tabs` — is exactly what somebody typed and is taken as it
		// stands.
		var lastResort: String?
		for line in lines {
			guard let data = line.data(using: .utf8),
			      let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			      record["type"] as? String == "user",
			      let message = record["message"] as? [String: Any]
			else { continue }
			guard let text = said(message["content"]), let asked = request(in: text) else { continue }
			if isBareCommand(asked) {
				if lastResort == nil { lastResort = asked }
				continue
			}
			return asked
		}
		return lastResort
	}

	/// A slash command with nothing after it: `/clear`, `/compact`. It names a
	/// thing that was done to the session rather than what the session was for.
	private static func isBareCommand(_ asked: String) -> Bool {
		asked.hasPrefix("/") && !asked.contains(" ")
	}

	/// The text of a message, whichever of the two shapes its content is in.
	private static func said(_ content: Any?) -> String? {
		if let text = content as? String { return text }
		guard let blocks = content as? [Any] else { return nil }
		let text = blocks.compactMap { block -> String? in
			guard let block = block as? [String: Any], block["type"] as? String == "text" else {
				return nil
			}
			return block["text"] as? String
		}.joined(separator: " ")
		return text.isEmpty ? nil : text
	}

	/// What somebody actually asked, out of one message, or nil when the message
	/// is not a request at all.
	static func request(in text: String) -> String? {
		func tagged(_ tag: String) -> String? {
			guard let open = text.range(of: "<\(tag)>"),
			      let close = text.range(of: "</\(tag)>", range: open.upperBound..<text.endIndex)
			else { return nil }
			return String(text[open.upperBound..<close.lowerBound])
				.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		// A slash command: the name and its arguments are what was typed.
		if let name = tagged("command-name") {
			let arguments = tagged("command-args") ?? ""
			return tidy(arguments.isEmpty ? name : "\(name) \(arguments)")
		}
		// The harness's caveat before a local command's output. Not a request,
		// and the real one is in a later record.
		if text.contains("<local-command-caveat>") || text.contains("<command-message>") {
			return nil
		}
		// A tool's result, or an interruption, rather than something asked.
		if text.hasPrefix("<") && text.contains(">") && !text.contains(" ") { return nil }

		let asked = tidy(text)
		return asked.isEmpty ? nil : asked
	}

	/// One line, short enough for a tree row.
	private static func tidy(_ text: String, budget: Int = 120) -> String {
		var flattened = ""
		var lastWasSpace = false
		for character in text {
			if character.isWhitespace || character.isNewline {
				if !lastWasSpace, !flattened.isEmpty { flattened.append(" ") }
				lastWasSpace = true
			} else {
				flattened.append(character)
				lastWasSpace = false
			}
		}
		let trimmed = flattened.trimmingCharacters(in: .whitespaces)
		guard trimmed.count > budget else { return trimmed }
		return String(trimmed.prefix(budget)) + "\u{2026}"
	}
}
