import Foundation

/// A commit message drafted from what is staged.
///
/// **The staged diff and not the working copy.** The draft describes the commit
/// being made, not everything on disk — a page with room for a description is
/// exactly where a blank field is hardest to start, and a summary of work that
/// is not in the commit is worse than none.
///
/// **Through the `claude` command rather than the API.** This app already meets
/// Claude in its terminals and through `ClaudeHookRunner`; calling the API here
/// would add a dependency and a credential path to something that has neither.
/// When the command is not on the `PATH` the feature is *absent* rather than
/// failing when pressed.
public enum ClaudeDraft {
	/// What comes back: two fields somebody was going to type in anyway.
	public struct Draft: Sendable, Equatable {
		public let summary: String
		public let description: String

		public init(summary: String, description: String) {
			self.summary = summary
			self.description = description
		}
	}

	/// What would be sent, and what would not fit.
	public struct Ask: Sendable, Equatable {
		public let prompt: String
		/// Files whose diff was too large to include, named so the draft can
		/// say what it did not read.
		public let unread: [String]

		public init(prompt: String, unread: [String]) {
			self.prompt = prompt
			self.unread = unread
		}
	}

	public enum Failure: Error, Sendable, Equatable {
		/// There is no `claude` on the `PATH`. Not an error to report at the
		/// moment of pressing — a control that fails when pressed is worse than
		/// one that is not there — so the caller asks `isAvailable` first.
		case notInstalled
		/// Nothing is staged, so there is no commit to describe.
		case nothingStaged
		/// The command ran and said something that was not a draft.
		case said(String)
	}

	/// How much of the diff is sent before it is cut.
	///
	/// Characters rather than tokens, because a token count needs the tokeniser
	/// and this only has to be roughly right: what it is protecting against is
	/// a two-thousand-file rename landing in one request.
	public static let defaultLimit = 40_000

	/// How many recent subjects go along with it.
	///
	/// Twenty is enough to show a house style and few enough to cost nothing.
	public static let subjectsRead = 20

	// MARK: - Whether it can be done at all

	/// The places to look besides the `PATH`.
	///
	/// A parameter so a test can say "nowhere" and mean it: these are absolute
	/// and exist on the machine the suite runs on, so an empty `PATH` alone
	/// does not describe a machine without the command.
	public static func fallbackPlaces(
		home: URL = FileManager.default.homeDirectoryForCurrentUser
	) -> [URL] {
		[
			home.appendingPathComponent(".local/bin"),
			home.appendingPathComponent(".claude/local"),
			URL(fileURLWithPath: "/opt/homebrew/bin"),
			URL(fileURLWithPath: "/usr/local/bin"),
		]
	}

	/// Where the command is, or nil when it is not anywhere.
	///
	/// The `PATH` this process has, and then the places a per-user install puts
	/// it — a GUI app launched from Finder does not inherit the shell's `PATH`,
	/// so looking only there would say "not installed" on most machines that
	/// have it.
	public static func executable(
		environment: [String: String] = ProcessInfo.processInfo.environment,
		besides extra: [URL]? = nil
	) -> URL? {
		var places = (environment["PATH"] ?? "")
			.split(separator: ":")
			.map { URL(fileURLWithPath: String($0)) }
		places += extra ?? fallbackPlaces()

		for place in places {
			let candidate = place.appendingPathComponent("claude")
			if FileManager.default.isExecutableFile(atPath: candidate.path) {
				return candidate
			}
		}
		return nil
	}

	public static var isAvailable: Bool { executable() != nil }

	// MARK: - What is sent

	/// The request that would be made, or nil when nothing is staged.
	///
	/// `conventional` is the setting's answer rather than the setting itself:
	/// the kit does not read defaults for a caller that may be a test.
	public static func ask(
		in root: URL, limit: Int = defaultLimit, conventional: Bool = true
	) async -> Ask? {
		let staged = await GitRepository.run(["diff", "--cached", "--name-only"], in: root)
		let paths = staged.stdout
			.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
		guard !paths.isEmpty else { return nil }

		// Per file rather than one `git diff --cached`, so that cutting the
		// request at a budget cuts it at a file boundary and can say which
		// files went missing. A truncated hunk would produce a message that is
		// confidently wrong about the half it could see.
		var diffs: [String] = []
		var unread: [String] = []
		var spent = 0
		for path in paths {
			let diff = await GitRepository.run(["diff", "--cached", "--", path], in: root)
			let text = diff.stdout
			guard spent + text.count <= limit else {
				unread.append(path)
				continue
			}
			spent += text.count
			diffs.append(text)
		}

		let recent = await GitRepository.run(
			["log", "-\(subjectsRead)", "--format=%s"], in: root
		)
		let subjects = recent.stdout
			.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

		return Ask(
			prompt: prompt(
				diffs: diffs, subjects: subjects, unread: unread, conventional: conventional
			),
			unread: unread
		)
	}

	/// The words around the diff.
	///
	/// Two shapes, because a commit message has two audiences. Conventional
	/// Commits is what changelog, release and version tooling reads, and it is
	/// the default: a draft in prose has to be rewritten by hand before such a
	/// repository can commit it. Turned off, the recent subjects *are* the
	/// instruction — this repository does not write `fix: update handler`; it
	/// writes "A Java edit reaches the JVM that is already running".
	static func prompt(
		diffs: [String], subjects: [String], unread: [String], conventional: Bool = true
	) -> String {
		var said = """
		Write a git commit message for the staged change below.

		Answer with the summary on the first line, then a blank line, then the \
		description. No preamble, no code fences, no "Here is". If the change is \
		small enough to need no description, answer with the summary alone.
		"""

		if conventional {
			said += """


			The summary must be a Conventional Commit v1.0.0 subject line:

			  <type>[optional scope][!]: <description>

			The type is one of feat, fix, build, chore, ci, docs, style, \
			refactor, perf, test. feat is a new feature, fix is a bug fix; the \
			rest are what their names say. A scope is optional and, when given, \
			is a noun in parentheses naming a part of the codebase — a component, \
			not a file name. The description follows the colon and a space, in \
			the imperative and on one line.

			Mark a breaking change either with ! before the colon or with a \
			BREAKING CHANGE: footer in the description; BREAKING CHANGE is \
			uppercase. Footers go at the end of the description, one per line, \
			as Token: value.
			"""
		}

		if !subjects.isEmpty {
			// With the format prescribed, the subjects are demoted on purpose:
			// twenty narrative subjects and an instruction to write
			// `feat(scope):` are contradictory instructions, and examples
			// usually win. What they are still good for is the nouns — the
			// difference between `fix(navigator):` and
			// `fix(ProjectNavigatorViewController):` is a scope and a file name.
			said += conventional
				? """


				Recent subjects from this repository. They are here for its \
				vocabulary and for what it calls its parts, so the scope reads \
				like one of them — not for the shape of the subject line, which \
				is the format above:

				\(subjects.map { "- \($0)" }.joined(separator: "\n"))
				"""
				: """


				Recent subjects from this repository, so the summary matches how \
				it is written here:

				\(subjects.map { "- \($0)" }.joined(separator: "\n"))
				"""
		}

		if !unread.isEmpty {
			said += """


			These files are part of the change and their diffs were too large to \
			include. Say in the description that they were not read:

			\(unread.map { "- \($0)" }.joined(separator: "\n"))
			"""
		}

		said += "\n\nThe staged diff:\n\n" + diffs.joined(separator: "\n")
		return said
	}

	// MARK: - Reading what comes back

	/// The first line is the summary; the rest is the description.
	static func parse(_ answer: String) -> Draft {
		// Fences stripped even though the prompt asks for none: a model that
		// wraps the answer anyway should not put ``` into somebody's commit.
		var lines = answer
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.components(separatedBy: "\n")
		if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
		if lines.last?.hasPrefix("```") == true { lines.removeLast() }

		guard let summary = lines.first else { return Draft(summary: "", description: "") }
		let rest = lines.dropFirst()
			.joined(separator: "\n")
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return Draft(
			summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
			description: rest
		)
	}

	// MARK: - Doing it

	/// Asks, and answers with a draft.
	public static func draft(
		in root: URL,
		limit: Int = defaultLimit,
		conventional: Bool = true
	) async -> Result<Draft, Failure> {
		guard let command = executable() else { return .failure(.notInstalled) }
		guard let ask = await ask(in: root, limit: limit, conventional: conventional) else {
			return .failure(.nothingStaged)
		}

		let result = await run(command, prompt: ask.prompt, in: root)
		guard result.exitCode == 0 else {
			let said = result.stderr.isEmpty ? result.stdout : result.stderr
			return .failure(.said(said.trimmingCharacters(in: .whitespacesAndNewlines)))
		}
		let draft = parse(result.stdout)
		guard !draft.summary.isEmpty else { return .failure(.said("It answered with nothing.")) }
		return .success(draft)
	}

	/// Runs the command with the prompt on standard input.
	///
	/// On stdin rather than as an argument: a staged diff is tens of thousands
	/// of characters and an argument list has a limit that a large commit walks
	/// straight through.
	private static func run(
		_ command: URL,
		prompt: String,
		in root: URL
	) async -> (stdout: String, stderr: String, exitCode: Int32) {
		await withCheckedContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				let process = Process()
				process.executableURL = command
				process.arguments = ["-p"]
				process.currentDirectoryURL = root

				let out = Pipe(), err = Pipe(), input = Pipe()
				process.standardOutput = out
				process.standardError = err
				process.standardInput = input

				do {
					try process.run()
				} catch {
					continuation.resume(returning: ("", "\(error)", -1))
					return
				}

				// Written on a thread of its own and both pipes drained
				// together: a program blocked writing to a pipe nobody is
				// reading deadlocks against a reader waiting for it to finish.
				// The same lesson `ProcessPipes` records, and the same several
				// afternoons.
				DispatchQueue.global(qos: .utility).async {
					input.fileHandleForWriting.write(Data(prompt.utf8))
					try? input.fileHandleForWriting.close()
				}

				let data = out.fileHandleForReading.readDataToEndOfFile()
				let problem = err.fileHandleForReading.readDataToEndOfFile()
				process.waitUntilExit()
				continuation.resume(returning: (
					String(decoding: data, as: UTF8.self),
					String(decoding: problem, as: UTF8.self),
					process.terminationStatus
				))
			}
		}
	}
}
