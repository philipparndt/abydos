import Foundation

/// One entry in the titlebar's recent-projects list.
public struct RecentProject: Codable, Equatable, Sendable, Identifiable {
	public var path: String
	public var lastOpened: Date
	/// Index into the badge palette. Carried over from IDEA's
	/// `RecentProjectColorInfo` when imported so badges keep the colours the user
	/// already associates with each project.
	public var colorIndex: Int?

	public var id: String { path }
	public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
	public var name: String { url.lastPathComponent }
	public var displayPath: String { Project.abbreviate(url) }

	public init(path: String, lastOpened: Date, colorIndex: Int? = nil) {
		self.path = path
		self.lastOpened = lastOpened
		self.colorIndex = colorIndex
	}
}

/// Persistent recent-projects list backing the titlebar switcher.
public final class RecentProjects {
	public static let shared = RecentProjects()

	private let storeURL: URL
	private let limit = 60

	/// Most-recently-opened first.
	public private(set) var entries: [RecentProject] = []

	public init(storeURL: URL? = nil) {
		let support = FileManager.default
			.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
			.appendingPathComponent("ideai", isDirectory: true)
		try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
		self.storeURL = storeURL ?? support.appendingPathComponent("recents.json")
		load()
	}

	// MARK: - Persistence

	private func load() {
		guard let data = try? Data(contentsOf: storeURL),
		      let decoded = try? JSONDecoder().decode([RecentProject].self, from: data)
		else { return }
		entries = decoded.sorted { $0.lastOpened > $1.lastOpened }
	}

	private func save() {
		guard let data = try? JSONEncoder().encode(entries) else { return }
		try? data.write(to: storeURL, options: .atomic)
	}

	/// Moves a project to the front of the list.
	public func record(url: URL) {
		let path = url.standardizedFileURL.path
		let existingColor = entries.first { $0.path == path }?.colorIndex
		entries.removeAll { $0.path == path }
		entries.insert(RecentProject(path: path, lastOpened: Date(), colorIndex: existingColor), at: 0)
		if entries.count > limit { entries.removeLast(entries.count - limit) }
		save()
	}

	public func remove(path: String) {
		entries.removeAll { $0.path == path }
		save()
	}

	/// Drops entries whose directory no longer exists.
	public func pruneMissing() {
		let before = entries.count
		entries.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
		if entries.count != before { save() }
	}

	// MARK: - Import

	/// Seeds the list from IDEA on first run only, so the switcher is useful
	/// immediately instead of starting empty.
	public func seedFromJetBrainsIfEmpty() {
		guard entries.isEmpty else { return }
		let imported = JetBrainsRecentProjects.discover()
		guard !imported.isEmpty else { return }
		entries = Array(imported.prefix(limit))
		save()
	}
}

/// Reads IDEA's `recentProjects.xml`.
public enum JetBrainsRecentProjects {
	/// Collects recents across every installed JetBrains IDE, newest wins.
	public static func discover(
		supportDirectory: URL? = nil
	) -> [RecentProject] {
		let base = supportDirectory ?? FileManager.default
			.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
			.appendingPathComponent("JetBrains", isDirectory: true)

		guard let ideDirectories = try? FileManager.default.contentsOfDirectory(
			at: base, includingPropertiesForKeys: [.isDirectoryKey]
		) else { return [] }

		// A user typically has many IDE versions installed; merging them all and
		// keeping the newest timestamp per path gives the best single list.
		var merged: [String: RecentProject] = [:]
		for directory in ideDirectories {
			let xml = directory
				.appendingPathComponent("options", isDirectory: true)
				.appendingPathComponent("recentProjects.xml")
			for project in parse(fileURL: xml) {
				if let existing = merged[project.path], existing.lastOpened >= project.lastOpened {
					continue
				}
				merged[project.path] = project
			}
		}

		return merged.values
			.filter { FileManager.default.fileExists(atPath: $0.path) }
			.sorted { $0.lastOpened > $1.lastOpened }
	}

	static func parse(fileURL: URL) -> [RecentProject] {
		guard let data = try? Data(contentsOf: fileURL),
		      let document = try? XMLDocument(data: data)
		else { return [] }
		return parse(document: document)
	}

	static func parse(document: XMLDocument) -> [RecentProject] {
		// Layout: RecentProjectsManager > option[additionalInfo] > map > entry[key]
		guard let entries = try? document.nodes(
			forXPath: "//component[@name='RecentProjectsManager']//map/entry"
		) else { return [] }

		let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
		var result: [RecentProject] = []

		for case let entry as XMLElement in entries {
			guard let rawKey = entry.attribute(forName: "key")?.stringValue else { continue }

			// Paths are stored with macro placeholders rather than absolute paths.
			let path = rawKey
				.replacingOccurrences(of: "$USER_HOME$", with: home)
				.replacingOccurrences(of: "$APPLICATION_HOME_DIR$", with: "/Applications")
			guard path.hasPrefix("/") else { continue }

			// Prefer activationTimestamp (last focused) over projectOpenTimestamp.
			let timestamp = milliseconds(in: entry, named: "activationTimestamp")
				?? milliseconds(in: entry, named: "projectOpenTimestamp")
			let colorIndex = (try? entry.nodes(forXPath: ".//RecentProjectColorInfo"))?
				.compactMap { ($0 as? XMLElement)?.attribute(forName: "associatedIndex")?.stringValue }
				.compactMap(Int.init)
				.first

			result.append(RecentProject(
				path: URL(fileURLWithPath: path).standardizedFileURL.path,
				lastOpened: timestamp.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast,
				colorIndex: colorIndex
			))
		}

		return result.sorted { $0.lastOpened > $1.lastOpened }
	}

	private static func milliseconds(in entry: XMLElement, named name: String) -> Double? {
		guard let nodes = try? entry.nodes(forXPath: ".//option[@name='\(name)']") else { return nil }
		for case let node as XMLElement in nodes {
			if let value = node.attribute(forName: "value")?.stringValue, let ms = Double(value) {
				return ms
			}
		}
		return nil
	}
}
