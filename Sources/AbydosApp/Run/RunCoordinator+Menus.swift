import AppKit
import AbydosKit

/// What can be run, and choosing one.
///
/// Part of `RunCoordinator`, in a file of its own because the whole of it is
/// some 2,900 lines and one file of that size is what this change exists to
/// stop. Still one type: the state is in the main file, private to that type,
/// rather than spread between three of them.
extension RunCoordinator {
	/// Offers what can be done with the line the play button sits on.
	///
	/// A menu rather than running straight away: run and debug are both things
	/// you want from the same marker, and a button that starts a process on a
	/// single click with no way to say which is a button you learn to distrust.
	func runConfiguration(forFile url: URL, line: Int) {
		let path = RunConfigurationDiscovery.canonicalPath(url)
		let matching = runConfigurations.filter { $0.file == path && $0.line == line }

		// The marker is drawn from the same list, so an empty match means the
		// two have drifted — say so rather than appearing to do nothing.
		guard !matching.isEmpty else {
			presentNothingToRun(at: line, in: url)
			return
		}

		let menu = NSMenu()
		menu.autoenablesItems = false

		for (index, configuration) in matching.enumerated() {
			// The name above the verbs rather than inside them. A Go
			// configuration is called "go run app", because that is what it
			// does, and putting it after a verb produced "Run go run app" —
			// which reads as a stutter and gets longer with every source that
			// names its configurations after a command line.
			if index > 0 { menu.addItem(.separator()) }
			let header = NSMenuItem(title: configuration.name, action: nil, keyEquivalent: "")
			header.isEnabled = false
			menu.addItem(header)

			let runItem = NSMenuItem(
				title: "Run",
				action: #selector(runMenuItem(_:)),
				keyEquivalent: ""
			)
			runItem.target = self
			runItem.representedObject = configuration.id
			runItem.toolTip = configuration.commandLine
			menu.addItem(runItem)

			// Listing a Debug that cannot start would be worse than leaving it
			// out. Go goes through Delve; Java goes through an adapter inside a
			// jdtls, which since 0452 is started for the debugger alone when the
			// server editing the project is not one that hosts it — so what has to
			// be asked here is whether *anything* can host it, not which server
			// happens to be answering about files.
			if configuration.isDebuggable, javaDebugSettledRefusal(configuration) == nil {
				let debugItem = NSMenuItem(
					title: "Debug",
					action: #selector(debugMenuItem(_:)),
					keyEquivalent: ""
				)
				debugItem.target = self
				debugItem.representedObject = configuration.id
				menu.addItem(debugItem)
			}

			// The gutter is where a program is run the first time, so it is
			// also where the configuration for it should come from: pressing
			// play twice from the same arrow should not mean typing it in.
			//
			// Except for a test. Tests are run from every function in a file
			// and saving one for each would leave hundreds nobody wants.
			if configuration.isDebuggable, !RunConfigurationDiscovery.isTest(configuration) {
				let save = NSMenuItem(
					title: "Save as Launch Configuration\u{2026}",
					action: #selector(saveGutterConfiguration(_:)),
					keyEquivalent: ""
				)
				save.target = self
				save.representedObject = configuration.id
				menu.addItem(save)
			}
		}

		popUpAtPointer(menu)
	}

	/// Shows a menu where the pointer is, in this window's coordinates.
	func popUpAtPointer(_ menu: NSMenu) {
		guard let contentView = hostWindow()?.contentView, let window = hostWindow() else {
			menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
			return
		}
		let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
		menu.popUp(positioning: nil, at: contentView.convert(inWindow, from: nil), in: contentView)
	}

	func presentNothingToRun(at line: Int, in url: URL) {
		notify("Nothing to run here", detail: """
		No run configuration was found for \(url.lastPathComponent):\(line). 		This is a bug — the marker is drawn from the same list.
		""")
	}

	/// Writes a launch configuration for what the gutter would have run.
	///
	/// The arrow beside `func main` knows the package, the arguments and where
	/// it runs; a configuration written from it is the same thing with a name,
	/// and it opens for editing so the arguments can be filled in before the
	/// first run.
	@objc func saveGutterConfiguration(_ sender: NSMenuItem) {
		guard let project = currentProject(), let discovered = configuration(for: sender) else { return }

		let package = MakeLaunch.relativeToWorkspace(
			path: discovered.workingDirectory, root: project.root
		)
		// A Java configuration names a class rather than a directory, and its
		// arguments are the program's — the goals that got Maven to start it are
		// not something to carry into a launch configuration.
		var configuration = discovered.mainClass.map { mainClass in
			LaunchConfiguration(
				name: discovered.name,
				type: "java",
				request: "launch",
				program: mainClass,
				workingDirectory: package,
				environment: discovered.environment
			)
		} ?? LaunchConfiguration(
			name: discovered.name,
			type: "go",
			request: "launch",
			program: package,
			arguments: discovered.arguments.filter { $0 != "run" && $0 != "." },
			workingDirectory: package,
			environment: discovered.environment
		)
		// A name that is already taken would replace something somebody else
		// wrote; the file is shared with the rest of the team.
		configuration.name = LaunchNames.free(
			like: discovered.name, avoiding: launchConfigurations.map(\.name)
		)
		presentConfigurationEditor(configuration, isNew: true)
	}

	@objc func runMenuItem(_ sender: NSMenuItem) {
		guard let configuration = configuration(for: sender) else { return }
		run(configuration)
	}

	@objc func debugMenuItem(_ sender: NSMenuItem) {
		guard let configuration = configuration(for: sender) else { return }
		debug(configuration)
	}

	/// Shows every configuration, for the Run menu.
	@objc func showRunConfigurations(_ sender: Any?) {
		guard !runConfigurations.isEmpty else {
			notify(
				"Nothing to run",
				detail: "No run configurations, makefiles or Go entry points were found in this project."
			)
			return
		}

		let menu = NSMenu()
		menu.autoenablesItems = false
		var lastSource: RunConfiguration.Source?

		for configuration in runConfigurations {
			if configuration.source != lastSource {
				if lastSource != nil { menu.addItem(.separator()) }
				let header = NSMenuItem(title: title(for: configuration.source), action: nil, keyEquivalent: "")
				header.isEnabled = false
				menu.addItem(header)
				lastSource = configuration.source
			}

			let item = NSMenuItem(title: configuration.name, action: #selector(runMenuItem(_:)), keyEquivalent: "")
			item.target = self
			item.representedObject = configuration.id
			item.toolTip = configuration.commandLine

			// A scheme runs somewhere, and where is a second choice beside it
			// rather than an entry of its own for each combination: a machine
			// with several simulator runtimes offers dozens, and a list of
			// dozens is not a list anybody reads.
			if let target = configuration.xcode {
				item.submenu = destinationMenu(for: configuration, target: target)
			}
			menu.addItem(item)
		}

		// Centred in the window: this is reached from the menu bar and from ⌃R,
		// so the pointer is not where the user is looking. The previous version
		// converted a screen point that was already in screen coordinates and
		// placed the menu off the window entirely.
		guard let contentView = hostWindow()?.contentView else { return }
		menu.popUp(
			positioning: nil,
			at: NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY),
			in: contentView
		)
	}

	/// Where a scheme can go, with a run mark beside where it went last.
	///
	/// Filled in as the answer arrives rather than before the menu opens: the
	/// question takes about twelve seconds and a menu that waits for it is a
	/// menu that does not open. Items are added to a menu that may already be
	/// on screen, which AppKit allows and which is the whole point — the list
	/// grows under the pointer instead of appearing a keystroke later.
	func destinationMenu(for configuration: RunConfiguration, target: XcodeTarget) -> NSMenu {
		let menu = NSMenu()
		menu.autoenablesItems = false

		let known = XcodeDestinations.shared.known(for: target)
		if known.isEmpty {
			let waiting = NSMenuItem(title: "Finding destinations…", action: nil, keyEquivalent: "")
			waiting.isEnabled = false
			menu.addItem(waiting)

			let directory = URL(fileURLWithPath: configuration.workingDirectory)
			Task { @MainActor in
				let found = await XcodeDestinations.shared.destinations(
					for: target, workingDirectory: directory
				)
				menu.removeAllItems()
				if found.isEmpty {
					let empty = NSMenuItem(title: "No destinations", action: nil, keyEquivalent: "")
					empty.isEnabled = false
					menu.addItem(empty)
					return
				}
				self.fill(menu, with: found, for: configuration, target: target)
			}
		} else {
			fill(menu, with: known, for: configuration, target: target)
		}
		return menu
	}

	func fill(
		_ menu: NSMenu,
		with destinations: [XcodeDestination],
		for configuration: RunConfiguration,
		target: XcodeTarget
	) {
		let remembered = xcodeDestinations[XcodeDestinationMemory.key(for: target)]
			?? XcodeDestinations.shared.preferred(among: destinations)?.id

		// This Mac and the devices on the desk in full, then one simulator per
		// family — the newest of each — and the other seventy-odd behind a
		// dialog that can be typed into. A real project answers with 79
		// destinations, of which 75 are simulators, and a menu that long is a
		// column running off the screen with no way to search it.
		let shortlist = XcodeDestinationMenu.newestOfEachFamily(among: destinations)
		let rest = XcodeDestinationMenu.rest(among: destinations, shown: shortlist)
		let inMenu = destinations.filter { $0.kind != .simulator } + shortlist

		// This Mac, then the phones and iPads, then the simulators — the order
		// somebody scans in. `xcodebuild` happens to answer in this order;
		// sorting says so rather than relying on it.
		let order: [XcodeDestination.Kind] = [.mac, .device, .simulator]
		let sorted = inMenu.enumerated().sorted { left, right in
			let a = order.firstIndex(of: left.element.kind) ?? order.count
			let b = order.firstIndex(of: right.element.kind) ?? order.count
			// Within a kind, the order they came in: simulators arrive grouped
			// by model and sorted by runtime, which is more useful than
			// alphabetical.
			return a != b ? a < b : left.offset < right.offset
		}.map(\.element)

		var lastKind: XcodeDestination.Kind?
		for destination in sorted {
			if destination.kind != lastKind {
				if lastKind != nil { menu.addItem(.separator()) }
				lastKind = destination.kind
				// Said rather than implied. A simulator and the phone on the
				// desk are one list of names otherwise, and "iPad (A16)" reads
				// like a device somebody owns — the runtime in brackets after
				// it is not what anybody notices first.
				//
				// This Mac belongs with the devices: it is a real machine, and
				// the heading is about what the thing is rather than what
				// `xcodebuild` calls its platform.
				let heading = NSMenuItem(
					title: destination.kind == .simulator ? "Simulators" : "Devices",
					action: nil, keyEquivalent: ""
				)
				heading.isEnabled = false
				menu.addItem(heading)
			}

			// How it is attached, beside its name: a phone on a cable and one
			// paired over Wi-Fi are offered identically by `xcodebuild`, and
			// the difference only shows up minutes later as an sidebar.install that
			// times out.
			let attachment = XcodeDestinations.shared.attachment(of: destination)?.attachment
			let item = NSMenuItem(
				title: attachment.map { "\(destination.title) — \($0)" } ?? destination.title,
				action: #selector(runOnDestination(_:)),
				keyEquivalent: ""
			)
			item.target = self
			item.representedObject = [configuration.id, destination.id]
			// The same mark as the scheme above it, because it means the same
			// thing one level down: the scheme says what will run and the
			// destination says where, and together they are the single path the
			// play button takes. Two different marks for one sentence is what
			// made this pair read as two unrelated settings.
			markWillRun(item, destination.id == remembered)
			menu.addItem(item)
		}

		// Nothing is hidden, only moved: everything the shortlist left out is
		// here, and a chosen one is remembered like any other.
		guard !rest.isEmpty else { return }
		menu.addItem(.separator())
		let more = NSMenuItem(
			title: "Other Simulators… (\(rest.count))",
			action: #selector(chooseOtherDestination(_:)),
			keyEquivalent: ""
		)
		more.target = self
		more.representedObject = [configuration.id]
		menu.addItem(more)

		// A device plugged in since is noticed on its own — `devicectl` is
		// asked every time this menu opens and is quick about it. A simulator
		// installed since is not: nothing cheap reports one, and asking
		// `xcodebuild` costs twelve seconds, which is not a thing to spend
		// every time somebody looks at a menu. So it is offered.
		let again = NSMenuItem(
			title: "Look Again…",
			action: #selector(refreshDestinations(_:)),
			keyEquivalent: ""
		)
		again.target = self
		again.representedObject = [configuration.id]
		menu.addItem(again)
	}

	@objc func refreshDestinations(_ sender: NSMenuItem) {
		guard let pair = sender.representedObject as? [String], let id = pair.first,
		      let configuration = runConfigurations.first(where: { $0.id == id }),
		      let target = configuration.xcode
		else { return }

		Task { @MainActor in
			_ = await XcodeDestinations.shared.destinations(
				for: target,
				workingDirectory: URL(fileURLWithPath: configuration.workingDirectory),
				refresh: true
			)
			// Rebuilt rather than left to the next opening: somebody who asks
			// for this is standing in front of the menu waiting for it.
			refreshRunConfigurations()
		}
	}

	@objc func chooseOtherDestination(_ sender: NSMenuItem) {
		guard let pair = sender.representedObject as? [String], let id = pair.first,
		      let configuration = runConfigurations.first(where: { $0.id == id }),
		      let target = configuration.xcode
		else { return }

		let all = XcodeDestinations.shared.known(for: target)
		let shortlist = XcodeDestinationMenu.newestOfEachFamily(among: all)
		let rest = XcodeDestinationMenu.rest(among: all, shown: shortlist)
		DestinationPicker.show(among: rest, relativeTo: hostWindow()) { [weak self] chosen in
			guard let self else { return }
			self.selectedConfigurationName = configuration.name
			self.start(configuration, target: target, on: chosen)
		}
	}

	@objc func runOnDestination(_ sender: NSMenuItem) {
		guard let pair = sender.representedObject as? [String],
		      pair.count == 2,
		      let configuration = runConfigurations.first(where: { $0.id == pair[0] }),
		      let target = configuration.xcode
		else { return }

		let chosen = XcodeDestinations.shared.known(for: target).first { $0.id == pair[1] }
		guard let chosen else { return }

		// Chosen on purpose, so it becomes what the play button repeats.
		selectedConfigurationName = configuration.name
		start(configuration, target: target, on: chosen)
	}

	/// Chooses a configuration by name, as the menu does.
	func selectConfigurationForTesting(named name: String) {
		selectedConfigurationName = name
		refreshRunControl()
	}

	/// Derives a configuration from a make goal and starts it.
	/// Picks a Makefile goal from the run menu exactly as clicking it does, and
	/// says what the run control shows afterwards.
	func chooseMakeRunForTesting(_ goal: String) {
		let goals = makeGoals()
		print("MAKE RUNS: \(goals.map(\.name))")
		guard let found = goals.first(where: { $0.name == goal }) else {
			print("MAKE: no goal called \(goal)")
			return
		}
		let item = NSMenuItem()
		item.representedObject = [found.makefile.path.path, found.name]
		makeGoalChosen(item)
		print("MAKE SELECTED: \(runControl?.selectedNameForTesting ?? "(none)")")
	}

	/// What play would start right now, without starting it.
	func describeRunTargetForTesting() {
		switch runTarget {
		case let .make(name):          print("MAKE PLAY: \(name)")
		case let .configuration(name): print("MAKE PLAY: \(name)")
		case .none:                    print("MAKE PLAY: (nothing)")
		}
	}

	func runMakeGoalForTesting(_ goal: String, debug: Bool) {
		guard let project = currentProject() else { return }
		let goals = debuggableMakeGoals()
		print("MAKE GOALS: \(goals.map(\.name))")

		guard let found = goals.first(where: { $0.name == goal }),
		      let configuration = MakeLaunch.configuration(
		          for: goal, in: found.makefile, projectRoot: project.root
		      )
		else {
			print("MAKE: no plan for \(goal)")
			return
		}
		_ = try? LaunchStore.save(configuration, in: currentLaunchRoot())
		selectedConfigurationName = configuration.name
		refreshRunControl()

		print("MAKE CONFIG: \(configuration.json)")
		if debug {
			debugConfiguration(configuration, in: currentLaunchRoot())
		} else {
			runConfiguration(configuration, in: currentLaunchRoot())
		}
	}

	func printConfigurationMenuForTesting(open goal: String?) {
		let list = runList()
		print("MENU: \(list.arrangement.rowCount) rows for "
			+ "\(list.arrangement.flatCount) runnable things")
		if let control = runControl {
			onShowConfigurationMenu(control.bounds, control)
			for line in ProjectSwitcherPopover.rowsForTesting() { print("MENU: \(line)") }
			guard let goal else { return }
			print("MENU: --- opening \(goal) ---")
			for line in ProjectSwitcherPopover.openGoalForTesting(goal) { print("MENU: \(line)") }
		}
		// Redirected to a file, stdout is fully buffered, and this run has no
		// natural end — the window stays up until it is killed, which throws the
		// buffer away along with the only thing the run was for.
		fflush(stdout)
	}

	/// Opens the editor on the selected configuration, making one if there is
	/// none yet — what pressing play would have done first.
	func editConfigurationForTesting() {
		guard let configuration = selectedConfiguration ?? createSuggestedConfiguration() else { return }
		selectedConfigurationName = configuration.name
		refreshRunControl()
		presentConfigurationEditor(configuration, isNew: false)
	}

	/// Writes a configuration for a project that has none, and says so.
	func createSuggestedConfiguration() -> LaunchConfiguration? {
		guard currentProject() != nil, let suggestion = LaunchFile.suggestion(for: currentLaunchRoot()) else { return nil }
		do {
			_ = try LaunchStore.save(suggestion, in: currentLaunchRoot())
			notify(
				"Created a launch configuration",
				detail: "Written to .vscode/launch.json as “\(suggestion.name)”. Edit it from the run menu.",
				kind: .information
			)
			return suggestion
		} catch {
			notify("Could not write launch.json", detail: error.localizedDescription)
			return nil
		}
	}

	func runConfiguration(_ configuration: LaunchConfiguration, in root: URL) {
		prepare(configuration, in: root) { [weak self] environment in
			guard let self else { return }
			if configuration.devPod != nil {
				self.runInCluster(configuration, in: root, environment: environment, debug: false)
			} else {
				self.startRun(configuration, in: root, environment: environment)
			}
		}
	}

	/// Everything the run popover needs: what can be run, what is chosen, and
	/// what choosing one means.
	///
	/// The four sources are the menu's own, untouched — this is only what is
	/// done with what they found.
	func runList() -> ProjectSwitcherPopover.RunList {
		let saved = launchConfigurations
		let savedNames = Set(saved.map(\.name))

		// The saved ones as rows. Only a name and a source are read from these:
		// choosing one selects it by name, exactly as the menu item did.
		var all: [RunConfiguration] = saved.map { entry in
			RunConfiguration(
				name: entry.name,
				source: .vscode,
				executable: entry.program,
				arguments: entry.arguments,
				workingDirectory: entry.workingDirectory
			)
		}

		all += runConfigurations.filter { $0.source == .xcodeScheme }

		for goal in makeGoals() where !savedNames.contains("make \(goal.name)") {
			all.append(RunConfiguration(
				name: "make \(goal.name)",
				source: .make,
				executable: "make",
				arguments: [goal.name],
				workingDirectory: goal.makefile.path.deletingLastPathComponent().path,
				file: goal.makefile.path.path
			))
		}

		all += runConfigurations.filter {
			($0.source == .maven || $0.source == .gradle || $0.source == .javaMain)
				&& !savedNames.contains($0.name)
		}

		var actions: [(title: String, symbol: String, handler: () -> Void)] = []
		if selectedConfiguration != nil {
			actions.append(("Edit\u{2026}", "pencil", { [weak self] in
				self?.editSelectedConfiguration()
			}))
			// One local and one in the cluster differ by two fields, so the way
			// to get the second is a copy of the first.
			actions.append(("Duplicate\u{2026}", "plus.square.on.square", { [weak self] in
				self?.duplicateSelectedConfiguration()
			}))
		}
		actions.append(("New\u{2026}", "plus", { [weak self] in self?.addConfiguration() }))
		actions.append(("Open launch.json", "doc.text", { [weak self] in self?.openLaunchFile() }))

		return ProjectSwitcherPopover.RunList(
			arrangement: RunPicker.arrange(all, pinned: savedNames),
			selected: selectedConfigurationName,
			choose: { [weak self] configuration in self?.chose(configuration) },
			actions: actions
		)
	}

	/// What choosing a row means, which depends on where the row came from.
	///
	/// The same four behaviours the menu items had, in one place instead of four
	/// selectors: a saved configuration is selected, a scheme is started, a make
	/// goal goes through `MakeLaunch` because it may become a debuggable entry,
	/// and everything else is selected as the goal to run.
	func chose(_ configuration: RunConfiguration) {
		switch configuration.source {
		case .vscode, .intelliJ:
			selectedMakeRun = nil
			selectedConfigurationName = configuration.name
			refreshRunControl()

		case .xcodeScheme:
			// A scheme has a second axis of its own — where it runs — and in the
			// menu that axis was a submenu, which is the only way a scheme could
			// be started from this control at all. A popover row has no submenu,
			// so the destination list opens as a menu from where the row was.
			// It is not folded like a reactor's modules because the destinations
			// are not known yet: asking Xcode takes about twelve seconds, and a
			// row that could not say what was behind it until then would be
			// worse than the menu it replaced.
			guard let target = configuration.xcode, let control = runControl else {
				run(configuration)
				return
			}
			let menu = destinationMenu(for: configuration, target: target)
			menu.popUp(positioning: nil, at: NSPoint(x: 0, y: control.bounds.maxY), in: control)

		case .make:
			guard let file = configuration.file, let goal = configuration.arguments.first else { return }
			chooseMakeGoal(goal, inMakefileAt: URL(fileURLWithPath: file))

		default:
			// Chosen, not started — the same bargain the build goals had: picking
			// from a list says which one, and the play button says when.
			selectedMakeRun = configuration
			selectedConfigurationName = configuration.name
			refreshRunControl()
		}
	}

	/// The goals in the project's Makefiles that start a Go program.
	///
	/// Read fresh each time the menu opens: a Makefile is edited while the
	/// project is open, and a stale list would offer goals that no longer
	/// exist and hide the ones just added.
	func debuggableMakeGoals() -> [(makefile: Makefile, name: String, summary: String)] {
		makeGoals().filter { MakeLaunch.plan(for: $0.name, in: $0.makefile) != nil }
	}

	/// Every goal the project's Makefiles define, worth offering to run.
	///
	/// Read here rather than taken from the discovered configurations: those
	/// are found on a background queue when the project opens, and a menu
	/// opened before that finished showed nothing at all — which is what "why
	/// is `make dev` not offered" turned out to be.
	///
	/// Goals that clean, sidebar.install or explain themselves are left out: a run
	/// menu is a list of ways to start the thing being worked on.
	func makeGoals() -> [(makefile: Makefile, name: String, summary: String)] {
		guard let project = currentProject() else { return [] }
		var found: [(Makefile, String, String)] = []

		let uninteresting: Set<String> = [
			"help", "clean", "distclean", "sidebar.install", "uninstall", "all",
		]
		for url in Makefile.find(in: project.root) {
			guard let makefile = Makefile.read(at: url) else { continue }
			for target in makefile.targets
			where !uninteresting.contains(target.name) && !target.recipe.isEmpty {
				found.append((makefile, target.name, target.summary))
			}
		}
		return found
	}

	/// Every goal every Makefile in the project defines, for the dialog.
	///
	/// Unfiltered, unlike the ones offered beside the play button. That list
	/// leaves out the goals nobody wants suggested — `help`, `clean`,
	/// `sidebar.install` — because suggesting them is noise; but somebody who came
	/// here has said which one they want, and refusing to show `sidebar.install`
	/// because it is usually uninteresting is refusing the thing they asked
	/// for.
	func allMakeGoals() -> [(makefile: Makefile, name: String, summary: String)] {
		guard let project = currentProject() else { return [] }
		var found: [(Makefile, String, String)] = []
		for url in Makefile.find(in: project.root) {
			guard let makefile = Makefile.read(at: url) else { continue }
			for target in makefile.targets where !target.recipe.isEmpty {
				found.append((makefile, target.name, target.summary))
			}
		}
		return found
	}

	/// Makes a launch configuration out of any goal in the project.
	@objc func newFromMakeGoal(_ sender: Any?) {
		let goals = allMakeGoals()
		guard !goals.isEmpty else {
			notify("No Makefile goals here", detail: "Nothing in this project defines any.")
			return
		}

		let alert = NSAlert()
		alert.messageText = "New from Make goal"
		alert.informativeText = "It becomes a launch configuration you can run, edit and keep."
		alert.addButton(withTitle: "Create")
		alert.addButton(withTitle: "Cancel")

		let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 25))
		for goal in goals {
			// The summary beside the name, since a Makefile that documents
			// itself has already said what each one is for.
			let title = goal.summary.isEmpty ? goal.name : "\(goal.name) — \(goal.summary)"
			picker.addItem(withTitle: title)
		}
		alert.accessoryView = picker

		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let goal = goals[max(0, min(goals.count - 1, picker.indexOfSelectedItem))]

        let directory = goal.makefile.path.deletingLastPathComponent()
		let configuration = LaunchConfiguration(
			name: LaunchNames.free(
				like: "make \(goal.name)", avoiding: launchConfigurations.map(\.name)
			),
			type: "shell",
			program: "make",
			arguments: [goal.name],
			workingDirectory: directory.path
		)
		do {
			_ = try LaunchStore.save(configuration, in: currentLaunchRoot())
		} catch {
			notify("Could not write the configuration", detail: error.localizedDescription)
			return
		}
		refreshRunConfigurations()
		selectedConfigurationName = configuration.name
		refreshRunControl()
	}

	/// Runs a goal the Makefile defines but nothing here can debug.
	///
	/// Exactly what `make <goal>` does, in the terminal, where its output
	/// belongs — the same path the play button beside a target in a Makefile
	/// takes.
	@objc func makeGoalRunChosen(_ sender: NSMenuItem) {
		guard let parts = sender.representedObject as? [String], parts.count == 2 else { return }
		// Chosen, not started: picking something from a list of things to run
		// says which one, and the play button says when. Starting a build
		// because somebody looked at the menu is a surprise.
		selectedMakeRun = RunConfiguration(
			name: "make \(parts[1])",
			source: .make,
			executable: "make",
			arguments: [parts[1]],
			workingDirectory: URL(fileURLWithPath: parts[0]).deletingLastPathComponent().path
		)
		selectedConfigurationName = selectedMakeRun?.name
		refreshRunControl()
	}


	/// Runs a goal of a Maven or Gradle build, chosen from the run menu.
	///
	/// Chosen, not started — the same bargain as a make goal: picking from a
	/// list says which one, and the play button says when.
	@objc func buildGoalChosen(_ sender: NSMenuItem) {
		guard let id = sender.representedObject as? String,
		      let configuration = runConfigurations.first(where: { $0.id == id })
		else { return }

		selectedMakeRun = configuration
		selectedConfigurationName = configuration.name
		refreshRunControl()
	}

	@objc func makeGoalChosen(_ sender: NSMenuItem) {
		guard let parts = sender.representedObject as? [String], parts.count == 2 else {
			notify("That Makefile could not be read")
			return
		}
		chooseMakeGoal(parts[1], inMakefileAt: URL(fileURLWithPath: parts[0]))
	}

	/// Picks a Makefile goal to run, from the menu or from the run popover.
	///
	/// Shared rather than duplicated: what a goal becomes is decided here, by
	/// `MakeLaunch`, and deciding it anywhere else is how a goal came to be
	/// offered as debuggable and then do nothing.
	func chooseMakeGoal(_ goal: String, inMakefileAt path: URL) {
		guard let project = currentProject(), let makefile = Makefile.read(at: path) else {
			notify("That Makefile could not be read")
			return
		}

		// Chosen, not started: picking something from a list of things to run
		// says which one, and the play button says when.
		switch MakeLaunch.choice(for: goal, in: makefile, projectRoot: project.root) {
		case let .run(configuration):
			selectedMakeRun = configuration
			selectedConfigurationName = configuration.name
			refreshRunControl()

		case let .debug(configuration):
			do {
				_ = try LaunchStore.save(configuration, in: currentLaunchRoot())
				selectedMakeRun = nil
				selectedConfigurationName = configuration.name
				refreshRunControl()
				notify(
					"Added “\(configuration.name)”",
					detail: Self.describe(configuration, root: currentLaunchRoot()),
					kind: .information
				)
			} catch {
				notify("Could not write launch.json", detail: error.localizedDescription)
			}
		}
	}

	@objc func configurationChosen(_ sender: NSMenuItem) {
		selectedMakeRun = nil
		selectedConfigurationName = sender.representedObject as? String
		refreshRunControl()
	}

	/// Copies the selected configuration under a free name and opens it.
	///
	/// The copy is what somebody wanted: the same program and arguments, run
	/// somewhere else. It opens in the editor because the name and the one
	/// field that differs are the reason for making it.
	@objc func duplicateSelectedConfiguration() {
		guard let configuration = selectedConfiguration else { return }
		var copy = configuration
		copy.name = LaunchNames.copy(
			of: configuration.name, avoiding: launchConfigurations.map(\.name)
		)
		presentConfigurationEditor(copy, isNew: true)
	}

	@objc func editSelectedConfiguration() {
		guard let configuration = selectedConfiguration else { return }
		presentConfigurationEditor(configuration, isNew: false)
	}

	/// Asks for the parts of a configuration worth changing by hand.
	///
	/// Arguments, working directory and environment — the three that differ
	/// between one run and the next. Everything else in the entry is left
	/// alone, including keys this app knows nothing about.
	func presentConfigurationEditor(_ configuration: LaunchConfiguration, isNew: Bool) {
		guard currentProject() != nil else { return }

		// A configuration that is not written down yet is written now, so the
		// page has something to select. Nothing is lost by it: an unwanted one
		// is deleted with the same button that deletes any other.
		if isNew {
			let free = LaunchNames.free(
				like: configuration.name, avoiding: launchConfigurations.map(\.name)
			)
			var stored = configuration
			stored.name = free
			do {
				_ = try LaunchStore.save(stored, in: currentLaunchRoot())
			} catch {
				notify("Could not write the configuration", detail: error.localizedDescription)
				return
			}
			selectedConfigurationName = free
			refreshRunControl()
			showLaunchConfigurations(selecting: free)
			return
		}
		showLaunchConfigurations(selecting: configuration.name)
	}

	/// Opens the launch configurations as a page in the editor.
	///
	/// A page rather than a dialog: a configuration is edited while looking at
	/// the code it runs, and a modal panel takes the project away for as long
	/// as it is open.
	func showLaunchConfigurations(selecting name: String? = nil) {
		onLeaveTerminalFullScreen()
		guard currentProject() != nil, let group = editor.activeGroup else { return }

		let page = (group.page(identifier: "launch") as? LaunchConfigurationsPage)
			?? LaunchConfigurationsPage()
		page.onSave = { [weak self] updated, previousName in
			guard let self else { return }
			do {
				// Renaming replaces rather than duplicating.
				if let previousName, previousName != updated.name {
					_ = try LaunchStore.remove(named: previousName, in: currentLaunchRoot())
					if self.selectedConfigurationName == previousName {
						self.selectedConfigurationName = updated.name
					}
				}
				_ = try LaunchStore.save(updated, in: currentLaunchRoot())
				self.refreshRunControl()
			} catch {
				notify("Could not write the configuration", detail: error.localizedDescription)
			}
		}
		page.onDelete = { [weak self] name in
			guard let self else { return }
			_ = try? LaunchStore.remove(named: name, in: currentLaunchRoot())
			if self.selectedConfigurationName == name { self.selectedConfigurationName = nil }
			self.refreshRunControl()
		}
		page.onStart = { [weak self] configuration, mode in
			guard let self else { return }
			self.selectedConfigurationName = configuration.name
			self.refreshRunControl()
			switch mode {
			case .run: self.runSelectedConfiguration(debug: false)
			case .debug: self.runSelectedConfiguration(debug: true)
			case .profile: self.profileSelectedConfiguration()
			case .coverage: self.runSelectedWithCoverage()
			}
		}

		group.openPage(page, title: "Launch Configurations", identifier: "launch", symbol: "play.square")

		// The part being worked on, not the repository around it: a subproject
		// has its own configurations, and a page showing the ones belonging to
		// somewhere else is a page showing nothing.
		page.load(
			LaunchStore.read(in: currentLaunchRoot()),
			root: currentLaunchRoot(),
			selecting: name ?? selectedConfigurationName
		)

		// The clusters this machine knows about, once kubectl has answered:
		// asking takes a moment and the rest of the page should not wait.
		if Kubernetes.isAvailable {
			Task { @MainActor [weak page] in
				let contexts = await Kubernetes.contexts()
				page?.setContexts(contexts)
			}
		}
	}

}
