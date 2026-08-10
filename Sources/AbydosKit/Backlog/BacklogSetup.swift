import Foundation

/// Making a backlog, and pointing the assistants at it.
///
/// Written so it can be run twice. The second run is the ordinary one — a new
/// version of the app with something to say in `AGENTS.md`, or somebody adding
/// a second assistant — so everything here either belongs to this tool and is
/// rewritten, or belongs to the project and is left exactly as it was found.
/// Nothing is asked twice and nothing anybody typed is overwritten.
public enum BacklogSetup {
	public struct Report: Sendable {
		public enum Outcome: String, Sendable {
			case created = "created"
			case updated = "updated"
			case kept = "left alone"
		}

		public struct Entry: Sendable {
			public let path: String
			public let outcome: Outcome
		}

		public var entries: [Entry] = []

		mutating func note(_ path: String, _ outcome: Outcome) {
			entries.append(Entry(path: path, outcome: outcome))
		}
	}

	/// Creates or brings up to date the backlog of the project at `projectRoot`.
	@discardableResult
	public static func run(
		projectRoot: URL,
		assistants: [BacklogAssistant],
		worktrees: Bool = true
	) throws -> Report {
		let backlog = Backlog(projectRoot: projectRoot)
		let projectName = projectRoot.lastPathComponent
		let manager = FileManager.default
		var report = Report()

		try AbydosFolder.create(in: projectRoot)
		try allowInGit(AbydosFolder.url(in: projectRoot).appendingPathComponent(".gitignore"))

		// The state folders. An empty one gets a `.gitkeep`, because git tracks
		// files and not directories: without one, a clone of a project whose
		// `ready/` happens to be empty arrives with no `ready/` at all, and the
		// first thing that writes to it has to know to make it.
		//
		// Only while it is empty. A folder with items in it is already in the
		// repository, and a `.gitkeep` beside forty tasks is a file that means
		// nothing sitting where somebody is looking for something.
		for state in BacklogState.created {
			let folder = backlog.directory(for: state)
			let existed = manager.fileExists(atPath: folder.path)
			try manager.createDirectory(at: folder, withIntermediateDirectories: true)

			let keep = folder.appendingPathComponent(".gitkeep")
			let contents = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
			if contents.contains(where: { $0 != ".gitkeep" && !$0.hasPrefix(".") }) {
				try? manager.removeItem(at: keep)
			} else if !manager.fileExists(atPath: keep.path) {
				try Data().write(to: keep)
			}
			report.note(relative(folder, to: projectRoot), existed ? .kept : .created)
		}

		try manager.createDirectory(at: backlog.specDirectory, withIntermediateDirectories: true)
		try write(
			specReadme(projectName: projectName),
			to: backlog.specDirectory.appendingPathComponent("README.md"),
			ownership: .owned,
			projectRoot: projectRoot,
			into: &report
		)

		// Ours, and rewritten every time: it is this version of the tool saying
		// how this version of the tool works, and a workflow document that goes
		// stale is worse than none.
		try write(
			BacklogInstructions.canonical(projectName: projectName),
			to: backlog.instructionsFile,
			ownership: .owned,
			projectRoot: projectRoot,
			into: &report
		)

		// Theirs, and written once: the README says what the folders are for,
		// and this repository's own is three pages of why. Overwriting that
		// with a template would be the kind of tool that argues with its user.
		try writeIfAbsent(
			BacklogInstructions.readme(),
			to: backlog.readmeFile,
			projectRoot: projectRoot,
			into: &report
		)
		try writeIfAbsent(
			BacklogInstructions.projectTemplate(projectName: projectName),
			to: backlog.projectFile,
			projectRoot: projectRoot,
			into: &report
		)

		let before = BacklogConfiguration.read(backlog.configFile)
		var configuration = before ?? BacklogConfiguration()
		// Added to rather than replaced: somebody running `init` again to add
		// opencode is not saying they have stopped using Claude.
		for assistant in assistants where !configuration.assistants.contains(assistant.rawValue) {
			configuration.assistants.append(assistant.rawValue)
		}
		configuration.worktrees = worktrees
		// Only when it actually changed, so running `init` again on a project
		// that is already set up touches nothing at all — which is the thing
		// that makes it safe to run again.
		if configuration != before {
			try configuration.write(to: backlog.configFile)
			report.note(relative(backlog.configFile, to: projectRoot), before == nil ? .created : .updated)
		} else {
			report.note(relative(backlog.configFile, to: projectRoot), .kept)
		}

		// Every configured assistant, not only the ones just chosen, so a
		// second run brings the first tool's files up to date too.
		var written: Set<String> = []
		for assistant in configuration.known {
			for file in assistant.instructionFiles(projectName: projectName) {
				// Two tools reading `AGENTS.md` is one file, written once.
				guard written.insert(file.path).inserted else { continue }
				try write(
					file.contents,
					to: projectRoot.appendingPathComponent(file.path),
					ownership: file.ownership,
					projectRoot: projectRoot,
					into: &report
				)
			}
		}

		return report
	}

	// MARK: - Writing

	private static func write(
		_ contents: String,
		to url: URL,
		ownership: InstructionFile.Ownership,
		projectRoot: URL,
		into report: inout Report
	) throws {
		let manager = FileManager.default
		try manager.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		let existing = try? String(contentsOf: url, encoding: .utf8)
		let text: String
		switch ownership {
		case .owned:
			text = contents.hasSuffix("\n") ? contents : contents + "\n"
		case .shared:
			text = fencing(contents, into: existing)
		}

		guard text != existing else {
			report.note(relative(url, to: projectRoot), .kept)
			return
		}
		try text.write(to: url, atomically: true, encoding: .utf8)
		report.note(relative(url, to: projectRoot), existing == nil ? .created : .updated)
	}

	private static func writeIfAbsent(
		_ contents: String,
		to url: URL,
		projectRoot: URL,
		into report: inout Report
	) throws {
		guard !FileManager.default.fileExists(atPath: url.path) else {
			report.note(relative(url, to: projectRoot), .kept)
			return
		}
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		let text = contents.hasSuffix("\n") ? contents : contents + "\n"
		try text.write(to: url, atomically: true, encoding: .utf8)
		report.note(relative(url, to: projectRoot), .created)
	}

	/// Our section of somebody else's file, between the markers.
	///
	/// A file with no markers gets them at the end rather than at the start:
	/// what is already in an `AGENTS.md` is what its author thought should be
	/// read first, and a tool that puts itself above that has decided that for
	/// them.
	static func fencing(_ contents: String, into existing: String?) -> String {
		let block = """
		\(BacklogInstructions.startMarker)
		\(contents.trimmingCharacters(in: .newlines))
		\(BacklogInstructions.endMarker)
		"""

		guard let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return block + "\n"
		}
		guard let start = existing.range(of: BacklogInstructions.startMarker),
		      let end = existing.range(of: BacklogInstructions.endMarker),
		      start.lowerBound < end.lowerBound
		else {
			let head = existing.hasSuffix("\n") ? existing : existing + "\n"
			return head + "\n" + block + "\n"
		}

		var updated = existing
		updated.replaceSubrange(start.lowerBound..<end.upperBound, with: block)
		return updated
	}

	/// Makes sure `.abydos/.gitignore` lets the backlog through.
	///
	/// The folder ignores everything by default — it is mostly one machine's
	/// caret positions — so a backlog written into it is invisible to git until
	/// something says otherwise, and "my backlog did not push" is a bad first
	/// hour with a tool.
	static func allowInGit(_ gitignore: URL) throws {
		let wanted = ["!backlog/", "!backlog/**"]
		let existing = (try? String(contentsOf: gitignore, encoding: .utf8)) ?? AbydosFolder.gitignore
		var lines = existing.components(separatedBy: "\n")
		let missing = wanted.filter { line in !lines.contains { $0.trimmingCharacters(in: .whitespaces) == line } }
		guard !missing.isEmpty else { return }

		while lines.last?.isEmpty == true { lines.removeLast() }
		lines += missing
		lines.append("")
		try lines.joined(separator: "\n").write(to: gitignore, atomically: true, encoding: .utf8)
	}

	static func relative(_ url: URL, to root: URL) -> String {
		let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
		return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
	}

	static func specReadme(projectName: String) -> String {
		"""
		# What \(projectName) does

		One file per capability, each a list of requirements. This is the
		account of the program that stays: the backlog says what to do and then
		forgets, and once enough items are in `completed/` the only other
		account of what the program does is the program itself.

		A file looks like this:

		    # Terminal

		    One paragraph on what this part of the program is.

		    ## Requirement: A pane keeps its ligatures when another is focused

		    Prose saying what is true, in the present tense, about the program as
		    it is now.

		    ### Scenario: two panes, the second focused

		    - **Given** two panes showing the same file
		    - **When** the second is focused
		    - **Then** the first still draws `!=` as one glyph

		Nothing is edited here by hand while an item is in flight. A change to
		behaviour is written as a delta inside the item that makes it —
		`spec/<capability>.md` in the item's folder, with `ADDED`, `MODIFIED` or
		`REMOVED` in front of each requirement — and folded in when the item is
		finished, by `abydos-backlog done <number>`. That way the spec and the
		code change in the same commit, and a requirement never arrives here
		before the thing it describes.

		"""
	}
}
