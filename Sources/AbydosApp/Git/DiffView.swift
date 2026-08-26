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

		init(author: String, when: String, body: String, isOutdated: Bool = false) {
			self.author = author
			self.when = when
			self.body = body
			self.isOutdated = isOutdated
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

	private enum Row {
		case header(String)
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
	}

	required init?(coder: NSCoder) { fatalError("not used") }

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
		let heading = comment.isOutdated
			? "\(comment.author) · \(comment.when) · on an earlier version"
			: "\(comment.author) · \(comment.when)"
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
		rows = patch.header.map { Row.header($0) }

		// **A comment whose line has gone is shown, not dropped.** GitHub calls
		// these outdated; a reviewer still needs to know a conversation happened
		// even when the code it was about is not there any more. Against the
		// file, at the top, because there is no line left to put it against.
		for comment in outdatedComments {
			rows += commentRows(for: comment)
		}

		var index = 0
		for (position, hunk) in patch.hunks.enumerated() {
			let heading = hunk.heading.isEmpty ? "" : " \(hunk.heading)"
			rows.append(.hunkHeader(index: position, text: "@@ hunk \(position + 1)\(heading)"))
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
				if let commentedLine, let left = comments[commentedLine] {
					for comment in left { rows += commentRows(for: comment) }
				}
				index += 1
			}
		}

		if patch.hunks.isEmpty {
			rows.append(.header(""))
			rows.append(.header("No textual changes."))
		}
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
		guard rows.indices.contains(row), case let .line(index, line, _, _) = rows[row], line.isSelectable else {
			return nil
		}
		return index
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		guard let row = row(at: convert(event.locationInWindow, from: nil)) else { return }

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
		// happened, and offering to undo part of it here would be a lie.
		guard !isReadOnly else { return nil }

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
		let apply = NSMenuItem(
			title: (isStaged ? "Unstage Selected Lines" : "Stage Selected Lines") + suffix,
			action: #selector(applySelection),
			keyEquivalent: ""
		)
		apply.target = self
		menu.addItem(apply)

		if !isStaged, onStashSelection != nil {
			menu.addItem(.separator())
			let stash = NSMenuItem(
				title: "Stash Selected Lines" + suffix,
				action: #selector(stashSelection),
				keyEquivalent: ""
			)
			stash.target = self
			menu.addItem(stash)
		}

		if !isStaged {
			menu.addItem(.separator())
			let discard = NSMenuItem(
				title: "Discard Selected Lines" + suffix,
				action: #selector(discardSelection),
				keyEquivalent: ""
			)
			discard.target = self
			menu.addItem(discard)
		}
		return menu
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
			let colour = comment.isOutdated
				? Theme.current.gitIgnored
				: (isFirst ? Theme.current.gitModified : Theme.current.sidebarText)
			let marked = isFirst ? "💬 " + text : "   " + text
			marked.draw(
				at: NSPoint(x: textX, y: y),
				font: isFirst
					? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
					: font,
				color: colour
			)

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
