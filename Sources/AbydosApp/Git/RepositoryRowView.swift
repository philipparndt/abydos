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
	private var branch: String?
	private var state: GitPush.State?

	/// Where the head is when it is not on a branch, and what git has stopped
	/// in the middle of — `detached at 83ae05a`, `rebasing`, or both.
	///
	/// **Nothing in this pane said either of them.** `for-each-ref` marks no
	/// branch current while the head is detached, so the tree simply lost its
	/// checkmark and the row lost its name, and a repository stopped mid-rebase
	/// looked like one sitting quietly on no branch in particular. The banner
	/// under this row only appears for conflicted *paths*, which a rebase
	/// stopped on `edit` or a failed `exec` does not have.
	private var headNotice: String?

	/// How many submodules this repository holds, when it holds any.
	///
	/// **Said here because it changes what everything below means.** `level` on
	/// a superproject is a true sentence about the superproject and says nothing
	/// about the forty services under it, and a reader who does not know this is
	/// a superproject has no reason to look further.
	///
	/// **Only said, and not given a verb.** This row's action is the remote
	/// traffic — fetch when level, pull when behind, push when ahead — and that
	/// is the whole reason this specification draws the repository as a row at
	/// all: a verb hangs off the row that draws its object. A second verb here
	/// would dilute the one thing the row was pinned for. The way to the
	/// overview is the Submodules section's own header, which is the row that
	/// draws *that* object, and ⇧⌘M.
	private var submoduleCount = 0

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

	/// `↓` out of this row and into the tree, so the two read as one list.
	var onDownArrow: (() -> Void)?

	/// Every verb the remote allows, for a right-click.
	///
	/// **Because the row draws one verb and there are four.** Which one it
	/// draws is chosen from a state that is itself as old as the last fetch:
	/// `Push` on a row that is `1 ahead` is a claim about a tracking ref
	/// somebody last refreshed on Tuesday. The pane had no way to fetch while
	/// ahead at all — the button says `Push`, and `Fetch` is only ever the
	/// primary when there is nothing to push or pull — so the answer to "am I
	/// actually still ahead" was a terminal.
	///
	/// Built on demand: what is enabled depends on the state, and how long ago
	/// the last fetch was is read when the menu is opened rather than kept.
	var buildMenu: (() -> NSMenu?)?

	override func menu(for event: NSEvent) -> NSMenu? { buildMenu?() }

	init() { super.init(frame: .zero) }

	required init?(coder: NSCoder) { fatalError("not used") }

	func show(
		branch: String?, state: GitPush.State?, notice: String? = nil, submodules: Int = 0
	) {
		self.branch = branch
		self.state = state
		self.headNotice = notice
		self.submoduleCount = submodules
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
		// The names this row no longer draws are still worth having on hover:
		// what is drawn is a distance with nothing beside it saying whose.
		action = RowAction(
			title: title,
			help: state.behind > 0
				? "Pull \(state.behind) into \(branch ?? state.branch)"
				: state.explanation,
			isAlwaysShown: true
		)

		// **Not the same word twice.** The second verb exists so that `Fetch`
		// is on the row whatever the first one says — and when the first one
		// *is* `Fetch`, which is what a branch level with its upstream gets,
		// the two were drawn side by side saying the same thing. Reported as
		// "two fetch buttons but no pull button": the row was on a level branch
		// and the `↓2` in the picture belonged to another branch's own row.
		//
		// Dropped here rather than by whoever sets it, because this is where
		// the first verb is decided; the pane sets the second on every refresh,
		// so it comes back the moment the first verb is Pull or Push again.
		if title == "Fetch", secondaryAction?.title == "Fetch" { secondaryAction = nil }
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

		// **Only what the titlebar does not say.** This row used to name the
		// project and the branch, both of which are written a few points above
		// it in the titlebar — so on a repository with nothing to report it was
		// two words already on screen and a glyph. What is left is the thing
		// nothing else says and the thing this row was pinned for: how far the
		// branch is from its upstream, and the verb that follows from it.
		//
		// The width fallback went with the name. There is nothing left to give
		// way — `2 behind · 1 ahead` fits at 250 points on its own, which is
		// what dropping the name was buying room for in the first place.
		// The head notice goes first and in the conflict colour, because it is
		// the one thing here that is not routine: how far a branch is from its
		// upstream is worth knowing, and being on no branch at all is worth
		// noticing before anything else on the row is read.
		var x = RowMetrics.textInset
		let limit = bounds.maxX - RowMetrics.trailingInset - actionWidth
		let font = Theme.current.uiFont(11, weight: .medium)
		if let headNotice {
			// `draw` answers where it ended, which is where the next one starts.
			x = RowMetrics.draw(
				headNotice + " · ",
				font: font,
				colour: Theme.current.gitConflict,
				at: x,
				in: bounds,
				limit: limit
			)
		}
		drawnDistance = distance
		x = RowMetrics.draw(
			drawnDistance,
			font: font,
			colour: Theme.current.sidebarHeaderText,
			at: x,
			in: bounds,
			limit: limit
		)
		if submoduleCount > 0 {
			RowMetrics.draw(
				" · \(submoduleCount) submodules",
				font: font,
				colour: Theme.current.gitIgnored,
				at: x,
				in: bounds,
				limit: limit
			)
		}

		drawAction()
	}

	/// What a driven run reads off the row.
	var reportForTesting: String {
		(headNotice.map { $0 + " · " } ?? "")
			+ "\(drawnDistance.isEmpty ? distance : drawnDistance)"
			+ (submoduleCount > 0 ? " · \(submoduleCount) submodules" : "")
			+ " · \(action?.title ?? "nothing to press")"
			// The second verb by name, because the claim this row is now under
			// is that `Fetch` is there *whatever* the first verb says — and a
			// screenshot of a row is the least reliable way to check a control
			// that is dropped when the row is narrow.
			+ " · second \(secondaryAction?.title ?? secondaryAction?.symbol ?? "none")"
	}
}
