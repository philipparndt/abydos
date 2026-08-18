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

	/// Where this change stands, worked out from what is on the disk.
	///
	/// **A backlog item's state is the folder it is in; a change has no such
	/// folder**, so this is derived — which is also why a card for one must not
	/// be draggable. Dragging an item between columns is the `mv` that changes
	/// its state; dragging a change could only mean ticking or unticking
	/// checkboxes in a file nobody opened.
	///
	/// `waiting` is never answered. Nothing in a change says it is stuck on
	/// something, and a marker invented here would be a format this project made
	/// up and then had to keep.
	public func state(progress: BacklogItem.Progress?) -> BacklogState {
		guard artifacts.contains(.tasks) else { return .open }
		guard let progress, progress.total > 0 else { return .ready }
		if progress.done == 0 { return .ready }
		return progress.isComplete ? .completed : .inProgress
	}

	/// What is written and what is not, for a change with no tasks to count.
	public var artifactSummary: String {
		let written = OpenSpecArtifact.allCases.filter { artifacts.contains($0) }
		guard !written.isEmpty else { return "nothing written yet" }
		return written.map(\.label).joined(separator: ", ")
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
	/// **Not a column on the board.** It is `history`'s argument exactly — a
	/// long column beside four short ones is a wall with the work hidden behind
	/// it — so these belong in the list.
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

	/// What somebody would run to archive a finished change.
	///
	/// The command rather than the running of it: archiving rewrites the
	/// project's specs, and a pane that did that from a menu would be doing the
	/// larger half of somebody's review for them.
	public static func archiveCommand(for change: OpenSpecChange) -> String {
		"openspec archive \(change.name)"
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
