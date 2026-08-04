import Foundation

/// Where a project's launch configurations live.
///
/// In `.ideai/run`, one file each, because that is this app's own folder and a
/// configuration is a small shared thing: a file per configuration means two
/// people adding one on the same afternoon do not meet in a merge conflict.
///
/// `.vscode/launch.json` is read but never written. Plenty of projects have
/// one and it would be rude to take it over — so it is imported: anything in
/// it that has no configuration here becomes one, once, and after that the two
/// go their own ways.
public enum LaunchStore {
	/// Everything the project defines, ours first.
	public static func read(in root: URL) -> [LaunchConfiguration] {
		var found = readOwn(in: root)
		let names = Set(found.map(\.name))

		for imported in LaunchFile.read(in: root) where !names.contains(imported.name) {
			found.append(imported)
		}
		return found
	}

	/// Only what is in `.ideai/run`, in the order a person would expect: by
	/// name, since the file system's order is nobody's.
	public static func readOwn(in root: URL) -> [LaunchConfiguration] {
		let directory = IdeaiFolder.runDirectory(in: root)
		let files = (try? FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: nil
		)) ?? []

		return files
			.filter { $0.pathExtension == "json" }
			.sorted { $0.lastPathComponent < $1.lastPathComponent }
			.compactMap { file in
				guard let data = try? Data(contentsOf: file),
				      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
				else { return nil }
				return LaunchConfiguration(json: object)
			}
	}

	/// Adds a configuration, or replaces the one with that name.
	@discardableResult
	public static func save(_ configuration: LaunchConfiguration, in root: URL) throws -> [LaunchConfiguration] {
		try IdeaiFolder.create(in: root)

		// The same configuration written under another file name — a rename
		// that changed the slug, a file somebody copied — would otherwise show
		// up twice in the menu.
		let target = fileURL(for: configuration.name, in: root)
		for duplicate in files(named: configuration.name, in: root) where duplicate != target {
			try? FileManager.default.removeItem(at: duplicate)
		}

		let data = try JSONSerialization.data(
			withJSONObject: configuration.json,
			options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		)
		var text = String(decoding: data, as: UTF8.self)
		if !text.hasSuffix("\n") { text += "\n" }
		try text.write(to: target, atomically: true, encoding: .utf8)

		return read(in: root)
	}

	@discardableResult
	public static func remove(named name: String, in root: URL) throws -> [LaunchConfiguration] {
		for file in files(named: name, in: root) {
			try FileManager.default.removeItem(at: file)
		}
		return read(in: root)
	}

	/// Brings a `.vscode/launch.json` in, for a project that has one.
	///
	/// Returns what it added. Nothing already here is touched: a configuration
	/// this app has been edited in is the newer of the two.
	@discardableResult
	public static func importVSCode(in root: URL) throws -> [LaunchConfiguration] {
		let existing = Set(readOwn(in: root).map(\.name))
		let incoming = LaunchFile.read(in: root).filter { !existing.contains($0.name) }
		guard !incoming.isEmpty else { return [] }

		try IdeaiFolder.create(in: root)
		for configuration in incoming {
			_ = try save(configuration, in: root)
		}
		return incoming
	}

	/// The file a configuration is written to.
	///
	/// Named after the configuration so a directory listing reads like the
	/// menu, with the characters a file system dislikes replaced rather than
	/// the name being turned into a number.
	public static func fileURL(for name: String, in root: URL) -> URL {
		IdeaiFolder.runDirectory(in: root).appendingPathComponent(slug(name) + ".json")
	}

	static func slug(_ name: String) -> String {
		let cleaned = name.map { character -> Character in
			if character.isLetter || character.isNumber { return character }
			return "-"
		}
		var slug = String(cleaned)
		while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
		slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
		return slug.isEmpty ? "configuration" : String(slug.prefix(60))
	}

	/// Every file holding a configuration with this name, whatever they are
	/// called.
	static func files(named name: String, in root: URL) -> [URL] {
		let directory = IdeaiFolder.runDirectory(in: root)
		let files = (try? FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: nil
		)) ?? []

		return files.filter { file in
			guard file.pathExtension == "json",
			      let data = try? Data(contentsOf: file),
			      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
			else { return false }
			return object["name"] as? String == name
		}
	}
}

/// This machine's view of a project: what was open in it.
public enum SessionStore {
	public static func read(in root: URL) -> ProjectSession? {
		guard let data = try? Data(contentsOf: IdeaiFolder.sessionFile(in: root)),
		      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return nil }

		let files = object["files"] as? [[String: Any]] ?? []
		let open = files.compactMap { entry -> ProjectSession.OpenFile? in
			guard let path = entry["path"] as? String else { return nil }
			return ProjectSession.OpenFile(
				path: path,
				line: entry["line"] as? Int ?? 1,
				isPreview: entry["preview"] as? Bool ?? false
			)
		}

		let terminals = (object["terminals"] as? [[String: Any]] ?? [])
			.compactMap { entry -> ProjectSession.OpenTerminal? in
				guard let name = entry["name"] as? String else { return nil }
				return ProjectSession.OpenTerminal(
					name: name,
					directory: entry["directory"] as? String,
					isRenamed: entry["renamed"] as? Bool ?? false
				)
			}

		let session = ProjectSession(
			files: open,
			activePath: object["active"] as? String,
			terminals: terminals,
			isPanelVisible: object["panel"] as? Bool ?? false,
			subprojectPath: object["subproject"] as? String,
			selectedConfiguration: object["run"] as? String
		)
		return session.isEmpty ? nil : session
	}

	/// Writes what is open, or removes the file when nothing is.
	public static func write(_ session: ProjectSession, in root: URL) throws {
		let file = IdeaiFolder.sessionFile(in: root)
		guard !session.isEmpty else {
			try? FileManager.default.removeItem(at: file)
			return
		}

		try IdeaiFolder.create(in: root)
		var object: [String: Any] = [
			"files": session.files.map { open -> [String: Any] in
				var entry: [String: Any] = ["path": open.path, "line": open.line]
				if open.isPreview { entry["preview"] = true }
				return entry
			},
		]
		if let active = session.activePath { object["active"] = active }
		if session.isPanelVisible { object["panel"] = true }
		if let subproject = session.subprojectPath { object["subproject"] = subproject }
		if let run = session.selectedConfiguration { object["run"] = run }
		if !session.terminals.isEmpty {
			object["terminals"] = session.terminals.map { terminal -> [String: Any] in
				var entry: [String: Any] = ["name": terminal.name]
				if let directory = terminal.directory { entry["directory"] = directory }
				if terminal.isRenamed { entry["renamed"] = true }
				return entry
			}
		}

		let data = try JSONSerialization.data(
			withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		)
		try data.write(to: file, options: .atomic)
	}
}

/// Naming configurations so two never collide.
///
/// The menu finds a configuration by its name and saving replaces by name, so
/// a duplicate that keeps the original's name replaces what it was copied
/// from — which is the opposite of duplicating.
public enum LaunchNames {
	/// `run the api` → `run the api copy`, then `copy 2`, and so on.
	public static func copy(of name: String, avoiding taken: [String]) -> String {
		free(like: name + " copy", avoiding: taken)
	}

	/// The name itself when nothing has it, and a number after it otherwise.
	public static func free(like name: String, avoiding taken: [String]) -> String {
		let existing = Set(taken)
		guard existing.contains(name) else { return name }

		var attempt = 2
		while existing.contains("\(name) \(attempt)") { attempt += 1 }
		return "\(name) \(attempt)"
	}
}
