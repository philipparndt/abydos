import AppKit
import AbydosKit

/// The run control: what this project can be told to do, and what pressing one
/// of those rows starts.
extension SwitcherViewController {
	// MARK: - Runs

	/// What the run control offers, with a reactor's goals named once each.
	///
	/// The sections are the ones the menu had — Configurations, Schemes, From
	/// the Makefile, From the build — because they were the right sections. What
	/// changes is that a goal offered in a hundred modules is one row in its
	/// section rather than a hundred, and the modules are reached by opening it
	/// or by typing one.
	func buildRunRows() {
		rows = []
		guard let runs else {
			rows.append(.header("Nothing to run"))
			return
		}

		// A goal that has been opened is the whole list: the question on screen
		// is no longer "what shall I run" but "where".
		if let openGoal, filterText.isEmpty {
			// A row rather than a heading, because a heading cannot be clicked
			// and ← is not something a mouse has either.
			rows.append(.action(
				title: openGoal.name,
				symbol: "chevron.left",
				shortcut: nil,
				detail: "\(openGoal.places) places",
				handler: { [weak self] in _ = self?.closeOpenGoal() }
			))
			if let root = openGoal.atRoot {
				rows.append(.run(
					root, title: "the reactor root", where: nil, isCurrent: isSelected(root)
				))
			}
			for configuration in openGoal.inModules {
				rows.append(.run(
					configuration,
					title: configuration.module ?? configuration.name,
					where: nil,
					isCurrent: isSelected(configuration)
				))
			}
			return
		}

		let needle = filterText.lowercased()
		if !needle.isEmpty {
			// Flattened, the way the branch list flattens its folders: somebody
			// who has typed a module name has already said which one they mean,
			// and a goal that has to be opened first would be asking twice.
			let found = RunPicker.matches(for: needle, in: runs.arrangement, limit: Self.runLimit)
			if found.isEmpty {
				rows.append(.header("Nothing matches"))
			} else {
				rows.append(.header("Runs"))
				for match in found {
					rows.append(.run(
						match.configuration,
						title: match.configuration.goalName,
						where: match.configuration.module,
						isCurrent: isSelected(match.configuration)
					))
				}
			}
			appendRunActions(matching: needle)
			return
		}

		if !runs.arrangement.pinned.isEmpty {
			rows.append(.header("Configurations"))
			for configuration in runs.arrangement.pinned {
				rows.append(.run(
					configuration, title: configuration.name,
					where: nil, isCurrent: isSelected(configuration)
				))
			}
		}

		// Singles and goals together, in their sections, in the order discovery
		// found them — a goal sits where its siblings would have.
		var sections: [(title: String, rows: [Row])] = []
		func place(_ row: Row, under title: String) {
			if let index = sections.firstIndex(where: { $0.title == title }) {
				sections[index].rows.append(row)
			} else {
				sections.append((title, [row]))
			}
		}
		for configuration in runs.arrangement.singles {
			place(
				.run(
					configuration, title: configuration.goalName,
					where: configuration.module, isCurrent: isSelected(configuration)
				),
				under: Self.heading(for: configuration.source)
			)
		}
		for goal in runs.arrangement.goals {
			guard let any = goal.whenChosen else { continue }
			place(.goal(goal), under: Self.heading(for: any.source))
		}
		for section in sections {
			rows.append(.header(section.title))
			rows.append(contentsOf: section.rows)
		}

		if rows.isEmpty { rows.append(.header("No configurations yet")) }
		appendRunActions(matching: "")
	}

	func isSelected(_ configuration: RunConfiguration) -> Bool {
		runs?.selected == configuration.name
	}

	/// Edit, duplicate, new, open the file — under everything, where the menu
	/// kept them.
	func appendRunActions(matching needle: String) {
		let actions = (runs?.actions ?? []).filter {
			needle.isEmpty || $0.title.lowercased().contains(needle)
		}
		guard !actions.isEmpty else { return }
		rows.append(.header("Configure"))
		for action in actions {
			rows.append(.action(
				title: action.title, symbol: action.symbol,
				shortcut: nil, detail: nil, handler: action.handler
			))
		}
	}

	/// The heading a discovered configuration belongs under — the menu's own
	/// words, kept.
	static func heading(for source: RunConfiguration.Source) -> String {
		switch source {
		case .xcodeScheme: "Schemes"
		case .make: "From the Makefile"
		case .maven, .gradle, .javaMain: "From the build"
		case .goModule, .swiftPackage, .bazel, .conan: "From the build"
		case .intelliJ, .vscode: "Configurations"
		}
	}

	/// The glyph beside a run row, so the sections are told apart at a glance
	/// rather than only by their headings.
	static func symbol(for source: RunConfiguration.Source) -> String {
		switch source {
		case .intelliJ, .vscode: "play.fill"
		case .xcodeScheme: "hammer"
		case .make: "gearshape"
		case .javaMain: "cup.and.saucer"
		case .maven, .gradle, .bazel, .conan, .swiftPackage, .goModule: "shippingbox"
		}
	}

	/// How many runs a filtered list shows. The same argument as the projects
	/// and files above: a two-letter query in a reactor matches hundreds, and
	/// the answer to "too many" is another letter.
	static let runLimit = 12

	/// What `:` offers: one row, once there is a number to go to.
	func buildLineRows(_ number: Int?) {
		rows = [.header("Go to Line")]
		guard let number, number > 0 else {
			// Nothing to do yet, but the header alone reads as a broken list.
			rows.append(.action(title: "Type a line number", symbol: "number", shortcut: nil, detail: nil, handler: {}))
			return
		}
		rows.append(.action(title: "Line \(number)", symbol: "arrow.right", shortcut: nil, detail: nil, handler: { [weak self] in
			self?.onDismiss?()
			self?.owner?.goTo(line: number)
		}))
	}

	/// One thing this repository can be handed off to.
	struct Handoff {
		let title: String
		let symbol: String
		let handler: () -> Void
	}

	/// Where this repository can be opened other than here: Fork, and whatever
	/// forge it is on.
	///
	/// **Shared, because the branch pill lost these when it became a popover.**
	/// They were `BranchMenu`'s and they came back only in the palette's action
	/// list, which the branch pill does not build — so somebody clicking the
	/// pill to open the branch on GitHub found the entry simply gone. One list,
	/// asked for by both.
	func repositoryActions() -> [Handoff] {
		var found: [Handoff] = []

		if let root = currentProject?.root, let fork = ForkIntegration.applicationURL() {
			found.append(Handoff(title: "Open in Fork", symbol: "arrow.up.forward.app", handler: {
				ForkIntegration.open(repository: root, application: fork)
			}))
		}

		guard let forge else { return found }
		let host = forge.displayName
		if let branch = currentBranch, let url = forge.url(forBranch: branch) {
			found.append(Handoff(title: "Open Branch on \(host)", symbol: "globe", handler: {
				NSWorkspace.shared.open(url)
			}))
		}
		if let url = forge.pullRequestsURL {
			found.append(Handoff(title: "Open Pull Requests on \(host)", symbol: "globe", handler: {
				NSWorkspace.shared.open(url)
			}))
		}
		if let url = forge.webURL {
			found.append(Handoff(title: "Open Repository on \(host)", symbol: "globe", handler: {
				NSWorkspace.shared.open(url)
			}))
		}
		return found
	}

	/// The things this window can be asked to do, as rows.
	///
	/// The same two handoffs the branch menu offers, flattened: a submenu cannot
	/// be typed at, so the host's pages become rows of their own and are found
	/// by the words in them.
	func matchingActions(_ needle: String) -> [Row] {
		var actions = repositoryActions().map {
			(title: $0.title, symbol: $0.symbol, handler: $0.handler)
		}

		if let root = currentProject?.root {
			actions.append((title: "Reveal in Finder", symbol: "magnifyingglass", handler: {
				NSWorkspace.shared.activateFileViewerSelecting([root])
			}))
		}

		let delegate = NSApp.delegate as? AppDelegate
		actions.append((title: "Open…", symbol: "folder", handler: { [weak self] in
			self?.onDismiss?()
			delegate?.openProjectPanel(nil)
		}))
		actions.append((title: "New Project…", symbol: "plus", handler: { [weak self] in
			self?.onDismiss?()
			self?.newProject()
		}))
		actions.append((title: "Clone Repository…", symbol: "arrow.trianglehead.branch", handler: { [weak self] in
			self?.onDismiss?()
			self?.cloneRepository()
		}))

		// Everything the menus offer, which is everything the app can do: a
		// command added to a menu tomorrow is in here the moment it is added,
		// with whatever key it answers to, and nobody has to remember this
		// list exists. The few above are the ones with no menu item of their
		// own — what this project's forge can do, which depends on the
		// repository rather than on the app.
		let contextual = actions.map {
			CommandDescriptor(title: $0.title, path: ["Project"], shortcut: nil)
		}
		let fromMenus = MenuCommands.all()

		let ranked = CommandSearch.match(contextual + fromMenus.map(\.descriptor), query: needle)

		return ranked.compactMap { command -> Row? in
			if let contextualIndex = actions.firstIndex(where: {
				$0.title == command.title && command.path == ["Project"]
			}) {
				let action = actions[contextualIndex]
				return .action(
					title: action.title, symbol: action.symbol,
					shortcut: nil, detail: nil, handler: action.handler
				)
			}

			guard let entry = fromMenus.first(where: {
				$0.descriptor.title == command.title && $0.descriptor.path == command.path
			}) else { return nil }

			return .action(
				title: command.title,
				symbol: "command",
				shortcut: command.shortcut,
				detail: command.path.joined(separator: " › "),
				handler: { [weak self] in
					self?.onDismiss?()
					// After the popover has gone: a menu action that opens a
					// sheet or moves the keyboard cannot do it while a popover
					// still has the window.
					DispatchQueue.main.async { entry.perform() }
				}
			)
		}
	}

	/// Starts the file list building, before anything has been typed.
	///
	/// On open rather than on the first keystroke: the first build of a large
	/// repository is a `git ls-files` of tens of thousands of paths, and started
	/// here it overlaps with somebody reaching for the keyboard instead of
	/// happening after they have finished with it. Only `everything` — the
	/// branch pill's list has no files in it and should not pay for one.
	func prepareFiles() {
		guard case .everything = focus, let files = currentProject?.files else { return }
		let askedAt = Date()
		Task { @MainActor [weak self] in
			await files.prepare()
			let count = await files.count
			guard let self, self.isViewLoaded else { return }
			// Only the flag. Anything already typed has a search of its own in
			// flight, waiting on this same build, and it redraws when it lands —
			// redrawing here as well would be the same list twice.
			self.filesAreReady = true

			guard ProjectSwitcherPopover.reportsForTesting else { return }
			print(String(
				format: "FILEINDEX ready after %8.1f ms  %6d files  %@",
				Date().timeIntervalSince(askedAt) * 1000, count, LaunchClock.loadSaid
			))
			fflush(stdout)
		}
	}

	/// Asks the index which files match, and redraws when it answers.
	///
	/// Off the main thread and out of `buildRows`. Matching 25,000 paths costs
	/// 25 ms, which is a quarter of the way to a visible stutter on every
	/// keystroke, and the project switch that held the main thread for 2,419 ms
	/// is recent enough to be worth not repeating through a different door.
	func searchFiles() {
		fileSearch?.cancel()
		fileSearch = nil

		guard scope.offersFiles, let query = scope.query,
		      let files = currentProject?.files
		else {
			fileMatches = []
			filesQuery = nil
			return
		}
		// The previous answer is kept on screen while this one is found, rather
		// than blanked: the list somebody is reading is nearly right, and a
		// section that empties and refills on every keystroke cannot be clicked.
		guard filesQuery != query else { return }

		let askedAt = Date()
		fileSearch = Task { @MainActor [weak self] in
			await files.prepare()
			let found = await files.matches(query, limit: Self.fileLimit)
			let ready = await files.isReady
			guard !Task.isCancelled, let self, self.isViewLoaded else { return }
			// Two keystrokes in flight land in whatever order they land, and an
			// older answer must not overwrite a newer one.
			guard case let .everything(current) = self.scope, current == query else { return }

			let answeredAt = Date()
			self.fileMatches = found
			self.filesQuery = query
			self.filesAreReady = ready
			self.rebuildPreservingSelection()

			guard ProjectSwitcherPopover.reportsForTesting else { return }
			// Two numbers, because they fail differently: the first is what the
			// index cost, the second is what the main thread paid for it.
			print(String(
				format: "FILEMATCH %-14@ answered %7.2f ms  drew %6.2f ms  %d hits",
				query as NSString,
				answeredAt.timeIntervalSince(askedAt) * 1000,
				Date().timeIntervalSince(answeredAt) * 1000,
				found.count
			))
			fflush(stdout)
		}
	}

	/// Redraws the list and puts the selection back where it was.
	///
	/// The files section arrives after the rest, so without this the highlight
	/// jumps to the top of the list a moment after somebody stopped typing —
	/// which is when they are about to press Return.
	func rebuildPreservingSelection() {
		let selected = rows.indices.contains(tableView.selectedRow)
			? describeForTesting(rows[tableView.selectedRow])
			: nil

		buildRows()
		tableView.reloadData()
		updatePreferredSize()

		if let selected,
		   let index = rows.firstIndex(where: { describeForTesting($0) == selected }) {
			tableView.selectRowIndexes([index], byExtendingSelection: false)
		} else {
			selectFirstSelectableRow()
		}
	}

	func applyFilter(_ text: String) {
		filterText = text.trimmingCharacters(in: .whitespaces)
		// Typing is a question about the whole list, not about the goal that
		// happened to be open when it started.
		if !filterText.isEmpty { openGoal = nil }
		searchFiles()
		buildRows()
		tableView.reloadData()
		updatePreferredSize()
		selectFirstSelectableRow()
	}
}
