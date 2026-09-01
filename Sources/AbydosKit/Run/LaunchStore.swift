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
		let directory = AbydosFolder.runDirectory(in: root)
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
		try AbydosFolder.create(in: root)

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

		try AbydosFolder.create(in: root)
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
		AbydosFolder.runDirectory(in: root).appendingPathComponent(slug(name) + ".json")
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
		let directory = AbydosFolder.runDirectory(in: root)
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
	/// The session file for a project, or the one every folder shares.
	private static func file(for root: URL?, sharedFile: URL?) -> URL? {
		guard let root else { return sharedFile ?? defaultSharedFile() }
		return AbydosFolder.sessionFile(in: root)
	}

	/// Where the session for a folder that is in no working copy lives.
	///
	/// One file for all of them, kept where the application keeps its own
	/// things. A folder somebody walked into does not own a session: writing one
	/// beside it would leave a `.abydos` in every directory a shell has ever
	/// passed through — a session file per `cd`, scattered across a disk, for
	/// folders nobody chose to open.
	///
	/// nil rather than a second pair of functions, because it is the shape this
	/// already has next door: `OpenScratches.key(for:)` is
	/// `projectRoot.map(ScratchFiles.directoryName(for:))
	/// ?? ScratchFiles.globalDirectoryName`, and a scratch belongs either to a
	/// project or to nobody in particular. Beside `recents.json`, which is the
	/// other thing here that is about no project in particular.
	static func defaultSharedFile() -> URL? {
		guard let support = FileManager.default
			.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
		else { return nil }
		let folder = support.appendingPathComponent("Abydos", isDirectory: true)
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		return folder.appendingPathComponent("folder-session.json")
	}

	/// What the project had open, or nothing at all when the app is being
	/// driven.
	///
	/// A driven run shows what it was given and nothing else. This is the half
	/// of item 0522 that would have prevented every one of its three incidents
	/// on its own: a typing verb goes to whatever the window is showing, and
	/// what the window was showing was the tabs and the terminals somebody had
	/// left open in a project of their own — so `--type` landed in a source file
	/// nobody was editing, and characters meant for a shell of the run's own
	/// reached a tmux session the user was attached to elsewhere.
	///
	/// Refused here rather than at each of the eight places that ask, because a
	/// rule about what a run may see is not a rule any single caller can keep.
	///
	/// - Parameter driven: whether this run is one. An argument with the global
	///   as its default rather than a bare read of the global, so the rule can
	///   be put a question without a test having to make the whole process
	///   pretend to be a driven run — which the rest of the suite, running
	///   beside it, would then also be.
	/// - Parameter root: the project, or nil for a folder that is not one. See
	///   `defaultSharedFile` for what nil means and why it is spelled this way.
	/// - Parameter sharedFile: where the session every folder shares lives, or
	///   nil for the real one. A parameter for the reason `driven` is one: a test
	///   has to be able to put this question without writing into somebody's
	///   Application Support folder, which is a real place with real sessions in
	///   it.
	public static func read(
		in root: URL?,
		driven: Bool = DrivenRun.isActive,
		sharedFile: URL? = nil
	) -> ProjectSession? {
		guard !driven else { return nil }
		guard let file = file(for: root, sharedFile: sharedFile),
		      let data = try? Data(contentsOf: file),
		      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { return nil }

		let files = object["files"] as? [[String: Any]] ?? []
		let open = files.compactMap { entry -> ProjectSession.OpenFile? in
			guard let path = entry["path"] as? String else { return nil }
			return ProjectSession.OpenFile(
				path: path,
				line: entry["line"] as? Int ?? 1,
				isPreview: entry["preview"] as? Bool ?? false,
				// `mode` is the pane and `preview` is the provisional tab. Two
				// keys a word apart meaning entirely different things, which is
				// the file paying for a name collision older than it is.
				//
				// An unknown name reads as nothing rather than as a default: a
				// file written by a later version knows a mode this one does not,
				// and guessing at it is worse than falling back to the kind.
				previewMode: (entry["mode"] as? String).flatMap(PreviewMode.init(rawValue:)),
				dividerFraction: dividerFraction(entry["divider"])
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
			tmuxWindow: object["tmuxWindow"] as? String,
			subprojectPath: object["subproject"] as? String,
			selectedConfiguration: object["run"] as? String,
			xcodeDestinations: XcodeDestinationMemory.remembered(
				object["destinations"] as? [String: String] ?? [:]
			),
			breakpoints: readBreakpoints(object["breakpoints"]),
			reviewTicks: readReviewTicks(object["review"]),
			reviewCheckouts: (object["reviewCheckouts"] as? [String: Any] ?? [:])
				.compactMapValues { $0 as? Int },
			composedMessage: readComposedMessage(object["message"]),
			pages: readPages(object["pages"])
		)
		return session.isEmpty ? nil : session
	}

	/// The commit message a session file claims, if there is anything to it.
	///
	/// Either half may be missing — a summary with no description is the common
	/// shape — and a pair with nothing in it reads as nothing typed, so that a
	/// file left holding empty strings does not make a session non-empty.
	private static func readComposedMessage(_ raw: Any?) -> ProjectSession.ComposedMessage? {
		guard let entry = raw as? [String: Any] else { return nil }
		let message = ProjectSession.ComposedMessage(
			summary: entry["summary"] as? String ?? "",
			description: entry["description"] as? String ?? ""
		)
		return message.isEmpty ? nil : message
	}

	/// The pages a session file claims.
	///
	/// An entry with no identifier is nothing to reopen and is dropped rather
	/// than guessed at; what a page was showing is read as strings, since that
	/// is what a ref, a path and a stash's name are, and an identifier this
	/// version does not know simply finds no opener.
	private static func readPages(_ raw: Any?) -> [ProjectSession.OpenPage] {
		(raw as? [[String: Any]] ?? []).compactMap { entry in
			guard let identifier = entry["id"] as? String, !identifier.isEmpty else { return nil }
			let showing = (entry["showing"] as? [String: Any] ?? [:])
				.compactMapValues { $0 as? String }
			return ProjectSession.OpenPage(identifier: identifier, showing: showing)
		}
	}

	/// A divider a session file claims, if it is one a pane could have.
	///
	/// This file is JSON on disk that anything may have written, and a fraction
	/// outside the pane is not a divider at all: zero, one, a negative, or the
	/// `NaN` that any arithmetic on a missing number produces. A refused one
	/// leaves the halves equal, which is what an unsplit tab starts as anyway.
	static func dividerFraction(_ value: Any?) -> Double? {
		guard let fraction = (value as? NSNumber)?.doubleValue,
		      fraction.isFinite, fraction > 0, fraction < 1
		else { return nil }
		return fraction
	}

	/// Which files of which pull request had been read.
	///
	/// Read defensively, like everything else here: this is JSON on disk that
	/// anything may have written, and a tick that cannot be understood is a tick
	/// that never happened — which shows a file as unread, and showing is the
	/// safe direction.
	static func readReviewTicks(_ value: Any?) -> [String: [String: String]] {
		guard let entries = value as? [String: Any] else { return [:] }
		var found: [String: [String: String]] = [:]
		for (number, ticks) in entries {
			guard Int(number) != nil, let ticks = ticks as? [String: Any] else { continue }
			let paths = ticks.compactMapValues { $0 as? String }
			guard !paths.isEmpty else { continue }
			found[number] = paths
		}
		return found
	}

	/// The breakpoints a session file lists, back into what the debugger holds.
	///
	/// Unverified, always: whether the adapter can put a breakpoint on a line is
	/// a fact about a program that is running, and nothing is running yet. Drawn
	/// hollow until one says so, which is what an unverified breakpoint means.
	static func readBreakpoints(_ value: Any?) -> [String: [Breakpoint]] {
		guard let entries = value as? [[String: Any]] else { return [:] }

		var found: [String: [Breakpoint]] = [:]
		for entry in entries {
			guard let path = entry["path"] as? String, let line = entry["line"] as? Int else { continue }
			var breakpoint = Breakpoint(file: path, line: line)
			breakpoint.isEnabled = (entry["disabled"] as? Bool) != true
			breakpoint.condition = entry["condition"] as? String
			breakpoint.hitCondition = entry["hits"] as? String
			breakpoint.logMessage = entry["log"] as? String
			found[path, default: []].append(breakpoint)
		}
		return found
	}

	/// Writes what is open, or removes the file when nothing is.
	/// Writes what a project has open — unless the app is being driven, in which
	/// case there is nothing here that belongs to the project.
	///
	/// The other half of the rule above, and the one that answers "leaves
	/// nothing behind": a driven run that wrote its session would put its own
	/// tabs into the project it was pointed at and, for a project that has no
	/// `.abydos` yet, create the folder to do it in — which for somebody's own
	/// checkout is a file appearing in `git status` after a capture.
	/// - Parameter root: the project, or nil for a folder that is not one.
	/// - Parameter sharedFile: as on `read`.
	public static func write(
		_ session: ProjectSession,
		in root: URL?,
		driven: Bool = DrivenRun.isActive,
		sharedFile: URL? = nil
	) throws {
		guard !driven else { return }
		guard let file = file(for: root, sharedFile: sharedFile) else { return }

		// What a folder shares is the files and nothing else. Terminals, the
		// tmux window and the chosen configuration are all answers to "what was
		// this project set up to do", and a folder is not set up to do anything:
		// a shell in one is a shell somebody is using, not a shell the folder
		// came with. Refused here rather than at the callers, for the reason the
		// driven rule above is refused here.
		let session = root == nil ? session.filesOnly : session

		guard !session.isEmpty else {
			try? FileManager.default.removeItem(at: file)
			return
		}

		if let root { try AbydosFolder.create(in: root) }
		var object: [String: Any] = [
			"files": session.files.map { open -> [String: Any] in
				var entry: [String: Any] = ["path": open.path, "line": open.line]
				if open.isPreview { entry["preview"] = true }
				// Only where there is something to remember. Most tabs are source
				// files with no rendered form, and a `"mode": "source"` beside
				// every one of them is a line of noise per tab in a file somebody
				// reads when a session comes back wrong.
				if let mode = open.previewMode { entry["mode"] = mode.rawValue }
				if let divider = open.dividerFraction {
					// Two places, which is a pixel or so on any pane anybody has:
					// the rest is a fraction printing itself in full, and it makes
					// the file noisy in git for a divider that did not move.
					entry["divider"] = (divider * 100).rounded() / 100
				}
				return entry
			},
		]
		if let active = session.activePath { object["active"] = active }
		if session.isPanelVisible { object["panel"] = true }
		if let window = session.tmuxWindow { object["tmuxWindow"] = window }
		if let subproject = session.subprojectPath { object["subproject"] = subproject }
		if let run = session.selectedConfiguration { object["run"] = run }
		if !session.xcodeDestinations.isEmpty { object["destinations"] = session.xcodeDestinations }
		if !session.breakpoints.isEmpty {
			// Flat rather than grouped by file, because that is what a breakpoint
			// is: one line in one file, and a file with none should leave nothing
			// behind. Sorted, so a file that gains and loses one does not rewrite
			// itself in a different order each time and turn into a diff.
			object["breakpoints"] = session.breakpoints
				.sorted { $0.key < $1.key }
				.flatMap { file, list in
					list.sorted { $0.line < $1.line }.map { breakpoint -> [String: Any] in
						var entry: [String: Any] = ["path": file, "line": breakpoint.line]
						if !breakpoint.isEnabled { entry["disabled"] = true }
						if let condition = breakpoint.condition { entry["condition"] = condition }
						if let hits = breakpoint.hitCondition { entry["hits"] = hits }
						if let message = breakpoint.logMessage { entry["log"] = message }
						return entry
					}
				}
		}
		if !session.reviewTicks.isEmpty {
			object["review"] = session.reviewTicks
		}
		if !session.reviewCheckouts.isEmpty {
			object["reviewCheckouts"] = session.reviewCheckouts
		}
		if let message = session.composedMessage, !message.isEmpty {
			// Each half only where it says something, for the reason `mode` is
			// written that way: a `"description": ""` beside every summary is a
			// line of noise in a file somebody reads when a session comes back
			// wrong.
			var entry: [String: Any] = [:]
			if !message.summary.isEmpty { entry["summary"] = message.summary }
			if !message.description.isEmpty { entry["description"] = message.description }
			object["message"] = entry
		}
		if !session.pages.isEmpty {
			object["pages"] = session.pages.map { page -> [String: Any] in
				var entry: [String: Any] = ["id": page.identifier]
				if !page.showing.isEmpty { entry["showing"] = page.showing }
				return entry
			}
		}
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
