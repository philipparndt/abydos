import AppKit
import AbydosKit

/// The repository, as a row.
///
/// **Not a header.** The thing this replaces was a button in a box above the
/// tree, and it was there for a reason its own comment gave: *a verb here hangs
/// off the row that draws its object, and nothing drew the repository*. This
/// draws the repository, so the verb comes home — fetch when level, pull when
/// behind, push when ahead, on the row that says which of those it is.
///
/// It does not scroll, and that is the one thing a row does not get for free.
/// Everything else in this tree is a thing you go and look at; how far you are
/// from the remote is a thing you need to have noticed, and a repository with
/// forty branches would put it off screen at once.
///
/// It says its distance in words. The button had room for `↓3 ↑1` and a tooltip;
/// a row has room for `3 behind · 1 ahead`, and abbreviates when it does not.
final class RepositoryRowView: ActionableRowView {
	private let name: String
	private var branch: String?
	private var state: GitPush.State?

	/// Focus is its own, because it is outside the outline: the tree cannot
	/// select a row it does not contain.
	private var hasKeyboard = false

	/// The spelling of the distance that was last actually drawn.
	///
	/// Reported rather than `distance`, because which one fits is the thing
	/// worth checking and a report of what *could* have been drawn cannot show
	/// it — the first version of this said the sentence while the row showed
	/// the arrows, and looked correct.
	private var drawnDistance = ""

	/// Whether the project name was drawn, for the same reason.
	///
	/// It is the first thing dropped when the pane is narrow, so a report that
	/// always names it says the row is fuller than it is.
	private var drewName = true

	/// `↓` out of this row and into the tree, so the two read as one list.
	var onDownArrow: (() -> Void)?

	init(name: String) {
		self.name = name
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	func show(branch: String?, state: GitPush.State?) {
		self.branch = branch
		self.state = state
		updateAction()
		needsDisplay = true
	}

	/// What the distance is, said as a sentence.
	private var distance: String {
		guard let state, state.hasRemote else { return "no remote" }
		guard state.hasCommits else { return "nothing pushed yet" }
		// Said before the counts are looked at, because a gone upstream has
		// none: it would otherwise read `level`, about a ref that is not there.
		if state.upstreamIsGone { return "upstream gone" }
		if state.upstream == nil { return "not published" }
		var parts: [String] = []
		if state.behind > 0 { parts.append("\(state.behind) behind") }
		if state.ahead > 0 { parts.append("\(state.ahead) ahead") }
		if parts.isEmpty { return "level" }
		return parts.joined(separator: " · ")
	}

	/// The short spelling, for a pane too narrow for the sentence.
	private var shortDistance: String {
		guard let state, state.hasRemote, state.hasCommits else { return "" }
		if state.upstreamIsGone { return "gone" }
		if state.upstream == nil { return "" }
		var parts: [String] = []
		if state.behind > 0 { parts.append("↓\(state.behind)") }
		if state.ahead > 0 { parts.append("↑\(state.ahead)") }
		return parts.joined(separator: " ")
	}

	private func updateAction() {
		guard let state, state.hasRemote else {
			// Nothing to press: a repository with no remote has nowhere to
			// fetch from, and a button that cannot act is one to explain away.
			action = nil
			return
		}
		// **Behind wins over ahead**, which is the rule the button already kept:
		// what somebody else has done comes first, because pushing on top of it
		// is the mess this is meant to avoid.
		let title: String
		// A gone upstream is answered by fetching: a prune clears the tracking,
		// and pushing to a ref somebody deleted on purpose is not this row's
		// call to make.
		if state.upstreamIsGone { title = "Fetch" }
		else if state.behind > 0 { title = "Pull" }
		else if state.canPush { title = "Push" }
		else { title = "Fetch" }
		action = RowAction(
			title: title,
			help: state.behind > 0 ? "Pull \(state.behind)" : state.explanation,
			isAlwaysShown: true
		)
	}

	override var acceptsFirstResponder: Bool { true }

	override func becomeFirstResponder() -> Bool {
		hasKeyboard = true
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		hasKeyboard = false
		needsDisplay = true
		announceKeyboardFocusChange()
		return super.resignFirstResponder()
	}

	override var isRowSelected: Bool { hasKeyboard }

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		super.mouseDown(with: event)
	}

	override func keyDown(with event: NSEvent) {
		// ⌘⏎ is the row's verb, the same key it is on every other row here.
		if event.keyCode == 36 || event.keyCode == 76 {
			if event.modifierFlags.contains(.command) { fireAction() }
			return
		}
		// ↓ leaves for the tree, so the pinned row and the list read as one.
		if event.keyCode == 125 {
			onDownArrow?()
			return
		}
		super.keyDown(with: event)
	}

	override func draw(_ dirtyRect: NSRect) {
		if hasKeyboard {
			Theme.current.sidebarHeaderText.withAlphaComponent(0.10).setFill()
			bounds.fill()
		}

		RowMetrics.glyph("shippingbox", colour: Theme.current.gitIgnored, in: bounds)

		let taken = actionWidth
		let limit = bounds.maxX - RowMetrics.trailingInset - taken
		let gap = Theme.current.scaled(8)

		func width(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular) -> CGFloat {
			ceil(NSAttributedString(string: text, attributes: [
				.font: Theme.current.uiFont(size, weight: weight),
			]).size().width)
		}

		// **The project name is the first thing to go, not the distance.**
		// The titlebar already says which project this is; nothing else says
		// how far the branch is from its upstream, which is what this row is
		// pinned for. At 260 points — the width this pane actually opens at —
		// the name is what stands between the sentence and the arrows.
		let sentence = distance
		let short = shortDistance
		let branchWidth = branch.map { width($0, 11) + gap } ?? 0
		let sentenceFits = RowMetrics.textInset + width(name, 12, .semibold) + gap
			+ branchWidth + width(sentence, 10.5) <= limit
		let fitsWithoutName = RowMetrics.textInset + branchWidth
			+ width(sentence, 10.5) <= limit
		let showsName = sentenceFits || short.isEmpty || !fitsWithoutName
		let said = sentenceFits || fitsWithoutName || short.isEmpty ? sentence : short

		var after = RowMetrics.textInset
		if showsName {
			after = RowMetrics.draw(
				name,
				font: Theme.current.uiFont(12, weight: .semibold),
				colour: Theme.current.sidebarHeaderText,
				at: after, in: bounds, limit: limit
			) + gap
		}
		if let branch {
			after = RowMetrics.draw(
				branch,
				font: Theme.current.uiFont(11, weight: showsName ? .regular : .semibold),
				colour: Theme.current.gitModified,
				at: after, in: bounds, limit: limit
			) + gap
		}
		drawnDistance = said
		drewName = showsName
		RowMetrics.draw(
			said,
			font: Theme.current.uiFont(10.5),
			colour: Theme.current.gitIgnored,
			at: after, in: bounds, limit: limit
		)

		drawAction()
	}

	/// What a driven run reads off the row.
	var reportForTesting: String {
		"\(drewName ? name : "(name dropped)")"
			+ " · \(branch ?? "no branch") · \(drawnDistance.isEmpty ? distance : drawnDistance)"
			+ " · \(action?.title ?? "nothing to press")"
	}
}
