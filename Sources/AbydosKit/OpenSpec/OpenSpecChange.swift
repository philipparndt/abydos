import Foundation

/// The documents a change is written as, in the order they are written.
///
/// A change in the `spec-driven` schema is a directory of markdown: why, then
/// how, then what the behaviour becomes, then the list of work. Which of them
/// exist is what "how far along is this" means before any task is ticked, so
/// they are worth knowing about separately from the tasks.
public enum OpenSpecArtifact: String, CaseIterable, Sendable {
	case proposal, design, specs, tasks

	/// What it is called on a card.
	public var label: String {
		switch self {
		case .proposal: return "proposal"
		case .design:   return "design"
		case .specs:    return "specs"
		case .tasks:    return "tasks"
		}
	}

	/// The file it is, inside a change's directory. `specs` is a folder rather
	/// than a file: one per capability the change touches.
	var fileName: String { self == .specs ? "specs" : "\(rawValue).md" }

	/// The order the schema requires them in.
	///
	/// `spec-driven`'s `apply.requires` is `[tasks]`; `tasks` requires `specs`
	/// and `design`, and both of those require `proposal`. So a `tasks.md` on
	/// the disk implies the whole chain, which is what makes every state below
	/// readable from a directory listing rather than from the CLI.
	///
	/// `specs` and `design` are siblings — neither requires the other — so the
	/// order between those two is the order they are read in and nothing more.
	public static let chain: [OpenSpecArtifact] = [.proposal, .design, .specs, .tasks]
}

/// Where a change stands, in OpenSpec's own vocabulary.
///
/// **Not the backlog's folders**, which is what this answered first and what
/// forced the two records into one set of columns. A backlog item's state is the
/// folder it sits in; OpenSpec has no folders to sit in, and it has three
/// vocabularies of its own — measured against the installed CLI, not guessed at:
/// `openspec list` says `no-tasks`/`in-progress`/`complete`, `openspec status`
/// says `done`/`ready`/`blocked` per artifact, and `openspec instructions apply`
/// says `blocked`/`ready`/`all_done`.
///
/// **The apply vocabulary is the one these are**, because "can this be picked
/// up" is the question a board answers — and it is what `ready` means on the
/// backlog's board too, so the two stay legible side by side.
///
/// `writing` is apply's `blocked`. `ready` and `inProgress` are both apply's
/// `ready`, split by whether anything is ticked: **`openspec list` calls both of
/// them `in-progress`, and this disagrees on purpose**, because "nobody has
/// started" against "somebody is in the middle of this" is most of what a board
/// is for. Nothing reports a different answer to anything but the eye — the
/// fraction on the card is the number the CLI gives either way.
public enum OpenSpecState: String, CaseIterable, Sendable {
	/// An artifact `apply` needs is missing. `openspec instructions apply`
	/// answers `blocked` here and names what it is waiting for.
	case writing
	/// Every required artifact is there and nothing is ticked.
	case ready
	case inProgress = "in-progress"
	/// Every task ticked, and `openspec archive` not yet run.
	case complete
	/// Under `changes/archive/`.
	case archived

	/// What it is called on a board or a heading.
	public var title: String {
		switch self {
		case .writing: return "Writing"
		case .ready: return "Ready"
		case .inProgress: return "In progress"
		case .complete: return "Complete"
		case .archived: return "Archived"
		}
	}

	/// The one line that says what belongs here, for a column with nothing in
	/// it — which is most of them on a project that has just run `openspec init`.
	public var summary: String {
		switch self {
		case .writing:
			return "Being written. A document apply needs is not there yet, and the card says which."
		case .ready:
			return "Every document written and no task ticked. Anybody — or any agent — can pick this up."
		case .inProgress:
			return "Some tasks ticked and some not."
		case .complete:
			return "Every task ticked, waiting for openspec archive to be run."
		case .archived:
			return "Archived, with its specs folded into the project's."
		}
	}

	/// The columns of the board, left to right.
	///
	/// **All five, and the archive is one of them.** The backlog keeps `history`
	/// off its board because that is 390 records of what happened before the
	/// backlog existed while `completed/` is on the board — and borrowing that
	/// argument here put every finished change out of sight, because OpenSpec
	/// has no `completed/` at all. A change moves to `changes/archive/` the
	/// moment it is done, so the archive *is* the finished column. It goes last,
	/// where `completed` is on the other board.
	///
	/// It only grows: nine today, and when it is longer than the board is tall
	/// it wants collapsing or a date cut. That is a separate item with a real
	/// number behind it rather than a guess made now.
	public static let board: [OpenSpecState] = allCases
}

/// One OpenSpec change, read off the disk.
///
/// **Nothing here runs the `openspec` CLI**, and that is the design rather than
/// an omission. Measured on this machine, `openspec list --json` costs 0.60 s
/// and `openspec status --change` another 0.60 s each — Node start-up, not work
/// — and this is built on the same walk the backlog board runs whenever
/// anything under the directory changes, which includes an agent ticking a
/// checkbox. Eight changes through the CLI would be five seconds per keystroke
/// somebody else made.
///
/// The other half of the reason is where the CLI turns out to live:
/// `~/.local/state/fnm_multishells/91100_1786908065368/bin/openspec`, an fnm
/// directory with a shell's PID in its name. An app launched from the Dock has
/// `PATH=/usr/bin:/bin:/usr/sbin:/sbin` — measured, see `Executables` — so a
/// board that needed the CLI would be empty for exactly the people who have it
/// installed. A change is committed markdown; a teammate with no Node still has
/// all of it.
public struct OpenSpecChange: Identifiable, Sendable, Equatable {
	/// The directory's own name, which is what every `openspec` verb calls it.
	public let name: String
	public let directory: URL
	/// Whether it lives under `changes/archive/`.
	public let isArchived: Bool
	/// Which of the four documents are there.
	public let artifacts: Set<OpenSpecArtifact>
	/// From `.openspec.yaml`, which has two keys and does not need a parser.
	public let schema: String?
	public let created: String?

	public var id: String { name }

	public init(
		name: String,
		directory: URL,
		isArchived: Bool = false,
		artifacts: Set<OpenSpecArtifact> = [],
		schema: String? = nil,
		created: String? = nil
	) {
		self.name = name
		self.directory = directory
		self.isArchived = isArchived
		self.artifacts = artifacts
		self.schema = schema
		self.created = created
	}

	public static let headerFileName = ".openspec.yaml"

	/// Reads a change, or says this directory is not one.
	///
	/// A directory with none of the four documents in it is not a change: the
	/// `archive/` folder itself is a directory beside them, and so is anything
	/// else somebody leaves in there.
	public init?(at url: URL, isArchived: Bool = false) {
		let manager = FileManager.default
		var isDirectory: ObjCBool = false
		guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
		else { return nil }
		guard let names = try? manager.contentsOfDirectory(atPath: url.path) else { return nil }

		let present = Set(names)
		var found: Set<OpenSpecArtifact> = []
		for artifact in OpenSpecArtifact.allCases where present.contains(artifact.fileName) {
			// A `specs/` with nothing in it is a scaffold, not an artifact —
			// `openspec new change` makes the folder before anything is written.
			if artifact == .specs {
				let specs = url.appendingPathComponent(artifact.fileName, isDirectory: true)
				let contents = (try? manager.contentsOfDirectory(atPath: specs.path)) ?? []
				guard !contents.isEmpty else { continue }
			}
			found.insert(artifact)
		}
		guard !found.isEmpty else { return nil }

		let header = Self.header(at: url.appendingPathComponent(Self.headerFileName))
		self.init(
			name: url.lastPathComponent,
			directory: url,
			isArchived: isArchived,
			artifacts: found,
			schema: header.schema,
			created: header.created
		)
	}

	/// The two keys `.openspec.yaml` holds, read as lines.
	///
	/// No YAML parser is added for `schema: spec-driven` and `created:
	/// 2026-08-17`, and a header that grows something structural is a reason to
	/// revisit that with the reason written down at the time. A header that is
	/// missing or unreadable costs nothing: it is still a change, with its
	/// artifacts and its tasks.
	static func header(at url: URL) -> (schema: String?, created: String?) {
		guard let text = try? String(contentsOf: url, encoding: .utf8) else { return (nil, nil) }
		var schema: String?
		var created: String?
		for line in text.components(separatedBy: .newlines) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.hasPrefix("schema:") {
				schema = String(trimmed.dropFirst("schema:".count)).trimmingCharacters(in: .whitespaces)
			}
			if trimmed.hasPrefix("created:") {
				created = String(trimmed.dropFirst("created:".count)).trimmingCharacters(in: .whitespaces)
			}
		}
		return (schema?.isEmpty == true ? nil : schema, created?.isEmpty == true ? nil : created)
	}

	public var tasksFile: URL { directory.appendingPathComponent(OpenSpecArtifact.tasks.fileName) }

	public func file(for artifact: OpenSpecArtifact) -> URL {
		directory.appendingPathComponent(artifact.fileName)
	}

	/// Every spec a change writes, one per capability it touches.
	public func specFiles() -> [URL] {
		let specs = directory.appendingPathComponent(OpenSpecArtifact.specs.fileName, isDirectory: true)
		let manager = FileManager.default
		guard let capabilities = try? manager.contentsOfDirectory(atPath: specs.path) else { return [] }
		return capabilities.sorted().compactMap { capability in
			let file = specs.appendingPathComponent(capability).appendingPathComponent("spec.md")
			return manager.fileExists(atPath: file.path) ? file : nil
		}
	}

	/// Every document of the change, in the order they are meant to be read.
	public func openableFiles() -> [URL] {
		var files = [OpenSpecArtifact.proposal, .design, .tasks]
			.filter { artifacts.contains($0) }
			.map { file(for: $0) }
		files += specFiles()
		return files
	}

	/// The tasks, counted.
	///
	/// **The same counting a backlog item's fraction comes from**, and
	/// deliberately not a second implementation: `- [x]` against `- [ ]` means
	/// the same thing under `## Steps` and under `## 1. Reading a change`, and
	/// two functions that agree today are two that can disagree later. Checked
	/// against the eight changes in this repository, the counts are the ones the
	/// CLI reports.
	///
	/// Nothing at all where there is no `tasks.md`, which is not `0/0`: a change
	/// still being written has no fraction, and a card should say what it has
	/// instead.
	public func progress() -> BacklogItem.Progress? {
		guard artifacts.contains(.tasks) else { return nil }
		guard let text = try? String(contentsOf: tasksFile, encoding: .utf8) else { return nil }
		return BacklogItem.progress(in: text)
	}

	/// The one schema whose states this can read.
	///
	/// A change carries `schema:` in its `.openspec.yaml`. `spec-driven`'s
	/// requirement chain is what makes every state below computable from a
	/// directory listing, and that is true of exactly this one.
	public static let understoodSchema = "spec-driven"

	/// Whether this change is written in a schema whose states this can read.
	///
	/// A missing header is taken as `spec-driven` rather than as unknown: it is
	/// what `openspec new change` writes, and a header that failed to be read is
	/// still a directory with four documents in it.
	public var isSchemaUnderstood: Bool {
		schema == nil || schema == Self.understoodSchema
	}

	/// Which document is wanted next, while a change is being written.
	///
	/// The per-artifact `done`/`ready`/`blocked` that the chain implies, said as
	/// the one useful thing at that stage: "needs tasks" rather than a silent
	/// card in a column. Nil once every document is there — and for a schema
	/// this cannot read, where the chain is not known to apply.
	public var nextArtifact: OpenSpecArtifact? {
		guard isSchemaUnderstood else { return nil }
		return OpenSpecArtifact.chain.first { !artifacts.contains($0) }
	}

	/// Where this change stands, worked out from what is on the disk.
	///
	/// **A backlog item's state is the folder it is in; a change has no such
	/// folder**, so this is derived — which is also why a card for one must not
	/// be draggable. Dragging an item between columns is the `mv` that changes
	/// its state; dragging a change could only mean ticking or unticking
	/// checkboxes in a file nobody opened.
	///
	/// `isComplete` from the CLI is never read as finished, and this is where
	/// that would go wrong: it means every artifact needed to *start* exists, so
	/// a change with a full set of documents and nothing ticked has it. That
	/// change is `ready` here.
	///
	/// **A change in a schema this cannot read is answered as `writing` and says
	/// so on its card**, rather than being placed by a rule that is not known to
	/// apply to it. Reading the schema out of the CLI's own package directory
	/// was refused: it is under an fnm path with a Node version in it, it is
	/// that package's private layout, and it would put a per-machine dependency
	/// on a path this deliberately keeps clear of one.
	public func state(progress: BacklogItem.Progress?) -> OpenSpecState {
		if isArchived { return .archived }
		guard isSchemaUnderstood else { return .writing }
		guard artifacts.contains(.tasks) else { return .writing }
		guard let progress, progress.total > 0 else { return .ready }
		if progress.done == 0 { return .ready }
		return progress.isComplete ? .complete : .inProgress
	}

	/// What is written and what is wanted next, for a change with no tasks to
	/// count.
	public var artifactSummary: String {
		if !isSchemaUnderstood {
			return "unknown schema: \(schema ?? "")"
		}
		let written = OpenSpecArtifact.chain.filter { artifacts.contains($0) }
		guard !written.isEmpty else { return "nothing written yet" }
		let listed = written.map(\.label).joined(separator: ", ")
		guard let next = nextArtifact else { return listed }
		return "\(listed) \u{2014} needs \(next.label)"
	}
}

/// The OpenSpec directory beside a project: where it is, and what is in it.
///
/// A value rather than a singleton, for the same reason `Backlog` is one: the
/// app has a window per project and the command line has whatever directory
/// somebody is standing in.
public struct OpenSpec: Sendable {
	public let projectRoot: URL

	public init(projectRoot: URL) {
		self.projectRoot = projectRoot
	}

	public static let directoryName = "openspec"
	public static let changesDirectoryName = "changes"
	public static let archiveDirectoryName = "archive"
	public static let specsDirectoryName = "specs"

	public var directory: URL {
		projectRoot.appendingPathComponent(Self.directoryName, isDirectory: true)
	}

	public var changesDirectory: URL {
		directory.appendingPathComponent(Self.changesDirectoryName, isDirectory: true)
	}

	public var archiveDirectory: URL {
		changesDirectory.appendingPathComponent(Self.archiveDirectoryName, isDirectory: true)
	}

	/// Whether this project keeps its work here at all.
	///
	/// The `changes` directory rather than `openspec` itself: `openspec init`
	/// makes both, and a project with the outer one and nothing inside it has
	/// nothing for a board to show.
	public var exists: Bool {
		FileManager.default.fileExists(atPath: changesDirectory.path)
	}

	/// Every change that is not archived, by name.
	public func changes() -> [OpenSpecChange] {
		read(in: changesDirectory, isArchived: false)
	}

	/// Every archived change.
	///
	/// **A column on the board, and the finished one.** This was kept off it at
	/// first by borrowing the argument that keeps the backlog's `history` off
	/// its own — and that argument is the opposite of this case. The backlog
	/// excludes `history` because it is 390 records from before the backlog
	/// existed *while `completed/` is on the board*; OpenSpec has no
	/// `completed/` at all, so excluding the archive excluded every finished
	/// change, and a project that had just archived nine of them showed five
	/// empty columns.
	public func archived() -> [OpenSpecChange] {
		read(in: archiveDirectory, isArchived: true)
	}

	/// The `openspec` command line tool, if this machine has one.
	///
	/// **Nothing that draws the board asks this**, and that is the point: a
	/// change is read from its files, so a project's work shows whether or not
	/// the tool is installed. What it is for is the verbs that *write* — the
	/// archive, which moves a change and folds its specs into the project's, and
	/// which would be wrong to reimplement here.
	///
	/// Through `Executables.locate`, which asks the login shell, because of
	/// where this actually lives on the machine it was written on:
	///
	///     ~/.local/state/fnm_multishells/91100_1786908065368/bin/openspec
	///
	/// An fnm multishell directory with a shell's PID in its name. A Dock-
	/// launched app has `PATH=/usr/bin:/bin:/usr/sbin:/sbin` — measured with
	/// `ps eww`, see `Executables` — so no fixed list of directories would ever
	/// find it, and the path is not one to remember between launches either.
	public static func commandLine() -> String? {
		Executables.locate("openspec")
	}

	/// How to get it, for saying when it is not there.
	public static let installHint = "npm install -g @fission-ai/openspec"

	/// What somebody would run to set a project up for OpenSpec.
	///
	/// **The command, and it is run where its questions can be answered.**
	/// `openspec init` asks which assistants to write slash commands and skills
	/// for — `--tools` exists so that it need not ask, and takes `all`, `none`
	/// or a list of two dozen names — and what it writes goes into somebody's
	/// repository. `--tools all` writes two dozen tools' worth of files nobody
	/// asked for and `--tools none` leaves an `openspec/` no assistant can
	/// drive, so neither is a quiet default worth having. A terminal in the
	/// project is where this belongs, and the string lives here rather than in
	/// a view for the same reason `archiveCommand` does.
	public static func initCommand() -> String { "openspec init" }

	/// What somebody would run to archive a finished change.
	///
	/// The command rather than the running of it: archiving rewrites the
	/// project's specs, and a pane that did that from a menu would be doing the
	/// larger half of somebody's review for them.
	public static func archiveCommand(for change: OpenSpecChange) -> String {
		"openspec archive \(change.name)"
	}

	/// What somebody would run to pick a change up — where it can be picked up.
	///
	/// **Not `openspec apply`, because there is no such verb.** The CLI's
	/// commands are `init`, `update`, `list`, `view`, `change`, `archive`,
	/// `spec`, `config`, `schema`, `validate`, `show`, `status`, `instructions`,
	/// `feedback` and `completion` — checked against the installed one rather
	/// than assumed. Applying is `openspec instructions apply --change <name>`
	/// printing what to do, and an agent then doing it, so the thing a person
	/// actually pastes is the slash command. It lives in
	/// `.claude/commands/opsx/apply.md`, committed to the project, which is why
	/// this is offered whether or not the CLI is installed — unlike
	/// `archiveCommand`, which goes into a terminal and wants
	/// `commandLine()` found first.
	///
	/// Nil where the change cannot be picked up. `writing` cannot — `openspec
	/// instructions apply` answers `blocked` there itself — and `complete` and
	/// `archived` have nothing left to apply, with `complete` having the archive
	/// command to offer instead. **A menu entry that hands somebody a command an
	/// agent then refuses is worse than no entry.**
	public static func applyCommand(for change: OpenSpecChange, in state: OpenSpecState) -> String? {
		switch state {
		case .ready, .inProgress: return "/opsx:apply \(change.name)"
		case .writing, .complete, .archived: return nil
		}
	}

	private func read(in folder: URL, isArchived: Bool) -> [OpenSpecChange] {
		let manager = FileManager.default
		guard let names = try? manager.contentsOfDirectory(atPath: folder.path) else { return [] }
		return names
			.filter { $0 != Self.archiveDirectoryName }
			.sorted()
			.compactMap {
				OpenSpecChange(at: folder.appendingPathComponent($0, isDirectory: true), isArchived: isArchived)
			}
	}
}
