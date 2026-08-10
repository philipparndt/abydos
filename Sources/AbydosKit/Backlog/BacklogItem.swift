import Foundation

/// One thing to do, in whichever of the two shapes it has.
///
/// The two shapes are the point. `0401-run-every-external-tool.md` is a task
/// that is only words, which is most of them, and it stays one file that `grep`
/// finds and `git log` follows. `0443-the-capsule-is-clipped/` is a task with a
/// screenshot of the clipping in it, and a folder is the only place a
/// screenshot can go. Nothing had to be migrated for the second to exist: an
/// entry in a state folder is an item if it is a `.md` file *or* a directory
/// holding `task.md`, and both were true from the day the folder form landed.
public struct BacklogItem: Identifiable, Sendable, Equatable {
	/// Where a folder-shaped item keeps what it carries.
	public static let attachmentsDirectoryName = "images"

	/// Given once, when the item is written, and never changed again.
	public let number: Int
	/// The rest of the file name — the title, when it was written.
	public let slug: String
	public let state: BacklogState
	/// The item's own directory, for an item that has one.
	public let folder: URL?
	/// The markdown that is the item: the file itself, or `task.md` in the
	/// folder. Everything that reads or edits an item reads this, so neither
	/// shape is a special case anywhere above here.
	public let file: URL
	/// The first heading, with the number taken off the front.
	public let title: String

	public var id: Int { number }

	/// Whether it can carry files as it stands. A file-shaped item cannot, and
	/// `Backlog.makeFolder(for:)` is how it comes to.
	public var carriesFiles: Bool { folder != nil }

	public init(
		number: Int,
		slug: String,
		state: BacklogState,
		folder: URL?,
		file: URL,
		title: String
	) {
		self.number = number
		self.slug = slug
		self.state = state
		self.folder = folder
		self.file = file
		self.title = title
	}

	/// Reads an item from whatever is at `url`, or nothing if it is neither
	/// shape — a `.DS_Store`, a stray note, the `spec` folder itself.
	public init?(at url: URL, state: BacklogState) {
		let manager = FileManager.default
		var isDirectory: ObjCBool = false
		guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }

		let name: String
		let file: URL
		let folder: URL?
		if isDirectory.boolValue {
			let task = url.appendingPathComponent(Backlog.taskFileName)
			guard manager.fileExists(atPath: task.path) else { return nil }
			name = url.lastPathComponent
			file = task
			folder = url
		} else {
			guard url.pathExtension == "md" else { return nil }
			name = url.deletingPathExtension().lastPathComponent
			file = url
			folder = nil
		}

		guard let parsed = Self.parseName(name) else { return nil }
		self.number = parsed.number
		self.slug = parsed.slug
		self.state = state
		self.folder = folder
		self.file = file
		self.title = Self.readTitle(from: file) ?? Self.titleFromSlug(parsed.slug)
	}

	/// `0401-run-every-external-tool` → 401 and the rest.
	static func parseName(_ name: String) -> (number: Int, slug: String)? {
		let digits = name.prefix { $0.isNumber }
		guard !digits.isEmpty, let number = Int(digits) else { return nil }
		var slug = String(name.dropFirst(digits.count))
		if slug.hasPrefix("-") { slug.removeFirst() }
		return (number, slug)
	}

	/// The first `# ` heading, without the `401. ` the file repeats from its
	/// own name.
	///
	/// Only the head of the file is read. These are prose — several are two
	/// thousand words — and a board of forty cards should not be forty whole
	/// documents pulled through memory to find forty first lines.
	static func readTitle(from file: URL) -> String? {
		guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
		defer { try? handle.close() }
		guard let head = try? handle.read(upToCount: 4096), let text = String(data: head, encoding: .utf8)
		else { return nil }

		for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
			guard line.hasPrefix("# ") else { continue }
			var title = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
			// `# 401. Run every external tool…` — the number is in the file
			// name and on the card already, and twice is noise.
			if let dot = title.firstIndex(of: "."),
			   title[title.startIndex..<dot].allSatisfy(\.isNumber),
			   dot > title.startIndex {
				title = String(title[title.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
			}
			return title.isEmpty ? nil : title
		}
		return nil
	}

	/// A readable-enough title for a file whose first line is not a heading.
	static func titleFromSlug(_ slug: String) -> String {
		let words = slug.replacingOccurrences(of: "-", with: " ")
		return words.prefix(1).uppercased() + words.dropFirst()
	}

	// MARK: - What it carries

	/// The screenshots, logs and recordings beside the task, in name order.
	///
	/// Everything in the folder that is not the task and not the spec delta —
	/// stated that way round on purpose, so dropping a file in is all there is
	/// to attaching one, and nothing has to be registered anywhere.
	public func attachments() -> [URL] {
		guard let folder else { return [] }
		let manager = FileManager.default
		var found: [URL] = []

		func walk(_ directory: URL, depth: Int) {
			guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
			for name in names.sorted() where !name.hasPrefix(".") {
				let url = directory.appendingPathComponent(name)
				if url == file { continue }
				var isDirectory: ObjCBool = false
				guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
				if isDirectory.boolValue {
					// The delta belongs to the spec, not to the gallery.
					if depth == 0, name == Backlog.specDirectoryName { continue }
					// One level down, which is `images/`. Deeper than that is
					// somebody keeping a project in here, and a task's folder
					// is not that.
					if depth < 1 { walk(url, depth: depth + 1) }
				} else {
					found.append(url)
				}
			}
		}
		walk(folder, depth: 0)
		return found
	}

	/// The attachments that can be shown rather than only opened.
	public func images() -> [URL] {
		let shown: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "pdf", "svg"]
		return attachments().filter { shown.contains($0.pathExtension.lowercased()) }
	}

	/// The changes this item proposes to the global spec, one file per
	/// capability, named as the capability is named in `spec/`.
	public func specDeltas() -> [URL] {
		guard let folder else { return [] }
		let directory = folder.appendingPathComponent(Backlog.specDirectoryName, isDirectory: true)
		guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
		return names.sorted()
			.filter { $0.hasSuffix(".md") }
			.map { directory.appendingPathComponent($0) }
	}

	public func text() -> String {
		(try? String(contentsOf: file, encoding: .utf8)) ?? ""
	}

	// MARK: - How far along it is

	/// How much of an item's checklist has been ticked.
	public struct Progress: Equatable, Sendable {
		public let done: Int
		public let total: Int

		public var isComplete: Bool { done == total }
		public var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
		/// `3/7`, which is the whole of what a card has room for.
		public var summary: String { "\(done)/\(total)" }
	}

	/// The item's steps, counted.
	///
	/// Read out of the markdown rather than kept in a field beside it, because
	/// the checklist is the thing somebody edits — in the editor, in a diff, in
	/// an agent's write — and a count stored anywhere else is a count that is
	/// wrong within a day. `nil` when the item has no checklist at all, which
	/// is different from one with nothing ticked: a card should say `0/4` for
	/// the second and nothing for the first.
	public func progress() -> Progress? {
		Self.progress(in: text())
	}

	/// The steps still unticked, as they are written.
	///
	/// Printed by `done`, because "you said this item was finished and five
	/// lines in it say otherwise" is the one thing worth interrupting somebody
	/// for — and naming them beats a count, since half of them are usually
	/// steps that were finished and not marked.
	public func remainingSteps() -> [String] {
		Self.remainingSteps(in: text())
	}

	static func remainingSteps(in markdown: String) -> [String] {
		markdown.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard let bullet = trimmed.first, "-*+".contains(bullet) else { return nil }
			let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
			guard rest.hasPrefix("[ ]") else { return nil }
			let text = rest.dropFirst(3).trimmingCharacters(in: .whitespaces)
			return text.isEmpty ? nil : text
		}
	}

	static func progress(in markdown: String) -> Progress? {
		var done = 0
		var total = 0
		for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			// `- [ ]`, `* [x]`, `+ [X]`. Anything else with square brackets in
			// it is prose or a link, and counting those would make the number
			// meaningless in exactly the items that have the most words.
			guard let bullet = trimmed.first, "-*+".contains(bullet) else { continue }
			let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
			guard rest.count >= 3, rest.hasPrefix("[") else { continue }
			let mark = rest[rest.index(rest.startIndex, offsetBy: 1)]
			guard rest[rest.index(rest.startIndex, offsetBy: 2)] == "]" else { continue }

			switch mark {
			case " ": total += 1
			case "x", "X": done += 1; total += 1
			default: continue
			}
		}
		return total == 0 ? nil : Progress(done: done, total: total)
	}

	/// The path to write in a prompt or a commit message: relative to the
	/// project, because an absolute one is somebody else's machine.
	public func displayPath(from projectRoot: URL) -> String {
		let full = (folder ?? file).path
		let prefix = projectRoot.path.hasSuffix("/") ? projectRoot.path : projectRoot.path + "/"
		return full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : full
	}

	/// The branch a worktree for this item checks out.
	public var branchName: String { String(format: "backlog/%04d-%@", number, slug) }
}
