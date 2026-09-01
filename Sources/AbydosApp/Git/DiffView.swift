import AppKit
import AbydosKit

/// A unified diff, rendered as coloured lines, with the changed ones
/// selectable so parts of it can be staged.
///
/// Hand-drawn like the code view rather than built on `NSTextView`: a diff is a
/// list of short lines with one colour each, and the same virtualised drawing
/// keeps a large one — a lockfile, a generated file — instant to open.
final class DiffView: NSView {
	/// Stage or unstage the selected lines. The direction depends on which side
	/// of the index this diff came from, which the pane already knows.
	var onApplySelection: ((Set<Int>) -> Void)?
	/// Throw away the selected work-tree lines.
	var onDiscardSelection: ((Set<Int>) -> Void)?
	/// Put just these lines aside. Nil where the caller cannot do it — an old
	/// git, or a staged hunk, which is already where a stash would take it.
	var onStashSelection: ((Set<Int>) -> Void)?
	/// Leave a remark on a line or a run of them, by number on the new side.
	///
	/// The new side because that is the only position a forge can resolve: a
	/// comment is anchored to the file as it is now, not as it was. Two numbers
	/// because a remark is often about a block rather than a line, and pointing
	/// at the first line of a five-line mistake makes the reader find the rest.
	var onCommentOnLines: ((_ from: Int, _ to: Int) -> Void)?
	/// Change a remark written here and not yet sent.
	var onEditComment: ((Comment) -> Void)?
	/// Take one back.
	var onDeleteComment: ((Comment) -> Void)?

	private var patch = GitPatch()
	private(set) var isStaged = false
	/// A diff of something already committed: there is nothing to stage in it.
	var isReadOnly = false
	/// Syntax tokens per patch line, when the file is in a language we parse.
	private var highlights: [Int: [HighlightToken]] = [:]

	/// Flat rows: hunk headers and lines interleaved, as drawn.
	private var rows: [Row] = []
	/// Selected *line* indices, in `GitPatch`'s flat numbering.
	private var selection: Set<Int> = []
	/// Anchor for shift-click range selection.
	private var anchorRow: Int?
	/// The remark under the selection, and the rows it occupies.
	///
	/// A remark is several rows and is selected as one thing: picking the third
	/// line of somebody's paragraph is not a gesture anybody means to make.
	private var selectedComment: (comment: Comment, rows: ClosedRange<Int>)?

	/// A remark somebody left on a line of this diff.
	///
	/// The view's own shape rather than `ReviewComment`: what it needs is three
	/// strings and a flag, and a diff view that knew what a pull request was
	/// would be a diff view the changes pane could not use.
	struct Comment: Equatable {
		let author: String
		let when: String
		let body: String
		/// Whether the code it was about has been written over since.
		let isOutdated: Bool
		/// Written here and not sent yet, which is the only kind this view can
		/// offer to change: somebody else's remark is theirs.
		let isPending: Bool
		/// The line it sits on, on the new side.
		let line: Int?
		/// Where its range begins, when it is about more than one line.
		let startLine: Int?

		init(
			author: String,
			when: String,
			body: String,
			isOutdated: Bool = false,
			isPending: Bool = false,
			line: Int? = nil,
			startLine: Int? = nil
		) {
			self.author = author
			self.when = when
			self.body = body
			self.isOutdated = isOutdated
			self.isPending = isPending
			self.line = line
			self.startLine = startLine
		}

		/// How the range reads on the heading: `40` or `36–40`.
		var place: String {
			guard let line else { return "" }
			guard let startLine, startLine != line else { return "line \(line)" }
			return "lines \(startLine)–\(line)"
		}
	}

	/// Remarks against the lines they were left on, by line number on the new
	/// side — which is the side that still exists.
	private var comments: [Int: [Comment]] = [:]
	/// Remarks whose line has gone, shown against the file instead.
	private var outdatedComments: [Comment] = []

	/// Puts the conversation on the diff.
	///
	/// **A reviewer who cannot see the existing comments reviews what somebody
	/// has already reviewed and says it again**, which is worse than saying
	/// nothing: the author now has two conversations about one line.
	func setComments(at lines: [Int: [Comment]], andOutdated outdated: [Comment]) {
		comments = lines
		outdatedComments = outdated
		rebuildRows()
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	/// Whether git's own preamble is drawn, and whether the sides are beside
	/// each other. Both are preferences; both are read at rebuild.
	private var showsChrome = Settings.shared.diffShowsChrome
	private var isSideBySide = Settings.shared.diffIsSideBySide

	/// Re-reads the two preferences and redraws if either moved.
	///
	/// Called from the settings notification rather than polled, and cheap when
	/// nothing changed — a diff of five thousand rows should not rebuild because
	/// somebody changed the font.
	@objc func applyDiffSettings() {
		// **The zoom is a settings change too, and this used to drop it.** The
		// guard below asked only whether the two *diff* preferences had moved,
		// so a ⌘+ arrived here, matched neither, and returned — leaving the
		// font and the line height at the size they were read at when the view
		// was built. The diff scaled when it was closed and opened again and
		// not before, which is exactly how it was reported.
		let was = lineHeight
		updateMetrics()
		let metricsMoved = lineHeight != was

		let chrome = Settings.shared.diffShowsChrome
		let sideBySide = Settings.shared.diffIsSideBySide
		guard metricsMoved || chrome != showsChrome || sideBySide != isSideBySide else { return }
		showsChrome = chrome
		isSideBySide = sideBySide
		rebuildRows()
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	private enum Row {
		case header(String)
		/// The declaration a hunk is inside, when the preamble is not drawn and
		/// git has guessed one.
		case scope(String)
		/// One line of each side, beside each other. Side by side only.
		case pair(left: Side?, right: Side?)
		/// One line of a remark, drawn under the line it is about.
		case comment(Comment, text: String, isFirst: Bool)
		case hunkHeader(index: Int, text: String)
		/// A line, and where it sits in each side of the file.
		///
		/// **Both numbers, because a diff has two files in it.** A removed line
		/// has a place in the old one and none in the new; an added line the
		/// other way round; and a line somebody wants to go and look at is
		/// nearly always identified by one of the two.
		case line(index: Int, line: GitPatch.Line, old: Int?, new: Int?)
	}

	/// One half of a side-by-side row.
	private struct Side: Equatable {
		let index: Int
		let line: GitPatch.Line
		let number: Int
	}

	private var font: NSFont = Theme.terminalFont(size: Theme.current.fontSize)
	private var lineHeight: CGFloat = 0
	private static let horizontalInset: CGFloat = 12
	/// Room for the selection marker down the left edge.
	private static let gutterWidth: CGFloat = 14
	/// Room for the two line numbers beside it.
	private var numberWidth: CGFloat {
		// Measured from the font rather than guessed: a diff of a four-figure
		// file and one of a hundred lines should not indent differently, so it
		// is a fixed five columns either side.
		("0" as NSString).size(withAttributes: [.font: font]).width * 5
	}

	override var isFlipped: Bool { true }
	override var acceptsFirstResponder: Bool { true }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		updateMetrics()
		// Its own observer rather than a call from each pane that owns one:
		// three panes draw diffs, and a preference that reached two of them
		// would be a menu item that half works.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(applyDiffSettings),
			name: .abydosSettingsChanged,
			object: nil
		)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit { NotificationCenter.default.removeObserver(self) }

	private func updateMetrics() {
		font = Theme.terminalFont(size: Theme.current.fontSize)
		lineHeight = (font.ascender - font.descender + font.leading).rounded() + 2
	}

	func applyThemeChange() {
		updateMetrics()
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	// MARK: - Content

	/// How much of a diff is on screen, for a driver that cannot photograph it.
	var reportForTesting: String {
		guard !rows.isEmpty else { return "empty" }
		let remarks = rows.filter {
			if case .comment(_, _, true) = $0 { return true }
			return false
		}.count
		return remarks == 0 ? "\(rows.count) rows" : "\(rows.count) rows, \(remarks) comments"
	}

	/// The conversation as it is drawn, for a run that cannot photograph it.
	func commentsForTesting() -> [String] {
		rows.compactMap { row in
			guard case let .comment(comment, text, isFirst) = row, isFirst else { return nil }
			return (comment.isOutdated ? "outdated: " : "at a line: ") + text
		}
	}

	func setDiff(_ text: String, staged: Bool, url: URL? = nil) {
		// A parse of the patch and two whole tree-sitter parses behind
		// `highlights`, all inline and bounded only at 5,000 lines. Marked so a
		// diff that took a second says it was a diff.
		StallWatch.mark("diff render") {
			isStaged = staged
			// The conversation belongs to the file that was on screen, and this
			// is a different file — or the same one at a different head. The
			// caller puts them back.
			comments = [:]
			outdatedComments = []
			selectedComment = nil
			patch = GitPatch.parse(text)
			selection = []
			anchorRow = nil
			rebuildRows()
			highlights = Self.highlights(for: patch, url: url)
			invalidateIntrinsicContentSize()
			needsDisplay = true
		}
	}

	/// Above this many changed lines the colours are not worth the parse.
	///
	/// A diff that size is a lockfile or a generated file, which nobody reads
	/// line by line — and reconstructing both sides of it costs more than the
	/// whole view is meant to.
	private static let highlightLineLimit = 5000

	private static func highlights(for patch: GitPatch, url: URL?) -> [Int: [HighlightToken]] {
		guard let url, let languageId = LanguageRegistry.shared.languageId(for: url) else { return [:] }
		let lines = patch.hunks.reduce(0) { $0 + $1.lines.count }
		guard lines <= highlightLineLimit else { return [:] }
		return DiffHighlighter.highlight(patch, languageId: languageId)
	}

	/// How many lines of one remark are drawn before it is cut short.
	///
	/// A comment is prose and a diff is a list of lines; four is enough for the
	/// remarks people actually leave, and the rest is one click away in the
	/// browser. Cutting it is said out loud rather than done silently.
	private static let commentLineLimit = 4

	private func commentRows(for comment: Comment) -> [Row] {
		var parts = [comment.author]
		if !comment.when.isEmpty { parts.append(comment.when) }
		if comment.isOutdated { parts.append("on an earlier version") }
		if let startLine = comment.startLine, let line = comment.line, startLine != line {
			parts.append("lines \(startLine)–\(line)")
		}
		let heading = parts.joined(separator: " · ")
		var made: [Row] = [.comment(comment, text: heading, isFirst: true)]
		// **Every line ending, not only `\n`.** GitHub hands these back with
		// CRLF in them, and a lone `\r` inside a string drawn by Core Text moves
		// the pen back to the start of the row — so a remark written on a
		// Windows machine drew its second paragraph on top of its first.
		let body = comment.body
			.replacingOccurrences(of: "\r\n", with: "\n")
			.replacingOccurrences(of: "\r", with: "\n")
			.split(separator: "\n", omittingEmptySubsequences: false)
			// A row is a row. A paragraph of prose is longer than any line of
			// code beside it, and one running the width of three windows is not
			// something anybody reads to the end of.
			.map { $0.count > 160 ? $0.prefix(159) + "…" : $0 }
		for line in body.prefix(Self.commentLineLimit) {
			made.append(.comment(comment, text: String(line), isFirst: false))
		}
		if body.count > Self.commentLineLimit {
			made.append(.comment(
				comment,
				text: "… and \(body.count - Self.commentLineLimit) more lines",
				isFirst: false
			))
		}
		return made
	}

	private func rebuildRows() {
		// **Git's preamble, or none of it.** The pane already says which file
		// this is; see `Settings.diffShowsChrome`.
		rows = showsChrome ? patch.header.map { Row.header($0) } : []

		// **A comment whose line has gone is shown, not dropped.** GitHub calls
		// these outdated; a reviewer still needs to know a conversation happened
		// even when the code it was about is not there any more. Against the
		// file, at the top, because there is no line left to put it against.
		for comment in outdatedComments {
			rows += commentRows(for: comment)
		}

		var index = 0
		for (position, hunk) in patch.hunks.enumerated() {
			if showsChrome {
				let heading = hunk.heading.isEmpty ? "" : " \(hunk.heading)"
				rows.append(.hunkHeader(index: position, text: "@@ hunk \(position + 1)\(heading)"))
			} else if !hunk.heading.isEmpty {
				// The declaration the hunk is inside, which is the one part of
				// the preamble the rest of the window does not already say.
				rows.append(.scope(hunk.heading))
			} else if position > 0 {
				// Something between two hunks, so a jump in the line numbers is
				// visible as a jump rather than as a mystery.
				rows.append(.scope(""))
			}

			if isSideBySide {
				index = appendPairs(of: hunk, from: index)
				continue
			}

			// Counted off the hunk header, which is where git puts the only
			// statement of where a hunk begins.
			var old = hunk.oldStart
			var new = hunk.newStart
			for line in hunk.lines {
				var commentedLine: Int?
				switch line.kind {
				case .added:
					rows.append(.line(index: index, line: line, old: nil, new: new))
					commentedLine = new
					new += 1
				case .removed:
					rows.append(.line(index: index, line: line, old: old, new: nil))
					old += 1
				default:
					rows.append(.line(index: index, line: line, old: old, new: new))
					commentedLine = new
					old += 1
					new += 1
				}
				// Under the line rather than beside it: a diff is as wide as the
				// code and a remark is prose, and prose in a margin is a column
				// four words across.
				if let commentedLine { appendComments(at: commentedLine) }
				index += 1
			}
		}

		if patch.hunks.isEmpty {
			rows.append(.header(""))
			rows.append(.header("No textual changes."))
		}
	}

	/// The rows of one hunk, with the two sides beside each other.
	///
	/// **A run of removals is paired with the run of additions that follows
	/// it**, which is what makes a rewritten block readable: the old line and
	/// the line that replaced it end up on one row, and a run that is longer on
	/// one side pads the other with nothing. Anything else — a deletion with no
	/// addition after it, an addition out of nowhere — is a row with one side.
	private func appendPairs(of hunk: GitPatch.Hunk, from start: Int) -> Int {
		var index = start
		var old = hunk.oldStart
		var new = hunk.newStart
		var removed: [Side] = []
		var added: [Side] = []

		func flush() {
			for position in 0..<max(removed.count, added.count) {
				rows.append(.pair(
					left: position < removed.count ? removed[position] : nil,
					right: position < added.count ? added[position] : nil
				))
				if let right = position < added.count ? added[position] : nil {
					appendComments(at: right.number)
				}
			}
			removed = []
			added = []
		}

		for line in hunk.lines {
			switch line.kind {
			case .removed:
				removed.append(Side(index: index, line: line, number: old))
				old += 1
			case .added:
				added.append(Side(index: index, line: line, number: new))
				new += 1
			case .noNewline:
				break
			default:
				flush()
				let side = Side(index: index, line: line, number: new)
				rows.append(.pair(
					left: Side(index: index, line: line, number: old), right: side
				))
				appendComments(at: new)
				old += 1
				new += 1
			}
			index += 1
		}
		flush()
		return index
	}

	/// The remarks left on one line of the new side, if there are any.
	private func appendComments(at line: Int) {
		guard let left = comments[line] else { return }
		for comment in left { rows += commentRows(for: comment) }
	}

	// MARK: - Selection

	var hasSelection: Bool { !selection.isEmpty }
	var selectedLines: Set<Int> { selection }

	override func selectAll(_ sender: Any?) {
		selection = Set(patch.selectableIndices())
		needsDisplay = true
	}

	func clearSelection() {
		selection = []
		anchorRow = nil
		needsDisplay = true
	}

	/// Selects every changed line in a hunk, for "stage this hunk".
	func selectHunk(_ hunkIndex: Int) {
		selection = Set(patch.indices(inHunk: hunkIndex))
		needsDisplay = true
	}

	private func row(at point: NSPoint) -> Int? {
		let top = Theme.current.scaled(8)
		let index = Int((point.y - top) / lineHeight)
		return rows.indices.contains(index) ? index : nil
	}

	private func lineIndex(atRow row: Int) -> Int? {
		guard rows.indices.contains(row) else { return nil }
		// Side by side, a row is two lines and the right-hand one is the one a
		// remark or a stage is about — it is the side that still exists.
		if case let .pair(left, right) = rows[row] {
			guard let side = right ?? left else { return nil }
			guard side.line.isSelectable || (isReadOnly && right != nil) else { return nil }
			return side.index
		}
		guard case let .line(index, line, _, new) = rows[row] else {
			return nil
		}
		// **Staging can only touch a changed line; a remark can touch any line
		// that exists.** In a read-only diff there is nothing to stage, so
		// letting the selection cover context is free — and it is what makes
		// "comment on these five lines" possible, three of which are usually
		// context.
		guard line.isSelectable || (isReadOnly && new != nil) else { return nil }
		return index
	}

	/// The new-side numbers the selection covers, in the order they are drawn.
	var selectedNewLines: [Int] {
		rows.compactMap { row in
			switch row {
			case let .line(index, _, _, new):
				guard let new, selection.contains(index) else { return nil }
				return new
			case let .pair(_, right):
				guard let right, selection.contains(right.index) else { return nil }
				return right.number
			default:
				return nil
			}
		}
	}

	/// The new-side number a row carries, in either arrangement.
	private func newNumber(atRow row: Int) -> Int? {
		guard rows.indices.contains(row) else { return nil }
		switch rows[row] {
		case let .line(_, _, _, new): return new
		case let .pair(_, right):     return right?.number
		default:                      return nil
		}
	}

	/// Which rows one remark occupies, given the row its heading is on.
	private func commentBlock(startingAt row: Int) -> ClosedRange<Int>? {
		guard case let .comment(comment, _, isFirst) = rows[row], isFirst else { return nil }
		var last = row
		while last + 1 < rows.count,
		      case let .comment(next, _, isNext) = rows[last + 1],
		      !isNext, next == comment {
			last += 1
		}
		return row...last
	}

	/// The remark a row belongs to, whichever of its rows was clicked.
	private func comment(atRow row: Int) -> (Comment, ClosedRange<Int>)? {
		guard rows.indices.contains(row), case .comment = rows[row] else { return nil }
		var first = row
		while first > 0 {
			if case let .comment(_, _, isFirst) = rows[first], isFirst { break }
			first -= 1
		}
		guard case let .comment(comment, _, isFirst) = rows[first], isFirst,
		      let block = commentBlock(startingAt: first)
		else { return nil }
		return (comment, block)
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		guard let row = row(at: convert(event.locationInWindow, from: nil)) else { return }

		// A click on a remark takes the remark — all of its rows, because a
		// paragraph is one thing.
		if let (comment, block) = comment(atRow: row) {
			selectedComment = (comment, block)
			selection = []
			anchorRow = nil
			needsDisplay = true
			return
		}
		selectedComment = nil

		// A click on a hunk header takes the whole hunk, which is the common
		// case — line-by-line is for when a hunk mixes two changes.
		if case let .hunkHeader(hunkIndex, _) = rows[row] {
			selectHunk(hunkIndex)
			anchorRow = row
			return
		}

		guard let index = lineIndex(atRow: row) else { return }

		if event.modifierFlags.contains(.shift), let anchor = anchorRow {
			// Range from the anchor, skipping context that falls between.
			let bounds = min(anchor, row)...max(anchor, row)
			for position in bounds {
				if let candidate = lineIndex(atRow: position) { selection.insert(candidate) }
			}
		} else if event.modifierFlags.contains(.command) {
			if selection.contains(index) { selection.remove(index) } else { selection.insert(index) }
			anchorRow = row
		} else {
			selection = [index]
			anchorRow = row
		}
		needsDisplay = true
	}

	override func mouseDragged(with event: NSEvent) {
		guard let anchor = anchorRow,
		      let row = row(at: convert(event.locationInWindow, from: nil))
		else { return }

		var updated: Set<Int> = []
		for position in min(anchor, row)...max(anchor, row) {
			if let index = lineIndex(atRow: position) { updated.insert(index) }
		}
		guard updated != selection else { return }
		selection = updated
		needsDisplay = true
	}

	override func keyDown(with event: NSEvent) {
		// Return applies, which is the whole point of having a selection here.
		if event.keyCode == 36 || event.keyCode == 76, hasSelection {
			onApplySelection?(selection)
			return
		}
		super.keyDown(with: event)
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		// A commit's diff has nothing to stage or throw away; it has already
		// happened, and offering to undo part of it here would be a lie. A pull
		// request's has nothing to stage either — it is somebody else's branch —
		// but it does have somewhere to leave a remark.
		guard !isReadOnly else { return commentMenu(for: event) }

		// Right-clicking outside the selection moves it there first, so the
		// command acts on what was aimed at.
		if let row = row(at: convert(event.locationInWindow, from: nil)) {
			if case let .hunkHeader(hunkIndex, _) = rows[row] {
				selectHunk(hunkIndex)
			} else if let index = lineIndex(atRow: row), !selection.contains(index) {
				selection = [index]
				anchorRow = row
				needsDisplay = true
			}
		}
		guard hasSelection else { return nil }

		let menu = NSMenu()
		menu.autoenablesItems = false

		let count = selection.count
		let suffix = count == 1 ? "" : " (\(count))"
		// **Only what this view has somewhere to send.** These items used to be
		// added whatever the view had been told, and a diff whose owner had not
		// wired them up offered "Stage Selected Lines", enabled, over a closure
		// nobody had set — which is what the commit page did: fifteen lines
		// selected, the item pressed, and the working copy exactly as it was.
		// A missing item is a thing somebody can see; a dead one is not.
		if onApplySelection != nil {
			let apply = NSMenuItem(
				title: (isStaged ? "Unstage Selected Lines" : "Stage Selected Lines") + suffix,
				action: #selector(applySelection),
				keyEquivalent: ""
			)
			apply.target = self
			menu.addItem(apply)
		}

		if !isStaged, onStashSelection != nil {
			if !menu.items.isEmpty { menu.addItem(.separator()) }
			let stash = NSMenuItem(
				title: "Stash Selected Lines" + suffix,
				action: #selector(stashSelection),
				keyEquivalent: ""
			)
			stash.target = self
			menu.addItem(stash)
		}

		if !isStaged, onDiscardSelection != nil {
			if !menu.items.isEmpty { menu.addItem(.separator()) }
			let discard = NSMenuItem(
				title: "Discard Selected Lines" + suffix,
				action: #selector(discardSelection),
				keyEquivalent: ""
			)
			discard.target = self
			menu.addItem(discard)
		}
		return menu.items.isEmpty ? nil : menu
	}

	/// What a read-only diff offers: a remark on the lines under the pointer,
	/// and the verbs for a remark already written here.
	private func commentMenu(for event: NSEvent) -> NSMenu? {
		guard onCommentOnLines != nil else { return nil }
		guard let row = row(at: convert(event.locationInWindow, from: nil)) else { return nil }

		// Over a remark: the two things that can be done to one written here.
		// Somebody else's is theirs, and this offers nothing over it rather
		// than something that would fail.
		if let (comment, block) = comment(atRow: row) {
			selectedComment = (comment, block)
			needsDisplay = true
			guard comment.isPending else { return nil }
			let menu = NSMenu()
			for (title, action) in [
				("Edit Comment…", #selector(editComment)),
				("Delete Comment", #selector(deleteComment)),
			] {
				let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
				item.target = self
				menu.addItem(item)
			}
			return menu
		}

		// Whichever arrangement is drawn: a row is commentable when it has a
		// line on the new side, which is the only side a forge can anchor to.
		guard let index = lineIndex(atRow: row), newNumber(atRow: row) != nil else { return nil }

		// **Right-clicking outside the selection moves it there first**, so the
		// remark is about what was aimed at — the same rule the staging menu
		// keeps one function up.
		if !selection.contains(index) {
			selection = [index]
			anchorRow = row
			selectedComment = nil
			needsDisplay = true
		}

		let lines = selectedNewLines
		guard let from = lines.min(), let to = lines.max() else { return nil }
		commentRange = (from, to)

		let menu = NSMenu()
		let item = NSMenuItem(
			title: from == to ? "Comment on Line \(from)…" : "Comment on Lines \(from)–\(to)…",
			action: #selector(commentOnLines),
			keyEquivalent: ""
		)
		item.target = self
		menu.addItem(item)
		return menu
	}

	/// Which lines the menu was opened over.
	private var commentRange: (from: Int, to: Int)?

	@objc private func commentOnLines() {
		guard let commentRange else { return }
		onCommentOnLines?(commentRange.from, commentRange.to)
	}

	@objc private func editComment() {
		guard let comment = selectedComment?.comment else { return }
		onEditComment?(comment)
	}

	@objc private func deleteComment() {
		guard let comment = selectedComment?.comment else { return }
		onDeleteComment?(comment)
	}

	/// Leaves a remark on a run of lines, for a driven run that has no pointer.
	func commentOnLinesForTesting(from: Int, to: Int) -> Bool {
		let available = Set(commentableLinesForTesting())
		guard available.contains(from), available.contains(to) else { return false }
		onCommentOnLines?(from, to)
		return true
	}

	/// Selects a run of lines the way a drag does, so a run can then ask the
	/// menu what it would offer.
	func selectLinesForTesting(from: Int, to: Int) {
		selection = []
		for row in rows {
			let place: (index: Int, number: Int)?
			switch row {
			case let .line(index, _, _, new): place = new.map { (index, $0) }
			case let .pair(_, right):         place = right.map { ($0.index, $0.number) }
			default:                          place = nil
			}
			guard let place, place.number >= from, place.number <= to else { continue }
			selection.insert(place.index)
		}
		selectedComment = nil
		needsDisplay = true
	}

	/// What the menu over a selection would offer, and whether pressing it
	/// would reach anything.
	///
	/// **The second half is the claim.** The menu is built here for any diff
	/// that is not read-only, so its items appear whether or not the view has
	/// been told what to do with them — which is how the commit page came to
	/// offer "Stage Selected Lines" over its own diff and do nothing at all
	/// when it was pressed.
	func verbsForTesting() -> String {
		"readOnly=\(isReadOnly)"
			+ " apply=\(onApplySelection == nil ? "none" : "wired")"
			+ " discard=\(onDiscardSelection == nil ? "none" : "wired")"
			+ " stash=\(onStashSelection == nil ? "none" : "wired")"
	}

	/// Selects the first `count` lines that can be staged and applies them, the
	/// way the menu item does.
	func applyFirstLinesForTesting(_ count: Int) -> String {
		let selectable = patch.selectableIndices().prefix(count)
		guard !selectable.isEmpty else { return "nothing selectable" }
		selection = Set(selectable)
		needsDisplay = true
		guard onApplySelection != nil else { return "\(selectable.count) selected, nothing wired" }
		onApplySelection?(selection)
		return "\(selectable.count) selected, applied"
	}

	/// The remark the selection is on, if it is on one.
	func selectedCommentForTesting() -> String? {
		guard let comment = selectedComment?.comment else { return nil }
		return "\(comment.author) · \(comment.place)"
			+ (comment.isPending ? " · not sent" : "")
	}

	/// Selects a remark the way a click does, by the line it is on.
	@discardableResult
	func selectCommentForTesting(onLine line: Int) -> Bool {
		for (position, row) in rows.enumerated() {
			guard case let .comment(comment, _, isFirst) = row, isFirst, comment.line == line,
			      let block = commentBlock(startingAt: position)
			else { continue }
			selectedComment = (comment, block)
			selection = []
			needsDisplay = true
			return true
		}
		return false
	}

	/// The line numbers a remark could be left on, so a run can name one.
	func commentableLinesForTesting() -> [Int] {
		rows.compactMap {
			switch $0 {
			case let .line(_, _, _, new): return new
			case let .pair(_, right):     return right?.number
			default:                      return nil
			}
		}
	}

	@objc private func applySelection() { onApplySelection?(selection) }
	@objc private func discardSelection() { onDiscardSelection?(selection) }
	@objc private func stashSelection() { onStashSelection?(selection) }

	// MARK: - Drawing

	override var intrinsicContentSize: NSSize {
		NSSize(
			width: NSView.noIntrinsicMetric,
			height: max(CGFloat(rows.count) * lineHeight + Theme.current.scaled(16), 10)
		)
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.current.editorBackground.setFill()
		dirtyRect.fill()

		let top = Theme.current.scaled(8)
		// Only the rows in view are laid out, which is what keeps a huge diff
		// as cheap to scroll as a small one.
		let first = max(0, Int((dirtyRect.minY - top) / lineHeight))
		let last = min(rows.count, Int((dirtyRect.maxY - top) / lineHeight) + 1)
		guard last > first else { return }

		for position in first..<last {
			draw(row: rows[position], at: top + CGFloat(position) * lineHeight)
		}
	}

	private func draw(row: Row, at y: CGFloat) {
		let textX = Self.horizontalInset + Self.gutterWidth + numberWidth * 2

		switch row {
		case .header(let text):
			guard !text.isEmpty else { return }
			text.draw(at: NSPoint(x: textX, y: y), font: font, color: Theme.current.gitIgnored)

		case let .comment(comment, text, isFirst):
			// A tint of its own down the whole row, so a conversation reads as
			// something other than code at a glance.
			Theme.current.gitModified.withAlphaComponent(comment.isOutdated ? 0.05 : 0.10).setFill()
			NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()

			if selectedComment?.comment == comment {
				Theme.current.gitModified.withAlphaComponent(0.20).setFill()
				NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
				Theme.current.gitModified.setFill()
				NSRect(x: 0, y: y, width: Theme.current.scaled(3), height: lineHeight).fill()
			}
			let colour = comment.isOutdated
				? Theme.current.gitIgnored
				: (isFirst ? Theme.current.gitModified : Theme.current.sidebarText)
			// ✍️ for one being written here, 💬 for one that has been said.
			let marked = isFirst ? (comment.isPending ? "✍️ " : "💬 ") + text : "   " + text
			marked.draw(
				at: NSPoint(x: textX, y: y),
				font: isFirst
					? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
					: font,
				color: colour
			)

		case .scope(let text):
			// A rule with the declaration on it, rather than four lines of
			// preamble: the one thing git's `@@` line says that the pane around
			// it does not.
			Theme.current.gitIgnored.withAlphaComponent(0.12).setFill()
			NSRect(
				x: 0, y: y + lineHeight / 2, width: bounds.width, height: max(1, lineHeight * 0.06)
			).fill()
			guard !text.isEmpty else { return }
			let attributes: [NSAttributedString.Key: Any] = [
				.font: font,
				.foregroundColor: Theme.current.gitIgnored,
			]
			let measured = (text as NSString).size(withAttributes: attributes)
			// Sitting on the rule with the background cut out behind it, so it
			// reads as a label on a separator and not as a line of the file.
			let inset = Theme.current.scaled(6)
			Theme.current.editorBackground.setFill()
			NSRect(
				x: textX - inset, y: y, width: measured.width + inset * 2, height: lineHeight
			).fill()
			text.draw(at: NSPoint(x: textX, y: y), font: font, color: Theme.current.gitIgnored)

		case let .pair(left, right):
			drawPair(left: left, right: right, at: y)

		case .hunkHeader(_, let text):
			NSColor.white.withAlphaComponent(0.05).setFill()
			NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
			text.draw(
				at: NSPoint(x: textX, y: y),
				font: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask),
				color: Theme.current.gitModified
			)

		case .line(let index, let line, let old, let new):
			let isSelected = selection.contains(index)

			if let background = background(for: line.kind) {
				background.setFill()
				NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
			}

			if isSelected {
				// A tint over the whole row plus a bar in the gutter: the tint
				// alone is hard to see against a row that already has one.
				Theme.current.gitModified.withAlphaComponent(0.20).setFill()
				NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
				Theme.current.gitModified.setFill()
				NSRect(x: 0, y: y, width: Theme.current.scaled(3), height: lineHeight).fill()
			}

			// The two numbers, right-aligned in their own columns and dimmer
			// than the code: they are there to be read off when you want one,
			// not to be read past on every line.
			let numbers = Theme.current.gitIgnored.withAlphaComponent(0.7)
			let numberFont = font
			func column(_ value: Int?, at x: CGFloat) {
				guard let value else { return }
				let text = "\(value)" as NSString
				let width = text.size(withAttributes: [.font: numberFont]).width
				text.draw(
					at: NSPoint(x: x + numberWidth - width - Theme.current.scaled(4), y: y),
					withAttributes: [.font: numberFont, .foregroundColor: numbers]
				)
			}
			let numbersX = Self.horizontalInset + Self.gutterWidth
			column(old, at: numbersX)
			column(new, at: numbersX + numberWidth)

			guard !line.marker.isEmpty || !line.text.isEmpty else { return }

			// The marker keeps the diff's own colour — it is what the line does,
			// not what it says — and the text is coloured as code. Which side a
			// line is on is carried by the tint behind it, the way it is in a
			// review: reading a diff is reading code, and code that is all one
			// colour is the thing syntax highlighting exists to fix.
			line.marker.draw(at: NSPoint(x: textX, y: y), font: font, color: color(for: line.kind))
			let markerWidth = line.marker.size(withAttributes: [.font: font]).width
			drawText(line, index: index, at: NSPoint(x: textX + markerWidth, y: y))
		}
	}

	/// Draws one row of a side-by-side diff: the old file on the left, the new
	/// on the right, and a rule between them.
	///
	/// Each half is clipped to its own column, so a long line runs to the middle
	/// and stops rather than across the other side of the file.
	private func drawPair(left: Side?, right: Side?, at y: CGFloat) {
		let middle = (bounds.width / 2).rounded()

		func half(_ side: Side?, in column: NSRect) {
			if let side, let background = background(for: side.line.kind) {
				background.setFill()
				column.fill()
			} else if side == nil {
				// Nothing on this side of the row: a shade rather than the
				// editor's background, so a deletion with no replacement reads
				// as an absence rather than as a blank line of the file.
				Theme.current.gitIgnored.withAlphaComponent(0.06).setFill()
				column.fill()
			}
			guard let side else { return }

			if selection.contains(side.index) {
				Theme.current.gitModified.withAlphaComponent(0.20).setFill()
				column.fill()
				Theme.current.gitModified.setFill()
				NSRect(
					x: column.minX, y: y, width: Theme.current.scaled(3), height: lineHeight
				).fill()
			}

			let numbers = Theme.current.gitIgnored.withAlphaComponent(0.7)
			let number = "\(side.number)" as NSString
			let width = number.size(withAttributes: [.font: font]).width
			let numberX = column.minX + Self.gutterWidth + numberWidth - width - Theme.current.scaled(4)
			number.draw(
				at: NSPoint(x: numberX, y: y),
				withAttributes: [.font: font, .foregroundColor: numbers]
			)

			let start = column.minX + Self.gutterWidth + numberWidth + Theme.current.scaled(6)
			NSGraphicsContext.saveGraphicsState()
			NSRect(
				x: start, y: y, width: max(0, column.maxX - start), height: lineHeight
			).clip()
			// The marker is dropped: which side a line is on is what the column
			// says, and a `+` down the left of every line of the right-hand file
			// is a column of punctuation.
			drawText(side.line, index: side.index, at: NSPoint(x: start, y: y))
			NSGraphicsContext.restoreGraphicsState()
		}

		half(left, in: NSRect(x: 0, y: y, width: middle - 1, height: lineHeight))
		half(
			right,
			in: NSRect(x: middle + 1, y: y, width: bounds.width - middle - 1, height: lineHeight)
		)

		Theme.current.gitIgnored.withAlphaComponent(0.25).setFill()
		NSRect(x: middle, y: y, width: 1, height: lineHeight).fill()
	}

	/// Draws a line's text, in syntax colours where there are any.
	private func drawText(_ line: GitPatch.Line, index: Int, at origin: NSPoint) {
		guard !line.text.isEmpty else { return }
		let fallback = color(for: line.kind)

		guard let tokens = highlights[index], !tokens.isEmpty else {
			line.text.draw(at: origin, font: font, color: fallback)
			return
		}

		let attributed = NSMutableAttributedString(string: line.text, attributes: [
			.font: font,
			.foregroundColor: fallback,
		])
		for token in tokens {
			let lower = max(0, token.range.lowerBound)
			let upper = min(attributed.length, token.range.upperBound)
			guard upper > lower else { continue }
			attributed.addAttribute(
				.foregroundColor,
				value: Theme.current.color(for: token.kind),
				range: NSRange(location: lower, length: upper - lower)
			)
		}
		attributed.draw(at: origin)
	}

	private func background(for kind: GitPatch.Line.Kind) -> NSColor? {
		switch kind {
		case .added:   return Theme.current.gitAdded.withAlphaComponent(0.13)
		case .removed: return Theme.current.gitUnversioned.withAlphaComponent(0.13)
		default:       return nil
		}
	}

	private func color(for kind: GitPatch.Line.Kind) -> NSColor {
		switch kind {
		case .added:     return Theme.current.gitAdded
		case .removed:   return Theme.current.gitUnversioned
		case .noNewline: return Theme.current.gitIgnored
		case .context:   return Theme.current.sidebarText
		}
	}
}

private extension String {
	func draw(at point: NSPoint, font: NSFont, color: NSColor) {
		NSAttributedString(string: self, attributes: [
			.font: font,
			.foregroundColor: color,
		]).draw(at: point)
	}
}
