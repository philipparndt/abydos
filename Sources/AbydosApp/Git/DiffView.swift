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
		let was = (font.fontName, font.pointSize, lineHeight)
		font = Theme.terminalFont(size: Theme.current.fontSize)
		lineHeight = (font.ascender - font.descender + font.leading).rounded() + 2

		// **Only when the face actually moved.** A different one measures
		// differently, so what was measured in the old one is worth nothing —
		// but this runs on *every* `Settings` write, because
		// `applyDiffSettings` calls it precisely to find out whether the
		// metrics moved. Forgetting unconditionally threw away a live text
		// selection whenever anybody changed any setting in the app: the
		// selection vanished when somebody toggled something in another pane,
		// with no gesture near the diff at all.
		guard (font.fontName, font.pointSize, lineHeight) != was else { return }
		textRun.forget()
	}

	func applyThemeChange() {
		updateMetrics()
		layer?.backgroundColor = Theme.current.editorBackground.cgColor
		invalidateIntrinsicContentSize()
		needsDisplay = true
	}

	// MARK: - Content

	func setDiff(_ text: String, staged: Bool, url: URL? = nil) {
		// Inline, for the callers that have the text in hand and nowhere to
		// hop. Marked so a diff that took a second says it was a diff.
		StallWatch.mark("diff render") {
			setDiff(Self.prepare(text, url: url), staged: staged)
		}
	}

	func setDiff(_ prepared: Prepared, staged: Bool) {
		isStaged = staged
		// The conversation belongs to the file that was on screen, and this
		// is a different file — or the same one at a different head. The
		// caller puts them back.
		comments = [:]
		outdatedComments = []
		selectedComment = nil
		patch = prepared.patch
		selection = []
		anchorRow = nil
		rebuildRows()
		highlights = prepared.highlights
		invalidateIntrinsicContentSize()
		needsDisplay = true
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
