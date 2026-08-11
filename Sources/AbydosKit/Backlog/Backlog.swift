import Foundation

/// Where an item stands, which is the folder it is in.
///
/// The state is the directory and nothing else — no field in a header that can
/// disagree with where the file actually is. Moving something along is `git mv`,
/// which is a change anybody can read in a diff and revert with another one.
public enum BacklogState: String, CaseIterable, Sendable {
	case open
	/// Written, understood, agreed — and therefore safe to hand to an agent.
	///
	/// The reason this is its own folder rather than a flag on `open`: `open`
	/// is a pile, and half of what is in it is a sentence somebody wrote down
	/// so as not to forget it. An agent that picks from the pile will pick one
	/// of those and spend an afternoon inventing the parts nobody decided.
	/// `ready` is the promise that the deciding is done.
	case ready
	case inProgress = "in-progress"
	case waiting
	case completed
	case history

	public var directoryName: String { rawValue }

	/// What it is called on a board or a heading.
	public var title: String {
		switch self {
		case .open: return "Open"
		case .ready: return "Ready"
		case .inProgress: return "In progress"
		case .waiting: return "Waiting"
		case .completed: return "Completed"
		case .history: return "History"
		}
	}

	/// The one line that says what belongs here, used by `init` when it writes
	/// the README and by the pane when a column is empty.
	public var summary: String {
		switch self {
		case .open:
			return "Written down so it is not forgotten. Not yet agreed, not yet anybody's."
		case .ready:
			return "Decided. Anybody — or any agent — can pick this up and start."
		case .inProgress:
			return "Being worked on right now, by a person or in a worktree of its own."
		case .waiting:
			return "Stuck on something that is not work, and says what it is waiting for."
		case .completed:
			return "Done, keeping the number it was given."
		case .history:
			return "The commit log in the backlog's shape, from before the backlog. Not added to."
		}
	}

	/// The columns of the board, left to right.
	///
	/// `history` is not one of them. It is 390 records of what already
	/// happened, and a column that long beside four short ones is not a board
	/// anybody can read — it is a wall with the work hidden behind it.
	public static let board: [BacklogState] = [.open, .ready, .inProgress, .waiting, .completed]

	/// The folders `init` makes. Same list: nothing creates `history`, because
	/// nothing writes to it.
	public static let created: [BacklogState] = board
}

/// The backlog beside a project: where it is, what is in it, and moving things
/// between the two.
///
/// A value rather than a singleton, because the app has a window per project
/// and the command line has whatever directory somebody is standing in.
public struct Backlog: Sendable {
	/// The project this is the backlog of.
	public let projectRoot: URL

	public init(projectRoot: URL) {
		self.projectRoot = projectRoot
	}

	// MARK: - Where things are

	public static let directoryName = "backlog"
	/// The item itself, inside an item that is a folder.
	public static let taskFileName = "task.md"
	/// The global spec, and the name of a delta folder inside an item.
	public static let specDirectoryName = "spec"
	/// The canonical instructions, which every assistant's own file points at.
	public static let instructionsFileName = "AGENTS.md"
	public static let projectFileName = "project.md"
	public static let configFileName = "config.json"
	public static let readmeFileName = "README.md"

	public var directory: URL {
		AbydosFolder.url(in: projectRoot).appendingPathComponent(Self.directoryName, isDirectory: true)
	}

	public func directory(for state: BacklogState) -> URL {
		directory.appendingPathComponent(state.directoryName, isDirectory: true)
	}

	/// What the project *is*, as opposed to what is left to do about it.
	public var specDirectory: URL {
		directory.appendingPathComponent(Self.specDirectoryName, isDirectory: true)
	}

	public var instructionsFile: URL {
		directory.appendingPathComponent(Self.instructionsFileName)
	}

	public var projectFile: URL {
		directory.appendingPathComponent(Self.projectFileName)
	}

	public var configFile: URL {
		directory.appendingPathComponent(Self.configFileName)
	}

	public var readmeFile: URL {
		directory.appendingPathComponent(Self.readmeFileName)
	}

	/// Whether this project has a backlog at all, which is what `init` asks
	/// before offering to make one.
	public var exists: Bool {
		FileManager.default.fileExists(atPath: directory.path)
	}

	// MARK: - Reading

	/// Every item in one state, lowest number first.
	public func items(in state: BacklogState) -> [BacklogItem] {
		let folder = directory(for: state)
		let manager = FileManager.default
		guard let names = try? manager.contentsOfDirectory(atPath: folder.path) else { return [] }

		return names.compactMap { name in
			BacklogItem(at: folder.appendingPathComponent(name), state: state)
		}
		.sorted { $0.number < $1.number }
	}

	/// Everything except `history`.
	///
	/// The default because `history` answers a different question — what was
	/// done before this folder existed — and every caller that wants it says so.
	public func items() -> [BacklogItem] {
		BacklogState.board.flatMap { items(in: $0) }
	}

	/// One item, wherever it happens to be.
	///
	/// Every state is looked in, and that is the point rather than thoroughness:
	/// a number is the only durable name an item has, and the folder it is in is
	/// the one thing about it that changes. The board asks this of a *worktree*
	/// to find the copy an agent is ticking, and by then that copy may have been
	/// moved to `completed/` by `done` while the project still has it in
	/// `in-progress/` — so a path would be the wrong question.
	///
	/// The names are matched before anything is read. This used to build every
	/// item in every state and then look for the number, which reads the head of
	/// four hundred and fifty files to answer a question the directory listing
	/// already answers — cheap enough once, and this now runs per card on a walk
	/// that a board waits for.
	public func item(number: Int) -> BacklogItem? {
		let manager = FileManager.default
		for state in BacklogState.allCases {
			let folder = directory(for: state)
			guard let names = try? manager.contentsOfDirectory(atPath: folder.path) else { continue }
			for name in names.sorted() {
				guard let parsed = BacklogItem.parseName(name), parsed.number == number else { continue }
				if let found = BacklogItem(at: folder.appendingPathComponent(name), state: state) { return found }
			}
		}
		return nil
	}

	// MARK: - Numbers

	/// The number the next item gets.
	///
	/// One sequence over the whole backlog, `history` included: the numbers
	/// carry on from the commits that came before the backlog was written down,
	/// and a number is given once and never changes. Taken from the highest in
	/// use rather than from a counter in a file, so a number cannot be handed
	/// out twice by two checkouts that both wrote the counter.
	public func nextNumber() -> Int {
		let highest = BacklogState.allCases
			.flatMap { items(in: $0) }
			.map(\.number)
			.max()
		return (highest ?? 0) + 1
	}

	// MARK: - Writing

	/// Makes an item, as a file or as a folder.
	///
	/// - Parameter carriesFiles: whether it gets a folder of its own. A folder
	///   is what a screenshot needs somewhere to live in; a task that is only
	///   words does not need the extra directory and does not get one.
	@discardableResult
	public func create(
		title: String,
		state: BacklogState = .open,
		carriesFiles: Bool = false,
		body: String? = nil
	) throws -> BacklogItem {
		let number = nextNumber()
		let slug = Self.slug(from: title)
		let name = String(format: "%04d-%@", number, slug)
		let manager = FileManager.default
		let stateFolder = directory(for: state)
		try manager.createDirectory(at: stateFolder, withIntermediateDirectories: true)

		let text = body ?? Self.template(number: number, title: title)
		let file: URL
		var itemFolder: URL?
		if carriesFiles {
			let folder = stateFolder.appendingPathComponent(name, isDirectory: true)
			try manager.createDirectory(at: folder, withIntermediateDirectories: true)
			file = folder.appendingPathComponent(Self.taskFileName)
			itemFolder = folder
		} else {
			file = stateFolder.appendingPathComponent(name + ".md")
		}
		try text.write(to: file, atomically: true, encoding: .utf8)

		return BacklogItem(number: number, slug: slug, state: state, folder: itemFolder, file: file, title: title)
	}

	/// Moves an item into another state, keeping its number and its files.
	///
	/// Whatever it is — a file or a folder with three screenshots in it — moves
	/// as one thing, because an item's pictures are part of the item and not
	/// something that stays behind in `open` when the item reaches `completed`.
	@discardableResult
	public func move(_ item: BacklogItem, to state: BacklogState) throws -> BacklogItem {
		guard item.state != state else { return item }
		let manager = FileManager.default
		let destination = directory(for: state)
		try manager.createDirectory(at: destination, withIntermediateDirectories: true)

		let source = item.folder ?? item.file
		let target = destination.appendingPathComponent(source.lastPathComponent)
		guard !manager.fileExists(atPath: target.path) else {
			throw BacklogError.alreadyThere(target)
		}
		try manager.moveItem(at: source, to: target)

		guard let moved = BacklogItem(at: target, state: state) else {
			throw BacklogError.unreadable(target)
		}
		return moved
	}

	/// Turns a one-file item into a folder, so something can be put beside it.
	///
	/// Done on demand rather than making every item a folder from the start:
	/// 435 items already exist as files, and a migration that rewrites all of
	/// them to gain a directory each buys nothing for the 400 that will never
	/// carry a picture.
	@discardableResult
	public func makeFolder(for item: BacklogItem) throws -> BacklogItem {
		if item.folder != nil { return item }
		let manager = FileManager.default
		let name = item.file.deletingPathExtension().lastPathComponent
		let folder = directory(for: item.state).appendingPathComponent(name, isDirectory: true)
		try manager.createDirectory(at: folder, withIntermediateDirectories: true)
		try manager.moveItem(at: item.file, to: folder.appendingPathComponent(Self.taskFileName))

		guard let converted = BacklogItem(at: folder, state: item.state) else {
			throw BacklogError.unreadable(folder)
		}
		return converted
	}

	/// Copies a file in beside an item, making it a folder first if it is not
	/// one yet. Returns the item as it now is, and where the file landed.
	@discardableResult
	public func attach(_ file: URL, to item: BacklogItem) throws -> (item: BacklogItem, attachment: URL) {
		let folder = try makeFolder(for: item)
		guard let directory = folder.folder else { throw BacklogError.unreadable(folder.file) }
		let images = directory.appendingPathComponent(BacklogItem.attachmentsDirectoryName, isDirectory: true)
		try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)

		// A name that is already taken gets a number rather than overwriting:
		// two screenshots of the same bug are usually called `Screenshot.png`
		// twice, and losing the first one silently is the worst of the three
		// things that could happen here.
		var target = images.appendingPathComponent(file.lastPathComponent)
		var attempt = 2
		while FileManager.default.fileExists(atPath: target.path) {
			let stem = file.deletingPathExtension().lastPathComponent
			let extensionName = file.pathExtension
			let name = extensionName.isEmpty ? "\(stem)-\(attempt)" : "\(stem)-\(attempt).\(extensionName)"
			target = images.appendingPathComponent(name)
			attempt += 1
		}
		try FileManager.default.copyItem(at: file, to: target)
		return (folder, target)
	}

	// MARK: - Names

	/// The file-name form of a title.
	///
	/// Cut at a word rather than mid-letter: the existing numbers include
	/// `…-past-about-one-and-a-half-t`, which is a hard truncation at sixty
	/// characters, and reading it back is a small daily irritation that costs
	/// one `lastIndex(of:)` to avoid.
	public static func slug(from title: String, limit: Int = 60) -> String {
		let lowered = title.lowercased()
		var slug = ""
		var lastWasDash = false
		for character in lowered {
			if character.isLetter || character.isNumber {
				slug.append(character)
				lastWasDash = false
			} else if !lastWasDash, !slug.isEmpty {
				slug.append("-")
				lastWasDash = true
			}
		}
		while slug.hasSuffix("-") { slug.removeLast() }
		guard slug.count > limit else { return slug.isEmpty ? "item" : slug }

		let cut = String(slug.prefix(limit))
		guard let boundary = cut.lastIndex(of: "-"), boundary > cut.startIndex else { return cut }
		return String(cut[cut.startIndex..<boundary])
	}

	/// What a new item says before anybody has written anything in it.
	///
	/// The headings are the ones the instructions ask for, so a task written by
	/// hand and a task written by an agent come out the same shape — and so
	/// that the empty ones are visible: a `## Ruled out` with nothing under it
	/// is a question somebody has not answered yet.
	///
	/// One checklist and not two. An item used to carry a plan and a separate
	/// list of what would make it done, and the two always disagreed by the
	/// end — so `## Steps` is both: the work in the order it happens, ticked as
	/// it happens, ending with the two steps every item has.
	static func template(number: Int, title: String) -> String {
		"""
		# \(number). \(title)

		What is wrong, or what is missing. Written for somebody who has not been
		looking at this all week.

		## Ruled out

		What has already been tried and did not work, and why — so the next
		person does not spend the afternoon finding out again.

		## Steps

		- [ ] The work, in the order it happens. One line each, and a line is
		      something you can tell you have finished.
		- [ ] Write down here what was ruled out on the way.
		- [ ] `\(Self.specDirectoryName)/<capability>.md` says what the project now does.

		"""
	}
}

public enum BacklogError: Error, CustomStringConvertible {
	case noBacklog(URL)
	case noSuchItem(Int)
	case alreadyThere(URL)
	case unreadable(URL)

	public var description: String {
		switch self {
		case let .noBacklog(root):
			return "\(root.path) has no backlog — run `abydos-backlog init` there first."
		case let .noSuchItem(number):
			return "There is no item \(number)."
		case let .alreadyThere(url):
			return "\(url.path) already exists."
		case let .unreadable(url):
			return "Could not read \(url.path)."
		}
	}
}
