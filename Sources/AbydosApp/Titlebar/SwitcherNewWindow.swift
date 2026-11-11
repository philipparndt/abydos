import AppKit
import AbydosKit

/// File ▸ New Window's list: projects, and the sessions on the tmux server,
/// either opened in a window of its own.
///
/// It used to open a copy of the window in front — the same project, its
/// terminal a second client of the same tmux session — which is what a second
/// monitor got, 2026-10-22. A project is shown in one window at most now, so a
/// new window asks what it is for. The sessions are here because a session is
/// often the work itself: one started in iTerm, or one a project's window left
/// behind, holding an agent somebody wants a window on.
extension SwitcherViewController {
	func buildNewWindowRows() {
		let delegate = NSApp.delegate as? AppDelegate
		RecentProjects.shared.pruneMissing()
		let needle = filterText.trimmingCharacters(in: .whitespaces)
		func matches(_ name: String) -> Bool {
			needle.isEmpty || name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
		}

		rows = []
		let openRoots = delegate?.openProjectRoots ?? []
		// Compared resolved: a project opened through a link — `/tmp` for
		// `/private/tmp` — is the same project as its recent entry.
		func key(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }
		let openPaths = Set(openRoots.map { key($0.path) })
		// The open ones as well as the recent and the discovered: a project can
		// be open without being in either, and its row is how this list says a
		// window has it.
		let open = openRoots.map { root in
			RecentProjects.shared.entries.first { key($0.path) == key(root.path) } ?? RecentProject(path: root.path, lastOpened: Date())
		}
		var listed: Set<String> = []
		var projects: [RecentProject] = []
		for entry in RecentProjects.shared.entries + discoveredProjects(excluding: []) + open where !listed.contains(key(entry.path)) {
			listed.insert(key(entry.path))
			if matches(entry.name) { projects.append(entry) }
		}
		if !projects.isEmpty {
			rows.append(.header("Projects"))
			// Open ones last among the projects: choosing one raises its window
			// rather than opening anything, which is not what this list is
			// mostly for.
			let closed = projects.filter { !openPaths.contains(key($0.path)) }
			let open = projects.filter { openPaths.contains(key($0.path)) }
			rows.append(contentsOf: closed.prefix(Self.projectLimit * 3).map { .project($0, isOpen: false) })
			rows.append(contentsOf: open.map { .project($0, isOpen: true) })
		}

		let sessions = TmuxGroups.shownAsOne(tmuxSessions).filter { matches($0.name) }
		if !sessions.isEmpty {
			rows.append(.header("tmux Sessions"))
			for session in sessions {
				rows.append(.action(
					title: session.name,
					symbol: "terminal",
					shortcut: nil,
					detail: sessionDetail(session)
				) { [weak self] in
					self?.onDismiss?()
					(NSApp.delegate as? AppDelegate)?.openInNewWindow(tmuxSession: session.name)
				})
			}
		}

		guard needle.isEmpty else { return }
		rows.append(.header("Elsewhere"))
		rows.append(.action(title: "Open…", symbol: "folder", shortcut: nil, detail: nil) { [weak self] in
			self?.onDismiss?()
			delegate?.openProjectPanel(nil)
		})
	}

	/// Asks the server once, and lists what it said.
	func readTmuxSessions() {
		Task { @MainActor [weak self] in
			let sessions = await TmuxMirror.sessions()
			guard let self, self.isViewLoaded else { return }
			self.tmuxSessions = sessions
			self.buildRows()
			self.tableView.reloadData()
			self.updatePreferredSize()
		}
	}

	/// What a project row says after its name in this list: whether a window has
	/// it, and whether it has a tmux session yet. Nothing in any other list.
	func projectNote(for entry: RecentProject) -> String? {
		guard case .newWindow = focus else { return nil }
		let isOpen = (NSApp.delegate as? AppDelegate)?.window(showing: entry.url) != nil
		let name = TmuxSessionName.of(entry.url)
		let session = tmuxSessions.first { $0.name == name || $0.group == name }
		let tmux = session.map { "tmux · \($0.windowCount) window\($0.windowCount == 1 ? "" : "s")" }
		return [isOpen ? "open" : nil, tmux].compactMap(\.self).joined(separator: " · ").nilIfEmpty
	}

	/// How many windows a session has, what its agents are doing, and which
	/// Abydos window is on it.
	func sessionDetail(_ session: TmuxMirror.SessionSummary) -> String {
		let members: Set<String> = session.group.map { group in
			Set(tmuxSessions.filter { $0.group == group }.map(\.name))
		} ?? [session.name]
		let agents = RunningSessions.shared.grouped(firstSlugs: [])
			.flatMap(\.sessions)
			.filter { $0.tmuxSession.map(members.contains) == true }
			.map { $0.shown(at: Date()) }
		let working = agents.filter { $0 == .working }.count
		let waiting = agents.filter { $0 == .needsInput }.count
		let windows = (NSApp.delegate as? AppDelegate)?.windowControllers
			.filter { controller in members.contains { controller.showsTmuxSession($0) } }
			.compactMap { $0.project?.name } ?? []

		var parts = ["\(session.windowCount) window\(session.windowCount == 1 ? "" : "s")"]
		if working > 0 { parts.append("\(working) working") }
		if waiting > 0 { parts.append("\(waiting) waiting") }
		if let first = windows.first { parts.append("in \(first)") }
		return parts.joined(separator: " · ")
	}
}

private extension String {
	var nilIfEmpty: String? { isEmpty ? nil : self }
}
