import Foundation

/// One scratch, wherever it came from.
public struct ScratchEntry: Equatable, Sendable {
	public let url: URL
	/// The project it belongs to, or nil for a global one.
	public let projectRoot: URL?
	public let modified: Date
	public let size: Int

	public init(url: URL, projectRoot: URL?, modified: Date, size: Int) {
		self.url = url
		self.projectRoot = projectRoot
		self.modified = modified
		self.size = size
	}

	public var title: String { ScratchFiles.title(for: url) }
	public var isGlobal: Bool { projectRoot == nil }
	public var isEmpty: Bool { size == 0 }
}

/// The scratches of one project, or the global ones.
public struct ScratchCollection: Equatable, Sendable {
	public let projectRoot: URL?
	public var entries: [ScratchEntry]

	public var isGlobal: Bool { projectRoot == nil }

	/// What the section is called: the project's directory name, since that is
	/// how projects are named everywhere else in the window.
	public var title: String {
		projectRoot?.lastPathComponent ?? "Global"
	}

	public init(projectRoot: URL?, entries: [ScratchEntry]) {
		self.projectRoot = projectRoot
		self.entries = entries
	}
}

/// Where a query was found inside a scratch.
public struct ScratchMatch: Equatable, Sendable {
	public let entry: ScratchEntry
	/// One-based, or nil when only the name matched.
	public let line: Int?
	/// The matching line, trimmed, or the opening of the file when the name is
	/// what matched — either way, enough to recognise it by.
	public let excerpt: String

	public init(entry: ScratchEntry, line: Int?, excerpt: String) {
		self.entry = entry
		self.line = line
		self.excerpt = excerpt
	}
}

/// Every scratch on the machine, whichever project it was written in.
///
/// A scratch outlives the moment it was made for: the query you worked out
/// last month is worth more than the tab it was in. This is what makes them
/// findable again once the tab is closed and the project moved on — without
/// it, a scratch is only as durable as somebody's memory of where it was.
public struct ScratchLibrary {
	public let root: URL

	public init(root: URL? = nil) {
		self.root = root ?? ScratchFiles.defaultRoot
	}

	/// Everything, grouped: global first, then projects by name.
	///
	/// Global leads because those are the notes that are always relevant;
	/// a project's are relevant when you are in it.
	public func collections() -> [ScratchCollection] {
		let directories = (try? FileManager.default.contentsOfDirectory(
			at: root,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles]
		)) ?? []

		var global: ScratchCollection?
		var projects: [ScratchCollection] = []

		for directory in directories {
			guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
			let isGlobal = directory.lastPathComponent == ScratchFiles.globalDirectoryName
			let projectRoot = isGlobal ? nil : ScratchFiles.projectRoot(ofDirectory: directory)

			// A digest folder with no marker cannot be attributed to a project,
			// but it still holds somebody's notes: shown under whatever the
			// folder is called rather than dropped.
			let entries = self.entries(in: directory, projectRoot: projectRoot)
			guard !entries.isEmpty else { continue }

			if isGlobal {
				global = ScratchCollection(projectRoot: nil, entries: entries)
			} else {
				projects.append(ScratchCollection(projectRoot: projectRoot, entries: entries))
			}
		}

		projects.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
		return (global.map { [$0] } ?? []) + projects
	}

	/// Everything, flat, most recently changed first.
	public func all() -> [ScratchEntry] {
		collections()
			.flatMap(\.entries)
			.sorted { $0.modified > $1.modified }
	}

	private func entries(in directory: URL, projectRoot: URL?) -> [ScratchEntry] {
		let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
		let files = (try? FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: keys,
			options: [.skipsHiddenFiles]
		)) ?? []

		return files.compactMap { url in
			let values = try? url.resourceValues(forKeys: Set(keys))
			guard values?.isRegularFile == true else { return nil }
			return ScratchEntry(
				url: url,
				projectRoot: projectRoot,
				modified: values?.contentModificationDate ?? .distantPast,
				size: values?.fileSize ?? 0
			)
		}
		.sorted { $0.modified > $1.modified }
	}

	/// Scratches matching a query, by name or by what is written in them.
	///
	/// Searching the contents is the point: a scratch is rarely named, so its
	/// name is the one thing you cannot search it by.
	public func search(_ query: String, limit: Int = 200) -> [ScratchMatch] {
		let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !needle.isEmpty else {
			return all().prefix(limit).map { ScratchMatch(entry: $0, line: nil, excerpt: opening(of: $0)) }
		}

		var matches: [ScratchMatch] = []
		for entry in all() {
			if let match = self.match(entry, needle: needle) {
				matches.append(match)
				if matches.count >= limit { break }
			}
		}
		return matches
	}

	private func match(_ entry: ScratchEntry, needle: String) -> ScratchMatch? {
		let text = (try? String(contentsOf: entry.url, encoding: .utf8)) ?? ""

		// The line it is on, which is what makes a hit worth showing.
		for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
		where line.range(of: needle, options: .caseInsensitive) != nil {
			return ScratchMatch(
				entry: entry,
				line: index + 1,
				excerpt: line.trimmingCharacters(in: .whitespaces)
			)
		}

		// A name can match too, once somebody has given it one.
		guard entry.title.range(of: needle, options: .caseInsensitive) != nil else { return nil }
		return ScratchMatch(entry: entry, line: nil, excerpt: opening(of: entry))
	}

	/// The first line with something on it, to tell one unnamed note from
	/// another without opening either.
	private func opening(of entry: ScratchEntry) -> String {
		guard let text = try? String(contentsOf: entry.url, encoding: .utf8) else { return "" }
		for line in text.split(separator: "\n") {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if !trimmed.isEmpty { return trimmed }
		}
		return ""
	}
}
