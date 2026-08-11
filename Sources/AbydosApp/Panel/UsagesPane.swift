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
/// ## Docked, with a way out to a window
///
/// This lives in the bottom panel beside search — that is where the checklist it
/// reuses already lives, and a list of usages is read beside the code rather
/// than on top of it. **Expand** moves the very same view into a window for
/// somebody who wants one big enough to read, and **Dock** in that window moves
/// it back. One view, two hosts, no third way to show the list.
final class UsagesPane: NSView {
	/// A row was activated, with whether the keyboard goes with it.
	var onOpen: ((URL, Int, ResultChecklist.Intent) -> Void)?
	/// Asked to move out of the bottom panel and into a window of its own.
	var onExpand: (() -> Void)?
	/// Asked to come back into the bottom panel.
	var onDock: (() -> Void)?

	private var heading: NSTextField!
	private var hideDoneButton: NSButton!
	private var moveButton: NSButton!
	private let list = ResultChecklist()

	/// What the heading says before the tally, so the pane can be labelled.
	private(set) var subject = "Usages"
	private var locationCount = 0
	private var fileCount = 0

	/// Whether the pane is currently in a window rather than in the panel, which
	/// is the only thing the move button's title depends on.
	var isInWindow = false {
		didSet { updateMoveButton() }
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

		moveButton = NSButton(title: "Expand", target: self, action: #selector(moveClicked))
		moveButton.bezelStyle = .rounded
		moveButton.controlSize = .small
		moveButton.font = Theme.current.uiFont(10, weight: .medium)

		let controls = NSStackView(views: [heading, hideDoneButton, moveButton])
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
			self?.onOpen?(result.url, match.line + 1, intent)
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
		updateMoveButton()
	}

	private var controlsHeight: NSLayoutConstraint!

	private func updateMoveButton() {
		moveButton.title = isInWindow ? "Dock" : "Expand"
		moveButton.toolTip = isInWindow
			? "Put these back in the panel below the editor"
			: "Show these in a window of their own"
	}

	@objc private func hideDoneChanged() {
		list.setHidesDone(hideDoneButton.state == .on)
		updateHeading()
	}

	@objc private func moveClicked() {
		if isInWindow { onDock?() } else { onExpand?() }
	}

	func applySettings() {
		controlsHeight.constant = Theme.current.scaled(30)
		heading.font = Theme.current.uiFont(11)
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
	var title: String { subject == "Usages" ? "Usages" : "Usages of \(subject)" }

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
		case "expand": onExpand?()
		case "dock": onDock?()
		case "heading":
			print("USAGES heading: \(heading.stringValue) "
				+ "window=\(isInWindow) "
				+ list.undoStateForTesting
				+ " opened=[\(list.openedForTesting.joined(separator: " "))]")
		default:
			list.stepForTesting(step)
		}
	}

	var openedForTesting: [String] { list.openedForTesting }
}

/// The window a usages list is expanded into.
///
/// A panel rather than a window so it floats over the code it is about without
/// taking the editor's key status away from the project window it belongs to;
/// `canBecomeKey` because a list nobody can type in is not one this item is
/// about.
final class UsagesWindow: NSPanel {
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
