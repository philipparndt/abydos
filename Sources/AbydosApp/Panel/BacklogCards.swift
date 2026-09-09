import AppKit
import AbydosKit

/// What a card is, in both of the two things this pane reads: a `backlog-spec`
/// item and an OpenSpec change. Two shapes, one list, and the board rows are
/// what they have in common.
import AppKit
import AbydosKit

/// One item, with everything a row or a card says about it already worked out.
///
/// Exists so that drawing costs nothing. An item's title, its checklist, its
/// screenshots and its spec delta are four reads of the file system, and a
/// board redraws on every scroll — so they are done once, on the thread that
/// re-reads the folder, and what reaches `draw(_:)` is five fields.
struct BacklogCard {
	/// Which copy of the item the checklist, the pictures and the delta were
	/// read from.
	///
	/// **State from the project, progress from the worktree**, and the two are
	/// not the same question. Where an item stands is the project's answer —
	/// `in-progress/` until the branch lands, because work finished on a branch
	/// nobody has merged is not done here. How far along it is is the branch's
	/// answer, because the ticking happens there: measured while 0454 was being
	/// worked, the project's copy said 0 of 6 and the branch's said 3 of 6, and
	/// the card showed the first — the fraction the item had at the moment it was
	/// picked up, held there until the merge, which is when nobody needs to watch
	/// it any more.
	enum Source: Equatable {
		/// The project's own copy, which for an item nobody has picked up is the
		/// only copy there is.
		case project
		/// The checkout the work is happening in. Which one is `run`, which the
		/// card carries anyway in order to draw the branch and to offer the
		/// three things its menu does with it.
		case worktree
	}

	let item: BacklogItem
	let progress: BacklogItem.Progress?
	let estimate: BacklogItem.Estimate?
	let images: Int
	let hasSpecDelta: Bool
	let run: BacklogRun?
	let source: Source
	/// The markdown the fraction above was counted from, which is the copy a
	/// box ticked on this card has to write.
	///
	/// **Not `item.file`**, for the same reason `source` exists: an item being
	/// worked in a checkout of its own has two copies, and the card draws the
	/// checkout's. A tick that went to the project's would tick a step the card
	/// was not showing, on a copy whose fraction the card was not drawing — so
	/// the number under the pointer would not move, and the one that did move
	/// would be somebody else's.
	///
	/// Worked out here, on the walk, rather than asked for while drawing: the
	/// question is which copy `progress` came from, and this is where that was
	/// decided.
	let checklistFile: URL

	init(_ item: BacklogItem, run: BacklogRun?) {
		self.item = item
		self.run = run

		// The second read, and it is here rather than anywhere nearer the
		// drawing on purpose: this initialiser runs on the walk that re-reads
		// the folder, off the main thread, and `draw(_:)` runs on every scroll.
		// A fraction that costs a file open is a fraction nobody should be able
		// to put on a card.
		//
		// Nothing extra is paid by the cards that have no run, which is nearly
		// all of them: `itemInWorktree` is `nil` without touching the disk
		// unless a checkout was recorded for this number and is still there.
		let onBranch = run?.itemInWorktree
		let copy = onBranch ?? item
		self.progress = copy.progress()
		self.estimate = copy.estimate()
		self.images = copy.images().count
		self.hasSpecDelta = !copy.specDeltas().isEmpty
		self.source = onBranch == nil ? .project : .worktree
		self.checklistFile = copy.file
	}

	var number: Int { item.number }
	var title: String { item.title }
	var state: BacklogState { item.state }
}

/// One OpenSpec change, with everything a card says about it worked out.
///
/// The same shape as `BacklogCard` and for the same reason — the reads happen on
/// the walk, not while drawing — and cheaper: a change is one directory listing
/// and one file, where an item is four reads.
///
/// **It has no number**, and that is the difference that matters rather than a
/// missing field. A backlog item is `0540` for ever and its state is the folder
/// it sits in; a change is a name, and its state is worked out from what is in
/// its directory. That is why a card for one cannot be dragged: dragging an item
/// between columns *is* the `mv` that changes its state, and dragging a change
/// could only mean ticking somebody's checkboxes.
struct OpenSpecCard: Equatable {
	let change: OpenSpecChange
	let progress: BacklogItem.Progress?
	/// **In OpenSpec's own vocabulary**, not the backlog's folders. Answering in
	/// `BacklogState` is what put a change into a column it has no notion of.
	let state: OpenSpecState

	init(_ change: OpenSpecChange) {
		self.change = change
		// The second read, here rather than nearer the drawing, exactly as
		// `BacklogCard` does it: this runs on the walk that re-reads the folder,
		// and `draw(_:)` runs on every scroll.
		let progress = change.progress()
		self.progress = progress
		self.state = change.state(progress: progress)
	}

	var name: String { change.name }

	/// The file the fraction was counted from, and the one a tick writes.
	///
	/// A change has only ever one copy — it is not picked up into a checkout of
	/// its own the way an item is — so this is `tasks.md` and nothing else. It
	/// is still asked by name rather than derived at the point of writing,
	/// because the tip asks the same question of both records and one answer to
	/// it is one behaviour to keep.
	var checklistFile: URL { change.tasksFile }

	/// The line under the name, and **in one place** because three of them read
	/// it: the card, the row in the list, and the measurement that decides how
	/// tall the card is. Those had the same expression written out three times,
	/// and the one that can disagree is the height — a card measured without a
	/// line it is then drawn with comes out short.
	///
	/// What is written and what is wanted next, while there are no tasks to
	/// count. **And where the schema is one this cannot read, always**: that
	/// change has a fraction like any other — `- [x]` means the same thing in
	/// any schema — so keying on "no progress" alone would count its tasks and
	/// never say that the column it is in was not derived.
	var marks: String {
		guard progress == nil || !change.isSchemaUnderstood else { return "" }
		return change.artifactSummary
	}
}

/// One thing on the board, whichever record it came from.
enum BoardEntry {
	case item(BacklogCard)
	case change(OpenSpecCard)

	var column: BoardColumn {
		switch self {
		case let .item(card):   return .backlog(card.state)
		case let .change(card): return .openSpec(card.state)
		}
	}

	/// What a card is called, whichever record it came from.
	///
	/// **The tip keys on this rather than on the view it was opened from.** A
	/// card view is a cell the table recycles, and the board rebuilds its rows
	/// on every reload — including the reload a tick causes — so a tip holding
	/// a view would be a tip about whichever card the table happened to reuse
	/// that object for. A number and a name are what survive a walk.
	enum Identity: Hashable {
		case item(Int)
		case change(String)
	}

	var identity: Identity {
		switch self {
		case let .item(card):   return .item(card.number)
		case let .change(card): return .change(card.name)
		}
	}

	/// Whether this is a card somebody is in the middle of.
	///
	/// The one column the task tip opens over. A Ready card has nothing
	/// verified — ticking its first box is an agent picking the work up, not a
	/// person confirming it — and a Complete one has nothing open to list.
	var isInProgress: Bool {
		switch self {
		case let .item(card):   return card.state == .inProgress
		case let .change(card): return card.state == .inProgress
		}
	}

	/// The file whose boxes this card's fraction was counted from.
	var checklistFile: URL {
		switch self {
		case let .item(card):   return card.checklistFile
		case let .change(card): return card.checklistFile
		}
	}
}

/// One column of the board, from whichever record is showing.
///
/// **Each source brings its own**, which is the whole of this: the backlog's are
/// its folders and OpenSpec's are its lifecycle, and one set of columns over two
/// records is what sorted a change into `waiting` — a folder OpenSpec has no
/// notion of and nothing can ever be in.
///
/// The two are not merged into a common five. They have `ready` and
/// `in-progress` in common and nothing else, and a column called Open that means
/// "written down, not agreed" for one record and "the proposal is not finished"
/// for the other is a heading that has to be read twice.
enum BoardColumn: Hashable {
	case backlog(BacklogState)
	case openSpec(OpenSpecState)

	var title: String {
		switch self {
		case let .backlog(state):  return state.title
		case let .openSpec(state): return state.title
		}
	}

	/// The one line that says what belongs here, for a column with nothing in it.
	var summary: String {
		switch self {
		case let .backlog(state):  return state.summary
		case let .openSpec(state): return state.summary
		}
	}

	/// What a driver prints and what the summary line counts by. The backlog's
	/// is its folder name, because that is a real path somebody can `cd` to;
	/// OpenSpec's is the state's own name, because there is no folder.
	var key: String {
		switch self {
		case let .backlog(state):  return state.directoryName
		case let .openSpec(state): return state.rawValue
		}
	}

	/// The backlog state this column is, where it is one.
	///
	/// **Nil for every OpenSpec column, and that is what makes a drop into one
	/// impossible to write.** A drag moves a file between folders; there are no
	/// folders on that side, so the type says so rather than a guard hoping to.
	var backlogState: BacklogState? {
		switch self {
		case let .backlog(state): return state
		case .openSpec:           return nil
		}
	}
}

/// The backlog, as a list and as a board.
///
/// Two presentations of one directory, and the toggle between them is a view
/// change rather than a mode: the list is for reading — everything in one
/// column, in number order, which is how you find the thing you half remember
/// — and the board is for moving, because dragging a card from `ready` to
/// `in-progress` is the same `mv` and is the one gesture a list cannot make.
///
/// Neither holds any state of its own. What is on screen is what is in
/// `.abydos/backlog`, re-read when it changes, so somebody moving a file in a
/// terminal sees the board move too.
