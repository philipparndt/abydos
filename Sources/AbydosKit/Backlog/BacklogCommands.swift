import Foundation

/// `abydos-backlog`, the command line over the same files the app shows.
///
/// Everything here is something somebody could do with `mv` and an editor, and
/// that is on purpose: the tool is a convenience over a directory, never a
/// gatekeeper in front of one. What it is actually for is the three things that
/// are tedious by hand — giving out the next number, making a worktree and
/// starting an agent in it, and folding a spec delta in without losing a
/// paragraph.
public enum BacklogCommands {
	// MARK: - Entry

	public static func run(arguments: [String]) async -> Int32 {
		var arguments = arguments
		let verb = arguments.isEmpty ? "status" : arguments.removeFirst()

		do {
			switch verb {
			case "init": return try await runInit(arguments)
			case "status": return try status()
			case "list", "ls": return try list(arguments)
			case "show", "cat": return try show(arguments)
			case "new": return try new(arguments)
			case "move", "mv": return try move(arguments)
			case "attach": return try attach(arguments)
			case "next": return try next()
			case "start": return try await start(arguments)
			case "spec": return try spec(arguments)
			case "fold": return try await fold(arguments, thenComplete: false)
			case "done": return try await fold(arguments, thenComplete: true)
			case "runs": return try runs(arguments)
			case "help", "--help", "-h": usage(); return 0
			default:
				warn("abydos-backlog: no such command \u{201C}\(verb)\u{201D}")
				usage()
				return 2
			}
		} catch {
			warn("abydos-backlog: \(error)")
			return 1
		}
	}

	// MARK: - init

	private static func runInit(_ arguments: [String]) async throws -> Int32 {
		let options = Options(arguments)
		let root = await projectRoot(preferGitTop: true)
		let backlog = Backlog(projectRoot: root)

		out("Abydos backlog \u{2014} \(root.path)")
		out(backlog.exists
			? "There is a backlog here already; this will bring it up to date."
			: "There is no backlog here yet.")
		out("")

		let chosen: [BacklogAssistant]
		if let named = options.value("assistant") ?? options.value("agent") {
			chosen = try parse(assistants: named)
		} else if options.has("yes") || !isInteractive {
			// Not a terminal: a script, a hook, a `make` goal. Asking a
			// question nobody can answer would hang, so the installed ones are
			// the answer and the line above says which they were.
			chosen = BacklogAssistant.allCases.filter(\.isInstalled)
			out("Setting up for the assistants that are installed: "
				+ (chosen.isEmpty ? "none found" : chosen.map(\.name).joined(separator: ", ")))
		} else {
			chosen = ask()
		}

		let report = try BacklogSetup.run(
			projectRoot: root,
			assistants: chosen,
			worktrees: !options.has("no-worktrees")
		)

		out("")
		for entry in report.entries where entry.outcome != .kept {
			out("  \(entry.outcome.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0))  \(entry.path)")
		}
		let kept = report.entries.filter { $0.outcome == .kept }.count
		if kept > 0 { out("  \(kept) already there and left alone") }

		await warnAboutIgnoredFiles(report, in: root)

		out("")
		out("Read \(BacklogSetup.relative(backlog.instructionsFile, to: root)) \u{2014} it is the workflow, and it is one page.")
		out("Then: abydos-backlog new \"the first thing that is wrong\"")
		return 0
	}

	/// Says when what was just written will never be committed.
	///
	/// Worth a process, because the failure is silent and slow: a project that
	/// ignores `.claude/` — plenty do, for the worktrees an agent leaves there
	/// — gets a skill file that works perfectly for the person who ran `init`
	/// and does not exist for anybody who clones. The first they hear of it is
	/// an assistant that has never heard of the backlog.
	private static func warnAboutIgnoredFiles(_ report: BacklogSetup.Report, in root: URL) async {
		let written = report.entries
			.filter { $0.outcome != .kept }
			.map(\.path)
		guard !written.isEmpty else { return }

		let result = await GitRepository.run(["check-ignore"] + written, in: root)
		// 0 means at least one was ignored; 1 means none were; anything else is
		// not a repository, or no git, and there is nothing to say.
		guard result.exitCode == 0 else { return }
		let ignored = result.stdout
			.split(separator: "\n")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
		guard !ignored.isEmpty else { return }

		out("")
		out("Ignored by git, so nobody who clones this will get \(ignored.count == 1 ? "it" : "them"):")
		for path in ignored { out("  \(path)") }
		out("These describe how to work this project, so they are worth committing.")
	}

	/// The one question `init` asks.
	private static func ask() -> [BacklogAssistant] {
		out("Which assistant works this backlog?")
		out("")
		let all = BacklogAssistant.allCases
		let width = all.map(\.name.count).max() ?? 0
		for (index, assistant) in all.enumerated() {
			let name = assistant.name.padding(toLength: width, withPad: " ", startingAt: 0)
			let mark = assistant.isInstalled ? "  \u{2022} installed" : ""
			out("  \(index + 1)  \(name)   \(assistant.writes)\(mark)")
		}
		let installed = all.filter(\.isInstalled)
		out("")
		out("More than one is fine \u{2014} 1,3. 0 for none: the backlog is still made, and")
		out("the instructions are still written, they are just not pointed at anything.")
		let suggestion = installed.isEmpty
			? "0"
			: installed.map { String((all.firstIndex(of: $0) ?? 0) + 1) }.joined(separator: ",")
		FileHandle.standardOutput.write(Data("[\(suggestion)] > ".utf8))

		let typed = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
		let answer = typed.isEmpty ? suggestion : typed
		if answer == "0" { return [] }

		let picked = answer.split(whereSeparator: { ",  ".contains($0) })
			.compactMap { Int($0) }
			.compactMap { $0 >= 1 && $0 <= all.count ? all[$0 - 1] : nil }
		guard !picked.isEmpty else {
			out("Nothing recognised in \u{201C}\(answer)\u{201D} \u{2014} setting up for none.")
			return []
		}
		return picked
	}

	private static func parse(assistants named: String) throws -> [BacklogAssistant] {
		try named.split(separator: ",").map { name in
			let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
			guard let assistant = BacklogAssistant(rawValue: trimmed) else {
				throw Failure("no such assistant \u{201C}\(trimmed)\u{201D} — one of: "
					+ BacklogAssistant.allCases.map(\.rawValue).joined(separator: ", "))
			}
			return assistant
		}
	}

	// MARK: - Reading

	private static func status() throws -> Int32 {
		let backlog = try existing()
		out(backlog.directory.path)
		out("")
		for state in BacklogState.board {
			let items = backlog.items(in: state)
			let count = String(items.count).leftPadded(to: 4)
			out("  \(count)  \(state.directoryName.padding(toLength: 12, withPad: " ", startingAt: 0))\(state.summary)")
		}

		let live = BacklogRuns(projectRoot: backlog.projectRoot).all().filter(\.isPresent)
		if !live.isEmpty {
			out("")
			out("Being worked on:")
			for run in live { out("  \(String(format: "%04d", run.number))  \(run.branch)  \(run.worktreePath)") }
		}

		let specs = BacklogSpecStore(backlog: backlog).documents()
		if !specs.isEmpty {
			let requirements = specs.reduce(0) { $0 + $1.requirements.count }
			out("")
			out("Spec: \(specs.count) \(specs.count == 1 ? "capability" : "capabilities"), "
				+ "\(requirements) \(requirements == 1 ? "requirement" : "requirements")")
		}
		return 0
	}

	private static func list(_ arguments: [String]) throws -> Int32 {
		let backlog = try existing()
		let states: [BacklogState]
		if let named = arguments.first(where: { !$0.hasPrefix("-") }) {
			guard let state = BacklogState(rawValue: named) else {
				throw Failure("no such state \u{201C}\(named)\u{201D} — one of: "
					+ BacklogState.allCases.map(\.rawValue).joined(separator: ", "))
			}
			states = [state]
		} else {
			states = BacklogState.board
		}

		for state in states {
			let items = backlog.items(in: state)
			guard !items.isEmpty else { continue }
			if states.count > 1 { out("\n\(state.title)") }
			for item in items {
				var line = "  \(String(format: "%04d", item.number))  "
				// The fraction before the title rather than after it, so a
				// column of them reads down: how far along everything is, is
				// the question a list is being scanned for.
				line += (item.progress()?.summary ?? "").leftPadded(to: 5) + "  \(item.title)"
				var marks: [String] = []
				if !item.images().isEmpty { marks.append("\(item.images().count) image(s)") }
				if !item.specDeltas().isEmpty { marks.append("spec") }
				if !marks.isEmpty { line += "  [\(marks.joined(separator: ", "))]" }
				out(line)
			}
		}
		return 0
	}

	private static func show(_ arguments: [String]) throws -> Int32 {
		let backlog = try existing()
		let item = try find(arguments, in: backlog)
		out(item.text())

		if let progress = item.progress() {
			out("\n---")
			out(progress.isComplete
				? "Steps: \(progress.summary) — every one ticked."
				: "Steps: \(progress.summary) done, \(progress.total - progress.done) still missing.")
		} else {
			out("\n---\nNo `## Steps` checklist, so there is no saying what is left.")
		}

		let attachments = item.attachments()
		if !attachments.isEmpty {
			out("\n---\nCarries:")
			for file in attachments { out("  \(BacklogSetup.relative(file, to: backlog.projectRoot))") }
		}
		let deltas = item.specDeltas()
		if !deltas.isEmpty {
			out("\n---\nSpec delta:")
			for file in deltas { out("  \(BacklogSetup.relative(file, to: backlog.projectRoot))") }
			let problems = BacklogSpecStore(backlog: backlog).check(item)
			for problem in problems { out("  ! \(problem)") }
		}
		return 0
	}

	private static func next() throws -> Int32 {
		let backlog = try existing()
		guard let item = BacklogRunner.next(in: backlog) else {
			out("Nothing is ready.")
			return 1
		}
		out("\(String(format: "%04d", item.number))  \(item.title)")
		out(item.displayPath(from: backlog.projectRoot))
		return 0
	}

	// MARK: - Writing

	private static func new(_ arguments: [String]) throws -> Int32 {
		let backlog = try existing()
		let options = Options(arguments)
		let title = options.rest.joined(separator: " ").trimmingCharacters(in: .whitespaces)
		guard !title.isEmpty else { throw Failure("what is it called? — abydos-backlog new \"the title\"") }

		let state = try options.value("state").map { try parse(state: $0) } ?? .open
		let item = try backlog.create(title: title, state: state, carriesFiles: options.has("files"))
		out("\(String(format: "%04d", item.number))  \(item.title)")
		out(item.displayPath(from: backlog.projectRoot))
		return 0
	}

	private static func move(_ arguments: [String]) throws -> Int32 {
		let backlog = try existing()
		let options = Options(arguments)
		guard options.rest.count >= 2 else { throw Failure("abydos-backlog move <number> <state>") }
		let item = try find([options.rest[0]], in: backlog)
		let state = try parse(state: options.rest[1])

		// Said rather than refused. Moving something into `ready` by hand is a
		// judgement — sometimes the delta is stale on purpose because this item
		// is the thing that will fix it — and a tool that will not let somebody
		// make it is a tool they stop using.
		if state == .ready {
			for problem in BacklogSpecStore(backlog: backlog).check(item) { out("  ! \(problem)") }
		}

		let moved = try backlog.move(item, to: state)
		out("\(String(format: "%04d", moved.number))  \(moved.state.directoryName)/")
		return 0
	}

	private static func attach(_ arguments: [String]) throws -> Int32 {
		let backlog = try existing()
		let options = Options(arguments)
		guard options.rest.count >= 2 else { throw Failure("abydos-backlog attach <number> <file>") }
		let item = try find([options.rest[0]], in: backlog)

		var last = ""
		var current = item
		for path in options.rest.dropFirst() {
			let file = URL(fileURLWithPath: path)
			guard FileManager.default.fileExists(atPath: file.path) else {
				throw Failure("\(file.path) does not exist")
			}
			let result = try backlog.attach(file, to: current)
			current = result.item
			last = BacklogSetup.relative(result.attachment, to: backlog.projectRoot)
			out(last)
		}
		if item.folder == nil {
			out("\(String(format: "%04d", item.number)) is a folder now, so it can carry things.")
		}
		return 0
	}

	// MARK: - The spec

	private static func spec(_ arguments: [String]) throws -> Int32 {
		let backlog = try existing()
		let store = BacklogSpecStore(backlog: backlog)
		var arguments = arguments
		let verb = arguments.isEmpty ? "list" : arguments.removeFirst()

		switch verb {
		case "list":
			let documents = store.documents()
			guard !documents.isEmpty else {
				out("The spec is empty. It fills up as items are finished.")
				return 0
			}
			for document in documents {
				out("  \(document.capability.padding(toLength: 20, withPad: " ", startingAt: 0))"
					+ "\(document.requirements.count) requirements")
			}
			return 0

		case "show":
			guard let name = arguments.first else { throw Failure("abydos-backlog spec show <capability>") }
			let document = store.document(for: name)
			out(document.text)
			return 0

		case "add":
			// Here because a delta lives inside the item's folder and most
			// items are one file. Without this, the first step of writing a
			// delta is knowing that the item has to become a directory first —
			// which is a thing about how this is stored, not about the work.
			guard arguments.count >= 2 else { throw Failure("abydos-backlog spec add <number> <capability>") }
			let item = try find([arguments[0]], in: backlog)
			let capability = Backlog.slug(from: arguments[1])
			let folder = try backlog.makeFolder(for: item)
			guard let directory = folder.folder else { throw BacklogError.unreadable(folder.file) }
			let deltas = directory.appendingPathComponent(Backlog.specDirectoryName, isDirectory: true)
			try FileManager.default.createDirectory(at: deltas, withIntermediateDirectories: true)
			let file = deltas.appendingPathComponent("\(capability).md")
			guard !FileManager.default.fileExists(atPath: file.path) else {
				out(BacklogSetup.relative(file, to: backlog.projectRoot))
				return 0
			}
			try deltaTemplate(capability: capability, store: store)
				.write(to: file, atomically: true, encoding: .utf8)
			out(BacklogSetup.relative(file, to: backlog.projectRoot))
			return 0

		case "check":
			// One item, or every item that carries a delta — which is the check
			// worth running before a merge: it is the whole backlog agreeing
			// with the spec, not one file agreeing with itself.
			let items: [BacklogItem]
			if let first = arguments.first {
				items = [try find([first], in: backlog)]
			} else {
				// Everything except what is finished. A completed item's delta
				// has already been folded, so checking it asks whether the
				// spec still contains what was put into it — which is always
				// an `ADDED` that collides, and forty of those hide the one
				// real answer.
				items = backlog.items()
					.filter { $0.state != .completed && !$0.specDeltas().isEmpty }
			}
			var problems = 0
			for item in items {
				for problem in store.check(item) {
					out("\(String(format: "%04d", item.number))  \(problem)")
					problems += 1
				}
			}
			out(problems == 0
				? "Every delta fits the spec (\(items.count) checked)."
				: "\(problems) that would not fold.")
			return problems == 0 ? 0 : 1

		default:
			throw Failure("abydos-backlog spec [list | show <capability> | add <number> <capability> | check [number]]")
		}
	}

	/// A delta with the existing requirement names in it, commented out.
	///
	/// The commonest way a delta fails to fold is a `MODIFIED` naming a
	/// requirement whose heading has since been reworded, and the names are the
	/// one thing that has to match exactly. So they are put in front of
	/// whoever is about to write one.
	private static func deltaTemplate(capability: String, store: BacklogSpecStore) -> String {
		let existing = store.document(for: capability).requirements
		var text = """
		<!-- What this item changes about `\(capability)`. Folded into
		     .abydos/backlog/spec/\(capability).md by `abydos-backlog done`.

		     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
		     Write each requirement as it will read in the spec, in the present
		     tense — not as a description of the edit.

		"""
		if existing.isEmpty {
			text += "     Nothing has been said about \(capability) yet, so this is all ADDED.\n"
		} else {
			text += "     The requirements already there, to name exactly:\n"
			for requirement in existing { text += "       \(requirement.name)\n" }
		}
		text += """
		-->

		## ADDED Requirement:

		### Scenario:

		- **Given**
		- **When**
		- **Then**

		"""
		return text
	}

	/// `fold` puts the delta in the spec; `done` folds and then completes.
	private static func fold(_ arguments: [String], thenComplete: Bool) async throws -> Int32 {
		let backlog = try existing()
		let item = try find(arguments, in: backlog)
		let store = BacklogSpecStore(backlog: backlog)

		let deltas = item.specDeltas()
		let problems = try store.fold(item)
		for problem in problems { out("  ! \(problem)") }

		if deltas.isEmpty {
			out("\(String(format: "%04d", item.number)) carries no spec delta.")
		} else {
			out("Folded \(deltas.count) \(deltas.count == 1 ? "delta" : "deltas") into "
				+ BacklogSetup.relative(backlog.specDirectory, to: backlog.projectRoot) + "/")
		}

		guard thenComplete else { return problems.isEmpty ? 0 : 1 }

		// Said before the move, and named rather than counted.
		//
		// Not a refusal: the person running this is looking at the work and
		// knows whether a step was dropped on purpose. But finishing an item
		// whose own list says five things are missing is worth being told
		// about, because the commonest reason is that they were done and never
		// ticked — and then the list is a lie that outlives the work.
		let remaining = item.remainingSteps()
		if !remaining.isEmpty {
			out("\(remaining.count) \(remaining.count == 1 ? "step is" : "steps are") still unticked:")
			for step in remaining { out("  [ ] \(step)") }
			out("Tick what you did; leave what you did not, and say underneath why.")
		}

		// Completed anyway, and the problems printed above.
		//
		// The alternative — refusing to finish over a heading that has drifted
		// — leaves the item in `in-progress/` with the work merged, which is a
		// worse lie than a spec with a gap in it that was just printed in red.
		let moved = try backlog.move(item, to: .completed)
		// Forgotten where it was recorded, which is the checkout the worktree
		// was made from and not this one. An agent finishing an item is
		// standing in the worktree, and a run left in the project's list keeps
		// the dashboard saying somebody is on it.
		let primary = await BacklogRunner.primaryCheckout(from: backlog.projectRoot) ?? backlog.projectRoot
		try? BacklogRuns(projectRoot: primary).forget(moved.number)
		out("\(String(format: "%04d", moved.number))  completed/")
		// Compared as resolved paths: git answers `/private/var/…` where the
		// project holds `/var/…`, and one of the two ends in a slash — so two
		// URLs for the same directory are unequal twice over, and the sentence
		// below would appear in the checkout it is about.
		if primary.path != backlog.projectRoot.resolvingSymlinksInPath().path {
			out("In \(primary.lastPathComponent) it stays in in-progress/ until this branch lands there.")
		}
		if !problems.isEmpty {
			out("The delta did not fold cleanly. Fix the headings above and run "
				+ "`abydos-backlog fold \(moved.number)` again.")
		}
		return problems.isEmpty ? 0 : 1
	}

	// MARK: - Running one

	private static func start(_ arguments: [String]) async throws -> Int32 {
		let backlog = try existing()
		let options = Options(arguments)
		let configuration = BacklogConfiguration.read(backlog.configFile) ?? BacklogConfiguration()

		let item: BacklogItem
		if options.rest.isEmpty {
			guard let ready = BacklogRunner.next(in: backlog) else {
				out("Nothing is ready.")
				return 1
			}
			item = ready
		} else {
			item = try find(options.rest, in: backlog)
		}

		let assistant = try options.value("assistant").map { try parse(assistants: $0).first }
			?? configuration.preferred
		let start = try await BacklogRunner.start(
			item,
			in: backlog,
			assistant: assistant,
			useWorktree: configuration.worktrees && !options.has("no-worktree")
		)

		out("\(String(format: "%04d", start.item.number))  \(start.item.title)")
		if let branch = start.branch { out("  branch    \(branch)") }
		out("  worktree  \(start.directory.path)")

		guard let command = start.command else {
			let names = configuration.known.map(\.name).joined(separator: ", ")
			out("")
			out(configuration.known.isEmpty
				? "No assistant is configured — run `abydos-backlog init` to choose one."
				: "None of \(names) is installed, so nothing was started. The worktree is ready.")
			out(start.prompt)
			return 0
		}

		if options.has("print") {
			out("")
			out(([command.executable] + command.arguments).joined(separator: " "))
			return 0
		}

		out("  agent     \(start.assistant?.name ?? command.executable)")
		out("")
		return runInherited(command, in: start.directory)
	}

	/// Runs the assistant with this terminal, and waits.
	///
	/// The handles are inherited rather than piped: these are interactive
	/// programs that draw a whole screen, and a pipe turns one into a
	/// scrollback of escape sequences.
	private static func runInherited(_ command: AgentLauncher.Command, in directory: URL) -> Int32 {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: command.executable)
		process.arguments = command.arguments
		process.currentDirectoryURL = directory
		do {
			try process.run()
		} catch {
			warn("could not start \(command.executable): \(error)")
			return 1
		}
		process.waitUntilExit()
		return process.terminationStatus
	}

	private static func runs(_ arguments: [String]) throws -> Int32 {
		let backlog = try existing()
		let store = BacklogRuns(projectRoot: backlog.projectRoot)

		if arguments.first == "prune" {
			let gone = try store.prune()
			out(gone.isEmpty
				? "Every run still has its worktree."
				: "Forgot \(gone.count): " + gone.map { String($0.number) }.joined(separator: ", "))
			return 0
		}

		let all = store.all()
		guard !all.isEmpty else {
			out("Nothing is being worked on from this machine.")
			return 0
		}
		for run in all {
			let mark = run.isPresent ? " " : "!"
			out("\(mark) \(String(format: "%04d", run.number))  \(run.branch)  \(run.worktreePath)")
		}
		if all.contains(where: { !$0.isPresent }) {
			out("\n! — the worktree is gone. `abydos-backlog runs prune` forgets those.")
		}
		return 0
	}

	// MARK: - Plumbing

	struct Failure: Error, CustomStringConvertible {
		let description: String
		init(_ description: String) { self.description = description }
	}

	/// The options a verb takes, separated from the words it takes.
	private struct Options {
		private var flags: Set<String> = []
		private var values: [String: String] = [:]
		/// Everything that was not an option, in order.
		var rest: [String] = []

		init(_ arguments: [String]) {
			var pending: String?
			for argument in arguments {
				if let name = pending {
					values[name] = argument
					pending = nil
					continue
				}
				guard argument.hasPrefix("--") else {
					rest.append(argument)
					continue
				}
				let body = String(argument.dropFirst(2))
				if let equals = body.firstIndex(of: "=") {
					values[String(body[body.startIndex..<equals])] = String(body[body.index(after: equals)...])
				} else if Self.takesAValue.contains(body) {
					pending = body
				} else {
					flags.insert(body)
				}
			}
		}

		/// Named rather than guessed from what follows: `--assistant` with
		/// nothing after it should be an error, not silently eat the number.
		static let takesAValue: Set<String> = ["assistant", "agent", "state"]

		func has(_ name: String) -> Bool { flags.contains(name) }
		func value(_ name: String) -> String? { values[name] }
	}

	private static func parse(state named: String) throws -> BacklogState {
		guard let state = BacklogState(rawValue: named) else {
			throw Failure("no such state \u{201C}\(named)\u{201D} — one of: "
				+ BacklogState.allCases.map(\.rawValue).joined(separator: ", "))
		}
		return state
	}

	private static func find(_ arguments: [String], in backlog: Backlog) throws -> BacklogItem {
		guard let first = arguments.first(where: { !$0.hasPrefix("-") }), let number = Int(first) else {
			throw Failure("which item? — a number, as `abydos-backlog list` prints them")
		}
		guard let item = backlog.item(number: number) else { throw BacklogError.noSuchItem(number) }
		return item
	}

	/// The backlog to work on, or a sentence saying there is not one.
	private static func existing() throws -> Backlog {
		let root = locate()
		let backlog = Backlog(projectRoot: root)
		guard backlog.exists else { throw BacklogError.noBacklog(root) }
		return backlog
	}

	/// Walks up from here looking for a project, the way `git` does.
	///
	/// A backlog is worked on from wherever somebody happens to be standing in
	/// the project, which is usually three directories down.
	static func locate(from directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> URL {
		var candidate = directory.standardizedFileURL
		while true {
			if AbydosFolder.exists(in: candidate) { return candidate }
			let parent = candidate.deletingLastPathComponent()
			if parent.path == candidate.path { return directory }
			candidate = parent
		}
	}

	/// Where `init` should make one: the repository, if this is one, since a
	/// backlog belongs beside the whole project and not beside `Sources/`.
	private static func projectRoot(preferGitTop: Bool) async -> URL {
		let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
		let found = locate(from: here)
		if AbydosFolder.exists(in: found) { return found }
		guard preferGitTop, let repository = await GitRepository.discover(from: here) else { return here }
		return repository.root
	}

	private static var isInteractive: Bool { isatty(FileHandle.standardInput.fileDescriptor) == 1 }

	private static func out(_ line: String) {
		FileHandle.standardOutput.write(Data((line + "\n").utf8))
	}

	private static func warn(_ line: String) {
		FileHandle.standardError.write(Data((line + "\n").utf8))
	}

	private static func usage() {
		out("""
		abydos-backlog — the backlog beside a project, as files

		  init [--assistant claude,opencode] [--yes] [--no-worktrees]
		                          make one here, and point the assistants at it
		  status                  what is in each state
		  list [state]            the items, or the items in one state
		  show <number>           one item, with what it carries
		  new "title" [--files]   write one down. --files gives it a folder
		  move <number> <state>   move it along
		  attach <number> <file>  put a screenshot beside it
		  next                    the lowest-numbered ready item
		  start [number]          worktree, branch, agent. Defaults to `next`
		  runs [prune]            what this machine has going
		  spec list               the capabilities the spec covers
		  spec show <capability>  one of them, as it stands
		  spec add <n> <capab.>   start a delta on an item, with the names to match
		  spec check [number]     whether the deltas still fit the spec
		  fold <number>           fold this item's delta into the spec
		  done <number>           fold, then move it to completed

		States: \(BacklogState.allCases.map(\.rawValue).joined(separator: ", "))
		""")
	}
}

private extension String {
	func leftPadded(to width: Int) -> String {
		count >= width ? self : String(repeating: " ", count: width - count) + self
	}
}
