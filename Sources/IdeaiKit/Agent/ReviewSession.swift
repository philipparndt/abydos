import Foundation

/// One finding reported by a review agent.
public struct ReviewFinding: Identifiable, Equatable, Sendable {
	public enum Severity: String, Sendable, CaseIterable {
		case error, warning, info

		/// Sort order — worst first, which is how a review should be read.
		var rank: Int {
			switch self {
			case .error: return 0
			case .warning: return 1
			case .info: return 2
			}
		}
	}

	public let id: UUID
	public var file: String
	public var line: Int
	public var severity: Severity
	public var title: String
	public var detail: String
	/// Optional suggested replacement, shown inline when present.
	public var suggestion: String?

	public init(
		id: UUID = UUID(),
		file: String,
		line: Int,
		severity: Severity,
		title: String,
		detail: String,
		suggestion: String? = nil
	) {
		self.id = id
		self.file = file
		self.line = line
		self.severity = severity
		self.title = title
		self.detail = detail
		self.suggestion = suggestion
	}
}

/// Collects an agent's structured output for one review.
///
/// The agent reports through MCP tool calls rather than by printing, so findings
/// arrive typed and incrementally. The raw terminal session stays available
/// alongside this, which is what lets the user switch from the review UI into
/// the conversation and take over.
public final class ReviewSession {
	public private(set) var findings: [ReviewFinding] = []
	public private(set) var statusMessage: String?
	public private(set) var isComplete = false

	/// Fired whenever findings or status change.
	public var onChange: (() -> Void)?

	/// Base directory that relative paths in findings resolve against.
	public let projectRoot: URL

	public init(projectRoot: URL) {
		self.projectRoot = projectRoot
	}

	public func absoluteURL(for finding: ReviewFinding) -> URL {
		if finding.file.hasPrefix("/") {
			return URL(fileURLWithPath: finding.file)
		}
		return projectRoot.appendingPathComponent(finding.file)
	}

	// MARK: - Tools

	/// The tools an agent may call during a review.
	public func makeTools() -> [MCPServer.Tool] {
		[reportFindingsTool(), reportStatusTool(), completeTool()]
	}

	private func reportFindingsTool() -> MCPServer.Tool {
		MCPServer.Tool(
			name: "report_review_findings",
			// The description is the agent's only instruction manual for this
			// tool, so it states the contract rather than just naming it.
			description: """
			Report code review findings to the ideai editor UI. Call this as soon as \
			you identify issues — you may call it multiple times as you work, and \
			findings appear immediately. Use paths relative to the repository root.
			""",
			inputSchema: [
				"type": "object",
				"properties": [
					"findings": [
						"type": "array",
						"description": "The findings to add.",
						"items": [
							"type": "object",
							"properties": [
								"file": ["type": "string", "description": "Path relative to the repository root."],
								"line": ["type": "integer", "description": "1-based line number."],
								"severity": [
									"type": "string",
									"enum": ["error", "warning", "info"],
									"description": "error: a bug or breakage. warning: risky or unclear. info: a suggestion.",
								],
								"title": ["type": "string", "description": "One-line summary."],
								"detail": ["type": "string", "description": "Why it matters, and what to do."],
								"suggestion": ["type": "string", "description": "Optional replacement code."],
							],
							"required": ["file", "line", "severity", "title", "detail"],
						],
					],
				],
				"required": ["findings"],
			]
		) { [weak self] arguments in
			guard let self else { return "Session ended." }
			let raw = arguments["findings"] as? [[String: Any]] ?? []
			let added = self.add(rawFindings: raw)
			return "Recorded \(added) finding\(added == 1 ? "" : "s"). Total: \(self.findings.count)."
		}
	}

	private func reportStatusTool() -> MCPServer.Tool {
		MCPServer.Tool(
			name: "report_review_status",
			description: "Report what you are currently working on, shown as progress in the ideai UI.",
			inputSchema: [
				"type": "object",
				"properties": [
					"message": ["type": "string", "description": "Short progress description."],
				],
				"required": ["message"],
			]
		) { [weak self] arguments in
			guard let self else { return "Session ended." }
			self.statusMessage = arguments["message"] as? String
			self.onChange?()
			return "Status updated."
		}
	}

	private func completeTool() -> MCPServer.Tool {
		MCPServer.Tool(
			name: "complete_review",
			description: "Signal that the review is finished. Call this once, after reporting all findings.",
			inputSchema: [
				"type": "object",
				"properties": [
					"summary": ["type": "string", "description": "Optional closing summary."],
				],
			]
		) { [weak self] arguments in
			guard let self else { return "Session ended." }
			self.isComplete = true
			self.statusMessage = arguments["summary"] as? String ?? "Review complete."
			self.onChange?()
			return "Review marked complete."
		}
	}

	// MARK: - Ingestion

	/// Converts raw tool arguments into findings, skipping malformed entries.
	///
	/// Tolerant on purpose: a model that mislabels one severity or omits a line
	/// number should not cost the user the rest of the review.
	@discardableResult
	func add(rawFindings: [[String: Any]]) -> Int {
		var added = 0
		for raw in rawFindings {
			guard let file = raw["file"] as? String, !file.isEmpty else { continue }
			guard let title = raw["title"] as? String, !title.isEmpty else { continue }

			let line = (raw["line"] as? Int) ?? Int(raw["line"] as? String ?? "") ?? 1
			let severity = ReviewFinding.Severity(
				rawValue: (raw["severity"] as? String)?.lowercased() ?? "info"
			) ?? .info

			findings.append(ReviewFinding(
				file: file,
				line: max(1, line),
				severity: severity,
				title: title,
				detail: raw["detail"] as? String ?? "",
				suggestion: (raw["suggestion"] as? String).flatMap { $0.isEmpty ? nil : $0 }
			))
			added += 1
		}

		if added > 0 {
			// Worst first, then grouped by file so related findings read together.
			findings.sort {
				$0.severity.rank != $1.severity.rank
					? $0.severity.rank < $1.severity.rank
					: ($0.file == $1.file ? $0.line < $1.line : $0.file < $1.file)
			}
			onChange?()
		}
		return added
	}

	public func reset() {
		findings.removeAll()
		statusMessage = nil
		isComplete = false
		onChange?()
	}
}

/// Builds the command line that runs an agent against an ideai MCP server.
public enum AgentLauncher {
	public struct Command {
		public let executable: String
		public let arguments: [String]
	}

	/// Locates the `claude` executable.
	///
	/// A GUI app does not inherit a login shell's PATH, so the usual install
	/// locations are checked directly before falling back to a bare name.
	public static func findClaudeExecutable() -> String? {
		let candidates = [
			"/opt/homebrew/bin/claude",
			"/usr/local/bin/claude",
			NSHomeDirectory() + "/.claude/local/claude",
			NSHomeDirectory() + "/.local/bin/claude",
		]
		return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
	}

	/// Builds an interactive review invocation.
	///
	/// Interactive rather than `--print`: the session must stay alive so the user
	/// can switch to the chat and take it over. `--strict-mcp-config` keeps the
	/// user's own MCP servers out of this session, and confines it to ours.
	public static func reviewCommand(
		executable: String,
		server: MCPServer,
		prompt: String
	) -> Command {
		var arguments: [String] = []
		arguments += ["--mcp-config", server.configurationJSON()]
		arguments += ["--strict-mcp-config"]

		// Pre-allow only our reporting tools, so the review is not interrupted by
		// a permission prompt for the thing it was asked to do.
		let allowed = server.qualifiedToolNames()
		if !allowed.isEmpty {
			arguments += ["--allowedTools"] + allowed
		}
		arguments.append(prompt)

		return Command(executable: executable, arguments: arguments)
	}

	/// The prompt used for a branch review.
	public static func reviewPrompt(baseBranch: String) -> String {
		"""
		Review the changes on this branch compared to \(baseBranch).

		Report every issue you find by calling the report_review_findings tool \
		rather than printing them — the results are displayed in a navigable UI. \
		Call report_review_status as you go so progress is visible, and call \
		complete_review when you are done.

		Focus on correctness bugs, then risky or unclear code. Be specific about \
		file and line.
		"""
	}
}
