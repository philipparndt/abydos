import AppKit
import AbydosKit

/// Building the list: which rows there are, in which order, and what the
/// filter leaves of them.
extension SwitcherViewController {
	// MARK: - Rows

	func buildRows() {
		// Branches only, filter or no filter: the pill opened this to pick a
		// branch, and offering to clone a repository underneath the results
		// would be answering a question nobody asked.
		if case .branches = focus {
			buildBranchRows()
			return
		}
		if case .runs = focus {
			buildRunRows()
			return
		}

		let delegate = NSApp.delegate as? AppDelegate
		RecentProjects.shared.pruneMissing()

		// While filtering, the list is only matching projects: the New/Open/Clone
		// actions are not things a filter can match, and keeping them would push
		// the results down.
		guard filterText.isEmpty else {
			buildFilteredRows(delegate: delegate)
			return
		}

		rows = []

		let openRoots = delegate?.openProjectRoots ?? []
		let openPaths = Set(openRoots.map(\.path))

		if !openRoots.isEmpty {
			rows.append(.header("Open Projects"))
			let recents = RecentProjects.shared.entries
			for root in openRoots {
				let entry = recents.first { $0.path == root.path }
					?? RecentProject(path: root.path, lastOpened: Date())
				rows.append(.project(entry, isOpen: true))
			}
		}

		// Recents excludes what is already listed above to avoid duplicates.
		let recents = RecentProjects.shared.entries.filter { !openPaths.contains($0.path) }
		if !recents.isEmpty {
			rows.append(.header("Recent Projects"))
			for entry in recents {
				rows.append(.project(entry, isOpen: false))
			}
		}

		// Everything else found on disk. A switcher that lists only what has
		// been opened before cannot help with the case it exists for: opening a
		// project for the first time.
		var listed = openPaths
		listed.formUnion(recents.map(\.path))
		let discovered = discoveredProjects(excluding: listed)
		if !discovered.isEmpty {
			rows.append(.header("All Projects"))
			for entry in discovered {
				rows.append(.project(entry, isOpen: false))
			}
		}

		// Underneath, not on top. This list is opened to reach a project, and
		// the three commands that are not one were standing in front of them.
		// They stay here rather than moving to the menu bar because only Open
		// is there today.
		rows.append(.header("Elsewhere"))
		if let root = currentProject?.root {
			// The folder this window is actually looking at, which on a linked
			// worktree is the worktree rather than the repository it came from.
			rows.append(.action(title: "Reveal in Finder", symbol: "magnifyingglass", shortcut: nil, detail: nil) { [weak self] in
				self?.onDismiss?()
				NSWorkspace.shared.activateFileViewerSelecting([root])
			})
		}
		rows.append(.action(title: "Open…", symbol: "folder", shortcut: nil, detail: nil) { [weak self] in
			self?.onDismiss?()
			delegate?.openProjectPanel(nil)
		})
		rows.append(.action(title: "New Project…", symbol: "plus", shortcut: nil, detail: nil) { [weak self] in
			self?.onDismiss?()
			self?.newProject()
		})
		rows.append(.action(title: "Clone Repository…", symbol: "arrow.trianglehead.branch", shortcut: nil, detail: nil) { [weak self] in
			self?.onDismiss?()
			self?.cloneRepository()
		})
	}

	/// How many matching projects a filtered list shows before the branches and
	/// actions below them would be pushed off the end.
	static let projectLimit = 8

	/// And how many files, for the same reason. Smaller than the project limit
	/// is deliberate: a two-letter query matches thousands of files where it
	/// matches a dozen projects, and the answer to "too many" is another letter.
	static let fileLimit = 8

	/// What the typing is asking for. The decision itself is `PaletteScope`,
	/// in the kit, where it can be asserted about without a window.
	var scope: PaletteScope { PaletteScope.of(filterText) }

	/// Matches on both name and path, so "3d" finds everything under ~/dev/3d.
	func buildFilteredRows(delegate: AppDelegate?) {
		let needle: String
		switch scope {
		case let .commands(query):
			rows = [.header("Actions")]
			rows.append(contentsOf: matchingActions(query))
			return
		case let .line(number):
			buildLineRows(number)
			return
		case let .everything(query):
			needle = query
		}

		let openPaths = Set((delegate?.openProjectRoots ?? []).map(\.path))

		var candidates = RecentProjects.shared.entries
		for root in delegate?.openProjectRoots ?? [] where !candidates.contains(where: { $0.path == root.path }) {
			candidates.append(RecentProject(path: root.path, lastOpened: Date()))
		}

		// Typing searches everything on disk, not just what has been opened.
		let known = Set(candidates.map(\.path))
		candidates.append(contentsOf: discoveredProjects(excluding: known))

		let projects = ProjectFilter.match(candidates, query: needle)

		rows = []
		if !projects.isEmpty {
			// Capped, and the header says so. A short query matches half the
			// disk, and without a limit the branches and actions underneath sit
			// below a hundred rows of projects, which is the same as not being
			// there. Narrowing the query is how the rest are reached.
			let shown = projects.prefix(Self.projectLimit)
			rows.append(.header(
				projects.count > shown.count
					? "Projects — \(shown.count) of \(projects.count)"
					: "Projects"
			))
			rows.append(contentsOf: shown.map {
				Row.project($0, isOpen: openPaths.contains($0.path))
			})
		}

		// Files of the project already open. Beside the projects rather than
		// behind a prefix of their own: somebody typing `mvnw` should not have
		// to decide which of four kinds of thing it is before they are allowed
		// to type it.
		if scope.offersFiles {
			if !filesAreReady {
				rows.append(.header("Files — still reading…"))
			} else if !fileMatches.isEmpty {
				rows.append(.header("Files"))
				rows.append(contentsOf: fileMatches.map(Row.file))
			}
		}

		// Branches of the repository already open. Typing a branch name is the
		// same gesture as typing a project's, and ends in the same place the
		// branch menu would have.
		let matched = branches.filter { $0.lowercased().contains(needle) }
		if !matched.isEmpty {
			rows.append(.header("Branches"))
			for branch in matched {
				rows.append(.branch(branch, isCurrent: branch == currentBranch))
			}
		}

		let actions = matchingActions(needle)
		if !actions.isEmpty {
			rows.append(.header("Actions"))
			rows.append(contentsOf: actions)
		}
	}

	/// Branches, in their folders, with the ones nobody should hunt for on top.
	///
	/// Filtering flattens the folders deliberately. Somebody who has typed
	/// `valid` is looking at four rows and does not need to be told which
	/// folders they are in — the names say that — and headings between four
	/// results are most of the list.
	func buildBranchRows() {
		rows = []
		let needle = filterText.lowercased()

		guard !branches.isEmpty else {
			// Said rather than left blank. Until git answers there is nothing to
			// show, and an empty popover looks like a repository with no
			// branches rather than one that has not been read yet.
			rows.append(.header(currentProject == nil ? "No repository" : "Reading branches…"))
			appendRepositoryRows(matching: needle)
			return
		}

		if !needle.isEmpty {
			let matched = branches.filter { $0.lowercased().contains(needle) }
			if matched.isEmpty {
				rows.append(.header("No branch matches"))
			} else {
				for branch in matched {
					rows.append(.branch(branch, isCurrent: branch == currentBranch))
				}
			}
			// Typing `fork` or `github` reaches the handoffs the same way typing
			// a branch name reaches a branch.
			appendRepositoryRows(matching: needle)
			return
		}

		// In the refs tree's LOCAL order, because the spec pins the two lists
		// together: two lists of the same branches in one window must not
		// disagree about their order.
		let arranged = BranchGrouping.arrange(
			branches, current: currentBranch, default: defaultBranch,
			by: Settings.shared.refsSortLocal, created: branchDates
		)
		for branch in arranged.pinned {
			rows.append(.branch(branch, isCurrent: branch == currentBranch))
		}
		for section in arranged.sections {
			// The loose branches keep the heading they always had; a folder gets
			// its own name, which is what somebody scanning for `fix/` reads.
			rows.append(.header(section.folder ?? "Branches"))
			for branch in section.branches {
				rows.append(.branch(branch, isCurrent: branch == currentBranch))
			}
		}
		appendRepositoryRows(matching: needle)
	}

	/// The handoffs, under the branches, where the branch menu used to keep them.
	///
	/// Under rather than over: this popover is opened to pick a branch, and the
	/// branch somebody wants must not have moved down four rows to make room for
	/// something they asked for once a week.
	func appendRepositoryRows(matching needle: String) {
		let handoffs = repositoryActions().filter {
			needle.isEmpty || $0.title.lowercased().contains(needle)
		}
		guard !handoffs.isEmpty else { return }
		rows.append(.header("Repository"))
		for handoff in handoffs {
			rows.append(.action(
				title: handoff.title, symbol: handoff.symbol,
				shortcut: nil, detail: nil, handler: handoff.handler
			))
		}
	}
}
