import Foundation

/// A file `init` writes so an assistant knows this backlog exists.
public struct InstructionFile: Sendable, Equatable {
	/// Whose file it is.
	public enum Ownership: Sendable, Equatable {
		/// Written for this and nothing else. Rewritten whole on every `init`.
		case owned
		/// A file the project already had opinions in — `AGENTS.md`,
		/// `copilot-instructions.md`. Ours is one fenced section of it, and a
		/// second `init` replaces that section and leaves the rest alone.
		case shared
	}

	/// Relative to the project root.
	public let path: String
	public let contents: String
	public let ownership: Ownership

	public init(path: String, contents: String, ownership: Ownership) {
		self.path = path
		self.contents = contents
		self.ownership = ownership
	}
}

/// The assistants that can be pointed at this backlog.
///
/// A closed list rather than "type the name of your tool": each one is a
/// different file in a different place with a different header, and a list of
/// five that are known to be right is worth more than a text field that writes
/// `.yourtool/skills/backlog.md` and leaves somebody to find out it was never
/// read. Adding a sixth is this file and nothing else.
public enum BacklogAssistant: String, CaseIterable, Sendable, Identifiable {
	case claude
	case copilot
	case opencode
	case codex
	case cursor

	public var id: String { rawValue }

	public var name: String {
		switch self {
		case .claude: return "Claude Code"
		case .copilot: return "GitHub Copilot CLI"
		case .opencode: return "opencode"
		case .codex: return "Codex CLI"
		case .cursor: return "Cursor Agent"
		}
	}

	/// Where its instructions go, said in one line for the chooser.
	public var writes: String {
		switch self {
		case .claude: return ".claude/skills/backlog/, .claude/commands/backlog.md"
		case .copilot: return ".github/copilot-instructions.md, .github/prompts/"
		case .opencode: return "AGENTS.md, .opencode/command/backlog.md"
		case .codex: return "AGENTS.md"
		case .cursor: return ".cursor/rules/backlog.mdc"
		}
	}

	// MARK: - Running one

	/// The command, as it is called on a PATH.
	public var executableName: String {
		switch self {
		case .claude: return "claude"
		case .copilot: return "copilot"
		case .opencode: return "opencode"
		case .codex: return "codex"
		case .cursor: return "cursor-agent"
		}
	}

	/// How to hand it a task and leave it running.
	///
	/// Interactive in every case, and not `--print` or `exec --quiet`: the
	/// whole reason the run happens in a pane rather than in the background is
	/// that somebody can read what it is doing and take it over. A run that
	/// prints its answer and exits cannot be taken over.
	public func arguments(prompt: String) -> [String] {
		switch self {
		case .claude: return [prompt]
		case .copilot: return ["--prompt", prompt]
		case .opencode: return ["run", "--continue", prompt]
		case .codex: return [prompt]
		case .cursor: return [prompt]
		}
	}

	/// The full path of the tool, or nil when it is not installed.
	///
	/// Claude Code is asked for by `AgentLauncher`, which knows the two places
	/// it installs itself that are on nobody's `PATH`. The rest go through the
	/// ordinary search, which already falls back to both Homebrews — an app
	/// started from the Finder inherits almost no `PATH`.
	public func locate() -> String? {
		if self == .claude, let known = AgentLauncher.findClaudeExecutable() { return known }
		return Executables.locate(executableName)
	}

	public var isInstalled: Bool { locate() != nil }

	// MARK: - What it is told

	/// The files that make this backlog visible to this tool.
	public func instructionFiles(projectName: String) -> [InstructionFile] {
		let pointer = BacklogInstructions.pointer(projectName: projectName)

		switch self {
		case .claude:
			return [
				InstructionFile(
					path: ".claude/skills/backlog/SKILL.md",
					contents: """
					---
					name: backlog
					description: Work the \(projectName) backlog in .abydos/backlog — file an item, pick up a ready one in a worktree of its own, and keep the spec in .abydos/backlog/spec true as part of the work. Use whenever asked to file, pick up, start, implement or finish a backlog item, to say what is left to do, or to change what the spec says.
					---

					# The backlog

					\(BacklogInstructions.pointerBody(projectName: projectName))
					""",
					ownership: .owned
				),
				InstructionFile(
					path: ".claude/commands/backlog.md",
					contents: """
					---
					description: Show the backlog, or pick up an item by number
					---

					Read `.abydos/backlog/AGENTS.md` first if you have not already this
					session — it is the whole workflow and it is one page.

					Argument: `$ARGUMENTS`

					- **Empty** — run `abydos-backlog status`, then `abydos-backlog list ready`,
					  and say what is there. Do not start anything.
					- **A number** — pick that item up: read it, then follow the
					  "picking up a ready item" order in `AGENTS.md` from step 2.
					- **`next`** — run `abydos-backlog next` and pick up what it names, or
					  say there is nothing ready.
					""",
					ownership: .owned
				),
			]

		case .copilot:
			return [
				InstructionFile(path: ".github/copilot-instructions.md", contents: pointer, ownership: .shared),
				InstructionFile(
					path: ".github/prompts/backlog.prompt.md",
					contents: """
					---
					mode: agent
					description: Pick up the next ready item from the \(projectName) backlog
					---

					Read `.abydos/backlog/AGENTS.md`, then follow "picking up a ready item"
					in it from the top. If `abydos-backlog next` names nothing, say so and
					stop rather than choosing something out of `open/`.
					""",
					ownership: .owned
				),
			]

		case .opencode:
			return [
				InstructionFile(path: "AGENTS.md", contents: pointer, ownership: .shared),
				InstructionFile(
					path: ".opencode/command/backlog.md",
					contents: """
					---
					description: Show the backlog, or pick up an item by number
					---

					Read `.abydos/backlog/AGENTS.md` first if you have not already this
					session. Then, for `$ARGUMENTS`: empty means run `abydos-backlog status`
					and report; a number means pick that item up; `next` means
					`abydos-backlog next` and pick up what it names.
					""",
					ownership: .owned
				),
			]

		case .codex:
			return [InstructionFile(path: "AGENTS.md", contents: pointer, ownership: .shared)]

		case .cursor:
			return [
				InstructionFile(
					path: ".cursor/rules/backlog.mdc",
					contents: """
					---
					description: How the \(projectName) backlog under .abydos/backlog is worked
					alwaysApply: false
					---

					# The backlog

					\(BacklogInstructions.pointerBody(projectName: projectName))
					""",
					ownership: .owned
				),
			]
		}
	}
}

/// Which assistants this project's backlog is set up for.
///
/// Written down rather than guessed from which instruction files happen to
/// exist: half of them live in files the project already had, so "is there an
/// `AGENTS.md`" answers a different question than the one being asked.
public struct BacklogConfiguration: Codable, Sendable, Equatable {
	public var assistants: [String]
	/// Whether picking an item up makes a worktree for it.
	///
	/// On by default and worth being able to turn off: a project small enough
	/// that two people are never in it at once pays the cost of a second
	/// checkout for nothing.
	public var worktrees: Bool

	public init(assistants: [BacklogAssistant] = [], worktrees: Bool = true) {
		self.assistants = assistants.map(\.rawValue)
		self.worktrees = worktrees
	}

	/// The ones this build knows about. A name written by a newer version is
	/// kept in the file and ignored here rather than dropped on the next write.
	public var known: [BacklogAssistant] {
		assistants.compactMap(BacklogAssistant.init(rawValue:))
	}

	/// The one to run when nothing says otherwise: the first that is configured
	/// *and* installed, so a project set up for two tools on a machine that has
	/// one does the obvious thing.
	public var preferred: BacklogAssistant? {
		known.first(where: \.isInstalled) ?? known.first
	}

	public static func read(_ url: URL) -> BacklogConfiguration? {
		guard let data = try? Data(contentsOf: url) else { return nil }
		return try? JSONDecoder().decode(BacklogConfiguration.self, from: data)
	}

	public func write(to url: URL) throws {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		var data = try encoder.encode(self)
		data.append(0x0A)
		try data.write(to: url, options: .atomic)
	}
}
