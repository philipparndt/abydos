import AppKit
import AbydosKit

/// What is left of running, once `RunCoordinator` has the rest.
///
/// The menu-bar actions AppKit resolves against the responder chain and finds
/// here, the run dropdown (whose popover takes a `MainWindowController` as its
/// owner), and the navigation history a run moves through. Each of these stayed
/// for a reason recorded where it is, not for want of somewhere to go.
extension MainWindowController {
	/// Watches what is selected in the editor.
	///
	/// Selecting an expression and asking to watch it is the short way round:
	/// the long way is reading it, remembering it, finding the watch field and
	/// typing it back in — during which the thing being debugged has not moved,
	/// but the attention has.
	func watchFromEditor(_ expression: String) {
		guard let pane = bottomPanel.activeDebugPane else {
			// Rather than nothing at all: the menu item is offered whenever
			// something is selected, so the answer to "why did that do nothing"
			// has to come from somewhere.
			notify(
				"Nothing to watch it in",
				detail: "Watching an expression needs a debug session. Start one and try again."
			)
			return
		}

		setPanelVisible(true)
		pane.watch(expression)
	}

	/// Shows the backlog: the list and the board, over `.abydos/backlog`.
	@objc func showBacklog(_ sender: Any?) {
		setPanelVisible(true)
		guard bottomPanel.showBacklog() != nil else {
			notify("No project is open", detail: "A backlog lives beside a project, in .abydos/backlog.")
			return
		}
	}

	/// Chooses which of the dashboard's two presentations is showing.
	///
	/// Only for `--backlog list|board`, which is how the two are photographed
	/// without a click. The segmented control is how anybody else gets there.
	func showBacklogMode(list: Bool) {
		bottomPanel.showBacklog()?.showList(list)
	}

	/// Which record the pane shows, for `--backlog openspec`.
	func showBacklogSource(openSpec: Bool) {
		bottomPanel.showBacklog()?.showOpenSpec(openSpec)
	}

	/// Picks up the lowest-numbered ready item without opening the board first.
	///
	/// Worth its own command: once a backlog is in the habit of being worked
	/// this way, "start the next thing" is the whole of what somebody wants
	/// from it, and making them look at a board to press one button is making
	/// them look at a board.
	@objc func startNextBacklogItem(_ sender: Any?) {
		guard let root = project?.root else {
			notify("No project is open", detail: "A backlog lives beside a project, in .abydos/backlog.")
			return
		}
		let backlog = Backlog(projectRoot: root)
		guard backlog.exists else {
			notify(
				"This project has no backlog",
				detail: "Run `abydos-backlog init` in \(root.lastPathComponent) to make one."
			)
			return
		}
		guard let item = BacklogRunner.next(in: backlog) else {
			notify("Nothing is ready", detail: "Move an item into ready/ before an agent can pick it up.")
			return
		}

		setPanelVisible(true)
		bottomPanel.onBacklogNotice = { [weak self] title, detail in self?.notify(title, detail: detail) }
		bottomPanel.startBacklogItem(item)
	}

	/// Starts an agent review of this branch, reported over MCP.
	@objc func reviewBranch(_ sender: Any?) {
		setPanelVisible(true)

		Task { @MainActor in
			// Compare against the repository's default branch when we can tell
			// what it is, rather than assuming "main".
			let base = await defaultBaseBranch()
			startReview(scope: .branch(base: base))
		}
	}

	/// Reviews what is in the working tree but not yet committed.
	@objc func reviewUncommittedChanges(_ sender: Any?) {
		Task { @MainActor in
			// Checked first: starting an agent, waiting for it to look around and
			// report nothing is a slow way to learn there was nothing to review.
			if let project, let git = project.git {
				let root = git.root
				let status = await GitRepository.run(["status", "--porcelain"], in: root)
				if status.exitCode == 0,
				   status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					presentReviewProblem(
						title: "Nothing to review",
						message: "The working tree is clean — there are no uncommitted changes."
					)
					return
				}
			}

			setPanelVisible(true)
			startReview(scope: .uncommitted)
		}
	}

	private func startReview(scope: AgentLauncher.ReviewScope) {
		if case let .failure(error) = bottomPanel.startReview(scope: scope) {
			presentReviewProblem(title: "Could not start the review", message: error.message)
		}
	}

	/// Reports a reason a review did not start.
	///
	/// A sheet rather than an application-modal alert: it is attached to the
	/// window it concerns and does not stop the rest of the app, which matters
	/// for something as ordinary as a clean working tree.
	private func presentReviewProblem(title: String, message: String) {
		notify(title, detail: message)
	}

	/// Best guess at the branch a review should compare against.
	private func defaultBaseBranch() async -> String {
		guard let project, let git = project.git else { return "main" }
		let root = git.root

		// origin/HEAD names the default branch when the remote has been fetched.
		let result = await GitRepository.run(["symbolic-ref", "refs/remotes/origin/HEAD"], in: root)
		if result.exitCode == 0 {
			let reference = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
			if let name = reference.split(separator: "/").last, !name.isEmpty {
				return String(name)
			}
		}
		// Otherwise prefer whichever of the usual names exists.
		for candidate in ["main", "master"] {
			let exists = await GitRepository.run(["rev-parse", "--verify", candidate], in: root)
			if exists.exitCode == 0 { return candidate }
		}
		return "main"
	}

	@objc func newTerminal(_ sender: Any?) {
		setPanelVisible(true)
		bottomPanel.newTerminal()
	}

	/// What the chevron beside the panel's + offers.
	///
	/// The kinds of terminal there are: an ordinary one, and one inside each
	/// container this project says it can be worked on in. The + itself goes on
	/// making the ordinary one, exactly as the play button goes on running while
	/// the chevron beside it offers profiling and coverage — the same shape and
	/// the same bargain, because it is the same gesture.
	///
	/// **This is the menu the several-devcontainer refusal was waiting for.** A
	/// project with `.devcontainer/alpine` beside `.devcontainer/go` was refused
	/// whole, because picking one quietly is picking somebody's toolchain for
	/// them and there was nowhere to ask. There is now, so both are here, each
	/// named after itself.
	///
	/// Every item is the menu bar's own: the same selectors, put through the same
	/// `validateMenuItem`, so what the View menu offers and what this offers
	/// cannot drift apart, and a devcontainer entry is greyed out here for the
	/// projects it is greyed out for there.
	func newTerminalMenu() -> NSMenu {
		let menu = NSMenu()
		// Validated by hand below, item by item: left to itself AppKit asks the
		// responder chain, and a menu popped up from a view in the panel is not
		// always where this window is.
		menu.autoenablesItems = false

		let plain = NSMenuItem(
			title: "New Terminal", action: #selector(newTerminal(_:)), keyEquivalent: ""
		)
		plain.target = self
		menu.addItem(plain)

		let choices = devContainerChoices
		// One grey generic entry when there is nothing to name, so that the menu
		// says by being grey which projects this is for rather than by being
		// absent.
		for item in choices.isEmpty ? [makeContainerMenuItem(for: nil)] : choices.map(makeContainerMenuItem) {
			item.target = self
			// This is what names it after the container as well as what greys it
			// out — the item says "New Terminal in <the devcontainer's own name> ⬢"
			// for a project that has one, and stays grey and generic for the rest.
			item.isEnabled = validateMenuItem(item)
			menu.addItem(item)
		}
		return menu
	}

	/// A shell inside the container this project says it is worked on in.
	///
	/// The container is started if it is not up and reused if it is — which is
	/// what makes the second terminal, and coming back to the project, instant.
	/// Everything that can go wrong says what it was in one sentence rather than
	/// opening a shell somewhere half-configured: 0424 is explicit that a
	/// container missing what the file asked for looks like a broken editor.
	///
	/// **The tab opens now, not when it is ready.** The first time, this is a
	/// pull or a Dockerfile build and then everything the file asks to have run
	/// once the container exists, which together are minutes; a pane that stays
	/// empty for that long and then produces a prompt is a feature that looks
	/// like a hang. So the tab appears at once, the work is written into it, and
	/// that same pane becomes the shell — see `PreparingTerminal`.
	@objc func newTerminalInContainer(_ sender: Any?) {
		// The same root the menu item was enabled and named by, so that what is
		// started is what was clicked. Falling back to the scope when there is no
		// devcontainer anywhere keeps the "no devcontainer.json" message below,
		// which names the folder it looked in.
		guard let root = devContainerRoot ?? scopeRoot else { return }
		// Which of them was clicked. The item carries its own choice, because a
		// project offering two containers has two entries and the title is not
		// something an action can act on; nothing carrying one — the View menu's
		// single item, the harness — means the preferred one.
		let choice = choice(carriedBy: sender) ?? devContainerChoices.first
		setPanelVisible(true)
		// Named before anything is started, from the same file the menu item is
		// named from, so the tab is called what was clicked from the moment it
		// appears rather than being renamed under somebody at the end.
		let preparing = bottomPanel.newPreparingTerminal(
			title: Self.containerTabTitle(for: choice, in: root), subject: root.lastPathComponent
		)
		guard let choice else {
			preparing.refuse(
				"\(root.lastPathComponent) has no devcontainer.json — a project says what it "
					+ "needs to be worked on in .devcontainer/devcontainer.json."
			)
			return
		}
		preparing.step("Opening \(root.lastPathComponent) in \(choice.name)…")

		Task { @MainActor in
			guard let runtime = ContainerRuntime.discover(
				preference: ContainerRuntime.Preference(rawValue: Settings.shared.containerRuntime)
					?? .automatic
			) else {
				preparing.refuse(
					"Opening a project in its devcontainer needs a container runtime, and neither "
						+ "Docker nor Apple's `container` was found on this machine."
				)
				return
			}
			let outcome = await DevContainers.shared.session(
				for: choice.file,
				in: root,
				using: runtime,
				progress: preparing.progress
			)
			switch outcome {
			case let .refused(reason):
				preparing.refuse(reason)
			case let .running(session):
				// A terminal is an attach, which is the moment `postAttachCommand`
				// names. Not waited for: it is the one lifecycle command whose job
				// is to greet somebody, and a shell that opens a second later
				// because of it is worse than one that opens now.
				Task { await DevContainers.shared.attach(to: session) }
				preparing.becomeShell(running: DevContainers.terminalCommand(session))
			}
		}
	}

	/// How long something nobody asked to watch may take before the panel is
	/// opened to show it happening.
	///
	/// **Nobody asked for a pane here**, which is what the number is for. The
	/// language servers start a container because a file was opened, and a warm
	/// start is `docker run` and an attach — a second or two, after which a panel
	/// that had shown itself would be a panel that opened for nothing and has to
	/// be put away by hand. Past this, the thing being waited for is a pull, a
	/// build or a `postCreateCommand`, all of which are minutes, and minutes of
	/// silence is the complaint 0444's part 4 comes from.
	///
	/// The same number governs an image being fetched or built (0459), and for the
	/// same arithmetic rather than by analogy: an image already on the machine is
	/// answered for in milliseconds, and one that is not is a gigabyte or a
	/// compiler.
	private static let containerBuildRevealDelay: TimeInterval = 3

	/// A pane for a devcontainer that is being brought up for this project's
	/// language servers, or nil when no window is showing that project.
	///
	/// **Found by project rather than told to a window**, because the caller is
	/// `LanguageService`, which has no window: it starts containers for whichever
	/// project a file was opened in, from `warmUp`, which runs while the window is
	/// still being built. Nil is an ordinary answer and means the toasts that were
	/// there before.
	static func watchDevContainerStarting(
		project: URL, choice: DevContainerFile.Choice
	) -> PreparingTerminal? {
		let root = FilePath.canonical(project)
		let window = NSApp.windows.lazy
			.compactMap { $0.windowController as? MainWindowController }
			.first { $0.devContainerRoot.map(FilePath.canonical) == root }
		return window?.watchDevContainerStarting(choice: choice)
	}

	/// The same, for the window that is showing the project.
	///
	/// **The panel is not opened yet**, and that is the one decision here. The tab
	/// is made at once so that everything the start says is in it from the first
	/// line — there is no second chance at the output of a `docker build` — but a
	/// panel that shows itself is a panel that moved under somebody who was
	/// reading a file, so it waits to see whether there is anything worth showing.
	/// The keyboard is never touched either way: `takesFocus` is false, so even
	/// the shell this becomes leaves the editor where it was.
	private func watchDevContainerStarting(choice: DevContainerFile.Choice) -> PreparingTerminal {
		let root = devContainerRoot ?? choice.file.deletingLastPathComponent()
		let preparing = paneThatOpensLate(
			title: Self.containerTabTitle(for: choice, in: root),
			subject: root.lastPathComponent
		)
		preparing.step("Starting \(root.lastPathComponent) in \(choice.name)…")
		return preparing
	}

	/// A pane for an image being fetched or built for this project, or nil when
	/// no window is showing that project.
	///
	/// The same shape as `watchDevContainerStarting`, found the same way and for
	/// the same reason: the caller is `LanguageService` or a diagram, neither of
	/// which has a window, and the project is the only thing either of them knows
	/// that a window can be found by. Nil means the toast that was there before.
	///
	/// Either root, because either is what somebody would call this project: a
	/// language server is started for a subproject when one is open, and a
	/// diagram is exported against the project as a whole.
	static func watchImageArriving(
		project: URL, title: String, subject: String
	) -> PreparingTerminal? {
		let root = FilePath.canonical(project)
		let window = NSApp.windows.lazy
			.compactMap { $0.windowController as? MainWindowController }
			.first { controller in
				[controller.scopeRoot, controller.project?.root]
					.compactMap { $0 }
					.contains { FilePath.canonical($0) == root }
			}
		return window.map { $0.paneThatOpensLate(title: title, subject: subject) }
	}

	/// A pane for work nobody asked to watch: the tab is made now and shown
	/// later, or never.
	///
	/// **The panel is not opened yet**, and that is the one decision here. The tab
	/// is made at once so that everything the work says is in it from the first
	/// line — there is no second chance at the output of a `docker build` — but a
	/// panel that shows itself is a panel that moved under somebody who was
	/// reading a file, so it waits to see whether there is anything worth showing.
	/// The keyboard is never touched either way: `takesFocus` is false, so even a
	/// shell this becomes leaves the editor where it was.
	///
	/// One method for both the devcontainer coming up and the image arriving,
	/// because the terms are one decision rather than two that happen to agree —
	/// 0444 settled them and 0459 took them unchanged, and two copies would be two
	/// things to keep in step.
	private func paneThatOpensLate(title: String, subject: String) -> PreparingTerminal {
		let preparing = bottomPanel.newPreparingTerminal(
			title: title, subject: subject, takesFocus: false, select: false
		)
		// Work too quick to have been watched takes its tab away again rather than
		// leaving a pane nobody asked for — see `vanishesUnlessRevealed`, where the
		// arithmetic of one tab per session is written down.
		preparing.vanishesUnlessRevealed = true
		preparing.onRefused = { [weak self, weak preparing] in
			preparing?.reveal()
			self?.setPanelVisible(true)
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + Self.containerBuildRevealDelay) {
			[weak self, weak preparing] in
			// Still going: work that finished while nobody was looking has nothing
			// left to show, and a tab that was closed meanwhile is somebody saying
			// they do not want to watch.
			guard let preparing, preparing.isOpen, !preparing.isDone else { return }
			preparing.reveal()
			self?.setPanelVisible(true)
		}
		return preparing
	}

	/// The choice a menu item is carrying, if it is carrying one.
	func choice(carriedBy sender: Any?) -> DevContainerFile.Choice? {
		guard let file = (sender as? NSMenuItem)?.representedObject as? URL else { return nil }
		return devContainerChoices.first { $0.file == file }
	}

	/// What the tab in the container is called.
	///
	/// The devcontainer's own `name`, which is what the menu item that opens it
	/// says too — a window scoped to one subproject of ten that each have a
	/// devcontainer cannot say which one it means by saying "container", and
	/// neither can a project offering two of them. The folder the file sits in is
	/// the answer when it has no name of its own.
	static func containerTabTitle(for choice: DevContainerFile.Choice?, in root: URL) -> String {
		"\(containerName(for: choice, in: root)) \(containerMark)"
	}

	/// The mark of working inside a container.
	///
	/// Written once, because three things wear it and they have to be the same
	/// character: the terminal tab whose shell is in there, the menu item that
	/// opens one, and — since 0444 took the name off it — the whole of what the
	/// titlebar's pill shows.
	static let containerMark = "⬢"


	/// The same name without the `⬢`.
	///
	/// The hexagon is the mark of being *inside* — it is on the tab whose shell
	/// is in the container — so the titlebar pill wears it only while this
	/// project's tools are in there, and the dimmed pill for a container that is
	/// not in use does not (0438).
	static func containerName(for choice: DevContainerFile.Choice?, in root: URL) -> String {
		choice?.name ?? root.lastPathComponent
	}

	/// Where the devcontainer this window would open is, or nil when there is
	/// none to open.
	///
	/// **The subproject wins.** A repository of subprojects with a devcontainer
	/// each is not an unusual shape — `abydos-examples` is exactly that, and is
	/// the repository the examples live in — and the part somebody is working in
	/// is the part they mean. Asking `project?.root` alone made every one of
	/// those invisible to the menu.
	///
	/// The project root is still the answer when the subproject has none, which
	/// is every ordinary project and every subproject of one that carries the
	/// container for the whole repository.
	var devContainerRoot: URL? {
		if let subprojectRoot, DevContainerFile.exists(in: subprojectRoot) { return subprojectRoot }
		guard let root = project?.root, DevContainerFile.exists(in: root) else { return nil }
		return root
	}

	/// Whether this project has a devcontainer at all, which is what the menu
	/// item is enabled by.
	var hasDevContainer: Bool { devContainerRoot != nil }

	/// Every devcontainer this window can offer, named, in the order they are
	/// preferred.
	///
	/// Usually one. A project with `.devcontainer/alpine` beside
	/// `.devcontainer/go` has two, which used to refuse the project outright for
	/// want of anywhere to ask which one somebody meant.
	var devContainerChoices: [DevContainerFile.Choice] {
		guard let root = devContainerRoot else { return [] }
		return DevContainerFile.choices(in: root)
	}

	/// What the item is called when there is no container of ours to name.
	static let containerTerminalTitle = "New Terminal in Container"


	/// What a menu item says it will open.
	///
	/// Named after the container, exactly as the tab it opens is: a window
	/// scoped to one subproject of ten that each have a devcontainer cannot say
	/// which one it means by saying "Container", and neither can a project
	/// offering two at once. The devcontainer's own `name` is what the tab shows,
	/// so it is what this shows too, and the folder the file sits in is the
	/// answer when it has none.
	func devContainerMenuTitle(for choice: DevContainerFile.Choice?) -> String {
		// Nothing carried means the preferred one — which is the View menu's
		// single item, and every project that has only one.
		guard let root = devContainerRoot, let named = choice ?? devContainerChoices.first
		else { return Self.containerTerminalTitle }
		// The tab's own name, so the item and the tab it opens cannot drift.
		return "New Terminal in \(Self.containerTabTitle(for: named, in: root))"
	}

	/// What the View menu's single item says it will open.
	///
	/// **It opens the project's preferred devcontainer, and says which one that
	/// is.** A menu item is one command with one title; the alternative — turning
	/// it into a submenu when a project has several — costs the two things that
	/// make the ordinary case right, because AppKit does not send
	/// `validateMenuItem:` to an item that has a submenu, so it could no longer
	/// be renamed after the container it opens nor greyed out by the same rule as
	/// everything else in that menu. So it stays one item, and it does not
	/// disagree with the chevron's menu: it is that menu's first container entry,
	/// with the same title, opening the same container, through the same
	/// selector and the same validation. What it offers is a subset; what it says
	/// is never wrong.
	var devContainerMenuTitle: String { devContainerMenuTitle(for: nil) }

	/// Everything in this file, or everything in the project.
	@objc func goToSymbolInFile(_ sender: Any?) { results.goToSymbolInFile() }

	@objc func goToSymbolInProject(_ sender: Any?) { results.goToSymbolInProject() }

	/// Opens the profiler on the bottom panel.
	@objc func showProfiler(_ sender: Any?) {
		setPanelVisible(true)
		bottomPanel.showProfiler(address: RunCoordinator.lastProfilerAddress)
	}

	func reportDividerDrag(to position: CGFloat) {
		guard let split = editor.rootSplitForTesting, split.arrangedSubviews.count == 2 else {
			print("DIVIDER: no split of two groups")
			return
		}
		func report(_ stage: String) {
			let panes = split.arrangedSubviews
				.map { String(format: "%.0f", $0.frame.width) }
				.joined(separator: "|")
			print(String(
				format: "DIVIDER %@: window=%.0f total=%.0f panes=%@",
				stage, self.window?.frame.width ?? 0, split.bounds.width, panes
			))
		}
		for (index, pane) in split.arrangedSubviews.enumerated() {
			print(String(
				format: "DIVIDER pane%d: autoresizing=%@ fitting=%.0f",
				index,
				pane.translatesAutoresizingMaskIntoConstraints ? "yes" : "no",
				pane.fittingSize.width
			))
		}
		report("before")
		if let groups = split as? EditorGroupSplitView {
			groups.dragDividerForTesting(to: position)
		} else {
			split.setPosition(position, ofDividerAt: 0)
		}
		report("set")
		split.layoutSubtreeIfNeeded()
		report("split laid out")
		window?.contentView?.layoutSubtreeIfNeeded()
		report("window laid out")
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
			report("settled")
			// And what a narrower window does to the position somebody set,
			// which is the other half of a divider staying where it was put.
			// Put back afterwards, since the window remembers its size and a
			// run that measures something should not change it.
			if let window = self.window {
				let frame = window.frame
				var narrower = frame
				narrower.size.width -= 300
				window.setFrame(narrower, display: true, animate: false)
				window.contentView?.layoutSubtreeIfNeeded()
				report("window narrowed")
				window.setFrame(frame, display: true, animate: false)
				window.contentView?.layoutSubtreeIfNeeded()
				report("window back")
			}
			for (index, pane) in split.arrangedSubviews.enumerated() {
				for constraint in pane.constraintsAffectingLayout(for: .horizontal) {
					print("DIVIDER pane\(index) width: \(constraint)")
				}
			}
			fflush(stdout)
		}
	}

	/// Puts the caret on a line of the file being edited, for `:` in the palette.
	func goTo(line: Int) { editor.goTo(line: line) }

	/// The first responder from the keyboard outwards that answers a selector,
	/// having answered it — and its class, for the report.
	///
	/// The chain is walked here rather than handed to `NSApp.sendAction(_:to:
	/// from:)`, which is what a menu item with no target uses, because that one
	/// starts at the **key** window and a driven run has none: every step came
	/// back `reached nobody` while the pane plainly held the keyboard. This walks
	/// the same links AppKit would — first responder, then `nextResponder` out
	/// through the view tree, the window and this controller — so it still
	/// answers the question the item asks, which is who is in front of whom.
	func sendToKeyboard(_ selector: Selector) -> String {
		var responder: NSResponder? = window?.firstResponder
		while let current = responder {
			if current.responds(to: selector) {
				current.perform(selector, with: nil)
				return String(describing: type(of: current))
			}
			responder = current.nextResponder
		}
		return "nobody"
	}

	@objc func navigateBack(_ sender: Any?) {
		guard let place = navigation.back() else { return }
		go(to: place)
	}

	@objc func navigateForward(_ sender: Any?) {
		guard let place = navigation.forward() else { return }
		go(to: place)
	}

	private func go(to place: NavigationHistory.Place) {
		// A file that has been deleted since is dropped rather than reopened
		// empty, and the step is taken again so the shortcut still moves.
		guard FileManager.default.fileExists(atPath: place.file.path) else {
			navigation.forget(file: place.file)
			return
		}
		isNavigatingHistory = true
		editor.open(fileURL: place.file, atLine: place.line)
		DispatchQueue.main.async { [weak self] in self?.isNavigatingHistory = false }
	}

	var canNavigateBack: Bool { navigation.canGoBack }

	var canNavigateForward: Bool { navigation.canGoForward }

	/// The side buttons, taken here so that every view gets them.
	///
	/// **At the window, not in a view.** A window controller is in the responder
	/// chain behind everything in its window, so the editor, the tree, the panes
	/// and the terminal all reach this without any of them opting in — and a
	/// view that wants a side button for something of its own can still take it
	/// first, which is how the chain is meant to work.
	///
	/// The same `navigateBack` and `navigateForward` the menu items call: one
	/// history, one set of rules about when a step is possible, and one place
	/// where a file deleted since is dealt with. Both already return without
	/// doing anything where there is nowhere to go, which is what a button at
	/// the end of the history should do and needs no second check here.
	override func otherMouseDown(with event: NSEvent) {
		MouseReport.say("window down", event)
		// Consumed, so that a press nothing acted on does not arrive somewhere
		// else as one. What it will become happens on the release.
		switch MouseButtons.purpose(of: event.buttonNumber) {
		case .navigateBack, .navigateForward: return
		case .middleClick, .unclaimed: super.otherMouseDown(with: event)
		}
	}

	/// **On the release**, because a navigation changes what is on screen and a
	/// button still held is a hand still deciding — the same reason a click is a
	/// press and a release in the same place.
	override func otherMouseUp(with event: NSEvent) {
		MouseReport.say("window up", event)
		switch MouseButtons.purpose(of: event.buttonNumber) {
		case .navigateBack: navigateBack(nil)
		case .navigateForward: navigateForward(nil)
		case .middleClick, .unclaimed: super.otherMouseUp(with: event)
		}
	}

	@objc func stopSelected(_ sender: Any?) { run.stopRunning() }

	@objc func runSelected(_ sender: Any?) { run.runSelectedConfiguration(debug: false) }

	@objc func debugSelected(_ sender: Any?) { run.runSelectedConfiguration(debug: true) }

	/// A window for a terminal dragged out of a panel — including out of one of
	/// these windows, which is why it hands itself along.
	func openTerminalWindow(_ detached: DetachedTerminal, at screenPoint: NSPoint) {
		TerminalWindowController(
			detached: detached,
			at: screenPoint,
			workingDirectory: project?.root,
			openAnother: { [weak self] next, point in
				self?.openTerminalWindow(next, at: point)
			}
		).show()
	}

	/// A save during a Java debug session, which is what makes a swap happen.
	///
	/// **The compile is all this app asks for.** In `AUTO` the provider inside
	/// the bundle is listening to the workspace and redefines whatever jdtls
	/// writes, so the swap follows the compile finishing rather than this app
	/// guessing when it has.
	///
	/// One build at a time with at most one queued, the shape `refreshGitStatus`
	/// uses for the same reason: saves come faster than a workspace build
	/// finishes.
	func compileForHotSwapIfDebugging(_ url: URL) {
		guard url.pathExtension == "java", let project else { return }
		guard let session = bottomPanel.activeDebugSession, !session.cannotHotSwap else { return }
		// A session that has ended is not one a swap can reach, and asking for a
		// workspace build on every save after a debugging run would be the cost
		// of the feature without the feature.
		if case .terminated = session.state { return }
		if case .idle = session.state { return }
		run.queueHotSwapCompile(project: project.scopeRoot)
	}

	/// Opens the settings as a page in the editor.
	///
	/// A page rather than a window: a setting is judged by what it does to the
	/// thing beside it, and a preferences window covers exactly that.
	@objc func showSettingsPage(_ sender: Any?) {
		leaveTerminalFullScreen()
		guard let group = editor.activeGroup else { return }
		let page = (group.page(identifier: "settings") as? SettingsPage) ?? SettingsPage()
		group.openPage(page, title: "Settings", identifier: "settings", symbol: "gearshape")
		if let section = settingsSectionForTesting { page.show(named: section) }
		if let folded = settingsFoldForTesting { page.toggleFold(named: folded) }
	}

	/// Brings the debug panel forward.
	///
	/// Only that: what to start when nothing is running is a question with more
	/// than one answer, and the strip's button asks it rather than guessing.
	@objc func showDebugPanel(_ sender: Any?) {
		setPanelVisible(true)
		bottomPanel.showDebug()
	}

	/// ⌘T while the keyboard is in the terminal: another tab.
	///
	/// Enabled only there, so the shortcut belongs to the terminal the way it
	/// does in a terminal application, and is not taken away from anything
	/// else that might want it elsewhere in the window.
	@objc func newTerminalTab(_ sender: Any?) {
		guard bottomPanel.hasKeyboardFocus else { return }
		bottomPanel.newTerminal()
	}

	/// ⌘D: the same shell, in a column beside the one in front.
	@objc func newTerminalTabBeside(_ sender: Any?) {
		guard bottomPanel.hasKeyboardFocus else { return }
		bottomPanel.newTerminalBesideCurrent()
	}

	var isTerminalFocused: Bool { bottomPanel.hasKeyboardFocus }

	/// Keystrokes a terminal has a prior claim on.
	///
	/// Control and a letter is the shell's own alphabet: this app may borrow
	/// one for a menu, but not while the keyboard is in a terminal.
	static let terminalShortcuts: [(key: String, modifiers: NSEvent.ModifierFlags)] = [
		("a", [.control]), ("c", [.control]), ("d", [.control]), ("e", [.control]),
		("k", [.control]), ("l", [.control]), ("n", [.control]), ("p", [.control]),
		("r", [.control]), ("u", [.control]), ("w", [.control]), ("z", [.control]),
	]
}
