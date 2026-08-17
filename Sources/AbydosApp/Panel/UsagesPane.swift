import AppKit
import AbydosKit

/// Everywhere a symbol is used, as a job somebody works through.
///
/// The language server's answer rather than a text search: it tells a `Close`
/// on one type from a `Close` on another, and finds the ones spelled differently
/// because they came through an alias — neither of which grep will ever do.
///
/// ## Why this is the search pane's list and not a second one
///
/// A usage list and a search result list are the same job: a list of places in
/// files that somebody opens one at a time, decides about, and moves past. So
/// the list is a `ResultChecklist`, shared with `SearchPane` — multi-selection,
/// the done state, the file headings that count what is finished, the `✓` that
/// hides it, the undo, the key handling. Only the top of the pane differs: a
/// query field and three options there, a heading here.
///
/// The rows are `FileSearchResult`s built out of `LSPLocation`s, which is the
/// conversion that makes the sharing possible at all. It costs one pass over
/// each file to read the lines, which the old panel did anyway.
///
/// ## Four homes, one view
///
/// This arrives in the bottom panel beside search — that is where the checklist
/// it reuses already lives, and a list of usages is read beside the code rather
/// than on top of it. The **Place** control moves the very same view to any of
/// `ResultPlacement`'s four homes: the panel, under the project view, beside the
/// terminals, or a window of its own. One view, four hosts, and the ticks and
/// the scroll position survive every move because the view moves rather than
/// being rebuilt.
final class UsagesPane: NSView, ResultsPane {
	/// A row was activated: the file, the row's usage, and whether the keyboard
	/// goes with it. The whole usage rather than its line since item 533 — one far
	/// along a long line is off the side of the editor's pane, which a line number
	/// cannot say.
	var onOpen: ((URL, SearchMatch, ResultChecklist.Intent) -> Void)?
	/// Asked to move to one of the four homes.
	var onPlace: ((ResultPlacement) -> Void)?

	private var heading: NSTextField!
	private var hideDoneButton: NSButton!
	private var placeControl: PlacementControl!
	private let list = ResultChecklist()

	/// What the heading says before the tally, so the pane can be labelled.
	private(set) var subject = "Usages"
	private var locationCount = 0
	private var fileCount = 0

	/// Where the pane is showing, which is the only thing the control's title
	/// depends on.
	private(set) var placement: ResultPlacement = .panel

	func setPlacement(_ placement: ResultPlacement) {
		self.placement = placement
		placeControl.setPlacement(placement)
	}

	init() {
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }

	private func build() {
		heading = NSTextField(labelWithString: "")
		heading.font = Theme.current.uiFont(11)
		heading.textColor = Theme.current.gitIgnored

		hideDoneButton = NSButton(title: "✓", target: self, action: #selector(hideDoneChanged))
		hideDoneButton.setButtonType(.pushOnPushOff)
		hideDoneButton.bezelStyle = .rounded
		hideDoneButton.controlSize = .small
		hideDoneButton.font = Theme.current.uiFont(10, weight: .medium)
		hideDoneButton.toolTip = "Hide the rows marked done (␣ marks the selection)"

		placeControl = PlacementControl()
		placeControl.onChoose = { [weak self] home in self?.onPlace?(home) }

		let controls = NSStackView(views: [heading, hideDoneButton, placeControl])
		controls.orientation = .horizontal
		controls.spacing = 6
		controls.alignment = .centerY
		controls.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
		heading.setContentHuggingPriority(.defaultLow, for: .horizontal)

		// The feature item 470 asked for: ↓ through the list shows each one. Free
		// here in a way it is not in search, because a usage list is one symbol's
		// worth of places and looking at each of them is the whole point.
		list.opensOnSelectionChange = true
		list.logPrefix = "USAGES"
		list.onOpen = { [weak self] result, match, intent in
			self?.onOpen?(result.url, match, intent)
		}
		list.onProgressChanged = { [weak self] in self?.updateHeading() }
		list.onHideDoneChanged = { [weak self] in
			guard let self else { return }
			self.hideDoneButton.state = self.list.hidesDone ? .on : .off
		}

		addSubview(controls)
		addSubview(list)
		controls.translatesAutoresizingMaskIntoConstraints = false
		list.translatesAutoresizingMaskIntoConstraints = false

		controlsHeight = controls.heightAnchor.constraint(equalToConstant: Theme.current.scaled(30))
		NSLayoutConstraint.activate([
			controls.topAnchor.constraint(equalTo: topAnchor),
			controls.leadingAnchor.constraint(equalTo: leadingAnchor),
			controls.trailingAnchor.constraint(equalTo: trailingAnchor),
			controlsHeight,

			list.topAnchor.constraint(equalTo: controls.bottomAnchor),
			list.leadingAnchor.constraint(equalTo: leadingAnchor),
			list.trailingAnchor.constraint(equalTo: trailingAnchor),
			list.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	private var controlsHeight: NSLayoutConstraint!

	@objc private func hideDoneChanged() {
		list.setHidesDone(hideDoneButton.state == .on)
		updateHeading()
	}

	func applySettings() {
		controlsHeight.constant = Theme.current.scaled(30)
		heading.font = Theme.current.uiFont(11)
		placeControl.applySettings()
		list.applySettings()
	}

	// MARK: - What is in it

	/// Puts one symbol's usages in the list.
	///
	/// `subject` is what the question is keyed on as well as what the heading
	/// says: the definition site, so the usages of two different symbols are two
	/// different questions and the ticks from one do not arrive on the other.
	/// Asking again about the *same* symbol brings the ticks back, which is what
	/// somebody does after fixing one of them.
	func show(locations: [LSPLocation], of symbol: String, at origin: String, root: URL?) {
		subject = symbol.isEmpty ? "Usages" : symbol
		locationCount = locations.count
		let results = UsageResults.group(locations, root: root)
		fileCount = results.count
		list.question = SearchChecklist.Question(query: origin, options: SearchOptions())
		list.setResults(results)
		updateHeading()
	}

	/// The pane's own name for its tab and its window title.
	var paneTitle: String { subject == "Usages" ? "Usages" : "Usages of \(subject)" }

	private func updateHeading() {
		var text = "\(locationCount) usage\(locationCount == 1 ? "" : "s") "
			+ "in \(fileCount) file\(fileCount == 1 ? "" : "s")"
		// The count of what was found, always, and the progress beside it. A
		// heading that shrank as rows were ticked would lose the one number
		// somebody needs to know how big the job was.
		let done = list.doneCount
		if done > 0 { text += " · \(done) done" }
		heading.stringValue = text
	}

	/// The keyboard, in the list, which is where it has to be for any of this to
	/// be reachable without the mouse.
	func focusList() { list.focusList() }

	var hasKeyboard: Bool { list.hasKeyboard }

	// MARK: - Driving it from a script

	func stepForTesting(_ step: String) {
		switch step {
		// The two names item 470's scripts use, kept: `expand` and `dock` are
		// still exactly two of the four homes, and a step renamed is a script
		// somewhere that stops meaning anything.
		case "expand": onPlace?(.window)
		case "dock": onPlace?(.panel)
		case "heading":
			print("USAGES heading: \(heading.stringValue) "
				+ "where=\(placement.rawValue) "
				+ list.undoStateForTesting
				+ " opened=[\(list.openedForTesting.joined(separator: " "))]")
			fflush(stdout)
		default:
			if step.hasPrefix("place:"),
			   let home = ResultPlacement(rawValue: String(step.dropFirst("place:".count))) {
				onPlace?(home)
				return
			}
			// The control itself rather than the callback under it.
			if step.hasPrefix("menu:"),
			   let home = ResultPlacement(rawValue: String(step.dropFirst("menu:".count))) {
				print("USAGES menu: \(placeControl.chooseForTesting(home))")
				fflush(stdout)
				return
			}
			// A key pressed at the *window*, so the responder chain decides who
			// gets it. `space-key` and its neighbours go straight to the table,
			// which is the right test of what the table does with a key and no
			// test at all of whether the key would have reached it — and that is
			// the whole question in the home where the list sits beside a
			// terminal, which wants every keystroke it can get.
			if step.hasPrefix("window-key:") {
				pressAtWindowForTesting(String(step.dropFirst("window-key:".count)))
				return
			}
			list.stepForTesting(step)
		}
	}

	var openedForTesting: [String] { list.openedForTesting }
}

/// The window a results list is expanded into.
///
/// A panel rather than a window so it floats over the code it is about without
/// taking the editor's key status away from the project window it belongs to;
/// `canBecomeKey` because a list nobody can type in is not one this item is
/// about.
final class ResultsWindow: NSPanel {
	var onClose: (() -> Void)?

	override var canBecomeKey: Bool { true }

	override func close() {
		onClose?()
		super.close()
	}

	override func cancelOperation(_ sender: Any?) {
		onClose?()
	}
}
