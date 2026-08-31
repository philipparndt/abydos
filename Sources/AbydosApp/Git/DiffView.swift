import AppKit
import AbydosKit

/// A unified diff, rendered as coloured lines, with the changed ones
/// selectable so parts of it can be staged.
///
/// Hand-drawn like the code view rather than built on `NSTextView`: a diff is a
/// list of short lines with one colour each, and the same virtualised drawing
/// keeps a large one — a lockfile, a generated file — instant to open.
///
/// ## Four files, and why the state below is not `private`
///
/// A diff selects two things — whole lines, over the numbers, and characters,
/// over the code — and saying so took this file past the 1,100-line limit
/// `Scripts/file-size.sh` keeps. What moved out is:
///
///  * `DiffTextRun` — the character selection itself, the lines it measures and
///    the arithmetic that turns a point into an offset. **A collaborator that
///    owns its state**, which is the split that costs nothing: it is handed what
///    a row says and how a row is laid out, and holds no rows.
///  * `DiffView+Drawing`, `DiffView+Menu`, `DiffView+Driving` — the painting,
///    what a diff offers over a selection, and what a driven run may ask.
///
/// Those three are extensions, and an extension in another file cannot see
/// `private`: the fields below are internal because they are read there, and
/// that is the whole of the cost. Two of them write as well, and both are
/// honest about it — the menu moves the line selection to where the pointer was
/// aimed, which is what makes a command act on what was clicked, and the driven
/// verbs are the harness. The rule kept in exchange is that a *text* selection
/// only ever changes through `textRun`, and a line selection that puts it away
/// only through `setLineSelection`, so "the last gesture wins" cannot be broken
/// from a file that does not say it.
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

	var patch = GitPatch()
	private(set) var isStaged = false
	/// A diff of something already committed: there is nothing to stage in it.
	var isReadOnly = false
	/// Syntax tokens per patch line, when the file is in a language we parse.
	var highlights: [Int: [HighlightToken]] = [:]

	/// Flat rows: hunk headers and lines interleaved, as drawn.
	var rows: [Row] = []
	/// Selected *line* indices, in `GitPatch`'s flat numbering.
	var selection: Set<Int> = []
	/// Anchor for shift-click range selection.
	var anchorRow: Int?
	/// The remark under the selection, and the rows it occupies.
	///
	/// A remark is several rows and is selected as one thing: picking the third
	/// line of somebody's paragraph is not a gesture anybody means to make.
	var selectedComment: (comment: Comment, rows: ClosedRange<Int>)?
	/// The run of *characters* selected, if any, and which half of a
	/// side-by-side row it belongs to.
	///
	/// **Two selections rather than one the menu interprets**, and they are
	/// mutually exclusive: setting either puts the other away. A run of lines
	/// and a run of characters are different things — one is a set of
	/// `GitPatch` indices with a `+`/`-` meaning, the other a pair of points —
	/// and *Stage Selected Lines* over half a word is not a command.
	///
	/// A collaborator rather than fields here, and it is given `text(ofRow:in:)`
	/// and the geometry beside it in `init` — see `DiffTextRun`. What the driven
	/// verbs in `DiffView+Driving` reach is this, which is the arrangement the
	/// window controller's own driving file already has.
	let textRun = DiffTextRun()

	/// Which text column a point or a selection belongs to.
	typealias Column = DiffTextRun.Column

	/// Which lines the menu was opened over — see `DiffView+Menu`, where it is
	/// read. Here because an extension may not hold state.
	var commentRange: (from: Int, to: Int)?

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
	var isSideBySide = Settings.shared.diffIsSideBySide

	/// Re-reads the two preferences and redraws if either moved.
	///
	/// Called from the settings notification rather than polled, and cheap when
	/// nothing changed — a diff of five thousand rows should not rebuild because
	/// somebody changed the font.
	@objc func applyDiffSettings() {
		let chrome = Settings.shared.diffShowsChrome
		let sideBySide = Settings.shared.diffIsSideBySide
		guard chrome != showsChrome || sideBySide != isSideBySide else { return }
		showsChrome = chrome
		isSideBySide = sideBySide
		rebuildRows()
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	enum Row {
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
	struct Side: Equatable {
		let index: Int
		let line: GitPatch.Line
		let number: Int
	}

	var font: NSFont = Theme.terminalFont(size: Theme.current.fontSize)
	var lineHeight: CGFloat = 0
	static let horizontalInset: CGFloat = 12
	/// Room for the selection marker down the left edge.
	static let gutterWidth: CGFloat = 14
	/// One character of the code font, which is what a diff is drawn in.
	///
	/// The numbers are measured off it, and so is the sliver of highlight that
	/// stands for a line break inside a selection.
	var characterWidth: CGFloat {
		("0" as NSString).size(withAttributes: [.font: font]).width
	}
	/// Room for the two line numbers beside it.
	var numberWidth: CGFloat {
		// Measured from the font rather than guessed: a diff of a four-figure
		// file and one of a hundred lines should not indent differently, so it
		// is a fixed five columns either side.
		characterWidth * 5
	}

	override var isFlipped: Bool { true }
	override var acceptsFirstResponder: Bool { true }

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		updateMetrics()
		describeRows()
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
		// A different face measures differently, so what was measured in the
		// old one is worth nothing.
		textRun.forget()
		lineHeight = (font.ascender - font.descender + font.leading).rounded() + 2
	}

	func applyThemeChange() {
		updateMetrics()
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	// MARK: - Content


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

	static func highlights(for patch: GitPatch, url: URL?) -> [Int: [HighlightToken]] {
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
		// **The rows are about to be different rows.** A text selection is a
		// pair of positions in *this* list, and a measured line is the width of
		// one of its rows; neither survives the list being rebuilt. The line
		// selection is dropped by `setDiff` for the same reason, and the
		// rebuilds that reach here are all gestures somebody just made —
		// arrange, whole file, write a remark — rather than something arriving
		// on its own.
		textRun.forget()

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

	// MARK: - Where a character is

	/// Where a row's text begins, before its marker: the inset, the gutter the
	/// selection bar is drawn in, and the two number columns.
	var textX: CGFloat { Self.horizontalInset + Self.gutterWidth + numberWidth * 2 }

	/// Where the right-hand half of a side-by-side row begins, and the rule
	/// between the two.
	var pairMiddle: CGFloat { (bounds.width / 2).rounded() }

	/// The left edge of one half of a side-by-side row.
	///
	/// **One place says it**, because the drawing and the hit test have to
	/// agree about where a half begins: a highlight drawn from one number and
	/// hit-tested against another is a selection landing on the other file.
	func pairMinX(_ column: Column) -> CGFloat { column == .left ? 0 : pairMiddle + 1 }

	/// The bold face, for the two rows that are drawn in it.
	var boldFont: NSFont {
		NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
	}

	/// What a row *says*, with none of the diff's furniture on it — no number,
	/// no `+`/`-` marker, no gutter, and none of the emoji that marks a remark.
	///
	/// **This is the rule about what gets copied, and it lives here** so that
	/// drawing, hit-testing and copying cannot disagree about what a row's text
	/// is. The reason to take code out of a diff is to paste it somewhere that
	/// expects code, where a leading `+` makes every line wrong; and it is what
	/// makes the two arrangements copy the same characters, since side by side
	/// draws no marker at all.
	func text(ofRow index: Int, in column: Column = .only) -> String {
		guard rows.indices.contains(index) else { return "" }
		switch rows[index] {
		case let .header(text):        return text
		case let .scope(text):         return text
		case let .hunkHeader(_, text): return text
		case let .comment(_, text, _): return text
		case let .line(_, line, _, _): return line.text
		case let .pair(left, right):
			// The right-hand side unless the left was asked for: it is the side
			// that still exists, the same reading `lineIndex(atRow:)` makes.
			guard column == .left else { return right?.line.text ?? "" }
			return left?.line.text ?? ""
		}
	}

	/// Where that text is drawn from, which is where its highlight starts and
	/// where a pointer's x is measured against.
	///
	/// **The marker's measured width, not a column guessed off the font.** A
	/// line is drawn as a marker at `textX` and its text after it, and the
	/// expression that puts the text there used to live inside `draw(row:)` —
	/// so a highlight drawn from `textX` sat one marker-width to the left of the
	/// glyphs it was meant to be behind.
	func textOrigin(ofRow index: Int, in column: Column = .only) -> CGFloat {
		guard rows.indices.contains(index) else { return textX }
		switch rows[index] {
		case let .line(_, line, _, _):
			guard !line.marker.isEmpty else { return textX }
			return textX + line.marker.size(withAttributes: [.font: font]).width
		case let .comment(comment, _, isFirst):
			// ✍️ for one being written here, 💬 for one that has been said, and
			// three spaces for the rows under either.
			let prefix = isFirst ? (comment.isPending ? "✍️ " : "💬 ") : "   "
			return textX + prefix.size(withAttributes: [.font: isFirst ? boldFont : font]).width
		case .pair:
			return pairMinX(column) + Self.gutterWidth + numberWidth + Theme.current.scaled(6)
		default:
			return textX
		}
	}

	/// The face a row's text is drawn in, and therefore the one it is measured
	/// in: a hunk header and the heading of a remark are bold, and a bold row
	/// measured in the regular face puts the highlight short of the glyphs.
	private func face(ofRow index: Int) -> NSFont {
		guard rows.indices.contains(index) else { return font }
		switch rows[index] {
		case .hunkHeader:                 return boldFont
		case let .comment(_, _, isFirst): return isFirst ? boldFont : font
		default:                          return font
		}
	}

	/// What `DiffTextRun` is told a row is: what it says, the face it says it
	/// in, and where the saying starts. Set once, in `init`.
	///
	/// **One arrow out of the view and none back in.** The rule about what a
	/// row's text is lives above, in `text(ofRow:in:)`, and the arithmetic that
	/// turns a point into an offset in it lives in the collaborator — so
	/// drawing, hit-testing and copying cannot come to disagree about where a
	/// character is.
	private func describeRows() {
		textRun.textAt = { [weak self] row, column in
			self?.text(ofRow: row, in: column) ?? ""
		}
		textRun.rowAt = { [weak self] row, column in
			guard let self, self.rows.indices.contains(row) else {
				return DiffTextRun.Row(text: "", font: self?.font ?? .systemFont(ofSize: 12), origin: 0)
			}
			return DiffTextRun.Row(
				text: self.text(ofRow: row, in: column),
				font: self.face(ofRow: row),
				origin: self.textOrigin(ofRow: row, in: column)
			)
		}
	}

	/// How far into a row's text a point is, in UTF-16 code units.
	func offset(at point: NSPoint, ofRow index: Int, in column: Column) -> Int {
		textRun.offset(atX: point.x, row: index, in: column)
	}

	/// What a point in the view is over, which is what decides which selection
	/// a press makes.
	enum Region: Equatable {
		/// The numbers and the gutter beside them: whole lines, the selection
		/// that stages, discards, stashes and carries a remark.
		case numbers(row: Int, column: Column)
		/// The code itself: characters. The marker belongs here at offset 0,
		/// which is what a press on any text does — nothing until it moves.
		case text(row: Int, column: Column)
		/// A hunk header, which takes its whole hunk however it is pressed.
		case header(row: Int)
		/// Past the last row.
		case none
	}

	/// Off the same x boundaries the drawing uses, in both arrangements.
	func region(at point: NSPoint) -> Region {
		guard let index = row(at: point) else { return .none }
		if case .hunkHeader = rows[index] { return .header(row: index) }
		guard case .pair = rows[index] else {
			// One column. Everything left of the code is the numbers, the
			// gutter included — it is where the selection bar for a line is
			// drawn, so it belongs with the lines.
			return point.x < textX
				? .numbers(row: index, column: .only)
				: .text(row: index, column: .only)
		}
		let column: Column = point.x < pairMiddle ? .left : .right
		return point.x < textOrigin(ofRow: index, in: column)
			? .numbers(row: index, column: column)
			: .text(row: index, column: column)
	}

	/// The row a point is on, brought inside the diff.
	///
	/// A drag runs past the last row — that is what autoscroll is for — and a
	/// selection that stopped answering there would stop at whatever row was
	/// last under the pointer.
	func clampedRow(at point: NSPoint) -> Int? {
		guard let last = rows.indices.last else { return nil }
		let top = Theme.current.scaled(8)
		let index = Int((point.y - top) / lineHeight)
		return min(max(0, index), last)
	}

	/// Whether the keyboard is here, which is what a selection is drawn from.
	///
	/// Asked of the window on each draw rather than kept, for the reason
	/// `CodeView` gives: AppKit posts nothing when the first responder changes.
	var hasKeyboard: Bool { window?.firstResponder === self }

	// MARK: - Selection

	var hasSelection: Bool { !selection.isEmpty }
	var selectedLines: Set<Int> { selection }

	/// Whether a run of characters is selected — which is a different question
	/// from `hasSelection`, and the one *Copy* is offered over.
	var hasTextSelection: Bool { !textRun.isEmpty }

	/// ⌘A takes all of the diff's text, which is what it means in every other
	/// view in this window.
	///
	/// **It used to select every line that could be staged**, and nothing
	/// outside this file invoked it: no menu item targets it and no driven run
	/// reached it. Staging everything is still the file row's *Stage*, and a
	/// hunk is still its header.
	override func selectAll(_ sender: Any?) {
		guard let last = rows.indices.last else { return }
		// Side by side, the new side — the one that still exists, and the one a
		// reader means by "the file".
		textRun.takeEverything(through: last, in: isSideBySide ? .right : .only)
		tookText()
	}

	func clearSelection() {
		selection = []
		anchorRow = nil
		textRun.clear()
		needsDisplay = true
	}

	/// Selects every changed line in a hunk, for "stage this hunk".
	func selectHunk(_ hunkIndex: Int) {
		setLineSelection(Set(patch.indices(inHunk: hunkIndex)))
	}

	/// Whole lines, and nothing else selected.
	///
	/// **The two selections are mutually exclusive and the last gesture wins.**
	/// One is a set of `GitPatch` indices with a `+`/`-` meaning and the other a
	/// pair of points, and the staging path is untouched by any of this: the
	/// only thing that changed for it is which pixels fill the set.
	func setLineSelection(_ lines: Set<Int>) {
		selection = lines
		textRun.clear()
		needsDisplay = true
	}

	/// A run of characters was just taken, so the line selection goes.
	private func tookText() {
		selection = []
		anchorRow = nil
		needsDisplay = true
	}

	/// A remark, all of its rows, the way a click on one takes it.
	func selectComment(_ comment: Comment, rows block: ClosedRange<Int>) {
		selectedComment = (comment, block)
		selection = []
		anchorRow = nil
		textRun.clear()
		needsDisplay = true
	}

	func row(at point: NSPoint) -> Int? {
		let top = Theme.current.scaled(8)
		let index = Int((point.y - top) / lineHeight)
		return rows.indices.contains(index) ? index : nil
	}

	func lineIndex(atRow row: Int) -> Int? {
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
	func newNumber(atRow row: Int) -> Int? {
		guard rows.indices.contains(row) else { return nil }
		switch rows[row] {
		case let .line(_, _, _, new): return new
		case let .pair(_, right):     return right?.number
		default:                      return nil
		}
	}

	/// Which rows one remark occupies, given the row its heading is on.
	func commentBlock(startingAt row: Int) -> ClosedRange<Int>? {
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
	func comment(atRow row: Int) -> (Comment, ClosedRange<Int>)? {
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

	/// **Where the press landed decides which selection it makes.** The numbers
	/// take lines, the way a forge does it; the code takes characters, because
	/// the gesture over the code is needed for the code and there is one
	/// gesture. A hunk header — which is how most staging is actually done —
	/// does not move at all.
	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let point = convert(event.locationInWindow, from: nil)

		switch region(at: point) {
		case .none:
			return
		case let .header(row):
			selectedComment = nil
			// A click on a hunk header takes the whole hunk, which is the
			// common case — line-by-line is for when a hunk mixes two changes.
			guard case let .hunkHeader(hunkIndex, _) = rows[row] else { return }
			selectHunk(hunkIndex)
			anchorRow = row
		case let .numbers(row, _):
			pressLine(row: row, with: event)
		case let .text(row, column):
			pressText(row: row, in: column, at: point, with: event)
		}
	}

	/// The number column: whole lines, with shift and ⌘ behaving as they always
	/// have.
	func pressLine(row: Int, with event: NSEvent) {
		pressLine(
			row: row,
			shift: event.modifierFlags.contains(.shift),
			command: event.modifierFlags.contains(.command)
		)
	}

	/// The press itself, in the terms the gesture is made of — so a driven run
	/// makes the same press a pointer does.
	func pressLine(row: Int, shift: Bool, command: Bool) {
		// A remark has no numbers beside it, and a press anywhere on one takes
		// the remark: all of its rows, because a paragraph is one thing.
		if let (comment, block) = comment(atRow: row) {
			selectComment(comment, rows: block)
			return
		}
		selectedComment = nil
		guard let index = lineIndex(atRow: row) else { return }

		var updated = selection
		if shift, let anchor = anchorRow {
			// Range from the anchor, skipping context that falls between.
			for position in min(anchor, row)...max(anchor, row) {
				if let candidate = lineIndex(atRow: position) { updated.insert(candidate) }
			}
		} else if command {
			if updated.contains(index) { updated.remove(index) } else { updated.insert(index) }
			anchorRow = row
		} else {
			updated = [index]
			anchorRow = row
		}
		setLineSelection(updated)
	}

	/// The code: characters, from where the press landed.
	///
	/// A press with nothing dragged puts the caretless selection away — a click
	/// is how a selection is dismissed, not how one is made — and the two
	/// gestures a reader tries within the minute of discovering the drag are
	/// here too.
	func pressText(row: Int, in column: Column, at point: NSPoint, with event: NSEvent) {
		pressText(
			row: row,
			in: column,
			offset: offset(at: point, ofRow: row, in: column),
			clicks: event.clickCount,
			shift: event.modifierFlags.contains(.shift)
		)
	}

	/// The press itself, in the terms the gesture is made of rather than in
	/// AppKit's — so a driven run makes the same press a pointer does.
	func pressText(row: Int, in column: Column, offset: Int, clicks: Int, shift: Bool) {
		// A remark is one thing to *click* on and text to *drag over*: the click
		// takes the remark, and a drag from it hands the rows to the text
		// selection instead — see `mouseDragged`.
		if clicks == 1, !shift, let (comment, block) = comment(atRow: row) {
			selectComment(comment, rows: block)
		} else if clicks == 1 {
			selectedComment = nil
		}

		switch clicks {
		case 2:
			textRun.takeWord(row: row, offset: offset, in: column)
		case 3:
			textRun.takeRow(row, in: column)
		default:
			// Shift extends from where the gesture began, and only within the
			// half it began in.
			if shift, !textRun.isEmpty, textRun.column == column {
				textRun.extend(toRow: row, offset: offset)
			} else {
				textRun.press(row: row, offset: offset, in: column)
			}
		}
		tookText()
	}

	override func mouseDragged(with event: NSEvent) {
		// A selection that stops at the bottom of the visible rows is a
		// selection that cannot cover a hunk, and this view is inside a scroll
		// view in all five places it is used.
		autoscroll(with: event)
		let point = convert(event.locationInWindow, from: nil)

		if textRun.isPressed {
			guard let row = clampedRow(at: point) else { return }
			// **The half is carried through the drag**, which is how "a
			// selection belongs to one side" is enforced rather than checked
			// afterwards: a pointer past the divider goes on extending the side
			// it started on.
			textRun.extend(
				toRow: row, offset: offset(at: point, ofRow: row, in: textRun.column)
			)
			// A drag over a remark's rows is a selection of its text rather
			// than of the remark.
			if !textRun.isEmpty { selectedComment = nil }
			needsDisplay = true
			return
		}

		guard let anchor = anchorRow, let row = row(at: point) else { return }

		var updated: Set<Int> = []
		for position in min(anchor, row)...max(anchor, row) {
			if let index = lineIndex(atRow: position) { updated.insert(index) }
		}
		guard updated != selection else { return }
		selection = updated
		needsDisplay = true
	}

	/// The selection greys when the keyboard leaves and lifts when it comes
	/// back, and AppKit posts nothing when the first responder changes.
	override func becomeFirstResponder() -> Bool {
		needsDisplay = true
		return super.becomeFirstResponder()
	}

	override func resignFirstResponder() -> Bool {
		needsDisplay = true
		return super.resignFirstResponder()
	}

	override func keyDown(with event: NSEvent) {
		// Return applies, which is the whole point of having a selection here.
		if event.keyCode == 36 || event.keyCode == 76, hasSelection {
			onApplySelection?(selection)
			return
		}
		super.keyDown(with: event)
	}

	// MARK: - Copying

	/// What ⌘C would put on the clipboard, and nothing at all where nothing is
	/// selected.
	///
	/// **Reads `rows`, not the layout.** No line is measured and nothing
	/// off-screen is laid out, so ⌘A then ⌘C over a five-thousand-row diff costs
	/// a string join — which is why the text comes from `GitPatch` by way of
	/// `text(ofRow:in:)` rather than from anything the drawing built.
	var copiedText: String? {
		if let copied = textRun.copiedText { return copied }

		// **A run of lines selected and nothing selected as text is copied as
		// those lines.** A selection that is visibly on the screen and copies
		// nothing is the complaint this answers, and which of the two selections
		// it is does not matter.
		guard !selection.isEmpty else { return nil }
		let lines = rows.compactMap { row -> String? in
			switch row {
			case let .line(index, line, _, _):
				return selection.contains(index) ? line.text : nil
			case let .pair(left, right):
				if let right, selection.contains(right.index) { return right.line.text }
				if let left, selection.contains(left.index) { return left.line.text }
				return nil
			default:
				return nil
			}
		}
		return lines.isEmpty ? nil : lines.joined(separator: "\n")
	}

	/// ⌘C, and *Copy* wherever it is pressed from.
	///
	/// The Edit menu's *Copy* is `NSText.copy(_:)` with no target, so it walks
	/// the responder chain and arrives here: this is the whole of the keyboard
	/// plumbing.
	@objc func copy(_ sender: Any?) {
		guard let copiedText else { return }
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(copiedText, forType: .string)
	}


}

extension DiffView: NSMenuItemValidation {
	/// The Edit menu's *Copy* is enabled when this diff has the keyboard and
	/// something in it is selected, and disabled when nothing is.
	///
	/// **Only when it is the first responder**, because a pull request page is a
	/// file list beside a diff and each has its own keyboard: ⌘C in the list
	/// still copies what the list copies.
	func validateMenuItem(_ item: NSMenuItem) -> Bool {
		guard item.action == #selector(copy(_:)) else { return true }
		return hasKeyboard && copiedText != nil
	}
}

