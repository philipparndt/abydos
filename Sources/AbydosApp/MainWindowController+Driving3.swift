import AppKit
import AbydosKit

/// The third of the window's driving verbs, and the same residue as the other
/// two: what is left when everything that reached a sub-controller has gone to
/// it. Split by length rather than by subject, because it has none.
extension MainWindowController {
	func setPanelHeightForTesting(_ height: Double) {
		guard height > 0 else {
			setPanelVisible(false)
			return
		}
		if isPanelMaximized { togglePanelMaximized(nil) }
		setPanelVisible(true)
		panelHeight = CGFloat(height)

		DispatchQueue.main.async { [weak self] in
			guard let self else { return }
			let total = self.verticalSplitView.bounds.height
			guard total > 200 else { return }
			// The divider's own point, as everywhere else: a harness that asks
			// for 300 and gets 299 makes every capture a point out.
			self.verticalSplitView.setPosition(
				total - CGFloat(height) - self.verticalSplitView.dividerThickness,
				ofDividerAt: 0
			)
			self.tellTerminalsTheySizeChanged()
		}
	}

	/// Presses ⌘/ over the caret or selection a spec names, and says what came of
	/// it — which way it went, the sentence a refusal produces, and where the
	/// selection ended up. `--comment 3:5` or `--comment 3@8`.
	func toggleCommentForTesting(_ spec: String) {
		guard let (outcome, report) = editor.toggleCommentForTesting(spec) else {
			print("COMMENT \(spec): no editor")
			return
		}
		say(outcome)
		switch outcome {
		case let .toggled(toggle):
			print("COMMENT \(spec) \(toggle.commenting ? "commented" : "uncommented") — \(report)")
		case .nothing:
			print("COMMENT \(spec) nothing to do — \(report)")
		case let .unavailable(reason):
			print("COMMENT \(spec) refused: \(reason)")
		}
		fflush(stdout)
	}

	/// Works the search results the way somebody working through them does, and
	/// says what the list holds afterwards.
	///
	/// Recursive around `settle` for the same reason `treeStepsForTesting` is:
	/// the search itself streams in on the main queue, and a nested
	/// `RunLoop.run(until:)` here would wait without ever letting a batch land.
	func searchStepsForTesting(_ steps: String) {
		let script = steps.split(separator: ",").map(String.init)
		guard let pane = bottomPanel.existingSearchPane else {
			print("SEARCH: no results pane")
			return
		}
		for (index, step) in script.enumerated() {
			if step == "settle" || step.hasPrefix("settle:") {
				let seconds = step.hasPrefix("settle:")
					? Double(step.dropFirst("settle:".count)) ?? 1.0
					: 1.0
				let rest = script[(index + 1)...].joined(separator: ",")
				guard !rest.isEmpty else { return }
				DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
					self?.searchStepsForTesting(rest)
				}
				return
			}
			// ⌘Z the way the Edit menu sends it — at nobody in particular, down
			// the chain from whatever has the keyboard. Which of the window's undo
			// stacks answers is decided there and nowhere else, so asking the pane
			// directly would be answering the easier question.
			if step == "undo-key" || step == "redo-key" {
				NSApp.activate(ignoringOtherApps: true)
				window?.makeKeyAndOrderFront(nil)
				let selector = Selector((step == "undo-key" ? "undo:" : "redo:"))
				var responder = window?.firstResponder
				while let hop = responder, !hop.responds(to: selector) { responder = hop.nextResponder }
				func named(_ object: Any?) -> String {
					object.map { String(describing: type(of: $0)) } ?? "nobody"
				}
				print("SEARCH \(step): chain=\(named(responder)) "
					+ "appkit=\(named(NSApp.target(forAction: selector))) "
					+ "first=\(named(window?.firstResponder))")
				if !NSApp.sendAction(selector, to: nil, from: nil) {
					_ = responder?.tryToPerform(selector, with: nil)
				}
				continue
			}
			// ⇧⌘F again, which is the only way to ask where the *next* search
			// answers. The claim item 506 has to make about remembering is about
			// the next question and not about this pane, so a step that moved the
			// pane would be checking something else.
			if step == "again" {
				findInProject(nil)
				continue
			}
			// What the *editor* is showing after the row the walk has landed on,
			// which is the whole of item 533 and is a question about the other half
			// of the window. Between two `down`s it says whether the match the
			// selection moved onto is on the screen, and whether the view moved to
			// put it there.
			if step == "shown" {
				print("SEARCH shown: \(editor.revealReportForTesting)")
				fflush(stdout)
				continue
			}
			pane.stepForTesting(step)
		}
	}

	/// Says what the Cadova pane in the tab in front is doing, once a second.
	///
	/// Over time rather than once, because what 0499 claims is a *sequence*: a
	/// pane that says `building`, then `model` with a file beside it, and then —
	/// when somebody changes a constant and saves — `building` and `model` again
	/// with the run count one higher. A single reading cannot tell any of that
	/// from a pane that was showing a model all along. Flushed for the reason
	/// below.
	func watchCadovaForTesting(seconds: Double) {
		for second in 0...Int(seconds) {
			DispatchQueue.main.asyncAfter(deadline: .now() + Double(second)) { [weak self] in
				guard let self else { return }
				guard let pane = self.editorForTesting.cadovaPreview else {
					// **Never a bare "not found".** 0499 was watched green and shipped
					// broken because this line said only `no cadova pane in the tab in
					// front`, which is consistent with the pane being missing, with the
					// tab in front being some other file, and with there being no tab at
					// all — and the first of those was assumed. What the tab in front
					// *is* costs one line and tells the three apart.
					let groups = self.editorForTesting.groups
					let described = groups.isEmpty
						? "no editor group"
						: groups.map(\.activeTabDescriptionForTesting).joined(separator: " | ")
					print("CADOVA: \(second)s no cadova pane — \(described)")
					fflush(stdout)
					return
				}
				print("\(second)s \(pane.reportForTesting)")
				fflush(stdout)
			}
		}
	}

	/// Says where the diagram pane in the tab in front puts its message and its
	/// indicator, once a second.
	///
	/// 0512's instrument. A diagram pane goes through its states in the seconds
	/// after a file opens — a message with nothing turning, then the indicator
	/// over it while a tool runs, then a picture — and the claim the item makes
	/// is about the two rectangles at every one of them, so this prints them all
	/// rather than whichever moment a screenshot happened to catch. Flushed for
	/// the reason `--cadova-watch` is: a driver run ends in a kill, and a report
	/// still in stdout's buffer when the signal arrives never happened.
	func watchDiagramForTesting(seconds: Double) {
		for second in 0...Int(seconds) {
			DispatchQueue.main.asyncAfter(deadline: .now() + Double(second)) { [weak self] in
				guard let self else { return }
				guard let pane = self.editorForTesting.activeGroup?.diagramPreview else {
					// Never a bare "not found", for the reason above it: what the tab
					// in front *is* costs one line and tells three different failures
					// apart.
					let groups = self.editorForTesting.groups
					let described = groups.isEmpty
						? "no editor group"
						: groups.map(\.activeTabDescriptionForTesting).joined(separator: " | ")
					print("DIAGRAM: \(second)s no diagram pane — \(described)")
					fflush(stdout)
					return
				}
				print("\(second)s \(pane.reportForTesting)")
				fflush(stdout)
			}
		}
	}

	/// What is on the board and what the archive holds, for `--backlog openspec`.
	func backlogBoardReportForTesting() -> String {
		bottomPanel.showBacklog()?.boardReportForTesting ?? "no project"
	}

	/// Whether the first card of a column can be dragged.
	///
	/// By the column's name, which the pane resolves against whichever record is
	/// showing — the two no longer share a vocabulary, so `BacklogState` is the
	/// wrong thing to parse it into here.
	func backlogDragReportForTesting(state: String) -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.dragReportForTesting(column: state)
	}

	/// What the pane offers a project with no record of work, for
	/// `--backlog-offer`.
	func backlogOfferReportForTesting() -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.offerReportForTesting ?? "no offer: this project has a record of work"
	}

	/// The same, of a pane already open, **without showing it**.
	///
	/// `showBacklog()` reloads on the way past, so a report that asks through it
	/// cannot tell a pane that keeps itself up to date from one that is re-read
	/// by being asked. This is the question somebody sitting in front of the
	/// pane is asking: has it noticed yet, on its own?
	func backlogOfferAsItStandsForTesting() -> String {
		guard let pane = bottomPanel.existingBacklogPane else { return "no pane is open" }
		return pane.offerReportForTesting ?? "no offer: this project has a record of work"
	}

	/// Presses the OpenSpec offer, for `--backlog-offer openspec`.
	///
	/// Through the pane's own verb, so what is driven is what the button does
	/// and not a second path to the same command.
	func pressOpenSpecOfferForTesting() -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		pane.setUpOpenSpec()
		return OpenSpec.commandLine() == nil
			? "refused, because openspec is not installed"
			: "ran \(OpenSpec.initCommand()) in a terminal"
	}

	/// What a card's context menu offers, for `--backlog-menu`.
	func backlogMenuForTesting(number: Int) -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.menuTitlesForTesting(number: number)
	}

	/// The same for a change, which is named rather than numbered.
	func backlogMenuForTesting(change: String) -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.menuTitlesForTesting(change: change)
	}

	/// Files an item from the pane and says where it landed, for `--backlog-new`.
	func newBacklogItemForTesting(titled title: String) -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.newItemForTesting(titled: title)
	}

	/// Whether the pane is offering to make a backlog, and then making one.
	func backlogAbsentForTesting() -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.isOfferingToMakeOneForTesting ? "offering to make one" : "showing a backlog"
	}

	func makeBacklogForTesting() -> String {
		guard let pane = bottomPanel.showBacklog() else { return "no project" }
		return pane.makeBacklogForTesting()
	}

	/// Shows the panel and nothing else, so the strip has a layout to be asked
	/// about.
	///
	/// Deliberately not "open a terminal": the first terminal in a window
	/// attaches to tmux, and a window that is following its terminal then goes
	/// to wherever that session left its shell — a different project, with a
	/// different answer about devcontainers, which is what this dump is for.
	func showTerminalPanelForTesting() { setPanelVisible(true) }

	/// What that menu holds, for the harness: a menu cannot be photographed
	/// while it is open, which is why these dumps exist.
	func newTerminalMenuForTesting() -> String {
		newTerminalMenu().items
			.map { "\($0.title) enabled=\($0.isEnabled)" }
			.joined(separator: " | ")
	}

	/// What the language servers are doing, for the pill's tool tip.
	///
	/// Nothing at all for a project with none — a folder of Markdown has no
	/// servers to be waiting for, and a line saying so would be an answer to a
	/// question nobody asked.
	/// Presses the pill menu's entry whose words are these.
	@discardableResult
	func pressDevContainerMenuForTesting(_ title: String) -> Bool {
		guard let item = titlebar.devContainerPillMenu().items.first(where: { $0.title == title }),
		      let action = item.action, item.isEnabled
		else { return false }
		NSApp.sendAction(action, to: item.target, from: item)
		return true
	}

	/// Opens a terminal in the project's devcontainer and says what came back.
	///
	/// Through the menu item's own validation and action, because that is what
	/// the click does: a shell that works when a test calls the kit directly
	/// proves nothing about whether the menu reaches it.
	/// - Parameter which: the devcontainer to open, counting from one in the
	///   order the menu offers them, or nil for the one the View menu's item
	///   opens. A project offering two has to be openable in each, or "both are
	///   in the menu" is all that is ever proved.
	func exerciseDevContainerTerminalForTesting(which: Int? = nil) {
		let choices = devContainerChoices
		let chosen = which.flatMap { $0 >= 1 && $0 <= choices.count ? choices[$0 - 1] : nil }
		let item = makeContainerMenuItem(for: chosen)
		// The root as well as the answer: "there is no devcontainer here" is not
		// actionable without "here", and the project that is open is not always
		// the folder that was asked for. The container's root is printed beside
		// it because it is the subproject's rather than the project's whenever
		// the subproject has one, and the title because that is what somebody
		// reads before clicking.
		let enabled = validateMenuItem(item)
		print("DEVCONTAINER: root=\(project?.root.path ?? "-") "
			+ "scope=\(scopeRoot?.path ?? "-") container=\(devContainerRoot?.path ?? "-") "
			+ "file=\(hasDevContainer) choices=\(choices.count) enabled=\(enabled) "
			+ "title=\(item.title)")
		fflush(stdout)
		guard enabled else { return }
		// Through the item rather than through nil, so that which one was asked
		// for travels the way a click's does.
		item.target = self
		newTerminalInContainer(item)
		waitForContainerShellForTesting(seconds: 0)
	}

	/// The same, once for every devcontainer the project offers, each after the
	/// last has answered.
	///
	/// One at a time rather than all at once, and not on a clock: two shells
	/// coming up together would be two panes racing to be the active one, and
	/// what is being proved here is that a project really can have two containers
	/// up at the same time with somebody typing in each.
	func exerciseEveryDevContainerTerminalForTesting(from index: Int = 1) {
		let count = devContainerChoices.count
		guard index <= count else { return }
		exerciseDevContainerTerminalForTesting(which: index)
		guard index < count else { return }
		afterContainerShellForTesting = { [weak self] in
			self?.exerciseEveryDevContainerTerminalForTesting(from: index + 1)
		}
	}

	/// Waits for the tab to stop being a report and start being a shell, then
	/// types into it.
	///
	/// Asked of the pane rather than counted on a clock, because how long this
	/// takes is not something a number can be right about: a pull is minutes, a
	/// Dockerfile build is minutes, and `postCreateCommand` is however long
	/// somebody else's sidebar.install takes. The tab is there from the first moment
	/// either way — that is the point of it — so what is being waited for is the
	/// shell, and nothing else.
	private func waitForContainerShellForTesting(seconds: Int) {
		let outOfPatience = 180
		if bottomPanel.activeTerminalShowsOutputOnly, seconds < outOfPatience {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
				self?.waitForContainerShellForTesting(seconds: seconds + 1)
			}
			return
		}
		print("DEVCONTAINER: tab=\(bottomPanel.activeTerminalTitle ?? "-") ready after \(seconds)s")
		fflush(stdout)
		sendToTerminal("printf 'IN:%s:%s\\n' \"$(pwd)\" \"$(cat /etc/hostname)\"\n")
		DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
			guard let self else { return }
			for line in self.bottomPanel.terminalTextForTesting.split(separator: "\n")
			where line.contains("IN:") {
				print("DEVCONTAINER: \(line.trimmingCharacters(in: .whitespaces))")
			}
			fflush(stdout)
			let next = self.afterContainerShellForTesting
			self.afterContainerShellForTesting = nil
			next?()
		}
	}


	func pushChangesForTesting() { sidebar.changesPane?.pushForTesting() }

	/// Runs the selected configuration and puts the profiler on it.
	func profileSelectedForTesting() { run.profileSelectedConfiguration() }

	/// Opens two terminals side by side, as dropping one tab on the other's
	/// edge does.
	func splitTerminalsForTesting() {
		setPanelVisible(true)
		bottomPanel.newTerminal()
		bottomPanel.newTerminal()
		bottomPanel.splitForTesting()
	}

	/// Puts the profiler beside a terminal, as the tab menu does.
	func splitPanesForTesting() {
		setPanelVisible(true)
		bottomPanel.newTerminal()
		bottomPanel.showProfiler(address: RunCoordinator.lastProfilerAddress)
		bottomPanel.splitFirstBesideForTesting()
	}

	/// Splits, then does the things that used to collapse a split: opens a
	/// terminal, and activates another tab.
	func splitThenDisturbForTesting() {
		splitPanesForTesting()
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
			self?.bottomPanel.newTerminal()
			self?.bottomPanel.selectTabForTesting(0)
		}
	}

	/// One terminal, then "put it beside" — which is what somebody does first
	/// and what used to do nothing at all.
	func splitActiveForTesting() {
		setPanelVisible(true)
		bottomPanel.newTerminal()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
			self?.bottomPanel.splitActiveBesideForTesting()
		}
	}

	/// Puts settings in a group beside the editor and drags the divider between
	/// them, which is the only way to see this without a hand on the mouse.
	///
	/// A drag is a `setPosition` and the layout passes that follow it, so the
	/// position is set and then every stage is measured: the moment it is set,
	/// after the split has laid out, after the window has, and again once the
	/// run loop has been round. A width that is right at one stage and wrong at
	/// the next says which pass took it back.
	///
	/// `settings: false` is the control: the same two panes with a file in each,
	/// which says whether what happens is the page's doing or the split's.
	func dragSettingsDividerForTesting(to position: Double, settings: Bool = true) {
		guard editor.activeGroup?.activeTabURL != nil else {
			print("DIVIDER: nothing open to split")
			return
		}
		splitEditorRight(nil)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
			guard let self else { return }
			if settings { self.showSettingsPage(nil) }
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
				self.reportDividerDrag(to: CGFloat(position))
			}
		}
	}

	/// Shows the split preview a drag would show.
	func previewTerminalDropForTesting() {
		setPanelVisible(true)
		bottomPanel.newTerminal()
		bottomPanel.previewDropForTesting()
	}

	func tearOffTerminalForTesting() {
		setPanelVisible(true)
		bottomPanel.newTerminal()
		let point = window.map { NSPoint(x: $0.frame.maxX + 80, y: $0.frame.midY) } ?? .zero
		bottomPanel.tearOffForTesting(at: point)
	}

	/// Renames the terminal in front, the way a double-click on its tab does.
	func renameActiveTerminalForTesting(to name: String) {
		setPanelVisible(true)
		// An empty name opens the editor and leaves it there, which is how the
		// field itself gets captured.
		if name.isEmpty {
			bottomPanel.beginRenameActiveForTesting()
		} else {
			bottomPanel.renameActiveForTesting(to: name)
		}
	}

	func showPodsForTesting(filter: String, choose: Bool, kind: String?) {
		setPanelVisible(true)
		bottomPanel.showProfiler(address: "localhost:6060")?
			.showPodPickerForTesting(filter: filter, choose: choose, kind: kind)
	}

	func profileForTesting(address: String, kind: String) {
		setPanelVisible(true)
		guard let pane = bottomPanel.showProfiler(address: address) else { return }
		pane.connectForTesting(address: address)
		// After the index page has answered, since the kind list comes from it.
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
			pane.collectForTesting(kind: kind, seconds: 2)
			DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
				print("PROFILER: \(pane.statusForTesting) top=\(pane.topFunctionsForTesting)")
			}
		}
	}

	// The sub-controllers a driven run reaches, and the only state this class
	// exposes to one. A driving verb is declared on the thing it drives, so what
	// `AppDelegate` needs from the window is which editor, which panel and which
	// navigator — not the fields any of them keep.
	var editorForTesting: EditorAreaController { editor }

	var panelForTesting: BottomPanel { bottomPanel }


	var navigatorForTesting: ProjectNavigatorViewController { navigator }

	var resultsForTesting: ResultsPresenter { results }

	/// Walks the history and reports where each step landed.
	func navigateForTesting(_ steps: String) {
		for step in steps.split(separator: ",") {
			switch step {
			case "back": navigateBack(nil)
			case "forward": navigateForward(nil)
			default: continue
			}
			let place = editor.currentPlace
			print("NAV \(step): \(place.map { "\($0.url.lastPathComponent):\($0.line)" } ?? "nowhere")")
		}
	}

	/// Presses a mouse button over a named view, and says where the editor
	/// landed — `--mouse 3@editor,4@terminal`.
	///
	/// **The event goes to the view the pointer would be over**, not to the
	/// function it should end up calling. What was broken here was the path
	/// rather than the destination: `navigateBack` worked and nothing reached
	/// it, and the terminal ate the events on the way past. Calling
	/// `navigateBack` from a test would have passed the whole time.
	///
	/// The event is built through a `CGEvent` because that is the only way to
	/// set `buttonNumber` — `NSEvent.mouseEvent` has no parameter for it, and
	/// the number is the entire question. It carries a screen position rather
	/// than one in a window, so the cell a terminal would report it at is not
	/// meaningful; nothing here asks for one, and the side buttons never reach
	/// that code.
	func pressMouseForTesting(_ steps: String) {
		for step in steps.split(separator: ",") {
			let parts = step.split(separator: "@")
			guard let number = Int(parts.first ?? "") else { continue }
			let over = parts.count > 1 ? String(parts[1]) : "editor"
			guard let target = viewForMouseTesting(named: over) else {
				print("MOUSE \(step): there is no \(over) to press over")
				fflush(stdout)
				continue
			}
			pressForTesting(button: number, on: target)
			let place = editor.currentPlace
			print("MOUSE \(step): editor at "
				+ (place.map { "\($0.url.lastPathComponent):\($0.line)" } ?? "nowhere"))
			fflush(stdout)
		}
	}
}
