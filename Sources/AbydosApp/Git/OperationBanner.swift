import AppKit
import AbydosKit

/// The strip above the refs tree while git is in the middle of something.
///
/// **It used to be about conflicted files, and that was half the state.** It
/// appeared when `git status` reported unmerged paths and went away when the
/// last one was resolved — which is the moment a rebase most needs saying
/// something, because resolving the files is not finishing the rebase. There
/// was nothing anywhere in this app that ran `git rebase --continue`, so the
/// flow ended in the middle: resolve, stage, and then go and find a terminal.
///
/// So it is about the operation now. It shows for as long as one is in
/// progress, says which stage it is at, and carries the three verbs that end
/// it. Conflicted files are one of the things it can say, not the reason it
/// is there.
final class OperationBanner: NSView {
	var onOpenFiles: (() -> Void)?
	var onOpenInFork: (() -> Void)?
	var onCopyPrompt: (() -> Void)?
	/// `--continue`, `--skip` and `--abort`, in that order of appearance.
	var onCarryOn: (() -> Void)?
	var onSkip: (() -> Void)?
	var onAbort: (() -> Void)?

	private let label = NSTextField(labelWithString: "")
	private let position = NSTextField(labelWithString: "")
	private let state = NSTextField(labelWithString: "")
	private let bar = NSProgressIndicator()
	private var buttons: NSStackView!
	private var helpers: NSStackView!
	private var stack: NSStackView!

	private let carryOnButton: NSButton
	private let skipButton: NSButton
	private let abortButton: NSButton
	private let openFilesButton: NSButton
	private let forkButton: NSButton?
	private let promptButton: NSButton

	/// What the label last said, for a driven run to read.
	private(set) var said = ""

	override init(frame frameRect: NSRect) {
		func button(_ title: String) -> NSButton {
			let made = NSButton(title: title, target: nil, action: nil)
			made.bezelStyle = .rounded
			made.controlSize = .small
			made.font = Theme.current.uiFont(10.5)
			return made
		}
		carryOnButton = button("Continue")
		skipButton = button("Skip")
		abortButton = button("Abort")
		// **One word each on the second row.** This strip lives in a sidebar
		// somebody has made narrow, and `Open Files`, `Open in Fork` and
		// `Copy Prompt` together are wider than that sidebar — which is how
		// the first row came to be squeezed to slivers. The verbs are the
		// sentence above them; the tooltips carry what was cut.
		openFilesButton = button("Files")
		openFilesButton.toolTip = "Open the conflicted files in the editor"
		// **Fork's own icon, not the word.** `Fork` on a button next to a
		// branch list reads as a verb — make a fork of this repository — which
		// is not what it does and not a thing this app can do at all. The
		// application's icon says which Fork is meant, and it is narrower than
		// the word it replaces. Absent rather than present and failing: Fork
		// is not on every machine.
		if let application = ForkIntegration.applicationURL() {
			let made = button("")
			made.image = NSWorkspace.shared.icon(forFile: application.path)
			made.image?.size = NSSize(
				width: Theme.current.scaled(14), height: Theme.current.scaled(14)
			)
			made.imagePosition = .imageOnly
			made.imageScaling = .scaleProportionallyDown
			made.toolTip = "Open this repository in Fork"
			made.setAccessibilityLabel("Open in Fork")
			forkButton = made
		} else {
			forkButton = nil
		}
		promptButton = button("Prompt")
		promptButton.toolTip = "Copy a prompt describing the conflict, to paste into a session"

		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.gitConflict.withAlphaComponent(0.16).cgColor
		isHidden = true

		label.font = Theme.current.uiFont(11.5, weight: .semibold)
		label.textColor = Theme.current.gitConflict
		label.lineBreakMode = .byTruncatingTail

		// **Room, on purpose.** This strip is the one thing in the pane worth
		// looking at while it is up: the list under it is a list of branches
		// nothing can be switched to until the operation ends. So it says
		// where the rebase is rather than only that there is one — which
		// commit of how many, in its own words, and what is left to do about
		// it — and it takes three lines to do it.
		position.font = Theme.current.uiFont(10.5)
		position.textColor = Theme.current.sidebarText
		position.lineBreakMode = .byTruncatingTail
		state.font = Theme.current.uiFont(10.5)
		state.textColor = Theme.current.sidebarHeaderText
		state.lineBreakMode = .byTruncatingTail

		bar.style = .bar
		bar.isIndeterminate = false
		bar.controlSize = .small
		bar.minValue = 0

		// **Continue first and Abort last.** The order is the order somebody
		// wants them in, and it puts the one that throws work away furthest
		// from the one they came here to press.
		for (made, action) in [
			(carryOnButton, #selector(carryOn)),
			(skipButton, #selector(skip)),
			(openFilesButton, #selector(openFiles)),
			(forkButton, #selector(openInFork)),
			(promptButton, #selector(copyPrompt)),
			(abortButton, #selector(abort)),
		] as [(NSButton?, Selector)] {
			made?.target = self
			made?.action = action
		}
		// The default button: ⏎ on this pane finishes what git started.
		carryOnButton.keyEquivalent = "\r"

		// **Two rows, and the verbs on their own.** Six buttons in one row do
		// not fit a sidebar: the stack squeezed the first two to nothing, so
		// `Continue` and `Skip` — the entire reason the strip is here — were
		// two grey slivers left of `Open in Fork`. The flow gets a row to
		// itself, and the things that only help with conflicted files get the
		// row under it.
		let verbs = NSStackView(views: [carryOnButton, skipButton, abortButton])
		helpers = NSStackView(views: [openFilesButton, forkButton, promptButton].compactMap { $0 })
		for row in [verbs, helpers] as [NSStackView] {
			row.orientation = .horizontal
			row.spacing = Theme.current.scaled(6)
			row.alignment = .centerY
		}
		for made in [carryOnButton, skipButton, abortButton, openFilesButton, forkButton, promptButton] {
			// Never squeezed to a stub: a button whose title has been clipped
			// away is worse than one that has pushed its neighbour off the end.
			made?.setContentCompressionResistancePriority(.required, for: .horizontal)
		}

		buttons = NSStackView(views: [verbs, helpers])
		buttons.orientation = .vertical
		buttons.alignment = .leading
		buttons.spacing = Theme.current.scaled(4)

		// **One stack, because hidden views must take no room.** The rows were
		// pinned to each other, and a plain `isHidden` leaves the constraints
		// standing: a merge — which has no `1 of n` to draw, so no bar and no
		// position line — left a hole where they would have been and pushed the
		// buttons out through the bottom of the strip and over the repository
		// row. A stack view excludes what is hidden, which is the behaviour
		// this needed all along.
		let rows = NSStackView(views: [label, bar, position, state, buttons])
		rows.orientation = .vertical
		rows.alignment = .leading
		rows.spacing = Theme.current.scaled(3)
		rows.setHuggingPriority(.required, for: .vertical)
		stack = rows

		addSubview(rows)
		rows.translatesAutoresizingMaskIntoConstraints = false
		let inset = Theme.current.scaled(8)
		NSLayoutConstraint.activate([
			rows.topAnchor.constraint(equalTo: topAnchor, constant: inset / 2),
			rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
			rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
			// The bar spans the strip; everything else sizes to its text.
			bar.widthAnchor.constraint(equalTo: rows.widthAnchor),
		])
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	/// - Parameter operation: what git is in the middle of, which decides which
	///   verbs are offered at all — a merge has no `--skip`.
	/// - Parameter conflicted: how many files still have markers in them.
	/// - Parameter staged: whether anything is staged, which is the difference
	///   between "resolved, ready to go on" and "nothing here to commit".
	///
	/// **The label says the stage, not the state.** `Rebasing — 2 files
	/// conflicted` and `Rebasing — resolved, ready to continue` are the two
	/// halves of the thing this pane got wrong: the second one used to be no
	/// banner at all, which read as the rebase being over.
	func show(
		operation: GitConflicts.Operation,
		conflicted: Int,
		staged: Bool,
		what: String?,
		progress: GitConflicts.Progress?
	) {
		// The headline is the operation and what it is between: `Rebasing side
		// onto 1aec9f8d`. `describe` says the same thing for a merge, which
		// names the branch coming in, so it wins when it has an answer.
		if let progress, let branch = progress.branch {
			label.stringValue = progress.onto.map {
				"\(operation.titled) \(branch) onto \($0)"
			} ?? "\(operation.titled) \(branch)"
		} else {
			label.stringValue = what ?? operation.titled
		}

		if let progress, progress.total > 0 {
			bar.isHidden = false
			bar.maxValue = Double(progress.total)
			// **Half a step for the one in hand.** The commit being applied is
			// neither done nor untouched, and counting only the finished ones
			// draws an empty bar at `commit 1 of 3` — which reads as a rebase
			// that has not started, at the moment it is waiting on you.
			bar.doubleValue = Double(progress.position) - 0.5
			position.isHidden = false
			position.stringValue = "commit \(progress.position) of \(progress.total)"
				+ (progress.subject.map { " · \($0)" } ?? "")
		} else {
			bar.isHidden = true
			position.isHidden = true
			position.stringValue = ""
		}

		let title = label.stringValue
		// Truncation is the price of a narrow sidebar; losing the words is
		// not. Whatever the strip cannot show, it says under the pointer.
		label.toolTip = title
		position.toolTip = position.stringValue
		if conflicted > 0 {
			said = "\(title) — \(conflicted) file\(conflicted == 1 ? "" : "s") conflicted"
			state.stringValue = "\(conflicted) file\(conflicted == 1 ? "" : "s") conflicted"
		} else if staged {
			said = "\(title) — resolved, ready to continue"
			state.stringValue = "Resolved — ready to continue"
		} else {
			// Nothing conflicted and nothing staged: the commit in hand has
			// become empty, which is what `--skip` is for. Said plainly,
			// because `git` will otherwise say it as an error after the press.
			said = operation.canSkip
				? "\(title) — nothing left to apply, skip this commit"
				: "\(title) — nothing staged"
			state.stringValue = operation.canSkip
				? "Nothing left to apply — Skip it"
				: "Nothing staged"
		}

		// Only the verbs that mean something here. A merge cannot skip, and
		// the conflict helpers are about conflicted files.
		skipButton.isHidden = !operation.canSkip
		// The whole row, so its space goes back when there is nothing
		// conflicted to open.
		helpers.isHidden = conflicted == 0
		carryOnButton.isEnabled = conflicted == 0
		carryOnButton.toolTip = conflicted == 0
			? nil
			: "Resolve the conflicted files first — git will not carry on over markers."
	}

	/// How tall the strip wants to be — asked of what is in it rather than
	/// counted in points.
	///
	/// **Measured, because the guess was wrong.** It was `66 or 100, plus 24
	/// for the helpers`: three numbers standing in for what the strip is
	/// actually showing, which is how a merge — no bar, no position line, two
	/// rows of buttons — came out short and drew its second row over the
	/// repository row beneath it. Nothing needs to know the line count now.
	var wantedHeight: CGFloat {
		// The stack knows: it has excluded whatever is hidden and laid out the
		// rest at the width it has been given.
		layoutSubtreeIfNeeded()
		return ceil(stack.fittingSize.height) + Theme.current.scaled(12)
	}

	/// What a driven run reads off the banner: the sentence, and which verbs
	/// are actually pressable.
	var reportForTesting: String {
		let offered = [
			("continue", carryOnButton), ("skip", skipButton), ("open", openFilesButton),
			("fork", forkButton), ("prompt", promptButton), ("abort", abortButton),
		].compactMap { name, made -> String? in
			guard let made, !made.isHidden, !(made.superview?.isHidden ?? false) else { return nil }
			return made.isEnabled ? name : "\(name)(off)"
		}
		let counted = bar.isHidden
			? ""
			: " {\(bar.doubleValue)/\(Int(bar.maxValue)) \(position.stringValue)}"
		// The two heights, because the strip getting them wrong is what a
		// screenshot of the sidebar cannot show: a banner shorter than its
		// content draws its buttons over the row below, and a shot of a pane
		// with a translucent tint over nothing behind it looks wrong either
		// way.
		let sizes = "fits=\(Int(stack.fittingSize.height)) tall=\(Int(frame.height))"
		return "BANNER \(isHidden ? "hidden" : "shown"): \(said)\(counted)"
			+ " [\(offered.joined(separator: " "))] \(sizes)"
	}

	func pressForTesting(_ name: String) {
		switch name {
		case "continue": if carryOnButton.isEnabled { carryOn() }
		case "skip":     skip()
		case "abort":    abort()
		default:         print("BANNER: no button called \(name)")
		}
	}

	@objc private func openFiles() { onOpenFiles?() }
	@objc private func openInFork() { onOpenInFork?() }
	@objc private func copyPrompt() { onCopyPrompt?() }
	@objc private func carryOn() { onCarryOn?() }
	@objc private func skip() { onSkip?() }
	@objc private func abort() { onAbort?() }
}
