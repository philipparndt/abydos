import AppKit
import AbydosKit

/// What the pane shows a project that has no backlog yet, and the palette both
/// arrangements draw with.
// MARK: - No backlog yet

/// What the pane shows for a project that has no `.abydos/backlog`.
///
/// It used to show the board regardless: five empty columns, each with its
/// one-line description of what belongs in it, and nothing anywhere saying that
/// the folder those columns are over does not exist. That is the worst of both
/// — it looks like a backlog with nothing in it, which is a state somebody
/// would sensibly try to fix by dragging something into it.
///
/// So this says the folder is missing, says what making one would write, and
/// names the command that does the same thing, because the command line is not
/// a fallback here: it is the other half of the same tool, and somebody who
/// learns the name once can run it in a project this app has never opened.
/// What the pane shows a project that keeps no record of work yet.
///
/// **Both kinds, because the pane reads both.** It offered a backlog and only a
/// backlog for as long as that was the only record there was; the source switch
/// made `openspec/` the other half of this pane and left the empty state saying
/// the app knew about one of them. A project with neither was then told its
/// options, and the one it was not told about is the one this repository has
/// been keeping its own changes in.
///
/// **Drawn as the editor draws a file it cannot show.** `FileNoticeView` is the
/// same sentence about a different subject — there is nothing here, and here is
/// what to do about it — so it is the same shape: an icon, a name, one line of
/// reason, a row of `NoticeButton`s. That button is shared rather than copied,
/// which is the half of the resemblance that cannot drift.
final class BacklogAbsentView: NSView {
	var onMake: (() -> Void)?
	var onSetUpOpenSpec: (() -> Void)?

	private let projectName: String
	private var iconView: NSImageView!
	private var titleLabel: NSTextField!
	private var bodyLabel: NSTextField!
	private var commandLabel: NSTextField!
	private var hintLabel: NSTextField!
	private var makeButton: NoticeButton!
	private var openSpecButton: NoticeButton!

	/// Whether the `openspec` CLI is on this machine.
	///
	/// Asked once, when the view is built, and not on a drawing path:
	/// `Executables.locate` runs a login shell. This view is made when a pane
	/// is, and a project that has neither record is a project nobody is
	/// scrolling — but the shell is expensive enough that it should be asked
	/// deliberately rather than in a layout pass.
	private let hasOpenSpecTool: Bool

	/// Makes this view answer as a machine with no `openspec` on it, for
	/// `--backlog-offer missing`.
	///
	/// A seam rather than a driven install: `Executables.locate` asks the login
	/// shell, and on this machine the tool is under an fnm directory that the
	/// shell will always find — so the state where it is absent cannot be
	/// reached by a launch flag, only pretended. The same shape as
	/// `BacklogCardViewDrawReport`, and off unless a driver asked.
	static var pretendsTheToolIsMissing = false

	init(projectName: String) {
		self.projectName = projectName
		self.hasOpenSpecTool = !Self.pretendsTheToolIsMissing && OpenSpec.commandLine() != nil
		super.init(frame: .zero)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func build() {
		iconView = NSImageView()
		iconView.image = Theme.symbol("checklist", size: 34, color: Theme.current.gitIgnored)
		iconView.imageScaling = .scaleProportionallyUpOrDown
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.widthAnchor.constraint(equalToConstant: 40).isActive = true
		iconView.heightAnchor.constraint(equalToConstant: 40).isActive = true

		// The project's name where the notice has a file's, because that is what
		// this is about: not a missing folder, but this project having nowhere
		// to keep what is left to do.
		titleLabel = NSTextField(labelWithString: projectName)
		titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
		titleLabel.textColor = Theme.current.sidebarHeaderText
		titleLabel.alignment = .center

		bodyLabel = NSTextField(labelWithString: "No backlog and no OpenSpec directory yet.")
		bodyLabel.font = .systemFont(ofSize: 12)
		bodyLabel.textColor = Theme.current.gitIgnored
		bodyLabel.alignment = .center

		makeButton = NoticeButton(title: "Make a Backlog\u{2026}", symbol: "checklist")
		makeButton.onClick = { [weak self] in self?.onMake?() }

		openSpecButton = NoticeButton(title: "Set Up OpenSpec\u{2026}", symbol: "square.and.pencil")
		openSpecButton.onClick = { [weak self] in self?.onSetUpOpenSpec?() }
		openSpecButton.isEnabled = hasOpenSpecTool

		let buttons = NSStackView(views: [makeButton, openSpecButton])
		buttons.orientation = .horizontal
		buttons.spacing = 10

		// What each button is, so that somebody who would rather type it can.
		// The OpenSpec half is dropped where the tool is not there — a command
		// nothing on this machine can run is not an alternative.
		commandLabel = NSTextField(labelWithString: commandLine)
		commandLabel.font = Theme.current.uiFont(11)
		commandLabel.textColor = Theme.current.gitIgnored
		commandLabel.alignment = .center
		commandLabel.isSelectable = true

		hintLabel = NSTextField(labelWithString: "openspec is not installed.  \(OpenSpec.installHint)")
		hintLabel.font = Theme.current.uiFont(11)
		hintLabel.textColor = Theme.current.gitIgnored
		hintLabel.alignment = .center
		hintLabel.isSelectable = true
		hintLabel.isHidden = hasOpenSpecTool

		let stack = NSStackView(views: [iconView, titleLabel, bodyLabel, buttons, commandLabel, hintLabel])
		stack.orientation = .vertical
		stack.alignment = .centerX
		stack.spacing = 10
		stack.setCustomSpacing(16, after: bodyLabel)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
			stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
		])
	}

	private var commandLine: String {
		let backlog = "abydos-backlog init"
		guard hasOpenSpecTool else { return "in a terminal:  \(backlog)" }
		return "in a terminal:  \(backlog)   \u{00B7}   \(OpenSpec.initCommand())"
	}

	/// What this view is offering, for a driver to print.
	///
	/// The four states this has — neither record, no CLI, and either one made —
	/// are a view in the app target, which the suite cannot reach. A line of
	/// text can be read; a photograph has to be looked at by somebody.
	var offerReportForTesting: String {
		[
			"title: \(titleLabel.stringValue)",
			"detail: \(bodyLabel.stringValue)",
			"button: \(makeButton.caption) enabled=\(makeButton.isEnabled)",
			"button: \(openSpecButton.caption) enabled=\(openSpecButton.isEnabled)",
			"commands: \(commandLabel.stringValue)",
			"hint: \(hintLabel.isHidden ? "none" : hintLabel.stringValue)",
		].joined(separator: "\n")
	}

	func applySettings() {
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		iconView.image = Theme.symbol("checklist", size: 34, color: Theme.current.gitIgnored)
		titleLabel.textColor = Theme.current.sidebarHeaderText
		bodyLabel.textColor = Theme.current.gitIgnored
		commandLabel.font = Theme.current.uiFont(11)
		commandLabel.textColor = Theme.current.gitIgnored
		hintLabel.font = Theme.current.uiFont(11)
		hintLabel.textColor = Theme.current.gitIgnored
		// The buttons draw themselves from the theme every time, so a scheme
		// change reaches them through this.
		makeButton.needsDisplay = true
		openSpecButton.needsDisplay = true
	}
}

// MARK: - Shared drawing

/// What a state looks like, and what an item is wearing.
enum BacklogPalette {
	/// Borrowed from the version-control colours rather than invented.
	///
	/// Not laziness: those five are already the palette of "something is going
	/// on with this file" everywhere else in the window, and a board with its
	/// own green means two greens in one app that mean different things.
	static func colour(for state: BacklogState) -> NSColor {
		switch state {
		case .open: return Theme.current.gitUnversioned
		case .ready: return Theme.current.gitAdded
		case .inProgress: return Theme.current.gitModified
		case .waiting: return Theme.current.gitConflict
		case .completed, .history: return Theme.current.gitIgnored
		}
	}

	/// The same five colours for OpenSpec's states, matched by what they mean
	/// rather than by position: `ready` is the one an agent can pick up on
	/// either board, so it is the same green on both, and a change being written
	/// is the same grey as an item nobody has agreed yet.
	static func colour(for state: OpenSpecState) -> NSColor {
		switch state {
		case .writing: return Theme.current.gitUnversioned
		case .ready: return Theme.current.gitAdded
		case .inProgress: return Theme.current.gitModified
		case .complete, .archived: return Theme.current.gitIgnored
		}
	}

	static func colour(for column: BoardColumn) -> NSColor {
		switch column {
		case let .backlog(state):  return colour(for: state)
		case let .openSpec(state): return colour(for: state)
		}
	}

	/// The line under a card: how far along it is, how much longer it has, what
	/// it carries, and where it is being worked on.
	///
	/// The order is the order it can be lost in. This line truncates at the tail
	/// on a narrow column, so what is written first is what survives — and the
	/// fraction and the estimate are the two things that change while somebody is
	/// watching the board, while the branch name is both the longest and the one
	/// that has not changed since the item was picked up.
	static func marks(for card: BacklogCard, now: Date = Date()) -> String {
		var marks: [String] = []

		if let progress = card.progress {
			// The fraction says which copy it came from, because a fraction read
			// off a branch three commits ahead of the project is not the same
			// fact as one read off the project, and a card that shows the one as
			// the other is how somebody comes to trust a number they should not.
			//
			// Four words rather than the branch name, though the branch is the
			// more precise answer and is already on the line: this end of the
			// line is the end that survives a narrow column, and a branch name
			// here would push everything after it off every in-progress card on
			// the board. Which worktree is at the tail, where it can be lost;
			// that there is one is at the head, where it cannot.
			switch card.source {
			case .worktree: marks.append("\(progress.summary) in the worktree")
			case .project:
				// Said only where there is something to mistake it for. An item
				// nobody has picked up has one copy, and "in the project" on
				// every card of a board is a distinction without a difference —
				// but on an item with a checkout recorded and gone, it is the
				// difference between an old number and a current one.
				marks.append(card.run == nil
					? progress.summary
					: "\(progress.summary) in the project")
			}
		}
		if let estimate = card.estimate { marks.append(estimate.summary(now: now)) }
		if card.images > 0 { marks.append("\(card.images) image\(card.images == 1 ? "" : "s")") }
		if card.hasSpecDelta { marks.append("spec") }
		if let run = card.run, run.isPresent { marks.append(run.branch) }
		return marks.joined(separator: "  \u{00B7}  ")
	}
}


/// Turns on the per-card drawing report, which lives on a private type.
enum BacklogCardViewDrawReport {
	static func enable() { BacklogCardView.reportsDrawing = true }
}
